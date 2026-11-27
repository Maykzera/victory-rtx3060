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
# -Set 11: timers inside the tables made, and the same with the slots' old resources let go in batches
# -Set 12: a made table's descriptors copied in one call (VICTORY_TABLE_COPIES), and the default
# -Set 13: the default (fine timers off now), and with the fine timers on (VICTORY_TIMERS=1)
# -Set 14: a submission's batch kept for the next (VICTORY_BATCH_REUSE=1, off by default after it), and a new one each time
# -Set 15: the title's page mappings on 8 threads (VICTORY_MAP_THREADS=8, VIctory's own default), and on 1 (this fork's)
# -Set 16: page mappings that ask for what the pages show already left alone (VICTORY_ALIAS_SAME, removed after: none were), and the default
# -Set 17: buffers only the card uses left on the card (VICTORY_GPU_ONLY, from Victory-NV-Lite; taken out after: no buffer qualified), and the default
# -Set 18: the title one frame further ahead of the submitting thread (VICTORY_SUBMIT_FRAMES=2, the default after it), and 1
# -Set 19: more helper threads for the submitting thread's work (under 6, refresh 5, records 6; worse: 13.1 against 13.7), and the default
# -Set 20: the card copies' walk over the touched ones only (default now), and over all of them (VICTORY_CARD_TOUCHED=0)
# -Set 21: the title's 174 MB constants heap read by the card in place (VICTORY_INPLACE_CONSTANTS=1, fxceless), and the default
# -Set 22: one short run (use -Minutes 3) saying why the constants heap is not opened, with the in-place census (VICTORY_INPLACE_PROBE=1)
# -Set 23: the constants heap in place with its pages in order (VICTORY_INPLACE_CONSTANTS=1, VICTORY_PORT_CONSTANTS=1), and the default
# -Set 24: set 23 again with the card's fills reading the heap in place (round 23 waited ~30-40 ms a frame for them)
# -Set 5: the default twice (how much runs differ) and at 432p, with the timers of the big refresh flushes
# -Keys  the keys and when (seconds after input starts); '' for none
param(
    [Parameter(Mandatory)][string]$Exe,
    [int]$Minutes = 6,
    [ValidateSet(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24)][int]$Set = 24,
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
    11 {
        # Round 10: of the ~120 ms a frame of descriptor tables, 80-89 ms are the ~7,000 tables made afresh
        # (12 us each). Timers inside them (the line "tables made, inside") and around what slots show; then
        # the resources slots let go queued 256 at a time instead of one lock each (VICTORY_KEEP_BATCH).
        @{ Name = 'default, timers inside the tables made'; Args = @{}; More = @{} },
        @{ Name = 'slots let go in batches'; Args = @{}; More = @{ VICTORY_KEEP_BATCH = '1' } }
    }
    12 {
        # Round 11: the tables made afresh fill ~52,000 slots a frame, ~42,000 of them copied from views the
        # thread made before, one CopyDescriptorsSimple each; the batches of round 11 changed nothing (the
        # keeping is 10-13 ms). Those copies made in one CopyDescriptors a table, then the default.
        @{ Name = 'one copy call a table'; Args = @{}; More = @{ VICTORY_TABLE_COPIES = '1' } },
        @{ Name = 'default'; Args = @{}; More = @{} }
    }
    13 {
        # Profile of 27/11 (scripts/profile-3060.ps1): reading the clock for the fine timers of rounds 7-12 was
        # ~23 % of the list threads' work. They are off by default now; the same with them on, for the price.
        @{ Name = 'default, fine timers off'; Args = @{}; More = @{} },
        @{ Name = 'fine timers on'; Args = @{}; More = @{ VICTORY_TIMERS = '1' } }
    }
    14 {
        # Round 13: the submitting thread holds the frame; ~14 % of it was vectors growing each submission.
        # The submission's batch (refreshes, their index, fills, placed copies) kept with its room for the next,
        # and the card steps' lists made at their size; then a new batch each time, as before.
        @{ Name = 'batch kept for the next submission'; Args = @{}; More = @{ VICTORY_BATCH_REUSE = '1' } },
        @{ Name = 'a new batch each time'; Args = @{}; More = @{} }
    }
    15 {
        # Profile of 27/11: a third of the title's busiest thread is its page mappings (CopyPageMappings ->
        # xmem::map_aliases), mapped one page after the other because the play set asks VICTORY_MAP_THREADS=1.
        # VIctory's own default is 8 (xmem.rs: in a bench one thread mapped 1,500 pages a second, eight 30,000).
        @{ Name = 'page mappings on 8 threads'; Args = @{}; More = @{ VICTORY_MAP_THREADS = '8' } },
        @{ Name = 'page mappings on 1 thread (the play set)'; Args = @{}; More = @{} }
    }
    16 {
        # Round 15: 8 mapping threads 13.1 fps, 1 thread 14.1 (the kernel's lock, as xmem.rs says). Fewer mappings
        # instead: those that ask for the page a view shows already are left alone; both runs count them (the
        # line "page mappings of the GPU's").
        @{ Name = 'mappings that change nothing left alone'; Args = @{}; More = @{ VICTORY_ALIAS_SAME = '1' } },
        @{ Name = 'default'; Args = @{}; More = @{} }
    }
    17 {
        # From s2nrzc4f9d/Victory-NV-Lite (VICTORY_GPU_ONLY_BUFFERS): committed default-heap buffers the title's CPU
        # is not seen at are copied whole once, then not refreshed, compared or copied back. Its README: full buffer
        # copies 42.5 -> 0.2 MB a frame. Look at the picture too: a CPU write it misses would show.
        @{ Name = 'buffers only the card uses left on the card'; Args = @{}; More = @{ VICTORY_GPU_ONLY = '1' } },
        @{ Name = 'default'; Args = @{}; More = @{} }
    }
    18 {
        # Round 17's log: the submitting thread works ~60 ms of each ~64 ms frame, and the title's thread waits
        # ~35 ms a frame at presents for it. With one present more allowed in the line the title records ahead
        # while the thread works, so the thread need not stand idle between frames. Both runs count why parts
        # are not joined (the line "parts not taken along").
        @{ Name = 'title one frame further ahead'; Args = @{}; More = @{ VICTORY_SUBMIT_FRAMES = '2' } },
        @{ Name = 'default'; Args = @{}; More = @{ VICTORY_SUBMIT_FRAMES = '1' } }
    }
    19 {
        # Round 18: the submitting thread works ~60 ms of a ~64 ms frame and is the one limit left, with ~29 % of the
        # processor idle. The pools that help it were cut for six cores when the processor was the crowded part:
        # the title's bytes under flights' writes (UNDER 3 -> 6), the refresh flushes (WIDE 3 -> 5), the heaps'
        # records (VIEW 3 -> 6, which also sizes the views pool).
        @{ Name = 'more helpers for the submitting thread'; Args = @{}; More = @{ VICTORY_UNDER_THREADS = '6'; VICTORY_WIDE_THREADS = '5'; VICTORY_VIEW_THREADS = '6' } },
        @{ Name = 'default'; Args = @{}; More = @{} }
    }
    20 {
        # Profile of 27/11 10:55 (the build of round 19): card_dirty's walk over all ~3,900 copies in the card's memory
        # at every submission was ~5 % of the submitting thread; now only those given something since. Also in this
        # build, for both runs: the three vectors that grew most are made with room. Both count what may write the
        # place of the value waits that cut a frame into parts.
        @{ Name = 'card walk over the touched copies'; Args = @{}; More = @{} },
        @{ Name = 'card walk over all copies'; Args = @{}; More = @{ VICTORY_CARD_TOUCHED = '0' } }
    }
    21 {
        # ~35 ms a frame of the submitting thread keep host copies of title memory up to date (refreshes, the title's
        # bytes under flights' writes, copies in the card's memory, the write watch). fxceless bcc542151: the title's
        # 174 MB constants heap opened as a host heap on a view of ours of its pages, so the card reads the constants
        # where the title writes them and nothing is refreshed, sent, hashed or compared for it. The card's reads of it
        # cross the bus instead. Look at the picture, characters above all (the skinning passes write it).
        @{ Name = 'constants heap in place'; Args = @{}; More = @{ VICTORY_INPLACE_CONSTANTS = '1' } },
        @{ Name = 'default'; Args = @{}; More = @{} }
    }
    22 {
        # Round 21 opened no region: the 182 MB heap at 0x62e0000 was not taken for one run of a section. One run that
        # says why (the line "a big buffer below 4 GiB is not one run"), with the census of what could be opened.
        # Its answer: the heap is 3 views from more than one place (the title maps its pieces out of address order).
        # With VICTORY_PORT_CONSTANTS=1 xmem gives the 32-bit heap's fresh pages their slices in address order.
        @{ Name = 'constants heap, pages in order'; Args = @{}; More = @{ VICTORY_INPLACE_CONSTANTS = '1'; VICTORY_PORT_CONSTANTS = '1'; VICTORY_INPLACE_PROBE = '1' } }
    }
    23 {
        # Run 22 (3 minutes, with the census): the heap opened in place, 174 MB, and for a minute of the world the frame
        # was 44-50 ms (20-23 fps) with 26-31 ms preparing, then ~10 fps at the end (the census at 150 s?). Six minutes
        # each, without the census. Look at the picture in the first run, characters above all.
        @{ Name = 'constants heap in place, pages in order'; Args = @{}; More = @{ VICTORY_INPLACE_CONSTANTS = '1'; VICTORY_PORT_CONSTANTS = '1' } },
        @{ Name = 'default'; Args = @{}; More = @{} }
    }
    24 {
        # Round 23: 20-23 fps for ~1.5 minutes, then ~2 settles a frame (30-40 ms) for fills of constants out of the
        # heap: "not done on the card: no host copy holds all of it". The card's steps now take title memory in place
        # as a source with the switch. Same pair again (the default run of round 23 ended at once: window focus).
        @{ Name = 'constants heap in place, fills on the card'; Args = @{}; More = @{ VICTORY_INPLACE_CONSTANTS = '1'; VICTORY_PORT_CONSTANTS = '1' } },
        @{ Name = 'default'; Args = @{}; More = @{} }
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
