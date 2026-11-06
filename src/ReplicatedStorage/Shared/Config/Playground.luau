--!strict
-- Config.Playground: the playground's tuning and its placeholder colours.
-- Every position and size lives in ServerScriptService/Playground/Layout.luau instead
-- (docs/game/features/drift-playground.md "Rules and numbers"); nothing here is a coordinate.

return {
	-- Falling off
	FallY = -40, -- a car or character below this is put back at the Spawn spot
	FallCheckSeconds = 0.25,

	-- Cones. They are the one thing physics may touch, and they never touch the car's
	-- simulation: their own folder, never tagged DriftSurface.
	ConeResetSeconds = 20, -- how often knocked-about cones are put back
	ConeResetDistance = 2.5, -- a cone further than this from its spot is reset
	ConeResetTiltDegrees = 20, -- or leaning more than this
	ConeResetClearance = 30, -- but never while something is this close to it

	-- Budgets, asserted by PlaygroundTests
	PartBudget = 1500, -- the playground proper: plate, buildings, pillars, bowl, ramp, cones
	-- THE TEST HILL IS BUDGETED SEPARATELY, and it is bigger than everything else here put
	-- together (T-065). It is twenty-odd real road pieces, and a road piece that has a
	-- GRADE is cut into one box per `Config.Road.MaxPitchStep` of swing rather than being
	-- one long box: a flat straight is 1 segment and a straight on a 7-degree climb is 30,
	-- three parts apiece plus its centre-line dashes. So the hill costs about 130 parts a
	-- piece where the endless road's flat window costs about 36.
	--
	-- AND THEN THE SEAMS WERE TRIANGULATED (T-066) AND IT WENT UP BY THREE FIFTHS. Where a
	-- piece has grade and turn at once, two neighbouring boxes' top faces crossed and each
	-- stood proud of the other at the kerb; `Config.Road.TriangulateSegments` replaces each
	-- of those seams with two wedges that meet exactly. Measured on this hill: 2 723 parts
	-- before, 4 843 after, and the worst step at the kerb fell from 0.336 studs per stud to
	-- 0.169 -- inside the limit the CENTRE line is held to, where before it needed a looser
	-- one of its own.
	--
	-- It is a TESTING feature and it is permanent in every place, so the number is written
	-- down and asserted rather than left to grow: if a piece set change takes the hill past
	-- this, that is a thing to know about.
	HillPartBudget = 5500,

	-- Placeholder colours only (ART-DIRECTION.md: no art is generated for this world).
	-- They are chosen for *value* contrast against the plate, not for looks: the old
	-- course failed because road and ground were the same tone and the world vanished
	-- from the driver's seat. Buildings are far darker and far lighter than the plate,
	-- and alternate, so a street reads as a street at 800 studs.
	Palette = {
		Plate = Color3.fromRGB(104, 112, 120),
		BuildingDark = Color3.fromRGB(38, 42, 50),
		BuildingLight = Color3.fromRGB(206, 210, 214),
		Pillar = Color3.fromRGB(24, 26, 32),
		Circle = Color3.fromRGB(52, 58, 70),
		Ramp = Color3.fromRGB(208, 160, 52),
		-- The test hill's own ground. A shade off the plate's, on purpose: it is a
		-- different world's floor and the line where the two meet should be visible.
		HillPad = Color3.fromRGB(88, 96, 106),
		SpotMarker = Color3.fromRGB(240, 196, 48),
		Cone = Color3.fromRGB(226, 94, 32),
		ConeStripe = Color3.fromRGB(236, 236, 236),
	},
}
