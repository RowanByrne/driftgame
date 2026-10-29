# Workflow

How a game goes from idea to live. The current phase is in `docs/game/PROJECT.md`, and it decides what work makes sense right now.

**These phases are a starting point, not a rulebook.** The user may skip, merge, reorder or redefine them for any game, at any time; what they say wins. Without other direction, run through them in order. A change that holds for one game goes in that game's `PROJECT.md` ("Game-only rules").

| # | Phase | Goal | Ends when |
|---|---|---|---|
| 1 | Pitch | Decide what we're making and why it can win on Roblox | The user approves `PITCH.md` |
| 2 | Foundation | The project runs end to end on solid code | The foundation checklist passes |
| 3 | Core loop | Find the fun | The user plays it and says go |
| 4 | Production | Build the launch scope, with programmer-art UI | The launch scope in `ROADMAP.md` is done |
| 5 | UI | Turn the programmer-art UI into the finished look | The user approves every screen |
| 6 | Monetization | Build every launch offer, the shop and checkout | Every launch offer works end to end in a published test |
| 7 | Launch | Go public safely | The user publishes it publicly |
| 8 | Live | Keep players coming back; ship updates safely | (ongoing) |

Phases are short until UI. With agents working in parallel, a core loop can be playable on the first day and the launch scope built within weeks. UI and Monetization are the long ones: plan for each to take as long as everything before UI.

## Rules for every phase

- **The user decides at every gate.** Before asking, Claude writes a short gate review in chat: what's done, what was measured, open risks, and a recommendation. When the user says go, update the phase in `PROJECT.md` and add a line to `DECISIONS.md`.
- **Going back is fine.** If the game stops being fun in production, return to Core loop instead of piling on content.
- **Write the docs as you go.** Each phase's docs are part of its work, not a cleanup afterwards.
- **Out-of-phase ideas go in `ROADMAP.md` "Later"**, not into the current work.
- **Analytics runs through every phase** (`ANALYTICS.md`). Each phase below says what it adds. Events are designed with the feature they measure, never bolted on at the end.

## 1. Pitch

Decide what we're making before any code.

- **Produces:** `docs/game/PITCH.md`: the hook in one sentence, the core loop in 3 to 5 steps, who it's for, 2 or 3 games we borrow from and what we take from each, why players come back, how it makes money, the launch scope, the biggest risks, and the 3 to 5 numbers that will show the game works (day-1 retention, session length, purchase rate, ...). Also a first `ROADMAP.md`.
- **Claude:** looks at comparable Roblox games, proposes 2 or 3 directions when the idea is open, drafts the pitch, and pushes on its weak spots (a vague hook, no reason to return, a scope too big for weeks).
- **Not yet:** code, art, places.
- **Gate:** the user approves `PITCH.md`.

## 2. Foundation

Get the project running end to end, so everything built after it stands on code that lasts.

- **Produces:** the project from the template (`NEW-PROJECT.md`): GitHub repo, `PROJECT.md` filled in, places and lanes. The foundation kit in `src/` (`CODING.md`): Services and Controllers loaders, a remotes registry, DataService with memory mode in Studio, the debug bridges, the Studio test kit (test profile, quiet playtests), the analytics helper with the standard events (`ANALYTICS.md`). A placeholder world. First versions of `ARCHITECTURE.md` and `CONTRACTS.md`.
- **Gate (Claude's checklist, then tell the user):** every lane probes (`LANES.md`); a playtest in the Main place joins with no console errors or warnings; player data saves and loads through DataService; a quiet playtest is silent; the standard analytics events from a playtest show in the helper's Studio log with the right fields.

## 3. Core loop

Find out whether it's fun, as fast as possible.

- **Produces:** the core loop from `PITCH.md`, playable in the Main place with placeholder art and programmer-art UI (see Production). Tuning numbers live in config modules, never in the logic. The core loop section of `GDD.md` and a spec per loop feature in `features/`. Funnel events for each step of the loop, so the user's playtests produce data.
- **Rules:** speed over polish, but the code is real: server authority, contracts and tests still apply, because this code ships.
- **Not yet:** final art, monetization, content beyond what the loop needs.
- **Gate:** the user plays the first five minutes and says go, change or stop.

## 4. Production

Build out the launch scope in rounds (`CONDUCTOR.md`).

- **Produces:** the features and content in `ROADMAP.md`'s launch scope, each with a spec in `features/`. World art and models, with `ART-DIRECTION.md` set before the first art round (`ART-PIPELINE.md`). Sounds. The first-time player experience from join to the first reward. `MONETIZATION.md` filled in with the user: the targets, how pay-to-win, currencies and offers, so features leave room for what will be sold (it's built in the Monetization phase). Analytics events for every feature, listed in `EVENT-CATALOG.md`: a feature isn't done until its events fire.
- **UI is programmer art until the UI phase:** simple placeholder screens with little styling, built on the shared theme. Their job is to help the user work out the layout: what each screen shows, and where text and buttons go. The user decides every device layout here (desktop, phone landscape and portrait can be completely different; UI.md "Layouts per device"), never at the end. Spend the effort on layout and clarity, not looks.
- **Rules:** `main` must always play: a broken branch doesn't merge. Scope that isn't in the launch list goes to "Later".
- **Gate:** the launch scope is done and the user agrees to start UI.

