---@diagnostic disable: undefined-global, lowercase-global

-- shared/config.lua — configuração GLOBAL do vhub_ipad (sem return; sem estado).


VHubIpadCFG = VHubIpadCFG or {}


-- ============================================================
-- PLATAFORMA
-- ============================================================

-- nível da API de apps. Manifest com manifest_level > API_LEVEL é rejeitado
-- (o app espera uma versão do iPad mais nova que esta).
VHubIpadCFG.API_LEVEL = 1

-- CDN de ícones (jsDelivr → repo Void-Cla/vhub-assets). utils.js monta a URL final.
VHubIpadCFG.CDN = 'https://cdn.jsdelivr.net/gh/Void-Cla/vhub-assets@main'


-- ============================================================
-- PREFERÊNCIAS PADRÃO (aplicadas a personagem sem estado salvo)
-- ============================================================

VHubIpadCFG.DEFAULTS = {
  zoom         = 60,          -- largura do tablet em vw (clamp 30..100)
  wallpaper_id = 'default',   -- precisa existir em WALLPAPERS
}

-- Wallpapers válidos (verdade server-side). O cliente só escolhe DENTRO deste enum.
-- type='gradient' → CSS gradient (sem dependência externa). type='image' → URL.
VHubIpadCFG.WALLPAPERS = {
  { id = 'default', label = 'Meia-noite', type = 'gradient',
    value = 'linear-gradient(150deg, #1b2735 0%, #090a0f 70%)' },
  { id = 'aurora',  label = 'Aurora',     type = 'gradient',
    value = 'linear-gradient(160deg, #0f2027 0%, #203a43 50%, #2c5364 100%)' },
  { id = 'areia',   label = 'Areia vHub', type = 'gradient',
    value = 'linear-gradient(160deg, #2a2113 0%, #4a3a1c 45%, #0d0d0f 100%)' },
  { id = 'roxo',    label = 'Nebulosa',   type = 'gradient',
    value = 'linear-gradient(160deg, #232526 0%, #414345 100%)' },
}


-- ============================================================
-- APPS BUILTIN (registrados pelo próprio iPad via o MESMO caminho que terceiros)
-- ============================================================
-- id == nome do módulo NUI == diretório em web/modules/<id>/.
-- removable=false → app de sistema, sempre na home (não some, não desinstala).
-- removable=true  → aparece na LOJA para instalar/remover (estado per-char).

VHubIpadCFG.BUILTIN_APPS = {
  {
    id = 'settings', version = '1.0.0', manifest_level = 1,
    label = 'Configurações', icon = 'configuracao.png',
    category = 'sistema', removable = false,
    ui = { source = 'local',
           html = 'modules/settings/settings.html',
           css  = 'modules/settings/settings.css',
           js   = 'modules/settings/settings.js' },
  },
  {
    id = 'store', version = '1.0.0', manifest_level = 1,
    label = 'Loja', icon = 'loja.png',
    category = 'sistema', removable = false,
    ui = { source = 'local',
           html = 'modules/store/store.html',
           css  = 'modules/store/store.css',
           js   = 'modules/store/store.js' },
  },
  {
    id = 'relogio', version = '1.0.0', manifest_level = 1,
    label = 'Relógio', icon = 'relogio.png',
    category = 'utilidades', removable = true,
    ui = { source = 'local',
           html = 'modules/relogio/relogio.html',
           css  = 'modules/relogio/relogio.css',
           js   = 'modules/relogio/relogio.js' },
  },
  {
    id = 'racha', version = '1.0.0', manifest_level = 1,
    label = 'Racha', icon = 'chita.png',
    category = 'entretenimento', removable = true,
    dependency = 'vhub_racha',            -- só disponível se o racha estiver 'started'
    ui = { source = 'local',
           html = 'modules/racha/racha.html',
           css  = 'modules/racha/racha.css',
           js   = 'modules/racha/racha.js' },
    -- app EMBUTIDO: o painel do racha roda DENTRO da tela do iPad (relay broker).
    -- SERVER-ONLY (nunca vai no snapshot da NUI): o cliente nunca nomeia o export.
    relay = { resource = 'vhub_racha', export = 'ipadRelay' },
  },
  {
    -- Central LSPD: app de TRABALHO com UI REMOTA (arquivos no próprio vhub_lspdtool,
    -- carregados via cfx-nui-vhub_lspdtool). Registro pelo catálogo (caminho provado),
    -- UI + relay no resource dono. Login (char_id+senha) é validado no ipadRelay.
    id = 'lspd', version = '1.0.0', manifest_level = 1,
    label = 'Central LSPD', icon = 'lspd.png',
    category = 'trabalho', removable = true,
    dependency = 'vhub_lspdtool',         -- só disponível se o lspdtool estiver 'started'
    ui = { source = 'remote', resource = 'vhub_lspdtool',
           html = 'web/app_ipad/lspd.html',
           css  = 'web/app_ipad/lspd.css',
           js   = 'web/app_ipad/lspd.js' },
    relay = { resource = 'vhub_lspdtool', export = 'ipadRelay' },
  },
}

-- Apps REMOVÍVEIS pré-instalados num personagem novo (vazio = só os de sistema na home).
VHubIpadCFG.DEFAULT_INSTALLED = {}


-- ============================================================
-- RATE LIMIT (server-side)
-- ============================================================

VHubIpadCFG.rates = {
  use_ipad = 500,   -- cooldown ms para abrir o tablet (item/comando)
  mutate   = 250,   -- cooldown ms para install/uninstall/setPref
}
