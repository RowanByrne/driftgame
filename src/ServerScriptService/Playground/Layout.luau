--!nonstrict
-- Layout: every position and size in the playground, and nothing else.
-- The builder reads this and makes the parts; no coordinate lives anywhere else
-- (docs/workflow/WORLD-BUILDING.md "Rules", features/drift-playground.md).
--
-- The world is an open testing ground, not a course: a flat plate, an open yard with
-- the spawn in the middle of it, a district of blocky buildings making streets and
-- alleys to pick your own line through, and exactly two elevated features — one banked
-- circle and one ramp — because the drift model needs a banked surface and an airborne
-- case (features/drift-model.md "Rules and numbers" -> Ground). Everything else is flat.
--
-- Heights are studs above the plate's top, which is Y = 0 in every lane and place.
-- Headings are degrees: 0 faces -Z, -90 faces +X (Path.forward).

local Layout = {}

-- The plate. Deliberately thick: the banked circle and the ramp are solid prisms whose
-- undersides are buried in it, so neither shows daylight under a raised edge.
Layout.Plate = {
	size = 2000,
	thickness = 24,
}

-- Every drivable feature sits a quarter stud proud of the plate, so a downward ray never
-- has to choose between two coincident faces, and running wide is a kerb, not a cliff.
Layout.Surface = {
	height = 0.25,
}

-- Where the player starts: the middle of the open yard, facing the district.
Layout.Spawn = { x = -160, z = -75, heading = -90 }

-- The open yard: the rectangle of plate with no buildings on it. Scattered pillars,
-- blocks and cones stand in it; nothing at all stands within `clearRadius` of the spawn,
-- so the first thing the player sees is room.
Layout.Open = {
	minX = -800,
	maxX = 200,
	minZ = -380,
	maxZ = 360,
	clearRadius = 200,
}

-- The district. Buildings are the cross product of three X strips and five Z strips; the
-- gaps between the strips are the streets. Nothing here is drivable-tagged: a building is
-- a wall, and the car's ground ray must miss it.
--   X gaps:  56 and 76 studs — alleys running along Z
--   Z gaps: 44, 110, 44 and 50 studs — streets running along X; the 110 is the boulevard
--           the spawn faces, and the 44s are the ones that punish.
Layout.District = {
	columns = {
		{ from = 200, to = 300 },
		{ from = 356, to = 460 },
		{ from = 536, to = 628 },
	},
	rows = {
		{ from = -330, to = -230 },
		{ from = -186, to = -130 },
		{ from = -20, to = 76 },
		{ from = 120, to = 216 },
		{ from = 266, to = 350 },
	},
	-- Height of a building = its row's base plus its column's bump, so the skyline is
	-- varied but repeatable, and tall enough to read from the far side of the yard.
	rowHeight = { 72, 44, 104, 60, 118 },
	columnBump = { 0, 22, -12 },
	colours = { "BuildingDark", "BuildingLight" }, -- alternating, for value contrast
}

-- Expand the grid into explicit rectangles once, at load. Everything downstream — the
-- builder and the tests — reads this list, so a building is a coordinate like any other.
Layout.Buildings = {}
for ci, col in Layout.District.columns do
	for ri, row in Layout.District.rows do
		table.insert(Layout.Buildings, {
			id = `Block_{ci}_{ri}`,
			x = (col.from + col.to) * 0.5,
			z = (row.from + row.to) * 0.5,
			sizeX = col.to - col.from,
			sizeZ = row.to - row.from,
			height = Layout.District.rowHeight[ri] + Layout.District.columnBump[ci],
			colour = Layout.District.colours[(ci + ri) % 2 + 1],
		})
	end
end

-- Two standalone blocks out in the yard: something to swing round, and something for the
-- eye to measure speed against where there are no buildings.
Layout.Blocks = {
	{ id = "Yard_Shed", x = -560, z = -280, sizeX = 90, sizeZ = 60, height = 30, colour = "BuildingLight" },
	{ id = "Yard_Hall", x = 60, z = 160, sizeX = 70, sizeZ = 70, height = 36, colour = "BuildingDark" },
}

-- Standalone pillars, all at least `Open.clearRadius` from the spawn: posts to swing
-- round in the open, and the nearest thing to a slalom the world has.
Layout.Pillars = {
	{ id = "Pillar_1", x = -480, z = -180, radius = 9, height = 44 },
	{ id = "Pillar_2", x = -560, z = 60, radius = 9, height = 52 },
	{ id = "Pillar_3", x = -420, z = 200, radius = 9, height = 38 },
	{ id = "Pillar_4", x = -620, z = -260, radius = 11, height = 60 },
	{ id = "Pillar_5", x = 10, z = -300, radius = 9, height = 46 },
	{ id = "Pillar_6", x = 60, z = 220, radius = 9, height = 40 },
	{ id = "Pillar_7", x = -250, z = 300, radius = 9, height = 50 },
	{ id = "Pillar_8", x = -300, z = -300, radius = 9, height = 42 },
}

