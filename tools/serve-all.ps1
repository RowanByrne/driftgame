# Starts Lync for the Main place (repo\) and for lane1 to laneK, where K is this PC's row in
# docs\game\PROJECT.md "Workstations" (docs\workflow\LANES.md "How many lanes"). Each starts in its own window.
# Usage: tools\serve-all.bat [dry]
param([string]$Mode = '')
$dry = $Mode -eq 'dry'
$repo = Split-Path $PSScriptRoot -Parent
$lanes = Join-Path (Split-Path $repo -Parent) 'lanes'

# This PC's lane count from the Workstations table, matched on the computer name; $null if it has no row.
function Get-LaneCount {
	$inTable = $false
	foreach ($line in Get-Content (Join-Path $repo 'docs\game\PROJECT.md')) {
		if ($line -match '^##\s+Workstations') { $inTable = $true; continue }
		if ($inTable -and $line -match '^##\s') { break }
		if ($inTable -and $line -match '^\|') {
			$cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim().Trim('`') })
			if ($cells.Count -ge 3 -and $cells[0] -ieq $env:COMPUTERNAME -and $cells[2] -match '\d+') {
				return [int]$Matches[0]
			}
		}
	}
	return $null
}

function Start-Serve([string]$checkout) {
	$bat = Join-Path $checkout 'tools\serve.bat'
	if (-not (Test-Path $bat)) { Write-Warning "No tools\serve.bat in $checkout"; return }
	if ($dry) { Write-Output "would start $bat" }
	else { Start-Process -FilePath $bat -WorkingDirectory $checkout }
}

Start-Serve $repo
$count = Get-LaneCount
if ($null -eq $count) {
	Write-Warning "$env:COMPUTERNAME has no row in docs\game\PROJECT.md ""Workstations"", so only the Main place is served. See docs\workflow\LANES.md ""How many lanes""."
	exit 0
}
for ($n = 1; $n -le $count; $n++) {
	$lane = Join-Path $lanes "lane$n"
	if (Test-Path $lane) { Start-Serve $lane }
	else { Write-Warning "lane$n doesn't exist yet: run tools\add-lane.ps1 $n (docs\workflow\LANES.md ""Add a lane"")" }
}
