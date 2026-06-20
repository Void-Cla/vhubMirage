// tiers.js — calcula os valores-alvo do NUCLEO-8 por carro (regras PURAS, sem I/O)
//
// Precedencia: tier (base) -> override (patch) -> clamp de sanidade. O resultado e o
// conjunto dos 8 campos de performance que o pipeline reescreve no .meta.
//
// NUCLEO-8 (carskill.md §3.4 balde B — autoridade do dono 2026-06-15):
//   fInitialDriveForce, fInitialDragCoeff, fInitialDriveMaxFlatVel, fBrakeForce,
//   fTractionCurveMax, fTractionCurveMin, fAntiRollBarForce, fDriveInertia.
// Tudo o mais (lataria, dano, visual, suspensao, COM, inercia, gears) e PRESERVADO.
// O §5.3 do script.md v2.0 (injecao de anti-capotamento / 11 campos) esta SUPERADO.

const { clamp } = require('./util');


// ============================================================
// DECISAO FISICA: drive force NAO escala por massa
// ============================================================
//
// carskill.md §1.5: aceleracao ~= 10 x fInitialDriveForce; o torque na roda inclui fMass,
// mas a = F/m faz a massa CANCELAR. Dois carros com o mesmo fInitialDriveForce aceleram
// igual em reta, pesando 1000 ou 2000 kg. Escalar driveForce por massa super-recompensa
// carros pesados — foi o bug da v2 do balancer. Por isso o alvo de drive force e o valor
// do TIER direto (ajustavel por override), apenas clampado a banda do tier.


// ============================================================
// RESOLUCAO DE ALVOS
// ============================================================

// devolve { targets, tier, clampInfo } para um carro.
// `targets` mapeia campo do .meta -> valor numerico alvo (so o NUCLEO-8).
// tierKey opcional força um tier específico (UI escolhendo a média); senão usa o registry.
function resolveTargets(handlingName, cfg, tierKey) {
  const reg     = cfg.registry[handlingName] || {};
  const tierName = tierKey || reg.tier_base;
  const tier    = cfg.tiers[tierName];
  const ov      = cfg.overrides[handlingName] || {};

  // drive force: tier direto -> override -> clamp a +/-15% da referencia do tier
  const driveRaw = ov.fInitialDriveForce ?? tier.drive;
  const drive    = clamp(driveRaw, tier.drive * 0.85, tier.drive * 1.15);

  const targets = {
    fInitialDriveForce:      drive,
    fInitialDragCoeff:       ov.fInitialDragCoeff       ?? tier.drag,
    fInitialDriveMaxFlatVel: ov.fInitialDriveMaxFlatVel ?? tier.maxVel,
    fDriveInertia:           ov.fDriveInertia           ?? tier.driveInertia,
    fBrakeForce:             ov.fBrakeForce             ?? tier.brakeForce,
    fTractionCurveMax:       ov.fTractionCurveMax       ?? tier.gripMax,
    fTractionCurveMin:       ov.fTractionCurveMin       ?? tier.gripMin,
    fAntiRollBarForce:       ov.fAntiRollBarForce       ?? tier.antiRollBar,
  };

  // gripMin nunca pode superar gripMax (sanidade fisica)
  if (targets.fTractionCurveMin > targets.fTractionCurveMax) {
    targets.fTractionCurveMin = targets.fTractionCurveMax;
  }

  const clampInfo = (driveRaw !== drive)
    ? { field: 'fInitialDriveForce', raw: driveRaw, clamped: drive }
    : null;

  return { targets, tier: tierName, clampInfo };
}

// lista canonica dos campos do NUCLEO-8 (ordem estavel para diff/report)
const FIELDS = [
  'fInitialDriveForce', 'fInitialDragCoeff', 'fInitialDriveMaxFlatVel', 'fDriveInertia',
  'fBrakeForce', 'fTractionCurveMax', 'fTractionCurveMin', 'fAntiRollBarForce',
];


// ============================================================
// ORDEM DE TIERS + RECONCILIACAO (calculado x desejado x media)
// ============================================================

// ordem canonica dos tiers do mais fraco ao mais forte (D -> S+)
const ORDER = ['D', 'C', 'B', 'A', 'S', 'S+'];

// faixas de score (0-1000) por tier (carskill.md §3.6/§5.3)
const SCORE_BANDS = [
  { tier: 'D',  min: 0,   max: 199 },
  { tier: 'C',  min: 200, max: 399 },
  { tier: 'B',  min: 400, max: 599 },
  { tier: 'A',  min: 600, max: 749 },
  { tier: 'S',  min: 750, max: 899 },
  { tier: 'S+', min: 900, max: 1000 },
];

// indice 0..5 de um tier (-1 se desconhecido)
function tierIndex(tier) {
  return ORDER.indexOf(tier);
}

// mapeia um score 0-1000 para o tier correspondente
function scoreToTier(score) {
  for (const band of SCORE_BANDS) {
    if (score >= band.min && score <= band.max) return band.tier;
  }
  return score < 0 ? 'D' : 'S+';
}

// reconcilia tier calculado x desejado conforme o modo escolhido pelo humano.
// modo: 'calculado' | 'media' | 'desejado'. Default seguro = 'media'.
// devolve { final, calcIndex, desiredIndex, finalIndex, mode } — a media NUNCA
// teleporta um carro fraco para o topo: fica no meio do caminho (mantem balanceamento).
function reconcileTier(calculated, desired, mode) {
  const ci = tierIndex(calculated);
  const di = tierIndex(desired);
  const m = mode || 'media';

  let fi;
  if (m === 'calculado' || di < 0) fi = ci;
  else if (m === 'desejado')       fi = di;
  else                             fi = Math.round((ci + di) / 2); // media

  fi = Math.max(0, Math.min(ORDER.length - 1, fi));
  return { final: ORDER[fi], calcIndex: ci, desiredIndex: di, finalIndex: fi, mode: m };
}


module.exports = {
  resolveTargets, FIELDS,
  ORDER, SCORE_BANDS, tierIndex, scoreToTier, reconcileTier,
};
