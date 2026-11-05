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

1. **Brief.** What it's for, where it shows, its size and aspect at each screen size, transparent or not, and the style (`ART-DIRECTION.md`). UI art takes its sizes from the measured programmer art and its layers from the plan, both in `UI-INVENTORY.md` "Art slots" (UI.md "4. Assets").
2. **Generate candidates** with the image tool in `MODELS.md`. Today that's `powershell -ExecutionPolicy Bypass -File tools\imagegen.ps1 -Prompt "..." -Out ..\art\generated\<topic>\<name>-01.png [-Transparent] [-Reference a.png,b.png]`, which prints the size, alpha and SHA-256. Make 2 to 4 per brief, each from its own variation of the prompt (material, medium or composition): four copies of one prompt don't count. Log each in the topic's manifest: file, exact prompt, references used, hash, status `candidate`. Thumbnail concepts made in Rocco keep that record in a `.json` beside each image instead, until one is picked (RELEASING.md "Thumbnails").
   - **Check the image tool is current** before each round. Codex's image generation doesn't say which model it runs (a PNG's C2PA data says only `gpt-image`), so compare the Codex app's version with OpenAI's newest image release, and ask the user to update Codex if it's behind. Note both in the manifest.
   - **Measure every candidate** with `tools\ui\measure-png.ps1 <folder> -Aspect <slot aspect>`. The image tool ignores the aspect it's asked for, so drop any candidate outside the 20% limit (UI.md "4. Assets") before showing it.
3. **Show the user** the candidates side by side, in place on the real screen or model when possible. For UI art, `tools\ui\contact-sheet.ps1` draws each candidate into its slot at native size over a real screenshot of the game, then magnified; a whole screen's art is picked on one combined sheet (UI.md "1. Style"). The user picks. **Never upload art the user hasn't picked.** Record the pick, and the user's words, in the manifest.
4. **Approve.** Copy the picked file **unchanged** into `assets/<topic>/`: never re-save, recompress or crop it on the way. Its status becomes `approved`; the others become `rejected` and stay in `..\art\generated\`.
   - **A sheet of pieces** (related layers or icons generated together) is the master. Either upload it whole and show each piece by its rect, or cut it with `tools\ui\cut-sheet.ps1`, which copies pixels along the transparent gaps and changes nothing else. Keep the cuts beside the master and log each one, with the command that made it, in the manifest.
   - **Leave the empty canvas in.** Transparent margins aren't trimmed from the file; the game skips them with `ImageRectOffset` and `ImageRectSize` (step 5).
5. **Upload.** Uploading is the agent's job. Use the Studio MCP `upload_image`, which takes http URLs: serve the folder with `tools\ui\serve-assets.ps1 -Root assets\<topic> -Minutes 10` in the background, and request `/__stop` when done. Then measure what Roblox decoded, which isn't the file you uploaded: it scales an image down so its longest side is about 1024 px. `tools\ui\DecodeRects.luau`, run in the Edit datamodel, gives each id's decoded size and visible rect (alpha 8 or more, with a 1 px margin), per cell for an atlas. Every rect and aspect the game uses comes from the decoded image, never the source file. Record the asset id, decoded size and rect in the manifest.
6. **Wire it in.** Put the id in the game's asset registry module, one place in code (`ARCHITECTURE.md`), never scattered through scripts. A UI art entry lists its role's variants, each with its image, rect, aspect and any anchors (UI.md "Lay out from the art"). Check it renders in a fresh playtest, on screen: `IsLoaded` is true and `ContentProvider:GetAssetFetchStatus` returns `Success`. An image off screen can stay unloaded.
7. **Commit** the master, the manifest and the registry change together.

**Rules**
- **Record prompts exactly**, word for word.
- **Never invent an asset id** or report a placeholder as final art.
- **An unchanged master keeps its id.** New pixels mean a new upload and a manifest update. Give a new version a new file name (`-v2`) instead of overwriting one that older notes point to.
- **Reuse first.** Before generating, check the approved masters: one whose aspect passes the 20% limit wherever it's used is reused, with its existing id.
- **Never edit a pick's pixels.** Fix a flaw by generating again, or with an edit prompt and the pick attached ("Reproduce exactly the attached image, but remove the chevron").
- **Chat attachments and temporary files aren't a handoff.** Copy anything the user supplies into `..\art\` or `assets/` first, and record where it came from.
- **Original art only.** References guide the style; never copy or crop pixels from them.
- **If the image tool can't run on this PC, say so.** Don't substitute another source.

### Prompts

- **Lead with the medium,** and ban the generic look outright: "Avoid the polished game-item look: no shiny gold trims, no rows of rivets, no glossy 3D, no airbrushed gradients." Without that, directions drift to the same shiny style.
- **Prompt a layer as a layer.** Name it, and list what it must leave out: "ONLY the hollow ring: no fill, no icon, no glow". For a layer that's tinted in game, add "neutral grayscale only: white highlights, mid-grey body, no colour".
- **A set goes on one sheet** ("four items on one transparent canvas, one per quadrant, same hand and line weight"), then is cut apart (step 4). Separate prompts give separate hands.
- **A variant is a new drawing:** "a new portrait-shaped variant of the attached approved master, NOT a crop or stretch", with the master attached.
- **Match an existing set:** "by the same artist as the attached icons; match their medium, hand, line weight and palette exactly".
- **Draw items from the game's models.** Attach a sheet of the real models, name the one to draw, and spell out what must survive: counts, colours, shapes.
- **Art that text sits on** keeps its weathering at the edges: "all edge weathering within the outer 120 px; interior quiet".
- **If transparency keeps failing** (holes, a half-transparent centre), ask for an opaque version instead of fixing the alpha by hand.

### Icons drawn in code

Flat glyph icons are drawn, not generated. Each is an SVG on the same fixed grid, with one line weight and one silhouette style. `tools\ui\svg-icons-to-atlas.ps1` renders them white at 256 px, packs them into one atlas with each icon's rect, and makes a sheet of them at their real sizes (36 and 24 px) and magnified, which is what the user picks from. After the upload it writes the id and generates the Luau icon registry. The game tints them with `ImageColor3`.

## Roblox's limits

Checked 2026-11-02 ([meshes](https://create.roblox.com/docs/art/modeling/specifications), [textures](https://create.roblox.com/docs/art/modeling/texture-specifications), [4K textures](https://devforum.roblox.com/t/4k-texture-rendering/4316229), [uploads](https://create.roblox.com/docs/cloud/guides/usage-assets)). Models' memory of these is often out of date.

- **Meshes:** at most 20,000 triangles each, and at most 4 bone influences per vertex. Roblox publishes no bone limit for a skinned mesh; avatar bodies use 15 bones, plus up to 37 optional ones.
- **Textures:** up to 4096 × 4096 renders in game since 30 January 2026 (meshes, SurfaceAppearance, textures, decals, material variants); imports up to 8K are scaled down to 4K. Studio shows 4K only with Texture Streaming on. Budget about 256 × 256 per 2 × 2 × 2 studs of object, up to 1024 × 1024 for most props, and keep 4K for what fills the screen.
- **SurfaceAppearance:** a color map, a normal map (OpenGL tangent space only), roughness and metalness maps, and an emissive mask with `EmissiveStrength` and `EmissiveTint`.
- **Uploads:** images under 8000 × 8000 through Open Cloud; videos at most 20 a day. Roblox publishes no monthly count for images or meshes.
- **The game page:** sizes are in RELEASING.md "Game page".

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
