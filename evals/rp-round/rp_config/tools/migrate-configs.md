# Migrating the rp_* resources to rp_config

This sheet is the owner's checklist for a later pass. **No delivered resource was edited**:
each keeps its own `shared/config.lua` (or `config.lua` / `shared/items.lua`) as the default,
and only gains a read of the central override at start. `rp_config` is server-only and
answers from memory, so the read is synchronous, cheap, and safe at `onResourceStart`.

## The pattern (identical for every resource)

Add once, near the top of `server/main.lua` (after the config global exists):

```lua
-- rp_config override, when the store runs; the file value otherwise.
local function cfg(key, fallback)
    local ok, v = pcall(exports.rp_config.get, exports.rp_config, key, fallback)
    if ok and v ~= nil then return v end
    return fallback
end
```

Then one line per field, **before the field is first used** (for most resources that is the
top of the `onResourceStart` handler, before timers, POIs or NPCs are created from it):

```lua
Config.TransferFeePercent = cfg("rp_bank.transferFeePercent", Config.TransferFeePercent)
```

A branch key answers a whole table, so a position can be read in one line:

```lua
Config.hospital.respawn = cfg("rp_trauma.hospital.respawn", Config.hospital.respawn)
```

Optional, for live changes without a restart:

```lua
AddEventHandler("rp_config:changed", function(key, value)
    if key:sub(1, 10) ~= "rp_trauma." then return end
    -- re-run the assignment(s) above, then re-arm whatever timer or POI used the old value
end)
```

Do **not** declare `dependency "rp_config"` in a resource that ships a `client_script`: a
client manifest may not depend on a server-only resource (`missing_dependency`). Every
resource below except `rp_economy`, `rp_needs`, `rp_logs`, `rp_whitelist` and `rp_chat` has a
client script, so the `pcall` is the whole contract.

## Runtime of each key

- **server** -- consumed by the server only: prices, fees, salaries, rents, shares, timers,
  cooldowns, caps, server-side distance checks, switches. Safe to override now.
- **both** -- also read by the client from the `shared_script` copy of the config (ring and
  prompt positions, prompt distances, ring radii, blip settings). A server-side override moves
  the server's check but not the ring the client draws, until the resource forwards the value
  (`TriggerClientEvent` at `onPlayerReady` and on `rp_config:changed`). Until then, move a POI
  in the file.

The appendix at the end lists every key with its default; the sections below give the mapping
rule from key to field and the exceptions.

## Per resource

### rp_economy -- no config file (values in `server/main.lua`)
`rp_economy.startingBalance` -> the new-wallet constant (500); `rp_economy.payday.amount` (200)
and `rp_economy.payday.intervalMinutes` (10) -> the payday timer. Server. The interval needs
the timer re-armed on change.

### rp_bank -- `config.lua`, global `Config`
`rp_bank.<lowerCamel>` -> `Config.<UpperCamel>`: `transferFeePercent` -> `Config.TransferFeePercent`,
`transferFeeMin` -> `Config.TransferFeeMin`, `historyLimit` -> `Config.HistoryLimit`,
`atmRange` -> `Config.AtmRange`, `atmPromptRange` -> `Config.AtmPromptRange`,
`atmHeightTolerance` -> `Config.AtmHeightTolerance`, `maxAmount` -> `Config.MaxAmount` (server).
`rp_bank.atms.<id>.position.{x,y,z}` -> `Config.Atms[i].position` where `Config.Atms[i].id == <id>`
(both: the client draws the ATM rings from the same table).

### rp_needs -- no config file (constants in `server/main.lua`)
`rp_needs.decayPerMinute.{hunger,thirst,fatigue}` -> the three decay constants (0.8 / 1.2 /
0.4), `fatigueRecoveryPerMinute` (2), `tickSeconds` (10), `saveSeconds` (60). Server.

### rp_inventory -- `shared/items.lua`, global `RpInventoryConfig`
`rp_inventory.<field>` -> `RpInventoryConfig.<field>` (same names). `interactDistance` is both
(the client checks it for give / pick up prompts); the rest server.

### rp_jobs -- `shared/config.lua`, global `RpJobsConfig`
`rp_jobs.salary.<job>.<grade>` -> `RpJobsConfig.Jobs[i].salary[grade]` for the entry whose
`name == <job>` (server; `rp_jobs.hud.jobLabels` is not centralised). `payrollIntervalMs` ->
`RpJobsConfig.PayrollIntervalMs` (server, re-arm the payroll timer on change),
`societyStartingFund` -> `.SocietyStartingFund`, `hireDistance` -> `.HireDistance`,
`nameplateMaxDistance` -> `.NameplateMaxDistance` (both). `rp_jobs.agency.position.{x,y,z}`,
`.radius`, `.promptDistance` -> `RpJobsConfig.Agency.*` (both); `.reach` server.

### rp_zones -- `shared/config.lua`, global `Config`
`rp_zones.tickMs` -> `Config.tickMs`, `rp_zones.hysteresis` -> `Config.hysteresis` (server).
`rp_zones.<name>.centre.{x,y,z}` and `rp_zones.<name>.radius` -> `Config.zones[i].centre` /
`.radius` for the entry whose `name == <name>` (both: the client draws the rings and pins; the
server's zone definitions are created from the same table at start, so the read must happen
before `Open77.zones.*` definitions are registered).

### rp_ncpd -- `shared/config.lua`, global `Config`
Same path: `rp_ncpd.cell.{x,y,z,heading,radius}` -> `Config.cell` (server: the teleport),
`rp_ncpd.entrance.*` -> `Config.entrance` (server), `actionDistance` (server),
`menuDistance` (both: the ALT+click range is checked on the client), `vehicle.range` /
`.lockExit` / `.preferRear` -> `Config.vehicle.*`, `prison.*`, `fine.*`, `warrant.nativeHeat`,
`alert.blipMs` (both: the blip TTL is applied client-side), `grantKitRights` (server).

### rp_trauma -- `shared/config.lua`, global `Config`
`rp_trauma.<field>` -> `Config.<field>`, same names, all server except `actionRange` (both,
the ALT+click reach) and `hospital.respawn.{x,y,z}` / `hospital.heading` (server: the respawn
teleport). `av.*` -> `Config.av.*` (server).

### rp_delamain -- `shared/config.lua`, global `RpDelamainConfig`
`rp_delamain.<field>` -> `RpDelamainConfig.<UpperCamel>`: `baseFare` -> `.BaseFare`,
`perHundredMetres` -> `.PerHundredMetres`, `driverShare` -> `.DriverShare`, `autoEndMetres` ->
`.AutoEndMetres`, `sampleMs` -> `.SampleMs`, `waitTimeoutSec` -> `.WaitTimeoutSec`,
`pickupTimeoutSec` -> `.PickupTimeoutSec`, `ratingWindowSec` -> `.RatingWindowSec` (server);
`blipTtlSec` -> `.BlipTtlSec`, `waypointRefreshM` -> `.WaypointRefreshM` (both).

### rp_mecano -- `shared/config.lua`, global `Config`
Same path (`rp_mecano.repair.price` -> `Config.repair.price`, ...). Server, except
`repair.reach`, `tow.reach`, `paint.reach`, `impound.reach`, `fuel.reach`, `bill.reach` which
the client menus may pre-check (both). `impoundAnywhereForTesting` server.

### rp_ferrailleur -- `shared/config.lua`, global `RpFerrailleurConfig`
Same path. `points.<n>.{x,y,z}` -> `Config.points[n]` and `dealer.position.*` / `dealer.yaw` /
`ringRadius` / `promptDistance` are both (rings + the dealer NPC); `searchReach`,
`heightTolerance`, `searchMs`, `regenMs`, `crowbar.*`, `basePrices.*`, `priceVariation`,
`priceIntervalMs`, `societyShare`, `dealer.reach` server.

