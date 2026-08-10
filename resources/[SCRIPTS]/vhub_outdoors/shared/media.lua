-- shared/media.lua - validacao pura de midia e tipos primitivos

VHubOutdoors = VHubOutdoors or {}

local CFG = VHubOutdoors.cfg
local DISCORD_HOSTS = {
  ['cdn.discordapp.com'] = true,
  ['media.discordapp.net'] = true,
}
local IMGUR_HOSTS = {
  ['i.imgur.com'] = true,
  ['imgur.com'] = true,
  ['www.imgur.com'] = true,
}
local YOUTUBE_HOSTS = {
  ['youtu.be'] = true,
  ['youtube.com'] = true,
  ['www.youtube.com'] = true,
  ['m.youtube.com'] = true,
  ['music.youtube.com'] = true,
  ['youtube-nocookie.com'] = true,
  ['www.youtube-nocookie.com'] = true,
}
local IMAGE_EXTENSIONS = {
  png = true,
  jpg = true,
  jpeg = true,
  webp = true,
  gif = true,
}
local VIDEO_EXTENSIONS = {
  mp4 = true,
  webm = true,
}

local function trim(value)
  return value:match('^%s*(.-)%s*$')
end

local function youtube_id(host, path)
  local id
  if host == 'youtu.be' then
    id = path:match('^/([%w_%-]+)')
  elseif host:find('youtube%-nocookie%.com$', 1, false) then
    id = path:match('^/embed/([%w_%-]+)')
  else
    id = path:match('[?&]v=([%w_%-]+)')
      or path:match('^/shorts/([%w_%-]+)')
      or path:match('^/embed/([%w_%-]+)')
  end
  return id and #id == 11 and id:match('^[%w_%-]+$') and id or nil
end

-- Converte um numero hostil em valor finito ou nil.
function VHubOutdoors.finite(value)
  local number = tonumber(value)
  if not number or number ~= number or number == math.huge or number == -math.huge then
    return nil
  end
  return number
end

-- Valida um identificador idempotente usado nas mutacoes.
function VHubOutdoors.validOperationId(value, maximum)
  return type(value) == 'string'
    and #value >= 8
    and #value <= (tonumber(maximum) or 96)
    and value:match('^[%w:_%-]+$') ~= nil
end

-- Normaliza um titulo curto sem caracteres de controle.
function VHubOutdoors.sanitizeTitle(value)
  if type(value) ~= 'string' then return nil end
  local title = trim(value)
  if #title < 1 or #title > CFG.limits.max_title or title:find('%c') then return nil end
  return title
end

-- Classifica e normaliza URL permitida de Discord CDN, Imgur direto ou YouTube.
function VHubOutdoors.parseMedia(value)
  if type(value) ~= 'string' then return nil end
  local url = trim(value)
  if #url < 1 or #url > CFG.limits.max_url or url:find('%c')
      or url:find('\\', 1, true) or url:find('#', 1, true) then
    return nil
  end

  local host, path = url:match('^https://([%w%.%-]+)(/[^%s]*)$')
  if not host or not path then return nil end
  host = host:lower()

  if YOUTUBE_HOSTS[host] then
    local id = youtube_id(host, path)
    if not id then return nil end
    return {
      media_type = 'youtube',
      media_url = ('https://www.youtube.com/watch?v=%s'):format(id),
      youtube_id = id,
      source = id,
    }
  end

  local discord = DISCORD_HOSTS[host]
    and path:match('^/attachments/%d+/%d+/') ~= nil
  local imgur = IMGUR_HOSTS[host]
    and path:match('^/[%w_%-]+%.[%w]+[?%w%%&=_%-%.]*$') ~= nil
  if not discord and not imgur then
    return nil
  end

  local file_path = path:match('^([^?]+)')
  local extension = file_path and file_path:match('%.([%w]+)$')
  extension = extension and extension:lower() or nil
  local media_type = extension and IMAGE_EXTENSIONS[extension] and 'image'
    or extension and VIDEO_EXTENSIONS[extension] and 'video'
    or nil
  if not media_type then return nil end
  if imgur and media_type ~= 'image' then return nil end

  local canonical_host = imgur and 'i.imgur.com' or host
  local canonical_url = ('https://%s%s'):format(canonical_host, path)

  return {
    media_type = media_type,
    media_url = canonical_url,
    youtube_id = nil,
    source = canonical_url,
  }
end

-- Confirma a origem compacta recebida pela replica global.
function VHubOutdoors.validSnapshotSource(media_type, source)
  if media_type == 'youtube' then
    return type(source) == 'string'
      and #source == 11
      and source:match('^[%w_%-]+$') ~= nil
  end
  local media = VHubOutdoors.parseMedia(source)
  return media ~= nil and media.media_type == media_type
end
