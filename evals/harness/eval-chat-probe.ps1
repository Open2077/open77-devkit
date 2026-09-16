#requires -Version 7.0
# Probe of the two-client chat path: launches A and B, sends an harmless
# command from each, alternating, N times, and counts on the server how many
# arrived. Stops both clients at the end. Used to prove the input path before
# trusting the gate script's verdicts.
param([int] $Rounds = 3)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
function Keys([int] $ProcId, [string[]] $keys, [int] $hold = 80) { & (Join-Path $root 'scripts/game-input.ps1') -ProcessId $ProcId -Keys $keys -HoldMilliseconds $hold -DelayMilliseconds 70 | Out-Null }
function Chat([int] $ProcId, [string[]] $keys) { Keys $ProcId @('t') 120; Start-Sleep -Milliseconds 900; Keys $ProcId ($keys + 'enter'); Start-Sleep -Seconds 3 }
$pids = @()
try {
    & (Join-Path $root 'scripts/agent-play.ps1') up -DevLocal -TimeoutSeconds 240 | Out-Null
    $a = (Get-Process Cyberpunk2077 | Sort-Object StartTime | Select-Object -Last 1).Id; $pids += $a
    & (Join-Path $root 'scripts/agent-play.ps1') connect -DevLocal -Endpoint 127.0.0.1:11798 -ProcessId $a -TimeoutSeconds 300 | Select-Object -Last 1
    & (Join-Path $root 'scripts/launch-extra-client.ps1') -IdentityProfile 'eval-b' -PlayerName 'evalb' | Out-Null
    Start-Sleep -Seconds 20
    $b = (Get-Process Cyberpunk2077 | Where-Object Id -ne $a | Sort-Object StartTime | Select-Object -Last 1).Id; $pids += $b
    & (Join-Path $root 'scripts/agent-play.ps1') connect -DevLocal -Endpoint 127.0.0.1:11798 -ProcessId $b -TimeoutSeconds 300 | Select-Object -Last 1
    $log = Join-Path $env:TEMP 'op77-eval-server.log'
    $before = (Get-Content $log | Measure-Object -Line).Lines
    # `arena.mark` is a harmless restricted sub-command that the server logs on execution.
    for ($i = 1; $i -le $Rounds; $i++) {
        Chat $a @('slash','a','r','e','n','a','space','m','a','r','k')
        Chat $b @('slash','a','r','e','n','a','space','m','a','r','k')
    }
    Start-Sleep -Seconds 3
    $landed = (Get-Content $log | Select-Object -Skip $before | Select-String "executed 'arena mark'").Count
    Write-Host "chat probe: $landed of $($Rounds * 2) sends reached the server"
}
finally {
    foreach ($p in $pids) { & (Join-Path $root 'scripts/agent-play.ps1') down -StopGame -ProcessId $p | Out-Null }
}
