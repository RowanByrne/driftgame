# Feature: Garage and car customization

**Status:** approved 2026-11-10 (T-100), building: T-101 catalog (built: the catalog, fitting and saving, no drawing), T-102 room, T-103 menus, T-104 paint and wheels, T-105 kits, T-106 feel. **Owner task:** see `docs/CLAIMS.md`.

## Goal

A garage where the player works on their car: change how it looks and how it drives, across seven categories, and keep what they built. This is the scaffolding: every category works end to end with placeholder parts and programmer UI, so real parts, art and (later) prices drop into a frame that already works.

## How it plays

1. **Get into the garage.** Drive into the garage's door in the playground (or press **Garage** on the HUD). The car rolls onto a turntable in the garage interior, and the camera frames it.
2. **Pick a category** from a row of tabs: Engine, Suspension, Wheels & tyres, Body kits, Underglow, Interior, Paint & wraps.
3. **Pick a part** from the list. The car shows it straight away (a preview); the camera turns to where the part is (the wheels, the underside, the cabin). Performance parts show what they change as bars: before and after.
4. **Keep it or not.** **Fit** keeps the part on the car; backing out of the list goes back to what was fitted.
5. **Leave.** **Drive out** puts you back in the playground in the car you built. It is saved and is there next time you play.

Something going wrong: a part the server won't accept (not in the catalog, or a combination it refuses) goes back to what was fitted, and the list says why.

## Left out

- Prices, currency and unlocks: everything is free and unlocked. Meta progression is still undecided (GDD.md "Open after the prototype").
- Real part art: every part is programmer art (boxes and colours) until it's made through ART-PIPELINE.md.
- A wrap editor (stickers, layers, drawing): wraps are a short list of presets.
- More than one car, and selling or trading parts.
- Other players visiting your garage. Each player's garage is their own interior; others see the result in the playground.

## Rules and numbers

**The catalog** (`Shared/Customization`, one table): every category, its parts, and what each part does. Adding a part is a line of data, never code. Start with 3 to 5 placeholder parts per category, plus "Stock".

| Category | Kind | What a part changes |
|---|---|---|
| Engine | performance | Acceleration and top speed, within bounds |
| Suspension | performance and looks | Ride height and stiffness (the v2 suspension, `car-v2.md`), and a little of how the car corners |
| Wheels & tyres | looks and performance | The rim and tyre models, and tyre grip a little |
| Body kits | looks | Bumpers, side skirts, spoilers, fender flares, as parts on the rig's kit slots |
| Underglow | looks | A light under the car: off or a colour, steady or pulsing |
| Interior | looks | Roll cage, sound system, seats, steering wheel |
| Paint & wraps | looks | Body colour, a second colour for the two-tone, finish (matte, gloss, metallic), and a few wrap presets |

**Performance parts move the existing car numbers**, the same ones the tuner moves (`car-tuner.md`), and only inside bounds that keep the drift feel the user approved: no part takes a number outside the tuner's ranges, and the stock car is exactly today's car. Starting bounds: up to ±15% on what each part touches.

**A built car is saved** as `{ base, parts = { [category] = partId }, paint = {...} }` next to the tuner's saved cars, in the same small dev store (GarageService); it moves into the real save system when that's built.

### What the first step built (T-101)

The shapes, the remote and the attributes are in `CONTRACTS.md` "Customization"; this is what they hold.

- **The catalog** (`Shared/Customization/Catalog.luau`): six part categories of stock plus four placeholder parts each, and paint as four choices: 9 colours plus `stock`, 3 finishes plus `stock`, 4 generic wraps plus `none`. **Every name, look and number is a placeholder** for the menus and the drawing to work on; the user names and picks the real ones.
- **Which numbers each category may move**, one owner per key so a whole build stays inside ±15% on every key:

