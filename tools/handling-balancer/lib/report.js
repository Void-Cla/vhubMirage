// report.js — saida PT-BR no terminal, render de diff e build-report.json
//
// Sem biblioteca de cores (decisao de simplicidade): console direto com prefixo PT-BR.
// O build-report.json acompanha o commit do `apply` -> a revisao fica trivial (auditavel
// linha a linha, casando com o estilo do vHub).

const path = require('path');
const io   = require('./io');
const { f6 } = require('./util');

const REPORT_PATH = path.join(io.TOOL_ROOT, 'build-report.json');


// ============================================================
// LOG (PT-BR, padronizado)
// ============================================================

const log = {
  info: (msg) => console.log(`   ${msg}`),
  ok:   (msg) => console.log(`[ ok ] ${msg}`),
  warn: (msg) => console.warn(`[aviso] ${msg}`),
  erro: (msg) => console.error(`[erro] ${msg}`),
  head: (msg) => console.log(`\n=== ${msg} ===`),
};


// ============================================================
// RENDER DE DIFF (terminal)
// ============================================================

// imprime o diff de um carro: campos alterados antes->depois + warnings + skip.
function renderDiff(entry) {
  if (entry.skipped) {
    log.warn(`${entry.name}: ignorado (${entry.skipped})`);
    return;
  }

  const changes = entry.changes.filter((c) => c.changed);
  if (changes.length === 0 && entry.warnings.length === 0) {
    log.ok(`${entry.name} [${entry.tier}]: ja conforme (nada a alterar)`);
    return;
  }

  console.log(`\n  ${entry.name}  [tier ${entry.tier}]  (${entry.file})`);
  for (const c of entry.changes) {
    if (c.missing) {
      console.log(`    - ${pad(c.field)} campo AUSENTE no .meta (nao injetado)`);
    } else if (c.changed) {
      console.log(`    ~ ${pad(c.field)} ${f6(c.from)}  ->  ${f6(c.to)}`);
    }
  }
  for (const w of entry.warnings) {
    console.log(`    ! ${w}`);
  }
}

// resumo final de um lote (planejado/aplicado)
function renderSummary(verb, entries) {
  const touched = entries.filter((e) => !e.skipped && e.changes.some((c) => c.changed));
  const skipped = entries.filter((e) => e.skipped);
  const warned  = entries.filter((e) => !e.skipped && e.warnings.length > 0);

  log.head('RESUMO');
  log.info(`carros classificados : ${entries.length - skipped.length}`);
  log.info(`${verb.padEnd(20)} : ${touched.length}`);
  log.info(`ignorados            : ${skipped.length}`);
  log.info(`com avisos           : ${warned.length}`);
}


// ============================================================
// BUILD-REPORT.JSON
// ============================================================

// grava o relatorio de build (por carro: tier, campos alterados antes->depois, warnings)
function writeBuildReport(entries, meta) {
  const report = {
    generatedAt: new Date().toISOString(),
    backupId:    meta.backupId || null,
    summary: {
      classified: entries.filter((e) => !e.skipped).length,
      written:    entries.filter((e) => e.written).length,
      skipped:    entries.filter((e) => e.skipped).length,
    },
    // mapa key(lower) <-> handling_name(real) para a ponte humana da Fase 2 (contrato)
    keyMap: entries
      .filter((e) => !e.skipped)
      .map((e) => ({ catalog_key: e.name.toLowerCase(), handling_name: e.handlingNameRaw })),
    vehicles: entries.map((e) => ({
      name: e.name,
      handling_name: e.handlingNameRaw,
      tier: e.tier || null,
      file: e.file,
      skipped: e.skipped || null,
      written: !!e.written,
      changes: (e.changes || []).map((c) => ({
        field: c.field,
        from: c.missing ? null : c.from,
        to: c.missing ? null : c.to,
        changed: c.changed,
        missing: c.missing,
      })),
      warnings: e.warnings || [],
    })),
  };
  io.writeJson(REPORT_PATH, report);
  return REPORT_PATH;
}


// ============================================================
// HELPERS
// ============================================================

const pad = (s) => String(s).padEnd(24);


module.exports = { log, renderDiff, renderSummary, writeBuildReport, REPORT_PATH };
