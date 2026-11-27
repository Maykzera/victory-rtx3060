# One run of the default setup with a sampling profile of the runtime in the open world: the game starts as in
# bench-3060.ps1 (Enter pressed by the runtime, the character stands still), after -Warm minutes it records
# the machine's processor samples for -Seconds with Windows' own recorder (wpr, CPU profile), then the run is
# closed and samply turns the recording into a profile. Windows asks once to let the recorder run elevated (it
# reads the kernel's sampling events). The game's executable is only read, as in every run.
#   scripts\profile-3060.ps1 -Exe <path of your own copy's executable> [-Warm 4] [-Seconds 60]
# The profile: %LOCALAPPDATA%\victory\logs\profile-<date>.json.gz (+ .syms.json), next to the run's log.
param(
    [Parameter(Mandatory)][string]$Exe,
    [double]$Warm = 4,
    [int]$Seconds = 60,
    [string]$Keys = '20:Enter,30:Enter,40:Enter,50:Enter,60:Enter',
    [hashtable]$More = @{}
)
$samply = (Get-Command samply -ErrorAction SilentlyContinue).Source
if (-not $samply) { throw 'samply not found: cargo install --locked samply' }
$play = Join-Path $PSScriptRoot 'play-nvidia.ps1'
$logs = Join-Path $env:LOCALAPPDATA 'victory\logs'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $logs "profile-$stamp.json.gz"
$etl = Join-Path $logs "profile-$stamp.etl"
$m = $More.Clone()
if ($Keys) { $m.VICTORY_KEYS = $Keys }
$a = @{ More = $m }
$job = Start-Job -ScriptBlock {
    param($play, $exe, $a)
    & $play -Exe $exe @a
} -ArgumentList $play, $Exe, $a
Write-Host "Warming up for $Warm minutes..."
$deadline = (Get-Date).AddMinutes($Warm)
while ((Get-Date) -lt $deadline -and $job.State -eq 'Running') { Start-Sleep -Seconds 5 }
# The runtime runs as victory_sm.exe (Smooth Motion copy) or victory.exe.
$proc = Get-Process victory_sm, victory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
    Write-Host "Recording $Seconds s (process $($proc.Id)) to $etl"
    $cmd = "wpr -cancel 2>`$null; wpr -start CPU -filemode; Start-Sleep -Seconds $Seconds; wpr -stop '$etl'"
    Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $cmd
} else {
    Write-Host 'The runtime is not running: nothing recorded.'
}
Get-Process victory_sm, victory -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Wait-Job $job -Timeout 60 | Out-Null
Receive-Job $job -ErrorAction SilentlyContinue | Select-String -Pattern '^log' | ForEach-Object { Write-Host $_ }
Remove-Job $job -Force
if (Test-Path $etl) {
    Write-Host "Turning the recording into $out"
    & $samply import $etl -s --unstable-presymbolicate -o $out
}
Write-Host ""
Write-Host "Done: $out"
