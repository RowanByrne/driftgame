# Feature: Road ahead map

**Status:** specced (plan for the user).

## Goal

A small see-through map in the top left of the screen shows the shape of the road ahead and its coming turns, with an arrow where the car is. That way a player can set up a drift before the bend comes into view.

The user, 2026-11-15 (C-5a24c5): "can we add a feature that shows the upcoming turns and road shape, with a small arrow where the player is? like a minimap but it's transparent and sits top left of your screen?"

## How it plays

1. In a run, a transparent panel sits in the top left.
2. The road is drawn as a line:
   - **Ahead:** about 800 studs of road.
   - **Behind:** a short tail of about 100 studs.
   - **Heading-up:** the car's arrow stays fixed near the bottom middle of the panel pointing up, and the road turns around it.
3. Hairpins and tight bends are easy to read. The line is drawn a little thicker or brighter through them.
4. **Off the road:** when the car is off the road or respawning, the map stays on the road's line nearest the car.
5. **Outside a run:** in the playground and garage, there is no map.

## Left out

- Terrain, other players' cars, a full-world map, zoom controls.
- A setting to turn it off: open question below.

## Rules and numbers

Config in `Config/RoadMap` (new), starting values:

| Setting | Value |
|---|---|
| Size on PC | 220 px square |
| Size on phone | 140 px square |
| Margin | 16 px |
| Road ahead | 800 studs |
| Road behind | 100 studs |
| Points along the line | One every 16 studs |
| Redraw | 20 times a second |
| Panel transparency | 0.6 |
| Line | Off-white, 0.15 transparent |
| Tight bends | Orange (`#f29e52`), on bends of radius 220 studs or less |

## UI

- A new HUD piece in the top left, which `UI-INVENTORY.md` gains.
- Programmer art until the UI phase, but it uses the colour tokens from the settings style.
- It must not cover the score HUD (top middle) or the phone's top-left Roblox buttons. On phones it moves down below them.
- It is checked at the smallest phone layout and at 1080p.

## Server and client

Client only. The client already has the whole spline road (`SplineWorld`/`SplineRoadView`), and the map reads it. Nothing is sent.

## Contracts

`Drift/RoadMap` with `DebugState()`: shown, the points drawn, studs ahead and the car's place on the road. Added to `CONTRACTS.md` with the code.

## Analytics

None.

## Monetization

None.

## Platform risks

None.

## Art and sound

- The arrow and line are native UI: frames, or a few rotated frames for line segments.
- No new images.

## Testing

- Live in a lane, the line's points match the spline ahead to within a stud.
- The car's arrow is on the road's line when the car is on the road.
- It updates through a hairpin with no jumps.
- Cost: under 0.3 ms a frame.
- A screenshot at PC and at phone size.

## Open questions

- **Heading-up or north-up:** heading-up is the default, as most racing maps do.
- **Off switch:** should it have a Settings toggle, or a size slider?
