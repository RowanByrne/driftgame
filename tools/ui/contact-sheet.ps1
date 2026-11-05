<#
.SYNOPSIS
  Builds the contact sheet the user picks from: each candidate shown in its real slot at native size,
  then magnified, with its visible aspect checked against the slot (docs/workflow/ART-PIPELINE.md "Images").

.DESCRIPTION
  For every candidate PNG the visible rect (alpha >= -AlphaThreshold) is drawn into a -Slot sized box,
  stretched as the artwork helper does within the 20% limit (or -Fit for icons), over a background:
    -Background + -SlotAt  a game screenshot, with the slot's top-left at that point (best: real context)
    -Background alone      an image scaled to fill each cell (use a tile or panel crop)
    neither                a flat -BackgroundColor
  The 1x composite is the in-game pixels; the 2x/3x panels magnify it with nearest-neighbour so the
  user sees those exact pixels larger, not a smoother re-render. Candidates whose visible aspect is
  more than -Limit away from the slot's are labelled OFF-ASPECT, or left out with -DropOffAspect.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ui\contact-sheet.ps1 docs\ui\assets\hud-ribbon\candidates -Slot 420x64 -Background shots\desktop-1280x720.png -SlotAt 24,80 -Out docs\ui\assets\hud-ribbon\contact-native.png
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ui\contact-sheet.ps1 icons\*.png -Slot 40x40 -Fit -Background tile-56.png -Out contact.png
#>
param(
	[Parameter(Mandatory = $true, Position = 0)][string[]]$Candidates,
	[Parameter(Mandatory = $true)][string]$Slot,
	[Parameter(Mandatory = $true)][string]$Out,
	[string]$Background,
	[object]$SlotAt,
	[string]$BackgroundColor = '#1E1E1E',
	[int]$Context = 24,
	[object[]]$Zoom = @(1, 2, 3),
	[switch]$Fit,
	[double]$Limit = 1.20,
	[switch]$DropOffAspect,
	[int]$AlphaThreshold = 8
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\RobloxUiTools.ps1"

if ($Slot -notmatch '^(\d+)x(\d+)$') { throw "-Slot must look like 420x64" }
$slotW = [int]$Matches[1]; $slotH = [int]$Matches[2]
$slotAspect = $slotW / $slotH
$Zoom = @(Split-RuiList $Zoom | ForEach-Object { [int]$_ })
$at = $null
if ($SlotAt) {
	$xy = Split-RuiList $SlotAt
	if ($xy.Count -ne 2 -or ($xy -join ',') -notmatch '^\d+,\d+$') { throw "-SlotAt must look like 24,80" }
	$at = @([int]$xy[0], [int]$xy[1])
	if (-not $Background) { throw "-SlotAt needs -Background" }
}
$bgColor = ConvertTo-RuiColor $BackgroundColor
$bg = if ($Background) { [RobloxUi.ImageOps]::Load((Resolve-Path $Background).Path) } else { $null }
$compW = $slotW + 2 * $Context
$compH = $slotH + 2 * $Context

function New-Composite($bmp, $b) {
	$comp = New-Object System.Drawing.Bitmap $compW, $compH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$g = [System.Drawing.Graphics]::FromImage($comp)
	try {
		$g.Clear($bgColor)
		if ($bg -and $at) {
			$src = New-Object System.Drawing.Rectangle ($at[0] - $Context), ($at[1] - $Context), $compW, $compH
			$clip = [System.Drawing.Rectangle]::Intersect($src, (New-Object System.Drawing.Rectangle 0, 0, $bg.Width, $bg.Height))
			if ($clip.Width -gt 0 -and $clip.Height -gt 0) {
				$g.DrawImage($bg, (New-Object System.Drawing.Rectangle ($clip.X - $src.X), ($clip.Y - $src.Y), $clip.Width, $clip.Height), $clip, [System.Drawing.GraphicsUnit]::Pixel)
			}
		} elseif ($bg) {
			[RobloxUi.ImageOps]::DrawHq($g, $bg, (New-Object System.Drawing.Rectangle 0, 0, $bg.Width, $bg.Height), (New-Object System.Drawing.RectangleF 0, 0, $compW, $compH))
		}
		if (-not $b.Empty) {
			$dst = New-Object System.Drawing.RectangleF $Context, $Context, $slotW, $slotH
			if ($Fit) {
				$s = [Math]::Min($slotW / $b.W, $slotH / $b.H)
				$w = $b.W * $s; $h = $b.H * $s
				$dst = New-Object System.Drawing.RectangleF ($Context + ($slotW - $w) / 2), ($Context + ($slotH - $h) / 2), $w, $h
			}
			[RobloxUi.ImageOps]::DrawHq($g, $bmp, (New-Object System.Drawing.Rectangle $b.X, $b.Y, $b.W, $b.H), $dst)
		}
	} finally { $g.Dispose() }
	return $comp
}

$letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
$rows = @()
$i = 0
foreach ($file in (Expand-RuiPaths $Candidates)) {
	$id = if ($i -lt 26) { $letters[$i] } else { "$($i + 1)" }
	$i++
	$bmp = [RobloxUi.ImageOps]::Load($file)
	$b = [RobloxUi.ImageOps]::AlphaBounds($bmp, $AlphaThreshold, 0)
	$dist = if ($b.Empty) { [double]::PositiveInfinity } else { [Math]::Max($b.Aspect / $slotAspect, $slotAspect / $b.Aspect) }
	$ok = $Fit -or ($dist -le $Limit + 1e-9)
	$rows += [pscustomobject]@{
		id = "$id"; file = (Split-Path $file -Leaf); path = $file; bmp = $bmp; bounds = $b
		visibleAspect = if ($b.Empty) { $null } else { [Math]::Round($b.Aspect, 3) }
		distortion = if ($b.Empty) { $null } else { [Math]::Round($dist, 3) }
		status = if ($b.Empty) { 'EMPTY' } elseif ($ok) { 'ok' } else { 'OFF-ASPECT' }
		sha256 = Get-RuiSha256 $file
	}
}
if ($rows.Count -eq 0) { throw "No candidate PNGs found in: $($Candidates -join ', ')" }
$shown = if ($DropOffAspect) { @($rows | Where-Object { $_.status -eq 'ok' }) } else { $rows }
if ($shown.Count -eq 0) { throw "Every candidate is off-aspect for slot $Slot; nothing to show." }

$pad = 12; $header = 22
$maxZ = ($Zoom | Measure-Object -Maximum).Maximum
$sheetW = $pad
foreach ($z in $Zoom) { $sheetW += $compW * $z + $pad }
$rowH = $header + $compH * $maxZ + $pad
$sheetH = $pad + $header + $shown.Count * $rowH
$sheet = New-Object System.Drawing.Bitmap ([int]$sheetW), ([int]$sheetH), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$font = New-Object System.Drawing.Font 'Segoe UI', 9
$bold = New-Object System.Drawing.Font 'Segoe UI', 9, ([System.Drawing.FontStyle]::Bold)
$ink = [System.Drawing.Brushes]::Gainsboro
$warn = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 235, 120, 90))
try {
	$g.Clear([System.Drawing.Color]::FromArgb(255, 24, 24, 24))
	$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
	$mode = if ($Fit) { 'Fit' } else { 'Stretch' }
	$g.DrawString("Slot $Slot ($mode, slot aspect $([Math]::Round($slotAspect, 3)), limit $Limit)   zooms: $($Zoom -join 'x, ')x   nearest-neighbour magnification of the 1x pixels", $font, $ink, $pad, $pad)
	$y = $pad + $header
	foreach ($r in $shown) {
		$label = "$($r.id)   $($r.file)   visible aspect $($r.visibleAspect)   distortion $($r.distortion)"
		$g.DrawString($label, $bold, $ink, $pad, $y)
		if ($r.status -ne 'ok') {
			$w = $g.MeasureString($label, $bold).Width
			$g.DrawString("  $($r.status)", $bold, $warn, $pad + $w, $y)
		}
		$comp = New-Composite $r.bmp $r.bounds
		$x = $pad
		foreach ($z in $Zoom) {
			$panel = if ($z -eq 1) { $comp } else { [RobloxUi.ImageOps]::Magnify($comp, $z) }
			$g.DrawImageUnscaled($panel, [int]$x, [int]($y + $header))
			if ($z -ne 1) { $panel.Dispose() }
			$x += $compW * $z + $pad
		}
		$comp.Dispose()
		$y += $rowH
	}
	$outPath = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location).Path $Out }))
	$dir = Split-Path $outPath -Parent
	if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
	$sheet.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
	$g.Dispose(); $sheet.Dispose(); $font.Dispose(); $bold.Dispose(); $warn.Dispose()
	foreach ($r in $rows) { $r.bmp.Dispose() }
	if ($bg) { $bg.Dispose() }
}

Write-Output "contact-sheet: $outPath ($($shown.Count) of $($rows.Count) candidates shown)"
$rows | Select-Object id, file, visibleAspect, distortion, status, sha256 | Format-Table -AutoSize | Out-String -Width 220
