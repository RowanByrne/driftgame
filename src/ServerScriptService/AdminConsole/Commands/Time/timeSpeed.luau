local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "time-speed",
	Aliases = { "timespeed" },
	Description = "Runs your sky's day-night cycle this many times as fast, from where it is (1 is normal; the whole cycle is under five minutes at 1). Your screen only.",
	Group = "Time",
	Args = {
		{ Type = "number", Name = "times", Description = "How many times as fast: 0.1 to 100." },
	},
	ClientRun = function(_context, times: number): string
		if times ~= times or times < 0.1 or times > 100 then
			return "Between 0.1 and 100 times."
		end
		local s = controller("SkyController"):DebugSpeed(times)
		return string.format("Sky running x%g from clock %.2f; one cycle takes %.0f s.", times, s.clock, s.length / times)
	end,
}
