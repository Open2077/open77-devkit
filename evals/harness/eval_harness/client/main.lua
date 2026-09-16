-- eval_harness / client
-- /wpahead [metres]  place the map waypoint N metres ahead of the local character
-- /wpclear           clear it
RegisterCommand("wpahead", function(_, args)
    local metres = tonumber(args and args[1]) or 200
    local st = Open77.character.state()
    if not st or not st.position or not st.forward then
        print("eval_harness: no character state")
        return
    end
    local target = {
        x = st.position.x + st.forward.x * metres,
        y = st.position.y + st.forward.y * metres,
        z = st.position.z,
    }
    local ok, reason = Open77.blips.setWaypoint(target)
    print(("eval_harness: waypoint %s at %.1f,%.1f,%.1f (%s)"):format(
        ok and "set" or "refused", target.x, target.y, target.z, tostring(reason)))
end, false, { help = "harness: waypoint N m ahead", parameters = {} })

RegisterCommand("wpclear", function()
    local ok, reason = Open77.blips.clearWaypoint()
    print(("eval_harness: waypoint clear %s (%s)"):format(ok and "ok" or "refused", tostring(reason)))
end, false, { help = "harness: clear the waypoint", parameters = {} })

-- F7: report whether the vanilla world map is open. Open77.map.close only
-- closes a map the resource itself opened (not_owner otherwise), so the
-- harness toggles the map with M and uses this line to know the state.
RegisterKeyMapping("eval_harness_mapstate", "harness: report the world map state", "F7", function()
    local open, reason = Open77.map.isOpen()
    print(("eval_harness: map open=%s (%s)"):format(tostring(open), tostring(reason)))
end)

-- /wppick: open the world map in pick mode (Open77.map.pickPoint). The vanilla
-- right-click gesture on the map then tracks a genuine custom-position waypoint, the same
-- pin a player places by hand, and the adapter closes the map by itself. That
-- is the only route the harness has to a waypoint the taxi eval will accept.
RegisterCommand("wppick", function()
    local ticket, reason = Open77.map.pickPoint({ timeoutMilliseconds = 30000 })
    print(("eval_harness: pick %s (%s)"):format(ticket and "armed" or "refused", tostring(ticket or reason)))
end, false, { help = "harness: open the map to pick a waypoint", parameters = {} })

AddEventHandler("open77:map:pointPicked", function(payload)
    local p = payload and payload.position or {}
    print(("eval_harness: point picked at %s,%s,%s"):format(tostring(p.x), tostring(p.y), tostring(p.z)))
end)
