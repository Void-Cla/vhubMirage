// rename.js — renomeia o veículo (nome de spawn) em TODOS os arquivos do mod
//
// Mods vêm com nomes aleatórios (ex.: "a80"). Este módulo troca o token do modelo em todos
// os .meta da pasta de dados (modelName, txdName, handlingId, gameName, handlingName, refs de
// modkit/layout/driveby...) E renomeia os assets .yft/.ytd nomeados pelo modelo. Tudo:
//   - CIRÚRGICO: só o token muda no conteúdo (resto byte-a-byte) — replace no conteúdo inteiro;
//   - PREVIEW-FIRST: `preview()` mostra cada arquivo/ocorrência e cada asset antes de aplicar;
//   - BACKUP-SEMPRE: `execute()` faz backup de tudo antes de tocar qualquer arquivo;
//   - VALIDADO: confere que o token é seguro e que sobra um asset principal <novo>.yft.
//
// O token casa por DELIMITADOR (não \b): pega "a80" em STD_a80_FRONT e a80_modkit (vizinhos _),
// mas NÃO em "a800" nem "xa80" (vizinhos alfanuméricos). Case-insensitive, case-PRESERVADO.

const fs   = require('fs');
const path = require('path');
const io   = require('./io');


// erro de validação de rename — mapeado para exit/HTTP pelo chamador
class RenameError extends Error {
  constructor(msg) { super(msg); this.name = 'RenameError'; }
}


// ============================================================
// VALIDAÇÃO DO NOVO NOME
// ============================================================

// nome de modelo válido: letras/dígitos/underscore, 1..24 chars, começa com letra.
const NAME_RE = /^[A-Za-z][A-Za-z0-9_]{0,23}$/;

// valida e devolve o novo nome (ou lança RenameError com mensagem PT-BR)
function validateName(newName) {
  const n = String(newName || '').trim();
  if (!n) throw new RenameError('novo nome vazio.');
  if (!NAME_RE.test(n)) {
    throw new RenameError(
      `nome inválido: "${n}". Use letras/dígitos/underscore, começando por letra, até 24 chars.`);
  }
  return n;
}


// ============================================================
// SUBSTITUIÇÃO DE TOKEN (case-insensitive, case-preservada)
// ============================================================

