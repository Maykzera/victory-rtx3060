# "NVIDIA Compatibility" profile: starts the title with the switch set this fork
# was measured with on an NVIDIA RTX 4070 12 GB / 32 GB RAM (diagnostics/README.md),
# and writes the whole log to a file.
#
#   scripts\play-nvidia.ps1 -Exe <path of your own copy's executable>
#
# -Console      SeriesX (default, as tested) or SeriesS (the title asks for less memory)
# -RayTracing   the title's ray-traced passes through the BVH builder (experimental; off)
# -Plain        the build's defaults only (no speed switches): the first thing to try
#               when something is wrong
# -Build        diag (default: the build with frame checks and stage logs), release, or perf
#               (scripts/build-perf.ps1: release with LTO for this processor; frame pacing still logged)
# -More         other settings: -More @{VICTORY_GFX_WATCH='2'}
# -Force        run even if no NVIDIA card is found (the switches are not vendor-only)
# -Warmup       a run to fill the pipeline caches: ten pipeline workers instead of six,
#               for sitting in a scene until "being made" falls to 0. Slower to play.
# -Ambient      the stand-in for the ray-traced indirect light (crates/victory-gpu/src/ambient.rs,
#               from VIctory-7900XTX): a share of the estimate, 0.8 by default; 0 turns it off;
#               'constant:0.3' is a flat level. Lights what the sun does not reach.
# -NoFast       leave out the newest copy savings (on by default; see below)
# -MoreTextures textures may fill up to 94 % of the card's budget instead of 90 %: on a
#               12 GB card the layer let 119,000 texture copies go and made 39,000 again in
#               one session (late, blurry, wrong textures). NOT RECOMMENDED on 12 GB: run
#               2026-11-26 00:21 reached 10.6 of 11.3 GB and the card hung after 4 minutes
#               in the world (0x887A0006, no fault address).
# -Display      the television the console reports: 4K (default, as before), 1440p or
#               1080p (VICTORY_DISPLAY_MODE). This title IGNORES it: with 1080p it still
#               rendered at 2560x1440 (run 2026-11-26 00:21). Kept for other titles.
# -GpuLoadMs    what the title's own GPU timestamps say a frame took, in ms
#               (VICTORY_GPU_LOAD_MS; 0 = as now, where they say ~0 ms and its dynamic
#               resolution stays at 2560x1440). Above its 33 ms budget the title may lower
#               its render resolution itself, as a console that falls behind does: try 40,
#               then 60 or 80. The log says "the title's render size" whenever it changes.
#
# Works in Windows PowerShell 5.1. Run it from a normal window, not as administrator.
param(
    [Parameter(Mandatory)][string]$Exe,
    [ValidateSet('SeriesX', 'SeriesS')][string]$Console = 'SeriesX',
    [switch]$RayTracing,
    [switch]$Plain,
    [ValidateSet('diag', 'release', 'perf')][string]$Build = 'diag',
    [hashtable]$More = @{},
    [switch]$Force,
    [switch]$Warmup,
    [string]$Ambient = '0.8',
    [switch]$NoFast,
    [switch]$MoreTextures,
    [ValidateSet('4K', '1440p', '1080p')][string]$Display = '4K',
    [ValidateRange(0, 1000)][int]$GpuLoadMs = 0
)

# --- which card ------------------------------------------------------------
$cards = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
$nvidia = $cards | Where-Object { $_.PNPDeviceID -match 'VEN_10DE' -or $_.Name -match 'NVIDIA' } | Select-Object -First 1
foreach ($c in $cards) { Write-Host ("GPU            {0}  (driver {1})" -f $c.Name, $c.DriverVersion) }
if (-not $nvidia -and -not $Force) {
    Write-Host 'No NVIDIA card found. This profile is for NVIDIA; use scripts\play.ps1 elsewhere, or -Force.'
    return
}

