# vHub Inventory — Super Plano da Mochila Perfeita

> **Resource:** `resources/[SCRIPTS]/vhub_inventory`
> **Escopo exclusivo:** Mochila do jogador · Baús (fixos/facção, porta-malas, drops no chão) · Player Info HUD (ID, telefone)
> **Fora de escopo (responsabilidade única):** Lojas e Marketplace. Vivem em outro resource.
> **Modelo:** Server-authoritative (L-01), VRAM-first + batch SQL, NUI componentizada (A-01..A-08), UI Otimista com rollback.
> **Alvo de performance:** resmon ≤ 0.5 ms ativo · idle ≪ 0.1 ms · servidor < 0.2 ms/tick com 3000+ players.
> **Status:** PLANO APROVADO COM CONDIÇÕES pelos agentes `vhub_arquiteto`, `vhub_guardiao_seguranca`, `vhub_guardiao_performance` (2026-05-29). Pré-código.

Este documento registra a análise das bases de referência e o plano de execução. Nenhuma linha
de código é definida aqui sem ownership e lifecycle explícitos (L-07). Tudo que for "segunda
verdade", redundância ou lixo morto foi cortado **antes** de entrar no plano.


---


# ETAPA 1 — Análise da Base Ouro (`vrp_mochilaprimevoid`)

Engenharia reversa conceitual da espinha dorsal estrutural. O que aproveitar, o que descartar.


## 1.1 — O que a base ouro faz de melhor (ADOTAR o conceito)

| Conceito | Onde (base ouro) | Por que vale | Adaptação vHub |
|----------|------------------|--------------|----------------|
| **Tags por item** | `shared/items.lua` | Define comportamento do item por dado, não por código | Tags na config do `vhub_inventory`; **funções de uso fora** (scripts externos) |
| **Anti-dupe por serial+checksum** | `transacoes.lua` `criarItensDB` | Rastreia instância única, detecta duplicação | Serial **só na META de itens únicos** (arma, chave, especial), **não** 1 linha SQL por unidade |
| **Ledger de transação** | `vrp_inventario_transacoes` + `criarTransacao` | Auditoria forense de cada operação | Auditoria **enxuta** via webhook + log opcional; sem tabela de ledger por operação |
| **Transação atômica tudo-ou-nada** | `iniciar/commit/rollback_transacao_db` | Multi-write consistente (mochila↔baú) | `vHub.State:begin()/commit()` (manual §3.3) — atomicidade no VRAM/batch |
| **Bloqueios por tag** | `bloqueado_drop`, `permitido_bau`, `bloqueado_mercado` | Regra de jogo declarativa | Tags `perdivel`, `negociavel`, `permitido_bau`, `legalidade` |
| **Capacidade por classe de veículo** | `bau_veiculo.multiplicador_por_classe` | Porta-malas realista (truck > carro > moto) | multiplicador por `vtype` do registro do `vhub_garage` (não `GetVehicleClass` server-side) |
| **Painel de identidade + foto** | `nui.lua` `abrirMochila`, `app.js` `renderPlayerInfo` | UX premium (nome, ID, cargo, saldo) | Painel no módulo `backpack/`; foto **cacheada** (não busca a cada abertura) |
| **Hotbar / binds (1–5)** | `app.js` `renderBinds`, `saveBind` | Uso rápido sem abrir mochila | Hotbar como slice de store; persistida em cdata |
| **Quantidade via modal** | `app.js` `openQtyModal` | Split de stack controlado | Modal de quantidade + **drag por mouse** (HTML5 DnD é instável no CEF) |

## 1.2 — Responsabilidades essenciais de interface e lógica

**Lógica (server, autoritativa):**
- `listarMochila(userId)` → itens + peso atual + peso máximo. (vHub: deriva peso, nunca armazena.)
- `adicionarItemSeguro` / `removerItemSeguro` → validação (existe? peso? tag?) antes de mutar.
- `moverItemMochilaParaContainer` / inverso → checa tag `permitido_bau`, peso do destino, posse.
- `droparItemSeguro` → checa `bloqueado_drop`, gera drop, remove da mochila.
- `transferirItemParaJogador` → P2P, valida posse de ambos antes de commitar.

**Interface (NUI):**
- Slots renderizados como cards (`createItemCard`): ícone, nome, quantidade, peso.
- Seleção → ação (usar / dropar / enviar / mover) com quantidade.
- Barra de peso (`updateWeight`) com `peso / maxpeso` e largura proporcional.
- Troca de contexto (mochila / baú) — na base ouro era monólito com `setContext`; **no vHub vira módulos isolados**.

## 1.3 — Conversão da UI legada → padrão web vHub

A base ouro usa **uma NUI monolítica** (`app.js` 467 linhas) com `state` global e `setContext('mochila'|'bau'|'market'|'loja')` alternando `view.classList`. Isso viola A-02/A-03/A-05.

**Conversão obrigatória:**

