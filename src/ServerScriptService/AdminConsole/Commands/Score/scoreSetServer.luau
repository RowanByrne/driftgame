local Ops = require(script.Parent.Parent.Parent.Ops)

-- Reached only when the command targets someone other than the caller alone: each target's
-- own client does it (`CmdrController:Act`), because only it drives its car and keeps its score.
return function(context, players: { Player }?, points: any, multiplier: any): string
	if type(points) ~= "number" or points ~= points or points < 0 then
		return "The score can't be negative."
	end
	return Ops.sendAction(context, players, "scoreSet", points, multiplier)
end
