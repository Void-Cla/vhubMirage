# PROMPT MESTRE — `vhub_ipad` v2 (Sistema de Tablet para FiveM)

> **Destinatário**: IA de implementação com acesso ao repositório completo  
> **Escopo**: Refatoração total do `resources/[SCRIPTS]/vhub_ipad` + integrações  
> **Contexto completo abaixo — leia TODO antes de escrever 1 linha de código**

---

## 1. CONTEXTO DO PROJETO

**Framework**: vHub Mirage — NÃO é vRP2 padrão e um vhub original. É um fork interno com APIs próprias.  
**Core**: `[CORE]/vhub` — FROZEN v1.0 (2026-05-22). **Nunca modificar.**  
**Lei-mestra**: `manual_dev_vhub.md` — toda decisão arquitetural segue esse documento.  
**Linguagem Lua**: 5.4, com `lua54 'yes'` no fxmanifest.  
**CDN de assets**: `https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main`  
**Repositório de assets**: `https://github.com/Void-Cla/vhub-assets`

### APIs fundamentais do vHub (exports do core)
```lua
exports.vhub:getUser(src)          -- retorna { source, char_id, uid, ... } | nil
exports.vhub:getCData(char_id, k)  -- lê KV de personagem (chave prefixada 'vhub_ipad_*')
exports.vhub:setCData(char_id, k, v) -- escreve KV (batch interno)
exports.vhub:notify(src, msg)      -- toast nativo
```

### Padrão de rate limiter (copiar, não reinventar)
```lua
-- server/core.lua de qualquer resource vHub
local _last = {}
function Core.rate(src, key, ms)
  local now = GetGameTimer()
  local k = src .. ':' .. key
  if (now - (_last[k] or 0)) < ms then return false end
  _last[k] = now; return true
end
AddEventHandler('playerDropped', function()
  local p = source .. ':'; for k in pairs(_last) do if k:sub(1,#p)==p then _last[k]=nil end end
end)
```

---

## 2. ESTADO ATUAL DO `vhub_ipad` (protótipo)

```
resources/[SCRIPTS]/vhub_ipad/
├── client.lua       ← toggle /ipad + F1, exports Open/Close/SetZoom/SetWallpaper
├── css/style.css    ← frame SVG, painel de controles (glassmorphism dark)
├── html/index.html  ← SVG do iPad com wallpaper + botão 3-pontos
├── js/app.js        ← zoom, wallpaper, controles
└── fxmanifest.lua   ← básico (não segue padrão canônico)
```

**O protótipo TEM**: frame SVG do iPad bem feito (manter visual), zoom funcional, troca de wallpaper, panel de controles glassmorphism.  
**O protótipo NÃO TEM**: home screen com ícones, navegação, App Store, persistência, integração com inventory/racha, padrão de módulos vHub.

**Ação**: Refatorar COMPLETAMENTE para o padrão canônico. Manter o visual do frame SVG como referência.

---

## 3. OBJETIVO FINAL

Um tablet iOS-style que substitui comandos `/cmd` por ícones clicáveis, com:

| Feature | Detalhe |
|---|---|
| Home screen | Grade de ícones de apps instalados (múltiplas páginas via dots) |
| Barra de navegação | ◀ Voltar · ⌂ Home · × Fechar iPad (fixo na base) |
| App Store | Listar apps disponíveis + instalar/desinstalar |
| App: Configurações | Zoom, wallpaper, reset — estado persiste em localStorage |
| App: Racha | Abre painel do `vhub_racha` (v1: delegate; v2: iframe embutido) |
| Persistência | localStorage CEF: zoom, wallpaper, apps instalados, ordem dos ícones |
| Item no inventário | `'ipad'` no `vhub_inventory` — usar item abre o tablet |
| Status bar | Relógio fake (hora local), bateria estática |

---

## 4. ARQUITETURA DA NUI (PADRÃO vHub OBRIGATÓRIO)

### 4.1 Runtime

Copie o runtime do `vhub_racha/web/runtime/` (versão avançada com lazy-load):

```
web/runtime/
├── bus.js      ← vhub.emit / vhub.listen (event bus inter-módulo)
├── store.js    ← vhub.store(domain) com get/set/patch
├── bridge.js   ← vhub.post(action, data) → Promise (com timeout 8s)
└── core.js     ← createModule/mount/show/hide/unmount + dispatcher window.message
```

> **bridge.js**: `GetParentResourceName()` retorna `'vhub_ipad'` — não hardcode o nome.

### 4.2 Lazy-load de módulos (padrão do core.js do racha)

`vhub.mount('settings')` faz `fetch('modules/settings/settings.html')` e injeta CSS/HTML automaticamente. Cada módulo é um diretório `web/modules/<nome>/` com três arquivos: `.html`, `.css`, `.js`.

### 4.3 Dispatcher de mensagens

O `core.js` escuta `window.addEventListener('message')` e emite via bus:
- Shape `{ action, data }` → emite `'nui:' + action`
- Shape `{ type, payload }` → emite `'nui:' + type`

Módulos escutam: `vhub.bus.listen('nui:open', fn)` — nunca escutam `window.message` diretamente.

---

## 5. ESTRUTURA COMPLETA DE ARQUIVOS

```
resources/[SCRIPTS]/vhub_ipad/
├── fxmanifest.lua
├── shared/
│   ├── config.lua        ← VHubIpadCFG.* (global, sem return)
│   └── events.lua        ← VHubIpadE.* (global, sem return)
├── server/
│   └── init.lua          ← item_use, session guard, exports
├── client/
│   └── init.lua          ← toggle, NuiFocus, callbacks NUI, relay racha
└── web/
    ├── index.html
    ├── runtime/           ← copiar de vhub_racha/web/runtime/ (4 arquivos)
    ├── shared/
    │   ├── tokens.css     ← CSS vars do tema vHub
    │   ├── reset.css      ← reset canônico
    │   └── utils.js       ← vhub.cdn, vhub.icon(), vhub.persist.get/set
    └── modules/
        ├── home/          ← home.html + home.css + home.js
        ├── settings/      ← settings.html + settings.css + settings.js
        ├── store/         ← store.html + store.css + store.js
        └── racha/         ← racha.html + racha.css + racha.js
```

