# UI

How UI is built in every game. It happens in two stages (WORKFLOW.md): **programmer art** through Core loop and Production, then the **UI phase**, which turns it into the finished look.

**Readability on every screen size comes first.** A beautiful screen that's hard to read or use on a phone is unfinished. When goals compete: working behaviour, readability and input access first; then visual hierarchy and consistency; then decorative detail.

## Programmer art

UI before the UI phase is placeholder: simple and plainly styled. Its job is to help the user work out the layout: what each screen shows, and where its text and buttons go.

- **Build it from the UI kit** (`UI/Theme`, `UI/Create`; CODING.md): theme colours, plain panels and buttons, native text. No generated art, no decoration.
- **Build UI in code:** one ScreenGui per feature, `ResetOnSpawn = false`, `IgnoreGuiInset = true`, `ZIndexBehavior = Sibling`, and its `DisplayOrder` from `UI/Layers`.
- **Each screen is a view.** A view module builds the screen and draws it from a plain table (`setData`); it never touches remotes, services or saved data, and its buttons only fire signals. Its controller feeds it real data and acts on those signals. A fixtures module beside it (`<Screen>View.fixtures.luau`) holds sample data for every state, long text and big numbers included, so the screen can be previewed and measured without playing to that state. The API is in CODING.md "The kit's fixed names".
- **Use the shared pieces.** Buttons, panels, tabs and lists come from the kit rather than being drawn per screen, so the UI phase can restyle each one in one place.
- **It still has to work.** The readability and layout rules below apply now, in every supported layout, with every input type. The layouts the user settles on here carry into the finished UI.
- **Move things now.** Layout changes are cheap in programmer art and expensive after the UI phase. Every screen has a **drag mode** in the UI preview (CODING.md), so the user can try placements by hand:
  - **Whole widgets, not their parts.** The user drags each card, each action button, each counter. A second level moves whole clusters, like a strip of cards. Never a widget's parts, such as a caption on its own.
  - **Snapping, with an on/off switch.** Edges and centres line up with other widgets and with 8, 16 and 24 px screen margins, and a guide line shows the match. Otherwise a widget snaps to an 8 px grid. Holding Alt skips snapping for one drag.
  - **Fixed areas show.** What the game can't move, like Roblox's chat window or the touch controls, shows as a fixed block, and a widget dropped over anything turns red.
  - **Export, then code.** Dragging never changes the layout code. Export prints each moved widget's distance from its nearest screen corner, which goes into the screen's layout code and `UI-INVENTORY.md`; reset puts everything back where the code places it.
  - **Studio only.** It's `UI/Dev/LayoutDrag`, copied unchanged from `tools/ui/LayoutDrag.luau`, and it never runs in a published game.
- **Measure before art.** When the user approves a screen's layouts, measure it in each one (TESTING.md "Checking UI") and record each piece's size and aspect in `UI-INVENTORY.md` "Art slots". The UI phase makes the art to those numbers.

## Layouts per device

Each device gets a layout that suits it, never a scaled copy of another. The HUD on a laptop and on a phone can be completely different, and so can a phone held in portrait and in landscape: what shows, where it sits, and when it appears.

- **Decide the supported layouts when the first screens are built:** desktop, tablet, phone landscape, and phone portrait and console if the game supports them. Record them in `UI-INVENTORY.md`, with how each one is chosen.
- **The user decides every layout during programmer art, not at the end.** Each new screen is built in every supported layout from its first version and shown to the user in each, at that layout's reference size ("Screen sizes" below). Never "desktop now, phone later": a layout left to the end means rebuilding finished screens.
- **Choose the layout from the input type and the measured screen,** not a guess at the device, and switch live when the screen rotates or resizes.
- **Same screen, different placement.** Every layout uses the same components and shows the same data; only position, size, grouping and visibility change. Keep each screen's per-layout placement together in one place in its code, so behaviour can't drift between layouts.
- **Phones get a minimal HUD.** Decide, for each gameplay state, what shows, and cover as little of the screen as possible. Coverage is a number, the share of the screen the UI draws on, and the UI checks report it. Start from 15% while playing and 25% while a temporary card shows, unless the user sets other targets, and record the measured number beside its target in `UI-INVENTORY.md`.
- **Keep the touch controls clear.** Roblox's thumbstick zone (about the left 40% of the bottom two-thirds in landscape, the bottom 40% in portrait) and its jump button (about 70 px, near the bottom-right corner) can't be moved. Nothing tappable goes in them: a tap there moves the character instead. When a moment needs the space, hide them through `GuiService.TouchControlsEnabled` and put them back however the moment ends.

## The UI phase

### 1. Style

