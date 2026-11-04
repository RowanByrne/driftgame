# Setup

How an agent turns the user's onboarding answers into the game's docs, and, for a new game, goes straight on to plan the prototype for the user to approve. The user answers Rocco's onboarding (the questions are in `tools/onboarding.json`). Rocco commits the answers to `docs/game/ONBOARDING.md`; for a new game it also records how many lanes this PC runs (PROJECT.md "Workstations") and opens them. Then it opens the user's agent on this brief, as the game's conductor, with a Workboard task. When the user says **"set up the game"**, the conductor does the same.

There are three parts: **New game** (then **The prototype**), **More detail** (the optional tiles, now or later), and **Existing game**. The prompt names the part and the Workboard task (`T-012`).

## The answers

`docs/game/ONBOARDING.md` holds the user's own words, each under its question, with the doc sections it's for (`For: PITCH.md "Hook"`). Its first lines say which flow it was ("A new game" or "A game brought in") and, for one brought in, where it came from. Read it all first. An empty answer is skipped, not guessed at.

## Rules

- **The user's words first.** Keep their phrasing where it fits; tidy it, but don't change the idea.
- **Never invent facts.** A section the answers don't cover keeps its prompt, or gets a short proposal marked **(proposed)** for the user to accept or change. Numbers and targets are always proposals until the user says otherwise.
- **Each doc keeps its shape.** Replace the prompts (the `>` lines) with answers; keep the headings and tables. Where a section already has content (a later run), merge the new answer in, and say what changed.
- **Only the docs this part names.** No code or art in the docs part: for a new game, that comes next, in "The prototype".
- **Platform risks** the answers raise (other companies' names, paid random rewards, mature content) go in PITCH.md "Biggest risks" (PLATFORM-RISKS.md).
- **The Workboard card** (Rocco's commands, in PowerShell from `repo\`: `..\..\_tools\rocco\rocco.ps1`):
  - **As you go:** `set T-012 -Step "PITCH.md"`.
  - **When done:** `set T-012 -Status ready -Where main -Summary "<what's filled, what's proposed, and the open questions>"`. Setup needs no review: Rocco approves the card as it turns ready. The user reads and changes the docs in Rocco's Docs whenever they like.
  - **A question that blocks the docs:** `ask T-012 -Question "..." -Options "...","..."`, then stop. Options are a few words each, the detail in the question (WORKER.md). Anything that doesn't block goes in the summary instead.
- **Commit** as `Setup: <what>` with your Co-Authored-By line (AGENTS.md "Git"), then `git pull` and push `main`.
- **Report** short (AGENTS.md "Talking to the user"): what's filled, and what the user should read or decide.

## New game

The first drafts that the prototype needs. When they're done, go straight on to "The prototype".

1. **PITCH.md:**
   - **Hook** from `idea`, in one sentence.
   - **Core loop** from `loop`.
   - **Who it's for** from `players`.
   - **Games we borrow from** from `likeThese`, as the table.
   - **Why players come back** from `comeBack`.
   - **Launch scope:** a short proposal from the answers, marked "(proposed)": what the first public version needs. `smallest` is the first playtest, not the launch.
   - **Not doing** from `avoid`.
   - **How it makes money** from the Monetization tile if it was answered, else a one-line proposal.
   - **Numbers that show it works:** 3 proposed numbers and targets.
   - **Biggest risks:** from the answers, plus the platform risks.
   - Status stays **Draft**.
2. **GDD.md:**
   - **Overview** from `idea`, one paragraph.
   - **Core loop** from `loop`, as numbered steps.
   - **First five minutes** from `firstMinutes`.
   - The other sections keep their prompts unless a tile answered them.
3. **ART-DIRECTION.md:**
   - **Pillars:** three short phrases from `look`.
   - **World:** style, shapes, palette and mood, as far as `look` says.
   - **References:** the games and styles in `references`, by name or link. Images come later, through ART-PIPELINE.md.
   - The UI part waits for the UI phase.
4. **ROADMAP.md:**
   - **Launch scope:** the proposal from PITCH.md, still "(proposed)".
   - **Now:** "Prototype: " and `smallest`, the first version to playtest (WORKFLOW.md "Core loop").
   - **Next:** "Pitch: the user approves PITCH.md", once they've played the prototype.
   - **Later:** anything the answers push out of the first version.
5. **PROJECT.md:** "Current focus" from `notes`, or "The prototype". `notes` that are decisions also get a dated line in DECISIONS.md.
6. **`features/prototype.md`,** the first build's spec, copied from `features/_TEMPLATE.md`. It's what the prototype plan builds and what the user approves, so it says plainly what they'll get:
   - **Goal** from `smallest`: the one moment that has to feel right.
   - **How it plays** from `controls` and `playground`: what the player does, on which device, and in what space, step by step.
   - **Left out** from `notYet`, plus anything else the answers push past the first build.
   - **Rules and numbers:** only the starting values the build needs, every one **(proposed)**.
   - **Testing** from `judge`: what the user looks for when they play it, and what you'll measure.
   - **Open questions:** each choice the answers leave open that changes what gets built (a control scheme, a camera, the size of the space), with the option you'd pick, marked **(proposed)**.
   - Sections that don't apply to a first build (Monetization, mostly UI) say "Not in the prototype". Status: **specced**. Link it from GDD.md "Systems" and ROADMAP.md "Now".
7. **The card:** ready, with what's filled, what's proposed and what's open in its summary. It approves itself.

## The prototype

Straight after the New game docs, in the same session. The onboarding is the go-ahead for the docs and for planning the prototype, not for building it: the first build is what the user plays first, so they see exactly what it will be, and approve it, before any code is written. The pitch stays **Draft**; the user changes it in Rocco's Docs while the prototype comes together, and approves it once they've played it.

1. **Places and lanes.** Rocco opened them as the onboarding finished: the Main place and this PC's lanes (PROJECT.md "Workstations"), each open in Studio with Lync serving it. Rocco makes a missing place as a plain baseplate with its `__lync_port` already set.
   - **Check each one:** it's in `list_roblox_studios`, and it probes (LANES.md "Probe a lane"; Main's probe file goes in `repo\src\Workspace\`). Still loading? Plan first, then check.
   - **Something missing or not syncing:** `rocco.ps1 lanes` opens whatever isn't open yet, and Lync's plugin may need Resume clicked in that place. A lane that still won't probe stays out of the round: say so in the plan.
   - **No Workstations row for this PC** (the user picked none in Rocco, or there's no Rocco): ask how many (LANES.md "How many lanes"), then `rocco.ps1 lanes -Count N`. Without Rocco, NEW-PROJECT.md steps 5 and 6.
   - **No Studio MCP:** say so, and build without Studio (AGENTS.md "Studio").
2. **Plan it for the user to approve,** from `features/prototype.md` and nothing beyond it:
   - **Foundation first:** the foundation kit the loop stands on (WORKFLOW.md "Foundation", CODING.md), as the first step, which the others wait on. Shared modules and contracts have one owner (CONDUCTOR.md "A round").
   - **Then the spec's Goal and How it plays,** by WORKFLOW.md "Core loop": placeholder art, programmer-art UI, a gray blockout, tuning in config modules, and the loop's first analytics events. Nothing from "Left out", and no extras the spec doesn't name: a good idea goes in its Open questions or ROADMAP.md "Later", not into the build.
   - **On the Workboard:** `plan -Title "Prototype: <the Goal, in a few words>" -Summary "..." -Steps "title|lane|tier",... -Spec docs/game/features/prototype.md`. The summary is what the user reads to decide, so it says, in a few short lines: what they'll be able to play and how, what's placeholder, what's left out, and each choice you made for them that they might not expect ("drift on one key (proposed)"). The card links the spec.
   - **Then wait for the user** (CONDUCTOR.md "Watching the board"). Nothing is built until they approve. They may ask for changes (`[revise]`): change the spec and the plan together (`set <plan> -Summary ... -Steps ...`), then `clear`.
3. **When they approve** (`[approved]`): a task per step (CONDUCTOR.md "What waits on you"). In PROJECT.md set "Phase" to Core loop, and add a dated line to DECISIONS.md: "Prototype plan approved; the pitch stays a draft until the user has played it". Fold the spec's answered Open questions in, as DECISIONS.md lines.
4. **Build it in rounds** (CONDUCTOR.md "A round") in the lanes that probed, merged and checked in a lane before it reaches `main` (CONDUCTOR.md "Checking in a lane"), keeping to the approved spec. A worker that finds the spec doesn't say asks (`ask`), rather than deciding something the user will notice. Each merged task goes to To test, with what to try in the Main place.
5. **When `main` plays end to end** (checked in an idle lane): the Core loop gate (WORKFLOW.md "Rules for every phase"). Write the short gate review, and ask the user to play the first five minutes, then approve the pitch or change it.

Between rounds, and after the report, keep watching the board, so notes the user sends while it's built are picked up.

## More detail

The prompt names the tiles: their sections of ONBOARDING.md, under "More detail". Fill the doc sections each answer's `For:` line names, by the rules above. An answer for a doc the game has moved past (a feature already built differently, say) goes in as a note for the user to decide, not over what's true.

## Existing game

Rocco has made the project folder. ONBOARDING.md's first lines say where the game came from. In order:

1. **Bring in the code.** How depends on where the game came from:
   - **A git repo** (on GitHub, or a folder on the PC): `repo\` is the game's own repo, with its history. The `template` remote is there, but none of the template's files are yet.
     1. Find the newest release: `git fetch template --tags`, then `git tag -l "template/v*" --sort=-v:refname`.
     2. Merge it on `main`: `git merge --no-ff --allow-unrelated-histories template/vX.Y.Z`.
     3. Resolve the conflicts:
        - **The game's code and data win.**
        - **The template's rules, docs and tools come in whole.**
        - **`.gitignore`:** both sets of lines, the game's under `# This game`.
        - **`README.md`:** the game's text, plus the template's "Working on it" and "Folders".
     4. Turn on the commit check: `git config core.hooksPath tools/hooks`.
   - **A folder without git:** `repo\` is a new project from the template, and the game's files are in `..\import\`.
     1. Move the code into `src\`, keeping its structure.
     2. Commit.
     3. Leave anything that isn't code (models, place files) in `..\import\`, and list it in the summary.
   - **A place file, or only in Studio:** `repo\` is a new project from the template. A copy of the place is in `..\places\<CODE>-Main.rbxl` and `..\backups\`; if no file was given, the user opens the game in Studio.
     1. Through the Roblox Studio MCP, export every Script, LocalScript and ModuleScript into `src\`, following `default.project.json`'s mapping. They become `.luau` files with the right first-line markers (AGENTS.md "Code").
     2. Count the scripts in Studio and the files in `src\`: they must match before anyone starts Lync on that place. Lync replaces each script that has a file of the same name and leaves the rest where they are, so a script that wasn't exported would stay in the place, running beside the synced code but outside git.
2. **`default.project.json`** is what Lync serves (Rojo's project format).
   - It maps where the game's code really is: keep the game's own layout rather than moving everything.
   - It keeps the template's top-level fields: `name`; `port`, the game's Lync port base; and `experienceId` and `placeId` when they're known.
   - **A cloned repo needs its port base picked:** the first of 34870, 34890, 34910, ... that no other game in the RoDev folder uses (their `default.project.json`). Use the same number in PROJECT.md. A project made from the template has one already.
3. **PROJECT.md:**
   - Name, code and GitHub.
   - The Roblox ids and owner, from `published`.
   - **Phase:** Live if `live` says it's public, else the phase the game is really in (WORKFLOW.md).
   - **Launched:** the date, if it's live.
   - **Hands-off places** and **Game-only rules**, from `team` and `keep`.
   - **Current focus**, from `next`.
4. **Read all of the code,** then fill in:
   - **ARCHITECTURE.md:** modules, services and controllers, registries, vendored libraries with their versions.
   - **CONTRACTS.md:** saved data (keys and shape), remotes, tags, attributes, service APIs.
   - **EVENT-CATALOG.md:** every analytics event the code sends.
   - **MONETIZATION.md:** every game pass, developer product and subscription in the code, with the `money` answer.
   - **GDD.md:** an overview, the core loop, and a row in "Systems" for each system found. Fill progression, economy, content and social as far as the code shows.
   - **PITCH.md:** the game as it is, from the answers and the code. If it's live, "Launch scope" is what shipped.
   - **WORLD.md:** the named spots and areas the code knows.
   - **ROADMAP.md:** "Now" from `next` and `problems`.
   - **`live/EXPERIENCE.md` and `live/RELEASES.md`** if it's live, with a first row: "Brought into the RoDev workflow".
   - **DECISIONS.md:** a dated line, "Brought into the RoDev workflow".
5. **Don't rewrite working code to the template's rules now** (CODING.md). List the biggest gaps as suggestions on the Workboard (`suggest -Title "..." -Summary "..."`) for the user to queue.
6. **Places and lanes come later,** when the user's ready: Lanes in Rocco's sidebar opens them (or NEW-PROJECT.md steps 5 and 6). Say so in the summary.
7. **The card:** ready, with what came in and what to read first (ARCHITECTURE.md and PITCH.md: is this the game?), then the suggestions, in its summary. It approves itself.
