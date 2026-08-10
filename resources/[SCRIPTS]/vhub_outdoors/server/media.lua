-- server/media.lua - preflight remoto restrito aos hosts permitidos

VHubOutdoors = VHubOutdoors or {}

local CFG = VHubOutdoors.cfg
local M = {}
VHubOutdoors.Media = M

local MIME_BY_TYPE = {
  image = {
    ['image/png'] = true,
    ['image/jpeg'] = true,
    ['image/webp'] = true,
    ['image/gif'] = true,
  },
  video = {
    ['video/mp4'] = true,
    ['video/webm'] = true,
  },
}

local function header_of(headers, wanted)
  if type(headers) ~= 'table' then return nil end
  for name, value in pairs(headers) do
    if type(name) == 'string' and name:lower() == wanted then
      return type(value) == 'string' and value or tostring(value)
    end
  end
  return nil
end

local function resolve_once(state, pending, value)
  if state.finished then return end
  state.finished = true
  pending:resolve(value)
end

-- Confirma MIME e tamanho sem baixar o corpo da midia Discord.
function M.probe(media)
  if type(media) ~= 'table' then return false, 'invalid_media' end
  if media.media_type == 'youtube' then return true end

  local allowed_mime = MIME_BY_TYPE[media.media_type]
  local byte_limit = media.media_type == 'image'
    and CFG.limits.max_image_bytes
    or CFG.limits.max_video_bytes
  if not allowed_mime or not byte_limit then return false, 'invalid_media' end

  local pending = promise.new()
  local state = { finished = false }
  Citizen.SetTimeout(CFG.limits.probe_timeout_ms, function()
    resolve_once(state, pending, { ok = false, err = 'probe_timeout' })
  end)
  PerformHttpRequest(media.media_url, function(status, _, headers)
    local content_type = header_of(headers, 'content-type')
    content_type = content_type and content_type:match('^%s*([^;]+)')
    content_type = content_type and content_type:lower() or nil
    local content_length = tonumber(header_of(headers, 'content-length'))
    local status_code = tonumber(status)
    local ok = status_code and status_code >= 200 and status_code < 300
      and allowed_mime[content_type] == true
      and content_length and content_length >= 1 and content_length <= byte_limit
    resolve_once(state, pending, {
      ok = ok == true,
      err = ok and nil or 'remote_media_rejected',
    })
  end, 'HEAD', '', {
    ['Accept'] = table.concat(media.media_type == 'image'
      and { 'image/png', 'image/jpeg', 'image/webp', 'image/gif' }
      or { 'video/mp4', 'video/webm' }, ','),
  }, { followLocation = false })

  local result = Citizen.Await(pending)
  return result.ok, result.err
end