// regex do token delimitado por não-alfanumérico (pega STD_a80_X e a80_modkit; não a800)
function tokenRegex(token) {
  const esc = token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(?<![A-Za-z0-9])${esc}(?![A-Za-z0-9])`, 'gi');
}

// preserva a caixa do trecho casado ao trocar pelo novo nome
function applyCase(matched, newName) {
  const isUpper = matched === matched.toUpperCase() && matched !== matched.toLowerCase();
  const isLower = matched === matched.toLowerCase();
  if (isUpper) return newName.toUpperCase();
  if (isLower) return newName.toLowerCase();
  return newName;
}

// troca todas as ocorrências do token no conteúdo inteiro (preserva todo o resto)
function replaceToken(content, token, newName) {
  return content.replace(tokenRegex(token), (m) => applyCase(m, newName));
}


// ============================================================
// PREVIEW (read-only)
// ============================================================

// monta o plano de rename SEM tocar nada: ocorrências por arquivo + renomeação de assets.
function preview(car, newNameRaw, existingModels) {
  const newName = validateName(newNameRaw);
  const token = car.model;
  const warnings = [];

  if (token.toLowerCase() === newName.toLowerCase()) {
    warnings.push('o novo nome é igual ao atual (nada mudaria).');
  }
  if (Array.isArray(existingModels)) {
    const collide = existingModels.find(
      (m) => m && m.toLowerCase() === newName.toLowerCase() && m.toLowerCase() !== token.toLowerCase());
    if (collide) warnings.push(`já existe outro veículo com o modelo "${newName}" — colisão de spawn.`);
  }

  // ---- ocorrências nos .meta ----
  const re = tokenRegex(token);
  const metaChanges = [];
  for (const [key, abs] of Object.entries(car.metaFilesAbs || {})) {
    if (!io.exists(abs)) continue;
    const content = io.readText(abs);
    const occ = lineOccurrences(content, token, newName);
    if (occ.length > 0) {
      metaChanges.push({ key, file: io.rel(abs), count: totalMatches(content, re), lines: occ });
    }
  }

  // ---- renomeação de assets ----
  const assetRenames = [];
  for (const a of car.assets || []) {
    const to = renameBasename(a.name, token, newName);
    if (to && to !== a.name) {
      assetRenames.push({ from: a.name, to, fromRel: a.rel });
    }
  }

  // ---- invariante: precisa sobrar um asset principal <novo>.yft ----
  const hasMainYft = (car.assets || []).some((a) => /\.yft$/i.test(a.name)
    && a.name.toLowerCase().replace(/\.yft$/i, '') === token.toLowerCase());
  if (!hasMainYft && assetRenames.length === 0) {
    warnings.push('nenhum asset principal <modelo>.yft encontrado — confira se o carro ainda ' +
      'vai spawnar com o novo nome (o .yft precisa casar com o modelName).');
  }

  return {
    handlingName: car.handlingName,
    oldName: token,
    newName,
    newHandlingName: applyCase(car.handlingNameRaw, newName),
    metaChanges,
    assetRenames,
    warnings,
    valid: warnings.every((w) => !w.includes('colisão')),
  };
}


// ============================================================
// EXECUTE (escreve — backup primeiro)
// ============================================================

// aplica o rename: backup -> reescreve .meta (token) -> renomeia assets. Devolve relatório.
function execute(car, newNameRaw, opts) {
  const newName = validateName(newNameRaw);
  const token = car.model;
  const doBackup = !opts || opts.backup !== false;

  // arquivos que serão tocados (metas com ocorrência + assets a renomear)
  const re = tokenRegex(token);
  const metaTargets = [];
  for (const abs of Object.values(car.metaFilesAbs || {})) {
    if (!io.exists(abs)) continue;
    if (totalMatches(io.readText(abs), re) > 0) metaTargets.push(abs);
  }
  const assetTargets = (car.assets || [])
    .filter((a) => renameBasename(a.name, token, newName) !== a.name)
    .map((a) => a.abs);

  if (metaTargets.length === 0 && assetTargets.length === 0) {
    return { changed: false, newName, message: 'nada a renomear.' };
  }

  // ---- backup de tudo antes de tocar ----
  let backupId = null;
  if (doBackup) backupId = io.backup([...metaTargets, ...assetTargets]);

  // ---- reescreve metas (token) ----
  const metasWritten = [];
  for (const abs of metaTargets) {
    const before = io.readText(abs);
    const after = replaceToken(before, token, newName);
    if (after !== before) { io.writeText(abs, after); metasWritten.push(io.rel(abs)); }
  }

  // ---- renomeia assets (.yft/.ytd) ----
  const assetsRenamed = [];
  for (const a of car.assets || []) {
    const toName = renameBasename(a.name, token, newName);
    if (toName === a.name) continue;
    const dest = path.join(path.dirname(a.abs), toName);
    if (fs.existsSync(dest)) {
      throw new RenameError(`destino já existe: ${io.rel(dest)} (rename abortado, sem perda).`);
    }
    fs.renameSync(a.abs, dest);
    assetsRenamed.push({ from: a.name, to: toName });
  }

  return {
    changed: true,
    newName,
    newHandlingName: applyCase(car.handlingNameRaw, newName),
    backupId,
    metasWritten,
    assetsRenamed,
  };
}


// ============================================================
// HELPERS
// ============================================================

// renomeia um basename trocando o token-prefixo pelo novo nome (a80_spoil.yft -> r34_spoil.yft)
function renameBasename(basename, token, newName) {
  const low = basename.toLowerCase();
  const tok = token.toLowerCase();
  if (!low.startsWith(tok)) return basename;
  const after = basename.slice(token.length);
  if (after !== '' && !after.startsWith('_') && !after.startsWith('.')) return basename;
  return newName + after;
}

// ocorrências por linha (para preview legível); execute NÃO usa isto (usa replace no todo)
function lineOccurrences(content, token, newName) {
  const re = tokenRegex(token);
  const out = [];
  content.split(/\r?\n/).forEach((line, i) => {
    re.lastIndex = 0;
    if (re.test(line)) {
      out.push({ n: i + 1, before: line.trim(), after: replaceToken(line, token, newName).trim() });
    }
  });
  return out;
}

// conta o total de ocorrências do token no conteúdo
function totalMatches(content, re) {
  re.lastIndex = 0;
  const m = content.match(re);
  return m ? m.length : 0;
}


module.exports = { preview, execute, validateName, replaceToken, RenameError };