### rp_nomade -- `shared/config.lua`, global `RpNomadeConfig`
`rp_nomade.camp.*` -> `RpNomadeConfig.Camp.*` (both: board ring, truck spawn), `contract.*` ->
`.Contract.*` (server), `truck.*` -> `.Truck.*` (server), `crate.*` -> `.Crate.*` (both),
`ambush.*` -> `.Ambush.*` (server).

### rp_bar -- `shared/config.lua`, global `RpBarConfig`
`rp_bar.counter.*` -> `RpBarConfig.counter.*` (both), `drinks.<id>.price` / `.alcohol` ->
`RpBarConfig.drinks[id].price` / `.alcohol` (server), `ingredients.<id>.cost` ->
`RpBarConfig.ingredients[id].cost` (server), `craft.durationMs`, `sale.*`, `drunk.*`,
`ambience.*` -> same path (server; `ambience.radius` drives a server sweep).

### rp_ripperdoc -- `shared/config.lua`, global `RpRipperConfig`
`rp_ripperdoc.chair.*` -> `RpRipperConfig.chair.*` (both), scalars same path (server),
`rp_ripperdoc.grades.<key>.<gradeId>.price` / `.durationMs` -> `RpRipperConfig.catalogue[i].grades[j]`
for the entry whose `key == <key>` and grade `id == <gradeId>` (server).
`cyberpsychosisDurationSeconds` -> `RpRipperConfig.cyberpsychosis.durationSeconds`.

### rp_fixer -- `shared/config.lua`, global `Config`
Same path. `office.{x,y,z}`, `promptDistance` both (board ring); `templates.<id>.pay` /
`.timeLimitSec` -> `Config.templates[id].pay` / `.timeLimitSec`, `guards.*`, `reputation.*`,
the rest server.

### rp_netrunner -- `shared/config.lua`, global `Config`
Same path. `accessPoint.position.*`, `.radius`, `.promptDistance` both; `hacks.<kind>.*` ->
`Config.hacks[kind].*` (server: the hack definitions are declared from them at start, so read
before `Open77.hacking.define`), `ping.*`, `jam.*`, `breach.*`, `deck.price`, `cooldownMs`,
`traceChance` server.

### rp_vigile -- `shared/config.lua`, global `VigileConfig`
`rp_vigile.<field>` -> `VigileConfig.<field>` (server); `rp_vigile.templates.<zone>.minutes` ->
`VigileConfig.templates[i].minutes` for the entry whose `zone == <zone>` (server).

### rp_garage -- `shared/config.lua`, global `Config`
`rp_garage.garages.<id>.position.*` / `.spawnPoint.*` -> `Config.garages[i]` where `id == <id>`
(both for `position`, server for `spawnPoint`); `dealership.*` -> `Config.dealership.*` (both
for `position`); `rp_garage.vehicles.<slug>.price` -> `Config.vehicles[i].price` in file order
-- `archer_hella` = `Vehicle.v_standard2_archer_hella_player`, `arch_nazare` =
`Vehicle.v_sportbike2_arch_player`, `thorton_mackinaw` = `Vehicle.v_standard3_thorton_mackinaw_player`,
`villefort_cortes_delamain` = `Vehicle.v_standard2_villefort_cortes_delamain_player`,
`quadra_turbo_r` = `Vehicle.v_sport1_quadra_turbo_player` (server); `impound.fee`,
`impound.lotPosition.*`, `reach.*` (`reach.prompt` both), `spawn*`, `minHealthOnTakeOut`,
`snapshotIntervalMs`, `stolenCooldownS`, `menuTimeoutMs`, `confirmTimeoutMs` server.

### rp_shops -- `shared/config.lua`, global `RpShopsConfig`
Scalars same path (server; `reach` and `promptDistance` both). `rp_shops.shops.<id>.position.*`
/ `.yaw` -> `RpShopsConfig.shops[i]` where `id == <id>` (both: vendor NPC and ring);
`rp_shops.shops.<id>.prices.<catalogueId>` -> `RpShopsConfig.shops[i].catalogue[j].price` where
`catalogue[j].id == <catalogueId>` (server); `shops.pharmacy.restockTo` -> `.restockTo`.

### rp_housing -- `shared/config.lua`, global `Config`
Scalars same path (server; `promptDistance`, `agency.radius` both).
`rp_housing.agency.position.*` -> `Config.agency.position` (both); `rp_housing.homes.<id>.price`
/ `.entrance.*` / `.interior.*` -> `Config.homes[i]` where `id == <id>` (`price` server,
positions both -- the door and stash rings). Note `Config.homes[i].rent` defaults to
`Config.rent` in the file's derived-helpers loop: read `rp_housing.rent` before that loop runs,
or re-derive after.

### rp_hud -- `shared/config.lua`, global `RpHudConfig`
Same names. `minPushIntervalMs`, `refreshMs`, `joinRepushMs`, `dependencyRepushMs` server;
`needsWarnAt`, `panelWidthPx` are forwarded to the page by the client (both).

### rp_phone -- `shared/config.lua`, global `RpPhoneConfig`
Same path. `requireItem` server; `call.ringSeconds`, `sms.*`, `contacts.*`, `location.blipSeconds`,
`ads.*`, `pushThrottleMs`, `intentsPerSecond` server (the page receives state, not config).

### rp_radio -- `shared/config.lua`, global `Config`
**Already reads** `rp_radio.requireItem`, `rp_radio.badlandsCut`, `rp_radio.rememberFrequency`
(its README, "Configuration"): nothing to do for those three. The others map by name:
`rememberDelayMs`, `maxTextLength`, `band.{min,max,step}`, `jam.staticIntervalMs`,
`jam.garbleText`, `jam.garbleRatio` server; `jam.localGain` both (client gain).

### rp_gangs -- `shared/config.lua`, global `RpGangsConfig`
Same names (server), `rp_gangs.buyer.reach` server, `buyer.promptDistance` both,
`rp_gangs.territories.<zone>.buyer.{x,y,z,yaw}` -> `Config.territories[i].buyer` where
`name == <zone>` (both: the buyer NPC prompt).

### rp_ambiance -- `shared/config.lua`, global `Config`
**Already reads** the eight keys of its `Config.overrides` list (`rp_ambiance.realHoursPerDay`,
`.weatherMinMinutes`, `.weatherMaxMinutes`, `.badlands`, `.noticeIntervalMinutes`,
`.figurantsEnabled`, `.musicVolume`, `.alertsEnabled`), at start and on `/ambiance reload`:
nothing to do. The extra keys map to `Config.cycle.weatherTransitionSeconds`,
`Config.cycle.announceWeather`, `Config.figurants.*`, `Config.notices.enabled` /
`.durationMs`, `Config.alerts.*` -- adding a row to `Config.overrides` is the one-line change
for each (`{ key = "rp_ambiance.alerts.range", section = "alerts", field = "range" }`).

### rp_admin -- `shared/config.lua`, global `RpAdminConfig`
`rp_admin.<lowerCamel>` -> `RpAdminConfig.<UpperCamel>` (`maxMoney` -> `.MaxMoney`,
`teleportOffset` -> `.TeleportOffset`, `spectate.*` -> `.Spectate.*`, ...). Server.
`AdminRight` is deliberately not a tunable (an ACL string is not a setting an admin may move).

### rp_logs -- `shared/config.lua`, global `RpLogsConfig`
Same names, server. The webhook URL is **not** in the catalogue and must never be: it stays in
the server convars / the resource's own tunable.

### rp_whitelist -- `shared/config.lua`, global `Config`
Same names, server. `rp_whitelist.enabled` competes with the resource's own KVP-persisted
switch (`/wl activer`), which overrides the file: decide one owner -- either drop the KVP
switch and read `rp_config`, or keep `/wl` and leave `enabled` out of the migration.

### Not centralised
`rp_identity` (no tunable beyond text), `rp_chat`, `rp_medic` (absorbed by `rp_trauma`),
`rp_shop` v1 (unloaded), `eval_taxi`, `rp_selftest`, `rp_taxitest`; and `rp_mdt` / `rp_crime`,
written in parallel with this sheet -- add their sections to `shared/defaults.lua` once their
configs are frozen.