---

## 6. ESPECIFICAÇÃO DE CADA ARQUIVO

### 6.1 `fxmanifest.lua`

```lua
---@diagnostic disable: undefined-global, lowercase-global
fx_version 'cerulean'
game       'gta5'
lua54      'yes'

name        'vhub_ipad'
author      'vHub Mirage'
version     '2.0.0'
description 'Sistema de tablet iOS — shell de apps vHub'

dependencies {
  'vhub',
  'vhub_inventory',
}
-- vhub_racha é soft-dep (verificado em runtime via GetResourceState)

shared_scripts {
  'shared/config.lua',
  'shared/events.lua',
}

server_scripts {
  'server/init.lua',
}

client_scripts {
  'client/init.lua',
}

ui_page 'web/index.html'

files {
  'web/index.html',
  'web/runtime/bus.js',
  'web/runtime/store.js',
  'web/runtime/bridge.js',
  'web/runtime/core.js',
  'web/shared/tokens.css',
  'web/shared/reset.css',
  'web/shared/utils.js',
  'web/modules/home/home.html',
  'web/modules/home/home.css',
  'web/modules/home/home.js',
  'web/modules/settings/settings.html',
  'web/modules/settings/settings.css',
  'web/modules/settings/settings.js',
  'web/modules/store/store.html',
  'web/modules/store/store.css',
  'web/modules/store/store.js',
  'web/modules/racha/racha.html',
  'web/modules/racha/racha.css',
  'web/modules/racha/racha.js',
}
```

---

### 6.2 `shared/config.lua`

```lua
---@diagnostic disable: undefined-global, lowercase-global

VHubIpadCFG = VHubIpadCFG or {}

VHubIpadCFG.CDN = 'https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main'

VHubIpadCFG.DEFAULTS = {
  zoom      = 60,
  wallpaper = 'https://media.discordapp.net/attachments/1475217847859937333/1514419365733208256/wp7996624.jpg?format=webp&width=998&height=562',
}

-- catálogo de apps disponíveis (fonte de verdade do servidor)
-- 'builtin' = módulo NUI interno ao vhub_ipad
-- 'removable' = pode ser desinstalado da home screen
-- 'dependency' = resource que precisa estar rodando (verificado no client)
VHubIpadCFG.APPS = {
  configuracoes = {
    id        = 'configuracoes',
    label     = 'Configurações',
    icon      = 'configuracao.png',   -- relativo ao CDN (utils.js monta URL)
    module    = 'settings',
    builtin   = true,
    removable = false,
    category  = 'sistema',
  },
  racha = {
    id         = 'racha',
    label      = 'Racha',
    icon       = 'chita.png',
    module     = 'racha',
    builtin    = true,
    removable  = true,
    category   = 'entretenimento',
    dependency = 'vhub_racha',
  },
  -- extensão futura: outros resources registram via export
}

-- apps pré-instalados por padrão (localStorage sobrescreve se player customizou)
VHubIpadCFG.DEFAULT_INSTALLED = { 'configuracoes', 'racha' }

VHubIpadCFG.rates = {
  use_ipad = 500,   -- cooldown ms para usar o item
}

-- v1 = false (delegate: fecha iPad, abre racha fullscreen)
-- v2 = true  (embed: iframe dentro do iPad com scale transform)
VHubIpadCFG.EMBED_MODE = false
```

---

### 6.3 `shared/events.lua`

```lua
---@diagnostic disable: undefined-global, lowercase-global

-- fonte ÚNICA de nomes de eventos — GLOBAL, sem return
VHubIpadE = {
  OPEN         = 'vhub_ipad:client:Open',
  CLOSE        = 'vhub_ipad:client:Close',
  RACHA_CLOSED = 'vhub_ipad:client:RachaClosed',  -- racha sinalizou que fechou
}
```

---

### 6.4 `server/init.lua`

```lua
---@diagnostic disable: undefined-global, lowercase-global

-- server/init.lua — registro do item + sessões + rate limiter

local Core = {}
local _last = {}

function Core.rate(src, key, ms)
  local now = GetGameTimer()
  local k = src .. ':' .. key
  if (now - (_last[k] or 0)) < ms then return false end
  _last[k] = now; return true
end

AddEventHandler('playerDropped', function()
  local p = source .. ':'
  for k in pairs(_last) do if k:sub(1,#p)==p then _last[k]=nil end end
end)

-- registra handler do item 'ipad' (com pcall: inventory pode carregar depois)
local function registerIpadItem()
  local ok, err = pcall(function()
    exports.vhub_inventory:registerItemUse('ipad', function(src, _slot, _meta)
      if not Core.rate(src, 'use_ipad', VHubIpadCFG.rates.use_ipad) then return false end
      TriggerClientEvent(VHubIpadE.OPEN, src)
      return false  -- não consome o item (é durável)
    end)
  end)
  if not ok then
    print('[vhub_ipad] registerItemUse falhou (tentará em onResourceStart):', tostring(err))
  end
  return ok
end

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() and res ~= 'vhub_inventory' then return end
  CreateThread(function()
    Wait(500)
    registerIpadItem()
  end)
end)
```

---

### 6.5 `client/init.lua`

