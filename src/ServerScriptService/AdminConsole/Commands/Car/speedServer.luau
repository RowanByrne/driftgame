local Ops = require(script.Parent.Parent.Parent.Ops)

-- Reached only when the command targets someone other than the caller alone: each target's
-- own client does it (`CmdrController:Act`), because only it drives its car and keeps its score.
return function(context, players: { Player }?, speed: any): string
	if type(speed) ~= "number" then
		return "Give a speed to set other players' cars; reading one works for your own car only."
	end
	if speed ~= speed or math.abs(speed) > 1000 then
		return "Speed is -1000 to 1000 studs/s."
	end
	return Ops.sendAction(context, players, "speed", speed)
end
