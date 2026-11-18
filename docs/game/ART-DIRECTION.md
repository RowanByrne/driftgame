# Art direction

How this game looks. The world part is set in Production, before the first art round; the UI part in the UI phase's style step (docs/workflow/WORKFLOW.md). Every piece of art is checked against this doc (docs/workflow/ART-PIPELINE.md, UI.md). Replace each prompt with the answer.

## Pillars

- **Stylized low poly.**
- **Cars curved where a car is curved,** simple and angular only where the car is angular.
- **Drivable before pretty:** no surface the drift model can't hold.

## References

**Environment mood (the user's concept art, 2026-11-15):** "this is the vibes I want to be able to create with this project." The target for the environment work that follows better road and terrain generation. Mood references only: the look to aim for in low poly, not pixels to copy (ART-PIPELINE.md), and the car in them is the reference car, not approved art.

| Image (`assets/reference/environment-mood/`) | What we take |
|---|---|
| `autumn-maple-cliffs.png` | Switchbacks cut into pale cliffs, red-orange maple canopy, river gorge below, snow peaks over a cloud sea; leaves kicked up by the drift |
| `waterfall-gorge-rain.png` | Road on a ledge over a tiered waterfall and white water, rock tunnel, moss and ferns, wet road with god rays |
| `sakura-shrine-dusk.png` | Purple-pink dusk, cherry blossom and tall cedars, stone retaining wall, torii and steps up the bank, rusty guardrail, switchbacks stacked down the valley |
| `moonlit-pampas-ridge.png` | Open grassy ridge at night, full moon, wind-blown pampas grass, windswept pines, valley fog, low road posts instead of rails |
| `rainy-forest-night.png` | Heavy rain in a dark cedar forest, one sodium streetlamp and a convex corner mirror, reflections on the wet road, creek below |
| `snow-pass-sunset.png` | High snowy pass at sunset, alpenglow peaks, cloud sea filling the valleys, golden larches, snow spray off the rear tyres |

Across all six: a guardrailed mountain road on the edge of a big drop, a far layered vista with fog or cloud between the ridges, one strong weather or time of day per scene, and something the drift throws up (smoke, leaves, petals, spray, snow).

## World

- **Setting:** Japan, starting with classic mountain roads (DECISIONS.md, 2026-11-12; `features/mountain-road.md`). References, palette and lighting for it come with the scenery feature.
- **Style:** Stylized low poly throughout. Cars are stylized but not faceted: their large curved surfaces (body panels, bumpers, glass, lamp lenses) follow the real car's curves and are shaded smooth, with real creases kept hard, and only parts that are angular to begin with (a side skirt, a trim strip, a block) are simple and flat-sided. Where two parts of a car meet, each folds inward and they overlap a little; a gap is never left (DECISIONS.md, 2026-11-12; ART-PIPELINE.md "3D assets"). The environment can go much further: very low poly is fine for anything the car doesn't drive on.
- **Surfaces:** > Usually a mix: Roblox materials on some assets, generated textures (on UV-unwrapped models, with shared atlases) on others, sometimes both on one asset. Say when each fits, such as "terrain and buildings use materials; creatures and hero props get textures". Each asset's surfaces are decided when it's made (ART-PIPELINE.md "3D assets").
- **Shapes and proportions:** Faceted, flat-shaded forms with hard edges for the world; cars are the exception (Style, above). **The driving surfaces are the exception to "very low poly":** roads, ramps and berms need enough geometric resolution that an elevation change reads as a curve, not as a stack of flat segments — a segmented low-poly road would break the drift model. Everything off the racing line can be as coarse as it likes.
- **Lighting and mood:** > Time of day, atmosphere, how night looks.
- **Palette:** > The main colours of the world, and what bright accents are for.

**Open:** if development goes well the user intends to bring in an artist for the cars, so the car style should stay easy to hand over.

## Characters and creatures

> How characters, NPCs and creatures look, if the game has them: proportions, faces, how rarer or stronger ones stand out.

## UI

**Endless-run score HUD (T-307, November 17, 2026).** The user picked Akina Race Tape, Split Feed. [The approved reference](../../assets/reference/akina-split-feed.png) shows the 4.49-second frame of the scoring study. The game draws native text and tape directly over its chase view. The run score sits to the left, the condensed italic rank fills with the segmented meter, and the small multiplier closes the row. A held event counts above the word. One-offs and loss notices sit below it. The event lettering uses dark edge ink for changing scenery, with the scene visible between its glyphs.

The demo used Barlow Condensed and IBM Plex Mono. The Studio component uses Roblox’s bundled Roboto Condensed Bold Italic for rank and held labels, Roboto Condensed Bold for standing captions and Roboto Mono SemiBold for numbers. The compact italic face was rendered and measured in the component showcase. All presentation colours and faces live in `UI/Theme.ScoreTape`. Warmup is silver, Gripped slate, Loose ice blue, Sideways cyan and Linked violet. The subsequent playable ranks introduce lilac, orchid, electric blue and pale mint. A short snap, edge echo and directional streaks build with rank. Reduced Motion keeps the charge and the settled result.

The approved naming sequence is Warmup, Gripped, Loose, Sideways, Linked, Committed, Smoked, Boosted, Locked In, Full Send, Overdrive, Flat Out, Redline, Ghost, Demon and Untougeable. The current gameplay ladder ends at Locked In ×9.

Set in the UI phase's style step (UI.md).

**Settings brief (2026-11-14; no style picked yet):** the user requested clean modern UI, glass panes, fogginess, semi-transparency and tiles, with Assetto Corsa EVO and Assetto Corsa Rally as style references. Draft three directions on the settings page first, then build the user's pick. This is a settings concept brief, not approved UI art or a restyle of every screen (`features/settings-menu.md`).

**Settings style reference (T-201, 2026-11-14):** A / Smoked glass, the left column of `assets/reference/settings-menu-concepts-01.png`. Dark charcoal glass, softly fogged gameplay, quiet off-white type, warm orange selections, rounded panes and tiles. Wide settings pages use a left category rail; compact pages reflow into category chips and stacked/scrolling content. This approves settings only; other menus keep their current look. Native Roblox surfaces and text reproduce the material; the real blur scope and opacity are checked in lane 1 before calling the page ready. B and C on the comparison sheet are unpicked.

**Colour tokens.** Components use these names, never raw colours.

| Token | Value | Role |
|---|---|---|
| `Surface.Primary` | `#14191d` (`Theme.Color.Surface`) | Main settings glass |
| `Surface.Secondary` | `#232a2f` (`Theme.Color.Tile`) | Inset tiles and controls |
| `Text.Primary` | `#f4f5f4` (`Theme.Color.Text`) | Text on dark surfaces |
| `Text.OnLight` | `#171b1e` (`Theme.Color.OnAccent`) | Text on orange selected controls |
| `Action.Primary` | `#f29e52` (`Theme.Color.Accent`) | Important selections and slider fill |
| `Focus` | White, 3 px native rim | Focus indicator, without a glow |
| `Error` | | Errors (always with an icon or label too) |
| `Disabled` | `#737c83` | Unavailable component state, with interaction disabled |

**Fonts.** Checked in Studio at the smallest size, numbers and punctuation included.

| Role | Font | Checked |
|---|---|---|
| Headings | Gotham Bold | Settings, lane 1, 2026-11-14 |
| Body and controls | Gotham Medium | Native 16 px secondary / 18 px body at smallest tested layouts; 2026-11-14 |
| Numbers | Gotham Medium / Bold | Sensitivity 1–10 and range punctuation checked; 2026-11-14 |

**Settings input hints:** native P keycap and labelled controls. No generated icon atlas or new outside art is used.

**Rules of the look:**
Settings uses native rounded surfaces, a fine rim and quiet interiors. Text and targets stay native. Scene fog is a client-only BlurEffect over the entire 3D scene; it is not localized pane refraction. Other game HUD is put away while the modal is active. No animations are needed for this first page; all transitions are instant and interruptible. Accent-filled selections use dark text for contrast. These tokens currently apply only to settings.

## Do and don't

| Do | Don't |
|---|---|
| Keep a car's curved panels smooth and its angular parts simple | Build a road whose elevation reads as flat segments |
| Fold a car's parts into each other at every seam, with a small overlap | Put flat planes on a car's curved surface, or leave a gap at a seam |
| Keep off-road geometry very cheap | Copy a real manufacturer's car, name or badge |
