local Players = game:GetService("Players")

local function cmdr()
	return require(Players.LocalPlayer.PlayerScripts.Controllers.CmdrController)
end

-- Runs on the caller's own client when it targets only them; otherwise the server sends it
-- to each target's client (`get-inServer`, `CmdrController:Act`).
return {
	Name = "get-in",
	Aliases = { "getin" },
	Description = "Gets players back into their cars, as the car's prompt does (each must be near the door).",
	Group = "Car",
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
			return console:Act("getIn")
		end
		return nil
	end,
}
