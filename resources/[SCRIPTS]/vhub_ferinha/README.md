# vhub_ferinha — Marketplace (Leilões P2P)

**Versão:** 0.1.0 | **Owner:** vhub_ferinha

Marketplace server-authoritative: leilões de veículos com escrow automático. Consome `vhub_conce` para transferência de dono, `vhub_inventory` para chaves e `vhub_money` para economia. Não persiste dono nem estado físico.

---

## O que faz

- Leilões de veículos com lance mínimo, buyout e duração configurável
- Escrow de bid em moeda real: o dinheiro é reservado ao dar lance e liberado/cobrado ao finalizar
- Finalização automática por cron: expirados são processados e os ganhadores notificados
- Cancelamento pelo admin com refund automático do escrow
- Zona da casa de leilões configurável (ownership do ferinha, decisão #25)

---

## Dependências

```
vhub, vhub_conce, vhub_inventory, vhub_money, oxmysql
```

---

## Exports disponíveis (server-side, TRUSTED)

Todos os exports são default-deny (apenas `vhub`, `vhub_garage`, `vhub_admin`, `vhub_conce`).

### Leitura

```lua
-- lista todos os leilões ativos (usado pelo garage para a NUI)
local lista = exports.vhub_ferinha:listActiveAuctions()
-- Retorna: { { id, plate, model, min_bid, buyout, current_bid, bidder_cid, expires_at }, ... }

-- leilão ativo de uma placa específica (nil se não houver)
local auction = exports.vhub_ferinha:getAuctionByPlate('ABC1234')

-- zona da casa de leilões (para o garage agregar no boot)
-- Retorna flat {id, label, x, y, z, raio, blip} ou nil — L-19: coord achatada no export
local zona = exports.vhub_ferinha:getZones()
```

### Mutações (TRUSTED)

```lua
-- cria novo leilão (chamado pelo garage via ação admin)
-- dur_min = duração em minutos; buyout = nil para leilão sem compra direta
local result = exports.vhub_ferinha:newAuction(src, 'ABC1234', 50000, 200000, 60)
-- Retorna { ok = true/false, msg = 'string' }

-- registra um lance (src = player que dá o lance)
local result = exports.vhub_ferinha:bid(src, auction_id, 75000)
-- Retorna { ok = true/false, msg = 'string' }

-- admin: cancela leilão com refund do escrow
local ok = exports.vhub_ferinha:cancelAuction(auction_id, actor_cid)

-- finaliza todos os leilões expirados (chamado pelo cron do garage)
local count = exports.vhub_ferinha:finalizeExpired()
```

---

## Fluxo de leilão

```
CRIAR (garage:adminNewAuction)
  → ferinha:newAuction valida placa + dono + status
  → registra em vhub_ferinha_auctions (status='active')

BID (player)
  → ferinha:bid valida bid > current_bid
  → escrow: debita bid do player (vhub_money)
  → refund do bid anterior (se houver)
  → atualiza current_bid + bidder_cid

FINALIZAR (cron ou buyout)
  → ferinha:finalizeExpired
  → conce:transferOwner(plate, winner_cid)
  → garage:updateStatus(plate, 'parked')
  → notifica ganhador e perdedores
```

---

## Como registrar uma zona de leilão (config)

```lua
-- shared/config.lua (dono desde a decisão #25)
VHubFerinha.cfg.leilao_local = {
  id    = 'ferinha_principal',
  label = 'Casa de Leilões',
  coord = vec3(-30.0, -1103.0, 26.4),  -- vec3 LOCAL (L-19)
  raio  = 20.0,
  blip  = { sprite = 272, color = 3, label = 'Leilão' },
}
```

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 | Escrow e transferência 100% server-side |
| L-04 | Dono do veículo = conce; ferinha chama `transferOwner` após leilão ganho |
| L-13 | Nunca escreve estado físico do veículo diretamente |
| L-19 | Zona exportada como coord achatada `{x,y,z}` (não `vec3`) |
| §3.7 | Todos os exports são TRUSTED — nenhum player acessa diretamente |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `listActiveAuctions` | `() → lista de leilões ativos` | vhub_garage (NUI de leilão) |
| 2 | `getAuctionByPlate` | `(plate) → auction\|nil` | vhub_garage |
| 3 | `getZones` | `() → {id, label, x, y, z, raio, blip}` | vhub_garage (boot) |
| 4 | `newAuction` | `(src, plate, min_bid, buyout, dur_min) → {ok, msg}` | vhub_garage (ação admin) |
| 5 | `bid` | `(src, auction_id, valor) → {ok, msg}` | vhub_garage (lance) |
| 6 | `cancelAuction` | `(auction_id, actor_cid) → ok` | vhub_admin |
| 7 | `finalizeExpired` | `() → count` | vhub_garage (cron) |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `notify` |
| `oxmysql` | Persistência de leilões (`vhub_ferinha_auctions`) |
| `vhub_conce` | `transferOwner` (transferência após leilão ganho) |
| `vhub_inventory` | `giveVehicleKey` (chave ao vencedor) |
| `vhub_money` | `tryPayment` (escrow de lance), `giveBankChar` (refund de lance anterior) |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_ferinha:auctionEnded` | server→participantes | `{auction_id, winner_cid, plate, valor}` |
| `vhub_ferinha:newBid` | server→participantes | `{auction_id, valor, bidder_cid}` |
