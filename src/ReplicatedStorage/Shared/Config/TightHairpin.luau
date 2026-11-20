--!strict
-- Config.TightHairpin: the touge hairpin whose legs run side by side, laid as a fixed shape
-- (features/tight-hairpins.md, T-329). Every number here is a starting value to tune with
-- the user in a lane.

return {
	-- THE TURN. 40 studs to the centre line, picked by the user from step 1's measurements
	-- (DECISIONS.md 2026-11-19): every car gets round it, sliding, about 34 studs/s at the
	-- apex. The one bend allowed under `Config.Spline.MinRadius`.
	Radius = 40, -- studs
	-- Studs of easing into and out of the half circle: far quicker than the road's
	-- `MaxCurvatureRate` (79 studs at this radius), so the turn is a turn and the legs stay
	-- close. The car was measured round this on the test pad (12) and the playground's (2).
	Ease = 24, -- studs

	-- WHERE. In place of the hairpin that ends a descent's leg (`Range` traverse), now and then:
	-- the first not before `First` studs into the road, then one every `Every` studs at most
	-- often (so never within 1 500 of another), on a face at least `MinFaceSlope` steep, where
	-- the next leg's heading is within `ShortOfHalf` (degrees under, over) a half turn, the
	-- shape leaves the road no more than `MaxOff` off the mountain (fill in full, a cut scaled
	-- as a turnaround's is: `Spline.Ground.TurnMaxOff` / `TurnMaxCut`), and it is clear of old
	-- road. Anywhere else the ordinary hairpin is laid.
	First = { 1000, 3000 }, -- studs
	Every = { 4000, 6000 }, -- studs
	MinFaceSlope = 8, -- degrees
	ShortOfHalf = { 10, 60 }, -- degrees
	-- (a cut counts in full too: a tight hairpin is laid where the face takes it, not in a trench)
	MaxOff = 20, -- studs (`Spline.Ground.TurnMaxOff`)
	-- Climbs too, or descents only. Descents (2026-11-20): on seed 7 a climb's tight hairpin sent
	-- the rest of that climb into trenches (walled on both shoulders) and kept it off the fourth
	-- ridge, where the ordinary switchback does neither.
	OnClimbs = false,
	-- The legs' tarmac edges are never nearer each other than this (the tests' bar; the shape
	-- keeps about 31).
	LegGap = 10, -- studs

	-- THE LEGS. Straight and side by side for this long either side of the turn, then the leg
	-- out bends away from the leg in by the turn's extra (what the next leg's heading asks
	-- beyond a half turn), within these, and runs on until it is clear of the leg in.
	Parallel = 120, -- studs
	-- (no more than 35: the island's bank is taken across the legs square to the leg in, and a
	-- leg out leaving at more than that would be nearer the leg in than the bank's width says)
	DivergeDegrees = { 20, 35 },
	DivergeRadius = 150, -- studs
	-- The lead (`Road/TightHairpin.build`) keeps older road this much further from the leg out
	-- than the island's hand-back needs, for a road that was still bending into the shape.
	LeadMargin = 20, -- studs

	-- THE GRADE through the side by side run: the face's own (the height between where the legs
	-- run beside each other, over the road between them), never steeper than this. Gentle on
	-- purpose: the two legs' heights part by this grade times the road between them, and the
	-- island is the bank between them. At 0.075, 31 studs of island and 120 studs of side by
	-- side: 29 studs, 43 degrees at its steepest.
	Grade = 0.075,
	-- Past the side by side run the grade follows the mountain as any section's does, aiming at
	-- the hillside this far ahead.
	FollowLook = 96, -- studs

	-- THE ISLAND: the ground between the legs is a bank from the upper leg's inner edge down
	-- to the lower one's, not the mountain. No runoff on that side of either leg. As the legs
	-- part, the bank hands back to the mountain: wholly the bank while the legs' edges are
	-- under `IslandFull` apart, wholly the mountain from `IslandGone` (by then each leg's own
	-- cut or fill, `Spline.Ground.BlendMax` at most, has room to reach it before the other's).
	IslandRunoff = 0, -- studs of grass on the island's side
	-- (two legs this near and this far apart in height would otherwise meet in a step: each
	-- leg's own cut or fill reaches the other's)
	IslandFull = 150, -- studs between the legs' edges
	IslandGone = 200,
	IslandMaxSlope = 45, -- degrees: a bank, never a wall (the tests' bar)
}