## Appendix: every key and its default at delivery (2026-09-18)

### rp_config (1 keys)

| Key | Default |
|---|---|
| `rp_config.chatListMax` | `30` |

### rp_economy (3 keys)

| Key | Default |
|---|---|
| `rp_economy.payday.amount` | `200` |
| `rp_economy.payday.intervalMinutes` | `10` |
| `rp_economy.startingBalance` | `500` |

### rp_bank (22 keys)

| Key | Default |
|---|---|
| `rp_bank.atmHeightTolerance` | `4.0` |
| `rp_bank.atmPromptRange` | `5.0` |
| `rp_bank.atmRange` | `3.0` |
| `rp_bank.atms.atm_east.position.x` | `416.0` |
| `rp_bank.atms.atm_east.position.y` | `-2401.0` |
| `rp_bank.atms.atm_east.position.z` | `182.0` |
| `rp_bank.atms.atm_north.position.x` | `381.0` |
| `rp_bank.atms.atm_north.position.y` | `-2376.0` |
| `rp_bank.atms.atm_north.position.z` | `182.0` |
| `rp_bank.atms.atm_south.position.x` | `381.0` |
| `rp_bank.atms.atm_south.position.y` | `-2446.0` |
| `rp_bank.atms.atm_south.position.z` | `182.0` |
| `rp_bank.atms.atm_spawn.position.x` | `381.0` |
| `rp_bank.atms.atm_spawn.position.y` | `-2401.0` |
| `rp_bank.atms.atm_spawn.position.z` | `182.0` |
| `rp_bank.atms.atm_west.position.x` | `326.0` |
| `rp_bank.atms.atm_west.position.y` | `-2416.0` |
| `rp_bank.atms.atm_west.position.z` | `182.0` |
| `rp_bank.historyLimit` | `10` |
| `rp_bank.maxAmount` | `1000000000` |
| `rp_bank.transferFeeMin` | `1` |
| `rp_bank.transferFeePercent` | `1` |

### rp_needs (6 keys)

| Key | Default |
|---|---|
| `rp_needs.decayPerMinute.fatigue` | `0.4` |
| `rp_needs.decayPerMinute.hunger` | `0.8` |
| `rp_needs.decayPerMinute.thirst` | `1.2` |
| `rp_needs.fatigueRecoveryPerMinute` | `2.0` |
| `rp_needs.saveSeconds` | `60` |
| `rp_needs.tickSeconds` | `10` |

### rp_inventory (5 keys)

| Key | Default |
|---|---|
| `rp_inventory.defaultStashCapacity` | `100.0` |
| `rp_inventory.dropTtlMs` | `1800000` |
| `rp_inventory.interactDistance` | `3.0` |
| `rp_inventory.maxCarryWeight` | `40.0` |
| `rp_inventory.useDurationMs` | `3000` |

### rp_jobs (54 keys)

| Key | Default |
|---|---|
| `rp_jobs.agency.position.x` | `396.0` |
| `rp_jobs.agency.position.y` | `-2388.0` |
| `rp_jobs.agency.position.z` | `181.99` |
| `rp_jobs.agency.promptDistance` | `3.0` |
| `rp_jobs.agency.radius` | `1.5` |
| `rp_jobs.agency.reach` | `12.0` |
| `rp_jobs.hireDistance` | `5.0` |
| `rp_jobs.nameplateMaxDistance` | `40` |
| `rp_jobs.payrollIntervalMs` | `600000` |
| `rp_jobs.salary.barman.0` | `150` |
| `rp_jobs.salary.barman.1` | `220` |
| `rp_jobs.salary.barman.2` | `300` |
| `rp_jobs.salary.barman.3` | `420` |
| `rp_jobs.salary.delamain.0` | `200` |
| `rp_jobs.salary.delamain.1` | `300` |
| `rp_jobs.salary.delamain.2` | `400` |
| `rp_jobs.salary.delamain.3` | `550` |
| `rp_jobs.salary.ferrailleur.0` | `150` |
| `rp_jobs.salary.ferrailleur.1` | `220` |
| `rp_jobs.salary.ferrailleur.2` | `300` |
| `rp_jobs.salary.ferrailleur.3` | `420` |
| `rp_jobs.salary.fixer.0` | `250` |
| `rp_jobs.salary.fixer.1` | `400` |
| `rp_jobs.salary.fixer.2` | `550` |
| `rp_jobs.salary.fixer.3` | `750` |
| `rp_jobs.salary.mecano.0` | `200` |
| `rp_jobs.salary.mecano.1` | `300` |
| `rp_jobs.salary.mecano.2` | `400` |
| `rp_jobs.salary.mecano.3` | `550` |
| `rp_jobs.salary.ncpd.0` | `300` |
| `rp_jobs.salary.ncpd.1` | `450` |
| `rp_jobs.salary.ncpd.2` | `600` |
| `rp_jobs.salary.ncpd.3` | `800` |
| `rp_jobs.salary.netrunner.0` | `250` |
| `rp_jobs.salary.netrunner.1` | `400` |
| `rp_jobs.salary.netrunner.2` | `550` |
| `rp_jobs.salary.netrunner.3` | `750` |
| `rp_jobs.salary.nomade.0` | `180` |
| `rp_jobs.salary.nomade.1` | `260` |
| `rp_jobs.salary.nomade.2` | `360` |
| `rp_jobs.salary.nomade.3` | `500` |
| `rp_jobs.salary.ripper.0` | `250` |
| `rp_jobs.salary.ripper.1` | `400` |
| `rp_jobs.salary.ripper.2` | `550` |
| `rp_jobs.salary.ripper.3` | `750` |
| `rp_jobs.salary.trauma.0` | `300` |
| `rp_jobs.salary.trauma.1` | `450` |
| `rp_jobs.salary.trauma.2` | `600` |
| `rp_jobs.salary.trauma.3` | `800` |
| `rp_jobs.salary.vigile.0` | `180` |
| `rp_jobs.salary.vigile.1` | `260` |
| `rp_jobs.salary.vigile.2` | `360` |
| `rp_jobs.salary.vigile.3` | `500` |
| `rp_jobs.societyStartingFund` | `50000` |

### rp_zones (38 keys)

| Key | Default |
|---|---|
| `rp_zones.afterlife.centre.x` | `360.0` |
| `rp_zones.afterlife.centre.y` | `-2390.0` |
| `rp_zones.afterlife.centre.z` | `182.0` |
| `rp_zones.afterlife.radius` | `10.0` |
| `rp_zones.badlands.centre.x` | `381.36` |
| `rp_zones.badlands.centre.y` | `-2401.79` |
| `rp_zones.badlands.centre.z` | `181.99` |
| `rp_zones.badlands.radius` | `900.0` |
| `rp_zones.blackmarket.centre.x` | `400.0` |
| `rp_zones.blackmarket.centre.y` | `-2390.0` |
| `rp_zones.blackmarket.centre.z` | `182.0` |
| `rp_zones.blackmarket.radius` | `10.0` |
| `rp_zones.hospital.centre.x` | `400.0` |
| `rp_zones.hospital.centre.y` | `-2366.0` |
| `rp_zones.hospital.centre.z` | `182.0` |
| `rp_zones.hospital.radius` | `12.0` |
| `rp_zones.hysteresis` | `1.0` |
| `rp_zones.mecano_shop.centre.x` | `341.0` |
| `rp_zones.mecano_shop.centre.y` | `-2401.0` |
| `rp_zones.mecano_shop.centre.z` | `180.3` |
| `rp_zones.mecano_shop.radius` | `10.0` |
| `rp_zones.ncpd_hq.centre.x` | `440.0` |
| `rp_zones.ncpd_hq.centre.y` | `-2366.0` |
| `rp_zones.ncpd_hq.centre.z` | `181.0` |
| `rp_zones.ncpd_hq.radius` | `12.0` |
| `rp_zones.nomad_camp.centre.x` | `420.0` |
| `rp_zones.nomad_camp.centre.y` | `-2378.0` |
| `rp_zones.nomad_camp.centre.z` | `182.0` |
| `rp_zones.nomad_camp.radius` | `9.0` |
| `rp_zones.scrapyard.centre.x` | `462.0` |
| `rp_zones.scrapyard.centre.y` | `-2352.0` |
| `rp_zones.scrapyard.centre.z` | `178.0` |
| `rp_zones.scrapyard.radius` | `12.0` |
| `rp_zones.spawn_plaza.centre.x` | `381.36` |
| `rp_zones.spawn_plaza.centre.y` | `-2401.79` |
| `rp_zones.spawn_plaza.centre.z` | `181.99` |
| `rp_zones.spawn_plaza.radius` | `45.0` |
| `rp_zones.tickMs` | `500` |

