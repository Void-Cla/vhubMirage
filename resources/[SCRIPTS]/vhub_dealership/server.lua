-- vhub_dealership/server.lua
-- Compra, venda e test drive de veículos.
-- Estado do veículo: user.data.vehicles[plate] (autosave vHub).
-- Unicidade de placa: tabela vhub_plates via oxmysql.

local _sessions = {}   -- src → live user ref

-- ── Configuração ──────────────────────────────────────────────────────────────

local CFG = {
  fator_revenda     = 0.6,
  taxa_placa_custom = 200,

  concessionarias = {
    { label = "Concessionária Legião Americana", x = -42.56,  y = -1100.74, z = 26.42, raio = 10.0 },
    { label = "Concessionária Premium Deluxe",   x = -45.81,  y = -1099.35, z = 26.56, raio = 10.0 },
    { label = "Concessionária Sandy Shores",      x = 1670.02, y = 3762.31,  z = 34.62, raio = 10.0 },
  },

  catalogo = {
    ["sultan"]    = { nome="Sultan",        preco=18000,   cat="Carros",    desc="Sedan esportivo 4 portas"     },
    ["kuruma"]    = { nome="Kuruma",        preco=35000,   cat="Carros",    desc="Sedan blindado japonês"       },
    ["schafter2"] = { nome="Schafter V12",  preco=42000,   cat="Carros",    desc="Sedã executivo de luxo"       },
    ["tailgater"] = { nome="Tailgater",     preco=28000,   cat="Carros",    desc="Sedan esportivo 4 portas"     },
    ["oracle2"]   = { nome="Oracle XS",     preco=32000,   cat="Carros",    desc="Sedan de luxo 4 portas"       },
    ["adder"]     = { nome="Adder",         preco=1000000, cat="Esportivos",desc="Hipercarro exclusivo"         },
    ["zentorno"]  = { nome="Zentorno",      preco=725000,  cat="Esportivos",desc="Supercar alta performance"    },
    ["t20"]       = { nome="T20",           preco=2200000, cat="Esportivos",desc="O supercar mais rápido"       },
    ["turismor"]  = { nome="Turismo R",     preco=500000,  cat="Esportivos",desc="Supercar italiano clássico"   },
    ["entityxf"]  = { nome="Entity XF",     preco=795000,  cat="Esportivos",desc="Supercar britânico"           },
    ["baller"]    = { nome="Baller",        preco=90000,   cat="SUVs",      desc="SUV de luxo"                  },
    ["cavalcade"] = { nome="Cavalcade",     preco=65000,   cat="SUVs",      desc="SUV americano grande"         },
    ["granger"]   = { nome="Granger",       preco=35000,   cat="SUVs",      desc="SUV policial reconvertido"    },
    ["xls"]       = { nome="XLS",           preco=120000,  cat="SUVs",      desc="SUV de ultra luxo"            },
    ["bati801"]   = { nome="Bati 801",      preco=15000,   cat="Motos",     desc="Moto esportiva leve"          },
    ["akuma"]     = { nome="Akuma",         preco=9000,    cat="Motos",     desc="Moto naked japonesa"          },
    ["daemon"]    = { nome="Daemon",        preco=11000,   cat="Motos",     desc="Chopper custom"               },
    ["faggio2"]   = { nome="Faggio Sport",  preco=4500,    cat="Motos",     desc="Scooter leve e econômico"     },
    ["burrito"]   = { nome="Burrito",       preco=22000,   cat="Vans",      desc="Van de carga versátil"        },
    ["speedo"]    = { nome="Speedo",        preco=18000,   cat="Vans",      desc="Van de entrega compacta"      },
    ["youga"]     = { nome="Youga",         preco=16000,   cat="Vans",      desc="Van de passageiros"           },
    ["dinghy"]    = { nome="Dinghy",        preco=25000,   cat="Barcos",    desc="Lancha rápida"                },
    ["jetmax"]    = { nome="Jetmax",        preco=275000,  cat="Barcos",    desc="Iate esportivo de luxo"       },
    ["marquis"]   = { nome="Marquis",       preco=130000,  cat="Barcos",    desc="Veleiro clássico"             },
  },
}

-- ── Inicialização ─────────────────────────────────────────────────────────────