- **Concepts.** Generate a few style directions with the image tool (ART-PIPELINE.md), each shown as a mock of a real screen from this game. The user picks one, or combines them.
  - **Concept rounds are partial.** A direction needs only the pieces that define its look: one of each kind (a button, a panel, a bar, a tag). Reuse or skip the rest, and label anything reused. The full set is made after the pick.
  - **One sheet per round.** Show all the directions on one combined sheet: each one's screen assembled at native size over a real scene from the game, its animated pieces in their states (ready, cooldown, unavailable, in use), and every layer on its own. The user approves or asks for changes there, and nothing goes into the game before that.
- **Record it** in `docs/game/ART-DIRECTION.md`:
  - the approved reference images (`assets/reference/`)
  - the palette as semantic tokens (`Surface.Primary`, `Text.Primary`, `Text.OnLight`, `Action.Primary`, `Focus`, `Error`, `Disabled`); components use tokens, never raw colours
  - the fonts
  - the input-icon set used for every input prompt
  - the rules of the look (what it does and doesn't do)
- **Fonts:** render the chosen fonts in Studio at the smallest size, numbers and punctuation included, before committing to them. Never substitute one silently.
- **The style sets the look, not the words.** Keep the game's own terms and features; a reference doesn't license new themed copy.

### 2. Inventory

List every screen built so far in `docs/game/UI-INVENTORY.md`. Include the HUD, menus, dialogs, shops, notifications, onboarding, and UI created at runtime or placed in the world (billboards, prompts). Leave out what Roblox draws itself.

For each screen record:
- its source module and how it opens
- how it's laid out in each supported layout
- the data it shows and the inputs it takes
- its states (empty, loading, error, full, locked, ...)
- anything other code relies on (instance names, attributes, public API)

Mark anything you couldn't see as unverified.

### 3. Components

From the inventory, list the components the screens are made of, in `UI-INVENTORY.md`. Only the ones this game uses: buttons, icon buttons, tabs, panels, dialogs, list rows, item slots, badges, counters, toggles, sliders, scroll areas, tooltips, notifications, input prompts.

**Group, don't multiply.** The goal is a small, flexible component system that covers the whole game, so later screens are built from what exists instead of needing new components and new art.
- **Merge similar elements into one component.** Programmer art grows many near-identical elements. Fold each family into one component with variants and options: one button with sizes, styles (primary, secondary, destructive) and an optional icon, not eight button components.
- **Map every element.** In the inventory, map each programmer-art element to the component and variant it becomes.
- **Extend before adding.** Add a variant to an existing component before creating a new one. A new component needs a role none of the others can fill.

For each component, specify:
- **Purpose and variants.**
- **Size, padding and minimum touch target.**
- **States:** normal, hover, focus, pressed, selected, disabled and loading, where they apply. A button that waits on the server shows it (Pending, input ignored), and is wide enough for its longest caption so a state change never reflows its row.
- **Layers:** which parts animate or change with state ("Layers for animation" below).
- **Behaviour:** on compact screens and with long content.

**Each component shows its state as an attribute** (`State = "Pending"`), so tests read it instead of guessing from colours.

Build a component showcase in Studio before rebuilding any screen.

### 4. Assets

Work with the user through ART-PIPELINE.md to make the art each component needs: candidates, the user's pick, upload. UI art also follows these rules:

- **Text stays native.** Changing text, numbers, icons and hit areas are never baked into an image.
- **Whole images, not stretched ones.** A textured surface uses one image drawn for its shape, not nine-slicing or tiled edges.
- **The 20% aspect limit.** Resizing an image unevenly may change its visible aspect by at most 20%: `max(target / source, source / target) <= 1.20`, measured on the visible artwork without its empty transparent edges, in the image Roblox decoded (ART-PIPELINE.md "Images"). Past that, make an image for the new shape or reshape the component; never hide the mismatch by cropping decorative ends or repeating edges.
- **A variant per shape.** When a component's shape changes between layouts or with its content, make an image for each shape (wide, square, tall). `UI/Artwork` (CODING.md) picks the closest one at runtime, stretches it when it's within the limit and fits it when it isn't, and marks the frame with what it chose, so the UI checks can prove the limit held.
- **Each component gets its own art.** A button, a panel and a tab each get art drawn for their role. Never spread one decorated texture across everything.
- **Quiet interiors.** Keep the areas under text calm; weathering and ornament go at the edges, and only where they mark hierarchy.
- **Size art for how big it renders**, and reuse uploads wherever the art is the same.
- **Lay out from the art.** Where art holds content (a portrait socket, the band where bars and text sit), measure where it is in the image (`tools\ui\measure-anchors.ps1`), keep that in the asset registry with the variant, and place the content from it. Never assume where the generator drew it.
- **Icons** read at their real size, usually 24 to 36 px, and always use `ScaleType.Fit`. Keep one silhouette style and line weight across the set. Flat glyph icons are drawn in code (ART-PIPELINE.md "Icons drawn in code"). Key names like Space or Esc are native text on a keycap, never images.
- **A plain fill until the art loads.** Every image-backed piece shows a readable plain fill until its image has really loaded (`IsLoaded` and a fetch status of `Success`), then hides it.

**Layers for animation.** Anything that animates or changes with state is its own image. A state baked into one picture can only be swapped, never animated. Plan the layers before generating, and record them in `UI-INVENTORY.md` "Art slots".
- **The usual stack, back to front:** glow, base plate, frame or ring, content (icon, portrait, native text), state overlays (cooldown wipe, lock, selection), one-off effects (a burst on use).
- **Tinted layers are grayscale:** white highlights and a mid-grey body, coloured in game with `ImageColor3`, so a state or rarity recolours without new art. Keep a layer in colour only when its colours are the point.
- **Effects are their own images.** A glow or burst never sits inside the plate. A light sweep is usually a moving `UIGradient`, not an image.
- **Exact shapes are drawn in code,** never generated: a cooldown wipe, masks, hit shapes.
- **Generate related layers together,** on one sheet, so they look drawn by one hand (ART-PIPELINE.md "Images").
- **Hover needs a pointer.** A HUD that only shows information has no hover, but its layers leave room for one, so menus can reuse the art.
- **Bars and status tags get art too.** A bar is an art casing for each length, with a fill that's clipped, never stretched, and a moving glint at its tip. A status tag (READY, NEW) is native text on an art plate, or at least inside an art border.
- **Ready states are crisp:** a tight rim, with glints that can turn and pulse. Never a soft halo glowing behind the piece.

### 5. Rebuild

Apply the finished components to each screen, keeping the layout the user settled on in programmer art.

- **A small group at a time**, each one measured in every supported layout with the UI checks (TESTING.md "Checking UI") and compared with the approved reference, then shown to the user for approval. Numbers passing isn't the same as looking right: compare real screenshots with the reference.
- **Fix recurring problems in the shared component**, not screen by screen. Allow a screen-specific exception only when its content needs one, and note why.
- **Never change what a screen does:** same data, remotes, inputs and public API, and the instance names, tags and attributes other code relies on. Its open and close keys and gamepad binds, input blocking while it's open, focus order and hiding during cutscenes all still work.
- **Remove old UI** only after its replacement is checked and nothing still uses it.

## Readability rules

These apply to every screen, programmer art included.

**Text and contrast**
- **Sizes:** body and control text around 18 to 20 px, secondary text around 16. Essential text never below 16 effective px in the smallest layout, after scaling. 14 px only for text a player can do without, and only after checking it visually.
- **Never shrink text to make it fit.** Wrap, widen, reflow or scroll instead. Never cut off a cost, quantity, action, error or objective.
- **`TextScaled` only inside a `UITextSizeConstraint`**, never across the board.
- **Contrast:** at least 4.5:1 for text and 3:1 for meaningful outlines and indicators, measured on the real background, image textures included.
- **Text over moving gameplay** gets a backing solid enough to read on bright, dark and busy scenes. An outline alone isn't enough.
- **States show in more than colour:** hover, focus, selection, error and disabled each get a border, mark, icon or label too.

**Layout and input**
- **Measure the space first:** available space after safe areas, the top bar and on-screen controls (thumbstick, jump button).
- **Reflow, don't shrink.** Compact and wide layouts are based on what the content needs. Reflow columns, simplify secondary detail and scroll long content; never scale the desktop screen down for phones.
- **Targets:** at least 44 × 44 effective px, 48 × 48 for touch. Small art can sit inside a bigger target.
- **Reachable:** long lists and dialogs scroll with their essential actions reachable, and there is always a visible way to close or go back.
- **Every input type:** hover is never required, and everything works with touch, keyboard and mouse, and gamepad. Gamepad focus is obvious, moves logically and returns sensibly when a dialog closes. Input hints follow the input the player is using.
- **Layering:** a fixed order (HUD, menus, dialog backdrops, dialogs, tooltips), kept in one module, `UI/Layers`, that every ScreenGui takes its `DisplayOrder` from. Decoration never takes input (`Active = false`) and sits below the content; a button's caption sits above its art. A hidden screen leaves no invisible blocker or live handler behind.
- **Motion:** transitions of about 160 ms that can be interrupted; rapid clicks always end in the same state.

## Screen sizes

Check these, then add the game's actual supported devices. Record the viewport, UI scale, safe insets and input for each check.

| Layout | Check at | Risks |
|---|---|---|
| Small landscape | 640 × 360, 844 × 390 | Short height, notches, touch controls, tiny text |
| Tablet | 1024 × 768 | In-between layouts, stretching |
| Desktop | 1280 × 720, 1920 × 1080 | Density, spacing, hierarchy |
| Ultrawide | 2560 × 1080 | Stretched panels, actions far apart |
| Portrait, if supported | 360 × 640, 390 × 844 | Column reflow, keyboard, scrolling |
| Console, if supported | Its resolution and TV-safe area | Viewing distance, focus, controller navigation |

- **Check at real scale** and at widths around each layout breakpoint. A device preview in Studio shrinks the view to fit, so its screenshot doesn't prove real-size readability. Use Studio's device simulator at actual resolution (TESTING.md "Checking UI"), and record the viewport it really gave: an iPhone 13 Pro held upright gives 390 × 763 of usable screen, not 390 × 844.
- **Stress the content:** long names, 30 to 50% longer text, large numbers, empty and full lists, loading, errors and unavailable actions.
- **If a supported size fails, fix the layout.** Don't quietly drop the device.

## Player settings

What a player sets in their own Roblox settings, and what the game does with it (record each in `docs/game/SETTINGS.md` "From Roblox"). All of these can change while the player is in the game, so follow their changed signals. Checked 2026-11-02:

- **Text size:** `GuiService.PreferredTextSize` (Medium by default, then Large, Larger, Largest). Text that uses `AutomaticSize` and `TextWrapped` grows with it; `TextScaled` text doesn't, so leave room for larger text in every layout.
- **Transparency:** `GuiService.PreferredTransparency`, from 1 (the default) down to 0 (fully opaque). Multiply each panel's `BackgroundTransparency` by it.
- **Reduced motion:** `GuiService.ReducedMotionEnabled`. When it's on, drop tweens to an instant change or a short fade, and stop camera shake and screen flashes.
- **Input:** `UserInputService.PreferredInput` (`Touch`, `Gamepad` or `KeyboardAndMouse`) decides which input hints show, and changes as the player switches. Actions are bound through the Input Action System (CODING.md "Conventions").
- **Also:** never rely on colour or sound alone, and give music and effects their own volume settings.

## Localization

Roblox translates games automatically, into 18 languages: Arabic, Chinese (Simplified and Traditional), English, French, German, Hindi, Indonesian, Italian, Japanese, Korean, Polish, Portuguese, Russian, Spanish, Thai, Turkish and Vietnamese. Checked 2026-11-02. For it to work:

- **Text lives in text objects** with `AutoLocalize` on. Automatic text capture (turned on in the game's settings) collects them into the game's translation table. It can't capture text baked into images, what players type, or badge and pass names.
- **Build sentences from a whole string with placeholders,** like `"{count:int} coins"`, translated as one, never glued from pieces in code.
- **Text set from code** goes through a translator: `LocalizationService:GetTranslatorForPlayerAsync(player)`, in `pcall` since it can fail. A table key can swap an image per language.
- **Leave room:** translated text runs longer ("Stress the content" above).
- **Translation tables in git:** Lync syncs a `.csv` file into a `LocalizationTable`.
- **The game page:** its name and description are translated automatically where a language's entry is blank, and each language can have its own icon and thumbnails (RELEASING.md "Game page").

## Done

The UI phase is done when:

- **Coverage:** every screen in `UI-INVENTORY.md` is rebuilt and approved in every supported layout, with no mix of old and new styling.
- **Measured:** the UI checks pass for every screen at every screen size, with the reason for any exemption recorded.
- **Readable:** essential text is readable at the smallest supported size; nothing overlaps, clips or disappears.
- **Usable:** touch targets, focus, scrolling, back and close, and input hints work with every supported input.
- **Real states work:** real data updates, loading, empty and error states, repeated opening, respawn and other lifecycle moments, with no new errors or duplicated handlers.
- **Assets and fonts:** every asset id loads in the published experience and the chosen fonts render.
- **Performance:** the heaviest screens perform no worse than before.

Properties alone aren't visual proof, and a screenshot alone isn't functional proof: check both. Report exactly what couldn't be checked: usually real phones, tablets and controllers, real notches, asset access in the published game, and speed on low-end devices.

## Roblox references

Check current API details before relying on them:
[9-slice UI](https://create.roblox.com/docs/ui/9-slice) ·
[Size modifiers and constraints](https://create.roblox.com/docs/ui/size-modifiers) ·
[On-screen containers and safe areas](https://create.roblox.com/docs/ui/on-screen-containers) ·
[UI styling](https://create.roblox.com/docs/ui/styling) ·
[Font](https://create.roblox.com/docs/reference/engine/datatypes/Font) ·
[Console guidelines](https://create.roblox.com/docs/production/publishing/console-guidelines) ·
[Accessibility](https://create.roblox.com/docs/production/publishing/accessibility) ·
[Localization](https://create.roblox.com/docs/production/localization) ·
[Input Action System](https://create.roblox.com/docs/input/input-action-system)
