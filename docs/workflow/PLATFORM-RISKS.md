# Platform risks

The big ways a game can get into trouble with Roblox: a wrong maturity rating, gambling rules, copyright claims, moderation of uploads or accounts, rules on text and links, and player data. Breaking them can cost the game its audience, its listing or its revenue, and can put the owner's account at risk. Each game records its positions on these in `live/EXPERIENCE.md` "Platform risks".

**Roblox changes these rules often.** Before deciding anything, read the current page linked below. When something is unclear or close to a line, flag it to the user: how much risk to take is the user's call, recorded in `docs/game/DECISIONS.md`.

## When to check

- **Pitch:** does the idea lean on another company's game or characters, random paid rewards, or content only older players should see?
- **Every feature spec:** its "Platform risks" line says which areas below it touches (`features/_TEMPLATE.md`).
- **Monetization phase:** paid random items, trading and offers, in full.
- **Before every publish:** the questionnaire answers are still true for the new content (RELEASING.md).
- **Launch:** every area, in the launch review (LAUNCH.md).

## Maturity questionnaire and labels

Roblox rates every game from the **Maturity & Compliance Questionnaire** (Creator Hub → the game → Audience), and the label decides which accounts can see it.

| Label | Who can play |
|---|---|
| Minimal, Mild | All ages, including Roblox Kids (5–8) and Roblox Select (9–15) accounts |
| Moderate | Roblox Select (9–15) and standard (16+) accounts |
| Restricted | Only ID-verified users 18 and over |

- **Answer for the most mature thing a player can run into,** not the typical session. The questionnaire covers areas such as violence, blood, fear, crude humor, gambling, paid random items, paid item trading, social features, AI interactions, free-form creation and media feeds.
- **Re-take it whenever content changes** what an answer would be, and before the publish that ships it.
- **Never leave a game unrated:** unrated games lose reach.
- **Content May Vary** (16+, age-checked) applies to games whose content players create themselves.

Record the date, the label and the answers that could change in `live/EXPERIENCE.md` "Questionnaire".

## Age and audience

- **Account groups:** Roblox Kids (about 5–8, chat off by default), Roblox Select (9–15) and standard (16+). Design the first-time experience, text and social features for the youngest group the label lets in.
- **Gambling-like content is off limits for under-13s.**
- **Reach can be gated:** a new game may not reach younger players straight away, until it has enough engaged players or passes a review. Check the Audience page early in Launch.
- **Voice chat and camera:** review them against the audience before opening the game to younger players.

## Paid random items and gambling

A **paid random item** is anything bought with Robux, or with a currency Robux can buy, that gives a random result:
- capsules, crates and gacha pulls
- enhancement rolls, such as enchanting, rerolls and upgrades that can fail
- combining items into a random result
- anything that changes the odds: luck boosts and pity

The rules:
- **Show the odds before every purchase,** as percentages adding up to exactly 100%, for every outcome, for the current state. Long decimals keep at least 4 places. When the list doesn't fit, a labelled "Info" or "Details" button may open it; an unlabelled (i) icon isn't enough.
- **Respect regional rules:** where a player's policy restricts paid random items (`PolicyService`), they can't buy them. Offer a guaranteed purchase or another way to play instead.
- **Trading:** players whose policy doesn't allow paid item trading can't trade the results.
- **The questionnaire says yes** to paid random items for as long as the game has any.
- **Grey areas:** paid things that change random outcomes without being bought as a roll (a paid item that changes drop odds, for example). Write down the game's position in `live/EXPERIENCE.md`, and consider publishing the odds anyway.

## Copyright and trademarks

- **No one else's names, characters, music or logos:** not in the game, its name, description, thumbnails or event cards. "Inspired by <another game>" on the game page is a risk too.
- **Original art only:** references guide the style, but never copy their pixels (ART-PIPELINE.md). Prompts never ask for a protected character, brand or logo.
- **Outside assets:** only from the Creator Store, free; audio only from the sources AUDIO-PIPELINE.md allows. Record each one (ART-PIPELINE.md "Creator Store assets").
- **DMCA takedowns:** a copyright holder can have an asset removed, which breaks whatever uses it, and repeat infringement is punished on the owner's account. If a takedown arrives, replace the asset and log an incident; a counter-notice is only for claims that are wrong.
- **Our own work:** if someone copies our game or assets, Roblox's DMCA process applies the other way. That's the user's call.

## Uploads and account moderation

- **Every upload is moderated:** images, audio, meshes, text. A rejected upload can bring a warning or ban on the uploading account, and a banned owner account takes its games with it.
- **Check generated images before upload:**
  - no realistic gore
  - no real people
  - no text that names other games or sites
  - nothing that reads as a brand

  The user picks every image (ART-PIPELINE.md), and the pick includes this check.
- **Group ownership limits the damage:** with the game owned by a group, one member's moderation doesn't take the game down.

## Text, chat and links

- **Filter all player-written text** before anyone else sees it: names, signs, pet names, anything typed. Chat goes through `TextChatService`.
- **No off-platform links inside the game:** no links, invite codes or "join our server" handles. In-game text may only point to "links on our game page". Social links go on the game page and group only, and Roblox shows them only to age-verified 16+ users.
- **Romance and dating features** are against Roblox's rules.

## Engagement incentives

- **Rewards for likes, favorites or joining a group:** common in popular games, and community answers say rewards for likes are allowed. But there's no clear official rule, so check the current Terms of Use and Community Standards before building one, and record the decision.
- **Never misleading:** thumbnails, titles, event cards and in-game prompts never promise what the game doesn't have.

## Player data and privacy

- **No personal information** in analytics or any data we keep: no usernames, chat or anything players write (ANALYTICS.md "Privacy"). Our own data system is anonymized (DATA-SYSTEM.md).
- **Deletion requests:** every data store has a right-to-be-forgotten template (LAUNCH.md "Player data").

## Sources

Check these before deciding:
- [Content maturity](https://create.roblox.com/docs/production/promotion/content-maturity)
- [Experience guidelines](https://create.roblox.com/docs/production/promotion/experience-guidelines)
- [Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items)
- [PolicyService](https://create.roblox.com/docs/reference/engine/classes/PolicyService)
- [Roblox Terms of Use](https://en.help.roblox.com/hc/en-us/articles/115004647846)
- [Community Standards](https://en.help.roblox.com/hc/en-us/articles/203313410)
