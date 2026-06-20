// util.js — helpers puros compartilhados (sem I/O, sem side-effects)

// normaliza handlingName: trim + UPPERCASE (chave de registry/overrides/seal)
const norm = (s) => String(s).trim().toUpperCase();

// formata numero como o .meta espera: 6 casas decimais (padrao da engine GTA5)
const f6 = (n) => Number(n).toFixed(6);

// limita n ao intervalo [lo, hi]
const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));

// true se n e um numero finito (rejeita NaN/Infinity)
const isNum = (n) => typeof n === 'number' && Number.isFinite(n);

// arredonda para inteiro (usado em base_alloc / pontos de orcamento)
const r0 = (n) => Math.round(n);

module.exports = { norm, f6, clamp, isNum, r0 };
