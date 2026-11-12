local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, players: { Player }?): string
	local road = Ops.need("RoadService")
	return Ops.forEach(context, players, function(player)
		if not road:InRun(player) then
			return "Not in a run."
		end
		local cf = Ops.endRun(player)
		if not cf then
			return "Run ended (the car stayed where it was)."
		end
		return `Run ended; back {Ops.placed(cf)}.`
	end)
end
