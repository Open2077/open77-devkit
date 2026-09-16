resource "eval_announce"
version "1.0.0"
open77_version "*"
auto_start true

-- Open77.notifications.send / broadcast and RegisterNetEvent all require network.events
-- (per their native cards). Open77.chat.* and RegisterCommand check no permission.
permissions { "network.events" }

-- The server notification natives route to the official open77_notifications client
-- package; the notifications guide declares it as a dependency.
dependency "open77_notifications"

server_script "server/main.lua"
