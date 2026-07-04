# Skill — Validação física na réplica (net event de veículo sem confiar no client)

> Padrão validado nas decisões #37/#47 (2026-07-02/03, dev limpo). Owner de referência:
> `resources/[CORE]/vhub/server/boot.lua` (handlers vEnter/vLeave) + `client/vehicle.lua`.

## Quando usar
Qualquer net event onde o client ALEGA uma relação com uma entidade (entrei no carro X,
saí do assento Y, estou dirigindo a placa Z). Nunca aceite a alegação — verifique-a na
réplica server-side. Foi assim que o vetor do ADR #24 (forjar vEnter com netid da vítima)
morreu de vez.

## Verdades de plataforma (pagas com crash real em dev — não redescobrir)
- **`NetworkSetEntityOwner` NÃO EXISTE no build server.** Chamar = `attempt to call a nil
  value`. O OneSync migra a ownership da entidade para o motorista SOZINHO — não há (nem
  precisa haver) native server-side para forçar. A "autoridade" do framework é registro
  interno (`vd.driver`), não a engine.
- **Existem server-side** (e sustentam este padrão): `NetworkGetEntityFromNetworkId`,
  `DoesEntityExist`, `GetVehicleNumberPlateText`, `GetPedInVehicleSeat`, `GetPlayerPed`,
  `GetAllVehicles`, `DeleteEntity`, `GetEntityCoords/Heading`.
- **`GlobalState.x = v`** (server) replica para todos os clients — kill-switch barato.
- A réplica TEM LAG: o ped só aparece sentado no server ~100–300ms depois do client.
  Sem tolerância a isso, todo vEnter legítimo é rejeitado.

## O padrão (3 passos, ordem importa)
```lua
-- 1. A ALEGAÇÃO é verificável? (entidade existe + placa real == alegada)
local ent = NetworkGetEntityFromNetworkId(netid)
if not ent or ent == 0 or not DoesEntityExist(ent) then return end
local real    = normalizePlate((GetVehicleNumberPlateText(ent) or ''):gsub('%s+', ' '))
local alegada = normalizePlate(plate:gsub('%s+', ' '))
if not real or real ~= alegada then return end

-- 2. A alegação é FISICAMENTE verdadeira? (ped do src está no assento alegado)
if GetPedInVehicleSeat(ent, seat) ~= GetPlayerPed(src) then
  Logger:warn(...)  -- rejeição LOGA (forensia); aceitação é silenciosa
  return
end

-- 3. Só então o efeito. Ações subsequentes (vState) exigem o registro
--    criado aqui (vd.driver == src) — nunca re-validam do zero por evento.
```

## Lado client (espelho obrigatório do lag de réplica)
- **Estabilidade de 2 passadas** antes de anunciar vEnter (≈500ms no loop adaptativo):
  dá tempo da réplica refletir o ped no assento — sem isso o server rejeita o legítimo.
- **Reafirmação idempotente** (reenviar vEnter a cada 30s enquanto no assento): cura
  vEnter perdido por lag/packet loss. O handler server DEVE ser idempotente (R14 —
  `occupants[src]=seat` de novo é no-op).
- **Gate por `GlobalState.vh_core_active`**: se false, o client NÃO emite nada — desarmar
  o pipeline = 1 linha server-side, sem restart de client (fecha o desperdício do F-019).
- Placa: `GetVehicleNumberPlateText` vem com PADDING de espaços — normalizar (upper +
  colapsar espaços internos + trim) NOS DOIS LADOS com a MESMA regra, senão nunca casa.

## Regras de ouro
1. Rejeição silenciosa para o client (nunca avisar o atacante), com `warn` no log.
2. `vLeave` só de quem tem `occupants[src]` registrado por vEnter validado — sem estado
   prévio, sem efeito.
3. Superfícies que o client não pode provar fisicamente (spawn/despawn) NÃO ganham net
   event — entram por export gated do dono server-side.
4. Rate-limit continua por cima (o gate físico não substitui o `Kernel:net` rate).

## Checklist de runtime (antes de confiar)
Entrar como motorista → registro OK, vState aceito. Passageiro → passengerMode.
Forjar vEnter com netid de outro carro → warn + zero efeito. Trocar de assento → leave+enter.
`GlobalState.vh_core_active=false` → tráfego client morre em ≤2s.
