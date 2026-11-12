--!strict
-- SkyController: the sky and the day-night cycle on this client
-- (docs/game/features/day-night.md, T-144).
--
-- Works the moment out from the server's clock (`workspace:GetServerTimeNow()`), asks
-- `Shared/DayNight` for that moment's look, and sets it on this client's Lighting: the
-- clock (so Roblox's own sun, moon and stars move), the light, the atmosphere, the clouds
-- and the colour grading. Every client does the same sum, so everyone on a server sees the
-- same sky and nothing is sent. The server sets no lighting.
--
-- It runs everywhere, not only in the run: there is one sky. The garage room is lit by its
-- own lamps.
--
-- THE INSTANCES it drives, made on this client if the place has none, and adopted if it
-- has: Lighting's `Atmosphere` and `Sky`, the Terrain's `Clouds`, and three post effects of
-- its own in Lighting (`DayNightGrade`, `DayNightBloom`, `DayNightRays`).
--
-- THE CLIFFS' HAZE: the foot of each cliff in the road's mesh takes the look's `CliffHaze`
-- (`Road/SplineMesh.setHaze`), rewritten only when it has moved `HazeStep`.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DayNight = require(ReplicatedStorage.Shared.DayNight)
local SplineMesh = require(ReplicatedStorage.Shared.Road.SplineMesh)

local SkyController = {}
SkyController.Priority = 0

local cycle: DayNight.Cycle
local atmosphere: Atmosphere
local sky: Sky
local clouds: Clouds?
local grade: ColorCorrectionEffect
local bloom: BloomEffect
local rays: SunRaysEffect

-- Studio test controls: hold the cycle at a moment, or run it faster from one
local hold: number? = nil
local speed = 1
local anchorT = 0
local anchorClock = 0

local lastHaze: Color3? = nil
local stats = { applied = 0, hazeWrites = 0, hazeMeshes = 0, worstMs = 0 }
local lastLook: { [string]: any }? = nil

local function adopt<T>(parent: Instance, className: string, name: string?): T
	local found = if name then parent:FindFirstChild(name) else parent:FindFirstChildOfClass(className)
	if found and found:IsA(className) then
		return found :: any
	end
	local made = Instance.new(className)
	if name then
		made.Name = name
	end
	made.Parent = parent
	return made :: any
end

local function now(): number
	if hold then
		return hold
	end
	if speed ~= 1 then
		return (anchorT + (os.clock() - anchorClock) * speed) % cycle.length
	end
	return cycle:cycleTime(workspace:GetServerTimeNow())
end

local function hazeMoved(a: Color3, b: Color3): boolean
	local step = Config.DayNight.HazeStep
	return math.abs(a.R - b.R) >= step or math.abs(a.G - b.G) >= step or math.abs(a.B - b.B) >= step
end

local function apply(look: { [string]: any })
	Lighting.ClockTime = look.Clock
	Lighting.Brightness = look.Brightness
	Lighting.ExposureCompensation = look.Exposure
	Lighting.Ambient = look.Ambient
	Lighting.OutdoorAmbient = look.OutdoorAmbient
	Lighting.ColorShift_Top = look.SunColour

	atmosphere.Density = look.AtmosphereDensity
	atmosphere.Offset = look.AtmosphereOffset
	atmosphere.Color = look.AtmosphereColour
	atmosphere.Decay = look.AtmosphereDecay
	atmosphere.Glare = look.AtmosphereGlare
	atmosphere.Haze = look.AtmosphereHaze

	if clouds then
		clouds.Cover = look.CloudCover
		clouds.Density = look.CloudDensity
		clouds.Color = look.CloudColour
	end

	grade.TintColor = look.Tint
	grade.Contrast = look.Contrast
	grade.Saturation = look.Saturation
	bloom.Intensity = look.BloomIntensity
	bloom.Threshold = look.BloomThreshold
	rays.Intensity = look.SunRays

	local haze: Color3 = look.CliffHaze
	if not lastHaze or hazeMoved(lastHaze, haze) then
		lastHaze = haze
		stats.hazeMeshes = SplineMesh.setHaze(haze)
		stats.hazeWrites += 1
	end

	stats.applied += 1
	lastLook = look
end

local function step()
	local t0 = os.clock()
	apply(cycle:sample(now()))
	stats.worstMs = math.max(stats.worstMs, (os.clock() - t0) * 1000)
end

function SkyController:Init()
	cycle = DayNight.new()
	local fixed = Config.DayNight.Fixed

	atmosphere = adopt(Lighting, "Atmosphere")
	sky = adopt(Lighting, "Sky")
	sky.CelestialBodiesShown = true
	sky.StarCount = fixed.StarCount
	sky.SunAngularSize = fixed.SunAngularSize
	sky.MoonAngularSize = fixed.MoonAngularSize

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	clouds = if terrain then adopt(terrain, "Clouds") else nil

	grade = adopt(Lighting, "ColorCorrectionEffect", "DayNightGrade")
	bloom = adopt(Lighting, "BloomEffect", "DayNightBloom")
	bloom.Size = fixed.BloomSize
	rays = adopt(Lighting, "SunRaysEffect", "DayNightRays")
	rays.Spread = fixed.SunRaysSpread

	Lighting.GlobalShadows = fixed.GlobalShadows
	Lighting.EnvironmentDiffuseScale = fixed.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = fixed.EnvironmentSpecularScale
	Lighting.ShadowSoftness = fixed.ShadowSoftness
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
end

function SkyController:Start()
	step()
	local every = 1 / Config.DayNight.Rate
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since < every then
			return
		end
		since = 0
		step()
	end)
