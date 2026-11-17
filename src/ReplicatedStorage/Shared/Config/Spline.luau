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
	-- Every section is accepted only if the road could still straighten up and run this far
	-- clear afterwards. That is the escape: the road can never box itself in, because the
	-- way out is checked before the way in is taken.
	EscapeLength = 260, -- studs of straight
	CandidateTries = 14, -- random sections tried before taking the escape itself

	-- --------------------------------------------------------------- the mountain's direction
	-- (features/mountain-direction.md, T-166; on the range since T-238, features/mountain-range.md.)
	-- The road has ONE FALL LINE, fixed in the world for the whole road: the range's way on is
	-- down it. The road is laid as LEGS across the faces toward the pass ahead
	-- (`SplineGen._planRange`, numbers in `Config.Range` and `Ground` below), joined by
	-- planned HAIRPINS that send it back the other way. Ordinary bends inside a leg stay
	-- within `LegHeadingLimit` of it, so only a hairpin can turn the road back. Chosen by the
	-- server from the seed; clients only replay. (The old descent planner's legs, switchbacks,
	-- double hairpins, sideways stretches and height band went with features/legacy-removal.md.)
	Mountain = {
		-- Uphill is the start heading turned this far, to a side chosen from the seed, so the
		-- first leg runs across the slope.
		FallLineTurn = 90, -- degrees
		-- Heading within this of straight up or down the slope counts as neither side: the
		-- uphill side holds what it was, so a wiggle can't flip it (the cliff step).
		AlongFallLine = 30, -- degrees
		LegHeadingLimit = 60, -- degrees: no ordinary bend takes the road further off its leg
		LegUphillLimit = 30, -- degrees, and no further off it UP the slope, toward the leg above
		HairpinRadius = { 75, 110 }, -- studs: a hairpin off steep ground (`Range.SteepHairpinRadius` on it)
		-- A turnaround is laid only once the road heads within this of its leg; further off,
		-- a bend first brings it back, so every hairpin turns about the same amount.
		TurnWindow = 20, -- degrees
		StraightenRadius = { 200, 500 }, -- studs, that bend
		-- When a planned turn is refused (it would come too close to old road), the stretch
		-- before it runs on this far and it is tried again.
		RetryAfter = 120, -- studs
		TurnTries = 6, -- radii tried for one planned turn before it is refused
		-- Fit sharp turns to the mountain the client draws (T-190, `Road/SplineTurnFit`). Clear
		-- radii are ranked by excess rock ahead and by cutting/fill at the runoff's sides.
		TurnChecks = true,
		TurnFitTries = 3, -- fixed terrain-preview budget per sharp turn
		TurnCheckAngle = 60, -- degrees: smaller heading corrections keep the old path
		TurnViewDistances = { 50, 100, 150 }, -- horizontal checks from three places round a turn
		TurnViewExcess = 15, -- studs above the eye plus the natural uphill plane
		TurnSideReach = 20, -- studs beyond runoff for the sideways checks
		TurnMaxCut = 90, -- studs: a very deep cutting near a turn
		TurnMaxFill = 120, -- studs: an outsized embankment/drop near a turn
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
		-- so nothing steps, from the mountain's side slope (`Ground.RunoffWide` to `RunoffThin`).
		-- Grass grips and scores as `Config.Drift.GripGrass` / `ScoreGrass`.
		RunoffMin = 12, -- studs, about 2 car widths: the narrowest outside a tight edge or a carve
		RunoffMax = 40, -- studs, about 5: the widest outside a grove (it sizes the no-crossing gap)
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
		-- THE EDGES ARE THE DRAWN GROUND (T-258, T-261, features/car-edges.md): no rock face,
		-- hedge or cliff is chosen per side any more. Only a road with NO mountain (a test's
		-- hand-made road, the collision tests' yardstick) is walled at its runoff's outer edge,
		-- `BareWallHeight` high to the car and `BareWallThickness` thick to a walker
		BareWallHeight = 6, -- studs
		BareWallThickness = 4, -- studs
		-- How far past the runoff an edge reaches, for keeping two stretches of road apart.
		EdgeDepth = 4, -- studs
		-- WHICH SIDE IS UPHILL follows from the heading against the fall line (T-166,
		-- `Mountain.AlongFallLine`): no stretch length and no random swap any more. K-rails,
		-- tight edges and carved apexes are placed by it (`Spline:uphillAt`).
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

	-- --------------------------------------------------------------- the tarmac's texture
	-- T-268 (features/road-surface.md): the tarmac painted IN CODE into one image every chunk
	-- shares (`Road/RoadTexture`), nothing uploaded. Its colours and lines are `Config.Road`'s.
	-- Drawn when the ground draws the runoff (`Ground.RunoffBy = "ground"`); with the road
	-- drawing its own grass the grass's texture is on the mesh instead, and the tarmac is flat.
	-- Distances are studs of road; "along" repeats every `PeriodStuds`.
	Tarmac = {
		Enabled = true, -- false: the flat tarmac and the dash parts, as before
		-- THE RESOLUTION (T-268 send-back, the user: "bit higher res this time for the main
		-- asphalt texturing"): 1 024 x 1 024, the largest EditableImage, 4 MB. Across, the tarmac
		-- gets all but `PlainPx` each side, the line band and the gravel band: 16.6 pixels a stud.
		-- Along, 8.5 (T-277, the user: "is the road texture stretched length wise"; 4.3 over 240
		-- studs before). The shorter repeat that buys is hidden by the vertices' tone, which
		-- never repeats
		Width = 1024, -- pixels across
		Length = 1024, -- pixels along
		-- THE UPLOADED COPY (T-274, `assets/road/MANIFEST.md`): these pixels exactly, so the
		-- client loads it instead of painting it (a painted 1 024 x 1 024 EditableImage holds
		-- 32 tiles of its mesh memory, `Mesh.Budget`). "" paints it, as before. `ImageHash`: the
		-- painted pixels' sum (`RoadTexture.pixelHash`); `SplineMeshTests` checks the painting
		-- still makes it, so a change to anything it paints from is exported and uploaded again
		Image = "rbxassetid://116617809550507", -- tarmac-v2.png (T-277)
		ImageHash = 1346105968,
		PeriodStuds = 120, -- studs along one copy (rounded to whole `MarkInterval`s; 240 before T-277)
		PlainPx = 32, -- plain `Grass.Shade` columns each side, where the rest of the mesh samples
		-- (a thirty-second of the width each side, as before: still a pixel at a 32-wide mip)
		SliceMs = 3, -- ms of painting a frame (it is painted once, as the client loads)
		Seed = 268,
		-- the tone of each tarmac vertex, so the period never shows as a repeat: darker by up
		-- to 2 x `Tone` from smooth noise over `ToneStuds` of road, a little warmer or cooler.
		-- Kept slow (200+), so a chunk drawn coarse far ahead (cuts 96 studs apart) shades alike
		Tone = 0.09,
		ToneStuds = 200,
		ToneHue = 0.03,
		-- the grain: large soft mottling, painterly strokes stretched along, a finer aggregate
		-- octave (what the resolution is for), and speckle
		Mottle = 0.06,
		MottleStuds = 9,
		Grain = 0.06,
		GrainStuds = { 0.6, 3.5 }, -- across, along
		Fine = 0.05,
		FineStuds = { 0.18, 0.6 },
		Speckle = 0.05,
		-- the wheel tracks: two a lane, `TrackGap` apart about its middle, `TrackWidth` wide,
		-- `TrackDark` of the way to `TarmacWorn` in the middle, wandering `TrackWobble` either
		-- way over `TrackWobbleStuds`, their grain `TrackSmooth` smoother (polished); a faint
		-- oil strip between them. Send-back (the user: "tyre marks are ugly"): broad and
		-- faint, polish rather than stripes (0.9 dark and 3.2 wide in the first cut)
		TrackGap = 6.4,
		TrackWidth = 4.5,
		-- Send-back 2 ("I still don't like the tire marks ... otherwise keep it simple
		-- textured"): none. (Tracks only on the hairpins would need a second tarmac in the
		-- image, and the car's own drift marks already rubber the hairpins it is drifted round)
		TrackDark = 0,
		TrackSmooth = 0,
		TrackWobble = 0.8,
		TrackWobbleStuds = 60,
		OilWidth = 1.2,
		OilDark = 0,
		-- THE DUSTY EDGE (T-277, the user: "use the current area that is static-y on the road
		-- texture to prepare for the transition to gravel, the soft transition is what we are
		-- looking for. no gravel pebbles on the road texture itself"): no specks; the tarmac
		-- goes over to the gravel's bare bed (`Colours.GravelDust`) toward its edge, all of it
		-- in the last `EdgeFull` studs, none past `EdgeWear`, in soft ragged shapes (noise over
		-- `EdgeStuds` across and along, moving it up to `EdgeRagged` studs either way)
		EdgeWear = 1.4,
		EdgeFull = 0.25,
		EdgeRagged = 0.45,
		EdgeStuds = { 0.5, 1.3 },
		-- the paint's wear (0 none, 1 worn through where the noise is highest)
		LineWear = 0.35,
		-- THE PAINT'S WEATHERING (send-back 2: "faded and cracked/weather lines"), the edge
		-- lines and the double yellow alike: each line's paint fades along the road between
		-- `LineFade` (of full) over `LineFadeStuds`, wears through to the tarmac where the hole
		-- noise (over `LineHoleStuds` across and along) passes `LineHoles` (-1..1: higher, fewer),
		-- thins with the fine grain by up to `LineGrain`, has its sides chipped by up to
		-- `LineChip` studs, and is broken by `LineCracks` cracks across it a copy
		LineFade = { 0.5, 0.95 },
		LineFadeStuds = 30,
		LineHoles = 0.42,
		LineHoleStuds = { 0.35, 1.6 },
		LineGrain = 0.35,
		LineChip = 0.06,
		LineCracks = 5, -- a copy (120 studs; 10 over 240 before T-277)
		-- THE LINE BAND: columns of the image, right of the tarmac, holding one yellow line
		-- (`Config.Road.CentreLineWidth`) on tarmac, which the double yellow's strips are mapped
		-- to, `LineInsetPx` in from its sides
		LineBandPx = 32,
		LineInsetPx = 4,
		-- patches of newer and older tarmac, a seam round each
		Patches = 1, -- a copy (120 studs since T-277; 2 over 240, 4 over 480 in the first cut)
		PatchLength = { 8, 26 },
		PatchWidth = { 6, 16 },
		PatchSeam = 0.2,
		PatchBlend = 0.5,
		PatchSoft = 0.6, -- studs
		PatchRagged = 0.8, -- studs
		-- cracks: mostly along the road `CrackEdge` in from an edge, `CrackAcross` of them across
		Cracks = 3, -- a copy (6 over 240 before T-277)
		CrackWidth = 0.12, -- studs
		CrackLength = { 6, 26 },
		CrackEdge = { 1, 4.5 },
		CrackAcross = 0.15,
		CrackDark = 0.35,
	},

	-- --------------------------------------------------------------- the gravel's texture
	-- T-270 (features/road-surface.md "The gravel"), the user: "do the same for the gravel on
	-- the sides of the road. get a proper texture for it". Painted in code into a band of the
	-- tarmac's image (`Road/RoadTexture.paintGravel`), so it costs no image of its own; its
	-- colours are `Config.Road.Colours.Gravel*`. The bevel at each edge of the tarmac is mapped
	-- to it, and so is a strip laid over the narrow gravel runoff of a tight cliff edge.
	Gravel = {
		Enabled = true, -- false: the bevels plain gravel colour, no runoff strips, as before
		BandPx = 96, -- columns of the 1 024-wide image (taken from the tarmac's: 16.6 pixels a stud there)
		InsetPx = 4, -- columns each side of the band nothing is mapped to, so nothing bleeds in
		BandStuds = 3, -- studs of gravel across the band: 29 pixels a stud
		PeriodStuds = 64, -- studs along one copy: 16 pixels a stud
		Seed = 270,
		-- THE LOOK: B, the user's pick of three (2026-11-16) after "too noisy and static-y" and
		-- "too cartoony" (features/road-surface.md "The gravel"), painted like the asphalt.
		-- The bed's grain (`Mottle`, `Grain`, `Fine`, each over its cells in studs across and
		-- along, as the asphalt's); its stones by size (so many a square stud, a radius range in
		-- studs), `Gap` studs kept between them; how far a stone's tone goes toward
		-- `GravelLight` or `GravelDark` (`Contrast`); its soft shading toward the light (`Lit`);
		-- its edge `SoftPx` pixels wide; how much it covers the bed (`Opacity`); its shadow,
		-- `ShadowOffset` of a radius away, `ShadowDark` dark (1: none)
		MottleStuds = { 0.8, 1.4 }, Mottle = 0.06,
		GrainStuds = { 0.3, 0.8 }, Grain = 0.04,
		FineStuds = { 0.08, 0.2 }, Fine = 0.065,
		Stones = {
			{ Density = 0.6, Radius = { 0.26, 0.36 } },
			{ Density = 1.6, Radius = { 0.15, 0.22 } },
		},
		Gap = 0.02,
		Contrast = 0.6, Lit = 0.18, SoftPx = 2, Opacity = 1,
		ShadowOffset = 0.35, ShadowDark = 0.82,
		Aspect = { 0.8, 1.2 }, -- a stone's two radii, as shares of its size
		LightAngle = -125, -- degrees, in the band (across, along): where the stones are lit from
		-- THE EDGES, no hard seams: the tarmac's dusty edge takes over raggedly over the band's
		-- first `EdgeSoft` studs; grass tufts creep in from `GrassFrom` studs to its end
		EdgeSoft = 0.45,
		GrassFrom = 2.4,
		EdgeStuds = { 0.5, 1.2 }, -- the size of the edges' ragged shapes (across, along)
		-- THE MAPPING: the bevel runs from the band's start (the tarmac's edge) to its end (the
		-- grass) and, in a gravel run, to `RunFoot` only (no grass where gravel goes on); the
		-- strip over a gravel run's flat runoff, from its foot to its lip, reads `RunFrom` to
		-- `RunFoot`, lifted `RunoffLift` over the ground (more on a coarse chunk: its tolerance / 4)
		RunFoot = 2.2,
		RunFrom = 1.0,
		RunoffLift = 0.06,
	},

	-- --------------------------------------------------------------- the ground
	-- (features/ground-trial.md, T-218; the only ground since T-247, features/legacy-removal.md.)
	-- The ground BUILT FIRST, as one mountain the road is cut into (`Road/Ground`), drawn by
	-- each client as its own grid meshes (`Drift/GroundMeshView`).
	Ground = {
		-- THE MOUNTAIN, h(x, z), through the road's start, is the range (`Road/Range`,
		-- `Config.Range`, T-238): a pure function of the seed and the place. (The T-228 belts and
		-- their ridges and gullies went with features/legacy-removal.md.)
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
		-- ITS ANGLE ACROSS THE MOUNTAIN: from h's slope where the road is (the gradient `AimSpan`
		-- studs across, blended with the range's own, `Config.Range.AimSpan`/`AimRelief`), a leg
		-- heads across the face toward the pass ahead, tilted just enough to descend (or climb)
		-- `LegGrade` (one per leg, from the plan's stream): nearly across where h is steep, more
		-- directly down (or up) it where it is gentle, at most `LegTiltMax` off across. Its bends
		-- may stray no further down the slope than keeps the grade within `FollowGrade` of
		-- `MaxGrade` (never under `AimMinLimit`), so the road can follow h there
		AimSpan = 60, -- studs
		LegGrade = { 0.035, 0.07 }, -- descent per stud of road along a leg: 2 to 4 degrees
		LegGradeSteep = 0.1, -- plus this much of h's slope there (T-228), to `FollowGrade` at most
		-- less this much a stud for every stud the road is above h where it is (more if below):
		-- a road left above the mountain turns across it until the mountain is back
		CatchUp = 1 / 150, -- (1 / 100 measured worse on 20 seeds, and one boxed in)
		LegTiltMax = 75, -- degrees off straight across
		FollowGrade = 0.9,
		-- A SHARP PLANNED TURN (a hairpin) that would leave the road more than
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
		-- WHO DRAWS THE RUNOFF (T-251, an experiment): "road", the road's own mesh (its grass
		-- strips and the skirt above), or "ground", the ground mesh. With "ground" the road's
		-- mesh stops at its gravel bevel's foot, and the ground under the road and runoff is
		-- the runoff's own surface (`Spline:underY`, what the car stands on past the bevel),
		-- carried in `RoadLip` under the bevel and tarmac, so the runoff flows into the cut or
		-- fill with no seam and no skirt. Each spacing sinks `RunoffSinks` under it (the finest
		-- none: what is drawn is what the car stands on), and its runoff vertices are coloured
		-- `Terrain.GrassColour` (gravel in a gravel run). A short skirt, `BevelSkirt` down from
		-- the bevel's foot, hides the step where coarse ground far ahead sits lower. In Studio the
		-- workspace attribute `__runoff_by` ("road" or "ground") overrides this from the next
		-- run (`Ground.runoffBy`), to compare the two
		RunoffBy = "ground",
		RunoffSinks = { 0, 0.4, 2.5, 4, 4 }, -- studs, per spacing (as `Sinks`)
		BevelSkirt = 3, -- studs
		BevelSkirtLean = 0.5, -- studs

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
		-- and far along the road (T-263), coarser still: no tile coarser than `Coarsest` beside
		-- road `From` studs or more from the car, either way. Past about 2 400 studs a 64-stud
		-- tile is a few pixels; at 32 the corridor of 9 600 studs each way took every tile.
		RoadFar = { { From = 2400, Coarsest = 64 }, { From = 4800, Coarsest = 128 } },
		-- the most tiles the Road ahead and Road behind steps may add past Ultra's own (T-263):
		-- (45 still ran out on Ultra with both at Longest while driving: the hidden spare tiles and
		-- a chunk being rebuilt both count)
		CorridorMost = 20,
		RoadPad = 256, -- studs: tiles this near the drawn road are drawn even past `Reach`
		ReleaseOnFail = 24, -- tiles let go if the device will not make another (room for the road)
		-- the fewest tiles (besides `Spare`) the ground gives way to when the road is out of mesh
		-- memory (T-273, `Drift/MeshBudget`): Light's own, so far ground goes coarser before any
		-- road is let go, and the ground round the car stays
		YieldFloor = 128,
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
		-- studs of road per chunk. The client's mesh budget (`Budget`, in tiles) once limited the
		-- window: a GROWABLE mesh holds back about 10 400 triangles of it however little it
		-- uses, which is where "eight meshes" came from (measured, T-230), and a fixed-size
		-- copy its own triangles. SINCE T-274 A DRAWN CHUNK HOLDS NONE: it is written into a
		-- fixed-size copy of a blank template and made opaque content (`Road/SplineMesh`), and
		-- only the one being built holds its size for a moment. The window is chunk-aligned:
		-- from the chunk `Behind` studs back to the one `Ahead` on, so the road kept behind is
		-- `Behind` to `Behind + ChunkLength` studs (both
		-- are the player's settings: `Drift/RoadBehind`, `Drift/RoadAhead`).
		-- A device that runs out anyway lets the furthest chunk behind go before the road
		-- ahead falls back to parts (`Drift/SplineRoadView`).
		ChunkLength = 480,
		-- THE PLAYER'S "ROAD AHEAD" AND "ROAD BEHIND" (Settings, Graphics; docs/game/SETTINGS.md,
		-- T-230, T-263): how far in front of the car, and behind it, the road and the ground along
		-- it are drawn: at least `Studs` (chunk-aligned, so up to a chunk more). THE SAME STEPS
		-- BOTH WAYS, three times the first ones (the user's send-back, 2026-11-16: Road ahead was
		-- 1 000 to 3 200, Road behind 300 to 3 000 in five steps). Past `Near` a chunk is drawn
		-- at `Far`'s detail, about a quarter of a whole chunk's triangles: that is what lets
		-- Longest both ways fit the mesh budget (measured: 41 chunks, about 14 000 triangles).
		-- `GroundTiles`: more tiles for the ground's corridor beside the longer road (32-stud
		-- tiles to `Ground.RoadFar`, coarser past it), so the sharp ground round the car keeps
		-- its share; never more than `Ground.CorridorMost` past Ultra's own.
		-- A DEVICE CAN ONLY DRAW ROAD THE SERVER HAS SENT: `RoadService` lays the longest
		-- `Ahead` step past the end of the leader's section.
		Ahead = {
			{ Name = "Short", Studs = 3000, GroundTiles = 40 },
			{ Name = "Medium", Studs = 4800, GroundTiles = 60 },
			{ Name = "Long", Studs = 7200, GroundTiles = 80 },
			{ Name = "Longest", Studs = 9600, GroundTiles = 100 },
		},
		AheadDefault = 2, -- Medium: three times the 1 600 before
		AheadTouchDefault = 2, -- the same on a phone or tablet
		-- behind: a chunk behind was built when it was ahead, so each step back costs the chunks
		-- it keeps, not building (a whole one is drawn again far once it is past `Near`)
		Behind = {
			{ Name = "Short", Studs = 3000, GroundTiles = 30 },
			{ Name = "Medium", Studs = 4800, GroundTiles = 40 },
			{ Name = "Long", Studs = 7200, GroundTiles = 55 },
			{ Name = "Longest", Studs = 9600, GroundTiles = 70 },
		},
		-- Short: three times the old 1 300 is 3 900, as near Short as Medium, and Short is cheaper
		BehindDefault = 1, -- keyboard and mouse, or gamepad
		BehindTouchDefault = 1, -- a phone or tablet (it was Medium, 800: three times is 2 400)
		-- the ground beside the road behind stays as sharp as ahead for this far back, and is
		-- `Ground.RoadCoarsest` past it (it was Short's 300 studs before T-263 tripled the steps)
		BehindSharp = 300, -- studs
		-- FAR AWAY (T-263): a chunk wholly past `Near` of the car (ahead or behind) is drawn at
		-- `Far`'s coarser detail, and rebuilt whole as the car comes within `Near`; a chunk drawn
		-- whole that falls behind past it is drawn again far. That is what lets 9 600 studs each
		-- way fit the mesh budget (measured: whole chunks alone ran out at Longest ahead).
		Near = { Ahead = 1600, Behind = 480 }, -- studs
		-- `LeanTrees` (T-273): a far chunk's grove trees have no trunk and no flat underside, the
		-- same outline from 480 studs behind or 1 600 ahead at about half the mesh memory
		Far = { Tolerance = 1, MaxStep = 96, Across = 1, LeanTrees = true },
		FallbackStep = 4, -- studs between cross-sections when a device draws parts instead
		-- THE CLIENT'S MESH MEMORY (T-273, features/ground-trial.md "The mesh budget"), in
		-- TILES: what a fixed-size mesh of 128 triangles costs (one ground tile). Measured in a
		-- DR-Lane1 client by filling it with copies of a tile: 563 free before a run; a road
		-- chunk, a mark strip or the vista's arc costs about its triangles / 128; and
		-- EditableImages count too. OPAQUE CONTENT COSTS NONE OF IT (T-274, measured: 60 chunks
		-- of 1 800 triangles made opaque, 0 tiles; a 1 024 x 1 024 image likewise), and neither
		-- does an uploaded image. Every user must fit (`SplineMeshTests` "every mesh user fits"):
		Budget = {
			Tiles = 640, -- all of it, about 82 000 triangles (T-225 measured about 81 000)
			-- what a growable mesh holds however little is in it (measured: empty, 128 or 6 144
			-- triangles alike). Nothing keeps one since T-274: each is made, used and let go
			-- (the road's templates, once a size; the ground's master; the marks; the vista)
			Growable = 80,
			Image1024 = 32, -- a 1 024 x 1 024 EditableImage (the painted tarmac, only as a fallback)
			TileTriangles = 128,
			-- what the others hold, at most (`SplineMeshTests` checks each against what is
			-- built): a whole road chunk and a far one (its trees lean, `Far.LeanTrees`) as they
			-- are built, and what a chunk holds once drawn (none: opaque, T-274); the most a
			-- chunk's build holds for a moment (a copy of its template, which needs about twice
			-- its size while it is made, measured: a 960-triangle one 13 to 16 tiles, a 1 536 one
			-- 21 to 24; the heaviest chunk's, 3 008, about 47); the drift marks' two ribbons
			-- (T-274: half as long; their textures are opaque); the vista's arc (opaque, T-274)
			WholeChunk = 14,
			FarChunk = 3,
			DrawnChunk = 0,
			Building = 48,
			Marks = 22,
			Vista = 0,
			-- left over, for a stretch heavier than those, and the moments a tile is replaced
			-- (old and new both held)
			Spare = 24,
			-- THE GROUND'S SHARE (`SplineMesh.groundRoom`): never more tiles than the budget has
			-- room for beside the road the player's settings draw, so the far ground is coarser
			-- before any road runs out. STILL WORKED OUT FROM T-273'S FIGURES (the others' total
			-- then: a kept growable mesh, the marks at 44, the vista at 2, the painted texture and
			-- the ground's master; a chunk's 14 whole and 3 far, and one more whole), so the
			-- ground draws what it drew: the tiles T-274 freed stay free (`SplineMesh.freeTiles`)
			-- until the user picks what they buy (T-274: spent only with the user's OK)
			GroundShare = { Others = 159, WholeChunk = 14, FarChunk = 3 },
			-- OUT OF IT (`Drift/SplineRoadView`, `Drift/MeshBudget`): tiles asked of the others
			-- at a time, tries before giving up on a chunk, and how long nothing already drawn is
			-- redrawn after one gave up (shorter when the ground is merging tiles to make room)
			AskTiles = 32,
			MaxTries = 6,
			HoldSeconds = 4,
			WaitSeconds = 0.5,
		},
		-- A chunk is built over as many frames as it needs (T-193): its build hands the frame
		-- back whenever this much of it has been spent, and carries on next frame. Nothing is
		-- seen until the whole chunk is done, so nothing pops: it all appears at once.
		SliceMs = 3, -- ms of building in any one frame, at most (about; one step can overrun)
		-- THE TEMPLATES a client makes as it loads (T-274, `Road/SplineMesh` "THE TEMPLATES"):
		-- every size up to the one that holds this many triangles, past the heaviest chunk
		-- measured (over 2 400 whole, with a grove, in a drive at the defaults; a far one about
		-- 400), so a run seldom makes one (making one holds a growable mesh for a moment)
		PrepareFaces = 3008,
	},

}

return Spline
