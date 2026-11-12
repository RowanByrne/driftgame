local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, players: { Player }, key: string?): string
	local cars = Ops.need("CarService")
	if key == nil then
		return `Cars: {table.concat(Cars.Order, ", ")}.\n` .. Ops.forEach(context, players, function(player)
			return `In the {cars:CarKey(player)}.`
		end)
	end
	local numbers = Cars.resolve(key)
	return Ops.forEach(context, players, function(player)
		-- Through CarService's own switch-and-tell: the server re-dresses the car and tells
		-- that player's client which car it's in, exactly as an accepted CarSwitch is answered.
		local got = cars:DebugSetCar(key, player.UserId)
		if got ~= key then
			return `No switch to {key} (no car yet?). In the {cars:CarKey(player)}.`
		end
		return `Now in the {key}` .. (if numbers then `, top speed {math.round(numbers.TopSpeed)}.` else ".")
	end)
end