### rp_ncpd (26 keys)

| Key | Default |
|---|---|
| `rp_ncpd.actionDistance` | `3.0` |
| `rp_ncpd.alert.blipMs` | `60000` |
| `rp_ncpd.cell.heading` | `180.0` |
| `rp_ncpd.cell.radius` | `6.0` |
| `rp_ncpd.cell.x` | `436.0` |
| `rp_ncpd.cell.y` | `-2362.0` |
| `rp_ncpd.cell.z` | `181.5` |
| `rp_ncpd.entrance.heading` | `90.0` |
| `rp_ncpd.entrance.x` | `430.0` |
| `rp_ncpd.entrance.y` | `-2369.0` |
| `rp_ncpd.entrance.z` | `182.0` |
| `rp_ncpd.fine.autoWarrantLevel` | `1` |
| `rp_ncpd.fine.inviteTimeoutMs` | `30000` |
| `rp_ncpd.fine.max` | `100000` |
| `rp_ncpd.fine.min` | `1` |
| `rp_ncpd.grantKitRights` | `false` |
| `rp_ncpd.menuDistance` | `3.5` |
| `rp_ncpd.prison.leashCheckMs` | `5000` |
| `rp_ncpd.prison.maxMinutes` | `120` |
| `rp_ncpd.prison.minMinutes` | `1` |
| `rp_ncpd.prison.notifyEverySeconds` | `60` |
| `rp_ncpd.prison.persistEverySeconds` | `60` |
| `rp_ncpd.vehicle.lockExit` | `true` |
| `rp_ncpd.vehicle.preferRear` | `true` |
| `rp_ncpd.vehicle.range` | `5.0` |
| `rp_ncpd.warrant.nativeHeat` | `false` |

### rp_trauma (24 keys)

| Key | Default |
|---|---|
| `rp_trauma.actionRange` | `3.0` |
| `rp_trauma.av.spawnDistance` | `8.0` |
| `rp_trauma.av.spawnUp` | `1.0` |
| `rp_trauma.av.ttlMs` | `1800000` |
| `rp_trauma.commandRange` | `5.0` |
| `rp_trauma.contractMaxFailures` | `2` |
| `rp_trauma.contractMinutes` | `30` |
| `rp_trauma.contractPrice` | `1000` |
| `rp_trauma.countdownWithoutMedics` | `true` |
| `rp_trauma.downHealthFraction` | `0.05` |
| `rp_trauma.downReminderSeconds` | `30` |
| `rp_trauma.downSeconds` | `60` |
| `rp_trauma.healFee` | `100` |
| `rp_trauma.hospital.heading` | `180.0` |
| `rp_trauma.hospital.respawn.x` | `400.0` |
| `rp_trauma.hospital.respawn.y` | `-2366.0` |
| `rp_trauma.hospital.respawn.z` | `182.0` |
| `rp_trauma.hospitalBill` | `500` |
| `rp_trauma.medicCooldownSeconds` | `10` |
| `rp_trauma.reviveFee` | `300` |
| `rp_trauma.reviveGraceMs` | `5000` |
| `rp_trauma.reviveHealthFraction` | `0.5` |
| `rp_trauma.reviveMs` | `8000` |
| `rp_trauma.stabiliseMs` | `5000` |

### rp_delamain (10 keys)

| Key | Default |
|---|---|
| `rp_delamain.autoEndMetres` | `100` |
| `rp_delamain.baseFare` | `50` |
| `rp_delamain.blipTtlSec` | `180` |
| `rp_delamain.driverShare` | `0.8` |
| `rp_delamain.perHundredMetres` | `15` |
| `rp_delamain.pickupTimeoutSec` | `900` |
| `rp_delamain.ratingWindowSec` | `900` |
| `rp_delamain.sampleMs` | `2000` |
| `rp_delamain.waitTimeoutSec` | `180` |
| `rp_delamain.waypointRefreshM` | `8` |

### rp_mecano (19 keys)

| Key | Default |
|---|---|
| `rp_mecano.bill.max` | `50000` |
| `rp_mecano.bill.mechanicShare` | `0.7` |
| `rp_mecano.bill.reach` | `10.0` |
| `rp_mecano.bill.timeoutMs` | `60000` |
| `rp_mecano.fuel.reach` | `4.0` |
| `rp_mecano.impound.fee` | `100` |
| `rp_mecano.impound.reach` | `8.0` |
| `rp_mecano.impound.testingReach` | `6.0` |
| `rp_mecano.impoundAnywhereForTesting` | `false` |
| `rp_mecano.paint.price` | `250` |
| `rp_mecano.paint.reach` | `6.0` |
| `rp_mecano.repair.components` | `2` |
| `rp_mecano.repair.durationMs` | `15000` |
| `rp_mecano.repair.reach` | `4.0` |
| `rp_mecano.repair.requireToolkit` | `true` |
| `rp_mecano.tow.distance` | `6.0` |
| `rp_mecano.tow.minMove` | `0.3` |
| `rp_mecano.tow.reach` | `8.0` |
| `rp_mecano.tow.tickMs` | `2000` |

### rp_ferrailleur (40 keys)

| Key | Default |
|---|---|
| `rp_ferrailleur.basePrices.chip` | `200` |
| `rp_ferrailleur.basePrices.component` | `60` |
| `rp_ferrailleur.basePrices.scrap` | `15` |
| `rp_ferrailleur.crowbar.durability` | `20` |
| `rp_ferrailleur.crowbar.price` | `250` |
| `rp_ferrailleur.dealer.position.x` | `462.0` |
| `rp_ferrailleur.dealer.position.y` | `-2352.0` |
| `rp_ferrailleur.dealer.position.z` | `178.0` |
| `rp_ferrailleur.dealer.reach` | `5.0` |
| `rp_ferrailleur.dealer.yaw` | `200.0` |
| `rp_ferrailleur.heightTolerance` | `4.0` |
| `rp_ferrailleur.points.1.x` | `456.0` |
| `rp_ferrailleur.points.1.y` | `-2356.0` |
| `rp_ferrailleur.points.1.z` | `178.0` |
| `rp_ferrailleur.points.2.x` | `461.0` |
| `rp_ferrailleur.points.2.y` | `-2359.0` |
| `rp_ferrailleur.points.2.z` | `178.0` |
| `rp_ferrailleur.points.3.x` | `467.0` |
| `rp_ferrailleur.points.3.y` | `-2357.0` |
| `rp_ferrailleur.points.3.z` | `178.0` |
| `rp_ferrailleur.points.4.x` | `469.0` |
| `rp_ferrailleur.points.4.y` | `-2351.0` |
| `rp_ferrailleur.points.4.z` | `178.0` |
| `rp_ferrailleur.points.5.x` | `465.0` |
| `rp_ferrailleur.points.5.y` | `-2346.0` |
| `rp_ferrailleur.points.5.z` | `178.0` |
| `rp_ferrailleur.points.6.x` | `459.0` |
| `rp_ferrailleur.points.6.y` | `-2346.0` |
| `rp_ferrailleur.points.6.z` | `178.0` |
| `rp_ferrailleur.points.7.x` | `455.0` |
| `rp_ferrailleur.points.7.y` | `-2350.0` |
| `rp_ferrailleur.points.7.z` | `178.0` |
| `rp_ferrailleur.priceIntervalMs` | `600000` |
| `rp_ferrailleur.priceVariation` | `0.2` |
| `rp_ferrailleur.promptDistance` | `3.0` |
| `rp_ferrailleur.regenMs` | `300000` |
| `rp_ferrailleur.ringRadius` | `1.2` |
| `rp_ferrailleur.searchMs` | `8000` |
| `rp_ferrailleur.searchReach` | `3.5` |
| `rp_ferrailleur.societyShare` | `0.1` |

