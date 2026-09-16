-- eval_shop: a WebUI shop opened with F6. Prices live on the server only.
resource "eval_shop"
version "1.0.0"
auto_start true

-- network.events : TriggerServerEvent / RegisterNetEvent / TriggerClientEvent
-- input.actions  : RegisterKeyMapping (F6)
permissions { "network.events", "input.actions" }

-- Open77.notifications.send routes to this official client package.
dependency "open77_notifications"

client_script "client/main.lua"
server_script "server/main.lua"
web_files { "web/**" }
