local Tunnel = module('vrp', 'lib/Tunnel')
local Proxy = module('vrp', 'lib/Proxy')

vRP = Proxy.getInterface('vRP')

local vRPIdentidade = Tunnel.getInterface('vrp_identidade')
local Config = VOIDC.cfg or {}

local css = [[
    @import url('https://fonts.googleapis.com/css?family=Muli:300,400,700');

    .clear {
        clear: both;
    }

    #DocumentSection {
        background-image: url("https://i.imgur.com/sVU9DCo.png");
        width: 425px;
        height: 274px;
        border-radius: 5px;
        box-shadow: 0px 0px 20px rgba(0, 0, 0, 2);
        text-align: center;
        position: absolute;
        right: 0.5%;
        top: 50%;
        font-family: 'Muli';
        color: #5eb4ff;
        padding-bottom: 5px;
        z-index: 1;
        overflow: hidden;
    }

    #DocumentSection:before,
    #DocumentSection:after {
        content: ' ';
        position: absolute;
        width: 100%;
        height: 100%;
    }

    #DocumentSection:before {
        background-color: #00FFFF;
        top: -300%;
        left: -100%;
        transform: rotate(-5deg);
        z-index: 1;
    }

    #DocumentSection:after {
        background-color: #000000;
        top: -191%;
        left: -100%;
        transform: rotate(-6deg);
        z-index: 0;
    }

    #DocumentSection .each-info {
        display: block;
        margin: 0;
        width: 80%;
        color: #000000;
        margin: 0 auto;
    }

    #DocumentSection .each-info.person-name {
        font-size: 20px;
    }

    #DocumentSection .each-info.person-age {
        font-size: 15px;
    }

    #DocumentSection .each-info2 {
        font-size: 15px;
        border-radius: 10px;
        left: 50%;
        color: #000000;
    }

    #DocumentSection .each-info.person-job2 {
        top: 95%;
        left: 85%;
        font-size: 15px;
    }

    #DocumentSection .each-info.person-job {
        border-bottom: 3px solid rgba(0, 179, 156, 0.8);
        top: 90%;
        left: 80%;
        font-size: 15px;
    }

    #DocumentSection .secondary-info {
        margin-top: 25px;
    }

    #DocumentSection .secondary-info .clear {
        margin-bottom: 2px;
        display: block;
    }

    #DocumentSection .secondary-info .each-info strong {
        float: left;
        font-weight: 300;
    }

    #DocumentSection .secondary-info .each-info span {
        float: right;
        font-weight: bold;
        color: #000000;
    }
]]

local identityOpen = false

local function fecharIdentidade()
    if vRP and vRP._removeDiv then
        vRP._removeDiv('rg')
    end
    if vRP and vRP._DeletarObjeto then
        vRP._DeletarObjeto()
    end
    identityOpen = false
end

local function abrirIdentidade()
    if not vRPIdentidade or not vRPIdentidade.Identidade then return end

    local foto, name, firstname, user_id, registration, age, phone, carteira, vip, banco, multas, paypal, groupname, groupname2 = vRPIdentidade.Identidade()
    if not user_id then return end

    if not vip or vip == '' then vip = '' end
    if not groupname2 or groupname2 == '' then groupname2 = '' end
    if not foto or foto == '' then foto = '' end

    local html = string.format("<div id='DocumentSection'><div class='avatar-img'><img src='%s'></div> <div class='infos'><div class='main-info'>"..
        "<h1 class='each-info person-name'>%s %s</h1>"..
        "<h2 class='each-info person-age'>%s anos</h2>"..
        "<h2 class='each-info person-job'>%s</h2>"..
        "<h2 class='each-info person-job2'>%s</h2>"..
        "</div>"..
        "<div class='secondary-info'>"..
        "<div class='each-info'><strong>Identidade:</strong><span class='person-id'>%s</span></div>"..
        "<div class='clear'></div>"..
        "<div class='each-info'><strong>Registro: </strong><span class='person-passport'>%s</span></div>"..
        "<div class='clear'></div>"..
        "<div class='each-info'><strong>Telefone:</strong><span class='person-phone'>%s</span></div>"..
        "<div class='clear'></div>"..
        "<div class='each-info'><strong>Carteira:</strong><span class='person-phone'>$%s</span></div>"..
        "<div class='clear'></div>"..
        "<div class='each-info'><strong>Banco:</strong><span class='person-phone'>$%s</span></div>"..
        "<div class='clear'></div>"..
        "<div class='each-info'><strong>Multas:</strong><span class='person-phone'>$%s</span></div>"..
        "<div class='clear'></div>"..
        "<div class='each-info2'><strong></strong><span class='person-phone'>%s</span></div>"..
        "<div class='clear'></div>"..
        "</div>"..
        "</div>"..
        "</div>", foto, name, firstname, age, groupname, groupname2, user_id, registration, phone, carteira, banco, multas, vip)

    if vRP and vRP._CarregarObjeto then
        vRP._CarregarObjeto('amb@world_human_stand_mobile@female@text@enter', 'enter', 'p_ld_id_card_01', 50, 28422)
        Wait(1500)
    end

    if vRP and vRP._setDiv then
        vRP._setDiv('rg', css, html)
    end

    identityOpen = true
end

local function toggleIdentidade()
    if identityOpen then
        fecharIdentidade()
        return
    end
    abrirIdentidade()
end

local comandoIdentidade = (Config.identidade and Config.identidade.comando) or 'identidade'

RegisterCommand(comandoIdentidade, function()
    if Config.identidade and Config.identidade.habilitar == false then return end
    toggleIdentidade()
end, false)

if not (Config.identidade and Config.identidade.habilitar == false) then
    RegisterKeyMapping(comandoIdentidade, 'Abrir identidade', 'keyboard', (Config.identidade and Config.identidade.tecla) or 'F11')
end
