# Models

Which AI model and settings each job uses. Every other doc names a **job** or a **worker tier**, never a model or an effort level. When models or effort settings change, only this file and the agent files' frontmatter change.

## Jobs

**Last reviewed: 2026-10-29.** "Recommended" is the best fit we know of for the job; "In use" is what the user actually runs. Keep both current.

| Job | Agent or tool | Recommended | In use | Set in |
|---|---|---|---|---|
| Conductor (the main session) | Claude Code, opened in `repo\` | Claude Opus 5.5 | Claude Opus 5.5 | The app's model and effort settings |
| Worker, heavy tier | `roblox-dev-heavy` | Claude Opus 5.5, high effort | Claude Opus 5.5, high effort | `.claude/agents/roblox-dev-heavy.md` |
| Worker, standard tier | `roblox-dev-standard` | Claude Opus 5.5, medium effort | Claude Opus 5.5, medium effort | `.claude/agents/roblox-dev-standard.md` |
| Worker, light tier | `roblox-dev-light` | Claude Opus 5.5, low effort | Claude Opus 5.5, low effort | `.claude/agents/roblox-dev-light.md` |
| Merging branches | `git-integrator` | Same as the conductor | Same as the conductor | `.claude/agents/git-integrator.md` |
| Creator Store lookups | `asset-scout` | Claude Sonnet 5.5, low effort | Claude Sonnet 5.5, low effort | `.claude/agents/asset-scout.md` |
| 3D assets: building, rigging, texturing, animating (ART-PIPELINE.md) | A worker agent with the Blender MCP | Claude Opus 5.5, heavy tier | Claude Opus 5.5, heavy tier | The worker agent file; the Blender MCP set up on the PC (WORKSTATION.md) |
| Images: reference sheets, textures, storyboards, UI art | `tools\imagegen.ps1` | Codex's built-in image generation | Codex's built-in image generation, through the Codex desktop app signed in on the PC | `tools\imagegen.ps1`, the Codex app |

## Worker tiers

Tasks are sorted by how hard they are, not by effort level. The conductor picks a tier (CONDUCTOR.md); this file decides what each tier runs.

| Tier | For |
|---|---|
| Heavy | Core systems, tricky gameplay, anything touching player data or money |
| Standard | Well-specified features, content, UI |
| Light | Small, mechanical, clearly specified fixes |

Claude Code's effort levels today are low, medium, high, xhigh and max. If the scale changes, or a tier needs more or less, change the `effort` (or `model`) in that tier's agent file and its row above. Nothing else in the docs changes.

## Changing a model

1. Update "Recommended" and "In use" above, and the "Last reviewed" date.
2. Change the `model` / `effort` frontmatter in the agent files (the three worker files share one body; only the frontmatter differs).
3. Commit to the template and "update from template" in each game (CLAUDE.md "Template-owned files").

Try a new model on one round before switching every tier. A game can keep different settings in its `PROJECT.md` ("Game-only rules") when it has a reason to.
