# Releasing

How an update gets from `main` to players. **Publishing is the user's job, never the agent's.** The agent gets every release ready: the checks, update notes when the user wants them, and the record afterwards.

When the user says they're **about to publish**, do "Before a publish" first. When they ask for **update notes**, write them (below).

## Before a publish

1. **Sync.** Refresh (CONDUCTOR.md "Refresh"), so `main` has every finished branch meant for this release and is pushed. The release is `origin/main` at that commit.
2. **Check the build** in the Main place, since it's what the user publishes. They asked for this check, so Main is yours for it, once they're not in a playtest (`get_studio_state`, TESTING.md):
   - A playtest joins with no console errors or warnings, and the update's headline features work.
   - Automated tests pass for anything touching saving, purchases or odds since the last release (TESTING.md).
   - A data schema change has its migration, tested on saved data from the previous version (CODING.md "Saving").
   - New products and passes exist on the dashboard, their ids are in code, and they're recorded in `live/EXPERIENCE.md`.
   - New assets load in the published experience (ART-PIPELINE.md "Ownership and permissions").
   - New analytics events are in `EVENT-CATALOG.md` and fire.
   - New config keys exist on the dashboard, staged values are tested, and the code has defaults for them (CONFIGS.md), and their live values are recorded in `live/EXPERIENCE.md`.
   - Changed screens are checked in every supported layout (UI.md).
3. **Update notes, only if the user wants them.** If the game has an update log (`PROJECT.md`), ask whether this update gets notes. If yes, write them (below), show them to the user, apply their edits, and commit `Update notes: <title>`. If the game has no update log, skip this step.
4. **Push `main`** and tell the user it's ready to publish, with anything they need to do on the dashboard: new products, game page text (`live/GAME-PAGE.md`), game page events (`live/CALENDAR.md`).

## After a publish

When the user says it's live:

- **Record it** in `live/RELEASES.md`: date, the commit it covers, the notes title if it had notes, and anything notable.
- **Tag it:** `git tag release/<YYYY-MM-DD>` on that commit (a second publish the same day adds `-b`), and push the tag.
- **Ask the user to try it** in a live server: the headline features, a purchase if purchases changed.
- **Post-release check** (POST-RELEASE.md): the build landed and new servers run it, its analytics events are coming through, errors look normal, and no debug code, stale branches or claims are left behind. Right after the publish, and again after the first hour. Anything that loses data, money or access is an incident (`live/INCIDENTS.md`). Rolling back to the previous version on the dashboard is the user's call.

## Update notes

Both are the user's call:
- **Whether the game has an update log at all.** Recorded in `PROJECT.md` ("Update log"). An in-game update log is a data module of entries, newest first, a page that shows them, and an unread marker that tells a returning player there's news. Its module is named in `ARCHITECTURE.md`.
- **Whether a given update gets notes.** Even with an update log, ask for each update; never add notes the user didn't ask for.

**1. Range.** `git pull` `main`, then read everything since the last notes:
`git log --no-merges --format='%h %ad %s' --date=short <newest entry's through>..origin/main`.
On a big update, also read the merge commits' subjects and what changed in `docs/game/`. Open a commit only when its subject doesn't say what a player would see.

**2. Pick** only what players should know:
- **In order:** new content first (features, places, items, events), then changes they'll notice, then fixes to things they care about (saves, the core actions, purchases, anything that blocked them).
- **Leave out** docs, tests, refactors, debug tools, tuning nobody notices, and fixes to bugs that never went live.
- **Group related commits into one bullet.** Even a 300-commit update ends up with about 5 to 12 bullets.

**3. Write** a new entry at the top of the entries:
- **`title`:** short and fun. **`headline`:** one or two sentences, the biggest news first.
- **Sections in order:** ✨ New, 🛠️ Changes, 🐛 Fixes. Leave out an empty one.
- **Bullets:** each starts with one emoji and is a sentence or two in players' words. No file names, code terms or internal names.
- **Pictures** tease new content: at most one per bullet, plus a `hero` for the headline. Only images the user picked, as with all art.
- **`id` and `date`:** the day it drops (`"YYYY-MM-DD"`; a second drop the same day is `"YYYY-MM-DD-b"`). **`through`:** the last `main` commit the notes cover.
- **Never rewrite a published entry**, apart from typos.

