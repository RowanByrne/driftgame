--!strict
-- Config.Range: the mountain range every run crosses (features/mountain-range.md, T-233).
-- Read by `Road/Range`, `Road/Ground` and `Road/SplineGen`. Every number is a starting value, tuned in a lane.
--
-- THE SHAPE, in the run's own frame: `t` studs on along the way the run goes (the old fall
-- line's downhill), `v` studs across it. RIDGES lie across the way, one every `Spacing` studs
-- give or take `Jitter`, each wandering up to `Wobble[1]` studs either way over `Wobble[2]`
-- across. Along its crest a ridge rises to PEAKS and dips to SADDLES (the passes), from
-- noise every `SaddleEvery` studs across. A VALLEY lies between two ridges, its floor
-- `ValleyAt` of the way from one to the next, flat for `Floor` of each face, its height
-- from `ValleyBase` and wandering `FloorVary` over `FloorEvery` across. Each face falls
-- from the crest to the floor as (1 - x) ^ `Profile`: steep near the crest, easing out at
-- the floor, as a real face does. SPURS and GULLIES run down the faces (`Octaves`), none on
-- the valley floors and all of them from `ReliefRise` of the way up a face.
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
-- (200) studs higher than twice T-238's, the start valley's floor staying the zero: doubled
-- as they were, the lowest ground came within 90 studs of the fall-kill height (-500). So
-- the start valley lies about 200 studs lower among the others than it did, and the faces
-- either side of it are that much taller (about a tenth: the first climb's are a little
-- steeper); every other face is exactly twice the size.

