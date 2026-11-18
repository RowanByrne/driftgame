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

## Session UI shortcut (T-200)

`Controllers/UiVisibilityController.luau` binds keyboard `P` through the Input Action System. One press hides the game's screen UI and another restores it. A focused TextBox or the Roblox menu prevents toggling. No new screen or button is added; gamepad and touch have no new shortcut.

Visual roots under game ScreenGuis are reduced below a pixel with a temporary UIScale. ScreenGui `Enabled` and GuiObject `Visible` remain owned by each screen, so menu changes and UI created while hidden restore to their current state. Existing root scales are preserved, including changes made while hidden. Roblox chat, bubble chat and touch controls, CoreGui, and the `DriftControls.DragArea` driving pad are excluded. Collapsing the tuner ends an active slider drag before further pointer movement can alter the tune.

Lane2 verification (2026-11-14): actual P hides all 21 game visual roots below one pixel; the driving pad stays 1234 x 592. Actual P while typing makes no toggle. Ten hide/restore cycles leave one binding, no suppression scales and no suppressed roots. A new root, a removed root, changed Visible/Enabled flags, a changed existing scale (0.75 to 0.8) and avatar respawn restore correctly. Keyboard steer reads 0.75 and a 200-pixel mouse drag reads 0.365 while hidden; two brake presses toggle twice. Both tuner slider types retain their value after P and pointer movement. Two changed scripts matched disk and compiled before the quiet playtest; console checked and playtest stopped. No new layout or art needs approval.

## Layouts

### Settings page (T-201, T-208)

