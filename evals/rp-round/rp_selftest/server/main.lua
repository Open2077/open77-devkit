-- rp_selftest: server-only checks of the RP round's cross-resource contracts.
-- Runs once at start; every line is "[rp_selftest] PASS|FAIL <check> -- detail".

local passed, failed = 0, 0

local function check(name, ok, detail)
    if ok then
        passed = passed + 1
        print(("[rp_selftest] PASS %s -- %s"):format(name, tostring(detail or "")))
    else
        failed = failed + 1
        print(("[rp_selftest] FAIL %s -- %s"):format(name, tostring(detail or "")))
    end
end

local function call(resource, name, ...)
    local ok, a, b = pcall(function(...)
        return exports[resource][name](exports[resource], ...)
    end, ...)
    if not ok then return nil, "error: " .. tostring(a) end
    return a, b
end

local changed = {}
AddEventHandler("rp_economy:changed", function(playerId, balance, delta, reason)
    changed[#changed + 1] = { playerId = playerId, balance = balance, delta = delta, reason = reason }
end)

AddEventHandler("onResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(500)
        -- economy: argument validation must refuse without touching anything
        local v, r = call("rp_economy", "add", "x", 10, "test")
        check("economy.add refuses a non-numeric id", v == nil and type(r) == "string", r)
        v, r = call("rp_economy", "add", 999999, -5, "test")
        check("economy.add refuses a negative amount", v == nil and type(r) == "string", r)
        v, r = call("rp_economy", "getBalance", 999999)
        check("economy.getBalance answers a number for an unknown player", type(v) == "number", tostring(v) .. " " .. tostring(r))
        v, r = call("rp_economy", "remove", 999999, 1, "test")
        check("economy.remove refuses when the player is unknown or has no funds", v == nil and type(r) == "string", r)

        -- jobs
        v, r = call("rp_jobs", "getJob", 999999)
        check("jobs.getJob answers nil for an unknown player", v == nil, tostring(v) .. " " .. tostring(r))
        v, r = call("rp_jobs", "hasJob", 999999, "livreur")
        check("jobs.hasJob answers false for an unknown player", v == false, tostring(v) .. " " .. tostring(r))
        v, r = call("rp_jobs", "hasJob", "abc", "livreur")
        check("jobs.hasJob survives a bad id", v == false or v == nil, tostring(v) .. " " .. tostring(r))

        Wait(200)
        check("economy.changed was not raised by refused calls", #changed == 0, #changed .. " event(s)")
        print(("[rp_selftest] done: %d passed, %d failed"):format(passed, failed))
    end)
end)
