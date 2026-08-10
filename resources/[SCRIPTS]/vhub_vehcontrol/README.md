# vhub_vehcontrol — Controle de Veículo + Engine de Skill

**Versão:** 1.6.0 | **Owner:** vhub_vehcontrol

Painel de controle do veículo (portas, motor, trava, luzes, banco, câmera, cinto, rádio, DVD) + **engine de skill** (decisão #27): fonte única de tier/score/afinidade derivados da placa. Consome o prontuário do `vhub_conce`; aplica física derivada no carro dirigido (decisão #28).

---

## O que faz

- **Painel**: portas, motor, trava (dono via garage OU chave física via item `veh_key`), luzes, bancos
- **Ficha do veículo**: tier ('D'..'S+'), score (0..1000), afinidade por pista, calibração de alloc
- **Física derivada (F5)**: `client/handling.lua` aplica `SetVehicleHandlingFloat` no carro dirigido a partir da sheet — derivado **nunca persiste** (só o alloc em `customization.handling`)
- **Rádio**: aba Som/URL via `vhub_wow` (soft-dep), com modo streamer persistente
- **DVD**: telinha de vídeo no carro (iframe YT mute, decisão #53)
- **Nitro**: ponte da ficha para `vhub_nitro` (liga/nível/abastece — delega, decisão #30)
- **Telemetria**: stateSync do prontuário via conce (fuel/engine/body/odo)
- **Trava/motor**: State Bags server-owned; somente o owner de rede aplica as natives

---

## Dependências

```
vhub, vhub_inventory
```

Soft-deps (pcall): `vhub_wow` (rádio), `vhub_garage` (caminho "dono"), `vhub_conce` (prontuário), `vhub_nitro` (nitro).

---

## Exports disponíveis (server-side)

Fonte ÚNICA de tier/score/afinidade — **ninguém recalcula por conta própria** (L-04).

```lua
-- ficha completa derivada (flat, primitivos L-19) — nil se o modelo não tem p1
-- { tier, score, affinity = {reta,curva,montanha,drift,cidade}, alloc, hnd, nitro, ... }
local sheet = exports.vhub_vehcontrol:getVehicleSheet('ABC1234')

-- tier atual ('D','C','B','A','S','S+') ou nil
local tier = exports.vhub_vehcontrol:getVehicleTier('ABC1234')

-- score 0..1000 ou nil
local score = exports.vhub_vehcontrol:getVehicleScore('ABC1234')

-- afinidade por tipo de pista ou nil
local aff = exports.vhub_vehcontrol:getVehicleAffinity('ABC1234')

-- ficha HIPOTÉTICA com alloc proposto (nunca persiste) — prévia para UI de calibração
local preview = exports.vhub_vehcontrol:getVehicleSheetPreview('ABC1234', draftAlloc)
```

Mutações de oficina são exact-gated para `vhub_custom` e usam reserva por placa:

```lua
local reservation = exports.vhub_vehcontrol:reserveWorkshopRecalibration(src, plate, alloc)
local result = exports.vhub_vehcontrol:commitWorkshopRecalibration(src, reservation.token)
exports.vhub_vehcontrol:cancelWorkshopRecalibration(src, reservation.token)
```

---

## Como a derivação funciona (decisão #27)

```
catálogo do conce (.p1 = identidade física do modelo)
  + customization.mods (stages da oficina)
  + customization.turbo
  + customization.handling (alloc persistido — ÚNICO dado que persiste)
  → TR.buildSheet() → { tier, score, affinity, hnd } (derivação on-read PURA)
```

- **Persiste**: só o `alloc` (via RECALIBRATE — toolbox ou oficina)
- **Nunca persiste**: tier, score, hnd (física) — derivados on-read
- A oficina (`vhub_custom`) consulta a sheet; **não** recalcula score

---

## Consumidores conhecidos

| Consumidor | O que usa |
|------------|-----------|
| `vhub_custom` (oficina) | `getVehicleSheet` para exibir tier/score na calibração |
| `vhub_racha` | classe/tier do veículo para gate de corrida |
| `vhub_nitro` | sheet.nitro (agregado read-only na ficha) |
| UI da chave | `REQ_SHEET` (evento NUI read-only) |

---

## Itens integrados (vhub_inventory)

| Item | Efeito |
|------|--------|
| `veh_key` | Chave física — abre/liga o veículo da placa vinculada (meta.plate) |
| `caixadeferramentas` | Toolbox — abre a calibração de alloc fora da oficina |

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-04 | Fonte única de tier/score; consumidores nunca recalculam |
| Doutrina da Placa | Só o alloc persiste (`customization.handling`); física derivada é efêmera |
| L-19 | Sheet exportada flat (primitivos); vec3 nunca cruza o export |
| §2.5 | Soft-deps via pcall — sem wow/garage/nitro o painel continua funcional |
| L-02 | `handling.lua` aplica física localmente no carro dirigido; server valida o alloc |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `getVehicleSheet` | `(plate) → {tier, score, affinity, alloc, hnd, nitro, …}` | vhub_custom, vhub_racha |
| 2 | `getVehicleTier` | `(plate) → 'D'\|'C'\|'B'\|'A'\|'S'\|'S+'\|nil` | vhub_racha (gate de corrida) |
| 3 | `getVehicleScore` | `(plate) → 0..1000\|nil` | vhub_racha, vhub_custom |
| 4 | `getVehicleAffinity` | `(plate) → {reta, curva, montanha, drift, cidade}` | vhub_racha |
| 5 | `getVehicleSheetPreview` | `(plate, draftAlloc) → sheet_hipotetica` | vhub_custom (prévia UI) |
| 6 | `reserveWorkshopRecalibration` | `(src, plate, alloc) → reserva` | vhub_custom |
| 7 | `commitWorkshopRecalibration` | `(src, token) → resultado` | vhub_custom |
| 8 | `cancelWorkshopRecalibration` | `(src, token) → bool` | vhub_custom |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getCharacterId` |
| `vhub_inventory` | `hasVehicleKey`, `hasItem`, `takeItem`, `giveItem`, `registerItemUse` |
| `vhub_wow` | `PlayAtEntity`, `Destroy`, `SetVolume`, `RequestSearch`, `GetRadioTrack`, streamer mode |
| `vhub_garage` | `getVehicle` (fallback de ownership) |
| `vhub_conce` | `canOperate`, `getCatalog`, `getVehicle`, `getVehicleState`, `saveVehicleState` |
| `vhub_nitro` | `getNitro`, `setEnabled`, `setLevel`, `chargeFromItem` — soft-dep |
