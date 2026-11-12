local Players = game:GetService("Players")

local function controller(name: string)
	return require(Players.LocalPlayer.PlayerScripts.Controllers[name])
end

return {
	Name = "get-in",
	Aliases = { "getin" },
	Description = "Gets you back into your car, as its prompt does (you must be near the door).",
	Group = "Car",
	Args = {},
	ClientRun = function(): string
		local ok, why = controller("CarEntryController"):RequestEnter()
		return if ok then "Getting in." else `Not in: {tostring(why)}.`
	end,
}
