# Feature: Garage and car customization

**Status:** specced, waiting on the user's OK (T-098). **Owner task:** none yet.

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

In `CONTRACTS.md`, in the first step's commit: the catalog's shape, the saved car's shape, remotes `CustomizeFit` (ask) and its answer, the car attributes that carry what's fitted, and the rig's kit slots (from `car-v2.md`'s rig).

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

- The catalog: every part valid, every performance part's numbers inside the tuner's ranges, stock equals today's car exactly.
- Fit each part in each category in a lane: the car shows it, the server saves it, rejoin keeps it, other players see it.
- The drift tests pass unchanged with the stock car.

## Open questions

- **Do engine and suspension change how the car drives,** or only how it looks? Proposed: they do, a little, inside the approved feel.
- **Where the garage is:** a room in the playground you drive into, as proposed, or a menu you open anywhere.
