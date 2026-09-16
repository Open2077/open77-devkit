resource "eval_whereami"
version "1.0.0"
auto_start true

-- world.vehicles : server Open77.players.getVehicleSeat
-- input.actions  : client RegisterKeyMapping
-- players.read   : client Open77.players.isInVehicle
-- vehicles.read  : client Open77.vehicles.getPlayerSeat / Open77.vehicles.get
permissions { "world.vehicles", "input.actions", "players.read", "vehicles.read" }

server_script "server/main.lua"
client_script "client/main.lua"
