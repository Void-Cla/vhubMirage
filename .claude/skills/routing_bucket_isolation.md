# Skill — Isolamento por Routing Bucket (sessão/dimensão)

> Padrão validado na Decisão #35 (2026-06-27). Owner de referência:
> `resources/[SCRIPTS]/vhub_player_state/server.lua`.

## Quando usar
Isolar jogadores em "dimensões" de rede: entrada/loading, test-drive, arena PVP,
replay, qualquer atividade que não pode colidir/interferir no mundo principal.

## Verdades de plataforma (não prometa o impossível)
- `SetPlayerRoutingBucket(src, n)` isola **apenas ENTIDADES DE REDE** (players,
  peds de rede, veículos, objetos, pickups). **A geometria do mapa SEMPRE carrega**
  no cliente — bucket não dá "tela preta". Para tela limpa, use hold/câmera no HAL.
- `SetRoutingBucketPopulationEnabled(bucketId, false)` — desliga tráfego/peds do
  bucket (GLOBAL por bucket, setar 1× no `onResourceStart`, não por-player).
- `SetRoutingBucketEntityLockdownMode(bucketId, "strict")` — modos: `strict` |
  `relaxed` | `inactive`. `strict` impede o cliente de criar entidade de rede.
- Todas são **server-side**.

## Convenção vHub
- **999** = entrada isolada (sem população + `strict`).
- **1** = mundo principal.
- **2** = atividade isolada (test-drive/arena/replay).

## Regras de ouro (aprendidas em revisão)
1. **Escritor único (L-16).** UM resource toca `SetPlayerRoutingBucket`. Aqui é o
   spawn owner (`vhub_player_state`), porque bucket é o "onde" do spawn elevado a
   dimensão. NÃO colocar no core (fura a fronteira de camada + L-11 frozen).
2. **Bucket NÃO é fonte de verdade (L-04).** É visibilidade/sync de rede. Não toca
   dado persistido → **não há vetor de dupe por bucket** (dupe é problema da TX do
   core, ver readme do core §17). Não reimplemente persistência "por causa do bucket".
3. **Cuidado com o REPLAY-GUARD.** O core re-dispara `vHub:characterLoad`/
   `vHub:playerSpawn` para TODAS as sessões em `onResourceStart` de qualquer
   resource. Se você setar 999 incondicionalmente em `characterLoad`, um restart de
   resource joga jogadores que JÁ estão no mundo de volta ao 999 e os prende.
   **Gateie a entrada no 999 por `first_spawn == true`** (replay vem `false`) e/ou
   atrás do replay-guard que já retorna antes.
4. **Saída do 999 ANTES de soltar o ped.** `SetPlayerRoutingBucket(src, 1)` no
   ponto único de release (com o ped ainda em hold), nunca depois do cliente já
   estar solto — esconde o re-stream e evita pop-in e "preso no 999 vazio".
5. **Idempotência.** Só troque quando difere (`GetPlayerRoutingBucket`) para evitar
   re-stream à toa.

## Export para terceiros (atividade) — default-deny
```lua
local BUCKET_TRUSTED = {}  -- vazio = só interno. NÃO popular sem ownership (L-07).
local function invokerOK()
  local who = GetInvokingResource()
  if not who or who == GetCurrentResourceName() then return true end
  return BUCKET_TRUSTED[who] == true
end

exports("setActivityBucket", function(src, n)
  if not invokerOK() then return false end          -- só resources confiáveis
  src = tonumber(src); n = tonumber(n)
  if not src or src <= 0 then return false end
  if n ~= 1 and n ~= 2 then return false end          -- NUNCA 999 (anti-grief)
  if not (_pronto and _vHub.Auth:getUser(src)) then return false end  -- alvo online
  setBucket(src, n); return true
end)
```
- `n ∈ {1,2}` apenas — expor 999 a terceiros permitiria prender/ocultar player.
- Exigir alvo online fecha src-spoof/offline mesmo vindo de resource trusted.
- Nenhum `RegisterNetEvent` deve tocar bucket — cliente nunca decide dimensão (L-01/L-02).

## Checklist de runtime (antes de confiar)
1º login → 999 sem população → escolhe spawn → mundo populado (bucket 1).
AFK no selector → timeout libera no mundo. `usar_selector=false` → spawna direto.
**Restart de outro resource com player online → player NÃO volta ao 999.**
Morte → respawn normal. `resmon` do owner estável.
