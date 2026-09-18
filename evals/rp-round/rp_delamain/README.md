# rp_delamain — player-driven Delamain cabs

Server-authoritative taxi service for an Open77 RP server (build `2.31.13+op77.76`). A client
calls a cab, every **on-duty Delamain driver** (`rp_jobs`, job `delamain`) is paged with the
distance and a temporary map pin, one driver accepts and gets a GPS route to the client, the
**meter** runs while the client sits in the driver's car, and the fare is settled **in cash**
(`rp_economy`): 80 % to the driver, 20 % to the `delamain` society (`rp_bank`). With no driver
on duty the client is sent to the NPC cab of `eval_taxi` (`/taxi`).

The server decides everything (who is a driver, who rides with whom, how far, what it costs,
who is paid). The client half only draws pins, moves the driver's GPS and reports the caller's
map waypoint — which the server re-validates.

## Commands

| Command | Who | Effect |
|---|---|---|
| `/delamain` | anyone | Calls a driver. Every on-duty Delamain driver (except you) reads `Ride #N: <you> is calling a cab 240 m from you. /accepter N`, gets a toast and a `Delamain call #N` pin at your position. You read `Delamain dispatch: looking for a driver... (ride #N, 2 drivers paged)`. Your **map waypoint** (right-click on the map before calling) becomes the destination; without one the driver asks. With nobody on duty: `No Delamain driver on duty. Type /taxi for the automated cab (short trips only).` |
| `/delamain annuler` | either side | Client: drops the call (refused while rolling — get out of the cab instead). Driver: hands the call back to the board; the other drivers are paged again, you are not. |
| `/accepter <rideId>` | on-duty driver | Takes the call. The client reads your RP name and distance; your GPS is set to the client and follows them while you drive over; the other drivers' pins go away. Without an id, takes the oldest waiting call. |
| `/course` | either side | Status: waiting / driver on the way (name, distance) / rolling (metres so far, fare so far). A driver also reads their record: rides driven and **average rating**. |
| `/fin` | driver | Ends the ride once the passenger got **out** (refused while they are still seated, or if they never boarded). |
| `/note <1-5>` | client | Rates the last ride, once, within 15 min. The driver is told; the average shows in their `/course`. |

Every refusal is explained in chat as `Delamain` (yellow). From the server console every command
answers `run this from the game, not the console`. Command suggestions are published on
`chat:ready` and once at start.

## How a ride goes

```text
waiting  --/accepter-->  accepted  --client seated in the driver's car-->  riding  --> ended
   |                        |                                                |
   +-- /delamain annuler, 3 min without a driver ----> cancelled              +-- client out after >= 100 m: auto
   +-- driver bails / clocks out / disconnects: back to waiting (re-paged)     +-- driver: /fin once the client is out
```

