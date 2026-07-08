# Skill — Migração de interação: proximidade+[E] → `vhub_target` (olho)

**Validada em:** decisão #57 (2026-07-08, `vhub_money` banco/ATM — primeiro consumidor real do `vhub_target`).
**Quando aplicar:** um resource `[SCRIPTS]` hoje detecta proximidade por thread + hint `[E]` +
`DrawMarker` e quer trocar o gatilho pelo `vhub_target`. Padrão só para **gatilho de UI**, nunca
para verdade crítica.

---

## Princípio

O `vhub_target` (#56) é **L2/L3 client-side puro**: dá o *affordance* (highlight ao mirar) e chama
um `onSelect`. Ele **não** decide verdade. Portanto a migração é **neutra em segurança** DESDE QUE o
servidor já revalide a condição (raio/posse/permissão) no handler que o `onSelect` dispara. Se o server
já valida → o gate de segurança é dispensável (foi o caso do #57). Se NÃO valida → a migração é
proibida até o server passar a validar.

---

## Receita (box zone por coordenada de lista curada — "opção A")

Use quando os pontos de interação vêm de uma **lista de coordenadas curada** (ATMs, balcões, etc.)
que o **servidor já usa** para revalidar. A MESMA lista vira as box zones no client — 1 fonte, N
consumidores (L-04: sem 2ª fonte de verdade).

```lua
-- client/zones.lua — interação via vhub_target (olho), não mais [E] por proximidade
---@diagnostic disable: undefined-global, lowercase-global

-- não abre de dentro de um veículo (bloqueio client leve; NÃO é verdade crítica)
local function onFoot()
  return not IsPedInAnyVehicle(PlayerPedId(), false)
end

local function openStation(mode)
  TriggerServerEvent('meu_resource:open', { mode = mode })   -- server revalida o raio/posse
end

CreateThread(function()
  -- MESMA lista que o server usa p/ revalidar (não addModel de props)
  for i, a in ipairs(MinhaListaCurada) do
    exports.vhub_target:addBoxZone({
      coords  = vec3(a[1], a[2], a[3]),          -- vec3 é uso LOCAL (L-19); não cruza fronteira
      size    = vec3(1.2, 1.2, 2.0),
      options = {
        {
          name        = ('meu_resource:x_%d'):format(i),  -- nome único por zona
          label       = 'Interagir',
          icon        = 'card',                             -- chave do icons.js do target
          distance    = 1.5,
          canInteract = onFoot,
          onSelect    = function() openStation('atm') end,  -- closure by-ref (mesmo runtime)
        },
      },
    })
  end
end)
```

## Regras de ouro (checadas no #57)

1. **Server intocado / server dispõe.** O `onSelect` só emite `TriggerServerEvent`; o server
   revalida raio/posse contra a MESMA lista antes de abrir. Payload carrega **primitivo** (`mode`
   string), nunca `vec3` (L-19 fronteira). Client é gatilho de UI.
2. **1 fonte de verdade.** A lista curada é autoridade server-side + (opcional) blips + box zones
   client. Não duplicar coords numa 2ª tabela (L-04).
3. **`canInteract = onFoot`** para interações que não fazem sentido de dentro do carro. É bloqueio
   de conveniência client — a verdade continua no server.
4. **`vec3`/closures são LOCAIS.** `addBoxZone` é export client→client no MESMO runtime: `vec3` é
   consumido em aritmética e `canInteract`/`onSelect` passam por referência (msgpack NÃO serializa
   closure nem vetor). Não viola L-19.
5. **Ciclo de vida automático.** `addBoxZone` tagueia `data.resource = GetInvokingResource()`; o
   `onClientResourceStop` do `vhub_target` (`client/api.lua`) remove as zonas do seu resource ao
   parar. Registrar 1x no boot → sem thread, sem órfão (L-07/L-15).
6. **`dependency 'vhub_target'`** no `fxmanifest.lua` + `ensure vhub_target` ANTES do seu resource
   em `config/resources.cfg` (ordem de load).
7. **Ícone existe.** A `icon` deve resolver no `web/js/icons.js` do target (chave direta ou alias
   `fa-*`); ícone desconhecido cai no fallback `dot` (sem 404). Se faltar, adicionar SVG local
   (aditivo, beneficia consumidores futuros) — nunca CDN (A-10).

## Deletar é entrega (L-15)

A migração REMOVE: threads de proximidade (fria + quente), `draw_hint`/`DrawMarker`, comando `/…`
de abertura por proximidade, e **as chaves de config órfãs** que só serviam ao fluxo antigo
(`CMD_*`, `KEY_*`, `*_INTERACT_RADIUS` do client). Conferir com grep que nenhuma sobra referenciada.
> Pegadinha do #57: `INTERACT_RADIUS` ficou órfão em `config.lua` (limpeza incompleta) — o client
> não lê mais e o server hardcoda seu próprio raio. Varrer TODAS as chaves do fluxo antigo.

## Ganho de performance a registrar

`N` threads permanentes/player → **0**. O custo de interação migra para o scan do target
(`O(nZonas)` `contains` **só com o olho aberto**; olho fechado = 0). Registrar no contexto.md.

## Testes runtime faltantes (owner confirma in-game)

- Olho abre o painel de cada tipo de ponto.
- `canInteract` recusa de dentro do veículo.
- Blips (se houver) intactos.
- Fora do raio server → server recusa mesmo com o olho tendo aberto.
