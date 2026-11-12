local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, seed: number?): string
	local player = context.Executor
	local road = Ops.need("RoadService")
	if seed == nil then
		local current = Ops.seed()
		return if current then `Seed {current}.` else "No road is up."
	end

	if road:HasRoad() then
		local others = road:RunnerCount() - (if road:InRun(player) then 1 else 0)
		if others > 0 then
			return `{others} other driver(s) are on this road; a new seed would pull it out from under them.`
		end
		if road:InRun(player) then
			Ops.endRun(player) -- the last runner leaving takes the road down
		end
		if road:HasRoad() then
			road:Stop()
		end
	end
	road:Generate(seed)
	local cf = Ops.startRun(player)
	if not cf then
		if road:RunnerCount() == 0 then
			road:Stop()
		end
		return "The run didn't start (no car yet?)."
	end
	return `Run restarted on seed {seed}, {Ops.placed(cf)}.`
end
