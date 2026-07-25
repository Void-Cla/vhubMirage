# vhub_nitro — Nitro Server-Authoritative

**Versão:** 2.0.0 | **Owner:** vhub_nitro

Nitro seguindo a **Doutrina da Placa**: todo o estado (`kit`, `qty`, `enabled`, `level`) vive em `customization.nitro` no prontuário da placa (via `vhub_conce`). O `vhub_nitro` é o **único escritor** dessa subtabela. Ativação in-game no **Shift Direito**.

---

## O que faz

- Estado do nitro na placa: `{ kit, qty (0..100), enabled, level (1..10) }`
- Kit instalado na oficina (`vhub_custom` chama `installKit` após cobrar)
- Carga recarregada consumindo a garrafa (item `nitro` do inventário) via ficha do vehcontrol
- Liga/desliga e nível calibrados na ficha do `vhub_vehcontrol`
- Level = trade-off durabilidade↔velocidade; drain server-side do motorista
- HUD sincronizado por push após cada escrita (`vhub_nitro:state`)

---

## Dependências

```
vhub, vhub_inventory
```

Soft-deps (pcall): `vhub_conce` (prontuário/placa), `vhub_custom` (oficina instala o kit).

---

## Exports disponíveis (server-side)

Escritas restritas a TRUSTED interno: `vhub_custom`, `vhub_vehcontrol`, `vhub_nitro`.

```lua
-- estado do nitro da placa (read-only derivado; SEMPRE os 4 campos com defaults seguros)
-- { kit = bool, qty = 0..100, enabled = bool, level = 1..10 }
local n = exports.vhub_nitro:getNitro('ABC1234')

-- instala o kit (chamado pela OFICINA após cobrar; valida canOperate; idempotente)
local ok = exports.vhub_nitro:installKit(src, 'ABC1234')

-- liga/desliga o nitro (FICHA do vehcontrol; exige kit instalado)
local ok = exports.vhub_nitro:setEnabled(src, 'ABC1234', true)

-- ajusta o nível 1..10 (clamp server-side; exige kit)
local ok = exports.vhub_nitro:setLevel(src, 'ABC1234', 7)

-- recarrega consumindo 1 garrafa do inventário (ordem anti-perda: takeItem → persist → estorno se falhar)
local ok = exports.vhub_nitro:chargeFromItem(src, 'ABC1234')
```

Todas as escritas validam `canOperate(src, plate)` (dono ou chave válida via conce) + rate-limit por player (350ms anti-double-click).

---

## Regra de escrita (patch sempre completo)

O `mergeCust` do conce é **raso**: a subtabela `nitro` é REPLACE atômico. Por isso todo write interno envia o patch completo `{kit, qty, enabled, level}` — nunca parcial. Terceiros **nunca** escrevem `customization.nitro` direto (nem via `commitVehicleState`): chamam os exports daqui.

```lua
-- ERRADO (quebra o escritor único):
-- exports.vhub:commitVehicleState(plate, { customization = { nitro = {...} } }, ...)

-- CERTO:
exports.vhub_nitro:setEnabled(src, plate, true)
```

---

## Fluxo do jogador

```
1. OFICINA: compra o kit → vhub_custom cobra → installKit(src, plate)
2. INVENTÁRIO: compra garrafas de nitro (item 'nitro')
3. FICHA (vehcontrol): abastece (chargeFromItem), liga (setEnabled), calibra nível (setLevel)
4. PISTA: Shift Direito ativa o boost; drain server-side valida motorista (seat -1, fail-closed)
```

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| Doutrina da Placa | Estado na placa via conce; derivados nunca persistem |
| L-04 / L-13 | vhub_nitro = escritor único de `customization.nitro` |
| §3.7 | Escritas TRUSTED + `canOperate` provando o PLAYER, não só o resource |
| L-14 | Leitura por `getVehicleState`; nunca muta o retorno |
| §4.6 | Rate-limit por player nas escritas (anti-spam/anti-churn SQL) |
