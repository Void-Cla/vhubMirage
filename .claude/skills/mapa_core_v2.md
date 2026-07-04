# Skill — Mapa mestre do CORE v2 (leia ISTO antes de tocar em veículo/CORE)

> Estado consolidado do descongelamento (decisões #37–#50, 2026-07-02/03). Fonte
> detalhada: `.claude/plano_core_v2/WORKLOG_CORE_V2.md` (mapa, métricas, checklists).
> Esta skill é o atalho de orientação para uma sessão nova dominar a estrutura em 2 min.

## Onde a verdade vive (hoje — transição FASE 1→2)
| Dado | Dono ATUAL | Rumo (FASE 2) |
|------|-----------|----------------|
| Identidade do veículo (placa↔chave↔dono) | `vhub_conce` (`vhub_vehicles`/`_keys` + espelho `vh_vehicles`) | permanece |
| Físico PERSISTIDO (fuel/health/custom) | prontuário `vhub_vehicle_state` (conce, Doutrina da Placa) | CORE vira fonte; conce vira cache/validação |
| Físico em RUNTIME (VRAM + bags) | CORE `Veh._veh` — reanimado, validado em dev | permanece |
| Aplicação física no carro (natives) | `vhub_vehcontrol` (requestState) | CORE `vehicleStateLoad` (flag `vhub_veh_state_apply`) |
| Fuel | `vhub_legacyfuel` + prontuário; CORE em SHADOW (espelho #44 aquece) | CORE (`vhub_core_fuel 1` + bag `vh_fuel`) |
| Spawn/despawn de veículo | garage/conce server-side; CORE via exports `registerVehicleSpawn/Despawn` | permanece |

## Interruptores (convars no `config/server.cfg`)
- `vhub_trusted_resources` (CSV) — allowlist dos exports sensíveis do CORE. **Vazio = CORE
  nega tudo** (warn de boot orienta). Hoje: conce, garage, custom, vehcontrol, nitro,
  racha, admin, ferinha, legacyfuel.
- `vhub_core_fuel` (0) e `vhub_veh_state_apply` (0) — cutover da FASE 2. NÃO ligar sem
  desligar o dono atual do campo (escritor duplo, L-04).
- `GlobalState.vh_core_active` (setado em `server/boot.lua`) — kill-switch do pipeline
  veicular: false = client para de emitir vEnter/vLeave/vState sem restart.

## Superfícies novas do CORE (v2.0.0-alpha.1)
- Exports: `commitVehicleState` (gated, SOURCE_GATES), `getVehicleState` (CÓPIA),
  `getVehicle` (CÓPIA desde #50), `getVehicleDriver`, `getVehicleOccupants`,
  `registerVehicleSpawn/Despawn` (gated). `getVHub()` segue vivo por contrato (#36) —
  L-14 vale para quem o usa.
- `vHub.audit(...)` → tabela `vh_audit` append-only (toda mutação privilegiada).
- Eventos novos em `shared/events.lua`: `EVT_VEH_COMMITTED`, `CLI_VEH_STATE_LOAD`,
  `CLI_PASSENGER_MODE`.
- Despawn de veículo por placa: `exports.vhub_garage:despawnVehicleByPlate` (gated) —
  server-side `GetAllVehicles`+`DeleteEntity`; broadcasts `-1` de despawn NÃO existem mais.

## Guard-rails que protegem você
- Hooks v2 em `.claude/hooks/` (PreToolUse SQL/git destrutivo; PostToolUse leis L-13/14/
  15/16/17) — são os que o `settings.json` executa desde #45.
- Rollback global da sprint: tag git `pre-frozen-core-2-remediation`.
- Registro EFÊMERO: placa sem âncora não persiste (ver skill `batch_sql_resiliencia`).
- Batch com cap de 5 retries — op envenenada não derruba mais o flush.

## O que NÃO fazer (aprendido com sangue)
- ❌ Chamar `NetworkSetEntityOwner` no server (não existe — crash).
- ❌ Escrever `vh_fuel`/drain no CORE com legacyfuel ativo (HUD diverge).
- ❌ Flipar `if not caller then return true` em outros resources sem verificar chamadas
  internas (idioma padrão FiveM; só o garage foi flipado, com prova).
- ❌ Mexer em `fTractionCurveMax/Min` no Drift OU vehcontrol sem teste em jogo — os dois
  mutam os MESMOS campos (F-059, conflito real confirmado, decisão pendente de runtime).
- ❌ Criar âncora `vh_vehicles` fora do conce "para passar FK".

## Pendências que valem a próxima sessão
1. Checklist PARTE V do `frozen_core_2.md` em dev (pentest spoof vEnter = inegociável).
2. FASE 2 cutover (conce→CORE; ligar as 2 flags; unificar fuel — F-050/F-066).
3. F-059 (Drift×vehcontrol) com 2 players em jogo; F-053 (handling model-wide).
4. Auditoria caso-a-caso do idioma `caller nil` (conce/money/ferinha/inventory/ipad/groups).
5. b64→JSON (F-021) e WAL (F-010) — exigem banco real + backup.
