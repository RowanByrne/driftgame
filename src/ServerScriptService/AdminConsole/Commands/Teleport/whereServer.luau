local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, target: Player?): string
	local player = target or context.Executor
	local cars = Ops.need("CarService")
	local at = cars:BelievedPosition(player.UserId)
	if not at then
		return `The server hasn't placed {player.Name}'s car yet.`
	end
	local parts = { `{player.Name}: at {Ops.v3(at)}, in the {tostring(cars:WorldAt(at))}` }
	local road = Ops.service("RoadService")
	local piece = road and road:PieceAt(at)
	if piece then
		local studs = Ops.roadDistance(at)
		table.insert(
			parts,
			`on piece {piece.n} ({piece.kind}, {math.round(piece.t * 100)}% along, {math.round(piece.lateral)} studs off centre)`
				.. (if studs then `, {math.floor(studs)} studs from the road's start` else "")
		)
	end
	local visit = Ops.service("GarageVisitService")
	if visit and visit:InGarage(player) then
		table.insert(parts, "in the garage")
	end
	table.insert(parts, `in the {cars:CarKey(player)}`)
	return table.concat(parts, ", ") .. "."
end
