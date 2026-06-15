# Manual — Como transformar QUALQUER resource em app do iPad

> Guia oficial de conversão da plataforma `vhub_ipad`.
> Exemplo de referência ao longo do documento: **`vhub_lspdtool`** (Central LSPD).
>
> Premissa: o iPad é uma **plataforma de plugins**. Adicionar um app **não exige
> editar o `vhub_ipad`** — o seu resource se auto-registra e o painel dele roda
> *dentro* da tela do tablet via um broker opaco (App SDK relay).

---

## 0. Mapa mental (leia antes de tudo)

```
   SEU RESOURCE (dono do domínio)          vhub_ipad (broker OPACO)            CEF do iPad
 ┌───────────────────────────────┐     ┌───────────────────────────┐     ┌──────────────────┐
 │ server: ipadRelay(src,act,d)  │◀────│  relay.lua  (ACL + cap)   │◀────│ vhub.app         │
 │   - valida perm/login         │     │  registry  (catálogo)     │     │   .channel('x')  │
 │   - executa a regra crítica   │     │  appPush(src,app,act,d)   │────▶│   .send(act,d)   │
 │   - appPush de volta ─────────┼────▶│                           │     │   .on(act,fn)    │
 │ web/app_ipad/x.html|css|js    │◀────┼── cfx-nui-<resource>/ ────┼────▶│  <script>/<link> │
 └───────────────────────────────┘     └───────────────────────────┘     └──────────────────┘
```

Três verdades que **nunca** mudam:

1. **Verdade crítica é do SERVER do seu resource** (L-01). O iPad só transporta. Ele
   nunca lê, valida ou persiste o payload de domínio (L-04).
2. **O cliente só nomeia o app + a ação.** Quem é o jogador (`src`) é injetado pelo
   broker server-side — o cliente não consegue forjar isso.
3. **O painel roda DENTRO do iPad** (sensação de "estou usando o tablet"). HUDs
   in-game (radar, helicam, velocímetro) continuam nativos no seu resource — só o
   **painel interativo** vira app.

---

## 1. Duas decisões independentes: REGISTRO × LOCAL da UI

Converter um resource em app combina **duas escolhas ortogonais**:

**(a) Onde o app é REGISTRADO no catálogo:**

| Registro | Como | Edita o `vhub_ipad`? | Status |
|----------|------|----------------------|--------|
| **Builtin (catálogo)** ★ | entrada em `vhub_ipad/shared/config.lua` → `BUILTIN_APPS` | Sim (1 bloco) | **Provado** (settings, store, racha, lspd) |
| **Self-register** | `exports.vhub_ipad:registerApp(manifest)` do seu resource | Não | Experimental — valide no seu build |

**(b) Onde vivem os arquivos web (HTML/CSS/JS):**

| UI | Onde | `ui.source` |
|----|------|-------------|
| **Local** | dentro do `vhub_ipad` (`web/modules/<id>/`) | `'local'` |
| **Remota** ★ | no SEU resource (`web/app_ipad/`), servida via `cfx-nui-<resource>` | `'remote'` |

> **Recomendado (provado): Builtin + UI Remota.** O manifest é declarado no catálogo do
> iPad (1 bloco em `BUILTIN_APPS`, confiável e idêntico ao caminho dos apps de sistema),
> mas o HTML/CSS/JS e o `ipadRelay` ficam no SEU resource. É o que o **`vhub_lspdtool`**
> usa. O `vhub_racha` usa Builtin + UI Local (foi o 1º porte).
>
> O sonho "zero edição no iPad" = **Self-register + Remota** — documentado no §2 Passo 3
> como alternativa, mas o caminho `registerApp` de um resource externo ainda está em
> validação de runtime; em produção, prefira **Builtin** até confirmá-lo no seu servidor.

O resto deste manual usa a combinação recomendada (**Builtin + Remota**).

---

## 2. Receita — modelo A (self-register + remote), passo a passo

### Passo 1 — Crie o painel web no SEU resource

