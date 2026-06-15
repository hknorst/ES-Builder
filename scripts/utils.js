'use strict';

const fs = require('fs');
const path = require('path');
const { execSync, spawnSync } = require('child_process');

// Projetos gerenciados pelo es-builder
const PROJETOS_PERMITIDOS = [
  'portal',
  'portal-fake',
  'projeto-a',
  'projeto-b',
  'projeto-c',
  'projeto-d',
  'projeto-e',
];

const ROOT_DIR = path.resolve(__dirname, '..');
const STATE_DIR = path.join(ROOT_DIR, 'state');
const LOGS_DIR = path.join(ROOT_DIR, 'logs');

// Executa um comando shell.
// Com stream: true, imprime output em tempo real (stdio: 'inherit') — sem retorno de string.
// Sem stream, captura stdout e retorna como string; inclui stderr na mensagem de erro.
function run(cmd, opts = {}) {
  const { stream = false, timeout, cwd } = opts;

  if (stream) {
    const result = spawnSync(cmd, {
      shell: true,
      stdio: 'inherit',
      ...(cwd && { cwd }),
      ...(timeout && { timeout }),
    });
    if (result.status !== 0) {
      throw new Error(`Command failed (exit ${result.status ?? 'unknown'}): ${cmd}`);
    }
    return '';
  }

  try {
    return execSync(cmd, {
      encoding: 'utf8',
      maxBuffer: 200 * 1024 * 1024,
      ...(cwd && { cwd }),
      ...(timeout && { timeout }),
    }).trim();
  } catch (err) {
    if (err.stderr) err.message += `\nSTDERR:\n${err.stderr}`;
    throw err;
  }
}

// Lê o estado persistido de um projeto; retorna objeto vazio se não existir
function loadState(project) {
  const stateFile = path.join(STATE_DIR, `${project}.json`);
  if (!fs.existsSync(stateFile)) {
    return {
      lastSuccessSha: null,
      previousSha: null,
      lastFailedSha: null,
      lastDeployAt: null,
    };
  }
  try {
    return JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  } catch {
    return {
      lastSuccessSha: null,
      previousSha: null,
      lastFailedSha: null,
      lastDeployAt: null,
    };
  }
}

// Persiste o estado de um projeto em JSON formatado
function saveState(project, state) {
  if (!fs.existsSync(STATE_DIR)) {
    fs.mkdirSync(STATE_DIR, { recursive: true });
  }
  const stateFile = path.join(STATE_DIR, `${project}.json`);
  fs.writeFileSync(stateFile, JSON.stringify(state, null, 2), 'utf8');
}

// Escreve no console e em arquivo de log com timestamp ISO
function log(project, message) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] [${project}] ${message}`;
  console.log(line);

  const projectLogsDir = path.join(LOGS_DIR, project);
  if (!fs.existsSync(projectLogsDir)) {
    fs.mkdirSync(projectLogsDir, { recursive: true });
  }

  // Um arquivo de log por dia para não fragmentar demais
  const datePrefix = timestamp.slice(0, 10);
  const logFile = path.join(projectLogsDir, `${datePrefix}.log`);
  fs.appendFileSync(logFile, line + '\n', 'utf8');
}

module.exports = {
  PROJETOS_PERMITIDOS,
  ROOT_DIR,
  run,
  loadState,
  saveState,
  log,
};
