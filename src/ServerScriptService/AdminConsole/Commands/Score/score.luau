local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "score",
	Description = "Shows your run's score: points, multiplier rung and its bar, best, and whether you're in a run.",
	Group = "Score",
	Args = {},
	ClientRun = function(): string
		local r = controller("ScoreController"):DebugState()
		return string.format(
			"Score %d, x%d (bar %.2f), best %d, peak x%d, %s.",
			math.floor(r.score),
			r.multiplier,
			r.progress,
			math.floor(r.best),
			r.peakMultiplier,
			if r.inRun then "in a run" else "not in a run"
		)
	end,
}
