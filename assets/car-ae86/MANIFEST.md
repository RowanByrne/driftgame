# car-ae86

The car the drift prototype drives, in place of the block the code used to build. A
placeholder for the feel test only (`docs/game/features/drift-model.md`).

**Nothing in this folder is a file.** The car is geometry, not an image, and it lives as
text in `src/ReplicatedStorage/Shared/Cars/AE86.luau` (31 KB) so Lync syncs it into every
place and a published game gets it too. `assets/` is not in `default.project.json`'s tree,
so a model file here would reach nothing. This manifest is the record of where it came
from and what it carries.

## Where it came from

- **Supplied by the user,** 2026-11-03: they added a Toyota AE86 to the Main place from the
  Roblox Toolbox and asked, in full, *"added a toyota ae86 to the main studio. can u rig it
  to work with our game? ditch all the scripts attached to it"*.
- **Read out of `places\DR-Main.rbxl`** (read-only, Edit datamodel) by `T-020`, as
  `workspace["AE86 (First Stage)"]`. Place files are not in git, so the copy in the Main
  place is not the car the game has; this text is.
- The copy that landed in the repo was checked byte-for-byte against the string Studio
  emitted (djb2 `a33a1cfc` over 23 978 bytes of shell, `fbc0251b` over 3 764 of wheels).
- **Not matched to a Creator Store listing.** The seven "First Stage AE86" models on the
  store by `Drifto_AE86` / `Dorifto_AE86` are all 156 parts and use different body meshes;
  the user's is 160 parts on meshes uploaded later. So it is a newer build of the same
  family, and there is **no asset id to re-insert it from** -- which is the other reason it
  is written down rather than loaded.

## What was kept, and what was thrown away

| | Original | In the repo |
|---|---|---|
| BaseParts | 160 | 98 (every visible one) |
| Scripts (Script, LocalScript, ModuleScript) | 54 | 0 |
| Sounds | 27 | 0 |
| ParticleEmitters | 14 | 0 |
| SpotLights | 6 | 0 |
| VehicleSeat | 1 | 0 |
| BodyVelocity / BodyForce / BodyThrust | 1 / 4 / 3 | 0 |
| GUIs (ScreenGui, SurfaceGui and their contents) | 2 + 139 | 0 |
| ClickDetectors, handle adornments, value objects | 2 + 36 + 61 | 0 |
| Invisible chassis, axle, suspension and weight parts | 62 | 0 |

The original is an **A-Chassis** vehicle: it drives itself. Our car is kinematic and
Roblox physics never touches it (`docs/game/DECISIONS.md`, 2026-11-03), so all of that had
to go. `DriftTests` asserts a built car holds none of it
(`CarModel.physicsOffenders` and `CarModel.strayOffenders`).

## The asset ids it carries

**124 distinct Roblox asset ids**, every one a third party's upload: meshes, textures and
PBR map sets, in four groups by uploader era --

- `696829111`–`696842916`: the steering wheel
- `1021818616`–`1021995704`, `2254775296`, `2292430862`–`2292447031`, `2675785344`,
  `3044336267`, `3208425159`, `3545844190`–`3545852658`, `4400495007`–`4400495975`,
  `5158395387`–`5158490045`, `5211564152`–`5211564225`, `5594502442`–`5692273340`,
  `5988414653`, `6048777826`, `6215060282`: wheels, brakes, engine, plates, number plate
- `10786939809`–`10786950938`: the body, interior, bumpers, lights and their PBR maps
- `12156615709`–`12156658152`: number-plate furniture

They are read from the one place they are written down, `Shared/Cars/AE86.luau`, and
nowhere else. If any is moderated or taken down, `CarModel` warns and leaves that part out;
if enough go, the car falls back to the block.

## Platform risk -- READ BEFORE THIS SHIPS

`docs/workflow/PLATFORM-RISKS.md`, "Copyright and trademarks": *"No one else's names,
characters, music or logos"*, and *"Outside assets: only from the Creator Store, free.
Record each one."*

