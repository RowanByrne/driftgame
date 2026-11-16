--!strict
-- Drift/SoundLevels: the player's "Sound" settings (T-256, docs/game/SETTINGS.md), on this
-- device, for this session, the same way as `Drift/GroundDetail`. `SettingsController` sets
-- them; the sound modules put each `Sound` they make in its category's `SoundGroup`, and
-- Roblox plays a sound at its own `Volume` times its group's. So a level scales a category
-- ON TOP of the mix the code sets (`Config.Fx`), live, one-shots and loops alike, and none of
-- the sound modules has to read it each frame.
--
-- A level is a whole percent, 0 to 100, default 30, and 30 IS TODAY'S MIX (the user,
-- 2026-11-16): a group plays at `level / Reference`, so 30% is 1x, 15% half, 0 silent and
-- 100% about 3.33x the mix. The groups live in `SoundService` as
-- `SoundLevel_<Category>`, made on the client only: on the server (the Fx tests build sounds
-- there) `apply` leaves a sound alone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Signal = require(ReplicatedStorage.Shared.Signal)

local SoundLevels = {}
SoundLevels.Changed = Signal.new() -- (category, level)

-- The categories, in the order the settings tab shows them, with their labels.
SoundLevels.Categories = { "Music", "TireSqueal", "OffRoad", "Suspension", "Engine" }
SoundLevels.Labels = {
	Music = "Music",
	TireSqueal = "Tire squeal",
	OffRoad = "Off-road drift",
	Suspension = "Suspension",
	Engine = "Engine",
}
SoundLevels.Default = 30
SoundLevels.Reference = 30 -- the level that plays the mix as `Config.Fx` sets it

local levels: { [string]: number } = {}
local groups: { [string]: SoundGroup } = {}

local function known(category: any): boolean
	return type(category) == "string" and SoundLevels.Labels[category] ~= nil
end

function SoundLevels.get(category: string): number
	return levels[category] or SoundLevels.Default
end

-- Every level, as `{ [category] = percent }`.
function SoundLevels.all(): { [string]: number }
	local out = {}
	for _, category in SoundLevels.Categories do
		out[category] = SoundLevels.get(category)
	end
	return out
end

-- The category's `SoundGroup`, made on first ask (client only; nil on the server).
function SoundLevels.group(category: string): SoundGroup?
	if not known(category) or not RunService:IsClient() then
		return nil
	end
	local group = groups[category]
	if group and group.Parent then
		return group
	end
	local name = "SoundLevel_" .. category
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		group = existing
	else
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Parent = SoundService
	end
	(group :: SoundGroup).Volume = SoundLevels.scale(category)
	groups[category] = group :: SoundGroup
	return group
end

-- What the category's group multiplies its sounds by: `level / Reference`.
function SoundLevels.scale(category: string): number
	return SoundLevels.get(category) / SoundLevels.Reference
end

-- Put `sound` in `category`'s group, so the player's level scales it. Server: does nothing.
function SoundLevels.apply(sound: Sound, category: string)
	local group = SoundLevels.group(category)
	if group then
		sound.SoundGroup = group
	end
end

-- Returns whether `value` was taken: a number from 0 to 100, rounded to a whole percent.
function SoundLevels.set(category: any, value: any): boolean
	if not known(category) or type(value) ~= "number" or value ~= value then
		return false
	end
	local v = math.floor(value + 0.5)
	if v < 0 or v > 100 then
		return false
	end
	local before = SoundLevels.get(category)
	levels[category] = v
	local group = SoundLevels.group(category)
	if group then
		group.Volume = v / SoundLevels.Reference
	end
	if v ~= before then
		SoundLevels.Changed:Fire(category, v)
	end
	return true
end

return SoundLevels
