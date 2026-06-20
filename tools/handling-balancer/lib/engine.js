// engine.js — pipeline compartilhado scan -> processar (sem escrita)
//
// Coracao reaproveitado por scan/plan/apply (L-09): descobre arquivos, fatia em blocos,
// casa com o registry, resolve os alvos do NUCLEO-8 e calcula as mudancas que SERIAM
// feitas — sem gravar nada. Cada comando decide o que fazer com o resultado.

const io    = require('./io');
const meta  = require('./meta');
const tiers = require('./tiers');
const { norm, isNum } = require('./util');


// ============================================================
// DESCOBERTA + CLASSIFICACAO
// ============================================================

// varre os scan-paths e devolve um inventario cru:
//   files: [{ file, content, blocks:[{ handlingName, raw, block }] }]
//   names: mapa handlingName(UPPER) -> [{ file }]  (para detectar duplicatas)
function inventory(cfg) {
  const sp = cfg.scanPaths;
  const paths = io.discover(sp.roots, sp.matchFiles, sp.exclude);

  const files = [];
  const names = {};

  for (const abs of paths) {
    const content = io.readText(abs);
    const segs = meta.splitBlocks(content);
    const blocks = [];

    for (const seg of segs) {
      if (!seg.isHandling) continue;
      const raw = readRawName(seg.text);
      const handlingName = raw ? norm(raw) : null;
      blocks.push({ handlingName, raw, block: seg.text });
      if (handlingName) {
        (names[handlingName] = names[handlingName] || []).push({ file: io.rel(abs) });
      }
    }
    files.push({ file: io.rel(abs), abs, content, blocks });
  }

  return { files, names };
}


// ============================================================
// PROCESSAMENTO (calcula mudancas, NAO grava)
// ============================================================

// processa o inventario contra o registry. devolve [entry] por carro classificado +
// orfaos (sem tier) e duplicatas reportadas. `filter` opcional: { only:Set, tier:string }.
function process(cfg, inv, filter) {
  const entries = [];
  const orphans = [];

  for (const f of inv.files) {
    for (const b of f.blocks) {
      if (!b.handlingName) {
        orphans.push({ file: f.file, reason: 'sem handlingName' });
        continue;
      }
      const reg = cfg.registry[b.handlingName];
      if (!reg) {
        orphans.push({ file: f.file, name: b.handlingName, reason: 'sem tier no registry' });
        continue;
      }
      if (filter && filter.only && !filter.only.has(b.handlingName)) continue;
      if (filter && filter.tier && reg.tier_base !== filter.tier) continue;

      entries.push(processBlock(cfg, f, b));
    }
  }

  return { entries, orphans, duplicates: findDuplicates(inv.names) };
}

// processa UM bloco: calcula os 8 alvos, o diff vs valores atuais e os warnings.
function processBlock(cfg, file, b) {
  const entry = {
    name: b.handlingName,
    handlingNameRaw: b.raw.trim(),
    file: file.file,
    abs: file.abs,
    content: file.content,
    tier: cfg.registry[b.handlingName].tier_base,
    block: b.block,
    changes: [],
    warnings: [],
    skipped: null,
    written: false,
  };

  // massa invalida -> nao da pra classificar com honestidade (edge case obrigatorio)
  const mass = meta.readValue(b.block, 'fMass');
  if (!isNum(mass) || mass <= 0) {
    entry.skipped = 'massa-invalida';
    return entry;
  }
  warnIfMassOutOfBand(entry, cfg, mass);

  const { targets, clampInfo } = tiers.resolveTargets(b.handlingName, cfg);
  if (clampInfo) {
    entry.warnings.push(
      `${clampInfo.field} fora da banda do tier: alvo ${clampInfo.raw.toFixed(6)} ` +
      `clampado para ${clampInfo.clamped.toFixed(6)} (revisar tier/override)`);
  }

  // computa o diff sem aplicar (apply reaproveita os mesmos alvos)
  let newBlock = b.block;
  for (const field of tiers.FIELDS) {
    const from = meta.readValue(newBlock, field);
    const r = meta.setValue(newBlock, field, targets[field]);
    newBlock = r.block;
    entry.changes.push({
      field,
      from: isNum(from) ? from : null,
      to: targets[field],
      changed: r.changed,
      missing: r.missing,
    });
    if (r.missing) entry.warnings.push(`campo ausente no .meta: ${field} (nao injetado)`);
  }

  entry.newBlock = newBlock;
  return entry;
}


// ============================================================
// GUARDAS / EDGE CASES
// ============================================================

// avisa se a massa esta muito fora da faixa esperada do tier (provavel tier errado)
function warnIfMassOutOfBand(entry, cfg, mass) {
  const base = cfg.tiers[entry.tier].massBase;
  const ratio = mass / base;
  if (ratio < 0.5 || ratio > 2.0) {
    entry.warnings.push(
      `massa ${mass}kg muito fora da base do tier ${entry.tier} (${base}kg) — ` +
      `confirmar classificacao`);
  }
}

// handlingName que aparece em mais de um arquivo (registro fica ambiguo)
function findDuplicates(names) {
  const dups = [];
  for (const [name, occ] of Object.entries(names)) {
    if (occ.length > 1) dups.push({ name, files: occ.map((o) => o.file) });
  }
  return dups;
}

// le o handlingName cru (sem normalizar) para preservar a caixa real no relatorio
function readRawName(block) {
  const m = block.match(/<handlingName>\s*([^<]+?)\s*<\/handlingName>/);
  return m ? m[1] : null;
}


module.exports = { inventory, process };
