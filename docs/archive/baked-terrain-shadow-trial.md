# Native baked terrain shadow trial — T-214

2026-11-14. Isolated Studio prototype based on Main `ec8311a`, with the later
overnight approval delegation merged. This does not replace the production
renderer. Only the two new trial modules and this report belong to the trial.

## Finding

Runtime `AssetService:CreateDataModelContentAsync(Content.fromObject(mesh))`
successfully returns `CreateContentResult.Success` and static
`ContentSourceType.Opaque`. A `CreateMeshPartAsync` made from it casts an
engine-rendered shadow. No plugin, asset upload or inventory asset is involved.

A deliberately notched, one-sided panel isolates the cause:

- The live EditableMesh, with no hidden blockers, does not cast.
- The static baked MeshPart with `CollisionFidelity.Box` casts the notched
  silhouette, matching ordinary thin Parts. Its front shadow is not a bounding box.
- The reversed single-sided baked panel does not cast from its back.
- Setting `MeshPart.DoubleSided=true` restores the tested reversed panel's notched
  back shadow. The trial's final baked terrain uses this property.
- An empty receiver remains lit. The ordinary Part control proves that shadows
  were enabled in the actual renderer.

This is rendered evidence, not a claim based on raycasts. Low-front controls used
15° sun and a normal/light dot of 0.965926. The combined terrain/backface control
used 60° sun. Solar latitude 23.5° makes the test light cross the panels directly.
The first alignment attempt was invalid and is retained as a failed fixture.

## Real terrain readback

Seed101, generated through3000studs; the unchanged production `SplineMesh.build`
draws chunk480–960, with the camera focused near road distance625. The complete
chunk is translated to the isolated trial stage; no terrain shape is changed.

An exact EditableMesh copy feeds the bake and is then destroyed. A fresh editable
readback from the resulting Opaque Content still succeeds, and the baked terrain
remains rendered. The original source remains alive only for the live/reference
comparison modes and is destroyed at trial cleanup.

| Check | Measured |
|---|---:|
| Source/static triangles |17,556 /17,556 |
| One-to-one triangle matches |17,556 |
| Missing/extra triangles |0 /0 |
| Reversed winding accepted |None; matcher permits cyclic order only |
| Source/static vertices |10,096 /21,246 |
| Maximum position difference |0stud |
| Maximum UV / colour difference |0 /0 |
| Maximum normal vector difference |0.000824334 |
| Bounds / UV bounds difference |0 /0 |
| MeshSize, both representations |1376.72534 ×306.74509 ×721.23242studs |

The vertex-count increase comes with unchanged triangle membership and corner
attributes; vertex IDs/shared vertex counts are not assumed stable. Comparison
tolerances remain position0.02stud, normal0.001, UV0.001 and colour0.005.

The baked MeshPart retains the original patched `GrassTexture` TextureContent,
material, CFrame and Size. That shared EditableImage is not destroyed. This is a
geometry bake, not an image bake. The reference chunk contains144 hidden shadow
blockers and165 total Parts. Each standalone live/baked terrain mode contains one
MeshPart; ordinary reference rails/paint Parts are omitted consistently from both.
Separate labelled receiver/control Parts are diagnostic fixtures, not terrain.

## Timing and lifetime evidence

All numbers are Studio client observations on a shared machine. Main remained in
the user's Play session and Lane2 was active. Neither was inspected or stopped.
Elapsed async call time is **not CPU time**. Heartbeat deltas are sampled
separately around each call, including its following frame. These results do not
replace the game's existing generation, chunk-work, frame or streaming guards.

Cold startup remains a failure/risk. Across source-gated fixture revisions:

| Session | Conversion wall time | CreateMeshPart wall time | Largest associated frame gap |
|---|---:|---:|---:|
|1, invalid panel alignment |6500.77ms |263.66ms |2447.00ms |
|2, invalid sun/receiver alignment |1391.42ms |4559.43ms |2218.82ms |
|3, controlled front/back proof |2958.36ms |9.61ms |2341.09ms |
|4, final bounded benchmark |388.28ms |5356.91ms |5010.77ms |
|6, final property/cleanup smoke only |5446.22ms |95.05ms |2531.31ms |

The invalid geometry fixtures do not prove shadows; their actual API costs remain
recorded. None of these cold observations is called a production budget pass or
attributed entirely to native CPU work.

The one settled lifecycle pass baked the same real17,556-triangle snapshot11times:
five published resident MeshParts, then six replacements. Publication took place
outside the comparison camera so it measures DataModel/API lifetime work without
claiming five distinct visible road chunks or a driving/streaming performance pass.

