# vHub Mirage 1

Framework FiveM GTARP server-authoritative, Lua 5.4. Foco: cidade de corrida.
**`compat: none`** — shim vRP removido em Frozen v1.0 (2026-05-22, decisão #6); resources usam exclusivamente `exports.vhub:*`.

## Leitura obrigatória antes de qualquer ação (nesta ordem — economia de tokens)

1. **Este `AGENTS.md`** — leis L-01..L-19 (fonte única), Registro de Ownership, Orçamentos, **Fase Atual**
2. `.Codex/contexto.md` — memória institucional (SOMENTE o índice + as seções citadas pela tarefa)
3. `.Codex/AGENTS.md` — como os agentes operam (fluxo, formato de veredito, economia)
4. `.Codex/skills/*.md` — padrões JÁ validados (aplicar, não reinventar)
5. `.Codex/plano_core_v2/frozen_core_2.md` — **plano de descongelamento** do CORE (só quando a tarefa toca o CORE ou veículos)

> Hierarquia de verdade: **código/manifests atuais → AGENTS.md → contexto.md → plano_core_v2/**.
> Divergência doc×código: prevalece o código; registrar o risco.

---

## ⚠️ FASE ATUAL — Descongelamento do CORE (v1.0 → v2.0)

> O time deixou de ser **guardião do freeze** e passou a ser **guia da migração**. A missão
> não é mais "não tocar no CORE"; é **mover para o CORE o que é dele, sob gate**, sem gambiarra.

> **STATUS 2026-07-10 — FASE 1 APLICADA e VALIDADA EM DEV; fuel da FASE 2 cortado
> para o CORE** (decisões/ADRs #37–#50 e #61–#65 — mesma numeração no `contexto.md` e no
> `.claude/plano_core_v2/WORKLOG_CORE_V2.md`; **próximo livre = #66**): CORE v2.0.0-alpha.3 —
> handlers veiculares reanimados com gate físico (boot dev limpo 2026-07-03),
> `commitVehicleState`/`getVehicleState`(cópia)/`vh_audit`, VRAM eviction TTL, batch com cap
> de retry, registro efêmero anti-FK, despawn server-side (zero broadcast `-1`), dual-write
> de fuel conce→CORE concluído. Fuel autoritativo ativo (`vhub_core_fuel=1`). Trust populado
> via `setr vhub_trusted_resources` no `config/server.cfg`. Orientação rápida:
> `.claude/skills/mapa_core_v2.md`. **Checklist PARTE V (pentest/stress) pendente — bloqueia produção.**

**O que mudou de intenção:**
- O `CORE FROZEN v1.0` está sendo **descongelado de forma faseada** rumo ao **v2.0**. Tocar
  `resources/[CORE]/vhub/**` deixou de ser proibido e passou a ser **gated**: exige (1) gate do
  `vhub_arquiteto` + `vhub_guardiao_revisao`, (2) uma **ADR numerada**, (3) bump de versão. Sem os três → REPROVAR.
- **Tudo que é do CORE volta para o CORE.** Estado de veículo, posse, dinheiro, permissão — verdade
  crítica mora no kernel. Recursos em `[SCRIPTS]/` **não guardam verdade paralela**; eles pedem ao CORE.
- **`[SCRIPTS]` só criam regra de negócio pedindo permissão ao CORE.** Leem por `exports.<core>:get*()`
  e escrevem por **contrato de commit** (`commitVehicleState`, `spawnAt`, …). Nunca `set*Data` fora do CORE (L-13).
- **Export-first, total suporte.** Toda função pública do CORE (e de cada recurso) é exposta via
  `exports` — gated default-deny (`_invoker_allowed()` + `GetInvokingResource()`) — para que qualquer
  script acople regra nova sem reimplementar. Recurso sem export é redundante ou morto (R3).

**Regras de ouro do v2.0** (o detalhe e o roteiro FASE 0→8 estão em `plano_core_v2/frozen_core_2.md`):

| # | Regra de ouro | # | Regra de ouro |
|---|---------------|---|---------------|
| R1 | Server-side por padrão (client propõe, server dispõe) | R9 | Nomes de evento só em `shared/events.lua` |
| R3 | Tudo tem export (gated) | R10 | Zero `print()` — usar `vHub.Logger` |
| R4 | Um dono por dado (escritor único) | R12 | Toda mutação audita (source/actor/ts/before/after) |
| R5 | Estado contínuo = State Bag; evento discreto = `TriggerClientEvent` (nunca `-1` p/ estado) | R13 | Anti-cheat em 3 camadas (client+server+audit) |
| R6 | Replay-safe (handler institucional tem replay-guard) | R14 | Idempotência (retry = mesmo estado) |
| R7 | Fronteira externa envolta em `pcall` (falha isolada) | R15 | Contrato quebra só com deprecation path + migration |
| R8 | Loop declara budget (Hz/ms); sem laço infinito sem sleep | A1..A5 | CORE mínimo/estável; domínios auto-contidos; delegação e contratos explícitos; falha isolada |

**Diretriz permanente de operação (qualidade · eficiência · economia):**
1. Opere no mais alto nível de engenharia — arquitetura **separada por responsabilidade**, semântica correta, segurança server-authoritative.
2. **Honestidade técnica precede tudo:** alto nível ≠ over-engineering. Não criar 2ª fonte de verdade, não inflar camada sem ganho mensurável, não fabricar achado. Na dúvida entre conveniente e seguro → **seguro**.
3. **Economia é lei:** menor evidência suficiente para o veredito; nunca reenviar histórico; deletar é entrega (L-15).

## Estrutura do projeto

```
resources/[CORE]/vhub/             ← framework principal
  shared/  server/  client/  sql/
  bootstrap.lua  base.lua  fxmanifest.lua
resources/[SCRIPTS]/vhub_*/        ← recursos do jogo (usam exports do core)
resources/[CORE]/oxmysql/          ← driver MySQL upstream (não alterar)
resources/[CORE]/vhub_oxmysql/     ← adaptador vHub para oxmysql
resources/[TOOLS]/vhub_testrunner/ ← runner de testes server-side
tools/                             ← scripts PS1 de manutenção SQL
metas/                             ← roadmap, decisões técnicas, referência natives
.Codex/
  contexto.md    AGENTS.md         ← memória institucional e protocolo
  agents/*.md                      ← agentes especializados (Codex nativo)
```

## Leis imutáveis (L-01 a L-12)

| Lei | Regra |
|-----|-------|
| L-01 | Servidor é autoritativo para toda verdade crítica |
| L-02 | Cliente: UI/HUD/física efêmera. Servidor valida e persiste |
| L-03 | Fallback de dado cliente = rollback para último estado válido do servidor |
| L-04 | Sem segunda fonte de verdade; sem ownership duplicado |
| L-05 | Native FiveM antes de infraestrutura custom |
| L-06 | Sem loop/polling — preferir evento, State Bag ou timer mínimo |
| L-07 | Sem novo resource/módulo sem ownership e lifecycle explícitos |
| L-08 | Código em inglês; comentários, saídas e `lang.*` em PT-BR |
| L-09 | Funções curtas, sem redundância, máximo reaproveitamento sem acoplamento rígido |
| L-10 | Toda função pública comentada com uma linha objetiva em PT-BR |
| L-11 | **REVOGADA** (Frozen v1.0, 2026-05-22): `server/compat.lua` foi removido — `compat: none`. Número preservado para não quebrar referências |
| L-12 | Transações SQL são atômicas e exclusivamente server-side |

## Leis estendidas (pós-auditoria / pós-freeze)

> Consolidadas aqui (fonte única). Antes viviam só em `plano_core_v2/01_reference_docs.md` e nos agentes — drift real corrigido.

| Lei | Regra |
|-----|-------|
| L-13 | **Escritor único de persistência.** `set*Data` (`setVData/setUData/setCData/setGData`) só dentro de `[CORE]/vhub`. Terceiros escrevem por **contrato de commit** (`commitVehicleState`, …), nunca direto. |
| L-14 | **Não mutar internos via `getVHub()`/`getVehicle()`.** Leitura de estado por `getVehicleState`/export; escrita por contrato. `getVHub()` para escrita = repair-hack proibido. |
| L-15 | **Código morto zero.** Todo `.lua` referenciado no `fxmanifest.lua` no mesmo commit; arquivo órfão/módulo-fantasma proibido. **Deletar é entrega.** |
| L-16 | **Escritor único de entidade/spawn.** `SetPlayerModel`/`SetEntityCoords` de spawn fora do owner registrado (`vhub_player_state`) é proibido; a UI devolve coordenada por export do owner. |
| L-17 | **Replay-guard.** Handlers institucionais (`vHub:playerSpawn`, `vHub:characterLoad`) toleram re-disparo em `onResourceStart` sem duplicar efeito nem prender o player. |
| L-18 | **Orçamentos = contrato.** Toda thread/loop declara budget (Hz/ms); estourar sem renegociação registrada = REPROVAR. Custo por player **O(1)**. |
| L-19 | **Coordenadas como tipos vetoriais nativos.** `vec3(x,y,z)` para todo ponto sem orientação (blip, zona, marker, raio). `vec4(x,y,z,w)` (w=heading) **somente** para posição de spawn de veículo/ped (`test_spawn`, spawn de garagem, offset de saída). Nunca `vec4` para blip/zona/marker. **Fronteira:** `vec3`/`vec4` são de uso LOCAL — NÃO cruzam `TriggerClientEvent`/`TriggerServerEvent`/`exports`/`SendNUIMessage` (msgpack entrega o vetor como tabela indexada `{1,2,3}`; `json.encode(vec)` vira `{}`). Todo payload que cruza fronteira carrega coord como primitivo `{x=,y=,z=[,h=]}`; o consumidor reconstrói o vetor no ponto de uso. Adoção incremental: aplica-se a código novo e a config tocada (zonas de veículo migradas na decisão #25). |

## Condições de parada obrigatória

Parar e reduzir escopo imediatamente ao detectar:

- Segunda fonte de verdade para o mesmo dado
- Novo resource/módulo sem ownership e lifecycle documentados
- Cliente decidindo verdade crítica sem validação server-side
- SQL inline fora de `state.lua`/`sql.lua` (CORE only)
- Export sensível sem `_invoker_allowed()`
- Loop sem condição de saída explícita

## Sistema multi-agente

Agentes definidos em `.Codex/agents/*.md` — formato nativo Codex, invocáveis via `Agent` tool.

### Quando invocar cada agente

| Agente | Invocar quando |
|--------|----------------|
| `vhub_arquiteto` | Mudança estrutural, novo módulo/resource, dúvida de ownership ou placement |
| `vhub_guardiao_contrato` | Tocar API pública, exports, schema, `shared/events.lua`, `server/compat.lua` |
| `vhub_guardiao_seguranca` | Tocar auth, permissão, evento cliente, spawn, ban, payload |
| `vhub_guardiao_natives` | Tocar entity, ped, netid, State Bag, spawn, bucket, vehicle |
| `vhub_guardiao_performance` | Tocar thread, loop, batch SQL, flush, serialização |
| `vhub_guardiao_simplicidade` | Criar módulo, helper, camada nova, ou qualquer refactor |
| `vhub_guardiao_designer` | Tocar NUI, CEF, HUD, `client/`, `SendNUIMessage`, `RegisterNUICallback` — identidade visual + CEF |
| `vhub_guardiao_runtime` | Tocar engine NUI (`web/runtime/*`), lifecycle de módulo, store/eventbus/router, native bridge, lazy load |
| `vhub_guardiao_revisao` | O guardiao da revisao morreu, agora todos os agentes escrevem em contexto de forma resumida mas cirugica sobre oque acabou de fazer e onde mexeu. |
| `vhub_designer` | Proposta ou redesign de NUI/interface componentizada |

### Fluxo preferencial multi-agente

```
1. Ler .Codex/contexto.md
2. Mapear arquivos tocados
3. vhub_arquiteto → ownership, placement, fase
4. Guardiões relevantes em PARALELO (somente os pertinentes ao risco — ver "Gate mínimo" em AGENTS.md)
5. Worker executa SOMENTE após todos aprovarem
6. vhub_guardiao_revisao → gate final + atualiza contexto.md se necessário
```

### Economia de tokens (obrigatório)

- Enviar ao agente: objetivo + restrições + diff + arquivos tocados (nunca histórico completo)
- Agente para na menor evidência suficiente para o veredito
- `SEM ACHADOS CRÍTICOS` quando não houver problema real — nunca fabricar achados
- Gate `vhub_guardiao_revisao` somente quando diff tem código relevante

## Padrões obrigatórios de código

### Módulo server-side mínimo (Lua 5.4)

```lua
-- módulo.lua — <descrição em PT-BR>
local M = {}; M.__index = M; vHub.NomeModulo = M

function M:init(cfg, driver) ... end

return M
```

### Regras de escrita

- OOP via `vHub.class()` para domínios com estado; tabela simples para utilitários puros
- `vHub.assertThread()` obrigatório em toda função pública com `Citizen.Await`
- `Citizen.CreateThread` apenas para operações assíncronas reais; destruir ao fim
- Sem `while true do` sem condição de saída explícita
- Sem `print()` fora de `shared/logger.lua` e `bootstrap.lua`
- Sem SQL inline — CORE usa `S:prepare()` + `S:query()`; resources externos usam `exports.oxmysql` diretamente
- Exports sensíveis: `_invoker_allowed()` + `GetInvokingResource()`
- **Export-first (API nativa preventiva, decisão do dono 2026-06-27):** todo resource expõe `exports(...)` das suas ações públicas **mesmo sem consumidor atual** — quando a integração futura vier, o export já existe pronto (sem gambiarra/refactor). **Obrigatoriamente gated default-deny** (`_invoker_allowed()`/`invokerOK` + `GetInvokingResource()` + validação de args + alvo online). Assim NÃO conta como dead code (L-15) — é superfície de API deliberada; ownership ainda exigido (L-07). Referência: `setActivityBucket` em `vhub_player_state` (decisão #35).

### Ordem de carregamento em `server/init.lua` (não alterar sem gate do arquiteto)

```
kernel → state → sql → notify → auth → vehicle → security → boot → exports
```

### Ordem global (fxmanifest)

```
shared/config.lua → shared/events.lua → shared/utils.lua → shared/logger.lua
bootstrap.lua → base.lua → server/init.lua
client/bootstrap.lua → client/vehicle.lua → client/modules/*
```

## Arquitetura componentizada (camadas e ownership)

O vHub Mirage opera em **quatro camadas** com ownership estrito. Toda mudança respeita a fronteira da camada à qual pertence. Esta seção COMPLEMENTA as leis L-01..L-12 — não as substitui.

### Camadas e responsabilidades

| Camada | Tecnologia | Responsabilidade | NUNCA faz |
|--------|------------|------------------|-----------|
| **L1 — Kernel** | Lua server | Verdade autoritativa: SQL, dinheiro, inventário, permissão, ban, anti-cheat, State Bag *writer* | UI, render, animação, fluxo visual |
| **L2 — HAL** | Lua client | Hardware Abstraction Layer: natives, ped, veículo, câmera, controles, raycast, markers, sync entidade | Decidir verdade crítica, regras de negócio |
| **L3 — Runtime** | JS/HTML/CSS | Application runtime: UI, HUD, menus, animação, UX, transições, áudio UI | Validar dinheiro, permissão, cálculo crítico |
| **L4 — Componente** | JS módulo isolado | Módulo isolado com lifecycle próprio (lobby, editor, race, hud, garage…) | Acessar DOM/estado de outro componente sem store/eventbus |

### Estrutura recomendada por resource (a partir de novos projetos)

```
vhub_<dominio>/
├── core/
│   ├── server/       ← L1 — kernel authoritative (SQL, validação, persistência)
│   ├── client/       ← L2 — HAL (bridge natives, ped/veículo/câmera)
│   └── shared/       ← contratos, eventos, utils puros
│
├── web/
│   ├── runtime/      ← L3 — engine (router, state, eventbus, native bridge, animation, sound)
│   ├── modules/      ← L4 — componentes (lobby/, editor/, hud/, race/, garage/…)
│   ├── shared/       ← componentes comuns, layouts, ícones, services, stores compartilhadas
│   └── bootstrap/    ← entrada da aplicação, registro de módulos
│
├── assets/           ← imagens, sons, fontes locais
├── config/           ← config estática carregada server/client
└── fxmanifest.lua
```

### Anatomia de um componente em `web/modules/<nome>/`

```
<nome>/
├── index.html        ← markup do módulo (sem CSS/JS inline)
├── style.css         ← escopado por seletor raiz `.mod-<nome>`
├── app.js            ← lifecycle (onInit / onMount / onShow / onHide / onDestroy)
├── store.js          ← slice de estado isolado do módulo
├── events.js         ← registros de eventbus do módulo
├── components/       ← subcomponentes (átomo / molécula)
├── services/         ← chamadas ao native bridge / TriggerServerEvent
└── views/            ← telas / sub-rotas do módulo
```

---

## Engine de runtime (web/runtime)

Mini framework próprio — **sem React/Vue/webpack**. Convenções obrigatórias:

| API | Responsabilidade |
|-----|------------------|
| `vhub.createModule(spec)`           | Registra módulo com lifecycle padronizado |
| `vhub.mount(name)` / `unmount(name)` | Insere/remove módulo do DOM com cleanup garantido |
| `vhub.emit(event, payload)`         | Publica evento no event bus central |
| `vhub.listen(event, fn)`            | Inscreve handler no event bus (retorna `off()`) |
| `vhub.store(domain)`                | Slice global tipado (player, race, lobby, vehicle, settings) |
| `vhub.router.navigate(name, params)` | Roteamento entre telas — substitui `display:none` manual |
| `vhub.native.<api>.<fn>(args)`      | Chamada nativa via bridge centralizado (throttled, validado) |

### Lifecycle obrigatório por componente

```js
vhub.createModule('garage', {

    // ============================================================
    // INIT — registrar listeners, criar slice de store
    // ============================================================
    onInit() {
        // ...
    },

    // ============================================================
    // MOUNT — DOM inserido; query selectors, bind handlers
    // ============================================================
    onMount() {
        // ...
    },

    // ============================================================
    // SHOW / HIDE — visibilidade; animações pausam quando hide
    // ============================================================
    onShow() { /* ... */ },
    onHide() { /* ... */ },

    // ============================================================
    // DESTROY — cleanup OBRIGATÓRIO (A-07)
    // ============================================================
    onDestroy() {
        // cancelar RAF, clearInterval, removeEventListener, observer.disconnect
    },

});
```

### Native bridge — fluxo canônico

```lua
-- core/client/native_bridge.lua — exposição central de natives à NUI