Crie `web/app_ipad/<id>.html`, `<id>.css`, `<id>.js` (ex.: `web/app_ipad/lspd.*`).

Regras do markup (`<id>.html`):

- **Sem** `<html>`, `<head>`, `<body>` — é um **fragmento**. O iPad injeta dentro de
  `#vhub-app`. Comece direto no `<section>` raiz.
- **Sem** botão de fechar e **sem** `ESC` — a navbar do iPad (◀ ⌂ ×) fecha.
- **Sem** CSS/JS inline. Tudo nos arquivos `.css`/`.js`.
- Raiz com uma classe de escopo única: `class="lspd-shell"` etc.

Regras do CSS (`<id>.css`):

- **Tudo escopado** sob o seletor raiz do módulo: o core monta seu HTML dentro de uma
  `<div class="mod-<id>">`. Então escopo = `.mod-lspd .qualquer-coisa { … }`.
- Identidade visual vHub: **Liquid Glass + Areia + Dourado**. Use variáveis locais
  (`--lspd-gold`, `--lspd-glass`…) no `.mod-lspd` para não vazar tokens.
- `backdrop-filter` **no container**, não em cada card (1 camada CEF, não N).

Regras do JS (`<id>.js`):

```js
// web/app_ipad/lspd.js — app EMBUTIDO do LSPD no iPad
(() => {
    'use strict';

    // 1) helpers LOCAIS — o iPad NÃO expõe window.vhubUtils ao app remoto
    function el(tag, attrs, kids) { /* … */ }

    // 2) canal de relay + store isolado do app
    const ch    = vhub.app.channel('lspd');   // <id> == 'lspd'
    const store = vhub.store('lspd');

    let chOffs = [];   // off() acumulados → desfeitos no onDestroy (A-07)

    // 3) lifecycle padronizado (A-02)
    vhub.createModule('lspd', {
        onInit() {
            // registre os ch.on AQUI (antes do DOM). Guarde os off() em chOffs.
            chOffs.push(ch.on('data', onData));
            chOffs.push(ch.on('result', onResult));
        },
        onMount(root) {
            // root = a <div class="mod-lspd">. querySelectors + addEventListener aqui.
            ensureFontAwesome();   // injete FA UMA vez se usar ícones
        },
        onShow() {
            ch.send('open');       // pede o estado ao server do SEU resource
        },
        onHide() { /* pause timers se houver */ },
        onDestroy() {
            for (const off of chOffs) { try { off(); } catch (_) {} }
            chOffs = [];
            // removeEventListener, cancelAnimationFrame, clearInterval, observer.disconnect
        },
    });
})();
```

- O nome em `vhub.createModule('<id>')`, `vhub.app.channel('<id>')` e `vhub.store('<id>')`
  **tem que ser idêntico** ao `id` do manifest. O core casa tudo por esse nome.
- `ch.send(action, data)` substitui CADA `vhub.post(...)`/`TriggerServerEvent`.
- `ch.on(action, fn)` substitui CADA `SendNUIMessage`/`window.addEventListener('message')`.
- `onDestroy` é **obrigatório** (A-07) — sem ele o core loga warning e há leak no re-mount.

### Passo 2 — Exponha os arquivos web em `files{}`

No `fxmanifest.lua` do SEU resource, adicione os 3 arquivos a `files{}`. **NÃO** precisa
ser `ui_page` (eles são servidos via `cfx-nui-<resource>/` para o CEF do iPad):

```lua
files {
    -- … seus arquivos atuais …
    'web/app_ipad/lspd.html',
    'web/app_ipad/lspd.css',
    'web/app_ipad/lspd.js',
}
```

> O seu resource pode manter o `ui_page` próprio (HUDs de radar/helicam). O app do iPad
> são só `files{}` extras — o CEF do iPad faz `fetch('https://cfx-nui-<resource>/web/app_ipad/lspd.html')`.

### Passo 3 — Registre o app no catálogo do iPad

**Recomendado (provado): builtin no catálogo.** Adicione UM bloco a
`vhub_ipad/shared/config.lua` → `VHubIpadCFG.BUILTIN_APPS`. A UI continua **remota** (no
seu resource) — só o registro mora no iPad:

