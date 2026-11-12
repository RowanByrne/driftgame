local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "trajectory",
	Description = "Shows or hides the projected line of where the car is heading. No argument toggles it.",
	Group = "Car",
	Args = {
		{
			Type = "boolean",
			Name = "on",
			Description = "on or off. Leave it out to toggle.",
			Optional = true,
		},
	},
	ClientRun = function(_context, on: boolean?): string
		local now = controller("DriftController"):DebugTrajectory(on)
		return if now then "Trajectory line on." else "Trajectory line off."
	end,
}
