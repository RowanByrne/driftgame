--!strict
-- Score: every number the endless run's score is made of, and none of them in the logic
-- (docs/game/features/endless-score.md "Rules and numbers", docs/workflow/CODING.md
-- "Foundation kit").
--
-- The maths is the reference's, read off its decompile (features/drift-model.md "Score"),
-- and lives in `Drift/Score`. EXACT means the number is the reference's own; FALLBACK means
-- it was not in the decompile and is a guess, to be tuned by driving.
--
-- WHAT IS NOT HERE: the SURFACE's share of the score (`ScoreTarmac`, `ScoreDirt`,
-- `ScoreUnspecified`). Those are the world's, read by the ground rays alongside the grip, and
-- stay in `Config.Drift`; the model hands the result over as `state.surfaceScore`.

return {
	-- --------------------------------------------------------------------- the points
	-- base  = |slip| * speed * surfaceScore * ScoreRate * dt
	-- score += base * multiplier
	-- Only while |slip| >= Config.Drift.MinSlipAngleForDrift and the car is going the way
	-- its nose points: past 90 degrees of slip the car is sliding backwards, and that
	-- earns nothing (the reference's reverse-drift bonus is left out, below).
	ScoreRate = 0.2864789, -- points per radian of slip per stud travelled. EXACT (the
	-- reference's constant is per metre; this is it converted)

	-- -------------------------------------------------------------------- the ladder
	-- progress += clamp(base * ProgressRate - (grounded and MultiplierDecay * rung * dt or 0),
	--                   -MaxProgressDown * dt, MaxProgressUp * dt)
	-- progress > 1            -> one rung up (to MaxMultiplier), progress -= 1
	-- progress <= MinProgress -> one rung down (to 1), progress += 1 - MinProgress
	-- So the bar fills while the car is sideways and bleeds while it is not, and it bleeds
	-- faster the higher the rung: every rung is harder to hold than the last.
	MaxMultiplier = 9, -- FALLBACK. The top of the ladder
	ProgressRate = 0.06, -- FALLBACK. Bar per point: how fast drifting fills the next rung
	MultiplierDecay = 0.15, -- per second per rung, on the ground. FALLBACK (its 3 x 0.05)
	MaxProgressUp = 1, -- per second. FALLBACK. Ceiling on how fast the bar fills
	MaxProgressDown = 0.75, -- per second. FALLBACK. And empties
	MinProgress = -0.25, -- FALLBACK. How far below empty before a rung is lost

	-- -------------------------------------------------------------- not used yet
	-- The user asked for basic scoring only (T-119): no bonuses, no wall or fall penalty.
	-- Kept so they need not be read off the reference again.
	ReverseDriftBonus = 400, -- FALLBACK. A drift held past 90 deg: floor(ln(t+1) * this)
	AirTimeBonusMin = 10, -- FALLBACK. Airborne and forward: an exponential in the air
	-- time, ignored below this

	-- ------------------------------------------------------------------- ours
	SummarySeconds = 5, -- how long the run's final score shows after END RUN
}
