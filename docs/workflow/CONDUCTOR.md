# Conductor

The main agent session is the **conductor**, whichever agent the user works with (MODELS.md). It plans the work, hands tasks to workers (each in a checkout of its own, borrowing a lane to test: LANES.md, WORKER.md), and merges their branches into `main`.

The conductor works in `repo\`, the main checkout, which is always on `main`. Workers never touch it. `repo\` serves the **Main place, which is the user's**: what lands in `repo\` shows there at once, and they playtest there. So code is built in a task's checkout, checked in a lane, and `main` only moves to a build that plays ("Checking before main"). No agent playtests in Main or changes it unless the user asks (TESTING.md).

The user hands over work and follows it in Rocco's Workboard, and the conductor keeps the board current ("The Workboard").

## Workers or do it yourself

- **Workers:** several independent tasks, or one big task. Each task gets a checkout of its own, so tasks aren't held to the number of lanes: only to how many agents this PC works at once ("Every agent busy").
- **Conductor, yourself:** a small change (one file, a few lines, nothing claimed). Code still gets a card and a checkout, like a worker's (`work T-034 -Branch agent/<slug>`): commit it there, check it in a lane, and push it ("Checking before main"). Docs, claims and update notes, which Lync doesn't sync, are committed straight in `repo\` and pushed.

## A round

1. **Plan.** Split the request into tasks that own **separate files**: no file belongs to two tasks. Shared modules (`src/ReplicatedStorage/Shared`, contracts) get one owner per round, or go first in a round of their own. Read `docs/CLAIMS.md` and never assign a file another task has claimed. Pick a branch and a worker tier per task (table below). Show the user the plan as a table (task, files, branch, tier) before spawning. Each task is a Workboard task: the user's note itself, or one you add ("The Workboard").
2. **Claim and sync.** Add the round's claims to `docs/CLAIMS.md`, commit, and push `main`, so workers branch from the latest. Then make each task's checkout: `rocco.ps1 work T-012 -Branch agent/<task-slug>`, which prints its folder (LANES.md "Lending a lane").
3. **Spawn** the workers in parallel, each task's card set Working first, the way your agent starts workers (MODELS.md "Workers by agent"). Each prompt starts with "Follow docs/workflow/WORKER.md", then gives:
   - **Task:** what to build, and what done looks like, with its Workboard id (`T-012`).
   - **Files owned:** exact paths; new files marked "(new)".
   - **Checkout:** the folder `work` printed, as an absolute path, resolved now (the project folder can move between sessions).
   - **Branch:** `agent/<task-slug>`.
   - **Proof:** the numbers, logs or debug state that will show it works. Screenshots only for "does it look right?", at most 3, and the final look is left to the user.
4. **Merge, in a checkout.** When workers report, merge their branches in one of the round's checkouts, never in `repo\` and never in a lane ("Checking before main"). Resolve simple conflicts yourself, keeping both sides' intent; with Claude Code, messy or multiple conflicts can go to the `git-integrator` subagent, given the checkout. Record any contract or analytics changes the workers report in `CONTRACTS.md` / `EVENT-CATALOG.md`, in the same checkout.
5. **Check, then push.** Put the merged build in a lane, check it in that lane's place, then push it to `main` from the checkout, so Main gets exactly the build you checked. When it doesn't play, fix it in the checkout first, or drop the merge: nothing was pushed, so `main` never had it.
6. **Lanes need nothing.** A lane holds whatever it was last lent for, and the next loan moves it.
7. **Clean up.** Remove the round's lines from `docs/CLAIMS.md` and push. Delete the merged `agent/*` branches, locally and on GitHub. Rocco removes a merged task's checkout as its card turns ready in Main or its merge is cleared, when nothing in it is uncommitted; one it says it left is yours to look at (`git worktree remove ..\work\<name>` once it's clean).
8. **Report** to the user, short (AGENTS.md "Talking to the user"): what merged and what to try in the Main place, then anything flagged: problems workers raised, follow-ups, decisions needed. On the Workboard, each merged task goes to To test, with what to try, except one the user already tested and approved in its lane (`[merge]`): it stays done.

### Checking before main

How code reaches `main`: a round's merges, your own fixes, and a rollback (ROLLBACK.md). Main only ever moves to a build you've checked, and the user's playtests there are never in your way. The merge is made in a task's checkout, and a lane only ever shows it.

1. **In the task's checkout** (for a round, any one of its tasks'), once its worker is done: `git -C <checkout> fetch origin`, then `git -C <checkout> switch --detach origin/main`.
2. **Make the change there:** `git -C <checkout> merge --no-ff origin/agent/<slug>` for each branch of the round, or your own commit.
3. **Put it in a lane:** `rocco.ps1 sync T-012` when the task still has the lane it was tested in (one the user just approved does), else `rocco.ps1 borrow T-012`. Check the place holds it (the fingerprint, WORKER.md "Testing in a lane").
4. **Check it** in that lane's place, `<CODE>-LaneN`: a quiet playtest (TESTING.md), exercise what changed, and read the console for errors and warnings.
5. **Push it:** `git -C <checkout> push origin HEAD:main`, then `git pull` in `repo\`, which moves `main`, and the Main place, to the build you checked. Rejected, because `main` moved meanwhile: `git -C <checkout> fetch origin`, `git -C <checkout> merge origin/main`, `sync`, check again, and push again.
6. **It doesn't play:** fix it there with another commit and `sync`, or drop it: `git -C <checkout> switch agent/<slug>`. Nothing reached `main`.

After the push, set the card ready (`-Where main`), or `clear` one the user had already approved in its lane (`[merge]`): either lets its lane go, and its checkout with it.

**No lane on this PC:** `repo\` and Main are all there is, so merge and check there. First check the user isn't in a playtest (`get_studio_state` on Main), and tell them you're testing in Main.

### Which tier

Pick a worker tier by how hard the task is. `MODELS.md` says which model and effort each tier runs, and how your agent starts a worker of that tier (with Claude Code: the `roblox-dev-heavy`, `-standard` or `-light` subagent).

| Tier | Use for |
|---|---|
| Heavy | Core systems, tricky gameplay, anything touching player data or money |
| Standard | Well-specified features, content, UI |
| Light | Small, mechanical, clearly specified fixes |

Every tier follows the same brief, WORKER.md; only the model and effort differ.

## The Workboard

Rocco's Workboard (`tools\rocco.bat`) is where the user hands over work and follows it: notes they send, questions, plans to approve, and cards that move from Up next through Working (or Stuck) to To test, until they approve. Keep it current with Rocco's commands, run in PowerShell from `repo\`: `..\..\_tools\rocco\rocco.ps1 <command>` (Rocco's README, "Commands", and the script's header list every option). Not through `powershell -File`: lists like `-Steps` and `-Options` don't survive it. On a PC without Rocco, skip this section.

**What waits on you.** At the start of a session, and of every round, `rocco.ps1 list -Pending`, then `show` each task it lists (between rounds, `wait` lists them as they come: "Watching the board"). What the user did decides what you do:

| `list` shows | The user | You |
|---|---|---|
| `[plan]` | Sent a note as a card (before messages), or Rocco queued a setup card | Take it on as "Taking a message on" says, below, with the note as the card. A setup card (its note starts "Follow docs/workflow/SETUP.md") is done as its note says |
| `[question]` | Asked something | `reply T-012 -Text "..."`, short. It shows under their note box |
| `[approved]` | Approved a feature plan | A task per step: `new -Title "..." -Plan T-020 [-After T-021]` (`-After`: it needs that done first). Then `clear T-020` |
| `[revise]` | Asked for changes to a plan | Change its spec, then `set T-020 -Summary "..." -Steps ...`, then `clear` |
| `[answer]` | Answered a Stuck task's question | Carry on with their answer (to the worker, if one asked), and `set -Status working` |
| `C-… [answer]` | Answered a question you asked them ("Talking to the user") | Carry on with it, then `clear C-…` |
| `C-… [message]` | Wrote to you: a bug, tweak, idea, feature or question, or a reply to one of your messages | `show C-…` (its screenshots, and what they said it is), take it on as "Taking a message on" says, below, then `clear C-…` |
| `C-… [message]` from Rocco itself (`show` says so) | Clicked Fix lanes: a lane with work in it went down (its place closed in Studio, or its Lync stopped), and Rocco is opening it again | Check that lane's place is open (`rocco.ps1 lanes` opens what isn't), have the worker testing there `sync` its task and check the place again (LANES.md "Lync"), and redo what failed while it was down. Then `clear C-…` |
| `C-… [message]` from a feature's agent (`show` says so) | Nothing: an agent of their approved feature wrote to you with `rocco.ps1 tell` | Do what it needs of you (merge its approved branch, a file to claim), then `clear C-…`. Answer it with `rocco.ps1 tell T-020 -Text "..."`, never through Rocco's API or the user's chat |
| `[stop]`, `[resume]`, `[restart]`, `[assign]` | Stepped in on a task from its card: Pause, Resume, Start again, or a lane to test in, or a worker, picked for it | Do what `show T-012` says for it: stop its worker and keep its branch; hand it out again; stop its worker and start a fresh one from what it left; or move it. Then `clear` |
| `[reopen]` | Tested it: not right yet | Their words are the last `you` line in `show`. Fix it as a task again: with the worker that built it, if it's still there (below) |
| `[followup]` | Added to a task while it ran | Fold it in, or pass it to the worker (below); then `clear`. A question about it ("are you stuck?"): answer on its card with `reply T-012 -Text "..."`, which leaves the card where it is. Never `set -Status ready` to answer: ready means built and checked |
| `[merge]` | Approved a feature they tested in a lane, or one with nothing to test approved itself | Merge its branch ("A round", step 4), then `clear`. It's done, so don't `set` it ready again (`set` refuses) |
| `[cancel]` | Deleted a task while it ran, or before its branch merged (its status is `removed`) | Stop its worker, if one is on it (a worker hears it from `set` too). In its checkout, commit what it left to its branch, so nothing is lost. Don't merge the branch, and leave it there in case they change their mind. Take its row out of `docs/CLAIMS.md` and push. What's already in `main` stays; if they want it out, they'll say. Then `clear`, which removes its checkout once nothing in it is uncommitted |
| `[lane]` | Nothing: a task you parked because every agent was busy (below), and one is free now | Start it: `work T-012 -Branch ...`, `set T-012 -Status working ...`, and spawn its worker |

**Passing the user's words to a worker:** send them to the worker that has the task, word for word (with Claude Code, `SendMessage` to its agent), so it carries on with what it already knows: no new worker reading everything again. The user types into the card as into a session, and its session shows the worker's reply. Start a new worker only when that one is gone.

**Every agent busy:** a PC works only so many agents at once (two per lane it opens, or the number in Rocco's Settings), and `work` says when that's reached. Park the task with `set T-012 -ForLane` (or `new -ForLane`), never with words alone in `-Waiting`. It stays in Up next, its card tells the user what it waits for, and `wait` hands it back as `[lane]` the moment an agent finishes: nothing depends on you remembering it.

**Taking a message on** (`C-… [message]`). A message carries no card: the user sees it in the chat, and a card shows under it only when work comes of it. What they said it is (the note box's Fix, Ask or Feature) is in `show`; go with it unless it's plainly something else, and say so.
1. **No card for what isn't work.** A question: answer it in the chat. Something to do that changes nothing in the game (open the lanes, start Studio, push main, run the checks): do it, and say what you did. Then `clear C-…`.
2. **A card for each piece of work, from the message, as you start it:** `new -Title "..." -From C-…`, then at once `set T-034 -Status working -Step "..."`, whether you do it or a worker will (spawning adds its lane). The card gets their words and screenshots, and the chat shows it under their message. The title is a few words that name it, like "Keep the baseplate in playtests": the card shows one line (50 characters at most), and the user's own words stay under it. Work that has to wait for something else: `new ... -From C-… -Waiting "After the trade window"`, and leave it in Up next.
3. **Split it by what it asks, not by how it arrived.** Several unrelated requests in one message are a card each, each `-From` it, with `-Note "<their words for it>"`.
4. **Plan each one as a round.** A feature plan is for **one feature** that takes several tasks to build, or has choices the user should OK first. Never use one to group unrelated requests. Write its spec in `docs/game/features/` first, then `plan -Title "..." -Summary "..." -Steps "title\|lane\|tier",... -Spec docs/game/features/<name>.md -From C-…`. The summary says what they'll get, what's left out, and any choice you made that they might not expect; nothing is built until they approve. Anything smaller is just its task.

A note that came as a card (`[plan]`, from before messages) is taken on the same way, with the note as the card: `set T-034 -Title "..." -Status working -Step "..."` as you start it; a question, `reply T-034 -Answer -Text "..."`, and an errand, `reply T-034 -Done -Text "..."`, close it with no card kept; a feature, `plan ...`, then `set T-034 -Status removed`.

**Through a round:**
- **Spawning:** `work T-012 -Branch agent/<slug>`, then `set T-012 -Status working -Step "Starting"`, and give the worker its id and its checkout. Workers add their own steps, progress and questions.
- **Work you do yourself:** `set -Status working -Step "..."` as you start, and `log` what matters.
- **Merged and checked:** `set T-012 -Status ready -Where main -Summary "what changed" -Test "Drive a lap","Drift the hairpin"`. The summary is a sentence or two on what changed, and the test the few steps to try in the Main place, 30 words each: the card's hover shows them whole. The detail goes in `log`, and a choice for the user is a question ("Talking to the user"), not a line in the summary. A feature the user should try before it merges stays on its branch: `-Where lane`. Rocco holds a lane for them to test it in (the one its worker last tested in, else a free one) and the card says which; with none free, the card offers to load it into one. Approving it asks you to merge it (`[merge]`), and it stays done through the merge.
- **Nothing for the user to try yet** (groundwork a later step makes visible, a record of their pick, agents' own tools): add `-NothingToTest` to `set -Status ready`, with `-Test` saying why. The card approves itself, as their Approve would, and a step waiting on it can start. When it can be tried, even with some setting up (two players), it's a test: say what to try. `set` refuses a test that starts "Nothing to..." without it.
- **The user's questions while a task runs** (`ask` from a worker, or from you) turn its card Stuck until they answer. Options are a few words each, with what each means in the question (WORKER.md): the card shows two lines of an option at most.
- **Things you notice outside the task:** `suggest -Title "..." -Summary "why"`. The user queues or dismisses them.

The user approves a task, never you: don't set one `done`. Only two kinds of card skip the user's OK, approving themselves as they turn ready: a setup card (SETUP.md), since it only fills in docs from their own answers, and one with nothing for them to try (`-NothingToTest`, above). A plan always waits for them.

## Talking to the user

The user follows you in Rocco, above their note box, not in your window: what you're doing, your messages, and your questions. They don't watch your terminal, so never wait there for an answer.

- **If Rocco opened you with its hooks** (your first prompt says Rocco shows them what you do), talk to them as usual: Rocco picks up your steps, your messages and your questions (AskUserQuestion) by itself, and they answer permission prompts there too.
- **Otherwise**, say it through Rocco: `doing "Merging the trade window"` as you start each step, `say -Text "..."` for your report and anything else you'd tell them, and `ask -Question "..." -Options "A","B"` (no task) to ask them something. Options are a few words each, as on a Stuck card.
- **Either way, what they send you** comes back through `wait` ("What waits on you"): an answer to your question, or a message.

## Watching the board

Between jobs, the conductor watches the Workboard, so what the user sends is picked up without them having to prompt you. `rocco.ps1 wait` returns as soon as something waits on you, listed as `list -Pending` lists it. Run it after every report, and handle what it returns as "What waits on you" says. Then run it again: **every time it returns, start it again** once you've handled what it listed. A wait that returned with work isn't watching any more, and that's the one most easily forgotten.

- **How it runs depends on your agent.** Claude Code runs it as a background command (`run_in_background`), with no `-Timeout`, and is woken when it returns: a timeout only wakes you for nothing. An agent without background commands runs it with `-Timeout 540`, and runs it again when it says nothing's new.
- **Rocco checks it** for a Claude Code conductor it opened: at the end of each turn, a hook sends you back if something still waits on you, or if no `wait` is running.
- **Rocco shows it:** the status line above the note box says the conductor is listening while `wait` runs, and working (on its latest step) while your agent runs anything else.
- **No conductor running** when the user hands something over (a note, an answer, an approved plan): Rocco opens your agent in its own window, minimized in the taskbar, as the conductor, on what's waiting. So keep one conductor per game: the session Rocco opened, or the one the user started.

## Claims

`docs/CLAIMS.md` lists every task in progress and the files it owns, so parallel sessions and workers never edit the same file.

- One row per task: its branch, and the files it owns (folders as `folder/*`, new files marked "(new)").
- Claim before spawning, and push the claim; remove it after merging, and push again.
- **Append-only registries** (a list that tasks only add to, like a sounds registry) can be shared by anchor: claim "new block after `X` only". Nobody else edits that file's existing lines.

## Refresh

When the user says **"refresh"**, sync with GitHub both ways and leave every place on the latest build.

1. **Check for local changes first; never throw anything away.** `git status` in `repo\` and every checkout in `work\`. Commit what you understand (docs, claims, finished work). Show the user anything unexplained or half-done, like a stopped worker's edits in its checkout, and ask before committing it.
2. **Merge.** `git pull` (merge, not rebase) in `repo\`. Finished `agent/*` branches whose workers have reported are merged, checked in a lane and pushed ("Checking before main").
3. **Push** what `repo\` has of its own (docs, claims). If the push is rejected, pull and push again.
4. **Lanes need nothing:** each holds what it was last lent for, and the next loan moves it. A checkout in `work\` whose task is merged or deleted, with nothing uncommitted, can go: `git worktree remove ..\work\<name>`.
5. **Check the calendar.** An update in `live/CALENDAR.md` that's due its game page event and still says `Not yet` gets one queued (RELEASING.md "Game page events"). Rocco does this by itself while it runs.
6. **Report**, short: what went up and what came down, then any checkout, lane or place that needs attention.

## Main

- **Code reaches `main` checked in a lane** ("Checking before main"), so the user's Main place only ever gets a build that plays. Only docs, claims and update notes are committed in `repo\`.
- `git pull` (merge, not rebase) in `repo\` before committing there and right before pushing. Never force-push or rewrite `main`.
- **Shared contracts move first.** A change to `CONTRACTS.md`, `EVENT-CATALOG.md` or `src/ReplicatedStorage/Shared` that other tasks build on is its own small commit, pushed straight away (code through a lane, like any other).
- `main` must always play (WORKFLOW.md): a branch that breaks the build doesn't merge until it's fixed.

