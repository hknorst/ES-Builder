'use strict';

const fs = require('fs');
const path = require('path');
const { PROJETOS_PERMITIDOS, ROOT_DIR, run, loadState, saveState, log } = require('./utils');

const BUILD_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutos por build

// Retag de imagem Docker: origem → destino. No-op se já apontam para o mesmo digest.
function retagImage(from, to) {
  const fromId = run(`docker inspect --format={{.Id}} ${from}`).trim();
  let toId = null;
  try { toId = run(`docker inspect --format={{.Id}} ${to}`).trim(); } catch {}
  if (fromId === toId) return;
  run(`docker tag ${from} ${to}`);
}

// Sobe apenas os serviços do projeto especificado
function composeUp(project) {
  const composeFile = path.join(ROOT_DIR, 'compose', `${project}.yml`);
  const base = `docker compose -f docker-compose.yml -f "${composeFile}"`;
  run(
    `${base} up -d --force-recreate --no-deps ${project}-backend ${project}-frontend`,
    { cwd: ROOT_DIR }
  );
}

// Remove imagens antigas do projeto, mantendo apenas :current e :previous
function limparImagensAntigas(project) {
  const repos = [`${project}-backend`, `${project}-frontend`];
  const manter = new Set(['current', 'previous']);

  for (const repo of repos) {
    let output;
    try {
      output = run(`docker images --format "{{.Tag}}" ${repo}`);
    } catch {
      continue;
    }

    for (const tag of output.split('\n').filter(Boolean)) {
      if (manter.has(tag) || tag === '<none>') continue;
      try {
        run(`docker rmi ${repo}:${tag}`);
        log(project, `Imagem antiga removida: ${repo}:${tag}`);
      } catch (err) {
        // Imagem pode estar em uso ou já removida — não é erro crítico
        log(project, `Não foi possível remover ${repo}:${tag} — ${err.message}`);
      }
    }
  }
}

// Para os containers do projeto (sem remover volumes)
function composeStop(project) {
  const composeFile = path.join(ROOT_DIR, 'compose', `${project}.yml`);
  run(
    `docker compose -f docker-compose.yml -f "${composeFile}" stop ` +
    `${project}-backend ${project}-frontend`,
    { cwd: ROOT_DIR }
  );
}

