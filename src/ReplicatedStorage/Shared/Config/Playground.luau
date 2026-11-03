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
		SpotMarker = Color3.fromRGB(240, 196, 48),
		Cone = Color3.fromRGB(226, 94, 32),
		ConeStripe = Color3.fromRGB(236, 236, 236),
	},
}
