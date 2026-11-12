local Players = game:GetService("Players")

local function cmdr()
	return require(Players.LocalPlayer.PlayerScripts.Controllers.CmdrController)
end

-- Runs on the caller's own client when it targets only them; otherwise the server sends it
-- to each target's client (`get-outServer`, `CmdrController:Act`).
return {
	Name = "get-out",
	Aliases = { "getout" },
	Description = "Gets players out of their cars, as the Get out button does (each car must be slow enough).",
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
			return console:Act("getOut")
		end
		return nil
	end,
}
