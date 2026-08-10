-- config/config.lua — tunables do vhub_login (SEM regra de negócio, só parâmetros).

VHubLogin = VHubLogin or {}

VHubLogin.Config = {
  -- Interruptor mestre: enquanto false, o gate NÃO intercepta o spawn (resource
  -- inerte). Ligado em 2026-06-27 para runtime-validate no servidor vivo.
  enabled = true,

  -- Credencial
  username_min = 3,
  username_max = 20,
  password_min = 8,
  password_legacy_min = 6,
  password_max = 64,
  email_max = 254,
  whatsapp_min = 10,
  whatsapp_max = 15,

  -- Consentimento persistido. Alterar a versão exige fluxo futuro de reaceite.
  terms_version = "2026-07-19",

  -- Pepper server-only: convar opcional no primeiro boot. Sem convar, o resource
  -- deriva um segredo da licença do servidor e o preserva em KVP. Nunca usar `setr`.
  pepper_convar = "vhub_login_pepper",

  -- Prazo do gate: sem concluir login+char dentro disso → DropPlayer. DEVE ser
  -- MENOR que o selector_timeout do vhub_hss (300s) para preemptar o
  -- fallback que spawnaria um não-autenticado (GAP de segurança #4 do arquiteto).
  auth_deadline = 120,         -- segundos

  -- Palco privado de selecao. O mapa e iniciado como dependencia do resource;
  -- os peds sao locais e cada sessao autenticada recebe bucket exclusivo no HSS.
  selection = {
    map_resource = "depzitamadasptlnd",
    positions = {
      { x = -80.4353, y = 3.2092, z = 1.0001, heading = 174.4306 },
      { x = -76.6213, y = 3.2019, z = 1.0001, heading = 182.2863 },
      { x = -72.7645, y = 2.9722, z = 1.0001, heading = 180.8838 },
    },
    camera = {
      x = -77.0000, y = -4.2500, z = 2.5500,
      target_x = -77.0000, target_y = 3.1400, target_z = 1.6500,
      fov = 48.0,
        focus_distance = 2.95,
        focus_height = 1.02,
        focus_target_height = 0.68,
        focus_fov = 44.0,
        transition_ms = 850,
    },
  },

  -- Anti brute-force
  rate = {
    login = { max = 6, window = 15000 },
    register = { max = 3, window = 60000 },
    recovery = { max = 3, window = 60000 },
    pick = { max = 4, window = 15000 },
    create = { max = 2, window = 30000 },
  },
  lockout = { fails = 5, ms = 60000 },     -- por UID: 5 falhas → trava 60s

  -- Export default-deny; HSS e selector consultam somente o estado do gate.
  login_trusted = {
    vhub_hss = true,
    vhub_spawselector = true,
  },
}
