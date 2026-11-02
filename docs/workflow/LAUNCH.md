# Launch

The Launch phase (WORKFLOW.md): go public without losing player data or money. **Start early.** Some of Roblox's checks take days, and some unlock only after enough players.

## The launch review

The agent works through the checklist below and writes a launch review in `docs/archive/LAUNCH-REVIEW-<date>.md`.

- **Look widely:**
  - The Creator Dashboard, read in the browser while the user is signed in.
  - The code, with separate passes for security and data, Roblox policy, and analytics and live ops.
  - A measured Studio performance and error run.
- **Fix what's safe and in scope.** Anything that's the user's call, or that spends money, goes under "Your decisions". The agent never spends Robux.
- **The review's sections:** Verdict, Done, Blockers, Your decisions, After launch (recommendations by priority), Measurements.
- **Run it again** when blockers are cleared, and update the verdict. The user decides when to go public, and publishes.

## Checklist

### Player data

- **Saving is safe:** the saving rules in CODING.md are in place, and the save tests pass (TESTING.md).
- **Launch wipe (the user decides):** start everyone fresh by moving the data store names up a version, or carry beta progress over. Leave the old stores untouched either way.
- **Right to be forgotten:** one deletion template per data store, keyed by user id (Creator Dashboard, data stores). These are standing auto-delete rules, so create them only with the user's OK.
- **Storage:** a full server's save traffic fits the data store limits, and the storage total is well under the experience's limit (CODING.md "Data store limits"), with Roblox's storage notifications on.
- **Tests never touch live data.** With Studio API access on, Studio uses the live data stores, so keep tests on memory mode or fake stores.

### Purchases (if the game sells anything)

Built and tested in the Monetization phase (WORKFLOW.md); check them again here on the build that goes public.

- **Set up and recorded:** every pass and product exists on the dashboard with its name, description, price and image; its id is in code; it's recorded in `live/EXPERIENCE.md`.
- **Descriptions are right:**
  - They describe what's live, with nothing retired.
  - Read each one back after saving: Roblox's text filter can turn a description into `####`.
- **Receipts:** granted exactly once, failing closed (CODING.md "Server rules"), and the purchase tests pass.
- **Paid random items:**
  - Odds are shown as percentages before every purchase, for the current state.
  - Players whose policy restricts paid random items (`PolicyService`) can't buy them, and still have a way to play.
  - The questionnaire says the game has them.
- **A way to switch checkout off** without republishing (a Roblox config flag, CONFIGS.md), so a broken offer can be stopped at once.
- **Live smoke test (the user):** buy the smallest product once, rejoin, and confirm it stuck with no double grant. Check pass benefits with an account that isn't the creator's.

### Roblox rules

Every area in PLATFORM-RISKS.md is checked against Roblox's current rules, and the game's positions are recorded in `live/EXPERIENCE.md` "Platform risks".

- **Questionnaire:** the maturity and compliance questionnaire is submitted and still true. Re-check it after content changes.
- **No one else's names:** the name and description don't use another company's game or trademark. "Inspired by <game>" is a risk.
- **Social links** go only on the game page and the group, never inside the game. In-game text may only point to "links on our game page".
- **Text:** no player-written text reaches other players unfiltered. Chat goes through `TextChatService`.
- **Audience:** check who can play (Manage audience) early. Younger players may be held back until enough engaged players or a review fee. Review voice chat and camera settings for the audience.
- **Owner:** settle account vs group before launch. A later transfer keeps ids, but changes who receives revenue and who must grant asset permissions.

### Assets

- **Every asset loads in the published experience:** run the permissions check (ART-PIPELINE.md "Ownership and permissions").
- **Audio:** every sound has its source and license recorded, and any credits it needs show in the game (AUDIO-PIPELINE.md).
- **Badges** are published, with their ids set in code.

### Devices and performance

- **Real phones:** every supported layout checked on a real phone, not only in Studio's emulation (UI.md).
- **Measured and recorded in the review:** frame time, client script time (phones are several times slower), server heartbeat, remotes per second, time to playable on a cold load, and client memory on a low-end phone (target under about 1 GB).
- **Clean console:** a fresh session shows no errors and no warnings.
- **Streaming:** the `StreamingEnabled` decision is recorded in `ARCHITECTURE.md`, with the reasons.

### Security

- **Remotes:** every remote is type-checked and rate-limited, with no `InvokeClient`. Debug hooks run only in Studio, and the admin console on live servers is limited to the owner and listed admins.
- **Client-decided outcomes:** anything the client decides that pays out (a catch, a score, a win) has a server check, such as plausibility or minimum times. The review lists what's still open.
- **Leaderboards** ignore admin-forced or debug outcomes.

### Analytics

- **Arriving before launch:** the standard events show up in Roblox's dashboards from a published test, with the standard slice filled in (ANALYTICS.md).
- **Events fire:** the FTUE funnel, every economy source and sink, purchases and progression.
- **Privacy:** strings from the client are allow-listed, so no personal information gets through.
- **Alerts:** once the game has 100+ daily players, alerts for crashes and other critical health metrics are set up with a webhook (DASHBOARDS.md "Alerts"; record them in `live/EXPERIENCE.md`).

### Game page

- **Ready to publish:** the final name (no "[beta]" or "[test]"), description, icon, thumbnails, a gameplay video, genre, and social links (`live/GAME-PAGE.md`).
- **A launch event** on the game page (`live/CALENDAR.md`).
- **Private servers:** on or off, and the price (the user decides).

### Going live

- **The build is current:** what gets published is the current `main` (RELEASING.md "Before a publish").
- **The user** makes the experience public and publishes. Then follow RELEASING.md "After a publish" and record the launch date in `PROJECT.md`.

## Worth having

Not required to launch; the review lists whichever are missing, by priority.

- **Roblox configs** for feature flags and calendar values, not just checkout (CONFIGS.md).
- **Updating without kicking:** a soft shutdown with an "update available" notice, and the version number shown in settings.
- **Return reasons:** experience notifications (opt-in after a first success) and daily or weekly goals.
- **Social:** an invite prompt, a group-join reward, a favourite prompt after a first big moment, a playing-with-friends bonus.
- **An in-game update log,** if the user wants one (RELEASING.md "Update notes").
