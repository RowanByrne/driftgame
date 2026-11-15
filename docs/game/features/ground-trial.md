# Feature: Ground-first mountain trial

**Status:** building (`T-218`): plan approved 2026-11-15; step 1 (`T-219`, the shared shape and road cut) step 2 (`T-220`, option 1, our own mesh) and step 3 (`T-224`, option 2, Roblox Terrain) built; awaiting the user's pick. **Owner task:** `T-218`.

## Goal

The user, 2026-11-15, after rolling back the biome work (`DECISIONS.md`): *"i want to take a step back and think about how we are currently doing terrain surrounding the road ... we want to create the driving environment of the famous japanese mountains where drifting was born ... given we have the spline system for our driving surface - that's the starting point."*

Today the ground is built outward from the road: each section draws its own rock face and drop, and rays negotiate the ground between legs (`continuous-mountain.md` "As built"). Every new kind of ground (fields, joins) meant more negotiation code, which is why the biome work grew so heavy. This trial builds the ground **first**, as one mountain the road is cut into, two ways, on the same stretch of road, so the user can drive both and pick one.

## How it plays

Nothing changes for a player yet. In a lane, the user starts a run and drives the same seeded stretch (about 2 km, with switchbacks) twice, once with each ground:

1. **Option 1, our own mesh.** One height function of world position, h(x, z): the mountain falling along the fall line, with seeded ridges, gullies and shelves. The road is pressed into it: within a corridor the ground meets the road's edge; past it, it blends back to h through a cut (rock wall) or fill (bank or drop). Drawn as chunked grid meshes, coarser further out. Between two legs is simply h, with no negotiation.
2. **Option 2, Roblox Terrain.** The same h(x, z) and corridor, written as voxels (`Terrain:WriteVoxels`) in chunks as the road streams in, with built-in grass and rock materials chosen by slope. The road stays our own mesh on top.

The user judges how each looks while driving (switchbacks, the view between legs, cuttings, drops). The numbers below go on the cards.

## Left out

- The touge kit (walls, guardrails, forest, props), seasons and a new backdrop: they follow the pick and sit on top of either ground.
- Any change to the car, its physics or what it drives on: the car still drives on the spline maths (`Drift/SplineWorld`).
- Biomes; replacing the current renderer on `main` (the trial is switched on in its lane only, off by default).

## Rules and numbers

First guesses, in a new `Config.Spline.Ground` block, off by default (`Mode = "current" | "mesh" | "terrain"`):

| | Start | Notes |
|---|---|---|
| Height function | The fall line from `mountain-direction.md` plus 2-3 octaves of seeded noise (400-900 studs, plus or minus 30-60 studs) | Pure function of seed and position: same on server and client |
| Corridor | Road edge plus runoff, then a 20-60 stud blend to h | Cut steeper than 45 degrees draws as rock |
| Mesh grid (option 1) | 8 studs near, 32 studs past 400, 128 past 1 200 | Chunked; built a few ms a frame |
| Voxels (option 2) | 4-stud voxels, chunks of 128 by 128 studs | Written over frames as road arrives, cleared behind |
| Drawn out to | 1 200 studs from the car | The horizon covers the rest |

- **The road lays itself on h:** the turn fitting (`SplineTurnFit`) samples h instead of today's hillside.
- **Budgets:** no frame over 20 ms while driving at 100 studs/s; chunk build work under 40 ms in total, sliced.

## Server and client

- **Server:** lays the road on h (the turn checks). Nothing new over the wire: the seed already is.
- **Client:** draws the ground from the same h and the road it was sent.

## Contracts

`Config.Spline.Ground` (new). Any new debug methods go in `CONTRACTS.md` with the build. No remotes or data.

## Platform risks

None.

## Art and sound

Programmer colours: greens and rock greys by slope, matching today's palette. No new assets.

## Testing

For each option, on the same three seeds:

- **Seams and holes:** no gaps between chunks, and no ground above the road's surface or runoff (sampled).
- **Between legs:** the ground between two legs is continuous (sampled heights match h).
- **Cost:** chunk build time (mean and worst), triangles or voxels per chunk, memory, frames over 20 ms while streaming 5 000 studs at 100 studs/s.
- **Studio stability:** note any crash (`PROJECT.md` "Studio crashes on large live syncs").
- The user drives both in lanes and picks one.

## Open questions

- Which option goes on to the full build: the user's pick after driving both.

## As built (step 1, T-219): the shared mountain and the road cut

`Road/Ground` is the maths, numbers in `Config.Spline.Ground`. Nothing is drawn yet: the next two steps draw it.

