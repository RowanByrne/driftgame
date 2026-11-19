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

	-- THE LEGS. Straight and side by side for this long either side of the turn, then the leg
	-- out bends away from the leg in by the turn's extra (what the next leg's heading asks
	-- beyond a half turn), within these, and runs on until it is clear of the leg in.
	Parallel = 120, -- studs
	DivergeDegrees = { 25, 60 },
	DivergeRadius = 150, -- studs

	-- THE GRADE through the whole shape, falling on a descent. Gentle on purpose: the two legs'
	-- heights part by this grade times the road between them, and the island is the bank
	-- between them. At 0.06, 30 studs of island and 120 studs of side by side: 22 studs, 36
	-- degrees at its steepest.
	Grade = 0.06,

	-- THE ISLAND: the ground between the legs is a bank from the upper leg's inner edge down
	-- to the lower one's, not the mountain. No runoff on that side of either leg; past the
	-- side by side run the bank hands back to the mountain over `IslandFade` studs.
	IslandRunoff = 0, -- studs of grass on the island's side
	IslandFade = 60, -- studs
	IslandMaxSlope = 45, -- degrees: a bank, never a wall (the tests' bar)
}