**4. Check** in the Main place: the unread marker shows, the page reads well in every supported layout, every picture renders, and reading the notes clears the marker.

**5. Show the user** the title, headline and bullets in chat, and apply their edits.

## Timed releases

Content can ship closed and open itself at a set time, so it goes out in an earlier publish and opens without one.

- **A releases module** maps each release id to a UTC time, with `isOpen(id)` and a countdown, using server time on both server and client.
- **Anything locked checks `isOpen` itself:** the server action that must refuse, the quests or shops that depend on it, and a "Coming soon" sign with the countdown where players would reach it.
- **Running servers open it on time.** When it opens, the signs come down and everyone gets an announcement.
- **Studio** can move a release's time through the debug bridge, to test the opening.
- **Adding a release:** an id and time, the gates, the sign, the announcement, and its card in `live/CALENDAR.md`, with its game page event if it gets one (below).

## Game page

The game page is what players see before they join: the description, icon, thumbnails, and events (Creator Hub, Events & updates) announcing what's coming. Rocco shows it: **Updates** has the calendar and the events, **Thumbnails** has the thumbnails and how each one does.

- **The agent drafts, the user publishes.** The agent writes the text and makes the images through ART-PIPELINE.md (approved files in `assets/marketing/`). Nothing goes public without the user: an event goes up as a private draft, and the user publishes it (one click in Rocco's Updates, or the Creator Hub).
- **Sizes:** the icon is 512 × 512. Thumbnails are 16:9 at 1920 × 1080, up to 10, plus up to 3 video thumbnails a month. Event cards are 16:9 too; Roblox's docs give no size, so make them 1024 × 576.
- **Other languages:** the name and description are translated automatically where a language's entry is blank, and each language can have its own icon and thumbnails (UI.md "Localization").
- **Record what's live,** word for word: events and their ids in `live/CALENDAR.md`, the description, icon and thumbnails in `live/GAME-PAGE.md`.

### Roblox Open Cloud

With the user's Open Cloud API key (`ROBLOX_API_KEY` on the PC, linked in Rocco's Connections), the agent works on the game page directly. Send it as the `x-api-key` header to `https://apis.roblox.com`; the universe id is in PROJECT.md. Without the key, or when a call is refused, hand that step to the user with exactly what to enter, or do it in the browser if they ask.

These APIs are experimental or beta at Roblox, so they change. When a call is refused, read the error, adjust, and say what changed in the report; and fix this table in the template (AGENTS.md "Template-owned files").

| What | Call | The key needs |
|---|---|---|
| Events, drafts included | `GET /virtual-events/v3/universes/{universeId}/game-events` | Events: read |
| A new event | `POST /virtual-events/v3/universes/{universeId}/game-events`: `title`, `subtitle`, `description`, `startTime` and `endTime` (UTC), `visibility: "private"`, `categories` (`[{ category, rank }]`, from `newContent`, `contentUpdate`, `newFeature`, `itemDrop`, `newSeason`, `festival`, `challenge`, `activity` and others), and `thumbnails` (`[{ mediaId, rank }]`, image asset ids) | Events: write |
| A change to one | `PATCH /virtual-events/v3/game-events/{eventId}`, with only the fields that change | Events: write |
| An image | The Assets API (`/assets/v1/assets`), as an image asset; its asset id is the event's `mediaId` | Assets: write |
| Game page thumbnails | `POST /legacy-game-internationalization/v1/game-thumbnails/games/{universeId}/language-codes/en/image` (multipart field `Files`), then `.../images/order` | Legacy universe: manage |
| How thumbnails do | `POST /analytics-query-api/v1/universes/{universeId}/metrics`: `metric` (`ThumbnailImpressions`, `ThumbnailQualifiedPlays`, `ThumbnailQualifiedPTR`), `granularity` `OneDay`, `startTime`, `endTime`, `breakdown: ["ThumbnailAsset"]`. A big query comes back pending: ask its `path` until `done` | Analytics: read |

