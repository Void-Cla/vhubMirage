# vhub_login — Gate de Entrada (Login + Seleção de Personagem)

**Versão:** 0.6.1 | **Owner:** vhub_login

Gate de entrada do servidor: login, seleção, criação autoritativa no CORE e handoff ao `vhub_sims`. O HSS mantém o bucket-base 999 e aloca uma subinstância privada após autenticação; previews locais usam o mapa `depzitamadasptlnd`.

---

## O que faz

- Login e cadastro com usuário, senha, confirmação, e-mail e WhatsApp
- Recuperação provisória por contato, restrita ao mesmo UID atual
- Contatos cifrados; lookups, IP e senha protegidos por pepper fora do banco
- Aceite versionado de termos e declaração 18+

O evento legado `vhub_login:tryRegister(username,password)` permanece por um ciclo apenas para
responder `cadastro_atualizacao_necessaria`. Novos clientes usam `vhub_login:tryRegisterV2(payload)`.
- Seleção de personagem da conta autenticada
- Cards agregados por `vhub_hss` + `vhub_identity`
- Fluxo: `login` → `charselect` → `creating` → `charselect`; só então `spawning`
- Criação idempotente persistida no CORE, com limite de três personagens
- Fail-closed: conta inválida delega recusa ao core
- Habilitável por config (`enabled=false` por padrão até o runtime-validate do dono)

---

## Dependências

```
vhub, vhub_hss, vhub_identity, vhub_sims, vhub_spawselector, depzitamadasptlnd
```

---

## Exports disponíveis (server-side, export-first default-deny)

Trust configurado em `config/config.lua` (`login_trusted`) — vazio por padrão (só consumo interno).

```lua
-- true se o player concluiu o login nesta sessão
local ok = exports.vhub_login:isAuthenticated(src)

-- dados NÃO sensíveis da conta (nunca hash/salt)
-- { account_id, username, user_id } ou nil
local conta = exports.vhub_login:getAccount(src)

-- etapa atual: 'login' | 'charselect' | 'creating' | 'spawning' | 'ready' | nil
local step = exports.vhub_login:getSessionStep(src)
```

---

## Como autorizar outro resource a consultar o login

```lua
-- config/config.lua
VHubLogin.Config.login_trusted = {
  ['vhub_admin'] = true,   -- painel pode checar isAuthenticated
}
```

Sem entrada na lista, o export retorna o valor de negação (`false`/`nil`) — default-deny.

---

## Fluxo do gate (Opção A — interceptação do chooseSpawn)

```
1. Player conecta → core dispara fluxo de spawn
2. vhub_login intercepta chooseSpawn → segura o player na tela de login
3. Login ok → agrega resumos HSS/Identity → player escolhe ou cria
4. Com criação: SIMS assume o estágio e devolve ao charselect ao concluir ou cancelar
5. Personagem concluído → step='spawning' → abre o selector sobre o mesmo palco
6. O jogador pode voltar ao `charselect`; somente a confirmação final encerra o bucket privado
```

Runbook pré-enable: validar o fail-open do selector antes de ligar `enabled=true` (passo do dono, pós runtime-validate).

## Identificadores e privacidade

- Rockstar/Cfx, Steam, Discord, FiveM, Live e Xbox permanecem no owner canônico do CORE (`vh_user_ids`).
- O login não duplica esses identificadores; mantém somente `user_id` e digest do último IP.
- `source` é efêmero e não é persistido. MAC não é exposto de forma confiável pelo FiveM.
- O pepper fica no KVP do resource. Para instalação nova, pode ser fornecido antes do primeiro boot
  pela convar server-only `vhub_login_pepper`; sem ela, deriva deterministicamente da licença server-only
  e é fixado no KVP. Preserve o KVP em backups e não troque a convar após criar contas.

---

## Regras aplicáveis (manual_dev_vhub.md)

| Lei | Aplicação aqui |
|-----|---------------|
| L-01 | Senha validada server-side; hash nunca sai do servidor |
| §3.7 | Export-first com `invokerOK` default-deny (trust vazio = só interno) |
| L-16 | Não toca o ped — segura o fluxo e devolve ao owner do spawn |
| L-17 | Replay-safe: re-disparo do fluxo não duplica sessão nem prende o player |

---

## Mapa de Integração

| # | Export | Assinatura resumida | Quem consome |
|---|--------|---------------------|--------------|
| 1 | `isAuthenticated` | `(src) → bool` | vhub_spawselector |
| 2 | `getAccount` | `(src) → {user_id, chars_count, …}` | vhub_spawselector |
| 3 | `getSessionStep` | `(src) → 'auth'\|'char'\|'spawn'\|'ready'` | vhub_spawselector |
| 4 | `runPersistenceTest` | `() → ok` | vhub_testrunner |
| 5 | `getPersistenceTest` | `() → resultado` | vhub_testrunner |
| 6 | `isGateActive` | `() → bool` | vhub_spawselector (feature flag) |
| 7 | `completeEntry` | `(src) → bool` | vhub_spawselector (ACK final) |

## Consome de

| Resource | Exports usados |
|----------|----------------|
| `vhub` (CORE) | `getUser`, `getUID`, `notify` |
| `vhub_hss` | `isPendingSpawn`, `getCharacterSummaries`, `isolateEntrySession`, `releaseEntrySession` |
| `vhub_identity` | `getCharacterSummaries` (lista de chars para seleção) |
| `vhub_sims` | `needsCreation`, `beginCreation` (personagem novo) |
| `vhub_spawselector` | intercepta fluxo `chooseSpawn` (provider) |

## Eventos emitidos

| Evento | Direção | Payload resumido |
|--------|---------|-----------------|
| `vhub_login:authenticated` | server→client (player) | `{user_id}` |
| `vhub_login:charSelected` | server→client (player) | `{char_id}` |
