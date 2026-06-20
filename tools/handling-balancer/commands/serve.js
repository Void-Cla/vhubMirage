// serve.js — sobe a interface web (servidor HTTP local)
//
// Diferente dos outros comandos, NÃO retorna exit code: mantém o processo vivo enquanto o
// servidor escuta. Sinaliza isso devolvendo { keepAlive: true } para o entrypoint.

const server = require('../lib/server');


// inicia o servidor; flag --port define a porta (default 7920)
function run(args /*, cfg */) {
  const port = args.port ? parseInt(args.port, 10) : 7920;
  server.start(port);
  return { keepAlive: true };
}

module.exports = { run, describe: 'sobe a interface web em http://127.0.0.1:7920 (--port)' };
