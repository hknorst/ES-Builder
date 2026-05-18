'use strict';

const { PROJETOS_PERMITIDOS, log } = require('./utils');
const { deployProject } = require('./deployer');

const INTERVALO_MS = 60 * 1000; // 60 segundos

async function verificarTodosProjetos() {
  for (const project of PROJETOS_PERMITIDOS) {
    try {
      await deployProject(project);
    } catch (err) {
      // Erro em um projeto não interrompe o loop; outros continuam normalmente
      log(project, `Erro tratado pelo watcher: ${err.message}`);
    }
  }
}

async function iniciarWatcher() {
  log('watcher', `Iniciado. Verificando a cada ${INTERVALO_MS / 1000}s.`);
  log('watcher', `Projetos monitorados: ${PROJETOS_PERMITIDOS.join(', ')}`);

  // Loop sequencial: aguarda o ciclo anterior terminar antes de iniciar o próximo.
  // Evita builds simultâneos do mesmo projeto quando um ciclo demora mais que o intervalo.
  while (true) {
    await verificarTodosProjetos();
    await new Promise(resolve => setTimeout(resolve, INTERVALO_MS));
  }
}

iniciarWatcher().catch((err) => {
  console.error('Falha crítica no watcher:', err.message);
  process.exit(1);
});
