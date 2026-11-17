--!strict
-- Drift/RoadAhead: the player's "Road ahead" setting (T-263, docs/game/SETTINGS.md), on this
-- device, for this session. `SettingsController` sets it; `Drift/SplineRoadView` and
-- `Drift/GroundMeshView` read it, and draw or let go of road and ground in front of the car
-- as soon as it changes. A whole number 1 (shortest) to #Config.Spline.Mesh.Ahead (furthest);
-- the default is Medium, 1 600 studs. The pattern is `Drift/RoadBehind`'s; the steps are its own (T-278).
--
-- It can only draw road the server has sent: `Config.Road.AheadStuds` covers the longest step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local RoadAhead = {}
RoadAhead.Changed = Signal.new()

local chosen: number? = nil

function RoadAhead.count(): number
	return #Config.Spline.Mesh.Ahead
end

-- The default for this device (the same on both today, kept apart so touch can differ).
function RoadAhead.default(): number
	local M = Config.Spline.Mesh
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	return if touch then M.AheadTouchDefault else M.AheadDefault
end

function RoadAhead.get(): number
	return chosen or RoadAhead.default()
end

-- Returns whether `value` was taken: a number from 1 to `count()`, rounded to a whole one.
function RoadAhead.set(value: any): boolean
	if type(value) ~= "number" or value ~= value then
		return false
	end
	local v = math.floor(value + 0.5)
	if v < 1 or v > RoadAhead.count() then
		return false
	end
	local before = RoadAhead.get()
	chosen = v
	if v ~= before then
		RoadAhead.Changed:Fire(v)
	end
	return true
end

-- The step's numbers (the current one if none is given): `{ Name, Studs, GroundTiles }`.
function RoadAhead.preset(value: number?): any
	return Config.Spline.Mesh.Ahead[value or RoadAhead.get()]
end

function RoadAhead.name(value: number?): string
	return RoadAhead.preset(value).Name
end

-- Studs of road drawn in front of the car at least (chunk-aligned, so up to a chunk more).
function RoadAhead.studs(value: number?): number
	return RoadAhead.preset(value).Studs
end

-- The longest step's studs: what the server's window ahead must cover.
function RoadAhead.most(): number
	local most = 0
	for _, step in Config.Spline.Mesh.Ahead do
		most = math.max(most, step.Studs)
	end
	return most
end

return RoadAhead
