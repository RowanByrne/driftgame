# Feature: Settings menu

**Status:** specced; awaiting the user's plan approval. **Owner task:** the Workboard plan linked to this spec; Rocco assigns its feature agent after approval.

## Goal

Give Drift a clean, modern settings page and establish a reusable UI look through concepts first. The user's brief (2026-11-14) is glass panes, fogginess, semi-transparency and tiles, with Assetto Corsa EVO and Assetto Corsa Rally as style references. The settings page comes first because the user has existing controls they want to move into it.

This is the user's requested visual exploration for settings. It does not advance the whole game's phase or approve a finished style for the other menus.

## How it plays

1. The user compares three distinct settings-page concepts on one sheet, over the same real scene from Drift. Each direction shows a desktop page and its compact phone layout, with enough real controls to judge it.
2. The user picks a direction or asks for a combination or revision. Record the pick in `ART-DIRECTION.md` and `DECISIONS.md` before building the styled page.
3. Build the chosen settings page in the feature's lane. It has a visible Settings entry, a visible close/back action, category tiles or tabs, and space for labelled rows, switches and sliders. Its exact layout follows the pick.
4. With the user, agree which existing controls belong here. Move that agreed batch, keep their behaviour and permissions, and remove an old on-screen control only after its replacement works. Do not guess that developer tools are ordinary player settings.
5. The user tries the page in its lane before its code is offered to the conductor for merging.

## Left out

- Restyling the garage, score HUD, driving controls or every other screen.
- New handling, tyre or camera simulation, car upgrades, or changes to the approved driving feel.
- Moving the whole developer tuner or admin console into public settings by default.
- New audio, graphics, accessibility or other preferences solely to populate a concept. Categories without implemented content are omitted from the live page.
- New cross-session saving or a player-profile foundation in this first buildout. Existing controls retain their current storage behaviour; the concept must not suggest that a session-only value is saved permanently.
- Uploading unpicked art, changing Creator Dashboard settings, or publishing.

## Rules and numbers

- Generate three genuinely different directions within the brief: smoky dark glass, lighter frosted glass, and a restrained motorsport tile composition. These describe candidate directions, not approved colours or final names.
- Keep the same content in all three so the user is comparing the look and layout. Use Drift's own terms and original art; the named racing games guide the material, spacing and hierarchy.
- The first concept round is partial: one representative panel, category tile, button, slider and toggle, with selected, focused and disabled examples. Show their layers and keep text, values and hit areas native in the eventual game.
- Use the image tool and candidate/manifest workflow in `docs/workflow/ART-PIPELINE.md` and `docs/workflow/UI.md`. Candidates stay outside git; only approved references and shipping assets enter it.
- Prove that the chosen glass/fog treatment is achievable and readable in Roblox before committing to it. Record any difference between the concept and the real implementation, including the scope of any scene blur. Do not promise a particular blur technique from an image alone.
- Essential text is at least 16 effective pixels; touch targets are at least 48 by 48 pixels. Reflow and scroll before shrinking text. Follow the user's Roblox text-size, transparency and reduced-motion preferences live.
- Use a small shared component set and semantic theme/layer tokens. The documented `UI/Theme`, `UI/Create` and `UI/Layers` kit is not currently implemented here; build only what this page needs and document its API before other screens depend on it.

## UI

Plan and show desktop, tablet, phone landscape and phone portrait layouts from the start. Verify console/gamepad focus and TV-safe placement if the game supports console; record the supported layouts and the actual measured viewports in `UI-INVENTORY.md` rather than treating its unfinished table as a decision to drop devices.

Desktop can use a category rail and a tiled content pane. Compact layouts reflow to fewer columns or one scrolling column while keeping the active category and close/back action reachable. The concept pick settles the composition, font, palette and density.

Opening the page owns menu input. A slider, scroll, tile press or closing gesture must not also steer, apply the handbrake, move the camera or activate another menu. The whole-screen driving pad is `DriftControls` at DisplayOrder 5: the settings modal must be above it and consume input, and its ScreenGui must use `ZIndexBehavior = Sibling`.

Define the open/close shortcut and focus return as part of the shell; do not take Roblox's Escape/menu handling or an occupied binding. Coordinate with the garage and developer console. Closing, respawning, switching input type or hiding the game UI must end an active slider drag and leave no invisible blocker. Preserve the existing keyboard P hide/restore behaviour.

## Existing controls and migration

Catalogue each proposed move with its current owner, authority, default, range, shortcut and storage behaviour before wiring it into the page. Update `SETTINGS.md`, `UI-INVENTORY.md`, `ARCHITECTURE.md` and affected feature specs when the move is implemented.

