local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ops = require(script.Parent.Parent.Parent.Ops)

return function(context, target: Player?): string
	local player = target or context.Executor
	local ok, why = Ops.need("CmdrService"):Allowed(player)
	return string.format(
		"%s (%d): %s, because %s. %d user id(s) on the admin list; the game is owned by %s %d.",
		player.Name,
		player.UserId,
		if ok then "admin" else "not an admin",
		why,
		#Config.Admin.UserIds,
		string.lower(game.CreatorType.Name),
		game.CreatorId
	)
end
