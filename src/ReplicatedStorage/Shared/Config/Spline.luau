--!strict
-- Config.Spline: every number of the spline road (features/spline-road.md, T-132).
--
-- The spline road is ONE CONTINUOUS CURVE, described by three things that each change
-- smoothly with distance along it: how sharply it turns (curvature), how steeply it climbs
-- (grade) and how far it leans (bank). Each is a list of knots joined by straight lines,
-- so the turn eases in and out the way a real road's does (a clothoid), a crest is a
-- parabola, and nothing ever steps. `Road/Spline` is that maths; `Road/SplineGen` chooses
-- the knots from a seed.
--
-- THE TARMAC'S WIDTH AND COLOURS are still `Config.Road`'s. What lies either side of it --
-- the grass runoff, the rock face, hedge or cliff it ends in, the K-rails -- is `Terrain`
-- below (features/mountain-road.md, T-140). The road has no side barriers any more.

local Spline = {
	-- --------------------------------------------------------------- sampling the curve
	-- The plan position is the integral of the heading, which has no closed form for a
	-- clothoid, so it is integrated once (Simpson's rule) and kept every `SampleStep`
	-- studs. A query between two samples integrates the last few studs itself, so the
	-- curve is exact to well under a thousandth of a stud and never faceted: the spacing
	-- is a cost, not a resolution.
	SampleStep = 4, -- studs
	-- Points the no-crossing test and the "where am I" search are kept at. Coarser than
	-- the samples because the question they answer ("is any old road near here?") has a
	-- clearance of tens of studs.
	CheckStep = 8, -- studs
	HashCell = 64, -- studs: the grid those points are filed in

	-- --------------------------------------------------------------- what the curve may do
	-- THE TIGHTEST BEND, and the only number that decides whether a corner can be taken.
	-- 70 is the piece road's hairpin, which the car is proven on.
	MinRadius = 70, -- studs to the centre line
	MaxRadius = 900, -- studs; gentler than this is a straight to the eye
	-- HOW FAST THE TURN MAY TIGHTEN OR OPEN: curvature change per stud of road. Reaching
	-- the tightest bend from straight takes at least `MinRadius x` this many studs:
	-- 1 / (70 x 45) is 45 studs of easing into a hairpin, and twice that into a hairpin
	-- the other way straight out of one.
	MaxCurvatureRate = 1 / (70 * 45), -- 1/stud per stud
	MinTransition = 24, -- studs: no easing is shorter than this, however small the change

	-- GRADE, as in `Config.Road`: a safety lid, not a target. Real touge grades are 4-8.
	MaxGrade = 8, -- degrees
	-- How fast the grade may change: the crest and dip of a vertical curve. 0.0015 of grade
	-- per stud is the piece road's 1.15 degrees per 13-stud segment.
	MaxGradeRate = 0.0015, -- grade (dy/ds) per stud
	-- The road may not wander off up or down for ever: it keeps its height inside this band
	-- round where it started, and the grade is chosen to head back when it nears an edge.
	-- On a descent the band's centre drops as the road goes on (`Mountain.DescentRate`).
	MinHeight = -160, -- studs relative to the start
	MaxHeight = 160,
	-- How often a section keeps the grade it has rather than choosing a new one.
	KeepGradeChance = 0.35,

	-- BANK, raised on the OUTSIDE of the bend. 10 is what the user chose for the touge's
	-- banked corner (DECISIONS.md, 2026-11-06); `Config.Road.MaxBank`'s 30 is the most the
	-- car is proven on, and that is where this goes once the car can unstick from a wall.
	MaxBank = 10, -- degrees
	MaxBankRate = 1.5 / 13, -- degrees per stud: the piece road's `MaxBankStep` per chord
	-- A bend is banked in proportion to how tight it is, full bank at this radius or under.
	FullBankRadius = 160, -- studs
	UnbankedChance = 0.3, -- how often a bend is left flat anyway

	-- --------------------------------------------------------------- no crossing
	-- Two stretches of road that are not neighbours along the curve must keep their centre
	-- lines this far apart in plan: the tarmac, the widest runoff and an edge either side,
	-- and a gap (`SplineGen.limits`).
	ClearanceGap = 20, -- studs between the outer faces of the two stretches' edges
	-- With no mountain to follow (`Mountain.Mode = "traverse"`, not used yet) the road keeps
	-- its start heading and may wander this far off it either way. On a descent the legs'
	-- own limit (`Mountain.LegHeadingLimit`) does this job.
	HeadingLimit = 115, -- degrees either side of `Config.Road.StartHeading`
	-- Every section is accepted only if the road could still straighten up and run this far
	-- clear afterwards. That is the escape: the road can never box itself in, because the
	-- way out is checked before the way in is taken.
	EscapeLength = 260, -- studs of straight
	CandidateTries = 14, -- random sections tried before taking the escape itself

	-- --------------------------------------------------------------- the mountain's direction
	-- (features/mountain-direction.md, T-166.) The mountain has ONE FALL LINE, fixed in the
	-- world for the whole road: uphill one way, the valley the other. The road is laid as
	-- LEGS across the slope, each tilted a little downhill, joined by TURNAROUNDS (a hairpin,
	-- or a switchback of two tight bends) that send it back the other way, a level lower.
	-- Ordinary bends inside a leg stay within `LegHeadingLimit` of it, so only a turnaround
	-- can turn the road back. Chosen by the server from the seed; clients only replay.
	Mountain = {
		-- "descent" is the only one used. "ascent" climbs the same way (the legs tilt uphill
		-- and the height band rises); "traverse" is the road as it was before: no legs, the
		-- start heading kept within `HeadingLimit`, the height band fixed.
		Mode = "descent",
		-- Uphill is the start heading turned this far, to a side chosen from the seed, so the
		-- first leg runs across the slope.
		FallLineTurn = 90, -- degrees
		-- Heading within this of straight up or down the slope counts as neither side: the
		-- uphill side holds what it was, so a wiggle can't flip it (the cliff step).
		AlongFallLine = 30, -- degrees
		LegTilt = { 10, 25 }, -- degrees downhill off straight across
		LegLength = { 1200, 3000 }, -- studs, then a turnaround
		LegHeadingLimit = 60, -- degrees: no ordinary bend takes the road further off its leg
		LegUphillLimit = 30, -- degrees, and no further off it UP the slope, toward the leg above
		-- A turnaround: mostly a hairpin; sometimes two tight bends with a short run straight
		-- down the slope between them.
		HairpinRadius = { 75, 110 }, -- studs
		TurnaroundSwitchbackChance = 0.25,
		SwitchbackRadius = { 95, 150 }, -- studs, each of the two bends
		SwitchbackGap = { 40, 140 }, -- studs between them, heading down the slope
		-- A DOUBLE HAIRPIN in the middle of a leg: the road runs back the way it came for a
		-- short stretch, a level lower, then turns back onto its leg another level down.
		DoubleHairpinChance = 0.15, -- per leg
		DoubleHairpinBack = { 150, 500 }, -- studs of the reversed stretch
		-- A SIDEWAYS stretch in the middle of a leg: straight down (or now and then up) the
		-- slope for a while, then back onto the leg.
		SidewaysChance = 0.2, -- per leg
		SidewaysLength = { 300, 1200 }, -- studs
		-- of sideways stretches, how many climb rather than descend. 0: a climb ran into the
		-- leg above and boxed the road in on 2 seeds of 40 at 0.3 (measured), so they are off
		SidewaysUpShare = 0,
		SidewaysUpLength = { 200, 500 }, -- studs: a climb is kept short, below the leg above
		-- degrees its own bends may wander off straight up or down: inside `AlongFallLine`, so
		-- the uphill side holds through the whole stretch
		SidewaysLimit = 25,
		SidewaysRadius = { 150, 320 }, -- studs, the bends into and out of it
		-- A turnaround is laid only once the road heads within this of its leg; further off,
		-- a bend first brings it back, so every hairpin turns about the same amount.
		TurnWindow = 20, -- degrees
		-- Bends in a stretch lean back toward its line (from where it began, along its
		-- heading) as well as its heading: this far off the line, they aim back at half the
		-- stretch's heading limit. Keeps each leg on its own level of the slope.
		LineReach = 300, -- studs
		StraightenRadius = { 200, 500 }, -- studs, that bend
		-- When a planned turn is refused (it would come too close to old road), the stretch
		-- before it runs on this far and it is tried again.
		RetryAfter = 120, -- studs
		TurnTries = 6, -- radii tried for one planned turn before it is refused
		-- THE DESCENT: the height band (`MinHeight..MaxHeight`) moves with the road, its centre
		-- dropping this much per stud of road, so the grade still goes up and down locally but
		-- the run works its way down. 1 in 25 is about 2.3 degrees net.
		DescentRate = 1 / 25, -- studs of height per stud of road
	},

	-- --------------------------------------------------------------- the bends
	StartStraight = 220, -- studs of straight the road begins with (a car spawns 20 in)
	StraightChance = 0.4, -- after a bend, how often a straight comes next
	StraightLength = { 60, 260 }, -- studs
	-- Each kind of bend: a radius range, a turn range, a weight, and how far into the road
	-- before it may appear (`minS`). A kind used a lot recently is chosen less, as the piece
	-- road's chooser does, so the mix stays even.
	Bends = {
		{ name = "Hairpin", radius = { 70, 95 }, turn = { 120, 195 }, weight = 1, minS = 1500 },
		{ name = "Tight", radius = { 95, 170 }, turn = { 45, 120 }, weight = 2, minS = 0 },
		{ name = "Medium", radius = { 170, 340 }, turn = { 30, 95 }, weight = 3, minS = 0 },
		{ name = "Sweeper", radius = { 340, 900 }, turn = { 15, 60 }, weight = 2, minS = 0 },
	},
	RecentBends = 6, -- how many bends back the chooser counts
	SwitchbackChance = 0.45, -- how often a bend is followed straight away by one the other way

	-- --------------------------------------------------------------- the mountainside
	-- What lies either side of the tarmac (features/mountain-road.md, T-140). Each side, at
	-- every s: tarmac to `Config.Road.Width / 2`, then grass runoff, then an EDGE. Chosen by
	-- the server with the curve (`SplineGen`), sent with each section, replayed by clients.
	Terrain = {
		-- THE RUNOFF: a strip of grass each side, its width eased (smoothstep) between knots
		-- so nothing steps. Grass grips and scores as `Config.Drift.GripGrass` / `ScoreGrass`.
		RunoffMin = 12, -- studs, about 2 car widths
		RunoffMax = 40, -- studs, about 5
		RunoffKnotEvery = { 120, 220 }, -- studs between two widths chosen
		StartRunoff = 24, -- studs, both sides, on the straight a run begins with
		-- On the inside of a bend the grass never reaches past this share of the way to the
		-- bend's centre, so the inside of a hairpin keeps a strip, not a spike.
		InsideShare = 0.6,
		-- THE EDGES. A rock face and a hedge are walls at the runoff's outer edge; a cliff is
		-- where the ground ends.
		RockHeight = { 25, 60 }, -- studs. A look; to the car it is a wall
		RockSlope = { 50, 70 }, -- degrees
		HedgeHeight = 6, -- studs
		HedgeThickness = 4, -- studs
		CliffDrop = 80, -- studs the face is drawn down into haze
		-- How far past the runoff an edge reaches, for keeping two stretches of road apart.
		EdgeDepth = 4, -- studs: a hedge's thickness, and the foot of a rock face
		-- WHICH SIDE IS UPHILL is kept for a long stretch, then swaps through a straight with
		-- hedge both sides (the road crossing a ridge). Never in a bend.
		UphillStretch = { 900, 2600 }, -- studs between two swaps
		UphillHedgeChance = 0.2, -- per section: hedge instead of rock on the uphill side
		DownhillHedgeChance = 0.15, -- per section: hedge instead of cliff on the downhill side
		-- K-RAILS: drawn as METAL CRASH BARRIERS (T-149): a W-beam steel guardrail held off
		-- square posts on spacer blocks, a striped hazard panel at each end of a run; the
		-- `KRail` names stay, since the generator and the car's collision read them. To the
		-- car it is a wall `KRailThickness` thick and `KRailHeight` high, inner face exactly on
		-- the tarmac's edge; the drawn beam's face is on that edge and its top at
		-- `KRailHeight`, its spacers and posts inside the wall.
		KRailHeight = 3, -- studs: the car's wall, and the drawn beam's top
		KRailThickness = 2, -- studs: the car's wall (the drawn barrier is thinner)
		KRailRun = { 60, 300 }, -- studs
		KRailBendChance = 0.5, -- on the outside of a bend whose outside is a cliff
		KRailOtherChance = 0.08, -- per section, on either side, anywhere else
		-- The drawing only (`Road/SplineMesh`): the beam's W profile is two rounded ridges
		-- with a groove between, `KRailBeam` tall in all, its top at `KRailHeight`.
		KRailBeam = 1.2, -- studs, the beam's height
		KRailRidge = 0.35, -- studs, how far each rounded ridge stands out from the groove
		KRailPostEvery = 7, -- studs between posts
		KRailPostSize = 0.4, -- studs, a square post's side
		KRailSpacer = 0.4, -- studs, the block holding the beam off a post
		KRailSpliceEvery = 2, -- posts between two splices of the beam, each with its bolts
		KRailSpliceBolts = 2, -- bolt heads drawn at a splice (0: none)
		KRailStep = 12, -- studs, the longest straight piece of beam (bends cut it finer)
		-- Programmer colours (the look is set with the next feature)
		GrassColour = Color3.fromRGB(86, 140, 62),
		HedgeColour = Color3.fromRGB(44, 92, 40),
		RockColour = Color3.fromRGB(112, 108, 102),
		ScrubColour = Color3.fromRGB(78, 104, 58), -- the ledge on top of a rock face
		CliffColour = Color3.fromRGB(104, 96, 88),
		HazeColour = Color3.fromRGB(196, 210, 222), -- the foot of a cliff fades into this
		-- the guardrail, beam and posts: galvanized steel. Many in Japan are painted white:
		-- swap in the line below for that
		KRailColour = Color3.fromRGB(176, 182, 186),
		-- KRailColour = Color3.fromRGB(236, 236, 232), -- painted white
		KRailBoltColour = Color3.fromRGB(58, 60, 62),
		KRailHazardColours = { Color3.fromRGB(246, 196, 24), Color3.fromRGB(24, 24, 24) }, -- the end panel's stripes
	},

	-- --------------------------------------------------------------- the mesh (step 3)
	-- What each device draws (`Road/SplineMesh`, `Drift/SplineRoadView`). Purely visual.
	Mesh = {
		-- How far the drawn surface may stand off the true one between two cross-sections,
		-- at the centre and at both kerbs. Cuts go as far apart as this allows.
		Tolerance = 0.05, -- studs
		MaxStep = 12, -- studs between cross-sections on a straight
		MinStep = 1, -- and never closer than this, however tight the bend
		-- Strips across the road. Where the bank rolls on a grade through a bend the surface
		-- twists, and one full-width triangle cannot follow it (6.5 degrees off, measured).
		Across = 4,
		-- studs of road per chunk. A chunk holds one EditableMesh while it is drawn, and a
		-- client may hold only eight (measured), so the window round the car is kept to five
		-- or six chunks: (Ahead + Behind) / ChunkLength + 1, plus the one being built
		ChunkLength = 480,
		Ahead = 1600, -- studs of road drawn in front of the car
		Behind = 300, -- and kept behind it
		FallbackStep = 4, -- studs between cross-sections when a device draws parts instead
	},

	-- --------------------------------------------------------------- the Studio test road
	-- `SplineTestService` (Studio only): a spline road to drive before the run lays one.
	-- Far out on +X, clear of the track, the playground, the garage and the piece road.
	TestOrigin = Vector3.new(30000, 0, -20000),
	TestLength = 8000, -- studs
}

return Spline
