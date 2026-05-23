-- shared/definitions.lua — vhub_groups
-- Catalogo de grupos do servidor. Cada grupo tem:
--   label   : nome legivel
--   type    : 'system' | 'staff' | 'job' | 'gang' | 'faction'
--             types 'job' e 'gang' sao mutuamente exclusivos por tipo
--             (so 1 job ativo e 1 gang ativo por char_id ao mesmo tempo)
--   color   : cor de exibicao na UI (hex)
--   icon    : Font Awesome class
--   levels  : 1..N hierarquicos, nivel N herda permissoes de 1..N-1
--             cada nivel = { label, permissions = { 'perm.id', ... } }
--
-- Wildcards aceitos em permissions:
--   'prefix.*'  → casa qualquer permissao que comece com 'prefix.'
--   '*'         → super (cuidado — equivale a owner)
--
-- Para criar novos grupos, adicionar aqui. Restart vhub_groups aplica.

VHubGroupsDefs = {

  -- ─── Sistema ───────────────────────────────────────────────────────────────

  cidadao = {
    label = 'Cidadao',
    type  = 'system',
    color = '#d9c19a',
    icon  = 'fa-solid fa-user',
    levels = {
      [1] = {
        label = 'Padrao',
        permissions = { 'player.base' },
      },
    },
  },

  -- ─── Staff (hierarquia administrativa) ─────────────────────────────────────

  staff = {
    label = 'Staff',
    type  = 'staff',
    color = '#f3b53a',
    icon  = 'fa-solid fa-shield-halved',
    levels = {
      [1] = {
        label = 'Suporte',
        permissions = {
          'vhub.admin.panel',
          'admin.tickets',
          'admin.announce',
          'player.list',
          'player.coords',
          'player.rg',
          'player.heal',
          'player.revive',
          'admin.car.dv',
        },
      },
      [2] = {
        label = 'Moderador',
        permissions = {
          'player.kick',
          'player.freeze',
          'player.warn',
          'player.tptome',
          'player.tpto',
          'player.tpcoords',
          'player.noclip',
          'admin.car.fix',
          'admin.car.fuel',
          'admin.car.give',
          'admin.weapon.god',
          'admin.spectate',
        },
      },
      [3] = {
        label = 'Administrador',
        permissions = {
          'player.ban',
          'player.unban',
          'player.whitelist',
          'player.unwhitelist',
          'admin.money.give',
          'admin.money.take',
          'admin.money.set',
          'admin.item.give',
          'admin.item.take',
          'admin.car.delete',
          'admin.world.weather',
          'admin.world.time',
          'admin.report.*',
        },
      },
      [4] = {
        label = 'Founder',
        permissions = {
          'vhub.admin.*',
          'vhub.groups.admin',
          'vhub.commands.admin',
          'admin.*',
        },
      },
    },
  },

  -- ─── Jobs (mutuamente exclusivos por type='job') ───────────────────────────

  policia = {
    label = 'Policia',
    type  = 'job',
    color = '#4a8bd9',
    icon  = 'fa-solid fa-handcuffs',
    levels = {
      [1] = {
        label = 'Recruta',
        permissions = {
          'policia.radio',
          'policia.armario',
          'policia.veiculo',
        },
      },
      [2] = {
        label = 'Soldado',
        permissions = {
          'policia.abordagem',
          'policia.algemar',
          'policia.consulta',
          'policia.multa',
        },
      },
      [3] = {
        label = 'Sargento',
        permissions = {
          'policia.prender',
          'policia.apreender',
          'policia.investigar',
        },
      },
      [4] = {
        label = 'Comandante',
        permissions = {
          'policia.*',
          'policia.gerencia',
          'policia.recrutar',
        },
      },
    },
  },

  medico = {
    label = 'Medico',
    type  = 'job',
    color = '#e8513f',
    icon  = 'fa-solid fa-suitcase-medical',
    levels = {
      [1] = {
        label = 'Paramedico',
        permissions = {
          'medico.atendimento',
          'medico.veiculo',
          'medico.bandagem',
        },
      },
      [2] = {
        label = 'Socorrista',
        permissions = {
          'medico.resgate',
          'medico.reviver',
          'medico.medkit',
        },
      },
      [3] = {
        label = 'Chefia',
        permissions = {
          'medico.*',
          'medico.gerencia',
          'medico.recrutar',
        },
      },
    },
  },

  mecanico = {
    label = 'Mecanico',
    type  = 'job',
    color = '#ff9a1f',
    icon  = 'fa-solid fa-wrench',
    levels = {
      [1] = {
        label = 'Assistente',
        permissions = {
          'mecanico.veiculo',
          'mecanico.reparo.basico',
        },
      },
      [2] = {
        label = 'Mecanico',
        permissions = {
          'mecanico.reparo.full',
          'mecanico.tuning',
          'mecanico.pintura',
        },
      },
      [3] = {
        label = 'Gerente',
        permissions = {
          'mecanico.*',
          'mecanico.gerencia',
        },
      },
    },
  },

  taxi = {
    label = 'Taxi',
    type  = 'job',
    color = '#f3d23a',
    icon  = 'fa-solid fa-taxi',
    levels = {
      [1] = {
        label = 'Taxista',
        permissions = {
          'taxi.servico',
          'taxi.veiculo',
        },
      },
      [2] = {
        label = 'Gerente',
        permissions = {
          'taxi.*',
          'taxi.gerencia',
        },
      },
    },
  },

  -- ─── Gangs (mutuamente exclusivos por type='gang') ─────────────────────────

  ballas = {
    label = 'Ballas',
    type  = 'gang',
    color = '#9b59b6',
    icon  = 'fa-solid fa-users',
    levels = {
      [1] = { label = 'Soldado',  permissions = { 'gang.ballas.base' } },
      [2] = { label = 'Tenente',  permissions = { 'gang.ballas.gerencia' } },
      [3] = { label = 'Lider',    permissions = { 'gang.ballas.*' } },
    },
  },

  families = {
    label = 'Families',
    type  = 'gang',
    color = '#2ecc71',
    icon  = 'fa-solid fa-users',
    levels = {
      [1] = { label = 'Soldado',  permissions = { 'gang.families.base' } },
      [2] = { label = 'Tenente',  permissions = { 'gang.families.gerencia' } },
      [3] = { label = 'Lider',    permissions = { 'gang.families.*' } },
    },
  },
}
