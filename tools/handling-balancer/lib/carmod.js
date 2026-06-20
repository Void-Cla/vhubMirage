// carmod.js — descoberta do MOD completo de um carro (além do handling.meta)
//
// O handling.meta sozinho não basta para renomear: o "nome aleatório" do mod (o modelName,
// o nome de spawn) vive em vehicles.meta e dá nome aos arquivos .yft/.ytd. Este módulo liga
// cada bloco de handling ao seu InitData em vehicles.meta e descobre os metas irmãos + os
// assets de stream, para que o rename possa atuar em TODOS os arquivos necessários.
//
// Convenção da árvore (verificada no repo):
//   carmod/<pasta>/common/handling.meta   (dados)
//   carmod/stream/<pasta>/<model>*.yft     (assets nomeados pelo MODELO, não pela pasta)
// A pasta (ex.: "supra") pode diferir do modelo (ex.: "a80") — o token de rename é o MODELO.

const fs   = require('fs');
const path = require('path');
const io   = require('./io');
const meta = require('./meta');
const { norm } = require('./util');


// ============================================================
// DESCOBERTA DE TODOS OS CARROS
// ============================================================

// devolve [car] — um por bloco <Item CHandlingData> encontrado nos scan-paths.
function discoverAll(cfg) {
  const sp = cfg.scanPaths;
  const handlingPaths = io.discover(sp.roots, sp.matchFiles, sp.exclude);
  const cars = [];

  for (const hAbs of handlingPaths) {
    const content = io.readText(hAbs);
    for (const seg of meta.splitBlocks(content)) {
      if (!seg.isHandling) continue;
      const raw = readRawName(seg.text);
      if (!raw) continue;
      cars.push(buildCar(hAbs, raw, seg.text, cfg));
    }
  }
  return cars;
}


// monta o objeto Car completo a partir do handling.meta + vizinhança no disco.
function buildCar(handlingAbs, handlingNameRaw, block, cfg) {
  const handlingName = norm(handlingNameRaw);
  const dataDir = path.dirname(handlingAbs);
  const carRoot = ['common', 'data'].includes(path.basename(dataDir).toLowerCase())
    ? path.dirname(dataDir) : dataDir;
  const carFolder = path.basename(carRoot);

  const metaFiles = listMetaFiles(dataDir);
  const vehInfo = resolveVehicleInfo(metaFiles.vehicles, handlingName);

  // token de rename = modelName (nome de spawn / base dos assets). Fallback = handlingName.
  const modelToken = vehInfo.modelName || handlingNameRaw.trim();
  const txdToken   = vehInfo.txdName || modelToken;

  const stream = findStream(carRoot, carFolder, [modelToken, txdToken]);

  return {
    handlingName,                 // normalizado (UPPER) — chave do registry/seal
    handlingNameRaw: handlingNameRaw.trim(),
    handlingFile: io.rel(handlingAbs),
    handlingAbs,
    block,
    carFolder,
    carRootAbs: carRoot,          // raiz do mod (p/ descoberta de áudio/fxmanifest)
    dataDir: io.rel(dataDir),
    dataDirAbs: dataDir,
    metaFiles,                    // { handling, vehicles, carcols, carvariations, ... } (rel)
    metaFilesAbs: metaFiles._abs, // mesmos paths absolutos
    model: modelToken,            // nome de spawn atual ("a80", "skyline", "370z")
    txd: txdToken,
    vehicleInfo: vehInfo,         // { modelName, txdName, handlingId, gameName }
    streamDir: stream.dir ? io.rel(stream.dir) : null,
    streamDirAbs: stream.dir,
    assets: stream.files,         // [{ name, rel }] do MODELO — só .yft/.ytd (áudio é à parte)
    registry: cfg.registry[handlingName] || null,
  };
}


// ============================================================
// vehicles.meta — liga handlingId -> modelName/txdName/gameName
// ============================================================

// resolve o InitData cujo handlingId casa com o handlingName; single-car usa o único item.
function resolveVehicleInfo(vehiclesAbs, handlingName) {
  const empty = { modelName: null, txdName: null, handlingId: null, gameName: null };
  if (!vehiclesAbs || !io.exists(vehiclesAbs)) return empty;

  const content = io.readText(vehiclesAbs);
  const items = splitInitDataItems(content);
  if (items.length === 0) return empty;

  const read = (item) => ({
    modelName: tag(item, 'modelName'),
    txdName:   tag(item, 'txdName'),
    handlingId:tag(item, 'handlingId'),
    gameName:  tag(item, 'gameName'),
  });

  if (items.length === 1) return read(items[0]);

  // multi-car: casa pelo handlingId
  for (const item of items) {
    const info = read(item);
    if (info.handlingId && norm(info.handlingId) === handlingName) return info;
  }
  return read(items[0]); // fallback: primeiro item
}

