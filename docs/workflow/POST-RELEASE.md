# Post-release check

After the user publishes, confirm the new build is really live and healthy, and tidy up after the release. Claude runs it when the user says the update is live (RELEASING.md "After a publish"). The automated tests already ran before the publish; this checks the live game and the repo, not the code. Where to find each view is in DASHBOARDS.md "After a publish".

**When:** right after the publish, for what's up to the minute, and again about an hour later, for what fills in after a delay.

## 1. The build landed

- **The new version exists:** the place's version history on the Creator Dashboard shows a new version at the time of the publish. Note its number: it's the "new version" for every check below.
- **New servers run it:**
  - **Performance**, broken down by Place Version, shows players on the new version (it needs 100+ daily players).
  - On a smaller game, check the `ServerStarted` events on the hour-later pass (ANALYTICS.md "Standard events"), or ask the user to join a fresh server and read the version wherever the game shows it.
- **Old servers:** servers started before the publish keep the old version until they close. Moving everyone to the new version from the dashboard is the user's call. Suggest it when the update fixes something that matters.

## 2. Events are coming through

On the hour-later pass, since custom events reach the dashboards after a delay:

- **The new build reports:** in Explore, `ServerStarted` broken down by field 1 shows the new version.
- **New events arrive:** every event this release added to `docs/game/EVENT-CATALOG.md` shows up, with sensible fields and the standard slice filled in.
- **Funnels still flow:** the onboarding and core-loop funnels show no step suddenly dropping to zero.

If something is missing after a reasonable delay, find out why before the next release.

## 3. Errors look normal

- **Error Report:** turn on **Show version** and set **New errors since** to the new version. Every new error gets a cause, and is either fixed in the next release or explained.
- **Overall level:** errors and warnings per hour, compared with before the publish. A spike is a problem even if every message is old.
- **Performance:** client crash rate and server health against the previous version.
- **Alerts:** none fired since the publish (`live/EXPERIENCE.md` "Alerts").

Anything that loses players' data, money or access is an incident: follow `live/INCIDENTS.md` straight away.

## 4. Nothing left behind in the build

- **No debug code outside Studio:** a search of `src/` for debug prints, temporary flags and test hooks finds nothing that runs on live servers. Debug bridges and test kits stay behind their Studio-only checks.
- **No test values:** no Roblox config left on a test value or with a staged change nobody meant to publish (CONFIGS.md), and no testing shortcut still switched on in code.

Anything found is fixed in the next release, not by editing the live game.

## 5. The repo is tidy

- **Branches:** merged `agent/*` branches are deleted, locally and on GitHub (`git branch -r --merged origin/main`).
- **Claims:** finished claims are gone from `docs/CLAIMS.md`.
- **Lanes:** every idle lane is on the new `main` ("refresh", CONDUCTOR.md).
- **Release record:** the row in `live/RELEASES.md` and the `release/<date>` tag are pushed.

## Report

A short report to the user, and a line in the release's "Notable" column in `live/RELEASES.md`:

- the new version, and whether new servers run it
- whether the new events arrived
- new errors since the version, and the overall error level
- anything left behind, and what was tidied
- what goes into the next release because of it