```lua
---@diagnostic disable: undefined-global, lowercase-global

-- client/init.lua — toggle, NuiFocus, callbacks, relay vhub_racha

local isOpen   = false
local appOpen  = nil   -- id do app aberto fora do iPad (ex: 'racha')

-- ── Abrir / Fechar ────────────────────────────────────────────────────────

local function openIpad(payload)
  if isOpen then return end
  isOpen = true
  SetNuiFocus(true, true)
  SendNUIMessage({
    action  = 'open',
    apps    = VHubIpadCFG.APPS,
    cdn     = VHubIpadCFG.CDN,
    defaults = VHubIpadCFG.DEFAULTS,
    embed   = VHubIpadCFG.EMBED_MODE,
  })
end

local function closeIpad()
  if not isOpen then return end
  isOpen  = false
  appOpen = nil
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
end

-- ── Eventos de rede ───────────────────────────────────────────────────────

RegisterNetEvent(VHubIpadE.OPEN)
AddEventHandler(VHubIpadE.OPEN, openIpad)

-- quando racha sinaliza que fechou o painel, reabre o iPad
AddEventHandler(VHubIpadE.RACHA_CLOSED, function()
  if appOpen == 'racha' then
    appOpen = nil
    openIpad()
  end
end)

-- ── Comandos (fallback / dev) ──────────────────────────────────────────────

RegisterCommand('ipad', function()
  if isOpen then closeIpad() else openIpad() end
end, false)
RegisterKeyMapping('ipad', 'Abrir / Fechar iPad', 'keyboard', 'F1')

-- ── NUI Callbacks ─────────────────────────────────────────────────────────

-- fechar pela NUI (botão × ou ESC)
RegisterNUICallback('close', function(_, cb)
  closeIpad()
  cb({ ok = true })
end)

-- app racha solicitou abertura: fecha iPad e abre racha
RegisterNUICallback('openRacha', function(_, cb)
  if GetResourceState('vhub_racha') ~= 'started' then
    cb({ ok = false, err = 'vhub_racha_offline' })
    return
  end
  isOpen  = false
  appOpen = 'racha'
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
  -- dispara abertura do painel do racha via evento do resource
  TriggerServerEvent(VHubRachaE.NUI_OPEN)
  cb({ ok = true })
end)

-- salvar preferências persistentes (NUI as envia ao mudar; server não precisa saber)
RegisterNUICallback('nui_ready', function(data, cb)
  cb({ ok = true, apps = VHubIpadCFG.APPS, cdn = VHubIpadCFG.CDN })
end)

-- ── Exports ───────────────────────────────────────────────────────────────

exports('OpenIpad',  openIpad)
exports('CloseIpad', closeIpad)
```

**IMPORTANTE**: O `client/init.lua` usa `VHubRachaE.NUI_OPEN` — essa constante vem de `vhub_racha/shared/events.lua`, que é `shared_scripts` do resource racha. Como os `shared_scripts` de outros resources NÃO são carregados automaticamente, você tem duas opções:

- **Opção A (recomendada)**: Hardcode a string `'vhub_racha:nui:open'` localmente com comentário explicativo, já que é uma dependência externa:
  ```lua
  local RACHA_NUI_OPEN = 'vhub_racha:nui:open'  -- VHubRachaE.NUI_OPEN
  ```
- **Opção B**: Adicionar `vhub_racha/shared/events.lua` como shared_script do ipad (cria acoplamento forte).

Use a **Opção A**.

---

### 6.6 `web/shared/utils.js`

```js
// web/shared/utils.js — helpers puros globais

// CDN (preenchido pelo Lua via SendNUIMessage { action:'open', cdn:... })
vhub.cdn = 'https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main';

// monta URL completa de ícone a partir do nome do arquivo
vhub.icon = function(filename) {
  return `${vhub.cdn}/${filename}`;
};

// Persistência via localStorage CEF
// Em FiveM CEF (Chromium), localStorage persiste entre sessões.
// Use sempre com try/catch (pode falhar em modo privado/modo sandbox).
vhub.persist = {
  get(key, defaultValue) {
    try {
      const raw = localStorage.getItem('vhub_ipad.' + key);
      return raw != null ? JSON.parse(raw) : defaultValue;
    } catch { return defaultValue; }
  },
  set(key, value) {
    try { localStorage.setItem('vhub_ipad.' + key, JSON.stringify(value)); }
    catch {}
  },
  remove(key) {
    try { localStorage.removeItem('vhub_ipad.' + key); }
    catch {}
  },
};

// Formata hora atual HH:MM
vhub.clock = function() {
  const d = new Date();
  return String(d.getHours()).padStart(2,'0') + ':' + String(d.getMinutes()).padStart(2,'0');
};
```

---

### 6.7 `web/index.html`

Estrutura (sem CSS/JS inline; tudo em arquivos separados):

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <link rel="stylesheet" href="shared/tokens.css" />
  <link rel="stylesheet" href="shared/reset.css" />
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
</head>
<body>
  <!--
    Layout:
    body (hidden por padrão, display:flex quando 'visible')
      └─ #ipad-wrapper (posição + sombra + zoom via CSS var)
           └─ #ipad-frame (SVG bezel reutilizado do protótipo)
                ├─ #ipad-statusbar (hora + bateria)
                ├─ #ipad-screen  (área onde os módulos são montados)
                │    └─ #vhub-app  (ponto de injeção dos módulos lazy)
                └─ #ipad-navbar   (◀ Home × — sempre visível)
  -->
  <div id="ipad-wrapper">
    <div id="ipad-frame">
      <!-- SVG bezel do iPad (reutilizar do protótipo, ajustar proporções) -->
      <!-- Status bar dentro da tela -->
      <div id="ipad-statusbar">
        <span id="ipad-clock">00:00</span>
        <div id="ipad-statusbar-icons">
          <span>📶</span><span>🔋 87%</span>
        </div>
      </div>
      <!-- Área de conteúdo -->
      <div id="ipad-screen">
        <div id="vhub-app"></div>
      </div>
      <!-- Barra de navegação inferior (sempre visível) -->
      <nav id="ipad-navbar">
        <button id="btn-back"  data-action="back"  title="Voltar">◀</button>
        <button id="btn-home"  data-action="home"  title="Home">⌂</button>
        <button id="btn-close" data-action="close" title="Fechar iPad">×</button>
      </nav>
    </div>
  </div>

  <!-- Runtime (ordem obrigatória) -->
  <script src="runtime/bus.js"></script>
  <script src="runtime/store.js"></script>
  <script src="runtime/bridge.js"></script>
  <script src="runtime/core.js"></script>
  <script src="shared/utils.js"></script>

  <!-- Módulos (auto-registram via createModule) -->
  <script src="modules/home/home.js"></script>
  <script src="modules/settings/settings.js"></script>
  <script src="modules/store/store.js"></script>
  <script src="modules/racha/racha.js"></script>

  <!-- Bootstrap + shell controller -->
  <script src="shared/shell.js"></script>