end

-- Whether the headlights should be on now: the same moment the sky is showing, so a held or
-- sped-up sky (Studio tests) switches them too.
function SkyController:LightsOn(): boolean
	return cycle:lightsAt(now())
end

-- The look now, the moment it was taken at, and what was set.
function SkyController:DebugState(): { [string]: any }
	local look = lastLook or {}
	return {
		t = look.T,
		phase = look.Phase,
		phaseF = look.PhaseF,
		from = look.From,
		to = look.To,
		blend = look.Blend,
		clock = Lighting.ClockTime,
		sunY = Lighting:GetSunDirection().Y,
		moonY = Lighting:GetMoonDirection().Y,
		brightness = Lighting.Brightness,
		haze = lastHaze and lastHaze:ToHex(),
		held = hold,
		speed = speed,
		length = cycle.length,
		applied = stats.applied,
		hazeWrites = stats.hazeWrites,
		hazeMeshes = stats.hazeMeshes,
		lights = cycle:lightsAt(now()),
		worstMs = stats.worstMs,
		clouds = clouds ~= nil,
	}
end

-- The look at `t` seconds into the cycle, without setting it; every value, colours as hex.
function SkyController:DebugLook(t: number): { [string]: any }
	local out = {}
	for k, v in cycle:sample(t) do
		out[k] = if typeof(v) == "Color3" then (v :: Color3):ToHex() else v
	end
	return out
end

-- Where each keyframe falls in the cycle.
function SkyController:DebugKeyTimes(): { { name: string, t: number } }
	return cycle:keyTimes()
end

-- Hold the sky at `t` seconds into the cycle (Studio tests and review shots).
function SkyController:DebugHold(t: number): { [string]: any }
	hold = t % cycle.length
	step()
	return self:DebugState()
end

-- Run the cycle `k` times as fast, from `t` (or from now).
function SkyController:DebugSpeed(k: number, t: number?): { [string]: any }
	anchorT = t or now()
	anchorClock = os.clock()
	hold = nil
	speed = k
	stats.worstMs = 0
	step()
	return self:DebugState()
end

-- Back on the server's clock.
function SkyController:DebugResume(): { [string]: any }
	hold = nil
	speed = 1
	step()
	return self:DebugState()
end

return SkyController
