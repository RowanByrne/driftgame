# World building

How the world gets laid out, built, and kept working as it changes. The user decides the layout and approves each stage; the agent sketches, builds, measures, and keeps `docs/game/WORLD.md` current. The look follows `docs/game/ART-DIRECTION.md`; models and textures come through `ART-PIPELINE.md`.

## When

- **Foundation:** a placeholder world. Decide whether the world is built by code or by hand (below), and record it in `ARCHITECTURE.md` "World and streaming".
- **Core loop:** only the world the loop needs, as a gray blockout.
- **Production:** the whole layout is sketched and approved before any area is built. Then areas are built in rounds (`CONDUCTOR.md`).

## By code or by hand

- **By code:** the world is generated at runtime by modules in `src/`. It can be reviewed and merged like any code, and every lane builds the same world. Best for worlds made of repeated pieces: islands, terrain, paths, rooms. The Edit datamodel looks nearly empty, so use the map preview (below) or a playtest to see it.
- **By hand:** built in Studio, in the Main place only (when the user asks: Main is theirs), and copied to the lanes after it changes (`LANES.md` "Hand-built content"). Best for one-off, sculpted spaces.
- **Mixed** is common: a code-built layout with hand-built set pieces, or the reverse. Record which parts are which in `ARCHITECTURE.md`.
- **One lane owns the map at a time.** Claim the world's modules, or the Main place's map, before editing (`CONDUCTOR.md` "Claims").

## Stages

The user approves each stage before the next one starts, as in the art pipeline.

1. **Layout sketch.** A top-down map drawn from the areas in `WORLD.md`, saved as `assets/reference/map-v<N>.png`. It shows every area, route, landmark and spawn, with distances and travel times worked out from the player's speed.

   **Gate: the user approves the layout.**
2. **Blockout.** The layout in gray parts and rough terrain, at true scale, with the named spots in place. Play it:
   - walk every route and time it against the sketch;
   - check landmarks can be seen from where players need them;
   - check locked areas can't be reached early.

   **Gate: the user plays the blockout and approves it.**
3. **Build.** Terrain, buildings and props, following `ART-DIRECTION.md`, with new assets through `ART-PIPELINE.md`. The named spots stay where the blockout put them unless the user moves them.

   **Gate: the user approves the built area,** from review shots and a playtest.
4. **Dress and light.** Details, foliage, lighting, and ambience (`AUDIO-PIPELINE.md`).

   **Gate: the user approves the area,** and `WORLD.md` marks it approved.

A change to an approved area goes back to the stage it touches. Moving an area is a new layout sketch; adding a prop is a build change.

## Rules

- **No world positions in gameplay code.** Code finds places by marker parts, tags and attributes, or from one layout module. List each in `WORLD.md` "Named spots" and `CONTRACTS.md`. Then moving an area means moving its markers, not hunting through code.
- **Every named spot gets a debug teleport,** a Cmdr `tp <spot>` command, so testers and agents get there in one step.
- **Tag a map version before moving areas:** `git tag map-v<N>`, recorded in `WORLD.md` "Versions". Rolling back is reverting to the tag.
- **Before moving an area, list what depends on it:** every named spot, route, quest waypoint, camera shot, signpost and line of text that mentions it. Fix them all in the same round.
- **Measure, then show.** Distances, heights, travel times and counts come from Studio, not from the sketch. Review shots answer "does this look right?" (`TESTING.md`).
- **New players first.** Walk the route from spawn to the first reward after every layout change, on touch and on keyboard.

## Checks

Each game builds these when its world is first built, as Studio-only modules reached through the debug bridges (`TESTING.md` "Reaching live game state"):

- **Map audit.** Runs after every map change. It checks that:
  - every named spot stands on ground or a deck (nothing floating, nothing buried);
  - every route is clear and walkable;
  - locked areas can't be reached early;
  - nothing a player needs is outside the streaming radius;
  - the world is within its part budget.

  It prints pass, warn and fail counts, and a fail is fixed before merging. It can also draw the map as an image, to set beside the layout sketch.
- **Map preview.** For a code-built world: builds it in the Edit datamodel without a playtest, to look around and take review shots.
- **Review spots.** A fixed set of camera spots per area, kept in the layout module, so before-and-after shots line up.
