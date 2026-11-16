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
	-- "belts" is the T-228 mountain, one fall line, always down; "range" is this one, and since
	-- T-238 the road climbs to its passes on it (`SplineGen._planRange`)
	Shape = "range",

	Spacing = 6500, -- studs between ridges, on average
	Jitter = 1200, -- studs either way, so 4 100 to 8 900 apart
	Wobble = { 850, 6500 }, -- studs either way, over studs across (never more than half of `Spacing - 2 * Jitter`)

	Peak = { 550, 900 }, -- studs above the start valley's floor: a ridge's peaks (before `PeakVary`)
	SaddleDepth = { 250, 480 }, -- studs below its peaks: its saddles
	SaddleMin = 380, -- studs above the start valley's floor: no saddle lower
	PeakVary = { 0.2, 9000 }, -- a ridge rises and falls along its length: this share either way, over studs
	SaddleEvery = 3000, -- studs across: about one saddle in this
	SaddleWarp = 0.5, -- how much the spacing wanders (under 1, so saddles never merge)
	SaddleSharp = 1.3, -- how much of the crest is near a peak or a saddle, not between
	SaddleRise = 60, -- studs: a saddle's crest rises at least this much on both sides...
	SaddleSpan = 2000, -- ...within this many studs

	ValleyAt = { 0.4, 0.6 }, -- of the way from one ridge to the next
	ValleyBase = { -110, 80 }, -- studs from the start valley's floor
	FloorVary = 60, -- studs either way along a valley...
	FloorEvery = 6000, -- ...over studs across
	Floor = { 0, 0.12 }, -- of each face, flat at the floor
	Profile = { 1.0, 1.4 }, -- a face's exponent: higher, steeper near the crest and wider at the floor
	CrestRound = 40, -- studs: the crest rounded over about this much

	Octaves = { { 1400, 60, "ridge" }, { 600, 24, "gully" }, { 220, 8 } }, -- (100 tall, the road could not follow them)
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

	-- THE ROAD TO THE PASS (`SplineGen._planRange`, T-238). Climbing a face, the road heads
	-- straight for the pass once it can climb to it at `DirectGrade` or less, on `PassOver`
	-- studs past it; until then it climbs in legs across the face, each ending `PassBand / 2`
	-- studs past the pass across (`LegMin` to `LegMax` studs long), joined by turnarounds:
	-- switchbacks stacked below the pass. Coming down, legs the same way toward the next pass.
	-- `TowardBias` adds the way to the pass to the slope, so flat ground has a way on. On
	-- steep ground (`Spline.Ground.SlopeSteep`) a hairpin is as tight as the road allows
	DirectGrade = 0.05, -- 3 degrees...
	DirectReach = 900, -- ...and no further off than this (straight up from further, the road left the slope)
	PassOver = 300, -- studs
	PassBand = 3000, -- studs across
	LegMin = 400, -- studs
	LegMax = 6000, -- studs
	TowardBias = 0.05,
	AimRelief = 0.35, -- of the spurs' and gullies' slope a leg's heading reads, with the face's...
	AimSpan = 200, -- ...over this many studs, where the road is
	LegOnward = 8, -- degrees: every leg heads at least this much along the way on, never back
	SteepHairpinRadius = { 70, 80 }, -- studs (`Spline.MinRadius` is 70)
	-- about to box itself in, the road tries every bend of these turns either way on these radii
	RescueTurns = { 20, 45, 70, 100, 130, 160 }, -- degrees
	RescueRadii = { 70, 110, 170, 260, 400 }, -- studs
	GiveUp = 6, -- times a planned turn may be refused before the way to the pass is planned again
	-- heading further off its aim than its bends may stray, the road turns back onto it on these
	-- radii rather than run on straight (T-242)
	RecoverRadius = { 90, 250 }, -- studs
	-- (T-242 trial switches, temporary)
	AimFlip = "hyst", -- "flip" | "hyst" | "near" | "keep"
	CurlEnd = false,
	Recover = "turn", -- "turn" | "converge" | "none"
	NearestBy = "worst", -- "worst" | "end"
	Follow = true,
	FollowTurns = { 20, 40, 60, 90, 120 }, -- degrees
	FollowRadii = { 120, 300 }, -- studs
	FollowStraight = 160, -- studs
	FollowAimCost = 0.5, -- studs a degree past the aim's limit
	FollowBackCost = 100, -- studs, heading straight back
	FollowDeepCut = 30, -- studs of cut...
	FollowDeepCost = 2, -- ...past which each stud deeper costs this many more
	FollowHold = 0, -- studs of straight after each bend tried (0: none)
	AimLocal = true,
	AimLocalAhead = 120, -- studs
	AimLocalSwing = 60, -- degrees either way
	AimLocalStep = 10, -- degrees
	AimLocalTurnCost = 0.3, -- studs a degree off the plan's heading
	AimLocalBackCost = 60, -- studs, heading straight back
}