| Legado (vrp) | vHub (web/runtime + módulos) |
|--------------|------------------------------|
| `state` global único | `vhub.store('inventory')`, `vhub.store('container')` — slices por domínio (A-04) |
| `setContext()` + `classList` | `vhub.mount('backpack')` / `mount('container')` — lazy load (A-05) |
| `window.addEventListener('message')` gigante | dispatcher do `web/runtime/core.js` → `vhub.emit('nui:*')` (A-03) |
| `fetch(https://res/cb)` espalhado | `vhub.native.*` / `services/` centralizado (A-06) |
| Sem cleanup | `onDestroy`: cancela RAF/listener/observer (A-07) |
| Drag-drop ausente (era click+modal) | **drag por mouse** (`vhub.interact`, confiável no CEF) + modal de quantidade |


---


# ETAPA 2 — Varredura de Features Secundárias

De cada base, **só** a responsabilidade complementar útil. O resto é descartado.


## 2.1 — Features a ADOTAR (priorizadas)

| # | Feature | Origem | Justificativa |
|---|---------|--------|---------------|
| 1 | **Cooldown anti-race por jogador** (`actived[src]`) | `vrp_chest` | Evita dup de double-action sem lock SQL pesado |
| 2 | **Mutex por container** (`_locks[container_id]`) | (lacuna detectada pela segurança) | Serializa acesso concorrente ao MESMO baú (2 players, 1 item) |
| 3 | **Chave hierárquica de container** | `vrp_trunkchest` | `static:<nome>`, `trunk:<placa>`, `faction:<grupo>` — legível e escalável |
| 4 | **Capacidade por classe de veículo** | `vrp_trunkchest` | multiplicador por `vtype` do registro do `vhub_garage`; truck > carro > moto |
| 5 | **Drops com TTL server-side** | `vrp_itemdrop` | Expiração determinística sem depender de evento externo |
| 6 | **Prop local por proximidade** | `vrp_itemdrop` (melhorado) | Cliente spawna prop local; **sem entidade networkada** (anti-storm) |
| 7 | **Validação de peso dinâmica** | todas | `peso_atual + peso_item*qty ≤ max` — obrigatório |
| 8 | **Slots dinâmicos / expansíveis** | `dpn_inventory_chest` | Mochila/baú com slot count configurável |
| 9 | **Anti-dupe proativo** | `dpn_inventory_chest` | Detecta N ações simultâneas → log/kick (config) |
| 10 | **Envio P2P por proximidade** | `unity_inventory` | `getNearestPlayer(2m)` validado server-side |

## 2.2 — Features a DESCARTAR (lixo / peso morto)

| Descartado | Origem | Motivo |
|------------|--------|--------|
| Webhooks Discord **hardcoded no código** | `vrp_chest`, `vrp_trunkchest`, config ouro | Segredos no código; vão para `config/` ou env |
| **Foto buscada a cada abertura** | `unity_inventory` | Query em hot path; cachear por sessão |
| Loop cliente de distância 3s indiscriminado | `vrp_itemdrop` | Substituir por thread fria 1s + quente só perto |
| Loop server "downtime" 2s global | `vrp_chest` | Substituir por mutex + cooldown sob demanda |
| **1 linha SQL por unidade de item** | base ouro `criarItensDB` | Inviável em alta performance; serial vai na meta |
| **Tabela de ledger por operação** | base ouro `transacoes` | Auditoria pesada; webhook + log enxuto basta |
| Lojas / Marketplace / NPC shop | base ouro `comprarDaLoja` etc. | **Fora de escopo** — outro resource |
| Salário / AFK / HUD genérico / placas | base ouro `config.player` | Fora de escopo — não é inventário |
| Permissões embutidas em tabela Lua | `vrp_chest` | Usar `vhub_groups:hasPermission` + config |
| **Tabela SQL `vhub_inv_drops`** | (cogitada) | **Cortada** — drops são efêmeros; SQL infla sem ganho (L-09) |


---


# ETAPA 3 — Plano de Execução do Inventário Perfeito vHub

Dividido nas 4 camadas vHub. Cada arquivo tem ownership e responsabilidade única.


## 3.0 — Veredito dos agentes (condições obrigatórias)

> Estas condições foram levantadas pelos guardiões e são **pré-requisito** para a implementação.