```lua
{
    id = 'lspd', version = '1.0.0', manifest_level = 1,
    label = 'Central LSPD', icon = 'lspd.png',   -- ícone no CDN de assets
    category = 'trabalho', removable = true,      -- aparece na Loja p/ instalar/remover
    dependency = 'vhub_lspdtool',                 -- 'available' segue o estado do resource
    ui = { source = 'remote', resource = 'vhub_lspdtool',
           html = 'web/app_ipad/lspd.html',
           css  = 'web/app_ipad/lspd.css',
           js   = 'web/app_ipad/lspd.js' },
    relay = { resource = 'vhub_lspdtool', export = 'ipadRelay' },
},
```

> `dependency` faz o catálogo marcar o app como indisponível quando o seu resource está
> parado — sem precisar desregistrar. O registro é reaplicado no boot do iPad (idempotente).
> **Não** combine com o self-register abaixo (manifest duplicado).

**Alternativa (zero edição no iPad — experimental): self-register.** Em vez do bloco acima,
chame do SERVER do seu resource, no boot **e** quando o `vhub_ipad` (re)iniciar. Verifique
no SEU build se o app aparece na Loja; se não aparecer, use o builtin (provado):

```lua
-- registra o app do LSPD no catálogo do iPad (idempotente)
local function registerIpadApp()
    if GetResourceState('vhub_ipad') ~= 'started' then return end
    local ok, err = pcall(function()
        return exports.vhub_ipad:registerApp({
            id             = 'lspd',
            version        = '1.0.0',
            manifest_level = 1,
            label          = 'Central LSPD',
            icon           = 'lspd.png',          -- nome do ícone no CDN de assets
            category       = 'trabalho',
            removable      = true,                -- aparece na Loja p/ instalar/remover

            -- UI REMOTA: arquivos no PRÓPRIO resource (cfx-nui-vhub_lspdtool/…)
            ui = {
                source   = 'remote',
                resource = 'vhub_lspdtool',
                html     = 'web/app_ipad/lspd.html',
                css      = 'web/app_ipad/lspd.css',
                js       = 'web/app_ipad/lspd.js',
            },

            -- RELAY: o broker do iPad roteia ch.send → este export. SERVER-ONLY.
            relay = { resource = 'vhub_lspdtool', export = 'ipadRelay' },
        })
    end)
    if not ok then print('[vhub_lspdtool] registerApp falhou: ' .. tostring(err)) end
end

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() or res == 'vhub_ipad' then registerIpadApp() end
end)
```

> **NÃO** coloque `permission` no manifest a menos que sua permissão seja do KERNEL
> (`exports.vhub:hasPerm`). Permissões de **grupo** (`policia.consulta`, via
> `vhub_groups`) NÃO passam pelo gate do manifest — você as valida no `ipadRelay`
> (Passo 4). Ver §5.

### Passo 4 — Implemente o `ipadRelay` no SERVER (o coração)

É o receptor de TODAS as ações do app. **Duas regras de ouro** (senão falha em silêncio):

```lua
-- relay do app EMBUTIDO do LSPD (broker vhub_ipad).
-- ┌─ REGRA 1: o body roda em CreateThread — o yield de Citizen.Await NÃO pode
-- │           cruzar a fronteira C do export (senão a corrotina é ABANDONADA:
-- │           o broker loga "OK" mas o appPush de volta nunca dispara).
-- └─ REGRA 2: SEMPRE valide src + permissão + (login) ANTES de agir (zero-trust).
exports('ipadRelay', function(src, action, data)
    if type(src) ~= 'number' or not GetPlayerName(src) then return false end
    data = (type(data) == 'table') and data or {}

    CreateThread(function()                         -- ← REGRA 1
        local ok, err = pcall(function()

            -- ← REGRA 2: autoridade do domínio (vhub_groups, NÃO o iPad)
            if not VHubLspd.hasPerm(src, 'policia.consulta') then
                exports.vhub_ipad:appPush(src, 'lspd', 'denied', { reason = 'sem_acesso' })
                return
            end

            if     action == 'open'   then exports.vhub_ipad:appPush(src, 'lspd', 'data', buildData(src))
            elseif action == 'login'  then doLogin(src, data)
            elseif action == 'bolo_add' then ...
            -- … demais ações …
            end
        end)
        if not ok then print('[vhub_lspdtool] ipadRelay ERRO: ' .. tostring(err)) end
    end)

    return true   -- responda imediatamente; o resultado volta por appPush
end)
```

