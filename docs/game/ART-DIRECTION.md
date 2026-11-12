# Art direction

How this game looks. The world part is set in Production, before the first art round; the UI part in the UI phase's style step (docs/workflow/WORKFLOW.md). Every piece of art is checked against this doc (docs/workflow/ART-PIPELINE.md, UI.md). Replace each prompt with the answer.

## Pillars

- **Stylized low poly.**
- **Cars curved where a car is curved,** simple and angular only where the car is angular.
- **Drivable before pretty:** no surface the drift model can't hold.

## References

No references yet — the user's call: "not yet, for now we keep it simple". Added here when the first ones are approved; images come through ART-PIPELINE.md.

| Image | What we take |
|---|---|
| | |

## World

- **Style:** Stylized low poly throughout. Cars are stylized but not faceted: their large curved surfaces (body panels, bumpers, glass, lamp lenses) follow the real car's curves and are shaded smooth, with real creases kept hard, and only parts that are angular to begin with (a side skirt, a trim strip, a block) are simple and flat-sided. Where two parts of a car meet, each folds inward and they overlap a little; a gap is never left (DECISIONS.md, 2026-11-12; ART-PIPELINE.md "3D assets"). The environment can go much further: very low poly is fine for anything the car doesn't drive on.
- **Surfaces:** > Usually a mix: Roblox materials on some assets, generated textures (on UV-unwrapped models, with shared atlases) on others, sometimes both on one asset. Say when each fits, such as "terrain and buildings use materials; creatures and hero props get textures". Each asset's surfaces are decided when it's made (ART-PIPELINE.md "3D assets").
- **Shapes and proportions:** Faceted, flat-shaded forms with hard edges for the world; cars are the exception (Style, above). **The driving surfaces are the exception to "very low poly":** roads, ramps and berms need enough geometric resolution that an elevation change reads as a curve, not as a stack of flat segments — a segmented low-poly road would break the drift model. Everything off the racing line can be as coarse as it likes.
- **Lighting and mood:** > Time of day, atmosphere, how night looks.
- **Palette:** > The main colours of the world, and what bright accents are for.

**Open:** if development goes well the user intends to bring in an artist for the cars, so the car style should stay easy to hand over.

## Characters and creatures

> How characters, NPCs and creatures look, if the game has them: proportions, faces, how rarer or stronger ones stand out.

## UI

Set in the UI phase's style step (UI.md).

**Style references:** > The approved UI references, as mocks of this game's screens.

**Colour tokens.** Components use these names, never raw colours.

| Token | Value | Role |
|---|---|---|
| `Surface.Primary` | | Main panel surface |
| `Surface.Secondary` | | Secondary surface |
| `Text.Primary` | | Text on dark surfaces |
| `Text.OnLight` | | Text on light surfaces |
| `Action.Primary` | | Primary buttons, important selections |
| `Focus` | | Focus and selection outline |
| `Error` | | Errors (always with an icon or label too) |
| `Disabled` | | Disabled controls |

**Fonts.** Checked in Studio at the smallest size, numbers and punctuation included.

| Role | Font | Checked |
|---|---|---|
| Headings | | |
| Body and controls | | |
| Numbers | | |

**Input icons:** > The icon set used for every input prompt (keyboard, mouse, gamepad, touch): its name, licence, and where its atlas and manifest live in `assets/`.

**Rules of the look:**
> What the UI does and doesn't do. For example: how decorated the HUD is compared with full menus, where ornament goes, how restrained transitions are.

## Do and don't

| Do | Don't |
|---|---|
| Keep a car's curved panels smooth and its angular parts simple | Build a road whose elevation reads as flat segments |
| Fold a car's parts into each other at every seam, with a small overlap | Put flat planes on a car's curved surface, or leave a gap at a seam |
| Keep off-road geometry very cheap | Copy a real manufacturer's car, name or badge |
