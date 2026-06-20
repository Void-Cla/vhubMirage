// restore.js — restaura os .meta do backup mais recente (ou --backup <id>)
//
// Rede de seguranca: desfaz um `apply` restaurando os arquivos exatamente como estavam
// (copia byte-a-byte do .backups/). Nao mexe no selo — apos restaurar, rode `seal` ou
// `apply` de novo para realinhar .seal/seal.json com os arquivos restaurados.

const io     = require('../lib/io');
const { log } = require('../lib/report');


// erro de I/O — mapeado para exit 3 pelo entrypoint
class IoError extends Error {
  constructor(msg) { super(msg); this.name = 'IoError'; this.exitCode = 3; }
}


// executa o restore; devolve exit code (0 ok; 3 backup inexistente)
function run(args /*, cfg */) {
  const backups = io.listBackups();
  if (backups.length === 0) {
    throw new IoError('nenhum backup disponivel em .backups/.');
  }

  const id = args.backup || backups[0];
  if (!backups.includes(id)) {
    throw new IoError(`backup "${id}" nao existe. Disponiveis: ${backups.join(', ')}`);
  }

  log.head('RESTAURACAO');
  log.info(`restaurando do backup: ${id}`);

  let restored;
  try {
    restored = io.restoreBackup(id);
  } catch (e) {
    throw new IoError(e.message);
  }

  for (const abs of restored) log.ok(`restaurado: ${io.rel(abs)}`);
  log.info(`${restored.length} arquivo(s) restaurado(s). Rode \`seal\` ou \`apply\` ` +
           `para realinhar o selo.`);
  return 0;
}

module.exports = { run, IoError, describe: 'restaura do backup mais recente (ou --backup <id>)' };
