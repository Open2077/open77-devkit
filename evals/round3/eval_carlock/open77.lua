resource "eval_carlock"
version "0.1.0"
auto_start true

-- Every native this resource calls that is gated by a permission
-- (getPlayerSeat, get, setLocked, occupantInSeat) requires world.vehicles.
-- seatName, isLocked, players.name, chat.send, RegisterCommand and
-- AddEventHandler check no permission.
permissions { "world.vehicles" }

server_script "server/main.lua"
