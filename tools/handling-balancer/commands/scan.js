// scan.js — lista handlingNames reais, tier atual, orfaos e duplicatas (READ-ONLY)
//
// O primeiro comando a rodar num mod novo: revela os nomes REAIS (a v1.0 falhava por
// casar nome de pasta em vez do handlingName). Nunca grava.

const config = require('../lib/config');
const engine = require('../lib/engine');
const { log } = require('../lib/report');


// executa o scan; devolve exit code (0 sempre — scan e informativo)
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const { entries, orphans, duplicates } = engine.process(cfg, inv);

  if (args.json) return emitJson(inv, entries, orphans, duplicates);

  log.head('CARROS CLASSIFICADOS');
  if (entries.length === 0) {
    log.info('(nenhum carro do registry encontrado nos scan-paths)');
  }
  for (const e of entries) {
    const reg = cfg.registry[e.name];
    log.info(`${pad(e.handlingNameRaw)} tier ${reg.tier_base} -> ${reg.tier_max}   ${e.file}`);
  }

  log.head('ORFAOS (sem tier no registry — IGNORADOS, nunca tocados)');
  if (orphans.length === 0) log.info('(nenhum)');
  for (const o of orphans) {
    log.info(`${pad(o.name || '?')} ${o.reason}   ${o.file}`);
  }

  log.head('DUPLICATAS (mesmo handlingName em varios arquivos — registro ambiguo)');
  if (duplicates.length === 0) log.info('(nenhuma)');
  for (const d of duplicates) {
    log.warn(`${d.name}: ${d.files.join('  +  ')}`);
  }

  log.head('TOTAL');
  log.info(`arquivos varridos    : ${inv.files.length}`);
  log.info(`carros classificados : ${entries.length}`);
  log.info(`orfaos               : ${orphans.length}`);
  log.info(`duplicatas           : ${duplicates.length}`);
  return 0;
}

function emitJson(inv, entries, orphans, duplicates) {
  console.log(JSON.stringify({
    files: inv.files.length,
    classified: entries.map((e) => ({
      handling_name: e.handlingNameRaw, tier: e.tier, file: e.file,
    })),
    orphans,
    duplicates,
  }, null, 2));
  return 0;
}

const pad = (s) => String(s).padEnd(16);

module.exports = { run, describe: 'lista handlingNames reais, tier, orfaos e duplicatas (read-only)' };
