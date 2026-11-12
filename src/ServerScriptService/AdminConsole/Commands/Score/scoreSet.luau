local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "score-set",
	Aliases = { "scoreset" },
	Description = "Sets your run's score, and optionally the multiplier rung. The score lives on this client only (nothing saves it yet).",
	Group = "Score",
	Args = {
		{ Type = "number", Name = "points", Description = "The score." },
		{ Type = "integer", Name = "multiplier", Description = "The rung, 1 to the top.", Optional = true },
	},
	ClientRun = function(_context, points: number, multiplier: number?): string
		local Config = require(ReplicatedStorage.Shared.Config)
		if points ~= points or points < 0 then
			return "The score can't be negative."
		end
		local score = controller("ScoreController").score
		score.score = points
		if multiplier ~= nil then
			score.multiplier = math.clamp(multiplier, 1, Config.Score.MaxMultiplier)
			score.peakMultiplier = math.max(score.peakMultiplier, score.multiplier)
			score.progress = 0
		end
		return `Score {math.floor(score.score)}, x{score.multiplier}.`
	end,
}
