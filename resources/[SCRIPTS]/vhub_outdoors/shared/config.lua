-- shared/config.lua - configuracao publica do dominio de outdoors

VHubOutdoors = VHubOutdoors or {}

VHubOutdoors.cfg = {
  commands = {
    create = 'outdoor',
    remove = 'outdoorremover',
    list = 'outdoorlistar',
    remote = 'outdoorcontrole',
  },

  permission = 'outdoors.manage',

  sizes = {
    small = {
      label = 'pequeno',
      hint = 'TV de parede, classe 60-65 polegadas',
      order = 1,
      modo = 'parede',
      visual = {
        load_distance = 100.0,
        unload_distance = 150.0,
      },
      prop = {
        modelo = 'prop_tv_flat_michael',
        frente = -1.0,
        tela = {
          offset = 0.006,
          min_x = -0.72998046875,
          max_x = 0.728515625,
          y = -0.05322265625,
          min_z = -0.3662109375,
          max_z = 0.4541015625,
        },
      },
    },
    medium = {
      label = 'medio',
      hint = 'Telao de parede',
      order = 2,
      modo = 'parede',
      visual = {
        load_distance = 180.0,
        unload_distance = 200.0,
      },
      prop = {
        modelo = 'prop_huge_display_02',
        frente = -1.0,
        tela = {
          offset = 0.050,
          min_x = -4.44775390625,
          max_x = 4.04541015625,
          y = -0.0478515625,
          min_z = -2.4091796875,
          max_z = 2.3828125,
        },
      },
    },
    large = {
      label = 'grande',
      hint = 'Outdoor com estrutura de solo',
      order = 3,
      modo = 'chao',
      visual = {
        load_distance = 250.0,
        unload_distance = 300.0,
      },
      prop = {
        modelo = 'prop_billboard_10',
        frente = -1.0,
        solo_z = 0.0,
        tela = {
          offset = 0.001,
          min_x = -5.9921875,
          max_x = 6.0078125,
          y = -1.19287109375,
          min_z = 2.78662109375,
          max_z = 6.70556640625,
        },
      },
    },
  },

  size_aliases = {
    pequeno = 'small',
    medio = 'medium',
    grande = 'large',
    small = 'small',
    medium = 'medium',
    large = 'large',
  },

  -- Fail-closed: exports server-side ficam inacessiveis enquanto a lista estiver vazia.
  trusted_resources = {},

  rates = {
    open_create_ui = 750,
    request_placement = 750,
    remove_ui = 750,
    create_command = 1000,
    submit_placement = 1500,
    remove_command = 1000,
    list_command = 1000,
    export_create = 1000,
    export_remove = 1000,
    remote_grant = 1000,
    remote_open = 750,
    remote_media = 2000,
    remote_volume = 300,
    remote_move = 1000,
    remote_submit = 1000,
  },

  limits = {
    max_outdoors = 32,
    max_streamed = 4,
    max_animated_streamed = 3,
    max_title = 80,
    max_url = 768,
    max_reason = 120,
    pending_seconds = 60,
    commit_retry_ms = 2000,
    max_commit_retries = 5,
    sql_timeout_ms = 10000,
    probe_timeout_ms = 8000,
    max_image_bytes = 4194304,
    max_video_bytes = 25165824,

    ray_distance = 30.0,
    placement_distance = 35.0,
    max_surface_tilt = 0.35,
    surface_offset = 0.015,
    min_width = 0.5,
    max_width = 20.0,
    min_height = 0.5,
    max_height = 12.0,
    max_area = 120.0,

    world_xy = 10000.0,
    world_z_min = -200.0,
    world_z_max = 2000.0,
  },

  remote = {
    item = 'controle_outdoor',
    session_seconds = 300,
    control_distance = 50.0,
    routing_bucket = 1,
  },

  renderer = {
    load_distance = 120.0,
    unload_distance = 145.0,
    idle_check_ms = 1500,
    active_check_ms = 750,
    dui_width = 1024,
    dui_height = 576,
    dui_timeout_ms = 5000,
    model_timeout_ms = 5000,
    prop_surface_offset = 0.001,
  },

  audio = {
    max_sources = 3,
    volume = 0.45,
    duck_strength = 0.90,
    distance = 45.0,
    activation_distance = 55.0,
    unload_distance = 65.0,
    active_check_ms = 1000,
    idle_check_ms = 5000,
    ready_timeout_ms = 15000,
    retry_base_ms = 2000,
    retry_max_ms = 30000,
  },
}

for _, preset in pairs(VHubOutdoors.cfg.sizes) do
  local tela = preset.prop.tela
  preset.width = math.abs(tela.max_x - tela.min_x)
  preset.height = math.abs(tela.max_z - tela.min_z)
end

-- Resolve nome PT-BR ou canonico para um preset imutavel de tamanho.
function VHubOutdoors.resolveSize(value)
  if type(value) ~= 'string' then return nil end
  local name = VHubOutdoors.cfg.size_aliases[value:lower()]
  local preset = name and VHubOutdoors.cfg.sizes[name] or nil
  return name, preset
end

-- Deriva os cantos do preset sem consultar estado do jogador ou do mundo.
function VHubOutdoors.deriveGeometry(center, normal, size_name)
  local name, preset = VHubOutdoors.resolveSize(size_name)
  if type(center) ~= 'table' or type(normal) ~= 'table' or not preset then return nil end

  local center_x = tonumber(center.x)
  local center_y = tonumber(center.y)
  local center_z = tonumber(center.z)
  local normal_x = tonumber(normal.x)
  local normal_y = tonumber(normal.y)
  if not center_x or not center_y or not center_z or not normal_x or not normal_y then
    return nil
  end

  center_x = center_x + normal_x * VHubOutdoors.cfg.limits.surface_offset
  center_y = center_y + normal_y * VHubOutdoors.cfg.limits.surface_offset
  local tangent_x = -normal_y
  local tangent_y = normal_x
  local half_width = preset.width * 0.5
  local half_height = preset.height * 0.5
  return {
    top_left = {
      x = center_x - tangent_x * half_width,
      y = center_y - tangent_y * half_width,
      z = center_z + half_height,
    },
    bottom_right = {
      x = center_x + tangent_x * half_width,
      y = center_y + tangent_y * half_width,
      z = center_z - half_height,
    },
  }, name
end
