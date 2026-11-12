local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context): string
	local player = context.Executor
	local road = Ops.need("RoadService")
	if not road:InRun(player) then
		return "You're not in a run."
	end
	local cf = Ops.endRun(player)
	if not cf then
		return "Run ended (the car stayed where it was)."
	end
	return `Run ended; back {Ops.placed(cf)}.`
end
