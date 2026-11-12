--!nonstrict
-- Horizon: every number of the mountains round the endless run, and none of them in the logic
-- (docs/game/features/horizon.md "Rules and numbers", T-150).
--
-- WHAT READS WHAT:
--   `Shared/Horizon`      the shapes: each layer's ridge line and the snow peak, as triangles
--   `Drift/HorizonView`   draws them as wedge parts and keeps them on the horizon
--
-- WHERE THEY STAND: round the camera, never anywhere fixed. `Radius` is studs from the camera
-- to the ridge line; heights are studs above the road's start (its origin), and the whole
-- horizon rises and falls by `FollowHeight` of the camera's own height above that start (eased
-- over `HeightLag`). All of it would keep them where they are in the frame however high the
-- road climbs; none, and at 2 400 studs the road's +-160 would swing the near ridges by 4
-- degrees in a band of sky only 7 tall. So climbing still sinks them a little.
--
-- HOW HIGH, IN THE FRAME: the chase camera looks down 18-23 degrees, and the top of the
-- screen is only about 8 degrees above level (measured parked: level at 122 px from the top,
-- 5 degrees at 48, 8 at the very top). So the ridges stand about 2 to 5 degrees up
-- (height / radius) and the snow peak's summit 5.5, inside the frame with sky above. At the
-- spec's first sizes (9-12 degrees) they filled the sky like a wall.
--
-- HOW FAR: the day's haze (`DayNight` `AtmosphereDensity` ~0.29) washed out everything past
-- 2 500 studs at the spec's first distances, so the layers are nearer than the spec's. The
-- nearest faces stay beyond the road drawn ahead (1 600) wherever the road could be (down to
-- 160 below its start), even at the layer's `MaxLag` (the unit test checks).
--
-- WHY THEY TRAIL (`Lag`): a layer that follows the camera exactly looks infinitely far away,
-- like the sky. A layer whose centre catches the camera up over `Lag` seconds slides a little
-- as you drive and turn, which reads as distance. The nearest layer trails most, the snow
-- peak not at all (it holds its bearing). `MaxLag` caps how far a layer may fall behind, so
-- you never get closer to it than `Radius - MaxLag`.
--
-- PLAIN PARTS, NOT A MESH: a mesh may be at most 2 048 studs across (measured in the lane:
-- "Mesh extents size too large"), and the ring is ten times that. Each triangle is two wedge
-- parts; a triangle longer than `MaxEdge` is split first.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	Seed = 7311, -- the same mountains on every client
	Material = Enum.Material.SmoothPlastic,
	Thickness = 8, -- studs each face's slab hangs behind it
	MaxEdge = 1900, -- studs; a part may be at most 2 048 on a side
	-- Parts made per frame while the horizon is first built, so the run's start never hitches.
	BuildPerFrame = 120,
	FollowHeight = 0.75,
	HeightLag = 2, -- s

	-- ----------------------------------------------------------------- the ridges
	-- Nearest first. Each is a ring of `Segments` peaks and saddles: a ridge vertex every
	-- 360/Segments degrees (jittered by `AngleJitter` of a step), at `Radius` (jittered by
	-- `RadiusJitter` of it), between `Height[1]` and `Height[2]` tall; the faces run down
	-- to `Base`, `Depth` (a fraction of `Radius`) nearer, half a step round, so the faces
	-- are triangles that meet in gullies.
	--
	-- `Height` is shaped by `Waves` (slow swells round the ring, so there are taller and
	-- lower stretches) and `Rough` (each vertex's own jump). Each facet's colour is the
	-- layer's `Colour`, lightened or darkened by up to `Shade`, so neighbouring faces differ.
	Layers = {
		{
			Name = "Near",
			Radius = 2400,
			Segments = 32,
			Height = { 70, 190 },
			Base = -560,
			Depth = 0.2,
			AngleJitter = 0.3,
			RadiusJitter = 0.06,
			Waves = { 3, 7 },
			Rough = 0.35,
			Colour = rgb(26, 50, 32), -- dark forested green (the haze lightens it a lot)
			Shade = 0.1,
			Lag = 3, -- s
			MaxLag = 250, -- studs
		},
		{
			Name = "Middle",
			Radius = 3200,
			Segments = 28,
			Height = { 120, 250 },
			Base = -500,
			Depth = 0.18,
			AngleJitter = 0.3,
			RadiusJitter = 0.05,
			Waves = { 2, 5 },
			Rough = 0.3,
			Colour = rgb(50, 82, 92), -- blue-green
			Shade = 0.08,
			Lag = 1.5,
			MaxLag = 250,
		},
		{
			Name = "Far",
			Radius = 4500,
			Segments = 36,
			Height = { 180, 370 },
			-- higher and steeper than the others, so its faces stay under `MaxEdge` unsplit;
			-- the nearer layers hide its foot
			Base = -150,
			Depth = 0.07,
			AngleJitter = 0.25,
			RadiusJitter = 0.04,
			Waves = { 2, 4 },
			Rough = 0.3,
			Colour = rgb(104, 124, 150), -- pale blue-grey
			Shade = 0.06,
			Lag = 0.6,
			MaxLag = 150,
		},
	},

	-- ------------------------------------------------------------- the snow peak
	-- One mountain standing above the far layer, always at `Bearing` (degrees clockwise from
	-- the world's -Z, which is where the run's road heads at the start when its yaw is 0).
	-- A cone of `Sides` faces, only the half facing you built: its foot at `Base`, a shoulder
	-- at `Shoulder` of its height, the snow line at `SnowLine` of it (jagged by `SnowJag`),
	-- and the summit at `Height`, leaning a little off centre by `Lean` of its foot's radius.
	Peak = {
		Bearing = 35,
		Radius = 6000,
		Height = 580,
		Base = -300,
		Foot = 700, -- studs, the radius of its foot
		Sides = 9,
		Shoulder = 0.32,
		SnowLine = 0.66,
		SnowJag = 0.06,
		Lean = 0.12,
		Rock = rgb(88, 98, 120),
		Snow = rgb(248, 250, 255),
		Shade = 0.07,
	},
}
