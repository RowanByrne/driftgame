local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, players: { Player }?): string
	local cars = Ops.need("CarService")
	return Ops.forEach(context, players, function(player)
		local believed = cars:BelievedPosition(player.UserId)
		local cf = nil
		local where = "world spawn"
		if Ops.inRun(player) then
			cf = Ops.need("RoadService"):SafeStart(believed)
			where = "road"
		end
		if not cf then
			cf = if believed then cars:SpawnCFrameNear(believed) else cars:SpawnCFrame()
		end
		local placed, why = Ops.place(player, cf)
		if not placed then
			return `No respawn: {why}.`
		end
		return `Respawned on the {where}, {Ops.placed(placed)}.`
	end)
end
