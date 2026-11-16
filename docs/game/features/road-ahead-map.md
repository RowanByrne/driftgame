# Feature: Road ahead map

**Status:** built (T-236), with the user to try in a lane.

## Goal

A small see-through map in the top left of the screen shows the shape of the road ahead and its coming turns, with an arrow where the car is. That way a player can set up a drift before the bend comes into view.

The user, 2026-11-15 (C-5a24c5): "can we add a feature that shows the upcoming turns and road shape, with a small arrow where the player is? like a minimap but it's transparent and sits top left of your screen?"

## How it plays

1. In a run, a transparent panel sits in the top left.
2. The road is drawn as a line:
   - **Ahead:** about 800 studs of road.
   - **Behind:** a short tail of about 100 studs.
   - **Road-up** (the user, 2026-11-15): the road's direction at the car is up, so the map turns only as the road bends, eased over 0.35 s. The arrow sits near the bottom middle and turns to show the car's nose against the road, drift included.
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

`RoadMapController` with `DebugState()` (shown, the points drawn, studs ahead and behind, the car's place on the road, the cost), `DebugCheck()` (the drawn pixels measured back against the spline) and `DebugFixture(name)`; `PlayerGui.RoadMap`. In `CONTRACTS.md`.

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

- ~~Heading-up or north-up~~: decided, road-up (DECISIONS.md, 2026-11-15).
- **Off switch:** should it have a Settings toggle, or a size slider?

## Built (T-236)

- `Shared/Config/RoadMap` (every number), `Drift/RoadMapView` (the view) with `RoadMapView.fixtures`, `Controllers/RoadMapController` (its feed), `UI/Layers.RoadMap` = 12.
- Points on a fixed 16-stud grid along the road plus the car's own place, so the line doesn't crawl. The line is cut at the panel's inner edge by hand: rotated frames are not clipped by their parent.
- Measured in DR-Lane2, 2026-11-15, the car stepped along 2,290 studs of a real run at 80 studs/s (a 79-stud bend included): every drawn point within 0.000001 stud of the spline; the arrow within 1.2 px (5.7 studs) of the line; the map's up never turned more than 4.2 degrees between redraws, lagging the road by 29 degrees at most in the tightest bend; the arrow never jumped more than 1 px. Cost 0.15 ms a redraw on average at 20 a second (1.5 ms once, building the pool). Car 600 studs off the road: the map holds its last place; 50 studs off on the grass: the arrow sits beside the line.
- Layouts measured: HD 1080 (220 px, top left), iPhone 13 Pro landscape 750 x 390 and iPhone 7 landscape 667 x 375 (140 px, top left), iPhone 13 Pro portrait 390 x 763 (140 px, dropped below the score panel to 146 px). It overlaps none of the run button, its line or the score panel at any of them. On iPhone 7 landscape its bottom edge reaches the top of the test-only buttons (bottom left, not shipping).
