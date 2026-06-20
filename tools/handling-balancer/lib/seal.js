// seal.js — selo de integridade (sha256) e deteccao de drift
//
// O selo registra um hash assinado do estado APROVADO de cada .meta. `verify` recomputa
// o hash e compara: divergiu => o carro foi editado a mao fora do pipeline (drift), e o
// CI falha (script.md §11). O .seal/seal.json e a FONTE VIVA do hash (so `verify` o le);
// o hash que vai dentro do catalog-patch e uma COPIA de auditoria do momento do apply.
//
// Chave do seal = handlingName normalizado (UPPERCASE), espelhando como ele vive no .meta.
// (O catalog-patch usa key lowercase para casar com o catalogo — convencao separada,
// intencional: dominios diferentes, integridade-do-arquivo vs merge-no-catalogo.)

const crypto = require('crypto');
const path   = require('path');
const io     = require('./io');

const SEAL_PATH = path.join(io.TOOL_ROOT, '.seal', 'seal.json');


// ============================================================
// HASH
// ============================================================

// sha256 do conteudo (prefixado 'sha256:' para deixar o algoritmo explicito no JSON)
function hashContent(content) {
  return 'sha256:' + crypto.createHash('sha256').update(content, 'utf8').digest('hex');
}

// sha256 de um arquivo .meta no disco
function hashFile(absPath) {
  return hashContent(io.readText(absPath));
}


// ============================================================
// PERSISTENCIA DO SELO
// ============================================================

// le o seal.json atual (objeto handlingName -> { tier, sha256, file }); {} se nao existir
function read() {
  if (!io.exists(SEAL_PATH)) return {};
  const raw = io.readJson(SEAL_PATH);
  delete raw._doc;
  return raw;
}

// grava o seal.json (ordenado por handlingName para diff git estavel)
function write(sealMap) {
  const ordered = {
    _doc: 'Selo de integridade gerado por `apply`/`seal`. Chave = handlingName real do ' +
          '.meta. `verify` recomputa o sha256 de cada arquivo e falha (exit 1) se divergir. ' +
          'NAO editar a mao.',
  };
  for (const key of Object.keys(sealMap).sort()) ordered[key] = sealMap[key];
  io.writeJson(SEAL_PATH, ordered);
}


// ============================================================
// COMPARACAO (drift)
// ============================================================

// compara o estado atual dos arquivos contra o selo gravado.
// `entries` = [{ name, file, content }]. devolve { ok, drift:[], missing:[], unsealed:[] }.
function diff(entries, sealMap) {
  const result = { ok: true, drift: [], missing: [], unsealed: [] };

  for (const e of entries) {
    const sealed = sealMap[e.name];
    if (!sealed) {
      result.unsealed.push(e.name); // carro classificado mas nunca selado
      result.ok = false;
      continue;
    }
    const current = hashContent(e.content);
    if (current !== sealed.sha256) {
      result.drift.push({ name: e.name, file: e.file, expected: sealed.sha256, got: current });
      result.ok = false;
    }
  }

  // selo aponta um arquivo que nao apareceu mais no scan
  const seen = new Set(entries.map((e) => e.name));
  for (const name of Object.keys(sealMap)) {
    if (name === '_doc') continue;
    if (!seen.has(name)) {
      result.missing.push(name);
      result.ok = false;
    }
  }

  return result;
}


module.exports = { hashContent, hashFile, read, write, diff, SEAL_PATH };
