# vhub_lspdtool — Ferramentas LSPD

**Versão:** 2.0.0 | **Owner:** vhub_lspdtool

Kit policial completo: radar automático de velocidade, leitura de placa (radar + helicam), BOLO (alerta de placa), MDT, procurados, prisão/detenção, apreensão de veículo e o app "Central LSPD" no iPad.

---

## O que faz

- **Radar**: mede velocidade de veículos próximos e lê placas automaticamente
- **Helicam**: câmera de helicóptero com leitura de placa e rastreamento
- **BOLO**: alerta por placa — qualquer scan da placa marcada notifica a LSPD
- **MDT**: consulta de placas/cidadãos in-game
- **App iPad "Central LSPD"**: login por char_id+senha, procurados, prender, apreender
- **Prisão**: detenção com algemas (HAL client) + integração HSS
- **Apreensão**: delega ao `vhub_garage:forceImpound`

---

## Dependências

```
vhub, oxmysql
```

Soft-deps (pcall): `vhub_groups` (permissões), `vhub_ipad` (app), `vhub_garage` (apreensão), `vhub_identity` (prontuário), `vhub_hss` (algemas).

---

## Exports disponíveis (server-side)

### BOLO

```lua
-- registra alerta de placa; opts = { by = char_id, expires = unix_ts }
exports.vhub_lspdtool:addBolo('ABC1234', 'Fuga de blitz', { by = char_id })

-- remove alerta
exports.vhub_lspdtool:removeBolo('ABC1234')

-- true + dados se a placa tem BOLO ativo
local bolo = exports.vhub_lspdtool:checkBolo('ABC1234')

-- lista todos os BOLOs ativos
local lista = exports.vhub_lspdtool:listBolos()
```

### Scans e placas

```lua
-- registra leitura de placa vinda de fonte externa (radar de terceiro etc.)
-- opts = { source = 'radar'|'helicam'|'manual', officer = char_id }
exports.vhub_lspdtool:reportPlate(src, 'ABC1234', { source = 'manual' })

-- últimas N leituras de placa registradas
local scans = exports.vhub_lspdtool:getRecentScans(50)
```

### Procurados

```lua
-- true + dados se o char_id está na lista de procurados
local wanted = exports.vhub_lspdtool:checkWanted(char_id)

-- lista completa de procurados
local lista = exports.vhub_lspdtool:listWanted()
```

### Relay iPad

```lua
-- relay opaco do app Central LSPD (chamado APENAS pelo broker vhub_ipad)
exports.vhub_lspdtool:ipadRelay(src, action, data)
```

---

## App "Central LSPD" no iPad

O app é **builtin no catálogo do iPad** (registrado no config do `vhub_ipad`, UI remota servida via `cfx-nui-vhub_lspdtool/web/app_ipad/`). Login com `char_id` + senha (SHA2 server-side, contas em `server/accounts.lua`).

Funções do app: procurados (adicionar/remover), prender (detenção), apreender veículo (via `vhub_garage:forceImpound`).

---

## Exemplo de integração (radar de terceiro)

```lua
-- Um radar custom pode alimentar o sistema de scans/BOLO:
local bolo = exports.vhub_lspdtool:checkBolo(plate)
if bolo then
  -- notificar viaturas
end
exports.vhub_lspdtool:reportPlate(src, plate, { source = 'radar' })
```

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 | BOLO/procurados/prisão são verdade do servidor; client só exibe |
| L-04 | Apreensão delega ao garage (dono do status); detenção integra HSS (dono das algemas) |
| §2.5 | Integrações via soft-dep + pcall — sem helicam/radar externo o resto funciona |
| A-10 | Assets do app iPad declarados em `files{}` (UI remota) |
