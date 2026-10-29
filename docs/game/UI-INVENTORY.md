# UI inventory

Every layout, screen and component in this game's UI, and where each one stands. Started with the first screens, when the layouts are decided, and completed in the UI phase (docs/workflow/UI.md). Replace each prompt with the answer.

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
| | | | | | | |

> For any screen whose layouts differ, a short section on how:

### <Screen>

- **Desktop:**
- **Phone landscape:**
- **Phone portrait:**

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
