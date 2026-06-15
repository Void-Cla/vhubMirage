# Drift

Mecânica de drift para FiveM: ajusta o **handling** em tempo real (handbrake +
acelerador) e dá um **boost** controlado (anti-exploit). Além da mecânica, ele
**fabrica a pontuação bruta** de drift (ângulo × velocidade × combo) e a expõe
via export. **Não desenha UI** — o HUD e o "banco" da pontuação são do `vhub_racha`.

## Como pontua

Enquanto driftar (ângulo ≥ 15°, ≥ 30 km/h, sem bater):

```
pontos/seg = min(ângulo × velocidade / 40, 150) × combo
combo = 1.0 → 1.5 (5s) → 2.0 (12s) → 3.0 (25s) de drift contínuo
```

- **Bater** (queda de body health) reseta o combo e conta como "crash".
- Soltar o drift por > 700 ms zera o combo (oscilação normal não derruba).

> O `SCORE_CAP_PER_SEC`, o divisor e o combo devem ficar **alinhados** com o
> `vhub_racha` (`shared/config.lua → DRIFT`), pois o **servidor é a autoridade**
> e faz o cap final por segundo.

## Export (consumido pelo vhub_racha)

```lua
local t = exports.Drift:getTelemetry()
-- t.total    → pontuação bruta acumulada (monotônica, nunca zera) → usada p/ banco
-- t.crashes  → contador de batidas (monotônico) → racha descarta o lote ao mudar
-- t.combo    → multiplicador atual
-- t.angle    → ângulo de drift (graus)
-- t.speed    → velocidade (km/h)
-- t.drifting → está pontuando neste frame?
-- t.active   → handling de drift engajado?
```

## Divisão de responsabilidade

| Camada | Faz |
|--------|-----|
| **Drift** (este resource) | mecânica (handling + boost) + **fabrica** a pontuação bruta + telemetria |
| **vhub_racha** (modo drift) | **banca** a pontuação: a cada 5 s sem bater o lote vira válido; bater perde o lote pendente. Envia o bancado ao servidor (autoridade) e mostra no HUD |

## Controles

- **Acelerador + Freio de mão** com velocidade: entra em drift (handling assistido).
- Mantendo ângulo ≥ 20°: ativa **boost** (1.2 s, cooldown 4 s).

## Créditos

Base original: *MoravianLion* / *VoidMods*. Adaptado para o vHub Mirage
(remoção da UI, fabricação de pontuação e export `getTelemetry`).
