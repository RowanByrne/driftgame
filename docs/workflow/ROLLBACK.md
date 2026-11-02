# Rollback

Backing out a change that broke something. How depends on what broke:

| What broke | How it's undone | Whose call |
|---|---|---|
| `main` (the code) | A revert commit ("Code on main" below) | The conductor, telling the user |
| The live game, after a publish | Restore the previous version from the place's version history on the Creator Dashboard | The user (`live/INCIDENTS.md`) |
| A live config value | Restore the old value from the Configs page's History, then publish it (CONFIGS.md) | The user, or the agent when asked |
| The map | Revert to its `map-v<N>` tag (WORLD-BUILDING.md) | The user decides; the conductor reverts |
| One player's saved data | Data store keys keep earlier versions for 30 days (`DataStore:ListVersionsAsync`, `GetVersionAsync`), so a save can be put back by hand | The user, case by case |

A bad change to how data is saved isn't rolled back: it's fixed forward with a migration (CODING.md "Saving"), because players have already saved in the new shape.

## Code on main

When `main` breaks (it doesn't play, or a merge brought in something wrong), back the change out with a new commit. Never reset or force-push `main`.

1. **Find what brought it in:** `git log --first-parent --oneline -15` lists main's own commits and merges, newest first.
2. **Revert it:** `git revert -m 1 <merge>` for a merged branch (`-m 1` keeps main's side), or `git revert <commit>` for a plain commit. Revert the newest first when there are several.
3. **Check** the Main place plays again (quiet playtest, console), then push `main` and refresh the idle lanes (CONDUCTOR.md "Refresh" step 4).
4. **Tell the user** what was backed out and why. The task goes back to Up next on the Workboard, with what broke in its note.
5. **Landing it again:** the branch's commits are already in main's history, so merging the branch again changes nothing. Start the fix from a new branch off `main`, revert the revert there (`git revert <the revert commit>`), fix it, and merge that branch as usual.

If the broken code already went out to players, the code revert fixes `main`, and the next publish carries the fix. Until then, the live game is the user's call: a config switch (CONFIGS.md) or restoring the previous version (above).
