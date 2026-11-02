# Data system

> **Being designed by the user.** It shows on Rocco's Metrics tab.

Our own view of each game's numbers, built from its custom events (ANALYTICS.md): the views and weekly numbers the decisions need, which the Creator Hub's dashboards don't give in one place.

## Decided

- **Source:** the game's custom events, pulled from Roblox's Analytics Query API (Open Cloud, beta) with the user's key (`universe.analytics:read`, linked in Rocco's Connections). No backend of our own.
- **Stored in the project folder,** next to `repo\` (`<Game>\metrics\`, outside git). The API returns totals, never single players, so what's stored is anonymous by nature.
- **Shown on Rocco's Metrics tab,** including the weekly numbers that steer `docs/game/ROADMAP.md` "After launch" and `RETENTION.md` "Measured" (WORKFLOW.md "Live").
- **Funnels are custom events** (ANALYTICS.md "Naming"); the FTUE is the main one.
- **The Creator Hub stays** for what only Roblox has: the Error Report, Performance and alerts (DASHBOARDS.md).

## What the API gives

Checked 2026-11-02 ([guide](https://create.roblox.com/docs/cloud/guides/analytics), [metrics](https://create.roblox.com/docs/cloud/guides/analytics/metrics)):

- **Totals only,** by hour, day, week or month: `CustomEventCount`, `CustomEventCountUser` (unique players), and the sum, average, minimum and maximum of an event's value. Broken down by event name, custom fields 1 to 3, platform, operating system, age group, gender, new or returning, and payer status.
- **No player ids,** so nothing per player: a funnel is each step's count and unique players against the first step's, not each player's path.
- **The economy too:** `EconomyTransactionCount`, `EconomyTransactionAmount` and `EconomyAverageWalletBalance`, by currency, flow, transaction type and SKU.
- **Limits:** 30 queries a minute; a big query runs as an operation to poll until it's done. History goes back 4 years.
- **Freshness:** the Creator Hub says custom events can take up to 24 hours to show. How soon the API has them isn't documented: measure it before promising anything faster.

## Still open

- How often Rocco pulls, and how far back it keeps.
- The first views, and which decision each one serves (a post-release view would fit POST-RELEASE.md).
- Anything that needs per-player data the API can't give. That would mean the game keeping its own records, a separate decision.
