# World

This game's world and map: its areas, how players get around, and the named spots code reads. The layout is the user's call. It's sketched and approved before areas are built (docs/workflow/WORLD-BUILDING.md), then kept current as the map changes. How the world looks is in `ART-DIRECTION.md` "World"; how it's built (by code or by hand, streaming) is in `ARCHITECTURE.md`. Replace each prompt with the answer.

## Overview

> One paragraph: what the world is and how it's laid out, such as "a hub island with four themed islands around it, reached by boat".

**Map:** > The current top-down map in `assets/reference/` (`map-v1.png`, `map-v2.png`, ...), with every area, route and landmark named.

## Areas

> Every area. Role: hub, first zone, endgame, secret. Status: sketch, blockout, built, dressed, approved.

| Area | Role | What's there | Unlocks by | Travel from spawn | Status |
|---|---|---|---|---|---|
| | | | | | |

## Getting around

> How players move between areas: walking, vehicles, teleports. The measured travel times, what keeps players out of an area they haven't unlocked, and where they're put back if they get in anyway.

## Landmarks and wayfinding

> What players steer by: landmarks seen from a distance, signposts, a minimap or compass, the tutorial's path. A new player should always know where to go next.

## Named spots

> Every place code reads, area by area: spawns, NPC stands, shop counters, resource spots, landings. Code finds each by a marker, tag or attribute, never by coordinates (WORLD-BUILDING.md "Rules"); its contract is in `CONTRACTS.md`.

| Spot | Area | How code finds it | Teleport |
|---|---|---|---|
| | | | `tp <spot>` |

## Scale

- **Player:** > Walk and run speed and jump height, from the config.
- **Sizes:** > Doors, paths, buildings and props next to a player, and how far apart areas are.
- **World:** > Its size, the streaming radius if streaming is on, and the part budget, as the map audit measures them.

## Versions

> Each map version, tagged in git (`map-v1`, `map-v2`, ...): when, what changed, and the user's decision behind it. Rolling back is reverting to a tag.

| Version | Date | What changed |
|---|---|---|
| | | |