RegisterNUICallback('native', function(req, cb)

    local api = NativeRegistry[req.api]
    if not api then return cb({ ok = false, err = 'unknown_api' }) end

    cb({ ok = true, data = api(req.args) })

end)
```

```js
// web/runtime/native.js — wrappers tipados, throttling e cache leve

vhub.native.vehicle.getSpeed = () => bridge('vehicle.getSpeed');
vhub.native.camera.shake    = (intensity) => bridge('camera.shake', { intensity });
```

JS **nunca** acumula `fetch('https://<resource>/<endpoint>')` em hot path — toda native passa por `vhub.native.*` que centraliza throttling, batching e validação.

---

## Leis de componentização (A-01 a A-10)

Complementam L-01..L-12; aplicam-se a NUI/runtime/cliente-JS. Não sobrescrevem nenhuma lei imutável.

| Lei | Regra |
|-----|-------|
| **A-01** | Separação de camada — Lua kernel não renderiza UI; JS não decide regra de negócio crítica |
| **A-02** | Todo módulo NUI novo nasce com lifecycle padronizado (onInit / onMount / onShow / onHide / onDestroy) |
| **A-03** | Comunicação inter-módulo passa pelo event bus; sem acesso direto a DOM/estado de outro módulo |
| **A-04** | Estado por domínio em `store.<domain>` — sem segunda fonte de verdade dentro da NUI |
| **A-05** | Lazy load — módulo só é montado quando navegado; `unmount` libera memória de fato |
| **A-06** | Native bridge centralizado — JS não acumula `fetch` espalhado nem chama native fora de `vhub.native.*` |
| **A-07** | Cleanup obrigatório no `onDestroy`: `cancelAnimationFrame`, `clearInterval`, `removeEventListener`, `observer.disconnect` |
| **A-08** | `SendNUIMessage` em hot path usa batching/delta sync — nunca 60fps de payload bruto |
| **A-09** | **CEF transparente.** `html, body { background: transparent }` SEMPRE. `backdrop-filter` é PROIBIDO em HUD/overlay direto sobre o jogo — no CEF do FiveM ele só desfoca o que está dentro da página e renderiza um **bloco preto sólido** sobre o mundo GTA. Vidro nesses casos é SIMULADO com fundo translúcido em camadas (opacidade do piso ≈0.78–0.86). `backdrop-filter` só é permitido quando há uma camada de fundo OPACA (`#vhub-bg` com `bg.png`) atrás do painel. |
| **A-10** | **Assets declarados.** Todo arquivo que a NUI carrega (`<script>`, `<link>`, imagem, fonte) DEVE constar no `files{}` do `fxmanifest.lua` — omitir = 404 no CEF = a NUI não monta. Sem CDN externo (Google Fonts, FontAwesome, cdnjs): offline falha; usar fonte do sistema/embarcada + ícone SVG/unicode. |

