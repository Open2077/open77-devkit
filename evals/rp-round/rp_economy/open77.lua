-- rp_economy: server-authoritative wallet for an RP server.
-- Server only: no client script, every decision and every message comes from the server.
resource "rp_economy"
version "1.0.0"
open77_version "*"
auto_start true

-- network.events: required by RegisterNetEvent (the chat:ready suggestion hook)
-- and by Open77.notifications.send (the toast that accompanies /money).
permissions { "network.events" }

server_script "server/main.lua"
