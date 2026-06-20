// io.js — leitura/escrita preservando bytes, descoberta por glob e backup
//
// Regra de ouro do pipeline (script.md §6): NUNCA reserializar o arquivo. Lemos o
// conteudo como texto, alteramos so as substrings-alvo no meta.js, e gravamos de volta
// o MESMO texto com apenas essas substrings trocadas. Sem normalizar BOM, line-endings
// ou trailing newline. Aqui ficam apenas as primitivas de I/O e localizacao de arquivos.

const fs   = require('fs');
const path = require('path');


// ============================================================
// CONSTANTES DE CAMINHO
// ============================================================

// raiz do repo, resolvida a partir de tools/handling-balancer/ -> ../../
const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');

// raiz do proprio tool (onde vivem config/, out/, .seal/, .backups/)
const TOOL_ROOT = path.resolve(__dirname, '..');


// ============================================================
// LEITURA / ESCRITA (preserva bytes)
// ============================================================

// le um arquivo de texto UTF-8 preservando o conteudo exato (incl. BOM se houver)
function readText(absPath) {
  return fs.readFileSync(absPath, 'utf8');
}

// grava texto exatamente como recebido (sem tocar EOL/BOM/trailing newline)
function writeText(absPath, content) {
  fs.mkdirSync(path.dirname(absPath), { recursive: true });
  fs.writeFileSync(absPath, content, 'utf8');
}

// le JSON com mensagem de erro clara apontando o arquivo (usado por config/seal)
function readJson(absPath) {
  const raw = fs.readFileSync(absPath, 'utf8');
  try {
    return JSON.parse(raw);
  } catch (e) {
    const err = new Error(`JSON invalido em ${rel(absPath)}: ${e.message}`);
    err.io = true;
    throw err;
  }
}

// grava JSON identado (artefatos: seal.json, catalog-patch.json, build-report.json)
function writeJson(absPath, obj) {
  writeText(absPath, JSON.stringify(obj, null, 2) + '\n');
}

// true se o arquivo existe
function exists(absPath) {
  return fs.existsSync(absPath);
}


// ============================================================
// DESCOBERTA POR GLOB (sem dependencia externa)
// ============================================================

// varre os roots recursivamente e devolve os caminhos absolutos dos arquivos-alvo
function discover(roots, matchFiles, exclude) {
  const targets = new Set(matchFiles);
  const blocked = new Set(exclude || []);
  const found = [];

  const walk = (dir) => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return; // root inexistente (ex.: [CAR]/carmod vazio) — ignora silenciosamente
    }

    for (const entry of entries) {
      if (blocked.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (targets.has(entry.name)) {
        found.push(full);
      }
    }
  };

  for (const root of roots) {
    walk(path.resolve(REPO_ROOT, root));
  }
  return found.sort();
}


// ============================================================
// BACKUP (rede de seguranca antes de `apply`)
// ============================================================

// copia o .meta para .backups/<timestamp>/<path-relativo-ao-repo>; devolve o id do lote
function backup(absPaths) {
  const id = stamp();
  const root = path.join(TOOL_ROOT, '.backups', id);
  for (const abs of absPaths) {
    const relPath = path.relative(REPO_ROOT, abs);
    const dest = path.join(root, relPath);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(abs, dest);
  }
  return id;
}

// lista os ids de backup disponiveis (mais recente primeiro)
function listBackups() {
  const root = path.join(TOOL_ROOT, '.backups');
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(root, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort()
    .reverse();
}

// restaura todos os arquivos de um lote de backup para suas posicoes originais no repo
function restoreBackup(id) {
  const root = path.join(TOOL_ROOT, '.backups', id);
  if (!fs.existsSync(root)) {
    const err = new Error(`backup nao encontrado: ${id}`);
    err.io = true;
    throw err;
  }

  const restored = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else {
        const relPath = path.relative(root, full);
        const dest = path.join(REPO_ROOT, relPath);
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.copyFileSync(full, dest);
        restored.push(dest);
      }
    }
  };
  walk(root);
  return restored;
}


// ============================================================
// HELPERS
// ============================================================

// caminho relativo ao repo, com barras normais (mensagens e seal.json consistentes)
function rel(absPath) {
  return path.relative(REPO_ROOT, absPath).split(path.sep).join('/');
}

// timestamp compacto para id de backup (YYYYMMDD-HHMMSS)
function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-` +
         `${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}


module.exports = {
  REPO_ROOT, TOOL_ROOT,
  readText, writeText, readJson, writeJson, exists,
  discover, backup, listBackups, restoreBackup,
  rel, stamp,
};