// isola <InitDatas> e fatia em <Item> de TOPO (depth-aware: itens aninhados existem)
function splitInitDataItems(content) {
  const region = (content.match(/<InitDatas>([\s\S]*?)<\/InitDatas>/) || [null, content])[1];
  const items = [];
  const tok = /<Item\b[^>]*?(\/?)>|<\/Item>/g;
  let depth = 0, start = -1, m;
  while ((m = tok.exec(region)) !== null) {
    if (m[0] === '</Item>') {
      depth -= 1;
      if (depth === 0 && start >= 0) { items.push(region.slice(start, tok.lastIndex)); start = -1; }
    } else if (m[1] !== '/') {
      if (depth === 0) start = m.index;
      depth += 1;
    }
  }
  return items;
}


// ============================================================
// METAS IRMÃOS + STREAM
// ============================================================

// lista os *.meta da pasta de dados, indexados por nome conhecido + lista bruta.
function listMetaFiles(dataDir) {
  const out = { _abs: {} };
  let entries = [];
  try { entries = fs.readdirSync(dataDir); } catch { /* dir some — devolve vazio */ }

  for (const name of entries) {
    if (!name.toLowerCase().endsWith('.meta')) continue;
    const abs = path.join(dataDir, name);
    const key = metaKey(name);
    out[key] = io.rel(abs);
    out._abs[key] = abs;
  }
  return out;
}

// chave amigável por nome de arquivo .meta
function metaKey(name) {
  const n = name.toLowerCase();
  if (n.includes('handling'))      return 'handling';
  if (n.includes('carvariations')) return 'carvariations';
  if (n.includes('carcols'))       return 'carcols';
  if (n.includes('vehiclelayouts'))return 'vehiclelayouts';
  if (n.includes('vehicles'))      return 'vehicles';
  if (n.includes('contentunlocks'))return 'contentunlocks';
  if (n.includes('dlctext'))       return 'dlctext';
  return n.replace(/\.meta$/, '');
}

// acha a pasta de stream (carmod/stream/<pasta>) e os assets nomeados pelos tokens do modelo.
function findStream(carRoot, carFolder, tokens) {
  const carmodDir = path.dirname(carRoot);             // .../carmod
  const candidates = [
    path.join(carmodDir, 'stream', carFolder),
    path.join(carRoot, 'stream'),
    path.join(carmodDir, 'stream'),
  ];

  for (const dir of candidates) {
    if (!io.exists(dir)) continue;
    const files = collectAssets(dir, tokens);
    if (files.length > 0) return { dir, files };
  }
  return { dir: null, files: [] };
}

// assets do MODELO = só arquivos visuais .yft/.ytd. Áudio (.awc/.rel) é identidade SEPARADA
// (ver lib/audio.js) e NUNCA entra no rename do modelo.
const MODEL_ASSET_RE = /\.(yft|ytd)$/i;

// arquivos .yft/.ytd (recursivo) cujo basename casa um dos tokens do modelo (prefixo delimitado)
function collectAssets(dir, tokens) {
  const found = [];
  const toks = tokens.filter(Boolean).map((t) => t.toLowerCase());

  const walk = (d) => {
    let entries;
    try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const full = path.join(d, e.name);
      if (e.isDirectory()) { walk(full); continue; }
      if (!MODEL_ASSET_RE.test(e.name)) continue;       // ignora áudio e outros não-modelo
      const base = e.name.toLowerCase();
      if (toks.some((t) => assetMatchesToken(base, t))) {
        found.push({ name: e.name, rel: io.rel(full), abs: full });
      }
    }
  };
  walk(dir);
  return found.sort((a, b) => a.name.localeCompare(b.name));
}

// true se o arquivo é "<token>.ext" ou "<token>_algo.ext" (prefixo delimitado por _ ou .)
function assetMatchesToken(basename, token) {
  if (!basename.startsWith(token)) return false;
  const after = basename.slice(token.length);
  return after === '' || after.startsWith('_') || after.startsWith('.');
}


// ============================================================
// HELPERS
// ============================================================

function tag(block, name) {
  const m = block.match(new RegExp(`<${name}>\\s*([^<]+?)\\s*</${name}>`));
  return m ? m[1].trim() : null;
}

function readRawName(block) {
  const m = block.match(/<handlingName>\s*([^<]+?)\s*<\/handlingName>/);
  return m ? m[1] : null;
}


module.exports = { discoverAll, buildCar, assetMatchesToken, splitInitDataItems };
