local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "time-resume",
	Aliases = { "timeresume" },
	Description = "Puts your sky back on the server's clock, at normal speed, where everyone else's is.",
	Group = "Time",
	Args = {},
	ClientRun = function(): string
		local s = controller("SkyController"):DebugResume()
		return string.format("Sky back on the server's clock: %.2f (%s).", s.clock, tostring(s.phase))
	end,
}
