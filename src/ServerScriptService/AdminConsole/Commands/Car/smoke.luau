local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The low end's smoke, switched live for the comparison (T-290, features/tyre-particles.md
-- "The low end"). Sets the Workspace attribute `Drift/Wheels` reads every frame, on this
-- client only. Comes out with the losing look.
return {
	Name = "smoke",
	Description = "Switches the light-drift smoke: billows, wisp, or off (today's). Your screen only.",
	Group = "Car",
	Args = {
		{
			Type = "string",
			Name = "mode",
			Description = "billows, wisp or off",
		},
	},
	ClientRun = function(_context, mode: string): string
		local L = require(ReplicatedStorage.Shared.Config).Fx.LowSmoke
		mode = string.lower(mode)
		if mode ~= "billows" and mode ~= "wisp" and mode ~= "off" then
			return `Unknown smoke "{mode}": use billows, wisp or off.`
		end
		workspace:SetAttribute(L.Attribute, mode)
		return `Light-drift smoke: {mode}.`
	end,
}
