// catalogPatcher.js — aplica bloco p1 gerado pelo apply diretamente em catalog.lua
//
// Estrategia: substituicao cirurgica de STRING — nao e parser Lua geral.
// Opera em tres passos por carro processado:
//   1. resolve a chave FISICA do catalog.lua (case-insensitive — catalog tem UPPERCASE e lowercase)
//   2. localiza e substitui APENAS o bloco `p1 = { ... }` da entrada (inserindo se ausente)
//   3. merge por campo: campos emitidos pelo balancer sao escritos; campos extras em p1 sao preservados
//
// CONTRATO DE CAMPOS:
//   - O balancer e dono de: handling_name, class_budget, tier_max, archetype, grip_modifier,
//     base_alloc, drive_bias, susp_raise, mass, inertia_z, low_speed_loss, seal
//   - Qualquer campo em p1 NAO presente nessa lista sobrevive ao merge (override manual)
//
// GRAFIA FISICA PRESERVADA: a key usada no catalog.lua (ex: TOYOTASUPRA, m3e46) nao e alterada.
// O patcher reescreve o BLOCO p1 dentro da entrada existente, sem tocar a chave da entrada.
//
// SEGURANCA:
//   - Carro ausente do catalog.lua = skip com warning (o patcher nao cria entradas)
//   - Bloco p1 malformado no catalog = substituicao total do bloco (safe — emitter e autoridade)
//   - Arquivo sem mudanca real = nao reescreve (idempotente)

'use strict';

const path = require('path');
const io   = require('./io');
const { log } = require('./report');

// campos EMITIDOS pelo balancer (balancer e dono; campo presente = sobrescreve no catalog)
const BALANCER_FIELDS = new Set([
  'handling_name', 'class_budget', 'tier_max', 'archetype', 'grip_modifier',
  'base_alloc', 'drive_bias', 'susp_raise', 'mass', 'inertia_z', 'low_speed_loss', 'seal',
]);

// caminho absoluto do catalog.lua (dono: vhub_conce)
const CATALOG_PATH = path.join(io.REPO_ROOT, 'resources', '[SCRIPTS]', 'vhub_conce', 'shared', 'catalog.lua');


// ============================================================
// INDEX DE CHAVES FISICAS (case-insensitive lookup)
// ============================================================

// le o catalog.lua e constroi { lowercase_key -> physical_key } para lookup case-insensitive.
// Detecta linhas de cabecalho de entrada: `  NOME = {` ou `  nome = {` no nivel 1 de indent.
function buildKeyIndex(content) {
  const index = {};
  // captura: key = IDENTIFIER antes do `=` na raiz da tabela (2 espacos de indent = nivel 1)
  // nao captura linhas dentro de sub-tabelas (ex.: `    p1 = {`) — indent 4+
  for (const m of content.matchAll(/^  ([A-Za-z0-9_]+)\s*=\s*\{/gm)) {
    const phys = m[1];
    index[phys.toLowerCase()] = phys;
  }
  return index;
}


// ============================================================
// LOCALIZADOR DA ENTRADA (offset de inicio/fim)
// ============================================================

// encontra o bloco inteiro da entrada NOME = { ... } no catalog.lua.
// Retorna { start, end } (indices de caractere) ou null se nao encontrar.
// Usa contagem de chaves para delimitar o bloco (robusto contra multiline).
function findEntryBlock(content, physKey) {
  // ancora: inicio exato da linha `  NOME = {`
  const anchor = new RegExp(`^  ${escapeRegex(physKey)}\\s*=\\s*\\{`, 'm');
  const m = anchor.exec(content);
  if (!m) return null;

  let depth = 0;
  let i = m.index;
  const start = i;

  while (i < content.length) {
    const ch = content[i];
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) return { start, end: i + 1 };
    }
    i++;
  }
  return null; // chave incompleta (arquivo malformado)
}


// ============================================================
// LOCALIZADOR DO BLOCO p1 DENTRO DA ENTRADA
// ============================================================

