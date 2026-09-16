resource "eval_garage"
version "0.1.0"
auto_start true

-- world.vehicles gates Open77.vehicles.create / remove / getProperties /
-- setProperties / warpPlayerIntoVehicle (server), per open77_api.
-- RegisterCommand, Open77.chat.send, Open77.players.get,
-- Open77.vehicles.getPlayerSeat and Open77.vehicles.get check no permission.
permissions { "world.vehicles" }

server_script "server/main.lua"
