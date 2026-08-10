# Skill — Derivador on-read cross-resource (dado bruto ≠ tradução derivada)

> **Validado em:** ADR #82 F2.1 (2026-08-08/09) — peças de engenharia (`vhub_custom`) →
> `sheet.eng` derivado (`vhub_vehcontrol`). Gates arquiteto+contrato+persistência+segurança: APROVAR.

## Quando usar

Um resource A é **dono do dado bruto** (persiste em `customization.*`, tem o catálogo declarativo). Um resource
B precisa **traduzir** esse dado numa grandeza derivada (física, score, preço, o que for) e **é dono da
tradução** (a semântica é do domínio dele). Os namespaces Lua são isolados por resource — B não enxerga o
catálogo de A. A tentação errada é **copiar** os dados para B (2ª fonte de verdade, L-04). O padrão certo:

## Receita (3 peças)

1. **A expõe o catálogo por export GATED** (não o estado por placa — o *catálogo estático*):
   ```lua
   -- em A/server/*.lua — devolve CÓPIA ESTÁTICA (nunca a referência mutável do catálogo, L-19)
   local _snapshot = nil
   local function build()
     if _snapshot then return _snapshot end
     local out = {}
     for _, item in ipairs(A.Catalog.ITEMS) do out[item.id] = { deltas = copyOf(item.deltas) } end
     _snapshot = out; return out
   end
   exports('getCatalogDeltas', function()
     if GetInvokingResource() ~= 'B' then return nil end   -- default-deny: só o dono da tradução
     return build()
   end)
   ```

2. **B tem o derivador PURO** em `shared/` (função pura, zero I/O — espelha tier_rules.lua):
   ```lua
   -- B/shared/derivador.lua — recebe (dadoBruto, catálogoDeltas, base) → grandeza derivada
   function D.derive(rawMap, deltasCat, base)
     -- itera rawMap READ-ONLY (é referência viva do cache VRAM do dono — NUNCA mutar)
     -- resolve cada id contra deltasCat (whitelist: id fora do catálogo = ignorado)
     -- clampa e devolve tabela FLAT de primitivos (pré-validada; o consumidor re-clampa)
   end
   ```

3. **B compõe on-read**, com cache read-through do catálogo (espelha o `buildIndex` do conce):
   ```lua
   local _deltas = nil
   local function deltas()
     if _deltas then return _deltas end
     local ok, raw = pcall(function() return exports.A:getCatalogDeltas() end)
     if not ok or type(raw) ~= 'table' or not next(raw) then return {} end  -- A ainda carregando
     _deltas = raw; return raw
   end
   -- na ficha derivada (sheetOf), ADITIVO, só quando há dado (evita payload vazio):
   if D.hasData(raw.parts) then sheet.derived = D.derive(raw.parts, deltas(), base) end
   ```

## Regras de ouro (pagas em gate)

1. **Derivado NUNCA persiste.** É recomposto a cada leitura, igual a score/tier/nitro. Comentário-guarda
   "derivado — nunca persistir" no ponto de composição. Se alguém gravar o derivado de volta → 2ª fonte (L-04).
2. **`getVehicleState`/getters do dono devolvem CÓPIA RASA** → `state.customization` e `.parts`/`.mods` são
   **referências VIVAS do cache VRAM**. O derivador itera com `pairs` **read-only**, acumula em tabela local
   nova, nunca escreve na tabela iterada (envenenaria o cache entre respawns). Ver [[conce-getvehiclestate-shallow-copy]].
3. **Remoção em mapa esparso (`MERGE_SPARSE`) = gravar `[id]=false`, e o LEITOR ignora falsy.** O merge aditivo
   nunca apaga chave; só sobrescreve. Ensinar o derivador: `installed(v) = v ~= nil and v ~= false` (senão a
   peça "removida" continua contando). Fix do leitor e a escrita do `false` vão no **mesmo commit**.
4. **Namespace de id casa entre escrita e leitura.** Se A grava `customization.parts[id]`, o `id` tem de ser a
   chave do **catálogo** (a mesma que `getCatalogDeltas` devolve) — não um id legado de outro mapa. Senão o
   derivador resolve nada → derivado sempre vazio (bug silencioso).
5. **Cache read-through com nil-sentinel**, não TTL: catálogo é estático no boot; se A reiniciar, o próximo
   `pcall` reconstrói. Sem thread, sem invalidação por placa.
6. **Sem ciclo de boot:** as chamadas cross-resource são runtime (`pcall(exports…)`), toleram o outro
   indisponível (retorna nil → derivado ausente → applier no-op). A dependência declarada fica só numa direção.

## Ativação segura (quando o derivado vira efeito)

O derivado só produz efeito atrás de flag (`Config.applyPerEntity` no F2.1), default `false` = ZERO regressão.
Ligar só após smoke in-game. O applier client (se houver) é **escritor único** da grandeza aplicada e
**restaura a base ao sair** (LEFT_VEHICLE), com overlays efêmeros (ex.: nitro) somando por cima e restaurando
via evento, nunca hardcode do valor neutro.

## Teste offline (obrigatório antes do smoke)

Função pura → teste `tools/test_*.lua` com `dofile` do derivador + do catálogo real (ambos módulos puros):
idempotência (2 chamadas idênticas), clamp (empilhar não estoura teto), remoção-por-`false` zera, whitelist
(id fora do catálogo = sem efeito), troca (replaces reflete só a nova). Referência: `tools/test_engineering.lua`
(15 asserts). Rodar junto o teste do módulo puro vizinho (ex.: `test_tier_rules` 594) p/ garantir não-regressão.
