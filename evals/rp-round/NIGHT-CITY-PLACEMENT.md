# Night City placement — the RP server moves off the eval plateau onto the real map (2026-09-18)

The owner's verdict on the delivered round: "why no real props, no real map location, it looks like AI slop".
Every RP point of interest leaves the Badlands test plateau (x 340–460 / y −2350..−2410) and goes to a
REAL Night City location. Coordinates below are measured, not guessed — sources noted. The hub is
**Watson**: Kabuki Market (walked, flat, 14 known spots) with the Afterlife, Lizzie's, Viktor's clinic and
Megabuilding H10 a few hundred metres away, all in one streamed district. The Badlands keep the nomads and
the junkyard; Westbrook keeps the dealership; the NCPD building is in the city centre (cops drive).

## Hard rules for this wave
- Edit only the resources assigned to you. Keep every command, export, event, table and README section name.
- Positions live in `shared/config.lua` (or `config.lua`) — change the numbers and the labels/descriptions,
  never the code paths, except where noted (props, doors). Labels are ENGLISH, cyberpunk, and name the REAL
  place ("The Afterlife", "Kabuki Market — Noodle Row", "Vik's clinic", "Megabuilding H10"), never
  "Placeholder", "eval", "plaza" or "test".
- `z` values: use the measured value + 0.1 for rings. For a ring on a walked point use that point exactly.
- Every POI that stands in the open world gets **real props** through `Open77.props.create` on the server
  (permission `world.props`; `Open77.props.remove` on stop; store the ids; bucket 0) using mesh depot
  paths from `C:\Games\cyberm\op77-eval-server\wiki\data\catalogues\props.json` (8 143 records; a raw
  `.mesh` path works: `{ kind = "prop", model = "<path>", position = {x,y,z}, yaw = <deg> }` — read
  `C:\Games\cyberm\op77-eval-server\wiki\props.md` §"Creating" for the exact field names before writing).
  Choose meshes that read as the thing: `device_data_terminal_*` for a bank/ATM terminal or a job board,
  `signage_garage_shop` / `entropy_shutter_door_*` for a garage, cargo crates for nomads, medical
  `surgical_chair_*` only if the clinic lacks one (it does not), market/food meshes for stalls, holograms
  and neon frames for shop signs, barriers/cones for the mechanic. One to three props per POI, no clutter.
  Position props 0.6–1.5 m off the prompt ring so the ring stays readable. A prop create that fails must
  only log (never stop the resource).
- Remove every "plateau"/"Badlands Plaza"/"eval" wording from READMEs and comments; update the README
  "Where things are" tables and the 2-minute test path with the new places and distances.
- Validate + lint after editing (see REVIEW-BRIEF.md in this folder for the exact commands).

