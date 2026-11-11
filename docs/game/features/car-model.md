# The car model

The game's own car, built through ART-PIPELINE.md "3D assets" as the pipeline's first test: the 1980s liftback the placeholder already is, in faceted low poly, with the whole car modeled and its parts moving as the real ones do (DECISIONS.md, 2026-11-09). It replaces the Toolbox car in `Shared/Cars/AE86.luau`. The record of every reference is `assets/car-ae86/MANIFEST.md`.

## Where it stands

| Gate | State |
|---|---|
| Reference sheet | Approved 2026-11-09: `assets/car-ae86/ref-sheet-02.png` |
| A reference for every view | Approved 2026-11-09: 15 views in `..\art\generated\car-ae86\views\` (the manifest lists which) |
| Gray model | **Approved 2026-11-10** ("ok approved."), after seven rounds of notes on the second build. The first, a headless scripted build, was rejected: "not even close" |
| Textured model | **Surfaces decided 2026-11-10: materials and colour, per piece. Exported, imported into the Lane 3 place and coloured there; waiting for the look to be tuned and the user's verdict** ("Surfaces and export") |
| Animation | Not started |

## What is built

Everything: body, glass, interior, engine bay, boot and underside. Right-hand drive. No badges or names, and no licence plates at all for now: the user's call (DECISIONS.md, 2026-11-09), to be settled before anything ships (the manifest's "Platform risk").

**Scale:** the concept art's proportions, scaled so the wheelbase is the game's 9.6 studs (`Shared/Cars/Archetypes.luau`), with the game's 5.6 track: 17.7 long, 5.8 high, wheels 2.58 across. The width is 7.0, because the concept disagrees with itself: its front and rear views draw the car 7.6 wide, its top view 6.6; 7.0 is also the real car's proportion. The game's `WheelDiameter` is 2.3, so the wheels will sit small in the arches unless it becomes 2.6: the user's call when the model is wired in.

**Moving parts**, each its own mesh with its origin on the real hinge line or pivot:

| Part | Moves |
|---|---|
| Two doors | Swing out on the front hinges |
| Door windows | Slide down into the door |
| Hood, and its prop rod | Lifts on the rear hinges; the rod swings up to hold it |
| Hatch, and its two struts | Lifts on the roof hinges; the struts extend |
| Two headlight pods | Rotate up out of the nose; each carries its lens, a part of its own |
| Four wheels | Spin; the front pair steer |
| Four brake calipers | Never spin with the wheels: each is a part of its own with its origin on its wheel's centre. The front two turn with the steering; the rear two do not move |
| The engine's crank pulley, its fan (with the water pump's pulley) and the alternator's pulley | Turn about their own axes, front to back; added when the new engine went in |
| Steering wheel | Turns with the steering |
| Speedometer, tachometer, fuel and temperature needles | Turn about the dial centre |
| Gear lever, handbrake, three pedals | Tilt about their pivot: the lever's base, the handbrake's rear, the pedals' tops (they hang) |
| Two wipers | Sweep about their spindles |

## Blender and Studio

The game's car is moved by code and holds no physics (DECISIONS.md, 2026-11-03), so nothing gets a physics hinge or a Blender armature.

| Blender | Studio |
|---|---|
| All geometry | Opening and closing: code turns each part about its pivot |
| Every moving part as its own mesh, origin on its hinge line | The open angles and timing |
| Test poses at full open, to prove nothing clips | Needles from speed and revs; the steering wheel from the steering |
| UVs, textures, a shared atlas | Lights: glow on and off, headlight beams, brake and indicator lamps |
| Export: one file, cut by part and by surface | Wheels spinning and steering, which the game already does |

## The gray model

**Second build, revised 2026-11-09, waiting for the user's verdict.** Built in the open Blender 5.2.3 through the Blender MCP, from the approved concept views only: nothing from the first build was used. The first build (a headless script, matched by outline score) was rejected and is kept untouched beside this one, for the record.

**The revision.** The user's verdict on the second build was "needs changes": exterior details, and the inside and open views. Reworked against every reference view:

- **Outside:** the nose (a visible grille slit under the hood's edge, squarer bumper corners, brighter lamps, taller plate), the pop-up lights at the size the front view draws them, mirrors as chamfered housings on a black sail corner, wheels from the wheel sheet (rim lip, eight tapered spokes, four nuts, brake disc and caliper), tail lamps in a black frame with seams, a deeper rear bumper, a larger tail pipe.
- **Inside:** a new cabin (dashboard with vents, heater sliders, radio, glovebox; an instrument cluster with tick marks and warning lights; bucket seats; console; door cards with armrest, pull, handle and winder; visors and mirror), the rear seat folded flat and the boot with its spare-wheel well and trim, a new engine bay (twin-cam engine, intake and exhaust, radiator and fan, booster, battery, air box, hoses, strut towers, cowl), a new underside (alloy sump and gearbox, propshaft, axle and links, springs, tank, exhaust), ribs under the hood, heater lines on the hatch glass.

Source, outside git: `..\art\source\car-ae86\car-ae86-gray2.blend`, the modelling code in `..\art\source\car-ae86\gray2\` (`final.py` rebuilds, checks, renders and saves), and `..\art\source\car-ae86\pivots-gray2.json`. Renders: `..\art\generated\car-ae86\gray2\`. The manifest lists them.

**The third round, the same day.** The user on the revised model: "good prog", then five notes, all done:

- **Hood and front fenders, in three tries,** each on the user's word. A fully flat hood with level fenders: "fenders are too high and outwards and the whole hood is too flat now". The concept's evenly bowed profile: "almost", then, with photographs of the real car: "it's not an even curve downwards, it's mostly flat until the headlights where it starts to nose down". So the hood now runs nearly flat from the windscreen to the headlights and noses down over their lids; it is flat across its middle with a slight fall to the shut lines. Each fender top is one plane sloping from the shut line down to its edge, which arrives exactly on the door's beltline at the cowl; the fender sides lean in toward that edge. The first sloped version warped the fender top over the corner lamp; a single plane cannot.
- **The body line along the side,** which the user drew on photographs of the real car and on the reference sheet: "an indent that comes back out". This round made it a small groove on the two-tone split, running from nose to tail; the fourth round replaced it.
- **The sides are flat panels.** One lean runs the length of the car from the body line up to the belt, and a small ledge at the belt carries the windows inboard, so every facet between two stations is flat where the old sides twisted.
- **The pop-up lights' lids carry a front lip** that hides the folded lamp behind the nose band; raised, the lip is the lamp's brow, as on the real car.
- **The bumpers run into the wheel arches.** Each bumper's side carries on to the arch and ends against the arch's lip, flush with the lip's face and cut to its edge, where it used to stop short with a blunt, notched end ("clean up how the front bumper just stops", the user; the rear was the same and got the same fix). Along the sides the front bumper's black face is flat: the recess for the fog lamps fades out round the corner.
- **Seams closed:** panels that share an edge now share its corners point for point (side to tail, side to nose, fender to side, hatch to body). Behind the shut lines of the doors, the hood and the hatch lies a black seal, so a gap shows black and nothing behind it. The doors' shut faces are black for the same reason, where the door-open view draws them white.
- **Every light is its own part:** 25 lenses, each standing a hair proud of a black housing, so the game can light each one and give it a glass surface. Headlights (they ride with their pods), front markers, front indicators, parking lamps, fog lamps, tail lamps, brake lamps, reversing lamps, rear indicators, the garnish between the tail lamps, and the six warning lights under the dials. `pivots-gray2.json` lists them under `lights`.
- **No licence plates.** The rear bumper's bar still stops short of the middle, where one would hang.
- **The dent over the rear wheels is gone:** it was the old side twisting between the door and the tail, and the arch's swell reaching up into it.

**The fourth round, 2026-11-10.** The user's notes on the open model, with crops of the reference views:

- **The body line is an indent above the split, from the tail lamp to the front wheel's flare** ("note how the indent runs from the taillight to the front wheel fender thing, not through the front fender thing"). Above the two-tone split the side goes in 0.07 and comes back out, over 0.30 of height, so the lower facet catches the light and the upper one sits in shade, as the side view draws it. It starts at the tail lamp's housing, breaks at the rear wheel's flare, ends at the front wheel's flare, and is not there ahead of the front wheel. It replaces the third round's groove.
- **The wheel flares are the reference's size.** They were thin lips, less than half the width the side view draws. Each is now a black face 0.31 wide standing 0.15 out from the body side at every height, under a white brow that is a plain bevel from the side out to it, on nine facets. The bumpers end against the flares' faces, and the sill runs between their feet. Found while measuring where the body line should end; the user had not asked for it.
- **Where the lamps meet the split** ("fix the rear corner too"). The tail lamp's black housing and the front corner lamp's both stand on the black below the split, with no white strip under them. The front lamp is lower and slanted at its front like the fender's tip, and its housing runs on into the nose band.
- **The fuel flap reads** ("improve visibility of the gas cap"): a plate with cut corners standing proud of a dark surround, placed and sized from the right side view.
- **The exhaust is one run** ("fix exhaust connection here"): the silencer stops short of the rear valance and necks down to the tail pipe, which runs out through a notch in the valance, on the car's left only, into the tip. Before, the valance cut through the silencer's end and the pipe began from nothing. The steel floor under the boot now reaches the tail panel, so nothing shows up through the notch.
- **The boot, to the hatch-open view** ("size of wheel well, shaping of wheel arches inside the car, support strut attachment, etc."). The spare-wheel well is a wide stepped octagon, about 2.7 across, with its clamp post. The trim over each wheel housing is a faceted hump, tall behind the seat, then stepping out and falling toward the tail. The back of each tail lamp is flush on the rear wall, facing into the boot: a white panel with the housing, bulb holder and wire. The hatch's struts are pinned where the view draws them: the black tube to a bracket under the hatch's side frame, the bright rod to a bracket on the pillar beside the opening.

**The fifth round, the same day.** More notes from the user, looking round the open model:

- **The wheel flares are simpler** ("simplify the wheel flares geometry, they are a bit off with how they merge into the car's body"). The face used to stand upright while the body tucked in under it, so the brow twisted and the flare's feet stood far out; and the body line ran into the brow. Now the face follows the side at a constant distance, so every facet of the brow is flat, and the body line fades out just short of each brow.
- **The wheels are round:** 48 sides where there were 16, with rounded shoulders and a slight bulge in each sidewall; 1,482 triangles each, three times what they were ("3x more tris basically").
- **All four calipers are parts of their own** ("make sure they are setup so that the inner brake calipers will not spin when the wheel spins"). The rear two used to be part of the underside. The disc turns with the wheel; the caliper never does. Every build now turns the wheels through one spoke's pitch, straight and at full lock, and fails if a caliper touches its wheel more than it does at rest.
- **The rear bumper's corner wraps the body's** ("fix this little overlap on the rear bumper"): the bar's corner was cut deeper than the body's own corner, which poked out through it.
- **The headlight wells are solid** ("solidify the headlight wells so they have solid cavities to pop away into"): each pop-up light folds into a closed black box, open only at the top, its floor following the arc of the lamp's foot. The pods are checked a quarter, a half and three quarters of the way up as well as shut and raised.
- **No way through beside the dashboard** ("solidify this gap in the side of the dash next to the door"): the firewall now reaches the body sides, the dashboard's ends stand close to the closed doors, and the pillar's foot ahead of each door is filled.
- **The tail lamps' backs are flush** ("rotate these to be flush"): they lie on the rear wall, facing into the boot, where they stood across the corners.
- **Faces point outward.** Found while rounding the wheels: every turned part (tyres, rims, knobs, dials, the brake booster, the axle), the sills and the dashboard block had their faces pointing inward. Blender draws both sides, so nothing showed; Roblox draws only the front. Fixed at the source, and checked with Blender's face-orientation overlay from every side, open and closed. Still one-sided on purpose: the glass, which shows only from outside. The export step's own check found more ("Surfaces and export").

- **How it was made:** every panel is drawn on the concept view it is seen in (side, top, front or rear) and laid onto the car's surfaces, so door seams, window lines, lamps, stripes and wheel arches sit where the concept draws them. The surfaces come from lines measured off the concept: hood and roof profiles, the widest line of the body, the shoulder, the greenhouse lean.
- **Matched by eye, four passes:** each pass rendered the model from the concept's own angles, set each render beside its reference, and fixed what differed. Passes 1 and 2 were the exterior, pass 3 the open and inside views, pass 4 everything again; the revision repeated it part by part. The sheets are `compare-1-exterior`, `compare-2-open`, `compare-3-ortho` and `compare-4-inside`, in colour and in gray, and `compare-5-nose`: the user's crop of the reference sheet beside the same crop of the model. No outline score is used: the first build's 91% said nothing about what the user saw.
- **24,382 triangles in 72 meshes** (25 of them lenses); the largest, the body, is 3,600, well under Roblox's 20,000 a mesh.
- **Flat colours are on it,** one material per colour, because the concept can only be compared in its two-tone. They are not the surfaces stage: the gray renders show the same model in one clay.
- **Every moving part** in the table above is its own mesh with its origin on its pivot. `pivots-gray2.json` records each pivot, axis and travel. Doors open 62 degrees, the hood 48, the hatch 46 (as far as the hatch-open view lifts it), the lights 44.7, the front wheels steer 30. The prop rod's length and its 63.4 degree swing follow from the hood's: its tip stops under the open hood.
- **Clip check, run by every build:** with every part at full travel, no part touches anything it did not touch closed. What touches closed is meant to: panels along their shut lines, the calipers on their discs, the gear lever in its boot, the two halves of each hatch strut, each strut's pin in its bracket, the wiper spindles.
- **The prop rod and the hood must move in order:** the rod cannot swing up through a hood that is already open, so the hood lifts first and settles onto the rod, as on the real car. Studio's opening code has to sequence them.
- **The door windows** drop by turning about a lengthwise axis far inboard, not by sliding straight down: the glass leans in more than the door does, so a straight drop would push it out through the door skin.
- **Each hatch strut is two parts,** a tube pinned to the hatch and a rod pinned to the body's pillar, each turning about its own pin to aim at the other's, so they telescope as the hatch lifts.
- **Settled from the references:** eight spokes; four dials, laid out as the instrument sheet draws them (speedometer on the driver's left, tachometer on the right, fuel over temperature between, six warning lights beneath). The rear seat's back is folded flat, as the hatch-open, door-open and interior views all show it. The prop rod stands on the car's left, as the hood-open view shows it. Where the views disagree: heights follow the side view, the width is 7.0, the spoiler sits where the side view puts it, the rear side lamp is all orange as on the reference sheet, the fuel flap is on the right, the exhaust runs down the car's left (the rear views; the underside view draws it on the other side), the pop-up lights' lids are white (the lights-down view; the top and engine-bay views draw them black).
- **Tyres are 1.1 wide,** not the placeholder's narrower ones, so the wheels fill the arches as the concept draws them; the track is still the game's 5.6.

**Short of the references, known:**

- **Dial numbers** are not modelled: tick marks only. Numbers are a texture, for the surfaces stage.
- **The pop-up lights are wedges,** hinged at the lid's rear edge: raised, the lid tilts up about 16 degrees and the lamp's foot hides behind the nose band; the reference sheet draws them nearer to boxes.
- **The hood departs from the concept's side view** on purpose: the concept bows it evenly, the real car's is flat to the headlights, and the user chose the real car's.
- **Camera framing** of the three-quarter, open and dashboard views is near the references, not identical: the references are drawn with a perspective, and in the dashboard view a seat position, that the model cannot repeat exactly.
- **The engine bay and underside** have the references' parts but fewer small ones: no wiring looms, bolts only on the main parts, pressed floor shapes simplified.
- **The wheels sit about 0.2 inside the flares at the top** and about flush with them at axle height, with the game's 5.6 track.
- **The tail's corners are square in plan.** The top view and the door-open view cut them back so the tail lamps wrap round the corners; the side view draws them square, and the model follows the side view. Put to the user on 2026-11-10.

**The engine on its own, 2026-11-10.** The user asked for six views of the engine alone, then: "confirm the engine is accurate to the real engine that came with the car, and that the refs are accurate to it. then model it in another blender window".

- **The engine is the right one:** the 1.6 litre twin-cam, 16-valve four with the variable intake, as fitted to this car from 1983 to 1987, mounted lengthwise. Checked against published descriptions and photographs of the real engine bay.
- **The six views get the layout right and several parts wrong.** Right: intake on the car's right, exhaust on its left, the throttle at the front of the intake, fuel rail and injectors beside the intake cam cover, two silver cam covers, three core plugs a side, the flywheel end. Wrong: coil units in the plug valley (the real engine has one distributor, at the front of the head on the exhaust side, with leads to the valley); twin round bulges on the timing cover (it is one wide ribbed cover); the alternator on the exhaust side (it sits low on the intake side); the starter on the intake side (it is on the exhaust side at the back); the oil filter at the back (it is in the front third); no fan (the water pump carries one); a tubular four-into-one manifold with no shield (it is a cast manifold under a pressed heat shield); separate curved intake pipes (it is a boxy plenum); a level sump (it is deep at the front).
- **The model follows the real engine** wherever the views differ, and the views for the style. It is a scene of its own, "Engine", in the car's Blender file, shown in a second window, and also saved alone as `..\art\source\car-ae86\engine\engine.blend`; the code is `engine.py` and `build.py` beside it. 4,928 triangles in 12 meshes. The crank pulley, the fan with the water pump's pulley, the alternator's pulley and the flywheel are meshes of their own with their origins on their axes (`..\art\source\car-ae86\pivots-engine.json`). No lettering or badges.
- **Approved and fitted the same day** ("engine is good, fit it but keep it saved as it's own file"). In the car it stands at nine tenths of its size, so it clears the closed hood and sits with its shallow sump over the crossmember, as the real one does. Its fixed parts are one mesh, `Engine`; the crank pulley, the fan and the alternator's pulley are parts of their own; the flywheel is left out, inside the gearbox's bellhousing. The first, simpler engine and the fan drawn on the radiator are gone. The radiator hoses, the intake duct and the exhaust pipe now start at the new engine, and the steering rack moved ahead of its sump. The engine alone stays in its own scene and its own file, with dotted part names (`Engine.Block`) so the two never share a name.

**The sixth round, the same day.** Four more notes on the car:

- **The front flares' rear legs** ("this odd wheel flare geometry on front wheel flares"): a panel line of the body crossed the brow there and let its facets be split across their corners. Every corner of each flare now has its own edge across the brow, and the sill's level is carried across the foot, so each facet is one flat piece.
- **The grille's overhang** ("front grill has this odd overhang"): the dark panel behind the lower grille ran on past the fog lamp and stuck out where the bumper turns the corner. It now ends behind the fog lamp.
- **The body line's ends** ("these weird triangle geometries where the indent goes into another feature"): it runs at full depth right up to each flare's brow and to the tail lamp's housing and stops in a narrow end wall that follows the feature's own edge, where it used to fade out over slanted triangles.
- **The door openings** ("still these holes where the door is ... the door hinges are not connected to anything when the door is open"): each opening now has a jamb, the body's own metal running inward all round it, with a pocket at the front, so nothing shows through beside an open door. Each hinge is in two halves: a knuckle on the opening's edge, fixed to the body, and a pad on the door's front edge. They sit where the skin is nearest the doors' upright hinge line, so they part by about a tenth of a stud when the door is open; hinges that stay joined would need the doors to swing inside the fenders, which they do not.

**The seventh round, the same day.** "car looking good", then three notes:

- **Hoses, pipes and wires bend as one tube** ("fix the random gaps in conctor lines and hoses and stuff"). Each used to be a row of separate cylinders, which left a wedge open on the outside of every bend; now the legs share a mitred ring at each corner. Every end is seated in or against the part it belongs to, and every build lists any end that touches nothing: none. The ignition coil stands on the left housing behind the battery, with the distributor's lead running to it.
- **The flanges round the engine bay have a thickness** ("these flanges ... are like 1 pixel thick, make them proper if they are supposed to be there"). They are supposed to be there: the black seals under the hood's and the pop-up lights' shut lines, the ledge the fenders bolt to, and the walls of the headlight wells. The seals are lips now, the ledge a strip with its bolts standing on it, and the wells' walls are solid. The door seals are narrow lips on the new jambs, and the hatch's seal is a lip too.
- **The gap at the windscreen's lower corners** ("this random gap ... near ... the lower corners of the windshield"): the corner of the fender top ran straight across where the body side steps in at the belt, leaving a sliver open. It now follows that step.
- **The door seals and jambs follow the body's edge** ("door seal not attached to side of car"): each ran straight from corner to corner of the opening, so along the tall rear edge it stood well inside the body side. Both now have a point at every height where the side bends, and the seal stands on the back of the opening's edge.
- **The pop-up lights are closed solids** ("headlights have lots of 1 pixel planes on them"): the housing is flush with the lid all round, where the lid used to overhang it as a bare sheet, and the front lip is a solid wedge.
- **A raised lamp stands against its well** ("fix this so it's connected to the headlight 'bucket' fully"): with the hood open and the lamp up, a sliver showed through between the lamp's side and the well's top edge, and the hood's seal ran beside the well's wall as a strip of its own. The well's inboard wall now stands in the gap between the hood's edge and the lid's and rises almost to the surface; the lamp's housing has a rear wall hanging from its hinge line, so raised, its sides reach below the wall's top all the way back to the hinge; and the lip the hood shuts over is a ledge of the well itself, round its rear corner too.

## Surfaces and export

The gray model was approved on 2026-11-10 and the surfaces decided with it (DECISIONS.md): **Roblox materials and colour, set per piece by the game.** The user's brief: "easy to have colorways or color swatches on it, differing materials, glass tints".

**How the car is cut.** One Roblox piece has one colour and one material, so every moving part is cut by surface: what the game can colour, give a material or light on its own. The 72 parts become **168 pieces**, each named `<Part>_<Surface>` (`Body_Paint`, `DoorL_Trim`, `WheelFL_Rim`). A colourway, a finish or a glass tint is then a line of data, never new art.

| Surface | What it is | The game's `Paint` tag |
|---|---|---|
| `Paint` | the body colour: panels, bumper tops, hood, hatch, lids, the engine bay's inner panels | `body` |
| `Second` | the two-tone's lower colour | `second` |
| `Rim`, `Tyre` | each wheel's rim and tyre | `rim`, `tyre` |
| `Caliper` | each brake caliper, one piece, so a build can paint them | none |
| `Glass` | every window, one sheet facing out: the game draws it from both sides | none |
| `Trim`, `Lining`, `Panel`, `Seat`, `SeatAccent`, `Rubber` | black plastic and seals; the cabin's lining; door cards and visors; the seats and their centres; hoses, pads and blades | none |
| `Metal`, `Light`, `Alloy`, `Iron`, `Rust`, `Brass`, `Disc`, `Mirror`, `Dial`, `Needle` | bright metal, light painted parts and dial marks, cast alloy, dark iron, the exhaust manifold, brass, brake discs, mirror glass, the instrument face, the needles | none |
| `LensHead`, `LensAmber`, `LensRed`, `LensBrake`, `LensFog`, `LensClear`, `LensReverse` | each lamp's lens, a piece of its own to light | none |
| `Accent…` | small coloured details: caps, labels, the cabin's red line | none |

**What is exported**, both in `assets/car-ae86/`:

- `car-ae86.fbx`: the whole car, shut, as 168 meshes in one file, 24,380 triangles, under 1 MB. One unit is one stud. Faces are flat, already triangles. Studio's importer brings it in facing +Z: turned half a turn about Y it is the game's car frame (X the car's right, Y up, -Z forward).
- `car-ae86.meshes.json`: the 168 pieces as Roblox mesh assets, read off the imported model: each piece's asset id and where its centre sits in the game's car frame. With this in git the car can be put together again in any place; the place it was imported into is not the only copy.
- `car-ae86.json`: for each of the 72 parts, how it moves (its pivot, axis, travel and what it rides on, as `pivots-gray2.json` gave them) and what lamp it is; for each piece, its part and surface; for each surface, a starting colour, material, shine and see-through, and its `Paint` tag; and the points the rig reads: the driver's seat, where the driver steps out (an estimate), and nine floor points.

**Wraps.** The `Paint` and `Second` pieces carry UVs: five plain views of the car (left, right, top, front, rear) on one square sheet, all at one scale, so a wrap is one picture drawn over them. Nothing else has UVs yet.

**Solid from every side.** Roblox draws a face from its front only, so before export the car was looked at along about 600,000 sight lines, from all round, underneath, close up and from the seats, shut and open, counting the ones that land on the back of a face. It found, and these were fixed: the bumpers were open at the back (each is a solid bar now, and the tail pipe's notch a pocket in it); the door jambs had no back; the seals and wiper blades were open at their edges; the rear window's heater lines, the mirror bezels and the gauge hood's inside faced the wrong way; the nose band had no back; the pop-up lights had a hairline crack at their outer front corner; the rear bumper's underside folded over itself at the corners. What is left is about 70 sight lines in 300,000, grazing ones and a slot behind each front wheel seen from under the car. Every build now prints this count.

**Checked:** the file was read back in on its own: 168 pieces, every triangle count the same, every point where it was sent, no smoothed faces, UVs on the 16 painted pieces.

**In Studio.** The user imported the file into the Lane 3 place on 2026-11-10, as `Workspace.car-ae86`. Measured there: 168 mesh pieces, each with its own uploaded mesh; 7.53 wide, 5.78 high, 17.83 long, so the scale is right; the model's pivot is the car's origin; it faced +Z and was turned round. It now stands on the baseplate at (0, 0, -30), facing -Z, every piece anchored and not collidable. Every piece carries its surface's colour, material, shine and see-through, and three attributes: `Paint` (the game's tag), `Surface` and `Part`; lamp lenses also carry `Lamp`. The five glass pieces are drawn from both sides. A few starting values were changed by eye there and written back to the data file: the second colour, trim, tyres and rims darker (the gray model's near-blacks came out too light), less shine on the second colour (a shiny dark surface takes on the sky's blue), and a darker glass tint. **A place is not in git:** the car there lasts only if the place is saved.

**Not done:**

- **The look, which is the surfaces gate.** The car has been seen only in the lane place's bare default lighting, where it reads correctly but plainly. Paint finish, lit lamps and above all lighting are not tuned; the art direction's lighting is still unset (ART-DIRECTION.md), and that is the user's call.
- **The detail sheet:** one small shared texture for dial numbers, tyre sidewalls, lamp lens patterns and the grille. Those pieces get their UVs when it is made; each is a piece of its own, so only they are imported again.
- **Wiring it into the game** through `Shared/Cars/Rig.assemble` (CONTRACTS.md "The car rig"): a task of its own.
- **168 pieces is the flexible cut, not the cheapest.** If cars turn out to cost too much to draw or move, pieces that are never recoloured can be joined (the engine, the engine bay and the underside first) by changing one table in `export.py`.

## Not settled

- **The car contract.** Today a car is a `Body` and four `Wheel*` groups (CONTRACTS.md). Parts that open need groups of their own; that change goes in first, as its own commit, when the model is wired in. The user: "we will adjust the game later to work with a car like this".
- **Differences between the references** for the build to settle, not copy: eight spokes on the wheels (the wheel sheet), and the instrument sheet's four dials over the dashboard view's simpler cluster.
- **The wheels' size.** The model's wheels are 2.58 across and the game's `WheelDiameter` is 2.3: the user's call when the model is wired in (see "Scale").