### Condições adicionais de parada obrigatória (NUI)

- Componente sem `onDestroy` definido enquanto cria listener/RAF/interval
- Dois módulos lendo/escrevendo o mesmo slice de store sem ownership declarado
- `fetch` direto a endpoint de resource fora de `vhub.native.*` ou `services/`
- Animação rodando com NUI fechada (idle > 0 em resmon)
- `backdrop-filter` em HUD/overlay sobre o jogo, ou `html`/`body` com fundo opaco (A-09)
- Asset carregado pela NUI ausente do `files{}` do fxmanifest, ou dependência de CDN externo (A-10)

---

## Estilo humano de código (legibilidade primeiro)

Além de separar **arquivos por componente e responsabilidade**, separar **contextos lógicos DENTRO do arquivo** com banners e respiração visual. Vale para Lua, JS, CSS e SQL.

### Padrão Lua

```lua
-- garage.lua — gerenciamento de garagem (server-authoritative)

local M = {}; M.__index = M; vHub.Garage = M


-- ============================================================
-- LIFECYCLE
-- ============================================================

-- inicializa módulo com config validada e driver SQL pronto
function M:init(cfg, driver)
    -- ...
end


-- ============================================================
-- QUERIES (read-only)
-- ============================================================

-- retorna lista de veículos do player (sem mutação)
function M:listPlayerVehicles(playerId)
    -- ...
end


-- ============================================================
-- MUTATIONS (validadas, atômicas, server-side)
-- ============================================================

-- guarda veículo na garagem do player (transação atômica)
function M:storeVehicle(playerId, plate)
    -- ...
end


return M
```