- **Switched on per run, from the console:** `ground mesh`, `ground terrain` or `ground current` (today's ground), only between runs, like `road-mode`. Off by default, so `main` and the game are unchanged (the road laid in "current" is the same road, checked).
- **The mountain, h(x, z):** a plane through the road's start rising up the fall line, plus three octaves of noise (900, 450 and 180 studs across; 45, 22 and 7 studs either way), stretched 1.8 times along the fall line so ridges and gullies run down the mountain. Measured relief over 4 by 4 km: -93 to +68 studs.
- **The plane is 7 degrees (0.12), not 11.** At 0.2 a road heading down the mountain can't keep up (it may descend at most 8 degrees) and ended up 113 studs above it. At 0.12 the road follows it: 14.5 studs off on average, 59 at worst.
- **The road follows the plane:** in a ground run the road's height band is centred on the plane under the road's end, 40 studs either way, with no climbs. **So a ground run only descends**, about 1 stud in 25, with no valley-and-climb cycle yet. Fine for the trial's 2 to 5 km; the full build needs an answer (a valley in h, or a deeper kill height).
- **The cut:** under the road and runoff the ground is 0.25 studs below their surface; past the runoff's edge it blends back to h over 20 to 60 studs at about 45 degrees. Each road station answers for the points square beside it (carrying the road's grade, bank and bend to them), and between two stretches the nearer edge wins smoothly, so there is no seam.
- **Turn fitting** samples this mountain in a ground run (the view ahead, the cut and fill beside).
- **The client** gets `ground` in the road's start message and makes the same mountain from the seed, origin and fall line.

### Measured (DR-Lane1, GroundTests)

Three seeds (31337, 101, 2024), 5 000 studs each.

- Same seed, same mountain: 200 of 200 points; a client's replay draws the same ground: 0 of 19 269 points differ. Live: a run started with `mesh` reached the client with the same mountain.
- No ground above the road or its runoff: 0 of 18 870 points; at the runoff's edge within 0.18 studs of the 0.25 below.
- Far from any road, and between the legs past both blends: exactly h (19 088 and 42 776 points).
- No seams: 0 of 77 082 grid points jump half a stud over a twentieth of one; the steepest slope is 4.3 (a deep cut's face).
- The cuts are big: up to 140 studs deep and 104 studs of fill at the centre line. The relief is a number to tune once it can be seen.
- Turn checks ran on the ground (5 sharp turns, 1 relaxed); worst generator step 7.3 ms. The maths is cheap: 0.3 ms to gather a 400-stud box's stations, 2.5 microseconds a point.

## As built (step 2, T-220): option 1, our own mesh

`Drift/GroundMeshView` draws it; numbers in `Config.Spline.Ground` (`Levels` and below). Console: `ground mesh`, then `start-run`.

- **The road in a ground run** (`Road/SplineMesh`, `ground` option) draws its tarmac, gravel, runoff, rails and groves only: no rock faces, drops or hillside. A 10-stud skirt hangs from each runoff's outer edge, so a dip in the ground beside it shows no gap.
- **The ground is two nested square grids round the car:** 8 studs apart over 512 by 512, and 32 studs apart over 1 984 by 1 984 (so about 1 000 studs out, not 1 200; the horizon takes over). The fine grid lies over a hole in the coarse one and takes the coarse one's heights round its rim, so they meet without a crack. Each is rebuilt round the car as it moves (every 96 and 256 studs), into a hidden copy over a few frames, then swapped in whole.
- **Round the road** every vertex sinks 1.25 studs under the road and runoff, and one within 12 studs of a runoff's edge (20 on the coarse grid) is held below the edge, so no triangle from a cutting covers the road. So a cutting starts about a cell out from the edge, with a shallow ditch, and the skirt hides the step.
- **Colours:** two greens blotched, rock grey past 45 degrees, on Roblox's grass material.

### The mesh budget (measured, DR-Lane2 client)

The binding limit for this option. A client holds only so many mesh vertices: about 35 000 to 40 000 in Studio, counting the road's. A growable mesh (the kind the road's chunks are built in) holds back far more than it uses: 7 empty ones fill the budget. A fixed-size copy costs only its size. And a mesh can't be let go once its part is made: the part then draws nothing (measured).

- So each grid is a fixed-size copy of a flat grid, only its vertices moved: 4 225 and 3 969 vertices, twice each, 16 388 in all.
- **That pushed the road out of budget** (4 of its chunks fell back to plain parts), so in a ground run each road chunk, once built, is copied into a fixed-size mesh and the growable one let go. Then no fallbacks. A copy costs 1.6 ms.