// dentro do entryBlock, encontra `p1 = { ... }` e retorna { start, end } relativos ao entryBlock,
// ou null se nao existir p1.
// `start` aponta para o inicio DA LINHA que contem `p1 = {` (incluindo o whitespace de indent)
// para que a substituicao nao deixe whitespace residual antes do bloco novo.
function findP1Block(entryContent) {
  // ancora: `p1 = {` com qualquer indent dentro da entrada
  const anchor = /\bp1\s*=\s*\{/;
  const m = anchor.exec(entryContent);
  if (!m) return null;

  // recua ate o inicio da linha (apos \n ou inicio da string) para capturar o whitespace
  let lineStart = m.index;
  while (lineStart > 0 && entryContent[lineStart - 1] !== '\n') lineStart--;

  let depth = 0;
  let i = m.index;

  while (i < entryContent.length) {
    const ch = entryContent[i];
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) return { start: lineStart, end: i + 1 };
    }
    i++;
  }
  return null;
}


// ============================================================
// PARSE DO BLOCO p1 EXISTENTE (extrai campos manuais extras)
// ============================================================

// extrai campos do bloco p1 do catalog.lua que NAO sao emitidos pelo balancer (overrides manuais).
// Parse minimo: busca pares `chave = valor` no nivel 1 do bloco p1.
// Limitacao consciente: nao parseia sub-tabelas aninhadas (nenhum campo manual atual usa isso).
// Campos do balancer sao descartados (o emitter e autoridade deles).
function extractManualFields(p1BlockContent) {
  const manual = {};

  // linha simples: `  key = valor,` ou `  key = valor` (sem virgula ao fim)
  // nao captura `base_alloc = {` (sub-tabela) — sera sobrescrita pelo emitter mesmo
  const lineRe = /^\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^{,\n]+),?\s*$/gm;
  for (const m of p1BlockContent.matchAll(lineRe)) {
    const key = m[1].trim();
    const rawVal = m[2].trim();
    if (!BALANCER_FIELDS.has(key)) {
      manual[key] = rawVal; // preserva o valor como string literal Lua
    }
  }
  return manual;
}


// ============================================================
// GERADOR DO BLOCO p1 NOVO
// ============================================================

// serializa um valor JS -> literal Lua (primitivos + tabela simples)
function luaVal(v) {
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') return String(v);
  if (typeof v === 'string') {
    // string sem aspas → e um identificador/tier (ex: 'S', 'A', 'rwd_heavy')
    return `'${v}'`;
  }
  if (typeof v === 'object') {
    // sub-tabela simples (base_alloc) — serializa em uma linha
    const pairs = Object.entries(v).map(([k, val]) => `${k}=${luaVal(val)}`).join(', ');
    return `{${pairs}}`;
  }
  return String(v);
}

// constroi o bloco `p1 = { ... }` completo a partir dos campos do emitter + campos manuais extras.
// Usa o mesmo indent da entrada existente (detectado do entryBlock).
function buildP1Block(entry, manualExtras, indent) {
  const ind = indent + '  '; // um nivel a mais que a entrada

  // ordem canonica dos campos emitidos
  const ordered = [
    ['handling_name', entry.handling_name],
    ['class_budget',  entry.class_budget],
    ['tier_max',      entry.tier_max],
    ['archetype',     entry.archetype],
    ['grip_modifier', entry.grip_modifier],
    ['base_alloc',    entry.base_alloc],
    ['drive_bias',    entry.drive_bias],
    ['susp_raise',    entry.susp_raise],
    ['mass',          entry.mass],
    ['inertia_z',     entry.inertia_z],
    ['low_speed_loss', entry.low_speed_loss],
    ['seal',          entry.seal],
  ].filter(([, v]) => v !== null && v !== undefined);

  // campos manuais extras (preservados ao final do bloco)
  for (const [k, rawLua] of Object.entries(manualExtras)) {
    ordered.push([k, { __raw: rawLua }]); // sentinela: raw Lua literal
  }

  const lines = ordered.map(([k, v]) => {
    const val = (v && v.__raw) ? v.__raw : luaVal(v);
    return `${ind}${k} = ${val},`;
  });

  return `${indent}p1 = {\n${lines.join('\n')}\n${indent}}`;
}


