local Ops = require(script.Parent.Parent.Parent.Ops)

local LIFT = 2 -- studs above where it was, so it settles on to the ground rather than into it
local REACH = 300 -- studs: further than this from where the server believes the car is, and
-- the client's pose is stale (a respawn in flight), so the server's own belief is used

return function(context): string
	local player = context.Executor
	local cars = Ops.need("CarService")
	local believed = cars:BelievedPosition(player.UserId)
	local pose = context:GetData()
	local at, heading
	if typeof(pose) == "CFrame" and pose.Position == pose.Position and (not believed or (pose.Position - believed).Magnitude <= REACH) then
		at, heading = pose.Position, Ops.headingOf(pose)
	elseif believed then
		at, heading = believed, 0
	else
		return "The server hasn't placed your car yet."
	end
	local cf = CFrame.new(at.X, at.Y + LIFT, at.Z) * CFrame.Angles(0, math.rad(heading), 0)
	local placed, why = Ops.place(player, cf)
	return if placed then `Righted {Ops.placed(placed)}.` else `Not moved: {why}.`
end
