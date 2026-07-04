# SUPERSEDED — 2026-07-03

> Este documento (rascunho externo, "Autor: Manus AI", 2026-06-28) foi **arquivado** por
> desalinhamento com a arquitetura real do vHub Mirage. Não usar como fonte operacional.
> Mantido apenas como **pedigree histórico** da ideia de balanceamento físico por arquétipo.

## Por que foi arquivado (drift confirmado contra o código)

- **SQL errado:** usava `MySQL.Async.fetchAll`/`MySQL.Async.execute` — o projeto usa
  **oxmysql** (`exports.oxmysql:...`). `MySQL.Async` não existe em nenhum resource.
- **Tabela inexistente:** assumia `player_vehicles` com colunas físicas
  `fMass/fDriveBiasFront/fTractionMax`. A verdade veicular vive em `vhub_vehicle_state`
  (prontuário/placa no `vhub_conce`), e **handling derivado nunca persiste** — doutrina da
  placa (decisões #24/#32; ver memória `vhub_nitro`).
- **Ownership errado (viola L-04/R4):** propunha `handling_rules.lua`/`validator_service.lua`/
  `boot_service.lua` dentro de `vhub_conce`, criando um 2º dono de handling. A regra de
  handling é do **`vhub_vehcontrol`**, que já tem o clamp em
  `shared/tier_rules.lua::TR.handlingFromAlloc`.
- **Anti-padrões de runtime:** `AddEventHandler('onResourceStart') → SELECT` full-table no boot
  viola P4 (lazy-load — prontuário não pré-carrega) e a eviction VRAM+TTL já aplicada;
  `print("^3[INTEGRIDADE]...")` viola R10/L-08 (usar `vHub.Logger`).

## Onde a intenção legítima continua viva

A ideia válida — **clamp de integridade física por arquétipo/categoria** (skill-gap por massa
e tração) — está preservada, melhor articulada, em:

- `frozen_core_2.md` §F-053 (Risco #1 — `SetVehicleHandlingFloat` model-wide).
- `frozen_core_2.md` §F-068 (balancer override com clamp em um só campo).
- `frozen_core_2.md` Apêndice B, **ADR #51 proposta** (resolução do Risco #1 — per-entity
  handling ou skill sandbox). *Numeração final: confirmar em `WORKLOG_CORE_V2.md`.*

**Ownership do clamp (para quando a ADR for aplicada):** escritor único = `vhub_vehcontrol`
(`shared/tier_rules.lua`); aplicação per-entity junto ao `SetVehicleHandlingFloat` em
`vhub_vehcontrol/client/handling.lua`. O `vhub_conce` **não** ganha módulo de handling —
permanece dono da placa/prontuário. Continuar por ali.