-- The banked circle: drive on to it from the plate and hold one slide. Its inner edge is
-- flush with the plate and the bank raises the outer edge by width x sin(bank), about
-- 8.4 studs. A part can bank but it cannot twist, and at a joint two neighbouring boxes'
-- outer corners pull apart by (half the width) x (the yaw step): the builder closes that
-- by lengthening each box by exactly that much, and 96 segments keeps what is left under
-- a tenth of a stud. `thickness` is what stops the raised outer edge floating: at 14 it
-- is buried in the plate the whole way round.
Layout.Circle = {
	id = "Circle",
	centre = { x = -420, z = -560 },
	radius = 150, -- to the middle of the band
	width = 60,
	thickness = 14,
	segments = 96,
	bank = 8, -- degrees, outer edge up
	colour = "Circle",
	spot = { name = "CircleCentre", heading = -90 },
	-- The apron outside the band. The band's rim stands `width x sin(bank)` -- 8.35 studs
	-- -- above the plate, which is a wall and not a kerb: once drivable parts had sides
	-- (T-026) the only way on to the bowl would have been over that wall, and before they
	-- had sides the car went straight through it and was thrown 144 studs into the air.
	-- This is a second ring banked the other way, its outer edge level with the plate and
	-- its inner edge exactly on the rim, so the bowl can be driven on to from any side.
	skirt = { width = 80, thickness = 14, segments = 96, colour = "Circle" },
}

-- Derived, so the apron can never drift away from the band it has to meet.
--
-- `rise` is how far the band's rim stands above the plate, and the apron's bank is
-- whatever puts its own raised edge at exactly that height. Its radius is worked out from
-- the two edges' HORIZONTAL reach, not from the nominal widths: a banked band of width w
-- only covers w x cos(bank) of ground, and taking the widths at face value left a
-- half-stud slot between the two rings, two studs deep, with a near-vertical face in it
-- that a ground ray reads as a surface climbing nine times faster than the car is going
-- (T-026). `overlap` buries the apron's inner edge inside the band instead.
Layout.Circle.skirt.overlap = 0.5
Layout.Circle.skirt.rise = Layout.Circle.width * math.sin(math.rad(Layout.Circle.bank))
Layout.Circle.skirt.bank = math.deg(math.asin(Layout.Circle.skirt.rise / Layout.Circle.skirt.width))
Layout.Circle.skirt.radius = Layout.Circle.radius
	+ Layout.Circle.width * 0.5 * math.cos(math.rad(Layout.Circle.bank))
	- Layout.Circle.skirt.overlap
	+ Layout.Circle.skirt.width * 0.5 * math.cos(math.rad(Layout.Circle.skirt.bank))

-- The ramp: the airborne case, and nothing more. Modest on purpose — 9 studs over 110 —
-- eased in at the bottom and STEEPEST AT THE TOP, with a lip that carries straight on at
-- that slope. It was eased out as well, and a car reached the flat lip travelling level
-- and simply fell off the end: 179 studs/s off it reached 11.7 studs, which is the height
-- of the ramp itself (T-026). `launch` is the shape that makes it a jump.
-- It is a solid prism too, for the same reason as the circle.
Layout.Ramp = {
	id = "Ramp",
	x = -380,
	z = 370,
	heading = 180, -- driven in +Z, approached straight off the open yard
	width = 60,
	thickness = 14,
	length = 110,
	rise = 9,
	shape = "launch",
	segments = 32,
	lip = { length = 16, segments = 2 },
	colour = "Ramp",
	spot = { name = "RampBase", at = 0.03 },
}

