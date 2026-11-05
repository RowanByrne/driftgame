<#
.SYNOPSIS
  Measures the content anchors a piece of art leaves for native content (docs/workflow/UI.md "Lay out from the art's
  measured anchors"): its socket (the largest enclosed transparent hole) and the body band a plate covers.

.DESCRIPTION
  All anchors are given in px of the file and as fractions of the visible rect (alpha >= 8, 1 px margin),
  which is what ImageRectOffset/ImageRectSize show at runtime, so a registry can store them with the
  variant and the layout can place a portrait in the socket and bars inside the band at any size.
  - socket: the largest region with alpha < -HoleAlpha that doesn't touch the file's border.
  - band: the median first and last row with alpha >= -BodyAlpha over the columns from -BandFrom to
    -BandTo (fractions of the visible width; default: right of the socket to 92%).
  - inner: for an outline frame, the median row where the top rim ends and the bottom rim starts over
    the same columns: the clear band content sits in (null when the plate is solid).
  Measure the decoded upload too (ART-PIPELINE.md "Images", step 5): Roblox rescales, but fractions survive a uniform rescale.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ui\measure-anchors.ps1 set\card-controlled-v1.png -Json
#>
param(
	[Parameter(Mandatory = $true, Position = 0)][string[]]$Path,
	[int]$HoleAlpha = 64,
	[int]$BodyAlpha = 160,
	[int]$MinHole = 400,
	[double]$BandFrom = -1,
	[double]$BandTo = 0.92,
	[switch]$Json
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\RobloxUiTools.ps1"

function Round4([double]$v) { [Math]::Round($v, 4) }
$rows = foreach ($file in (Expand-RuiPaths $Path)) {
	$bmp = [RobloxUi.ImageOps]::Load($file)
	try {
		$vis = [RobloxUi.ImageOps]::AlphaBounds($bmp, 8, 1)
		$holes = [RobloxUi.ImageOps]::EnclosedHoles($bmp, $HoleAlpha, $MinHole)
		$socket = $null
		if ($holes.Count -gt 0) {
			$hh = $holes[0]
			$socket = [ordered]@{
				px = "$($hh[0]),$($hh[1]) $($hh[2])x$($hh[3])"
				center = @((Round4 (($hh[0] + $hh[2] / 2 - $vis.X) / $vis.W)), (Round4 (($hh[1] + $hh[3] / 2 - $vis.Y) / $vis.H)))
				size = @((Round4 ($hh[2] / $vis.W)), (Round4 ($hh[3] / $vis.H)))
				roundness = Round4 ([Math]::Min($hh[2], $hh[3]) / [Math]::Max($hh[2], $hh[3]))
			}
		}
		$from = if ($BandFrom -ge 0) { $BandFrom } elseif ($socket) { (($holes[0][0] + $holes[0][2] - $vis.X) / $vis.W) + 0.05 } else { 0.1 }
		$x0 = [int]($vis.X + $vis.W * $from); $x1 = [int]($vis.X + $vis.W * $BandTo)
		$band = [RobloxUi.ImageOps]::BodyBand($bmp, $x0, $x1, $BodyAlpha)
		$inner = [RobloxUi.ImageOps]::InnerBand($bmp, $x0, $x1, $BodyAlpha)
		[pscustomobject]@{
			file    = Split-Path $file -Leaf
			visible = "$($vis.X),$($vis.Y) $($vis.W)x$($vis.H)"
			aspect  = Round4 $vis.Aspect
			socket  = $socket
			band    = if ($band[0] -lt 0) { $null } else { [ordered]@{ px = "$($band[0])..$($band[1])"; top = (Round4 (($band[0] - $vis.Y) / $vis.H)); bottom = (Round4 (($band[1] - $vis.Y) / $vis.H)); from = (Round4 $from); to = $BandTo } }
			inner   = if ($inner[0] -lt 0) { $null } else { [ordered]@{ px = "$($inner[0])..$($inner[1])"; top = (Round4 (($inner[0] - $vis.Y) / $vis.H)); bottom = (Round4 (($inner[1] - $vis.Y) / $vis.H)) } }
			holes   = $holes.Count
		}
	} finally { $bmp.Dispose() }
}
if ($Json) { $rows | ConvertTo-Json -Depth 5 } else { $rows | Format-List | Out-String -Width 200 }