## Measured points (world metres; source in brackets)
Spawn / hub (freeroam spawn is moved here by the coordinator):
- Kabuki Market Centre   -1191.30, 2006.88, 7.82   [cordon watson.lua, walked, hot]
- Kabuki — The Crossing  -1218.65, 2022.93, 7.82   [walked]
- Kabuki — Noodle Row    -1178.66, 2028.45, 7.95   [walked]
- Kabuki — East Row      -1160.50, 2019.06, 7.76   [walked]
- Kabuki — The Stalls    -1223.91, 1989.45, 7.98   [walked]
- Kabuki — Vendor Lane   -1212.26, 1978.53, 7.98   [walked]
- Kabuki — North Stalls  -1220.14, 2048.27, 7.82   [walked]
- Kabuki — The Arch      -1192.75, 2072.84, 7.82   [walked]
- Kabuki — The Gallery   -1173.12, 2087.44, 11.94  [walked, elevated]
- Kabuki — Lower Walkway -1201.07, 2035.60, 5.60   [walked, under the market]
- Kabuki — South Gate    -1218.13, 1950.17, 7.98   [walked; the market's street side — vehicles here]
- Kabuki — West Approach -1247.27, 1973.84, 7.97   [walked; street side]
- Kabuki — Far Corner    -1149.22, 2054.84, 7.76   [walked]
Landmarks:
- The Afterlife (bar floor, inside)        -1453.0, 1016.7, 16.5  yaw -138.5 [AMM; walked by cordon at -1455.07,1010.98,17.82]
- The Afterlife — bar counter              -1451.5, 1012.5, 17.8  [bot stood at the counter's end 2026-09-18]
- The Afterlife — meeting room (Rogue)     -1436.8,  977.0, 16.9  yaw 83 [AMM]
- The Afterlife — safe area (back room)    -1419.9,  989.4, 16.5  [AMM]
- Lizzie's Bar (Mox)                        -1188.9, 1566.2, 22.9  yaw -94.4 [AMM]
- Ripperdoc — Viktor's clinic (chair room) -1548.0, 1230.0, 11.5  yaw -89.5 [AMM; bot verified inside 2026-09-18]
- V's Apartment (Megabuilding H10, floor)  -1391.9, 1271.7, 123.1 yaw -99.3 [AMM]
- Megabuilding H10 — gym                   -1420.9, 1320.4, 119.1 [AMM]
- Judy's Apartment (Kabuki)                -906.3, 1868.7,  42.4  [AMM]
- Northside Apartment                      -1503.8, 2224.9, 22.2  [AMM]
- Japantown Apartment                      -785.3,  992.6,  12.0  [AMM]
- Glen Apartment (Heywood)                 -1524.0, -992.6,  9.1  [AMM]
- No-Tell Motel (Kabuki)                   -1202.2, 1333.2, 20.0  [AMM]
- Ho-Oh Club (Kabuki)                      -1043.6, 1354.3,  5.3  [AMM]
- NCPD building — conference room          -1761.5, -1010.8, 94.3 yaw 90.7 [AMM] (real NCPD interior, city centre)
- Junkyard (Rancho Coronado, Badlands edge) 1374.9, -1674.9, 49.3 yaw -173 [AMM]
- Aldecaldos camp (V's nomad tent)          1792.9, 2248.9, 180.2 yaw 58.6 [AMM]
- Drive-In Theater (Badlands)              -81.2, 1963.3, 100.7  [AMM]
- Vehicle dealership (Westbrook)            -1442.2, 127.4, 18.0  [freeroam goto list, driven]
- Westbrook race grid                       -1450.2, 119.9, 14.8  [freeroam, driven]
- Lower Watson junction (street)            -644.91, 1019.37, 36.56 [freeroam, driven]
- North promenade (Watson)                  -469.47, 930.99, 56.45 [freeroam]
Ground truth: `groundz <playerId> <x> <y>` (rp_taxitest, console) answers the top surface under a point
within 80 m of a connected player — it lies under overhangs (rooftops), so trust the walked/AMM points.
`Open77.world.nearby` is NOT usable on this build (part layout unproven): do not bind prompts to device
classes; place rings/props at the coordinates above.

## Assignment
### Group W1 — world & civic: rp_zones, rp_bank, rp_jobs, rp_admin, rp_ambiance, rp_vigile, rp_gangs, rp_crime, rp_netrunner, rp_trauma, rp_ncpd
- rp_zones: replace the plateau zones by: `kabuki_market` (safe, centre Market Centre, r 70), `kabuki`
  (district, centre -1200,1900,10, r 420, maxHeight 200), `afterlife` (bar, -1453,1017,16.5 r 25),
  `lizzies` (bar, r 18), `h10` (residential, V's apartment r 45), `viktor_clinic` (clinic, r 12),
  `ncpd_hq` (ncpd, r 30), `junkyard` (industrial, r 90), `nomad_camp` (r 120), `westbrook_dealer`
  (r 40), `badlands` (centre 1800,-400,100, r 2600, maxHeight 900 — everything east of the city).
  Keep the kinds/flags every consumer relies on (safe zone = kabuki_market; "no NCPD coverage" = badlands).
- rp_bank: ATMs = spawned `device_data_terminal` props + ring + E prompt at: Market Centre (+3 m east),
  Kabuki South Gate, Noodle Row, The Afterlife floor near the entrance stairs (-1447,1022,16.6), Viktor's
  alley = inside the clinic entrance (-1545,1233,11.6). Labels "ATM — Kabuki Market" etc.
- rp_jobs agency: The Gallery (Kabuki, elevated). rp_admin `Spawn` = Market Centre. rp_ambiance figurant
  zones/centres = kabuki_market, afterlife, lizzies, junkyard (use the new zone names). rp_vigile guard
  zones = afterlife, lizzies, kabuki_market. rp_gangs territories = kabuki_market (buyer at Far Corner),
  lizzies (buyer inside at -1185,1568,23), junkyard (buyer 1370,-1670,49.4), afterlife (no buyer); default
  holders: none. rp_crime: shops list must match rp_shops' new vendor positions (read rp_shops config —
  do NOT edit rp_shops; if its numbers are not there yet, reference the same points from this file), fence
  Vik moves to the Junkyard (1381,-1668,49.4, open 22:00–06:00). rp_netrunner breach point = Afterlife safe
  area terminal (spawn a `device_data_terminal` there). rp_trauma: hospital respawn = Viktor's chair room
  (-1546,1231,11.6, the lore's "you wake up at Vik's"), AV landing/dispatch = Kabuki South Gate, bill
  unchanged. rp_ncpd: HQ/cell/desk = NCPD building conference room (-1761.5,-1010.8,94.3; cell 6 m east,
  desk 4 m north), also a Kabuki street outpost ring at West Approach for patrols (radio/status only).
### Group W2 — jobs: rp_bar, rp_fixer, rp_ripperdoc, rp_mecano, rp_ferrailleur, rp_nomade, rp_delamain
- rp_bar: counter = The Afterlife bar counter (-1451.5,1012.5,17.8, r 3.5); second bar Lizzie's (-1188.9,
  1566.2,22.9) if the config supports several counters, else Afterlife only. No spawned counter props
  (the bar exists); a neon sign prop is fine.
- rp_fixer: the board = Afterlife meeting room (-1436.8,977,16.9), a `device_data_terminal` prop at the
  booth; gig objectives use Kabuki points, Lizzie's, the junkyard, the H10 floor.
- rp_ripperdoc: chair = Viktor's clinic (-1548,1230,11.5, r 4) — no chair prop (the clinic has one).
- rp_mecano: workshop = Kabuki West Approach (-1247.3,1973.8,8.0) with a `signage_garage_shop` prop and
  two cones/barriers; fuel pump ring 6 m along the street; impound/tow yard = Junkyard (1370,-1680,49.3).
- rp_ferrailleur: wrecks + dealer = Junkyard (wreck points within 40 m of 1374.9,-1674.9,49.3, dealer at
  1368,-1676,49.4). Zone name `junkyard`.
- rp_nomade: camp/board/truck bay = Aldecaldos camp (board 1790,2252,180.3; truck spawn 1800,2240,180.2
  facing the road); delivery targets = Junkyard, Kabuki South Gate, Drive-In Theater; ambush point on the
  road between camp and junkyard (pick ~1600,600,z from `groundz` at replay time — leave a config comment).
- rp_delamain: pickup/dropoff presets = Kabuki South Gate, The Afterlife lot (-1440,1035,22.7 from the
  South Approach probe), dealership, Lizzie's; fare table unchanged.
### Group W3 — world: rp_garage, rp_shops, rp_housing (rp_inventory is owned by another agent — do not touch)
- rp_garage: public garage ring = Kabuki South Gate (-1218.1,1950.2,8.0), bays along the street x −1226..
  −1210 at y 1946 facing north (yaw 0); society (mecano) garage = West Approach; dealership ring =
  Westbrook dealership (-1442.2,127.4,18.0), showroom spawn = race grid (-1450.2,119.9,14.8); impound =
  Junkyard. Props: `signage_garage_shop` at the public garage, a holo/neon frame at the dealership.
- rp_shops: five real market stalls: supermarket "Noodle Row" (-1178.7,2028.5,7.95), pharmacy "The
  Stalls" (-1223.9,1989.5,7.98), clothes "Vendor Lane" (-1212.3,1978.5,7.98), weapons "East Row"
  (-1160.5,2019.1,7.76), black market "Lower Walkway" (-1201.1,2035.6,5.6). Vendor NPCs stand 1.2 m
  behind the ring facing it; one market/food/sign prop per stall (`mixed_fast_food_*`, neon frames,
  vending_machine cage for the pharmacy).
- rp_housing: five REAL apartments — V's Apartment / Megabuilding H10 (interior -1391.9,1271.7,123.1,
  entrance = the flat's own front door: at start call `exports.open77_doors:near(position, 6)` from the
  interior point, take the nearest discovered door as `doorId`, put the entrance ring 1.5 m outside it
  (door position + 1.5 m along the door's facing if reported, else +1.5 m x) — implement this "auto door"
  once, guarded by pcall and a 60 s retry, keep the static fallback = interior + 3 m), Judy's Apartment,
  Northside Apartment, Japantown Apartment, Glen Apartment (same mechanism). Prices scale with the place
  (H10 studio 25k, Northside 9k, Japantown 40k, Judy's 30k, Glen 15k). Agency = Kabuki The Crossing.
