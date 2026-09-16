-- eval_arena: client presentation only. The server decides everything; this file turns
-- its round messages into Cyberpunk's own side toast so a player mid-fight sees them
-- without looking at chat. Nothing here is trusted by the server.

RegisterNetEvent("eval_arena:toast", function(text)
    if type(text) ~= "string" or text == "" then return end
    local ok, reason = Open77.hud.notify(text, { replace = true })
    if not ok then print("eval_arena: toast refused: " .. tostring(reason)) end
end)
