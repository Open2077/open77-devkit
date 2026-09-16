#requires -Version 7.0
# One-client probe of the taxi eval: the world map is opened and a waypoint
# placed with the vanilla right-click gesture, /taxi asks for the ride, and the proof is the resource's own server lines
# ("driving to", then "arrived") plus the body's position at the end.
param([int] $MouseDx = 30, [int] $MouseDy = -15, [int] $WaitSeconds = 240)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$ServerLog = Join-Path $env:TEMP 'op77-eval-server.log'
function Keys([int] $ProcId, [string[]] $keys, [int] $hold = 80) { & (Join-Path $root 'scripts/game-input.ps1') -ProcessId $ProcId -Keys $keys -HoldMilliseconds $hold -DelayMilliseconds 90 | Out-Null }
function Bridge([int] $ProcId, [string] $cmd) { (& (Join-Path $root 'scripts/debug-bridge.ps1') -ProcessId $ProcId -Command $cmd | Select-Object -Last 1) }
function Shot([int] $ProcId, [string] $name) { & (Join-Path $root 'scripts/agent-play.ps1') screenshot -ProcessId $ProcId -OutFile (Join-Path $root "evals-shots/$name.png") | Out-Null }
function Pos([int] $ProcId) {
    $line = Bridge $ProcId 'position'
    if ($line -match 'x=(-?[\d.]+) y=(-?[\d.]+) z=(-?[\d.]+)') { return @([double]$matches[1], [double]$matches[2], [double]$matches[3]) }
    throw "no position from $ProcId : $line"
}
function Dist($a, $b) { [math]::Sqrt(($a[0]-$b[0])*($a[0]-$b[0]) + ($a[1]-$b[1])*($a[1]-$b[1])) }
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
function ChatUnverified([int] $ProcId, [string[]] $keys) { Keys $ProcId @('t') 120; Start-Sleep -Milliseconds 900; Keys $ProcId ($keys + 'enter'); Start-Sleep -Seconds 3 }
# F7 (harness hotkey) prints `eval_harness: map open=<bool>`; a map left open
# on the passenger's client keeps the vehicle at 0 km/h.
function MapClosed([int] $ProcId, [string] $log) {
    $mark = (Get-Content $log | Measure-Object -Line).Lines
    Keys $ProcId @('f7') 120; Start-Sleep -Milliseconds 1500
    $line = Get-Content $log | Select-Object -Skip $mark | Select-String -SimpleMatch 'eval_harness: map open=' | Select-Object -Last 1
    if (-not $line) { return $false }
    return ($line.Line -match 'map open=false')
}
function WardenPlayers() {
    $sess = Get-Content (Join-Path $env:USERPROFILE '.open77\mcp\warden\127.0.0.1_11800.json') | ConvertFrom-Json
    Invoke-RestMethod -Uri 'http://127.0.0.1:11800/api/players' -Headers @{ cookie = $sess.cookie; origin = 'http://127.0.0.1:11800' }
}
if (Get-Process Cyberpunk2077 -ErrorAction SilentlyContinue) { throw 'a Cyberpunk2077 process is running; the window is not free' }
New-Item -ItemType Directory -Force (Join-Path $root 'evals-shots') | Out-Null
$result = $false
$a = 0
try {
    & (Join-Path $root 'scripts/agent-play.ps1') up -DevLocal -TimeoutSeconds 240 | Out-Null
    $a = (Get-Process Cyberpunk2077 | Sort-Object StartTime | Select-Object -Last 1).Id
    & (Join-Path $root 'scripts/agent-play.ps1') connect -DevLocal -Endpoint 127.0.0.1:11798 -ProcessId $a -TimeoutSeconds 300 | Select-Object -Last 1
    $idA = (WardenPlayers | Select-Object -First 1).playerId
    Write-Host "[  OK  ] player A=$idA (pid $a)"
    Start-Sleep -Seconds 6
    # The vehicle-AI guide's one locally validated Hella route starts at
    # 430,-2370,182 (next to the arena spawn, on the road) and runs east; the
    # arena plaza itself left the AI driver "blocked" and a city street left it
    # idle (measured). Start the ride from the validated point.
    Chat $a $idA 'tpc 430 -2370 182' @('slash','t','p','c','space','4','3','0','space','kpminus','2','3','7','0','space','1','8','2') | Out-Null
    Start-Sleep -Seconds 10
    $st0 = Bridge $a 'char.state'
    if ($st0 -notmatch 'alive=yes') { throw "player not alive after /tpc: $st0" }
    $p0 = Pos $a
    Write-Host "[  OK  ] pickup at $($p0[0].ToString('0.#', [System.Globalization.CultureInfo]::InvariantCulture)),$($p0[1].ToString('0.#', [System.Globalization.CultureInfo]::InvariantCulture))"

    # The taxi reads only the USER waypoint: a pin placed on the vanilla world
    # map, classified by its CustomPositionVariant, which resource-placed pins
    # never are. The harness opens the map in PICK mode (Open77.map.pickPoint):
    # a left click then tracks exactly that pin and the map adapter closes the
    # map itself, which matters because a hub menu left open on the passenger's
    # client (the vehicle's authority) keeps the taxi at 0 km/h.
    $clientLog = Get-ChildItem 'C:\Games\Cyberpunk 2077\red4ext\logs\open77-*.log' | Sort-Object LastWriteTime | Select-Object -Last 1
    ChatUnverified $a @('slash','w','p','p','i','c','k')
    Start-Sleep -Seconds 3
    Shot $a 'taxi-map-open'
    & (Join-Path $root 'scripts/game-input.ps1') -ProcessId $a -MouseMoveX $MouseDx -MouseMoveY $MouseDy | Out-Null
    Start-Sleep -Milliseconds 600
    & (Join-Path $root 'scripts/game-input.ps1') -ProcessId $a -Click right | Out-Null
    Start-Sleep -Seconds 3
    Shot $a 'taxi-map-waypoint'
    $picked = Select-String -Path $clientLog.FullName -Pattern 'eval_harness: (pick|point picked)' | Select-Object -Last 2
    foreach ($l in $picked) { Write-Host "[  OK  ] $($l.Line -replace '^.*\[Open77\] ', '')" }
    if (MapClosed $a $clientLog.FullName) { Write-Host '[  OK  ] world map closed' } else { Write-Host '[ FAIL ] world map still open before /taxi' }
    Start-Sleep -Seconds 3
    $before = (Get-Content $ServerLog | Measure-Object -Line).Lines
    # /taxi is a client command: verified by the client's own print, resent once.
    $sent = $null
    for ($try = 1; $try -le 2 -and -not $sent; $try++) {
        $mark = (Get-Content $clientLog.FullName | Measure-Object -Line).Lines
        ChatUnverified $a @('slash','t','a','x','i')
        $sent = Get-Content $clientLog.FullName | Select-Object -Skip $mark | Select-String -SimpleMatch '[eval_taxi] /taxi'
        if (-not $sent) { Keys $a @('esc') 80; Start-Sleep -Milliseconds 700; Keys $a @('esc') 80; Start-Sleep -Milliseconds 700 }
    }
    if ($sent) { Write-Host "[  OK  ] $($sent[0].Line -replace '^.*\[Open77\] ', '')" } else { Write-Host '[ FAIL ] /taxi never reached the client command (two tries)' }
    Start-Sleep -Seconds 8
    Shot $a 'taxi-boarding'
    $st = Bridge $a 'char.state'
    Write-Host "[ .... ] after /taxi: " + ($st -replace '^OK ', '').Substring(0, 60)
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $lines = @()
    while ((Get-Date) -lt $deadline) {
        $lines = Get-Content $ServerLog | Select-Object -Skip $before | Select-String -SimpleMatch '[eval_taxi]'
        if ($lines | Where-Object { $_.Line -match 'arrived|failed|cancelled|refused' }) { break }
        Start-Sleep -Seconds 5
    }
    foreach ($l in $lines) { Write-Host "         $($l.Line -replace '^.*\[resource:eval_taxi\] ', '')" }
    Shot $a 'taxi-end'
    $p1 = Pos $a
    $moved = Dist $p0 $p1
    $drive = $lines | Where-Object { $_.Line -match 'driving to (-?[\d.]+),(-?[\d.]+),' } | Select-Object -First 1
    $toDest = -1
    if ($drive -and $drive.Line -match 'driving to (-?[\d.]+),(-?[\d.]+),') {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $toDest = Dist $p1 @([double]::Parse($matches[1], $inv), [double]::Parse($matches[2], $inv), 0)
    }
    $arrived = [bool]($lines | Where-Object { $_.Line -match 'arrived' })
    $result = $arrived -and $toDest -ge 0 -and $toDest -lt 15
    Write-Host ("[ {0} ] taxi: moved {1:0.0} m from the pickup, ends {2:0.0} m from the destination, arrived={3}" -f ($(if ($result) { ' OK ' } else { 'FAIL' })), $moved, $toDest, $arrived)
}
finally {
    if ($a) { & (Join-Path $root 'scripts/agent-play.ps1') down -StopGame -ProcessId $a | Out-Null }
}
Write-Host ''
Write-Host ("taxi     {0}" -f $(if ($result) { 'PASS' } else { 'FAIL' }))
