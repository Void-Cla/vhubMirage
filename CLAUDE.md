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
| `vhub_guardiao_designer` | Tocar NUI, CEF, HUD, `client/`, `SendNUIMessage`, `RegisterNUICallback` |
| `vhub_guardiao_revisao` | Gate final antes de todo commit relevante; único autorizado a escrever em `contexto.md` |
| `vhub_designer` | Proposta ou redesign de NUI/interface |

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

## Ferramentas de teste

- `resources/[TOOLS]/vhub_testrunner/` — runner server-side (comando: `vhub_run_tests`)
- `tools/limpardadossql.ps1` / `tools/fix_vhub_db.ps1` — manutenção de dados SQL
- **ATENÇÃO**: testrunner executa queries reais → usar APENAS em ambiente de teste
