-- eval_cuff / client
--
-- Owns the control block and nothing else. The server decides *that* this
-- player is held; this side decides *what that takes away*:
--   cuff    the whole gameplay action stream, plus Map and Hub by name
--   escort  the same, sparing Movement so the target can walk himself
--   free    release every claim this resource holds
-- Chat, voice and the pause menu are never taken: a held player must still be
-- able to say so, reach settings and disconnect.

local CONTROL_EVENT = "eval_cuff:control"
local SYNC_EVENT    = "eval_cuff:sync"

local mode = "free"

-- Releasing something never claimed is not an error, so this runs unconditionally.
local function releaseAll()
    Open77.input.blockAll(false)
    Open77.input.setActionBlocked("Map", false)
    Open77.input.setActionBlocked("Hub", false)
end

local function apply(wanted)
    releaseAll()
    mode = "free"
    if wanted ~= "cuff" and wanted ~= "escort" then return end

    local ok, reason
    if wanted == "escort" then
        ok, reason = Open77.input.blockAll({ except = { "Movement" } })
    else
        ok, reason = Open77.input.blockAll()
    end
    if not ok then
        print(("eval_cuff: blockAll (%s) refused: %s"):format(wanted, tostring(reason)))
        return
    end

    -- Menu shortcuts arrive on a different controller: blockAll spares them by design.
    local okMap, mapReason = Open77.input.setActionBlocked("Map", true)
    if not okMap then print("eval_cuff: Map block refused: " .. tostring(mapReason)) end
    local okHub, hubReason = Open77.input.setActionBlocked("Hub", true)
    if not okHub then print("eval_cuff: Hub block refused: " .. tostring(hubReason)) end

    mode = wanted
end

RegisterNetEvent(CONTROL_EVENT, function(wanted)
    apply(wanted)
end)

-- A reload of this resource dropped its claims while the server may still hold
-- the player: ask the server to re-issue whatever is standing.
AddEventHandler("onClientResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    TriggerServerEvent(SYNC_EVENT)
end)
