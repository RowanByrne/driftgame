# Decisions

The user's decisions about this game, so they aren't reopened later. Before proposing something, check it hasn't already been decided here.

- **One line each, newest at the bottom:** the date, the decision, and why. Quote the user's own words when they say it best.
- **Phase gates go here too:** when the user says go at a gate (docs/workflow/WORKFLOW.md).
- **Never delete a line.** When a decision changes, add a new line and mark the old one "superseded by <date>".
- **Detail lives elsewhere.** A decision that changes a design or contract also updates that doc (`GDD.md`, `CONTRACTS.md`, a feature spec); this line just records that it was decided and why.

| Date | Decision | Why |
|---|---|---|
| 2026-11-03 | The cars are not driven by Roblox's physics system; the drift model is our own code | "its unreliable and too random" |
| 2026-11-03 | Meta progression and the larger scale stay undecided until a baseplate prototype proves the drift feel | The user wants "the sleek drifting game feel" first; what's left to decide is in GDD.md "Open after the prototype" |
| 2026-11-03 | The baseplate prototype is built now, before the pitch gate and before the rest of the foundation kit | The user asked to start building it ("start building the prototype"); the drift feel is the one risk nothing downstream survives (PITCH.md "Biggest risks"). DataService, analytics, UI kit and the rest are built before anything saves, sells or scores |
