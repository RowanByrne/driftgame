local Players = game:GetService("Players")

return {
	Name = "unstuck",
	Aliases = { "flip" },
	Description = "Rights your car where it is: stopped, level, facing the way it faced, a little above the ground.",
	Group = "Teleport",
	Args = {},
	-- Where this client's simulation has the car, which is where the player sees it stuck.
	Data = function()
		local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
		local controllers = scripts and scripts:FindFirstChild("Controllers")
		local drift = scripts and scripts:FindFirstChild("Drift")
		local module = controllers and controllers:FindFirstChild("DriftController")
		if not module or not drift or not drift:FindFirstChild("Model") then
			return nil
		end
		local state = require(module):CurrentState()
		return if state then require(drift.Model).cframe(state) else nil
	end,
}
