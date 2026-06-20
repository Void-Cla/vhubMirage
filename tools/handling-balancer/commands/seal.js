// seal.js — re-sela os hashes do estado atual (apos edicao manual aprovada)
//
// Uso: quando um .meta foi editado a mao DE FORMA APROVADA (fora do tier, por decisao
// consciente do dono), `seal` registra o novo hash como o estado valido. Depois disso o
// `verify` volta a passar. Nao reescreve .meta — so atualiza .seal/seal.json.

const engine = require('../lib/engine');
const seal   = require('../lib/seal');
const io     = require('../lib/io');
const { log } = require('../lib/report');


// executa o seal; devolve exit code (0 ok)
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const { entries } = engine.process(cfg, inv);

  const sealMap = {};
  let n = 0;
  for (const e of entries) {
    if (e.skipped) continue;
    sealMap[e.name] = { tier: e.tier, sha256: seal.hashContent(e.content), file: e.file };
    n += 1;
  }

  if (n === 0) {
    log.warn('nenhum carro classificado para selar.');
    return 0;
  }

  seal.write(sealMap);
  log.head('RE-SELO');
  log.ok(`${n} carro(s) selado(s) no estado atual: ${io.rel(seal.SEAL_PATH)}`);
  log.info('use isto apenas apos uma edicao manual APROVADA (caso contrario, rode `apply`).');
  return 0;
}

module.exports = { run, describe: 're-sela os hashes atuais (pos-edicao manual aprovada)' };