**`vhub_arquiteto` — APROVAR COM CONDIÇÕES:**
1. Mochila em `user.data.inventory` (cdata CORE) **não viola L-04** (donos distintos). Mas `backpack.lua` **DEVE validar peso/slot máx server-side antes de persistir** — o core não valida.
   > **⚠ CORREÇÃO PÓS-VERIFICAÇÃO (no início da implementação):** o core **frozen NÃO expõe** `getCData/setCData` a resources externos (`server/exports.lua` só tem `getUser`/`getUID`/`hasPerm`/`getVehicle`/`ban…`). Logo a mochila **não** vive no cdata do core — vive em **tabela própria `vhub_inv_player` via `exports.oxmysql`** (mesmo padrão do `vhub_garage`, decisão #8), com **cache VRAM apenas dos players ONLINE** (liberado em `playerDropped` — não infla a RAM com offline). Continua **fonte única** (a tabela + seu cache write-through); o princípio VRAM-first é honrado **dentro** do resource (leitura do cache, escrita debounced + flush triplo).
2. Porta-malas: conteúdo pertence ao inventory; **placa é read-only do `vhub_garage`** (decisão #12). Exige **contrato de cleanup** ao deletar veículo (senão órfãos).
3. Drops: **efêmeros em VRAM + cron TTL**. Cortada a tabela SQL `vhub_inv_drops`.
4. Separar `items.lua` (catálogo) de `item_use.lua` (dispatcher de handlers). ~~`playerinfo_sync.lua` é **sink**~~ → **descartado na implementação**: HUD é resolvido no cliente (ID local + evento `vhub_identity:load`), ver §3.5.
5. `web/runtime/` é **cópia local** — nunca compartilhar fisicamente com `vhub_racha`.

**`vhub_guardiao_seguranca` — APROVAR COM RESSALVAS:**
1. Cooldown por `src` **não basta** para baú compartilhado → **mutex `_locks[container_id]`** (timeout 300 ms).
2. `_open_containers[src]` — servidor registra qual baú autorizou abrir; mutação só aceita esse `container_id` (bloqueia forja).
3. **Nunca aceitar coords do cliente** — servidor sempre resolve via `GetEntityCoords`/NetId.
4. Validar `qty`: `math.type(qty) == 'integer' and qty >= 1 and qty <= stack_max`.
5. **Ignorar meta do payload** — servidor re-lê meta do VRAM; cliente nunca define serial/flags.

**`vhub_guardiao_performance` — APROVAR COM RESSALVAS:**
1. **Drop spawn budget** = 3 `CreateObject`/frame com `Wait(0)` entre lotes; cap `MAX_DROPS_POR_ZONA`.
2. **Flush triplo de baú**: dirty flag + debounce 3 s + `playerDropped` + `onResourceStop`.
3. **Cron TTL**: intervalo 60 s, chunk 50, `Wait(0)` entre chunks.
4. **Write-guard de State Bag**: só escreve se valor mudou.
5. Drops via **set O(1)** + evento de remoção imediata — nunca varredura O(n)/1 s.


## 3.1 — Estrutura de arquivos (ownership por camada)

```
vhub_inventory/
├── fxmanifest.lua
│
├── config/
│   └── inventory.lua          ← tags de item, slots, pesos, capacidades, CDN base, TTLs
│
├── shared/
│   ├── events.lua             ← VHubInvE.* (fonte única de nomes de evento)
│   └── utils.lua              ← helpers puros (fmtWeight, clampQty, hashSlots)
│
├── server/                    ← L1 KERNEL (autoritativo)
│   ├── sql.lua                ← exports.oxmysql wrappers + schema (containers only)
│   ├── items.lua              ← catálogo IMUTÁVEL de definições/tags (read-only)
│   ├── item_use.lua           ← registry de handlers de uso (dispatcher p/ scripts externos)
│   ├── backpack.lua           ← mochila: tabela vhub_inv_player + cache VRAM (só online); write-through
│   ├── containers.lua         ← baús fixos/facção/porta-malas (SQL próprio + mutex + open-guard)
│   ├── drops.lua              ← drops efêmeros (VRAM + cron TTL + set O(1))
│   ├── transfer.lua           ← transações atômicas (mochila↔baú, P2P, drop, pickup)
│   ├── init.lua               ← sessões, schema apply, wiring
│   └── exports.lua            ← API pública (_invoker_allowed nos mutadores)
│
├── client/                    ← L2 HAL (natives, sem decidir verdade)
│   ├── bridge.lua             ← native bridge NUI + foco + abre/fecha
│   ├── drops.lua              ← prop LOCAL por proximidade (CreateObject não-networked)
│   ├── containers.lua         ← DrawMarker proximity-gated + tecla de interação
│   └── playerhud.lua          ← lê State Bag → delta p/ HUD
│
└── web/
    ├── index.html             ← ui_page; carrega runtime + módulos
    ├── runtime/               ← L3 (cópia local do engine — NÃO compartilhar c/ racha)
    │   ├── bus.js  store.js  bridge.js  core.js  sand.js
    ├── shared/                ← tokens.css, reset.css, components.css, utils.js
    └── modules/               ← L4 COMPONENTES
        ├── backpack/          ← grid de slots, drag-drop, split/merge, peso, hotbar, painel id
        ├── container/         ← split mochila↔baú/porta-malas
        ├── hud/               ← Player Info HUD (id, telefone) sempre visível, via delta
        └── pickup/            ← prompt de pegar drop
```

> **Schema SQL:** `vhub_inv_player` (mochila) + `vhub_inv_containers` (baús). Drops **não** têm tabela (efêmeros). FK `INT UNSIGNED` para `vh_characters.id` (decisão #17).


## 3.2 — PILAR 1: Componentização e Tags Dinâmicas

**Princípio:** a *definição* do item (visual + tags) mora no `vhub_inventory`. A *função de uso*
mora no script dono do domínio (água → `vhub_survival`; lockpick → `vhub_crime`). O inventory
é o **dispatcher**, nunca o monólito de regras.

### Esquema de definição de item (`config/inventory.lua`)

```lua
-- config/inventory.lua — catálogo de itens (apenas DADOS; sem lógica de uso)

Inventory.Items = {

  -- ITEM EMPILHÁVEL (commodity) — sem meta, sem serial
  ['agua'] = {
    nome       = 'Água',
    desc       = 'Garrafa de água potável.',
    peso       = 0.20,
    stack      = true,             -- empilha
    max        = 999,              -- teto da pilha
    legalidade = 'comum',          -- legal | ilegal | comum
    negociavel = true,             -- pode P2P / mercado
    perdivel   = true,             -- cai no chão na morte / pode dropar
    permitido_bau = true,
    categoria  = 'consumivel',
    -- icon implícito = chave do item → CDN <agua>.png
  },

  -- ITEM ÚNICO (instância rastreável) — serial na meta, não empilha
  ['lockpick'] = {
    nome       = 'Lockpick',
    peso       = 0.10,
    stack      = false,            -- cada um ocupa 1 slot
    legalidade = 'ilegal',
    negociavel = true,
    perdivel   = true,
    permitido_bau = true,
    serial     = true,             -- gera serial server-side na criação
    categoria  = 'ferramenta',
  },

  -- ITEM VINCULADO (chave de veículo) — meta carrega a placa
  ['veh_key'] = {
    nome       = 'Chave de Veículo',
    peso       = 0.05,
    stack      = false,
    legalidade = 'legal',
    negociavel = false,            -- não negociável
    perdivel   = false,            -- não cai na morte / não dropa
    permitido_bau = false,
    serial     = true,
    categoria  = 'chave',
    -- meta = { plate = 'ABC1234' } definido pelo emissor (vhub_garage)
  },
}
```

### Tags e seu efeito (declarativo, validado no servidor)

| Tag | Tipo | Efeito server-side |
|-----|------|--------------------|
| `peso` | number | Soma no peso da mochila/baú; valida capacidade |
| `stack` / `max` | bool / int | Define empilhamento e teto da pilha |
| `legalidade` | `legal`/`ilegal`/`comum` | Filtros de revista policial, blips, hooks externos |
| `negociavel` | bool | Bloqueia P2P/mercado se `false` |
| `perdivel` | bool | Bloqueia drop e perda na morte se `false` |
| `permitido_bau` | bool | Bloqueia mover para baú se `false` |
| `serial` | bool | Gera serial único server-side (anti-dupe de itens valiosos) |
| `categoria` | string | Agrupamento visual na NUI |
| `meta` | table | Dados de instância (placa, durabilidade, munição) — **só server escreve** |

### Funções de uso ficam FORA (dispatcher)

```lua
-- OUTRO resource (ex: vhub_survival) registra o handler de uso:
exports.vhub_inventory:registerItemUse('agua', function(src, slot, meta)
  exports.vhub_survival:varyVital(src, 'agua', 0.30)
  return true   -- true = consome 1; false = não consome
end)
```

```lua
-- server/item_use.lua — dispatcher (NÃO contém regra de domínio)
function ItemUse.run(src, item_id, slot)
  local handler = _handlers[item_id]
  if not handler then return end

  -- re-valida posse no momento do uso (slot pode ter mudado)
  local entry = Backpack.peek(src, slot)
  if not entry or entry.id ~= item_id then return end

  -- consumo atômico: decrementa ANTES do efeito; reembolsa se falhar
  if not Backpack.takeFromSlot(src, slot, 1) then return end
  local ok, consumed = pcall(handler, src, slot, entry.meta)
  if not ok or consumed == false then
    Backpack.giveToSlot(src, slot, item_id, 1, entry.meta)  -- reembolso
  end
end
```


## 3.3 — PILAR 2: Assets via CDN Dinâmico (jsDelivr)

A config guarda **apenas o identificador** do item. O frontend resolve a URL.

```js
// web/shared/utils.js — resolução de ícone via CDN
const CDN_BASE = 'https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main';

function itemIcon(id) {
  return `${CDN_BASE}/${id}.png`;   // ex: .../agua.png
}
```

```js
// uso no card, com fallback gracioso (sem ícone quebrado)
img.src = itemIcon(item.id);
img.onerror = () => { img.replaceWith(fallbackInitial(item.nome)); };
```

**Regras:**
- A base do CDN é **uma constante** (em `config/inventory.lua` espelhada para a NUI no payload de `open`), não repetida por item.
- `loading="lazy"` + cache do navegador CEF; ícone só baixa quando o slot entra em viewport.
- **Fallback offline:** `onerror` mostra a inicial do nome (nunca quebra o layout). Registrado como risco em ambiente sem internet (mesma classe do CDN de fontes do `vhub_racha`).
- Nenhuma URL completa na config — só `Void-Cla/vhub-assets@main` no runtime.


## 3.4 — PILAR 3: UI Otimista e Rollback (Segurança + Otimização)

**Princípio:** o cliente **renderiza a movimentação imediatamente** (sensação instantânea), mas a
verdade é do servidor. Se o servidor negar, um **rollback visual** restaura o estado autoritativo.

### Modelo de dados da mochila (VRAM-first, fonte única)

```lua
-- Mochila — cache VRAM (só players online), escrito SOMENTE por backpack.lua;
-- persistido em vhub_inv_player via write-through (debounce + flush triplo).
inventory = {
  slots = {
    [1] = { id = 'agua',     amount = 3, meta = nil },
    [2] = { id = 'lockpick', amount = 1, meta = { serial = 'LP-7f3a..' } },
    -- slot vazio = ausente da tabela
  },
}
-- peso é DERIVADO (recalculado on-demand) — NUNCA armazenado (evita 2ª verdade)
```

> **🔒 ISOLAMENTO POR PERSONAGEM (regra dura):** mochila e baús são SEMPRE chaveados por
> **`char_id`**, NUNCA por `user_id`. Um `user_id` pode ter **5 `char_id`** — os inventários
> deles **jamais se cruzam**. `vhub_inv_player.char_id` é PK; `vhub_inv_containers.owner` é
> `char_id`. **Troca de personagem na mesma sessão** (mesmo `src`, outro `char_id`) faz
> **flush do char anterior ANTES de carregar o novo** em `Backpack.load` — sem isso, itens de
> um personagem vazariam ou se perderiam ao trocar para outro do mesmo `user_id`.

### Fluxo canônico — Mover item (Mochila → Baú)

```
┌─ CLIENTE (NUI) ───────────────────────────────────────────────┐
│ 1. drag slot_src → slot_dst (baú)                              │
│ 2. store.inventory aplica o movimento OTIMISTA (UI instantânea)│
│ 3. emite intenção: vhub.native → 'inv:move'                    │
│    payload = { from='backpack', to=container_id,               │
│               slot_src, slot_dst, qty }                        │
│    (NUNCA envia coords, peso, meta ou preço — só intenção)     │
└───────────────────────────────────────────────────────────────┘
                              │
┌─ SERVIDOR (transfer.lua) ──▼──────────────────────────────────┐
│ 4. checkPayload (tipos/ranges) — qty integer ≥1 ≤stack_max     │
│ 5. container_id == _open_containers[src] ? (anti-forja)        │
│ 6. adquire _locks[container_id] (mutex, timeout 300ms)         │
│ 7. distância server-side: GetEntityCoords(ped) vs baú ≤ raio   │
│ 8. posse real: slot_src tem o item e qty? (lê VRAM, não payload)│
│ 9. tag permitido_bau? peso resultante do baú ≤ capacidade?     │
│10. State:begin() → remove da mochila + add no baú → commit()   │
│11. libera lock · marca baú dirty (flush debounce/triplo)       │
└───────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
              SUCESSO                  FALHA
                    │                     │
   12a. envia DELTA dos slots      12b. envia 'inv:rollback'
        afetados (confirmação)          (estado autoritativo dos
        + persiste batch                 slots tocados) + notify erro
```

### Rollback (o ponto-chave)

```lua
-- servidor, em qualquer falha de validação:
TriggerClientEvent(VHubInvE.ROLLBACK, src, {
  backpack = Backpack.snapshotSlots(src, { slot_src, slot_dst }),  -- só os tocados
  container = container_id and Containers.snapshotSlots(container_id, {...}) or nil,
  reason   = 'peso_excedido',   -- chave de lang p/ notify PT-BR
})
```

```js
// cliente: rollback substitui o estado otimista pelo autoritativo
vhub.listen('nui:inv:rollback', ({ backpack, container, reason }) => {
  store('inventory').patch(backpack);     // reverte só os slots tocados
  if (container) store('container').patch(container);
  toast.error(LANG[reason] || 'Operação negada');
});
```

### Fluxos cobertos (todos atômicos + validados)

| Fluxo | Validações server-side obrigatórias |
|-------|-------------------------------------|
| Mochila → Baú | payload · open-guard · mutex · distância · posse · `permitido_bau` · peso baú |
| Baú → Mochila | payload · open-guard · mutex · re-distância no commit · peso mochila |
| P2P (enviar) | ambos online/vivos · `negociavel` · distância 2 m · cooldown src **e** target · meta re-lida do VRAM |
| Drop (chão) | posse · `qty>0` · `perdivel` · coords **server-side** · serial server-side |
| Pickup | drop existe e `claimed_by=nil` · distância · lock do `drop_id` · peso pós-adição |
| Usar item | handler registrado · cooldown · re-valida slot · consumo atômico (reembolso se falhar) |


## 3.5 — PILAR 4: Otimização de Tráfego (State Bags + Deltas)

### Player Info HUD (cliente resolve — ID local + evento de identidade)

HUD é display **não-crítico**: o cliente monta. Mas o **ID é SEMPRE o id do PERSONAGEM (`char_id`)**
— o cliente não conhece o `char_id` sozinho, então o **servidor envia** (`VHubInvE.HUD`). Um `user_id`
pode ter até **5 `char_id`**; a troca de personagem re-dispara `characterLoad` → novo `char_id` no HUD.
**Nome/telefone** vêm do evento público do dono (`vhub_identity:load`) — sem race, sem State Bag.

```lua
-- server/init.lua — envia o char_id ao HUD no load (e responde HUD_REQ)
TriggerClientEvent(E.HUD, src, { charId = user.char_id })

-- client/playerhud.lua
RegisterNetEvent(VHubInvE.HUD)
AddEventHandler(VHubInvE.HUD, function(d) _charId = d.charId; pushHud() end)   -- id = char_id
RegisterNetEvent('vhub_identity:load')
AddEventHandler('vhub_identity:load', function(id) _name = id.firstname..' '..id.lastname; _phone = id.phone; pushHud() end)
```

> **⚠ DECISÃO DE IMPLEMENTAÇÃO (2026-05-29):** o sink server-side via State Bag (`playerinfo_sync`)
> foi **descartado**. Motivo descoberto em runtime: `vhub_identity` carrega a linha de identidade
> **assincronamente** (thread + query) e seta `user.identity` depois; `getIdentity(src)` chamado no
> `characterLoad` do inventory caía em **race** (retornava nil → HUD sem nome/telefone). Além disso o
> ID é puramente local. Solução: o cliente monta o HUD (ID local + evento `vhub_identity:load`, que o
> próprio identity reemite em load/spawn/`:get`). Menos código, sem race, sem segunda fonte. State
> Bags ficam reservados para campos que o servidor realmente computa (ex.: job/wanted no futuro).

### Deltas de inventário (nunca tabela massiva)

```lua
-- só os slots que mudaram; slot limpo = false
TriggerClientEvent(VHubInvE.DELTA, src, {
  scope = 'backpack',
  slots = { [1] = { id='agua', amount=2 }, [5] = false },  -- [5] esvaziou
})
```

```js
// cliente aplica patch incremental; re-renderiza só os slots tocados
vhub.listen('nui:inv:delta', ({ scope, slots }) => {
  const s = store(scope === 'backpack' ? 'inventory' : 'container');
  s.patch(slots);                 // O(slots alterados), não O(n)
});
```

**Regras de tráfego:**
- `SendNUIMessage` **só em mudança real** — jamais por tick/frame (A-08).
- Abertura manda snapshot completo **uma vez**; o resto é delta.
- HUD via State Bag, não via `SendNUIMessage` periódico.
- Hotbar/binds: delta só quando o slot da hotbar muda.


## 3.6 — Drops no chão (efêmeros, sem entidade networkada)

> Servidor é dono da lista. Cliente spawna prop **local** por proximidade. **Sem** entidade
> networkada (evita storm com 3k players). Pickup validado por coords server-side.

```lua
-- server/drops.lua — drops em VRAM (set O(1)), cron TTL
Drops._list = {}           -- [drop_id] = { id, amount, meta, x, y, z, dim, expires_at, claimed_by }
Drops._seq  = 0

-- cap por zona (anti-spike): rejeita se a cell 100m² já tem MAX_DROPS_POR_ZONA
-- broadcast leve: TriggerClientEvent(VHubInvE.DROP_ADD, -1, dropSummary)

-- cron TTL: intervalo 60s, chunk 50, Wait(0) entre chunks
CreateThread(function()
  while true do
    Wait(60000)
    local now, n = os.time(), 0
    for drop_id, d in pairs(Drops._list) do
      if d.expires_at <= now then
        Drops._list[drop_id] = nil
        TriggerClientEvent(VHubInvE.DROP_DEL, -1, drop_id)
      end
      n = n + 1
      if n % 50 == 0 then Wait(0) end   -- yield: não trava tick
    end
  end
end)
```

```lua
-- client/drops.lua — prop LOCAL por proximidade, spawn com budget
local _spawned = {}        -- [drop_id] = object (set O(1))
local DROP_SPAWN_BUDGET = 3

-- thread fria (1s) decide o que precisa existir; spawn em lotes de 3 com Wait(0)
-- thread quente só desenha prompt quando há drop muito perto
-- DeleteObject imediato no evento DROP_DEL (sem varredura O(n))
```

| Natives | Uso |
|---------|-----|
| `CreateObject(hash, x,y,z, false, false, false)` | prop **local** (isNetwork=false) |
| `PlaceObjectOnGroundProperly(obj)` | assenta no chão |
| `SetEntityAsMissionEntity(obj, true, true)` | controle p/ deletar |
| `DeleteObject(obj)` | remove ao sair/pegar |
| `GetEntityCoords(ped)` | distância (server-side no pickup) |


## 3.7 — Baús, porta-malas e contrato com `vhub_garage`

### Capacidade do porta-malas — pelo registro do `vhub_garage` (NÃO `GetVehicleClass`)

> **⚠ AJUSTE DE IMPLEMENTAÇÃO (runtime):** nativas de entidade de veículo são **instáveis/ausentes
> server-side** — `NetworkDoesEntityExistWithNetworkId` é **nil** no servidor; `GetVehicleClass` ambíguo.
> Então o **cliente lê a placa** (`GetVehicleNumberPlateText`, client-side confiável) e envia
> `{ kind='trunk', plate }`; o **servidor** valida acesso (chave-na-mochila OU dono no garage) e deriva
> a capacidade do **tipo (`vtype`) do registro do garage**. Acesso é gated por chave → placa vinda do
> cliente **não é vetor econômico** (só abre porta-malas de quem tem a chave).

```lua
-- config/inventory.lua
Inventory.Trunk = {
  base_capacity = 40.0, range = 5.5, size = 40, require_access = true,
  -- multiplicador pelo TIPO do registro do vhub_garage (NAO GetVehicleClass server-side)
  vtype_mult = { car=1.0, bike=0.2, truck=2.5, trailer=3.0, boat=0.8, heli=0.6, plane=1.5 },
}
```

### Contrato de cleanup (condição do arquiteto)

> `vhub_garage` **não emite** evento de deleção hoje (só `SQL:deleteVehicle` interno).
> Sem cleanup, `trunk:<placa>` vira órfão na tabela. **Duas frentes:**

1. **Preferencial (a adicionar no garage):** `vhub_garage` emite `vHub:vehicleDeleted(plate)`;
   `vhub_inventory` assina e apaga `trunk:<plate>`.
2. **Fallback (dentro do inventory):** cron GC de baixa frequência (ex: 30 min) que cruza
   `trunk:*` contra `exports.vhub_garage:getVehicle(plate)` e remove órfãos (chunked, com yield).

> A placa é **read-only** — inventory nunca escreve em estruturas do garage (decisão #12).


## 3.8 — Modelo de Segurança Anti-Dupe (consolidado)

```lua
-- server/containers.lua — mutex + open-guard (condições da segurança)
local _locks = {}            -- [container_id] = expires_ms (mutex, timeout 300ms)
local _open  = {}            -- [src] = container_id (autorização de abertura)

local function lock(container_id)
  local now = GetGameTimer()
  if _locks[container_id] and _locks[container_id] > now then return false end
  _locks[container_id] = now + 300
  return true
end

local function authorized(src, container_id)
  return _open[src] == container_id     -- bloqueia container_id forjado
end
```

**Camadas de defesa (em ordem):**
1. `checkPayload` do core (tipos/ranges/tamanho) em todo evento de rede.
2. `qty` é integer, `1 ≤ qty ≤ stack_max` (bloqueia negativo/overflow).
3. `item_id` existe em `Inventory.Items` (bloqueia item fantasma).
4. Meta **re-lida do VRAM** — payload de meta é ignorado (bloqueia flags forjadas).
5. `_open_containers[src]` — só opera no baú que o servidor autorizou abrir.
6. `_locks[container_id]` — serializa acesso concorrente (bloqueia dupe A+B no mesmo baú).
7. Distância **server-side** via `GetEntityCoords` (bloqueia spoof de posição).
8. Transação atômica `State:begin()/commit()` (tudo-ou-nada).
9. Cooldown por `src` + antiflood do kernel (bloqueia double-action).
10. Anti-dupe proativo: > N ações/janela → log/kick (config).


## 3.9 — Contratos públicos (API)

### Exports (mutadores com `_invoker_allowed()`)

| Export | Proteção | Assinatura |
|--------|----------|------------|
| `getInventory` | pública | `(src) → slots` |
| `getItemAmount` | pública | `(src, item_id) → int` |
| `hasItem` | pública | `(src, item_id, qty) → bool` |
| `getInventoryWeight` | pública | `(src) → number` |
| `giveItem` | `_invoker_allowed()` | `(src, item_id, qty, meta?) → ok` |
| `takeItem` | `_invoker_allowed()` | `(src, item_id, qty) → ok` |
| `registerItemUse` | `_invoker_allowed()` | `(item_id, fn)` |
| `giveVehicleKey` | `_invoker_allowed()` | `(src, plate) → ok` |
| `hasVehicleKey` | pública | `(src, plate) → bool` |
| `openContainer` | `_invoker_allowed()` | `(src, container_id, opts) → ok` |

> Mantém compatibilidade com os exports do stub atual (`giveItem`/`takeItem`/`hasItem`/`getInventory`/
> chaves de veículo) — scripts que já dependem deles não quebram.

### Eventos (`shared/events.lua` — fonte única `VHubInvE.*`)

`OPEN`, `CLOSE`, `DELTA`, `ROLLBACK`, `USE`, `MOVE`, `DROP`, `PICKUP`, `P2P`,
`DROP_ADD`, `DROP_DEL`, `CONTAINER_SYNC`.

### Schema SQL (`sql/schema.sql` — mochila + containers)

```sql
-- MOCHILA do jogador (1 linha por personagem; slots em JSON)
CREATE TABLE IF NOT EXISTS `vhub_inv_player` (
  `char_id`    INT UNSIGNED NOT NULL,
  `data`       LONGTEXT     NOT NULL,            -- JSON { slots = { [i]={id,amount,meta} } }
  `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`char_id`),
  CONSTRAINT `fk_inv_player_char` FOREIGN KEY (`char_id`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- BAÚS (fixos/facção/porta-malas)
CREATE TABLE IF NOT EXISTS `vhub_inv_containers` (
  `container_id` VARCHAR(80)  NOT NULL,            -- static:<nome> | trunk:<placa> | faction:<grupo>
  `kind`         VARCHAR(20)  NOT NULL,
  `owner`        INT UNSIGNED NULL,                -- char_id dono (NULL p/ facção/estático)
  `data`         BLOB         NOT NULL,            -- msgpack { slots = {...} }
  `capacity`     DECIMAL(10,2) NOT NULL DEFAULT 100,
  `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`container_id`),
  KEY `idx_owner` (`owner`),
  CONSTRAINT `fk_inv_owner` FOREIGN KEY (`owner`)
    REFERENCES `vh_characters` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

> `data` é `LONGTEXT` (JSON via `oxmysql` — simples, debugável, robusto p/ "não perder"). FK `INT UNSIGNED` (decisão #17).
> Mochila em `vhub_inv_player`; baús em `vhub_inv_containers`. **Drops não têm tabela** (efêmeros em VRAM + TTL).


## 3.10 — Plano de Sprints

| Sprint | Entrega | Conteúdo | Status |
|--------|---------|----------|--------|
| **INV-1** | Núcleo autoritativo | `config` · `shared/events` · `shared/utils` · `sql` · `items` · `item_use` · `backpack` (tabela própria + cache + validação peso/slot) · `exports` (compat) · `client/bridge` · `client/playerhud` (HUD client-side por char_id) · `web` runnable | ✅ Aprovado (gate revisao) |
| **INV-2** | Mochila visual + baús | `web/modules/backpack` (grid + peso + painel id) · `containers` (SQL + mutex + open-guard + viewers) · `web/modules/container` (dual-pane) · `client/containers` (marker + porta-malas) · `transfer` atômico | ✅ Aprovado (gate revisao) |
| **INV-2.1** | Interação + UX | **drag por mouse** (`web/shared/interact.js`) + **modal de quantidade** · **tecla unificada `I`** (baú fixo > porta-malas > mochila) · DRY (`slots.css`, `fillSlot`) · `/item` (`server/dev.lua`) | ✅ Concluído |
| **INV-2.2** | Diferenciais (varredura) | **Hotbar 1-5** (persist. no blob por char_id, vincular arrastando, usar por tecla, limpar right-click) · **busca + categorias** · **menu de contexto** (Usar/Dividir) · **gradiente de peso** · trunk distância best-effort · `/item` aviso de boot | ✅ Concluído |
| **INV-3** | Drops + polimento | `drops` (VRAM + TTL + budget) · `client/drops` (prop local) · `web/modules/pickup` · split interno · P2P · anti-dupe proativo · CDN fallback offline | ⏳ Próximo |
| **INV-4** | Hardening | tuning de resmon (50+ players simulados) · GC órfãos trunk · smoke tests · gate final | ⏳ Pendente |

> A cada sprint com diff relevante: rodar guardiões pertinentes em paralelo + gate `vhub_guardiao_revisao` (CLAUDE.md).
> **Decisões de runtime (deltas do plano original):** mochila em tabela própria (core não expõe cdata) · HUD client-side por `char_id` (sem State Bag, sem race) · trunk por **placa** + garage (nativas de entidade de veículo são nil/ambíguas server-side) · **drag por mouse** (HTML5 DnD instável no CEF) · abertura unificada na tecla **`I`**.


## 3.11 — Checklist de Conformidade (antes de cada commit)

**Leis imutáveis (L-01..L-12):**
- [ ] Servidor decide toda verdade crítica (posse, peso, dupe) — cliente só intenção (L-01/L-02)
- [ ] Rollback = reenvio do estado autoritativo do servidor (L-03)
- [ ] Mochila e baús em tabelas próprias (cache VRAM só de online) — **uma fonte por dado** (L-04)
- [ ] Native-first: drops via `CreateObject` local, markers via `DrawMarker` (L-05)
- [ ] Sem `while true` sem saída; proximidade por thread fria + quente (L-06)
- [ ] Todo módulo/arquivo com ownership e lifecycle (L-07)
- [ ] Código inglês; saídas/comentários/lang PT-BR (L-08)
- [ ] Funções curtas, sem redundância (L-09)
- [ ] Toda função pública com comentário PT-BR de 1 linha (L-10)
- [ ] Transações SQL atômicas server-side (L-12)

**Leis de componentização (A-01..A-08):**
- [ ] JS não decide regra crítica; kernel não renderiza (A-01)
- [ ] Todo módulo NUI com lifecycle completo (A-02)
- [ ] Comunicação inter-módulo via event bus (A-03)
- [ ] Slice por domínio, owner declarado (A-04)
- [ ] Lazy load + unmount real (A-05)
- [ ] Native bridge centralizado (A-06)
- [ ] Cleanup no `onDestroy` (A-07)
- [ ] Delta sync; nunca payload bruto por frame (A-08)

**Segurança / Performance (condições dos guardiões):**
- [ ] `_locks[container_id]` mutex + `_open_containers[src]` open-guard
- [ ] `qty` integer validado; meta re-lida do VRAM; coords só server-side
- [ ] Drop spawn budget (3/tick) + cap por zona
- [ ] Flush triplo de baú (dirty + debounce 3 s + playerDropped + onResourceStop)
- [ ] Write-guard de State Bag; drops via set O(1)
- [ ] resmon ≤ 0.5 ms ativo, idle ≪ 0.1 ms


---


# Resumo em uma linha

> **Mochila em tabela própria + cache VRAM só de online (fonte única), baús em tabela com mutex, drops efêmeros
> com prop local proximity-gated, tags declarativas + uso externo, UI otimista com rollback
> autoritativo, tráfego por State Bag + delta. Servidor decide, cliente renderiza. Zero segunda
> verdade, zero entidade networkada, zero lixo.**

_Plano gerado com `vhub_arquiteto` + `vhub_guardiao_seguranca` + `vhub_guardiao_performance` · 2026-05-29 · Opus 4.8_
