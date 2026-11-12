local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, target: Player?): string
	local player = target or context.Executor
	local road = Ops.need("RoadService")
	local state = road:RunState(player)
	if not state.running then
		return `No road is up. Next run's road: {road:Mode()}.`
	end
	local names = {}
	for _, entry in road:RunReport() do
		local p = game:GetService("Players"):GetPlayerByUserId(entry.userId)
		table.insert(names, if p then p.Name else tostring(entry.userId))
	end
	local lines = {
		`Road up: seed {tostring(Ops.seed())}, {road:Mode()} road, furthest piece {state.furthestN}, drivers: {table.concat(names, ", ")}.`,
	}
	local who = if player == context.Executor then "You're" else `{player.Name} is`
	if state.inRun then
		local cars = Ops.need("CarService")
		local at = cars:BelievedPosition(player.UserId)
		local piece = at and road:PieceAt(at)
		local studs = at and Ops.roadDistance(at)
		local where = if piece then `piece {piece.n} ({math.round(piece.t * 100)}% along, {math.round(piece.lateral)} studs off centre)` else "off the road"
		if studs then
			where ..= `, {math.floor(studs)} studs from the start`
		end
		table.insert(lines, `{who} in the run: {where}.`)
	else
		table.insert(lines, `{who} not in it.`)
	end
	return table.concat(lines, "\n")
end