-- THE BODY PAD: shapes to drive the car's body over (features/car-body-physics.md, T-196).
-- A ledge, a ramp and a kerb do nothing special to the car -- its four springs take each as
-- ground under a wheel -- and this is where that is driven and measured. Three lanes side
-- by side in the yard, each driven in +Z from the `BodyPad` spot:
--
--   the LEDGE lane   a long easy climb to a deck 2.5 studs up that simply ends, then,
--                    past where a fast car lands, a second one 1 stud up: drive off the
--                    end and the car falls
--   the RAMP lane    a low ramp and deck under ONE side's wheels only, which tips the car
--                    (or, slid across sideways, lifts the rear and leaves the front on the
--                    ground); then a short steep kicker that ends in the air, last in its
--                    lane because at speed it carries the car 60 studs
--   the KERB lane    a 0.3 kerb under one side, a 0.3 kerb right across, a 0.6 kerb under
--                    the other side, and a 1-stud kerb with sloped faces (1 up over 3, the
--                    shape of the endless road's gravel edge -- but a real slope, which
--                    throws a wheel that meets it square on; the road's own edge reads as
--                    level ground to the car and is driven on the test road)
--
-- Every piece is a box or a slope: `dx` is its middle across the pad (+X), `dz` its near
-- edge along the drive, `from` and `to` the height of its top at the near and far ends
-- (the same: a box; different: a slope). Nothing is 0.25 proud here, unlike the bowl and the
-- ramp: a slope starts flush with the plate, because a kerb at its foot would be one more
-- shape than the one being tested.
Layout.BodyPad = {
	id = "BodyPad",
	x = -135, -- the middle lane's centre line
	z = 200, -- where the lanes start
	colour = "Ramp",
	pieces = {
		{ name = "LedgeClimb", dx = -45, width = 36, dz = 0, length = 50, from = 0, to = 2.5 },
		{ name = "LedgeDeck", dx = -45, width = 36, dz = 50, length = 36, from = 2.5, to = 2.5 },
		{ name = "LowLedgeClimb", dx = -45, width = 36, dz = 130, length = 24, from = 0, to = 1 },
		{ name = "LowLedgeDeck", dx = -45, width = 36, dz = 154, length = 16, from = 1, to = 1 },

		{ name = "SideRamp", dx = 8, width = 12, dz = 20, length = 4, from = 0, to = 0.8 },
		{ name = "SideDeck", dx = 8, width = 12, dz = 24, length = 24, from = 0.8, to = 0.8 },
		{ name = "Kicker", dx = 0, width = 36, dz = 100, length = 12, from = 0, to = 2.5 },

		{ name = "KerbLeft", dx = 54, width = 18, dz = 30, length = 3, from = 0.3, to = 0.3 },
		{ name = "KerbAcross", dx = 45, width = 36, dz = 60, length = 3, from = 0.3, to = 0.3 },
		{ name = "KerbRight", dx = 36, width = 18, dz = 90, length = 3, from = 0.6, to = 0.6 },
		{ name = "SlopedKerbUp", dx = 54, width = 18, dz = 120, length = 3, from = 0, to = 1 },
		{ name = "SlopedKerbTop", dx = 54, width = 18, dz = 123, length = 8, from = 1, to = 1 },
		{ name = "SlopedKerbDown", dx = 54, width = 18, dz = 131, length = 3, from = 1, to = 0 },
	},
}

-- Named spots that are simply a place on the plate. The two that sit on a feature
-- (CircleCentre, RampBase) are declared with the feature instead.
Layout.Spots = {
	{ name = "Spawn", x = Layout.Spawn.x, z = Layout.Spawn.z, heading = Layout.Spawn.heading },
	{ name = "OpenGround", x = -400, z = 0, heading = -90 },
	{ name = "DistrictGate", x = 150, z = -75, heading = -90 },
	{ name = "Boulevard", x = 400, z = -75, heading = -90 }, -- the 110-stud street
	{ name = "TightAlley", x = 400, z = 98, heading = -90 }, -- the 44-stud one
	{ name = "PillarRun", x = -500, z = 0, heading = 0 },
	-- lined up on the body pad's lanes, 40 studs short of them: ledge, ramp, kerb
	{ name = "BodyPadLedge", x = Layout.BodyPad.x - 45, z = Layout.BodyPad.z - 40, heading = 180 },
	{ name = "BodyPad", x = Layout.BodyPad.x, z = Layout.BodyPad.z - 40, heading = 180 },
	{ name = "BodyPadKerbs", x = Layout.BodyPad.x + 45, z = Layout.BodyPad.z - 40, heading = 180 },
}

-- A spot's CFrame sits this far above its surface, and is shown by a flat disc on the
-- ground: never a pillar, because a marker in the driving line blocks the view.
Layout.Spot = {
	height = 3,
	markerDiameter = 26,
	markerThickness = 0.3,
}

-- Cones: clusters from a fixed seed, so every lane gets the same scatter. They are the
-- one thing physics may touch and are never tagged DriftSurface. Each is rested on
-- whatever is actually below it by a ray, so none hangs in the air over the plate.
Layout.Cones = {
	seed = 20261103,
	size = { x = 2.4, y = 4, z = 2.4 },
	clusters = {
		{ x = -340, z = 30, radius = 60, count = 10 },
		{ x = -480, z = -120, radius = 50, count = 8 },
		{ x = 150, z = -75, radius = 40, count = 8 },
		{ x = 328, z = -75, radius = 36, count = 6 },
		{ x = -420, z = -380, radius = 50, count = 8 },
		-- Moved out of the ramp's mouth (T-026). It was at (-380, 290), 80 studs square in
		-- front of it and 40 wide against the ramp's 60: a car making the only straight run
		-- at the ramp met a cone, and a cone stops a car dead -- 179 studs/s to nothing in
		-- 30 steps. The ramp was unreachable at speed.
		{ x = -250, z = 180, radius = 40, count = 6 },
		{ x = -580, z = 150, radius = 60, count = 8 },
		{ x = 0, z = 280, radius = 50, count = 10 },
	},
}

return Layout
