# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/horizon-follows-range` | lent | `src/ReplicatedStorage/Shared/Horizon.luau`, `src/ReplicatedStorage/Shared/Config/Horizon.luau`, `src/StarterPlayerScripts/Drift/HorizonView.luau`, `src/ServerScriptService/Tests/HorizonTests.luau`, `docs/game/features/horizon.md`, `docs/game/features/mountain-range.md` (a new "As built: step 3" section only), `src/StarterPlayerScripts/Controllers/DriftController.luau` (only where it makes the HorizonView), `src/ReplicatedStorage/Shared/Road/Range.luau` (read-only helpers added at the end only) | 2026-11-15 (T-241) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

