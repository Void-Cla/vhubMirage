// apply.js — grava o balanceamento (backup + cirurgico + selo + patch + relatorio)
//
// Unico comando que ESCREVE .meta. Fluxo seguro (script.md §10):
//   1. processa (calcula mudancas, sem gravar)
//   2. backup automatico de todo .meta que vai mudar (sem backup, sem escrita)
//   3. reescreve cada arquivo CIRURGICAMENTE (so blocos-alvo; grava so se mudou)
//   4. hash de cada arquivo final, calculado UMA vez
//   5. seal.json (fonte viva) + catalog-patch.json (copia do hash) + build-report.json
//
// Idempotente: rodar 2x nao muda nada na 2a vez (alvos sao absolutos do tier).

const path    = require('path');
const io      = require('../lib/io');
const meta    = require('../lib/meta');
const engine  = require('../lib/engine');
const seal    = require('../lib/seal');
const emitter = require('../lib/catalogEmitter');
const report  = require('../lib/report');
const { log } = report;


// erro de I/O — o entrypoint mapeia para exit code 3
class IoError extends Error {
  constructor(msg) { super(msg); this.name = 'IoError'; this.exitCode = 3; }
}


// executa o apply; devolve exit code (0 ok; 3 erro de I/O)
function run(args, cfg) {
  const inv = engine.inventory(cfg);
  const filter = buildFilter(args);
  const { entries } = engine.process(cfg, inv, filter);

  const classified = entries.filter((e) => !e.skipped);
  if (classified.length === 0) {
    log.warn('nenhum carro classificado para aplicar.');
    return 0;
  }

  // --dry-run forca o comportamento de plan mesmo no apply (rede extra de seguranca)
  if (args['dry-run']) {
    log.head('DRY-RUN (apply sem gravar)');
    for (const e of entries) report.renderDiff(e);
    report.renderSummary('seriam alterados', entries);
    return 0;
  }

  // agrupa entries por arquivo (um arquivo pode ter varios carros)
  const byFile = groupByFile(classified);

  // arquivos que terao mudanca real
  const willChange = [...byFile.values()].filter((g) => g.entries.some(hasChange));
  const changingPaths = willChange.map((g) => g.abs);

  // ----- backup -----
  let backupId = null;
  if (changingPaths.length > 0) {
    if (args['no-backup']) {
      if (!args.force) {
        throw new IoError('--no-backup exige --force (rede de seguranca; script.md §10).');
      }
      log.warn('backup DESABILITADO (--no-backup --force).');
    } else {
      backupId = io.backup(changingPaths);
      log.ok(`backup criado: .backups/${backupId} (${changingPaths.length} arquivo(s))`);
    }
  } else {
    log.info('nada mudou — nenhum arquivo a gravar (idempotente).');
  }

  // ----- escrita cirurgica + hash -----
  const sealMap = seal.read();
  const patchByKey = {};

  for (const g of byFile.values()) {
    const changed = g.entries.some(hasChange);
    let finalContent = g.content;

    if (changed) {
      finalContent = rebuild(g);
      try {
        io.writeText(g.abs, finalContent);
      } catch (e) {
        throw new IoError(`falha ao gravar ${g.file}: ${e.message}`);
      }
      for (const e of g.entries) if (hasChange(e)) e.written = true;
      log.ok(`gravado: ${g.file}`);
    }

    // hash UMA vez por arquivo; selo + patch usam o MESMO valor (contrato)
    const fileHash = seal.hashContent(finalContent);
    for (const e of g.entries) {
      sealMap[e.name] = { tier: e.tier, sha256: fileHash, file: g.file };
      patchByKey[e.name.toLowerCase()] =
        emitter.buildEntry(e.handlingNameRaw, e.block, cfg, fileHash);
    }
  }

  // ----- artefatos -----
  seal.write(sealMap);
  log.ok(`selo atualizado: ${io.rel(seal.SEAL_PATH)}`);

  const patchPath = emitter.writePatch(patchByKey);
  log.ok(`catalog-patch emitido: ${io.rel(patchPath)} (mesclar manualmente na Fase 2)`);

  const reportPath = report.writeBuildReport(entries, { backupId });
  log.ok(`build-report: ${io.rel(reportPath)}`);

  report.renderSummary('gravados', entries);
  return 0;
}


// ============================================================
// REASSEMBLY CIRURGICO
// ============================================================

// reconstroi o conteudo do arquivo trocando so os blocos processados pelo seu newBlock.
// percorre os segmentos originais na ordem; cada bloco-handling consome o proximo entry.
function rebuild(group) {
  const segs = meta.splitBlocks(group.content);
  const queue = [...group.entries]; // mesma ordem do scan (engine percorre em ordem)
  let out = '';

  for (const seg of segs) {
    if (!seg.isHandling) { out += seg.text; continue; }
    const e = queue.shift();
    // seguranca: o bloco do segmento deve ser o mesmo que processamos
    if (e && e.block === seg.text) {
      out += (e.newBlock || seg.text);
    } else {
      // bloco nao classificado (orfao no mesmo arquivo) ou descasou — preserva original
      out += seg.text;
      if (e) queue.unshift(e); // devolve para o proximo handling-block real
    }
  }
  return out;
}


// ============================================================
// HELPERS
// ============================================================

// agrupa entries pelo arquivo de origem, preservando content/abs
function groupByFile(entries) {
  const map = new Map();
  for (const e of entries) {
    if (!map.has(e.abs)) map.set(e.abs, { abs: e.abs, file: e.file, content: e.content || readOnce(e), entries: [] });
    map.get(e.abs).entries.push(e);
  }
  return map;
}

// le o conteudo do arquivo uma vez (entries do engine nao carregam o content do arquivo)
function readOnce(e) {
  return io.readText(e.abs);
}

const hasChange = (e) => (e.changes || []).some((c) => c.changed);

function buildFilter(args) {
  const filter = {};
  if (args.only) filter.only = new Set(args.only.split(',').map((s) => s.trim().toUpperCase()));
  if (args.tier) filter.tier = String(args.tier).trim().toUpperCase();
  return filter;
}

module.exports = { run, IoError, describe: 'grava balanceamento (backup + cirurgico + selo + patch)' };
