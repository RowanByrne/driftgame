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
| Worker, heavy tier | A worker (WORKER.md) | Claude Opus 5.5, high effort | Claude Opus 5.5, high effort | Claude Code: `.claude/agents/roblox-dev-heavy.md`. Codex and Gemini CLI: `tools\start-worker.ps1` ("Worker models") |
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

## Worker models

Checked 2026-11-02. Codex and Gemini CLI workers take theirs from `tools\start-worker.ps1`, so change both together.

| Tier | Claude Code | Codex | Gemini CLI |
|---|---|---|---|
| Heavy | Opus 5.5, high | `gpt-6-astra`, high | `pro` |
| Standard | Opus 5.5, medium | `gpt-6.1-sol`, medium | `flash` |
| Light | Opus 5.5, low | `gpt-6.1-terra`, low | `flash-lite` |

Gemini's names are aliases that follow what each account can use. Codex's reasoning efforts run `low`, `medium`, `high`, `xhigh` and `max`; `ultra` runs more than one agent, so not for workers.

## Workers by agent

Every worker gets the same prompt, beginning "Follow docs/workflow/WORKER.md" (CONDUCTOR.md "A round", step 3), and reports in its last message. The conductor reads the reports, then merges.

- **Claude Code:** the conductor spawns the tier's subagent (`roblox-dev-heavy`, `-standard` or `-light`), several in parallel.
- **Codex and Gemini CLI:** each worker is its own run of the agent, in its lane's folder. Write each prompt to `..\scratch\workers\laneN-brief.md`, then start one worker per lane from `repo\`:
  ```
  powershell -ExecutionPolicy Bypass -File tools\start-worker.ps1 -Agent codex -Lane 2 -Tier heavy -Brief ..\scratch\workers\lane2-brief.md
  ```
  It returns at once with the worker's process id; start the next lane's straight away. `Wait-Process -Id <id>` waits for one. The report lands in `..\scratch\workers\laneN-report.md`, and the full output in `laneN-log.txt` beside it.
  - **What it runs for Codex:** `codex exec -C <lane> -m <model> -c model_reasoning_effort=<effort> --dangerously-bypass-approvals-and-sandbox -c mcp_servers.Roblox_Studio.default_tools_approval_mode=approve -c mcp_servers.Roblox_Studio.tool_timeout_sec=600 -o <report> -`, with the brief on stdin. Codex's Windows sandbox can't write a lane's git data (it lives in `repo\.git`, outside the lane), so a sandboxed worker can't commit: workers run without it, each in its own lane. Its Studio tools are approved up front, since nobody is there to answer them. `codex exec` loads the MCP servers from `~/.codex/config.toml`.
  - **What it runs for Gemini CLI:** `gemini -m <model> --approval-mode=yolo -o json -p "Follow the brief above."` in the lane's folder, with the brief on stdin and `GEMINI_CLI_TRUST_WORKSPACE=true` so the lane's MCP servers connect. In headless mode a tool that would ask is refused, hence `yolo`. The report is the `response` field of the JSON output.
  - **Not tried yet** with a real worker on this setup. If a flag has changed, `codex exec --help` or `gemini --help` shows the new one: fix the script and this section together, in the template.
- **By hand:** open the agent in the lane's folder and give it the prompt.

## Setting up an agent

- **Sign in** with your subscription.
- **The Roblox Studio MCP**, registered as `Roblox_Studio`, where the agent keeps MCP servers (table above; WORKSTATION.md).
- **Folders next to `repo\`:** agents work in `..\lanes`, `..\places`, `..\art`, `..\backups`, `..\scratch`, the template's checkout and Rocco (`..\..\_tools\rocco`). Claude Code is allowed in by `.claude/settings.json`. Others: allow them in the agent's own settings, or say yes when it asks.
- **Pick it in Rocco's Settings.**

## Changing a model

1. Update "Recommended" and "In use" above, and the "Last reviewed" date.
2. Change the model or effort where the agent sets it: for Claude Code workers, the `model` / `effort` frontmatter of `.claude/agents/roblox-dev-*.md` (they share one brief, WORKER.md; only the frontmatter differs). For Codex and Gemini CLI workers, `$Models` in `tools\start-worker.ps1` and the "Worker models" table.
3. Commit to the template and "update from template" in each game (AGENTS.md "Template-owned files").

Try a new model on one round before switching every tier. A game can keep different settings in its `PROJECT.md` ("Game-only rules") when it has a reason to.