### Padrão JS

```js
// app.js — runtime do módulo Garage


// ============================================================
// STATE
// ============================================================

const state = vhub.store('garage');


// ============================================================
// LIFECYCLE
// ============================================================

vhub.createModule('garage', {
    onInit()    { /* ... */ },
    onMount()   { /* ... */ },
    onDestroy() { /* ... */ },
});


// ============================================================
// HANDLERS
// ============================================================

function onStoreClick(event) {
    // ...
}
```

### Regras de formatação

- Banners `=` (60 colunas) separam grandes contextos; cabeçalho em **CAIXA ALTA**.
- **Duas linhas em branco antes** de cada banner; **uma linha em branco depois**.
- Função pública: **uma linha** de comentário em PT-BR objetiva imediatamente acima.
- Bloco de validação separado por linha em branco do bloco de execução.
- Imports/requires no topo, agrupados por origem (kernel → utils → services → views).
- Largura de linha alvo: **100 colunas**; máximo absoluto: 120.

---

## Ferramentas de teste

- `resources/[TOOLS]/vhub_testrunner/` — runner server-side (comando: `vhub_run_tests`)
- `tools/limpardadossql.ps1` / `tools/fix_vhub_db.ps1` — manutenção de dados SQL
- **ATENÇÃO**: testrunner executa queries reais → usar APENAS em ambiente de teste