1. **It is a real manufacturer's car,** modelled closely enough to be recognisable, and the
   mesh names say so outright (`TOY_TRUENO_BODY_LODA`, `TOY_TRUENO_CHASSIS_LODA`). A
   vehicle's shape and its model name are a manufacturer's to license; games that ship real
   cars license them. Roblox moderates on report, and a takedown lands on the **owner's
   account**, not just the asset.
2. **The mesh names are in the game's own source,** so the manufacturer's model name is now
   a string a published place contains, not only an asset it references.
3. **It is a third party's upload**, so we are relying on a Toolbox uploader having had the
   right to upload it, which for a licensed car design they almost certainly did not. A
   DMCA against them breaks our car.
4. **No Initial D livery is present.** The model was searched for under that name and the
   screenshot the user worked from shows the Fujiwara Tofu Shop car, but the parts that came
   across are plain white (`Paint` meshes at RGB 248,248,248) and carry **no decal or
   texture of any livery** -- the 4 decals and 10 textures in the data are an engine choke
   marking and an engine-block texture. So the anime trade dress is **not** in the repo.
   That removes one of the two copyright problems; the car itself is the other, and it
   remains.

**Status: placeholder, not approved to publish.** It is here so the user can judge the
drift's feel on a real car instead of a box, which is the phase gate
(`docs/game/features/drift-model.md`). Before anything is published, either the user
accepts the risk and records it in `docs/game/DECISIONS.md` and
`live/EXPERIENCE.md` "Platform risks", or the car is replaced with an original model of our
own -- which is cheap to do, because swapping it is one more module in `Shared/Cars` and one
string in `CarModel.BODIES`.

## Our own model: references (2026-11-09)

A model of our own, built through ART-PIPELINE.md "3D assets", to replace the Toolbox car
above. The user asked for it in full: exterior, interior, engine bay and boot, with doors,
hood, hatch, pop-up lights and dashboard needles that move as the real ones do. The risk in
"Platform risk", point 1, still stands for a recognisable real car: the references carry no
badge, name or plate text, and the shape is the user's call.

**The user's photo:** `..\art\reference\car-ae86\user-photo-front-three-quarter.webp`,
attached in chat on 2026-11-09 (a `.png` copy beside it is what the image tool was given).

**Image tool:** Codex's built-in image generation, Codex app 26.1029.7803.0. Not compared
with OpenAI's newest image release this round.

