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
-- THE ROAD'S CROSS-SECTION IS NOT HERE: width, barriers and colours are still
-- `Config.Road`'s, so the two roads stay the same road to look at.

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
	-- lines this far apart in plan: a whole road's width, both barriers, and a gap.
	ClearanceGap = 20, -- studs between the outer faces of the two barriers
	-- The road keeps a general direction and may wander this far off it either way. A
	-- hairpin can still swing it right round, but it can never spiral into itself.
	HeadingLimit = 115, -- degrees either side of `Config.Road.StartHeading`
	-- Every section is accepted only if the road could still straighten up and run this far
	-- clear afterwards. That is the escape: the road can never box itself in, because the
	-- way out is checked before the way in is taken.
	EscapeLength = 260, -- studs of straight
	CandidateTries = 14, -- random sections tried before taking the escape itself

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

	-- --------------------------------------------------------------- the Studio test road
	-- `SplineTestService` (Studio only): a spline road to drive before the run lays one.
	-- Far out on +X, clear of the track, the playground, the garage and the piece road.
	TestOrigin = Vector3.new(30000, 0, -20000),
	TestLength = 8000, -- studs
	TestStandInStep = 6, -- studs between the stand-in's cross-sections (it is only to look at)
}

return Spline