### Game page events

The update cards in `live/CALENDAR.md` are the plan, and each gets an event on the game page unless its card says `None`. Rocco queues the event as a Workboard task a set number of days before the update (the "Auto-queue" line at the top of CALENDAR.md, 14 by default), or when the user clicks to. When Rocco isn't running, the conductor checks the calendar on "refresh" and queues what's due itself.

**A card's form.** Rocco reads and writes the cards, so every card keeps this form, soonest first under "Upcoming":

- A marker line `<!-- update: <id> -->`, with a short id like `pet-evolution`, then the update's name as a `###` heading.
- **When:** the day, `YYYY-MM-DD`, and its time in UTC when it has one: `2026-11-14 17:00 UTC`.
- **Kind:** Update, Live event or Timed release.
- **Game page event:** Not yet, Queued (T-012), Drafted, Scheduled, Live, Over, or None when it shouldn't get one.
- **Event id:** once the event exists on Roblox. **Card image:** the card the user picked. **Release:** for timed content, its release id and the publish that carries it.
- Then the user's notes, in their words: what's in it, and anything the event should say.

For a queued event:

1. **Write the text** from the card, in the user's words where they gave them: a short title (the hook), a subtitle, a description (what's new, and when), and its categories. A card with only a day and no time: ask the user for the time on the task.
2. **Make the card image**, 1024 × 576, through ART-PIPELINE.md: 2 to 4 candidates in `..\art\generated\events\<card id>\`. Rocco shows them on the card, and the user picks one there; the pick lands on the card as `Card image`, and on the task as a follow-up.
3. **Approve and upload** the picked image (ART-PIPELINE.md steps 4 and 5): into `assets/marketing/`, uploaded as an image asset, its id in the manifest.
4. **Put the event up as a draft:** private, starting when the update opens in game and ending when its event should (a week later unless the card says otherwise). On the card: `Game page event: Drafted` and `Event id: <id>`. Without the key, put the text under "Game page event text", set `Drafted`, and the user makes it on the Creator Hub.
5. **Hand it over:** the task goes to To test, saying the draft is ready to publish in Updates. Rocco marks the card `Scheduled` when the user publishes it. Record the published text, word for word, under "Game page event text".

### Thumbnails

Rocco's Thumbnails view shows the game page's thumbnails, how each one did over the last 7 days with the key (impressions, qualified plays, and qualified play-through: the share of impressions that became a real play), directions to try, and concepts made from them.

- **Directions** are the agent's, in `live/GAME-PAGE.md` "Thumbnail directions". Rocco reads them, so each keeps this form: a marker line `<!-- direction: <id> -->` with a short id like `rare-pet`, the direction's name as a `###` heading, then **Why:** (why it should work for this game, from the numbers or the docs) and **Prompt:** (the exact image prompt, on one line). When the user asks for them (a Workboard task, with the numbers in its note): read the numbers, PITCH.md, ART-DIRECTION.md and what's on the page now, then write 3 to 5. Each says why it should work, tied to the numbers or the game, and its exact image prompt: what's in the shot, the style from ART-DIRECTION.md, no text, and a wide 16:9 composition with the subject centred. Replace directions that were tried and lost.
- **Concepts** are made from a direction in Rocco, in one click, with the image tool (MODELS.md): candidates in `..\art\generated\thumbnails\<direction>\`, each with its prompt and hash in a `.json` beside it.
- **The user picks one** in Rocco ("Use this one"), which queues a task: approve it into `assets/marketing/` (ART-PIPELINE.md step 4; the manifest takes the prompt and hash from its `.json`), fit it to 1920 × 1080, put it on the game page (with the key, or hand it to the user), and record it in `live/GAME-PAGE.md` "Icon and thumbnails". Fitting is the one change allowed on the way in: scale and crop to 16:9 without cutting into the subject, and note it in the manifest.
- **Give a new thumbnail a week** of impressions before judging it.
