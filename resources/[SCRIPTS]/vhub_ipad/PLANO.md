# PLANO — `vhub_ipad` v3 (Plataforma de Apps / Tablet iOS-style)

> **Status**: plano validado pelos agentes vHub (arquiteto + designer + runtime + contrato) em 2026-06-13.
> **Substitui o desenho do** `README.md` (mantido como referência da ideia original).
> **Princípio-mestre**: o iPad NÃO é um shell com apps fixos. É uma **plataforma de plugins** —
> apps se auto-registram via export e podem viver em QUALQUER resource. Adicionar um app novo
> = criar um resource + 1 chamada `registerApp`, **zero edição no `vhub_ipad`**.

---

## 0. POR QUE ESTE PLANO EXISTE (o que muda vs. o README)

O README descrevia um tablet excelente, mas com o catálogo de apps **hardcoded** em
`VHubIpadCFG.APPS`. Isso significa: cada app futuro exige editar o `vhub_ipad`. Os agentes
identificaram que esse é o atrito que você quer eliminar. Este plano troca o catálogo estático
por um **registry server-authoritative** alimentado por export — exatamente o mesmo padrão que o
`vhub_inventory` já usa para itens (`registerItemUse`, decisão #8).

### Gaps reais do README corrigidos aqui (rastreabilidade)

| # | Gap do README | Correção neste plano |
|---|---------------|----------------------|
| G1 | §1 lista `exports.vhub:getCData/setCData` | **Não existem** no core FROZEN. Persistência = localStorage (prefs) + oxmysql próprio (v2). Ver §10. |
| G2 | §1 lista `exports.vhub:notify` | **Não existe** no core. Notificação ao jogador via export do resource dono (ex.: inventory/admin) ou `chat`/draw nativo. Ver §12. |
| G3 | §4.1/§14 "copiar 4 arquivos do runtime" | São **5** (`bus/store/bridge/core/sand`). `core.js` quebra sem `window._vhubSand`. |
| G4 | §4.2 loader só carrega `modules/<name>/` local | **Bloqueante p/ apps de terceiro.** `core.js` (cópia owned) passa a ser URL-driven (`mount_kind: local\|remote`). Ver §7. |
| G5 | `VHubIpadCFG.APPS` hardcoded | Substituído por **registry server** (`registerApp`). Ver §3/§6. |
| G6 | §6.7 referencia `#ipad-wallpaper` mas não o define | Definido no **shell** (atrás de `#vhub-app`), dono = shell. Ver §8. |
| G7 | §6.8 `shell.js` pré-monta TODOS os módulos no boot | Fere A-05. Só monta `home` no open; resto sob navegação. Ver §8. |
| G8 | §6.9 `home.js` usa `window._ipadDefaults` (nunca setado) + `onDestroy` vazio | Reconciliação contra catálogo vivo + `off()` guardados. Ver §9. |
| G9 | §9 edita `vhub_racha/client/nui.lua` com string literal de evento | Handoff por **export bidirecional**, sem string de evento. Ver §11. |
| G10 | `core.js._loadFiles` duplica `<link>` CSS em re-mount (leak) | Guardar `mod._cssLink`, remover no unmount. Ver §7. |
| G11 | CLAUDE.md template cita `vhub.native.*` | **Não existe** no runtime real. Usar só `vhub.post`. Ver §7. |
| G12 | Wallpaper aceita URL livre (injeção em `background-image`) | Enum validado server-side + URL custom https-only com cap. Ver §10. |

---

## 1. DECISÕES DE ARQUITETURA (consolidadas dos 4 agentes)

| # | Decisão | Lei/Origem |
|---|---------|------------|
| D1 | `vhub_ipad` é **resource owned** novo. Camada CROSS: L1 (registry server) + L3 (runtime copiado/owned) + L4 (apps = componentes). | L-07 (arquiteto) |
| D2 | **Catálogo de apps = verdade ÚNICA no server** (`registry.lua`). localStorage NUNCA define "quais apps existem". | L-04 (arquiteto) |
| D3 | localStorage guarda **só preferência de UI** (zoom, wallpaper_id, ordem/visibilidade de ícones). É um dado DIFERENTE, dono = NUI, efêmero. | L-02 (arquiteto) |
| D4 | `core.js` do iPad é **cópia divergente** do runtime do `vhub_racha`. NUNCA "ressincronizar" com o racha. Registrar a divergência no `contexto.md`. | provenance (arquiteto) |
| D5 | Loader **URL-driven**: manifest fornece URLs; `local`→`modules/<id>/...`, `remote`→`https://cfx-nui-<resource>/...`. | runtime |
| D6 | Handoff iPad↔app-fullscreen por **export bidirecional**, NUNCA string de evento de outro resource. | L-04 / anti-drift (contrato) |
| D7 | Identidade visual: **device skin dark** (o iPad é um "aparelho"), mas o **accent de ação = Dourado vHub**. Confirmar com `vhub_guardiao_designer` na F2. | designer |
| D8 | `vhub.store('ipad')` tem **um único writer** (o shell). Settings/Store emitem via bus; o shell aplica. | A-04 (designer) |
| D9 | Manifest carrega `version` + `manifest_level`; o iPad declara `API_LEVEL`. Campos `badges/widgets/order` reservados (opcionais) já na v1. | versionamento (contrato) |

---

## 2. CAMADAS E OWNERSHIP

```
L1 — Kernel server (Lua)      registry autoritativo, validação de manifest, gating de permissão/dependency
L2 — HAL client (Lua)         toggle, NuiFocus, relay de handoff, item-use, exports openIpad/closeIpad
L3 — Runtime NUI (JS owned)   engine copiado: createModule/mount/show/hide/unmount + loader URL-driven
L4 — Componente (JS módulo)   shell + apps (home/store/settings/racha/…), cada um com lifecycle próprio
```

**Linha do Registro de Ownership** (a ser inserida no `contexto.md` pelo `vhub_guardiao_revisao`
ANTES da primeira linha de código — exigência do arquiteto):

> `vhub_ipad` | `server/registry.lua` | Catálogo de apps registrados (`id→manifest`). **Escritor
> único**: `registry.lua` via export `registerApp` (server→server, `_invoker_allowed`). Leitores:
> client no open (snapshot read-only) → NUI. Persistência: nenhuma na F1 (catálogo efêmero,
> reconstruído a cada start via `onResourceStart`); preferências de UI = localStorage (v1) →
> oxmysql próprio + `char_id` (v2). Contrato p/ terceiros: `exports.vhub_ipad:registerApp(manifest)`.

---

## 3. CONTRATOS PÚBLICOS (estáveis, versionados)

Todos registrados como fonte única em `shared/events.lua` do iPad (registro único de nomes).

### 3.1 Exports do `vhub_ipad` (server)

```lua
exports.vhub_ipad:registerApp(manifest)   -- registra/atualiza um app (idempotente). valida schema + _invoker_allowed
exports.vhub_ipad:unregisterApp(id)        -- remove um app do catálogo (resource parou)
exports.vhub_ipad:openIpad(src)            -- abre o iPad para o jogador (item-use, app retornando)
exports.vhub_ipad:closeIpad(src)           -- fecha o iPad
exports.vhub_ipad:isOpen(src)              -- bool (read-only)
```

> Nomes `openIpad/closeIpad` (não `open/close`) — evitam colisão conceitual futura (contrato).

### 3.2 Schema do manifest (v1, `manifest_level = 1`)

```lua
{
  id            = 'racha',               -- string única [a-z0-9_]+ (OBRIGATÓRIO)
  version       = '1.0.0',               -- versão DO APP (OBRIGATÓRIO — registerApp rejeita sem)
  manifest_level= 1,                     -- nível de schema que o app usa (default 1)
  label         = 'Racha',               -- nome exibido (PT-BR)
  icon          = 'chita.png',           -- relativo ao CDN (utils.js monta a URL)
  category      = 'entretenimento',      -- agrupamento na App Store
  removable     = true,                  -- usuário pode OCULTAR da home (não "desinstalar de existir")
  dependency    = 'vhub_racha',          -- OPCIONAL: resource que precisa estar 'started'
  permission    = nil,                   -- OPCIONAL: perm vHub p/ ver/abrir (exports.vhub:hasPerm)
  ui = {
    source = 'local',                    -- 'local' | 'remote'
    html   = 'modules/racha/racha.html', -- local: relativo ao iPad | remote: caminho dentro do resource
    css    = 'modules/racha/racha.css',
    js     = 'modules/racha/racha.js',
    resource = nil,                      -- OBRIGATÓRIO se source='remote': nome do resource (vira cfx-nui-<resource>)
  },
  -- RESERVADOS (opcionais, adicionáveis sem breaking):
  badges  = nil,                         -- contador no ícone (futuro)
  widgets = nil,                         -- widget na home (futuro)
  order   = nil,                         -- posição sugerida (futuro)
}
```

**Regras de validação (`registry.lua`)**:
- `id`, `version`, `label`, `ui.html/css/js` obrigatórios → senão **rejeita + log**.
- `manifest_level > API_LEVEL` do iPad → **rejeita** (app espera iPad mais novo) + log claro.
- `source='remote'` exige `ui.resource` → o server resolve `https://cfx-nui-<resource>/<path>`.
- Re-registro do mesmo `id` **sobrescreve** (idempotente — resource reiniciou).

### 3.3 Item no inventário

```lua
exports.vhub_inventory:registerItemUse('ipad', function(src, _slot, _meta)
  if not Core.rate(src, 'use_ipad', CFG.rates.use_ipad) then return false end
  exports.vhub_ipad:openIpad(src)
  return false   -- item durável: NÃO consome
end)
```

### 3.4 Handoff iPad ↔ app fullscreen (ex.: racha) — **por export, sem string de evento**

```
Player toca "Racha" na home
  → racha.js (módulo NUI): vhub.post('launchApp', { id = 'racha' })
  → client/init.lua RegisterNUICallback('launchApp'):
       valida dependency (GetResourceState('vhub_racha')=='started')
       exports.vhub_ipad:closeIpad(src-local)     -- fecha o iPad
       exports.vhub_racha:openPanel(localPlayerSrc?) -- ver nota de direção abaixo
  → racha abre seu painel (fluxo próprio dele, intacto)

Player fecha o painel do racha
  → (OPCIONAL, racha opta no contrato) exports.vhub_ipad:openIpad(src) → iPad reabre
  → OU player reabre com o item (v1 mínimo, zero dependência)
```

> **Direção do handoff (decisão do contrato)**: o iPad e o racha se conhecem **só por exports**.
> O racha publica `exports.vhub_racha:openPanel(src)` (1 linha, embrulha o `send_open(src)` que já
> existe em `vhub_racha/server/init.lua:107-118`). O iPad **nunca** emite a string
> `'vhub_racha:nui:open'`. A reabertura é simétrica: o racha chama `exports.vhub_ipad:openIpad(src)`
> no seu `close`. Custo total no racha = **2 exports de 1 linha** = pontos de integração publicados,
> versionáveis e rastreáveis por grep (a string crua derrotava o protocolo de descontinuação).
>
> **v1 mínimo sem tocar o racha**: se preferir zero edição no racha agora, o app racha vira um
> "launcher" que fecha o iPad e o player abre o racha pela tecla dele. O handoff fluido (2 exports)
> entra na F3 com gate do `vhub_guardiao_contrato`.

---

## 4. CONTRATO DE DADOS server → NUI (payload de `open`)

```jsonc
{
  "action": "open",
  "api_level": 1,
  "catalog_version": 7,          // int incremental; muda a cada registerApp/unregister — invalida cache da NUI
  "cdn": "https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main",
  "apps": {                      // SÓ os apps PERMITIDOS e DISPONÍVEIS p/ este player (server filtra)
    "racha": {
      "id": "racha",
      "label": "Racha",
      "icon": "chita.png",
      "category": "entretenimento",
      "removable": true,
      "api_version": "1.0.0",
      "available": true,         // dependency resource 'started'? (server resolve)
      "mount_kind": "local",     // 'local' | 'remote'
      "entry": {                 // URLs JÁ RESOLVIDAS pelo server
        "html": "modules/racha/racha.html",
        "css":  "modules/racha/racha.css",
        "js":   "modules/racha/racha.js"
      }
    }
  },
  "prefs_defaults": { "zoom": 60, "wallpaper_id": "default" },
  "wallpapers": [                // ENUM válido server-side (não URL livre do cliente)
    { "id": "default", "url": "https://.../wp_default.jpg" },
    { "id": "carbon",  "url": "https://.../wp_carbon.jpg" }
  ]
}
```

**O que é VERDADE do server** (a NUI nunca inventa): existência de app, `permitted`, `available`,
`mount_kind`, `entry`, lista de `wallpapers`. **O que é preferência local**: zoom, wallpaper
escolhido (dentro do enum), ordem/visibilidade de ícones.

---

## 5. ESTRUTURA DE ARQUIVOS

```
resources/[SCRIPTS]/vhub_ipad/
├── fxmanifest.lua
├── shared/
│   ├── config.lua          ← VHubIpadCFG (API_LEVEL, rates, defaults, wallpapers base, builtin apps)
│   ├── events.lua          ← VHubIpadE (registro único: exports + nomes de callback)
│   └── manifest_schema.lua ← validador PURO de manifest (sem estado) — usado pelo registry
├── server/
│   ├── init.lua            ← boot, rate limiter, item-use, sessions guard
│   ├── registry.lua        ← ESCRITOR ÚNICO do catálogo (register/unregister/snapshot/gating)
│   └── exports.lua         ← registerApp/unregisterApp/openIpad/closeIpad/isOpen (_invoker_allowed)
├── client/
│   └── init.lua            ← toggle, NuiFocus, callbacks NUI, relay de handoff
└── web/
    ├── index.html
    ├── runtime/            ← 5 arquivos copiados do racha (bus/store/bridge/core/sand) — core.js OWNED/divergente
    ├── shared/
    │   ├── tokens.css      ← tema device-dark + accent dourado vHub
    │   ├── reset.css
    │   ├── utils.js        ← vhub.cdn/icon/persist/clock
    │   └── shell.js        ← controlador do shell (writer único de store('ipad'))
    └── modules/
        ├── home/           ← grade de ícones a partir do catálogo (não hardcoded)
        ├── store/          ← App Store: lista o catálogo, alterna visibilidade (pref)
        ├── settings/       ← zoom, wallpaper (enum), reset
        └── racha/          ← launcher do racha (handoff por export)
```

> Apps de terceiros **não** ficam aqui — ficam no resource deles, com `ui.source='remote'`.

---

## 6. SERVER — registry + gating

```lua
-- server/registry.lua — catálogo authoritative de apps (escritor único)

local Registry = {}; vHubIpad.Registry = Registry
local _apps    = {}     -- id → manifest validado
local _version = 0      -- catalog_version (incrementa a cada mudança)


-- ============================================================
-- ESCRITA (único ponto — via export registerApp)
-- ============================================================

-- registra/atualiza um app; retorna ok,err. valida schema antes de aceitar.
function Registry:register(manifest)
  local ok, err = vHubIpad.validateManifest(manifest)   -- shared/manifest_schema.lua
  if not ok then return false, err end
  if (manifest.manifest_level or 1) > VHubIpadCFG.API_LEVEL then
    return false, 'manifest_level_acima_do_suportado'
  end
  _apps[manifest.id] = manifest
  _version = _version + 1
  return true
end

function Registry:unregister(id)
  if _apps[id] then _apps[id] = nil; _version = _version + 1 end
end


-- ============================================================
-- LEITURA (snapshot filtrado por jogador — verdade server, L-01)
-- ============================================================

-- monta o payload de apps visíveis/abríveis para `src` (permissão + dependency + URLs resolvidas)
function Registry:snapshotFor(src)
  local user = exports.vhub:getUser(src)
  local out  = {}
  for id, m in pairs(_apps) do
    -- gating de permissão (server-authoritative)
    local permitted = (not m.permission) or (user and exports.vhub:hasPerm(user, m.permission))
    if permitted then
      out[id] = {
        id = id, label = m.label, icon = m.icon, category = m.category,
        removable = m.removable, api_version = m.version,
        available = (not m.dependency) or (GetResourceState(m.dependency) == 'started'),
        mount_kind = m.ui.source,
        entry = self:_resolveEntry(m),
      }
    end
  end
  return out, _version
end

-- resolve URLs do manifest: local → relativo ao iPad; remote → cfx-nui-<resource>
function Registry:_resolveEntry(m)
  if m.ui.source == 'remote' then
    local base = ('https://cfx-nui-%s/'):format(m.ui.resource)
    return { html = base..m.ui.html, css = base..m.ui.css, js = base..m.ui.js }
  end
  return { html = m.ui.html, css = m.ui.css, js = m.ui.js }  -- NUI faz fetch relativo
end
```

**Builtins registram pelo MESMO caminho (dogfooding)**: no `onResourceStart` do próprio iPad,
itera `VHubIpadCFG.BUILTIN_APPS` e chama `Registry:register(...)`. Settings/Store/Home/Racha não
têm caminho privilegiado — entram pelo registry como qualquer terceiro.

**Ordem de eventos** (apps de terceiros podem subir antes OU depois do iPad):
- iPad sobe → registra builtins.
- Terceiro sobe → chama `registerApp` (export). Se o iPad ainda não subiu, o terceiro re-tenta no
  `onResourceStart` do iPad (mesmo padrão `pcall + retry` do item-use do README §6.4).
- iPad expõe um evento público `vhub_ipad:server:ready` que terceiros podem escutar para registrar.

---

## 7. RUNTIME OWNED — mudanças no `core.js` (validadas pelo guardião de runtime)

O `core.js` copiado vira **owned/divergente** (D4). Quatro mudanças cirúrgicas:

### 7.1 `_loadFiles` URL-driven (suporta local e remote)
```js
// recebe o manifest entry; usa as URLs resolvidas pelo server em vez do path fixo
async function _loadFiles(name, entry) {
  const mod = _modules[name];
  if (!mod || mod._loaded) return;

  // CSS: injeta só se ainda não existir esse href (evita <link> duplicado — fix do leak G10)
  if (!document.querySelector(`link[data-mod="${name}"]`)) {
    const link = document.createElement('link');
    link.rel = 'stylesheet'; link.href = entry.css; link.dataset.mod = name;
    document.head.appendChild(link);
    mod._cssLink = link;
  }

  const html = await (await fetch(entry.html)).text();
  const wrapper = document.createElement('div');
  wrapper.id = `mod-${name}`; wrapper.className = `mod-${name} hidden`;
  wrapper.innerHTML = html;
  _appEl.appendChild(wrapper);
  mod._el = wrapper; mod._loaded = true;
}
```

### 7.2 Carregar JS do app remoto e montar SÓ após `script.onload` (A-02, sem polling/L-06)
```js
// se o spec do app ainda não foi registrado (app remoto), injeta o <script> e aguarda onload.
// createModule roda SÍNCRONO no corpo do script → no onload, _modules[id] já existe.
function _ensureRegistered(id, jsUrl) {
  return new Promise((resolve) => {
    if (_modules[id]) return resolve(true);           // builtin/local já registrado
    const s = document.createElement('script');
    s.src = jsUrl; s.dataset.app = id;
    s.onload  = () => {
      if (!_modules[id]) { console.error(`[ipad] app '${id}' carregou mas não chamou createModule`); return resolve(false); }
      if (typeof _modules[id].onDestroy !== 'function') console.warn(`[ipad] app '${id}' sem onDestroy — A-07 risco de leak`);
      resolve(true);
    };
    s.onerror = () => { console.error(`[ipad] falha ao carregar JS de '${id}'`); resolve(false); };
    document.head.appendChild(s);
  });
}
```

### 7.3 `unmount` remove o `<link>` (fix do leak) e mantém spec como cache
```js
function unmount(name) {
  const mod = _modules[name]; if (!mod) return;
  if (typeof mod.onDestroy === 'function') { try { mod.onDestroy(); } catch(e){ console.error(e); } }
  if (mod._el)     { mod._el.remove(); mod._el = null; }
  if (mod._cssLink){ mod._cssLink.remove(); mod._cssLink = null; }   // <- fix G10
  mod._loaded = false; mod._mounted = false;
  // spec PERMANECE em _modules (cache de re-mount). destroy(name) opcional p/ delete real (app oculto).
}
```

### 7.4 Regras herdadas (não mudam, mas obrigatórias no plano)
- **NÃO existe `vhub.native.*`** (G11). NUI→Lua só por `vhub.post(action,data)`; Lua→NUI por
  `SendNUIMessage` → dispatcher → `vhub.bus.emit('nui:'+action)`.
- `store.js` é merge raso **sem subscribe**. Render é **pull** (recalcular em `onShow`).
- Catálogo vai 1x no `open` e fica em `vhub.store('ipad')` — **nunca** re-fetch por navegação (A-08).

---

## 8. SHELL — `web/shared/shell.js` (writer único do `store('ipad')`, A-04/A-08)

Responsabilidades (e SÓ elas):
- **Clock**: `setInterval(60s)` iniciado no open, **destruído no close** (sem timer com NUI fechada).
- **Wallpaper**: dono do elemento `#ipad-wallpaper` (camada `background-image` GPU **atrás** de
  `#vhub-app`, no shell — não no módulo home; senão some no unmount/handoff). G6.
- **Navegação sem router**: `home.hide()` → `app.show()` (home fica em memória, sem re-fetch).
  Cross-fade por CSS no `#ipad-screen`. Pilha `history` p/ botão ◀.
- **Fullscreen handoff (sem flicker)**: app pede `vhub.post('collapse',{app})`; o shell adiciona a
  classe `ipad-collapsed` (esconde frame/statusbar/navbar via CSS, **sem unmount**). Voltar = remover
  a classe. Lifecycle preservado.
- **Owner do `store('ipad')`**: settings/store **emitem via bus** (`ipad:set_pref`,
  `ipad:toggle_app`); o shell aplica e persiste. Nenhum outro módulo escreve o slice.
- **Boot lazy (A-05)**: no `nui:open`, aplica prefs do localStorage, monta **só** `home`, e chama
  `vhub.post('nui_ready')`. Demais apps montam sob navegação.

```js
// shell.js (esqueleto — writer único de store('ipad'))
const ui = vhub.store('ipad');

vhub.bus.listen('nui:open', (data) => {
  ui.set({ catalog: data.apps, version: data.catalog_version, wallpapers: data.wallpapers,
           cdn: data.cdn, defaults: data.prefs_defaults });
  applyPrefs();                 // zoom + wallpaper_id do localStorage (validados contra data)
  document.body.classList.add('visible');
  startClock();
  goHome();                     // monta só home
});

vhub.bus.listen('nui:close', closeIpad);
vhub.bus.listen('ipad:set_pref',   (p) => { applyPref(p); persistPref(p); });   // settings → shell
vhub.bus.listen('ipad:open_app',   (d) => navigateTo(d.id));                    // home → shell
vhub.bus.listen('ipad:toggle_app', (d) => { toggleHidden(d.id); });            // store → shell
```

---

## 9. MÓDULOS BUILTIN

Cada módulo = `vhub.createModule(id, spec)` com lifecycle completo; **`onDestroy` obrigatório**
guardando os `off()` do bus (A-07).

### 9.1 `home` — grade a partir do catálogo (não hardcoded)
- Em `onShow` (pull): `view = catalogo(server) → remove hidden(localStorage) → aplica order(localStorage)`.
  IDs do localStorage ausentes do catálogo são **descartados**; IDs novos do catálogo entram no fim.
  → garante D2 (existência = server) sem 2ª fonte de verdade.
- Paginação N por página (ex.: 4×6) + dots clicáveis. Ícone: CDN + `loading="lazy"` + `onerror` placeholder.
- App com `available=false` (dependency offline) renderiza esmaecido + toast "serviço indisponível" no clique.
- `onDestroy`: remove todos os listeners de bus guardados.

### 9.2 `store` — App Store (preferência, nunca inventa app)
- Lista `catalogo(server)` por categoria. Botão alterna **visibilidade** (`removable=true`):
  "Mostrar na home" / "Ocultar". Emite `ipad:toggle_app` (shell persiste no localStorage).
- App não-removível mostra "Fixo". App de dependency offline mostra "Requer <resource>".

### 9.3 `settings` — zoom + wallpaper (enum) + reset
- Slider zoom 30–100% (preview ao vivo) → `ipad:set_pref {zoom}`.
- Wallpaper: **galeria do enum** `wallpapers` (server). Seleção → `ipad:set_pref {wallpaper_id}`.
- (Avançado) URL custom: **https-only + cap de comprimento**, validada antes de aplicar (G12).
- Reset: limpa prefs do localStorage e volta aos `prefs_defaults` do server.

### 9.4 `racha` — launcher (handoff por export, §3.4)
- Splash com botão "Abrir Painel" → `vhub.post('launchApp',{id:'racha'})`.
- Estado de disponibilidade vem do `available` do catálogo (server). Sem lógica de corrida na NUI.

---

## 10. PERSISTÊNCIA

| Chave localStorage | Tipo | Default | Dono | Reconciliação |
|---|---|---|---|---|
| `vhub_ipad.zoom` | number | `defaults.zoom` | settings→shell | clamp 30–100 |
| `vhub_ipad.wallpaper_id` | string | `defaults.wallpaper_id` | settings→shell | deve existir no enum `wallpapers`; senão default |
| `vhub_ipad.wallpaper_custom` | string? | — | settings→shell | https-only + cap; opcional/avançado |
| `vhub_ipad.ui` | `{order:[id], hidden:[id]}` | `{}` | store/home→shell | só filtra/ordena dentro do catálogo vivo |

- **localStorage NUNCA é fonte de "quais apps existem"** (D2). Só filtra/ordena/escolhe dentro do
  conjunto que o server entregou.
- **v2 (server-side, opcional)**: prefs por `char_id` em tabela própria `vhub_ipad_prefs` via
  `exports.oxmysql` (padrão garage/inventory, decisão #8) — **nunca** core cdata (G1). Cache VRAM de
  online (load em `vHub:characterLoad`, free em `playerDropped`).

---

## 11. INTEGRAÇÕES EXTERNAS

### 11.1 `vhub_inventory` — item `'ipad'`
- Adicionar `['ipad']` em `vhub_inventory/config/inventory.lua` (seção eletrônicos): durável,
  `serial=true`, `negociavel=false`. Ícone resolvido pela NUI do inventory via CDN (`ipad.png`).
- Handler via `registerItemUse` (§3.3) com `pcall + retry` em `onResourceStart` (inventory pode subir
  depois).

### 11.2 `vhub_racha` — handoff por export (§3.4)
- **Recomendado (F3)**: racha publica `exports.vhub_racha:openPanel(src)` (embrulha `send_open`) e
  chama `exports.vhub_ipad:openIpad(src)` no seu `RegisterNUICallback('close')`. 2 linhas, publicadas.
- **v1 mínimo**: app racha só fecha o iPad; player abre o racha pela tecla dele. Zero edição no racha.

---

## 12. SEGURANÇA

| Vetor | Mitigação |
|---|---|
| `registerApp` payload hostil | `validateManifest` (schema estrito) + `_invoker_allowed()` + `GetInvokingResource()`. Rejeita id/version/ui faltantes. |
| Item-use spam | rate limiter server-side (500ms) antes de `openIpad`. `playerDropped` limpa `_last`. |
| App não-permitido visível | `snapshotFor` filtra por `hasPerm` server-side (L-01); apps não-permitidos **nem vão** no payload. |
| Wallpaper URL injetada | enum server-side; custom = https-only + cap (G12). |
| NUI decidindo verdade crítica | NUI só renderiza; toda ação crítica vai por `vhub.post`→server (A-01). Catálogo/permissão/dependency = server. |
| App remoto malicioso (3rd party) | só carrega resources que o admin instalou no servidor (cfx-nui é local ao servidor, não internet). `onDestroy` validado (warn). |
| Notificação (G2) | usar export do resource dono (ex.: inventory) ou nativo; **não** assumir `exports.vhub:notify`. |

---

## 13. PERFORMANCE (orçamentos — contrato)

| Contexto | Meta | Como |
|---|---|---|
| NUI fechada | **0.00 ms** | clock destruído no close; zero RAF; apps em `.hidden` pausam (onHide) |
| NUI aberta idle | < 0.5 ms | só clock tick 60s |
| Resmon Lua idle | ≤ 0.02 ms | zero `CreateThread` em loop; só `AddEventHandler`/`RegisterNUICallback` |
| Catálogo | 1 envio/open | fica em `store('ipad')`; nunca re-fetch por navegação (A-08) |
| Lazy load (A-05) | só `home` no open | demais apps montam sob navegação; `<link>`/DOM liberados no unmount (G10) |

---

## 14. FASES (com DoD por fase)

### F0 — Estrutura canônica + runtime
- Reescrever `fxmanifest.lua` (canônico, `lua54 'yes'`, listar TODOS os files).
- Copiar os **5** arquivos do runtime; deletar protótipo (`client.lua`, `css/`, `html/`, `js/`).
- Shell mínimo abre/fecha com NuiFocus correto.
- **DoD**: `/ipad` abre/fecha; resmon idle ≤ 0.02ms; `node --check` em todos os JS; `luac` em todos os Lua.

### F1 — Registry server + builtins por dogfooding
- `registry.lua` + `manifest_schema.lua` + `exports.lua` (`registerApp/unregister/openIpad/closeIpad`).
- `shared/config.lua` com `API_LEVEL`, `BUILTIN_APPS`, `wallpapers` base.
- **Inserir a linha do Registro no `contexto.md`** (via `vhub_guardiao_revisao`) ANTES de codar (arquiteto).
- **DoD**: builtins aparecem no snapshot; `registerApp` rejeita manifest inválido; gate de persistência+contrato.

### F2 — Home + Store + Settings (loader `local`)
- Os 3 módulos consumindo o snapshot; loader URL-driven funcionando para `local`.
- Identidade visual confirmada com `vhub_guardiao_designer` (D7: dark + accent dourado).
- **DoD**: ocultar/mostrar app persiste (localStorage) sem virar 2ª fonte; zoom/wallpaper aplicam; A-05/A-07 ok.

### F3 — Integração racha (handoff por export) + loader `remote`
- App racha + `exports.vhub_racha:openPanel` + reabertura simétrica.
- Validar carregamento `remote` (cfx-nui) com um app de teste.
- **Mapear o ponto real de handoff antes de codar** (arquiteto achado #3).
- **DoD**: abrir racha pelo iPad e voltar sem flicker; gate de contrato.

### F4 — Hardening + persistência v2
- `permission`/`dependency` gating completo; throttle de `openIpad`; testes runtime.
- (Opcional) prefs server-side `vhub_ipad_prefs` (oxmysql próprio).
- Engine v2 (memória): `vhub.raf`/`vhub.interval` rastreados e auto-cancelados no unmount (forçar A-07).
- **DoD**: gate final `vhub_guardiao_revisao` + atualização do `contexto.md`.

---

## 15. COMO ADICIONAR UM APP NOVO (a prova da modularidade)

**Caso A — app builtin (vive no iPad):**
1. Criar `web/modules/<id>/{<id>.html,<id>.css,<id>.js}` (lifecycle padrão).
2. Adicionar o manifest em `VHubIpadCFG.BUILTIN_APPS`.
3. Listar os 3 arquivos no `fxmanifest.lua`.
   → Pronto. Zero mudança em registry/shell/home.

**Caso B — app de terceiro (vive em OUTRO resource — sem tocar o `vhub_ipad`):**
1. No SEU resource, criar a UI (`web/app/<id>.{html,css,js}`) com lifecycle padrão e
   `createModule('<id>', {...})`.
2. Listar esses arquivos em `files{}` do SEU `fxmanifest.lua` (CEF precisa servi-los).
3. No `onResourceStart` do SEU resource:
   ```lua
   exports.vhub_ipad:registerApp({
     id='meuapp', version='1.0.0', label='Meu App', icon='meuapp.png',
     category='utilidades', removable=true, dependency='meu_resource',
     ui = { source='remote', resource='meu_resource',
            html='web/app/meuapp.html', css='web/app/meuapp.css', js='web/app/meuapp.js' },
   })
   ```
   → Pronto. O app aparece na App Store e na home. **Zero edição no `vhub_ipad`.**

---

## 16. PENDÊNCIAS QUE EXIGEM DECISÃO/GATE ANTES DE CODAR

1. **Linha do Registro no `contexto.md`** — escrever ANTES da F1 (arquiteto, obrigatório).
2. **Identidade visual** (D7) — confirmar dark+dourado com `vhub_guardiao_designer` na F2.
3. **Edição no `vhub_racha`** (F3) — 2 exports de 1 linha; gate `vhub_guardiao_contrato`. Decidir se
   entra na v1 (handoff fluido) ou fica como "launcher" simples primeiro.
4. **Mecanismo de notify** (G2) — confirmar a fonte real de toast no servidor (qual export/nativo).

---

*Plano consolidado dos veredictos: `vhub_arquiteto` (APROVAR + 2 reduções de escopo),
`vhub_designer` (ajustes de contrato de dados + ownership do wallpaper),
`vhub_guardiao_runtime` (loader/leak/onload/A-07),
`vhub_guardiao_contrato` (handoff por export + versionamento do manifest).*
