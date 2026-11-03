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
| 2026-11-03 | The prototype world is a flat plate with buildings and alleys to drift through, not a track of named corners | The first build was a one-way ribbon of track; the user: "all we need is a flat baseplate for testing - you can put some obstacles like pretend buildings or alleys to try and drift through to test the handling, but we don't need specific sections of track". Elevation is allowed where it earns its place, and is checked by screenshot |
| 2026-11-03 | The control scheme is one finger (or the mouse) slid left and right, as DRIFTO does it: the same input steers and puts the car into the drift. The two-thumb scheme (a stick plus a separate drift button) is dropped | "teh control style of the game should be like drifto - one finger that you slide left to right (or mouse) to put the car into a drift". Settles the open question in `features/drift-model.md` without the playtest it was waiting on |
| 2026-11-03 | The finger does not steer: it controls the back of the car and how hard the car is sliding. Pushed fully to one side and held, it scrubs the car's momentum away. Speed loss rises with slip angle | The user drove the first build: "its too smooth - like we are directly steering the car but you are just turning it sideways so it looks like we are drifting... our finger is controling how hard we are sliding into the drift... Drifting creates friction, and the harder the drift, the more friction, the more the car is going to get slowed down. The finger should feel like we are controlling the weight balance of the car." Supersedes the plain steer-and-drift mapping decided earlier the same day |
