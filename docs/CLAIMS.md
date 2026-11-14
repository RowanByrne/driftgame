# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `feature/glass-settings` (T-201, current step T-202) | 1 | `src/StarterPlayerScripts/Settings/*` (new), `src/StarterPlayerScripts/UI/*` (new), `Controllers/SettingsController.luau` (new), existing `Controllers/CarInputController.luau`, `Controllers/UiVisibilityController.luau`, `Controllers/GarageController.luau`, `Drift/TunerUI.luau`; `docs/game/features/settings-menu.md`, `docs/game/ART-DIRECTION.md` UI section, `docs/game/DECISIONS.md` settings entries only, `docs/game/UI-INVENTORY.md`, `docs/game/SETTINGS.md`, `docs/game/ARCHITECTURE.md` UI entries, `docs/game/CONTRACTS.md` UI entries; `assets/settings-menu/*`, `assets/reference/settings-menu-*` | 2026-11-14 |
| `feature/linked-biomes` (T-203, terrain T-209) | 2 | `docs/game/features/road-biomes.md`; `assets/reference/road-biomes/*`; `docs/game/DECISIONS.md` (append T-203 only); `docs/game/CONTRACTS.md` and `ARCHITECTURE.md` (biome entries); `src/ReplicatedStorage/Shared/Config/Spline.luau`; `src/ReplicatedStorage/Shared/Road/SplineBiome.luau`, `SplineCorridor.luau` (new), `Spline.luau`, `SplineGen.luau`, `SplineProfile.luau`, `SplineSequence.luau`, `SplineParts.luau`; `src/StarterPlayerScripts/Drift/SplineWorld.luau`; `src/StarterPlayerScripts/Controllers/SplineRoadController.luau`, `RoadGroundController.luau`; `src/ServerScriptService/Tests/SplineBiomeTests.luau`, `SplineCorridorTests.luau` (new), `SplineTurnTests.luau`, `SplineWorldTests.luau` | 2026-11-14 |
| `agent/consistent-tyre-mark-width` (T-207) | 3 | `src/StarterPlayerScripts/Drift/Wheels.luau`, `src/ServerScriptService/Tests/FxTests.luau`, `src/ReplicatedStorage/Shared/Config/Fx.luau` (budget comments only), `docs/game/features/car-fx.md`; `docs/game/CONTRACTS.md` (new T-207 row after rig effects instance names only), `docs/game/ARCHITECTURE.md` (new T-207 wheel mark note only) | 2026-11-14 |
| `agent/contained-shadow-blocks` (T-206) | 4 | `src/ReplicatedStorage/Shared/Road/SplineMesh.luau`, `src/ReplicatedStorage/Shared/Road/SplineShadow.luau` (new, if needed), `src/ServerScriptService/Tests/SplineMeshTests.luau`, `docs/game/features/mountain-road.md` | 2026-11-14 |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.


