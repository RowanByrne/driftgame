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
--
-- TWICE THE SIZE (T-245, the user: "2x the scale of the mountains and valleys ... the
-- steepness and shallowness is good the way it is"): every number of the big shape, across
-- and up alike, is twice what T-238 tuned, so every face keeps its steepness and only the
-- range grows. The spurs and gullies the road follows (`Octaves`), and everything about the
-- road's own bends, are the size they were. The valley floors and the crests sit `LIFT`
-- (120) studs higher than twice T-238's, the start valley's floor staying the zero: doubled
-- as they were, the lowest floors came within 160 studs of the fall-kill height (-500).

return {
	-- "belts" is the T-228 mountain, one fall line, always down; "range" is this one, and since
	-- T-238 the road climbs to its passes on it (`SplineGen._planRange`)
	Shape = "range",

	Spacing = 13000, -- studs between ridges, on average (6 500 until T-245)
	Jitter = 2400, -- studs either way, so 8 200 to 17 800 apart
	Wobble = { 1700, 13000 }, -- studs either way, over studs across (never more than half of `Spacing - 2 * Jitter`)

	-- (`LIFT` is 120: these are twice T-238's, and 120 more)
	Peak = { 1220, 1920 }, -- studs above the start valley's floor: a ridge's peaks (before `PeakVary`)
	SaddleDepth = { 500, 960 }, -- studs below its peaks: its saddles
	SaddleMin = 880, -- studs above the start valley's floor: no saddle lower...
	SaddleEase = 80, -- ...eased into over about this many studs (a hard floor left flat crests)
	PeakVary = { 0.2, 18000 }, -- a ridge rises and falls along its length: this share either way, over studs
	SaddleEvery = 6000, -- studs across: about one saddle in this
	SaddleWarp = 0.5, -- how much the spacing wanders (under 1, so saddles never merge)
	SaddleSharp = 1.3, -- how much of the crest is near a peak or a saddle, not between
	SaddleRise = 120, -- studs: a saddle's crest rises at least this much on both sides...
	SaddleSpan = 4000, -- ...within this many studs

	ValleyAt = { 0.4, 0.6 }, -- of the way from one ridge to the next
	ValleyBase = { -100, 280 }, -- studs from the start valley's floor (twice T-238's, and `LIFT`)
	FloorVary = 120, -- studs either way along a valley...
	FloorEvery = 12000, -- ...over studs across
	Floor = { 0, 0.12 }, -- of each face, flat at the floor
	Profile = { 1.0, 1.4 }, -- a face's exponent: higher, steeper near the crest and wider at the floor
	CrestRound = 80, -- studs: the crest rounded over about this much

	-- (the road's size, not the range's: kept as T-238 tuned them when T-245 doubled the range.
	-- 100 tall, the road could not follow them)
	Octaves = { { 1400, 60, "ridge" }, { 600, 24, "gully" }, { 220, 8 } },
	Stretch = 2.5, -- times longer along `t` (down the faces) than across
	ReliefFloor = 0.15, -- of the spurs and gullies on a valley floor...
	ReliefRise = 0.35, -- ...rising to all of them this far up a face

	-- WHERE YOU ARE (`Ground.where`): within `PassReach` studs of a crest and `PassShare` of
	-- the way from its peaks down to its saddle is a pass; within `RidgeReach` of a crest, a
	-- ridge; in the lowest `ValleyShare` of a face, a valley; anywhere else, a face
	PassReach = 700, -- studs (350 until T-245 doubled the range)
	PassShare = 0.75,
	RidgeReach = 500, -- studs (250 until T-245)
	ValleyShare = 0.12,

	-- THE PASS AHEAD (`Range.passAhead`): the saddle on the next ridge the road should cross,
	-- the lowest within `PassWindow` studs either way across of where the road is, each stud
	-- off to the side counting as `PassLean` studs of height
	PassWindow = 8000, -- studs (4 000 until T-245)
	PassLean = 0.08,
	PassStep = 100, -- studs between the crest's samples (50 on the range half the size)

	-- THE ROAD TO THE PASS (`SplineGen._planRange`, T-238). Climbing a face, the road heads
	-- straight for the pass once it can climb to it at `DirectGrade` or less, on `PassOver`
	-- studs past it; until then it climbs in legs across the face, each ending `PassBand / 2`
	-- studs past the pass across (`LegMin` to `LegMax` studs long), joined by turnarounds:
	-- switchbacks stacked below the pass. Coming down, legs the same way toward the next pass.
	-- `TowardBias` adds the way to the pass to the slope, so flat ground has a way on. On
	-- steep ground (`Spline.Ground.SlopeSteep`) a hairpin is as tight as the road allows
	-- (T-245 doubled the range: `DirectReach`, `PassBand` and `LegMax`, the range's size, with
	-- it; the rest is the road's own)
	DirectGrade = 0.05, -- 3 degrees...
	DirectReach = 1800, -- ...and no further off than this (straight up from further, the road left the slope)
	PassOver = 300, -- studs
	PassBand = 6000, -- studs across
	LegMin = 400, -- studs
	LegMax = 12000, -- studs
	TowardBias = 0.05,
	AimRelief = 0.35, -- of the spurs' and gullies' slope a leg's heading reads, with the face's...
	AimSpan = 200, -- ...over this many studs, where the road is
	LegOnward = 8, -- degrees: every leg heads at least this much along the way on, never back
	SteepHairpinRadius = { 70, 80 }, -- studs (`Spline.MinRadius` is 70)
	-- about to box itself in, the road tries every bend of these turns either way on these radii
	RescueTurns = { 20, 45, 70, 100, 130, 160 }, -- degrees
	RescueRadii = { 70, 110, 170, 260, 400 }, -- studs
	GiveUp = 6, -- times a planned turn may be refused before the way to the pass is planned again
	-- A LEG'S HEADING CHECKED AGAINST h ITSELF (T-242): every heading `AimLocalStep` degrees
	-- apart within `AimLocalSwing` either way of the one the face gives, scored on how far off h
	-- the road would still be `AimLocalAhead` studs on (and half that), plus `AimLocalTurnCost`
	-- studs a degree off the face's heading and `AimLocalBackCost` for heading straight back
	AimLocalAhead = 120, -- studs
	AimLocalSwing = 40, -- degrees
	AimLocalStep = 10, -- degrees
	AimLocalTurnCost = 0.3, -- studs a degree
	AimLocalBackCost = 200, -- studs
	-- THE MOUNTAIN FIRST (T-242): when no random section follows h, a straight of
	-- `FollowStraight` and every bend of `FollowTurns` either way on `FollowRadii`, each judged
	-- `FollowLook` studs on past it: how far off h the road is there, half the furthest it
	-- strays, `FollowAimCost` studs a degree past its aim's limit, `FollowBackCost` heading back
	FollowStraight = 160, -- studs
	FollowTurns = { 20, 40, 60 }, -- degrees (bigger ones, 90 and 120, swung the road through a face)
	FollowRadii = { 120, 250 }, -- studs
	FollowLook = 100, -- studs
	FollowAimCost = 0.5, -- studs a degree
	FollowBackCost = 250, -- studs (100 left the road heading back 500 studs, twice in 24 runs)
	StraightenMaxOff = 20, -- studs off h: a bend straightening the road before a hairpin goes no further (T-242)
}