### rp_nomade (35 keys)

| Key | Default |
|---|---|
| `rp_nomade.ambush.center.x` | `410.0` |
| `rp_nomade.ambush.center.y` | `-2384.0` |
| `rp_nomade.ambush.center.z` | `182.0` |
| `rp_nomade.ambush.count` | `3` |
| `rp_nomade.ambush.enabled` | `true` |
| `rp_nomade.ambush.lifetimeMs` | `180000` |
| `rp_nomade.ambush.minTravel` | `10.0` |
| `rp_nomade.ambush.radius` | `20.0` |
| `rp_nomade.ambush.spawnDistance` | `15.0` |
| `rp_nomade.camp.board.position.x` | `420.0` |
| `rp_nomade.camp.board.position.y` | `-2381.5` |
| `rp_nomade.camp.board.position.z` | `182.0` |
| `rp_nomade.camp.board.promptDistance` | `3.0` |
| `rp_nomade.camp.board.radius` | `1.0` |
| `rp_nomade.camp.board.reach` | `5.0` |
| `rp_nomade.camp.position.x` | `420.0` |
| `rp_nomade.camp.position.y` | `-2378.0` |
| `rp_nomade.camp.position.z` | `182.0` |
| `rp_nomade.camp.truckSpawn.x` | `427.0` |
| `rp_nomade.camp.truckSpawn.y` | `-2381.0` |
| `rp_nomade.camp.truckSpawn.yaw` | `180.0` |
| `rp_nomade.camp.truckSpawn.z` | `182.3` |
| `rp_nomade.contract.convoyBonus` | `0.25` |
| `rp_nomade.contract.convoyMinimum` | `2` |
| `rp_nomade.contract.convoyRadius` | `30.0` |
| `rp_nomade.contract.historyRows` | `10` |
| `rp_nomade.contract.payPerCrate` | `150` |
| `rp_nomade.contract.societyShare` | `0.15` |
| `rp_nomade.contract.timeLimitMs` | `1200000` |
| `rp_nomade.contract.unloadMs` | `6000` |
| `rp_nomade.crate.pickupDistance` | `3.5` |
| `rp_nomade.crate.promptDistance` | `3.0` |
| `rp_nomade.truck.reach` | `4.0` |
| `rp_nomade.truck.rental` | `100` |
| `rp_nomade.truck.ttlMs` | `2400000` |

### rp_bar (32 keys)

| Key | Default |
|---|---|
| `rp_bar.ambience.radius` | `30.0` |
| `rp_bar.ambience.stopRadius` | `34.0` |
| `rp_bar.ambience.sweepMs` | `5000` |
| `rp_bar.ambience.volume` | `0.5` |
| `rp_bar.counter.position.x` | `360.0` |
| `rp_bar.counter.position.y` | `-2390.0` |
| `rp_bar.counter.position.z` | `181.99` |
| `rp_bar.counter.promptDistance` | `3.0` |
| `rp_bar.counter.radius` | `1.5` |
| `rp_bar.counter.reach` | `8.0` |
| `rp_bar.craft.durationMs` | `4000` |
| `rp_bar.drinks.beer.alcohol` | `1` |
| `rp_bar.drinks.beer.price` | `30` |
| `rp_bar.drinks.johnny_silverhand.alcohol` | `3` |
| `rp_bar.drinks.johnny_silverhand.price` | `120` |
| `rp_bar.drinks.synth_soda.alcohol` | `0` |
| `rp_bar.drinks.synth_soda.price` | `20` |
| `rp_bar.drinks.whisky.alcohol` | `2` |
| `rp_bar.drinks.whisky.price` | `60` |
| `rp_bar.drunk.max` | `10` |
| `rp_bar.drunk.screenAbove` | `3` |
| `rp_bar.drunk.stumbleAbove` | `7` |
| `rp_bar.drunk.stumbleDurationMs` | `2000` |
| `rp_bar.drunk.tickMs` | `60000` |
| `rp_bar.ingredients.ingredient_ice.cost` | `10` |
| `rp_bar.ingredients.ingredient_mixer.cost` | `15` |
| `rp_bar.ingredients.ingredient_spirits.cost` | `40` |
| `rp_bar.sale.breakDistance` | `5.0` |
| `rp_bar.sale.distance` | `3.0` |
| `rp_bar.sale.durationMs` | `4000` |
| `rp_bar.sale.inviteTimeoutMs` | `20000` |
| `rp_bar.sale.tillShare` | `0.7` |

### rp_ripperdoc (28 keys)

| Key | Default |
|---|---|
| `rp_ripperdoc.chair.position.x` | `400.0` |
| `rp_ripperdoc.chair.position.y` | `-2386.0` |
| `rp_ripperdoc.chair.position.z` | `182.0` |
| `rp_ripperdoc.chair.promptDistance` | `3.0` |
| `rp_ripperdoc.chair.radius` | `1.2` |
| `rp_ripperdoc.chair.reach` | `3.5` |
| `rp_ripperdoc.chair.yaw` | `90.0` |
| `rp_ripperdoc.cyberpsychosisDurationSeconds` | `60` |
| `rp_ripperdoc.cyberpsychosisThreshold` | `4` |
| `rp_ripperdoc.grades.arms.industrial.durationMs` | `22000` |
| `rp_ripperdoc.grades.arms.industrial.price` | `3200` |
| `rp_ripperdoc.grades.arms.street.durationMs` | `15000` |
| `rp_ripperdoc.grades.arms.street.price` | `1500` |
| `rp_ripperdoc.grades.deck.street.durationMs` | `20000` |
| `rp_ripperdoc.grades.deck.street.price` | `2000` |
| `rp_ripperdoc.grades.ice.street.durationMs` | `14000` |
| `rp_ripperdoc.grades.ice.street.price` | `1800` |
| `rp_ripperdoc.grades.legs.athlete.durationMs` | `18000` |
| `rp_ripperdoc.grades.legs.athlete.price` | `2500` |
| `rp_ripperdoc.grades.legs.training.durationMs` | `12000` |
| `rp_ripperdoc.grades.legs.training.price` | `1200` |
| `rp_ripperdoc.grades.purge.street.durationMs` | `14000` |
| `rp_ripperdoc.grades.purge.street.price` | `1600` |
| `rp_ripperdoc.operateDistance` | `4.0` |
| `rp_ripperdoc.quoteTimeoutMs` | `30000` |
| `rp_ripperdoc.removalPriceFactor` | `0.5` |
| `rp_ripperdoc.restockMaxCount` | `5` |
| `rp_ripperdoc.restockPriceFactor` | `0.6` |

### rp_fixer (34 keys)

