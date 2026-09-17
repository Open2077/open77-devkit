resource "rp_shop"
version "1.0.0"
auto_start true

-- Money goes through rp_economy's server exports; weapons through the
-- official open77_weapons client relay (Open77.weapons.assign).
dependency "rp_economy"
dependency "open77_weapons >=0.1.0"

permissions {
    "network.events",      -- Open77.weapons.assign, RegisterNetEvent (chat:ready)
    "world.vehicles",      -- Open77.vehicles.create / get / remove
    "players.stats.apply", -- Open77.players.restoreHealth / setArmor, Open77.stats.restore
    "players.life.read",   -- Open77.players.isDead
}

server_script "server/main.lua"
