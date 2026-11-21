--!strict
-- Config.GroundLook: how the drawn mountain's ground is coloured and dressed, from its
-- steepness and its height (T-338, docs/game/features/ground-look.md; `Road/GroundLook`).
-- Roblox has no custom shaders, so the "shader" is worked out per vertex as each ground tile
-- is drawn (`Drift/GroundMeshView`), and blended across each face by the vertex colours.
--
-- THE LOOKS (step 1, T-339, a trial of three; `Look` picks one, and in a playtest the
-- `ground-look` command switches it live, redrawing the ground round the car):
--   "old"    today's: grass in two shades, flat grey rock past `Spline.Ground.RockAngle`
--   "blend"  colours only: grass fading through rocky grass to rock as it steepens, lush to
--            alpine to snow as it climbs, each band edge wandered by noise. Costs almost nothing
--   "detail" "blend" over one shared grey detail texture (`Road/DetailTexture`, made in code,
--            as the grass runoff has one), so grass and rock have grain up close
--   "rock"   "blend", with the steep faces in Roblox's own Rock material: a second mesh over
--            each tile that has rock in it. Best up close; costs a second mesh per such tile
--   "sheet"  (T-340, the user's pick of direction) "blend" over a texture SHEET: one image
--            holding grass, rocky grass, rock and snow textures, each triangle of ground
--            taking its square by steepness and height (`Road/GroundSheet`)

return {
	Look = "old",
	Looks = { "old", "blend", "detail", "rock", "sheet" },

	-- false: the sheet and the detail texture stay EditableImages (a 1 024 sheet holds about 32
	-- of the client's ~640 tiles of mesh memory). true makes them opaque content, which holds
	-- none, but the ground drew opaque textures garbled away from the car (T-340, DR-Lane2)
	OpaqueTextures = false,

	-- THE TEXTURE SHEET ("sheet", `Road/GroundSheet`). `Size` pixels each way, in 2 x 2
	-- squares, in `Order` (top left, top right, bottom left, bottom right). Each square holds
	-- its texture `Repeats` times each way, one repeat covering `PeriodStuds` of ground (the
	-- tile's spacing on tiles coarser than that); a face uses the middle of its square, the
	-- outer half repeat a margin so the image's far-off blur never reaches the next square.
	-- Its average is `Mean`, and the vertex colours are divided by it. A face takes a square
	-- from `From` of its weight (snow over rock over rocky grass over grass).
	-- `Image`: the picked sheet once uploaded (its four squares, each one tile, are repeated
	-- into the game's sheet here); nil draws placeholder textures made in code
	Sheet = {
		Size = 1024,
		Order = { "grass", "rocky", "rock", "snow" },
		Repeats = 3,
		PeriodStuds = 32,
		Mean = 0.8,
		From = 0.5,
		-- the painterly sheet, picked by the user (assets/ground-textures/MANIFEST.md)
		Image = "rbxassetid://76745644013222" :: string?,
	},

	-- STEEPNESS, in degrees from flat (a vertex's normal). Grass up to `Rocky[1]`, rocky grass
	-- by `Rocky[2]`; rock from `Rock[1]`, all rock by `Rock[2]` (eased between). Each edge is
	-- moved up to `Jitter` degrees either way by noise over `JitterStuds`, so the bands never
	-- run in lines. Up high the ground is rockier: every edge comes down `AlpineLower` degrees
	-- by the time the ground is alpine
	Rocky = { 19, 30 },
	Rock = { 27, 38 },
	Jitter = 6, -- degrees
	JitterStuds = 110,
	AlpineLower = 6, -- degrees

	-- HEIGHT, in studs above the floor of the valley the run starts in (the mountain's own
	-- zero, `Road/Ground` field `oy`): lush grass to `Alpine[1]`, alpine grass by `Alpine[2]`;
	-- snow from `Snow[1]`, all snow by `Snow[2]`. Each edge moved up to `HeightJitter` studs
	-- either way by noise over `HeightJitterStuds`. Snow does not lie on a face steeper than
	-- `SnowSteep[1]` (and none past `SnowSteep[2]`): the rock shows through
	Alpine = { 420, 780 }, -- studs
	Snow = { 900, 1100 }, -- studs
	HeightJitter = 140, -- studs
	HeightJitterStuds = 420,
	SnowSteep = { 26, 38 }, -- degrees

	-- THE COLOURS. Grass is two shades blotched by noise, as the old look has it (lush is the
	-- old look's own grass); rock is two greys by height with faint strata (`Strata` either
	-- way, over bands `StrataStuds` tall, wandered by noise)
	Lush = { Color3.fromRGB(86, 132, 62), Color3.fromRGB(70, 116, 54) },
	AlpineGrass = { Color3.fromRGB(108, 134, 70), Color3.fromRGB(92, 118, 62) },
	RockyGrass = Color3.fromRGB(114, 118, 90),
	RockLow = Color3.fromRGB(116, 110, 102),
	RockHigh = Color3.fromRGB(132, 130, 128),
	Strata = 0.07,
	StrataStuds = 9,
	SnowColour = Color3.fromRGB(232, 238, 246),
	BlotchStuds = 70,

	-- THE DETAIL TEXTURE ("detail", `Road/DetailTexture`): grey noise made in code, `Size`
	-- pixels each way, tiling every `Spline.Ground.UVStuds` (48 studs, the ground's UVs); its average is `Mean`, and the vertex colours
	-- are divided by it, so the ground keeps its brightness. `Contrast` is how far a pixel
	-- strays from the average (of 1), across `Octaves` of noise, the coarsest `Cells` across
	Detail = {
		Size = 256,
		Mean = 0.8,
		Contrast = 0.2,
		Octaves = 4,
		Cells = 4,
	},

	-- THE ROCK MESH ("rock"): each vertex of a tile with rock in it is drawn again, `Lift`
	-- studs out along its normal where it is all rock and `Sink` studs in where it is none, in
	-- the Rock material, so it shows through the grass from about where the rock weight is
	-- Sink / (Lift + Sink). Its colours are the ground's, times `Tint` (the material's own map
	-- darkens them). A tile whose vertices all have less than `From` of rock gets none
	RockMesh = {
		Lift = 0.35, -- studs
		Sink = 0.9, -- studs
		Tint = 1.25,
		From = 0.6,
		Material = Enum.Material.Rock,
	},
}
