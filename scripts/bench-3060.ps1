# Runs speed setups one after another, each for -Minutes, and closes each run by itself. Nothing to do
# meanwhile: the runtime presses Enter by itself in the menu (VICTORY_KEYS, diagnostics build: -Keys) so the
# game continues the last save, and the character stands still. Compare the logs afterwards
# (%LOCALAPPDATA%\victory\logs\nvidia-<date>.log, each with its settings at the top).
#   scripts\bench-3060.ps1 -Exe <path of your own copy's executable> [-Minutes 6] [-Set 2]
# -Set 1: -Classic, -Classic -SixCores, the default (the A/B of 26/11)
# -Set 2: the default, the default at render scale 0.4 (432p), the default with up to 16 submissions joined
# -Set 3: the default (16 joined, 540p), the default at 432p, 432p with up to 24 submissions joined
# -Set 4: the default, the refresh filter on several threads (VICTORY_FILTER_WIDE, since removed: no gain), that at 432p
# -Set 6: the diag build, the perf build, the perf build with 5 refresh threads (VICTORY_WIDE_THREADS)
# -Set 7: the default with the texture side's timers, and the default with 5 refresh threads (round 6's third run did not reach the world)
# -Set 8: the default with timers per kind of list call, and the default with 4 list threads (VICTORY_THIN_THREADS)
# -Set 9: the default with timers inside binding and indirect executions, and 4 list threads again
# -Set 10: the default (4 list threads now) with timers inside the descriptor tables, twice
# -Set 5: the default twice (how much runs differ) and at 432p, with the timers of the big refresh flushes
# -Keys  the keys and when (seconds after input starts); '' for none
param(
    [Parameter(Mandatory)][string]$Exe,
    [int]$Minutes = 6,
    [ValidateSet(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)][int]$Set = 10,
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
    3 {
        # Round 2's two gains together (432p: 15.0 fps; 16 joined, now the default: better lows), and joining
        # further (24 submissions, 144 lists).
        @{ Name = 'default (16 joined, 540p)'; Args = @{}; More = @{} },
        @{ Name = 'default at 432p'; Args = @{ Resolution = '432' }; More = @{} },
        @{ Name = '432p, 24 submissions joined'; Args = @{ Resolution = '432' }; More = @{ VICTORY_JOIN_PARTS = '24'; VICTORY_JOIN_LISTS = '144' } }
    }
    4 {
        # A code change: the refreshes known to copy nothing were told one after another on the submitting
        # thread, the wall (11 ms of refreshes a frame); VICTORY_FILTER_WIDE tells them on the kept threads.
        @{ Name = 'default'; Args = @{}; More = @{} },
        @{ Name = 'default + VICTORY_FILTER_WIDE'; Args = @{}; More = @{ VICTORY_FILTER_WIDE = '1' } },
        @{ Name = '432p + VICTORY_FILTER_WIDE'; Args = @{ Resolution = '432' }; More = @{ VICTORY_FILTER_WIDE = '1' } }
    }
    5 {
        # Timers inside the flushes of over 256 refreshes (the frame line): where the 11 ms of refreshes go.
        @{ Name = 'default'; Args = @{}; More = @{} },
        @{ Name = 'default at 432p'; Args = @{ Resolution = '432' }; More = @{} },
        @{ Name = 'default again'; Args = @{}; More = @{} }
    }
    6 {
        # Judge by the preparing thread's ms a frame and the refreshes' ms (the frame line), not fps alone:
        # the same setup gave 13.8, 14.1 and 15.2 fps in three runs.
        # Also: the skip list is a set now (it was 1,034 hashes compared one by one for every draw), and the
        # perf build (no diagnostics, fat LTO, -C target-cpu=znver3) runs with the skip list.
        @{ Name = 'diag build'; Args = @{}; More = @{} },
        @{ Name = 'perf build'; Args = @{ Build = 'perf' }; More = @{} },
        @{ Name = 'perf build, 5 refresh threads'; Args = @{ Build = 'perf' }; More = @{ VICTORY_WIDE_THREADS = '5' } }
    }
    7 {
        # Timers inside the texture side of the heap pass (2-15 ms a frame in the world, 40 at a scene's start;
        # the line "the texture side per frame"): which part to move off the frame's thread. Also the 5 refresh
        # threads again, on the diag build (round 6's run stopped before the world).
        @{ Name = 'default, texture timers'; Args = @{}; More = @{} },
        @{ Name = 'default, 5 refresh threads'; Args = @{}; More = @{ VICTORY_WIDE_THREADS = '5' } }
    }
    8 {
        # Round 7: the texture side is ~10 ms a frame in small parts; translating the title's list calls is
        # ~200 ms of processor time a frame (8 us a call) on the list threads. Timers per kind of call (the line
        # "list calls translated per frame, by kind"), and one list thread fewer on the six cores.
        @{ Name = 'default, timers per kind of call'; Args = @{}; More = @{} },
        @{ Name = 'default, 4 list threads'; Args = @{}; More = @{ VICTORY_THIN_THREADS = '4' } }
    }
    9 {
        # Round 8: indirect executions are ~60% of translating the list calls (4,000 a frame, 31 us each),
        # dispatches 31 us each too: timers inside binding and indirect executions (the line "binding per
        # frame"). And 4 list threads once more (round 8: 14.0 against 13.7 fps, within the noise).
        @{ Name = 'default, timers inside binding'; Args = @{}; More = @{} },
        @{ Name = 'default, 4 list threads'; Args = @{}; More = @{ VICTORY_THIN_THREADS = '4' } }
    }
    10 {
        # Round 9: the descriptor tables are 124 of the 155 ms a frame of binding (all threads). Timers inside
        # them (the line "descriptor tables per frame"); the default is 4 list threads now. Twice: the same
        # setup, for the spread.
        @{ Name = 'default (4 list threads), timers inside the tables'; Args = @{}; More = @{} },
        @{ Name = 'the same again'; Args = @{}; More = @{} }
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
