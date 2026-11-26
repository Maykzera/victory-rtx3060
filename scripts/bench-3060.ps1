# Runs speed setups one after another, each for -Minutes, and closes each run by itself. Nothing to do
# meanwhile: the runtime presses Enter by itself in the menu (VICTORY_KEYS, diagnostics build: -Keys) so the
# game continues the last save, and the character stands still. Compare the logs afterwards
# (%LOCALAPPDATA%\victory\logs\nvidia-<date>.log, each with its settings at the top).
#   scripts\bench-3060.ps1 -Exe <path of your own copy's executable> [-Minutes 6] [-Set 2]
# -Set 1: -Classic, -Classic -SixCores, the default (the A/B of 26/11)
# -Set 2: the default, the default at render scale 0.4 (432p), the default with up to 16 submissions joined
# -Keys  the keys and when (seconds after input starts); '' for none
param(
    [Parameter(Mandatory)][string]$Exe,
    [int]$Minutes = 6,
    [ValidateSet(1, 2)][int]$Set = 2,
    [string]$Keys = '20:Enter,30:Enter,40:Enter,50:Enter,60:Enter'
)
$play = Join-Path $PSScriptRoot 'play-nvidia.ps1'
$runs = switch ($Set) {
    1 {
        @{ Name = 'Classic'; Args = @{ Classic = $true }; More = @{} },
        @{ Name = 'Classic + SixCores'; Args = @{ Classic = $true; SixCores = $true }; More = @{} },
        @{ Name = 'default'; Args = @{}; More = @{} }
    }
    2 {
        # The preparing thread is the wall (about 55 ms a frame) with the card about 70% busy behind it:
        # Scale 0.4 takes work off the card; joining more submissions (VICTORY_JOIN_PARTS 8 -> 16, lists 48 -> 96)
        # takes per-submission work off the preparing thread.
        @{ Name = 'default'; Args = @{}; More = @{} },
        @{ Name = 'default at render scale 0.4 (432p)'; Args = @{}; More = @{ VICTORY_RENDER_SCALE = '0.4' } },
        @{ Name = 'default, 16 submissions joined'; Args = @{}; More = @{ VICTORY_JOIN_PARTS = '16'; VICTORY_JOIN_LISTS = '96' } }
    }
}
$i = 0
foreach ($run in $runs) {
    $i++
    Write-Host ""
    Write-Host "=== run $i of $($runs.Count): $($run.Name), $Minutes minutes ==="
    $a = $run.Args.Clone()
    $more = $run.More.Clone()
    if ($Keys) { $more.VICTORY_KEYS = $Keys }
    $a.More = $more
    $job = Start-Job -ScriptBlock {
        param($play, $exe, $a)
        & $play -Exe $exe @a
    } -ArgumentList $play, $Exe, $a
    $deadline = (Get-Date).AddMinutes($Minutes)
    while ((Get-Date) -lt $deadline -and $job.State -eq 'Running') { Start-Sleep -Seconds 5 }
    # The runtime runs as victory_sm.exe (Smooth Motion copy) or victory.exe.
    Get-Process victory_sm, victory -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Wait-Job $job -Timeout 60 | Out-Null
    Receive-Job $job -ErrorAction SilentlyContinue | Select-String -Pattern '^log' | ForEach-Object { Write-Host $_ }
    Remove-Job $job -Force
    Start-Sleep -Seconds 10
}
Write-Host ""
Write-Host "Done: logs in $(Join-Path $env:LOCALAPPDATA 'victory\logs') (nvidia-*.log)."
