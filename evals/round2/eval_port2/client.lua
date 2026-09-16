-- eval_port2 / client.lua
-- Port of the FiveM client.lua. Every FiveM line that could NOT be ported one-to-one,
-- and what the Open77 devkit MCP (answering for build 2.31.13+op77.75) said about it:
--
--   CreateThread(function() while true do Wait(0) if IsControlJustReleased(0, 166) ...
--     ABSENT. open77_fivem_equivalent for IsControlJustReleased returned an EMPTY match
--     list, and nothing in the docs polls a GTA control index. Two documented alternatives:
--       (a) poll Open77.input.isDown("F5") every frame and detect the falling edge yourself
--           (the card explicitly says "Prefer a press edge or a hold timer over firing every
--           frame", and the reads are PHYSICAL: they ignore whether a menu owns the key);
--       (b) RegisterKeyMapping -- "an engine primitive", rebindable from Pause -> Settings ->
--           KEY BINDINGS, suppressed while a page owns the keyboard, with an onReleased
--           callback in hold mode that fires on the key-up edge.
--     (b) is used: it is the documented port of a key check and matches "just released".
--     Behaviour differences: the mapping is rebindable by the player; it never fires while
--     chat / pause / a WebUI has the keyboard (the FiveM loop would); and the game still
--     sees F5 (the guide: "pressing a mapped key does not stop the game from also seeing it").
--     The CreateThread/Wait(0) loop is gone with it -- CreateThread and Wait DO exist (same
--     function values as Citizen.*) but there is nothing left to poll.
--     Needs the input.actions permission.
--     Return shape is documented two ways (card: "the effective key"; keybindings guide:
--     `true, "<effectiveKey>"`), so the return value is deliberately not relied upon.
--
--   RegisterNetEvent('port2:pong') + AddEventHandler('port2:pong', fn)
--     EQUIVALENT with a nuance: client RegisterNetEvent(event, handler?) "optionally attaches
--     a handler in the same call", and client AddEventHandler "never receives network traffic
--     unless the event was separately registered as a network event". The one-call form is
--     used since it is the one every card example shows.
--
--   print(('pong %s'):format(t))   -> EQUIVALENT: print writes to the Open77 log prefixed
--                                     with the resource name (not to chat).
--   TriggerServerEvent('port2:ping') -> EQUIVALENT (no payload, so the documented
--                                     `payload?: table` single-argument signature is moot).

-- FiveM: RegisterNetEvent('port2:pong') + AddEventHandler('port2:pong', function(t) ... end)
RegisterNetEvent('port2:pong', function(t)
    print(('pong %s'):format(t))
end)

-- FiveM: CreateThread + Wait(0) + IsControlJustReleased(0, 166) -- F5
-- Table form from the RegisterKeyMapping card / keybindings guide: hold = true makes
-- onReleased fire on the key-up edge, which is the "just released" the original polled for.
RegisterKeyMapping({
    id = "port2_ping",
    name = "Ping the server (eval_port2)",
    key = "F5",
    hold = true,
    onPressed = function() end,
    onReleased = function()
        TriggerServerEvent('port2:ping')
    end,
})
