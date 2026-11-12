local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, key: string?): string
	local player = context.Executor
	local cars = Ops.need("CarService")
	local now = cars:CarKey(player)
	if key == nil then
		local names = {}
		for _, k in Cars.Order do
			table.insert(names, if k == now then `[{k}]` else k)
		end
		return `Cars: {table.concat(names, ", ")}. You're in the {now}.`
	end
	-- Through CarService's own switch-and-tell: the server re-dresses the car and tells the
	-- client which car it's in, exactly as an accepted CarSwitch is answered.
	local got = cars:DebugSetCar(key, player.UserId)
	if got ~= key then
		return `No switch to {key} (no car yet?). You're in the {cars:CarKey(player)}.`
	end
	local numbers = Cars.resolve(key)
	return `Now in the {key}` .. (if numbers then `, top speed {math.round(numbers.TopSpeed)}.` else ".")
end