AddEventHandler("onResourceStart", function(res)
  if res ~= GetCurrentResourceName() then return end
  local schema = LoadResourceFile(GetCurrentResourceName(), "sql/schema.sql")
  if schema then
    exports['oxmysql']:execute(schema, {})
  end
  -- Envia setup a jogadores já online (resource restart em produção)
  for _, s in ipairs(GetPlayers()) do
    TriggerClientEvent("vhub_dealership:setup", tonumber(s),
      CFG.concessionarias, CFG.catalogo)
  end
  print("[vhub_dealership] Pronto.")
end)

-- ── Sessões (referências vivas) ───────────────────────────────────────────────

AddEventHandler("vHub:characterLoad", function(user)
  _sessions[user.source] = user
  if not user.data.vehicles then user.data.vehicles = {} end
end)

AddEventHandler("vHub:playerSpawn", function(user)
  _sessions[user.source] = user
  TriggerClientEvent("vhub_dealership:setup", user.source,
    CFG.concessionarias, CFG.catalogo)
end)

AddEventHandler("playerDropped", function()
  _sessions[source] = nil
end)

local function getUser(src)
  return _sessions[tonumber(src)]
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function validarPlaca(plate)
  if type(plate) ~= "string" then return nil end
  local p = plate:upper():match("^%s*(.-)%s*$")
  if not p or #p < 2 or #p > 8 then return nil end
  if not p:match("^[A-Z0-9][A-Z0-9 ]*$") then return nil end
  return p
end

-- oxmysql nessa versão não retorna promise sem callback.
-- Usa promise.new() nativo do FiveM para compatibilidade com Citizen.Await.
local function dbScalar(sql, params)
  local p = promise.new()
  exports['oxmysql']:scalar(sql, params, function(r) p:resolve(r) end)
  return Citizen.Await(p)
end

-- Deve ser chamada dentro de Citizen.CreateThread
local function placaExiste(plate)
  return dbScalar("SELECT 1 FROM vhub_plates WHERE plate = ? LIMIT 1", { plate }) ~= nil
end

local function gerarPlacaUnica()
  for _ = 1, 50 do
    local plate = string.format("%s%s%s %d%d%d%d",
      string.char(65 + math.random(0, 25)),
      string.char(65 + math.random(0, 25)),
      string.char(65 + math.random(0, 25)),
      math.random(0, 9), math.random(0, 9),
      math.random(0, 9), math.random(0, 9))
    if not placaExiste(plate) then return plate end
  end
  return "VH" .. tostring(os.time() % 100000)
end

local function registrarPlaca(plate, char_id)
  -- fire-and-forget: não precisa aguardar, inserção é idempotente (INSERT IGNORE)
  exports['oxmysql']:execute(
    "INSERT IGNORE INTO vhub_plates(plate, char_id) VALUES(?, ?)",
    { plate, char_id }, function() end)
end

local function removerPlaca(plate)
  exports['oxmysql']:execute(
    "DELETE FROM vhub_plates WHERE plate = ?", { plate }, function() end)
end

local function estadoVeiculoInicial(modelo)
  return {
    model         = modelo,
    customization = { model = modelo },
    condition     = nil,
    fuel          = 100.0,
    locked        = false,
    out           = false,
    position      = nil,
    rotation      = nil,
  }
end

-- ── Net events ────────────────────────────────────────────────────────────────

