local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "horizon",
	Description = "Shows or hides the mountains round the endless run on your screen (they exist only while you're on the spline road). No argument toggles them.",
	Group = "World",
	Args = {
		{
			Type = "boolean",
			Name = "on",
			Description = "on or off. Leave it out to toggle.",
			Optional = true,
		},
	},
	ClientRun = function(_context, on: boolean?): string
		local view = controller("DriftController").horizon
		if not view or view.dead or not view.folder then
			return "No horizon: it's only up on the spline road during a run."
		end
		local shown = view.folder.Parent ~= nil
		local want = if on == nil then not shown else on
		-- Out of the Workspace and back: the view keeps moving its layers either way, so
		-- putting it back puts it where it would have been.
		view.folder.Parent = if want then Workspace else nil
		local parts = view:DebugState().parts
		return if want then `Horizon shown ({parts} parts).` else `Horizon hidden ({parts} parts).`
	end,
}
