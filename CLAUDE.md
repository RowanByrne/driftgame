# Claude Code

The rules for every agent are in AGENTS.md, and this game's details in PROJECT.md. Both are loaded here:

@AGENTS.md

@docs/game/PROJECT.md

## Claude Code only

- **Workers are subagents:** `roblox-dev-heavy`, `roblox-dev-standard` and `roblox-dev-light` in `.claude/agents/`, one per worker tier (MODELS.md). Each follows `docs/workflow/WORKER.md`; only their frontmatter (model, effort, tools) differs. `git-integrator` merges worker branches, and `asset-scout` looks up Creator Store assets.
- **Access:** `.claude/settings.json` lets Claude Code work in the folders next to this repo, in the template's checkout, and in Rocco, without asking each time, whether it runs in `repo\` or in a lane (a lane is one folder deeper, so each path is listed at both depths).
- **Studio tools** reach the subagents only under the MCP name `Roblox_Studio`: their `tools` lists name them that way.
