# Analytics

Every game sends a complete set of custom events to Roblox's analytics (the Creator Hub dashboards), so decisions rest on data. There's no backend of our own. If one is ever added, only the analytics helper changes. This game's events are listed in `docs/game/EVENT-CATALOG.md`.

**Planned:** our own data system for the important metrics, filled from these same custom events and read there instead of the Creator Hub dashboards (DATA-SYSTEM.md, not designed yet). Until it exists, read them in the Creator Hub (DASHBOARDS.md).

## How events leave the game

One server module, the **analytics helper** (part of the foundation kit, CODING.md), sends every event through `AnalyticsService`. Nothing else calls it.

- **Never in the way:** every call is wrapped in `pcall` and sent from its own thread, so analytics can never break or slow gameplay.
- **Server only, published only:** Roblox accepts these events only from a server in a published game.
- **Within Roblox's limits:** a server may send about 120 + 20 × players events a minute. The helper counts its sends and drops the least important events first when it gets close.
- **What's real time:** custom-event dashboards fill in after a delay, and an event that stops sending drops off them 90 days later. The Error Report and Performance dashboard are up to the minute, and Roblox's alerts can notify a webhook in real time. Where to find each is in DASHBOARDS.md.
- **In Studio:** nothing is sent. The helper keeps the most recent events in memory, readable through the debug bridge, so tests can check them.

## Slicing the data

Every number should be splittable by who the player is and where they are in the game.

**Roblox slices by the player, for free.** Its dashboards filter and break down by player attributes such as country, platform, age group, new vs returning, when they first played, and payer status. These match the attributes Roblox configs target by (`live/CONFIGS.md`). The game never sends these.

**The game slices by the game, in custom fields.** Each event has three custom field slots, sent as `"<field>:<value>"`:

- **Fields 1 and 2** hold the event's own fields (`EVENT-CATALOG.md`).
- **Field 3** is the game's **standard slice**, the same on every event:
  - **Default: the player's progress band** (level or stage bands such as `L1-5`, `L6-10`). This is defined per game in `EVENT-CATALOG.md`.
  - **During an experiment**, the events that measure it carry the player's variant there instead (`live/EXPERIMENTS.md`).
- **Input device** (`touch`, `gamepad`, `keyboard`) goes on the onboarding and core-loop funnel steps, in a slot those steps leave free. Platform alone doesn't tell a phone with a controller from a phone with touch.

## Naming

- **Event names** are `PascalCase` with the feature first: `ShopPurchase`, `DataSaveFailed`, `QuestCompleted`.
- **Prefer fields to new names.** Roblox allows far fewer distinct event names than field values: `ShopPurchase` with `item:sword` beats `ShopPurchaseSword`.
- **Few values per field.** Values across all custom fields share a pool of about 8,000 before Roblox groups the rest as "Other". Use bands (`0-24`, `25-49`), never free text or exact numbers.
- **No commas or quotes** (`,` `"` `'`) in any name or value: Roblox rejects the whole event. The helper strips them.
- **Funnel steps are named for what the game requires** ("Reached a shop", not "Clicked the shop sign"). Roblox counts only the first time a step is logged, and logging a later step completes every earlier one.
- **Live names are fixed.** Once an event or funnel step has live data, never rename or renumber it: add a new one and mark the old one retired in the catalog. Before launch, renumbering only costs tester data.

## Standard events

Roblox already tracks sessions, retention and revenue. Every game adds these from the Foundation phase onward:

| Area | Events |
|---|---|
| Onboarding | A first-join funnel: loading, first control, first core action (Roblox's onboarding funnel) |
| Core loop | A funnel for one round of the loop, from the Core loop phase |
| Economy | Every source and sink of every currency, with its transaction type, a SKU (`<Kind>:<id>`, like `Rod:oak`) and the balance after the change. Not admin grants or test fixtures |
| Purchases | A funnel from prompt shown to receipt granted, plus failures, with the product and Robux value |
| Progression | Levels and questlines: start and complete |
| Errors | Script errors on server and client, as one event with the script's area in a field, rate-limited |
| Data | Load failures, save failures, kicks for data problems |
| Performance | A sample every few minutes: frame rate and memory bands per device |
| Builds | `ServerStarted` as each server starts, with its place version (`game.PlaceVersion`) in field 1, so each build's servers can be seen (POST-RELEASE.md) |

## Events from the client

Some things only the client sees: a card shown, a place reached, a cutscene skipped. The client reports them to the server through one remote, and the server decides whether to log them:

- **Known keys only,** listed in the events registry as client events.
- **Only when it makes sense:** the player must be in a state where the event can happen, each event logs at most once per session (or up to its listed limit), and reports are rate-limited per player.
- **Allow-listed values:** every field the client sends is checked against a list of allowed values. Anything else is logged as `other`, so no player-written text or personal information ever gets through.
- **Short strings:** keys and values have length limits. Reports that arrive before the player's data has loaded are queued briefly, then checked.

## Adding events for a feature

A feature isn't done until its events fire (WORKFLOW.md).

1. **Spec:** list the events in the feature's spec (`features/`), then add them to `EVENT-CATALOG.md`: name, when it fires, fields and their values, the owning feature, and the dashboard views that use it.
2. **Registry:** add them to the events registry module, the code copy of the catalog: name, source (server or client), fields and any per-session limit.
3. **Log them** from the server through the helper. Client-only moments go through the client reporter.
4. **Test in Studio:** read the helper's recent events through the debug bridge, and check that each event fires once, at the right moment, with the right fields and the standard slice (TESTING.md).

## Privacy

Events identify nothing beyond what Roblox already attaches: never usernames, display names, chat or anything else players write.
