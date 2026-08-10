VHubNpcAI = VHubNpcAI or {}

local CORES = {
    info = '^2',
    warn = '^3',
    error = '^1',
}

local function limpar(mensagem)
    return tostring(mensagem or '')
        :gsub('[\r\n]', ' ')
        :gsub('%^%d', '')
        :sub(1, 512)
end

local function escrever(nivel, mensagem)
    local cor = CORES[nivel] or '^7'
    print(('^5[vhub_npcai]^7 %s%s^7'):format(cor, limpar(mensagem)))
end

VHubNpcAI.Log = {
    info = function(mensagem) escrever('info', mensagem) end,
    warn = function(mensagem) escrever('warn', mensagem) end,
    error = function(mensagem) escrever('error', mensagem) end,
}
