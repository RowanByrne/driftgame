local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "vista",
	Description = "Shows or hides the painted vista round the run on your screen (the ridges and the cloud sea; only up on the spline road), or one part of it, for review shots. No argument toggles it all.",
	Group = "World",
	Args = {
		{
			Type = "string",
			Name = "what",
			Description = "on, off, or a part to toggle: Far, Middle, Near, CloudSea. Leave it out to toggle it all.",
			Optional = true,
		},
	},
	ClientRun = function(_context, what: string?): string
		local view = controller("DriftController").vista
		if not view or view.dead then
			return "No vista: it's only up on the spline road during a run."
		end
		if what == nil or what == "on" or what == "off" then
			local shown = view.folder.Parent ~= nil
			local want = if what == nil then not shown else what == "on"
			view:SetShown(want)
			return if want then `Vista shown ({view.parts} parts).` else "Vista hidden."
		end
		for _, layer in view:DebugState().layers do
			if string.lower(layer.name) == string.lower(what) then
				view:SetShown(not layer.shown, layer.name)
				return if layer.shown then `{layer.name} hidden.` else `{layer.name} shown.`
			end
		end
		if string.lower(what) == "cloudsea" then
			local sea = view.clouds[1]
			local shown = sea ~= nil and sea.folder.Parent ~= nil
			view:SetShown(not shown, "CloudSea")
			return if shown then "Cloud sea hidden." else "Cloud sea shown."
		end
		return `No part '{what}'. Try on, off, Far, Middle, Near or CloudSea.`
	end,
}