</body>
</html>
```

**ADICIONAR** `web/shared/shell.js` ao fxmanifest `files` e à lista de `shared/` — veja seção 6.8.

---

### 6.8 `web/shared/shell.js` (controlador do shell)

Este arquivo centraliza a lógica do shell (navegação, clock, eventos NUI principais). Evita espalhar lógica pelo HTML.

```js
// web/shared/shell.js — controlador do shell do iPad

(function() {
  'use strict';

  let clockTimer = null;
  let currentModule = null;
  let history = [];   // pilha de navegação: ['home', 'racha', ...]

  // ── Clock ────────────────────────────────────────────────────────────────
  function startClock() {
    if (clockTimer) return;
    const el = document.getElementById('ipad-clock');
    function tick() { if (el) el.textContent = vhub.clock(); }
    tick();
    clockTimer = setInterval(tick, 60000);
  }
  function stopClock() {
    if (clockTimer) { clearInterval(clockTimer); clockTimer = null; }
  }

  // ── Navegação ─────────────────────────────────────────────────────────────
  async function navigateTo(moduleName) {
    if (moduleName === currentModule) return;
    if (currentModule) {
      vhub.hide(currentModule);
      history.push(currentModule);
    }
    currentModule = moduleName;
    await vhub.show(moduleName);
    vhub.bus.emit('ipad:nav_changed', { current: moduleName, history });
  }

  function goBack() {
    if (history.length === 0) return navigateTo('home');
    const prev = history.pop();
    if (currentModule) vhub.hide(currentModule);
    currentModule = prev;
    vhub.show(prev);
    vhub.bus.emit('ipad:nav_changed', { current: currentModule, history });
  }

  function goHome() {
    history = [];
    if (currentModule && currentModule !== 'home') vhub.hide(currentModule);
    currentModule = 'home';
    vhub.show('home');
    vhub.bus.emit('ipad:nav_changed', { current: 'home', history });
  }

  // ── Abrir / Fechar iPad ───────────────────────────────────────────────────
  function openIpad(data) {
    // atualiza CDN se vier do Lua
    if (data && data.cdn) vhub.cdn = data.cdn;
    document.body.classList.add('visible');
    startClock();
    goHome();
    vhub.bus.emit('ipad:opened', data || {});
  }

  function closeIpad() {
    stopClock();
    document.body.classList.remove('visible');
    vhub.bus.emit('ipad:closed', {});
    vhub.post('close', {});
  }

  // ── Navbar buttons ────────────────────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', function() {
    document.getElementById('btn-back') ?.addEventListener('click', goBack);
    document.getElementById('btn-home') ?.addEventListener('click', goHome);
    document.getElementById('btn-close')?.addEventListener('click', closeIpad);
  });

  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') closeIpad();
  });

  // ── Escuta eventos NUI do Lua ─────────────────────────────────────────────
  vhub.bus.listen('nui:open',  openIpad);
  vhub.bus.listen('nui:close', closeIpad);

  // ── Bus inter-módulo ──────────────────────────────────────────────────────
  // módulos emitem 'ipad:open_app' para navegar
  vhub.bus.listen('ipad:open_app', function(data) {
    if (data && data.module) navigateTo(data.module);
  });

  // ── Bootstrap ─────────────────────────────────────────────────────────────
  (async function() {
    // pré-monta módulos que precisam estar prontos ao abrir
    for (const name of ['home', 'settings', 'store', 'racha']) {
      try { await vhub.mount(name); }
      catch(e) { console.error('[ipad shell] mount', name, e); }
    }
    // sinaliza Lua que NUI está pronta
    try { await vhub.post('nui_ready', { href: location.href }); }
    catch {}
  })();

  // export para debug
  window._iPadShell = { navigateTo, goBack, goHome, openIpad, closeIpad };

})();
```

---

### 6.9 Módulo `home` — Home Screen

**home.html**:
- `<div class="home-pages">` com suporte a múltiplas páginas
- `<div class="home-grid">` com ícones renderizados por JS
- `<div class="home-dots">` para indicar página atual

**home.js**:
```js
vhub.createModule('home', {
  _apps: [],         // lista de apps instalados (do localStorage)
  _allApps: {},      // catálogo completo (recebido via bus de NUI open)
  _offUninstall: null,

  onInit() {
    // escuta catálogo de apps ao abrir o iPad
    vhub.bus.listen('nui:open', (data) => {
      if (data && data.apps) {
        this._allApps = data.apps;
        this._loadInstalled();
      }
    });
    // escuta evento de instalar/desinstalar vindo do módulo store
    vhub.bus.listen('ipad:install_app',   (d) => this._install(d.id));
    vhub.bus.listen('ipad:uninstall_app', (d) => this._uninstall(d.id));
  },

  onMount(el) {
    this._el = el;
    this._renderGrid();
  },

  onShow() { this._renderGrid(); },
  onHide() {},
  onDestroy() { /* listeners do bus são removidos automaticamente? NÃO — guarde os off() */ },

  _loadInstalled() {
    const saved = vhub.persist.get('installed_apps', null);
    this._apps  = saved || (this._allApps ? Object.keys(this._allApps).filter(id => {
      const a = this._allApps[id];
      // inclui se não é removível ou se está na lista default
      return !a.removable || (window._ipadDefaults || []).includes(id);
    }) : []);
  },

  _install(id) {
    if (!this._apps.includes(id)) {
      this._apps.push(id);
      vhub.persist.set('installed_apps', this._apps);
      this._renderGrid();
    }
  },

  _uninstall(id) {
    const app = this._allApps[id];
    if (app && !app.removable) return;
    this._apps = this._apps.filter(a => a !== id);
    vhub.persist.set('installed_apps', this._apps);
    this._renderGrid();
  },

  _renderGrid() {
    const grid = this._el?.querySelector('.home-grid');
    if (!grid) return;
    grid.innerHTML = '';
    for (const id of this._apps) {
      const app = this._allApps[id];
      if (!app) continue;
      const icon = document.createElement('button');
      icon.className = 'home-icon';
      icon.innerHTML = `
        <img src="${vhub.icon(app.icon)}" alt="${app.label}"
             loading="lazy" onerror="this.src='data:image/svg+xml,<svg/>'">
        <span>${app.label}</span>
      `;
      icon.addEventListener('click', () => {
        vhub.bus.emit('ipad:open_app', { id, module: app.module });
      });
      grid.appendChild(icon);
    }
  },
});
```

**home.css**: Grid CSS com `display: grid; grid-template-columns: repeat(auto-fill, minmax(80px, 1fr)); gap: 16px;`. Ícones 64×64, label 11px abaixo.

---

### 6.10 Módulo `settings` — Configurações

**Conteúdo**:
- Título "Configurações"
- Seção "Aparência": slider zoom (30–100%) com preview ao vivo + label "%"
- Seção "Wallpaper": input URL + botão Aplicar + botão Reset
- Salva no localStorage **e** envia para Lua via `vhub.post`

**settings.js** (pontos-chave):
```js
vhub.createModule('settings', {
  _zoom: 60,
  _wallpaper: '',

  onMount(el) {
    this._el = el;
    // carrega do localStorage
    this._zoom      = vhub.persist.get('zoom', 60);
    this._wallpaper = vhub.persist.get('wallpaper', '');
    this._apply();
    // wire eventos
    el.querySelector('#settings-zoom')?.addEventListener('input', e => {
      this._zoom = +e.target.value;
      el.querySelector('#settings-zoom-val').textContent = this._zoom + '%';
      this._applyZoom();
      vhub.persist.set('zoom', this._zoom);
    });
    el.querySelector('#settings-apply-wp')?.addEventListener('click', () => {
      const url = el.querySelector('#settings-wp-input').value.trim();
      if (url) { this._wallpaper = url; this._applyWallpaper(); }
    });
    el.querySelector('#settings-reset')?.addEventListener('click', () => this._reset());
  },

  onShow() { this._apply(); },
  onHide() {},
  onDestroy() {},

  _applyZoom() {
    document.getElementById('ipad-wrapper').style.width = this._zoom + 'vw';
    vhub.persist.set('zoom', this._zoom);
  },
  _applyWallpaper() {
    const screen = document.getElementById('ipad-wallpaper');
    if (screen) screen.setAttribute('href', this._wallpaper);
    vhub.persist.set('wallpaper', this._wallpaper);
  },
  _apply() { this._applyZoom(); if (this._wallpaper) this._applyWallpaper(); },
  _reset() {
    this._zoom = 60; this._wallpaper = '';
    vhub.persist.remove('zoom'); vhub.persist.remove('wallpaper');
    this._apply();
  },
});
```

---

### 6.11 Módulo `store` — App Store

**store.html**: lista de cards de apps com nome, ícone, categoria e botão Instalar/Remover.

**store.js** (pontos-chave):
```js
vhub.createModule('store', {
  _allApps: {},
  _installed: [],

  onInit() {
    vhub.bus.listen('nui:open', (data) => {
      if (data?.apps) this._allApps = data.apps;
    });
    // sincroniza lista instalada quando home atualiza
    vhub.bus.listen('ipad:install_app',   d => this._installed.push(d.id));
    vhub.bus.listen('ipad:uninstall_app', d => {
      this._installed = this._installed.filter(x => x !== d.id);
    });
  },

  onMount(el) {
    this._el = el;
    this._installed = vhub.persist.get('installed_apps', []);
  },

  onShow() { this._render(); },
  onHide() {},
  onDestroy() {},

  _render() {
    const list = this._el?.querySelector('.store-list');
    if (!list) return;
    list.innerHTML = '';
    for (const [id, app] of Object.entries(this._allApps)) {
      const isInstalled = this._installed.includes(id);
      const card = document.createElement('div');
      card.className = 'store-card';
      card.innerHTML = `
        <img src="${vhub.icon(app.icon)}" class="store-icon">
        <div class="store-info">
          <strong>${app.label}</strong>
          <small>${app.category || ''}</small>
        </div>
        <button class="store-btn ${isInstalled ? 'installed' : ''}"
                data-app="${id}" data-installed="${isInstalled}">
          ${isInstalled ? (app.removable ? 'Remover' : 'Instalado') : 'Instalar'}
        </button>
      `;
      card.querySelector('.store-btn').addEventListener('click', (e) => {
        const installed = e.target.dataset.installed === 'true';
        if (installed && app.removable) {
          vhub.bus.emit('ipad:uninstall_app', { id });
        } else if (!installed) {
          vhub.bus.emit('ipad:install_app', { id });
        }
        this._render();
      });
      list.appendChild(card);
    }
  },
});
```

---

### 6.12 Módulo `racha` — App Racha

**v1 (EMBED_MODE = false)**: Tela de splash com botão que chama `vhub.post('openRacha', {})`.

**v2 (EMBED_MODE = true, deixar esqueleto preparado)**: Iframe com `https://cfx-nui-vhub_racha/web/index.html` dentro da screen area.

