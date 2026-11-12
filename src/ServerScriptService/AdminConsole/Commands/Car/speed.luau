local Players = game:GetService("Players")

local function cmdr()
	return require(Players.LocalPlayer.PlayerScripts.Controllers.CmdrController)
end

-- Runs on the caller's own client when it targets only them; otherwise the server sends it
-- to each target's client (`speedServer`, `CmdrController:Act`).
return {
	Name = "speed",
	Description = "Shows your car's speed, or sets players' speed (studs/s) along the way each nose points, straight out of any slide. Each car's model takes it from there.",
	Group = "Car",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "Who: names, me, all, others. Leave it out for yourself.",
			Optional = true,
		},
		{
			Type = "number",
			Name = "speed",
			Description = "Studs a second, -1000 to 1000. Leave it out to see your own speed.",
			Optional = true,
		},
	},
	ClientRun = function(_context, players, speed): string?
		local console = cmdr()
		if console.onlyMe(players) then
			return console:Act("speed", speed)
		end
		return nil
	end,
}
