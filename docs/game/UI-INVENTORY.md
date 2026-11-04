# UI inventory

Every layout, screen and component in this game's UI, and where each one stands. Started with the first screens, when the layouts are decided, and completed in the UI phase (docs/workflow/UI.md). Replace each prompt with the answer.

**This file is still mostly empty, and that is a gap, not a decision.** The game already has five
runtime-built screens — the debug readout, the steering slider, the handbrake and DBG buttons, the
car tuner, and the start button below — and only the last of them is listed, because `T-051` listed
the one it built rather than backfilling four it does not own. The layouts, components and element
map are all untouched. The inventory is written in full in the UI phase (UI.md "2. Inventory"); until
then, a screen added here is one row.

**One rule every screen in this game obeys, and it is not optional:** the whole screen is a steering
pad — a finger's horizontal distance IS the car's rate of turn (`Drift/DragControl`) — so anything
touchable must sit at a higher `DisplayOrder` than `DriftControls` (5) and be an Active GuiObject,
or a thumb on it also hauls the car round. And `Instance.new("ScreenGui")` still defaults to the
legacy `Global` `ZIndexBehavior`, where a child does not draw above its parent: set
`ZIndexBehavior = Sibling` or the text comes out painted over, a bug this game has already had once.

## Layouts

> The layouts this game supports and how each is chosen: from the input type and the measured screen, never a guess at the device (UI.md "Layouts per device"). Delete the rows the game doesn't support.

| Layout | Chosen when | Reference size | Supported |
|---|---|---|---|
| Desktop | | 1920 × 1080 | |
| Tablet | | 1024 × 768 | |
| Phone landscape | | 844 × 390 | |
| Phone portrait | | 390 × 844 | |
| Console | | TV resolution, TV-safe area | |

## HUD by state

> What the HUD shows in each gameplay state, per layout. Phones show as little as possible.

| State | Desktop | Phone landscape | Phone portrait |
|---|---|---|---|
| | | | |

## Screens

> Every screen, including runtime-created and in-world UI. Status: programmer art, layout approved (the user decided its layouts), rebuilt, approved (finished in the UI phase).

| Screen | Source | Opens from | Data and inputs | States | Relied on by | Status |
|---|---|---|---|---|---|---|
| **Start button** (`PlayerGui.DriftRun`) | `StarterPlayerScripts/Drift/RoadHud.luau`, a LocalScript | Always on screen, from the moment the client loads, in every world | **Shows:** which state the run is in, which piece the **server** has you on, and how many are driving. All of it comes down `RoadRun` from the server; nothing here is a client's own number. **Takes:** one press, which sends one boolean | **Not in a run** — green, `START ENDLESS RUN`, "not in a run". **A run is going but not yours** — green, "a run is going (N driving) -- press to join". **In a run** — red, `END RUN`, "on the road -- piece N, alone / N other drivers" | `features/endless-run.md`; `RunTests` and agent playtests read `PlayerScripts.RoadHudBridge` | Programmer art |

For any screen whose layouts differ, a short section on how, in this form:

### Start button

**The same at every layout, deliberately**, which is the one case where "a scaled copy of another"
is the right answer: it is a single 220 x 44 px button centred at the top of the screen, and 220 px
fits inside the narrowest layout this game supports (390 px, a phone in portrait) with 85 px either
side. Measured at 1525 x 663 in `DR-Lane3`: `AbsolutePosition` (652.5, 8), `AbsoluteSize` (220, 44)
— 652.5 + 110 = 762.5, which is half of 1525.

- **Desktop:** top middle, 8 px under the Roblox inset. The inset is respected (`IgnoreGuiInset =
  false`), unlike the drag pad and the tuner, because this is the one thing in the game that sits
  where Roblox puts its own chrome.
- **Phone landscape:** the same. Nothing else is at the top middle; the readout is top left and the
  tuner's and readout's buttons are top right.
- **Phone portrait:** the same.

## Components

> The component set, small enough to cover the whole game (UI.md "Group, don't multiply"). Status: listed, built, art approved, done.

| Component | Variants | Sizes and minimum target | States | Art (`assets/<topic>/`) | Status |
|---|---|---|---|---|---|
| | | | | | |

## Element map

> Each programmer-art element and the component and variant it becomes.

| Screen: element | Component: variant |
|---|---|
| | |
