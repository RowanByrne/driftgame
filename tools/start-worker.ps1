<#
.SYNOPSIS
  Starts one worker in a lane with Codex or Gemini CLI, in the background (docs\workflow\MODELS.md "Workers by agent").
  Claude Code doesn't use this: its workers are subagents.

.DESCRIPTION
  The conductor writes the task (CONDUCTOR.md "A round", step 3) to a brief file, then runs this once per lane; the
  workers run side by side. Each worker runs non-interactively in its lane's folder with the tier's model, and its
  final message, the report, lands in ..\scratch\workers\laneN-report.md when it finishes. Its full output goes in
  laneN-log.txt beside it. Wait for one with Wait-Process -Id <pid>.

  Workers run without the agent's sandbox: Codex's Windows sandbox can't write the lane's git data (it sits in
  repo\.git, outside the lane), so a sandboxed worker can't commit. Each worker still works only in its own lane,
  under the rules in WORKER.md.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\start-worker.ps1 -Agent codex -Lane 2 -Tier heavy -Brief ..\scratch\workers\lane2-brief.md
#>
param(
	[Parameter(Mandatory = $true)] [ValidateSet('codex', 'gemini')] [string]$Agent,
	[Parameter(Mandatory = $true)] [int]$Lane,
	[Parameter(Mandatory = $true)] [ValidateSet('heavy', 'standard', 'light')] [string]$Tier,
	[Parameter(Mandatory = $true)] [string]$Brief,
	[switch]$DryRun # print what would run, and start nothing
)
$ErrorActionPreference = 'Stop'

# Each tier's model, and Codex's reasoning effort (MODELS.md "Worker models"). Change them there and here together.
$Models = @{
	codex  = @{ heavy = @('gpt-6-astra', 'high'); standard = @('gpt-6.1-sol', 'medium'); light = @('gpt-6.1-terra', 'low') }
	gemini = @{ heavy = @('pro', ''); standard = @('flash', ''); light = @('flash-lite', '') }
}

$repo = Split-Path $PSScriptRoot -Parent
$game = Split-Path $repo -Parent
$laneDir = Join-Path $game "lanes\lane$Lane"
if (-not (Test-Path (Join-Path $laneDir '.git'))) { throw "No lane $Lane at $laneDir (LANES.md)." }
$briefPath = (Resolve-Path $Brief).Path
$out = Join-Path $game 'scratch\workers'
New-Item -ItemType Directory -Force $out | Out-Null
$report = Join-Path $out "lane$Lane-report.md"
$log = Join-Path $out "lane$Lane-log.txt"
Remove-Item -LiteralPath $report, $log -ErrorAction SilentlyContinue
$model, $effort = $Models[$Agent][$Tier]
$q = { param($s) "'" + ("$s" -replace "'", "''") + "'" }

if ($Agent -eq 'codex') {
	$exe = (Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1).Source
	if (-not $exe) {
		$found = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin') -Recurse -Filter codex.exe -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
		if ($found) { $exe = $found.FullName }
	}
	if (-not $exe) { if ($DryRun) { $exe = 'codex' } else { throw 'Codex isn''t installed on this PC.' } }
	# The brief goes in on stdin ("-"); the final message goes to the report. Studio tools are approved up front, since
	# nobody is there to answer, with time for slow Studio calls.
	$run = "Get-Content -LiteralPath $(& $q $briefPath) -Raw | & $(& $q $exe) exec -C $(& $q $laneDir) -m $model -c model_reasoning_effort=$effort " +
		"--dangerously-bypass-approvals-and-sandbox -c mcp_servers.Roblox_Studio.default_tools_approval_mode=approve " +
		"-c mcp_servers.Roblox_Studio.tool_timeout_sec=600 -o $(& $q $report) - 2>&1 | Out-File -Encoding utf8 $(& $q $log)"
} else {
	if (-not $DryRun -and -not (Get-Command gemini -ErrorAction SilentlyContinue)) { throw 'Gemini CLI isn''t installed on this PC.' }
	# Headless: tools that would ask are refused, so yolo approves them; the lane is trusted for its MCP servers. The
	# answer is the "response" field of the JSON output.
	$json = Join-Path $out "lane$Lane-output.json"
	$run = "`$env:GEMINI_CLI_TRUST_WORKSPACE = 'true'`n" +
		"Get-Content -LiteralPath $(& $q $briefPath) -Raw | gemini -m $model --approval-mode=yolo -o json -p 'Follow the brief above.' 2> $(& $q $log) | Out-File -Encoding utf8 $(& $q $json)`n" +
		"try { [IO.File]::WriteAllText($(& $q $report), (Get-Content -LiteralPath $(& $q $json) -Raw | ConvertFrom-Json).response) } catch { }"
}
$text = "Set-Location -LiteralPath $(& $q $laneDir)`n$run`n"

if ($DryRun) { Write-Output $text; return }
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($text))
$process = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded -WindowStyle Hidden -PassThru
Write-Output "Lane $Lane worker started: $Agent, $model$(if ($effort) { " ($effort)" }), process $($process.Id)."
Write-Output "Report when it finishes: $report"
Write-Output "Wait for it: Wait-Process -Id $($process.Id)"
