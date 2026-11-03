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
	PartBudget = 1500,

	-- Placeholder colours only (ART-DIRECTION.md: no art is generated for this world).
	Palette = {
		Plate = Color3.fromRGB(104, 112, 120),
		Road = Color3.fromRGB(74, 78, 84),
		Corner = Color3.fromRGB(86, 96, 110),
		Hairpin = Color3.fromRGB(96, 84, 110),
		SBend = Color3.fromRGB(80, 104, 104),
		Circle = Color3.fromRGB(88, 92, 70),
		Berm = Color3.fromRGB(118, 94, 66),
		Ramp = Color3.fromRGB(120, 104, 60),
		BrakeMarker = Color3.fromRGB(196, 62, 48),
		SpotMarker = Color3.fromRGB(240, 196, 48),
		Cone = Color3.fromRGB(226, 94, 32),
		ConeStripe = Color3.fromRGB(236, 236, 236),
	},
}
