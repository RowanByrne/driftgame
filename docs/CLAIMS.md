# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/range-road-doubles-back` | lent | `src/ReplicatedStorage/Shared/Road/SplineGen.luau`, `src/ReplicatedStorage/Shared/Road/SplineTurnFit.luau`, `src/ReplicatedStorage/Shared/Road/Range.luau`, `src/ReplicatedStorage/Shared/Road/Ground.luau`, `src/ReplicatedStorage/Shared/Config/Range.luau`, `Config/Spline.luau` (the `Ground` keys the road reads and `Mountain.Hairpin...`), `src/ServerScriptService/Tests/RangeTests.luau`, `src/ServerScriptService/Tests/GroundTests.luau`, `src/ServerScriptService/Tests/SplineTests.luau`, `docs/game/features/mountain-range.md` | 2026-11-15 (T-242) |
| `agent/remove-far-mountains` | lent | `src/ReplicatedStorage/Shared/Horizon.luau`, `src/ReplicatedStorage/Shared/Config/Horizon.luau`, `src/StarterPlayerScripts/Drift/HorizonView.luau`, `src/ServerScriptService/Tests/HorizonTests.luau`, `src/ServerScriptService/AdminConsole/Commands/World/horizon.luau`, `src/StarterPlayerScripts/Controllers/DriftController.luau` (the horizon lines only), `src/ServerScriptService/AdminConsole/Commands/World/counts.luau`, `docs/game/features/horizon.md`, `docs/game/CONTRACTS.md` (horizon entries) | 2026-11-16 (T-243) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

