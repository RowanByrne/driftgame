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
