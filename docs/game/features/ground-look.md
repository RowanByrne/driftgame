# Feature: Ground look by steepness and height

**Status:** step 1 built (T-339): three looks to try side by side, waiting on the user's pick. **Owner task:** `T-338` (`feature/ground-look-by-steepness-and-height`).

## Goal

The user, 2026-11-20: *"can we start looking at how we would use some type of shader to properly texture the mountain? to do it procedurally based off the steepness of the terrain and the altitude that we are at?"* The target is the six concept paintings (`ART-DIRECTION.md` "References").

Roblox has no custom shaders, so here "a shader" means working out each patch of ground's look from its steepness and its height as the ground is drawn: once a vertex, blended across each face by the vertex colours (`Road/GroundLook`). Before this the ground had a hard switch: grass, or flat grey rock past 45 degrees, and height changed nothing.

## How it plays

Step 1 (T-339) is a trial. In a playtest, during a run, the admin console (F2) command `ground-look` switches the look on your own screen and redraws the ground round you in a few seconds, so all four can be compared on the same stretch of mountain:

- `ground-look old`: today's ground.
- `ground-look blend`: colours only. Grass fades through rocky grass to rock as it steepens, and lush to alpine grass to snow as it climbs; every band edge wanders by noise so the bands never run in lines. Snow doesn't lie on steep faces: the rock shows through.
- `ground-look detail`: blend over one shared grey detail texture made in code, so grass and rock have grain up close.
- `ground-look rock`: blend, with the steep faces in Roblox's own Rock material, as a second mesh over each tile that has rock in it.
- `ground-look` alone says which look is on and how many tiles carry a rock mesh.

Step 2 puts the picked look on every mountain, as the default, and tunes the bands. Any new rock or snow pictures go to the user to pick first.

## Left out

- What the car drives on: purely visual. The car still treats ground steeper than about 45 degrees as a wall (`car-edges.md`), whatever colour it is.
- Roblox Terrain: the user passed on it on 2026-11-15 (`DECISIONS.md`).
- New uploaded art: the detail texture is noise made in code.
- The road's own mesh and its runoff colours are unchanged, except that "detail" puts its grain on the ground-drawn runoff too.

## Rules and numbers

All in `Shared/Config/GroundLook.luau`. Heights are studs above the floor of the valley the run starts in (the mountain field's `oy`).

| | Value | Notes |
|---|---|---|
| `Look` | `"old"` | The look until the user picks; the workspace attribute `__ground_look` overrides it on one device |
| Rocky grass | 19 to 30 degrees | eased; edges moved up to 6 degrees by noise over 110 studs |
| Rock | 27 to 38 degrees | the drawn mountain is gentle: on seed 31337 almost no vertex is past 40 degrees |
| Alpine lower | 6 degrees | alpine ground turns rocky at gentler slopes |
| Alpine grass | 420 to 780 studs | edges moved up to 140 studs by noise over 420 |
| Snow | 900 to 1 100 studs | none on faces past 26 to 38 degrees |
| Detail texture | 256 px, mean 0.8, contrast 0.2 | tiles every `Spline.Ground.UVStuds` (48 studs); vertex colours divided by the mean |
| Rock mesh | lift 0.35, sink 0.9 studs, tint 1.25 | a tile gets one only where a vertex is at least 0.6 rock |

### Measured (T-339, DR-Lane2, seed 31337)

At the climb's rockiest stretch (road 14 000 to 14 750 studs along, 600 to 700 studs up), with the old look redrawn, then each of the others:

| Look | Work a tile | Tiles with a rock mesh | Frame time (standing) | Memory |
|---|---|---|---|---|
| old | 2.3 ms | none | 16.7 ms | no change |
| blend | 2.7 ms | none | 16.7 ms | no change |
| detail | 2.6 ms | none | 16.7 ms | one 256 px texture (none of the mesh budget once made opaque) |
| rock | 6.8 to 8.3 ms | 34 of 251 to 63 of 211 | 16.7 ms | one extra mesh per rock tile: 34 to 63 of the client's ~640 mesh units, and 13 to 27% more triangles |

The rock look's extra meshes come out of the same budget the ground's tiles and the road share (`ground-trial.md` "The mesh budget"); on Ultra the ground alone holds up to about 375 units, so a cliffier stretch could run the client out, and phones have less. The survey of the drawn ground (`DebugLookSurvey`) on the climb: about 30% rocky grass, 3 to 4% rock, 1 to 15% snow near the pass.

## Server and client

Client only: each client works out its own ground's look (`Drift/GroundMeshView`, `Road/GroundLook`, `Road/DetailTexture`). Nothing is sent.

## Contracts

`CONTRACTS.md`: the workspace attribute `__ground_look`, `GroundMeshView:Restyle()`, `DebugRestyle(look)`, `DebugLook()`, `DebugLookSurvey(step)`, `Config.GroundLook`, the `ground-look` admin command.

## Testing

`Tests/GroundLookTests` (pure maths, `require(...).run()` in a playtest's server): the switch, bands that never step back, snow off steep faces, band edges that wander, colours, cost (under 1 microsecond a vertex), the detail texture's mean and tiling.
