# Starts a new game from the template: steps 1 to 4 of docs\workflow\NEW-PROJECT.md.
# Run it from the template's repo:
#   powershell -ExecutionPolicy Bypass -File tools\new-project.ps1 -Name MyGame -Code MG -GitHubRepo https://github.com/<owner>/<repo>.git
# -GitHubRepo is the game's new, empty GitHub repo. Without it the game is set up locally and pushed later.
# -PortBase picks the Lync port block; by default the first one no other game in the RoDev folder uses.
param(
	[Parameter(Mandatory)][string]$Name,
	[Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{2,4}$')][string]$Code,
	[string]$GitHubRepo = '',
	[int]$PortBase = 0
)
$ErrorActionPreference = 'Stop'

$templateRepo = Split-Path $PSScriptRoot -Parent
$template = Split-Path $templateRepo -Parent
$roDev = Split-Path $template -Parent
$game = Join-Path $roDev $Name
$repo = Join-Path $game 'repo'

if ($Name -match '[\\/:*?"<>|]') { throw 'The name cannot contain \ / : * ? " < > |' }
if (Test-Path $game) { throw "$game already exists." }

# 1. Update the template.
Write-Host 'Updating the template ...'
git -C $templateRepo pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Could not update the template. Check git status in template\repo, then try again.' }

# 2. Duplicate it. Lanes and Rocco's data are never copied: each belongs to one game.
Write-Host "Copying the template to $game ..."
robocopy $template $game /E /XD (Join-Path $template 'lanes') (Join-Path $template 'rocco') /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copying failed (robocopy exit $LASTEXITCODE)." }
New-Item -ItemType Directory -Force -Path (Join-Path $game 'lanes') | Out-Null

# 3. The game gets its own remote; the template stays reachable as "template".
git -C $repo worktree prune
git -C $repo remote rename origin template
git -C $repo config worktree.useRelativePaths true
git -C $repo config core.hooksPath tools/hooks
if ($GitHubRepo) { git -C $repo remote add origin $GitHubRepo }

# 4. Fill in the game's details.
if ($PortBase -eq 0) {
	$used = @(Get-ChildItem $roDev -Directory | Where-Object { $_.FullName -ne $game -and $_.FullName -ne $template } | ForEach-Object {
		$json = Join-Path $_.FullName 'repo\default.project.json'
		if (Test-Path $json) { [int](Get-Content $json -Raw | ConvertFrom-Json).port }
	})
	$PortBase = 34870
	while ($used -contains $PortBase) { $PortBase += 20 }
}
$repoName = '{{GITHUB_REPO}}'
if ($GitHubRepo -match 'github\.com[:/](.+?)(\.git)?$') { $repoName = $Matches[1] }
elseif ($GitHubRepo) { $repoName = $GitHubRepo }

$utf8 = New-Object System.Text.UTF8Encoding $false
function Update-File([string]$relative, [scriptblock]$change) {
	$path = Join-Path $repo $relative
	[IO.File]::WriteAllText($path, (& $change ([IO.File]::ReadAllText($path))), $utf8)
}
Update-File 'README.md' { param($t) $t.Replace('{{GAME_NAME}}', $Name) }
Update-File 'default.project.json' { param($t) $t.Replace('{{GAME_NAME}}', $Name) -replace '"port":\s*\d+', ('"port": ' + $PortBase) }
Update-File 'docs\game\PROJECT.md' {
	param($t)
	$t = $t.Replace('{{GAME_NAME}}', $Name).Replace('{{CODE}}', $Code).Replace('{{GITHUB_REPO}}', $repoName)
	$t -replace '(\| Lync port base \| `)\d+', ('${1}' + $PortBase)
}

git -C $repo add -A
git -C $repo commit -q -m "Start $Name from the template"
if ($GitHubRepo) {
	git -C $repo push -u origin main
	if ($LASTEXITCODE -ne 0) { Write-Warning 'The push failed. Check the GitHub repo exists and is empty, then in repo\ run: git push -u origin main' }
}

Write-Host ''
Write-Host "$Name is ready at $game"
Write-Host "  Code $Code, Lync port base $PortBase"
if (-not $GitHubRepo) { Write-Host '  No GitHub repo yet: create an empty private one, then in repo\ run: git remote add origin <url>, then git push -u origin main' }
Write-Host 'Next (docs\workflow\NEW-PROJECT.md): open Claude in repo\ and start the Pitch. Places and lanes can wait until'
Write-Host 'Foundation (steps 5 and 6), and the Roblox ids and owner until the experience exists (step 7).'
