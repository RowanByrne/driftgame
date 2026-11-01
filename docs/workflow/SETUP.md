# Setup

How an agent turns the user's onboarding answers into the game's docs. The user answers Rocco's onboarding (the questions are in `tools/onboarding.json`). Rocco commits the answers to `docs/game/ONBOARDING.md`, then opens the user's agent on this brief with a Workboard task. When the user says **"set up the game"**, the conductor does the same.

There are three parts: **New game**, **More detail** (the optional tiles, now or later), and **Existing game**. The prompt names the part and the Workboard task (`T-012`).

## The answers

`docs/game/ONBOARDING.md` holds the user's own words, each under its question, with the doc sections it's for (`For: PITCH.md "Hook"`). Its first lines say which flow it was ("A new game" or "A game brought in") and, for one brought in, where it came from. Read it all first. An empty answer is skipped, not guessed at.

## Rules

- **The user's words first.** Keep their phrasing where it fits; tidy it, but don't change the idea.
- **Never invent facts.** A section the answers don't cover keeps its prompt, or gets a short proposal marked **(proposed)** for the user to accept or change. Numbers and targets are always proposals until the user says otherwise.
- **Each doc keeps its shape.** Replace the prompts (the `>` lines) with answers; keep the headings and tables. Where a section already has content (a later run), merge the new answer in, and say what changed.
- **Only the docs this part names.** No code, art or places yet (WORKFLOW.md "Pitch").
- **Platform risks** the answers raise (other companies' names, paid random rewards, mature content) go in PITCH.md "Biggest risks" (PLATFORM-RISKS.md).
- **The Workboard card** (Rocco's commands, in PowerShell from `repo\`: `..\..\_tools\rocco\rocco.ps1`):
  - **As you go:** `set T-012 -Step "PITCH.md"`.
  - **When done:** `set T-012 -Status ready -Where main -Summary "<what's filled, and the open questions>" -Test "<what to read, and what to approve>"`.
  - **A question that blocks the docs:** `ask T-012 -Question "..." -Options "...","..."`, then stop. Anything that doesn't block goes in the summary instead.
- **Commit** as `Setup: <what>` with your Co-Authored-By line (AGENTS.md "Git"), then `git pull` and push `main`.
- **Report** short (AGENTS.md "Talking to the user"): what's filled, and what the user should read or decide.

## New game

The first drafts that prototyping needs; the Pitch phase carries on from them (WORKFLOW.md "Pitch").

1. **PITCH.md:**
   - **Hook** from `idea`, in one sentence.
   - **Core loop** from `loop`.
   - **Who it's for** from `players`.
   - **Games we borrow from** from `likeThese`, as the table.
   - **Why players come back** from `comeBack`.
   - **Launch scope** from `smallest`.
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
   - **Launch scope** from `smallest`.
   - **Later:** anything the answers push out of the first version.
   - **Now:** "Pitch: approve PITCH.md".
5. **PROJECT.md:** "Current focus" from `notes`, or "The pitch". `notes` that are decisions also get a dated line in DECISIONS.md.
6. **The card's test:** "Read PITCH.md, GDD.md and ART-DIRECTION.md, change anything in Rocco's Docs, and approve the pitch when it reads right."

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
     2. Count the scripts in Studio and the files in `src\`: they must match before anyone starts Lync on that place. Lync replaces the synced folders with what's in `src\`, so a script that wasn't exported would be lost from the place.
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
6. **Places and lanes come later,** when the user's ready (NEW-PROJECT.md steps 5 and 6). Say so in the summary.
7. **The card's test:** "Read ARCHITECTURE.md and PITCH.md: is this the game? Then the suggestions."