# --- the switches ------------------------------------------------------------
# Every one is read in the code with a comment that says what it does; all exist
# in this tree. They are about how the layer copies and submits work, not
# vendor tricks: the NVIDIA-specific handling (32-lane forms of console wave64
# programs, the 1,000,000-view heap cap with clamped indices, 64 KiB constant
# views, 65,535-group indirect dispatches) is chosen in the code from what the
# card reports, whatever is set here.
$settings = @{
    # Stage log and black-window watchdog (crates/victory-gpu/src/gfxwatch.rs).
    VICTORY_GFX_WATCH = '5'
    # Cheap crash tracing: the faulting command if the card is lost.
    VICTORY_D3D12_DRED = 'faults'
}
# Light where the title's rays would have found it (off while the structure builder runs).
if ($Ambient -and $Ambient -ne '0') { $settings.VICTORY_AMBIENT = $Ambient }
if (-not $Plain) {
    $speed = @{
        VICTORY_LEVELS_ON_DEMAND = '1'; VICTORY_ASYNC_SUBMIT = '1'; VICTORY_QUEUE2 = '1'
        VICTORY_INDIRECT_WINDOW = '1'; VICTORY_TEXTURE_NO_WAIT = '1'; VICTORY_MERGE_GAP = '64'
        VICTORY_MERGE_RUNS = '4096'; VICTORY_STAGING_POOL = '0'; VICTORY_COPY_PLAIN = '1'
        VICTORY_JOIN_PARTS = '1'; VICTORY_BACK_OWN_VIEW = '1'; VICTORY_INDIRECT_GATHER = '1'
        VICTORY_CARD_REHASH_RUNS = '1'; VICTORY_CARD_HASH_LEN = '1'
        # Copies of title buffers in the card's memory: 2 GiB of windows, 1.25 GiB of
        # small buffers. Measured on a 12 GB card at 84-92 % of its budget.
        VICTORY_CARD_WINDOWS_MB = '2048'; VICTORY_CARD_BUFFERS_MIN_KB = '64'; VICTORY_CARD_BUFFERS_MB = '1280'
        # Textures shaders write and the CPU reads go back (boats float).
        VICTORY_TEXTURE_BACK = '1'
    }
    foreach ($k in $speed.Keys) { $settings[$k] = $speed[$k] }
    if (-not $NoFast) {
        # The fork's newest savings on the CPU's copying, unit-tested and not yet
        # measured in a game by its author (README "Newest"). On a 6-core CPU the frame
        # is that copying (texture refreshes ~219 ms, copies ~200 MB a frame), so they
        # are on here; -NoFast leaves them out. (Their 'alt' modes each keep their own
        # 20 s clock, started at first use, so they would not turn together: compare
        # two runs instead.)
        $fast = @{
            # Fills under 256 bytes made in place, not by a kernel call (~8,000-12,000 a frame).
            VICTORY_FILLS_PLAIN = '1'
            # A step's copy found by an index, not a lock and a search (20,000-43,000 a frame).
            VICTORY_STEP_INDEX = '1'
            # A refresh of blocks read-only by our hand and unwritten since answered with
            # no lock and no kernel call (from VIctory-7900XTX).
            VICTORY_LIGHT_REFRESH = '1'
            # A block found unmapped is not asked of Windows again until the runtime
            # tells of it (outdoors those questions were 44 ms a frame).
            VICTORY_ABSENT_ONCE = '1'; VICTORY_ABSENT_MS = 'told'
            # Memory brought up to date once per submission, not again by later steps.
            VICTORY_REFRESH_ONCE = '1'
            # The card's hashes of its copies of title buffers with 64 threads a 64 KiB
            # piece instead of one (fork pull request #1014, measured on an RTX 3060:
            # "our send-and-hash lists" were 23-29 ms of the card's frame with one).
            # Here those lists were 28-46 ms while the card was the limit.
            VICTORY_CARD_HASH_WIDE = '1'
            # Upstream's newest, measured there on an RTX 4070 (README, 2026-11-26):
            # the texture pass on a thread of its own (pull request #1007; world frames
            # 6.2-6.7 -> 8.65-9.5 at the boat mission),
            VICTORY_HEAP_WORKER = '1'
            # refreshes spread over threads (8.7-9.4 ms less preparing a frame),
            VICTORY_PARALLEL_REFRESH = '1'
            # flights given more room before they are settled (-11.5 ms preparing),
            VICTORY_SETTLE_ROOM = '1'
            # and a cache of buffer host-copy lookups (pull request #1237; ~14 ms a frame).
            VICTORY_LOOKUP_CACHE = '1'
        }
        foreach ($k in $fast.Keys) { $settings[$k] = $fast[$k] }
    }
    if ($MoreTextures) {
        # (Not by shrinking the card copies of title buffers: with 1 GiB / 768 MiB the
        # title's lists took 235-287 ms of card time a frame against 28-53 ms with the
        # defaults (runs 2026-11-26 00:06 and 2026-11-25 22:51, other scenes, ~2x the
        # draws): buffers left in the PC's memory are read over the bus.)
        # Textures may fill up to 94 % of the card's budget instead of 90 % (the fork's own
        # note: at 90 about a tenth stays unused while thousands of textures wait; 94 gives
        # back ~450 MB). Never past it: there Windows pages the card's memory into the PC's
        # and runs 20 and 24 of the fork ended.
        $settings.VICTORY_TEXTURE_ROOM_PERCENT = '94'
    }
}
if ($RayTracing) { $settings.VICTORY_BVH_BUILDER = '1' }
if ($Display -eq '1440p') { $settings.VICTORY_DISPLAY_MODE = '2560x1440' }
if ($Display -eq '1080p') { $settings.VICTORY_DISPLAY_MODE = '1920x1080' }
if ($GpuLoadMs -gt 0) { $settings.VICTORY_GPU_LOAD_MS = [string]$GpuLoadMs }
if ($Warmup) {
    # Leave two logical processors to the title; the rest compile pipelines.
    $threads = [Environment]::ProcessorCount
    $settings.VICTORY_PIPELINE_WORKERS = [string][math]::Max(2, $threads - 2)
}
foreach ($k in $More.Keys) { $settings[$k] = $More[$k] }

