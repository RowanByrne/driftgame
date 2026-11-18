--!strict
--!native
-- Incised faces from the seed 7 mountain study. Each side of a ridge drains into
-- its own branching channels. Their layout is cached for the life of this range.
local Relief = {}

type Arm = { sign: number, join: number, length: number, spread: number, width: number, strength: number }
type Basin = { center: number, slant: number, phase: number, width: number, weight: number, arms: { Arm } }
export type Cache = { [number]: Basin }

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function Relief.crest(y: number): number
	local high = math.max(0, y - 1130)
	return y + 0.36 * high * ease(high / 240)
end

local function basin(cache: Cache, seed: number, ridge: number, side: number, cell: number): Basin
	local key = (seed * 7919 + (ridge + 65536) * 104729 + (cell + 65536) * 19891 + (side + 1) * 4373) % 2147483647
	local cached = cache[key]
	if cached then
		return cached
	end
	local rng = Random.new(key)
	local b: Basin = {
		center = 2050 * (cell + rng:NextNumber(0.19, 0.81)),
		slant = rng:NextNumber(-0.13, 0.13),
		phase = rng:NextNumber(-math.pi, math.pi),
		width = rng:NextNumber(510, 860),
		weight = rng:NextNumber(0.80, 1.18),
		arms = {},
	}
	for sign = -1, 1, 2 do
		table.insert(b.arms, {
			sign = sign, join = rng:NextNumber(1850, 4250), length = rng:NextNumber(1300, 2800),
			spread = rng:NextNumber(0.36, 0.69), width = rng:NextNumber(0.43, 0.70), strength = rng:NextNumber(0.55, 0.85),
		})
	end
	cache[key] = b
	return b
end

local function channel(distance: number, width: number, depth: number): number
	local around = math.sqrt(distance * distance + 16 * 16) - 16
	return depth * math.exp(-1.36 * around / width)
end

function Relief.face(cache: Cache, seed: number, ridge: number, side: number, v: number, d: number,
	up: number, saddle: number, floor: number, crest: number): (number, number)
	local raised = up ^ 1.08
	local base = floor + (crest - floor) * raised
	local soften = ease((up - 0.020) / 0.22)
	if soften == 0 then
		return base, raised
	end
	local edgeDist = math.sqrt(d * d + 18 * 18) - 18
	local edge = 34 * (1 - 0.63 * saddle) * (1 - math.exp(-edgeDist / 74)) * math.exp(-d / 610) * soften
	local active = soften * ease(d / 530)
	if active == 0 then
		return base - edge, raised
	end
	local cell = math.floor(v / 2050)
	local drift = 180 * math.sin(d / 1700 + 0.54 * ridge + 0.17 * seed) + 105 * math.sin(d / 920 + 0.22 * ridge - 0.29 * seed)
	local down = ease(d / 3600)
	local erosion = 0
	for i = cell - 2, cell + 2 do
		local b = basin(cache, seed, ridge, side, i)
		local stem = b.center + b.slant * (d - 2200) + drift + 115 * math.sin(d / 1180 + b.phase)
		local width = b.width * (0.71 + 0.46 * down)
		local depth = 240 * b.weight + 94
		erosion = math.max(erosion, channel(v - stem, width, (0.72 + 0.28 * down) * depth))
		for _, arm in b.arms do
			local reach = arm.join - d
			if reach >= -135 and reach < arm.length then
				local weight = ease((arm.length - reach) / (0.31 * arm.length)) * ease((reach + 135) / 135)
				local branch = stem + arm.sign * math.max(0, reach) * arm.spread * (1 + 0.16 * math.sin(d / 520 + b.phase))
				erosion = math.max(erosion, channel(v - branch, width * arm.width, weight * arm.strength * depth))
			end
		end
	end
	return base - edge + active * (94 - erosion), raised
end

return Relief
