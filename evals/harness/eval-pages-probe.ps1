#requires -Version 7.0
# One-client probe of the FiveM port's vehicle menu (the shop page was proven
# separately: F6, Tab, Tab, Enter -> server logged the purchase). The menu (/car spawns one, /cars opens the uikit menu,
# Enter picks the first row -> char.state vehicle=yes). Stops the client at
# the end whatever happened.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$ServerLog = Join-Path $env:TEMP 'op77-eval-server.log'
function Keys([int] $ProcId, [string[]] $keys, [int] $hold = 80) { & (Join-Path $root 'scripts/game-input.ps1') -ProcessId $ProcId -Keys $keys -HoldMilliseconds $hold -DelayMilliseconds 90 | Out-Null }
function Bridge([int] $ProcId, [string] $cmd) { (& (Join-Path $root 'scripts/debug-bridge.ps1') -ProcessId $ProcId -Command $cmd | Select-Object -Last 1) }
function Shot([int] $ProcId, [string] $name) { & (Join-Path $root 'scripts/agent-play.ps1') screenshot -ProcessId $ProcId -OutFile (Join-Path $root "evals-shots/$name.png") | Out-Null }
function Chat([int] $ProcId, [int] $PlayerId, [string] $Command, [string[]] $keys) {
    for ($try = 1; $try -le 2; $try++) {
        $before = (Get-Content $ServerLog | Measure-Object -Line).Lines
        Keys $ProcId @('t') 120; Start-Sleep -Milliseconds 900
        Keys $ProcId ($keys + 'enter'); Start-Sleep -Seconds 4
        if (Get-Content $ServerLog | Select-Object -Skip $before | Select-String -SimpleMatch "Player $PlayerId executed '$Command'") { return $true }
        Keys $ProcId @('esc') 80; Start-Sleep -Milliseconds 700; Keys $ProcId @('esc') 80; Start-Sleep -Milliseconds 700
    }
    Write-Host "[ FAIL ] chat send lost twice: '$Command'"; return $false
}
function WardenPlayers() {
    $sess = Get-Content (Join-Path $env:USERPROFILE '.open77\mcp\warden\127.0.0.1_11800.json') | ConvertFrom-Json
    Invoke-RestMethod -Uri 'http://127.0.0.1:11800/api/players' -Headers @{ cookie = $sess.cookie; origin = 'http://127.0.0.1:11800' }
}
if (Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue) { throw 'a Cyberpunk2077 process is running; the window is not free' }
New-Item -ItemType Directory -Force (Join-Path $root 'evals-shots') | Out-Null
$results = [ordered]@{}
$a = 0
try {
    & (Join-Path $root 'scripts/agent-play.ps1') up -DevLocal -TimeoutSeconds 240 | Out-Null
    $a = (Get-Process Cyberpunk2077 | Sort-Object StartTime | Select-Object -Last 1).Id
    & (Join-Path $root 'scripts/agent-play.ps1') connect -DevLocal -Endpoint 127.0.0.1:11798 -ProcessId $a -TimeoutSeconds 300 | Select-Object -Last 1
    $idA = (WardenPlayers | Select-Object -First 1).playerId
    Write-Host "[  OK  ] player A=$idA (pid $a)"
    Start-Sleep -Seconds 5

    # ---- port: a vehicle to find, then the menu, then the first row.
    Chat $a $idA 'car hella' @('slash','c','a','r','space','h','e','l','l','a') | Out-Null
    Start-Sleep -Seconds 6
    $before = (Get-Content $ServerLog | Measure-Object -Line).Lines
    # /cars is a CLIENT command: the server never logs it, so it is sent once,
    # unverified, and the menu is the proof (screenshot + the pick's effect).
    Keys $a @('t') 120; Start-Sleep -Milliseconds 900
    Keys $a @('slash','c','a','r','s','enter'); Start-Sleep -Seconds 3
    Shot $a 'port-menu'
    Keys $a @('enter') 80; Start-Sleep -Seconds 5
    $st = Bridge $a 'char.state'
    $inVehicle = $st -match 'vehicle=yes'
    Shot $a 'port-after-pick'
    $results.port = $inVehicle
    $refused = Get-Content $ServerLog | Select-Object -Skip $before | Select-String -SimpleMatch "eval_port:"
    if ($inVehicle) { Write-Host "[  OK  ] port: warped into the driver seat (char.state vehicle=yes)" } else { Write-Host "[ FAIL ] port: $st" ; if ($refused) { Write-Host "         $($refused[0].Line)" } }
}
finally {
    if ($a) { & (Join-Path $root 'scripts/agent-play.ps1') down -StopGame -ProcessId $a | Out-Null }
}
Write-Host ''
foreach ($k in $results.Keys) { Write-Host ("{0,-8} {1}" -f $k, ($(if ($results[$k]) { 'PASS' } else { 'FAIL' }))) }
