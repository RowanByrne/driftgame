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
-- the grass runoff, the rock face or cliff it ends in, the K-rails -- is `Terrain`
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
	-- banked corner (DECISIONS.md, 2026-11-06); 30 is the most the car is proven on (the old
	-- piece road's `MaxBank`), and that is where this goes once the car can unstick from a wall.
	MaxBank = 10, -- degrees
	MaxBankRate = 1.5 / 13, -- degrees per stud: the old piece road's 1.5 degrees per 13-stud chord
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
		-- Fit sharp turns to the same hill the client draws (T-190). Clear radii are
		-- ranked by excess rock ahead and by cutting/fill at the runoff's sides.
		TurnChecks = true,
		TurnFitTries = 3, -- fixed terrain-preview budget per sharp turn
		TurnCheckAngle = 60, -- degrees: smaller heading corrections keep the old path
		TurnViewDistances = { 50, 100, 150 }, -- horizontal checks from three places round a turn
		TurnViewExcess = 15, -- studs above the eye plus the natural uphill plane
		TurnSideReach = 20, -- studs beyond runoff for the sideways checks
		TurnMaxCut = 90, -- studs: a very deep cutting near a turn
		TurnMaxFill = 120, -- studs: an outsized embankment/drop near a turn
		TurnLocationRetries = 2, -- run on RetryAfter and retry before taking the best clear fit
		TurnDescentGrade = 0.025, -- downhill grade target in a descending turn, band safety wins
		-- THE DESCENT: the height band (`MinHeight..MaxHeight`) moves with the road, its centre
		-- dropping this much per stud of road, so the grade still goes up and down locally but
		-- the run works its way down. 1 in 25 is about 2.3 degrees net.
		DescentRate = 1 / 25, -- studs of height per stud of road
		-- THE CLIMBS that let a run go on for hours (the user, 2026-11-13: "we want a system
		-- that will allow for hours of running ... add uphill sections that are short and gain
		-- good vertically every now and then"). Once the band's centre is `DescentFloor` below
		-- the start, it rises at `ClimbRate` until it is back at `ClimbTop`, then the descent
		-- goes on.
		-- A CLIMB IS THE FAR SIDE OF A VALLEY (T-190). The road keeps zig-zagging the same way
		-- in plan, so while it climbs, each new leg is HIGHER than the one before it: the
		-- mountain is on the other side of the road. So a climb (and the descent after it)
		-- begins where the road next heads straight along the fall line, the middle of a
		-- hairpin as a rule, and from there the rock and the drop are on the other sides
		-- (`SplineGen.flip`). The band waits at `DescentFloor` (or `ClimbTop`) for that turn,
		-- and the stretches planned before it are cut to `FlipWithin` so it comes soon.
		-- With the band's 160 either side, the road stays above Y -440, clear of Roblox's
		-- fall-kill height (-500).
		DescentFloor = -280, -- studs, the centre's lowest, relative to the start
		ClimbRate = 1 / 10, -- studs of height per stud of road, about 5.7 degrees
		ClimbTop = 0, -- studs, where a climb hands back to the descent
		FlipWithin = 250, -- studs: the longest stretch left before the turn the mountain changes sides in
		-- but that turn comes no sooner than the faces already drawn were told it would: they
		-- are grand by their distance from a turnaround, full at `GrandNear + GrandRamp`
		FlipClear = 850, -- studs
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
		-- THE RAISED ROAD (T-184): the grass sits `RoadLip` below the tarmac's edge, reached
		-- down a straight GRAVEL BEVEL `RoadLipWidth` across (the user, 2026-11-13: "an angled
		-- section of like gravel ... that bridges the gap from the road down to the grass"),
		-- drawn in `GravelColour` and gripping as gravel. Everything on the runoff -- the
		-- grass, a hedge, the foot of a rock face, a cliff's lip -- stands on the lower ground.
		-- To the car it is no wall: a wheel on it rolls down and the drawn car tips (the plane
		-- through its wheels, `Drift/Model`); a wheel coming back rolls up it. Keep `RoadLip`
		-- under `RideHeight` (2.4): a wheel more than that below the others no longer carries
		-- the car
		RoadLip = 1, -- studs (the user, 2026-11-13: "do 1 stud of height instead")
		RoadLipWidth = 3, -- studs across the bevel ("make the gravel zone 3 studs wide"): about 18 degrees
		LipShare = 0.75, -- the most of a narrow runoff the bevel takes (a tight cliff edge's
		-- 2.5 to 3.5 studs of gravel is a 1.9 to 2.6 bevel and a flat strip before its lip; a
		-- carved apex's 1 stud, a 0.75 gutter)
		-- A CARVED APEX (T-182): on some sharp bends whose inside is the rock face and whose
		-- outside is the cliff, the inside grass narrows to almost nothing at the apex, so the
		-- rock rises right at the tarmac's edge, as if the road were cut into the cliff
		CarvedChance = 1, -- of the bends that could have one (about 1.1 per 10 000 studs, measured)
		CarvedMaxRadius = 220, -- studs: hairpins, tight bends and the tightest medium ones
		CarvedGap = 1, -- studs of grass left between the tarmac and the rock at the apex
		CarvedHold = { 20, 50 }, -- studs the rock stays that close, round the apex
		CarvedEase = 40, -- studs, at least, easing in and out
		-- the most the width changes per stud, on average between two knots (smoothstep's
		-- steepest is 1.5 times it). Steeper than the runoff's own 0.25, or a bend is too
		-- short to fit one; the car's wall leans with it, so it grinds rather than snags
		CarvedRate = 0.4,
		-- THE EDGES. A rock face is a wall at the runoff's outer edge (so is a hedge, never
		-- chosen as an edge since T-189); a cliff is where the ground ends. To the car only:
		-- nothing draws them since T-247 (the ground mesh stands in, `Drift/GroundMeshView`).
		-- The grand, tight and low numbers below still shape the section's `gd` knots, which
		-- nothing reads either; they go with the old descent planner (features/legacy-removal.md)
		-- The heights and slopes here are near a turnaround; mid-leg they grow to the `Grand`
		-- numbers below. `RockHeight[1]` is also the car's wall height (`Drift/SplineWorld`)
		RockHeight = { 25, 60 }, -- studs. A look; to the car it is a wall
		RockSlope = { 50, 70 }, -- degrees
		HedgeHeight = 6, -- studs
		HedgeThickness = 4, -- studs
		-- GRAND CLIFFS (T-185). The user, 2026-11-13: "cliffs should be more solid bodied and
		-- grand. the farther you get from a switchback, we can have sections where the average
		-- cliff height is huge, and then comes back down again as we near a switchback".
		-- A rock face is a SOLID BODY: its face, a top of scrub `RockTop` deep, and a back
		-- slope down to the ground `RockBack` of its height behind, closed at both ends. A
		-- cliff is a jagged face with closed ends.
		-- HOW GRAND, 0..1, is chosen by the server with each section (`gd` knots) from how far
		-- the road is from the nearest turnaround (hairpin, switchback or double hairpin):
		-- 0 within `GrandNear`, rising (smoothstep) to 1 over `GrandRamp` more. And never so
		-- tall that a rock body would stand up through old road on its uphill side (the leg
		-- above): it stays `GrandMargin` under that road wherever it reaches beneath it.
		GrandNear = 250, -- studs from a turnaround
		GrandRamp = 600, -- studs, then full
		GrandKnotEvery = 60, -- studs between two knots of a section's grandeur
		GrandRate = 300, -- studs, at the least, for the grandeur to go from 0 to 1 or back
		GrandMargin = 12, -- studs a rock body's top keeps under old road above it
		-- and short of that road, it may stand above it by this many studs for every stud it
		-- keeps off it, so no pinnacle towers right beside the leg above. Measured over five
		-- seeds, mid-leg (850+ studs from a turnaround) grandeur averages 0.54 at 1, 0.81 at 2,
		-- 0.87 at 3 and 0.92 with no limit but the road above (0.78 at 2 with `GrandRate`)
		GrandAbove = 2,
		GrandRockHeight = { 140, 220 }, -- studs, mid-leg (`RockHeight` near a turnaround)
		GrandRockSlope = { 64, 78 }, -- degrees, so a tall face doesn't reach out for ever
		RockTop = { 14, 36 }, -- studs of scrub on top, near and grand
		RockBack = 0.36, -- the back slope's run, as a share of the height
		-- LOWER THAN NEAR A TURNAROUND (T-189): with no hedges, the uphill side just past a
		-- hairpin is rock too, right under the leg you came down. Where even a low body would
		-- stand up through that road, the grandeur goes below 0 (to -1) and the body shrinks
		-- toward these, so it stays under the leg above. The car's wall stays `RockHeight[1]`
		LowRockHeight = 4, -- studs, at -1
		LowRockTop = 3, -- studs of scrub on top, at -1
		-- How far past the runoff an edge reaches, for keeping two stretches of road apart.
		EdgeDepth = 4, -- studs: a hedge's thickness, and the foot of a rock face
		-- WHICH SIDE IS UPHILL follows from the heading against the fall line (T-166,
		-- `Mountain.AlongFallLine`): no stretch length and no random swap any more. The uphill
		-- side is always rock and the downhill side always the drop: NO HEDGES as a road edge
		-- (T-189). They come back later as decoration; `HedgeHeight` and the rest stay for it.
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
		KRailChordTolerance = 0.04, -- studs: margin for changing curvature and beam end pieces
		KRailStep = 12, -- studs, the longest straight piece of beam (bends cut it finer)
		-- TIGHT CLIFF EDGES (T-181): the user, 2026-11-13, "some cliff edges should be barrier
		-- rails that are right on the edge of the asphalt with less than 3 or 4 studs of gravel
		-- before the cliff". In a section with a cliff the whole way along one side, now and
		-- then the runoff closes in to a strip of GRAVEL a few studs wide, a crash barrier on
		-- the tarmac's edge and the lip just past it, then opens out again. Gravel grips and
		-- scores as `Config.Drift.GripGravel` / `ScoreGravel`.
		TightChance = 0.3, -- per section with a cliff its whole length on a side
		TightRunoff = { 2.5, 3.5 }, -- studs of gravel between the tarmac and the lip
		TightRun = { 80, 270 }, -- studs at that width (with `TightLead` each end, a rail inside `KRailRun`)
		TightRate = 0.4, -- studs of width per stud the runoff closes in and opens out
		TightRamp = 20, -- studs, the shortest closing in or opening out
		TightLead = 12, -- studs the rail and the gravel reach past each end of the narrow part
		-- Programmer colours (the look is set with the next feature)
		GrassColour = Color3.fromRGB(86, 140, 62),
		GravelColour = Color3.fromRGB(146, 138, 124), -- a tight cliff edge's strip (T-181)
		-- the guardrail, beam and posts: galvanized steel. Many in Japan are painted white:
		-- swap in the line below for that
		KRailColour = Color3.fromRGB(176, 182, 186),
		-- KRailColour = Color3.fromRGB(236, 236, 232), -- painted white
		KRailBoltColour = Color3.fromRGB(58, 60, 62),
		KRailHazardColours = { Color3.fromRGB(246, 196, 24), Color3.fromRGB(24, 24, 24) }, -- the end panel's stripes

		-- GROVES (T-183): on a flat, gentle section a side's runoff widens to `GroveRunoff` and
		-- is dressed with low-poly trees and bushes (`Road/SplineGrove`), set back from the
		-- tarmac, so they hide the long views across the mountain. Chosen by the server with
		-- the section (`gv`, a seed per side); every device places the same trees from it.
		-- A section qualifies when no part of it is tighter than `GroveMinRadius`, steeper
		-- than `GroveMaxGrade` or shorter than `GroveMinLength`; then a grove `GroveChance` of
		-- the time, on one side, both `GroveBothChance` of those.
		GroveChance = 0.8,
		GroveBothChance = 0.3,
		GroveMinRadius = 200, -- studs: a wide bend or a straight
		GroveMaxGrade = 6, -- degrees (the road averages about 2.3 down, 8 at most)
		GroveMinLength = 120, -- studs
		-- The wide runoff. NO-CROSSING NEEDS NOTHING NEW up to `RunoffMax + ClearanceGap` (60):
		-- two stretches' centre lines are kept apart by both widest runoffs, both edges and the
		-- gap, so one side may take the gap's width and still never reach the other road's edge.
		GroveRunoff = { 46, 58 }, -- studs
		-- The trees: one item every `GroveSpacing` studs along the road, its offset past the
		-- tarmac random between its setback and the grass's outer edge (less its own size).
		-- A tree's trunk is a wall to the car (`Drift/SplineWorld`); a bush is not.
		GroveSpacing = { 3, 7 }, -- studs
		TreeSetback = 16, -- studs past the tarmac's edge: never a wall at the road's edge
		BushSetback = 8,
		GroveKinds = { conifer = 0.5, broadleaf = 0.2, bush = 0.3 }, -- shares of the items
		ConiferHeight = { 20, 34 }, -- studs
		BroadleafHeight = { 14, 22 },
		BushHeight = { 2.5, 5 },
		TrunkRadius = { 0.8, 1.4 }, -- studs: drawn and solid
		-- Programmer colours, a few shades each so a grove isn't one flat green
		ConiferColours = { Color3.fromRGB(40, 78, 46), Color3.fromRGB(52, 90, 50), Color3.fromRGB(34, 66, 44) },
		BroadleafColours = { Color3.fromRGB(78, 120, 54), Color3.fromRGB(92, 130, 60) },
		BushColours = { Color3.fromRGB(62, 104, 50), Color3.fromRGB(74, 112, 54) },
		TrunkColour = Color3.fromRGB(92, 70, 52),
	},

	-- --------------------------------------------------------------- the grass's texture
	-- The user, 2026-11-13: "give grass it's own texture" (T-187), then picked a painted
	-- grass tile from four looks (DECISIONS.md). One image every chunk shares
	-- (`Road/GrassTexture`), tiled over the grass faces in world studs. Everything else on the
	-- road's mesh samples its plain corner.
	Grass = {
		Enabled = true, -- false: flat grass, and the road's mesh as it was before
		-- the painted tile: 512 x 512, grey, evened out to average `Shade`, tiling seamlessly
		-- (`assets/grass-texture/grass-painted-grey512-v2.png`, MANIFEST.md there). v1 (256 px,
		-- 24 studs) showed seam lines and repeated plainly: the user, "very visible repeating patterns"
		Image = "rbxassetid://86031628618959",
		TileStuds = 48, -- studs one tile covers, each way (about 10.7 pixels a stud)
		-- What Roblox's Asphalt map multiplied the whole road's mesh by (measured, T-187: the
		-- tarmac drawn without it came out twice as bright). The texture's plain corners are
		-- this grey, so the tarmac, gravel, rocks and trees keep their brightness, and the
		-- tile averages it, so the grass keeps its own. Raise it to lighten all but the grass.
		Shade = 0.49,
		-- BLOTCHES over the tile, so neighbouring tiles never look alike: each grass vertex is
		-- lighter or darker by up to `Blotch`, from smooth noise over `BlotchStuds` cells in
		-- world X and Z (two octaves), blended across each face by the vertex colours
		Blotch = 0.12,
		BlotchStuds = 70,
	},

	-- --------------------------------------------------------------- the ground
	-- (features/ground-trial.md, T-218; the only ground since T-247, features/legacy-removal.md.)
	-- The ground BUILT FIRST, as one mountain the road is cut into (`Road/Ground`), drawn by
	-- each client as its own grid meshes (`Drift/GroundMeshView`).
	Ground = {
		-- THE MOUNTAIN, h(x, z), through the road's start. A pure function of the seed and the
		-- place. Since T-228 (the user: "sections where it gets very steep for several thousand
		-- studs, and sections where it's quite shallow ... big ridges that carve in and
		-- promontories that stick out"), and the road follows whatever it is (T-227):
		-- BELTS down the fall line: going down, a shallow BENCH (`Bench` studs of fall line at a
		-- slope from `Low`), a ramp (`Ramp` studs, eased), a steep SCARP (`Scarp` studs at a
		-- slope from `High`), a ramp, the next bench; each one's sizes from the seed. The road
		-- spends about as long on a scarp as on a bench: it loses height at its own rate, and a
		-- scarp is short but tall. Laid out `BeltsUp` studs up the fall line from the start and
		-- `BeltsDown` down, every `BeltStep`; past them, straight on. The belts curve across the
		-- mountain, up to `BeltWarp[1]` studs up or down it over `BeltWarp[2]` across.
		BeltBench = { 2000, 4000 }, -- studs of fall line
		BeltScarp = { 250, 600 }, -- studs of fall line
		BeltRamp = 300, -- studs of fall line
		BeltLow = { 0.03, 0.09 }, -- slope: about 2 to 5 degrees
		BeltHigh = { 0.45, 0.6 }, -- slope: about 24 to 31 degrees (27 to 37 left the road stranded above scarps)
		BeltsUp = 10000, -- studs of fall line
		BeltsDown = 60000,
		BeltStep = 16, -- studs
		BeltWarp = { 300, 4000 }, -- studs
		-- RIDGES AND GULLIES on the belts: {studs across, studs either way, kind} per octave of
		-- noise, `Stretch` times longer down the fall line than across it, so they run down the
		-- mountain. "ridge": sharp crests, promontories standing out; "gully": V-shaped, carving
		-- in; none, rounded. Their height is scaled by how steep the belt is there: `ReliefLow`
		-- of it where the belt's slope is `ReliefSlopes[1]` or less, all of it from `[2]`
		Octaves = { { 1400, 80, "ridge" }, { 600, 35, "gully" }, { 220, 8 } },
		Stretch = 2.5,
		ReliefLow = 0.25,
		ReliefSlopes = { 0.05, 0.6 },
		-- THE MOUNTAIN LEADS, THE ROAD FOLLOWS (T-226, features/road-on-the-slope.md). In a
		-- ground run the road reads everything from h alone, with no height band, descent rate
		-- or fixed heading of its own, so changing h changes the road with no road code touched.
		-- ITS HEIGHT: each section's grade is the one whose road best fits h along its centre
		-- line (every `FollowStep` studs), and `FollowAhead` studs on past its end (counted
		-- `FollowAheadWeight` as much), within the grade and vertical-curve limits. h is taken
		-- as the mean of five points `FollowRadius` apart, so the road ignores the smallest bumps
		-- chosen a piece of `FollowSegment` studs at a time. A random bend that would still leave
		-- the road more than `FollowMaxOff` off h gives way to one that follows it
		FollowStep = 8, -- studs
		FollowSegment = 64, -- studs
		FollowMaxOff = 10, -- studs
		FollowAhead = 160, -- studs
		FollowAheadWeight = 0.5,
		FollowRadius = 16, -- studs
		-- ITS ANGLE ACROSS THE MOUNTAIN: from h's slope where the road is heading (the gradient
		-- `AimSpan` studs across, at each of `AimAt` studs ahead), a leg heads across the local
		-- fall line, tilted down it just enough to descend `LegGrade` (one per leg, from the
		-- plan's stream): nearly across where h is steep, more directly down where it is gentle,
		-- at most `LegTiltMax` off across (straight down the fall line is a sideways stretch's).
		-- Its bends may stray no further down the slope than keeps the grade within
		-- `FollowGrade` of `MaxGrade` (never under `AimMinLimit`), so the road can follow h there.
		-- `DownhillBias` adds the plane's own downhill to h's slope, so flat ground has a way down
		AimAt = { 60, 180 }, -- studs ahead
		AimSpan = 60, -- studs
		LegGrade = { 0.035, 0.07 }, -- descent per stud of road along a leg: 2 to 4 degrees
		LegGradeSteep = 0.1, -- plus this much of h's slope there (T-228), to `FollowGrade` at most
		-- less this much a stud for every stud the road is above h where it is (more if below):
		-- a road left above the mountain turns across it until the mountain is back
		CatchUp = 1 / 150, -- (1 / 100 measured worse on 20 seeds, and one boxed in)
		LegTiltMax = 75, -- degrees off straight across
		FollowGrade = 0.9,
		-- A SHARP PLANNED TURN (a hairpin, a switchback) that would leave the road more than
		-- `TurnMaxOff` studs off h is laid further on (`Mountain.RetryAfter` each time, up to
		-- `TurnRetries` times) where it fits better: mid-turn the road heads straight down
		-- the slope, which a steep scarp leaves it far above (T-228)
		TurnMaxOff = 20, -- studs
		-- ON THE RANGE (T-238, DECISIONS.md 2026-11-15, hairpins hug the steep face): a
		-- turnaround is fitted with each stud of road above h counting `TurnFill` times one
		-- below, so it sits in a cut (a wall on its inside) rather than out on fill, and may
		-- be up to `TurnMaxCut` studs below h where `TurnMaxOff` is the most above it
		TurnFill = 4,
		TurnMaxCut = 45, -- studs
		TurnRetries = 6,
		AimMinLimit = 5, -- degrees (12 let a road on a 40-degree scarp stray to a 13-degree grade)
		DownhillBias = 0.05, -- (0.01 let the aim swing round on a near-flat bench and the road box itself in, T-228)
		-- THE CUT: under the road and its runoff the ground sits this far below their surface,
		-- and past the runoff's outer edge it blends back to h, never over more than `BlendMax`
		-- studs; how steeply, from the side slope (`BlendAngles`, below; 45 degrees and at least
		-- 20 studs until T-228)
		Under = 0.25, -- studs
		BlendMax = 60, -- studs
		-- WHAT IS BESIDE THE ROAD FROM THE SIDE SLOPE (T-228, features/road-on-the-slope.md): how
		-- steep h is across the road, from h `SideSpan` studs either side of the centre line,
		-- read as 0 under `SlopeShallow` degrees, 1 over `SlopeSteep`, eased between. From it:
		-- the runoff, `RunoffWide` studs on shallow ground to `RunoffThin` on steep (a width
		-- every `RunoffSlopeEvery` studs, changing no faster than a quarter of a stud a stud);
		-- and the cut or fill past the runoff's edge, at `BlendAngles` (shallow, steep) and no
		-- narrower than `BlendMins`: a slight lip and drop on shallow ground, a wall uphill and
		-- a drop downhill on steep. Their heights are what it takes to lay the road and its
		-- runoff flat into that slope
		SideSpan = 48, -- studs
		SlopeShallow = 8, -- degrees
		SlopeSteep = 30, -- degrees
		RunoffWide = 40, -- studs
		RunoffThin = 12, -- studs
		RunoffSlopeEvery = 32, -- studs
		BlendAngles = { 30, 65 }, -- degrees: shallow, steep
		BlendMins = { 20, 6 }, -- studs: shallow, steep
		BlendFoot = 1.5, -- studs past the runoff's edge, flat, before the cut or fill begins
		RockAngle = 45, -- degrees: ground steeper than this is drawn as rock
		-- how a point hears the road: how far past the edge it is, from the nearest point of
		-- the centre line (T-237); along the road, the stations (every `CheckStep` studs)
		-- hand over smoothly; and of two stretches the nearer edge wins over `Soft` studs, so
		-- the line between them has no seam. `Look` is only a margin the tests keep (it was how far from square beside
		-- it a station answered, until T-237)
		Look = 16, -- studs
		Soft = 3, -- studs
		-- THE ROAD is drawn with a skirt from each runoff's outer edge `Skirt` studs down,
		-- leaning `SkirtLean` out, so where the ground drawn apart dips below the edge no gap
		-- shows
		Skirt = 10, -- studs
		SkirtLean = 1.5, -- studs
		SkirtColour = Color3.fromRGB(70, 104, 54),

		-- THE MESH (`Drift/GroundMeshView`, T-220; redrawn as tiles in T-225): the ground drawn as small square TILES, each `TileCells` cells across, as a
		-- quadtree (`Drift/GroundTiles`): a tile `Spacings[k]` studs between vertices splits into
		-- four of the next finer while it is too coarse for how near it is to the car, or to the
		-- road (`Detail` below, the player's "Ground detail" setting). Tiles never overlap;
		-- where a finer tile meets a coarser one its edge takes the coarser one's heights, so
		-- the two meet without a crack.
		-- THE BUDGET: a client holds only so many mesh triangles, about 81 000 in Studio on a PC,
		-- the road's included (measured, T-225: 158 tiles of 512 triangles, 38 of 2 048 or 271
		-- of 128 into what was left; vertices, normals and colours do not count). A mesh run's
		-- road holds 10 000 to 17 000, more while a chunk is being built, so the ground holds
		-- `Detail[k].Tiles` tiles of 128 triangles, plus `Spare` built hidden before a change is
		-- shown. Small tiles: a road corridor wastes less of a tile, so the same triangles reach
		-- three times as far along the road as 16-cell tiles did (measured on seed 31337)
		TileCells = 8,
		Spacings = { 8, 16, 32, 64, 128 }, -- studs between vertices, finest first: tiles 64 to 1 024 studs
		-- per spacing: a vertex this near a runoff's edge is held below it, so no triangle
		-- reaching over from a cutting covers the road (a triangle holding a point of road has
		-- every vertex within 1.41 cells of it); so a cutting starts about a cell out. The
		-- road keeps its tiles to 32 studs or finer as far as it is drawn, so the last two
		-- never meet drawn road
		Clamps = { 12, 24, 46, 64, 64 }, -- studs
		-- per spacing: every vertex sinks this under the road and runoff (and under the edge
		-- within its clamp), more for coarser tiles, whose triangles bridge more of the road's
		-- curve between two vertices
		Sinks = { 1.25, 1.5, 2.5, 4, 4 }, -- studs
		-- THE WALL'S FOOT (T-231): holding grid points below the edge out to `Clamps` drew every
		-- cut wall as a sawtooth where the road runs at an angle across the grid. Now a vertex
		-- past a runoff's edge with a neighbour on the road moves onto the edge, `SnapFoot`
		-- studs past it (on the flat foot before the cut or fill), at most `SnapMax` of a cell,
		-- and is held below the edge there, so the wall rises from a line along the road.
		-- (`Clamps` still holds a vertex that cannot move, and one shared with a tile of another
		-- spacing.) Each cell is split along the diagonal nearer the ground at its middle,
		-- where the two differ there by `FitGap` studs or more, never along one joining a
		-- vertex on the road to open ground
		SnapFoot = 0.75, -- studs past the runoff's edge (`BlendFoot` is the flat foot's width)
		-- (0.9 left a road running along a grid line with its wall a cell out: the vertex a
		-- cell from the foot is up to a cell from it, measured on seed 31337)
		SnapMax = 1, -- of a cell
		FitGap = 0.2, -- studs
		-- tiles this fine or finer move their vertices; coarser ones (far ahead) hold them below
		-- the edge out to `Clamps`, as before: moved on a 32-stud tile, the drawn ground stood
		-- 5.8 studs over a runoff's edge (measured, seed 31337)
		SnapUpTo = 16, -- studs between vertices
		MeshSliceMs = 2, -- ms of building a frame
		FirstSliceMs = 6, -- ms a frame while nothing is drawn yet (a run's first second)
		Spare = 24, -- tiles built hidden, then swapped in whole, so a change never shows half done
		Hysteresis = 1.2, -- a split tile stays split until it is this much past needing it
		Reselect = 12, -- studs the car moves before the tiles are chosen again
		-- THE ROAD'S DETAIL: from `Mesh.Behind` back to `Mesh.Ahead` on along it (as far as the
		-- road is drawn), every `RoadStep` studs, a point of road wants tiles within
		-- `RoadRange` times their spacing of it finer than 8 studs * (how far along it is /
		-- `Detail[k].Fine`), and never coarser than `RoadCoarsest`
		RoadStep = 32, -- studs
		RoadRange = 4, -- 8-stud tiles within about 32 studs of the road's middle, 16 within 64...
		RoadCoarsest = 32, -- studs
		RoadPad = 256, -- studs: tiles this near the drawn road are drawn even past `Reach`
		ReleaseOnFail = 24, -- tiles let go if the device will not make another (room for the road)
		-- THE PLAYER'S "GROUND DETAIL" (Settings, Graphics; docs/game/SETTINGS.md), light to far.
		-- `Tiles`: how many may show (the nearest first; past that, ground stays coarser).
		-- `Fine`: along the road, 8-stud ground this far ahead, 16 to twice that, 32 beyond.
		-- `Ratio`: round the car, a tile of spacing s splits while it is nearer than s * Ratio
		-- (16: 8-stud cells within about 256 studs, 16 to 512, 32 to 1 024, 64 to 2 048).
		-- `Reach`: how far round the car the ground is drawn at all; past it is sky and fog.
		-- `Ratio` is kept modest on purpose: each tile spent round the car is one fewer along the
		-- road ahead, where the player looks (measured on seed 31337: Ultra at Ratio 20 kept
		-- 8-stud ground to about 1 000 studs ahead, at 14 to about 1 500)
		Detail = {
			{ Name = "Light", Tiles = 128, Fine = 300, Ratio = 8, Reach = 1100 },
			{ Name = "Low", Tiles = 176, Fine = 500, Ratio = 9, Reach = 1300 },
			{ Name = "Medium", Tiles = 240, Fine = 800, Ratio = 10, Reach = 1550 },
			{ Name = "High", Tiles = 290, Fine = 1100, Ratio = 12, Reach = 1800 },
			{ Name = "Ultra", Tiles = 330, Fine = 1500, Ratio = 14, Reach = 2100 },
		},
		DetailDefault = 3, -- keyboard and mouse, or gamepad
		DetailTouchDefault = 2, -- a phone or tablet
		-- programmer colours, by slope: grass in two shades blotched by the relief, rock past
		-- `RockAngle`
		GrassColours = { Color3.fromRGB(86, 132, 62), Color3.fromRGB(70, 116, 54) },
		GroundRockColour = Color3.fromRGB(116, 110, 102),
		UVStuds = 48, -- studs one tile of the ground's material covers
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
		-- studs of road per chunk. A chunk holds one EditableMesh while it is drawn. WHAT
		-- LIMITS THE WINDOW is the client's mesh budget, counted in triangles (about 81 000 in
		-- Studio on a PC, `Ground` "THE BUDGET"), not a count of meshes: a GROWABLE mesh holds
		-- back about 10 400 triangles of it however little it uses, which is where "eight
		-- meshes" came from (measured, T-230). So a chunk, once built, is copied into a
		-- fixed-size mesh (`Road/SplineMesh`) and costs only its own triangles: about 3 600 a
		-- chunk on today's ground, fewer on a ground run (no faces). Only the chunk being built
		-- is growable. The window is chunk-aligned: from the chunk `Behind` studs back to the one
		-- `Ahead` on, so the road kept behind is `Behind` to `Behind + ChunkLength` studs.
		-- A device that runs out anyway lets the furthest chunk behind go before the road
		-- ahead falls back to parts (`Drift/SplineRoadView`).
		ChunkLength = 480,
		Ahead = 1600, -- studs of road drawn in front of the car
		-- THE PLAYER'S "ROAD BEHIND" (Settings, Graphics; docs/game/SETTINGS.md, T-230): how far
		-- the road, and on a ground run the ground along it, stays drawn behind the car. Each
		-- step back costs the chunks it keeps (`Studs / ChunkLength` more: about 3 600 triangles
		-- and 20 to 250 plain parts each on today's ground, 2 100 on a ground run) and no
		-- building: a chunk behind was built when it was ahead. Short is the window before T-230.
		-- `GroundTiles`: on a ground run, the ground's corridor beside the road behind needs
		-- 32-stud tiles (no coarser tile may lie beside drawn road), and they came out of the
		-- Ground detail's own `Tiles` (measured on Light: sharp ground ahead 400 studs at Short,
		-- 232 at Long, 120 at Longest). So each step gives the ground that many more tiles
		-- (128 triangles each) for its corridor, and the sharp ground ahead keeps its share.
		Behind = {
			{ Name = "Short", Studs = 300, GroundTiles = 0 },
			{ Name = "Medium", Studs = 800, GroundTiles = 10 },
			{ Name = "Long", Studs = 1300, GroundTiles = 24 },
			{ Name = "Longer", Studs = 2000, GroundTiles = 38 },
			{ Name = "Longest", Studs = 3000, GroundTiles = 56 },
		},
		BehindDefault = 3, -- keyboard and mouse, or gamepad
		BehindTouchDefault = 2, -- a phone or tablet
		FallbackStep = 4, -- studs between cross-sections when a device draws parts instead
		-- A chunk is built over as many frames as it needs (T-193): its build hands the frame
		-- back whenever this much of it has been spent, and carries on next frame. Nothing is
		-- seen until the whole chunk is done, so nothing pops: it all appears at once.
		SliceMs = 3, -- ms of building in any one frame, at most (about; one step can overrun)
	},

}

return Spline
