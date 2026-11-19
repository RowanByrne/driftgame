# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/tilted-score-ranks` | Borrow to test | `src/StarterPlayerScripts/UI/ScoreTape.luau`, `UI/ScoreRankArt.luau`, `UI/ScoreRankRegistry.luau`, `src/StarterPlayerScripts/Drift/ScoreHudView.luau` (and its `.fixtures`), `docs/game/features/score-rank-art.md`, the score HUD's rows in `docs/game/UI-INVENTORY.md` | 2026-11-19, T-331 |
| `agent/gorge-approaches` | Borrow to test | `src/ReplicatedStorage/Shared/Config/Range.luau`, `Shared/Config/Spline.luau`, `Shared/Config/Road.luau`, `Shared/Road/Range.luau`, `Shared/Road/Ground.luau`, `Shared/Road/Seed7*.luau`, `Shared/Road/SplineGen.luau`, `Shared/Road/SplineContour*.luau`, `src/ServerScriptService/Services/RoadService.luau`, road and terrain tests in `src/ServerScriptService/Tests/` (`Ground*`, `Range*`, `Spline*`, `Seed7*`), `docs/game/features/mountain-range.md` | 2026-11-19, T-326 attempt 2 (gorge traverses) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

