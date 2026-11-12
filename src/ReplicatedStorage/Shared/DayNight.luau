--!strict
-- DayNight: the day-night cycle, as maths (docs/game/features/day-night.md, T-144).
--
-- PURE: a time in, a look out. Nothing here touches the game; `Controllers/SkyController`
-- puts the look on the client's Lighting. Every client works the time out from the server's
-- clock by itself, so two clients at the same server time get the same look and nothing is
-- sent.
--
--   local cycle = DayNight.new()                 -- from Config.DayNight
--   local look = cycle:at(workspace:GetServerTimeNow())
--   look.Clock, look.Brightness, look.AtmosphereColour, ... look.Phase, look.PhaseF
--
-- THE CLOCK runs through the keyframes' `Clock` values on a monotone cubic (Fritsch-
-- Butland tangents), so the sun slows into the sunset and speeds out of it without its
-- speed ever jumping, and never runs backwards. EVERY OTHER VALUE blends between the two
-- keyframes either side with a smoothstep: numbers and colours alike.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DayNight = {}
DayNight.__index = DayNight

DayNight.PHASES = { "day", "sunset", "night", "sunrise" }

-- the keyframe's own keys, which are not values to blend
local META = { Name = true, Phase = true, f = true, Clock = true }

export type Key = {
	name: string,
	t: number, -- s into the cycle
	clock: number, -- unwrapped: never less than the keyframe before it
	tangent: number, -- clock hours per second, at this keyframe
	values: { [string]: any },
}

export type Cycle = typeof(setmetatable(
	{} :: {
		length: number,
		starts: { [string]: number },
		lengths: { [string]: number },
		keys: { Key },
		fields: { string },
		offset: number,
	},
	DayNight
))

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

local function blend(a: any, b: any, s: number): any
	if typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b :: Color3, s)
	elseif type(a) == "number" then
		return a + (b - a) * s
	end
	return if s < 0.5 then a else b
end

-- Build a cycle from a config shaped like `Config.DayNight`. A bad config is an error here,
-- at load, not a wrong sky later.
function DayNight.new(cfg: any?): Cycle
	local c: any = cfg or Config.DayNight
	local starts, lengths = {}, {}
	local length = 0
	for _, phase in DayNight.PHASES do
		local len = c[if phase == "day" then "Day" elseif phase == "sunset" then "Sunset" elseif phase == "night" then "Night" else "Sunrise"]
		assert(type(len) == "number" and len > 0, `DayNight: the {phase} needs a length above 0`)
		starts[phase] = length
		lengths[phase] = len
		length += len
	end

	local first = c.Keyframes[1]
	assert(first, "DayNight: no keyframes")
	local fields = {}
	for key in first do
		if not META[key] then
			table.insert(fields, key)
		end
	end
	table.sort(fields)

	local keys: { Key } = {}
	for i, kf in c.Keyframes do
		local name = kf.Name or `#{i}`
		assert(starts[kf.Phase] ~= nil, `DayNight: keyframe '{name}' has no phase called '{kf.Phase}'`)
		assert(type(kf.f) == "number" and kf.f >= 0 and kf.f <= 1, `DayNight: keyframe '{name}' needs an f from 0 to 1`)
		assert(type(kf.Clock) == "number" and kf.Clock >= 0 and kf.Clock < 24, `DayNight: keyframe '{name}' needs a Clock from 0 to 24`)
		local values = {}
		for _, field in fields do
			local v = kf[field]
			assert(v ~= nil, `DayNight: keyframe '{name}' has no {field}`)
			assert(typeof(v) == typeof(first[field]), `DayNight: keyframe '{name}': {field} is a {typeof(v)}, not a {typeof(first[field])}`)
			values[field] = v
		end
		for key in kf do
			assert(META[key] or first[key] ~= nil, `DayNight: keyframe '{name}' has {key}, which the first keyframe does not`)
		end
		local t = (starts[kf.Phase] + kf.f * lengths[kf.Phase]) % length
		table.insert(keys, { name = name, t = t, clock = kf.Clock, tangent = 0, values = values })
	end
	table.sort(keys, function(a, b)
		return a.t < b.t
	end)
	for i = 2, #keys do
		assert(keys[i].t > keys[i - 1].t, `DayNight: keyframes '{keys[i - 1].name}' and '{keys[i].name}' fall at the same moment`)
	end

	-- unwrap the clock so it only ever goes forward, through midnight and on
	for i = 2, #keys do
		while keys[i].clock <= keys[i - 1].clock do
			keys[i].clock += 24
		end
	end
	local n = #keys
	-- one whole cycle must be one whole day of clock, or the sky would jump at the wrap
	local span = keys[1].clock + 24 - keys[n].clock
	assert(span > 0 and span < 24, "DayNight: the clocks must go round the day exactly once")

	-- Fritsch-Butland tangents, round the loop
	local function nextOf(i: number): (number, number) -- dt, dclock to the next key
		if i < n then
			return keys[i + 1].t - keys[i].t, keys[i + 1].clock - keys[i].clock
		end
		return keys[1].t + length - keys[n].t, keys[1].clock + 24 - keys[n].clock
	end
	for i = 1, n do
		local h1, c1 = nextOf(i)
		local h0, c0 = nextOf(if i == 1 then n else i - 1)
		local d0, d1 = c0 / h0, c1 / h1
		keys[i].tangent = 3 * (h0 + h1) / ((2 * h1 + h0) / d0 + (h1 + 2 * h0) / d1)
	end

	return setmetatable({
		length = length,
		starts = starts,
		lengths = lengths,
		keys = keys,
		fields = fields,
		offset = c.Offset or 0,
	}, DayNight)
