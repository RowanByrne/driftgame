# Feature: Score events

**Status:** draft, for the user's OK (written 2026-11-17, from the user's "big system time" request). Would become `docs/game/features/score-events.md`. **Owner task:** none yet.

## Goal

Drifting is the only way to score today. The user asked for more: *"lets add some ways to add to your score other than what we have now which is just drifting. we can call these score events ... they will fall into a few categories"*: **one-off events** (a near miss, a jump: one boost, sized by how close or how big) and **sustained events** (a bumper grind, a hang grind, a wheel lift: held as long as you can, like the drift itself), *"with UI displaying the events as they trigger or accumulate like a FPS game XP killfeed thing."*

This is the first part of a bigger score expansion. It builds the event system, the feed, and the events the game's world can already produce; events that need things the game doesn't have yet (traffic, opponents, collectibles, ramps, kerbs) are listed for later.

## What exists today (read off the code, 2026-11-17)

- **The score** is the endless run's only (`endless-score.md`, T-119): all on the client, nothing saved, nothing shown to anyone else. Each simulation step (1/120 s) while the car drifts forward: `points = slip × speed × surface × ScoreRate`, times the rung.
- **"The meter" is the multiplier ladder:** a bar under the score fills while you drift and drains while you don't (faster the higher you are); a full bar is the next rung, x1 to x9. In the air the bar holds.
- **Nothing banks and nothing fails.** Points go straight into the score as they are earned and are never taken away (the user, T-119: *"don't do the wall hit yet. for now just basic scoring"*). A fall or a wall costs nothing; only the ladder drains.
- **No server check.** No remote carries the score; the server never sees it. That's safe only because nothing is saved, ranked or rewarded.
- **Measured:** a steady drift on the real car is about 25° at 84 studs/s, about **10 points a second at x1**, and tops out at about x4. Event sizes below are set against that.
- **No analytics helper exists in code yet**, so no events can be sent (same as the endless score).

### The signals each event needs

| Event | Signal | There today? |
|---|---|---|
| Jump | The car is in the air (`state.airborne`), its vertical speed, the ground height it left (`fallFrom`), and a fall (`state.fell`) or put-back (`CarRespawn`) | **Yes.** But the endless road has no ramps: air comes from sharp crests at speed, the 1-stud drop off the tarmac's edge, and going over a steep drop beside the road. How often a real jump happens on a run must be measured |
| Wheel lift | Each wheel touching the ground (`state.wheelsDown`, FL FR RL RR) while the car is on the ground | **Yes**, per wheel, every step. But there are **no apex kerbs** on the road: the tarmac's edge is a 1-stud step **down** to the grass, so a lift happens over crests, banking changes and that edge, not over a kerb. A kerb is a later road task |
| Bumper grind | Which wall was hit, by which part of the car, how hard | **Half.** The road's world (`Drift/SplineWorld`) already works out the wall's kind (K-rail, rock cut, tree, closing barrier) and which of the car's six outline points touched (front corners, middles, rear corners), then throws both away; the model keeps only "a wall was hit" and its direction. Contact is also patchy: **about one step in twelve** even when held against a rail (T-074), so a grind needs a short grace. A small, look-only addition to the model's state carries them through |
| Hang grind | The floor resting on an edge while wheels hang (`state.hanging`, `state.floorContacts` with `edge`, `wheelsDown`) | **Yes.** It's what lights the floor sparks (`Drift/Scrape`). Where: the edge of a steep drop beside the road (car-edges, T-258). Tight cliff edges have a K-rail over them, so the drop is reachable only where no rail stands; how often must be measured |
| Near miss | Something solid to pass close by | **Some.** Grove tree trunks (solid, placed from a seed, `Road/SplineGrove`), K-rails, rock cuts, and **other players' cars** on the same road (`Drift/RemoteCars`, which also knows if they're drifting). **No traffic** and no cones on the road |
| Apex clip, edge drift, wall proximity | Where the car is across the road (`SplineWorld.locate` → along, across), the bend's tightness (`curvatureAt`), runoff widths, K-rails (`kRailAt`), which side the drop is on (`uphillAt`) | **Yes**, all from the road's own maths |
| Switchback, long drift, deep angle, save | The slip angle and its sign, speed, forward travel | **Yes** |

## How it plays

