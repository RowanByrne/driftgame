# The car model

The game's own car, built through ART-PIPELINE.md "3D assets" as the pipeline's first test: the 1980s liftback the placeholder already is, in faceted low poly, with the whole car modeled and its parts moving as the real ones do (DECISIONS.md, 2026-11-09). It replaces the Toolbox car in `Shared/Cars/AE86.luau`. The record of every reference is `assets/car-ae86/MANIFEST.md`.

## Where it stands

| Gate | State |
|---|---|
| Reference sheet | Approved 2026-11-09: `assets/car-ae86/ref-sheet-02.png` |
| A reference for every view | Approved 2026-11-09: 15 views in `..\art\generated\car-ae86\views\` (the manifest lists which) |
| Gray model | **Next.** Not started |
| Textured model | Not started |
| Animation | Not started |

## What is built

Everything: body, glass, interior, engine bay, boot and underside. Right-hand drive. No badges, names or plate text: blank for now, the user's call, to be settled before anything ships (the manifest's "Platform risk").

**Scale:** the game's car has a 6-stud wheelbase (`features/drift-model.md`); the model is built to it.

**Moving parts**, each its own mesh with its origin on the real hinge line or pivot:

| Part | Moves |
|---|---|
| Two doors | Swing out on the front hinges |
| Door windows | Slide down into the door |
| Hood, and its prop rod | Lifts on the rear hinges; the rod swings up to hold it |
| Hatch, and its two struts | Lifts on the roof hinges; the struts extend |
| Two headlight pods | Rotate up out of the nose |
| Four wheels | Spin; the front pair steer |
| Steering wheel | Turns with the steering |
| Speedometer, tachometer, fuel and temperature needles | Turn about the dial centre |
| Gear lever, handbrake, three pedals | Tilt about their base |
| Two wipers | Sweep about their spindles |

## Blender and Studio

The game's car is moved by code and holds no physics (DECISIONS.md, 2026-11-03), so nothing gets a physics hinge or a Blender armature.

| Blender | Studio |
|---|---|
| All geometry | Opening and closing: code turns each part about its pivot |
| Every moving part as its own mesh, origin on its hinge line | The open angles and timing |
| Test poses at full open, to prove nothing clips | Needles from speed and revs; the steering wheel from the steering |
| UVs, textures, a shared atlas | Lights: glow on and off, headlight beams, brake and indicator lamps |
| Export, one file per part group | Wheels spinning and steering, which the game already does |

## Not settled

- **The car contract.** Today a car is a `Body` and four `Wheel*` groups (CONTRACTS.md). Parts that open need groups of their own; that change goes in first, as its own commit, when the model is wired in. The user: "we will adjust the game later to work with a car like this".
- **Differences between the references** for the build to settle, not copy: eight spokes on the wheels (the wheel sheet), and the instrument sheet's four dials over the dashboard view's simpler cluster.
- **Surfaces:** materials, textures or a mix is decided at the surfaces stage (ART-DIRECTION.md "Surfaces" is still unset).
