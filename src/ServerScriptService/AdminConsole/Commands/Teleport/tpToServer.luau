local Ops = require(script.Parent.Parent.Parent.Ops)

local LIMIT = 1e6 -- studs: anything further is a typo, not a place

return function(context, players: { Player }, x: number, y: number, z: number, heading: number?): string
	for _, value in { x, y, z, heading or 0 } do
		if value ~= value or math.abs(value) > LIMIT then
			return "Those numbers aren't a place."
		end
	end
	local at = Vector3.new(x, y, z)
	local cf = CFrame.new(at) * CFrame.Angles(0, math.rad(heading or 0), 0)
	return Ops.forEach(context, players, function(player)
		if Ops.inRun(player) and not Ops.need("RoadService"):PieceAt(at) then
			Ops.leaveRun(player)
		end
		local placed, why = Ops.place(player, cf)
		return if placed then `Moved {Ops.placed(placed)}.` else `Not moved: {why}.`
	end)
end
