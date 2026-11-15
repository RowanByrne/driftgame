# Studio crashes after lane source updates

2026-11-15, WKEYSTUDIOS1680. T-203/T-212 validation remains unfinished.
All times below are EST (UTC-05:00). No Main playtest, desktop control, window
reopening or crash-dump upload was used for this investigation.

## Confirmed local evidence

Three matching crashpad reports identify the lane place, Studio build
`0.747.0.7471481`, exception `0xC0000005` with a null read (parameters `0, 0`),
and fault `RobloxStudioBeta.exe+0x5DAC31C`.

| Lane | Crash header time | Last completed Play teardown | Faulting thread |
|---|---|---|---|
| 2 |04:30:59 |04:22:45.597 |RBX Worker F |
| 3 |05:46:19 |05:44:11.585 |RBX Worker F |
| 1 |06:14:59 |06:01:57.945 |RBX Worker G |

No later Play appears before any crash. No explicit out-of-memory evidence or
ordinary clean-close sequence was found. The dumps establish native crashes;
the available metadata does not identify a renderer, GC, Lync or source-gate
function. An inventory entry can be stale: Lane1 was still listed after its
recorded crash time, then the attempted source gate reported it disconnected.

Dump files are under `%LOCALAPPDATA%\Roblox\logs\crashes\reports\`, with matching
Studio logs under its `attachments` directory:

- Lane2: `bf4d9d4e-7750-4bcb-a103-96949ab14740.dmp`, written04:31:01.255.
- Lane3: `62ab3e8c-1e44-408b-8d57-0a358c68590a.dmp`, written05:46:21.331.
- Lane1: `f2903bdf-e2a6-4c61-8e7e-aeb909d282ae.dmp`, written06:15:01.597.

## Source-update correlation

Git reflogs give Lane3's `ce4610e` to `2e5f507` checkout at05:46:18, and Lane1's
`00fcf1e` to `228f063` checkout at06:14:58. Both crashes occurred in the next
recorded second. Lync log filesystem writes align with those updates. Its log
entries have no timestamps or Studio delivery acknowledgments, so this does not
prove exact synchronization order or cause. Lane2 had no nearby checkout; its
source watcher continued logging edits after Studio crashed.

Lane1 remained connected in Edit for more than ten minutes after stopping the
`00fcf1e` tests, with no new dump, before the later checkout/crash. That bounded
observation did not establish lasting stability. The consumer-before-EditableMesh
hardening in `3e677f8` was present in `00fcf1e`; it did not prevent this recurrence.

The optional T-214/T-217 baked-shadow trial flag was absent in these terrain
checks. Its separately confirmed stop-during-native-await defect and T-217 fix
must not be presented as the cause or solution for these crashes.

## Validation boundary

`228f063` was not source-gated or played in Lane1. Its new cache, generation and
runtime checks remain unrun. T-212 still needs enabled natural-generation proof
and live render, fallback, walking, progress and retirement checks; its existing
timing failures remain explicit. No terrain readiness approval follows from the
helper tests or the short idle observation.

An official-source search found no matching current bug or verified workaround.
Historical mesh-shutdown and StudioTestService issues do not establish a cause
for this build/signature. Preserve the reports and exact tested source identities
for further investigation. Main remains hands-off; do not reopen windows against
the user's desktop-control instruction.