Stage 1, the reference sheet. Each was made with the user's photo attached; the exact prompt
is the `.prompt.txt` beside each image in `..\art\generated\car-ae86\`.

| File | What varies | Size | SHA-256 | Status |
|---|---|---|---|---|
| `ref-sheet-01.png` | True-to-life studio render, closed, lights up | 2172 x 724 | `9216572470A452633F3BA99D3440DCE618344B958A437989A3E785D38637FD73` | candidate |
| `ref-sheet-02.png` | Faceted low poly, as ART-DIRECTION.md asks of cars | 2172 x 724 | `DD98DF6ED8EF3E7A68CBD1262141654D15B6D06A49AA0F41FF693F349F4C8B4A` | **approved**, copied unchanged to `assets/car-ae86/ref-sheet-02.png` |
| `ref-sheet-03.png` | Everything open: doors, hood, hatch, engine bay, boot, interior | 2172 x 724 | `D22835D4B0B2D603431CA0CDBC591527DB5CB8CDDD2C5CF4E005ECDCA0B4C503` | kept as a parts guide only, not a style |

`ref-sheet-01.png` is rejected. The user's pick, 2026-11-09: "I love the faceted low poly
style - that's what we will do the full refs with."

Stage 2, a reference for every view, in `..\art\generated\car-ae86\views\`. Closed views
were made with `ref-sheet-02.png` attached; open views with `ref-sheet-02.png` (the style)
and `ref-sheet-03.png` (the parts). The exact prompt is the `.prompt.txt` beside each image.
**The user approved the set on 2026-11-09** ("approved"): every row marked candidate below
is an approved reference for the build; the rejected rows stay rejected.

| File | View | Size | SHA-256 | Status |
|---|---|---|---|---|
| `01-front.png` | Front, lights up | 2172 x 724 | `DB8666F19E443B9513FF3B038ABE803E278210B9AAA808FE9CF93FD0B4409ED0` | candidate |
| `02-rear.png` | Rear | 2172 x 724 | `5AFF217C98D9AE12E737A4164CEF9C42977353CE92B42ED640A30B61D8790F36` | candidate |
| `03-left.png` | Left side, lights down | 2172 x 724 | `2DAACD510A81EDA8555E4ADEFB1082FD0D7D4657EE84660D76BC4946925455FD` | candidate |
| `04-right.png` | Right side, lights up | 2172 x 724 | `3AF959A1454BB77B1A47550E303BD39997DEF47326076EFF108FC186FA1877E2` | candidate |
| `05-top.png` | Top | 2172 x 724 | `270E0A567990BFA78BF68F357A950BBD20DAE4877970DAEBD5B8C28D2A394D12` | rejected: steering wheel on the left |
| `05-top-v2.png` | Top, right-hand drive | 2172 x 724 | `AB16E859A37CE24EE0BB238D0675B5E65ECC2E7F1373F8BD9641656B6249A3FD` | candidate |
| `06-underside.png` | Underside | 2172 x 724 | `9CD48A8584FE652E8AABB352AD7D6AC4239671310A47FBEA2EA9E5F8640B670C` | candidate |
| `07-lights-down.png` | Front three-quarter, lights down | 1774 x 887 | `04D74B2840FF48C6728F5C9547B055D6954878D094B75093D001DB888E5DC83B` | candidate |
| `08-door-open.png` | Driver's door open | 1774 x 887 | `AFE9387B48CB38CB64D5E1F59391B681A201DB3AC78160D1E57696FD64776D98` | candidate |
| `09-engine-bay.png` | Engine bay | 1199 x 1312 | `E75D8551DC45B8C814931D4B5F5FB3C07E52138ABD1A9899392A0F3A7E0C9328` | rejected: whole car, not top-down, steering wheel on the left |
| `09-engine-bay-v2.png` | Engine bay close-up from above | 1230 x 1278 | `422EEAFFBB81C245CCA47C283B783936172FFFE3C67FD160EF66D091F56C9B35` | candidate |
| `10-hood-open.png` | Hood open, its underside | 1536 x 1024 | `EDEDB62866E65AB7F2EDDC8DBE81BE8EFB4FA8F1B2A330488A58598C9476BD07` | candidate |
| `11-hatch-open.png` | Hatch open, boot | 1536 x 1024 | `D95529197651661EE589319A154A40202FA75EF945D766F6823CC875AA674B13` | candidate |
| `12-dashboard.png` | Dashboard from the cabin | 2172 x 724 | `E0589AEF11BFDB35D83449A50FDD0FB58034FB8DD81335F24107E2F61F2304D9` | candidate |
| `13-interior-top.png` | Cabin from above, roof off | 2172 x 724 | `BF455B391F7EDD4737784322C0D13DBC76C7E5F7C1FD12EA522F2227B996BA7E` | candidate |
| `14-instruments.png` | Instrument cluster | 2172 x 724 | `673CF0A3080983EDD8042469753859A80BCBADE65B905E8E018DD38BD3FEAA34` | candidate |
| `15-wheel.png` | Wheel | 2172 x 724 | `4E86468D62BC8837269C051EC7E0724D487840B69020AB696FD73A6766061106` | rejected: drew the whole car, the wheel tiny |
| `15-wheel-v2.png` | Wheel, front and cut section | 1774 x 887 | `049AC0F2F0693C2FFDF4021846E0A87E14175E58CC87D282AF97F1C9DA6DF9DA` | candidate |

Known differences between views, for the build to settle rather than copy: the spoke count
on the side views (six to eight; the wheel sheet's eight is the one to build), and the
instrument sheet shows four dials where the dashboard view shows a simpler cluster.