# --- checks --------------------------------------------------------------------
$root = Join-Path $PSScriptRoot '..'
$victory = Join-Path $root "target\$Build\victory.exe"
if (-not (Test-Path $victory)) {
    Write-Host "No $victory. Build it first:"
    Write-Host '  cargo build --locked --profile diag -p victory --features diagnostics'
    return
}
if (-not (Test-Path $Exe)) { Write-Host "No $Exe."; return }
$Exe = (Resolve-Path $Exe).Path
$os = Get-CimInstance Win32_OperatingSystem
$freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$commitFreeGB = [math]::Round($os.FreeVirtualMemory / 1MB, 1)
Write-Host "memory         $freeGB GB of RAM free, $commitFreeGB GB of commit free"
if ($commitFreeGB -lt 30) {
    Write-Host '  warning: the title needs 23-27 GB in play (measured with 32 GB of RAM); close other programs.'
}

# --- log file (outside the source tree, as docs/asset-policy.md asks) -----------
$logs = Join-Path $env:LOCALAPPDATA 'victory\logs'
New-Item -ItemType Directory -Force $logs | Out-Null
$log = Join-Path $logs ('run-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Write-Host "log            $log"

# (Other settings left over in this window go; where your files are stays.)
$paths = 'VICTORY_CONFIG', 'VICTORY_GAME_DIR', 'VICTORY_CACHE_DIR', 'VICTORY_DATA_DIR'
Get-ChildItem Env:VICTORY_* | Where-Object { $_.Name -notin $paths } | ForEach-Object { Remove-Item "Env:$($_.Name)" }
foreach ($k in $settings.Keys) { Set-Item "Env:$k" $settings[$k] }
$consoleArg = if ($Console -eq 'SeriesS') { 'series-s' } else { 'series-x' }

$writer = New-Object System.IO.StreamWriter($log, $false, (New-Object System.Text.UTF8Encoding($false)))
$writer.AutoFlush = $true
$writer.WriteLine("# play-nvidia.ps1 $(Get-Date -Format o)")
foreach ($c in $cards) { $writer.WriteLine("# GPU $($c.Name) driver $($c.DriverVersion)") }
foreach ($k in ($settings.Keys | Sort-Object)) { $writer.WriteLine("# $k=$($settings[$k])") }
$writer.WriteLine("# console $consoleArg")

# Only what matters goes to this window (the file has everything): the stage
# lines, the watchdog, warnings, errors and the frame lines.
$show = 'graphics stage reached|frame pacing|title memory remapping|render size|VICTORY_GPU_LOAD_MS|BLACK WINDOW|stand-in for the indirect light|being made\)|pipeline workers|shaders from the cache|library saved|ERROR|device removed|^build|^bound|^title|^console|missing'
Push-Location $root   # victory.toml is looked for here
try {
    $line = '"{0}" run "{1}" --execute --console {2} 2>&1' -f $victory, $Exe, $consoleArg
    & cmd /c $line | ForEach-Object {
        $writer.WriteLine($_)
        if ($_ -match $show) { Write-Host $_ }
    }
} finally {
    $writer.Close()
    Pop-Location
    Write-Host "log saved: $log"
    Write-Host 'Last graphics stage and watchdog lines:'
    Select-String -Path $log -Pattern 'graphics stage reached|BLACK WINDOW' | Select-Object -Last 12 | ForEach-Object { Write-Host $_.Line }
}