| Observation | Result |
|---|---:|
|45-frame baseline mean /p95 /max |8.310 /9.070 /9.989ms |
|11 normal conversions, wall range |23.880–34.092ms |
|11 normal mesh creations, wall range |6.940–8.944ms |
|11 publications, largest synchronous wall time |0.0672ms |
|6 individual retirements, largest synchronous wall time |0.0759ms |
|Final five retirements together, synchronous wall time |0.1705ms |
|Largest sampled frame during the normal window calls |12.750ms |
|120 frames after dropping all window Content references, p95 /max |9.139 /10.237ms |

Native release may be deferred beyond that settling window; these measurements
are not a guarantee that all GC/release work completed synchronously. The source
build itself measured141.638ms aggregate /6.288ms slice in this session (existing
3ms slice target and40ms whole-chunk guard remain unchanged). The extra native
work is not a claim to fix those pre-existing render flags. The five-resident
benchmark was run once, with no repeat-until-pass or threshold relaxation.

Final code smoke at`04e21f7` repeated the readback (17,556/17,556 matches), checked
the baked terrain's Opaque Content and DoubleSided=true, and exercised all three
modes:1live Part/0blockers,1baked Part/0blockers,165reference Parts/144blockers.
Stop removed the fixture/UI and cleared input; calling Start again was refused,
with native call count unchanged4→4. The flag-off session5 made zero native calls.
Final source build work159.953ms/slice7.280ms remains above the same3ms slice target
and40ms aggregate guard. No second lifecycle/performance benchmark was run.

Both injected post-native cancellation points (after conversion and after mesh
creation) return no published MeshPart/Content, and their temporary references are
released. An invalid `Content.none` conversion is rejected. The original successful
readback/size checks plus those three failure checks passed5/5. Cleanup destroys
source/copy/readback meshes, standalone/clone Parts, resident windows and UI; drops
retained Content; and resumes the game sky, camera and input. The shared grass
image stays owned by its normal cache.

The controller permits one start per Play. A stopped generation cannot restart
while an older asynchronous job drains; another comparison starts with a fresh
Play. Setup and native-await failures are protected by cleanup. The explicit
flag-off session produced zero native calls, no trial folder or GUI, and no input
override. All tests use tracked StudioTestService sessions and end back in Edit.

## Reproduce in Lane3

To reproduce, explicitly set the lane Edit attribute `workspace.__baked_shadow_trial=true` before starting. The conductor clears this flag after the checked trial so idle lanes return to the normal game. Press Play in DR-Lane3; wait for the labelled
panel comparison. Use Low front, Low back and Higher sun. Terrain: baked lazily
builds the real snapshot; Terrain: live and Terrain: boxes compare the same
geometry/camera with no blockers or the original blockers. The raised controls
beside the terrain compare single-sided back, DoubleSided back and ordinary Parts.
This camera/input override exists only in Studio with that explicit flag.

Client DebugBridge routes for review:

```lua
local b=game.Players.LocalPlayer.PlayerScripts.DebugBridge
b:Invoke("BakedShadowTrialController","DebugState")
b:Invoke("BakedShadowTrialController","DebugTerrain","baked") -- async
b:Invoke("BakedShadowTrialController","DebugSelect","terrain","baked","high")
b:Invoke("BakedShadowTrialController","DebugMeasure") -- async, one bounded window
b:Invoke("BakedShadowTrialController","DebugStop")
```

Screenshot evidence lives outside git in the task's `screenshots/` folder:
`01-invalid-alignment.png` (excluded from proof), `02-front-back-controls.png`,
`03-terrain-double-sided.png`. Exactly three captures were taken.

## Limits and production handoff

The native route works for this controlled geometry and terrain snapshot. It is
not a drop-in production change. Static vertex colours freeze cliff haze; the
production SkyController currently recolours live cliff vertices. Moving/changing
terrain requires a new bake, with revision/cancellation checks after every native
await; streamed new-neighbour caps and stale chunks still need the feature owner's
real lifecycle. Failure/device fallback, cold stalls, retained Content/release,
textures, distant geometry and full road streaming need production validation.
No device/Player, exhaustive shadow coverage, natural full-run or performance
acceptance is claimed. Prior accepted T-206 aggregate-build/shadow-coverage and T-210/
T-213 generation/render timing flags remain in force.

The native API is documented in the [May18 full-release announcement](https://devforum.roblox.com/t/full-release-introducing-createdatamodelcontent-convert-editable-mesh-and-image-data-into-static-content/4541898/1).
The [October creation-stall report](https://devforum.roblox.com/t/createmeshpartasync-holds-the-main-thread-40%E2%80%93300-ms-for-some-editablemesh-content-deterministic-per-mesh-data/4944040)
was later not reproduced by staff and may describe a resolved issue, rather than
a universal current bug. The [November14 release-cost repro](https://devforum.roblox.com/t/releasing-a-runtime-baked-mesh-gets-slower-the-more-baked-meshes-exist/4990639)
uses hundreds/thousands of meshes in Studio; it does not predict this five-mesh
window. This trial's raw cold and warm observations stand separately.
