# Settings

Everything about how a player controls and sets up the game: the controls on every input type, the settings menu, and what the game takes from the player's own Roblox settings. Saved values and their checks are in `CONTRACTS.md` "Settings"; the screens are in `UI-INVENTORY.md`. Started with the first controls in the Core loop phase and kept current after that. Replace each prompt with the answer.

## Controls

> Every action and its control on each input type, and where the action is available. Every action works on all three (docs/workflow/CODING.md); on-screen hints show the control for the input in use.

| Action | Keyboard and mouse | Gamepad | Touch | Available |
|---|---|---|---|---|
| Open / close settings | `M`, Settings button | Right stick click (`R3`), Settings button | Settings button | While driving, outside the garage and Roblox menu; shortcuts ignore typing |
| Settings navigation / back | Tab, arrows, Enter; Backspace or visible Back/X to close | Directional focus, A to activate, B to close | Tabs, buttons and scrolling; visible Back/X | While settings is open; left/right nudges the selected slider |
| Hide / restore game UI | `P` | No shortcut | No shortcut | Keyboard shortcut requested by the user (T-200); ignored while typing or while the Roblox menu is open |

The UI starts shown each session. Press `P` again to restore the current game UI; menus closed or disabled while hidden stay closed. Driving input and Roblox chat, menus and touch controls stay available. This is a keyboard convenience shortcut, with no new on-screen button or saved setting.

## Settings menu

> Each setting a player can change: its default, its options, the `CONTRACTS.md` "Settings" key it's saved under, and what it changes.

| Setting | Default | Options | Saved as | What it changes |
|---|---|---|---|---|
| Steering mode | Dynamic | Dynamic / Centred | Session only | Pointer movement starts where the finger goes down, or at screen centre; no handling-model change |
| Pointer sensitivity | 5 | Whole values 1–10 | Session only | Shortens pointer travel as the value rises; keyboard/gamepad response stays unchanged |
| Hide / restore game UI | Shown | Keyboard P, shown as a shortcut in Interface | Session only | Preserves the T-200 keyboard shortcut; no touch toggle that could strand a hidden UI |
| Ground detail (Graphics, T-225) | Medium on keyboard and mouse or gamepad; Low on a phone or tablet (Roblox's preferred input is touch, or touch with no keyboard) | Light / Low / Medium / High / Ultra, a slider with - and + | Session only, on this device (`Drift/GroundDetail`) | How far ahead along the road, and round the car, the mesh ground stays sharp, and how many of the ground's tiles a device holds (`Config.Spline.Ground.Detail`). Changes the drawn ground live, with no rejoin; nothing else in the game reads it |
| Road behind (Graphics, T-230) | Long on keyboard and mouse or gamepad; Medium on a phone or tablet (the same test as Ground detail) | Short / Medium / Long / Longer / Longest (at least 300 / 800 / 1 300 / 2 000 / 3 000 studs, up to a 480-stud chunk more), a slider with - and + | Session only, on this device (`Drift/RoadBehind`) | How far back the road, and on a ground run the ground along it, stays drawn behind the car (`Config.Spline.Mesh.Behind`). Short is the window before T-230. Costs memory, not building: a chunk behind was built when it was ahead; raising the setting mid-run builds the few chunks behind that had gone. A device out of mesh memory lets the road behind go first, never the road ahead. Changes live, with no rejoin |
| Sound levels (Sound, T-256) | 30% each, which is the game's own mix | Music, Tire squeal, Off-road drift, Suspension, Engine: whole percents 0-100, a slider with - and + (10% steps) | Session only, on this device (`Drift/SoundLevels`) | Each category's volume: the game's own mix times level / 30, so 15% is half and 100% about 3.33x (AUDIO.md "Mix"). Changes live while dragging. Music is kept for when music exists; nothing plays it yet |

The smoked-glass page has Steering, Interface, Graphics and Sound categories. Settings is initially a driving menu, not available while walking or visiting the garage. Its entry sits below the existing tuner button and hides while that tuner is open; M remains available while driving. Opening settings puts the other game HUD away without changing its owners' visibility flags. It owns driving/menu input, uses a client-only whole-scene blur, and restores current HUD state when closed. P temporarily puts settings away too, releasing input and blur, then restores the open page on the next P. Respawn or entering the garage closes it.

## From Roblox

> What the game reads from the player's own Roblox settings and device, and how it responds (docs/workflow/UI.md "Player settings").

| Roblox setting | How the game responds |
|---|---|
| Text size | Native text grows through Medium/Large/Larger/Largest; rows wrap and content scrolls, with no whole-page scaling |
| Transparency | Multiplies glass transparency; at zero the page and its backdrop are opaque and blur is off |
| Reduced motion | The page uses instant transitions, with no decorative animation |
| Preferred input | Ends an active slider drag on a device change; focuses the page for gamepad and uses logical cyclic navigation |