Para **empurrar** dados de volta ao app (resposta, refresh, push assíncrono):

```lua
exports.vhub_ipad:appPush(src, 'lspd', '<action>', { … })
```

- `appPush` tem **owner-binding**: só o resource DONO do app (`relay.resource`) consegue
  empurrar para ele. Outro resource é rejeitado (fail-closed).
- Para **fechar** o iPad de fora (ex.: após uma ação que leva o jogador ao mundo):
  `exports.vhub_ipad:closeIpad(src)`.

### Passo 5 — Teste

Restart na ordem: **primeiro o seu resource**, depois confirme que o `vhub_ipad` já está
de pé (ou restart os dois). Abra o iPad → Loja → instale o app → abra. Veja §6 (checklist).

---

## 3. O contrato `vhub.app.*` (referência da API NUI)

| API (no `<id>.js`) | O que faz |
|--------------------|-----------|
| `vhub.app.channel(id)` | Retorna o canal do app: `{ send, on }`. Use `id` = id do manifest. |
| `ch.send(action, data)` | Publica `action`+`data` ao broker → `ipadRelay(src, action, data)`. |
| `ch.on(action, fn)` | Inscreve `fn(data)` para o push `appPush(..., action, data)`. Retorna `off()`. |
| `vhub.store(id)` | Slice de estado isolado do app (shallow-merge). Sem 2ª fonte de verdade (A-04). |
| `vhub.createModule(id, spec)` | Registra o módulo com lifecycle (A-02). |

Handlers são **escopados por app**: um `ch.on('data')` do `lspd` nunca recebe push do
`racha`. O shell define o app ativo ao navegar (`setActive`) — você não precisa cuidar disso.

---

## 4. As 3 armadilhas do FiveM (decoradas com sangue — não repita)

| # | Sintoma | Causa | Correção |
|---|---------|-------|----------|
| **1** | `ipadRelay` "loga OK" mas o `appPush` nunca chega | `Citizen.Await` (query SQL, dinheiro) **yield** cruzando a fronteira C do export → corrotina abandonada | Envolva TODO o corpo do `ipadRelay` em `CreateThread(function() … end)` e `return true` na hora |
| **2** | Export chamado mas o 1º argumento "some" / vira `self` | Forma colchete `exports[res][name](a,b,c)` com nome **dinâmico** descarta o 1º arg como `self` | (Já tratado no broker do iPad — passa o proxy como self.) Se VOCÊ chamar export de nome dinâmico, passe o proxy: `local p = exports[res]; p[name](p, a, b)` |
| **3** | Item/funcref passado por export "não funciona do outro lado" | Funcref **não sobrevive** à fronteira cross-resource | Use evento server-local (`TriggerEvent`/`AddEventHandler`) em vez de passar função por export |

Bônus (NUI remota):

- **App remoto não enxerga** `window.vhubUtils` nem CSS do seu resource original — o JS
  roda no documento do iPad. Carregue helpers **locais** no próprio `<id>.js` e injete
  FontAwesome no `onMount` se precisar de ícones.
- URLs relativas dentro do `<id>.css` resolvem contra `cfx-nui-<resource>/…` (correto).
  Para imagem do seu resource use `https://cfx-nui-<resource>/web/assets/x.png`.

Bônus (SQL — se o app adicionar tabelas):

- Schema com **mais de um `CREATE TABLE`**: aplique com `exports.oxmysql:query(schema)`,
  **nunca** `:execute(schema)`. O `:execute` usa prepared statements e não roda lotes
  multi-statement de forma confiável — só a 1ª tabela nasce e o resto falha em silêncio
  (login/persistência quebrados sem erro). É o mesmo padrão do CORE (`bootstrap.lua`).

