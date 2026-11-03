--!nonstrict
-- Loader: the shared half of the Services and Controllers loaders
-- (docs/workflow/CODING.md "Layout" and "Foundation kit").
--
-- Every direct ModuleScript child of the folder is required, then:
--   Init()  on all of them, highest Priority first, in order, and nothing yields here.
--   Start() on each, in its own thread.
-- A module that fails is warned about and skipped, so one broken module doesn't take the
-- game down; the warning is what a playtest's console check catches.

local RunService = game:GetService("RunService")

local Loader = {}

export type Loaded = { [string]: any }

function Loader.load(folder: Instance?, label: string): Loaded
	local loaded: Loaded = {}
	local order: { { name: string, module: any } } = {}

	if not folder then
		warn(`[{label}] there is no folder to load from`)
		return loaded
	end

	for _, child in (folder :: Instance):GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end
		local ok, result = pcall(require, child)
		if not ok then
			warn(`[{label}] {child.Name} failed to load: {result}`)
			continue
		end
		if type(result) ~= "table" then
			warn(`[{label}] {child.Name} returned a {type(result)}, not a table`)
			continue
		end
		loaded[child.Name] = result
		table.insert(order, { name = child.Name, module = result })
	end

	table.sort(order, function(a, b)
		local pa = a.module.Priority or 0
		local pb = b.module.Priority or 0
		if pa == pb then
			return a.name < b.name
		end
		return pa > pb
	end)

	for _, entry in order do
		local init = entry.module.Init
		if type(init) == "function" then
			local ok, err = pcall(init, entry.module)
			if not ok then
				warn(`[{label}] {entry.name}:Init() errored: {err}`)
			end
		end
	end

	for _, entry in order do
		local start = entry.module.Start
		if type(start) == "function" then
			task.spawn(function()
				local ok, err = pcall(start, entry.module)
				if not ok then
					warn(`[{label}] {entry.name}:Start() errored: {err}`)
				end
			end)
		end
	end

	return loaded
end

-- The Studio-only debug bridge (docs/workflow/TESTING.md "Reaching live game state").
-- Invoke(name, member, ...) where name is a loaded module, or Debug<Name>Tests for a
-- module in the tests folder. A function member is called as a method; anything else is
-- returned as it is.
function Loader.bridge(loaded: Loaded, parent: Instance, testsFolder: Instance?): BindableFunction?
	if not RunService:IsStudio() then
		return nil
	end

	local function resolve(name: string): any?
		local target = loaded[name]
		if target then
			return target
		end
		local testName = string.match(name, "^Debug(%w+Tests)$")
		if testName and testsFolder then
			local module = testsFolder:FindFirstChild(testName)
			if module and module:IsA("ModuleScript") then
				return require(module)
			end
		end
		return nil
	end

	local function names(): string
		local list = {}
		for name in loaded do
			table.insert(list, name)
		end
		if testsFolder then
			for _, child in testsFolder:GetChildren() do
				if child:IsA("ModuleScript") then
					table.insert(list, `Debug{child.Name}`)
				end
			end
		end
		table.sort(list)
		return table.concat(list, ", ")
	end

	local bridge = Instance.new("BindableFunction")
	bridge.Name = "DebugBridge"
	bridge.OnInvoke = function(name: string, member: string, ...)
		local target = resolve(name)
		if not target then
			error(`DebugBridge: no '{name}'. There is: {names()}`, 0)
		end
		local value = target[member]
		if value == nil then
			local members = {}
			for key in target do
				table.insert(members, tostring(key))
			end
			table.sort(members)
			error(`DebugBridge: {name} has no '{member}'. It has: {table.concat(members, ", ")}`, 0)
		end
		if type(value) == "function" then
			return value(target, ...)
		end
		return value
	end
	bridge.Parent = parent
	return bridge
end

return Loader
