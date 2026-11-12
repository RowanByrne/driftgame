--!nonstrict
-- DayNightTests: the day-night cycle's maths (features/day-night.md "Testing", T-144).
-- Pure: nothing in the place is touched. Run it in Studio:
--   game.ServerStorage.DebugBridge:Invoke("DebugDayNightTests", "run")
--
-- What it cannot check: whether the sky LOOKS right. That is the user's, in the lane.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "DayNightTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local DayNight = require(ReplicatedStorage.Shared.DayNight)

local Tests = {}

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 3) .. "f", x)
end

local function same(a: any, b: any, eps: number): boolean
	if typeof(a) == "Color3" then
		return math.abs(a.R - b.R) <= eps and math.abs(a.G - b.G) <= eps and math.abs(a.B - b.B) <= eps
	elseif type(a) == "number" then
		return math.abs(a - b) <= eps
	end
	return a == b
end

-- clock hours from a to b, forward round the day
local function forward(a: number, b: number): number
	return (b - a) % 24
end

local function copyConfig(): any
	local c = table.clone(Config.DayNight)
	c.Keyframes = {}
	for i, kf in Config.DayNight.Keyframes do
		c.Keyframes[i] = table.clone(kf)
	end
	return c
end

function Tests.run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local C = Config.DayNight
	local cycle = DayNight.new()

	-- 1. The cycle's length and its phases, at each boundary.
	local L = C.Day + C.Sunset + C.Night + C.Sunrise
	check("a whole cycle is day + sunset + night + sunrise", cycle.length == L, `{cycle.length} s`)
	local d, s, n = C.Day, C.Sunset, C.Night
	local boundaries = {
		{ 0, "day", 0 },
		{ d - 1e-3, "day", 1 },
		{ d, "sunset", 0 },
		{ d + s * 0.5, "sunset", 0.5 },
		{ d + s, "night", 0 },
		{ d + s + n - 1e-3, "night", 1 },
		{ d + s + n, "sunrise", 0 },
		{ L - 1e-3, "sunrise", 1 },
		{ L, "day", 0 },
		{ -1e-3, "sunrise", 1 },
	}
	local bad = {}
	for _, b in boundaries do
		local phase, f = cycle:phaseAt(b[1])
		if phase ~= b[2] or math.abs(f - b[3]) > 1e-3 then
			table.insert(bad, `{fmt(b[1])}s -> {phase} {fmt(f)}, wanted {b[2]} {b[3]}`)
		end
	end
	check("each boundary falls in the right phase", #bad == 0, if #bad > 0 then table.concat(bad, "; ") else `{#boundaries} boundaries`)

	-- 2. Each keyframe, at its own moment, is exactly itself.
	bad = {}
	local byName = {}
	for _, kf in C.Keyframes do
		byName[kf.Name] = kf
	end
	for _, k in cycle:keyTimes() do
		local look = cycle:sample(k.t)
		local kf = byName[k.name]
		for field, v in kf do
			if field == "Name" or field == "Phase" or field == "f" then
				continue
			end
			if not same(look[field], v, 1e-4) then
				table.insert(bad, `{k.name}.{field}`)
			end
		end
	end
	check("every keyframe is exactly its own look at its own moment", #bad == 0, if #bad > 0 then table.concat(bad, ", ") else `{#C.Keyframes} keyframes`)

	-- 3. The clock goes forward all the way round, smoothly, and once round the day.
	local stepT = 0.05
	local total, slowest, fastest, worstJerk = 0, math.huge, 0, 0
	local prevClock = cycle:sample(0).Clock
	local prevSpeed = nil
	for i = 1, math.floor(L / stepT) do
		local c = cycle:sample(i * stepT).Clock
		local dc = forward(prevClock, c)
		local sp = dc / stepT
		total += dc
		slowest = math.min(slowest, sp)
		fastest = math.max(fastest, sp)
		if prevSpeed then
			worstJerk = math.max(worstJerk, math.abs(sp - prevSpeed))
		end
		prevSpeed = sp
		prevClock = c
	end
	check("the clock never stops or runs backwards", slowest > 0, `slowest {fmt(slowest, 4)} h/s`)
	check("the clock goes once round the day per cycle", math.abs(total - 24) < 0.01, `{fmt(total, 4)} h`)
	check("the sun's speed never jumps", worstJerk < 0.002, `worst change {fmt(worstJerk, 5)} h/s per {stepT} s, fastest {fmt(fastest, 4)} h/s`)

	-- 4. The sunset and sunrise are spent with the sun low: the clock moves slower through
	--    them than across the day, and stays near the horizon (6:00 and 18:00).
	local function clockAt(t)
		return cycle:sample(t).Clock
	end
	local daySpeed = forward(clockAt(0), clockAt(d)) / d
	local setSpeed = forward(clockAt(d), clockAt(d + s)) / s
	local riseSpeed = forward(clockAt(d + s + n), clockAt(L - 1e-6)) / C.Sunrise
	check("the sun moves slower through the sunset than across the day", setSpeed < daySpeed * 0.6, `sunset {fmt(setSpeed, 4)} h/s, day {fmt(daySpeed, 4)} h/s`)
	check("and through the sunrise", riseSpeed < daySpeed * 0.6, `sunrise {fmt(riseSpeed, 4)} h/s`)
	local worstSet, worstRise = 0, 0
	for i = 0, 40 do
		local f = i / 40
		worstSet = math.max(worstSet, math.abs(clockAt(d + f * s) - 18))
		worstRise = math.max(worstRise, math.abs(clockAt(d + s + n + f * C.Sunrise * 0.999) - 6))
	end
	check("the whole sunset is within half an hour of 18:00", worstSet <= 0.5, `{fmt(worstSet)} h at worst`)
	check("the whole sunrise is within half an hour of 6:00", worstRise <= 0.5, `{fmt(worstRise)} h at worst`)

	-- 5. Every value blends without a jump, through every keyframe and round the wrap.
	local worstField, worstDiff = "", 0
	local probe = { 0 }
	for _, k in cycle:keyTimes() do
		table.insert(probe, k.t)
	end
	for _, t in probe do
		local a = cycle:sample(t - 1e-3)
		local b = cycle:sample(t + 1e-3)
		for field, v in a do
			if typeof(v) == "Color3" then
				local diff = math.max(math.abs(v.R - b[field].R), math.abs(v.G - b[field].G), math.abs(v.B - b[field].B))
				if diff > worstDiff then
					worstField, worstDiff = field, diff
				end
			elseif type(v) == "number" and field ~= "T" and field ~= "PhaseF" and field ~= "Blend" then
				local diff = if field == "Clock" then math.abs(forward(v, b[field])) else math.abs(v - b[field])
				if diff > worstDiff then
					worstField, worstDiff = field, diff
				end
			end
		end
	end
	check("no value jumps at a keyframe or at the wrap", worstDiff < 0.01, `worst {worstField} {fmt(worstDiff, 5)} across 2 ms`)

	-- 6. Two clients at the same server time get the same look; a whole cycle later, too.
	local other = DayNight.new()
	bad = {}
	for _, serverTime in { 1731400000.25, 1731400123.5, 1731409999.9, 0, 12.5 } do
		local a = cycle:at(serverTime)
		local b = other:at(serverTime)
		local c = cycle:at(serverTime + L)
		for field, v in a do
			if not same(v, b[field], 0) or not same(v, c[field], 1e-6) then
				table.insert(bad, `{serverTime}: {field}`)
				break
			end
		end
	end
	check("the same server time gives every client the same look", #bad == 0, if #bad > 0 then table.concat(bad, "; ") else "5 times, 2 clients, and a cycle later")

	-- 7. A bad config is refused when the cycle is made.
	local missing = copyConfig()
	missing.Keyframes[2].Brightness = nil
	local okMissing = pcall(DayNight.new, missing)
	local clash = copyConfig()
	clash.Keyframes[2].Phase = clash.Keyframes[1].Phase
	clash.Keyframes[2].f = clash.Keyframes[1].f
	local okClash = pcall(DayNight.new, clash)
	check("a keyframe missing a value is refused", not okMissing)
	check("two keyframes at one moment are refused", not okClash)

	-- 8. A phase's length can change without retuning the keyframes.
	local longer = copyConfig()
	longer.Day = 240
	local lc = DayNight.new(longer)
	local phase, f = lc:phaseAt(240 + 10)
	check("a longer day moves the sunset with it", lc.length == L + 120 and phase == "sunset" and math.abs(f - 0.5) < 1e-6, `{lc.length} s, {phase} {fmt(f)}`)

	local passed = 0
	for _, c in checks do
		if c.ok then
			passed += 1
		end
	end
	return { passed = passed == #checks, count = `{passed} of {#checks}`, checks = checks }
end

return Tests
