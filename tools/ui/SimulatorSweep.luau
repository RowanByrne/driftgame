--[[
SimulatorSweep.luau: one step of the viewport sweep through Studio's device simulator
(docs/workflow/TESTING.md "Checking UI").

The simulator and the measurement live in different datamodels, so the sweep is a loop the agent runs:
  1. action = "plan"  -> which simulator device matches each CONFIG.matrix row (run once)
  2. for each row: action = "set" with that row -> device, ActualResolution, orientation; returns the
     viewport the simulator reports
     then MeasureUI.luau in the Client datamodel; save its result under the row's label
  3. action = "stop"  -> LandscapeLeft, then stop the simulation (always run this, even after an error)
Datamodel (verified 2026-11-05, Studio 0.745): "Edit" when not playing; "Client" during Play (the Edit
datamodel is unavailable while playing). Every action works in both, and the device set in Client
applies to the running playtest (TouchEnabled turns true on phones).
The call sequence, as verified in Studio: GetDeviceListAsync / GetDeviceInfoAsync, SetDeviceAsync,
SetScalingModeAsync(ActualResolution), SetOrientationAsync, and LandscapeLeft before StopSimulationAsync.
Device names are matched case-, space- and underscore-insensitively against the id and any name-like
field: an exact match wins, then a substring match only if it is unique ("iPhone 13 Pro" is also inside
"iPhone 13 Pro Max", "iPad" inside nine devices). Ambiguous rows are reported, never guessed.
There is no "Desktop" device: desktop rows use HD 720 / HD 1080 / Average Laptop (action = "list").
]]

local CONFIG = {
	action = "plan", -- "plan" | "list" | "set" | "stop"
	-- For "set": one row (copy it from the matrix).
	row = { label = "phone-portrait", device = "iPhone 13 Pro", orientation = "Portrait" },
	matrix = {
		{ label = "desktop", device = "HD 720", orientation = "LandscapeLeft" },
		{ label = "desktop-large", device = "HD 1080", orientation = "LandscapeLeft" },
		{ label = "tablet", device = "iPad 6th Generation", orientation = "LandscapeLeft" },
		{ label = "phone-landscape-small", device = "iPhone 7", orientation = "LandscapeLeft" },
		{ label = "phone-landscape", device = "iPhone 13 Pro", orientation = "LandscapeLeft" },
		{ label = "phone-portrait", device = "iPhone 13 Pro", orientation = "Portrait" },
	},
	settleSeconds = 1.0,
}

local ok, sim = pcall(function()
	return game:GetService("StudioDeviceSimulatorService" :: any)
end)
if not ok or not sim then
	return { error = "StudioDeviceSimulatorService is not available in this datamodel: " .. tostring(sim) }
end
local S = sim :: any

local function squash(s: string): string
	return (string.gsub(string.lower(s), "[%s_%-]", ""))
end

local function describe(id: any): { [string]: any }
	local entry: { [string]: any } = { id = tostring(id) }
	local okInfo, info = pcall(function()
		return S:GetDeviceInfoAsync(id)
	end)
	if okInfo and type(info) == "table" then
		for k, v in info do
			if type(k) == "string" and (type(v) == "string" or type(v) == "number" or type(v) == "boolean") then
				entry[k] = v
			elseif type(k) == "string" and typeof(v) == "Vector2" then
				entry[k] = string.format("%dx%d", v.X, v.Y)
			end
		end
	elseif okInfo then
		entry.info = tostring(info)
	end
	return entry
end

local function devices(): { { [string]: any } }
	local okList, list = pcall(function()
		return S:GetDeviceListAsync()
	end)
	if not okList then
		error("GetDeviceListAsync failed: " .. tostring(list))
	end
	local out = {}
	for _, id in list do
		table.insert(out, describe(id))
	end
	return out
end

-- Exact id/Name match first; otherwise a substring match, but only when exactly one device has it.
local function match(all: { { [string]: any } }, wanted: string): ({ [string]: any }?, string?)
	local w = squash(wanted)
	local partial = {}
	for _, d in all do
		if squash(d.id) == w or (type(d.Name) == "string" and squash(d.Name) == w) then
			return d, nil
		end
		for _, v in d do
			if type(v) == "string" and string.find(squash(v), w, 1, true) then
				table.insert(partial, d)
				break
			end
		end
	end
	if #partial == 1 then
		return partial[1], nil
	elseif #partial > 1 then
		local ids = {}
		for _, d in partial do
			table.insert(ids, d.id)
		end
		return nil, "ambiguous: " .. table.concat(ids, ", ")
	end
	return nil, "no match"
end

local function viewport(): string
	local cam = workspace.CurrentCamera
	return if cam then string.format("%dx%d", cam.ViewportSize.X, cam.ViewportSize.Y) else "no camera"
end

if CONFIG.action == "list" then
	local list = devices()
	local byId = {}
	for _, d in list do
		byId[d.id] = d
	end
	return { count = #list, devices = byId }
elseif CONFIG.action == "plan" then
	local all = devices()
	local plan = {}
	for _, row in CONFIG.matrix do
		local d, why = match(all, row.device)
		plan[row.label] = if d then { id = d.id, orientation = row.orientation } else { missing = row.device, why = why }
	end
	return { plan = plan, note = "Use each id as row.device for action = \"set\"." }
elseif CONFIG.action == "set" then
	local row = CONFIG.row
	local all = devices()
	local d, why = match(all, row.device)
	if not d then
		return { error = row.device .. ": " .. tostring(why) .. " (run action = \"list\" and use an exact id or name)" }
	end
	local steps = {}
	local function step(name: string, fn: () -> ())
		local okStep, err = pcall(fn)
		steps[name] = if okStep then "ok" else tostring(err)
		return okStep
	end
	-- Device first: an orientation set before the device can be rejected or undone.
	step("SetDeviceAsync", function()
		S:SetDeviceAsync(d.id)
	end)
	step("SetScalingModeAsync", function()
		S:SetScalingModeAsync(Enum.DeviceSimulatorScalingMode.ActualResolution)
	end)
	step("SetOrientationAsync", function()
		S:SetOrientationAsync((Enum.ScreenOrientation :: any)[row.orientation])
	end)
	task.wait(CONFIG.settleSeconds)
	return { label = row.label, device = d.id, orientation = row.orientation, steps = steps, viewport = viewport() }
elseif CONFIG.action == "stop" then
	local steps = {}
	local okO, errO = pcall(function()
		S:SetOrientationAsync(Enum.ScreenOrientation.LandscapeLeft)
	end)
	steps.SetOrientationAsync = if okO then "ok" else tostring(errO)
	local okS, errS = pcall(function()
		S:StopSimulationAsync()
	end)
	steps.StopSimulationAsync = if okS then "ok" else tostring(errS)
	return { stopped = okS, steps = steps, viewport = viewport() }
end
return { error = "unknown action " .. tostring(CONFIG.action) }
