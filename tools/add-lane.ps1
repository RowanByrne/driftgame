# Creates lane N: a git worktree at <Game>\lanes\laneN with relative links, served by Lync on the
# port base + N (docs\workflow\LANES.md "Add a lane").
# Usage: powershell -ExecutionPolicy Bypass -File tools\add-lane.ps1 2
param([Parameter(Mandatory)][ValidateRange(1, 19)][int]$Number)

$repo = Split-Path $PSScriptRoot -Parent
$game = Split-Path $repo -Parent
$path = Join-Path $game "lanes\lane$Number"
$base = [int](Get-Content (Join-Path $repo 'default.project.json') -Raw | ConvertFrom-Json).port
$port = $base + $Number

if (Test-Path $path) { Write-Host "lane$Number already exists at $path"; exit 1 }

git -C $repo fetch origin
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
git -C $repo worktree add --relative-paths --detach $path origin/main
if ($LASTEXITCODE -ne 0) { Write-Host "git worktree add failed (relative lane links need Git 2.48 or newer)."; exit $LASTEXITCODE }
[IO.File]::WriteAllText((Join-Path $path '.lane-port'), "$port")

# The game's code from PROJECT.md, for the place file names (left as <CODE> until it's filled in).
$code = '<CODE>'
$match = Select-String -Path (Join-Path $repo 'docs\game\PROJECT.md') -Pattern '^\| Code \| `([^`]+)`' | Select-Object -First 1
if ($match -and $match.Matches[0].Groups[1].Value -notmatch '\{\{') { $code = $match.Matches[0].Groups[1].Value }

Write-Host ""
Write-Host "lane$Number ready: $path (port $port)"
Write-Host "Next (docs\workflow\LANES.md ""Add a lane""):"
Write-Host "  1. Copy places\$code-Main.rbxl to places\$code-Lane$Number.rbxl and open it in Studio."
Write-Host "  2. In its command bar: workspace:SetAttribute(`"__lync_port`", $port), then set the worker test profile, then save."
Write-Host "  3. Update docs\game\PROJECT.md (Lanes, Workstations), start Lync for the lane, and probe it."
