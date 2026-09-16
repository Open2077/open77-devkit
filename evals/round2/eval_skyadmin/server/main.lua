-- eval_skyadmin: admin tool for the world clock and weather (server side).
--
--   /settime <hour>                 sets the authoritative time of day (0-23)   [ACL: command.settime]
--   /setweather <preset> [seconds]  applies a weather preset over a transition  [ACL: command.setweather]
--   /sky                            reports the current time and weather        [anyone]
--
-- Time and weather go through the host-installed Open77.environment.* facade
-- (manifest permission world.environment). The authority is the bundled
-- open77_weather resource; when it is not running every setter answers
-- nil, "environment_unavailable" and we tell the caller instead of erroring.

local SOURCE_CONSOLE = 0

-- The preset names Open77.environment.setWeather documents. The REDengine
-- 24h_weather_* values are also accepted server-side, so they pass through.
local WEATHER_PRESETS = {
    "sunny", "lightclouds", "cloudy", "rain", "heavyclouds", "fog", "pollution", "sandstorm",
}
local WEATHER_PRESET_SET = {}
for _, preset in ipairs(WEATHER_PRESETS) do
    WEATHER_PRESET_SET[preset] = true
end
local WEATHER_PRESET_LIST = table.concat(WEATHER_PRESETS, ", ")

local MIN_TRANSITION_SECONDS = 0
local MAX_TRANSITION_SECONDS = 300

-- Human-readable text for every reason the environment natives document.
local REASON_TEXT = {
    ["environment_unavailable"] = "The world clock authority (open77_weather) is not running on this server.",
    ["permission_denied:world.environment"] = "eval_skyadmin lacks the world.environment permission; check its manifest.",
    ["invalid_time"] = "The server rejected that time of day.",
    ["unknown_weather"] = "Unknown weather preset. Valid presets: " .. WEATHER_PRESET_LIST .. ".",
    ["invalid_transition"] = "The transition must be a number of seconds between 0 and 300.",
    ["transition_must_be_between_0_and_300"] = "The transition must be between 0 and 300 seconds.",
    ["invalid_bucket"] = "The routing bucket is invalid.",
    ["unknown_bucket"] = "That routing bucket holds no environment override.",
    ["too_many_environment_overrides"] = "Too many routing-bucket environment overrides exist (64 at most).",
    ["invalid_argument"] = "The server rejected an argument.",
}

local function describeReason(reason)
    return REASON_TEXT[reason] or ("The world clock authority refused: " .. tostring(reason))
end

-- Answer the caller: the console gets a print, a player gets a private chat line.
local function reply(source, text)
    if source == SOURCE_CONSOLE then
        print("[eval_skyadmin] " .. text)
        return
    end
    local ok, reason = Open77.chat.send(source, { type = "system", author = "SKY", text = text })
    if not ok then
        print(("[eval_skyadmin] chat.send to %s failed: %s"):format(tostring(source), tostring(reason)))
    end
end

local function callerName(source)
    if source == SOURCE_CONSOLE then
        return "the server console"
    end
    return Open77.players.name(source) or ("player " .. tostring(source))
end

-- Tell everyone: one chat line plus one toast.
local function announce(text)
    local ok, reason = Open77.chat.broadcast({ type = "system", author = "SKY", text = text })
    if not ok then
        print("[eval_skyadmin] chat.broadcast failed: " .. tostring(reason))
    end
    local id, notifyReason = Open77.notifications.broadcast({
        type = "info",
        title = "Sky",
        message = text,
        durationMs = 6000,
    })
    if not id then
        print("[eval_skyadmin] notifications.broadcast failed: " .. tostring(notifyReason))
    end
end

-- RegisterCommand(..., true) already refuses a caller without command.<name>.
-- The recheck at execution time gives our own refusal message and keeps the
-- decision in the operator's ACL if the command is ever reached another way.
-- The dedicated console (source 0) is always authorised; isAllowed answers
-- false, "invalid_player_id" for it, so it is skipped explicitly.
local function ensureAllowed(source, commandName)
    if source == SOURCE_CONSOLE then
        return true
    end
    local right = "command." .. commandName
    local allowed, reason = Open77.acl.isAllowed(source, right)
    if allowed then
        return true
    end
    if reason then
        print(("[eval_skyadmin] acl.isAllowed(%s, %s) answered %s"):format(tostring(source), right, tostring(reason)))
    end
    reply(source, ("You are not allowed to use /%s (ACL right %s is required)."):format(commandName, right))
    return false
end

local function formatClock(state)
    return ("%02d:%02d"):format(state.hour or 0, state.minute or 0)
