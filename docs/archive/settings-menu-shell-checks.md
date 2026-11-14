# Settings shell lane checks — T-208

2026-11-14. Feature T-201, branch `feature/glass-settings`, DR-Lane1 only.

## Scope and result

The selected A / Smoked glass shell is working with the user's first batch, Steering and UI. The view uses native panes/text/controls and a client-only whole-scene blur. The P row is an accurate keyboard-shortcut explanation rather than a touch toggle that would hide its own route back. The lane build awaits the user's visual approval. Physical gamepad delivery remains unverified.

## Source and runtime

All 18 changed/new Luau modules matched disk and compiled in Studio before the final quiet runtime check, including the unchanged template LayoutDrag copy. Initial startup testing found the new UI folder arriving after a dependent module; explicit WaitForChild dependencies fixed that failure. The initial failed check is on the card.

Quiet playtests were stopped. Final console had no gameplay/script load errors from this change; Studio plugin connection notices were present. Studio was returned to Edit with device simulation stopped (`default`) and lane port 34871. Main was not inspected or changed.

## Layout measurements

Actual-resolution simulation; no page UIScale. Four fixtures per size: steering, interface, long copy, and 1.5× text with fully opaque panes.

| Camera viewport | Arrangement |
|---|---|
| 1280×720, 1920×1080 | Wide left rail |
| 1024×768 | Wide/tablet left rail |
| 667×375 | Short landscape, two control columns |
| 750×390 | Notched phone landscape; full GUI 844×390 |
| 390×763 | Notched portrait; full GUI 390×844 |
| 640×360 | Small landscape, two control columns; scrolling |
| 360×640 | One scrolling portrait column |
| 2560×1080 | Centred, width-limited wide pane |

The view reports no TextFits failures or controls below 48×48 in the six preset-device sweeps. The standard MeasureUI utility additionally passes all four fixtures at 640×360, 360×640 and 2560×1080: text, targets, safe area and layering checks pass; minimum essential text is 16 px, or 24 px in the largest fixture. Thumb zones were excluded from the modal's checks because the game's touch controls are disabled by the input owner while it is effective. Long content scrolls under a fixed Back/X; no text scaling or truncation is used.

The pane uses GuiService.GetInsetArea relative to the full-screen GUI origin, including horizontal and bottom safe bounds. Gamepad-preferred layouts add a 5% TV inset; physical gamepad preference switching was not verified.

## Input and lifecycle

- Actual M opens the page. Actual Backspace closes it and restores the driving input context and pointer pad.
- Actual mouse selection changes Dynamic to Centred through the runtime API. A right-button drag and wheel over the menu leave camera pan at zero and zoom target at 1.
- Actual D, Space, F4, F6, G, F8 and F while the page is effective produce no steering, brake flip, trajectory toggle, garage request, tuner open or car exit. The brake latch is preserved.
- Pointer sensitivity 1 and 10 produce 768 and 320 px travel at width 1280. Unknown mode, out-of-range and NaN requests all return false without partial mutation.
- Same-handler navigation selects the slider and nudges sensitivity 5 → 6. Layout drag handles/export/reset were exercised in Studio and switched off.
- Ten open/close cycles leave one Settings GUI, one disabled SettingsFog, two settings input contexts, no suppressed HUD roots and no menu input block after close. The separate P binding remains one.
- With the page open, 21 other game visual roots are suppressed. Actual P suspends the modal and blur and releases its driving block; another P restores the same open page. Final close restores zero suppressed roots.
- During an actual held slider press, P cancels the drag. Pointer movement while hidden leaves sensitivity unchanged (6 → 6).
- A focused temporary TextBox keeps M from closing the page. The temporary fixture is destroyed afterwards.
- Actual Escape opens the Roblox menu: settings stays logically open but is ineffective, with blur off and no slider drag. Closing Roblox's menu restores settings. Closing settings then leaves no block.
- Opening Cmdr closes settings and retains a separate console block; hiding Cmdr releases it. A real CarService respawn closes settings, leaves blur off, and restores zero suppressed roots.
- Resize and rotation were exercised across the device sweep. Larger text and reduced-transparency states use fixtures; user preference subscriptions are present. There are no decorative tweens.

## Contrast and material

Worst-case math composites the native layers over a white 3D scene at maximum preferred transparency. An initial 0.36 pane transparency failed secondary-text contrast; the final 0.26 pane and opaque control rims correct it. Ratios on the final tokens:

| Pair | Ratio |
|---|---:|
| Secondary text / worst pane | 4.92:1 |
| Primary text / worst tile | 10.63:1 |
| Button rim / solid control | 4.03:1 |
| Slider track / worst tile | 3.18:1 |
| Knob / track | 3.34:1 |
| Dark selected text / orange fill | 8.08:1 |

Black/night scenes improve these text contrasts. Lower preferred transparency makes the backing more opaque; zero also disables blur. Blur affects the whole 3D scene, not the GUI behind one pane.

Three Studio screenshots were used: desktop, one desktop retake after HUD suppression, and portrait. The two attached layout previews precede the final small contrast adjustment; the live pane is slightly more opaque and its control rims are brighter. They are layout previews, not proof of the final pixel values. The final contrast values above were source-gated and exercised in the final runtime smoke.

## Limits and next gate

Studio's gamepad key-injection calls returned success without delivering R3/B navigation or changing PreferredInput. Xbox emulation did supply a virtual pad; the failure was event delivery. The same navigation handlers were exercised through DebugNavigate, but actual gamepad activation/focus/held-B release still need a hands-on check. Phone layouts and the shared pointer path were tested in Studio; no physical touch device was attached.

The user should stop the car in lane 1, press M or Settings, try steering mode/sensitivity, use Interface, close/back, and P hide/restore. Their shell feedback comes before the final migration wrap-up. No code has been offered for merging or publishing.

