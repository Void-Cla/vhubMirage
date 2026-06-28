-- config/config.lua — tunables do vhub_login (SEM regra de negócio, só parâmetros).

VHubLogin = VHubLogin or {}

VHubLogin.Config = {
  -- Interruptor mestre: enquanto false, o gate NÃO intercepta o spawn (resource
  -- inerte). Ligado em 2026-06-27 para runtime-validate no servidor vivo.
  enabled = true,

  -- Credencial
  username_min = 3,
  username_max = 20,
  password_min = 6,
  password_max = 64,

  -- Prazo do gate: sem concluir login+char dentro disso → DropPlayer. DEVE ser
  -- MENOR que o selector_timeout do vhub_player_state (300s) para preemptar o
  -- fallback que spawnaria um não-autenticado (GAP de segurança #4 do arquiteto).
  auth_deadline = 120,         -- segundos

  -- Anti brute-force
  rate    = { max = 6, window = 15000 },   -- por SRC: 6 tentativas / 15s
  lockout = { fails = 5, ms = 60000 },     -- por USERNAME: 5 falhas → trava 60s (anti rotação de src)

  -- Export default-deny (export-first): vazio = só consumo interno.
  login_trusted = {},
}
