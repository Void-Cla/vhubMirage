// audio.js — diagnóstico e conserto de ÁUDIO customizado de veículos mod
//
// Carros com som próprio têm uma IDENTIDADE DE ÁUDIO separada do modelo. Ex.: o FERRARIF8 tem
// modelName "ferrarif8" mas o áudio é "ta488f154" (o nome com que o som foi COMPILADO). Essa
// identidade vive em:
//   - <audioNameHash> no vehicles.meta            (ex.: ta488f154)
//   - dentro dos .dat151.rel / .dat54.rel BINÁRIOS (ex.: bank "DLC_ta488f154\ta488f154")
//   - nos nomes dos arquivos .awc (banco de ondas) e .rel (definições)
//   - nas linhas data_file/files do fxmanifest.lua
//
// O nome verdadeiro está BAKED no binário (joaat) — NÃO dá para "renomear o som" por texto sem
// recompilar (CodeWalker). O que QUEBRA na prática é renomear os ARQUIVOS sem alinhar tudo:
// foi o caso do FERRARIF8 (arquivos viraram FERRARIF8_*, mas binário/manifest/hash = ta488f154).
//
// Este módulo: (1) DETECTA áudio custom; (2) descobre o nome VERDADEIRO (do binário); (3) acusa
// inconsistências; (4) CONSERTA com segurança — alinha NOMES de arquivo + fxmanifest + hash ao
// nome verdadeiro. Nunca edita o binário. Preview-first + backup.

const fs   = require('fs');
const path = require('path');
const io   = require('./io');

// extensões que compõem o áudio custom de um veículo
const AWC_RE = /\.awc$/i;
const DAT151_RE = /\.dat151\.rel$/i;
const DAT54_RE = /\.dat54\.rel$/i;


// ============================================================
// DETECÇÃO + DIAGNÓSTICO
// ============================================================

// inspeciona um carro e devolve o estado do áudio: { custom, status, canonical, files, problems, ... }
function detect(car) {
  const audioFiles = findAudioFiles(car.carRootAbs);
  const audioNameHash = readAudioHash(car.metaFilesAbs && car.metaFilesAbs.vehicles);

  if (audioFiles.length === 0) {
    // sem .awc/.rel = som NATIVO do GTA (audioNameHash aponta p/ um som do jogo). Sem problema.
    return { custom: false, status: 'none', audioNameHash, canonical: audioNameHash,
             files: [], fxmanifest: null, manifestRefs: [], problems: [] };
  }

  // nome verdadeiro do áudio: do banco referenciado no .dat54 (binário); fallback = audioNameHash
  const dat54 = audioFiles.find((f) => f.kind === 'dat54');
  const canonical = (dat54 && bankTokenFromDat(dat54.abs)) || audioNameHash || null;

  const fxmanifest = findManifest(car.carRootAbs);
  const manifestRefs = fxmanifest ? relRefsFromManifest(fxmanifest.abs) : [];

  // diagnóstico
  const problems = [];
  const ledger = audioFiles.map((f) => {
    const ok = canonical && f.leadingToken.toLowerCase() === canonical.toLowerCase();
    if (!ok) problems.push(`arquivo "${f.name}" não bate com o nome do áudio "${canonical}".`);
    return { ...f, ok };
  });

  if (canonical && audioNameHash && audioNameHash.toLowerCase() !== canonical.toLowerCase()) {
    problems.push(`audioNameHash "${audioNameHash}" difere do nome real do áudio "${canonical}".`);
  }
  for (const ref of manifestRefs) {
    if (!ref.exists) problems.push(`fxmanifest aponta para "${ref.file}", que não existe no disco.`);
  }
  if (!canonical) problems.push('não foi possível determinar o nome real do áudio (binário ilegível).');

  return {
    custom: true,
    status: problems.length ? 'broken' : 'ok',
    audioNameHash,
    canonical,
    files: ledger,
    fxmanifest: fxmanifest ? { abs: fxmanifest.abs, rel: io.rel(fxmanifest.abs) } : null,
    manifestRefs,
    problems,
  };
}


// ============================================================
// PREVIEW DO CONSERTO (read-only)
// ============================================================

