// profiler.js — fingerprint + score determinístico + tier calculado (read-only)
//
// Lê os valores ATUAIS do .meta e estima em que tier o carro naturalmente cai, comparando
// cada dimensão contra a banda da Matriz-Ouro (D = piso, S+ = teto). O resultado alimenta a
// decisão humana na UI: "o app calculou tier X" vs. "você deseja tier Y" -> média (tiers.js).
//
// Cruza RELAÇÕES (não soma campos isolados) conforme carskill.md §3.6:
//   accel(0.30) · launch(0.10) · grip(0.30) · brake(0.15) · estabilidade(0.15)
// fMass NÃO entra em accel (a=F/m cancela — §1.5); entra em power-to-weight (clamp) e
// na estabilidade (via suspensão/antiRoll). Tudo determinístico, sem IA.

const meta = require('./meta');
const { clamp, isNum } = require('./util');
const tiers = require('./tiers');


// ============================================================
// NORMALIZAÇÃO CONTRA A BANDA D..S+
// ============================================================

// normaliza um valor para 0..1 dentro de [lo, hi]; inverse=true para campos "menor é melhor"
function band(value, lo, hi, inverse) {
  if (!isNum(value)) return 0;
  const t = (value - lo) / (hi - lo);
  return clamp(inverse ? 1 - t : t, 0, 1);
}


// ============================================================
// ANÁLISE COMPLETA DE UM BLOCO
// ============================================================

// analisa um bloco <Item CHandlingData> e devolve fingerprint + score + tier calculado.
// `tiersMap` = cfg.tiers (precisa de D e S+ como âncoras de escala).
function analyze(block, tiersMap) {
  const D = tiersMap.D;
  const SP = tiersMap['S+'];

  // ---- leitura crua (fingerprint) ----
  const f = {
    mass:        meta.readValue(block, 'fMass'),
    driveForce:  meta.readValue(block, 'fInitialDriveForce'),
    driveBias:   meta.readValue(block, 'fDriveBiasFront'),
    gripMax:     meta.readValue(block, 'fTractionCurveMax'),
    gripMin:     meta.readValue(block, 'fTractionCurveMin'),
    brakeForce:  meta.readValue(block, 'fBrakeForce'),
    drag:        meta.readValue(block, 'fInitialDragCoeff'),
    maxVel:      meta.readValue(block, 'fInitialDriveMaxFlatVel'),
    driveInertia:meta.readValue(block, 'fDriveInertia'),
    antiRoll:    meta.readValue(block, 'fAntiRollBarForce'),
    suspForce:   meta.readValue(block, 'fSuspensionForce'),
    inertiaZ:    meta.readAttr(block, 'vecInertiaMultiplier', 'z'),
    gears:       meta.readValue(block, 'nInitialDriveGears'),
  };

  const drivetrain = classifyDrivetrain(f.driveBias);

  // ---- dimensões normalizadas (0..1) ----
  const accel = band(f.driveForce, D.drive, SP.drive);
  const grip  = band(f.gripMax,    D.gripMax, SP.gripMax);
  const brake = band(f.brakeForce, D.brakeForce, SP.brakeForce);

  // largada: torque sem grip patina ("canta pneu"); AWD agarra, RWD sofre (§1.5)
  const dtFactor = drivetrain === 'awd' ? 1.0 : drivetrain === 'rwd' ? 0.85 : 0.92;
  const launch = clamp((grip / Math.max(accel, 0.01)) * dtFactor, 0, 1);

  // estabilidade: antiRoll (banda) + suspensão (peso real entra aqui, não em accel)
  const stability = clamp(
    0.6 * band(f.antiRoll, D.antiRollBar, SP.antiRollBar) +
    0.4 * clamp((f.suspForce || 0) / 3.0, 0, 1), 0, 1);

  const parts = { accel, launch, grip, brake, stability };
  const score = Math.round(
    (accel * 0.30 + launch * 0.10 + grip * 0.30 + brake * 0.15 + stability * 0.15) * 1000);

  // ---- power-to-weight: clamp comparativo (impede absurdo) ----
  const pwr = isNum(f.driveForce) && isNum(f.mass) && f.mass > 0
    ? f.driveForce / (f.mass / 1000) : null;

  let calculatedTier = tiers.scoreToTier(score);
  const notes = [];

  // carro muito pesado com pouca força não merece tier alto mesmo com números altos
  if (pwr !== null && pwr < 0.12 && tiers.tierIndex(calculatedTier) >= tiers.tierIndex('A')) {
    const downIdx = Math.max(0, tiers.tierIndex(calculatedTier) - 1);
    notes.push(`power-to-weight baixo (${pwr.toFixed(3)}) — tier reduzido 1 nível (anti-absurdo)`);
    calculatedTier = tiers.ORDER[downIdx];
  }

  return {
    fingerprint: f,
    drivetrain,
    parts,                 // 0..1 por dimensão (para barras explicativas na UI)
    score,                 // 0..1000
    calculatedTier,
    powerToWeight: pwr,
    notes,
  };
}


// ============================================================
// HELPERS
// ============================================================

// drivetrain a partir de fDriveBiasFront (0=RWD, ~0.5=AWD, 1=FWD)
function classifyDrivetrain(driveBias) {
  if (!isNum(driveBias)) return 'awd';
  if (driveBias <= 0.2) return 'rwd';
  if (driveBias <= 0.8) return 'awd';
  return 'fwd';
}


module.exports = { analyze, classifyDrivetrain };
