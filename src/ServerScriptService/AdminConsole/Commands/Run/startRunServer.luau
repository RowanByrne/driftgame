local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, players: { Player }?, seed: number?): string
	local road = Ops.need("RoadService")
	local generated = false
	if seed ~= nil then
		if road:HasRoad() then
			return `A road is already up (seed {tostring(Ops.seed())}) with {road:RunnerCount()} driver(s) on it. Leave the seed out to join it, or seed <n> to restart it.`
		end
		road:Generate(seed)
		generated = true
	end
	local reply = Ops.forEach(context, players, function(player)
		if road:InRun(player) then
			return `Already in a run (seed {tostring(Ops.seed())}).`
		end
		local cf = Ops.startRun(player)
		if not cf then
			return "The run didn't start (no car yet, or on the Studio spline test road)."
		end
		return `Run started on seed {tostring(Ops.seed())}, {Ops.placed(cf)}.`
	end)
	if generated and road:RunnerCount() == 0 then
		road:Stop()
	end
	return reply
end