**racha.html**:
```html
<div class="racha-splash" data-el="splash">
  <img class="racha-app-icon" src="" data-cdn-icon="chita.png">
  <h2>Mirage Racha</h2>
  <p class="racha-status" data-el="status">Verificando serviço...</p>
  <button class="racha-open-btn" data-el="open-btn">Abrir Painel</button>
</div>
<!-- slot para v2 (iframe embedding) -->
<div class="racha-embed hidden" data-el="embed">
  <!-- iframe injetado dinamicamente em v2 -->
</div>
```

**racha.js**:
```js
vhub.createModule('racha', {
  _embedMode: false,

  onInit() {
    vhub.bus.listen('nui:open', (data) => {
      this._embedMode = !!(data && data.embed);
    });
  },

  onMount(el) {
    this._el = el;
    const btn = el.querySelector('[data-el="open-btn"]');
    const icon = el.querySelector('[data-cdn-icon]');
    if (icon) icon.src = vhub.icon('chita.png');
    btn?.addEventListener('click', () => this._open());
  },

  onShow() {
    // verifica se racha está disponível (Lua enviou no payload de open)
    const status = this._el?.querySelector('[data-el="status"]');
    const btn    = this._el?.querySelector('[data-el="open-btn"]');
    // disponibilidade checada pelo Lua; assume disponível aqui
    if (status) status.textContent = 'Serviço disponível';
    if (btn)    btn.disabled = false;
  },

  onHide() {},
  onDestroy() { this._removeIframe(); },

  _open() {
    if (this._embedMode) {
      this._openEmbed();
    } else {
      // v1: delega para Lua fechar iPad e abrir racha fullscreen
      vhub.post('openRacha', {}).then(res => {
        if (!res.ok) {
          const status = this._el?.querySelector('[data-el="status"]');
          if (status) status.textContent = 'Racha offline — tente mais tarde';
        }
      });
    }
  },

  // v2: iframe embedding (preparado, ativado com EMBED_MODE = true)
  _openEmbed() {
    const embedDiv = this._el?.querySelector('[data-el="embed"]');
    const splash   = this._el?.querySelector('[data-el="splash"]');
    if (!embedDiv || !splash) return;
    splash.classList.add('hidden');
    embedDiv.classList.remove('hidden');
    if (!embedDiv.querySelector('iframe')) {
      const iframe = document.createElement('iframe');
      // FiveM CEF permite carregar NUI de outros resources via cfx-nui://
      iframe.src = 'https://cfx-nui-vhub_racha/web/index.html';
      iframe.style.cssText = 'width:100%;height:100%;border:none;';
      embedDiv.appendChild(iframe);
    }
  },

  _removeIframe() {
    this._el?.querySelector('iframe')?.remove();
  },
});
```

