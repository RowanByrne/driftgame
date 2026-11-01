# Starts a game in the RoDev folder: a new one from the template (steps 1 to 4 of docs\workflow\NEW-PROJECT.md), or an
# existing one brought in (NEW-PROJECT.md "An existing game"). Rocco's onboarding runs it; by hand, from the template's repo:
#   powershell -ExecutionPolicy Bypass -File tools\new-project.ps1 -Name MyGame -Code MG -GitHubRepo https://github.com/<owner>/<repo>.git
#   ... -Existing https://github.com/<owner>/<game>.git   the game's own repo, cloned with its history
#   ... -Existing D:\Games\MyGame                         a folder: cloned if it's a git repo, else copied into import\
#   ... -Existing D:\Places\MyGame.rbxl                   a place file: copied into places\ and backups\
#   ... -StudioOnly                                       the game is only in Studio: the agent exports its scripts
# -GitHubRepo is the game's new, empty GitHub repo. Without it the game is set up locally and pushed later.
# -PortBase picks the Lync port block; by default the first one no other game in the RoDev folder uses.
# A game brought in is finished by an agent following docs\workflow\SETUP.md "Existing game".
param(
	[Parameter(Mandatory)][string]$Name,
	[Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{2,4}$')][string]$Code,
	[string]$GitHubRepo = '',
	[int]$PortBase = 0,
	[string]$Existing = '',
	[switch]$StudioOnly
)
$ErrorActionPreference = 'Stop'

$templateRepo = Split-Path $PSScriptRoot -Parent
$template = Split-Path $templateRepo -Parent
$roDev = Split-Path $template -Parent
$game = Join-Path $roDev $Name
$repo = Join-Path $game 'repo'

# Git's answer to a question, without stopping on what it says to stderr (Windows PowerShell would).
function Ask-Git { $ErrorActionPreference = 'Continue'; "$(git @args 2>$null)".Trim() }

if ($Name -match '[\\/:*?"<>|]') { throw 'The name cannot contain \ / : * ? " < > |' }
if (Test-Path $game) { throw "$game already exists." }

# What's brought in: a git repo (kept, with its history), a folder or place file (copied next to a new project), or nothing.
$kind = if ($StudioOnly) { 'studio' }
	elseif (-not $Existing) { 'new' }
	elseif ($Existing -match '^(https://|git@)') { 'git' }
	elseif (Test-Path -LiteralPath (Join-Path $Existing '.git')) { 'git' }
	elseif ((Test-Path -LiteralPath $Existing -PathType Leaf) -and $Existing -match '\.rbxlx?$') { 'place' }
	elseif (Test-Path -LiteralPath $Existing -PathType Container) { 'folder' }
	else { throw "Can't find ${Existing}: give a GitHub repo address, a folder, or a .rbxl place file." }

# The Lync port block: the first one no other game in the RoDev folder uses.
if ($PortBase -eq 0) {
	$used = @(Get-ChildItem $roDev -Directory | Where-Object { $_.FullName -ne $game -and $_.FullName -ne $template } | ForEach-Object {
		$json = Join-Path $_.FullName 'repo\default.project.json'
		if (Test-Path $json) { [int](Get-Content $json -Raw | ConvertFrom-Json).port }
	})
	$PortBase = 34870
	while ($used -contains $PortBase) { $PortBase += 20 }
}

# 1. Update the template.
Write-Host 'Updating the template ...'
git -C $templateRepo pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Could not update the template. Check git status in template\repo, then try again.' }

# A game in a git repo keeps its repo and history. The template is merged in later, by an agent (SETUP.md).
if ($kind -eq 'git') {
	Write-Host "Cloning $Existing into $repo ..."
	New-Item -ItemType Directory -Force $game | Out-Null
	git clone -q $Existing $repo
	if ($LASTEXITCODE -ne 0) { Remove-Item -Recurse -Force $game; throw "Could not clone $Existing." }
	# A clone of a folder points at the folder: that repo's own GitHub remote, if it has one, becomes origin.
	if ($Existing -notmatch '^(https://|git@)') {
		$upstream = Ask-Git -C $Existing remote get-url origin
		if ($upstream) { git -C $repo remote set-url origin $upstream } else { git -C $repo remote remove origin }
	}
	if ($GitHubRepo -and -not (Ask-Git -C $repo remote get-url origin)) { git -C $repo remote add origin $GitHubRepo }
	git -C $repo remote add template (Ask-Git -C $templateRepo remote get-url origin)
	git -C $repo fetch --quiet --tags template
	git -C $repo config worktree.useRelativePaths true
	git -C $repo config core.hooksPath tools/hooks
	foreach ($dir in 'lanes', 'places', 'art\generated', 'art\source', 'art\reference', 'art\captures', 'art\marketing', 'backups', 'scratch') {
		New-Item -ItemType Directory -Force (Join-Path $game $dir) | Out-Null
	}
	Write-Host ''
	Write-Host "$Name is cloned at $repo, with its history; the template is its 'template' remote."
	Write-Host "  Code $Code. Its Lync port base is picked when the template is merged in."
	Write-Host 'Next: your agent merges in the template and fills in the docs (docs\workflow\SETUP.md "Existing game", in the'
	Write-Host 'template). Rocco''s onboarding starts it for you.'
	exit 0
}

# 2. Duplicate the template. Lanes and Rocco's data are never copied: each belongs to one game.
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

# A game brought in from a folder or a place file: its files go next to the new project, for the agent (SETUP.md).
if ($kind -eq 'folder') {
	Write-Host "Copying $Existing into $game\import ..."
	robocopy $Existing (Join-Path $game 'import') /E /XD .git node_modules /NFL /NDL /NJH /NJS /NP | Out-Null
	if ($LASTEXITCODE -ge 8) { throw "Copying the game failed (robocopy exit $LASTEXITCODE)." }
}
if ($kind -eq 'place') {
	$extension = [IO.Path]::GetExtension($Existing)
	New-Item -ItemType Directory -Force (Join-Path $game 'places'), (Join-Path $game 'backups') | Out-Null
	Copy-Item -LiteralPath $Existing (Join-Path $game "places\$Code-Main$extension")
	Copy-Item -LiteralPath $Existing (Join-Path $game "backups\$Code-Main-before-import$extension")
}

Write-Host ''
Write-Host "$Name is ready at $game"
Write-Host "  Code $Code, Lync port base $PortBase"
if (-not $GitHubRepo) { Write-Host '  No GitHub repo yet: create an empty private one, then in repo\ run: git remote add origin <url>, then git push -u origin main' }
if ($kind -eq 'new') {
	Write-Host 'Next (docs\workflow\NEW-PROJECT.md): open your agent in repo\ and start the Pitch. Places and lanes can wait until'
	Write-Host 'Foundation (steps 5 and 6), and the Roblox ids and owner until the experience exists (step 7).'
} else {
	Write-Host 'Next: your agent brings the game in (docs\workflow\SETUP.md "Existing game"). Rocco''s onboarding starts it for you.'
}
