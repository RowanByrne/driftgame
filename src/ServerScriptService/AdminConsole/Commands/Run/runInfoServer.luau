local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context): string
	local player = context.Executor
	local road = Ops.need("RoadService")
	local state = road:RunState(player)
	if not state.running then
		return `No road is up. Next run's road: {road:Mode()}.`
	end
	local lines = {
		`Road up: seed {tostring(Ops.seed())}, {road:Mode()} road, {state.players} driver(s), furthest piece {state.furthestN}.`,
	}
	if state.inRun then
		local cars = Ops.need("CarService")
		local at = cars:BelievedPosition(player.UserId)
		local piece = at and road:PieceAt(at)
		local studs = at and Ops.roadDistance(at)
		local where = if piece then `piece {piece.n} ({math.round(piece.t * 100)}% along, {math.round(piece.lateral)} studs off centre)` else "off the road"
		if studs then
			where ..= `, {math.floor(studs)} studs from the start`
		end
		table.insert(lines, `You're in the run: {where}.`)
	else
		table.insert(lines, "You're not in it.")
	end
	return table.concat(lines, "\n")
end