return {
	Spacing = 13000, -- studs between ridges, on average (6 500 until T-245)
	Jitter = 2400, -- studs either way, so 8 200 to 17 800 apart
	Wobble = { 1700, 13000 }, -- studs either way, over studs across (never more than half of `Spacing - 2 * Jitter`)

	-- (`LIFT` is 200: these are twice T-238's, and 200 more)
	Peak = { 1300, 2000 }, -- studs above the start valley's floor: a ridge's peaks (before `PeakVary`)
	SaddleDepth = { 500, 960 }, -- studs below its peaks: its saddles
	SaddleMin = 960, -- studs above the start valley's floor: no saddle lower...
	SaddleEase = 80, -- ...eased into over about this many studs (a hard floor left flat crests)
	PeakVary = { 0.2, 18000 }, -- a ridge rises and falls along its length: this share either way, over studs
	SaddleEvery = 6000, -- studs across: about one saddle in this
	SaddleWarp = 0.5, -- how much the spacing wanders (under 1, so saddles never merge)
	SaddleSharp = 1.3, -- how much of the crest is near a peak or a saddle, not between
	SaddleRise = 120, -- studs: a saddle's crest rises at least this much on both sides...
	SaddleSpan = 4000, -- ...within this many studs

	ValleyAt = { 0.4, 0.6 }, -- of the way from one ridge to the next
	ValleyBase = { -20, 360 }, -- studs from the start valley's floor (twice T-238's, and `LIFT`)
	FloorVary = 120, -- studs either way along a valley...
	FloorEvery = 12000, -- ...over studs across
	Floor = { 0, 0.065 }, -- fraction of each face occupied by the level valley floor
	ValleyIncision = 165, -- studs cut from the valley datum relative to the adjoining crests
	Profile = { 1.0, 1.12 }, -- near-linear lower faces leave a narrower plain
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
	-- (200 until T-245 doubled the range: its legs twice as long, a heading a little back the
	-- way on fell back twice as far over one, 4 times on 96 roads of 50 000 studs, to 1 140;
	-- at 400 none, and no stall)
	AimLocalBackCost = 400, -- studs
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
	-- Screen the selected path and its exit before committing it. When the ground keeps
	-- rising or falling faster than a traverse should, try both flanks of the obstruction.
	ContourLook = 840, -- studs of country beyond the bend
	ContourExit = 560, -- studs of clear road beyond the bend
	ContourSample = 40, -- studs between height readings
	ContourGrade = 3.7, -- preferred degrees over a sustained climb or descent
	ContourPitchRise = 32, -- studs that a short pitch can gain above the sustained approach
	ContourSetback = 100, -- room for the apex to turn before it must head across the face again
	ContourTrigger = 11, -- predicted earthwork cost that merits another route
	ContourGain = 4, -- minimum improvement to change a chosen bend
	ContourTurns = { 22, 48, 80, 115, 155 }, -- degrees, either way from the incoming road
	ContourRadii = { 85, 180, 360 }, -- studs
	CorridorForward = 130, -- studs advanced into the range between surveyed layers
	CorridorAcross = 180, -- studs between alternate crossings of a layer
	CorridorColumns = 93, -- up to 12,090 studs of hillside in a survey
	CorridorHalfWidth = 28, -- 5,040 studs to either side
	CorridorReach = 6, -- a single traverse can go 1,080 studs across
	CorridorBendCost = 110, -- extra driving distance assigned to a radian of turn
	CorridorPitchCost = 220, -- distance cost per stud of rise/fall above the approach grade
	GorgeCost = 8, -- added travel per stud of paired-bank relief when heading up a channel
	GorgeLocalCost = 7, -- local steering cost for aiming into sustained paired banks
	TraverseSpan = 1600, -- length of hillside checked for a broad bend
	TraverseOffsets = { 350, 550, 760 }, -- alternative traverses beside the current corridor
	StraightenMaxOff = 20, -- studs off h: a bend straightening the road before a hairpin goes no further (T-242)
	-- A DESCENT IN LEGS ACROSS THE FACE (T-326, `Road/SplineContourTraverse`). Each leg is
	-- surveyed across the range one layer every `TraverseLayer` studs, `TraverseCell` studs
	-- between the places it may be on a layer, at most `TraverseShift` of them down or up the
	-- face a layer (67 degrees off straight across), no further than `TraverseBack` back up
	-- toward the mountain or `TraverseAhead` down it, and `TraverseMin` to `TraverseMax` long.
	-- A stud of height lost up to `TraverseGrade` earns `TraverseReward` times the length it
	-- took; a stud lost faster costs `TraverseSteep`; a stud regained costs what it would earn.
	-- Earthwork past `TraverseEarthTol` costs `TraverseEarth` a stud of depth, and steeply past
	-- `TraverseDeep`. The leg goes no further than `TraverseBand` past the next pass across.
	-- Its end is the hairpin, `TraverseHairpin` plus `TraverseSiteCost` per unit of slope over
	-- 0.15 there; the hairpin's radius is `TraverseRadiusSlope` over that slope (studs), within
	-- `SteepHairpinRadius[1]` and `TraverseRadiusMax`. The road follows the leg, aiming
	-- `TraverseLook` studs along it and straying no more than `TraverseLimit` degrees.
	TraverseGrade = 5, -- degrees: the sustained descent
	TraverseFrameSpan = 600, -- studs across: the crest's run a hairpin's way back is aimed along
	TraverseClear = 60, -- studs past the road's clearance: no leg (or hairpin) nearer old road...
	TraverseFromTip = 400, -- ...bar the road this far back from where the leg starts
	TraverseHairpinRoom = 250, -- studs down the fall line from a hairpin site that must be clear
	TraverseApproach = 6, -- layers before a hairpin that never climb back up the face
	TraverseExit = 200, -- studs of straight road clear past a hairpin's escape (`ContourExit` elsewhere)
	TraverseExitLayers = 4, -- layers of the next leg's start a hairpin site is judged on
	TraverseArrive = 120, -- studs short of a leg's end: the hairpin is first tried (and again either side of it)
	TraverseHairpinFall = 0.15, -- grade round a hairpin's half circle a site is judged on (8.5 degrees)
	TraverseLayer = 100, -- studs
	TraverseCell = 60, -- studs
	TraverseShift = 4,
	TraverseBack = 1200, -- studs: back up the face, round a gorge's head
	TraverseCrestMargin = 80, -- studs below the crest: no leg nearer it...
	TraverseBackOn = 1600, -- ...nor further back along the range than this behind where it starts
	TraverseStartTurn = 100, -- degrees: a leg this far off the road's heading would have to turn round first
	TraverseHopeless = 20000, -- a leg's score past which no drivable leg was found (seed 7's worst: 8 013)
	TraverseAhead = 3000, -- studs
	TraverseMin = 900, -- studs
	-- (7000 until T-337: legs of 5 000 to 7 500 studs held the top of the face for a whole
	-- leg, and a face came down in one or two; the user: "can we make it do more traverses".
	-- Over six seeds of 60 000 studs, 3500 turns back 52 times where 7000 did 44, with less
	-- road walled in (400 studs to 450) and no deeper cut or fill; 2500 turned 57 times but
	-- crossed one gully on 94 studs of fill)
	TraverseMax = 3500, -- studs
	TraverseReward = 1, -- (so a stud at the sustained grade costs nothing)
	TraverseRefund = 0.9, -- of the leg's length, refunded when choosing where it ends
	TraverseSteep = 45, -- studs of length per stud of height lost past the sustained grade
	TraverseEarthTol = 12, -- studs
	TraverseEarth = 6, -- studs of length per stud of depth
	TraverseDeep = 30, -- studs
	TraverseBendCost = 110, -- studs of length a radian of turn
	TraverseBand = 3000, -- studs
	TraverseHairpin = 500, -- studs of length
	TraverseSiteCost = 6000,
	TraverseRadiusSlope = 18,
	TraverseRadiusMax = 110, -- studs (so with its spread, 126 at most: tighter than `Dressing.Barrier.HairpinRadius`, railed as a hairpin)
	TraverseTurnMaxOff = 35, -- studs off h (fill, or cut scaled as `Spline.Ground.TurnMaxOff` is): a hairpin past this is tried again further on
	TraverseGiveUp = 3, -- times a hairpin may be refused before the next leg is surveyed from there
	TraverseLook = 300, -- studs
	TraverseLimit = 30, -- degrees
	TraverseFollowCost = 0.6, -- studs a degree off the leg, when no section follows h
	-- A steep pitch along a leg: grade past `PitchSustain` spends up to `PitchBudget` studs of
	-- height, paid back at `PitchRecover` of the shortfall when the grade eases under it (so
	-- 14 degrees lasts about 190 studs and 10 degrees about 470 before the grade must ease)
	PitchSustain = 6.5, -- degrees
	PitchBudget = 25, -- studs
	PitchRecover = 1,
	PitchSoft = 2, -- past the allowance: a stud of height gained too steeply counts as a stud off h
	-- The road along a leg (`SplineGen._track`): each curvature eased into and held for each
	-- of `TrackHolds` studs, judged on how far off the leg it ends, `TrackHeadingCost` a degree
	-- its heading misses a point `TraverseLook` on, and `TrackCurveCost` per 1/1000 of curvature
	TrackHolds = { 60, 140 }, -- studs
	TrackRadii = { 2000, 1000, 600, 400, 280, 200, 140, 100 }, -- studs
	TrackHeadingCost = 1.5,
	TrackCurveCost = 4,
	-- THE WEAVE (T-337): the line the road keeps to along a leg swings up and down the face
	-- either side of the surveyed one, `TraverseWeave` studs (picked a leg) over a whole wave of
	-- `TraverseWeaveWave` studs, never leaning more than `TraverseWeaveLean` off the leg (rise
	-- over run), so the leg is a run of S-bends cut into and built out from the hill rather than
	-- one straight line (the user: "the runs are really straight now, no real turns to enjoy";
	-- "it's okay to cut in and build out from/of the hill a bit"). It grows in over the first
	-- `TraverseWeaveIn` studs of a leg and is gone `TraverseWeaveOut` short of where the leg's
	-- stretch ends, so a hairpin, tight or not, is met from the surveyed line.
	TraverseWeave = { 70, 110 }, -- studs
	TraverseWeaveWave = { 450, 700 }, -- studs
	TraverseWeaveLean = 0.9,
	-- (on steep ground it swings no further than the face would fall this far over the swing,
	-- and every section along a leg is judged on how far off the hillside it leaves the road
	-- too: `TrackOffCost` a stud past `TrackOffTol`)
	TraverseWeaveOff = 25, -- studs
	TrackOffTol = 15, -- studs
	TrackOffCost = 2,
	TrackOffCheck = 8, -- of the best options are judged on it (its grade costs as much as the rest)
	-- (nor further from the surveyed line than its swing and `TrackStrayTol`: `TrackStrayCost`
	-- a stud past it)
	TrackStrayTol = 15, -- studs
	TrackStrayCost = 6,
	TraverseWeaveIn = 250, -- studs
	TraverseWeaveOut = 300, -- studs
	-- A CLIMB IN LEGS ACROSS THE FACE (T-332, `Road/SplineContourTraverse`): a climb's legs are
	-- surveyed as a descent's are (every `Traverse...` number above), mirrored up the face of the
	-- ridge ahead: a stud of height gained up to `ClimbGrade` earns, and a stud lost costs
	-- `ClimbLoss` times what it would earn. FORWARD PROGRESS FIRST: a leg drops no more than
	-- `ClimbBack` back down the face, comes no nearer the crest than `ClimbCrestMargin` (the road
	-- heads straight for the pass from in reach of it, `DirectReach`), and ends only where it has
	-- gained `ClimbMinGain` and `ClimbMinGrade` on average along its length; where no leg does,
	-- the old legs below (`LegMin` ...) climb the face instead
	ClimbLegs = true,
	ClimbGrade = 5, -- degrees: the sustained climb
	ClimbLoss = 3,
	-- (240 held a leg toward a peak, whose face rises along the crest, on a 10-degree climb the
	-- road could not follow: over 15 seeds of 60 000 studs, 3 225 studs of climbs walled in at
	-- 240, 1 150 at 600, 1 625 at 1 200)
	ClimbBack = 600, -- studs, of depth below the crest
	ClimbCrestMargin = 150, -- studs below the crest
	ClimbPassBelow = 40, -- studs: no leg runs on ground higher than this under the pass
	ClimbDirectGrade = 0.1, -- rise over run (6 degrees): from `DirectReach`, straight for the pass at up to this (`DirectGrade` for the old legs)
	ClimbMinGain = 60, -- studs
	ClimbMinGrade = 2, -- degrees
	-- (a climb's leg weaves as a descent's does, but swings no further than the face would rise
	-- this far over the swing, `TraverseWeaveOff` on a descent; 0: it does not weave)
	ClimbWeaveOff = 0, -- studs
	-- (heading away from where a climb's leg can go, the road turns round first, then surveys the
	-- leg from that hairpin's exit; once in this many studs at most)
	ClimbTurnFirstGap = 1500, -- studs
}
