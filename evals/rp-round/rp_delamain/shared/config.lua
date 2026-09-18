-- rp_delamain / shared config. Loaded on both runtimes; the owner tunes everything here.
RpDelamainConfig = {
    Job              = "delamain",   -- rp_jobs job name of the drivers (alias "taxi" accepted by rp_jobs)
    Society          = "delamain",   -- rp_bank society that receives the commission

    BaseFare         = 50,           -- eddies, charged on every completed ride
    PerHundredMetres = 15,           -- eddies per 100 m driven with the client on board
    DriverShare      = 0.80,         -- the driver's cut of the fare; the rest goes to the society

    AutoEndMetres    = 100,          -- the ride ends by itself when the client gets out after this many metres
    SampleMs         = 2000,         -- the meter samples server positions this often

    WaitTimeoutSec   = 180,          -- a call nobody accepted is dropped after this
    PickupTimeoutSec = 900,          -- an accepted call whose client never boarded is dropped after this
    RatingWindowSec  = 900,          -- how long after the ride the client may /note it

    -- The temporary map pin every on-duty driver gets when a client calls. `vehicle` renders on
    -- the HUD, the minimap and the world map; `Zzz19_DelamainTaxiVariant` is the vanilla
    -- Delamain icon but its map profile is not guaranteed (see the blips guide).
    BlipSprite       = "vehicle",
    BlipTtlSec       = 180,          -- a stale call pin removes itself after this
    WaypointRefreshM = 8,            -- the driver's GPS follows the waiting client when they move this far

    ChatAuthor       = "Delamain",
    ChatColor        = { 255, 200, 0 },   -- positional r, g, b (a keyed table is ignored by the chat UI)
}
