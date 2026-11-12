local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "speed",
	Description = "Shows your car's speed, or sets it (studs/s) along the way the nose points, straight out of any slide. The car's own model takes it from there.",
	Group = "Car",
	Args = {
		{
			Type = "number",
			Name = "speed",
			Description = "Studs a second. Leave it out to see the current speed.",
			Optional = true,
		},
	},
	ClientRun = function(_context, speed: number?): string
		local drift = controller("DriftController")
		local state = drift:CurrentState()
		if not state then
			return "No car."
		end
		local Model = require(Players.LocalPlayer.PlayerScripts.Drift.Model)
		if speed == nil then
			return `Speed {string.format("%.1f", Model.speed(state))} studs/s.`
		end
		if not drift:IsDriving() then
			return "Not driving: get in first."
		end
		if speed ~= speed or math.abs(speed) > 1000 then
			return "Speed is -1000 to 1000 studs/s."
		end
		-- The state CurrentState() hands out is the simulation's own: velocity is the one
		-- thing the model moves, and every other speed is read off it each step.
		local forward = Model.axes(state.yaw)
		state.velocity = forward * speed + Vector3.yAxis * state.velocity.Y
		return `Speed set to {speed} studs/s.`
	end,
}
