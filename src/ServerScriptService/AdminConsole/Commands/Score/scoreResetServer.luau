local Ops = require(script.Parent.Parent.Parent.Ops)

-- Reached only when the command targets someone other than the caller alone: each target's
-- own client does it (`CmdrController:Act`), because only it drives its car and keeps its score.
return function(context, players: { Player }?): string
	return Ops.sendAction(context, players, "scoreReset")
end