---

## 7. DESIGN VISUAL

### 7.1 Tokens CSS (`web/shared/tokens.css`)

```css
:root {
  /* Cores base (dark, igual ao protótipo) */
  --ipad-bg:          #0d0d0f;
  --ipad-bezel:       #1a1a1c;
  --ipad-bezel-edge:  #2a2a2c;
  --ipad-screen-bg:   #000;
  --ipad-glass:       rgba(28,28,32,0.78);
  --ipad-glass-light: rgba(255,255,255,0.08);
  --ipad-border:      rgba(255,255,255,0.15);
  --ipad-text:        rgba(255,255,255,0.9);
  --ipad-text-dim:    rgba(255,255,255,0.5);
  --ipad-accent:      #fff;

  /* Zoom (default, sobrescrito por CSS do settings) */
  --ipad-zoom: 60vw;

  /* Transitions */
  --ipad-trans: 0.2s ease;

  /* Navbar */
  --navbar-h: 48px;

  /* Status bar */
  --statusbar-h: 28px;
}
```

### 7.2 Diretrizes visuais

- **Frame iPad**: manter SVG do protótipo (bezel gradiente dark, câmera central, botão físico lateral)
- **Screen area**: `position: absolute` dentro do bezel, com clip-path
- **Status bar**: topo da screen, fundo semi-transparente, hora + ícones à direita
- **Home screen**: fundo = wallpaper do localStorage (default: URL do protótipo), grid de ícones sobre ele
- **Ícones**: `width:64px; height:64px; border-radius:16px; object-fit:cover`, sombra leve
- **Navbar**: barra inferior com glassmorphism, 3 botões icon-only
- **Módulos**: fundo `var(--ipad-glass)` com `backdrop-filter: blur(24px)`
- **Transições entre módulos**: `opacity 0.15s ease + transform scale(0.97→1)`
- **App Store cards**: lista vertical, card com ícone 48px + texto + botão direita

### 7.3 Fontes

Google Fonts: `Inter` (400, 500, 600, 700). Carregar no `index.html`.

---

## 8. INTEGRAÇÃO COM `vhub_inventory`

### 8.1 Adicionar item `'ipad'` ao catálogo

**Arquivo**: `resources/[SCRIPTS]/vhub_inventory/config/inventory.lua`

**Adicionar na seção de eletrônicos** (criar se não existir):
```lua
-- ELETRÔNICOS ----------------------------------------------------
['ipad'] = {
  nome = 'iPad', peso = 0.30, stack = false,
  legalidade = 'legal', negociavel = false, perdivel = false,
  permitido_bau = false, serial = true, categoria = 'eletronico',
  -- icon é resolvido automaticamente pela NUI: Inventory.CDN .. '/ipad.png'
},
```

> O ícone `ipad.png` no CDN `https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main/ipad.png` é buscado automaticamente pela NUI do inventory a partir do `id` do item.

### 8.2 Como o item é consumido

- `return false` no handler → item **não é consumido** (iPad é item durável)
- Cooldown de 500ms evita spam

---

## 9. INTEGRAÇÃO COM `vhub_racha`

### 9.1 Fluxo v1 (EMBED_MODE = false)

