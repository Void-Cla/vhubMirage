// server.js — servidor HTTP local + API JSON para a interface humana
//
// Tudo roda em 127.0.0.1 (ferramenta de dev offline; sem auth, sem rede externa). A UI em
// web/ consome esta API. Cada request carrega a config fresca (cheap p/ dezenas de carros) —
// assim mudanças no registry.json refletem na hora.
//
// Endpoints:
//   GET  /                      -> web/index.html (e /style.css, /app.js)
//   GET  /api/cars              -> lista de carros (perfil, score, tier calc/registry, assets)
//   POST /api/preview           -> diff dos 8 campos + bloco p1 p/ um tier escolhido
//   POST /api/reconcile         -> calculado x desejado x média (sem tocar nada)
//   POST /api/rename            -> preview (execute=false) ou aplica (execute=true) o rename
//   POST /api/apply             -> persiste o tier no registry e aplica o balanceamento

const http = require('http');
const fs   = require('fs');
const path = require('path');

const config        = require('./config');
const carmod        = require('./carmod');
const profiler      = require('./profiler');
const tiers         = require('./tiers');
const meta          = require('./meta');
const emitter       = require('./catalogEmitter');
const registryStore = require('./registryStore');
const rename        = require('./rename');
const audio         = require('./audio');
const report        = require('./report');
const io            = require('./io');
const { isNum, norm } = require('./util');

const applyCmd = require('../commands/apply');

const WEB_DIR = path.join(io.TOOL_ROOT, 'web');


// ============================================================
// MONTAGEM DA VISÃO DE UM CARRO (perfil + tiers)
// ============================================================

// junta carmod + profiler + tier para a UI. `analysis` reaproveitado em preview.
function carView(car, cfg) {
  const a = profiler.analyze(car.block, cfg.tiers);
  const registryTier = car.registry ? car.registry.tier_base : null;
  const au = audio.detect(car);
  return {
    audio: {
      custom: au.custom, status: au.status, canonical: au.canonical,
      audioNameHash: au.audioNameHash, problems: au.problems,
      files: au.files.map((f) => ({ name: f.name, kind: f.kind, ok: f.ok })),
    },
    handlingName: car.handlingName,
    handlingNameRaw: car.handlingNameRaw,
    model: car.model,
    carFolder: car.carFolder,
    dataDir: car.dataDir,
    handlingFile: car.handlingFile,
    drivetrain: a.drivetrain,
    score: a.score,
    calculatedTier: a.calculatedTier,
    parts: a.parts,
    powerToWeight: a.powerToWeight,
    notes: a.notes,
    fingerprint: a.fingerprint,
    registry: car.registry,                 // { tier_base, tier_max } | null
    currentTier: registryTier || a.calculatedTier,
    metaFiles: Object.keys(car.metaFiles).filter((k) => k !== '_abs'),
    assetsCount: (car.assets || []).length,
    streamDir: car.streamDir,
  };
}

// calcula o diff dos 8 campos + bloco p1 para um tier escolhido (preview, sem gravar)
function balanceFor(car, cfg, tierKey) {
  // injeta o tier escolhido na config em memória para o emitter casar (não persiste)
  const localCfg = { ...cfg, registry: { ...cfg.registry } };
  const prevReg = localCfg.registry[car.handlingName] || {};
  localCfg.registry[car.handlingName] = {
    tier_base: tierKey,
    tier_max: bumpTier(tierKey, prevReg.tier_max),
  };

  const { targets, clampInfo } = tiers.resolveTargets(car.handlingName, localCfg, tierKey);
  const fields = tiers.FIELDS.map((f) => {
    const from = meta.readValue(car.block, f);
    const r = meta.setValue(car.block, f, targets[f]);
    return { field: f, from: isNum(from) ? from : null, to: targets[f],
             changed: r.changed, missing: r.missing };
  });

  const p1 = emitter.buildEntry(car.handlingNameRaw, car.block, localCfg, '(preview)');
  return { tier: tierKey, fields, p1, clampInfo };
}


// ============================================================
// HANDLERS DA API
// ============================================================

