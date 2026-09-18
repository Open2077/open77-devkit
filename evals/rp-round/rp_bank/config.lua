-- rp_bank configuration, loaded on both runtimes (shared_script).
-- The client reads Config.Atms to place the pins, rings and prompts; the server reads the same
-- list to check that a player really stands next to an ATM before opening the menu.
Config = {}

-- ATM positions. Real Night City ATM coordinates are hard to know from the outside, so these
-- are laid out around the freeroam spawn area (381, -2401, 182): one at the spawn itself and four
-- between 20 and 60 m away, so the whole feature can be tested in two minutes without driving.
-- z is a best guess at 182 on every point: stand on the spot, run /pos, and paste the real
-- ground height here if a ring is invisible (a ring inside the floor renders nothing).
Config.Atms = {
    { id = "atm_spawn",  label = "ATM - Spawn plaza",   position = { x = 381.0, y = -2401.0, z = 182.0 } },
    { id = "atm_north",  label = "ATM - North walkway", position = { x = 381.0, y = -2376.0, z = 182.0 } },
    { id = "atm_east",   label = "ATM - East corner",   position = { x = 416.0, y = -2401.0, z = 182.0 } },
    { id = "atm_south",  label = "ATM - South lot",     position = { x = 381.0, y = -2446.0, z = 182.0 } },
    { id = "atm_west",   label = "ATM - West arcade",   position = { x = 326.0, y = -2416.0, z = 182.0 } },
}

-- /bank works within this many metres (horizontal) of an ATM.
Config.AtmRange = 3.0
-- The ATM prompt fires within the prompt's own 2.5 m; the server snapshot can lag a tick behind
-- a moving player, so the intent is accepted with a little more slack.
Config.AtmPromptRange = 5.0
-- Vertical tolerance for the distance check: the configured z is approximate.
Config.AtmHeightTolerance = 4.0

-- /virement fee: 1 % of the amount, at least 1 eddie. The fee leaves circulation.
Config.TransferFeePercent = 1
Config.TransferFeeMin = 1

-- Rows shown by the statement / "last transactions" screen.
Config.HistoryLimit = 10

-- Hard limits (server side).
Config.MaxAmount = 1000000000        -- one operation, 10^9
Config.MaxBalance = 1000000000000    -- an account or a society, 10^12

-- Client presentation.
Config.BlipSprite = "drop_point"     -- a map-capable service-point sprite (see the blips guide)
Config.LabelDistance = 40.0          -- metres the floating "ATM" label is readable from
Config.MarkerDistance = 120.0        -- metres the ground ring is visible from
Config.Color = "#22D8E2"
