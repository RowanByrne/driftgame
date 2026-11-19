# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `feature/tight-hairpins` | Borrow to test | `src/ReplicatedStorage/Shared/Road/Ground.luau`, `Shared/Road/Spline.luau`, `Shared/Road/TightHairpin.luau` (new), `Shared/Config/TightHairpin.luau` (new), `Shared/Config/init.luau` (the new `TightHairpin` line only), `src/ServerScriptService/Tests/TightHairpinTests.luau` (new), `docs/game/features/tight-hairpins.md`, `src/StarterPlayerScripts/Controllers/SplineRoadController.luau`, `Shared/Road/SplineGen.luau`, `Shared/Road/SplineSequence.luau`, `Shared/Config/Spline.luau`, `Shared/Road/RoadDressing.luau`, `Shared/Config/Dressing.luau`, `Spline*` tests in `src/ServerScriptService/Tests/` | 2026-11-19, T-333 (tight hairpins step 2) |
## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

- **2026-11-19, for the next conductor:** the user logged off mid-round. T-333 (tight hairpins step 2) stopped at `e0989ad` on `feature/tight-hairpins`, pushed: its last change is untested (its card says what's next). T-332 (climbs in legs) waits for T-333's planner claim. In `_tools\rocco` (9 files) and `template\repo` (CONDUCTOR.md, WORKER.md) there are uncommitted changes from another session (13:00 to 13:43 that day), not the Drift conductor's: leave them for whoever made them.

