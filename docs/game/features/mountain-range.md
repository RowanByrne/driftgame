# Feature: Mountain range

**Status:** specced (plan for the user). Builds on `road-on-the-slope.md` (T-226) and the mesh ground picked in `ground-trial.md`. Replaces nothing of `road-biomes.md`, which was rolled back. That spec chose biome stretches at random from the seed; this one reads them off where you are on the mountain.

## Goal

The run crosses a real-shaped mountain range: it climbs to passes, runs along ridges, drops through valleys and climbs again, so runs go up as well as down and can last hours without reaching the bottom of the world. Where you are on the range (high, steep, on a ridge, in a valley) sets the biome you drive through, aiming at the six environment mood images in `ART-DIRECTION.md`.

The user, 2026-11-15 (C-dd9f36): "we basically create a realistic shaped mountain range as the mesh terrain surface, and the road gets put on it. we go up and down, we go along ridges, through passes, down through valleys, etc. i want us to detect where we are and use that to determine the biome we will be in, like the concept art you stored earlier. when up high, that can be made a snowy peaks section, etc". Explainer pictures: `art/generated/mountain-passes/pass-aerial-01.png`, `pass-profile-01.png` (outside git).

## How it plays

1. A run starts low on a range. The road climbs a face in switchbacks that hug it (DECISIONS.md, 2026-11-15, hairpins hug the steep face).
2. It reaches a pass, a saddle between two peaks. It crests, and the next valley opens below.
3. It descends the far side, sometimes runs along a ridge with drops on both sides or along a valley floor beside a river line, then climbs to the next pass.
4. The scenery changes with the ground under you, blending over a stretch of road, never popping:
   - snow high up;
   - open grassy ridges;
   - forested steep faces;
   - wet, dark valley bottoms;
   - and so on.
5. Height stays within a band. The road never reaches Roblox's fall-kill height however long the run.

## Left out

- Props: trees, rocks, rails beyond today's, shrines, lamps, waterfalls and rivers as objects. The biome is ground colour and material, sky, fog and light first; props come in a later feature.
- Weather systems (rain, snow falling): open question below.
- Changes to the drift model, the car, the score or the tarmac's width.
- Driving off the road into the range.

## Rules and numbers

Starting values, tuned in a lane:

- **The range, h(x, z):** still one pure function of seed and position, the same on every device, and still the thing the road follows ("The mountain leads, the road follows", `road-on-the-slope.md`).
  - Ridges lie roughly across the run's way, about 3 000 to 8 000 studs apart, each with saddles a few hundred studs lower than its peaks.
  - Valleys lie between the ridges, with spurs and side ridges off the main ones.
  - Peaks rise 600 to 1 200 studs above the valley floors.
  - The whole range sits in a height band whose bottom is well above -500, the fall-kill height.
- **The road's route:**
  - Heads for the next pass: the lowest good saddle in the ridge ahead.
  - Climbs to it as switchbacks on the face, crosses it, and descends into the valley.
  - May follow a ridge or valley floor when that is the way on.
  - Grade, curve and hairpin rules as today: at most 8 degrees, and hairpins hug the face.
  - Climbs are as common as descents over a long run.
- **Where you are:** a pure function of position that reads h. It works out the height in the band; the slope; whether the spot is a ridge, valley, face or pass (from the curvature of h); and the distance to the nearest crest. Every device gets the same answer.
- **Biomes from where you are**, first mapping, from the mood images:

  | Where | Biome | From |
  |---|---|---|
  | High, above the snow line | Snowy pass: snow ground, alpenglow, cloud sea below | `snow-pass-sunset` |
  | Open ridge or high shallow ground | Pampas ridge: pale grass, wind, open sky | `moonlit-pampas-ridge` |
  | Steep faces, mid height | Maple cliffs: pale rock, red-orange canopy colour | `autumn-maple-cliffs` |
  | Low, gentle slopes | Sakura: soft pink and green, warm dusk light | `sakura-shrine-dusk` |
  | Valley bottoms | Cedar forest: dark greens, damp, low light | `rainy-forest-night`, `waterfall-gorge-rain` |

  Biomes blend over about 300 to 600 studs of road where two meet.

## UI

None. The biome name might show briefly on entering one; that's an open question.

## Server and client

- The server lays the road, as now.
- The range and the biome are pure maths, so the server and every client compute the same ones from the run's seed.
- Clients draw the ground, colour it and set the sky, fog and light by biome.
- Nothing is sent but the seed, as now.

## Contracts

- `Road/Ground`'s field gains the range. A new `Biome.at(field, x, z)` (or similar) returns the biome and blend weights.
- Rows added to `CONTRACTS.md` with the code.

## Analytics

None yet.

## Monetization

None.

## Platform risks

None.

## Art and sound

All placeholder: ground colours and materials, and lighting presets per biome. Final looks come with the environment work after this.

## Testing

- **GroundTests extended:**
  - h stays inside its band on 20 seeds.
  - A run of 50 000 studs never goes below the floor.
  - The share of road climbing is about the same as descending.
  - Passes are found and crossed.
  - Trench and causeway shares stay as low as `road-on-the-slope.md` measured.
- **Biome tests:**
  - The same biome on server and client.
  - Blends are continuous.
  - Each biome appears on a long run.
- **Live in a lane:** drive over a pass, and check the ground is drawn the same, there are no seams, and the cost per frame stays as today.

## Open questions

- Does a biome bring its own time of day and weather (the mood images each have one: dusk, night, rain, sunset), or only its land, with the day-night cycle carrying on as now?
- Should the biome's name show on screen when you enter one?
- How long between passes: about one every few minutes of driving, or longer?
