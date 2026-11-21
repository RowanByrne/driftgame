--!strict
--!native
-- Road/GroundLook: the drawn ground's look from its steepness and its height (T-338,
-- docs/game/features/ground-look.md). Pure maths, no instances: what colour a point of ground
-- is, and how much of it is rock, from where it is, how high, and which way it faces.
-- `Drift/GroundMeshView` asks it for each vertex as a tile is drawn. Numbers in
-- `Config.GroundLook`.
--
-- Roblox has no custom shaders, so this is the "shader": worked out once a vertex, and
-- blended across each face by the vertex colours.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local GroundLook = {}

-- THE LOOK IN USE: the workspace attribute `__ground_look` (set by the `ground-look` command,
-- on this device only), else `Config.GroundLook.Look`. One that is not a look reads as "old".
function GroundLook.current(): string
	local L = Config.GroundLook
	local a = Workspace:GetAttribute("__ground_look")
	local look = if type(a) == "string" then a else L.Look
	return if table.find(L.Looks, look) then look else "old"
end

local function ease(a: number, b: number, v: number): number
	local t = math.clamp((v - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- (`math.noise` is the same on every device; each use has its own third coordinate, never a
-- whole number, since it is 0 on the lattice)
local function n2(x: number, z: number, studs: number, salt: number): number
	return math.clamp(math.noise(x / studs, z / studs, salt), -0.5, 0.5) * 2
end

export type Weights = {
	angle: number, -- degrees from flat
	rocky: number, -- 0 to 1: grass to rocky grass
	rock: number, -- 0 to 1: to rock
	alpine: number, -- 0 to 1: lush to alpine grass
	snow: number, -- 0 to 1: how much snow lies here (none on steep faces)
}

-- HOW STEEP AND HOW HIGH, as weights: `alt` studs above the mountain's zero, `ny` the up part
-- of the ground's unit normal, at world (x, z).
function GroundLook.weights(x: number, z: number, alt: number, ny: number): Weights
	local L = Config.GroundLook
	local angle = math.deg(math.acos(math.clamp(ny, -1, 1)))
	local ha = alt + n2(x, z, L.HeightJitterStuds, 11.37) * L.HeightJitter
	local alpine = ease(L.Alpine[1], L.Alpine[2], ha)
	local a = angle + n2(x, z, L.JitterStuds, 5.71) * L.Jitter + alpine * L.AlpineLower
	local snow = ease(L.Snow[1], L.Snow[2], ha) * (1 - ease(L.SnowSteep[1], L.SnowSteep[2], a))
	return {
		angle = angle,
		rocky = ease(L.Rocky[1], L.Rocky[2], a),
		rock = ease(L.Rock[1], L.Rock[2], a),
		alpine = alpine,
		snow = snow,
	}
end

local function mix(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function scale(c: Color3, k: number): Color3
	return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
end

-- THE COLOUR at world (x, y, z), `alt` studs above the mountain's zero, facing `ny` up:
-- grass (lush to alpine, blotched), through rocky grass to rock (two greys by height, faint
-- strata), with snow over what is not steep up high. And the weights it came from.
function GroundLook.colour(x: number, y: number, z: number, alt: number, ny: number): (Color3, Weights)
	local L = Config.GroundLook
	local w = GroundLook.weights(x, z, alt, ny)
	local blotch = math.clamp(0.5 + 1.6 * math.noise(x / L.BlotchStuds, z / L.BlotchStuds, 3.37), 0, 1)
	local lush = L.Lush[1]:Lerp(L.Lush[2], blotch)
	local alpine = L.AlpineGrass[1]:Lerp(L.AlpineGrass[2], blotch)
	local c = mix(lush, alpine, w.alpine)
	c = mix(c, L.RockyGrass, w.rocky)
	if w.rock > 0 then
		local high = ease(L.Alpine[1], L.Snow[2], alt)
		local strata = 1 + L.Strata * math.sin((y + n2(x, z, 60, 7.13) * L.StrataStuds * 2) / L.StrataStuds * math.pi)
		c = mix(c, scale(mix(L.RockLow, L.RockHigh, high), strata), w.rock)
	end
	if w.snow > 0 then
		c = mix(c, L.SnowColour, w.snow)
	end
	return c, w
end

-- THE SHEET'S SQUARE a face takes (T-340, the "sheet" look), from its corners' mean weights:
-- 1 grass, 2 rocky grass, 3 rock, 4 snow (`Config.GroundLook.Sheet.Order`). Snow over rock over
-- rocky grass, each from `Sheet.From` of it.
function GroundLook.sheetCell(snow: number, rock: number, rocky: number): number
	local from = Config.GroundLook.Sheet.From
	if snow >= from then
		return 4
	elseif rock >= from then
		return 3
	elseif rocky >= from then
		return 2
	end
	return 1
end

-- How much of a point is rock, 0 to 1, for the rock mesh ("rock"): its rock weight.
function GroundLook.rockWeight(x: number, z: number, alt: number, ny: number): number
	return GroundLook.weights(x, z, alt, ny).rock
end

-- The vertex colour a look draws `c` at, under a texture ("detail", "sheet"): a part with a
-- texture loses its material's own map, which darkened the ground to about
-- `Spline.Grass.Shade` (measured, T-187: drawn without it the ground came out twice as
-- bright; T-340 saw it washed out), so the colour is scaled by Shade over the texture's
-- average and the ground keeps the brightness the grass material gave it.
function GroundLook.forTexture(look: string, c: Color3): Color3
	local shade = Config.Spline.Grass.Shade
	if look == "detail" then
		return scale(c, shade / Config.GroundLook.Detail.Mean)
	end
	if look == "sheet" then
		return scale(c, shade / Config.GroundLook.Sheet.Mean)
	end
	return c
end

return GroundLook
