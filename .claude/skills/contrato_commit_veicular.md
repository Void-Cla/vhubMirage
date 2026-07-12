# Skill — Contrato de commit de estado veicular (CORE v2)

> Padrão validado nas decisões #39/#38/#44 (2026-07-02/03). Owner de referência:
> `resources/[CORE]/vhub/server/exports.lua` (commitVehicleState) + `server/state.lua` (audit).

## Quando usar
Qualquer resource que precise ESCREVER estado físico de veículo no CORE (fuel, health,
damage, tuning, lifecycle). NUNCA `set*Data` fora do CORE (L-13), NUNCA mutar VD via
`getVHub()` (L-14). Ler = `getVehicleState` (devolve CÓPIA). Escrever = este contrato.

## A assinatura
```lua
-- de qualquer resource TRUSTED, dentro de Citizen.CreateThread:
local ok = exports.vhub:commitVehicleState(plate, { fuel = 42.5 }, 'pump')
```
O CORE valida em camadas: (1) invoker no `trusted_resources` (convar
`vhub_trusted_resources` no server.cfg — sem ele TUDO nega); (2) `source_tag` conhecido;
(3) cada campo do patch permitido para aquele source (SOURCE_GATES:
pump/fuel_can/fuel_admin→fuel pelo legacyfuel; fuel_migration/fuel_compat→fuel pelo conce;
repair→health/damage; tune→tuning; garage→lifecycle; system→tudo). Passou → VRAM +
State Bags + SQL batch + evento `vHub:vehicleCommitted(plate, source, patch)` + `vh_audit`.

## Regras de ouro
1. **Um source por identidade de negócio.** A bomba usa 'pump' e só pode mexer em fuel —
   um exploit no resource da bomba NÃO vira repair-hack. Gate de CAMPOS, não só de caller.
2. **Toda mutação audita sozinha** (R12): `vh_audit` recebe actor/action/target/source/
   before/after via batch — quem chama não escreve log manual.
3. **Reagir a mudanças = escutar `vHub:vehicleCommitted`**, nunca pollar getVehicleState.
4. **Shadow-flags durante migração de ownership**: enquanto uma flag estiver desligada,
   o CORE persiste sem aplicar aquela fronteira física. Fuel concluiu o corte na #61
   (`core_fuel_enabled=true`); health/body seguem com `veh_state_apply=false`.
5. **Dual-write de aquecimento (padrão de cutover)**: o dono ATUAL espelha o campo no
   CORE em thread própria, soft-dep (`pcall` + `GetResourceState`), APÓS persistir no
   seu lado — ver `vhub_conce/server/vstate.lua` (ADR #44). Espelhar SÓ o campo que o
   CORE não obtém por outro caminho; espelhar o que a telemetria validada já entrega
   seria 2º escritor.

## Anti-padrões (vistos e mortos nesta base)
- ❌ Broadcast `-1` para notificar mudança de estado (use a bag / o evento de commit).
- ❌ Persistir campo derivado (tier/score/hnd) — deriváveis são ON-READ (Doutrina da Placa).
- ❌ Chamar o export fora de thread (register interno usa Await → `assertThread` estoura).

## Checklist de runtime
Commit com source válido → bag atualiza + `vh_audit` ganha linha + evento dispara.
Commit com campo fora do gate do source → false + warn. Resource fora do trust → false.
Convar de trust ausente → warn de boot orienta o fix.