const routes = {

  // lista todos os carros com perfil e tiers
  'GET /api/cars': (req, res) => {
    const cfg = config.load();
    const cars = carmod.discoverAll(cfg).map((c) => carView(c, cfg));
    sendJson(res, 200, { cars, tiers: tiers.ORDER });
  },

  // diff de balanceamento para um tier escolhido
  'POST /api/preview': (req, res, body) => {
    const cfg = config.load();
    const car = findCar(cfg, body.handlingName);
    if (!car) return sendJson(res, 404, { error: 'carro não encontrado' });
    const tier = validTier(body.tier) || profiler.analyze(car.block, cfg.tiers).calculatedTier;
    sendJson(res, 200, balanceFor(car, cfg, tier));
  },

  // calculado x desejado x média (sem tocar nada)
  'POST /api/reconcile': (req, res, body) => {
    const cfg = config.load();
    const car = findCar(cfg, body.handlingName);
    if (!car) return sendJson(res, 404, { error: 'carro não encontrado' });
    const calc = profiler.analyze(car.block, cfg.tiers).calculatedTier;
    sendJson(res, 200, tiers.reconcileTier(calc, validTier(body.desired), body.mode));
  },

  // rename: execute=false -> preview; execute=true -> aplica (backup + token + assets)
  'POST /api/rename': (req, res, body) => {
    const cfg = config.load();
    const car = findCar(cfg, body.handlingName);
    if (!car) return sendJson(res, 404, { error: 'carro não encontrado' });
    const others = carmod.discoverAll(cfg).map((c) => c.model);

    try {
      if (!body.execute) {
        return sendJson(res, 200, rename.preview(car, body.newName, others));
      }
      const result = rename.execute(car, body.newName, { backup: true });
      if (result.changed && result.newHandlingName) {
        registryStore.migrateKey(car.handlingName, norm(result.newHandlingName));
      }
      sendJson(res, 200, { ok: true, ...result,
        note: 'rode o balanceamento de novo (apply) para re-selar o .meta com o novo nome.' });
    } catch (e) {
      sendJson(res, 400, { error: e.message });
    }
  },

  // áudio custom: execute=false -> preview do conserto; execute=true -> conserta (backup+rename+manifest)
  'POST /api/audio-fix': (req, res, body) => {
    const cfg = config.load();
    const car = findCar(cfg, body.handlingName);
    if (!car) return sendJson(res, 404, { error: 'carro não encontrado' });
    try {
      if (!body.execute) return sendJson(res, 200, audio.previewFix(car));
      const result = audio.executeFix(car, { backup: true });
      sendJson(res, 200, { ok: true, ...result });
    } catch (e) {
      sendJson(res, 400, { error: e.message });
    }
  },

  // persiste o tier escolhido no registry e aplica o balanceamento desse carro
  'POST /api/apply': (req, res, body) => {
    const tierBase = validTier(body.tierBase);
    if (!tierBase) return sendJson(res, 400, { error: 'tier inválido' });
    const tierMax = validTier(body.tierMax) || bumpTier(tierBase);

    // 1) persiste a decisão no registry (fonte única; CLI lê o mesmo)
    registryStore.setTier(body.handlingName, tierBase, tierMax);

    // 2) aplica só este carro (config recarregada para pegar o tier novo)
    const freshCfg = config.load();
    try {
      const code = applyCmd.run({ only: norm(body.handlingName) }, freshCfg);
      const out = {
        ok: code === 0,
        exitCode: code,
        report: readMaybe(report.REPORT_PATH),
        patch: readMaybe(emitter.PATCH_PATH),
      };
      sendJson(res, code === 0 ? 200 : 500, out);
    } catch (e) {
      sendJson(res, 500, { ok: false, error: e.message });
    }
  },
};


// ============================================================
// SERVIDOR HTTP
// ============================================================

// inicia o servidor na porta dada (default 7920), bind em 127.0.0.1
function start(port) {
  const p = port || 7920;
  const server = http.createServer((req, res) => {
    const url = req.url.split('?')[0];
    const key = `${req.method} ${url}`;

    // API (com corpo JSON em POST)
    if (url.startsWith('/api/')) {
      const handler = routes[key];
      if (!handler) return sendJson(res, 404, { error: 'rota desconhecida' });
      if (req.method === 'POST') return readBody(req, res, handler);
      return handler(req, res, {});
    }

    // estáticos (web/)
    serveStatic(url, res);
  });

  server.listen(p, '127.0.0.1', () => {
    report.log.head('vHub Handling Balancer — interface web');
    report.log.ok(`servidor no ar: http://127.0.0.1:${p}`);
    report.log.info('abra o endereço acima no navegador. Ctrl+C para encerrar.');
  });
  return server;
}


// ============================================================
// HELPERS HTTP
// ============================================================

function sendJson(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(body);
}

function readBody(req, res, handler) {
  let raw = '';
  req.on('data', (c) => { raw += c; if (raw.length > 1e6) req.destroy(); });
  req.on('end', () => {
    let body = {};
    try { body = raw ? JSON.parse(raw) : {}; } catch { return sendJson(res, 400, { error: 'JSON inválido' }); }
    try { handler(req, res, body); }
    catch (e) { sendJson(res, 500, { error: e.message }); }
  });
}

const MIME = { '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript',
               '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon' };

function serveStatic(url, res) {
  const rel = url === '/' ? 'index.html' : url.replace(/^\/+/, '');
  const abs = path.join(WEB_DIR, rel);

  // anti path-traversal: tudo precisa ficar dentro de web/
  if (!abs.startsWith(WEB_DIR)) { res.writeHead(403); return res.end('forbidden'); }

  fs.readFile(abs, (err, data) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }); return res.end('404'); }
    res.writeHead(200, { 'Content-Type': (MIME[path.extname(abs)] || 'application/octet-stream') + '; charset=utf-8' });
    res.end(data);
  });
}


// ============================================================
// HELPERS DE DOMÍNIO
// ============================================================

function findCar(cfg, handlingName) {
  const target = norm(handlingName || '');
  return carmod.discoverAll(cfg).find((c) => c.handlingName === target) || null;
}

function validTier(t) {
  return tiers.ORDER.includes(t) ? t : null;
}

// tier um nível acima (anti-salto: tier_max default = base + 1), respeitando teto/min existente
function bumpTier(base, existingMax) {
  const i = tiers.tierIndex(base);
  const up = tiers.ORDER[Math.min(tiers.ORDER.length - 1, i + 1)];
  if (existingMax && tiers.tierIndex(existingMax) >= i) return existingMax;
  return up;
}

function readMaybe(absPath) {
  try { return JSON.parse(fs.readFileSync(absPath, 'utf8')); } catch { return null; }
}


module.exports = { start, carView, balanceFor };
