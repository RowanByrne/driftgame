--!nonstrict
-- Config: every tuning number in the game, and none of them in the logic
-- (docs/workflow/CODING.md "Foundation kit").
--
-- One module per feature, as a child of this one: `Config.Drift`, `Config.Playground`.
-- They load on first use, so adding one never means editing this file.

local Config = {}

setmetatable(Config, {
	__index = function(_, key: string)
		local module = script:FindFirstChild(key)
		if not module or not module:IsA("ModuleScript") then
			local names = {}
			for _, child in script:GetChildren() do
				if child:IsA("ModuleScript") then
					table.insert(names, child.Name)
				end
			end
			error(`Config: no '{key}'. There is: {table.concat(names, ", ")}`, 2)
		end
		local value = require(module)
		rawset(Config, key, value)
		return value
	end,
})

return Config
