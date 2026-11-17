--!nonstrict
-- Vista: every number of the painted vista round the run, and none of them in the logic
-- (docs/game/features/painted-vista.md "Rules and numbers", T-266).
--
-- WHAT READS WHAT:
--   `Shared/Vista`              the pure sums: where each panel stands, how a layer follows
--   `Drift/VistaView`           builds the panels and the cloud sea on this client, moves them
--   `Controllers/SkyController` gives the look (`VistaTint`, `CloudSeaColour` in
--                               `Config.DayNight`), so they change with the time of day
--
-- A STAGE SET: painted ridge layers stand in a ring round the camera, and a cloud sea lies
-- below the road, all following the camera so you never reach them. Roblox's own sky stays
-- above them. Each panel is a flat invisible part with the art as a Decal on its inner face,
-- lit by Roblox's real sun (a panel with the sun behind it is dark), and tinted by the time
-- of day. The haze (`Atmosphere`) fades each layer by its distance.

return {
	-- Off: nothing is built, and the view off the road is the sky and the drawn ground.
	Enabled = true,

	-- ------------------------------------------------------------- the curved panel
	-- One mesh, built on this device when the first vista is (`Shared/Vista.arcGeometry`, an
	-- EditableMesh: nothing uploaded) and cloned for every panel: an arc of `ArcDeg` degrees
	-- in `Columns` strips, shaded smooth, so a ring of them shows no step where two meet in
	-- the sun's light (the user, on flat panels: "the seams you can see where they join").
	-- Its top `ArtShare` carries the picture; below that a skirt in the picture's own bottom
	-- row reaches down under the cloud sea. The picture is a SurfaceAppearance (its sky
	-- see-through), made ahead in `ReplicatedStorage.VistaSurfaces`, one per image, named by
	-- its asset id: a game script can't set one's picture itself (measured: "lacking
	-- capability Plugin"), and a mesh's own texture fills the sky in. `Build` off, or if the
	-- mesh can't be made, the layers fall back to flat panels with a Decal and a plain skirt.
	Mesh = {
		Build = true,
		ArcDeg = 36, -- so a curved layer has 360 / 36 = 10 panels
		Columns = 24,
		ArtShare = 0.4228, -- the far layer's art over art + skirt (659 of 1 559 studs)
		-- The shape starts this far down the picture, in its empty sky: at the very top, the
		-- picture's opaque bottom row wrapped round and drew a faint line along the panels'
		-- top edge (lane 2). The summits are 0.31 or more down every picture.
		TopV = 0.1,
		-- Under the picture the skirt fades, over `SkirtFade` of the picture's height, into one
		-- even colour: the picture's own mist at `SkirtUV`. Holding the bottom row, or stretching
		-- the misty base, ran each column's colour down the skirt in streaks (the user circled
		-- them; lane 2).
		SkirtFade = 0.25,
		-- At the picture's edge column, which every joined picture of a ring shares, so the
		-- skirts of neighbouring panels match.
		SkirtUV = Vector2.new(0.003, 0.97),
	},

	-- ------------------------------------------------------------- ridge layers
	-- Each layer is a ring of `Panels` flat panels, `Radius` studs from the camera (to each
	-- panel's ends; its middle is a little nearer), each panel as wide as its chord, which
	-- must stay under 2 048 studs (a part's largest size). The art's aspect sets each panel's
	-- height. `Peak` is where the art's highest summit stands, in degrees above the layer's
	-- level, and `PeakAt` where that summit is in the art, from its top (measured off the
	-- picked strips: 0.31 to 0.34). `Images` go round the ring in order; an empty one is
	-- left out (the panel stands with no art, so it can't be seen).
	--
	-- `Lag` (s) and `MaxLag` (studs): how far the layer trails the camera, so a nearer layer
	-- slides past a further one on a bend. The rings never cross, even at their full trails
	-- (the tests check), which is why the trails are short: every ring stands between the
	-- drawn ground's reach and the snow peaks.
	--
	-- `Slide` (step 2, the user's idea: "like the scenery of a puppet show"): the share of the
	-- camera's height above the road's start each ring rises by. A nearer ring rises less, so
	-- climbing sinks it below the further ones and the view opens; in a valley it stands up in
	-- front of them and closes it in.
	--
	-- A layer with no `Images` is not built. Its pictures are the `-joined` copies: every one
	-- ends in the halves of one connector cut from the ring's first picture, so any two meet
	-- without a seam (`pipeline/vista/join-strips.py`; lifting each picture to line up its
	-- saddles still left the mist bands stepped, the user's screenshot). `Edges` (optional):
	-- where each picture's end saddles sit, to lift it so they meet; the joined copies need
	-- none. `Skirt`: a plain part under each panel, in the
	-- colour of the art's base, reaching down `Skirt` studs so the bottom edge of the art is
	-- never seen above the cloud sea; `BaseColour` is the art's bottom tenth, averaged.
	Layers = {
		{
			Name = "Far",
			-- 4 500 washed the peaks out in the day's haze, and 5.5 degrees barely cleared the
			-- drawn ground's far edge (lane 3, first look): nearer and taller.
			Radius = 3200,
			Panels = 10,
			Aspect = 3, -- the art's width over its height (2172 x 724)
			Peak = 8,
			PeakAt = 0.33,
			Lag = 0.6,
			MaxLag = 40, -- was 120, before the nearer rings had to fit inside it
			Slide = 0.75,
			Skirt = 900,
			BaseColour = Color3.fromRGB(151, 172, 198),
			Images = {
				"rbxassetid://119692693529026", -- far-painted-02-joined (pipeline/vista/join-strips.py; assets/painted-vista/MANIFEST.md)
				"rbxassetid://115396242160535", -- far-painted-02-v1-joined (pipeline/vista/join-strips.py; assets/painted-vista/MANIFEST.md)
				"rbxassetid://85256458205915", -- far-painted-02-v2-joined (pipeline/vista/join-strips.py; assets/painted-vista/MANIFEST.md)
			},
		},
		{
			Name = "Middle",
			Radius = 2900,
			Panels = 10,
			Aspect = 3,
			Peak = 5.5,
			PeakAt = 0.33,
			Lag = 1.5,
			MaxLag = 50,
			Slide = 0.6,
			Skirt = 900,
			BaseColour = Color3.fromRGB(156, 175, 194), -- mid-ridge-02's bottom tenth
			Images = {
				"rbxassetid://80914219707896", -- mid-ridge-02-joined (pipeline/vista/join-strips.py; assets/painted-vista/MANIFEST.md)
				"rbxassetid://75118707726792", -- mid-ridge-02-v1-joined (pipeline/vista/join-strips.py; assets/painted-vista/MANIFEST.md)
				"rbxassetid://91599232524447", -- mid-ridge-02-v2-joined (pipeline/vista/join-strips.py; assets/painted-vista/MANIFEST.md)
			},
		},
		{
			Name = "Near",
			Radius = 2620,
			Panels = 10,
			Aspect = 3,
			Peak = 3.5,
			PeakAt = 0.33,
			Lag = 3,
			MaxLag = 60,
			Slide = 0.45,
			Skirt = 900,
			BaseColour = Color3.fromRGB(152, 169, 188), -- near-forest-01's bottom tenth
			Images = {
				"rbxassetid://90908547604599", -- near-forest-01-joined (pipeline/vista/join-strips.py; assets/painted-vista/MANIFEST.md)
				"rbxassetid://138672626842006", -- near-forest-01-v1-joined (pipeline/vista/join-strips.py; assets/painted-vista/MANIFEST.md)
				"rbxassetid://138887894601361", -- near-forest-01-v2-joined (pipeline/vista/join-strips.py; assets/painted-vista/MANIFEST.md)
			},
		},
	},

	-- Each layer stands at the road's start height plus its `Slide` of the camera's height
	-- above it, eased over `HeightLag` s. The cloud sea rises by `FollowHeight`.
	FollowHeight = 0.75,
	HeightLag = 2, -- s

	-- ------------------------------------------------------------- cloud sea
	-- `Layers` stacked layers, the top one `Below` studs under the road's start and each
	-- next one `Gap` under it, rising with the road like the ridges (`FollowHeight`). It never
	-- comes nearer than `MinBelow` under the camera, so a long descent can't bring it up to
	-- the road. Each layer is `Grid` x `Grid` parts of `PartSize` studs: the top one reaches
	-- past the ridge ring, so its edge is never seen; the ones under it only show through
	-- it, so they stay small. The cloud texture
	-- repeats every `Tile` studs, and must divide `PartSize` so neighbouring parts join; the
	-- parts move in whole tiles, so the cloud stays put while they follow the car. Each layer
	-- drifts at its own speed (studs/s) and direction (degrees), and lets more through the
	-- lower it is (`Transparency`).
	CloudSea = {
		-- Off for now (2026-11-16, the user: "get rid of the cloud layer thing, we will revisit
		-- that later"). Everything below stays for when it comes back.
		Enabled = false,
		Image = "rbxassetid://117132635448742", -- cloud-oil-03, the picked cloud texture (assets/painted-vista/MANIFEST.md)
		Below = 150,
		Gap = 30,
		MinBelow = 120,
		PartSize = 2048,
		Tile = 2048, -- 1 024 made small billows that read as a snowfield
		Layers = {
			{ Grid = 5, Transparency = 0.25, Drift = 2, Heading = 20 },
			{ Grid = 3, Transparency = 0.4, Drift = 2.6, Heading = 35 },
			{ Grid = 3, Transparency = 0.6, Drift = 1.6, Heading = 5 },
		},
	},
}