end

local function formatWeather(state)
    local weather = tostring(state.weather or "?")
    if state.weatherPreset and state.weatherPreset ~= state.weather then
        weather = weather .. " (" .. tostring(state.weatherPreset) .. ")"
    end
    return weather
end

-- /settime <hour>
RegisterCommand("settime", function(source, args)
    if not ensureAllowed(source, "settime") then return end

    local raw = args[1]
    local hour = tonumber(raw)
    if hour == nil or hour ~= math.floor(hour) or hour < 0 or hour > 23 then
        return reply(source, "Usage: /settime <hour>  (a whole number from 0 to 23)")
    end
    hour = math.floor(hour)

    local state, reason = Open77.environment.setTime(hour, 0, 0)
    if not state then
        return reply(source, "Could not set the time: " .. describeReason(reason))
    end

    announce(("%s set the world time to %s."):format(callerName(source), formatClock(state)))
    if state.frozen or state.timeFrozen then
        reply(source, "Note: the clock is frozen, so it will stay at " .. formatClock(state) .. ".")
    end
end, true)

-- /setweather <preset> [transitionSeconds]
RegisterCommand("setweather", function(source, args)
    if not ensureAllowed(source, "setweather") then return end

    local preset = args[1]
    if type(preset) ~= "string" or preset == "" then
        return reply(source, "Usage: /setweather <preset> [transitionSeconds]. Presets: " .. WEATHER_PRESET_LIST .. ".")
    end
    preset = preset:lower()
    if not WEATHER_PRESET_SET[preset] and preset:sub(1, 12) ~= "24h_weather_" then
        return reply(source, ("Unknown preset '%s'. Valid presets: %s."):format(preset, WEATHER_PRESET_LIST))
    end

    local transition = nil
    if args[2] ~= nil then
        transition = tonumber(args[2])
        if transition == nil or transition < MIN_TRANSITION_SECONDS or transition > MAX_TRANSITION_SECONDS then
            return reply(source, ("The transition must be a number of seconds from %d to %d."):format(
                MIN_TRANSITION_SECONDS, MAX_TRANSITION_SECONDS))
        end
    end

    local state, reason = Open77.environment.setWeather(preset, transition)
    if not state then
        return reply(source, "Could not set the weather: " .. describeReason(reason))
    end

    local over = ""
    if state.transitionSeconds and state.transitionSeconds > 0 then
        over = (" over %d s"):format(state.transitionSeconds)
    end
    announce(("%s set the weather to %s%s."):format(callerName(source), formatWeather(state), over))
    if state.randomWeather and not state.weatherFrozen then
        reply(source, "Note: random weather is still enabled; the scheduler may change the sky later.")
    end
end, true)

-- /sky
RegisterCommand("sky", function(source)
    local state, reason = Open77.environment.getState()
    if not state then
        return reply(source, "Cannot read the sky: " .. describeReason(reason))
    end

    local clock = formatClock(state)
    if state.frozen or state.timeFrozen then
        clock = clock .. " (frozen)"
    else
        clock = clock .. (" (x%s)"):format(tostring(state.rate or "?"))
    end

    local weather = formatWeather(state)
    if state.weatherTransitionRemainingMs and state.weatherTransitionRemainingMs > 0 then
        weather = weather .. (", transition ends in %d s"):format(math.ceil(state.weatherTransitionRemainingMs / 1000))
    end
    if state.weatherFrozen then
        weather = weather .. ", pinned"
    elseif state.randomWeather then
        weather = weather .. ", random"
    end

    reply(source, ("Time %s - weather %s - scope %s."):format(clock, weather, tostring(state.scope or "default")))
end, false)

-- Chat autocomplete for the three commands: everyone already connected now,
-- and each player as they become ready afterwards.
local SUGGESTIONS = {
    { command = "/settime", help = "Set the world time (admin)", parameters = { { name = "hour", help = "0 to 23" } } },
    { command = "/setweather", help = "Set the weather (admin)", parameters = {
        { name = "preset", help = WEATHER_PRESET_LIST },
        { name = "transitionSeconds", help = "optional, 0 to 300" },
    } },
    { command = "/sky", help = "Show the current time and weather" },
}

local function publishSuggestions(target)
    local ok, reason = Open77.chat.addSuggestions(target, SUGGESTIONS)
    if not ok then
        print(("[eval_skyadmin] chat.addSuggestions(%s) failed: %s"):format(tostring(target), tostring(reason)))
    end
end

publishSuggestions(-1)

AddEventHandler("onPlayerReady", function(playerId)
    publishSuggestions(playerId)
end)
