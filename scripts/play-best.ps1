# The fastest setup measured on the RTX 3060 12 GB + Ryzen 5 5600X (27/11, round 24): play-nvidia.ps1's defaults plus
# the title's 174 MB constants heap read by the card in place (VICTORY_INPLACE_CONSTANTS, after fxceless bcc542151),
# with its pages put in address order so it can be opened (VICTORY_PORT_CONSTANTS, after Victory-NV-Lite 7dc5c48 and
# 0ef93bb), and the constant buffers' fills out of it done on the card.
#   scripts\play-best.ps1 -Exe <path of your own copy's executable> [any play-nvidia.ps1 option]
# Round 24, last 10 s of the open world: 17.2 fps, frame median 56.5 ms, 1% low 9.5 fps (play-nvidia.ps1 alone, rounds
# 18-20: 14.9-16.0 fps, median 61-65 ms). The card is ~93% busy with it (it reads the constants over the bus), so a
# lower -Resolution helps here, which it did not before. The one thing to watch: characters (the skinning passes
# write that heap); if they look wrong, use play-nvidia.ps1.
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(ValueFromRemainingArguments)]$Rest
)
$play = Join-Path $PSScriptRoot 'play-nvidia.ps1'
$best = @{ VICTORY_INPLACE_CONSTANTS = '1'; VICTORY_PORT_CONSTANTS = '1' }
# Other play-nvidia.ps1 options pass through as they are (-SeriesX, -Resolution 432, ...).
$named = @{}
$i = 0
while ($i -lt $Rest.Count) {
    $name = [string]$Rest[$i]
    if ($name.StartsWith('-')) {
        $key = $name.TrimStart('-')
        $next = if ($i + 1 -lt $Rest.Count) { [string]$Rest[$i + 1] } else { $null }
        if ($null -ne $next -and -not $next.StartsWith('-')) { $named[$key] = $next; $i += 2 }
        else { $named[$key] = $true; $i += 1 }
    } else { $i += 1 }
}
& $play -Exe $Exe @named -More $best