async function deployProject(project) {
  // 1. Validar projeto permitido
  if (!PROJETOS_PERMITIDOS.includes(project)) {
    throw new Error(`Projeto "${project}" não está na lista de projetos permitidos.`);
  }

  const projectDir = path.join(ROOT_DIR, 'projects', project);
  if (!fs.existsSync(projectDir)) {
    throw new Error(`Diretório do projeto não encontrado: ${projectDir}`);
  }

  const config = JSON.parse(
    fs.readFileSync(path.join(ROOT_DIR, 'config', `${project}.json`), 'utf8')
  );

  const state = loadState(project);

  // 2. Buscar atualizações da branch deploy
  log(project, 'Buscando branch deploy...');
  try {
    run('git fetch origin deploy', { cwd: projectDir });
  } catch {
    log(project, 'Branch deploy não encontrada no remoto. Aguardando criação.');
    return;
  }

  // 3. Obter SHA atual do origin/deploy
  const sha = run('git rev-parse origin/deploy', { cwd: projectDir });
  log(project, `SHA remoto: ${sha}`);

  // 4. Sem mudanças desde o último deploy bem-sucedido
  if (state.lastSuccessSha === sha) {
    log(project, 'Sem alterações. Nenhum deploy necessário.');
    return;
  }

  // 5. Não tentar redeployar um SHA que já falhou anteriormente
  if (state.lastFailedSha === sha) {
    log(project, `SHA ${sha} falhou anteriormente. Pulando.`);
    return;
  }

  // 6. Sincronizar working tree com o estado remoto.
  // reset --hard é mais robusto que checkout: funciona mesmo após force push
  // porque usa a referência origin/deploy e não um SHA específico do histórico local.
  run('git reset --hard origin/deploy', { cwd: projectDir });
  log(project, `Working tree sincronizada com origin/deploy (${sha})`);

  const backendContext = path.join(projectDir, config.backend.context);
  const backendDockerfile = path.join(projectDir, config.backend.dockerfile);
  const frontendContext = path.join(projectDir, config.frontend.context);
  const frontendDockerfile = path.join(projectDir, config.frontend.dockerfile);

  const backendImage = `${project}-backend`;
  const frontendImage = `${project}-frontend`;

  try {
    // 7. Build do backend com timeout para evitar travamento indefinido
    log(project, 'Iniciando build do backend...');
    run(
      `docker build -f "${backendDockerfile}" -t ${backendImage}:${sha} "${backendContext}"`,
      { stream: true, timeout: BUILD_TIMEOUT_MS }
    );
    log(project, `Build backend concluído: ${backendImage}:${sha}`);

    // 8. Build do frontend com VITE_BASE_PATH dinâmico e timeout
    // O valor é derivado do nome do projeto; nunca hardcodado
    const viteBasePath = `/${project}/`;
    log(project, `Iniciando build do frontend (VITE_BASE_PATH=${viteBasePath})...`);
    run(
      `docker build --build-arg VITE_BASE_PATH=${viteBasePath} ` +
      `-f "${frontendDockerfile}" -t ${frontendImage}:${sha} "${frontendContext}"`,
      { stream: true, timeout: BUILD_TIMEOUT_MS }
    );
    log(project, `Build frontend concluído: ${frontendImage}:${sha}`);

    // 9. Promoção de tags

    if (state.lastSuccessSha) {
      // Preservar versão anterior para possível rollback
      retagImage(`${backendImage}:current`, `${backendImage}:previous`);
      retagImage(`${frontendImage}:current`, `${frontendImage}:previous`);
      log(project, 'Imagens current → previous preservadas.');
    }
    // Sem else: primeiro deploy não cria a tag previous

    // Promover novo SHA como current
    retagImage(`${backendImage}:${sha}`, `${backendImage}:current`);
    retagImage(`${frontendImage}:${sha}`, `${frontendImage}:current`);
    log(project, `Imagens ${sha} → current promovidas.`);

    // Subir serviços do projeto
    log(project, 'Subindo serviços...');
    composeUp(project);
    log(project, 'Serviços no ar.');

    // Salvar estado de sucesso
    saveState(project, {
      lastSuccessSha: sha,
      previousSha: state.lastSuccessSha || null,
      lastFailedSha: null,
      lastDeployAt: new Date().toISOString(),
    });

    // Remover imagens SHA antigas — manter apenas :current e :previous
    limparImagensAntigas(project);

    log(project, `Deploy concluído com sucesso. SHA: ${sha}`);
  } catch (err) {
    log(project, `ERRO no deploy: ${err.message}`);

    // Salvar SHA como falho para não retentativa automática
    saveState(project, {
      ...state,
      lastFailedSha: sha,
    });

    // Rollback: restaurar previous → current se existir
    if (state.lastSuccessSha) {
      log(project, 'Iniciando rollback para versão anterior...');
      try {
        retagImage(`${backendImage}:previous`, `${backendImage}:current`);
        retagImage(`${frontendImage}:previous`, `${frontendImage}:current`);
        composeUp(project);
        log(project, 'Rollback concluído. Serviços restaurados para versão anterior.');
      } catch (rollbackErr) {
        log(project, `ERRO no rollback: ${rollbackErr.message}`);
      }
    } else {
      // Primeiro deploy falhou; nenhuma versão anterior disponível
      log(project, 'Primeiro deploy falhou, nenhuma versão anterior disponível.');
      try {
        composeStop(project);
      } catch {
        // Ignorar erro ao parar; containers podem não existir ainda
      }
    }

    throw err;
  }
}

// Execução direta: node deployer.js <projeto>
if (require.main === module) {
  const project = process.argv[2];
  if (!project) {
    console.error('Uso: node deployer.js <projeto>');
    console.error(`Projetos disponíveis: ${PROJETOS_PERMITIDOS.join(', ')}`);
    process.exit(1);
  }

  deployProject(project)
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(err.message);
      process.exit(1);
    });
}

module.exports = { deployProject };
