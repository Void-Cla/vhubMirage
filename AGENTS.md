# vHub Mirage — Protocolo de Agentes (Claude Sonnet 4.6)

## Leitura obrigatória antes de qualquer ação

```
.claude/contexto.md          ← memória institucional viva (LEIA SEMPRE PRIMEIRO)
metas/plan.md               ← roadmap por sprint com critérios de aceite
metas/implementar.md        ← decisões técnicas congeladas
metas/fivem_natives_organizadas_ptbr.md ← referência de natives FiveM (consultar antes de custom)
```

---

## Verdades imutáveis do projeto

| Lei | Regra |
|-----|-------|
| **L-01** | Servidor é autoritativo para toda verdade crítica |
| **L-02** | Cliente processa estado local não-crítico (UI, física, HUD); servidor valida e persiste |
| **L-03** | Fallback de dado cliente = rollback para último estado válido do servidor |
| **L-04** | Sem segunda fonte de verdade; sem ownership duplicado |
| **L-05** | Native FiveM antes de infraestrutura custom |
| **L-06** | Sem loop/polling — preferir evento, State Bag ou timer mínimo |
| **L-07** | Sem novo resource/módulo sem ownership e lifecycle explícitos |
| **L-08** | Código em inglês; comentários, saídas e `lang.*` em PT-BR |
| **L-09** | Funções curtas, sem redundância, máximo reaproveitamento sem acoplamento rígido |
| **L-10** | Toda função pública comentada com uma linha objetiva em PT-BR |
| **L-11** | vRP-compat (`server/compat.lua`) deve permanecer funcional até vHub ter nome no mercado |
| **L-12** | Transações SQL são atômicas e exclusivamente server-side |

---

## Economia de tokens — protocolo obrigatório

- **Leia `.claude/contexto.md` antes de qualquer chamada a agente** — evita reenviar contexto que já está registrado
- Envie ao agente somente: objetivo, restrições, diff e arquivos tocados
- Jamais reenviar histórico completo se `.claude/contexto.md` e leitura local bastarem
- Respostas dos agentes: formato fixo, sem recapitular o pedido, sem expor raciocínio interno
- Cada agente para na menor evidência suficiente para o veredito
- `SEM ACHADOS CRÍTICOS` quando não houver problema real — não fabricar achados
- Gate pesado (`vhub_guardiao_revisao`) somente quando houver diff relevante ou risco estrutural

---

## Fluxo preferencial multi-agente

```
1. Ler .claude/contexto.md
2. Mapear arquivos tocados (explorer local)
3. Consultar vhub_arquiteto → ownership, placement, fase
4. Acionar em PARALELO apenas os guardiões relevantes ao risco:
   ├── vhub_guardiao_contrato   (se tocar API/export/schema)
   ├── vhub_guardiao_seguranca  (se tocar auth/permissão/entrada cliente)
   ├── vhub_guardiao_natives    (se tocar entity/ped/netid/State Bag/spawn)
   ├── vhub_guardiao_performance (se tocar thread/loop/batch/flush)
   ├── vhub_guardiao_simplicidade (se criar módulo/helper/camada nova)
   └── vhub_guardiao_designer   (se tocar NUI/client/HUD)
5. worker executa SOMENTE após forma aprovada
6. vhub_guardiao_revisao faz gate final quando diff tem código relevante
7. vhub_guardiao_revisao atualiza .claude/contexto.md se houver contexto durável novo
8. Agente pai consolida → APROVAR ou REPROVAR
```

---

## Padrões de código obrigatórios

### Lua 5.4 — estrutura mínima de módulo server-side
```lua
-- módulo.lua — <descrição de uma linha em PT-BR>
local M = {}; M.__index = M; vHub.NomeModulo = M

-- inicializa o módulo com driver e config validados
function M:init(cfg, driver) ... end

-- retorna M para encadeamento opcional
return M
```

