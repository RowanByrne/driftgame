--!strict
--!native
-- Classify a channel by the lower of its two natural banks at two distances.
-- Its axis runs perpendicular to the banks. A crossing sees open ground on at
-- least one side of its heading, even when the stream below it has steep walls.
local Ground = require(script.Parent.Ground)
local Gorge = {}

function Gorge.pressure(near: number, far: number): number
	return math.max(0, math.min(near - 12, 0.72 * (far - 24)))
end

function Gorge.along(f: Ground.Field, x: number, z: number, fx: number, fz: number, h: number): number
	local function section(dx: number, dz: number): number
		local near = math.min(Ground.h(f, x - 300 * dx, z - 300 * dz), Ground.h(f, x + 300 * dx, z + 300 * dz)) - h
		if near <= 12 then return 0 end
		local far = math.min(Ground.h(f, x - 550 * dx, z - 550 * dz), Ground.h(f, x + 550 * dx, z + 550 * dz)) - h
		return Gorge.pressure(near, far)
	end
	local banks = section(-fz, fx)
	return if banks > 0 then math.max(0, banks - section(fx, fz)) else 0
end

return Gorge