// monta o plano de conserto: renomear arquivos + ajustar fxmanifest + alinhar audioNameHash.
function previewFix(car) {
  const info = detect(car);
  if (!info.custom) return { applicable: false, reason: 'este carro usa som nativo (sem áudio custom).' };
  if (info.status === 'ok') return { applicable: false, reason: 'o áudio já está consistente.', info };
  if (!info.canonical) return { applicable: false, reason: 'nome real do áudio indeterminável; conserto manual.', info };

  const canonical = info.canonical;

  // 1) renomear arquivos de áudio cujo token líder ≠ canonical
  const fileRenames = [];
  const wrongTokens = new Set();
  for (const f of info.files) {
    if (f.ok) continue;
    const to = renameAudioBasename(f.name, canonical);
    if (to !== f.name) {
      fileRenames.push({ from: f.name, to, fromAbs: f.abs, dir: path.dirname(f.abs) });
      if (f.leadingToken.toLowerCase() !== canonical.toLowerCase()) wrongTokens.add(f.leadingToken);
    }
  }

  // 2) ajustar fxmanifest: trocar tokens errados → canonical (delimitado)
  const manifestEdits = [];
  if (info.fxmanifest) {
    const before = io.readText(info.fxmanifest.abs);
    let after = before;
    for (const wt of wrongTokens) after = replaceTokenInText(after, wt, canonical);
    if (after !== before) {
      manifestEdits.push({ file: info.fxmanifest.rel, lines: diffLines(before, after) });
    }
  }

  // 3) alinhar audioNameHash (se diferente do canonical)
  let hashEdit = null;
  if (info.audioNameHash && info.audioNameHash.toLowerCase() !== canonical.toLowerCase()) {
    hashEdit = { from: info.audioNameHash, to: canonical };
  }

  return { applicable: true, info, canonical, fileRenames, manifestEdits, hashEdit,
           wrongTokens: [...wrongTokens] };
}


// ============================================================
// EXECUTE (escreve — backup primeiro)
// ============================================================

// aplica o conserto: backup -> renomeia arquivos -> ajusta fxmanifest -> alinha audioNameHash.
function executeFix(car, opts) {
  const plan = previewFix(car);
  if (!plan.applicable) return { changed: false, reason: plan.reason };

  const doBackup = !opts || opts.backup !== false;
  const touched = [
    ...plan.fileRenames.map((r) => r.fromAbs),
    ...(plan.manifestEdits.length ? [plan.info.fxmanifest.abs] : []),
    ...(plan.hashEdit && car.metaFilesAbs.vehicles ? [car.metaFilesAbs.vehicles] : []),
  ];

  let backupId = null;
  if (doBackup && touched.length) backupId = io.backup(touched);

  // renomear arquivos de áudio
  const renamed = [];
  for (const r of plan.fileRenames) {
    const dest = path.join(r.dir, r.to);
    if (fs.existsSync(dest)) throw new Error(`destino já existe: ${io.rel(dest)} (conserto abortado).`);
    fs.renameSync(r.fromAbs, dest);
    renamed.push({ from: r.from, to: r.to });
  }

  // ajustar fxmanifest
  let manifestFixed = false;
  if (plan.manifestEdits.length) {
    const before = io.readText(plan.info.fxmanifest.abs);
    let after = before;
    for (const wt of plan.wrongTokens) after = replaceTokenInText(after, wt, plan.canonical);
    if (after !== before) { io.writeText(plan.info.fxmanifest.abs, after); manifestFixed = true; }
  }

  // alinhar audioNameHash
  let hashFixed = false;
  if (plan.hashEdit && car.metaFilesAbs.vehicles) {
    const before = io.readText(car.metaFilesAbs.vehicles);
    const after = before.replace(/(<audioNameHash>)\s*[^<]*\s*(<\/audioNameHash>)/,
      `$1${plan.canonical}$2`);
    if (after !== before) { io.writeText(car.metaFilesAbs.vehicles, after); hashFixed = true; }
  }

  return { changed: true, canonical: plan.canonical, backupId,
           renamed, manifestFixed, hashFixed };
}


// ============================================================
// HELPERS — descoberta de arquivos
// ============================================================

