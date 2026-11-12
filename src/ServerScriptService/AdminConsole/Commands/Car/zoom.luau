local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "zoom",
	Description = "Zooms the car camera by notches of the scroll wheel: positive nearer, negative farther.",
	Group = "Car",
	Args = {
		{
			Type = "integer",
			Name = "notches",
			Description = "Scroll-wheel notches: positive nearer, negative farther.",
		},
	},
	ClientRun = function(_context, notches: number): string
		local camera = controller("CarCameraController")
		camera:Zoom(notches)
		local target = camera:DebugState().zoomTarget
		return `Camera zoom heading for {string.format("%.2f", target or 1)}x the approved distance (1 is the approved camera).`
	end,
}
