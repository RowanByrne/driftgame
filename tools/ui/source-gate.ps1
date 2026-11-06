<#
.SYNOPSIS
  Disk side of the source gate: hashes changed .luau/.lua files and prints SourceGate.luau with CONFIG
  filled in, ready to run with execute_luau in the Edit datamodel (docs/workflow/TESTING.md "Every playtest").

.DESCRIPTION
  Hash: LF-normalised UTF-8 bytes (BOM dropped), h = (h * 31 + byte) mod 2^32, starting at 0, the same
  formula SourceGate.luau uses on Studio's .Source. Instance paths come from the Rojo/Lync project file
  ($path entries under "tree"); Foo.server.luau / Foo.client.luau become Foo, init.luau names its folder.
  Default files: every .luau/.lua changed against git HEAD in -Root (staged, unstaged and untracked).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ui\source-gate.ps1 -Root C:\dev\mygame -Out $env:TEMP\gate.luau
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\ui\source-gate.ps1 -Root . -Files src\StarterPlayerScripts\UI\Theme.luau -Table
#>
param(
	[string]$Root = '.',
	[string[]]$Files,
	[string]$Project = 'default.project.json',
	[string]$Out,
	[switch]$NoCompile,
	[switch]$Table
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\RobloxUiTools.ps1"

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$projPath = if ([IO.Path]::IsPathRooted($Project)) { $Project } else { Join-Path $rootPath $Project }
if (-not (Test-Path $projPath)) { throw "Project file not found: $projPath" }
$proj = Get-Content $projPath -Raw | ConvertFrom-Json

# Map each "$path" directory (relative to the project file) to its instance path.
$mounts = New-Object System.Collections.Generic.List[object]
function Walk($node, [string[]]$names) {
	foreach ($p in $node.PSObject.Properties) {
		if ($p.Name -eq '$path') {
			$dir = [IO.Path]::GetFullPath((Join-Path (Split-Path $projPath -Parent) $p.Value))
			$mounts.Add([pscustomobject]@{ dir = $dir.TrimEnd('\'); names = $names })
		} elseif (-not $p.Name.StartsWith('$') -and $p.Value -is [pscustomobject]) {
			Walk $p.Value ($names + $p.Name)
		}
	}
}
Walk $proj.tree @()

function InstancePath([string]$full) {
	$best = $mounts | Where-Object { $full.StartsWith($_.dir + '\', [StringComparison]::OrdinalIgnoreCase) } |
		Sort-Object { $_.dir.Length } -Descending | Select-Object -First 1
	if (-not $best) { return $null }
	$parts = @($full.Substring($best.dir.Length + 1) -split '\\')
	$leaf = $parts[-1] -replace '\.(luau|lua)$', '' -replace '\.(server|client)$', ''
	$parts = if ($leaf -eq 'init') { @($parts | Select-Object -SkipLast 1) } else { @($parts | Select-Object -SkipLast 1) + $leaf }
	return @($best.names) + $parts
}

if ($Files) { $Files = Split-RuiList $Files }
if (-not $Files) {
	Push-Location $rootPath
	# git writes harmless warnings (LF/CRLF) to stderr; under 'Stop' Windows PowerShell turns those into
	# terminating errors, so relax it for the git calls only.
	$eap = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	try {
		$changed = @(git -c core.safecrlf=false diff --name-only HEAD 2>$null) + @(git ls-files --others --exclude-standard 2>$null)
	} finally { $ErrorActionPreference = $eap; Pop-Location }
	$changed = @($changed | Where-Object { $_ -is [string] })
	$Files = $changed | Where-Object { $_ -match '\.(luau|lua)$' } | Sort-Object -Unique
	if (-not $Files) { Write-Output 'source-gate: no changed .luau/.lua files against HEAD; pass -Files to check specific ones.'; return }
}

$rows = foreach ($f in $Files) {
	$full = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($f)) { $f } else { Join-Path $rootPath $f }))
	if (-not (Test-Path -LiteralPath $full)) { Write-Warning "skipped (deleted or missing): $f"; continue }
	$bytes = [RobloxUi.SourceHash]::Normalise([IO.File]::ReadAllBytes($full))
	$ipath = InstancePath $full
	if (-not $ipath) { Write-Warning "not under any `$path in $(Split-Path $projPath -Leaf): $f"; continue }
	[pscustomobject]@{
		file  = ($full.Substring($rootPath.Length).TrimStart('\') -replace '\\', '/')
		path  = $ipath
		bytes = $bytes.Length
		hash  = [RobloxUi.SourceHash]::Hash($bytes)
	}
}

if ($Table) {
	$rows | Select-Object file, @{ n = 'instance'; e = { $_.path -join '.' } }, bytes, hash | Format-Table -AutoSize | Out-String -Width 220
	return
}

function LuaStr([string]$s) { '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }
$entries = foreach ($r in $rows) {
	"`t`t{ file = $(LuaStr $r.file), path = { $(($r.path | ForEach-Object { LuaStr $_ }) -join ', ') }, bytes = $($r.bytes), hash = $($r.hash) },"
}
$config = @(
	'-- CONFIG BEGIN',
	'local CONFIG = {',
	"`tcompile = $(if ($NoCompile) { 'false' } else { 'true' }),",
	"`tmodules = {"
) + $entries + @("`t},", '}', '-- CONFIG END')

$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SourceGate.luau'))
$pattern = '(?s)-- CONFIG BEGIN.*?-- CONFIG END'
$script = [regex]::Replace($template, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($m) $config -join "`n" })
if ($Out) {
	[IO.File]::WriteAllText([IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location).Path $Out })), $script, (New-Object System.Text.UTF8Encoding $false))
	Write-Output "source-gate: $(@($rows).Count) module(s) -> $Out (run it with execute_luau in the Edit datamodel)"
} else {
	$script
}