1. Start an endless run. The score panel is where it was: score, rung, bar.
2. **Do something.** Clear a crest: as the wheels come back down a line drops in under the score: `BIG AIR +420`. The bar jumps forward a chunk; a big one can tip you onto the next rung.
3. **Hold something.** Swing the tail into a K-rail and keep it there: a line appears, `BUMPER GRIND`, its points counting up live while the sparks fly. Lose the rail for more than a moment and the line stops, flashes, and its points fly into the score. While you hold it, the bar fills and doesn't drain.
4. **Stack them.** A grind during a drift scores both. A wheel lift in the middle of a grind is a second live line. Several near misses in a row merge into one line: `NEAR MISS x3 +540`.
5. **Repeat the same trick and it's worth less.** The same one-off again within a few seconds is worth half, and the same spot again (driving back to re-jump a crest) is worth nothing.
6. **Fall off mid-grind** and that line turns red and reads `LOST`: its points never reach the score. Points already in the score are never taken away.
7. END RUN shows the summary as now (a "best event" line is a later option).

## Left out

- **Penalties.** No cost for a wall hit, a crash or going onto the grass, as before (T-119). Only a fall or put-back voids a sustained event still in progress.
- **Events needing systems the game lacks:** traffic, opponents, collectibles, ramps, apex kerbs, judged zones (see "Later").
- **Saving, leaderboards, rewards.** Unchanged: nothing about the score is saved or ranked, so the server still doesn't check it (see "Server and client" for how it will).
- **Score outside the endless run.** The playground and garage stay unscored.
- **Sounds and final art.** Programmer UI; a sound per event is a later art step.
- **Analytics** until the analytics helper exists.
- **Other players' feeds.** Each player sees their own.

## Rules and numbers

### The two kinds

**A one-off event** happens at a moment and is then over (a jump lands, a near miss passes).

- **Points** = the event's base, scaled by its size (how big, how close), **times the current rung**, straight into the score.
- **Meter kick**: it pushes the bar forward by its `Kick` share of a rung, scaled by its size. **One event can climb at most one rung**: the kick is capped at whatever fills the current bar, plus a little toward the next (`MaxKick`).
- It starts a feed line that shows its name, a size word, and its points.

**A sustained event** is held (a grind, a lift).

- It **starts** only after its condition has held for `MinHold` seconds, so a one-step glitch never shows a line.
- **Points are earned per stud travelled while it holds,** not per second, so crawling along a rail earns almost nothing. Each step: `rate × studs this step × rung`. They collect **on the event's line**, counting up live.
- **The meter:** while it holds, the bar fills at the event's `Fill` rate and **doesn't drain**, as a drift does (it counts as scoring).
- **A short gap doesn't end it:** the condition may lapse for up to `Grace` seconds (wall contact is patchy, one step in twelve).
- **It ends** after `Grace` without its condition. Its points then **bank** into the score, and the line flashes and fades.
- **It's lost** if the car falls or is put back on the road before it ends: the line turns red, `LOST`, and its points never bank. (Option B below, the user's choice.)
- **A held event that runs long is capped** at `MaxSeconds`: it banks and a fresh line starts, so one endless grind can't run up unbounded points without being seen.

**The drift itself is unchanged.** Its points still pour into the score live, and its maths and numbers are untouched. Events are added on top: a grind during a drift scores both.

### Anti-farming

