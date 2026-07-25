# vhub_custom — Oficina, Bennys e Mec

**Versão:** 1.0.0 | **Owner:** vhub_custom

Três domínios de personalização veicular em um resource: Bennys (estética), Oficina (tuning de performance) e Mec (reparo/reboque). Estado persistido via `commitVehicleState` no CORE; regra de tier delegada ao `vhub_vehcontrol`.

---

## O que faz

**Bennys (estético):**
- Cor primária/secundária, pérola, cromado, vidros, rodas
- Extras, livery, placa personalizada
- Câmera orbital livre durante a customização (L2 HAL)

**Oficina (tuning de performance):**
- Stages de motor, freios, câmbio, suspensão, blindagem, turbo
- Cap de stage por classe GTA (estático, sem carskill)
- Tier/score derivado do `vhub_vehcontrol` — nunca recalcula por conta própria
- Instalação de kit de nitro (delega a `vhub_nitro:installKit`)

**Mec (manutenção):**
- Reparo de lataria e motor (débita em dinheiro)
- Reboque veicular (delega ao owner canônico do domínio correspondente)

---

## Dependências

```
vhub_conce, vhub_money
```

Soft-deps (via pcall): `vhub_vehcontrol` (sheet/tier), `vhub_nitro` (kit)

---

## Exports disponíveis (server-side)

O `vhub_custom` não expõe exports públicos — é consumidor, não provedor. Toda escrita de estado veicular passa por `exports.vhub:commitVehicleState` (CORE).

---

## Como funciona a persistência de tuning

O `vhub_custom` segue a **Doutrina da Placa** (decisão #22): o estado mora na placa.

```
1. Bennys: player seleciona cor → servidor valida → commitVehicleState({ customization: { colors: ... } })
2. Oficina: player compra stage → servidor cobra → commitVehicleState({ customization: { mods: { [11]: 4 } } })
3. Mec: reparo → servidor cobra → commitVehicleState({ body_health: 1000, engine_health: 1000 })
```

O `commitVehicleState` valida, clampa, marca dirty, sincroniza bags e loga razão:

```lua
-- de dentro do vhub_custom (não use de outro resource)
exports.vhub:commitVehicleState('ABC1234', {
  customization = { mods = { [11] = 4 } }
}, 'vhub_custom:oficina:motor_stage4')
```

---

## Integração entre domínios

**Oficina → vhub_vehcontrol (sheet):**

```lua
-- a oficina consulta o tier do carro antes de cobrar stage incompatível
local sheet = exports.vhub_vehcontrol:getVehicleSheet(plate)
-- sheet.tier: 'D', 'C', 'B', 'A', 'S', 'S+'
-- sheet.score: 0..1000
```

**Oficina → vhub_nitro (kit):**

```lua
-- após cobrar, a oficina instala o kit delegando para o escritor único
exports.vhub_nitro:installKit(src, plate)
```

---

## Zonas (configuração)

Zonas de cada estabelecimento vivem em `shared/config.lua`. Coordenadas como `vec3` (uso local), flat `{x,y,z}` em eventos (L-19):

```lua
VHubCustom.cfg.zones.bennys = {
  coord = vec3(-349.5, -134.0, 39.0),
  raio  = 12.0,
  label = 'Bennys Original Motorsports',
}
```

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-13 | Estado físico via `commitVehicleState` (CORE); nunca `setVData` direto |
| Doutrina da Placa | Tuning persiste na placa; derivados (tier/score) nunca persistem |
| L-04 | vhub_vehcontrol = fonte única de tier; vhub_custom não recalcula |
| §3.2 | Fluxo completo: validar → cobrar → commit → resposta ao cliente |
| A-09 | CEF transparente; sem `backdrop-filter` no overlay sobre o jogo |
