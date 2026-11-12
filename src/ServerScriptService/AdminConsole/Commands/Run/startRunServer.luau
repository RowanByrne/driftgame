local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, seed: number?): string
	local player = context.Executor
	local road = Ops.need("RoadService")
	if road:InRun(player) then
		return `You're already in a run (seed {tostring(Ops.seed())}). end-run first, or seed <n> to restart on another road.`
	end
	local generated = false
	if seed ~= nil then
		if road:HasRoad() then
			return `A road is already up (seed {tostring(Ops.seed())}) with {road:RunnerCount()} driver(s) on it. start-run with no seed joins it.`
		end
		road:Generate(seed)
		generated = true
	end
	local cf = Ops.startRun(player)
	if not cf then
		if generated and road:RunnerCount() == 0 then
			road:Stop()
		end
		return "The run didn't start (no car yet, or you're on the Studio spline test road)."
	end
	return `Run started on seed {tostring(Ops.seed())}, {Ops.placed(cf)}.`
end
