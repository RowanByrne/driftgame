# Art pipeline

How art gets made, approved and into the game. The user picks; the agent generates, records, uploads and wires it in. The style to aim for is in `docs/game/ART-DIRECTION.md`; UI art has extra rules in `UI.md`.

## Where art lives

| What | Where | In git |
|---|---|---|
| Every generated candidate | `..\art\generated\<topic>\` | No |
| Working source files (.psd, .blend, .kra) | `..\art\source\<topic>\` | No |
| References and inspiration | `..\art\reference\` | No |
| Approved style references | `assets/reference/` | Yes |
| Approved masters, up to 5 MB a file (a commit check refuses bigger) | `assets/<topic>/` | Yes |
| The record: prompts, hashes, status, upload ids | `assets/<topic>/MANIFEST.md` | Yes |

A topic is named for its role, like `hud-currency`, `shop-buttons` or `boat-models`.

## Images

1. **Brief.** What it's for, where it shows, its size and aspect at each screen size, transparent or not, and the style (`ART-DIRECTION.md`).
2. **Generate candidates** with the image tool in `MODELS.md`. Today that's `powershell -ExecutionPolicy Bypass -File tools\imagegen.ps1 -Prompt "..." -Out ..\art\generated\<topic>\<name>-01.png [-Transparent] [-Reference a.png,b.png]`, which prints the size, alpha and SHA-256. Make 2 to 4 per brief. Log each in the topic's manifest: file, exact prompt, references used, hash, status `candidate`.
3. **Show the user** the candidates side by side, in place on the real screen or model when possible. The user picks. **Never upload art the user hasn't picked.** Record the pick, and the user's words, in the manifest.
4. **Approve.** Copy the picked file **unchanged** into `assets/<topic>/`: never re-save, recompress or crop it on the way. Its status becomes `approved`; the others become `rejected` and stay in `..\art\generated\`.
5. **Upload.** Uploading is the agent's job. Use the Studio MCP `upload_image` (it takes http URLs: serve the folder from a local http server), then load the image in Studio and check it shows and its decoded size matches. Record the asset id and decoded size in the manifest.
6. **Wire it in.** Put the id in the game's asset registry module, one place in code (`ARCHITECTURE.md`), never scattered through scripts. Check it renders in a playtest.
7. **Commit** the master, the manifest and the registry change together.

**Rules**
- **Record prompts exactly**, word for word.
- **Never invent an asset id** or report a placeholder as final art.
- **An unchanged master keeps its id.** New pixels mean a new upload and a manifest update. Give a new version a new file name (`-v2`) instead of overwriting one that older notes point to.
- **Chat attachments and temporary files aren't a handoff.** Copy anything the user supplies into `..\art\` or `assets/` first, and record where it came from.
- **Original art only.** References guide the style; never copy or crop pixels from them.
- **If the image tool can't run on this PC, say so.** Don't substitute another source.

## 3D assets

Assets are built in Blender through the Blender MCP, by the 3D job in `MODELS.md`. When the user asks for an asset built straight in Studio instead, follow the same stages with Studio in Blender's place: build through the Studio MCP, texture with Roblox materials or SurfaceAppearance, animate with Studio's tools. Skip any stage that doesn't apply.

The user approves at up to four gates: the reference, the gray model, the textured model and the animation. A stage starts only after the gate before it.

1. **Reference sheet.** Generate one image with the image tool showing the asset from two angles on one sheet.

   **Gate: the user approves the reference.**
2. **All-angle references, for complex assets only.** For something complex, like a creature, generate a reference for every view: front, back, left, right, top and bottom. Skip this for something simple, like a chopstick.
3. **Build** the shape in Blender. Rig it if it will be animated.

   **Gate: the user approves the gray model**, untextured, shown from the reference angles.
4. **Surfaces.** Decide for this asset: Roblox materials, generated textures, or a mix, following `ART-DIRECTION.md` "Surfaces", and ask the user when it isn't clear. Materials are assigned and go straight to the gate; textured parts go through the steps below.
   - **Unwrap:** decide whether the asset needs a full UV unwrap to match its references. A creature does; a simple prop may not.
   - **Generate the textures** with the image tool.
   - **Atlas:** use texture atlases wherever possible, and put several assets' texture maps on one shared atlas.
   - **Compare:** render the textured asset from the reference camera angles and set the renders beside the references. Fix what differs and go again. Stop after **3 passes** at most; if it still isn't right, note what differs and tell the user.

   **Gate: the user approves the textured asset.**
5. **Animate, if it needs animation.** Generate animation ideas with the image tool and lay them out as a storyboard. Animate in Blender to match it, comparing against the storyboard, for at most **3 passes**; note anything still off and tell the user.

   **Gate: the user approves the animated asset.**

### Into the game

- **Export and check.** One export per asset, re-imported fresh to prove it works. The packed `.blend` goes in `..\art\source\<topic>\`; exports within the size limit go in `assets/<topic>/`. Log every reference sheet, render and storyboard in the topic's manifest.
- **Import.** When the user can batch imports by hand faster, give them a folder with exactly the files to import; the agent then inspects and arranges the result through the Studio MCP. Hand-built content lives only in places (LANES.md "Hand-built content").
- **Verify in Studio**, not by upload id: from every side, at play distance, in the lighting it's seen in, with its animations playing in game.
- **Commit** the approved exports, manifests and current state.

## Creator Store assets

- **The `asset-scout` agent** looks up free Creator Store assets and returns their ids. It never inserts anything.
- **Audio** has its own pipeline: `AUDIO-PIPELINE.md`.
- **Record every outside asset** with its id, creator and why it was chosen. Sound ids go in the sounds registry (CODING.md).

## Ownership and permissions

- **Who can load an asset.** An asset loads in the published game only if it's owned by the experience's owner, is open to everyone, or its owner granted the experience access. Only the asset's owner can grant that.
- **Upload as the owner.** Upload under the owner in `PROJECT.md` ("Roblox") where the tool allows it. Otherwise record who uploaded each asset, so the grants can be made.
- **Check before launch** and after an ownership change (LAUNCH.md). Collect every asset id the game uses from a running server's content properties: `.rbxm` files are compressed, and grepping them returns broken ids. Then check the experience has permission for each one. Record the result in `live/EXPERIENCE.md`.
