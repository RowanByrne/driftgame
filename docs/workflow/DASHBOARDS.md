# Dashboards

The analytics guidebook: where to find each number in Roblox's Creator Hub, and how to use the dashboard's tools. The important metrics will move to our own data system once it's built (DATA-SYSTEM.md); this guide stays for everything only Roblox has, such as the Error Report, Performance and alerts. The game sends its events as ANALYTICS.md describes; this guide is for reading them. This game's own custom dashboards and alerts are recorded in `live/EXPERIENCE.md`. Roblox moves pages now and then: when a path here is wrong, fix it in the template (CLAUDE.md "Template-owned files").

## Getting in

- **Open the game:** Creator Hub → **Creations** → pick the account or group that owns the game (top left) → the game.
- **Access:** the owner, or a group role with analytics permission ("View all analytics").
- **First time:** the owner activates analytics (a verified email, two-step verification, and agreeing to the terms; the **Activate Analytics** button on the game's overview page).
- **How many players it takes:**
  - Every KPI page: more than 10 daily players and 10 play hours, for 7 days in a row.
  - Performance charts, alerts and benchmark scorecards: 100+ daily players.

## Where each number lives

| Question | Where |
|---|---|
| How is the game doing overall? Big movements this week? | **Analytics → Overview**: insights flag large changes in daily players, new players and revenue |
| How do we compare with similar games? | **Overview**, benchmark scorecards (100+ daily players; updated daily) |
| Do players come back? (D1, D7, D30 retention) | **Analytics → Retention** |
| How many play, and for how long? (daily and monthly players, session length) | **Analytics → Engagement** |
| Revenue, payer conversion, revenue per payer and per daily player | **Analytics → Monetization** (sales data can be downloaded there) |
| Where do new players come from? Do recommendations convert? | **Analytics → Acquisition** |
| Age, gender, country, language | **Analytics → Demographics** |
| Ratings and comments | **Analytics → Feedback** |
| Where do players drop off? (onboarding, core loop, purchases) | **Analytics → Funnels**, one tab per funnel |
| Where currency comes from and goes | **Analytics → Economy** |
| Any custom event | **Analytics → Explore**, with the custom event as the source (below) |
| Errors and warnings, with stack traces | **Monitoring → Error Report**: up to the minute |
| Frame rate, memory, crashes, server health | **Monitoring → Performance**: up to the minute; charts need 100+ daily players |
| Alerts | **Configurations → Alerts** to set them up; their history is on the alerts' **Analytics** page |
| Saved views | **Custom dashboards** in the game's left navigation |

## Tools on every chart

- **Dates:** pick a range, or drag across a chart to zoom in.
- **Filter By:** narrows every chart on every page until you turn it off. Filters include:
  - age group, gender, country, language
  - source (recommendations, search, ads…)
  - when the player first played
  - active payer status (top 15%, intermediate, casual, lapsed, never)
  - platform spender status
  - in-game activity status (early, active, lapsed, reactivated)
  - weekly engagement
  - platform and OS
- **Breakdown by:** splits a chart into one line per segment, such as payer status or platform.
- **Explore** (top right of any chart): opens the chart in Explore to dig further.
- **Export:** downloads the chart's data.

## Explore

Builds any chart from standard metrics or custom events.

- **Configure chart:** choose a source (a standard area, or a custom event) and a metric, then a time interval, a breakdown and filters.
- **Custom fields:** break a custom event down by its custom fields. Field 3 is the game's standard slice (ANALYTICS.md "Slicing the data"), so breaking down by it splits any event by progress band, or by experiment variant.
- **Calculated metrics:** turn on **Use operations** to combine metrics with a formula, such as `A / B * 100` for a success rate.
- **Chart types:** line for trends, bar to compare segments, stacked column or pie for shares, table for several metrics side by side.
- **Keep it:** **Add to dashboard** saves the chart to a custom dashboard.

## Custom dashboards

Up to 20 per game, shared with everyone who can view analytics.

- **Make one:** **Custom dashboards → Manage all → Create**, then add widgets (charts, tables, summary cards). A dashboard is saved only when you **Publish** it.
- **Pin it:** turn on **Pin to sidebar** for the ones checked daily.
- **Record it** in `live/EXPERIENCE.md` "Custom dashboards".

## Alerts

Real-time warnings without a backend: Roblox watches a metric and notifies when it crosses a threshold. Up to 20 per game; needs 100+ daily players.

- **Set up:** **Configurations → Alerts → Create**. Pick:
  - the metric, and how often it's checked (each minute, half hour, hour or day)
  - the trigger, such as "client crash rate above 5% for 5 minutes"
  - optional filters (place version, OS, platform) and a breakdown
  - a webhook, such as a Discord channel, so the alert reaches people
- **Shortcut:** on the Performance dashboard, a chart's menu has **Create an alert**, already filled in for that chart.
- **Record it** in `live/EXPERIENCE.md` "Alerts".

## After a publish

The post-release check (POST-RELEASE.md) reads these:

- **Error Report:** turn on **Show version** to mark place versions on the chart, and use **New errors since** with the new version to see only what the update introduced.
- **Performance:** **Breakdown by → Place Version** compares the new build against the previous ones.
- **Alerts:** anything that fired since the publish.