```
Player clica em "Racha" no iPad
  → racha.js emite vhub.post('openRacha', {})
  → client/init.lua RegisterNUICallback('openRacha')
     → fecha iPad (SetNuiFocus false, SendNUIMessage close)
     → define appOpen = 'racha'
     → TriggerServerEvent('vhub_racha:nui:open')
  → vhub_racha server responde com TriggerClientEvent(E.NUI_OPENED, src, data)
  → vhub_racha client abre seu painel (SetNuiFocus true)

Player fecha o painel do racha (ESC ou botão ×)
  → vhub_racha/client/nui.lua: RegisterNUICallback('close')
     [MODIFICAÇÃO NECESSÁRIA]:
     Após SetNuiFocus(false,false) do racha, sinalizar o iPad:
       TriggerEvent('vhub_ipad:client:RachaClosed')
       -- OU: TriggerNetEvent se o handler for no server
  → vhub_ipad/client/init.lua AddEventHandler('vhub_ipad:client:RachaClosed')
     → se appOpen == 'racha': appOpen = nil; openIpad()
```

**MODIFICAÇÃO EM `vhub_racha/client/nui.lua`** — adicionar ao final do callback `'close'`:
```lua
RegisterNUICallback('close', function(_data, cb)
  L.open_nui = false
  SetNuiFocus(false, false)
  SendNUIMessage({ action = 'close' })
  -- sinaliza iPad que o painel do racha fechou
  TriggerEvent(VHubIpadE.RACHA_CLOSED)  -- local event, sem rede
  cb({ ok = true })
end)
```

> `VHubIpadE.RACHA_CLOSED = 'vhub_ipad:client:RachaClosed'` precisa estar disponível em `vhub_racha`. Como os shared_scripts são por resource, use a string literal com comentário:
> ```lua
> TriggerEvent('vhub_ipad:client:RachaClosed')  -- VHubIpadE.RACHA_CLOSED
> ```

### 9.2 Dependency check no client

Antes de tentar abrir o racha, verificar:
```lua
if GetResourceState('vhub_racha') ~= 'started' then
  -- notificar NUI que racha está offline
  SendNUIMessage({ action = 'rachaStatus', available = false })
  cb({ ok = false, err = 'offline' })
  return
end
```

---

## 10. PERSISTÊNCIA — RESUMO

| Chave localStorage | Tipo | Default | Origem |
|---|---|---|---|
| `vhub_ipad.zoom` | number | 60 | settings.js |
| `vhub_ipad.wallpaper` | string | URL do protótipo | settings.js |
| `vhub_ipad.installed_apps` | string[] | DEFAULT_INSTALLED | home.js |
| `vhub_ipad.icon_order` | Record<id,number> | {} | home.js (v2) |

**Leitura**: `vhub.persist.get('zoom', 60)` — chamada em `onMount` de cada módulo.  
**Escrita**: `vhub.persist.set('zoom', 60)` — chamada ao mudar o valor.  
**Aplicação na abertura**: shell.js ao receber `nui:open` aplica zoom e wallpaper do localStorage antes de mostrar a home.

```js
// em shell.js, dentro de openIpad():
const savedZoom = vhub.persist.get('zoom', data?.defaults?.zoom || 60);
const savedWp   = vhub.persist.get('wallpaper', data?.defaults?.wallpaper || '');
document.getElementById('ipad-wrapper').style.width = savedZoom + 'vw';
const wpEl = document.getElementById('ipad-wallpaper');
if (wpEl && savedWp) wpEl.setAttribute('href', savedWp);
```

---

## 11. PERFORMANCE (ORÇAMENTOS OBRIGATÓRIOS)

| Contexto | Meta |
|---|---|
| NUI fechada (body hidden) | **0.00 ms** — nenhum timer/RAF ativo |
| NUI aberta idle | < 0.5 ms — apenas clock tick a 60s |
| Resmon idle Lua | ≤ 0.02 ms — zero loops, apenas event handlers |
| Resmon ativo Lua | ≤ 0.10 ms p95 |

**Regras de performance**:

1. **Clock**: `setInterval` com 60.000ms — destruído em `stopClock()` ao fechar
2. **Sem RAF permanente** — animações CSS puras, sem `requestAnimationFrame` em loop
3. **Ícones CDN com lazy load**: `loading="lazy"` nas `<img>` + placeholder SVG inline no `onerror`
4. **Módulos**: lazy-mounted (fetch HTML/CSS só quando necessário)
5. **Lua**: zero `Citizen.CreateThread` em loop no client — apenas `AddEventHandler` e `RegisterNUICallback`
6. **Wallpaper**: CSS `background-image` (GPU) em vez de `<img>` — o SVG `<image>` do protótipo já é correto

---

## 12. SEGURANÇA

1. **Item use**: rate limiter server-side (500ms) antes de `TriggerClientEvent`
2. **NUI callbacks**: nenhum callback executa lógica de negócio — apenas relay para servidor
3. **App catalog**: enviado pelo Lua na abertura — cliente não inventa apps
4. **Sem estado crítico**: iPad não persiste dados de negócio, apenas preferências visuais (localStorage)
5. **vhub_racha relay**: Cliente do iPad não valida corridas — apenas dispara evento; racha é autoritativo

---

## 13. CHECKLIST DE QUALIDADE (DoD)

### Estrutura
- [ ] Todos os arquivos listados no `fxmanifest.lua` (L-15)
- [ ] `shared/events.lua` define `VHubIpadE` como global (sem `return`)
- [ ] `shared/config.lua` define `VHubIpadCFG` como global (sem `return`)
- [ ] `vhub_inventory/config/inventory.lua` tem item `'ipad'` cadastrado

### Client Lua
- [ ] `SetNuiFocus(false, false)` em TODOS os caminhos de close
- [ ] Zero `Citizen.CreateThread` em loop (apenas handlers de evento)
- [ ] `RACHA_NUI_OPEN` como string literal local com comentário de origem
- [ ] `GetResourceState('vhub_racha')` verificado antes do relay

