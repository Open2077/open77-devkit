resource "rp_jobs"
version "1.0.0"
auto_start true

-- network.events : RegisterNetEvent (chat:ready) and Open77.net.emitClient (waypoint relay)
-- world.vehicles : Open77.vehicles.create / remove (delivery van)
-- ui.vanilla.map : Open77.blips.setWaypoint / clearWaypoint (client side)
permissions { "network.events", "world.vehicles", "ui.vanilla.map" }

-- Delivery payouts go through exports.rp_economy:add(...)
dependency "rp_economy"

server_script "server/main.lua"
client_script "client/main.lua"
