<#
.SYNOPSIS
  Generates one image with Codex's built-in image generation (imagegen), using the Codex app's
  signed-in account on this PC, and copies the PNG unchanged to -Out.

.DESCRIPTION
  The image tool in docs/workflow/MODELS.md. It hands one prompt to the Codex CLI that ships with
  the Codex desktop app (codex exec, read-only sandbox, no shell or file tools), then picks the new
  PNG out of %USERPROFILE%\.codex\generated_images. Prints the output path, size and SHA-256.
  Log the exact prompt and the hash in the topic's assets\<topic>\MANIFEST.md yourself, and never
  upload a candidate the user hasn't picked (docs/workflow/ART-PIPELINE.md).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\imagegen.ps1 -Prompt "flat painted gold coin, ..." -Out ..\art\generated\hud-currency\coin-01.png -Transparent

.EXAMPLE
  # Edit / restyle from reference images (attached to the Codex prompt):
  powershell -ExecutionPolicy Bypass -File tools\imagegen.ps1 -Prompt "same button, warmer gold rim" -Reference assets\shop-buttons\buy.png -Out ..\art\generated\shop-buttons\buy-02.png
#>
param(
	[Parameter(Mandatory = $true)][string]$Prompt,
	[Parameter(Mandatory = $true)][string]$Out,
	[string[]]$Reference = @(),
	[switch]$Transparent,
	[int]$TimeoutSec = 600
)
$ErrorActionPreference = 'Stop'

function Find-Codex {
	$cmd = Get-Command codex -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	# The Codex desktop app keeps its CLI in a versioned folder; take the newest.
	$bin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
	if (Test-Path $bin) {
		$exe = Get-ChildItem $bin -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
			Sort-Object LastWriteTime -Descending | Select-Object -First 1
		if ($exe) { return $exe.FullName }
	}
	throw 'Codex CLI not found: install the Codex desktop app (or the codex CLI) and sign in.'
}

$codex = Find-Codex
$genRoot = Join-Path $env:USERPROFILE '.codex\generated_images'
$seen = @{}
if (Test-Path $genRoot) {
	Get-ChildItem $genRoot -Recurse -File -Filter *.png | ForEach-Object { $seen[$_.FullName] = $true }
}
$started = (Get-Date).AddSeconds(-2)

# An empty scratch folder as Codex's working root: it has nothing to read or change there.
$work = Join-Path ([IO.Path]::GetTempPath()) ('imagegen-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

$background = if ($Transparent) { 'Use a transparent background (real alpha channel), no backdrop.' } else { '' }
$instruction = @"
Generate exactly one image with your built-in image generation tool. Do not write code, run shell
commands, edit files or use any other tool. Use this as the image prompt, verbatim:

$Prompt

$background
When the image has been generated, reply with the single word DONE.
"@

function Quote([string]$s) { return '"' + ($s -replace '"', '\"') + '"' }
$codexArgs = @('exec', '--skip-git-repo-check', '-s', 'read-only', '-C', (Quote $work), '--color', 'never', '--json')
foreach ($r in $Reference) { $codexArgs += @('-i', (Quote (Resolve-Path $r).Path)) }
$codexArgs += '-' # read the instruction from stdin (no shell quoting of the prompt)

# A plain Process, so stdin is written and then really closed (codex exec waits for EOF).
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $codex
$psi.Arguments = $codexArgs -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
Write-Host "imagegen: asking Codex ($codex) ..."
$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEndAsync()
$stderr = $proc.StandardError.ReadToEndAsync()
$proc.StandardInput.Write($instruction)
$proc.StandardInput.Close()
if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
	$proc.Kill()
	throw "imagegen: Codex did not finish within $TimeoutSec s"
}
$log = $stdout.Result + "`n" + $stderr.Result
$exit = $proc.ExitCode

# Images land in generated_images\<thread id>\ (the thread id is in the JSON events).
$thread = ([regex]::Match($stdout.Result, '"thread_id":"([^"]+)"')).Groups[1].Value
$new = @()
if (Test-Path $genRoot) {
	$new = Get-ChildItem $genRoot -Recurse -File -Filter *.png |
		Where-Object {
			-not $seen.ContainsKey($_.FullName) -and $_.LastWriteTime -ge $started -and
			($thread -eq '' -or $_.DirectoryName -like "*$thread*")
		} |
		Sort-Object LastWriteTime -Descending
}
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
if ($new.Count -eq 0) {
	$tail = ($log -split "`r?`n" | Select-Object -Last 25) -join "`n"
	throw "imagegen: Codex produced no image (exit $exit). Last output:`n$tail"
}
if ($new.Count -gt 1) { Write-Warning "imagegen: Codex made $($new.Count) images; keeping the newest." }

$outPath = if ([IO.Path]::IsPathRooted($Out)) { [IO.Path]::GetFullPath($Out) } else { [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Out)) }
$outDir = Split-Path $outPath -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
Copy-Item $new[0].FullName $outPath -Force

Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($outPath)
$size = "$($img.Width)x$($img.Height)"
$alpha = [System.Drawing.Image]::IsAlphaPixelFormat($img.PixelFormat)
$img.Dispose()
$hash = (Get-FileHash $outPath -Algorithm SHA256).Hash
Write-Output "imagegen: $outPath"
Write-Output "  size=$size alpha=$alpha sha256=$hash source=$($new[0].FullName)"
