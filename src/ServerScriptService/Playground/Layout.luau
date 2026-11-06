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

-- THE TEST HILL: twenty pieces of the REAL endless road, ten up and ten down, built
-- permanently so the user can judge a climb and a descent without starting a run
-- (features/test-hill.md, T-065). It is the one feature in this world that is not made of
-- ribbons: `Shared/Road/Pieces` places it and `Shared/Road/Builder` turns it into parts,
-- exactly as a run does, because a hand-built slope would answer a different question.
--
-- WHERE IT IS: off the SOUTH edge of the plate (-Z), pushed as far towards +X as it fits,
-- which is the side the hand-placed track is on (`Config.Drift.PlaygroundOffsetFromTrack`
-- is -2024 on X, so the track is +X of this world). It cannot literally be beside the
-- track -- the track exists only in `DR-Main` and git never sees it -- so this is the
-- corner of the playground nearest to where one would be. It has a PLATE OF ITS OWN
-- (`pad`) because 5 136 studs of road does not fit on a 2 000-stud square that already
-- has a district, a bowl and a ramp on it.
--
-- WHY THESE TWENTY PIECES. Two facts about the piece set decide almost everything:
--
--   * `Link` is the ONLY piece that climbs, and it hands on +7 degrees. `Corkscrew` is
--     the only one that sets a descent, and it hands on -5. Everything else CARRIES the
--     grade it arrived at (`Config.Road.Pieces`, "the road's height is a state machine").
--     So the climb is at 7 degrees and the descent at 5, and ten pieces up gain MORE than
--     ten pieces down lose unless the descent is built of longer pieces. It is: the climb
--     leans on hairpins and chicanes (196 to 220 studs) and the descent on corners and
--     sweepers (314 to 346).
--   * The exit has to arrive LEVEL as well as low, and only `Banked30` and `HairpinStack`
--     end level (`EndGrade = 0`). Hence `Banked30R` last -- which also puts the one banked
--     piece in the set where the user will certainly drive it.
--
-- Measured, placed from this list (the heights are studs above the plate):
--
--   piece            grade      top at the end
--    1 Link          +3.5 deg       14.7   (blending from level to +7)
--    2 Straight      +7.0           41.8
--    3 HairpinR      +7.0           68.8
--    4 ChicaneR      +7.0           92.8
--    5 HairpinL      +7.0          119.8
--    6 ChicaneR      +7.0          143.8
--    7 Link          +7.0          161.0
--    8 SweeperR      +7.0          199.5
--    9 Link          +7.0          216.7
--   10 CornerL       +7.0          259.1   <- THE TOP, where the lift button puts you
--   11 CorkscrewL    -4.9          239.2   (8.8 deg at its steepest: the floor leaving)
--   12 CornerL       -5.0          208.9
--   13 HairpinStackR -5.2          168.9   (the switchback, 40 studs in one piece)
--   14 CorkscrewR    -4.9          148.9
--   15 CornerL       -5.0          118.7
--   16 SweeperR      -5.0           91.2
--   17 HairpinL      -5.0           72.0
--   18 SweeperR      -5.0           44.5
--   19 CornerR       -5.0           14.3
--   20 Banked30R     -3.8            0.25  <- the plate's own kerb height, exactly
--
-- All nine piece kinds appear, six of them in the climb. No two pieces overlap. It is
-- 5 136 studs of road, about 2 700 parts, and it tops out 259 studs above the plate.
--
-- THE START HEIGHT IS NOT WRITTEN DOWN, and that is deliberate: `PlaygroundService` places
-- the whole hill once at zero simply to read what it comes to, then places it again at the
-- height that lands its LAST piece on `Surface.height`. So the exit is pinned to the plate
-- by construction and the entry floats to wherever it must be -- 6.1 studs, today -- with
-- a short ramp under it. Change a piece in this list and the hill still meets the ground.
Layout.Hill = {
	id = "Hill",
	-- The first socket, and which way it points. Heading 0 faces -Z: straight off the
	-- plate's southern edge, away from everything.
	--
	-- `x` IS AS FAR TOWARDS THE TRACK AS IT CAN SAFELY GO, and the limit is not the
	-- geometry, it is `CarService:WorldAt`. That decides which world a position is in by
	-- which world's SPAWN is nearer, and the line between the playground's spawn and a
	-- track's falls at about x = +1 010 in these coordinates -- the plate's own eastern
	-- edge, which is where the two worlds meet, so that is right. A hill that crossed it
	-- would have a car falling off its eastern side respawn on the kart track. At 190 the
	-- pad reaches x = 957 and the whole hill is on the playground's side with about 50
	-- studs to spare at its worst point.
	x = 190,
	z = -1030,
	heading = 0,
	climbPieces = 10, -- the first N are the climb; piece N+1 is where the lift puts you
	pieces = {
		"Link",
		"Straight",
		"HairpinR",
		"ChicaneR",
		"HairpinL",
		"ChicaneR",
		"Link",
		"SweeperR",
		"Link",
		"CornerL",
		"CorkscrewL",
		"CornerL",
		"HairpinStackR",
		"CorkscrewR",
		"CornerL",
		"SweeperR",
		"HairpinL",
		"SweeperR",
		"CornerR",
		"Banked30R",
	},
	-- The ramp off the plate up to the road's first socket. Its LENGTH comes out of the
	-- rise, so it is the same grade whatever the pieces come to; `minLength` stops a small
	-- rise becoming a lip. A smoothstep is steepest in the middle at 1.5x its average, so
	-- `grade` 5 peaks at 7.5 -- about what the hill itself climbs at.
	approach = {
		grade = 5, -- degrees, mean
		minLength = 80, -- studs
		minThickness = 10,
		segments = 24,
	},
	-- The hill's own ground. Sized to the hill's own footprint at build time, so it is
	-- never bigger than it has to be, and it meets the playground's plate at its southern
	-- edge rather than leaving a seam to drop through.
	pad = {
		margin = 180, -- studs of ground outside the road, for running off and landing on
		meet = 2, -- studs it overlaps the playground's own plate by
		colour = "HillPad",
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