- **Repetition:** the same one-off kind within `RepeatWindow` (10 s) is worth `RepeatFactor` (×0.5) of the last, compounding; a different kind resets nothing.
- **The same spot:** a one-off whose position along the road is within `SameSpot` (40 studs) of the same kind in the last 60 s earns nothing (a crest jumped twice by driving back).
- **Forward only:** events count only while the car makes forward progress along its nose (as the drift does), above each event's `MinSpeed`.
- **Not while pinned:** nothing counts while the model says the car is pinned against a wall and crawling (`state.pinned`, T-074).
- **A ceiling:** all event points together may not exceed `MaxEventRate` points a second at x1, averaged over 5 s (the server's bound later uses the same number).

### The first events (recommended to build now)

| Event | Kind | Starts / fires when | Size | Ends / lost | Starting numbers |
|---|---|---|---|---|---|
| **Jump** (`JUMP` / `BIG AIR` / `HUGE AIR`) | one-off | The car lands after at least `MinAir` 0.4 s in the air, moving forward, and stays down 0.2 s without a fall or put-back | Air time, and the drop from takeoff to landing. Words at 1 s and 2 s | No points if it lands in a fall or a put-back | Base 40 at 0.5 s, growing as air time^1.5, capped at 400 before the rung; `Kick` 0.3 → `MaxKick` 1.1. **+50%** if it lands still drifting (`DRIFT LANDING`) |
| **Bumper grind** (`BUMPER GRIND`) | sustained | A front or rear corner of the car touches a K-rail or rock cut, sliding along it at least 40 studs/s, hitting it gently (into-speed under 25 studs/s) | Studs slid along the wall | `Grace` 0.25 s without contact; lost on a fall | 0.25 points a stud (at 80 studs/s, 20 a second: twice a drift); `Fill` 0.35 a second; `MaxSeconds` 15. A middle-of-the-door touch is a `WALL SCRAPE` at half rate (or nothing: the user's call) |
| **Hang grind** (`HANG GRIND`) | sustained | The floor rests on an edge, both wheels of one axle hang off it (the user's: the two rear), and the car keeps sliding at least 30 studs/s | Studs slid | `Grace` 0.2 s; lost if the car goes over (fall or put-back) | 0.4 a stud; `Fill` 0.5 a second; `MaxSeconds` 10. Front axle hanging also counts, same rate |
| **Wheel lift** (`WHEEL LIFT` / `TWO WHEELS`) | sustained | The car is on the ground, not hanging, with 1 wheel off for `MinHold` 0.15 s (`TWO WHEELS`: both on one side) | Studs travelled | `Grace` 0.1 s | 0.12 a stud (0.3 for two wheels); `Fill` 0.2 a second; `MaxSeconds` 6 |
| **Switchback** (`SWITCHBACK`) | one-off | The slip flips from at least 15° one way to at least 15° the other within 1.2 s, without the drift dropping out | The angle swung through | — | Base 30 at 30° of swing, up to 120; `Kick` 0.25 |
| **Near miss** (`NEAR MISS` / `CLOSE CALL` / `PAINT SWAP`) | one-off | Passing a tree trunk or another player's car within 3 studs at 50 studs/s or more, touching nothing for 0.5 s after | The gap: words at 1.5 and 0.5 studs | A touch within 0.5 s voids it | Base 25 at 3 studs to 100 at 0.5; `Kick` 0.15 → 0.4. Each tree once; each player's car once per 5 s. **No traffic exists**: on a solo run this event fires only off trees, which stand in the runoff, so it is rare until traffic or roadside objects exist |

The user named jump, bumper grind, hang grind, wheel lift and near miss. Switchback is added because it needs nothing new and happens on every run, so the feed is never empty while the rarer events are being tuned. Near miss is in, with the caveat in its row.

**Hang grind and wheel lift may be rare on today's road** (no kerbs; few railless drops). The first step measures how often each fires on a 5-minute run on a fixed seed, so the user can decide whether a road task (apex kerbs, ledges) should follow.

### Later: suggested events

**Buildable now** (the signals exist):

| Event | Kind | What |
|---|---|---|
| Long drift | one-off milestones | `5 S DRIFT`, `10 S`, `20 S` of unbroken drift. Cheap and frequent |
| Deep angle | sustained | Holding more than 60° of slip at speed, without passing 90° |
| Save | one-off | The slip passes 90° (the car starts to spin) and is brought back under 45° while still rolling forward, within 0.6 s. The reference's own reverse-drift bonus (`ReverseDriftBonus`) is a version of this |
| Apex clip | one-off | At the tightest point of a bend, drifting, with the car's inside within 2 studs of the tarmac's inside edge. The touge "clipping point" |
| Wall kiss (proximity) | sustained | Drifting with the car's outside corner within 2 studs of a K-rail or rock cut **without touching**. The safe-but-close version of the grind; a touch turns it into a grind |
| Edge drift (danger) | sustained | Drifting with a wheel within 3 studs of a drop with no rail. Pairs with hang grind |
| Hairpin | one-off | Drifting through a whole bend tighter than radius 120 without the drift breaking. `HAIRPIN` |
| Tandem | sustained | Drifting within 15 studs behind another player who is also drifting (the server already relays whether they drift). Multiplayer only |
| Overtake | one-off | Passing another player. Multiplayer only |
| 180 / 360 | one-off | A full spin that recovers and drives on. Low priority: on this road a spin is usually a mistake |

**Need a future system:**

| Event | Needs |
|---|---|
| Near miss on traffic, traffic dodge | Traffic cars on the road |
| Tandem / chase on AI, overtake on AI | Opponents |
| Token, gate, drift zone, clipping zone | Collectibles or judged zones placed by the road generator |
| Kerb lift (the user's apex-curb wheel lift) | Apex kerbs: a road task (generator and road mesh) |
| Ramp air, gap jump | Ramps or jumps on the road |
| Smash (cones, signs) | Breakable roadside props |
| Clean section, perfect line | A section to be judged on (what a run is: still undecided in PITCH.md) |
| Night drift, wet drift bonuses | Weather; a time-of-day bonus could use day/night now, but it's a tuning call, not an event |

### Numbers

All in `Config.Score.Events`, one table per event, plus the shared ones: `RepeatWindow` 10 s, `RepeatFactor` 0.5, `SameSpot` 40 studs, `MaxEventRate` 60 points a second at x1, `MaxKick` 1.1 rungs, `FeedLines` 5. All starting guesses, to be tuned by driving.

## UI

One new screen, **the score feed** (`Drift/ScoreFeedView`, `PlayerGui.ScoreFeed`), in `UI-INVENTORY.md`. Programmer art from the UI kit (`UI/Theme`, `UI/Layers`), in the settings page's approved colours (smoked glass, off-white text, warm orange accent). Nothing in it is `Active`: the whole screen is the steering pad.

**Each line** is one event, on a small smoked-glass plate (text over moving gameplay needs a backing, UI.md):

- **Left:** the event's name in caps, Gotham Bold 18 px: `BUMPER GRIND`. A size word replaces or follows it where there is one: `BIG AIR`, `CLOSE CALL`.
- **Right:** its points, `+1,240`, Gotham Bold 18 px, in the orange accent.
- **A merged line** adds a count: `NEAR MISS x3`.
- **A sustained line** has a thin orange underline that pulses while it holds, and its points count up live. When it banks, the line flashes white once and the points glide up into the score panel. A lost one turns red and reads `LOST`, with its points struck through.
- The **multiplier** the points were earned at is already inside them; the line doesn't repeat it.

**Timing:** a new line slides in at the top of the stack in 160 ms, pushing older ones down. A one-off stays 2.5 s; a banked sustained line 2 s; both fade over 0.4 s. A live sustained line stays as long as it holds. The same one-off within 1.5 s merges into its line (count and points add; its clock restarts). Most `FeedLines` 5 lines (3 on a phone): past that the oldest finished line fades out at once; live lines are never pushed out. With Reduced Motion on, no slide and no flash: lines appear and fade.

**Where:** directly under the score panel, in its centre column (the eye already goes run button → score), from 146 px below the inset, 220 px wide like the panel.

- **Desktop and phone landscape:** that column, 5 and 3 lines.
- **Phone portrait:** the road map already drops below the column on the left at 146 px, so the feed sits right of the map, right-aligned, 3 lines, narrower (text shrinks no lower than 16 px; long names are short by design).
- It sits under the score panel's `DisplayOrder` (14), at 13, over the drag pad (5), and goes away with the HUD (menus, P).
- **Drag mode** lets the user try it elsewhere (top right like an FPS killfeed, or lower centre near the car) before it's fixed.

**Fixtures:** empty; one of each event; a merged line; a live sustained line at 1,234,567; five lines with one lost; the longest name with the largest points.

## Server and client

**All on the client, as the drift score is.** The car is simulated on the client, so every signal is there, and nothing about the score is saved, ranked or rewarded, so there is nothing to cheat for yet.

Built to be checked later. When a score is first saved or ranked, the client sends at run end the total and a count and point total per event kind; the server bounds them:

- total points against the run's length and `MaxEventRate`;
- each kind against its own most-per-occurrence and most-per-minute;
- some events against what the server can see itself: it already receives each car's position, speed and whether it drifts (for other players' views), and it has the same road, so it can check that grinds happened near rails and jumps near crests or drops.

## Contracts

- **Config:** `Config.Score.Events` (new table in `Shared/Config/Score.luau`).
- **New client module `Drift/ScoreEvents`** (pure, like `Drift/Score`): `new()`, `Step(dt, state, road?) -> { Event }` (what started, grew, ended, banked or was lost this step), `Reset()`, `Get()`. An event: `{ id, kind, word?, size, points, live, state = "live" | "banked" | "lost" }`.
- **`Drift/Score`** gains `Award(points, kick)` (a one-off: points × rung, the bar pushed, at most one rung) and `Hold(fill)` (a sustained event's bar fill for the step, which also stops the drain). `Get()` adds `eventPoints`.
- **`ScoreController`** gains `OnEvent(fn)`, `DebugEvents()` (recent events), and Studio-only `DebugAward(kind, size)` to feed fixtures and test the feed without driving to it.
- **New view `Drift/ScoreFeedView`** and `ScoreFeedView.fixtures`; `UI/Layers` gains `ScoreFeed = 13`.
- **`Drift/Model` state** gains, read by nothing in the model itself (look-only, like the floor contacts): `wallKind` (`"krail" | "rock" | "tree" | "closing" | "other"`), `wallPoint` (`"front" | "middle" | "rear"`, `"left" | "right"`), `wallInto` (studs/s into the wall at the hit). `Drift/SplineWorld.sweep` hands its contact kind and outline point to the model by a new optional third and fourth return. **The car's motion must be the same to the bit**: `DriftTests` reproduce step for step.
- **No remotes, data keys, tags or attributes.**

## Analytics

None can be sent: there is no analytics helper in code yet. Planned for when there is, through the client reporter with an allow-list of kinds:

| Event | When | Field 1 | Field 2 | Limit |
|---|---|---|---|---|
| `RunEnded` | END RUN | `score:<band>` | `top:<event kind>` (the kind that earned the most) | 20 a session |
| `ScoreEventFirst` | The first time this session a kind fires | `kind:<event kind>` | `rung:<1-9>` | once per kind |

## Monetization

None.

## Platform risks

None: no paid items, no player text, no outside assets. Event names are the game's own text in text objects, so they translate automatically; each line is built from one whole string with placeholders (`"{name} +{points}"`), never glued in code. Sounds, when they come, follow AUDIO-PIPELINE.md.

## Art and sound

Programmer UI only. Later: a sound per kind (a short sting for one-offs, a held tone for grinds that ends in a "bank" chime), and the feed's final look in the UI phase.

## Testing

- **Unit tests (`ScoreEventsTests`),** on stand-in state sequences: each event fires, sizes and words come out right, `MinHold` and `Grace` behave (a contact one step in twelve still holds a grind), a fall voids a live line, repetition and same-spot rules cut points, `MaxSeconds` banks and restarts, one kick never climbs more than one rung, nothing counts backward or pinned, and the same drive at 30, 60 and 120 FPS gives the same points.
- **On the real model (`Drift/Sim`):** a car driven along a test wall grinds; a car driven off a ledge hangs then falls (and loses its line); `DriftTests` unchanged.
- **Feed:** each fixture drawn and measured at the UI checks' sizes (TESTING.md "Checking UI"): text at least 16 px, nothing `Active`, no overlap with the score panel, run button or road map.
- **Playtest in a lane:** a run on a fixed seed, teleported to a K-rail stretch (`Spline:kRailsIn`) to grind; driven over the fastest crest to jump; and 5 minutes of plain driving counting how often each event fires, reported to the user.

## Options for the user

1. **What happens to a grind in progress when you fall off?**
   - A. Nothing is lost: points go into the score as they're earned, like the drift.
   - **B. (recommended)** The grind's points wait on its line and bank when it ends; a fall or put-back loses them. Makes the risk real without adding any penalty for walls.
2. **Should the drift get a line in the feed?** **Recommended: not yet**; the score panel already shows it. A "drift chain" line (counting up, banking when the drift ends) is one config switch away if wanted.
3. **Where the feed sits.** **Recommended: under the score panel**, centred (right of the map on phone portrait). Alternatives: top right like an FPS killfeed, or low centre near the car. The user tries them in drag mode.
4. **The first set.** Recommended: jump, bumper grind, hang grind, wheel lift, switchback, near miss (trees and other players for now). Swap any for one from "Later".

## Build steps

| # | Step | Files | Tier | User's eye |
|---|---|---|---|---|
| 1 | **The event engine, with jump, wheel lift and switchback.** One-off and sustained kinds, kicks, `Award`/`Hold`, grace, banking and loss, repetition and same-spot rules, the ceiling. A debug readout line for live events; measures how often each fires on a 5-minute run | new `Drift/ScoreEvents.luau`; `Drift/Score.luau`; `Controllers/ScoreController.luau`; `Shared/Config/Score.luau`; new `Tests/ScoreEventsTests.luau`; `Tests/ScoreTests.luau`; `docs/game/features/score-events.md`, `endless-score.md`, `CONTRACTS.md` | heavy | Light: the numbers, by driving |
| 2 | **The feed.** `ScoreFeedView`, fixtures, merging, timing, per-layout placement, Reduced Motion, drag mode; fed from `OnEvent` | new `Drift/ScoreFeedView.luau`, `ScoreFeedView.fixtures.luau`; `Controllers/ScoreController.luau`; `UI/Layers.luau`; `UI-INVENTORY.md` | standard | **Yes:** the look and the placement in every layout |
| 3 | **Grinds.** The wall's kind, outline point and into-speed carried from the road's world to the model's state (look-only, motion unchanged to the bit); bumper grind and hang grind | `Drift/SplineWorld.luau`; `Drift/Model.luau` (state fields only); `Drift/ScoreEvents.luau`; `Shared/Config/Score.luau`; `Tests/ScoreEventsTests.luau`, `Tests/DriftTests.luau`; `CONTRACTS.md` | heavy | **Yes:** how a grind feels to hold. Save Main before pulling (big files crash Studio on sync, PROJECT.md) |
| 4 | **Near miss** (trees, other players' cars) and the cheap extras from "Later" the user picks (long drift, save, apex clip, wall kiss) | `Drift/ScoreEvents.luau`; `Shared/Config/Score.luau`; reads `Road/SplineGrove`, `Drift/RemoteCars`; `Tests/ScoreEventsTests.luau` | standard | Light: which extras, and their sizes |

Steps 1 and 2 can run side by side (the feed builds against fixtures). Step 3 touches the drift model's files and goes after any open task that claims them. A road task for apex kerbs or ledges follows only if step 1's counts show wheel lift or hang grind are too rare.

## Open questions

- Options 1 to 4 above.
- Whether a fall should also cost the ladder (today it doesn't). Recommended: no, keep T-119's "basic scoring" until a run has a structure.
- Whether `WALL SCRAPE` (a door on the rail) scores at all, or only the bumper does.

## The user's revision (2026-11-17)

The user, on the plan: *"first set i actually want: jump is actually a sustained event - the flight is the sustain; wheel lift (smaller boost, easy); bumper grind (medium boost, sort of hard); hang grind (big boost, difficult); near miss (easy, trees only, proximity to object gives higher boost). we already have 'long drift' that's what the current score system we are building on top of does. i also want to add another category: conditional events - these you must initiate the event, but then complete it in order to get the boost, and they can be static boosts or sustained boosts depending on the thing"* (full words on T-293). This replaces the first set and the extras above where they differ.

**The first set:**

| Event | Kind | Difficulty, boost |
|---|---|---|
| Jump | Sustained: the flight is the sustain (points per second of airtime, scaled by height) | |
| Wheel lift | Sustained | Easy, small |
| Bumper grind | Sustained | Sort of hard, medium |
| Hang grind | Sustained | Difficult, big |
| Near miss | One-off | Easy; trees only; the closer to the trunk, the bigger |

Switchback is out of the first set; "long drift" is the existing drift score, not a new event.

**A third kind: conditional events.** The player starts one, and only gets the boost by completing it; each is a static or sustained boost, as fits. They need a hairpin to be known ahead of the car, with an entry zone before it and its exit: the road already knows its tight stretches (`RoadTexture.centreRuns`: under 130 studs of radius, where the double yellow is drawn), which the detection builds on.

- **Perfect hairpin** (medium): a sustained drift through the whole hairpin while staying on your own side of the road (never crossing the double yellow). Two levels: a 2-wheel drift the whole way, and a 4-wheel drift the whole way, worth twice as much.
- **Scandinavian flick** (extreme): in the zone before a hairpin, a 4-wheel drift the opposite way to the hairpin; then, within a short window (about 1 s, to tune), a switch to a 4-wheel drift the right way for the hairpin; held as a 4-wheel drift through the rest of the hairpin to complete.
- **Reverse entry**: going into a hairpin, the car turns past 90 degrees towards the hairpin, so it is going backwards; it must then carry on in a drift (at least 2 wheels) through the rest of the hairpin to complete.

"2-wheel" and "4-wheel" drift mean how many tyres are sliding (past their slip gate), per wheel, from `Drift/Wheels`.

## The shared interface (built in parallel, 2026-11-17)

The user asked for the steps to run at the same time. So every step builds against this interface, written before any of them start; the engine (step 1) implements it, and each detector reaches it only through a `sink` it is given, so it can be built and tested without the engine.

**`Drift/ScoreEvents`** (client, step 1), the engine:
- `ScoreEvents.oneOff(kind: string, size: number, info: {}?)`: a one-off event; `size` 0..1 (how big, how close).
- `ScoreEvents.start(kind: string, info: {}?) -> Handle`: a sustained or conditional event begins. `Handle:update(size: number, dt: number)` while it is held (size 0..1, this frame), `Handle:finish(completed: boolean)` when it ends: `true` banks it, `false` voids it (a fall, a failed condition). A sustained event finishes `true` when let go cleanly.
- `ScoreEvents.feed`: a signal the feed listens to, fired with an entry `{ id, kind, label, points, state = "live" | "banked" | "void", rung }` whenever an event starts, grows or ends.
- `ScoreEvents.sink()`: the `{ oneOff, start }` table detectors are given.
- Kinds: `jump`, `wheelLift`, `bumperGrind`, `hangGrind`, `nearMiss`, `perfectHairpin`, `scandiFlick`, `reverseEntry`. Points per kind, difficulty, caps and diminishing repeats are the engine's (`Config/ScoreEvents`).

**Detectors** are modules in `src/StarterPlayerScripts/Drift/Events/` (one file each, owned by its step): `Detector.new(sink, rig) -> detector` with `detector:Update(dt, state)` called each frame by the drift controller with the model's state, and `detector:DebugState()`. They call only `sink.oneOff` / `sink.start` and the handles; tests pass a recording sink.

**Wiring:** step 1 adds the engine and its detectors to `DriftController`; each later step adds its own detectors there in one line each once step 1 is merged.

## As built: engine (T-295, 2026-11-17)

The interface above, exactly, in `Drift/ScoreEvents`; jump and wheel lift in `Drift/Events/Jump` and `Drift/Events/WheelLift`; every number in `Shared/Config/ScoreEvents.luau` (`Kinds` per event, `Detectors` per detector). What the interface left open, decided here:

- **Detectors are stepped once per simulation step** (1/120 s, `dt = FixedStep`), not once per frame, in `DriftController`'s step: the engine first (`ScoreEvents.step(dt, state)`), then each detector's `Update(dt, state)`, then the score's own step. So an event scores the same at every frame rate (measured: a jump off a test kicker, 70.184074 points at 30, 60 and 120 FPS). A detector that errors is warned once and skipped; it can't stop the car.
- **Adding a detector:** one line in `DriftController:_startScoreEvents`, into `self.scoreDetectors` by name: `NearMiss = require(events.NearMiss).new(sink, self.scoreRig),`.
- **`rig`** is a table of functions, each asked when wanted because each changes: `world()` (the car's world: `SplineWorld` on the road), `spline()` (the `Road/Spline`, or nil), `along()` (where the car last was along it), `car()` (the car's model).
- **The car put back** is a new state table (`Sim.newRunner`). The engine and both detectors take a different table that has a `time` as a put-back, and lose what is live; a test's stand-in states without `time` are never taken for one.
- **Bound to the run:** the engine feeds `ScoreController.score` only while `inRun`. Outside a run `oneOff` does nothing and `start` returns an inert handle (`handle.live == false`; `update` and `finish` do nothing), and a run ending loses what is live. A new run clears the repeat and same-spot history.
- **The engine itself loses every live event on a fall or a put-back**, whatever the detector does after; a later `finish` is ignored.
- **The size's scale** is `SizeFloor + (1 - SizeFloor) * size`, per kind. Labels come from the kind's `Words`, by peak size or by seconds held (`WordsBy`); `info.label` overrides.
- **Sustained points** are `Rate` a second or a stud (`Per`), with an optional `Ramp` (the jump's rate grows the longer it flies), times the scale, the repeat factor and the rung at that step. The bar gets `Fill * scale` a second, outside the drift's own `MaxProgressUp`, and doesn't drain. Nothing counts (points or fill) while the car goes backwards along its nose, is under `MinSpeed` (20 studs/s), or is pinned; `Forward = false` (reverse entry) drops only the first.
- **Conditional finish(true)** banks what collected, then adds `Static * mean scale * repeat factor` times the rung then, with `Kick * mean scale` on the bar (perfect hairpin: size 1 for 4-wheel, 0.5 for 2-wheel, `SizeFloor = 0`, so 4-wheel is worth exactly twice).
- **`MaxSeconds`** (sustained only) banks the line and carries on in a fresh one under the same handle (new `id`).
- **Anti-farming:** repeats of a kind started within its `RepeatWindow` (10 s; wheel lift 4, near miss 6) are worth x0.5 compounding. The same spot (within 40 studs, flat) as one started between `SameSpotGap` (4 s) and 60 s ago scores nothing: the gap lets a chain of lifts or trees in a row count. **The ceiling is 80 points a second at x1 over 10 s**, not the 60 over 5 s above: 300 points could not pay one Scandinavian flick (600 static).
- **The feed** gets a live entry at the start, the growing points at most every `FeedEvery` (0.05 s), and the end (`banked` or `void`); a one-off is one `banked` entry. Entries are copies. **A sustained line first shows when it has earned `ShowPoints` (1 point, rung included)**: a lift or jump that earns less (a flick of a wheel, sliding backwards) makes no line and banks what it has quietly, and one lost before then makes none either (both counted as `empty`). A conditional line shows at its start.
- **`Drift/Score`** gained `Award(points, kick) -> added`, `Hold(fill)`, `Bank(points)` and `Get().eventPoints`. With none of them called, its maths is bit for bit what it was (measured: 404.540252 x4 either way). `Config.Score.MaxKick` (1.1) is the one-rung cap.
- **Until the feed (T-296) draws them,** each finished event is printed in Studio: `[ScoreEvents] JUMP +52 x2 banked` (`Config.ScoreEvents.PrintInStudio`).
- **Debug:** `DriftController:DebugScoreEvents()` (the engine's counts per kind, live lines, last 40 finished, the ceiling's cut; each detector's own counts), and Studio-only `DriftController:DebugScoreEvent(kind, size?, seconds?)`, which fires one without driving to it (for the feed).
- **Jump:** starts after `MinAir` 0.4 s with all four wheels up (`state.airborne`), those seconds counted; size is height over the ground under the car / 12 studs; banks 0.2 s after landing (a hop inside that is the same jump); lost on a fall, a put-back, a wall touched in the air or on landing, or landing tilted past 60 degrees.
- **Wheel lift:** on the ground, not `hanging`, one or two wheels up (not three) for `MinHold` 0.15 s, gaps up to `Grace` 0.1 s bridged (before the start too). Size 0.4 one wheel, 1 both on one side (`TWO WHEELS`); banks when it ends or the car leaves the ground.

### Measured (T-295, DR-Lane3)

- **Tests:** `ScoreEventsTests` 29 of 29, `ScoreTests` 21 of 21 (5 new checks for `Award`, `Hold`, `Bank`).
- **Plain drifting is unchanged:** the real car drifting 12 s on the flat scores 404.540252 at x4 with the engine and both detectors stepped and without them, bit for bit; nothing fires.
- **How often they fire on today's road** (seed 2024, 5 minutes of a test autopilot that steers down the centre line: 12,600 studs at a mean 50 studs/s, drifting half the time, 3 put-backs or resets). The autopilot drives worse than a player, so treat these as a floor:
  - **Wheel lift is common:** 70 wheels up, 42 long enough to count (one every 7 s), 4 of them on two wheels, the longest 1.7 s. 26 earned points (13.2 s held in all, 80 points); 10 of those earned under a point, which is why a line now waits for `ShowPoints`, leaving 16 lines.
  - **Jump is rare:** 8 times all four wheels left the ground, 5 for 0.4 s or more (one a minute), the longest 1.29 s and the highest 11.9 studs. 2 scored (45 and 19 points); 3 earned nothing, sliding backwards or slow.
  - **The run:** 1,409 points, 145 of them (10%) from events; peak x3; the ceiling cut nothing.

### No farming in place (T-301)

- **Speed means ground really covered:** the engine's speed gate and per-stud points use the smaller of the velocity and how far the car truly moved since the last step (flat), so a car pressed against a rail or bouncing on the spot scores nothing.
- **A held line past `MaxSeconds` within `SameSpot` studs of where it began scores nothing** when it restarts; each kind may set its own `SameSpot` and `SameSpotGap` (`jump.SameSpotGap` 0, `wheelLift.SameSpot` 8 and `SameSpotGap` 0).
- **A jump needs to travel:** a flight counts only once it is `Detectors.Jump.MinTravel` (15) studs from take-off, and at most `MaxBounces` (1) bounce stays the same jump. Hopping in place for 30 s went from about 4 000 points to 0; the test kicker jump scores exactly as before.

### Speed (T-303)

The user: *"it's easier in slower cars to hit accurate 4 wheel lane drifts - so speed at which manuevers are done should affect the score you get from them."* Every event's points are multiplied by a **speed factor**, from the ground the car really covers (T-301's speed). Numbers in `Config.ScoreEvents.Speed`.

- **The curve:** 0.6 (`Floor`) at 30 studs/s (`Slow`) and under, rising in a straight line to 1 at 60 (`Reference`), then to 1.4 (`Cap`) at 100 (`Fast`) and over. At the reference speed an event is worth exactly what it was before.
- **Why those speeds (measured):** the real drift model, driven by T-299's slip-holding autopilot through all 11 double-yellow bends of the first 12,000 studs of seed 31337, in both lanes, three ways, arriving at 40, 60 and 80 studs/s (198 drives). Mean real speed over each completed event: lane drift 45 to 67 (median 58, 32 done), perfect lane drift 48 to 68 (15), perfect hairpin 47 to 61 (20), reverse entry 27 to 48 (median 35, 13). A bend settles the car near 55 to 60 whatever it arrives at, and a steady drift on the flat holds 84. So 60 is today's car drifting a bend well, 30 is crawling one, and 100 is faster than the AE86 carries through any of them. The autopilot's completed bends land between x0.80 and x1.08.
- **One-offs** take the factor of the speed at their moment.
- **Held and conditional events:** each step's points are times that step's own factor, and a conditional's finish (`Static`) is times the **time-weighted mean factor over the hold**. Per step, so the points earned are worth the speed they were earned at. Time-weighted, so a bend crawled through for most of it and rushed at the end is worth what most of it was, not what its last moment was.
- **The bar's fill and kick are not scaled:** speed changes the points, not the ladder.
- **Which kinds, and how much** (`Speed.Weights`, the share of the factor; default `Weight` 1):
  - **None:** wheel lift, bumper grind, hang grind. They're paid by the stud, so twice the speed is already twice the points.
  - **Half:** jump (its height already grows with speed) and near miss (it needs 50 studs/s to count at all).
  - **All of it:** lane drift, perfect lane drift, perfect hairpin, reverse entry, Scandinavian flick.
- **Reverse entry has its own speeds** (`Speed.Curves`): 18, 35 and 60 for `Slow`, `Reference` and `Fast`. It goes backwards past 90 degrees and loses half its speed doing it, so against 60 it would always sit near the floor.
- **The debug log and the Studio print show it:** each entry carries `speed` (at the moment, or the mean over the hold) and `speedFactor`, e.g. `[ScoreEvents] LANE DRIFT +142 x2 banked (58 studs/s, speed x0.95)`. `DebugScoreEvents().engine.counts[kind].speeds` keeps the last 50 events' speeds per kind.
- **Plain drift scoring is untouched:** the drift's own points never pass through the engine.