// localiza .awc/.dat151.rel/.dat54.rel sob a raiz do carro
function findAudioFiles(carRootAbs) {
  if (!carRootAbs) return [];
  const out = [];
  const walk = (dir) => {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) { walk(full); continue; }
      let kind = null;
      if (DAT151_RE.test(e.name)) kind = 'dat151';
      else if (DAT54_RE.test(e.name)) kind = 'dat54';
      else if (AWC_RE.test(e.name)) kind = 'awc';
      if (kind) out.push({ name: e.name, abs: full, rel: io.rel(full), kind,
                           leadingToken: leadingToken(e.name) });
    }
  };
  walk(carRootAbs);
  return out;
}

// token líder de um basename de áudio (parte antes do primeiro _ ou .)
function leadingToken(basename) {
  const m = basename.match(/^([^_.]+)/);
  return m ? m[1] : basename;
}

// reescreve o basename trocando o token líder pelo nome canônico (preserva o sufixo)
function renameAudioBasename(basename, canonical) {
  const m = basename.match(/^([^_.]+)(.*)$/);
  if (!m) return basename;
  if (m[1].toLowerCase() === canonical.toLowerCase()) return basename;
  return canonical + m[2];
}

// extrai o nome do banco do .dat54 binário a partir de "DLC_<token>\..." (ASCII embutido)
function bankTokenFromDat(absPath) {
  let buf;
  try { buf = fs.readFileSync(absPath); } catch { return null; }
  let run = '', best = null;
  for (const ch of buf) {
    if (ch >= 32 && ch < 127) { run += String.fromCharCode(ch); }
    else { best = best || scanBank(run); run = ''; }
  }
  return best || scanBank(run);
}
function scanBank(run) {
  const m = run.match(/DLC_([A-Za-z0-9]+)/);
  return m ? m[1] : null;
}

// lê o <audioNameHash> do vehicles.meta
function readAudioHash(vehiclesAbs) {
  if (!vehiclesAbs || !io.exists(vehiclesAbs)) return null;
  const m = io.readText(vehiclesAbs).match(/<audioNameHash>\s*([^<]+?)\s*<\/audioNameHash>/);
  return m ? m[1].trim() : null;
}

// acha o fxmanifest do recurso (na raiz do carro; senão na pasta-mãe)
function findManifest(carRootAbs) {
  for (const dir of [carRootAbs, path.dirname(carRootAbs)]) {
    for (const name of ['fxmanifest.lua', '__resource.lua']) {
      const abs = path.join(dir, name);
      if (io.exists(abs)) return { abs };
    }
  }
  return null;
}

// extrai referências a .rel do fxmanifest e checa se existem no disco
function relRefsFromManifest(manifestAbs) {
  const dir = path.dirname(manifestAbs);
  const content = io.readText(manifestAbs);
  const refs = [];
  const re = /['"]([^'"]+\.(?:dat151|dat54)\.rel)['"]/g;
  const seen = new Set();
  let m;
  while ((m = re.exec(content)) !== null) {
    const file = m[1];
    if (seen.has(file)) continue;
    seen.add(file);
    refs.push({ file, exists: io.exists(path.join(dir, file)) });
  }
  return refs;
}


// ============================================================
// HELPERS — texto
// ============================================================

// troca um token delimitado (case-insensitive) pelo nome canônico na sua caixa EXATA.
// Diferente do rename de modelo: o áudio tem UMA verdade (o nome no binário), e os nomes de
// arquivo/manifest precisam bater EXATAMENTE com ela (servidor Linux é case-sensitive).
function replaceTokenInText(content, token, canonical) {
  const esc = token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(?<![A-Za-z0-9])${esc}(?![A-Za-z0-9])`, 'gi');
  return content.replace(re, canonical);
}

// linhas que mudaram entre dois textos (para preview do fxmanifest)
function diffLines(before, after) {
  const a = before.split(/\r?\n/), b = after.split(/\r?\n/);
  const out = [];
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) out.push({ n: i + 1, before: a[i].trim(), after: (b[i] || '').trim() });
  }
  return out;
}


module.exports = { detect, previewFix, executeFix };
