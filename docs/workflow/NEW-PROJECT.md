# New project

How to start a game from the template, or bring in one that already exists. By hand, the pitch needs only steps 1 to 4: places, lanes and the Roblox experience can wait until Foundation (WORKFLOW.md).

**Usually, Rocco's onboarding does it** (New project, in its project menu). It asks a new game or one already made, then:
1. Makes the project, with the script below.
2. Asks a few questions about the game and the first thing to build: answer as little or as much as you like.
3. For a new game, asks how many lanes this PC can run (LANES.md "How many lanes").
4. Commits the answers to `docs/game/ONBOARDING.md`, and this PC's lanes to `PROJECT.md`.
5. Opens the Main place and the lanes: steps 5 and 6 below, done for you (LANES.md "Open them").
6. Opens your agent on SETUP.md as the game's conductor. It turns the answers into the first docs and, for a new game, the prototype's spec and plan, which wait on the Workboard for you to approve before anything is built (SETUP.md "The prototype").

Tiles add more detail (monetization, economy, the world, ...), then or any time later, from Docs ("Add game details").

**By hand, `tools\new-project.ps1` does steps 1 to 4.** Create the game's empty private GitHub repo first (no README, .gitignore or license), then from `template\repo` run:

```
powershell -ExecutionPolicy Bypass -File tools\new-project.ps1 -Name <Game> -Code <CODE> -GitHubRepo <the new repo's URL>
```

It pulls the template, copies it as `<Game>\` (never its lanes), sets the remotes, picks the first Lync port block no other game in the RoDev folder uses (or `-PortBase`), fills in the details, commits and pushes. Without `-GitHubRepo` it does everything except the push. The steps below are what it does, and how to do them by hand.

## Starting a game

1. **Update the template.** In the RoDev folder (WORKSTATION.md), pull the latest: `git -C template\repo pull`.
   No `template\` yet? Clone it into `template\repo` (`git clone https://github.com/RowanByrne/rodev_template.git template\repo`; the repo is private, so ask its owner for access), then in `template\repo` run `git config worktree.useRelativePaths true` and `git config core.hooksPath tools/hooks` (clones don't carry those settings), and create the folders next to it: `lanes`, `places`, `art\generated`, `art\source`, `art\reference`, `art\captures`, `art\marketing`, `backups`, `scratch`.
2. **Duplicate** `template\` as `<Game>\`, named for the game. A short name without spaces is easiest to type.
3. **Give the game its own GitHub repo.** Create an empty private repo on GitHub (no README, .gitignore or license), then in `<Game>\repo`:
   ```
   git remote rename origin template
   git remote add origin <the new repo's URL>
   git config worktree.useRelativePaths true
   git config core.hooksPath tools/hooks
   git push -u origin main
   ```
   The game keeps the template's history and its release tags; later template releases arrive with "update from template" (TEMPLATE.md).
4. **Fill in the game's details.** Replace every `{{...}}` in `docs/game/PROJECT.md`, `README.md` and `default.project.json`:
   - **Name** and **code**: a short prefix of 2 to 4 letters for the place files (`<CODE>-Main.rbxl`).
   - **GitHub:** the repo from step 3.
   - **Lync port base:** one no other game in this RoDev folder uses (34870, 34890, 34910, ...), in `PROJECT.md` and as `port` in `default.project.json`.
   - **Roblox ids and owner:** leave them until the experience exists (step 7).
   - **Phase:** Pitch. **Update log:** the user's call, whenever they decide.

   Commit `Start <Game> from the template` and push.
5. **Make the Main place.** With Rocco, `rocco.ps1 lanes` makes it and the lanes' places, starts Lync and opens them (LANES.md "Open them"); probe each, and skip to step 7. By hand: in Studio, open a new Baseplate and save it to `<Game>\places\<CODE>-Main.rbxl`. In its command bar run `workspace:SetAttribute("__lync_port", <port base>)`, then save. Run `tools\serve.bat` in `repo\`; the Lync plugin connects. Probe it as for a lane (LANES.md "Probe a lane"), with the probe file in `repo\src\Workspace\`.
6. **Add lanes.** Ask the user how many to create (LANES.md "How many lanes"): as many as the strongest PC that will work on the game opens. Create them all as in LANES.md "Add a lane", record the count in `PROJECT.md` ("Lanes"), and add this PC's row to "Workstations".
7. **Create the Roblox experience** when the game is ready for its first published test. The user publishes the Main place as a new private experience. Then fill in the universe id, start place id and owner in `PROJECT.md`, and `experienceId` / `placeId` in `default.project.json`. Settle account versus group ownership now if possible (LAUNCH.md "Roblox rules").
8. **Begin the Pitch:** open your agent in `<Game>\repo` and start with WORKFLOW.md. If the onboarding ran, SETUP.md has drafted the pitch already, and the prototype's plan is on the Workboard.

## Bringing in a game made elsewhere

A game that already exists, built in or out of this workflow, joins the RoDev folder through Rocco's onboarding ("A game I've already made") or `new-project.ps1 -Existing`:

| The game is | `-Existing` | What the script does |
|---|---|---|
| In a GitHub repo, or a git folder on this PC | its address or folder | Clones it as `<Game>\repo`, with its history, and adds the template as the `template` remote. The game keeps its repo. |
| In a folder without git | the folder | Makes a new project from the template, and copies the folder to `<Game>\import\` |
| In a place file | the `.rbxl` or `.rbxlx` | Makes a new project from the template, and copies the place to `places\<CODE>-Main.rbxl` and `backups\` |
| Only in Studio | `-StudioOnly` instead | Makes a new project from the template |

Then an agent finishes the job by SETUP.md "Existing game":
- **Merge in the template**, or import the code into `src\`.
- **Fit `default.project.json`** to where the code is.
- **Read all of the code** and fill in the docs.
- **Fill in PROJECT.md** from the answers.

Places and lanes follow, as in steps 5 and 6, when the user's ready.

## An existing game on another PC

To work on a game that isn't in this RoDev folder yet:

1. **Clone it** into `RoDev\<Game>\repo`. Then in `repo\`, add the template remote and turn on the settings clones don't carry:
   ```
   git remote add template https://github.com/RowanByrne/rodev_template.git
   git config worktree.useRelativePaths true
   git config core.hooksPath tools/hooks
   ```
2. **Create the folders** next to `repo\`: `lanes`, `places`, `art` (with its subfolders), `backups`, `scratch`.
3. **Copy the place files** into `places\` from wherever they're backed up (WORKSTATION.md "Backups"). If there are none, make them as in steps 5 and 6.
4. **Recreate the lanes** (LANES.md "Add a lane"), and give this PC its row in `PROJECT.md` "Workstations" if it has none.

Two copies of one game on two PCs both push to the same `main`: pull before every push (CONDUCTOR.md "Main"), and claim files in `docs/CLAIMS.md` before working on them.
