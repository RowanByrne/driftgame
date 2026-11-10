--!nonstrict
-- CarKits: where body kits and interiors sit on each body, and what each kit piece is made
-- of (docs/game/features/car-customization.md "Body kits", "Interior"; T-105;
-- CONTRACTS.md "Customization", the slot rows). Drawn by `Drift/CarKits`.
--
-- The catalog (`Shared/Customization/Catalog`) says which piece a part puts in which slot
-- (`kit_wide` = `KitFront = "LipWide"`, ...); this says where the slot is and what the piece
-- looks like. Every shape here is PROGRAMMER ART: boxes and wedges in flat colours, a
-- placeholder until real parts are made (ART-PIPELINE.md). No real kit design is copied
-- (PLATFORM-RISKS.md "Copyright").
--
-- THE CAR'S FRAME. Everything is in the car's own frame, the one the shell's `Body` group
-- rides (origin `RideHeight` above the road, front -Z, right +X). The kit parts follow the
-- simulation's `Body` part, which `Drift/Render` puts exactly there every frame, lean and
-- suspension included.
--
-- A SLOT IS A FRAME AND A SPAN. Each slot is a CFrame in the car's frame (its origin) and a
-- span, a Vector3 of studs the slot covers. A piece's shapes are sized and placed in
-- fractions of that span, plus optional absolute studs, so one "front lip" fits every body:
--   size     = span * s + (sa or 0)
--   position = slot origin + span * p + (pa or 0)
-- Where each slot sits comes, in order, from:
--   1. the car's own `Shell` attributes, when it carries them: `<Slot>` (CFrame, the slot's
--      origin in the car's frame) and `<Slot>Size` (Vector3, its span; absent = the span the
--      rules below give). The way a modelled or rigged car says exactly where its kits go.
--   2. the rules in `Drift/CarKits` (`slots`), from the body's measured size -- the box
--      around its `Body` group's parts, or the block car's `Body` part -- the wheels'
--      places, and `Bodies[<the car's Body attribute>]` below (`Default` for any other).

local CarKits = {}

-- ---------------------------------------------------------------------- colours

CarKits.Colours = {
	trim = Color3.fromRGB(34, 35, 40), -- satin black plastic
	carbon = Color3.fromRGB(46, 48, 54),
	metal = Color3.fromRGB(150, 154, 162), -- the cage's tube
	seat = Color3.fromRGB(150, 30, 34), -- bucket seats: red cloth
	seatDark = Color3.fromRGB(28, 28, 32),
	wheel = Color3.fromRGB(24, 24, 26),
	carpet = Color3.fromRGB(60, 60, 66),
	cone = Color3.fromRGB(16, 16, 18),
}
-- `c = "body"` on a shape takes the car's body colour as drawn (its paint, or the body's own
-- when stock), so a flare or a ducktail is painted with the car.
CarKits.BodyColour = "body"

CarKits.Material = "SmoothPlastic" -- faceted and flat: programmer art