---

## Roteamento de modelos (obrigatório)

### Sessão interativa (padrão)

O model padrão é `opusplan` — Opus 4.8 em PLAN MODE, Sonnet 4.6 em EXECUTE MODE.

```bash
# Padrão recomendado (já configurado no settings.json)
# Plan mode → Opus 4.8 (raciocínio profundo)
# Execute mode → Sonnet 4.6 (rápido, econômico)
```

### Quando mudar o modelo durante a sessão

| Contexto | Comando | Motivo |
|---------|---------|--------|
| Auditoria de segurança / bug crítico | `/model opus` + `/effort xhigh` | Máxima precisão, sem compromisso |
| Implementação conhecida | `/model sonnet` | Rápido, tokens mínimos |
| Revisão simples / busca de pattern | `/model sonnet` + `/effort low` | Mínimo de custo |
| Design de nova feature complexa | `/model opus` + `/effort high` | Raciocínio estrutural |
| Sessão longa com codebase grande | `/model opus[1m]` | Contexto 1M tokens |

### Mapa de modelos por agente

| Agente | Model | Effort | Por que |
|--------|-------|--------|---------|
| `vhub_arquiteto` | Opus 4.7 | xhigh | Decisões estruturais requerem raciocínio profundo. 4.7 tem xhigh como padrão |
| `vhub_guardiao_revisao` | Opus 4.8 | xhigh | Gate final: máxima precisão, zero tolerância a erro |
| `vhub_guardiao_seguranca` | Opus 4.8 | high | Zero-trust: precisão crítica, 4.8 mais confiável em edge cases |
| `vhub_guardiao_persistencia` | Opus 4.8 | high | L-13: histórico real de perda de dados (bind `@dkey`, 8 call-sites externos) — sem corte |
| `vhub_designer` | Opus 4.7 | high | Design técnico + criativo requer capacidade acima da média |
| `vhub_guardiao_natives` | Sonnet 4.6 | high | Autoridade de entidade/spawn é sutil (L-16) — mantido em high |
| `vhub_guardiao_contrato` | Sonnet 4.6 | **medium** (2026-07-08, ↓ de high) | Pattern matching contra contratos conhecidos — mecânico o bastante para medium |
| `vhub_guardiao_performance` | Sonnet 4.6 | **medium** (2026-07-08, ↓ de high) | Checagem contra tabela de Orçamentos (contrato fixo), não raciocínio aberto |
| `vhub_guardiao_designer` | Sonnet 4.6 | **medium** (2026-07-08, ↓ de high) | Checklist de identidade visual (A-09/A-10), fixo |
| `vhub_guardiao_runtime` | Sonnet 4.6 | **medium** (2026-07-08, ↓ de high) | Patterns arquiteturais JS (A-01..A-08), fixo |
| `vhub_guardiao_simplicidade` | **Haiku 4.5** (2026-07-08, ↓ de Sonnet) | medium | Check mais mecânico (L-15 dead code/duplicação) — não precisa de Sonnet |

