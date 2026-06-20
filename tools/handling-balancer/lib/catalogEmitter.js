// catalogEmitter.js — gera out/catalog-patch.json (a ponte Fase 1 -> Fase 2)
//
// O patch e um ARTEFATO INERTE: proposta de extensao do catalogo do conce, mesclada
// MANUALMENTE pelo dev na Fase 2 (carskill.md §4.1). A Fase 1 NUNCA edita catalog.lua.
//
// Convencoes de chave (travadas pelo guardiao de contrato):
//   - key do patch        = handlingName em LOWERCASE (casa 1:1 com a key do catalogo,
//                           que e o modelName minusculo; runtime usa catalog[norm(model)]
//                           com norm == string.lower).
//   - handling_name (dentro) = handlingName REAL do .meta (a80 / SKYLINE / 370Z) — ancora
//                           ao arquivo fisico.
//
// Nomes do bloco `p1` espelham carskill.md §4.1 EXATAMENTE (snake_case curto):
//   handling_name, tier_base, tier_max, archetype, grip_modifier,
//   base_alloc{potencia,grip,frenagem,aero,suspensao}, drive_bias, susp_raise, mass,
//   inertia_z, low_speed_loss, seal.

const path = require('path');
const io   = require('./io');
const meta = require('./meta');
const { r0 } = require('./util');

const PATCH_PATH = path.join(io.TOOL_ROOT, 'out', 'catalog-patch.json');

const AXES = ['potencia', 'grip', 'frenagem', 'aero', 'suspensao'];


// ============================================================
// ORCAMENTO BASE (invariante soma == budget)
// ============================================================

// distribui o budget igualmente entre os 5 eixos; sobra inteira vai para 'potencia'.
// garante, por construcao, soma(base_alloc) == budget (trava do contrato F1->F2).
function balancedAlloc(budget) {
  const each = Math.floor(budget / AXES.length);
  const alloc = {};
  let used = 0;
  for (const axis of AXES) { alloc[axis] = each; used += each; }
  alloc.potencia += (budget - used); // remainder -> potencia (mantem soma exata)
  return alloc;
}


// ============================================================
// ARQUETIPO (derivado por regra, sem IA)
// ============================================================

// classifica o arquetipo por fDriveBiasFront (drivetrain) + fMass (leve/pesado).
function deriveArchetype(driveBias, mass, rule) {
  const r = rule || {};
  const db = (r.driveBias || {});
  const heavy = mass >= (r.massThreshold ?? 1500);

  let drive;
  if (driveBias <= (db.rwd_max ?? 0.2))      drive = 'rwd';
  else if (driveBias <= (db.awd_max ?? 0.8)) drive = 'awd';
  else                                       drive = 'fwd';

  return `${drive}_${heavy ? 'heavy' : 'light'}`;
}


// ============================================================
// EMISSAO DO BLOCO p1 DE UM CARRO
// ============================================================

// monta o bloco p1 de um carro a partir do .meta preservado + config + selo.
// `block` = bloco <Item CHandlingData> ja localizado; `seal` = hash do apply (copia).
function buildEntry(handlingNameRaw, block, cfg, seal) {
  const name = handlingNameRaw.trim().toUpperCase();
  const reg  = cfg.registry[name];
  const ov   = cfg.overrides[name] || {};

  // campos PRESERVADOS lidos direto do .meta (identidade / afinidade — carskill §1.5)
  const driveBias    = meta.readValue(block, 'fDriveBiasFront');
  const suspRaise    = meta.readValue(block, 'fSuspensionRaise');
  const mass         = meta.readValue(block, 'fMass');
  const inertiaZ     = meta.readAttr(block, 'vecInertiaMultiplier', 'z');
  const lowSpeedLoss = meta.readValue(block, 'fLowSpeedTractionLossMult');

  const archetype = ov.archetype || deriveArchetype(driveBias, mass, cfg.archetypeRule);
  const archMod   = (cfg.archetypes[archetype] || {}).grip_modifier ?? 1.0;
  const budget    = cfg.tiers[reg.tier_base].budget;

  return {
    handling_name: handlingNameRaw.trim(),     // real (NAO uppercased) — ancora ao .meta
    tier_base:     reg.tier_base,
    tier_max:      reg.tier_max || reg.tier_base,
    archetype,
    grip_modifier: round2(ov.grip_modifier ?? archMod),
    base_alloc:    ov.base_alloc || balancedAlloc(budget),
    drive_bias:    round3(driveBias),
    susp_raise:    round3(suspRaise),
    mass:          round1(mass),
    inertia_z:     round3(inertiaZ),
    low_speed_loss: round3(lowSpeedLoss),
    seal,                                       // copia de auditoria do hash do apply
  };
}


// ============================================================
// ESCRITA DO PATCH
// ============================================================

// grava out/catalog-patch.json (chaves ordenadas para diff estavel).
function writePatch(entriesByKey) {
  const out = {
    _doc: 'Proposta de extensao do catalogo do conce (bloco p1 por veiculo). ARTEFATO ' +
          'INERTE: mesclar MANUALMENTE em vhub_conce/shared/catalog.lua na Fase 2 (gate ' +
          'do conce). key = modelName minusculo (casa com a entrada existente). NAO ' +
          'commitado (gerado por `apply`; veja `plan` para preview).',
  };
  for (const key of Object.keys(entriesByKey).sort()) out[key] = entriesByKey[key];
  io.writeJson(PATCH_PATH, out);
  return PATCH_PATH;
}


// ============================================================
// HELPERS
// ============================================================

const round1 = (n) => Number.isFinite(n) ? Math.round(n * 10) / 10 : null;
const round2 = (n) => Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
const round3 = (n) => Number.isFinite(n) ? Math.round(n * 1000) / 1000 : null;


module.exports = { buildEntry, writePatch, balancedAlloc, deriveArchetype, PATCH_PATH, AXES };