| Key | Default |
|---|---|
| `rp_fixer.arrivalDistance` | `5.0` |
| `rp_fixer.autoPublish` | `true` |
| `rp_fixer.boardReach` | `15.0` |
| `rp_fixer.commissionRate` | `0.15` |
| `rp_fixer.guards.count` | `2` |
| `rp_fixer.guards.engageDistance` | `25.0` |
| `rp_fixer.guards.guardRadius` | `8` |
| `rp_fixer.guards.health` | `150` |
| `rp_fixer.guards.postRadius` | `3.0` |
| `rp_fixer.interactReach` | `4.5` |
| `rp_fixer.maxOpenGigs` | `20` |
| `rp_fixer.office.x` | `400.0` |
| `rp_fixer.office.y` | `-2390.0` |
| `rp_fixer.office.z` | `182.0` |
| `rp_fixer.openBoardWithoutFixer` | `true` |
| `rp_fixer.promptDistance` | `3.0` |
| `rp_fixer.republishDelaySec` | `60` |
| `rp_fixer.reputation.abandoned` | `-1` |
| `rp_fixer.reputation.floor` | `0` |
| `rp_fixer.reputation.success` | `1` |
| `rp_fixer.reputation.timeout` | `-1` |
| `rp_fixer.templates.delivery_hot.pay` | `1200` |
| `rp_fixer.templates.delivery_hot.timeLimitSec` | `360` |
| `rp_fixer.templates.delivery_meds.pay` | `600` |
| `rp_fixer.templates.delivery_meds.timeLimitSec` | `600` |
| `rp_fixer.templates.escort_witness.pay` | `800` |
| `rp_fixer.templates.escort_witness.timeLimitSec` | `720` |
| `rp_fixer.templates.extraction_techie.pay` | `1500` |
| `rp_fixer.templates.extraction_techie.timeLimitSec` | `900` |
| `rp_fixer.templates.extraction_vip.pay` | `3000` |
| `rp_fixer.templates.extraction_vip.timeLimitSec` | `900` |
| `rp_fixer.templates.retrieval_shard.pay` | `1000` |
| `rp_fixer.templates.retrieval_shard.timeLimitSec` | `720` |
| `rp_fixer.warnBeforeDeadlineSec` | `60` |

### rp_netrunner (32 keys)

| Key | Default |
|---|---|
| `rp_netrunner.accessPoint.position.x` | `400.0` |
| `rp_netrunner.accessPoint.position.y` | `-2390.0` |
| `rp_netrunner.accessPoint.position.z` | `182.0` |
| `rp_netrunner.accessPoint.promptDistance` | `3.0` |
| `rp_netrunner.accessPoint.radius` | `1.2` |
| `rp_netrunner.accessPoint.reach` | `4.0` |
| `rp_netrunner.breach.bounty` | `200` |
| `rp_netrunner.breach.doorHoldMs` | `30000` |
| `rp_netrunner.breach.doorRadius` | `15.0` |
| `rp_netrunner.breach.durationMs` | `10000` |
| `rp_netrunner.breach.societyBounty` | `100` |
| `rp_netrunner.cooldownMs` | `30000` |
| `rp_netrunner.deck.price` | `0` |
| `rp_netrunner.hacks.overheat.damage` | `10` |
| `rp_netrunner.hacks.overheat.range` | `25` |
| `rp_netrunner.hacks.overheat.recoveryMs` | `4000` |
| `rp_netrunner.hacks.overheat.staminaCost` | `20` |
| `rp_netrunner.hacks.overheat.statusMs` | `750` |
| `rp_netrunner.hacks.overheat.uploadMs` | `2500` |
| `rp_netrunner.hacks.short_circuit.damage` | `25` |
| `rp_netrunner.hacks.short_circuit.range` | `25` |
| `rp_netrunner.hacks.short_circuit.recoveryMs` | `4000` |
| `rp_netrunner.hacks.short_circuit.staminaCost` | `20` |
| `rp_netrunner.hacks.short_circuit.statusMs` | `750` |
| `rp_netrunner.hacks.short_circuit.uploadMs` | `2000` |
| `rp_netrunner.jam.durationMs` | `60000` |
| `rp_netrunner.jam.noiseEveryMs` | `15000` |
| `rp_netrunner.ping.durationMs` | `60000` |
| `rp_netrunner.ping.range` | `50` |
| `rp_netrunner.ping.refreshMs` | `2000` |
| `rp_netrunner.ping.warnTarget` | `false` |
| `rp_netrunner.traceChance` | `0.5` |

### rp_vigile (20 keys)

| Key | Default |
|---|---|
| `rp_vigile.bodyguardRange` | `15.0` |
| `rp_vigile.escortHoldMs` | `120000` |
| `rp_vigile.escortRange` | `3.0` |
| `rp_vigile.expelDistance` | `20.0` |
| `rp_vigile.journalSize` | `50` |
| `rp_vigile.maxMinutes` | `240` |
| `rp_vigile.minMinutes` | `1` |
| `rp_vigile.minuteCoverage` | `0.75` |
| `rp_vigile.offerTimeoutSec` | `180` |
| `rp_vigile.ratePerMinute` | `20` |
| `rp_vigile.societyShare` | `0.2` |
| `rp_vigile.templates.afterlife.minutes` | `30` |
| `rp_vigile.templates.blackmarket.minutes` | `30` |
| `rp_vigile.templates.hospital.minutes` | `20` |
| `rp_vigile.templates.mecano_shop.minutes` | `20` |
| `rp_vigile.templates.nomad_camp.minutes` | `20` |
| `rp_vigile.templates.scrapyard.minutes` | `20` |
| `rp_vigile.tickMs` | `5000` |
| `rp_vigile.unpaidWarnAfter` | `2` |
| `rp_vigile.zoneOfferTimeoutSec` | `1800` |

### rp_garage (46 keys)

| Key | Default |
|---|---|
| `rp_garage.confirmTimeoutMs` | `30000` |
| `rp_garage.dealership.position.x` | `392.0` |
| `rp_garage.dealership.position.y` | `-2410.0` |
| `rp_garage.dealership.position.z` | `182.0` |
| `rp_garage.dealership.spawnPoint.x` | `392.0` |
| `rp_garage.dealership.spawnPoint.y` | `-2404.0` |
| `rp_garage.dealership.spawnPoint.yaw` | `0.0` |
| `rp_garage.dealership.spawnPoint.z` | `182.0` |
| `rp_garage.garages.mecano.position.x` | `341.0` |
| `rp_garage.garages.mecano.position.y` | `-2401.0` |
| `rp_garage.garages.mecano.position.z` | `180.3` |
| `rp_garage.garages.mecano.spawnPoint.x` | `347.0` |
| `rp_garage.garages.mecano.spawnPoint.y` | `-2405.0` |
| `rp_garage.garages.mecano.spawnPoint.yaw` | `90.0` |
| `rp_garage.garages.mecano.spawnPoint.z` | `180.5` |
| `rp_garage.garages.public.position.x` | `370.0` |
| `rp_garage.garages.public.position.y` | `-2405.0` |
| `rp_garage.garages.public.position.z` | `182.0` |
| `rp_garage.garages.public.spawnPoint.x` | `364.0` |
| `rp_garage.garages.public.spawnPoint.y` | `-2406.0` |
| `rp_garage.garages.public.spawnPoint.yaw` | `90.0` |
| `rp_garage.garages.public.spawnPoint.z` | `182.0` |
| `rp_garage.impound.fee` | `500` |
| `rp_garage.impound.lotPosition.x` | `440.0` |
| `rp_garage.impound.lotPosition.y` | `-2366.0` |
| `rp_garage.impound.lotPosition.z` | `181.0` |
| `rp_garage.menuTimeoutMs` | `60000` |
| `rp_garage.minHealthOnTakeOut` | `0.2` |
| `rp_garage.reach.garage` | `6.0` |
| `rp_garage.reach.height` | `4.0` |
| `rp_garage.reach.key` | `5.0` |
| `rp_garage.reach.keyVehicle` | `8.0` |
| `rp_garage.reach.lock` | `6.0` |
| `rp_garage.reach.plate` | `8.0` |
| `rp_garage.reach.prompt` | `3.0` |
| `rp_garage.reach.store` | `8.0` |
| `rp_garage.snapshotIntervalMs` | `30000` |
| `rp_garage.spawnClearance` | `3.0` |
| `rp_garage.spawnStep` | `4.5` |
| `rp_garage.spawnTries` | `3` |
| `rp_garage.stolenCooldownS` | `300` |
| `rp_garage.vehicles.arch_nazare.price` | `12000` |
| `rp_garage.vehicles.archer_hella.price` | `15000` |
| `rp_garage.vehicles.quadra_turbo_r.price` | `60000` |
| `rp_garage.vehicles.thorton_mackinaw.price` | `28000` |
| `rp_garage.vehicles.villefort_cortes_delamain.price` | `45000` |

