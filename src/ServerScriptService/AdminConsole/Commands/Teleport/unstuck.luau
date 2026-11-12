local Players = game:GetService("Players")

return {
	Name = "unstuck",
	Aliases = { "flip" },
	Description = "Rights players' cars where they are: stopped, level, a little above the ground. Yours keeps the heading your screen shows. Anyone else's faces along the road if they're in a run, otherwise -Z (the server doesn't know which way their car points).",
	Group = "Teleport",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "Who: names, me, all, others. Leave it out for yourself.",
			Optional = true,
		},
	},
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
