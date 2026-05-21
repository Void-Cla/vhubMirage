-- server/modules/spawn.lua — Envia dados de spawn para o cliente
-- vHub:playerSpawn é disparado pelo boot.lua após Auth:connect com sucesso.
-- Este módulo converte o evento server-side em TriggerClientEvent.

local CFG = {
  -- Posição de spawn padrão (Mission Row PD — ponto seguro e central)
  spawn_pos    = { x = 428.0, y = -984.0, z = 30.0, heading = 90.0 },
  spawn_radius = 3.0,          -- dispersão para evitar sobreposição entre players
  default_model  = "mp_m_freemode_01",  -- modelo masculino freemode
  default_health = 200,        -- saúde máxima (100 base + 100 extra GTA V)
}

AddEventHandler("vHub:playerSpawn", function(user, first_spawn)
  if not user or not user.source then return end
  local src = user.source

  -- Usa posição salva se existir; senão usa padrão com dispersão aleatória
  local pos = user.data.last_position
  if not pos then
    local r = CFG.spawn_radius
    pos = {
      x       = CFG.spawn_pos.x + (math.random() * r * 2 - r),
      y       = CFG.spawn_pos.y + (math.random() * r * 2 - r),
      z       = CFG.spawn_pos.z,
      heading = CFG.spawn_pos.heading,
    }
  end

  local model  = user.data.ped_model    or CFG.default_model
  local health = user.data.last_health  or CFG.default_health

  -- Envia ao cliente — client/modules/spawn.lua aplica tudo localmente
  TriggerClientEvent("vHub:doSpawn", src, {
    pos    = pos,
    model  = model,
    health = health,
    char_id = user.char_id,
    first  = first_spawn == true,
  })

  vHub.Logger:info("spawn",
    ("uid=%d src=%d → doSpawn pos=(%.1f,%.1f,%.1f) first=%s"):format(
      user.id, src, pos.x, pos.y, pos.z, tostring(first_spawn)))
end)

-- Morte: limpa posição para forçar spawn padrão no próximo login
AddEventHandler("vHub:playerDeath", function(user)
  if user then
    user.data.last_position = nil
    user.data.last_health   = nil
  end
end)

vHub.Logger:info("spawn", "Módulo de spawn carregado.")