---

## 5. Segurança — checklist obrigatório (zero-trust, L-01)

- [ ] **`src` é a única identidade confiável.** Nunca confie em `data.char_id`/`data.uid`
      vindo do cliente — derive server-side (`exports.vhub:getUser(src).char_id`).
- [ ] **Valide permissão no `ipadRelay`**, com a autoridade correta do domínio
      (`vhub_groups` para grupos; `exports.vhub:hasPerm` para kernel). Re-valide em
      **cada** ação mutadora — nunca só na abertura.
- [ ] **Sanitize todo `data`** (string → `tostring`+trim+cap de tamanho; número →
      `tonumber`+clamp; placa → `normalizePlate`). O cap de profundidade/keys (5/100)
      do broker é anti-DoS, não validação de domínio.
- [ ] **Exports mutadores** do seu resource: `_invoker_allowed()` + `GetInvokingResource()`.
- [ ] **Login/senha** (se o app exigir): senha **hasheada** (nunca em texto no banco),
      verificação server-side, sessão por `src` limpa no `playerDropped`. Ver o
      `vhub_lspdtool/server/accounts.lua` (hash via `SHA2` do MySQL — sem lib Lua).
- [ ] **Não** vaze segredo no snapshot: `relay` e qualquer credencial são **server-only**;
      o cliente nunca recebe o nome do export nem o hash.

---

## 6. Teste & resmon — checklist de aceite

- [ ] App aparece na **Loja** do iPad (categoria certa, ícone certo).
- [ ] Instala/desinstala e persiste **por personagem** (relog mantém).
- [ ] Abre **dentro** da tela do iPad (sem fullscreen, sem roubar foco de outro app).
- [ ] `ch.send` → server responde com `appPush` (veja o log do seu resource).
- [ ] Fechar o iPad chama `onDestroy` (sem timer/RAF rodando com NUI fechada — A-07/A-08).
- [ ] **resmon idle = 0.00ms** com o app fechado e com o iPad fechado.
- [ ] Restart do `vhub_ipad` sozinho → seu app **re-registra** (graças ao Passo 3).

---

## 7. Modelo B (builtin local) — quando o app é do próprio iPad

Só para apps de sistema mantidos dentro do `vhub_ipad`:

1. Crie `web/modules/<id>/<id>.{html,css,js}` (mesmo formato do Passo 1, `source='local'`).
2. Adicione os 3 arquivos ao `files{}` do `vhub_ipad/fxmanifest.lua`.
3. Adicione o manifest a `VHubIpadCFG.BUILTIN_APPS` em `shared/config.lua`
   (com `ui.source='local'` e, se embutido, `relay = { resource, export }`).

Tudo o mais (relay, `ipadRelay`, `vhub.app.channel`, gotchas) é **idêntico** ao modelo A.

---

## 8. TL;DR (cola rápida — Builtin + UI Remota, provado)

```
1. web/app_ipad/<id>.{html,css,js}     → fragmento escopado em .mod-<id>, lifecycle A-02
2. fxmanifest files{}                   → exponha os 3 arquivos (servidos via cfx-nui)
3. vhub_ipad/shared/config.lua          → 1 bloco em BUILTIN_APPS:
   { id, label, icon, removable=true, dependency='<seu_resource>',
     ui={source='remote', resource='<seu_resource>', html/css/js},
     relay={resource='<seu_resource>', export='ipadRelay'} }
4. exports('ipadRelay', fn)             → CreateThread + valida src/perm/login + appPush
5. NUI: vhub.app.channel('<id>').send/on
```

Dúvida de ownership/placement? Chame `vhub_arquiteto`. Mexeu em auth/payload? `vhub_guardiao_seguranca`.
Mexeu na NUI? `vhub_guardiao_runtime` + `vhub_guardiao_designer`. Antes do commit: `vhub_guardiao_revisao`.
