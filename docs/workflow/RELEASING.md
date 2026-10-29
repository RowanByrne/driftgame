# Releasing

How an update gets from `main` to players. **Publishing is the user's job, never Claude's.** Claude gets every release ready: the checks, update notes when the user wants them, and the record afterwards.

When the user says they're **about to publish**, do "Before a publish" first. When they ask for **update notes**, write them (below).

## Before a publish

1. **Sync.** Refresh (CONDUCTOR.md "Refresh"), so `main` has every finished branch meant for this release and is pushed. The release is `origin/main` at that commit.
2. **Check the build** in the Main place:
   - A playtest joins with no console errors or warnings, and the update's headline features work.
   - Automated tests pass for anything touching saving, purchases or odds since the last release (TESTING.md).
   - A data schema change has its migration, tested on saved data from the previous version (CODING.md "Saving").
   - New products and passes exist on the dashboard, their ids are in code, and they're recorded in `live/EXPERIENCE.md`.
   - New assets load in the published experience (ART-PIPELINE.md "Ownership and permissions").
   - New analytics events are in `EVENT-CATALOG.md` and fire.
   - New config keys exist on the dashboard, staged values are tested, and the code has defaults for them (`live/CONFIGS.md`).
   - Changed screens are checked in every supported layout (UI.md).
3. **Update notes, only if the user wants them.** If the game has an update log (`PROJECT.md`), ask whether this update gets notes. If yes, write them (below), show them to the user, apply their edits, and commit `Update notes: <title>`. If the game has no update log, skip this step.
4. **Push `main`** and tell the user it's ready to publish, with anything they need to do on the dashboard: new products, game page text (`live/GAME-PAGE.md`), game page events (`live/CALENDAR.md`).

## After a publish

When the user says it's live:

- **Record it** in `live/RELEASES.md`: date, the commit it covers, the notes title if it had notes, and anything notable.
- **Tag it:** `git tag release/<YYYY-MM-DD>` on that commit (a second publish the same day adds `-b`), and push the tag.
- **Ask the user to try it** in a live server: the headline features, a purchase if purchases changed.
- **Post-release check** (POST-RELEASE.md, not written yet): the build landed and new servers run it, its analytics events are coming through, errors look normal, and no debug code, stale branches or claims are left behind. Right after the publish, and again after the first hour. Anything that loses data, money or access is an incident (`live/INCIDENTS.md`). Rolling back to the previous version on the dashboard is the user's call.

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
- **Adding a release:** an id and time, the gates, the sign, the announcement, and its row in `live/CALENDAR.md`, with its game page event if it gets one (below).

## Game page

The game page is what players see before they join: the description, icon, thumbnails, and events (Creator Dashboard, Events & updates) announcing what's coming.

- **Events tease releases.** A game page event for a timed release starts when the release opens in game; keep both times in the same `live/CALENDAR.md` row so they can't drift apart.
- **Claude drafts, the user publishes.** Claude drafts the text and makes the images through ART-PIPELINE.md (approved files in `assets/marketing/`). The user posts them on the dashboard, or asks Claude to do it in the browser.
- **Event cards are 1024 × 576:** Roblox stores event images at that size, so make them that size.
- **Record what's live,** word for word: events and their ids in `live/CALENDAR.md`, the description, icon and thumbnails in `live/GAME-PAGE.md`.
