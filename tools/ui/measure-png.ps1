<#
.SYNOPSIS
  Measures PNG masters for the manifest: size, transparency, visible (alpha) rect, visible aspect, SHA-256.

.DESCRIPTION
  The visible rect is the box around pixels with alpha >= -AlphaThreshold (default 8, which ignores the
  faint haze generators leave), grown by -Margin px. Its aspect is what the 20% rule compares against
  (docs/workflow/UI.md "4. Assets"). This measures the SOURCE file: after upload, measure the decoded image again with
  DecodeRects.luau, because Roblox rescales anything over ~1024 px (docs/workflow/ART-PIPELINE.md "Images", step 5).
  With -Aspect, each file is also checked against target aspect +/- 20%.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ui\measure-png.ps1 docs\ui\assets\hud-xp\candidates
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ui\measure-png.ps1 a.png,b.png -Aspect 6.5 -Json
#>
param(
	[Parameter(Mandatory = $true, Position = 0)][string[]]$Path,
	[int]$AlphaThreshold = 8,
	[int]$Margin = 1,
	[double]$Aspect = 0,
	[double]$Limit = 1.20,
	[switch]$Json
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\RobloxUiTools.ps1"

$rows = foreach ($file in (Expand-RuiPaths $Path)) {
	$bmp = [RobloxUi.ImageOps]::Load($file)
	try {
		$b = [RobloxUi.ImageOps]::AlphaBounds($bmp, $AlphaThreshold, $Margin)
		$transparent = [RobloxUi.ImageOps]::HasTransparency($bmp)
	} finally { $bmp.Dispose() }
	$status = ''
	if ($Aspect -gt 0 -and -not $b.Empty) {
		$d = [Math]::Max($b.Aspect / $Aspect, $Aspect / $b.Aspect)
		$status = if ($d -le $Limit) { 'ok' } else { 'off-aspect' }
	}
	[pscustomobject]@{
		file          = Split-Path $file -Leaf
		path          = $file
		sourceSize    = "$($b.ImageW)x$($b.ImageH)"
		transparent   = $transparent
		visibleOffset = if ($b.Empty) { $null } else { "$($b.X),$($b.Y)" }
		visibleSize   = if ($b.Empty) { $null } else { "$($b.W)x$($b.H)" }
		visibleAspect = if ($b.Empty) { $null } else { [Math]::Round($b.Aspect, 3) }
		distortion    = if ($status) { [Math]::Round([Math]::Max($b.Aspect / $Aspect, $Aspect / $b.Aspect), 3) } else { $null }
		aspectCheck   = $status
		sha256        = Get-RuiSha256 $file
	}
}

if ($Json) { $rows | ConvertTo-Json -Depth 3 }
else { $rows | Format-Table file, sourceSize, transparent, visibleOffset, visibleSize, visibleAspect, distortion, aspectCheck -AutoSize | Out-String -Width 200 }
