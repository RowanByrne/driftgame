# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/score-engine` (T-295) | borrowed | `src/StarterPlayerScripts/Drift/ScoreEvents.luau` (new), `src/ReplicatedStorage/Shared/Config/ScoreEvents.luau` (new), `Drift/Events/Jump.luau` (new), `Drift/Events/WheelLift.luau` (new), `Drift/Score.luau`, `Shared/Config/Score.luau`, `src/ServerScriptService/Tests/ScoreTests.luau`, `Tests/ScoreEventsTests.luau` (new), `Controllers/DriftController.luau` (its score lines only), `docs/game/features/score-events.md` | 2026-11-17 |
| `agent/score-grinds` (T-297) | borrowed | `src/StarterPlayerScripts/Drift/Model.luau` (wall-contact state fields only), `Drift/SplineWorld.luau`, `Drift/Events/BumperGrind.luau` (new), `Drift/Events/HangGrind.luau` (new), `src/ServerScriptService/Tests/SplineWorldTests.luau`, `Tests/GrindEventsTests.luau` (new) | 2026-11-17 |
| `agent/score-nearmiss` (T-298) | borrowed | `src/StarterPlayerScripts/Drift/Events/NearMiss.luau` (new), `src/ServerScriptService/Tests/NearMissTests.luau` (new) | 2026-11-17 |
| `agent/score-hairpins` (T-299) | borrowed | `src/ReplicatedStorage/Shared/Road/Hairpins.luau` (new), `src/StarterPlayerScripts/Drift/Events/PerfectHairpin.luau` (new), `Drift/Events/ReverseEntry.luau` (new), `src/ServerScriptService/Tests/HairpinTests.luau` (new) | 2026-11-17 |
| `agent/score-flick` (T-300) | borrowed | `src/StarterPlayerScripts/Drift/Events/ScandiFlick.luau` (new), `src/ServerScriptService/Tests/ScandiFlickTests.luau` (new) | 2026-11-17 |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

