# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/fewer-redraws` (T-288) | borrowed | `src/StarterPlayerScripts/Drift/SplineRoadView.luau`, `Shared/Road/OpaqueBudget.luau`, `Shared/Road/RoadTexture.luau` (its opaque call only), `Drift/GroundMarks.luau` (its opaque call only), `Drift/GroundMeshView.luau` (its opaque call only), `Drift/VistaView.luau` (its opaque call only), `src/ServerScriptService/Tests/SplineMeshTests.luau` | 2026-11-17 |
| `agent/low-smoke` (T-290) | borrowed | `src/ReplicatedStorage/Shared/Config/Fx.luau`, `src/StarterPlayerScripts/Drift/Wheels.luau`, `src/ServerScriptService/Tests/FxTests.luau`, `docs/game/features/tyre-particles.md`, `features/car-fx.md` | 2026-11-17 |
| `agent/camera-lower` (T-291) | borrowed | `src/ReplicatedStorage/Shared/Config/Camera.luau`, `src/StarterPlayerScripts/Controllers/CarCameraController.luau`, `src/ServerScriptService/Tests/JitterTests.luau`, `docs/game/features/drift-camera.md` | 2026-11-17 |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