- **The meter** samples every 2 s (`Config.SampleMs`) the canonical position of the driver's
  vehicle (`Open77.vehicles.getPosition`, fallback: the client's own server position) while the
  client is seated in it and the driver is at the wheel (`Open77.vehicles.getPlayerSeat`, seat
  `seat_front_left`). Only server-spawned vehicles are in that ledger: the driver must use a
  server car (`/car`), not vanilla traffic. A single sample above 120 m is ignored (a teleport
  is not a fare).
- **Fare** = `BaseFare` 50 €$ + `PerHundredMetres` 15 €$ per 100 m (pro rata, rounded):
  640 m → 146 €$. Taken from the client's **cash** (`exports.rp_economy:remove`); the driver
  gets `DriverShare` 80 % (`rp_economy:add`), the rest goes to
  `exports.rp_bank:societyAdd("delamain", ...)`. A client short on cash pays nothing: the ride is
  logged **unpaid** and the driver told. If the driver cannot be credited the client is refunded.
- **Automatic end** when the client leaves the vehicle after `AutoEndMetres` 100 m (reacts to
  `onPlayerLeftVehicle`, re-checked 0.75 s later so a seat switch does not settle the ride; the
  2 s poll is the safety net). Below 100 m the ride pauses until the client gets back in or the
  driver types `/fin`.
- **Timeouts**: a call nobody accepts is dropped after `WaitTimeoutSec` 180 s; an accepted call
  whose client never boards after `PickupTimeoutSec` 900 s.
- **Disconnects**: client gone → ride cancelled, nothing paid, the driver told; driver gone
  before the pickup → the call goes back to the board; driver gone mid-ride → cancelled, nothing
  charged. A driver clocking out (`rp_jobs:duty`, `onDuty = false`) mid-ride settles the ride now,
  before the pickup hands it back to the board.

## Exports (server, synchronous, never yield)

```lua
exports.rp_delamain:call(playerId, destination)   -- rideId | nil, reason
--   destination: { x, y, z } or nil (the driver asks). Reasons: invalid_player_id,
--   player_not_found, already_in_ride, no_driver, jobs_offline, invalid_destination.
--   Pages the drivers and tells the client "looking for a driver..." itself.
exports.rp_delamain:activeRide(playerId)          -- nil, or
--   { id, phase = "waiting"|"accepted"|"riding", clientId, driverId, metres, fare,
--     destination, calledAt, acceptedAt, startedAt, seated }
```

Call them inside `pcall` from another resource (a synchronous export raises when the resource
is missing). This resource ships a client half, so both a server-only caller and one that is
delivered to clients may declare `dependency "rp_delamain"`; `pcall` alone works as well.

## Event (host-wide bus, `TriggerEvent`)

```lua
AddEventHandler("rp_delamain:ride", function(rideId, phase, driverId, clientId) end)
-- phase: "waiting" | "accepted" | "riding" | "ended" | "cancelled"
-- driverId is nil while nobody accepted (waiting, or cancelled before a pickup)
```

Internal net events (`rp_delamain:blip`, `rp_delamain:blipRemove`, `rp_delamain:setWaypoint`,
`rp_delamain:clearWaypoint`, `rp_delamain:askWaypoint`, `rp_delamain:waypoint`) are this
resource's own client/server transport, not an API.

## Persistence

Created inside `Open77.database.ready(...)` with `CREATE TABLE IF NOT EXISTS`, permission
`database.access`, one row per finished or cancelled-after-boarding ride:

```sql
rp_delamain_rides (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    client      VARCHAR(64) NOT NULL,   -- Open77.players.identifier of the client
    driver      VARCHAR(64) NOT NULL,   -- Open77.players.identifier of the driver
    metres      INT         NOT NULL DEFAULT 0,
    fare        INT         NOT NULL DEFAULT 0,   -- what the ride cost
    paid        INT         NOT NULL DEFAULT 0,   -- what was actually taken (0 = unpaid)
    rating      TINYINT     NOT NULL DEFAULT 0,   -- 1..5, 0 = not rated
    status      VARCHAR(16) NOT NULL DEFAULT 'ended',   -- ended | cancelled
    called_at   BIGINT, accepted_at BIGINT, started_at BIGINT, ended_at BIGINT   -- unix seconds
)
```

Rides are written with the callback forms (`insert`, `update`); the driver's record (rides,
rating average) is loaded once per driver with `single` and cached in memory, so the exports
never touch the database. **No database** (`ready` answers `database_unavailable`, or the
database still does not answer 15 s after the first player is ready): rides go to the
resource's `Open77.kvp` store (`ride:<n>`, `rides:count`, `stats:<identifier>`) and the log says
`[rp_delamain] store=kvp reason=...`. The choice is made once per boot.

## Log (grep-able)

```text
[rp_delamain] started: base fare 50, 15 per 100 m, driver share 80%, auto-end at 100 m, sample every 2000 ms
[rp_delamain] store=sql table=rp_delamain_rides
[rp_delamain] ride 1 called by player 2 (<identifier>) drivers_paged=1 destination=412,-2350,182
[rp_delamain] ride 1 accepted by player 1 (<identifier>) distance=24 m
[rp_delamain] ride 1 riding vehicle=17
[rp_delamain] ride 1 passenger out of the cab at 640 m
[rp_delamain] ride 1 ended (auto) metres=640 fare=146 paid=146 driver=<identifier> client=<identifier>
[rp_delamain] ride 1 rated 5 by <identifier>
[rp_delamain] ride 2 back on the board (driver_cancelled) drivers_paged=0
[rp_delamain] ride 2 cancelled by driver_cancelled phase_was=waiting metres=0
```

## Manifest

