# Experiments

A/B tests through Roblox's own experiments (Creator Hub → the game → **Experiments**), built on configs (CONFIGS.md). An experiment gives some players a different value for one config key and measures the difference. This game's experiments, with their hypotheses and results, are logged in `live/EXPERIMENTS.md`.

**Who decides:** whether to run an experiment, what to test (prices especially), and which variant wins are the user's calls. The agent proposes hypotheses, sets experiments up, watches them and reports.

## Is it worth running?

- **It needs players.** Roblox shows the **minimum detectable effect**: the smallest change the experiment can reliably see. If that's bigger than any change you'd expect, don't run it. Games under about 1,000 daily players often can't get useful results.
- **Good questions:** onboarding flows, progression, controls, shop layout and visibility, starter pack contents, prices.
- **One question per experiment,** written as a hypothesis first: what changes, what we expect to happen, and why.

## Setting one up

1. **Log the hypothesis** in `live/EXPERIMENTS.md`, with its goal metric.
2. **Make the code read a config key per player** (CONFIGS.md "In the code"), and publish that first. The control value is the config's current value; the code must handle every variant value.
3. **Create the experiment:** type In-game, a name, the goal metric, a duration of 14 to 60 days, the rollout (the share of players included), up to two variants plus the control, and the split between them. Prefer one variant against the control, 50/50, on a large rollout: the easiest to set up and to read.
4. **Target it, if needed,** to players by country, tenure, spending and the other config attributes. Targeting narrows the sample, so check the minimum detectable effect again.
5. **Start or schedule it.** Like publishing a config, this changes the live game: the user starts it, or tells the agent to. Once scheduled, the setup can't change, only the start time. Once running, the config key and the conditions it uses are locked until it ends.

## In the code

- **Enroll late.** Reading the key from the player's snapshot (`GetConfigForPlayerAsync`, then `GetValue`) is what enrolls the player. Read it only when the player reaches the part being tested, so players who never see it don't dilute the results. Only the first read is random; after that the player keeps their variant for that key.
- **Enrolling by in-game state** (such as players with 20+ wins): check the state first, and only then read the key.
- **Keeping a variant across sessions:** Roblox checks targeting again each session. If the test needs continuity, such as a multi-session onboarding flow, save the player's variant in their profile.
- **Log it:** an `ExperimentExposed` event when a player is enrolled (experiment and variant in its fields). The events that measure the experiment carry the variant in the standard slice (ANALYTICS.md "Slicing the data"), so our own measures can be split by variant too.

## While it runs

- **Leave it alone.** Fix major bugs only: other changes to the game can change player behaviour and spoil the results. Run two experiments at once only if they can't affect each other, and never two on one key.
- **First 24 hours: early harm.** Playtime, revenue per player and payer conversion update every 5 minutes. A variant flagged as critically harmful sends a notification (email, the Creator Hub tray, an optional webhook): review it and consider stopping. A **sample ratio mismatch** banner (players not split as set up) means stop and restart. Don't decide on a winner from these early numbers.
- **After that: daily results.** Roblox tracks D1 and D7 retention, playtime, revenue per player, revenue per payer, payer conversion and session time for every experiment, whatever the goal metric.
- **Let it run its full length.** New things get a burst of interest that fades, and early results swing in and out of significance.

## Deciding

- **Only statistically significant changes count:** the confidence interval of the change doesn't cross 0%. Ignore the rest, however big it looks.
- **Trade-offs are the user's call:** for example, revenue up but retention down. Weigh it against player feedback and the vision for the game.
- **Make decision** on the results page rolls out the choice: the control changes nothing; an untargeted variant becomes the config's new default; a targeted variant becomes a condition on the key.
- **Record it:** the result and decision in `live/EXPERIMENTS.md`, a line in `docs/game/DECISIONS.md`, and the key's new live value in `live/EXPERIENCE.md` "Configs". Remove experiment-only code, such as custom enrollment, in a later release.

## Matchmaking experiments

Roblox can also test custom matchmaking settings, one experiment at a time and with no code changes, if the game uses custom matchmaking.

Source: [Experiments (Roblox docs)](https://create.roblox.com/docs/production/experiments)
