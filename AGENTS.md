# Agent rules (Codex)

This project's rules live in `CLAUDE.md`. It's written for Claude, but it applies to you too. Before any work, read:

1. `CLAUDE.md`: project layout, who does what, the rules, and which doc to read for which task.
2. `docs/game/PROJECT.md`: this game's details and game-only rules.
3. The workflow doc for your task, from the table in `CLAUDE.md` "Docs".

- **Ownership.** Check `docs/CLAIMS.md` before editing: don't touch files another task owns, and preserve other sessions' uncommitted changes.
- **Claude-only parts.** Where `CLAUDE.md` names Claude-only tools (subagents, the Roblox Studio MCP), skip that part or use your own equivalent.
- **Images.** You can generate images yourself. Still follow `docs/workflow/ART-PIPELINE.md`: candidates go in `..\art\generated\`, each one is logged in its topic's manifest, and nothing is uploaded until the user picks it.
- **One copy of the rules.** Don't add rules here. A rule change goes in `CLAUDE.md` through the template (`CLAUDE.md` "Template-owned files").
