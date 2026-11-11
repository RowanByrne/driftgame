--!strict
-- SAMPLE DATA, not game state: snapshots for `ScoreHudView`, one per state the score panel
-- can be in, big numbers included, for previewing and measuring it without playing to that
-- state (docs/workflow/UI.md "Each screen is a view").

return {
	-- A run just started.
	runStart = { mode = "run", score = 0, multiplier = 1, progress = 0, maxMultiplier = 9 },
	-- Mid-drift, a few rungs up, the bar half full.
	runMid = { mode = "run", score = 4821.7, multiplier = 4, progress = 0.55, maxMultiplier = 9 },
	-- In the grace below empty: drawn as an empty bar.
	runGrace = { mode = "run", score = 12040, multiplier = 3, progress = -0.18, maxMultiplier = 9 },
	-- The top rung, a huge score: the widest the digits get.
	runTop = { mode = "run", score = 98765432.1, multiplier = 9, progress = 1, maxMultiplier = 9 },
	-- END RUN, short of the best.
	summary = { mode = "summary", score = 48210, best = 61004, newBest = false },
	-- END RUN, a new best.
	summaryBest = { mode = "summary", score = 61004, best = 61004, newBest = true },
	-- END RUN, the biggest numbers.
	summaryHuge = { mode = "summary", score = 98765432, best = 98765432, newBest = true },
	hidden = { mode = "hidden" },
}
