# vhub_sims — Editor de Aparência e Identidade

**Versão:** 1.2.0 | **Owner:** vhub_sims

Editor autoritativo de aparência e identidade do personagem. Gerencia criação de personagem novo (wizard), edição de aparência no SIMS (salões/lojas) e compra de outfits. Server-authoritative com UI NUI componentizada.

---

## O que faz

- **Wizard de criação**: guia o jogador novo pela criação de identidade civil + aparência inicial
- **Editor de aparência (Studio)**: edição completa de ped customization (rosto, corpo, cabelo, roupa)
- **Checkout**: compra de serviços (corte, tattoos, roupas) com cobrança via `vhub_money`
- **Controle de sessão**: sessão de edição com lock (sem trocar de char durante a edição)
- **Outfits**: salvar e carregar conjuntos de roupas por char
- **Pontos de serviço**: zonas de salão/loja configáveis com `vhub_target`

---

## Dependências

```
vhub, oxmysql, vhub_hss, vhub_identity, vhub_money, vhub_groups, vhub_target, depzitamadasptlnd
```

---

## Exports disponíveis (server-side, TRUSTED)

```lua
-- informa ao vhub_login se o char_id atual exige criação de personagem (wizard)
-- Retorna { ok = true/false, needs = bool }
local result = exports.vhub_sims:needsCreation(src)

-- inicia criação idempotente (chamado exclusivamente pelo vhub_login)
-- requestId é o idempotency key da sessão de criação
-- Retorna { ok = true/false, session = session_id }
local result = exports.vhub_sims:beginCreation(src, requestId)
```

---

## Fluxo de criação de personagem

Palco físico: `vec4(80.7225, 1.3156, 1.0001, 186.6230)`, aplicado pelo owner `vhub_hss`.

```
1. Login detecta char_id novo → chama vhub_sims:needsCreation
2. sims retorna { needs = true }
3. Login chama vhub_sims:beginCreation(src, requestId)
4. sims abre o wizard NUI (módulo web/modules/wizard/)
5. Jogador preenche nome/aparência → submit
6. sims chama vhub_identity:setIdentity + vhub_hss:commitCustomization
7. sims encerra sessão → login avança para seleção de spawn
```

---

## Fluxo de edição de aparência (salão)

```
1. Player entra na zona do salão (vhub_target)
2. Servidor abre o Studio NUI (web/modules/studio/)
3. Player edita aparência com preview em tempo real
4. Checkout (web/modules/checkout/) cobra via vhub_money:tryPayment
5. sims chama vhub_hss:sanitizeCustomizationPatch + commitCustomization
```

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 | Mutação de aparência validada e commitada server-side; cliente apenas propõe |
| L-04 | Aparência = verdade do vhub_hss; sims comita via contrato (commitCustomization) |
| L-13 | Nunca escreve CData/UData diretamente; usa contratos vhub_hss e vhub_identity |
| A-02 | Todos os módulos NUI (wizard, studio, checkout) com lifecycle padronizado |
| A-09 | CEF transparente; sem backdrop-filter no overlay sobre o jogo |
| A-10 | Todos os assets declarados em `files{}` do fxmanifest |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `needsCreation` | `(src) → {ok, needs}` | vhub_login (gate de personagem novo) |
| 2 | `beginCreation` | `(src, requestId) → {ok, session}` | vhub_login (inicia wizard) |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `notify` |
| `oxmysql` | Persistência de outfits e sessões |
| `vhub_hss` | `getCustomization`, `sanitizeCustomizationPatch`, `commitCustomization`, `setPedModel` (client: preview/restore/camera) |
| `vhub_identity` | `setIdentity` (dados civis do personagem novo) |
| `vhub_money` | `tryPayment` (custo dos serviços) |
| `vhub_groups` | `hasPermission` (descontos/acesso a itens premium) |
| `vhub_target` | `addSphereZone`, `addGlobalPed`, `removeZone` (zonas de salão/NPC) |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_sims:creationComplete` | server→client (player) | `{char_id}` |
| `vhub_sims:appearanceUpdated` | server→client (player) | `{char_id, patch}` |
