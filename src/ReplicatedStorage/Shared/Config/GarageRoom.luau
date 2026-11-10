--!strict
-- Config.GarageRoom: where the garage interior is, what it may cost, and its grey-box
-- colours (docs/game/features/car-customization.md, docs/game/WORLD.md "Garage").
--
-- The room's own geometry -- walls, props, the turntable, the named points -- lives in
-- ServerScriptService/GarageRoom/Layout.luau, written about the room's own origin. This
-- module holds only where that origin is in the world, and the numbers a test asserts.

return {
	-- WHERE IT IS. The centre of the turntable, on the garage floor. In the playground's open
	-- yard near its west edge, where the user moved it by hand in DR-Lane4 on 2026-11-10
	-- ("i remove the outside and move the garage to the main area of the playground").
	-- X, Z and the turn are theirs. Y is a quarter stud, not the 0.871 the drag left it at:
	-- every drivable feature sits a quarter stud proud of the plate (Playground/Layout), so
	-- the car meets a kerb it can take rather than a 0.87 step.
	Origin = Vector3.new(-717, 0.25, 0),
	-- Which way the room faces, in degrees about Y. At 180 the roller door is on the room's
	-- +X side in the world, facing the yard, and a car comes in heading -X.
	Yaw = 180,

	-- Asserted by GarageRoomTests: the whole room and the street before its door.
	PartBudget = 700,

	-- The largest step the car meets between the floor and the turntable's deck, studs.
	-- The playground's kerb is a quarter stud and the drift model takes it; so does this.
	MaxStep = 0.25,

	-- Grey-box colours, read off the picked concept (assets/garage-concept/garage-01.png):
	-- concrete greys with teal steel and orange accents, a dusk sky through the door.
	Palette = {
		Floor = Color3.fromRGB(122, 118, 116),
		Wall = Color3.fromRGB(150, 145, 140),
		WallDark = Color3.fromRGB(96, 92, 92),
		Roof = Color3.fromRGB(58, 56, 60),
		Teal = Color3.fromRGB(38, 140, 136),
		TealDark = Color3.fromRGB(28, 98, 98),
		Orange = Color3.fromRGB(232, 120, 40),
		Red = Color3.fromRGB(190, 70, 56),
		Wood = Color3.fromRGB(196, 150, 96),
		Steel = Color3.fromRGB(170, 172, 176),
		SteelDark = Color3.fromRGB(80, 82, 88),
		Tyre = Color3.fromRGB(40, 40, 44),
		Rim = Color3.fromRGB(196, 198, 202),
		Box = Color3.fromRGB(200, 170, 128),
		Light = Color3.fromRGB(250, 248, 236),
		Deck = Color3.fromRGB(104, 102, 104),
		DeckLine = Color3.fromRGB(72, 70, 74),
		Street = Color3.fromRGB(70, 68, 82),
		Rail = Color3.fromRGB(190, 186, 200),
		Silhouette = Color3.fromRGB(62, 52, 86),
		SilhouetteFar = Color3.fromRGB(92, 70, 112),
		Window = Color3.fromRGB(250, 170, 90),
		-- The dusk sky, bottom band to top.
		Sky = {
			Color3.fromRGB(240, 132, 92),
			Color3.fromRGB(212, 100, 112),
			Color3.fromRGB(150, 84, 136),
			Color3.fromRGB(96, 70, 128),
			Color3.fromRGB(60, 50, 100),
		},
		GlassDusk = Color3.fromRGB(128, 92, 150),
	},

	-- The strip lights: a SurfaceLight under each, so the room is lit whatever the
	-- place's own Lighting is doing.
	LightBrightness = 1.6,
	LightRange = 20,
}