### Regras de escrita
- OOP via `vHub.class()` para domínios com estado; tabela simples para utilitários puros
- `vHub.assertThread()` obrigatório em toda função pública que use `Citizen.Await`
- `Citizen.CreateThread` apenas para operações assíncronas reais; destruir a thread ao fim
- Sem `while true do` sem condição de saída explícita
- Sem `print()` fora de `shared/logger.lua` e `bootstrap.lua` (fallback)
- Sem SQL inline — toda query via `S:prepare()` + `S:query()`
- Sem validação ou persistência crítica no cliente
- Exports sensíveis protegidos por `_invoker_allowed()` + `GetInvokingResource()`

### Ordem de carregamento (não alterar sem gate do arquiteto)
```
shared/config.lua → shared/events.lua → shared/utils.lua → shared/logger.lua
bootstrap.lua → base.lua → server/init.lua
  → kernel → state → sql → notify → auth → vehicle → security → compat → boot → exports → modules/*
client/bootstrap.lua → client/core.lua → client/vehicle.lua → client/modules/*
```

---

## Papel dos agentes

| Agente | Responsabilidade |
|--------|-----------------|
| `vhub_arquiteto` | Decide placement, ownership e fase; aprova extensões antes dos exports |
| `vhub_guardiao_contrato` | Protege API, schema, nomenclatura e exports contra drift |
| `vhub_guardiao_seguranca` | Zero-trust: valida autoridade servidor, anti-dupe, fail-safe |
| `vhub_guardiao_natives` | Native-first: evita mirror/cache/shadow sem necessidade |
| `vhub_guardiao_performance` | Protege resmon, idle, CPU, rede e custo de thread |
| `vhub_guardiao_simplicidade` | Remove inflação, duplicação e camadas sem ganho técnico |
| `vhub_guardiao_designer` | NUI/CEF: compatibilidade FiveM, resmon baixo, sem regra de negócio |
| `vhub_guardiao_revisao` | Gate final: regressão, risco, testes, memória institucional |

---

## Condições de parada obrigatória

Se qualquer agente encontrar um dos itens abaixo, **pare imediatamente e reduza escopo**:

- Segunda fonte de verdade para o mesmo dado
- Novo resource sem ownership e lifecycle documentados
- Cliente decidindo verdade crítica sem validação server-side
- SQL no owner errado ou inline fora de `state.lua`/`sql.lua`
- Fallback estrutural sendo tratado como caminho normal
- Validação ou persistência crítica duplicada
- Loop sem condição de saída (potencial loop infinito)
- Export sensível sem `_invoker_allowed()`

---

## Plano de sprints (resumo de status)

| Sprint | Foco | Status |
|--------|------|--------|
| SPRINT 0 | `shared/` foundation | ✅ Concluído |
| SPRINT 1 | Estabilidade (race, flush, assertThread) | ✅ Aplicado — smoke tests pendentes |
| SPRINT 2 | Organização (split `base.lua`, compat vRP) | 🔄 Gate arquiteto pendente |
| SPRINT 3 | Client-side (State Bags, report) | 🔄 Inicial criado |
| SPRINT 4 | Segurança (ACE, payload hardening) | ⏳ Pendente |
| SPRINT 5 | Performance (flush tuning, GC, threads) | ⏳ Pendente |
| SPRINT 6 | Observabilidade (logger estruturado, health) | ⏳ Pendente |
| SPRINT 7 | Testes e validação (smoke, integração DB) | ⏳ Pendente |

---

## Memória institucional

- **Escritor oficial**: `vhub_guardiao_revisao` — único agente com escrita em `.claude/contexto.md`
- Registrar apenas: ownership, contrato, risco ativo, decisão congelada, fluxo validado, lacuna real
- Se `.claude/contexto.md` divergir do código, prevalece o código
- Nunca registrar: secrets, logs brutos, stacktrace completo, especulação sem fonte

— Assinado: `vhub_guardiao_revisao` | Migrado para Claude Sonnet 4.6
