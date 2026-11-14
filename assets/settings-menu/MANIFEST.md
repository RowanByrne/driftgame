# Settings menu concepts

Owner: T-201; concept step T-202; feature branch `feature/glass-settings`, lane 1.

## Round 1 — 2026-11-14

**Status:** candidate; awaiting the user's visual choice. No candidate is uploaded or wired into the game. The source image and generated sheet live in the project folder's `art/generated/settings-menu/`, outside git.

| File | Role | Size | SHA-256 | Status |
|---|---|---|---|---|
| `drift-mountain-backdrop-01.jpg` | Actual Drift mountain-road scene, captured in a quiet lane 1 playtest | 1186 × 591 | `833368B7152C925850EF644FEE38859F215D8CF915B196AB8EC665B00A208E80` | Supporting reference |
| `settings-concepts-01.png` | One comparison sheet: A Smoked glass, B Pale frost, C Motorsport tiles | 1672 × 941 | `02614D490B53882F0946450D06AED2B33DED1A7A7195D5ADB556E9D2C5307261` | Candidate |

The controls and real scene are reused across all three directions; only composition, material, palette and corner treatment vary. Each direction shows desktop, portrait and landscape arrangements, selected/focused/disabled component examples, and the proposed fog/pane/native-content stack. The sheet is a style target, not a playable settings page or a commitment to migrate these controls.

### Generation and version record

- Generated with the built-in `image_gen` tool; no API/CLI fallback. Supporting image: `drift-mountain-backdrop-01.jpg`.
- Installed bundled Codex CLI reported `0.167.0-alpha.4.1`; its installed bundle was updated on 2026-11-14. The built-in tool does not expose its image backend model or the desktop app version, so backend currency cannot be inferred from this CLI version.
- Official [image model reference](https://developers.openai.com/api/reference/resources/images/methods/generate) and [image generation guide](https://developers.openai.com/api/docs/guides/image-generation) checked 2026-11-14; these list GPT-Image-2.6 Sunburst/Flare. No evidence establishes that the built-in tool is behind; no model version is claimed.
- Requested 3840 × 2160; tool returned 1672 × 941. The unchanged output's aspect is 1.777; `measure-png.ps1 -Aspect 1.7777777778` reports distortion 1.001, within the 20% shape limit.
- Compact previews are illustrative; actual text/target sizes and safe areas are not yet measured in Roblox. The generated desktop mockups are smaller than native desktop size on this sheet. Native-resolution layout validation belongs to the chosen page's implementation.

### Capture and checks

The current drift, camera and UI-visibility scripts matched disk and compiled in lane 1 before capture. An agent-quiet playtest entered the existing mountain run through its normal debug handler; afternoon sky was held for the shot and P hid game UI. Two screenshots total were used in this task: a discarded playground view and the mountain backdrop. Playtests were stopped. Console output contained Studio plugin connection notices, with no gameplay error from this capture.

Glass and blur remain unimplemented. The image's scene-softening is a visual target; the chosen page must prove readable pane opacity and clarify whether Roblox blur affects the whole scene. Text, controls and hit areas will remain native UI.

## Exact prompt

```text
Use case: ui-mockup.
Asset type: one high-resolution design comparison sheet for the Roblox driving game Drift, 3840 by 2160 landscape.
Primary request: Create THREE distinct, polished modern frosted-glass SETTINGS menu concepts, side by side on ONE sheet. Original interface design inspired by the restraint and clean hierarchy of premium contemporary motorsport games. Glass panes, fogginess, semi-transparency and tiles are the main materials. Avoid the generic glossy game-item look: no gold trim, rivets, sci-fi HUD, neon outlines, hexagons, loud gradients, fake chrome, logos or decorative gauges.

Input image 1 is a SUPPORTING GAME-SCENE REFERENCE, not an interface to copy. It is an actual lane playtest of Drift: a small white 1980s liftback seen from behind on a gray mountain road, faceted green mountain to the right, valley to the left, pale cyan sky, and an orange/red starting strip in the foreground. Reuse this SAME real scene and SAME camera framing underneath every desktop mock. Do not replace it with a photorealistic racetrack or different car. Native 1186 by 591 scene framing; crop only as needed to fit the layout. Glass may soften the underlying scene while keeping recognizable scene silhouettes. Make it apparent which regions are transparent; keep text backing calm and readable.

Composition: Three equal vertical columns with generous separators and consistent baselines. Each column has (1) a clearly titled direction label, (2) one large DESKTOP screen at approximately 1186 by 667 pixels, (3) compact PHONE PORTRAIT and PHONE LANDSCAPE previews below that reflow the same content with large touch controls, (4) a small tidy component/state-and-layer strip. Prioritize large readable desktop menus and clear visual differences, not lots of annotations. Overall sheet title "Drift / Settings concepts". Subheading "Style exploration · controls shown are candidates". The desktop previews share the same size. Compact layouts must be visibly rearranged, not shrunken desktop screenshots.

Direction A label: "A / Smoked glass". Dark charcoal/smoke translucent panes, soft scene fog, off-white type, restrained warm orange selection, calm rounded rectangular category tiles. A generous floating menu with a left category rail and a two-column content area. This is the darkest, most immersive option. Fine light rim and sparse highlights, no outer glow.

Direction B label: "B / Pale frost". Clearly LIGHT warm pearl/ice frosted translucent panes, dark graphite typography, restrained cool teal selection, a generous large unified floating pane with inset light tiles. Maximum airy space, fine frosted white edges. Dark text must be readable over the actual mountain scene. This must look visibly lighter than A, not another black menu. Desktop category tiles sit horizontally above the content.

Direction C label: "C / Motorsport tiles". Graphite translucent surfaces with much sharper almost-square corners, separated modular rectangular tiles, white typography, one disciplined yellow/lime selection bar. A strong aligned editorial grid with the title on the left and tile navigation in a compact top row. Distinct from A's big rounded floating pane. Quiet precision, not racing-brand logos or checkered decoration.

Keep identical representative CONTENT across all three; do not invent settings. Main title "Settings"; category tiles "Steering" (selected) and "Interface"; active section "Driving controls"; steering mode segmented selector "Dynamic" selected / "Centred"; row "Pointer sensitivity" with value "5" and a clear horizontal slider marked "1" and "10"; secondary note "Higher = shorter travel". A separate "Interface" group includes "Show game UI" with an ON toggle, plus native keycap "P" and caption "Hide / restore UI". Clearly visible "Back to drive" action and a close X with a large target. Small plain note "Session only". Do not imply cloud saving or show Apply/Save when nothing is saved. No audio/graphics/accessibility or tuner tabs added just to fill the mock. Do not copy an existing game's words or branding.

Phone portrait: single scrolling column with category chips, stacked controls and a fixed reachable Back action. Phone landscape: slim top category row with two compact control columns, reachable close/back, no clipped slider. Keep control text effectively around 18px and touch targets about 48px in the implied actual-size layout. The small previews are illustrative, not measured implementation proofs.

Component strip in each column: show one matching panel tile, button, slider and toggle using the same hand. Label small state samples "Selected", "Focus", "Disabled". Disabled is an isolated component example, NOT a new feature/category. Focus has a visible non-color outline or marker. Add a simple three-layer material diagram "Fog / pane / native content" in that direction's colors. Text and controls are clean precise typesetting as a production UI mockup; eventual shipping text, controls and hit targets will remain native Roblox UI. No claims that blur is already implemented. Footer: "Visual targets · glass and blur to be proved in Roblox".
```

## Pick

Pending. Record the user's words, copy the chosen reference unchanged into `assets/reference/`, and update the settings spec, art direction and decisions before building the page.

