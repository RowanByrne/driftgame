# Brings a template release into this game (docs/workflow/TEMPLATE.md "Taking an update"): the newest one, or -To.
# It merges without committing, keeps the game's own starter files, and says what changed and what to look at.
# Run it from the game's repo\:
#   powershell -ExecutionPolicy Bypass -File tools\update-from-template.ps1 [-To template/v1.2.0] [-Check]
# -Check only says which release this game is on and what's newer. Nothing is committed or pushed: the conductor
# checks the merge, commits it and pushes.
param(
	[string]$To = '',
	[switch]$Check
)
$ErrorActionPreference = 'Continue'

# Starter files (TEMPLATE.md "Three kinds of file"): the template's first version of what is the game's own from the
# day it's made. While this merge runs, a starter file both sides changed keeps the game's version. Only here: a
# worker's branch merges these files as usual.
$Starter = 'docs/game/**', 'docs/CLAIMS.md', 'live/**', 'src/**', 'README.md', 'default.project.json'
$TemplateOwned = '^(AGENTS\.md|CLAUDE\.md|GEMINI\.md|\.claude/|docs/workflow/|tools/|\.gitignore$)'

$repo = Split-Path $PSScriptRoot -Parent
function RepoGit { git -C $repo @args }
function Stop-With([string]$message, [int]$code = 2) { Write-Host $message; exit $code }

if (-not (RepoGit remote get-url template 2>$null)) {
	Stop-With 'No "template" remote: this is the template itself, or a game that needs it added (NEW-PROJECT.md "An existing game on another PC").'
}
Write-Host 'Fetching the template ...'
RepoGit fetch --quiet --tags --force template
if ($LASTEXITCODE -ne 0) { Stop-With 'Could not reach the template on GitHub. Check you are online and signed in, then try again.' }

$current = "$(RepoGit describe --tags --abbrev=0 --match 'template/v*' HEAD 2>$null)"
$releases = @(RepoGit tag -l 'template/v*' --sort=-v:refname)
if (-not $releases) { Stop-With 'The template has no releases yet (TEMPLATE.md "Releasing").' }
$target = if ($To) { $To } else { $releases[0] }
if (-not (RepoGit rev-parse --verify --quiet "$target^{commit}")) { Stop-With "There's no $target in the template." }

function Test-Ancestor([string]$commit, [string]$of) { RepoGit merge-base --is-ancestor $commit $of; $LASTEXITCODE -eq 0 }

Write-Host "This game is on $(if ($current) { $current } else { 'no template release yet' })."
if (Test-Ancestor $target 'HEAD') { Write-Host "It already has $target. Nothing to do."; exit 0 }

# What's new: the releases the target brings that the game doesn't have yet, newest first.
$newer = @($releases | Where-Object { (Test-Ancestor $_ $target) -and -not (Test-Ancestor $_ 'HEAD') })
Write-Host ''
Write-Host "What's new up to ${target}:"
foreach ($tag in $newer) {
	Write-Host "  $tag"
	foreach ($line in @(RepoGit tag -l $tag '--format=%(contents)')) { if ("$line".Trim()) { Write-Host "    $line" } }
}
if ($Check) { exit 0 }

# The merge needs main, clean, and not in the middle of another merge.
if ("$(RepoGit symbolic-ref --short -q HEAD)" -ne 'main') { Stop-With 'repo\ has to be on main.' }
if (@(RepoGit status --porcelain --untracked-files=no).Count) { Stop-With 'repo\ has uncommitted changes. Commit them (or show the user anything unexplained) first.' }
if (Test-Path "$(RepoGit rev-parse --path-format=absolute --git-path MERGE_HEAD)") { Stop-With 'A merge is already in progress in repo\.' }

# Starter files keep the game's version, through a temporary entry in .git\info\attributes (never committed).
$attributes = "$(RepoGit rev-parse --path-format=absolute --git-path info/attributes)"
$before = if (Test-Path $attributes) { [IO.File]::ReadAllText($attributes) } else { $null }
New-Item -ItemType Directory -Force (Split-Path $attributes) | Out-Null
# A pattern with no / matches in every folder, so the root's files get a leading / (README.md, not docs/README.md).
$block = "`n# update-from-template.ps1 (temporary)`n" + (($Starter | ForEach-Object { "$(if ($_ -notmatch '/') { '/' })$_ merge=ours" }) -join "`n") + "`n"
[IO.File]::WriteAllText($attributes, "$before$block")
try {
	Write-Host ''
	Write-Host "Merging $target ..."
	RepoGit -c merge.ours.driver=true merge --no-ff --no-commit $target | Out-Null
	$merged = $LASTEXITCODE -eq 0
} finally {
	if ($null -eq $before) { Remove-Item -LiteralPath $attributes -Force } else { [IO.File]::WriteAllText($attributes, $before) }
}

# The report. The base is the release the game was on, or where its history meets the template's.
$base = if ($current) { $current } else { "$(RepoGit merge-base HEAD $target)" }
$changed = @(RepoGit diff --name-only $base $target)
$starterChanged = @(RepoGit diff --name-only $base $target '--' @Starter)
$kept = @($starterChanged | Where-Object { RepoGit diff --quiet $base HEAD '--' $_; $LASTEXITCODE -ne 0 })
$conflicts = @(RepoGit diff --name-only --diff-filter=U)
$owned = @($changed | Where-Object { $_ -match $TemplateOwned })
$other = @($changed | Where-Object { $_ -notmatch $TemplateOwned -and $starterChanged -notcontains $_ })

function Show-List([string]$title, [string[]]$files) {
	if (-not $files) { return }
	Write-Host ''
	Write-Host $title
	foreach ($f in $files) { Write-Host "  $f" }
}
Show-List 'Template-owned files it changed:' $owned
Show-List 'Starter files the template improved, taken as they are (this game had not changed them):' @($starterChanged | Where-Object { $kept -notcontains $_ })
Show-List "Starter files this game has its own version of, kept. The template changed them too: see what with 'git diff $base $target -- <file>', and bring over what the game wants:" $kept
Show-List 'Other files it changed (shared, merged as usual):' $other
Show-List 'CONFLICTS to resolve (TEMPLATE.md "Taking an update", step 3):' $conflicts

Write-Host ''
if ($merged) {
	Write-Host "Merged $target into main, not committed yet. Check it, commit it as `"Update from template: $target`", push main and refresh the lanes."
	exit 0
}
if ($conflicts) {
	Write-Host 'Resolve the conflicts, then commit, push main and refresh the lanes. To back out instead: git merge --abort'
	exit 1
}
Write-Host 'The merge stopped. Read git status, then fix it or back out with: git merge --abort'
exit 1
