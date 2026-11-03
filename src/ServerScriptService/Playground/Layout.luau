--!nonstrict
-- Layout: every position and size in the playground, and nothing else.
-- The builder reads this and makes the parts; no coordinate lives anywhere else
-- (docs/workflow/WORLD-BUILDING.md "Rules", features/drift-playground.md).
--
-- Heights are studs above the plate's top (Y = 0). The course is a chain: each step
-- starts where the last one ended, so the surface is continuous by construction and
-- moving one feature moves everything after it.

local Layout = {}

-- The plate. Its top is Y = 0, in every lane and in the Main place.
Layout.Plate = {
	size = 2000, -- studs square
	thickness = 8,
}

-- The road sits a quarter stud proud of the plate, so a downward ray never has to
-- choose between two coincident faces, and running wide is a kerb, not a cliff.
Layout.Road = {
	width = 60,
	thickness = 3,
	height = 0.25,
}

-- Where the course begins, and which way it faces (0 degrees faces -Z).
Layout.Start = { x = -460, z = 700, heading = 0 }

-- The chain. Each step is one feature or one link between features.
--   straight: length
--   arc:      angle (positive turns left), radius
--   segments: how many parts the surface is made of. A corner is at least 24 and the
--             circle 48, so a ray walking the surface never reads a step
--             (PITCH.md "Biggest risks": fidelity must beat the low-poly look).
--   height:   { shape = "flat" | "crest" | "ramp", peak = , to = } in studs above the
--             road's height. "crest" returns to where it started; "ramp" ends at `to`.
--   bank:     { shape = "flat" | "crest", degrees = }, the outer edge raised.
--   spot:     the named spot that sits at this step's start.
Layout.Course = {
	{
		id = "Straight",
		kind = "straight",
		length = 620,
		segments = 4,
		colour = "Road",
		spot = "StraightStart",
		spotAt = 0.1,
		-- Boards either side of the road, this far before the corner.
		brakeMarkers = { 150, 250, 350 },
	},
	{
		id = "Corner",
		kind = "arc",
		angle = -90,
		radius = 150,
		segments = 32,
		colour = "Corner",
		spot = "CornerEntry",
		height = { shape = "crest", peak = 4 },
	},
	{ id = "Link1", kind = "straight", length = 210, segments = 2, colour = "Road" },
	{
		id = "Hairpin",
		kind = "arc",
		angle = -180,
		radius = 62,
		segments = 48,
		colour = "Hairpin",
		spot = "HairpinEntry",
	},
	{ id = "Link2", kind = "straight", length = 190, segments = 2, colour = "Road" },
	{
		id = "SBendA",
		kind = "arc",
		angle = 72,
		radius = 120,
		segments = 24,
		colour = "SBend",
		spot = "SBendEntry",
	},
	{ id = "SBendMid", kind = "straight", length = 50, segments = 1, colour = "SBend" },
	{ id = "SBendB", kind = "arc", angle = -72, radius = 120, segments = 24, colour = "SBend" },
	{ id = "Link3", kind = "straight", length = 170, segments = 2, colour = "Road" },
	-- The berm is the expensive one. A box can bank but it cannot twist, so where the
	-- bank changes, two neighbouring segments disagree at the road's edge by
	-- (half the width) x (the bank change over one segment). Its three numbers are set
	-- by that: a long arc so the outer edge climbs gently, a modest bank, and far more
	-- segments than a flat corner. At 60 studs wide, 12 degrees and 192 segments the
	-- disagreement at the edge is under a tenth of a stud. Its bank rolls in and out of
	-- nothing, and the centre line lifts with it so the inner edge stays level with the
	-- road: the berm is a bowl to lean on, not a wall.
	{
		id = "Berm",
		kind = "arc",
		angle = -90,
		radius = 160,
		segments = 192,
		colour = "Berm",
		bank = { shape = "crest", degrees = 12 },
	},
	{ id = "Link4", kind = "straight", length = 150, segments = 2, colour = "Road" },
	{
		id = "Ramp",
		kind = "straight",
		length = 130,
		segments = 32,
		colour = "Ramp",
		spot = "RampBase",
		height = { shape = "ramp", to = 11 },
	},
	{ id = "RampLip", kind = "straight", length = 18, segments = 1, colour = "Ramp" },
}

-- The constant-radius circle stands on its own: drive on to it from the plate and hold
-- one slide. Its inner edge is flush with the plate, so the bank raises the outer edge.
Layout.Circle = {
	id = "Circle",
	centre = { x = 320, z = 300 },
	radius = 150, -- to the middle of the road
	width = 60,
	segments = 48,
	bank = 4, -- degrees, outer edge up
	colour = "Circle",
	spot = "CircleCentre",
}

-- Where the player and their car start: a little before the straight proper.
Layout.Spawn = { step = "Straight", at = 0.02 }

-- A spot marker stands this high, and a spot's CFrame sits this far above its surface.
Layout.Spot = {
	height = 3,
	markerSize = { x = 3, y = 14, z = 3 },
}

Layout.BrakeMarker = {
	size = { x = 2, y = 10, z = 2 },
	offset = 38, -- from the centre line, out past the road's edge
}

-- Cones: scattered along the course from a fixed seed, so every lane gets the same
-- scatter. They are the one thing physics may touch and are never tagged DriftSurface.
Layout.Cones = {
	count = 64,
	seed = 20261103,
	size = { x = 2.4, y = 4, z = 2.4 },
	lateralMin = 12, -- never on the exact centre line
	lateralMax = 44, -- out past the road's edge, so a wide line clips them
	skipSteps = { Ramp = true, RampLip = true }, -- nothing to hit on the launch
}

return Layout