> Downgrades de 2026-07-08: motivados por auditoria de custo de tokens (subagentes = 83% do
> uso do mês). Critério aplicado: guardiões com checklist/tabela fixa → `medium`; o mais
> mecânico (`simplicidade`) → Haiku. **Não** tocado: `persistencia`, `seguranca`, `revisao`,
> `arquiteto`, `natives` — histórico de risco real (perda de dado, spawn, gate final) não
> negocia custo. Se algum guardião rebaixado começar a deixar passar problema real, suba de
> volta primeiro para ele antes de qualquer outro ajuste.

### Economia de tokens na prática

- **Guardiões em paralelo** com Sonnet: ~60% mais barato que todos com Opus
- **opusplan** para sessão interativa: Opus só durante planejamento (5-10% do tempo)
- **ultrathink** no prompt: para raciocínio extra profundo sem mudar o modelo de sessão
- Incluir `contexto.md` no prompt do agente: evita reenviar histórico completo

### Keyword ultrathink

Inclua `ultrathink` no prompt para solicitar raciocínio mais profundo naquele turno sem mudar o modelo:

```
# Exemplo — análise de regressão profunda sem trocar de modelo
"Analise ultrathink este diff para identificar regressões sutis..."
```

---

## Auto-memory

O Codex gera memórias automáticas das conversas (`autoMemory: true` no settings.json).
Estas memórias ficam em `.Codex/memory/` e são carregadas em sessões futuras.