end

-- Seconds into the cycle at this server time.
function DayNight.cycleTime(self: Cycle, serverTime: number): number
	return (serverTime + self.offset) % self.length
end

-- The phase at `t` seconds into the cycle, and how far through it (0..1).
function DayNight.phaseAt(self: Cycle, t: number): (string, number)
	t %= self.length
	for _, phase in DayNight.PHASES do
		local s = self.starts[phase]
		if t < s + self.lengths[phase] then
			return phase, (t - s) / self.lengths[phase]
		end
	end
	return "day", 0 -- not reached: t < length
end

-- The seconds into the cycle that a phase starts, and its length.
function DayNight.phaseSpan(self: Cycle, phase: string): (number, number)
	return self.starts[phase], self.lengths[phase]
end

-- The look at `t` seconds into the cycle.
function DayNight.sample(self: Cycle, t: number): { [string]: any }
	t %= self.length
	local keys, n = self.keys, #self.keys
	-- the key at or before t, round the loop
	local i = n
	for k = 1, n do
		if keys[k].t <= t then
			i = k
		else
			break
		end
	end
	local a = keys[i]
	local b = keys[if i == n then 1 else i + 1]
	local h = b.t - a.t
	local dt = t - a.t
	if h <= 0 then
		h += self.length
	end
	if dt < 0 then
		dt += self.length
	end
	local cb = if i == n then b.clock + 24 else b.clock
	local s = dt / h

	local look: { [string]: any } = {}
	local e = smooth(s)
	for _, field in self.fields do
		look[field] = blend(a.values[field], b.values[field], e)
	end

	-- cubic Hermite for the clock
	local s2, s3 = s * s, s * s * s
	local clock = (2 * s3 - 3 * s2 + 1) * a.clock
		+ (s3 - 2 * s2 + s) * h * a.tangent
		+ (-2 * s3 + 3 * s2) * cb
		+ (s3 - s2) * h * b.tangent
	look.Clock = clock % 24

	local phase, pf = self:phaseAt(t)
	look.Phase = phase
	look.PhaseF = pf
	look.From = a.name
	look.To = b.name
	look.Blend = s
	look.T = t
	return look
end

-- The look at this server time.
function DayNight.at(self: Cycle, serverTime: number): { [string]: any }
	return self:sample(self:cycleTime(serverTime))
end

-- Where each keyframe falls, in seconds into the cycle, in order: { name, t }.
function DayNight.keyTimes(self: Cycle): { { name: string, t: number } }
	local list = {}
	for _, k in self.keys do
		table.insert(list, { name = k.name, t = k.t })
	end
	return list
end

return DayNight
