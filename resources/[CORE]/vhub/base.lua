-- base.lua — Carrega server/init.lua que complementa o vHub dos shared_scripts
-- O vHub já existe como tabela (criado por shared/config.lua) mas está INCOMPLETO:
--   tem Logger, Utils, E, mergeConfig — mas NÃO tem State, Auth, Kernel, init etc.
-- A flag vHub._server_ready indica se os módulos server/ já foram carregados.

local _RES = GetCurrentResourceName()
local name = _RES or error("[vHub][BASE] GetCurrentResourceName ausente")

-- Verifica se os módulos server/ já foram carregados nesta sessão
-- (ex: reload do resource — evita duplo loadmod)
local vHub_existente = rawget(_G, "vHub")
if type(vHub_existente) == "table" and vHub_existente._server_ready == true then
  return vHub_existente
end

-- Carrega server/init.lua que vai:
--   1. Pegar o vHub dos shared (rawget(_G, "vHub"))
--   2. Adicionar class(), assertThread(), loadmod()
--   3. Carregar todos os módulos server/ via loadmod()
--   4. Retornar o mesmo vHub enriquecido
local path = "server/init.lua"
local code = LoadResourceFile(name, path)
if not code or type(code) ~= "string" or code == "" then
  error(("[vHub][BASE] %s ausente ou vazio"):format(path))
end

local fn, err = load(code, ("@%s/%s"):format(name, path), "t", _ENV)
if not fn then error(("[vHub][BASE] erro de compilação em %s: %s"):format(path, err)) end

local ok, mod = pcall(fn)
if not ok then error(("[vHub][BASE] erro ao carregar %s: %s"):format(path, mod)) end
if type(mod) ~= "table" then
  error("[vHub][BASE] server/init.lua deve retornar tabela vHub")
end

-- Marca como totalmente carregado para evitar dupla inicialização em reload
mod._server_ready = true

-- Garante que o global aponta para o mesmo objeto (pode já apontar)
rawset(_G, "vHub", mod)
return mod