### Measured (DR-Lane2)

- GroundTests still pass (all 20); a point of the cut costs 1.6 microseconds.
- **Frame time,** streaming 5 000 studs at 100 studs a second, seed 31337, the same session: today's ground, mean 8.9 ms, p99 19.4, 50 frames of 5 619 over 20 ms (worst 121); the mesh ground, mean 9.5 ms, p99 22.0, 87 of 5 274 over 20 (worst 194). This PC had other Studio places open; earlier the same check on today's ground gave none over 20, so the slow frames are partly the PC.
- The near grid rebuilt 48 times and the far one 18; a rebuild is 15 to 19 ms of work, at most 3.7 ms in any frame. Drawing the ground costs nothing measurable: standing still, 8.4 ms a frame with it, 8.6 without.
- No road fallbacks, no build failures, no errors in the console.

### Known

- **To the car nothing changed:** on the uphill side it still meets an invisible wall at the runoff's edge, where the rock face was, and on the downhill side it still falls past the edge, where the drop was, though ground is now drawn there.
- A ground run only descends (step 1), and the cuts can be very deep (up to 140 studs).
- Fine detail reaches 256 studs round the car; past that the 32-stud grid's road margins are wider (a 20-stud ditch).

## As built (step 3, T-224): option 2, Roblox Terrain

`Drift/GroundTerrainView` writes it; numbers in `Config.Spline.Ground` (`Terrain...`, `DrawTo`, `KeepTo`). Console: `ground terrain`, then `start-run`. The road is drawn as in option 1 (no faces, a skirt).

- **The same ground written as Roblox's smooth terrain** on the client, in 256-stud chunks of 4-stud voxels, nearest the car first, out to 768 studs, cleared past 1 024, and rewritten when new road comes into one. Grass, rock past 45 degrees (Roblox's own textures, tinted to the programmer colours), dirt under the grass. Solid 8 studs under each chunk's lowest point.
- **Round the road** it sinks 2.5 studs under the road and runoff and is held that far below the edge within 6 studs of it (smooth terrain rounds off between voxels). Checked: of 1 134 rays down onto the tarmac and runoff over the first 1 000 studs, none hit terrain above the road; the highest is 0.55 studs below it.
- Its colours are put back, and every voxel it wrote cleared, when the run ends (checked: none left round the start).

### What it costs (measured, DR-Lane3)

- **Each write costs the next frame 16 to 34 ms, whatever its size** (64, 128 or 256 studs), so chunks are 256 studs (not the planned 128) and at least 0.1 s apart. The script's part is small: a chunk is worked out in under 30 ms, at most 4.2 ms a frame, and written in under 10 ms.
- **The terrain itself costs frames by how much of it there is, more while the camera moves.** With a ring out to 1 024 studs and nothing being written: 15 ms a frame standing still and 34 ms moving, on a busy PC; with it cleared, 12 ms. So it reaches 768 studs, not 1 024 like option 1; the horizon covers the rest.
- **Streaming 5 000 studs at 100 studs a second,** seed 31337, back to back in one session: today's ground, mean 9.3 ms, p99 21.8, 72 of 5 392 frames over 20 ms; terrain, mean 10.7 ms, p99 29.7, 190 of 4 653 over 20 (worst 308). 142 chunks written, 105 cleared; the first ring (28 chunks) took 6.4 s.

## The two side by side

| | Option 1, our own mesh | Option 2, Roblox Terrain |
|---|---|---|
| Look | Smooth-shaded grid, two greens and rock grey on Roblox's grass material | Roblox's terrain grass and rock textures, voxel-smooth |
| Drawn to | About 1 000 studs (8-stud detail to 256) | 768 studs (4-stud voxels throughout) |
| Frames, streaming at 100 studs/s | +0.6 ms mean; slow frames 1.6% vs 0.9% | +1.5 ms mean; slow frames 4.1% vs 1.3% |
| Standing still | No measurable cost | About 15 ms a frame with a 1 024 ring (busy PC) |
| Budget | 16 400 mesh vertices of a client's ~35 000; the road copied to fixed-size meshes to fit | No mesh budget; memory in voxels |
| Near the road | Cutting starts a cell (8 studs) out, a shallow ditch | Cutting starts within 6 studs |
| Later work on top (walls, rails, trees) | Our own geometry: anything | Terrain tools, and the car could later drive on it |

Both: the car still meets an invisible wall at the uphill runoff edge and falls past the downhill one (its maths is unchanged), a ground run only descends, and the cuts can be up to 140 studs deep.
