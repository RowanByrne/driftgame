# Drift

A Roblox game made with an AI coding agent (Claude Code, Codex or another), from the RoDev template. What it is: `docs/game/PITCH.md`. Where it stands: `docs/game/PROJECT.md` (the current phase) and `docs/game/ROADMAP.md`.

## Working on it

1. **First time on this PC?** Set it up once: `docs/workflow/WORKSTATION.md`.
2. **Open your agent** in this folder (`repo\`) and say **"refresh"** to sync with GitHub.
3. **Start Lync:** `tools\serve-all.bat`.
4. **Open the places** in Studio from `..\places\`: the Main place, plus this PC's lane places (`docs/game/PROJECT.md` "Workstations").
5. **Open Rocco:** `tools\rocco.bat`, for the Workboard, Docs, History and Connections.
6. **Before you stop:** save and close Studio, close Lync, and say "refresh" so everything is pushed.

How we make games, step by step: `docs/workflow/WORKFLOW.md`. Every doc is indexed in `docs/README.md`.

## Folders

The game's folder holds this repo and the working folders next to it. Only `repo\` is in git; back up the others by copying them off the drive (WORKSTATION.md "Backups").

```
<Game>\
  repo\                 this repo, on GitHub
    AGENTS.md             rules for every agent (CLAUDE.md and GEMINI.md point to it)
    .claude\agents\       Claude Code's worker subagents (every agent's worker brief: docs\workflow\WORKER.md)
    src\                  the game's Luau code, synced into Studio by Lync
    docs\workflow\        how we make games (the same in every game)
    docs\game\            what this game is
    docs\archive\         one-off reviews and audits
    assets\               approved art that ships, with manifests
    live\                 running the live game: releases, dashboard settings, calendar, incidents
    tools\                scripts: Lync, lanes, image generation, opening Rocco
  lanes\laneN\          worker copies of this repo, one per lane (docs/workflow/LANES.md)
  places\               Studio place files: <CODE>-Main.rbxl and <CODE>-LaneN.rbxl
  art\                  art in progress, not in git
    generated\            every generated image candidate
    source\               working files (.psd, .blend, .kra)
    reference\            references and inspiration
    captures\             screenshots and recordings
    marketing\            working files for icons, thumbnails, event cards, video
  backups\              place snapshots before risky edits
  scratch\              throwaway files; safe to delete
```

**In git:** all text, and approved art up to 5 MB a file (a commit check refuses bigger). **Outside git:** image candidates, source files, video and place files.
