// plan.js — diff campo-a-campo por carro + preview do catalog-patch (READ-ONLY)
//
// Comportamento mental padrao (script.md §10): mostra exatamente o que `apply` faria,
// sem gravar. Default seguro.

const config  = require('../lib/config');
const engine  = require('../lib/engine');
const emitter = require('../lib/catalogEmitter');
const seal    = require('../lib/seal');
const { log, renderDiff, renderSummary } = require('../lib/report');


// executa o plan; devolve exit code (0 ok; 3 nenhum carro classificado nao e erro)
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const filter = buildFilter(args);
  const { entries, orphans } = engine.process(cfg, inv, filter);

  if (args.json) return emitJson(entries);

  log.head('PLANO DE BALANCEAMENTO (preview — nada sera gravado)');
  for (const e of entries) renderDiff(e);

  if (orphans.length > 0) {
    log.head('IGNORADOS (sem tier)');
    for (const o of orphans) log.info(`${o.name || '?'}  (${o.reason})  ${o.file}`);
  }

  renderSummary('com alteracoes', entries);

  // preview do bloco p1 que o catalog-patch carregaria (selo provisorio = hash atual)
  log.head('PREVIEW catalog-patch (bloco p1 — mesclar na Fase 2)');
  for (const e of entries) {
    if (e.skipped) continue;
    const provisional = seal.hashContent(e.newBlock || e.block);
    const p1 = emitter.buildEntry(e.handlingNameRaw, e.block, cfg, provisional);
    log.info(`${e.name.toLowerCase()} = ${JSON.stringify(p1)}`);
  }

  return 0;
}

// filtros opcionais: --only A,B  e  --tier S
function buildFilter(args) {
  const filter = {};
  if (args.only) filter.only = new Set(args.only.split(',').map((s) => s.trim().toUpperCase()));
  if (args.tier) filter.tier = String(args.tier).trim().toUpperCase();
  return filter;
}

function emitJson(entries) {
  console.log(JSON.stringify(entries.map((e) => ({
    name: e.name, tier: e.tier, skipped: e.skipped,
    changes: (e.changes || []).filter((c) => c.changed),
    warnings: e.warnings,
  })), null, 2));
  return 0;
}

module.exports = { run, describe: 'diff campo-a-campo + preview do catalog-patch (read-only)' };
