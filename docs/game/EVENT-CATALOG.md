# Event catalog

Every analytics event this game sends, and what each field means. The rules (naming, slots, limits, client checks) are in docs/workflow/ANALYTICS.md; the code copy of this catalog is the events registry module (`ARCHITECTURE.md` "Registries"). A feature's events go here before it's done. Replace each prompt with the answer.

## Standard slice

Custom field 3 on every event (ANALYTICS.md "Slicing the data").

> What the slice is for this game and its values. By default it's the player's progress band, such as `L1-5`, `L6-10`, `L11-20`, `L21+`. Keep it to a handful of values.

| Value | Means |
|---|---|
| | |

## Funnels

> Each funnel's steps in order. A funnel is one custom event, with the step in field 1 (ANALYTICS.md "Naming"). After launch, never renumber a live funnel: add a new one.

### FTUE (`FtueStep`)

| # | Step | Source | Fields |
|---|---|---|---|
| 1 | | server / client | |

### Core loop (optional, `CoreLoopStep`)

| # | Step | Source | Fields |
|---|---|---|---|
| 1 | | | |

### Purchases (`PurchaseStep`)

| # | Step | Source | Fields |
|---|---|---|---|
| 1 | Prompt shown | server | product |
| 2 | Receipt granted | server | product |

## Custom events

> Every custom event. Field 3 always carries the standard slice, so only fields 1 and 2 are listed.

| Event | When it fires | Source | Field 1 | Field 2 | Value (the number sent) | Per-session limit | Feature | Dashboard views |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |

## Economy

> Every currency's sources and sinks, with their transaction type and SKU (`<Kind>:<id>`).

| Currency | Source or sink | Transaction type | SKU | Logged by |
|---|---|---|---|---|
| | | | | |

## Progression

| Path | Levels | Logged by |
|---|---|---|
| | | |

## Client allow-lists

> For every field a client can send, the values the server accepts. Anything else is logged as `other` (ANALYTICS.md "Events from the client").

| Field | Allowed values |
|---|---|
| `device` | `touch`, `gamepad`, `keyboard` |

## Retired

> Events and funnel steps no longer sent. Their names stay reserved, so they're never reused.

| Name | Retired | Replaced by |
|---|---|---|
| | | |
