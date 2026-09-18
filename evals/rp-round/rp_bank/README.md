# rp_bank — bank accounts, ATMs and societies

Server-authoritative bank for an Open77 RP server (build `2.31.13+op77.76`). Cash stays in
`rp_economy`; this resource owns the **account** (SQL, keyed by the durable identifier), the
**ledger** (append-only transactions) and the **society** funds (one row per job/company).
Players use it at ATMs placed in the world, or from anywhere with the phone-style commands.

## What the player sees

- A map pin, a ground ring and a floating `ATM` label at every configured ATM (`config.lua`).
  Walk up, look at it, press **E**: the server checks you really stand there and opens the menu.
- The menu (UI kit context menu, server-driven): **Deposit**, **Withdraw**, **Wire to a citizen**,
  **Statement** (last 10 operations), **Leave**. Every answer lands in chat as `NC Bank`.
- Chat lines are English, in eddies (`€$`).

## Commands

| Command | Where | Effect |
|---|---|---|
| `/bank` | within 3 m of an ATM | Opens the same menu as the ATM prompt. Refused elsewhere: `No ATM within 3 m.` |
| `/solde` | anywhere | `Cash: 500 €$ · Account: 1 200 €$` |
| `/virement <playerId> <amount>` | anywhere | Wires `amount` to a **connected** player. Fee **1 %** (at least 1 €$), taken from the sender and burned. Both players are told. |
| `/societe` | anywhere | The society balance of the caller's job (`exports.rp_jobs:getJob`, optional through `pcall`). |

From the server console every command answers `run this from the game`.

Validation is server side, always: positive whole amounts (max 10^9 per operation), enough
cash to deposit, enough account to withdraw or wire, the recipient must exist (a connected
player id, or a citizen id = durable identifier that already has an account), never yourself.
Refusals are explained in chat (`Not enough eddies in the account.`, `Unknown recipient. ...`).

## Persistence

Created inside `Open77.database.ready(...)` with `CREATE TABLE IF NOT EXISTS`, needs the manifest
permission `database.access`:

| Table | Columns |
|---|---|
| `rp_bank_accounts` | `identifier` (PK), `balance`, `created_at` |
| `rp_bank_transactions` | `id` (auto), `identifier`, `delta`, `balance_after`, `kind`, `note`, `at` |
| `rp_bank_societies` | `name` (PK), `balance` |

`kind` is one of `deposit withdraw transfer_out transfer_in fee society_add society_remove`.
Society ledger lines use the identifier `society:<name>`.

Every account and society is cached in memory and written through with the callback forms of
`Open77.database.*` (never `.await` on the export path — a synchronous export that yields fails
with `export_yielded`). The cache is loaded once when the database answers. Two dedicated
servers sharing one database would not see each other's writes: one server per database.

**No database** (`ready` answers `database_unavailable`, or the database is still not answering
15 s after the first player is ready): balances fall back to `Open77.kvp`, the statement is kept
in memory only, and the log says `[rp_bank] store=kvp reason=...`. The choice is made once per
boot.

## Exports (phase 1 contract, synchronous, never yield)

```lua
exports.rp_bank:getAccount(playerId)        -- { identifier, balance, createdAt } | nil, reason
exports.rp_bank:deposit(playerId, amount)   -- newBalance | nil, reason  (cash -> account)
exports.rp_bank:withdraw(playerId, amount)  -- newBalance | nil, reason  (account -> cash)
exports.rp_bank:transfer(fromPlayerId, toIdentifier, amount[, fee])
                                            -- sender's newBalance | nil, reason; fee (optional, >= 0) is burned
exports.rp_bank:society(name)               -- { name, balance } (row created on first use) | nil, reason
exports.rp_bank:societyAdd(name, amount, reason)     -- newBalance | nil, reason
exports.rp_bank:societyRemove(name, amount, reason)  -- newBalance | nil, "insufficient_funds" | reason
exports.rp_bank:charge(playerId, amount, society, reason)
                                            -- account -> society in one move (a fine, a bill, a
                                            -- subscription); the player's newBalance | nil, reason
```

Reasons: `invalid_player_id player_not_found bank_not_ready invalid_amount amount_too_large
insufficient_funds insufficient_cash balance_limit unknown_recipient self_transfer
wallet_unavailable invalid_society invalid_reason`. Society names are lower-cased
(`[A-Za-z0-9_.-]`, 1..64). `playerId` accepts the string form host events deliver.

Call them inside `pcall` from another resource (synchronous exports raise when the resource is
missing). A resource **without** a client script may declare `dependency "rp_bank"`; a resource
with one must not (this manifest is delivered to clients).

### Event

```lua
TriggerEvent("rp_bank:changed", playerId, identifier, newBalance, delta, kind)
-- playerId is nil for an offline recipient and for societies (identifier "society:<name>")
```

## Log (grep-able)

```
[rp_bank] store=sql accounts=12 societies=2
[rp_bank] player 3 loaded <identifier> account=700
[rp_bank] player 3 deposit 500 account=1200
[rp_bank] player 3 withdraw 200 account=1000
[rp_bank] player 3 transfer 100 fee 1 to <identifier> account=899
[rp_bank] player 4 transfer_in 100 from <identifier> account=100
[rp_bank] society police +250 fine:3 balance=250
```

