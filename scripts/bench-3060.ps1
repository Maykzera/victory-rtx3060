# Runs the three speed setups one after another, each for -Minutes, and closes each run by itself:
#   1. -Classic (the RTX 5070 settings)   2. -Classic -SixCores   3. the default (six cores + small buffers on the card)
# In each run: pick Continue in the menu, then leave the character standing still (same place every run).
# Each run keeps its log in %LOCALAPPDATA%\victory\logs\nvidia-<date>.log; compare them afterwards.
#   scripts\bench-3060.ps1 -Exe <path of your own copy's executable> [-Minutes 6]
param(
    [Parameter(Mandatory)][string]$Exe,
    [int]$Minutes = 6
)
$play = Join-Path $PSScriptRoot 'play-nvidia.ps1'
$runs = @(
    @{ Name = 'Classic'; Args = @{ Classic = $true } },
    @{ Name = 'Classic + SixCores'; Args = @{ Classic = $true; SixCores = $true } },
    @{ Name = 'default'; Args = @{} }
)
$i = 0
foreach ($run in $runs) {
    $i++
    Write-Host ""
    Write-Host "=== run $i of 3: $($run.Name), $Minutes minutes. Pick Continue, then leave the character still. ==="
    $a = $run.Args
    $job = Start-Job -ScriptBlock {
        param($play, $exe, $a)
        & $play -Exe $exe @a
    } -ArgumentList $play, $Exe, $a
    $deadline = (Get-Date).AddMinutes($Minutes)
    while ((Get-Date) -lt $deadline -and $job.State -eq 'Running') { Start-Sleep -Seconds 5 }
    # The runtime runs as victory_sm.exe (Smooth Motion copy) or victory.exe.
    Get-Process victory_sm, victory -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Wait-Job $job -Timeout 60 | Out-Null
    Receive-Job $job -ErrorAction SilentlyContinue | Select-String -Pattern 'log saved:' | ForEach-Object { Write-Host $_ }
    Remove-Job $job -Force
    Start-Sleep -Seconds 10
}
Write-Host ""
Write-Host "Done: three logs in $(Join-Path $env:LOCALAPPDATA 'victory\logs') (nvidia-*.log)."