**IMPORTANTE**: As memórias automáticas COMPLEMENTAM, não substituem o `contexto.md`.
- `contexto.md` = verdade institucional (escrita por `vhub_guardiao_revisao`)
- `.Codex/memory/` = padrões de uso e preferências detectados automaticamente

Se houver conflito, **prevalece o `contexto.md`**.

---

## Autonomia de produção e fábrica de skills (decisão do dono 2026-06-27)

O dono concedeu **autonomia detalhada de produção**: agir sem pedir confirmação a cada passo, tomando as decisões de engenharia e seguindo o fluxo lógico de criação/manutenção — para economizar tempo/tokens e manter o projeto coeso, semântico, seguro e flexível.

- **Autonomia ≠ pular governança.** Continue rodando os gates: `vhub_arquiteto` (estrutura/placement/ownership), guardiões pertinentes ao risco (em paralelo), e `vhub_guardiao_revisao` (gate final + escrita do `contexto.md`). Pare apenas nas **condições de parada obrigatória** reais (2ª fonte de verdade, core frozen sem destrave, cliente decidindo verdade crítica, etc.).
- **Fábrica de skills (`.Codex/skills/`):** ao validar um padrão novo (aprovado em revisão de agente), documente-o como skill reutilizável. Só padrões **validados** — nunca fabricar. Em sessões futuras, consulte `.Codex/skills/` e aplique.
- **`contexto.md` é o segundo cérebro COMPLETO.** Escreva tudo lá (via gate `vhub_guardiao_revisao`); **não enxugue por tamanho** — o cap de 20 KB do protocolo NÃO se aplica (o dono quer o registro completo; é o que economiza tokens em sessões futuras). Deduplicar conteúdo **stale/contraditório** é correção válida; encolher por tamanho, não.
- Encodar convenções/decisões permanentes neste `AGENTS.md` é permitido sob esta autonomia.

