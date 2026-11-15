# Feature: Ground-first mountain trial

**Status:** specced; awaiting the user's plan approval. **Owner task:** the Workboard plan linked to this spec.

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
