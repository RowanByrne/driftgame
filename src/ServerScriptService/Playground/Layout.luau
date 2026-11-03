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
}

-- The ramp: the airborne case, and nothing more. Modest on purpose — 9 studs over 110,
-- eased in and out so the car never reads a crease — with a short flat lip to leave from.
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
	segments = 32,
	lip = { length = 16, segments = 2 },
	colour = "Ramp",
	spot = { name = "RampBase", at = 0.03 },
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
		{ x = -380, z = 290, radius = 40, count = 6 },
		{ x = -580, z = 150, radius = 60, count = 8 },
		{ x = 0, z = 280, radius = 50, count = 10 },
	},
}

return Layout
