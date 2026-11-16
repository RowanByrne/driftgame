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
	-- slides past a further one on a bend. `Skirt`: a plain part under each panel, in the
	-- colour of the art's base, reaching down `Skirt` studs so the bottom edge of the art is
	-- never seen above the cloud sea; `BaseColour` is the art's bottom tenth, averaged.
	Layers = {
		{
			Name = "Far",
			Radius = 4500,
			Panels = 14,
			Aspect = 3, -- the art's width over its height (2172 x 724)
			Peak = 5.5,
			PeakAt = 0.33,
			Lag = 0.6,
			MaxLag = 120,
			Skirt = 900,
			BaseColour = Color3.fromRGB(151, 172, 198),
			Images = {
				"", -- far-painted-02 (assets/painted-vista/MANIFEST.md)
				"", -- far-painted-02-v1
				"", -- far-painted-02-v2
			},
		},
	},

	-- Each layer stands at the road's start height plus `FollowHeight` of the camera's
	-- height above it, eased over `HeightLag` s, so it holds its place in the frame as the
	-- road climbs and falls, sinking a little (as the old horizon did).
	FollowHeight = 0.75,
	HeightLag = 2, -- s

	-- ------------------------------------------------------------- cloud sea
	-- `Layers` stacked layers, the top one `Below` studs under the road's start and each
	-- next one `Gap` under it, rising with the road like the ridges (`FollowHeight`). It never
	-- comes nearer than `MinBelow` under the camera, so a long descent can't bring it up to
	-- the road. Each layer is `Grid` x `Grid` parts of `PartSize` studs. The cloud texture
	-- repeats every `Tile` studs, and must divide `PartSize` so neighbouring parts join; the
	-- parts move in whole tiles, so the cloud stays put while they follow the car. Each layer
	-- drifts at its own speed (studs/s) and direction (degrees), and lets more through the
	-- lower it is (`Transparency`).
	CloudSea = {
		Image = "", -- the picked cloud texture (assets/painted-vista/MANIFEST.md)
		Below = 300,
		Gap = 30,
		MinBelow = 200,
		Grid = 3,
		PartSize = 2048,
		Tile = 1024,
		Layers = {
			{ Transparency = 0.2, Drift = 2, Heading = 20 },
			{ Transparency = 0.4, Drift = 2.6, Heading = 35 },
			{ Transparency = 0.6, Drift = 1.6, Heading = 5 },
		},
	},
}
