// config.js — carrega e VALIDA toda a config (falha cedo, falha claro)
//
// Toda a "inteligencia" mora aqui em config versionada, nao no codigo (script.md §3).
// Qualquer erro de config dispara ConfigError (exit 2) com mensagem PT-BR apontando o
// problema. A validacao roda no inicio de QUALQUER comando.

const path = require('path');
const io   = require('./io');
const { norm } = require('./util');


// erro de config — o entrypoint mapeia para exit code 2
class ConfigError extends Error {
  constructor(msg) { super(msg); this.name = 'ConfigError'; this.exitCode = 2; }
}

const CONFIG_DIR = path.join(io.TOOL_ROOT, 'config');

// campos numericos obrigatorios em cada tier de tiers.json
const TIER_REQUIRED = [
  'drive', 'drag', 'maxVel', 'driveInertia',
  'gripMax', 'gripMin', 'brakeForce', 'antiRollBar', 'budget',
];

// os 8 campos de performance que o pipeline pode tocar via override (NUCLEO-8)
const OVERRIDE_PERF = new Set([
  'fInitialDriveForce', 'fInitialDragCoeff', 'fInitialDriveMaxFlatVel', 'fBrakeForce',
  'fTractionCurveMax', 'fTractionCurveMin', 'fAntiRollBarForce', 'fDriveInertia',
]);

// campos de identidade aceitos no override (nao sao escritos no .meta)
const OVERRIDE_IDENTITY = new Set(['archetype', 'grip_modifier', 'base_alloc']);


// ============================================================
// CARGA + VALIDACAO
// ============================================================

// carrega tiers/registry/overrides/archetypes/scan-paths, valida e devolve a config pronta
function load() {
  const tiersRaw     = readConfig('tiers.json');
  const registryRaw  = readConfig('registry.json');
  const overridesRaw = readConfig('overrides.json');
  const archetypes   = readConfig('archetypes.json');
  const scanPaths    = readConfig('scan-paths.json');

  const tiers     = tiersRaw.tiers || {};
  const registry  = normalizeKeys(registryRaw.vehicles || {});
  const overrides = normalizeKeys(overridesRaw.vehicles || {});

  validateTiers(tiers);
  validateRegistry(registry, tiers);
  validateOverrides(overrides, registry, tiers);
  validateScanPaths(scanPaths);

  return {
    tiers,
    registry,
    overrides,
    archetypes: archetypes.archetypes || {},
    archetypeRule: archetypes._regra || {},
    scanPaths,
  };
}


// ============================================================
// VALIDADORES
// ============================================================

// todo tier referenciado precisa ter os campos obrigatorios, com valores numericos
function validateTiers(tiers) {
  if (Object.keys(tiers).length === 0) {
    throw new ConfigError('config/tiers.json: nenhum tier definido em "tiers".');
  }
  for (const [key, t] of Object.entries(tiers)) {
    for (const field of TIER_REQUIRED) {
      if (typeof t[field] !== 'number' || !Number.isFinite(t[field])) {
        throw new ConfigError(
          `config/tiers.json: tier "${key}" sem campo numerico obrigatorio "${field}".`);
      }
    }
    if (t.gripMin > t.gripMax) {
      throw new ConfigError(
        `config/tiers.json: tier "${key}" tem gripMin (${t.gripMin}) > gripMax (${t.gripMax}).`);
    }
  }
}

// todo tier do registry precisa existir em tiers.json; tier_max nao pode ser abaixo do base
function validateRegistry(registry, tiers) {
  const order = tierOrder(tiers);
  for (const [name, entry] of Object.entries(registry)) {
    const base = entry.tier_base;
    const max  = entry.tier_max || base;
    if (!tiers[base]) {
      throw new ConfigError(
        `config/registry.json: "${name}" usa tier_base "${base}" inexistente em tiers.json.`);
    }
    if (!tiers[max]) {
      throw new ConfigError(
        `config/registry.json: "${name}" usa tier_max "${max}" inexistente em tiers.json.`);
    }
    if (order.indexOf(max) < order.indexOf(base)) {
      throw new ConfigError(
        `config/registry.json: "${name}" tem tier_max "${max}" ABAIXO do tier_base "${base}".`);
    }
  }
}

// toda chave de override precisa existir no registry; nenhum campo desconhecido;
// se base_alloc presente, soma deve bater com o budget do tier_base (invariante da Fase 2)
function validateOverrides(overrides, registry, tiers) {
  for (const [name, ov] of Object.entries(overrides)) {
    if (!registry[name]) {
      throw new ConfigError(
        `config/overrides.json: "${name}" nao existe em registry.json (override orfao).`);
    }
    for (const field of Object.keys(ov)) {
      if (!OVERRIDE_PERF.has(field) && !OVERRIDE_IDENTITY.has(field)) {
        throw new ConfigError(
          `config/overrides.json: "${name}" tem campo desconhecido "${field}".`);
      }
    }
    if (ov.base_alloc !== undefined) {
      validateAlloc(name, ov.base_alloc, registry[name].tier_base, tiers);
    }
  }
}

// base_alloc deve ter as 5 chaves e somar EXATAMENTE o budget do tier (trava do contrato F1->F2)
function validateAlloc(name, alloc, tierBase, tiers) {
  const AXES = ['potencia', 'grip', 'frenagem', 'aero', 'suspensao'];
  let sum = 0;
  for (const axis of AXES) {
    if (typeof alloc[axis] !== 'number' || !Number.isFinite(alloc[axis])) {
      throw new ConfigError(
        `config/overrides.json: "${name}".base_alloc sem eixo numerico "${axis}".`);
    }
    sum += alloc[axis];
  }
  const budget = tiers[tierBase].budget;
  if (sum !== budget) {
    throw new ConfigError(
      `config/overrides.json: "${name}".base_alloc soma ${sum}, mas budget do tier ` +
      `"${tierBase}" e ${budget}. A soma DEVE ser igual ao budget (invariante da Fase 2).`);
  }
}

// scan-paths precisa de roots e matchFiles nao-vazios
function validateScanPaths(sp) {
  if (!Array.isArray(sp.roots) || sp.roots.length === 0) {
    throw new ConfigError('config/scan-paths.json: "roots" deve ser uma lista nao-vazia.');
  }
  if (!Array.isArray(sp.matchFiles) || sp.matchFiles.length === 0) {
    throw new ConfigError('config/scan-paths.json: "matchFiles" deve ser uma lista nao-vazia.');
  }
}


// ============================================================
// HELPERS
// ============================================================

// le um JSON de config/ com erro de config (nao de I/O) se faltar/quebrar
function readConfig(name) {
  const abs = path.join(CONFIG_DIR, name);
  if (!io.exists(abs)) {
    throw new ConfigError(`config/${name} nao encontrado.`);
  }
  try {
    return io.readJson(abs);
  } catch (e) {
    throw new ConfigError(`config/${name}: ${e.message}`);
  }
}

// re-chaveia um mapa por handlingName normalizado (tolera erro de caixa no JSON)
function normalizeKeys(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (k.startsWith('_')) continue; // ignora campos de documentacao
    out[norm(k)] = v;
  }
  return out;
}

// ordem D..S+ a partir das chaves de tiers.json (assume insercao na ordem do arquivo)
function tierOrder(tiers) {
  return Object.keys(tiers);
}


module.exports = { load, ConfigError, tierOrder };
