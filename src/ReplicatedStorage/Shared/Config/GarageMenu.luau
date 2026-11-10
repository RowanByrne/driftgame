--!strict
-- Config.GarageMenu: the garage visit and its menus (docs/game/features/car-customization.md
-- "How it plays" and "UI", T-103).
--
-- Getting in (the door or the Garage button), the car parked on the turntable, the garage
-- camera, and the programmer-UI menus' sizes. The room itself is `Config.GarageRoom`; the
-- parts are `Shared/Customization`. A plain table with no write guard, like `Config.Road`,
-- so a Studio session can move a number and see it on the next frame.

return {
	-- THE VISIT ---------------------------------------------------------------------------

	-- The door's trigger, as a box in the ROOM'S frame (ServerScriptService/GarageRoom/
	-- Layout: origin the turntable's centre on the floor, the door in the -X wall at x = -26,
	-- the car coming in heading +X). It runs from the door's own plane through the whole
	-- bay, not a thin strip at the door: the server sees a car only at its 20 Hz packets, and
	-- a car at 180 studs/s covers 9 studs between two of them. A car the server believes is
	-- inside this box goes into the garage. `CarExit` (x = -40) is well outside it, so a car
	-- leaving is never pulled straight back in.
	Trigger = {
		minX = -26,
		maxX = 24,
		halfZ = 9, -- the door is 18 wide; the room's walls keep anything wider out anyway
		minY = -4,
		maxY = 10,
	},
	-- How often the server looks for cars at the door, seconds.
	TriggerPeriod = 0.1,

	-- Asks a second per UserId on `GarageVisit`, questions included; the rest are refused.
	RateLimit = 4,
	-- Seconds after leaving before the door or the button takes the same player in again.
	Cooldown = 1.5,

	-- The turntable, while somebody's car is on it: radians a second. A turn every ~42 s.
	SpinRate = 0.15,
	-- How often the server tells the other players where a parked, turning car is (they
	-- draw it from `CarStateOther`, like a driven one). Seconds.
	OthersPeriod = 0.1,

	-- THE CAMERA --------------------------------------------------------------------------

	-- Which named garage point frames each category. Close-ups turn with the turntable, so
	-- they stay on the wheel or the door while the car spins; the wide one stands still and
	-- watches the car go round.
	CameraFor = {
		Engine = "CamWide",
		Suspension = "CamUnderside",
		Wheels = "CamWheels",
		BodyKit = "CamWide",
		Underglow = "CamUnderside",
		Interior = "CamCabin",
		Paint = "CamWide",
	},
	CamFieldOfView = 60,
	-- How fast the camera eases to a new point: the share of the gap closed a second, as a
	-- rate (exp). 6 is about 0.4 s to settle.
	CamEase = 6,

	-- THE HUD BUTTON ----------------------------------------------------------------------
	-- Bottom right, in the row of the GET OUT button (Config.CarEntry: 96 x 48, 28 in from
	-- the right and 136 up) and 12 px to its left, so the left and the middle stay the
	-- steering finger's. Not stacked above it: on a 375-tall phone that put it over the
	-- tuner's button in the top right (measured on an iPhone 7 in the simulator).
	HudButtonSize = Vector2.new(96, 48),
	HudButtonMargin = 28 + 96 + 12,
	HudButtonAbove = 136,
	HudDisplayOrder = 13, -- above the drag pad's 5: a thumb here is a press
	HudText = "GARAGE",

	-- THE MENUS ---------------------------------------------------------------------------
	MenuDisplayOrder = 35, -- the menus band (CODING.md "UI layers")
	-- Other screens switched off while the menus are open, and put back as they were.
	HideGuis = { "DriftRun", "DriftTest", "DriftTuner", "DriftDebug" },

	Margin = 16, -- from the safe area's edges
	Gap = 8,
	TabHeight = 56, -- the bar; a tab inside it is 8 less, 48: a touch target
	TabMinWidth = 104,
	TabPadding = 28, -- either side of a tab's text, together
	RowHeight = 56,
	BarRowHeight = 24, -- one before/after bar under a performance part
	ButtonHeight = 52,
	FitWidth = 140,
	BackWidth = 112,
	DriveOutWidth = 148,
	SwatchSize = 52,
	ListWidthDesktop = 380,
	ListWidthCompact = 320,
	-- A screen this short or shorter is a phone in landscape: the list fills the height.
	CompactHeight = 520,
	-- Portrait: the list takes the bottom share of the screen, the car the top.
	PortraitListShare = 0.5,

	TextSize = 18,
	SmallTextSize = 16,
}