-- ---------------------------------------------------------------------- the bodies
--
-- Per body, the two places that are not the box's edges, as FRACTIONS of the measured box
-- (0 = its min, 1 = its max, along each of the car's axes; 0.5 across is the centreline):
--   deck    Vector3: where a spoiler stands -- the top of the boot or the tail. `x` unused.
--   cabin   { min, max }: the box inside the glasshouse the interior is drawn in, its
--           floor to the underside of the roof. The driver sits at +X (right-hand drive,
--           CONTRACTS.md "The car rig", `Seat`).
-- Read off each body's table (`Shared/Cars/Bodies`, `Shared/Cars/AE86`) on 2026-11-10; the
-- measured boxes, car frame, are in the comments.
--
-- Interiors draw inside the cabin box, so a body whose glasshouse is opaque (the three
-- closed parts bodies) hides most of one from outside; the slider is open and shows it.

CarKits.Bodies = {
	-- the box car: no cabin, so the "interior" stands on its roof, where it can be seen
	-- box x ±3.2, y -1.6..1.6, z ±7
	block = {
		deck = Vector3.new(0.5, 1.0, 0.9),
		cabin = { min = Vector3.new(0.1, 1.0, 0.36), max = Vector3.new(0.9, 1.75, 0.71) },
	},
	-- box x ±3.58, y -1.7..2.5, z -7.3..7.53. Deck top 1.15 at z 5.6; cabin z -1.8..3.6,
	-- floor 0.65 (the shoulder's top) to the roof's underside 2.15
	balanced = {
		deck = Vector3.new(0.5, 0.68, 0.87),
		cabin = { min = Vector3.new(0.09, 0.56, 0.37), max = Vector3.new(0.91, 0.92, 0.73) },
	},
	-- box x ±3.8, y -2.03..2.44, z -7.0..7.06. The fastback's tail top 1.0 at z 5.5; the
	-- canopy z -1.1..2.3, y 0..1.0 -- a low car, so its interior is small
	gripper = {
		deck = Vector3.new(0.5, 0.68, 0.89),
		cabin = { min = Vector3.new(0.18, 0.45, 0.42), max = Vector3.new(0.82, 0.68, 0.66) },
	},
	-- box x ±3.45, y -1.65..2.03, z -8.2..7.8. Deck top 1.15 at z 5.6; open: seats at
	-- y 0.6, the hoop's top at 1.95, z -0.9..2.2
	slider = {
		deck = Vector3.new(0.5, 0.76, 0.86),
		cabin = { min = Vector3.new(0.12, 0.61, 0.46), max = Vector3.new(0.88, 1.0, 0.65) },
	},
	-- box x ±3.7, y -1.8..3.5, z -8.23..8.5. Deck top 2.25 at z 6.0; cabin z -1.0..4.2,
	-- y 1.75..3.1
	bruiser = {
		deck = Vector3.new(0.5, 0.76, 0.85),
		cabin = { min = Vector3.new(0.08, 0.67, 0.43), max = Vector3.new(0.92, 0.92, 0.74) },
	},
	-- the imported placeholder: box x -3.59..3.68, y -1.89..2.82, z -8.09..8.52. A hatch:
	-- the spoiler stands on the hatch's top edge
	ae86 = {
		deck = Vector3.new(0.5, 0.74, 0.84),
		cabin = { min = Vector3.new(0.14, 0.36, 0.37), max = Vector3.new(0.86, 0.86, 0.67) },
	},
}
CarKits.Bodies.Default = CarKits.Bodies.balanced

-- ---------------------------------------------------------------------- the slots
--
-- How deep and tall each body-kit slot is, in studs; its width is the body's. Where its
-- origin goes is `Drift/CarKits.slots`:
--   KitFront    the front edge of the body's floor, on the centreline
--   KitRear     the rear edge of the body's floor
--   KitSkirts   the floor's centre, between the wheels; span x is the body's width, z the
--               gap between the arches (wheelbase - `ArchGap` x wheel diameter)
--   KitSpoiler  the deck point (`Bodies`)
--   KitFlares   the axles' midpoint at the wheels' centre height; span = the body's width,
--               a wheel's diameter, the wheelbase, so p = (±0.5, _, ±0.5) is on a wheel
--   Interior*   all four share the cabin box (`Bodies`): origin its floor's centre, span
--               its size
CarKits.Spans = {
	KitFront = { height = 0.6, depth = 1.0 },
	KitRear = { height = 0.8, depth = 1.0 },
	KitSkirts = { height = 0.6 },
	KitSpoiler = { height = 1.0, depth = 1.4 },
}
CarKits.ArchGap = 1.3

CarKits.Slots = {
	BodyKit = { "KitFront", "KitRear", "KitSkirts", "KitSpoiler", "KitFlares" },
	Interior = { "InteriorCage", "InteriorSeat", "InteriorWheel", "InteriorAudio" },
}

-- ---------------------------------------------------------------------- the pieces
--
-- Each piece the catalog names: the slot it goes in and its shapes. A shape:
--   k     "box" (default) or "wedge" (a WedgePart: tall at +Z, the back, low at -Z)
--   s/sa  size: fraction of the span, plus absolute studs
--   p/pa  centre: fraction of the span from the slot's origin, plus absolute studs
--   r     rotation in degrees (x, y, z), about the shape's own centre
--   c     a `Colours` name, or "body"
--   mx    also the mirror image across the centreline (x -> -x)
--   mz    also the mirror image front to back (z -> -z), for flares
--         (a mirror is a move, not a turn: keep mirrored shapes to unturned boxes)
-- `with` names another piece whose shapes come first (the full cage is the half cage and
-- more).

local V = Vector3.new
local TUBE = 0.18 -- a cage tube, studs square

CarKits.Pieces = {
	-- front: a splitter lip under the nose
	LipSmall = {
		slot = "KitFront",
		shapes = {
			{ s = V(0.9, 0.35, 0.7), p = V(0, 0.15, -0.2), c = "trim" },
		},
	},
	LipWide = {
		slot = "KitFront",
		shapes = {
			{ s = V(1.0, 0.4, 0.9), sa = V(0.3, 0, 0), p = V(0, 0.18, -0.3), c = "carbon" },
			-- a canard each side, on the bumper's corner
			{ s = V(0.08, 0, 0.5), sa = V(0, 0.12, 0), p = V(0.47, 1.1, 0.25), c = "carbon", mx = true },
		},
	},
	-- rear: a diffuser, a plate and four fins
	Diffuser = {
		slot = "KitRear",
		shapes = {
			{ s = V(0.8, 0.25, 0.9), p = V(0, 0.12, 0.05), c = "carbon" },
			{ s = V(0, 0.6, 0.9), sa = V(0.14, 0, 0), p = V(0.12, 0.45, 0.05), c = "carbon", mx = true },
			{ s = V(0, 0.6, 0.9), sa = V(0.14, 0, 0), p = V(0.3, 0.45, 0.05), c = "carbon", mx = true },
		},
	},
	-- side skirts: a sill along each side between the arches
	Skirts = {
		slot = "KitSkirts",
		shapes = {
			{ s = V(0, 0.8, 1.0), sa = V(0.45, 0, 0), p = V(0.5, 0.4, 0), c = "trim", mx = true },
		},
	},
	-- spoilers
	WingHigh = {
		slot = "KitSpoiler",
		shapes = {
			{ s = V(0, 1.15, 0.3), sa = V(0.22, 0, 0), p = V(0.3, 0.58, 0), c = "trim", mx = true },
			{ s = V(0.98, 0, 0.9), sa = V(0, 0.14, 0), p = V(0, 1.2, 0.05), c = "body" },
			{ s = V(0, 0.55, 1.05), sa = V(0.1, 0, 0), p = V(0.49, 1.15, 0.05), c = "trim", mx = true },
		},
	},
	Ducktail = {
		slot = "KitSpoiler",
		shapes = {
			{ k = "wedge", s = V(0.94, 0.4, 0.6), p = V(0, 0.2, 0.15), c = "body" },
		},
	},
	-- fender flares: one over each wheel, outside the body's side
	Flares = {
		slot = "KitFlares",
		shapes = {
			{ s = V(0, 0.55, 0.36), sa = V(0.45, 0, 0), p = V(0.5, 0.42, 0.5), c = "body", mx = true, mz = true },
			-- the flare's lower lip, darker, so the arch reads
			{ s = V(0, 0.12, 0.36), sa = V(0.5, 0, 0), p = V(0.5, 0.12, 0.5), c = "trim", mx = true, mz = true },
		},
	},

	-- interior: the cabin box, origin its floor's centre, front -Z, the driver at +X
	Bucket = {
		slot = "InteriorSeat",
		shapes = {
			{ s = V(0.24, 0.22, 0.26), p = V(0.24, 0.11, 0.12), c = "seat", mx = true }, -- cushion
			{ s = V(0.24, 0.72, 0), sa = V(0, 0, 0.3), p = V(0.24, 0.48, 0.27), c = "seat", mx = true }, -- back
			{ s = V(0.03, 0.72, 0.28), p = V(0.36, 0.4, 0.17), c = "seatDark", mx = true }, -- outer bolster
			{ s = V(0.03, 0.72, 0.28), p = V(0.12, 0.4, 0.17), c = "seatDark", mx = true }, -- inner bolster
		},
	},
	DeepDish = {
		slot = "InteriorWheel",
		-- a square-ish ring and its column, in front of the driver (+X)
		shapes = {
			{ s = V(0.17, 0, 0), sa = V(0, 0.14, 0.14), p = V(0.24, 0.78, -0.2), c = "wheel" },
			{ s = V(0.17, 0, 0), sa = V(0, 0.14, 0.14), p = V(0.24, 0.38, -0.2), c = "wheel" },
			{ s = V(0, 0.4, 0), sa = V(0.14, 0.14, 0.14), p = V(0.155, 0.58, -0.2), c = "wheel" },
			{ s = V(0, 0.4, 0), sa = V(0.14, 0.14, 0.14), p = V(0.325, 0.58, -0.2), c = "wheel" },
			{ s = V(0, 0, 0.22), sa = V(0.16, 0.16, 0), p = V(0.24, 0.58, -0.32), c = "wheel" }, -- the column
		},
	},
	HalfCage = {
		slot = "InteriorCage",
		-- the main hoop behind the seats, and a bar back to the rear
		shapes = {
			{ s = V(0, 0.96, 0), sa = V(TUBE, 0, TUBE), p = V(0.44, 0.48, 0.36), c = "metal", mx = true },
			{ s = V(0.88, 0, 0), sa = V(TUBE, TUBE, TUBE), p = V(0, 0.95, 0.36), c = "metal" },
			{ s = V(0, 0, 0.14), sa = V(TUBE, TUBE, 0), p = V(0.44, 0.95, 0.43), c = "metal", mx = true },
			{ s = V(0.88, 0, 0), sa = V(TUBE, TUBE, TUBE), p = V(0, 0.45, 0.36), c = "metal" }, -- harness bar
		},
	},
	FullCage = {
		slot = "InteriorCage",
		with = "HalfCage",
		-- the front hoop up the screen pillars, roof rails, and a door bar each side
		shapes = {
			{ s = V(0, 0.96, 0), sa = V(TUBE, 0, TUBE), p = V(0.44, 0.48, -0.36), c = "metal", mx = true },
			{ s = V(0.88, 0, 0), sa = V(TUBE, TUBE, TUBE), p = V(0, 0.95, -0.36), c = "metal" },
			{ s = V(0, 0, 0.72), sa = V(TUBE, TUBE, 0), p = V(0.44, 0.95, 0), c = "metal", mx = true },
			{ s = V(0, 0, 0.72), sa = V(TUBE, TUBE, 0), p = V(0.44, 0.35, 0), c = "metal", mx = true },
		},
	},
	SubBox = {
		slot = "InteriorAudio",
		-- a sub box behind the seats, two cones facing forward
		shapes = {
			{ s = V(0.5, 0.42, 0.14), p = V(0, 0.21, 0.42), c = "carpet" },
			{ s = V(0.13, 0.3, 0), sa = V(0, 0, 0.06), p = V(0.12, 0.21, 0.35), c = "cone", mx = true },
		},
	},
}

return CarKits