### rp_shops (52 keys)

| Key | Default |
|---|---|
| `rp_shops.blackmarket.closeHour` | `6` |
| `rp_shops.blackmarket.openHour` | `22` |
| `rp_shops.gunLicenceFee` | `500` |
| `rp_shops.maxCountPerPurchase` | `20` |
| `rp_shops.promptDistance` | `3.0` |
| `rp_shops.reach` | `3.5` |
| `rp_shops.restockCostRatio` | `0.5` |
| `rp_shops.robCooldownSeconds` | `1200` |
| `rp_shops.robDistance` | `5.0` |
| `rp_shops.robHandsUpMs` | `20000` |
| `rp_shops.robLoot.max` | `600` |
| `rp_shops.robLoot.min` | `200` |
| `rp_shops.robTakesFromSociety` | `true` |
| `rp_shops.shops.blackmarket.position.x` | `402.0` |
| `rp_shops.shops.blackmarket.position.y` | `-2393.0` |
| `rp_shops.shops.blackmarket.position.z` | `181.99` |
| `rp_shops.shops.blackmarket.prices.lockpick` | `80` |
| `rp_shops.shops.blackmarket.prices.qh_ping` | `120` |
| `rp_shops.shops.blackmarket.prices.synthcoke` | `150` |
| `rp_shops.shops.blackmarket.yaw` | `113.0` |
| `rp_shops.shops.clothes.position.x` | `352.0` |
| `rp_shops.shops.clothes.position.y` | `-2398.0` |
| `rp_shops.shops.clothes.position.z` | `181.99` |
| `rp_shops.shops.clothes.prices.styling` | `200` |
| `rp_shops.shops.clothes.yaw` | `263.0` |
| `rp_shops.shops.gunshop.position.x` | `410.0` |
| `rp_shops.shops.gunshop.position.y` | `-2386.0` |
| `rp_shops.shops.gunshop.position.z` | `181.99` |
| `rp_shops.shops.gunshop.prices.katana` | `900` |
| `rp_shops.shops.gunshop.prices.pistol` | `400` |
| `rp_shops.shops.gunshop.prices.rifle` | `1200` |
| `rp_shops.shops.gunshop.yaw` | `119.0` |
| `rp_shops.shops.pharmacy.position.x` | `396.0` |
| `rp_shops.shops.pharmacy.position.y` | `-2372.0` |
| `rp_shops.shops.pharmacy.position.z` | `181.99` |
| `rp_shops.shops.pharmacy.prices.bandage` | `40` |
| `rp_shops.shops.pharmacy.prices.bounceback` | `90` |
| `rp_shops.shops.pharmacy.prices.maxdoc` | `120` |
| `rp_shops.shops.pharmacy.restockTo` | `10` |
| `rp_shops.shops.pharmacy.yaw` | `154.0` |
| `rp_shops.shops.supermarket.position.x` | `370.0` |
| `rp_shops.shops.supermarket.position.y` | `-2385.0` |
| `rp_shops.shops.supermarket.position.z` | `181.99` |
| `rp_shops.shops.supermarket.prices.burrito` | `25` |
| `rp_shops.shops.supermarket.prices.chooh2` | `60` |
| `rp_shops.shops.supermarket.prices.cigarettes` | `20` |
| `rp_shops.shops.supermarket.prices.nicola` | `15` |
| `rp_shops.shops.supermarket.prices.water` | `10` |
| `rp_shops.shops.supermarket.yaw` | `214.0` |
| `rp_shops.societyShare` | `0.7` |
| `rp_shops.stylingFee` | `200` |
| `rp_shops.weaponFallbackMs` | `15000` |

### rp_housing (52 keys)

| Key | Default |
|---|---|
| `rp_housing.agency.position.x` | `365.0` |
| `rp_housing.agency.position.y` | `-2408.0` |
| `rp_housing.agency.position.z` | `182.0` |
| `rp_housing.agency.radius` | `1.5` |
| `rp_housing.agencyRadius` | `4.0` |
| `rp_housing.enterFade` | `400` |
| `rp_housing.evictAfter` | `2` |
| `rp_housing.homes.badlands_hideout.entrance.x` | `352.0` |
| `rp_housing.homes.badlands_hideout.entrance.y` | `-2404.0` |
| `rp_housing.homes.badlands_hideout.entrance.z` | `182.0` |
| `rp_housing.homes.badlands_hideout.interior.x` | `352.0` |
| `rp_housing.homes.badlands_hideout.interior.y` | `-2410.0` |
| `rp_housing.homes.badlands_hideout.interior.z` | `182.0` |
| `rp_housing.homes.badlands_hideout.price` | `15000` |
| `rp_housing.homes.h10_studio.entrance.x` | `376.0` |
| `rp_housing.homes.h10_studio.entrance.y` | `-2380.0` |
| `rp_housing.homes.h10_studio.entrance.z` | `182.0` |
| `rp_housing.homes.h10_studio.interior.x` | `376.0` |
| `rp_housing.homes.h10_studio.interior.y` | `-2374.0` |
| `rp_housing.homes.h10_studio.interior.z` | `182.0` |
| `rp_housing.homes.h10_studio.price` | `25000` |
| `rp_housing.homes.japantown_loft.entrance.x` | `390.0` |
| `rp_housing.homes.japantown_loft.entrance.y` | `-2399.0` |
| `rp_housing.homes.japantown_loft.entrance.z` | `182.0` |
| `rp_housing.homes.japantown_loft.interior.x` | `390.0` |
| `rp_housing.homes.japantown_loft.interior.y` | `-2405.0` |
| `rp_housing.homes.japantown_loft.interior.z` | `182.0` |
| `rp_housing.homes.japantown_loft.price` | `65000` |
| `rp_housing.homes.kabuki_flat.entrance.x` | `388.0` |
| `rp_housing.homes.kabuki_flat.entrance.y` | `-2388.0` |
| `rp_housing.homes.kabuki_flat.entrance.z` | `182.0` |
| `rp_housing.homes.kabuki_flat.interior.x` | `388.0` |
| `rp_housing.homes.kabuki_flat.interior.y` | `-2382.0` |
| `rp_housing.homes.kabuki_flat.interior.z` | `182.0` |
| `rp_housing.homes.kabuki_flat.price` | `40000` |
| `rp_housing.homes.northside_container.entrance.x` | `348.0` |
| `rp_housing.homes.northside_container.entrance.y` | `-2386.0` |
| `rp_housing.homes.northside_container.entrance.z` | `182.0` |
| `rp_housing.homes.northside_container.interior.x` | `342.0` |
| `rp_housing.homes.northside_container.interior.y` | `-2386.0` |
| `rp_housing.homes.northside_container.interior.z` | `182.0` |
| `rp_housing.homes.northside_container.price` | `9000` |
| `rp_housing.interiorRadius` | `8.0` |
| `rp_housing.keyDistance` | `3.0` |
| `rp_housing.promptDistance` | `3.0` |
| `rp_housing.rent` | `500` |
| `rp_housing.rentIntervalSec` | `600` |
| `rp_housing.rentTickSec` | `60` |
| `rp_housing.sellBackRatio` | `0.7` |
| `rp_housing.serverTolerance` | `2.5` |
| `rp_housing.spawnWaitSec` | `30` |
| `rp_housing.stashCapacity` | `200` |

### rp_hud (6 keys)

| Key | Default |
|---|---|
| `rp_hud.dependencyRepushMs` | `4000` |
| `rp_hud.joinRepushMs` | `6000` |
| `rp_hud.minPushIntervalMs` | `250` |
| `rp_hud.needsWarnAt` | `25` |
| `rp_hud.panelWidthPx` | `300` |
| `rp_hud.refreshMs` | `30000` |

