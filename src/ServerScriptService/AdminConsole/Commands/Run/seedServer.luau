local Players = game:GetService("Players")

local Ops = require(script.Parent.Parent.Parent.Ops)

-- The road is one road for everyone on it, so a new seed takes every driver with it rather
-- than leaving anyone on a road that no longer exists.
return function(context, seed: number?): string
	local road = Ops.need("RoadService")
	if seed == nil then
		local current = Ops.seed()
		return if current then `Seed {current}.` else "No road is up."
	end

	local drivers = {}
	if road:HasRoad() then
		for _, entry in road:RunReport() do
			local player = Players:GetPlayerByUserId(entry.userId)
			if player then
				table.insert(drivers, player)
			end
		end
	end
	if #drivers == 0 then
		drivers = { context.Executor }
	end
	for _, player in drivers do
		if road:InRun(player) then
			Ops.endRun(player) -- the last runner leaving takes the road down
		end
	end
	if road:HasRoad() then
		road:Stop()
	end
	road:Generate(seed)
	local moved = {}
	for _, player in drivers do
		if Ops.startRun(player) then
			table.insert(moved, player.Name)
		end
	end
	if #moved == 0 then
		if road:RunnerCount() == 0 then
			road:Stop()
		end
		return "The run didn't start (no car yet?)."
	end
	return `Road laid again on seed {seed}; at its start: {table.concat(moved, ", ")}.`
end
