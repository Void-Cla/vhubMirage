# vhub_identity — Identidade do Personagem

**Versão:** 1.1.1 | **Owner:** vhub_identity

Identidade civil do personagem: nome, sobrenome, idade, registro geral (RG) e telefone. Server-authoritative com tabela própria `vh_identity`. Gera identidade automática no primeiro load do personagem.

---

## O que faz

- Gera nome/sobrenome aleatórios (PT-BR), idade, RG e telefone únicos no primeiro `characterLoad`
- Persiste em tabela dedicada `vh_identity` (oxmysql direto)
- Resolve identidade por src, registro ou telefone
- Base para: LSPD (prontuário), telefone (contatos), documentos

---

## Dependências

```
oxmysql, vhub, vhub_money
```

---

## Exports disponíveis (server-side)

```lua
-- identidade completa do player online
-- { char_id, firstname, lastname, age, registration, phone }
local id = exports.vhub_identity:getIdentity(src)

-- nome completo formatado ("Carlos Silva")
local nome = exports.vhub_identity:getFullName(src)

-- busca personagem pelo número de registro (RG) — online ou offline
local char = exports.vhub_identity:getCharByRegistration('12345678')

-- busca personagem pelo telefone — online ou offline
local char = exports.vhub_identity:getCharByPhone('555-1234')

-- contratos ADR #74 (gated)
local result = exports.vhub_identity:setIdentity(src, data, operation_id) -- vhub_sims
local summaries = exports.vhub_identity:getCharacterSummaries(src)      -- vhub_login
```

---

## Exemplo de integração

```lua
-- LSPD consulta o cidadão pela placa → dono → identidade
local veh = exports.vhub_conce:getVehicle(plate)
if veh then
  local char = exports.vhub_identity:getCharByRegistration(veh.owner_registration)
  -- exibir prontuário no MDT
end

-- Notificação personalizada
local nome = exports.vhub_identity:getFullName(src)
TriggerClientEvent('vHub:notify', src, 'info', ('Bem-vindo, %s!'):format(nome))
```

---

## Nota arquitetural (por que oxmysql direto)

O `vhub_identity` usa `exports.oxmysql` diretamente em vez do `vhub.State` porque o FiveM **serializa tabelas em exports cross-resource** — chamadas como `S:prepare()` de fora do vhub não persistem no `_prepared` real do core. Este é o padrão para todo resource externo (ver §Regras de escrita do CLAUDE.md: "resources externos usam `exports.oxmysql` diretamente").

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 | Cliente jamais altera identidade; geração e persistência server-side |
| L-04 | Identidade civil = dado do vhub_identity (escritor único da vh_identity) |
| L-17 | `characterLoad` com replay-guard: identidade já existente não é regenerada |
| L-12 | INSERT de identidade nova é atômico (registro/telefone únicos) |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `getIdentity` | `(src) → {char_id, firstname, lastname, age, registration, phone}` | vhub_money, vhub_admin, vhub_lspdtool |
| 2 | `getFullName` | `(src) → string` | vhub_admin, vhub_racha |
| 3 | `getCharByRegistration` | `(registration) → char\|nil` | vhub_lspdtool (MDT) |
| 4 | `getCharByPhone` | `(phone) → char\|nil` | vhub_voicePMA (ligações) |
| 5 | `setIdentity` | `(src, data, op_id) → ok` | vhub_sims (criação de personagem) |
| 6 | `getCharacterSummaries` | `(src) → lista` | vhub_login (seleção de char) |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getCharacterId`, `notify` |
| `oxmysql` | Persistência direta (`vh_identity`) |
| `vhub_money` | `giveBank` (dinheiro inicial na criação) |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_identity:created` | server interno | `{char_id, firstname, lastname}` |
