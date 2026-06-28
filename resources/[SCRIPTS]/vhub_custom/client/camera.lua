-- client/camera.lua — L2 HAL: câmera orbital livre para customização de veículo
-- Substitui a câmera FIXA antiga (SetCamCoord estático). A câmera orbita o veículo
-- em coordenadas esféricas (yaw/pitch/raio) com interpolação suave e pode FOCAR
-- dinamicamente uma peça (frente/traseira/lateral/roda/teto), reposicionando o alvo
-- e aproximando o raio.
--
-- POR QUE A ÓRBITA VEM DA NUI: com SetNuiFocus(true,true) o cursor do CEF captura
-- o mouse, então o jogo NÃO recebe look pelos controles nativos. A NUI lê o arrasto
-- no palco central e envia deltas via bridge (Cam.orbit / Cam.zoom). Assim o controle
-- é fluido e convive com os painéis laterais clicáveis.
--
-- Contrato: uso LOCAL apenas (L-19). A thread de render só existe enquanto a câmera
-- está ativa e morre em stop() — zero loop ocioso (L-06).
---@diagnostic disable: undefined-global

VHubCustom     = VHubCustom or {}
VHubCustom.Cam = {}
local Cam = VHubCustom.Cam


-- ============================================================
-- ESTADO INTERNO
-- ============================================================

local _cam      = nil      -- handle da câmera nativa
local _veh      = 0        -- entidade alvo
local _running  = false    -- flag única de lifecycle da thread

-- coordenadas esféricas DESEJADAS (alvo da interpolação)
local _yaw, _pitch, _radius = 35.0, 16.0, 4.4
-- coordenadas esféricas ATUAIS (suavizadas a cada frame)
local _curYaw, _curPitch, _curRad = 35.0, 16.0, 4.4
-- deslocamento do alvo em relação ao centro do veículo (foco de peça)
local _focusOff = vec3(0.0, 0.0, 0.45)

-- limites de inspeção
local PITCH_MIN, PITCH_MAX = -18.0, 72.0
local RAD_MIN,   RAD_MAX   = 1.8, 7.5
local SMOOTH               = 0.16    -- fator de interpolação por frame (0..1)


-- ============================================================
-- HELPERS DE GEOMETRIA
-- ============================================================

-- centro do veículo + offset de foco da peça (coordenada de mundo)
local function targetCoord()
  if not DoesEntityExist(_veh) then return GetEntityCoords(PlayerPedId()) end
  return GetOffsetFromEntityInWorldCoords(_veh, _focusOff.x, _focusOff.y, _focusOff.z)
end

-- converte (yaw, pitch, raio) em torno do alvo → coordenada de mundo da câmera
-- yaw é relativo ao heading do veículo, para a órbita acompanhar o carro
local function sphericalToWorld(tgt, yaw, pitch, radius)
  local ry  = math.rad(yaw + GetEntityHeading(_veh))
  local rp  = math.rad(pitch)
  local horiz = radius * math.cos(rp)
  return vec3(
    tgt.x + horiz * math.sin(ry),
    tgt.y + horiz * math.cos(ry),
    tgt.z + radius * math.sin(rp)
  )
end

local function lerp(a, b, t) return a + (b - a) * t end


-- ============================================================
-- THREAD DE RENDER (criada no start, encerrada no stop)
-- só interpola e redesenha; a entrada vem da NUI via Cam.orbit/Cam.zoom
-- ============================================================

local function spawnRenderThread()
  Citizen.CreateThread(function()
    while _running do
      -- trava ações do jogador como defesa (caso o foco do CEF caia por 1 frame)
      DisablePlayerFiring(PlayerId(), true)
      DisableControlAction(0, 24, true)  -- Attack
      DisableControlAction(0, 25, true)  -- Aim
      DisableControlAction(0, 47, true)  -- Detonate
      DisableControlAction(0, 257, true) -- Attack2

      _curYaw   = lerp(_curYaw,   _yaw,    SMOOTH)
      _curPitch = lerp(_curPitch, _pitch,  SMOOTH)
      _curRad   = lerp(_curRad,   _radius, SMOOTH)

      if _cam and DoesCamExist(_cam) and DoesEntityExist(_veh) then
        local tgt = targetCoord()
        local pos = sphericalToWorld(tgt, _curYaw, _curPitch, _curRad)
        SetCamCoord(_cam, pos.x, pos.y, pos.z)
        PointCamAtCoord(_cam, tgt.x, tgt.y, tgt.z)
      end

      Citizen.Wait(0)
    end
  end)
