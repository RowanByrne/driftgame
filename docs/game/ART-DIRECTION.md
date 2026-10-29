# Art direction

How this game looks. The world part is set in Production, before the first art round; the UI part in the UI phase's style step (docs/workflow/WORKFLOW.md). Every piece of art is checked against this doc (docs/workflow/ART-PIPELINE.md, UI.md). Replace each prompt with the answer.

## Pillars

> Three short phrases the look always follows, such as "cozy, readable, hand-painted".

## References

> The approved reference images, stored in `assets/reference/`, and what we take from each. References guide the style; never copy their pixels.

| Image | What we take |
|---|---|
| | |

## World

- **Style:** > Stylized or realistic, and how detailed.
- **Surfaces:** > Usually a mix: Roblox materials on some assets, generated textures (on UV-unwrapped models, with shared atlases) on others, sometimes both on one asset. Say when each fits, such as "terrain and buildings use materials; creatures and hero props get textures". Each asset's surfaces are decided when it's made (ART-PIPELINE.md "3D assets").
- **Shapes and proportions:** > Chunky or slender, rounded or sharp, and the scale of props next to a player.
- **Lighting and mood:** > Time of day, atmosphere, how night looks.
- **Palette:** > The main colours of the world, and what bright accents are for.

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
| | |
