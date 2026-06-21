# vHub Mirage 1

Framework FiveM GTARP server-authoritative, Lua 5.4.
Compatibilidade vRP1/2 via `server/compat.lua` (shim imutável até vHub ter nome no mercado).

## Leitura obrigatória antes de qualquer ação

1. `.claude/contexto.md` — memória institucional (ownership, contratos, riscos, sprints)
2. `.claude/AGENTS.md` — leis L-01..L-12, padrões de código e fluxo completo

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
.claude/
  contexto.md    AGENTS.md         ← memória institucional e protocolo
  agents/*.md                      ← agentes especializados (Claude Code nativo)
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
| L-11 | `server/compat.lua` permanece funcional até vHub ter nome no mercado |
| L-12 | Transações SQL são atômicas e exclusivamente server-side |

## Leis estendidas (pós-freeze)

| Lei | Regra |
|-----|-------|
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

Agentes definidos em `.claude/agents/*.md` — formato nativo Claude Code, invocáveis via `Agent` tool.

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
| `vhub_guardiao_revisao` | Gate final antes de todo commit relevante; único autorizado a escrever em `contexto.md` |
| `vhub_designer` | Proposta ou redesign de NUI/interface componentizada |

### Fluxo preferencial multi-agente

```
1. Ler .claude/contexto.md
2. Mapear arquivos tocados
3. vhub_arquiteto → ownership, placement, fase
4. Guardiões relevantes em PARALELO (somente os pertinentes ao risco)
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

### Ordem de carregamento em `server/init.lua` (não alterar sem gate do arquiteto)

```
kernel → state → sql → notify → auth → vehicle → security → compat → boot → exports → modules/*
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
| `vhub_designer` | Opus 4.7 | high | Design técnico + criativo requer capacidade acima da média |
| `vhub_guardiao_contrato` | Sonnet 4.6 | high | Pattern matching contra contratos conhecidos |
| `vhub_guardiao_natives` | Sonnet 4.6 | high | Lookup de referência + pattern check |
| `vhub_guardiao_performance` | Sonnet 4.6 | high | Análise de padrões de performance |
| `vhub_guardiao_designer` | Sonnet 4.6 | high | Verificação de identidade visual |
| `vhub_guardiao_runtime` | Sonnet 4.6 | high | Patterns arquiteturais JS (A-01..A-08) |
| `vhub_guardiao_simplicidade` | Sonnet 4.6 | medium | Checks simples, não requer raciocínio profundo |

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

O Claude Code gera memórias automáticas das conversas (`autoMemory: true` no settings.json).
Estas memórias ficam em `.claude/memory/` e são carregadas em sessões futuras.

**IMPORTANTE**: As memórias automáticas COMPLEMENTAM, não substituem o `contexto.md`.
- `contexto.md` = verdade institucional (escrita por `vhub_guardiao_revisao`)
- `.claude/memory/` = padrões de uso e preferências detectados automaticamente

Se houver conflito, **prevalece o `contexto.md`**.

---

## Hook de proteção do CORE

O `settings.json` tem duas proteções para o CORE FROZEN v1.0:

1. **Deny rule**: `"Write(resources/[CORE]/vhub/**)"` — Claude Code não pode escrever diretamente
2. **settings.local.json**: Para edições emergenciais, adicione manualmente ao `.claude/settings.local.json`:
   ```json
   { "permissions": { "allow": ["Write(resources/[CORE]/vhub/**)"] } }
   ```
   ⚠️ `.claude/settings.local.json` está no `.gitignore` — nunca commitar.
