local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

-- T-339 (features/ground-look.md): the ground-look trial's switch, on your screen only.
return {
	Name = "ground-look",
	Aliases = { "look" },
	Description = "Switches how the mountain's ground looks, on your screen, redrawing it round you: old, blend, detail, rock or sheet. No argument says which is on and what it costs.",
	Group = "World",
	Args = {
		{
			Type = "string",
			Name = "look",
			Description = "old (today's), blend (colours by steepness and height), detail (blend with a detail texture), rock (blend with Roblox rock on steep faces), sheet (blend over the grass, rocky grass, rock and snow texture sheet).",
			Optional = true,
		},
	},
	ClientRun = function(_context, look: string?): string
		local Config = require(ReplicatedStorage.Shared.Config)
		local view = controller("DriftController").groundView
		if not view or view.dead then
			return "No ground: it's only drawn on the spline road during a run."
		end
		if look == nil then
			local d = view:DebugLook()
			return `Ground look {d.look}: {d.tiles} tiles shown, {d.rockShown} with rock ({d.rockHeld} rock meshes held).`
		end
		look = string.lower(look)
		if not table.find(Config.GroundLook.Looks, look) then
			return `No look '{look}'. Try {table.concat(Config.GroundLook.Looks, ", ")}.`
		end
		Workspace:SetAttribute("__ground_look", look)
		view:Restyle()
		return `Ground look: {look}. Redrawing round you.`
	end,
}