RegisterNetEvent("vhub_dealership:buy")
AddEventHandler("vhub_dealership:buy", function(modelo, placa_custom)
  local src  = source
  local user = getUser(src)
  if not user or not user.char_id then
    TriggerClientEvent("vhub_dealership:notify", src,
      "Sessão não carregada. Tente novamente em instantes.")
    return
  end

  local veh_cfg = CFG.catalogo[modelo]
  if not veh_cfg then
    TriggerClientEvent("vhub_dealership:notify", src, "Modelo inválido.")
    return
  end

  Citizen.CreateThread(function()
    local placa
    local preco_total = veh_cfg.preco

    if placa_custom and placa_custom ~= "" then
      placa = validarPlaca(placa_custom)
      if not placa then
        TriggerClientEvent("vhub_dealership:notify", src,
          "Placa inválida. Use 2-8 caracteres alfanuméricos.")
        return
      end
      if placaExiste(placa) then
        TriggerClientEvent("vhub_dealership:notify", src,
          "Esta placa já está em uso. Escolha outra.")
        return
      end
      preco_total = preco_total + CFG.taxa_placa_custom
    else
      placa = gerarPlacaUnica()
    end

    -- Debita saldo (carteira + banco)
    local ok_pag, pagou = pcall(function()
      return exports.vhub_money:tryFullPayment(src, preco_total)
    end)
    if not (ok_pag and pagou) then
      TriggerClientEvent("vhub_dealership:notify", src,
        ("Saldo insuficiente. Preço: R$ %d"):format(preco_total))
      return
    end

    -- Registra placa no BD
    registrarPlaca(placa, user.char_id)

    -- Tenta entregar chave ao inventário
    local ok_key, deu_chave = pcall(function()
      return exports.vhub_inventory:giveVehicleKey(src, placa)
    end)
    if not (ok_key and deu_chave) then
      -- Inventário cheio — estorna e remove placa
      pcall(function() exports.vhub_money:giveWallet(src, preco_total) end)
      removerPlaca(placa)
      TriggerClientEvent("vhub_dealership:notify", src,
        "Inventário cheio! Não foi possível entregar a chave. Pagamento estornado.")
      return
    end

    -- Estado inicial salvo no user.data (autosave vHub)
    if not user.data.vehicles then user.data.vehicles = {} end
    user.data.vehicles[placa] = estadoVeiculoInicial(modelo)

    TriggerClientEvent("vhub_dealership:compra_ok", src, {
      modelo = modelo,
      placa  = placa,
      preco  = preco_total,
      nome   = veh_cfg.nome,
    })
    TriggerClientEvent("vhub_dealership:notify", src,
      ("Parabéns! Você comprou um %s. Placa: %s. Chave no inventário!"):format(
        veh_cfg.nome, placa))
    print(("[vhub_dealership] buy uid=%d modelo=%s placa=%s preco=%d"):format(
      user.id, modelo, placa, preco_total))
  end)
end)

RegisterNetEvent("vhub_dealership:sell")
AddEventHandler("vhub_dealership:sell", function(placa)
  local src  = source
  local user = getUser(src)
  if not user or not user.char_id then
    TriggerClientEvent("vhub_dealership:notify", src,
      "Sessão não carregada. Tente novamente em instantes.")
    return
  end

  local p = validarPlaca(placa)
  if not p then
    TriggerClientEvent("vhub_dealership:notify", src, "Placa inválida.")
    return
  end

  local ok_has, tem = pcall(function()
    return exports.vhub_inventory:hasVehicleKey(src, p)
  end)
  if not (ok_has and tem) then
    TriggerClientEvent("vhub_dealership:notify", src,
      "Você não tem a chave deste veículo.")
    return
  end

  -- Lê estado do veículo (in-memory, sem async)
  if not user.data.vehicles then user.data.vehicles = {} end
  local veh_state = user.data.vehicles[p]
  local modelo    = type(veh_state) == "table" and veh_state.model or nil
  local veh_cfg   = modelo and CFG.catalogo[modelo]
  local preco_revenda = veh_cfg
    and math.floor(veh_cfg.preco * CFG.fator_revenda)
    or 0

  -- Não pode vender com veículo na rua
  if type(veh_state) == "table" and veh_state.out then
    TriggerClientEvent("vhub_dealership:notify", src,
      "Guarde o veículo na garagem antes de vender.")
    return
  end

  -- Remove chave, placa do BD e estado
  pcall(function() exports.vhub_inventory:takeVehicleKey(src, p) end)
  removerPlaca(p)
  user.data.vehicles[p] = nil

  if preco_revenda > 0 then
    pcall(function() exports.vhub_money:giveWallet(src, preco_revenda) end)
  end

  TriggerClientEvent("vhub_dealership:notify", src,
    ("Veículo vendido por R$ %d."):format(preco_revenda))
  print(("[vhub_dealership] sell uid=%d placa=%s recebeu=%d"):format(
    user.id, p, preco_revenda))
end)

RegisterNetEvent("vhub_dealership:test_drive")
AddEventHandler("vhub_dealership:test_drive", function(modelo, conc_idx)
  local src = source
  if not CFG.catalogo[modelo] then return end
  local conc = CFG.concessionarias[conc_idx]
  if not conc then return end
  local pos = { x = conc.x + 3.0, y = conc.y + 5.0, z = conc.z, heading = 0.0 }
  TriggerClientEvent("vhub_dealership:do_test_drive", src, modelo, pos)
end)

-- ── Exports ───────────────────────────────────────────────────────────────────

exports("getCatalogo",    function()        return CFG.catalogo          end)
exports("getModeloInfo",  function(modelo)  return CFG.catalogo[modelo]  end)
