local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context): string
	local player = context.Executor
	local visit = Ops.need("GarageVisitService")
	if not visit:InGarage(player) then
		return "You're not in the garage."
	end
	local ok, why = visit:Leave(player)
	if not ok then
		return `Still in: {tostring(why)}.`
	end
	local at = Ops.need("CarService"):BelievedPosition(player.UserId)
	return `Out of the garage, at {Ops.v3(at)}.`
end
