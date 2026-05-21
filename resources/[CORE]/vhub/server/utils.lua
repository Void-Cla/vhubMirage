-- server/utils.lua — helpers pequenos (utilitários)
function vHub.formatNumber(n)
  return tostring(math.floor(n)):reverse()
    :gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

function vHub.formatTime(s)
  local d=math.floor(s/86400); s=s-d*86400
  local h=math.floor(s/3600);  s=s-h*3600
  local m=math.floor(s/60);    s=s-m*60
  if d>0 then return ("%dd %02dh %02dm"):format(d,h,m)
  elseif h>0 then return ("%dh %02dm %02ds"):format(h,m,s)
  elseif m>0 then return ("%dm %02ds"):format(m,s)
  else return ("%ds"):format(s) end
end
