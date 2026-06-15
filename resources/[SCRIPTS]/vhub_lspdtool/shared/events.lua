-- events.lua — nomes canônicos de evento do LSPD Tool (fonte única, sem hardcode espalhado)
-- Namespace `vhub.lspdtool:*` é distinto do `vHub:*` do core. NÃO estende vHub.E.

VHubLspd = VHubLspd or {}


-- ============================================================
-- EVENTS (rede)
-- ============================================================

VHubLspd.E = {
    -- ----- Scan de placa -----
    PLATE_SCANNED    = 'vhub.lspdtool:plateScanned',     -- client → server (canônico, pipeline seguro)

    -- ----- BOLO / dispatch -----
    BOLO_ALERT       = 'vhub.lspdtool:boloAlert',        -- server → policial (direcionado)
    NOTIFY           = 'vhub.lspdtool:notify',           -- server → policial (texto simples)

    -- ----- Radar nativo -----
    REQ_RADAR        = 'vhub.lspdtool:reqRadar',         -- client → server (pede autorização)
    ENABLE_RADAR     = 'vhub.lspdtool:enableRadar',      -- server → client (autoriza abertura)

    -- ----- MDT / Central de Despacho -----
    REQ_MDT          = 'vhub.lspdtool:reqMdt',           -- client → server (pede dados, police-gated)
    MDT_DATA         = 'vhub.lspdtool:mdtData',          -- server → client (bolos + scans + canManage)
    MDT_ADD          = 'vhub.lspdtool:mdtAddBolo',       -- client → server (criar BOLO, permManageBolo)
    MDT_DEL          = 'vhub.lspdtool:mdtDelBolo',       -- client → server (remover BOLO, permManageBolo)

    -- ----- Prisão / detenção (RP arrest) -----
    DETAIN_APPLY     = 'vhub.lspdtool:detainApply',      -- server → alvo (entra em estado detido)
    DETAIN_RELEASE   = 'vhub.lspdtool:detainRelease',    -- server → alvo (sai do estado detido)

    -- ----- Procurados (pessoas) -----
    WANTED_ALERT     = 'vhub.lspdtool:wantedAlert',      -- server → policiais (direcionado)
}


-- ============================================================
-- NUI MESSAGE TYPES (Lua → CEF) — contrato único com web/app.js
-- ============================================================
-- O dispatcher (web/app.js) roteia pelo PREFIXO do type ('radar:' | 'helicam:' | 'mdt:') para o
-- módulo dono. Overlays PASSIVOS (sem NuiFocus): só recebem estado. Não decidem verdade.

VHubLspd.UI = {
    -- radar terrestre (módulo web/modules/radar)
    OPEN   = 'radar:open',     -- mostra o overlay do radar
    CLOSE  = 'radar:close',    -- esconde o overlay
    UPDATE = 'radar:update',   -- delta { patrol, front, rear, locked }

    -- heli-câmera (módulo web/modules/helicam)
    HELI_OPEN   = 'helicam:open',     -- mostra o HUD da câmera
    HELI_CLOSE  = 'helicam:close',    -- esconde o HUD
    HELI_UPDATE = 'helicam:update',   -- delta { zoom, altitude, heading, vision, spotlight, locked, target }

    -- MDT / despacho (módulo web/modules/mdt — INTERATIVO, com foco)
    MDT_OPEN    = 'mdt:open',          -- abre o painel com o snapshot
    MDT_CLOSE   = 'mdt:close',         -- fecha o painel
    MDT_DATA    = 'mdt:data',          -- refresca dados (após criar/remover BOLO)
}


return VHubLspd.E