### rp_phone (14 keys)

| Key | Default |
|---|---|
| `rp_phone.ads.maxLength` | `140` |
| `rp_phone.ads.maxListed` | `30` |
| `rp_phone.ads.maxPerPlayer` | `3` |
| `rp_phone.ads.minutes` | `60` |
| `rp_phone.ads.price` | `50` |
| `rp_phone.call.ringSeconds` | `30` |
| `rp_phone.contacts.max` | `60` |
| `rp_phone.contacts.nearbyRadius` | `8.0` |
| `rp_phone.intentsPerSecond` | `12` |
| `rp_phone.location.blipSeconds` | `120` |
| `rp_phone.pushThrottleMs` | `250` |
| `rp_phone.requireItem` | `true` |
| `rp_phone.sms.keepPerPlayer` | `300` |
| `rp_phone.sms.maxLength` | `200` |

### rp_radio (12 keys)

| Key | Default |
|---|---|
| `rp_radio.badlandsCut` | `false` |
| `rp_radio.band.max` | `108.0` |
| `rp_radio.band.min` | `87.5` |
| `rp_radio.band.step` | `0.1` |
| `rp_radio.jam.garbleRatio` | `0.45` |
| `rp_radio.jam.garbleText` | `true` |
| `rp_radio.jam.localGain` | `0.5` |
| `rp_radio.jam.staticIntervalMs` | `15000` |
| `rp_radio.maxTextLength` | `200` |
| `rp_radio.rememberDelayMs` | `4000` |
| `rp_radio.rememberFrequency` | `true` |
| `rp_radio.requireItem` | `true` |

### rp_gangs (40 keys)

| Key | Default |
|---|---|
| `rp_gangs.arrestInfluence` | `-5` |
| `rp_gangs.buyer.promptDistance` | `2.5` |
| `rp_gangs.buyer.reach` | `4.0` |
| `rp_gangs.dealCooldownMs` | `60000` |
| `rp_gangs.dealInfluence` | `1` |
| `rp_gangs.dealPrice` | `80` |
| `rp_gangs.dropOnJob` | `true` |
| `rp_gangs.gigInfluence` | `2` |
| `rp_gangs.openFounding` | `true` |
| `rp_gangs.racketAmount` | `100` |
| `rp_gangs.racketCooldownMs` | `60000` |
| `rp_gangs.racketReach` | `5.0` |
| `rp_gangs.recruitReach` | `5.0` |
| `rp_gangs.robCooldownMs` | `120000` |
| `rp_gangs.robReach` | `3.0` |
| `rp_gangs.robShare` | `0.3` |
| `rp_gangs.showTag` | `true` |
| `rp_gangs.tagMaxDistance` | `40.0` |
| `rp_gangs.territories.afterlife.buyer.x` | `358.0` |
| `rp_gangs.territories.afterlife.buyer.y` | `-2392.0` |
| `rp_gangs.territories.afterlife.buyer.yaw` | `45.0` |
| `rp_gangs.territories.afterlife.buyer.z` | `182.0` |
| `rp_gangs.territories.blackmarket.buyer.x` | `397.0` |
| `rp_gangs.territories.blackmarket.buyer.y` | `-2393.0` |
| `rp_gangs.territories.blackmarket.buyer.yaw` | `45.0` |
| `rp_gangs.territories.blackmarket.buyer.z` | `182.0` |
| `rp_gangs.territories.nomad_camp.buyer.x` | `418.0` |
| `rp_gangs.territories.nomad_camp.buyer.y` | `-2380.0` |
| `rp_gangs.territories.nomad_camp.buyer.yaw` | `45.0` |
| `rp_gangs.territories.nomad_camp.buyer.z` | `182.0` |
| `rp_gangs.territories.scrapyard.buyer.x` | `460.0` |
| `rp_gangs.territories.scrapyard.buyer.y` | `-2355.0` |
| `rp_gangs.territories.scrapyard.buyer.yaw` | `45.0` |
| `rp_gangs.territories.scrapyard.buyer.z` | `178.0` |
| `rp_gangs.tributeIntervalMs` | `600000` |
| `rp_gangs.tributePerZone` | `50` |
| `rp_gangs.warCooldownMs` | `600000` |
| `rp_gangs.warInfluence` | `10` |
| `rp_gangs.warMinutes` | `5` |
| `rp_gangs.warTickMs` | `30000` |

### rp_ambiance (21 keys)

| Key | Default |
|---|---|
| `rp_ambiance.alerts.cooldownSeconds` | `8` |
| `rp_ambiance.alerts.flashIntervalMs` | `1200` |
| `rp_ambiance.alerts.flashes` | `3` |
| `rp_ambiance.alerts.range` | `60.0` |
| `rp_ambiance.alertsEnabled` | `true` |
| `rp_ambiance.announceWeather` | `true` |
| `rp_ambiance.badlands` | `true` |
| `rp_ambiance.figurants.speakMaxSeconds` | `120` |
| `rp_ambiance.figurants.speakMinSeconds` | `60` |
| `rp_ambiance.figurants.speakRadius` | `8.0` |
| `rp_ambiance.figurants.sweepSeconds` | `300` |
| `rp_ambiance.figurants.wanderRadius` | `6.0` |
| `rp_ambiance.figurantsEnabled` | `true` |
| `rp_ambiance.musicVolume` | `0.35` |
| `rp_ambiance.noticeIntervalMinutes` | `15` |
| `rp_ambiance.notices.durationMs` | `10000` |
| `rp_ambiance.notices.enabled` | `true` |
| `rp_ambiance.realHoursPerDay` | `3` |
| `rp_ambiance.weatherMaxMinutes` | `25` |
| `rp_ambiance.weatherMinMinutes` | `12` |
| `rp_ambiance.weatherTransitionSeconds` | `45` |

### rp_admin (13 keys)

| Key | Default |
|---|---|
| `rp_admin.answerMaxBytes` | `300` |
| `rp_admin.godModeInAdminMode` | `true` |
| `rp_admin.maxGrade` | `3` |
| `rp_admin.maxMoney` | `1000000000` |
| `rp_admin.panelTimeoutMs` | `60000` |
| `rp_admin.recordLines` | `10` |
| `rp_admin.reportMaxBytes` | `300` |
| `rp_admin.spectate.blendMs` | `400` |
| `rp_admin.spectate.distance` | `5.0` |
| `rp_admin.spectate.height` | `2.0` |
| `rp_admin.teleportOffset` | `1.5` |
| `rp_admin.ticketListLimit` | `20` |
| `rp_admin.warnMaxBytes` | `200` |

### rp_logs (9 keys)

| Key | Default |
|---|---|
| `rp_logs.cacheSize` | `500` |
| `rp_logs.defaultListCount` | `10` |
| `rp_logs.flushBatchSize` | `50` |
| `rp_logs.flushIntervalMs` | `2000` |
| `rp_logs.maxListCount` | `50` |
| `rp_logs.pendingMax` | `2000` |
| `rp_logs.webhookBackoffSeconds` | `5` |
| `rp_logs.webhookMinIntervalMs` | `1000` |
| `rp_logs.webhookQueueMax` | `100` |

### rp_whitelist (12 keys)

| Key | Default |
|---|---|
| `rp_whitelist.bansWhenDisabled` | `true` |
| `rp_whitelist.discordLink` | `"https://discord.open2077.net"` |
| `rp_whitelist.enabled` | `false` |
| `rp_whitelist.failClosed` | `true` |
| `rp_whitelist.loadWaitSeconds` | `5` |
| `rp_whitelist.maxPlayers` | `0` |
| `rp_whitelist.mode` | `"allowlist"` |
| `rp_whitelist.queue.holdSeconds` | `6.5` |
| `rp_whitelist.queue.pollMs` | `500` |
| `rp_whitelist.queue.reserveSeconds` | `10` |
| `rp_whitelist.queue.ttlSeconds` | `120` |
| `rp_whitelist.recentRefusals` | `10` |
