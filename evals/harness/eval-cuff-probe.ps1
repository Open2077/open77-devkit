#requires -Version 7.0
# Probe of the cuff freeze only: two clients, A cuffs B, then B's movement lock
# state, Warden's frozen flag and B's position are read before and after B
# pushes forward. Prints raw facts; stops both clients at the end.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
function Keys([int] $ProcId, [string[]] $keys, [int] $hold = 80) { & (Join-Path $root 'scripts/game-input.ps1') -ProcessId $ProcId -Keys $keys -HoldMilliseconds $hold -DelayMilliseconds 70 | Out-Null }
function Bridge([int] $ProcId, [string] $cmd) { (& (Join-Path $root 'scripts/debug-bridge.ps1') -ProcessId $ProcId -Command $cmd | Select-Object -Last 1) }
function Warden() {
    $sess = Get-Content (Join-Path $env:USERPROFILE '.open77\mcp\warden\127.0.0.1_11800.json') | ConvertFrom-Json
    Invoke-RestMethod -Uri 'http://127.0.0.1:11800/api/players' -Headers @{ cookie = $sess.cookie; origin = 'http://127.0.0.1:11800' }
}
$pids = @()
try {
    & (Join-Path $root 'scripts/agent-play.ps1') up -DevLocal -TimeoutSeconds 240 | Out-Null
    $a = (Get-Process Cyberpunk2077 | Sort-Object StartTime | Select-Object -Last 1).Id; $pids += $a
    & (Join-Path $root 'scripts/agent-play.ps1') connect -DevLocal -Endpoint 127.0.0.1:11798 -ProcessId $a -TimeoutSeconds 300 | Out-Null
    & (Join-Path $root 'scripts/launch-extra-client.ps1') -IdentityProfile 'eval-b' -PlayerName 'evalb' | Out-Null
    Start-Sleep -Seconds 20
    $b = (Get-Process Cyberpunk2077 | Where-Object Id -ne $a | Sort-Object StartTime | Select-Object -Last 1).Id; $pids += $b
    & (Join-Path $root 'scripts/agent-play.ps1') connect -DevLocal -Endpoint 127.0.0.1:11798 -ProcessId $b -TimeoutSeconds 300 | Out-Null
    $players = Warden
    $idA = ($players | Where-Object name -ne 'evalb' | Select-Object -First 1).playerId
    $idB = ($players | Where-Object name -eq 'evalb' | Select-Object -First 1).playerId
    $sess = Get-Content (Join-Path $env:USERPROFILE '.open77\mcp\warden\127.0.0.1_11800.json') | ConvertFrom-Json
    $ident = ($players | Where-Object playerId -eq $idA).identifier
    Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:11800/api/acl/identities/$ident" -Headers @{ cookie = $sess.cookie; origin = 'http://127.0.0.1:11800' } -ContentType 'application/json' -Body (@{ permissions = @('command.cuff', 'command.escort') } | ConvertTo-Json) | Out-Null
    "A=$idA B=$idB"
    "spawn gap   : " + (Bridge $a 'position') + " | " + (Bridge $b 'position')
    # Both take freeroam's /goto arena, as the gate does when the spawns are apart.
    Keys $a @('t') 120; Start-Sleep -Milliseconds 900; Keys $a @('slash','g','o','t','o','space','a','r','e','n','a','enter'); Start-Sleep -Seconds 4
    Keys $b @('t') 120; Start-Sleep -Milliseconds 900; Keys $b @('slash','g','o','t','o','space','a','r','e','n','a','enter'); Start-Sleep -Seconds 10
    "after goto  : " + (Bridge $a 'position') + " | " + (Bridge $b 'position')
    "before cuff : lock=" + (Bridge $b 'movement.lock.state') + " | warden frozen=" + ((Warden | Where-Object playerId -eq $idB).frozen) + " | pos " + (Bridge $b 'position')
    Keys $a @('t') 120; Start-Sleep -Milliseconds 900
    Keys $a (@('slash','c','u','f','f','space') + ([string]$idB).ToCharArray() + 'enter'); Start-Sleep -Seconds 5
    "after cuff  : lock=" + (Bridge $b 'movement.lock.state') + " | warden frozen=" + ((Warden | Where-Object playerId -eq $idB).frozen) + " | pos " + (Bridge $b 'position')
    "char.state B: " + (Bridge $b 'char.state')
    Keys $b @('forward') 1500; Start-Sleep -Milliseconds 800
    "after walk  : lock=" + (Bridge $b 'movement.lock.state') + " | warden frozen=" + ((Warden | Where-Object playerId -eq $idB).frozen) + " | pos " + (Bridge $b 'position')
    # Release and cuff again: does a second cuff after the teleport hold?
    Keys $a @('t') 120; Start-Sleep -Milliseconds 900
    Keys $a (@('slash','c','u','f','f','space') + ([string]$idB).ToCharArray() + 'enter'); Start-Sleep -Seconds 4
    Keys $a @('t') 120; Start-Sleep -Milliseconds 900
    Keys $a (@('slash','c','u','f','f','space') + ([string]$idB).ToCharArray() + 'enter'); Start-Sleep -Seconds 5
    "after 2nd   : lock=" + (Bridge $b 'movement.lock.state') + " | warden frozen=" + ((Warden | Where-Object playerId -eq $idB).frozen) + " | pos " + (Bridge $b 'position')
    "char.state B: " + (Bridge $b 'char.state')
    Keys $b @('forward') 1500; Start-Sleep -Milliseconds 800
    "after walk2 : lock=" + (Bridge $b 'movement.lock.state') + " | warden frozen=" + ((Warden | Where-Object playerId -eq $idB).frozen) + " | pos " + (Bridge $b 'position')
    & (Join-Path $root 'scripts/agent-play.ps1') screenshot -ProcessId $b -OutFile (Join-Path $env:TEMP 'cuff-probe-b.png') | Out-Null
    & (Join-Path $root 'scripts/agent-play.ps1') screenshot -ProcessId $a -OutFile (Join-Path $env:TEMP 'cuff-probe-a.png') | Out-Null
}
finally {
    foreach ($p in $pids) { & (Join-Path $root 'scripts/agent-play.ps1') down -StopGame -ProcessId $p | Out-Null }
}