## ATM positions

`config.lua` is a `shared_script`: the client places pins/rings/prompts from `Config.Atms`, the
server checks distance against the same list and spawns one **terminal prop** per ATM
(`Open77.props.create`, `Config.AtmProp.model` = the curated prop alias `street.parking_meter`
(see `prop.catalog`; a raw `.mesh` path renders as a white slab), 1 m off the ring, removed on
stop; a refusal only logs). Five real Night City points,
measured 2026-09-18 — three around the freeroam spawn (Kabuki Market Centre
`-1191.30, 2006.88, 7.82`), two inside landmarks:

| ATM | Ring (x, y, z) | Terminal | Where |
|---|---|---|---|
| `atm_kabuki` — ATM — Kabuki Market | -1188.30, 2006.88, 7.82 | -1187.30, 2007.40 | Market Centre, 3 m east of the spawn |
| `atm_southgate` — ATM — Kabuki South Gate | -1218.13, 1950.17, 7.98 | -1219.10, 1949.60 | the market's street side, 63 m south-west (pedestrian alley) |
| `atm_noodle` — ATM — Noodle Row | -1178.66, 2028.45, 7.95 | -1177.70, 2029.10 | 25 m north-east of the spawn |
| `atm_afterlife` — ATM — The Afterlife | -1447.00, 1022.00, 16.60 | -1446.20, 1022.80 | the bar floor by the entrance stairs, 1.0 km south-west |
| `atm_viktor` — ATM — Vik's Clinic | -1545.00, 1233.00, 11.60 | -1544.20, 1233.80 | just inside the clinic entrance, 855 m south-west |

The ring `z` is the walked / measured floor (+0.1 m for the two interiors); if a ring is
invisible, stand on the spot, run `/pos`, and paste the ground height — a ring drawn inside the
floor is invisible even though everything reports success. The server tolerates 4 m of height
error (`Config.AtmHeightTolerance`). Up to 8 ATMs get a floating label (UI kit cap). The
terminal's `yaw` turns the prop towards its ring; the prop's forward axis was not measured, so
if a machine shows its back, add 180 to `prop.yaw`.

Manifest permissions: `database.access` (SQL), `network.events` (`RegisterNetEvent`,
`TriggerServerEvent`), `ui.vanilla.map` (`Open77.blips.create`), `world.props` (the terminals).
Dependencies: `open77_uikit`, `open77_worldui`. `rp_economy` and `rp_jobs` are reached through
`pcall` (server-only resources).

## Test in 2 minutes

1. Drop `rp_bank` next to `rp_economy` in the resource root, start the server. Log:
   `[rp_bank] started, 5 ATMs configured`, five `terminal prop <id> for atm_... at ...` lines
   (or `terminal prop for atm_... not spawned (<reason>)`: the ring still works), then
   `[rp_bank] store=sql accounts=0 societies=0` (or `store=kvp reason=database_unavailable`
   without a database).
2. Connect. Chat: `NC Bank: Account balance: 0 €$.` Log: `[rp_bank] new account <identifier> balance=0`.
3. `/solde` → `Cash: 500 €$ · Account: 0 €$`.
4. Open the map: five `ATM — ...` pins (three on Kabuki Market, one on the Afterlife, one on
   Vik's). Walk 3 m east from the spawn to the `ATM — Kabuki Market` ring — a data terminal
   stands next to it — look at the ring, press **E** (or type `/bank` within 3 m). The
   `Night City Bank` menu opens.
5. **Deposit eddies** → `300` → chat `Deposited 300 €$. Account: 300 €$.`; `/money` from
   `rp_economy` now says 200. Log: `[rp_bank] player <id> deposit 300 account=300`.
6. **Withdraw eddies** → `1000` → `Not enough eddies in the account.`; `50` → `Withdrew 50 €$.`
7. **Statement** → two rows, newest first, with the balance after each; **Back**.
8. Walk 10 m away, `/bank` → `No ATM within 3 m. Find one on the map.` (Noodle Row's ATM is
   25 m north-east, the South Gate one 63 m south-west; the Afterlife and Vik's are a drive.)
9. Second client (`id2`): `/virement id2 100` → sender `Wired 100 €$ to <name> (fee 1 €$).
   Account: 149 €$.`, recipient `<name> wired you 100 €$. Check /solde.`
   `/virement <self> 10` → refused; `/virement id2 999999` → `Not enough eddies in the account.`
10. At the ATM, **Wire to a citizen** with recipient `id2` (or their citizen id) → no fee.
11. `/societe` with a job from `rp_jobs` → `Society police: 0 €$.`; without → `You have no job, choom.`
12. Reconnect: the balance is back (`[rp_bank] player <id> loaded ... account=...`).
13. From another resource: `print(exports.rp_bank:getAccount(id).balance)`,
    `exports.rp_bank:societyAdd("police", 250, "fine:3")`.