### Server Lua
- [ ] `registerItemUse` com `pcall` + retry em `onResourceStart`
- [ ] Rate limiter ativo antes de `TriggerClientEvent`
- [ ] `playerDropped` limpa `_last`

### NUI / JavaScript
- [ ] `body { display: none }` por padrão; `.visible` para mostrar
- [ ] `stopClock()` chamado no `closeIpad()` — sem timer ativo com NUI fechada
- [ ] `onDestroy()` implementado em cada módulo (remover listeners de bus)
- [ ] `vhub.persist.*` com try/catch
- [ ] Ícones com `loading="lazy"` e `onerror` handler
- [ ] PT-BR em todos os labels, botões e mensagens de usuário

### Performance
- [ ] resmon idle ≤ 0.02ms no Lua client
- [ ] NUI fechada = 0.00ms (verificado com DevTools timeline)

### Extensibilidade
- [ ] `VHubIpadCFG.EMBED_MODE = false` flag declarado
- [ ] Módulo `racha.js` tem esqueleto `_openEmbed()` comentado para v2
- [ ] Catálogo de apps `VHubIpadCFG.APPS` extensível (comentário de como adicionar)
- [ ] `exports('RegisterApp', ...)` no server como TODO comentado

---

## 14. ARQUIVOS A CRIAR / MODIFICAR (RESUMO)

### Novos arquivos (`vhub_ipad`)
```
shared/config.lua
shared/events.lua
server/init.lua
client/init.lua
web/index.html
web/runtime/bus.js        ← copiar de vhub_racha/web/runtime/bus.js
web/runtime/store.js      ← copiar de vhub_racha/web/runtime/store.js
web/runtime/bridge.js     ← copiar de vhub_racha/web/runtime/bridge.js
web/runtime/core.js       ← copiar de vhub_racha/web/runtime/core.js
web/shared/tokens.css
web/shared/reset.css      ← copiar de vhub_racha/web/shared/reset.css
web/shared/utils.js
web/shared/shell.js
web/modules/home/home.html
web/modules/home/home.css
web/modules/home/home.js
web/modules/settings/settings.html
web/modules/settings/settings.css
web/modules/settings/settings.js
web/modules/store/store.html
web/modules/store/store.css
web/modules/store/store.js
web/modules/racha/racha.html
web/modules/racha/racha.css
web/modules/racha/racha.js
```

### Arquivos antigos a DELETAR (`vhub_ipad`)
```
client.lua          → substituído por client/init.lua
css/style.css       → substituído por web/shared/tokens.css + módulos
html/index.html     → substituído por web/index.html
js/app.js           → substituído por web/shared/shell.js + módulos
README.md           → atualizar com nova arquitetura
```

### Modificar em outros resources

**`vhub_inventory/config/inventory.lua`**:  
→ Adicionar item `'ipad'` na seção de eletrônicos

**`vhub_racha/client/nui.lua`**:  
→ No `RegisterNUICallback('close', ...)`, adicionar `TriggerEvent('vhub_ipad:client:RachaClosed')` após `SetNuiFocus(false, false)`

---

## 15. EXTENSÕES FUTURAS (JÁ PREPARADAS NA ARQUITETURA)

| Feature | Como ativar |
|---|---|
| Embed iframe racha | `VHubIpadCFG.EMBED_MODE = true` |
| Novo app de terceiro | `VHubIpadCFG.APPS['nome'] = {...}` no config |
| App registrado dinâmico | Implementar `exports('RegisterApp', ...)` no server/init.lua |
| Widgets na home | Adicionar `widgets = {}` no VHubIpadCFG e slot `#home-widgets` no HTML |
| Badge counter nos ícones | `vhub.bus.emit('ipad:set_badge', { id, count })` → home.js re-renderiza |
| Notificação push no ícone | `TriggerClientEvent('vhub_ipad:client:PushBadge', src, appId, count)` |
| Drag-and-drop de ícones | `vhub_ipad.icon_order` no localStorage + eventos `dragstart/drop` |
| Segundas telas (multi-page) | Array de arrays em `_pages`, dots indicators com click |

---

## 16. ÍCONES CDN (REFERÊNCIA)

| Arquivo CDN | Uso |
|---|---|
| `ipad.png` | Ícone do item no inventário (resolvido por `Inventory.CDN/ipad.png`) |
| `configuracao.png` | Ícone do app Configurações na home screen |
| `chita.png` | Ícone do app Racha na home screen |

**URL base**: `https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main`  
**Exemplo**: `https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main/chita.png`

Todos os ícones são `.png` — não usar extensão diferente sem confirmar no repositório `https://github.com/Void-Cla/vhub-assets`.

---

## 17. GLOSSÁRIO RÁPIDO

| Termo | Significado |
|---|---|
| `SendNUIMessage({action,...})` | Lua → NUI; o core.js despacha via bus como `'nui:' + action` |
| `vhub.post(cb, data)` | NUI → Lua; chama `RegisterNUICallback(cb)` |
| `vhub.bus.emit/listen` | Inter-módulo; nunca cross-resource |
| `vhub.persist` | localStorage com namespace `vhub_ipad.*` |
| `vhub.mount(name)` | Lazy-load HTML+CSS do módulo + chama `onMount` |
| `vhub.show(name)` | `mount` + remove `.hidden` + chama `onShow` |
| `vhub.hide(name)` | Adiciona `.hidden` + chama `onHide` |
| `VHubIpadCFG` | Tabela global Lua de configuração (shared/config.lua) |
| `VHubIpadE` | Tabela global Lua de eventos (shared/events.lua) |
| Soft-dep | `vhub_racha` não está em `dependencies{}` — verificado em runtime |
| EMBED_MODE | Flag v1/v2: false=delegate fullscreen, true=iframe dentro do iPad |

---

*Fim do prompt — implemente na ordem: fxmanifest → shared → server → client → web/runtime → web/shared → web/modules → integrações externas → DoD.*