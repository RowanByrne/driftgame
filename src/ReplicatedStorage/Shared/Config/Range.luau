--!strict
-- Config.Range: the mountain range a ground run crosses (features/mountain-range.md, T-233).
-- Read by `Road/Range` and `Road/Ground`. Every number is a starting value, tuned in a lane.
--
-- THE SHAPE, in the run's own frame: `t` studs on along the way the run goes (the old fall
-- line's downhill), `v` studs across it. RIDGES lie across the way, one every `Spacing` studs
-- give or take `Jitter`, each wandering up to `Wobble[1]` studs either way over `Wobble[2]`
-- across. Along its crest a ridge rises to PEAKS and dips to SADDLES (the passes), from
-- noise every `SaddleEvery` studs across. A VALLEY lies between two ridges, its floor
-- `ValleyAt` of the way from one to the next, flat for `Floor` of each face, its height
-- from `ValleyBase` and wandering `FloorVary` over `FloorEvery` across. Each face falls
-- from the crest to the floor as (1 - x) ^ `Profile`: steep near the crest, easing out at
-- the floor, as a real face does. SPURS and GULLIES run down the faces (`Octaves`, as
-- `Spline.Ground.Octaves`), none on the valley floors and all of them from `ReliefRise` of
-- the way up a face.
--
-- Heights are from the floor of the valley the run starts in, which is where the road's
-- start sits. Every number is the same on every device: the range is a pure function of the
-- seed and the place.

return {
	-- "belts" is the T-228 mountain, one fall line, always down; "range" is this one. Step 1
	-- builds the range with the road unchanged, so runs keep the belts until the road can
	-- climb to a pass (step 2)
	Shape = "belts",

	Spacing = 5500, -- studs between ridges, on average
	Jitter = 1200, -- studs either way, so 3 100 to 7 900 apart
	Wobble = { 450, 5000 }, -- studs either way, over studs across

	Peak = { 650, 1200 }, -- studs above the start valley's floor: a ridge's peaks
	SaddleDepth = { 250, 480 }, -- studs below its peaks: its saddles
	SaddleMin = 380, -- studs above the start valley's floor: no saddle lower
	SaddleEvery = 3000, -- studs across: about one saddle in this
	SaddleWarp = 0.5, -- how much the spacing wanders (under 1, so saddles never merge)
	SaddleSharp = 1.3, -- how much of the crest is near a peak or a saddle, not between
	SaddleRise = 60, -- studs: a saddle's crest rises at least this much on both sides...
	SaddleSpan = 2000, -- ...within this many studs

	ValleyAt = { 0.4, 0.6 }, -- of the way from one ridge to the next
	ValleyBase = { -110, 80 }, -- studs from the start valley's floor
	FloorVary = 60, -- studs either way along a valley...
	FloorEvery = 6000, -- ...over studs across
	Floor = { 0.05, 0.22 }, -- of each face, flat at the floor
	Profile = { 1.5, 2.2 }, -- a face's exponent: higher, steeper near the crest
	CrestRound = 40, -- studs: the crest rounded over about this much

	Octaves = { { 1600, 120, "ridge" }, { 650, 45, "gully" }, { 220, 8 } },
	Stretch = 2.5, -- times longer along `t` (down the faces) than across
	ReliefFloor = 0.15, -- of the spurs and gullies on a valley floor...
	ReliefRise = 0.35, -- ...rising to all of them this far up a face

	-- WHERE YOU ARE (`Ground.where`): within `PassReach` studs of a crest and `PassShare` of
	-- the way from its peaks down to its saddle is a pass; within `RidgeReach` of a crest, a
	-- ridge; in the lowest `ValleyShare` of a face, a valley; anywhere else, a face
	PassReach = 350, -- studs
	PassShare = 0.75,
	RidgeReach = 250, -- studs
	ValleyShare = 0.12,

	-- THE PASS AHEAD (`Range.passAhead`): the saddle on the next ridge the road should cross,
	-- the lowest within `PassWindow` studs either way across of where the road is, each stud
	-- off to the side counting as `PassLean` studs of height
	PassWindow = 4000, -- studs
	PassLean = 0.08,
	PassStep = 50, -- studs between the crest's samples
}
