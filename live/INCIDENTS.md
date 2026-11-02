# Incidents

Anything that loses players' data, money or access: saves lost or corrupted, purchases not granted or granted twice, players unable to join or play, an exploit handing out rewards. Smaller bugs go through normal work.

## While it's happening

1. **Tell the user straight away**, with what's known: what's broken, since when, how many players it hits.
2. **Stop the damage.** Switch the broken part off with a Roblox config (docs/workflow/CONFIGS.md), such as turning checkout off. Rolling back to the previous version (docs/workflow/ROLLBACK.md), or shutting servers down, is the user's call on the dashboard.
3. **Fix it** in a small, focused change, check it in the Main place, and release it (docs/workflow/RELEASING.md).
4. **Check the fix live** (docs/workflow/POST-RELEASE.md), and repair what players lost where the game can: restore items, grant missing purchases.

## Afterwards

Write a postmortem below. Keep it blameless: the aim is to change what let it happen, not to find fault.

| Date | What happened | Players affected | Status |
|---|---|---|---|
| | | | Open / fixed / closed |

### <Date>: <what happened>

- **Summary:** > One or two sentences.
- **Timeline:** > When it started, when it was noticed and how, when it was stopped, when it was fixed (UTC).
- **Impact:** > How many players, and what they lost (data, Robux, play time).
- **Cause:** > What went wrong, and why the checks before release didn't catch it.
- **What we did:** > The fix, and how players were made whole.
- **What we'll change:** > Tests, checks, alerts or rules that stop it happening again, each linked to where it was done (a doc, a commit, `docs/game/DECISIONS.md`).
