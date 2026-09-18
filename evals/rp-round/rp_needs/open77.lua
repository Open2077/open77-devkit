resource "rp_needs"
version "1.0.0"
auto_start true

-- Toasts render through the official package; a server-only resource still
-- declares it so a server whose load list lacks it refuses to start us
-- instead of dropping every warning without a word.
dependency "open77_notifications"

permissions {
    "network.events",       -- Open77.notifications.send, RegisterNetEvent (chat:ready)
    "database.access",      -- Open77.database / MySQL (rp_needs_state)
    "players.stats.read",   -- Open77.stats.get
    "players.stats.apply",  -- Open77.stats.setStaminaMax, Open77.stats.setHealth
    "players.life.read",    -- Open77.players.isDead
    "players.screenfx",     -- Open77.effects.screen / clearScreen (fatigue overlay)
}

server_script "server/main.lua"

-- Phase 1 contract: get(playerId) and consume(playerId, itemId).
server_exports { "get", "consume" }
