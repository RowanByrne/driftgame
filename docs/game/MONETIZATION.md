# Monetization

What players can buy and why it's worth it. This is the design; product ids and dashboard settings live in `live/EXPERIENCE.md`, purchase code follows docs/workflow/CODING.md "Server rules", and the launch checks are in LAUNCH.md "Purchases". Prices and what to sell are the user's call. Replace each prompt with the answer.

## Targets

The user sets these before any offer is designed.

- **How pay-to-win:** > How much paying may affect gameplay: cosmetics and convenience only, faster progress, or stronger stats. This shapes every offer below.
- **Numbers:** > The operating targets, such as payer conversion and revenue per paying user as Roblox benchmark percentiles. They're goals to steer by, not promises.

## Principles

- **Always free:** > What every player can reach without paying (the story, the core content, skill).
- **No prompts here:** > Moments a purchase prompt never appears on its own, such as while joining, during a story scene, mid-fight, or straight after a loss.
- **Where the shop lives:** > How players find offers: one shop entry, a launcher, in-world stalls.

## Currencies

> Every currency, what it buys and how it's earned. If there's a premium currency bought with Robux, say exactly what it's for, and whether players can also earn it by playing.

| Currency | Earned by | Bought with Robux | Spent on |
|---|---|---|---|
| | | | |

## Offers

> Every offer. Game passes are one-time and can also be bought from the game page at any time; developer products are bought in game only and can repeat, so anything that rotates (a weekly item) or is consumed is a product.

| Offer | Pass or product | Price (Robux) | What it gives | Why a player buys it | Status |
|---|---|---|---|---|---|
| | | | | | Idea / built / on sale |

## Starter offer

> The first-time offer, if there is one: what's in it, its price, when it appears, how long it lasts.

## Recurring

> Reasons to spend again: daily rewards, weekly or limited items, events (`live/CALENDAR.md`).

## Paid random items

> Anything bought with Robux, or with a currency bought with Robux, that gives a random result. If the game has none, say so.

- **Odds:** shown as percentages before every purchase, for the current state.
- **Restricted players:** players whose policy restricts paid random items (`PolicyService`) can't buy them, and still have a way to play.
- **Pity and trading:** > Any guarantee after a run of bad luck, and whether paid items can be traded.

## Price display

> How prices appear in game: Roblox's Robux glyph and the price, and what shows before a product exists or while its price loads ("Coming soon").

## Measuring it

- **Only real receipts count.** A cancelled prompt, a refund or a repeated receipt is not a conversion. The Creator Hub's revenue numbers are the authority.
- **Track** payer conversion, revenue per daily player and per payer, repeat payers, and each offer's share (`live/METRICS.md`).
- **Change one thing at a time**, and when experiments exist, test it (`live/EXPERIMENTS.md`). Never inflate conversion with token-price offers.

## Retired offers

> Offers no longer sold. Keep their product ids mapped in code, so receipts that are still outstanding are granted.

| Offer | Id | Retired | Why |
|---|---|---|---|
| | | | |

## Not doing

> Monetization ideas decided against, so they aren't proposed again.
