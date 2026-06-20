// verify.js — confere que cada .meta bate com o selo (gate de CI)
//
// Recomputa o sha256 de cada .meta classificado e compara com .seal/seal.json. Qualquer
// divergencia (edicao manual, merge errado, carro pirata colado) => exit 1 com o nome do
// carro. Roda no CI: PR que mexe num handling.meta sem passar pelo pipeline NAO mergeia.
//
// O seal.json e a UNICA fonte que o verify le (o hash do catalog-patch e so auditoria).

const engine = require('../lib/engine');
const seal   = require('../lib/seal');
const { log } = require('../lib/report');


// executa o verify; devolve exit code (0 ok; 1 drift/divergencia)
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const { entries } = engine.process(cfg, inv);

  const sealMap = seal.read();
  const checkable = entries
    .filter((e) => !e.skipped)
    .map((e) => ({ name: e.name, file: e.file, content: e.content }));

  const result = seal.diff(checkable, sealMap);

  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
    return result.ok ? 0 : 1;
  }

  log.head('VERIFICACAO DE SELO');

  if (result.ok) {
    log.ok(`todos os ${checkable.length} carro(s) batem com o selo. Sem drift.`);
    return 0;
  }

  for (const d of result.drift) {
    log.erro(`DRIFT: ${d.name} foi editado fora do pipeline (${d.file})`);
    log.info(`  selado:  ${d.expected}`);
    log.info(`  atual:   ${d.got}`);
  }
  for (const name of result.unsealed) {
    log.erro(`SEM SELO: ${name} esta classificado mas nunca foi selado (rode apply/seal)`);
  }
  for (const name of result.missing) {
    log.erro(`SELO ORFAO: ${name} esta no selo mas sumiu do scan`);
  }

  log.head('RESULTADO');
  log.erro(`drift: ${result.drift.length} | sem selo: ${result.unsealed.length} | ` +
           `orfao: ${result.missing.length}  => exit 1`);
  return 1;
}

module.exports = { run, describe: 'confere meta == selo; exit 1 em drift (CI)' };
