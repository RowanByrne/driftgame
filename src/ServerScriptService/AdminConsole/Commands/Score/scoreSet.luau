local Players = game:GetService("Players")

local function cmdr()
	return require(Players.LocalPlayer.PlayerScripts.Controllers.CmdrController)
end

-- Runs on the caller's own client when it targets only them; otherwise the server sends it
-- to each target's client (`score-setServer`, `CmdrController:Act`).
return {
	Name = "score-set",
	Aliases = { "scoreset" },
	Description = "Sets players' run score, and optionally the multiplier rung. Each score lives on that player's own client (nothing saves it yet).",
	Group = "Score",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "Who: names, me, all, others.",
		},
		{ Type = "number", Name = "points", Description = "The score." },
		{ Type = "integer", Name = "multiplier", Description = "The rung, 1 to the top.", Optional = true },
	},
	ClientRun = function(_context, players, points, multiplier): string?
		local console = cmdr()
		if console.onlyMe(players) then
			return console:Act("scoreSet", points, multiplier)
		end
		return nil
	end,
}
