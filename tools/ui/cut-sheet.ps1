<#
.SYNOPSIS
  Cuts a generated grid sheet (2x2, 3x2 ...) into one PNG per item, losslessly (docs/workflow/ART-PIPELINE.md "Images").

.DESCRIPTION
  Finds the fully transparent lines (every pixel alpha < -AlphaThreshold) nearest each nominal grid
  boundary, rows first across the whole width, then columns inside each row band, and copies each cell's
  pixels unchanged into its own file. No resampling and no colour change; unused transparent canvas
  stays in the file and is removed at runtime with ImageRectOffset/ImageRectSize (ART-PIPELINE.md "Images", step 5).
  If no transparent line exists within -Search px of a boundary, the items touch: the sheet fails and
  should be regenerated, never cut through an item.
  Prints each cell's rect in the sheet, its visible rect and visible aspect, and warns when an item
  touches its cell's edge (it may have been clipped by the generator).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ui\cut-sheet.ps1 -Sheet set\circle-kit-v1.png -Cols 3 -Rows 2 `
    -Names "ring,ring-ultimate,ring-portrait,plate,glow,burst" -OutDir set\layers
#>
param(
	[Parameter(Mandatory = $true)][string]$Sheet,
	[int]$Cols = 2,
	[int]$Rows = 2,
	[Parameter(Mandatory = $true)][string[]]$Names,
	[Parameter(Mandatory = $true)][string]$OutDir,
	[int]$Search = 160,
	[int]$AlphaThreshold = 8,
	[switch]$Json
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\RobloxUiTools.ps1"
$Names = Split-RuiList $Names
if ($Names.Count -ne $Cols * $Rows) { throw "cut-sheet: $($Names.Count) names for a ${Cols}x$Rows grid" }

# The transparent line nearest to nominal (centre of the transparent run that is closest), or -1.
function Find-Gap([int[]]$max, [int]$nominal, [int]$lo, [int]$hi) {
	$best = -1; $bestDist = [int]::MaxValue
	$x = [Math]::Max($lo, $nominal - $Search)
	$end = [Math]::Min($hi, $nominal + $Search)
	while ($x -le $end) {
		if ($max[$x] -lt $AlphaThreshold) {
			$start = $x
			while ($x + 1 -le $end -and $max[$x + 1] -lt $AlphaThreshold) { $x++ }
			$mid = [int][Math]::Floor(($start + $x) / 2)
			$d = [Math]::Abs($mid - $nominal)
			if ($d -lt $bestDist) { $best = $mid; $bestDist = $d }
		}
		$x++
	}
	return $best
}

$bmp = [RobloxUi.ImageOps]::Load((Resolve-Path $Sheet).Path)
try {
	$W = $bmp.Width; $H = $bmp.Height
	$rowMax = [RobloxUi.ImageOps]::LineAlphaMax($bmp, $false, (New-Object System.Drawing.Rectangle 0, 0, $W, $H))
	$ys = @(0)
	for ($r = 1; $r -lt $Rows; $r++) {
		$g = Find-Gap $rowMax ([int]($H * $r / $Rows)) 0 ($H - 1)
		if ($g -lt 0) { throw "cut-sheet: no transparent row near y=$([int]($H * $r / $Rows)): items touch; regenerate the sheet" }
		$ys += $g
	}
	$ys += $H
	if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
	$results = @()
	$i = 0
	for ($r = 0; $r -lt $Rows; $r++) {
		$y0 = $ys[$r]; $y1 = $ys[$r + 1]
		$colMax = [RobloxUi.ImageOps]::LineAlphaMax($bmp, $true, (New-Object System.Drawing.Rectangle 0, $y0, $W, ($y1 - $y0)))
		$xs = @(0)
		for ($c = 1; $c -lt $Cols; $c++) {
			$g = Find-Gap $colMax ([int]($W * $c / $Cols)) 0 ($W - 1)
			if ($g -lt 0) { throw "cut-sheet: no transparent column near x=$([int]($W * $c / $Cols)) in row $($r + 1): items touch; regenerate the sheet" }
			$xs += $g
		}
		$xs += $W
		for ($c = 0; $c -lt $Cols; $c++) {
			$rect = New-Object System.Drawing.Rectangle $xs[$c], $y0, ($xs[$c + 1] - $xs[$c]), ($y1 - $y0)
			$cell = [RobloxUi.ImageOps]::Crop($bmp, $rect)
			try {
				$b = [RobloxUi.ImageOps]::AlphaBounds($cell, $AlphaThreshold, 0)
				$name = $Names[$i]
				$out = Join-Path $OutDir "$name.png"
				$cell.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
				$touch = (-not $b.Empty) -and ($b.X -eq 0 -or $b.Y -eq 0 -or $b.X + $b.W -eq $rect.Width -or $b.Y + $b.H -eq $rect.Height)
				$results += [pscustomobject]@{
					name    = $name
					file    = $out
					cell    = "$($rect.X),$($rect.Y) $($rect.Width)x$($rect.Height)"
					visible = if ($b.Empty) { 'empty' } else { "$($b.X),$($b.Y) $($b.W)x$($b.H)" }
					aspect  = if ($b.Empty) { 0 } else { [Math]::Round($b.Aspect, 3) }
					warning = if ($b.Empty) { 'EMPTY cell' } elseif ($touch) { 'touches cell edge (check for clipping)' } else { '' }
					sha256  = Get-RuiSha256 $out
				}
			} finally { $cell.Dispose() }
			$i++
		}
	}
} finally { $bmp.Dispose() }

if ($Json) { $results | ConvertTo-Json -Depth 3 } else { $results | Select-Object name, cell, visible, aspect, warning | Format-Table -AutoSize | Out-String -Width 200 }