| Category | Car keys (tuner slider) | The parts, today |
|---|---|---|
| Engine | `MaxAcceleration` (Power), `TopSpeed` | +5/+3%, +10/+5%, +15/+10%, and long gears −8/+15% |
| Suspension | `MaxSteeringSpeed`, `MaxFriction`, `SlipSqFriction`, `DownforcePerSpeed` | lowering springs, two coilovers, lifted: 5-10% moves, plus ride height (−0.4 to +0.3 studs, drawn only) and stiffness (0.85 to 1.4 ×) |
| Wheels & tyres | `ConstantFriction` (Grip), `SlipFriction` (Catch) | mesh rims (looks only), deep dish +3% grip, semi-slicks +12/+10%, drift tyres −8/−5% |
| Body kits, Underglow, Interior, Paint | none | looks only |

- **Stock is today's car to the bit:** a stock build resolves to each archetype's own numbers, unclamped and unsnapped. A moved number is `own × (1 + fraction)`, snapped to the tuner slider's step, and on all four archetypes every combination of the three performance categories (125 builds each) stays inside every slider's range before any clamping.
- **Fitting:** one ask per part or paint change, checked against the catalog only. The server refuses a fit until the player's saved build has loaded, so a quick fit can never overwrite a saved build that hadn't arrived yet. A refusal answers with the whole build the server believes, so the menu can go straight back to it.
### Parts change the feel (T-106)

