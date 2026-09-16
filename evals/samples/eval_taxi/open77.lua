resource "eval_taxi"
version "1.0.0"
auto_start true

-- network.events    client: TriggerServerEvent   server: RegisterNetEvent
-- map.read          client: Open77.map.getWaypoint
-- world.vehicles    server: Open77.vehicles.create / remove / taskPlayerEnter /
--                           forcePlayerOutOfVehicle / ai.attachDriver / ai.driveTo / ai.removeDriver
-- players.life.read server: Open77.players.isDead (guard before seating a player)
permissions { "network.events", "map.read", "world.vehicles", "players.life.read" }

client_script "client/main.lua"
server_script "server/main.lua"