// ============================================================
// PATCH DE UMA ENTRADA
// ============================================================

// aplica um entry do catalog-patch em uma porcao do catalog.lua (o bloco da entrada).
// Retorna o entryBlock reescrito (ou o original se nao mudou).
function patchEntry(content, physKey, entry) {
  const loc = findEntryBlock(content, physKey);
  if (!loc) return null; // entrada nao encontrada — skip (warning emitido pelo caller)

  const entryContent = content.slice(loc.start, loc.end);

  // detecta indent da linha da entrada:
  // a ancora regex inclui os espacos no match (ex: '  TOYOTASUPRA = {')
  // portanto os espacos estao dentro de entryContent (que começa em loc.start)
  const indentMatch = entryContent.match(/^(\s*)[A-Za-z]/);
  const entryIndent = (indentMatch && indentMatch[1]) || '  ';
  const p1Indent = entryIndent + '  '; // p1 fica um nivel mais fundo

  const p1Loc = findP1Block(entryContent);
  const manualExtras = p1Loc
    ? extractManualFields(entryContent.slice(p1Loc.start, p1Loc.end))
    : {};

  const newP1 = buildP1Block(entry, manualExtras, p1Indent);

  let newEntryContent;
  if (p1Loc) {
    // substitui o bloco p1 existente
    newEntryContent = entryContent.slice(0, p1Loc.start) + newP1 + entryContent.slice(p1Loc.end);
  } else {
    // insere p1 antes do fechamento `}` da entrada (ultima `}` de nivel 0)
    // preserva trailing newline original
    const lastClose = entryContent.lastIndexOf('}');
    newEntryContent = entryContent.slice(0, lastClose)
      + `${p1Indent.slice(0, -2)}${newP1},\n${entryIndent}}`
      + entryContent.slice(lastClose + 1);
  }

  if (newEntryContent === entryContent) return null; // sem mudanca (idempotente)

  return {
    start: loc.start,
    end:   loc.end,
    replacement: newEntryContent,
  };
}


// ============================================================
// APPLY PRINCIPAL
// ============================================================

// aplica o catalog-patch.json no catalog.lua de forma cirurgica.
// `patchByKey` = { lowercase_key -> entry } (emitido por catalogEmitter.writePatch).
// Retorna { changed: bool, skipped: string[] } para o log do apply.
function applyPatch(patchByKey) {
  if (!io.exists(CATALOG_PATH)) {
    throw new Error(`catalog.lua nao encontrado em ${io.rel(CATALOG_PATH)}`);
  }

  const original = io.readText(CATALOG_PATH);
  const keyIndex = buildKeyIndex(original);

  let content  = original;
  const offset = []; // acumulador de deslocamento de indices apos cada substituicao
  const skipped = [];
  let totalChanged = 0;

  // processa cada key do patch (ordem alfabetica para diff estavel)
  for (const lcKey of Object.keys(patchByKey).sort()) {
    if (lcKey === '_doc') continue;
    const entry  = patchByKey[lcKey];
    const phys   = keyIndex[lcKey];

    if (!phys) {
      skipped.push(lcKey);
      log.warn(`catalogPatcher: '${lcKey}' ausente do catalog.lua — skip (adicione manualmente)`);
      continue;
    }

    // recalcula content com deslocamentos acumulados (cada substituicao desloca indices seguintes)
    const patch = patchEntry(content, phys, entry);
    if (!patch) continue; // sem mudanca real

    content = content.slice(0, patch.start) + patch.replacement + content.slice(patch.end);
    totalChanged++;
    log.ok(`  p1 aplicado: ${phys}`);
  }

  if (totalChanged === 0) {
    log.info('catalogPatcher: catalog.lua ja esta atualizado (idempotente).');
    return { changed: false, skipped };
  }

  io.writeText(CATALOG_PATH, content);
  log.ok(`catalogPatcher: catalog.lua atualizado (${totalChanged} entrada(s)).`);
  return { changed: true, skipped };
}


// ============================================================
// HELPERS
// ============================================================

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}


module.exports = { applyPatch, CATALOG_PATH };