Permissions: `network.events` (`RegisterNetEvent`, `TriggerClientEvent`,
`Open77.notifications.send` on the server; `RegisterNetEvent`, `TriggerServerEvent` on the
client), `database.access` (`Open77.database.*`), `world.vehicles`
(`Open77.vehicles.getPlayerSeat` / `getPosition`), `ui.vanilla.map` (`Open77.blips.create` /
`remove` / `setWaypoint` / `clearWaypoint` / `waypoint` on the client). No `dependency` line:
this manifest is delivered to clients and `rp_jobs`, `rp_economy`, `rp_bank`, `rp_identity` are
reached through `pcall` (without `rp_jobs` every call answers `Delamain dispatch is offline`;
without `rp_economy` a ride settles unpaid; without `rp_bank` the commission is logged, not
banked; without `rp_identity` account names are used). Toasts need `open77_notifications`
(chat carries every line anyway). `eval_taxi` has no export: the fallback is the `/taxi` line.

No fixed world position: everything is where the players are. `shared/config.lua` holds the
tariff, the timeouts, the pin sprite and the chat colour.

## Test in 2 minutes

Two clients at the freeroam spawn (`381.36, -2401.79, 181.99`), ids `1` (driver) and `2`
(client); `rp_jobs` v2, `rp_economy`, `rp_bank` running. Log on start: `[rp_delamain] started:
...` then `[rp_delamain] store=sql table=rp_delamain_rides`.

1. **Client 2**: `/delamain` → `No Delamain driver on duty. Type /taxi for the automated cab
   (short trips only).`
2. **Console**: `setjob 1 delamain 0`. **Driver 1**: `/service` → clocked in at Delamain.
   `/car` (any car) to have a server-spawned cab, and step out of it for now.
3. **Client 2**: open the map, right-click a point ~300 m down the road (a waypoint), close the
   map, `/delamain` → `Delamain dispatch: looking for a driver... (ride #1, 1 driver paged)`,
   then `Destination taken from your map waypoint (300 m away).` **Driver 1** reads `Ride #1:
   <name> is calling a cab 12 m from you, destination 300 m away. /accepter 1 to take it.`, a
   toast, and a `Delamain call #1` pin on the minimap. Log: `ride 1 called by player 2`.
4. **Driver 1**: `/accepter 1` → `You took ride #1. GPS set to <name> (12 m). Destination pinned
   300 m from the pickup. ...`; the GPS route points at client 2, the pin is gone. **Client 2**
   reads `Driver <RP name> took your call, 12 m away.` `/course` on either side shows the phase.
5. **Driver 1** gets in the driver seat; **client 2** gets in as passenger → both read `Meter
   running: 50 €$ base + 15 €$ per 100 m.`; the driver's GPS now points at the destination. Log:
   `ride 1 riding vehicle=<id>`.
6. Drive at least 100 m (around the plaza road is enough), stop, **client 2** gets out → within
   a second both read the settlement: client `Ride #1 over: 640 m, 146 €$ paid. Cash left: ...
   Rate <name> with /note <1-5>.`; driver `Ride #1 done: 640 m, fare 146 €$, your cut 116 €$
   (Delamain keeps 30 €$). Cash: ...`. `/money` on both confirms; `/societe` on the driver shows
   the Delamain society +30 €$. Log: `ride 1 ended (auto) metres=640 fare=146 paid=146`.
7. **Client 2**: `/note 5` → `Thanks, choom: 5/5 for <name>.`; driver reads `<name> rated ride
   #1 5/5.` **Driver 1**: `/course` → `No ride in progress. 0 calls waiting on the board.` then
   `Your Delamain record: 1 ride, 5.0/5 over 1 rating.`
8. **Short ride**: repeat 3–5, get out after 30 m → nothing happens (below 100 m); **driver 1**:
   `/fin` → settled for 50 + 4 = 54 €$.
9. **Unpaid**: empty client 2's wallet first (`/money`, then `/pay 1 <amount>` leaving less
   than 50 €$), ride again ≥ 100 m → client `... you're short on eddies. Delamain logged the
   debt, choom.`, driver `... couldn't pay (not enough cash). Ride logged unpaid, no cut this
   time.`; the row has `paid = 0`.
10. **Cancel paths**: client `/delamain` then `/delamain annuler` → `Call cancelled.`, the
    driver's pin disappears. Driver `/accepter` then `/delamain annuler` → `You dropped ride
    #N.`; with no other driver the client reads `Your driver is gone and no other Delamain driver
    is on duty. Type /taxi ...`. Driver `/service` (clock out) mid-call → same hand-back.
11. From another resource: `print(exports.rp_delamain:call(2, nil))` → `3` (or `nil no_driver`),
    `print(exports.rp_delamain:activeRide(2).phase)` → `waiting`.
