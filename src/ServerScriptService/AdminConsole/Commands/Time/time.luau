local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

-- The moment in the cycle whose clock is nearest `hour`, to the half second.
local function momentAt(cycle, hour: number): number
	local best, bestGap = 0, math.huge
	local t = 0
	while t < cycle.length do
		local clock = cycle:sample(t).Clock
		local gap = math.abs(clock - hour)
		gap = math.min(gap, 24 - gap)
		if gap < bestGap then
			best, bestGap = t, gap
		end
		t += 0.5
	end
	return best
end

local function slug(name: string): string
	return (string.gsub(string.lower(name), "%s+", "-"))
end

return {
	Name = "time",
	Description = "Holds your sky at a time of day: noon, sunset, night, sunrise, any keyframe of the cycle by name, midnight, or an hour (0-24). With nothing, says where the cycle is. Your screen only: the cycle runs on each player's own clock.",
	Group = "Time",
	Args = {
		{
			Type = "timeOfDay",
			Name = "when",
			Description = "noon, sunset, night, sunrise, morning, afternoon, golden-hour, dusk, dawn, midnight, or an hour 0-24",
			Optional = true,
		},
	},
	ClientRun = function(_context, when: any): string
		local sky = controller("SkyController")
		if when == nil then
			local s = sky:DebugState()
			return string.format(
				"Clock %.2f (%s), %.1f s into a %d s cycle%s.",
				s.clock,
				tostring(s.phase),
				s.t or 0,
				s.length,
				if s.held then ", held" elseif s.speed ~= 1 then `, running x{s.speed}` else ""
			)
		end
		local DayNight = require(ReplicatedStorage.Shared.DayNight)
		local cycle = DayNight.new()
		local t
		if type(when) == "number" then
			t = momentAt(cycle, when % 24)
		elseif when == "midnight" then
			t = momentAt(cycle, 0)
		else
			for _, key in cycle:keyTimes() do
				if slug(key.name) == when then
					t = key.t
					break
				end
			end
		end
		if not t then
			return `No time called {tostring(when)}.`
		end
		local s = sky:DebugHold(t)
		return string.format("Sky held at clock %.2f (%s). time-resume puts it back on the server's clock.", s.clock, tostring(s.phase))
	end,
}
