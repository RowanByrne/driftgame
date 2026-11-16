--!strict
-- Drift/RoadBehind: the player's "Road behind" setting (T-230, docs/game/SETTINGS.md), on this
-- device, for this session. `SettingsController` sets it; `Drift/SplineRoadView` and
-- `Drift/GroundMeshView` read it, and keep or let go of what is drawn behind the car as soon
-- as it changes. A whole number 1 (3 000 studs) to #Config.Spline.Mesh.Behind (furthest): the same
-- steps as `Drift/RoadAhead` since T-263.
-- Until the player picks one it is the device's default: shorter on touch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local RoadBehind = {}
RoadBehind.Changed = Signal.new()

local chosen: number? = nil

function RoadBehind.count(): number
	return #Config.Spline.Mesh.Behind
end

-- The default for this device: a phone or tablet gets the shorter one.
function RoadBehind.default(): number
	local M = Config.Spline.Mesh
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	return if touch then M.BehindTouchDefault else M.BehindDefault
end

function RoadBehind.get(): number
	return chosen or RoadBehind.default()
end

-- Returns whether `value` was taken: a number from 1 to `count()`, rounded to a whole one.
function RoadBehind.set(value: any): boolean
	if type(value) ~= "number" or value ~= value then
		return false
	end
	local v = math.floor(value + 0.5)
	if v < 1 or v > RoadBehind.count() then
		return false
	end
	local before = RoadBehind.get()
	chosen = v
	if v ~= before then
		RoadBehind.Changed:Fire(v)
	end
	return true
end

-- The step's numbers (the current one if none is given): `{ Name, Studs }`.
function RoadBehind.preset(value: number?): any
	return Config.Spline.Mesh.Behind[value or RoadBehind.get()]
end

function RoadBehind.name(value: number?): string
	return RoadBehind.preset(value).Name
end

-- Studs of road kept behind the car at least (the window is chunk-aligned, so up to a chunk more).
function RoadBehind.studs(value: number?): number
	return RoadBehind.preset(value).Studs
end

-- Where the drawn road starts, for a car at `at` along it: the start of the chunk `studs()`
-- back. `Drift/SplineRoadView` keeps from this chunk; the ground keeps its road detail from here.
function RoadBehind.from(at: number, studs: number?): number
	local L = Config.Spline.Mesh.ChunkLength
	return math.max(0, math.floor((at - (studs or RoadBehind.studs())) / L) * L)
end

return RoadBehind
