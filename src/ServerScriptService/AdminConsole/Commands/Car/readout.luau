local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "readout",
	Description = "Shows or hides the car's debug readout (the numbers panel; F3 does the same).",
	Group = "Car",
	Args = {},
	ClientRun = function(): string
		local on = controller("DriftController"):DebugToggleReadout()
		return if on then "Readout on." else "Readout off."
	end,
}
