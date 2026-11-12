local Ops = require(script.Parent.Parent.Parent.Ops)

local LIFT = 2 -- studs above where it was, so it settles on to the ground rather than into it
local REACH = 300 -- studs: further than this from where the server believes the car is, and
-- the client's pose is stale (a respawn in flight), so the server's own belief is used

return function(context, players: { Player }?): string
	local cars = Ops.need("CarService")
	local pose = context:GetData() -- the CALLER's car as their screen shows it
	return Ops.forEach(context, players, function(player)
		local believed = cars:BelievedPosition(player.UserId)
		local cf
		if
			player == context.Executor
			and typeof(pose) == "CFrame"
			and pose.Position == pose.Position
			and (not believed or (pose.Position - believed).Magnitude <= REACH)
		then
			cf = CFrame.new(pose.Position + Vector3.new(0, LIFT, 0)) * CFrame.Angles(0, math.rad(Ops.headingOf(pose)), 0)
		elseif believed and Ops.inRun(player) then
			-- the server knows the road's direction, not the car's
			local onRoad = Ops.need("RoadService"):SafeStart(believed)
			cf = onRoad
		elseif believed then
			cf = CFrame.new(believed + Vector3.new(0, LIFT, 0))
		else
			return "The server hasn't placed that car yet."
		end
		if not cf then
			return "Nowhere to put the car."
		end
		local placed, why = Ops.place(player, cf)
		return if placed then `Righted {Ops.placed(placed)}.` else `Not moved: {why}.`
	end)
end
