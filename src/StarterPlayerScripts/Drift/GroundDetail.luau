--!strict
-- Drift/GroundDetail: the player's "Ground detail" setting (T-225, docs/game/SETTINGS.md), on
-- this device, for this session. `SettingsController` sets it; `Drift/GroundMeshView` reads
-- it and redraws live when it changes. A whole number 1 (light) to #Config.Spline.Ground.Detail
-- (far and sharp). Until the player picks one it is the device's default: lighter on touch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local GroundDetail = {}
GroundDetail.Changed = Signal.new()

local chosen: number? = nil

function GroundDetail.count(): number
	return #Config.Spline.Ground.Detail
end

-- The default for this device: a phone or tablet gets the lighter one.
function GroundDetail.default(): number
	local G = Config.Spline.Ground
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	return if touch then G.DetailTouchDefault else G.DetailDefault
end

function GroundDetail.get(): number
	return chosen or GroundDetail.default()
end

-- Returns whether `value` was taken: a number from 1 to `count()`, rounded to a whole one.
function GroundDetail.set(value: any): boolean
	if type(value) ~= "number" or value ~= value then
		return false
	end
	local v = math.floor(value + 0.5)
	if v < 1 or v > GroundDetail.count() then
		return false
	end
	local before = GroundDetail.get()
	chosen = v
	if v ~= before then
		GroundDetail.Changed:Fire(v)
	end
	return true
end

-- The numbers for a setting (the current one if none is given).
function GroundDetail.preset(value: number?): any
	return Config.Spline.Ground.Detail[value or GroundDetail.get()]
end

function GroundDetail.name(value: number?): string
	return GroundDetail.preset(value).Name
end

return GroundDetail