Ver convenção **Export-first** em "Padrões obrigatórios de código → Regras de escrita".

---

## Gate do CORE (durante o descongelamento v1.0 → v2.0)

Enquanto o CORE está sendo descongelado, escrever em `resources/[CORE]/vhub/**` **não é proibido — é gated**. O `settings.json` usa `ask` (não `deny`) nesses caminhos: cada escrita **pausa e pede confirmação humana**, que é o gate exigido (arquiteto + revisão + ADR + bump de versão). Assim a migração anda, mas nunca em silêncio.

1. **`ask` rule**: `Write|Edit|MultiEdit(resources/[CORE]/vhub/**)` → confirmação a cada escrita.
2. **`contexto.md` permanece `deny`** (escritor exclusivo: `vhub_guardiao_revisao`).
3. **settings.local.json** (gitignored) pode dar `allow` para uma sprint de CORE sem prompts repetidos:
   ```json
   { "permissions": { "allow": ["Write(resources/[CORE]/vhub/**)", "Edit(resources/[CORE]/vhub/**)"] } }
   ```
   ⚠️ Nunca commitar. Ao concluir a sprint de CORE, remover o allow (volta a `ask`).
4. **Reverter para congelar de novo**: trocar `ask` → `deny` nesses três caminhos no `settings.json`.

---

## MCP — Model Context Protocol

Servidores MCP declarados em `.mcp.json` (raiz do repo, ao lado de `.Codex/`). São ferramentas
extras que a sessão e os agentes podem usar; ativação por servidor, sem segredo hardcoded.

- **`filesystem`** (ativo): leitura/escrita restrita à raiz do projeto — navegação e edição sob as mesmas regras de permissão/hook do Codex.
- **`git`** (opcional): histórico, diff e blame estruturados — útil para o `vhub_guardiao_revisao` inspecionar a mudança sem custo de shell. Requer `uvx`/Python; habilitar quando disponível.
- Regras: nenhum servidor MCP contorna os gates de `settings.json` nem escreve em `contexto.md`/CORE sem o mesmo gate. Chave/token de servidor MCP vai em `.env`/variável de ambiente, **nunca** no `.mcp.json` versionado.

Para adicionar um servidor, editar `.mcp.json` e reiniciar a sessão (o Codex recarrega MCP no boot).
