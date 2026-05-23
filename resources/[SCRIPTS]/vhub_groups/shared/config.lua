-- shared/config.lua — vhub_groups
-- Configuracao global do dominio. Carregado em shared (server + client).

VHubGroupsCfg = {
  -- char_id que e o dono absoluto da cidade. Recebe permissao "*" automaticamente.
  -- Cuidado: e fixo no design (decisao do projeto). Nao alterar sem aprovacao.
  OWNER_CHAR_ID = 1,

  -- Permissao virtual concedida ao owner (wildcard global)
  OWNER_PERMISSION = '*',

  -- Grupo aplicado automaticamente no primeiro characterLoad (sem grupo no banco)
  DEFAULT_GROUP   = 'cidadao',
  DEFAULT_LEVEL   = 1,

  -- Cache TTL — quanto tempo o set de permissoes computado fica em VRAM antes de
  -- ser invalidado por TTL (independente das invalidacoes por mutacao/drop)
  CACHE_TTL_SECONDS = 600,   -- 10 min: VRAM-first + invalidacao explicita

  -- Intervalo do cron que remove grupos expirados
  EXPIRE_CHECK_INTERVAL_MS = 60000,   -- 60s

  -- Permissao necessaria para acessar o painel admin
  ADMIN_PERMISSION = 'vhub.groups.admin',
  -- ACE alternativo (server.cfg: add_ace identifier vhub.groups.admin allow)
  ADMIN_ACE        = 'vhub.groups.admin',

  -- Resources que podem chamar exports sensiveis (grant/revoke)
  -- Vazio = todos podem (mesma regra do core). Preencher para restringir.
  TRUSTED_RESOURCES = {
    ['vhub']        = true,
    ['vhub_admin']  = true,
    ['vhub_garage'] = true,
  },

  -- Comandos
  CMD_OPEN_PANEL = 'grupos',     -- /grupos — abre painel admin
  CMD_MY_GROUPS  = 'meusgrupos', -- /meusgrupos — mostra grupos do proprio personagem
  KEY_OPEN_PANEL = 'F7',         -- atalho admin (RegisterKeyMapping)

  -- Limite de linhas retornadas em audit log no painel
  AUDIT_LIMIT_DEFAULT = 100,
  AUDIT_LIMIT_MAX     = 500,

  -- Log level: 0=quiet 1=info 2=debug
  LOG_LEVEL = 1,
}
