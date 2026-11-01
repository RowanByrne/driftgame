# Agents and models

Which coding agent and model runs each job. The user works with whichever agent their subscription gives them: Claude Code, Codex, Gemini CLI, or the next one. Nothing in the project depends on one of them. Every other doc names a **job** or a **worker tier**, never an agent, a model or an effort level. When those change, only this file and the agents' own settings change.

## Your agent

Each PC picks its agent in Rocco's Settings ("Your agent"). Rocco opens it for onboarding (SETUP.md), says its name where it asks the agent for something, and checks it in Connections. Every agent reads `AGENTS.md` (Claude Code through `CLAUDE.md`, Gemini CLI through `GEMINI.md`, Codex directly).

| Agent | Opened in `repo\` with | Workers | Where it keeps MCP servers |
|---|---|---|---|
| Claude Code | `claude` | Subagents, one per tier: `.claude/agents/roblox-dev-*.md` | `~/.claude.json`, `mcpServers` |
| Codex | `codex` | Their own sessions, one per lane ("Workers by agent") | `~/.codex/config.toml`, `[mcp_servers.<name>]` |
| Gemini CLI | `gemini` | Their own sessions, one per lane ("Workers by agent") | `~/.gemini/settings.json`, `mcpServers` |

Another agent works too if it reads `AGENTS.md` (or can be pointed at it), runs PowerShell, and can use MCP servers for Studio. Add it to this table and to Rocco's agent list (Rocco's `server/agents.ps1`).

## Jobs

**Last reviewed: 2026-11-01.** "Recommended" is the best fit we know of for the job; "In use" is what the user actually runs. Keep both current.

| Job | Runs as | Recommended | In use | Set in |
|---|---|---|---|---|
| Conductor (the main session) | Your agent, opened in `repo\` | Claude Opus 5.5 (Claude Code) | Claude Opus 5.5 | The agent's own model setting |
| Setup from the onboarding answers (SETUP.md) | Your agent, opened in `repo\` by Rocco | Same as the conductor | Same as the conductor | The agent's own model setting |
| Worker, heavy tier | A worker (WORKER.md) | Claude Opus 5.5, high effort | Claude Opus 5.5, high effort | Claude Code: `.claude/agents/roblox-dev-heavy.md`. Others: the worker session's model setting |
| Worker, standard tier | A worker (WORKER.md) | Claude Opus 5.5, medium effort | Claude Opus 5.5, medium effort | Claude Code: `.claude/agents/roblox-dev-standard.md`. Others: as above |
| Worker, light tier | A worker (WORKER.md) | Claude Opus 5.5, low effort | Claude Opus 5.5, low effort | Claude Code: `.claude/agents/roblox-dev-light.md`. Others: as above |
| Merging branches | The conductor; Claude Code can hand it to `git-integrator` | Same as the conductor | Same as the conductor | `.claude/agents/git-integrator.md` |
| Creator Store lookups | The conductor; Claude Code can hand it to `asset-scout` | A small, fast model | Claude Sonnet 5.5, low effort | `.claude/agents/asset-scout.md` |
| 3D assets: building, rigging, texturing, animating (ART-PIPELINE.md) | A heavy-tier worker with the Blender MCP | Claude Opus 5.5, heavy tier | Claude Opus 5.5, heavy tier | The worker's setting; the Blender MCP set up on the PC (WORKSTATION.md) |
| Images: reference sheets, textures, storyboards, UI art | `tools\imagegen.ps1` | Codex's built-in image generation | Codex's built-in image generation, through the Codex desktop app signed in on the PC | `tools\imagegen.ps1`, the Codex app |
| Sound effects and music (AUDIO-PIPELINE.md) | The ElevenLabs API | ElevenLabs Sound Effects and Music | None yet: the user picks a tool and a plan that allows commercial use | `ELEVENLABS_API_KEY` on the PC, linked in Rocco's Connections (WORKSTATION.md) |

## Worker tiers

Tasks are sorted by how hard they are, not by effort level. The conductor picks a tier (CONDUCTOR.md); this file decides what each tier runs.

| Tier | For |
|---|---|
| Heavy | Core systems, tricky gameplay, anything touching player data or money |
| Standard | Well-specified features, content, UI |
| Light | Small, mechanical, clearly specified fixes |

Agents name their effort levels differently (Claude Code today: low, medium, high, xhigh and max). Map each tier to the closest setting your agent has.

## Workers by agent

- **Claude Code:** the conductor spawns the tier's subagent (`roblox-dev-heavy`, `-standard` or `-light`), several in parallel. Its prompt carries the task (CONDUCTOR.md "A round", step 3).
- **An agent without subagents** (Codex, Gemini CLI): each worker is its own session, started in its lane's folder with the tier's model, and given the same prompt, beginning "Follow docs/workflow/WORKER.md". Start them in the agent's non-interactive mode from the conductor (one per lane, in parallel), or open one per lane by hand. Each reports in its last message; the conductor reads the reports, then merges.

## Setting up an agent

- **Sign in** with your subscription.
- **The Roblox Studio MCP**, registered as `Roblox_Studio`, where the agent keeps MCP servers (table above; WORKSTATION.md).
- **Folders next to `repo\`:** agents work in `..\lanes`, `..\places`, `..\art`, `..\backups`, `..\scratch`, the template's checkout and Rocco (`..\..\_tools\rocco`). Claude Code is allowed in by `.claude/settings.json`. Others: allow them in the agent's own settings, or say yes when it asks.
- **Pick it in Rocco's Settings.**

## Changing a model

1. Update "Recommended" and "In use" above, and the "Last reviewed" date.
2. Change the model or effort where the agent sets it: for Claude Code workers, the `model` / `effort` frontmatter of `.claude/agents/roblox-dev-*.md` (they share one brief, WORKER.md; only the frontmatter differs).
3. Commit to the template and "update from template" in each game (AGENTS.md "Template-owned files").

Try a new model on one round before switching every tier. A game can keep different settings in its `PROJECT.md` ("Game-only rules") when it has a reason to.
