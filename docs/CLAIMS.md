# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/engine-rev-top` (T-147) | lane2 | `src/StarterPlayerScripts/Drift/Engine.luau`, `src/ReplicatedStorage/Shared/Config/Fx.luau` (`Engine` block only), `src/ServerScriptService/Tests/EngineTests.luau`, `docs/game/features/engine-sound.md` | 2026-11-12 |
| `agent/metal-guardrails` (T-149) | lane4 | `src/ReplicatedStorage/Shared/Road/SplineMesh.luau`, `src/ReplicatedStorage/Shared/Config/Spline.luau` (`KRail*` lines only), `src/ServerScriptService/Tests/SplineMeshTests.luau`, `docs/game/features/mountain-road.md` | 2026-11-12 |
| `agent/no-launch-marks` (T-151) | lane3 | `src/StarterPlayerScripts/Drift/Wheels.luau`, `src/ReplicatedStorage/Shared/Config/Fx.luau` (`Gates` block only), `docs/game/features/car-fx.md` | 2026-11-12 |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.


