# Revenue

Every way a Roblox game earns, with the rules and APIs for each. These change often, and models' training data lags behind them: trust this doc over memory, and re-check it against Roblox's docs before designing an offer. This game's offers and targets are in `docs/game/MONETIZATION.md`, paid random items in PLATFORM-RISKS.md, and granting purchases safely in CODING.md "Server rules".

**Last checked against Roblox's docs: 2026-11-02.**

## Payouts from Roblox

Earned without a purchase in the game.

- **Creator Rewards** replaced Engagement-Based Payouts (the payouts for Premium members' playtime) on 2025-07-24. Nothing pays for Premium playtime any more.
  - **Daily engagement:** 5 Robux a day for each Active Spender who plays the game 10 minutes or more that day, across sessions. Only the first 3 experiences a user opens each day count. An Active Spender has spent at least $9.99 on Roblox in the past 60 days and isn't a new or returning user.
  - **Audience expansion:** 35% of the first $100 a new or returning user (away 60 days or more) spends anywhere on Roblox in their first 60 days. It counts when they arrived through the game's share link, a direct link or a search by name, started their day in the game, and played 10 minutes or more. The game must average 100 or more daily players over those 60 days, and the creator must be ID-verified.
  - Both pay Earned Robux, held for 60 days.
  - **What this rewards:** daily sessions of 10 minutes or more, being a player's first stop of the day, and bringing players in through share links. Weigh it in `docs/game/RETENTION.md` and `PACING.md`.
- **Roblox Plus** replaced Premium for new subscribers on 2026-04-30. It pays up to 100 Robux for each Plus subscriber who spends 60 minutes or more in the game's paid private servers over 30 days, and up to 750 Robux for each new Plus subscriber the game brings in through `MarketplaceService:PromptRobloxSubscriptionPurchase`.

## Passes and developer products

- **Regional pricing.** Passes have Roblox-managed regional prices, on by default; turn them off per pass in the Creator Hub (Monetization, Passes, Disable Managed Pricing). Developer products are opted in one at a time, and only once the game reads prices at run time and checks price levels (below). A regional price is up to 70% below the default and never above it.
- **Never hard-code a displayed price.** Show what `MarketplaceService:GetProductInfoAsync` returns, which is that player's regional price; `GetDeveloperProductsAsync` returns every product's.
- **Trading and gifting** anything bought with Robux: read each player's price level with `MarketplaceService:GetUsersPriceLevelsAsync(userIds)` when they join, and don't cache it. Each level is 1 to 1000, where 1000 is the full price. Roblox suggests gifts only from a higher price level to a lower or equal one, and trades only between equal levels. This is required before opting products into regional pricing.

## Subscriptions

- **Up to 50 per game:** Durable, Consumable or Currency. Tiers that replace each other aren't supported.
- **Price:** in Robux, 49 or more, with regional pricing always on; the creator gets 70%. Or in local currency, at $2.99, $4.99, $7.99, $9.99 or $14.99, for an ID- or phone-verified creator, and not in every country; the creator gets 70% the first month, then 100%.
- **API:** the server checks `MarketplaceService:GetUserSubscriptionStatusAsync(player, subscriptionId)`, which returns `{ IsSubscribed, IsRenewing }`, when a player joins and again on `Players.UserSubscriptionStatusChanged`. The client prompts with `MarketplaceService:PromptSubscriptionPurchase(player, subscriptionId)`.
- **Rules:** the same benefits on every platform, honored for the whole term. No extra tasks to unlock a benefit (battle passes excepted), and never send players off Roblox to buy. The Robux price changes at most once every 60 days, with 30 days' notice before a rise.

## Rewarded video ads

- **Who can show them:** a public game with an approved maturity questionnaire, no free-form user creation, and 2,000 or more unique visitors a month; its publisher 13 or older, ID-verified, with 2-step verification on. Only players 13 and older see ads. Turn them on in the Creator Dashboard: Monetization, Ads, Settings.
- **API:** the client checks `AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)`. The server makes the reward with `AdService:CreateAdRewardFromDevProductId(productId)` and shows the ad with `AdService:ShowRewardedVideoAdAsync(player, reward, placementId)`. The reward is granted through `ProcessReceipt`, like a purchase.
- **Rules:** the reward is a developer product, never Robux and never random, worth about 3 to 10 Robux. Progress never depends on watching an ad.
- **Pay:** per impression, at a rate Roblox doesn't publish.

## Private servers

Free, priced in Robux, or off: the setting is in `live/EXPERIENCE.md` "Multiplayer". Paid private servers also earn the Roblox Plus payout above.

## Sources

- Creator Rewards: https://create.roblox.com/docs/creator-rewards
- Roblox Plus: https://about.roblox.com/newsroom/2026/04/introducing-roblox-plus-subscription
- Regional pricing: https://create.roblox.com/docs/production/monetization/regional-pricing
- Subscriptions: https://create.roblox.com/docs/production/monetization/subscriptions
- Rewarded video ads: https://create.roblox.com/docs/production/promotion/rewarded-video-ads
- The APIs: https://create.roblox.com/docs/reference/engine/classes/MarketplaceService and https://create.roblox.com/docs/reference/engine/classes/AdService