Known starting points for the concept and that catalogue:

| Control or tool | Existing status | Boundary for this feature |
|---|---|---|
| Steering mode and sensitivity | Already specified in `drift-model.md`: dynamic or centred, default dynamic; sensitivity 1-10, default 5. `Drift/DragControl.luau` implements them, but the available controller settings hook is Studio-only | Good candidates for real personal settings, if the user includes them. Give them an intentional runtime API; do not call a Studio debug hook in the live page |
| Hide/restore game UI | Keyboard P, session-only (`SETTINGS.md`, T-200) | Preserve it; a hidden menu must not strand a modal input block or change a setting through a stale drag |
| Camera controls | Existing camera/controller owns the view and its inputs | Catalogue supported controls and ask which should move; do not turn all camera tuning constants into settings |
| Car tuner, readouts, trajectory and admin commands | Developer tools with their existing access rules | Keep those rules and entry points unless the user explicitly selects a development section; never expose server-wide actions as personal preferences |

The exact first batch is a question for the feature agent after the concept pick, not a blank cheque to relocate every HUD button. Existing source and contracts take precedence over this initial catalogue if a control has changed.

## Server and client

The visual shell, menu focus, local preferences and blur are client-owned. Views draw plain data and emit actions; a controller coordinates the existing input, camera and visibility owners. Fixtures cover every supported state without requiring a run to be played first.

Existing server-owned actions keep their current remotes, validation and access checks. No new persistent data or settings remote is authorised by the visual shell. Do not attach personal preferences to the throwaway `DriftGarageDev_v1` tuner/build store.

## Contracts

No data keys, remotes or public APIs change in this planning commit. Implementation records component/controller APIs, layer ownership, input blocking and any changed existing setting contract in the same commit as code. Shared contracts needed by later steps go first as a small checked commit.

## Analytics

No analytics events are added by concept work. Audit the existing event catalogue when implementing the page; document any agreed menu/settings events before they are emitted, and never log arbitrary input text or developer commands as setting values.

## Monetization

None.

## Platform risks

Use the named racing games for inspiration and original concepts, without their logos, screenshots as shipping assets, copied UI art or branded player-facing copy.

## Art and sound

One combined comparison sheet for the three directions, following the UI concept workflow. Use a real Drift scene captured in a quiet lane playtest, never a conductor playtest in Main. Keep image candidates in `art/generated/settings-menu/` relative to the project folder, prompts and hashes in a topic manifest, and the chosen reference in `assets/reference/` after approval. Generate separate shipping layers only if the chosen material needs them; native panels and controls remain code. No sound work is included.

## Testing

- Concepts: confirm each direction contains the same real controls, readable desktop/compact layouts and clearly labelled component states; leave the visual pick to the user.
- Before implementation playtests: source-gate the changed scripts in the assigned lane, mark the playtest quiet, and stop it afterwards.
- Measure all supported layouts at the sizes in `UI.md`, including the smallest landscape, portrait and ultrawide cases. Check text, contrast over bright/night/busy scenes, safe areas, touch targets, scrolling, long labels and larger preferred text. Preserve readable panels when transparency is reduced.
- Exercise mouse, touch, keyboard and gamepad navigation; prove menu gestures cause no steering/braking/camera action and that closing restores normal controls. Record any simulated input.
- Open/close ten times, rotate/resize, respawn, switch input type, open the Roblox menu, and press P while the page or a slider is active. Measure that one page/input owner remains and no drag, blur or modal blocker leaks after closing or hiding.
- For each moved control, compare its value and effect with the old entry point, including defaults, limits, permission failures and its existing saving/session behaviour. No dead or decorative controls in the live page.
- Read the console for errors and warnings. Screenshots answer visual questions only, at most three per task. The user approves the lane build before merge.

## Planned steps

1. **Draft settings style concepts** - three directions on the combined sheet; the user picks the style and layouts before step 2.
2. **Build the chosen settings page** - the reusable components, responsive shell, fixtures and input/focus lifecycle; checked in the feature lane.
3. **Move the selected settings** - catalogue and agree the first batch with the user, connect it to its existing owners, then remove only replaced controls and verify behaviour.

All steps belong to the feature's own agent and its reserved lane after the plan is approved. They are sequential; the conductor handles only the final merge request.

## Open questions

- Which of the three visual directions, or combination, should become the settings style? Asked with the concepts.
- Which existing controls does the user want moved first, and which belong in a developer-only section? Asked with a concrete catalogue after the visual pick.
- Exact opening shortcut, category names and supported device layouts are settled with the shell; current behaviour and occupied controls must be checked first.
