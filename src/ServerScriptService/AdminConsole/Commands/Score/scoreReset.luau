local Players = game:GetService("Players")

local function cmdr()
	return require(Players.LocalPlayer.PlayerScripts.Controllers.CmdrController)
end

-- Runs on the caller's own client when it targets only them; otherwise the server sends it
-- to each target's client (`score-resetServer`, `CmdrController:Act`).
return {
	Name = "score-reset",
	Aliases = { "scorereset" },
	Description = "Resets players' run score and multiplier to the start of a run (the run's score counts toward their best first, as a new run does).",
	Group = "Score",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "Who: names, me, all, others. Leave it out for yourself.",
			Optional = true,
		},
	},
	ClientRun = function(_context, players): string?
		local console = cmdr()
		if console.onlyMe(players) then
			return console:Act("scoreReset")
		end
		return nil
	end,
}
