-- eval_announce / server/main.lua
--
-- Server-only resource.
--   /announce <text...>  admin-only (RegisterCommand restricted = true, so the caller must hold
--                        the ACL right `command.announce`; the dedicated console is always allowed).
--                        Shows the text to every player as a toast and as a chat line.
--   /motd                any player: the current message of the day as a private toast.
--
-- Anything that reaches clients (notifications, chat suggestions) is refused with
-- `resource_preparing` while the chunk is loading, so nothing below runs at top level:
-- everything is inside onResourceStart, a command, or an event handler.

local RESOURCE_NAME = "eval_announce"

local MAX_MESSAGE_BYTES = 384      -- notifications definition reference: message max 384 UTF-8 bytes
local MAX_TITLE_BYTES = 96         -- title max 96 UTF-8 bytes
local MOTD_DURATION_MS = 8000      -- timed values are 750-120000
local ANNOUNCE_DURATION_MS = 10000
local MOTD_DELAY_MS = 3000         -- onPlayerReady is a barrier lifting, not "world is up"

local motd = nil

-- Every reason the natives document, mapped to a readable sentence. Unknown reasons still
-- produce a message: nothing here may crash on an unexpected string or on nil.
local REASON_TEXT = {
    -- Open77.notifications.send / Open77.notifications.broadcast
    ["network_unavailable"] = "the network transport is unavailable",
    ["permission_denied:network.events"] = "the manifest does not declare network.events",
    ["duplicate_notification_id"] = "a notification with that id is already live for this resource",
    ["resource_preparing"] = "the resource chunk is still loading, clients cannot be reached yet",
    -- Open77.chat.send / broadcast / addSuggestion / addSuggestions
    ["invalid_chat_message"] = "the chat message is malformed",
    ["invalid_chat_target"] = "the chat target is not a connected player id or -1",
    ["invalid_chat_command"] = "the suggested command text is invalid",
    ["invalid_chat_suggestion"] = "the suggestion descriptor is malformed",
}

local function describe(reason)
    if reason == nil then
        return "no reason given"
    end
    return REASON_TEXT[reason] or ("unexpected reason '" .. tostring(reason) .. "'")
end

local function log(fmt, ...)
    print(("[%s] " .. fmt):format(RESOURCE_NAME, ...))
end

local function truncateBytes(text, maxBytes)
    text = tostring(text or "")
    if #text <= maxBytes then
        return text
    end
    return text:sub(1, maxBytes - 3) .. "..."
end

-- source is the player id, or 0 for the dedicated console.
local function isConsole(source)
    return source == nil or tonumber(source) == 0
end

-- Answer the caller: chat for a player, the log for the console. Never assumes the chat
-- facade succeeded.
local function reply(source, text)
    if isConsole(source) then
        log("%s", text)
        return
    end
    local ok, reason = Open77.chat.send(source, { type = "system", author = RESOURCE_NAME, text = text })
    if not ok then
        log("reply to player %s failed: %s", tostring(source), describe(reason))
    end
end

-- Chat autocomplete entries for both commands.
local SUGGESTIONS = {
    {
        command = "/announce",
        help = "Admin: show a message to every player (toast + chat)",
        parameters = { { name = "text", help = "The announcement text" } },
    },
    {
        command = "/motd",
        help = "Show the message of the day",
    },
}

local function publishSuggestions(target)
    local ok, reason = Open77.chat.addSuggestions(target, SUGGESTIONS)
    if not ok then
        log("could not publish chat suggestions to %s: %s", tostring(target), describe(reason))
        return false
    end
    return true
end

-- Private toast with the current message of the day. Returns true on success, or
-- false plus a sentence explaining why.
local function sendMotd(playerId)
    if motd == nil then
        return false, "no message of the day is set"
    end
    local id, reason = Open77.notifications.send(playerId, {
        type = "info",
        title = "Message of the day",
        message = motd,
        icon = "MOTD",
        position = "top_center",
        durationMs = MOTD_DURATION_MS,
    })
    if id == nil then
        return false, "motd toast failed: " .. describe(reason)
    end
    return true
end

-- Resource start: set the message of the day, and advertise the commands to everyone
-- already connected (their chat:ready fired before this resource existed).
AddEventHandler("onResourceStart", function(name)
    if name ~= GetCurrentResourceName() then
        return
    end
    motd = truncateBytes("Welcome to the server. Be nice, have fun, and type /motd to read this again.", MAX_MESSAGE_BYTES)
    log("message of the day set: %s", motd)
    publishSuggestions(-1)
end)

-- A player's chat UI came up: publish this resource's suggestions to that player.
-- `source` is the authenticated connection (RegisterNetEvent). A RegisterNetEvent handler also
-- receives host-wide bus events, where source is not set, so validate it before use.
RegisterNetEvent("chat:ready", function(...)
    local target = source
    if isConsole(target) then
        local first = ...
        if first ~= nil then
            target = first
        else
            log("chat:ready without a usable source; suggestions not published")
            return
        end
    end
    publishSuggestions(target)
end)

-- The join-time readiness gate lifted for a player: show them the message of the day.
-- playerId arrives as a string, which Open77.notifications.send accepts.
AddEventHandler("onPlayerReady", function(playerId, detail)
    if playerId == nil then
        log("onPlayerReady without a player id (detail=%s); motd skipped", tostring(detail))
        return
    end
    CreateThread(function()
        Wait(MOTD_DELAY_MS)
        local ok, why = sendMotd(playerId)
        if not ok then
            log("motd for player %s not shown: %s", tostring(playerId), tostring(why))
        end
    end)
end)

-- /announce <text...>  -- restricted: ACL right command.announce (console always allowed).
RegisterCommand("announce", function(source, args, raw)
    local words = {}
    for _, value in ipairs(args or {}) do
        words[#words + 1] = tostring(value)
    end
    local text = table.concat(words, " ")
    text = text:match("^%s*(.-)%s*$") or ""
    if text == "" then
        reply(source, "Usage: /announce <text>")
        return
    end

    local body = truncateBytes(text, MAX_MESSAGE_BYTES)
    local who = "SERVER"
    if not isConsole(source) then
        who = Open77.players.name(source) or ("player " .. tostring(source))
    end

    local problems = {}

    -- 1. toast to everyone
    local id, reason = Open77.notifications.broadcast({
        type = "warning",
        title = truncateBytes("Announcement from " .. who, MAX_TITLE_BYTES),
        message = body,
        icon = "!",
        position = "top_center",
        durationMs = ANNOUNCE_DURATION_MS,
    })
    if id == nil then
        problems[#problems + 1] = "toast: " .. describe(reason)
    end

    -- 2. chat line to everyone (system message, positional RGB colour)
    local ok, chatReason = Open77.chat.broadcast({
        type = "system",
        author = "ANNOUNCE",
        text = ("[%s] %s"):format(who, body),
        color = { 255, 196, 0 },
    })
    if not ok then
        problems[#problems + 1] = "chat: " .. describe(chatReason)
    end

    if #problems == 0 then
        log("announcement by %s: %s", who, body)
        reply(source, "Announcement sent.")
    else
        local summary = table.concat(problems, "; ")
        log("announcement by %s partially failed (%s): %s", who, summary, body)
        reply(source, "Announcement problems: " .. summary)
    end
end, true)

-- /motd  -- any player; the console gets the text in its log.
RegisterCommand("motd", function(source, args, raw)
    if isConsole(source) then
        log("message of the day: %s", motd or "(none set)")
        return
    end
    local ok, why = sendMotd(source)
    if not ok then
        reply(source, "Could not show the message of the day: " .. tostring(why))
    end
end, false)
