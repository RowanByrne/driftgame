# Settings

Everything about how a player controls and sets up the game: the controls on every input type, the settings menu, and what the game takes from the player's own Roblox settings. Saved values and their checks are in `CONTRACTS.md` "Settings"; the screens are in `UI-INVENTORY.md`. Started with the first controls in the Core loop phase and kept current after that. Replace each prompt with the answer.

## Controls

> Every action and its control on each input type, and where the action is available. Every action works on all three (docs/workflow/CODING.md); on-screen hints show the control for the input in use.

| Action | Keyboard and mouse | Gamepad | Touch | Available |
|---|---|---|---|---|
| Hide / restore game UI | `P` | No shortcut | No shortcut | Keyboard shortcut requested by the user (T-200); ignored while typing or while the Roblox menu is open |

The UI starts shown each session. Press `P` again to restore the current game UI; menus closed or disabled while hidden stay closed. Driving input and Roblox chat, menus and touch controls stay available. This is a keyboard convenience shortcut, with no new on-screen button or saved setting.

## Settings menu

> Each setting a player can change: its default, its options, the `CONTRACTS.md` "Settings" key it's saved under, and what it changes.

| Setting | Default | Options | Saved as | What it changes |
|---|---|---|---|---|
| | | | | |

## From Roblox

> What the game reads from the player's own Roblox settings and device, and how it responds (docs/workflow/UI.md "Player settings").

| Roblox setting | How the game responds |
|---|---|
| | |