**Status:** approved and merged to Main, 2026-11-14. Approved style A / Smoked glass. Source: `Settings/SettingsView` and fixtures, driven by `Controllers/SettingsController`. Open from Settings, M or gamepad R3 while driving. Close from Back/X, Backspace or B. Categories: Steering, Interface, Graphics (T-225 Ground detail, T-263 Road ahead, T-230 Road behind) and Sound (T-256: five volume sliders, 0-100% (default 30%, today's mix) with minus/plus nudges of 10%, for Music, Tire squeal, Off-road drift, Suspension and Engine; fixtures `sound` and `largestSound`). Native controls: mode segments, integer sensitivity slider with minus/plus nudges, and the existing P shortcut's keycap/instructions. Session-only values; no decorative live sliders or unavailable categories.

One `Settings` ScreenGui, DisplayOrder 36, Sibling order. Full-screen backdrop; the pane and entry are fitted to the measured core/device-safe rectangle. Wide layouts (width at least 1000 and height at least 500) use the left rail; narrower layouts use horizontal tabs. Short landscape places steering and sensitivity in two columns where they fit; portrait and larger text stack and scroll. The Back and X targets stay fixed and reachable. The entry sits below TUNE and is put away while that tuner is open so it cannot cover its header.

The other game HUD is suppressed while settings is effective, through UiVisibilityController's shared owner-aware registry; HUD owners keep their own flags. Keyboard P suspends the modal and releases blur, focus and driving input ownership, then restores it on P again. Car/avatar respawn and garage entry close it. The console closes settings and owns its own input block. Menu gestures do not steer, toggle the brake, pan/zoom the camera, enter the garage, open the tuner or fire debug shortcuts.

Measured at actual simulator resolution on 2026-11-14: desktop 1280×720 and 1920×1080; tablet 1024×768; small landscape 667×375 and 640×360; notched phone landscape camera viewport 750×390 (full GUI 844×390); notched portrait camera viewport 390×763 (full GUI 390×844); compact portrait 360×640; ultrawide 2560×1080. Native essential text is at least 16 px, all buttons/slider hit areas at least 48×48. Long-copy and 1.5× text/opaque-pane fixtures fit by wrapping and scrolling. The settings modal suppresses the game's touch controls, so thumb-control zones are not active during its measurements. Details and input-tool limitations are in `docs/archive/settings-menu-shell-checks.md`.

The glass material is native, with quiet inset tiles and a fine rim; the client BlurEffect softens the entire 3D scene, not individual GUI panes. Immediate transitions respect reduced motion. Preferred text size, transparency and input changes are observed live. No UI image load or aspect-ratio risk exists in this implementation.

### Layouts for the existing screens

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
| **Score panel** (`PlayerGui.ScoreHud`) | `Drift/ScoreHudView`, its fixtures, `UI/ScoreTape`, `Controllers/ScoreController` | The server opens an endless run | Run total at left, named multiplier, progress through its letters and tape. Passive | Hidden, run, grace, rank up/down, bank receipt, end summary, best | `DebugView`, `DebugFixture`, score engine snapshots | Akina Race Tape, T-307 |
| **Score feed** (`PlayerGui.ScoreFeed`) | `Drift/ScoreFeedView`, its fixtures and `Controllers/ScoreController` | A score event or hairpin notice arrives | Growing events above the rank, completed events and directional hints below. Passive | Empty, live, banked, merged, lost, notice, full, reduced motion | `DebugFeed`, `DebugFeedFixture`, `DebugFeedDrag`, `DebugFeedMotion`, `HairpinHintTests` | Split Feed, T-307 |
| **Road-ahead map** (`PlayerGui.RoadMap`) | `Drift/RoadMapView.luau` (view), `Drift/RoadMapView.fixtures.luau`; driven by `Controllers/RoadMapController.luau` | Shown whenever this client has a spline road and a car: in a run | **Shows:** the next 800 studs of road and 100 behind as a line, road-up, tight bends (radius 220 or less) orange and thicker, the tail behind fainter, an arrow for the car turned to its nose. All from the client's own copy of the road. **Takes:** nothing: nothing in it is `Active` | **Hidden** -- no run. **Map** -- line and arrow. Put away with the HUD by menus and P | `features/road-ahead-map.md`; `RoadMapController:DebugState()`, `DebugCheck()`, `DebugFixture(name)` | Programmer art (T-236) |
| **Garage button** (`PlayerGui.GarageHud`) | `Controllers/GarageController.luau` | On screen while driving (not walking, not in the garage) | **Takes:** one press, which sends `GarageVisit(true)`; `G` and gamepad DPad down do the same. **Shows:** nothing else | **Driving** -- shown. **Walking, getting in or out, in the garage** -- hidden | `features/car-customization.md`; `GarageController:DebugState().hudVisible` | Programmer art (T-103) |
| **Garage menus** (`PlayerGui.GarageMenu`) | `Garage/GarageMenuView.luau` (view), `Garage/MenuModel.luau` (its data), `Garage/GarageMenuView.fixtures.luau`; driven by `Controllers/GarageController.luau` | The server taking the car into the garage: through the door, or the Garage button | **Shows:** seven category tabs; the part list (name, FITTED, before/after bars for what a performance part changes, from `Customization.resolve`); on Paint, colour grids for body and second colour and pickers for finish and wrap; a status line. **Takes:** a tab, a row or swatch (a preview on the car, this client only), Fit (`CustomizeFit`), Back, Drive out (`GarageVisit(false)`). Gamepad: selection on the rows, B Back, X Fit, Y Drive out, L1/R1 tabs; keyboard Backspace, Return, Q/E | **Nothing picked** -- Fit and Back disabled. **Previewing** -- the row outlined, status "Previewing ...". **Asking** -- Fit reads `Fitting...`, `State = Pending`. **Fitted** -- green status. **Refused** -- red status with the server's reason, the car back to what is fitted. **Body kits, Interior** -- listed and fitted, nothing drawn yet (T-105) | `features/car-customization.md`; `GarageController:DebugState().view` (the view's `describe()`), the `State`, `Fitted` and `Layout` attributes | Programmer art (T-103) |

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

### Score panel and split feed

The score readout, rank word and multiplier form one passive widget. The score sits to the left of the rank, with both aligned on their bottom edges. The rank’s charged lettering and 14 tape segments share the same clamped engine progress. The caption, compact separator and top rule come from native text and frames. The score widget draws on layer 14 and its event feed on 13. The run button stays on layer 15.

`UI/ScoreTape.layout` computes the rank’s inset-relative anchor for both screens. The wide layout targets the reference at 33.65% across and 52.5% down. Short phones use a 151 × 36 px rank and keep its upper live row clear of the map. Portrait reflows the cluster toward the centre and leaves room for the map above. Large preferred text sizes widen the widget and its text reservation. The run score uses tabular digits so adjacent ranks and event rows hold their position as points accrue.

The live event’s dot, italic name and growing points sit above the rule. Completing a held event pulls the text back and drives it into the rank. A point value then flies to the score. One-offs and directional notices stay below. Lost points carry a visible strike and the word LOST. Up to five rows appear on larger displays and three on phones, with live events taking priority. Long event names wrap. Reduced Motion keeps the numbers, ranks and outcomes while removing travel, shake and echoes.

`ScoreHudView.fixtures` includes the five introductory ranks, grace, maximum and summaries. `ScoreFeedView.fixtures.splitFeed` pairs with the HUD’s `splitFeed` sample to reproduce the approved still. The shared component was measured independently in Studio before the screen integration. The compact Roboto Condensed Bold Italic face fit all seven sampled labels including COMMITTED (99 of 122 px) and LOCKED IN (84 of 122 px). At 55% charge the tape measured 83.05 of 151 px and the same fraction of each word was lit.

### Road-ahead map

A see-through square, top left of the safe area, 16 px in (`IgnoreGuiInset` false, `CoreUISafeInsets`), so it is always below Roblox's top bar and its buttons. `DisplayOrder = 12`, under the score (14) and the run button (15), over the drag pad (5). Its size is chosen from the measured screen: 220 px when the short side is 500 px or more, 140 px below that. When the screen is too narrow for it to sit beside the top centre's column (220 px wide: the run button, its line and the score), it drops below that column, to 146 px.

- **Desktop:** 220 px, top left. HD 1080: (16, 16) in the inset space.
- **Phone landscape:** 140 px, top left. iPhone 13 Pro 750 x 390 and iPhone 7 667 x 375: (16, 16). On iPhone 7 its bottom reaches the test-only buttons' label (not shipping).
- **Phone portrait:** 140 px, below the score. iPhone 13 Pro 390 x 763: (16, 146).

### Testing buttons

**The same at every layout, for the same reason and in the one corner nothing else uses.** Two
200 x 40 px buttons and a 16 px label, stacked in the bottom left with 16 px of margin: the readout
is top left, the tuner and the DBG button top right, the start button top middle, the handbrake
bottom right and the steering slider bottom middle. 200 px fits inside the narrowest layout this
game supports (390 px) with room either side.

- **`DisplayOrder = 16`,** above the drag pad's 5 and below the tuner's 20. Without it a thumb on a
  button is also a thumb steering the car.
- **`IgnoreGuiInset = true`,** unlike the start button: the bottom left is nowhere near Roblox's own
  chrome.
- **It is deliberately ugly.** A magenta nothing else in the game uses, and a header that says
  `TEST ONLY -- NOT SHIPPING`. The one thing that must never happen is this going out with the game.

### Garage button

One 96 x 48 button, bottom right, in the GET OUT button's row and 12 px to its left: 136 px in from the right edge and 136 up. It was first stacked above GET OUT, and on a 375-tall phone that put it over the tuner's button in the top right, so it moved into the row. `DisplayOrder = 13`, above the drag pad. Measured in the simulator at actual resolution (T-103), overlapping nothing on screen but the drag pad itself: iPhone 7 landscape (667 x 375) at (435, 133), iPhone 13 Pro landscape (750 x 390) at (518, 148), HD 720 at (1048, 478), each 12 px left of GET OUT.

### Garage menus

**Chosen from the measured safe area, live on resize** (`GarageMenuView.layoutFor`): narrower than tall is **portrait**; 520 px tall or less is **compact** (a phone on its side); anything else **desktop**. All three use the same pieces; the placement is in one function (`_layout`). The safe area is Roblox's (`ScreenInsets = CoreUISafeInsets`), because the tabs are at the top. While the menus are up the steering pad is off (`CarInputController:SetDriving(false)`), Roblox's touch controls are off (`GuiService.TouchControlsEnabled = false`, put back on the way out), and the start, testing, tuner and debug screens are switched off and put back as they were.

- **Desktop:** the tabs across the top (56 tall, each tab 48), the list down the left (380 wide), Back and Fit under it, Drive out bottom right.
- **Compact:** the tabs across the top, scrolling sideways to keep the open one in view; the list down the left (320 wide) and the whole height; Back, Fit and Drive out stacked in the bottom-right corner (148 x 52 each), Drive out lowest. The car shows between them.
- **Portrait:** the tabs on top, the car in the top half, the list in the bottom half, Back, Fit and Drive out in one row under it.

Measured in the simulator at actual resolution (T-103), on the Suspension list with a part picked (four bars a row): no piece off the safe area, no two pieces overlapping, no button under 44 px, no essential text under 16 px (the swatches' small FIT mark is 14, `TextAux`), every text fitting.

| Size | Safe area | Layout | List height | Share of the screen covered |
|---|---|---|---|---|
| iPhone 7 landscape, 667 x 375 | 667 x 317 | compact | 141 | 49% |
| iPhone 13 Pro landscape, 750 x 390 | 750 x 332 | compact | 156 | 47% |
| iPhone 13 Pro portrait, 390 x 763 | 390 x 705 | portrait | 197 | 46% |
| HD 720, 1280 x 720 | 1280 x 662 | desktop | 426 | 31% |
| HD 1080, 1920 x 1080 | 1920 x 1022 | desktop | 786 | 22% |

The coverage is a menu's, with nothing to drive behind it; the HUD targets do not apply. Not checked: a real phone, a real controller (gamepad focus was not driven), and the screen at the user's text size.

## Components

> The component set, small enough to cover the whole game (UI.md "Group, don't multiply"). Status: listed, built, art approved, done.

| Component | Variants | Sizes and minimum target | States | Art (`assets/<topic>/`) | Status |
|---|---|---|---|---|---|
| | | | | | |

## Art slots

> Each piece that gets art: its size and aspect in each layout, measured on the approved programmer art, and its layers, back to front (UI.md "Layers for animation"). The art is made to these numbers. Coverage targets and measured coverage go under "HUD by state".

| Component: variant | Desktop | Phone landscape | Phone portrait | Layers, back to front | What animates |
|---|---|---|---|---|---|
| | | | | | |

## Element map

> Each programmer-art element and the component and variant it becomes.

| Screen: element | Component: variant |
|---|---|
| | |
