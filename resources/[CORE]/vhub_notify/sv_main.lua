-- sv_main.lua — ponte server->client do toast global (acucar sobre o evento vHub:notify)

-- dispara um toast para um jogador especifico (data = tabela rica { type, title, msg, duration })
local function notify(source, data)
    if not data then return end
    if source == -1 then return end                 -- sem broadcast acidental
    TriggerClientEvent('vHub:notify', source, data)
end

exports('notify', notify)
exports('sendAlert', notify)                         -- alias de compatibilidade