- **A build is a layer on the car,** between the archetype and the tuner: `Cars` resolves Base, then the archetype, then the build, then the tuner (`Cars.setBuild`, `Shared/Cars`). `Config.Drift` resolves through it on every read, so a Fit changes the car on the next simulation step; nothing in the model changed.
- **The tuner moves from the build.** A slider the dev tuner has moved wins for that one number; letting go of it gives the build's number back, and the tuner never clears the build. The tuner's knobs still draw the archetype's own numbers for sliders it hasn't moved (it doesn't know the build): it's a dev tool, and this is its price.
- **The parts go with the player into whichever car they're in now.** `base` (`Fit_Base`) records the car at the last fit, but each part moves the car being driven by its own fractions: `Customization.carFields(build, carKey)`, and `Customization.layer(build)` for all four cars at once, so a car switch lands on the right numbers. The menu's before/after bars still read `base` (T-103's), so after a switch they show the old car until the next fit.
- **On the driving client,** `Shared/Cars/BuildFeel.follow(LocalPlayer)` watches the player's own car's `Fitted` and sets the layer from its `Fit_*` attributes. `PartsFeelController` starts it. **On the server,** `CustomizationService` hands each real player's build to `CarService:SetBuild` on load, fit and every publish, and every `CarState` bound uses their car with the build over it (`CarService:_numbers`). A build that lowers top speed opens `CarSwitchGrace`, as a car switch does. The dev tuner's server-wide `TopSpeed` ceiling can only raise a built car's bound, never pull it below the build.
- **Measured** (`PartsFeelTests`, 9 checks, all passing, 2026-11-10, `DR-Lane4`): a stock build is all 32 numbers `==` and DriftTests' corner point for point (gap 0); on a straight the race engine goes 178.99 → 196.99 studs/s (+10.06%, part +10%) and long gears → 205.98 (+15.08%); the server's bound 223.75 → 246.25 and a packet at 245 is taken; 8,400 moved numbers (4 saved bases × 4 cars driven × 125 builds) all inside the tuner's ranges; one step's push ×1.145 against power ×1.147 the step after a fit. In a playtest a real Fit moved the server's bound 179 → 197 and back, and the client's `Config.Drift.TopSpeed` 179 → 197 → 179 through `BuildFeel`.
- **Stock is still today's car to the bit:** a stock build is an empty layer. **Suspension parts move only their four tuner numbers** (rate of turn and the grip curve): ride height and stiffness are still drawn only, because the v2 suspension's numbers (`Config.Drift.Suspension`) are the model's, not the car's, and moving them per car needs a `Config/Drift` change that wasn't asked for yet.

## UI

Programmer UI, as the user asked: plain frames and text, built to the layout below, styled in the UI phase.

- **Tabs** across the top for the seven categories.
- **Part list** on the left: name, a "fitted" mark, and for performance parts, bars for what changes.
- **Paint** has a colour grid and a finish picker in place of a list.
- **Buttons:** Fit, Back, Drive out. Works with touch, mouse and gamepad.

## Server and client

- **The server decides** what a car is: the client asks to fit a part, the server checks it against the catalog and saves it. It also applies the performance numbers to that player's car (as it already bounds speed per car, `CarService`).
- **The client** shows previews before asking, and draws the parts, paint and underglow on every car it draws, from attributes the server sets on the car.

## Contracts

In `CONTRACTS.md` "Customization" (T-101): the catalog's shape, the saved car's shape (a `build` key beside `cars` in the dev store), the remote `CustomizeFit` (ask, and its answer on the same remote), the car attributes that carry what's fitted (`Fit_*` and `Fitted`), and the kit and interior slot names the drawing steps add to the rig.

## Analytics

`GarageOpened`, `PartPreviewed`, `PartFitted` (category, part), when analytics are built (EVENT-CATALOG.md). They become the main signal for what to make next.

## Monetization

None yet. Customization is the obvious place for it later (REVENUE.md), so the catalog keeps room for a price and a "how you get it" per part, unused for now.

## Platform risks

- **Wraps and body kits must not copy real brands** (no real logos, sponsor decals or licensed kit designs; PLATFORM-RISKS.md "Copyright").
- **Paid random items:** none; nothing here is random or paid.

## Art and sound

- **The garage interior:** built to the picked concept, `assets/garage-concept/garage-01.png` (the dusk street garage, 2026-11-10): grey-box first, the real art later.
- **Parts:** programmer art. Fit and paint sounds: Creator Store candidates later.

## Testing

`ServerScriptService/Tests/CustomizationTests.luau` (`DebugCustomizationTests`), with a fake store and stand-in players. **18 checks, all passing, 2026-11-10 (`DR-Lane3`):**

| Check | What it reported |
|---|---|
| Seven categories, stock plus 3-5 parts | 5 parts in each of six; paint 10 colours / 4 finishes / 5 wraps |
| Every part valid, every field present | 0 problems; 30 parts, all price 0, unlock `"free"` |
| Performance inside ±15%, one owner per key | 21 numbers, the largest 15%; 8 keys |
| **No build leaves the tuner's ranges** | 500 builds × 8 keys on the four cars, all inside before clamping; the tightest 3.5% of a range from its edge |
| **Stock is today's car exactly** | 32 numbers on 4 cars, every one `==` the archetype; no tune, delta or look |
| A part moves only its own numbers | 88 numbers; race build on balanced: power 14.3 → 16.4, top speed 179 → 197 |
| **Bad asks refused** | 26 of 26 by the catalog and 26 of 26 through the real handler, build and store untouched |
| A flood | 8 of 40 taken |
| A fit before the store answers | refused `loading`, nothing written |
| **Fit, save, forget, rejoin** | a build in all seven categories came back equal, with a tuned car beside it kept |
| Old and damaged saves | a garage with no build loads as stock with its cars; unknown parts and colours become stock, the rest kept |
| **The car carries the build** | 11 `Fit_*` attributes plus `Fitted`, read back equal; a refit moves `Fitted` 1 → 2 |

**In a quiet playtest:** a client fired `CustomizeFit` itself: the question, an engine part and a paint were answered `ok` and reached its car's attributes (`Fitted` 1 → 3), and an engine ask naming a wheel part was refused `wrong category`. The player was then forgotten and re-joined through `GarageService`: the build came back and was republished on the car. A car switch kept the attributes. GarageTests 24, DriftTests 50, PlaygroundTests 76, RigTests 11 and GarageRoomTests 14 all still pass, and the console was clean of game code.

Still to test, in later steps:

- The catalog: every part valid, every performance part's numbers inside the tuner's ranges, stock equals today's car exactly (done, above).
- Fit each part in each category in a lane: the car shows it, the server saves it, rejoin keeps it, other players see it.
- The drift tests pass unchanged with the stock car.

## Open questions

- **Do engine and suspension change how the car drives,** or only how it looks? Proposed: they do, a little, inside the approved feel.
- **Where the garage is:** a room in the playground you drive into, as proposed, or a menu you open anywhere.
