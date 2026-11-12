local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "time-pause",
	Aliases = { "timepause" },
	Description = "Stops your sky where it is now. Your screen only.",
	Group = "Time",
	Args = {},
	ClientRun = function(): string
		local sky = controller("SkyController")
		local now = sky:DebugState()
		local s = sky:DebugHold(now.t or 0)
		return string.format("Sky paused at clock %.2f (%s).", s.clock, tostring(s.phase))
	end,
}
