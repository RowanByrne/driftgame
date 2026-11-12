local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "get-out",
	Aliases = { "getout" },
	Description = "Gets you out of the car, as the Get out button does (the car must be slow enough).",
	Group = "Car",
	Args = {},
	ClientRun = function(): string
		local ok, why = controller("CarEntryController"):RequestExit()
		return if ok then "Getting out." else `Not out: {tostring(why)}.`
	end,
}
