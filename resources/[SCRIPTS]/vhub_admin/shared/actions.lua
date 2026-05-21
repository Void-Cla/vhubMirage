-- shared/actions.lua  cat logo de a  es admin (usado por painel + comandos slash)
-- Cada a  o tem: descricao, perm, categoria, campos (UI), perigosa (confirma  o)
VHubAdmin = VHubAdmin or {}

VHubAdmin.ACTIONS = {
  -- ---------- Modera  o ---------------------------------------------------
  kick      = { perm='kick',      cat='moderation', desc='Expulsar jogador do servidor',  fields={'target','reason'},   dangerous=false },
  ban       = { perm='ban',       cat='moderation', desc='Banir jogador permanente',      fields={'target','reason'},   dangerous=true  },
  unban     = { perm='unban',     cat='moderation', desc='Remover banimento pelo UID',    fields={'uid'},               dangerous=false },
  whitelist = { perm='whitelist', cat='moderation', desc='Aprovar jogador na lista',      fields={'target'},            dangerous=false },
  unwl      = { perm='whitelist', cat='moderation', desc='Remover jogador da lista',      fields={'target'},            dangerous=false },
  warn      = { perm='warn',      cat='moderation', desc='Enviar aviso ao jogador',       fields={'target','message'},  dangerous=false },
  jail      = { perm='jail',      cat='moderation', desc='Prender em cadeia por minutos', fields={'target','minutes','reason'}, dangerous=true },
  unjail    = { perm='jail',      cat='moderation', desc='Soltar da cadeia',              fields={'target'},            dangerous=false },
  mute      = { perm='mute',      cat='moderation', desc='Silenciar jogador no chat',     fields={'target','minutes','reason'}, dangerous=false },
  unmute    = { perm='mute',      cat='moderation', desc='Liberar fala no chat',          fields={'target'},            dangerous=false },

  -- ---------- Teleporte -----------------------------------------------------
  tp        = { perm='tp',        cat='teleport',   desc='Ir at  o jogador',         fields={'target'},            dangerous=false },
  tptome    = { perm='bring',     cat='teleport',   desc='Trazer jogador at  mim',   fields={'target'},            dangerous=false },
  tpgo      = { perm='tpgo',      cat='teleport',   desc='Ir ao marcador no mapa',   fields={},                    dangerous=false },
  tpcds     = { perm='tpcds',     cat='teleport',   desc='Ir a coordenadas X Y Z',   fields={'x','y','z'},         dangerous=false },
  tpall     = { perm='tpall',     cat='teleport',   desc='Trazer todos at  mim',     fields={},                    dangerous=true  },
  tplast    = { perm='tp',        cat='teleport',   desc='Voltar   posi  o anterior',fields={},                    dangerous=false },

  -- ---------- Jogador ------------------------------------------------------
  heal      = { perm='heal',      cat='player',     desc='Curar jogador',            fields={'target'},            dangerous=false },
  healall   = { perm='heal',      cat='player',     desc='Curar todos os jogadores', fields={},                    dangerous=false },
  god       = { perm='god',       cat='player',     desc='Alternar invencibilidade', fields={},                    dangerous=false },
  freeze    = { perm='freeze',    cat='player',     desc='Alternar congelamento',    fields={'target'},            dangerous=false },
  revive    = { perm='revive',    cat='player',     desc='Reviver jogador',          fields={'target'},            dangerous=false },
  reviveall = { perm='revive',    cat='player',     desc='Reviver todos',            fields={},                    dangerous=false },
  invis     = { perm='invisible', cat='player',     desc='Alternar invisibilidade',  fields={},                    dangerous=false },
  skin      = { perm='skin',      cat='player',     desc='Trocar skin do alvo',      fields={'target','model'},    dangerous=false },
  spec      = { perm='spec',      cat='player',     desc='Espectar jogador',         fields={'target'},            dangerous=false },
  kill      = { perm='god',       cat='player',     desc='Matar jogador',            fields={'target'},            dangerous=true  },

  -- ---------- Ve culo ------------------------------------------------------
  spawncar  = { perm='spawncar',  cat='vehicle',    desc='Spawnar ve culo (admin)',     fields={'model'},             dangerous=false },
  delveh    = { perm='delveh',    cat='vehicle',    desc='Deletar ve culo mais pr ximo',fields={},                    dangerous=false },
  fix       = { perm='fix',       cat='vehicle',    desc='Reparar ve culo pr ximo',     fields={},                    dangerous=false },
  tuning    = { perm='tuning',    cat='vehicle',    desc='Aplicar tuning completo',     fields={},                    dangerous=false },
  carcolor  = { perm='carcolor',  cat='vehicle',    desc='Cor RGB do ve culo',          fields={'r','g','b'},         dangerous=false },

  -- ---------- Mundo --------------------------------------------------------
  weather   = { perm='weather',   cat='world',      desc='Mudar clima',                 fields={'wx'},                dangerous=false },
  time      = { perm='time',      cat='world',      desc='Definir hor rio do dia',      fields={'hour','minute'},     dangerous=false },
  blackout  = { perm='blackout',  cat='world',      desc='Alternar apag o',             fields={},                    dangerous=true  },
  clearzone = { perm='clearzone', cat='world',      desc='Limpar  rea (raio em metros)',fields={'radius'},            dangerous=true  },
  announce  = { perm='announce',  cat='world',      desc='An ncio global',              fields={'message'},           dangerous=false },
  staffchat = { perm='staffchat', cat='world',      desc='Chat privado da equipe',      fields={'message'},           dangerous=false },

  -- ---------- Economia / Invent rio / Grupos ------------------------------
  givemoney = { perm='givemoney', cat='economy',    desc='Dar dinheiro',                fields={'target','amount','rota'}, dangerous=false },
  setmoney  = { perm='setmoney',  cat='economy',    desc='Definir saldo',               fields={'target','amount','rota'}, dangerous=true  },
  giveitem  = { perm='giveitem',  cat='inventory',  desc='Dar item ao jogador',         fields={'target','item','qty'},    dangerous=false },
  clearinv  = { perm='clearinv',  cat='inventory',  desc='Limpar invent rio do alvo',   fields={'target'},                 dangerous=true  },
  addgroup  = { perm='addgroup',  cat='groups',     desc='Adicionar grupo ao jogador',  fields={'target','group'},         dangerous=false },
  delgroup  = { perm='delgroup',  cat='groups',     desc='Remover grupo do jogador',    fields={'target','group'},         dangerous=true  },

  -- ---------- Informa  o ---------------------------------------------------
  rg        = { perm='rg',        cat='info',       desc='Ver ficha completa do alvo',  fields={'target'},            dangerous=false },
  coords    = { perm='coords',    cat='info',       desc='Mostrar coordenadas atuais',  fields={},                    dangerous=false },
  pon       = { perm='pon',       cat='info',       desc='Listar jogadores online',     fields={},                    dangerous=false },

  -- ---------- Den ncias ----------------------------------------------------
  reports   = { perm='reports',   cat='reports',    desc='Fila de den ncias',           fields={},                    dangerous=false },
}