## 5. UI

Turn the programmer-art UI into the finished look. This is the most demanding phase: the full workflow is in `UI.md`.

- **Why after production:** by now every screen's layout has been worked out in programmer art, so the style is designed once, for screens that have settled.
- **Steps:**
  1. **Style.** Decide the concept art and style with the user. Record it in `ART-DIRECTION.md` with the approved reference images.
  2. **Inventory.** Gather every screen built as programmer art so far, and what's on each, in `UI-INVENTORY.md`.
  3. **Components.** From the inventory, group similar elements into a small set of flexible components (buttons, panels, tabs, counters, icons, ...), in the same file: one button component with variants, not eight. The set should cover the whole game, so later screens don't need new components.
  4. **Assets.** Work with the user to generate the art for each component (`ART-PIPELINE.md`): candidates, the user's pick, upload.
  5. **Rebuild.** Apply the finished components to every screen, keeping the layouts the user settled on in programmer art, for every device.
- **Rules:** every screen passes the readability and layout checks in `UI.md` on every supported screen size. A rebuild never changes what a screen does: input and gameplay behaviour stay the same.
- **Gate:** the user approves every screen, and agrees to start Monetization.

## 6. Monetization

Build what `MONETIZATION.md` designed: every launch offer, the shop, checkout and what each purchase grants. This is a large phase of its own, not a task squeezed into another one.

- **Why after UI:** offers need settled features to sell and finished UI to sell them in (the shop, purchase buttons, offer windows), so they're built once.
- **Steps:**
  1. **Review the design** in `MONETIZATION.md` with the user: targets, how pay-to-win, currencies, offers and prices. The user decides prices.
  2. **Create the offers** on the Creator Dashboard: the user does it, or asks Claude to in the browser. Record ids and prices in `live/EXPERIENCE.md`, and the ids in code.
  3. **Build** the shop and purchase flows from the UI phase's components (new art through `ART-PIPELINE.md`), the receipts and grants (CODING.md "Server rules"), currencies, the starter offer, recurring offers, and paid random items with their odds and policy gate.
  4. **Instrument** the purchase funnel and every currency source and sink (`EVENT-CATALOG.md`).
  5. **Test:** the purchase tests pass (TESTING.md "Automated tests"), checkout can be switched off by a Roblox config (`live/CONFIGS.md`), and the user runs a live smoke test in a private published test: buy the smallest offer, rejoin, and check it stuck with no double grant.
- **Rules:** Claude never spends Robux. No purchase prompt appears on its own at the moments `MONETIZATION.md` rules out.
- **Gate:** every launch offer works end to end in a published test, and the user approves the shop.

## 7. Launch

Go public without losing player data or money.

- **Produces:** every item in `LAUNCH.md` checked, including data safety, monetization set up and tested, Roblox's questionnaire, asset permissions, devices and performance, and the store page. Analytics events arriving in Roblox's dashboards from a published test. A launch review in `docs/archive/`. Start early: some of Roblox's checks take days.
- **Gate:** the user publishes publicly. Record the date in `PROJECT.md` ("Launched") and the release in `live/RELEASES.md`.

## 8. Live

Keep players coming back and ship updates safely.

- **Every publish:** the pre-publish checklist (`RELEASING.md`), update notes when the user wants them, then a line in `live/RELEASES.md`. Publish often: when the live build falls behind `main`, store text and docs start describing features players don't have yet.
- **After each publish:** watch the Creator Hub error report and server stats; anything that loses data, money or access is an incident.
- **Live changes without a publish:** tuning, flags and timed content go through Roblox configs (`live/CONFIGS.md`).
- **Weekly:** review the key numbers in the Creator Hub (docs/workflow/DASHBOARDS.md shows where each one is) and let them steer `ROADMAP.md`.
- **Live events:** plan them in `live/CALENDAR.md`.
- **Incidents:** anything that loses data, money or access gets a postmortem in `live/INCIDENTS.md`.
- **Data changes:** a data schema change ships with a migration that was tested on saved data from the previous version.
