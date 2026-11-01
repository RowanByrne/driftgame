# Configs

Changing values in the live game without publishing, through Roblox's experience configs (Creator Hub → the game → **Configs**, or in Studio **File → Open Configs**). This game's keys and their live values are recorded in `live/EXPERIENCE.md` "Configs".

## What a config is for

- **Switches:** turn a feature on or off, and kill switches for when something breaks, such as checkout off (LAUNCH.md "Purchases", `live/INCIDENTS.md`).
- **Tuning:** numbers that may need changing while the game is live: drop rates, XP, timers, rewards.
- **Timing:** when timed content opens or an event runs, so a date can move without a publish (RELEASING.md "Timed releases").
- **Targeting:** different values for different groups of players: new or returning, by country or language, payers, how long ago they first played, how engaged they are.

Not for: anything the code doesn't support yet (a new feature still needs a publish), secrets (use Roblox's secrets store), or anything saved per player.

## In the code

One server module, the **config wrapper**, reads every config (CODING.md "Foundation kit"); nothing else calls `ConfigService`.

- **Every key has a default in code.** A missing key returns nil, and configs can fail to load (outages, unpublished places), so the game always runs on the defaults alone.
- **Global values:** `ConfigService:GetConfigAsync()` once, wrapped in `pcall`. It only throws if it has never loaded.
- **Per-player values** (targeting, experiments): `ConfigService:GetConfigForPlayerAsync(player)` when the player joins, kept for that player.
- **Updates:** a snapshot doesn't change on its own. When `UpdateAvailable` fires, the wrapper calls `Refresh()` and announces the keys that changed (`GetValueChangedSignal`).
- **When a change applies:** decided per key. Some apply at once; others wait for a safe moment, such as the next round or the next join, so nothing shifts mid-fight.
- **Types are checked:** a live value of the wrong type is ignored, with a warning, and the default used.
- **The client never reads configs:** `ConfigService` is server-only. Values the client needs are sent by the server, and listed in `docs/game/CONTRACTS.md`.
- **In tests:** where configs don't load, the wrapper runs on defaults; tests override values through the debug bridge, or with `ConfigService:SetTestingValue` where configs do load. A testing value lasts only for that server or Studio session.

## Changing a value

Publishing a config changes the live game for every player, so it's treated like publishing: the user publishes, or tells the agent to.

1. **Edit** the key on the Configs page or in Studio's Configs widget. The change is **staged**: only Studio play sessions see it.
2. **Test** the staged value in a Studio play session, and check the game picks it up.
3. **Publish** with a message saying what changed and why: **Publish now** reaches everyone in about 15 seconds to a minute; **Publish over 15 min** rolls it out gradually.
4. **Record** the new live value in `live/EXPERIENCE.md` "Configs".

**Undo:** the **History** page lists every change, who made it and the values before and after. **Restore** stages the old value; publish it to roll back. Studio's **Publish As** copies all configs to another experience, such as from a test experience to the live one.

## Targeting

A config can give different values to players who match **conditions**, built from these attributes:

| Attribute | Examples |
|---|---|
| Country, language | |
| New vs returning | |
| Source | Home recommendation, search, ads |
| When the player first played | 0–30 days ago, 31–90 days ago |
| In-game payer status | Top payers, casual, lapsed, never |
| In-game activity status | Early, active, lapsed, reactivated |
| Engagement | Days played in the last week |
| Platform spender and activity status | Across all of Roblox |

- **Rules run top to bottom,** and the first match wins. The order is global across every key, so check it on the **Conditions** tab before publishing.
- **Each value must match the key's type.**
- **Read targeted values with `GetConfigForPlayerAsync`.** `GetConfigAsync` ignores targeting.

Experiments use the same per-player configs (`EXPERIMENTS.md`).

## Limits

- 1,000 active configs; 100 conditions per game, 20 per key.
- String and JSON values up to 100,000 characters; numbers exact up to 2^53.
