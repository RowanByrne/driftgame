local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "score-reset",
	Aliases = { "scorereset" },
	Description = "Resets your run's score and multiplier to the start of a run (the run's score counts toward your best first, as a new run does).",
	Group = "Score",
	Args = {},
	ClientRun = function(): string
		local score = controller("ScoreController").score
		score:Reset()
		return `Score 0, x1. Best {math.floor(score.best)}.`
	end,
}