end


-- ============================================================
-- API PÚBLICA
-- ============================================================

-- inicia a câmera orbital sobre o veículo (idempotente)
function Cam.start(veh)
  if _cam then return end
  if not DoesEntityExist(veh) or veh == 0 then return end

  _veh = veh
  _yaw, _pitch, _radius        = 35.0, 16.0, 4.4
  _curYaw, _curPitch, _curRad  = _yaw, _pitch, _radius
  _focusOff                    = vec3(0.0, 0.0, 0.45)

  _cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
  local tgt = targetCoord()
  local pos = sphericalToWorld(tgt, _curYaw, _curPitch, _curRad)
  SetCamCoord(_cam, pos.x, pos.y, pos.z)
  PointCamAtCoord(_cam, tgt.x, tgt.y, tgt.z)
  SetCamFov(_cam, 50.0)
  SetCamActive(_cam, true)
  RenderScriptCams(true, true, 600, true, false)

  _running = true
  spawnRenderThread()
end

-- aplica delta de arrasto do mouse (vindo da NUI) à órbita
function Cam.orbit(dx, dy)
  if not _cam then return end
  _yaw   = _yaw + (tonumber(dx) or 0.0) * 0.35
  _pitch = math.max(PITCH_MIN, math.min(PITCH_MAX, _pitch + (tonumber(dy) or 0.0) * 0.30))
end

-- aplica zoom (delta>0 aproxima; delta<0 afasta)
function Cam.zoom(delta)
  if not _cam then return end
  _radius = math.max(RAD_MIN, math.min(RAD_MAX, _radius - (tonumber(delta) or 0.0) * 0.5))
end

-- foca dinamicamente uma peça reposicionando o alvo + aproximando o raio
-- part: 'geral' | 'frente' | 'traseira' | 'lateral' | 'roda' | 'teto'
function Cam.focus(part)
  if not DoesEntityExist(_veh) then return end
  -- GetModelDimensions retorna (min, max) do bounding box local do modelo
  local mn, mx = GetModelDimensions(GetEntityModel(_veh))
  local len = (mx.y - mn.y)
  local wid = (mx.x - mn.x)
  local hei = (mx.z - mn.z)
  local cz  = (mx.z + mn.z) * 0.5

  if part == 'frente' then
    _focusOff = vec3(0.0, len * 0.42, cz);     _yaw, _pitch, _radius = 18.0, 12.0, 3.2
  elseif part == 'traseira' then
    _focusOff = vec3(0.0, -len * 0.42, cz);    _yaw, _pitch, _radius = 162.0, 12.0, 3.2
  elseif part == 'lateral' then
    _focusOff = vec3(0.0, 0.0, cz);            _yaw, _pitch, _radius = 90.0, 6.0, 3.8
  elseif part == 'roda' then
    _focusOff = vec3(-wid * 0.5, len * 0.30, mn.z + hei * 0.18)
    _yaw, _pitch, _radius = 62.0, 4.0, 2.2
  elseif part == 'teto' then
    _focusOff = vec3(0.0, 0.0, mx.z);          _yaw, _pitch, _radius = 35.0, 48.0, 4.0
  else -- 'geral'
    _focusOff = vec3(0.0, 0.0, cz + 0.1);      _yaw, _pitch, _radius = 35.0, 16.0, 4.4
  end
end

-- encerra a câmera, mata a thread e devolve o controle ao jogador (cleanup A-07)
function Cam.stop()
  _running = false
  if _cam then
    RenderScriptCams(false, true, 500, true, false)
    SetCamActive(_cam, false)
    DestroyCam(_cam, false)
    _cam = nil
  end
  _veh = 0
end

-- true se a câmera está ativa (consulta por outros módulos)
function Cam.active() return _cam ~= nil end
