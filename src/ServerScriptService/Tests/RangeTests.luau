--!nonstrict
-- RangeTests: the mountain range a ground run crosses (features/mountain-range.md, T-233).
-- Pure maths:
--   require(game.ServerScriptService.Tests.RangeTests).run()
-- Takes a few seconds: from execute_luau, run it in a task.spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "RangeTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)
local Range = require(ReplicatedStorage.Shared.Road.Range)

local Tests = {}

local ORIGIN = { x = 0, y = 0, z = 0, yaw = 0 }
local FALL = math.rad(90) -- a start heading turned a quarter, as `SplineGen` does
local KILL = -500 -- Roblox's fall-kill height

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

local function field(seed: number)
	return Ground.field(seed, ORIGIN, FALL, "range")
end

-- Every ridge from `k0` to `k1`, measured along v = `v`: where its crest is, its height,
-- the floors either side.
local function ridges(f, k0: number, k1: number, v: number)
	local out = {}
	for k = k0, k1 do
		local t = Range.ridgeT(f.range, k, v)
		local c = Range.crest(f.range, k, v)
		table.insert(out, { k = k, t = t, crest = c, before = Range.floor(f.range, k - 1, v), after = Range.floor(f.range, k, v) })
	end
	return out
end

local function run(check, opts)
	local R = Config.Range
	local seeds = (opts and opts.seeds) or 20

	-- a pure function of the seed and the place
	do
		local a, b, c = field(7), field(7), field(8)
		local same, differ = 0, 0
		for i = 1, 300 do
			local x, z = (i * 137.3) % 30000 - 15000, (i * 291.7) % 30000 - 15000
			if Ground.h(a, x, z) == Ground.h(b, x, z) then
				same += 1
			end
			if math.abs(Ground.h(a, x, z) - Ground.h(c, x, z)) > 1 then
				differ += 1
			end
		end
		check("the range is a pure function of the seed and the place", same == 300, `{same} of 300`)
		check("another seed is another range", differ > 250, `{differ} of 300 differ`)
		check("the road's start sits on the range", math.abs(Ground.h(a, 0, 0)) < 1e-6, fmt(Ground.h(a, 0, 0), 6))
		local w = Ground.where(a, 0, 0)
		check("the run starts low, in a valley", w.kind == "valley" and w.height < 0.25, `{w.kind}, height {fmt(w.height, 2)}`)
	end

	-- the band, ridges, peaks and saddles, on `seeds` seeds
	local lowest, highest = math.huge, -math.huge
	local spacingLo, spacingHi = math.huge, 0
	local riseLo, riseHi = math.huge, 0
	local noSaddle, saddleShallow, saddles = 0, 0, 0
	local passBad = 0
	local kinds = { pass = 0, ridge = 0, valley = 0, face = 0 }
	local steepN, shallowN, slopeN = 0, 0, 0
	for seed = 1, seeds do
		local f = field(seed)
		-- the band: a 90 000 by 40 000 stud box, every 250 studs
		for t = -30000, 60000, 250 do
			for v = -20000, 20000, 250 do
				local x, z = Range.world(f.range, t, v)
				local y = Ground.h(f, x, z)
				lowest = math.min(lowest, y)
				highest = math.max(highest, y)
			end
		end
		-- ridges ahead of the start, along three lines across
		for _, v in { -6000, 0, 6000 } do
			local list = ridges(f, 0, 10, v)
			for i = 2, #list do
				local gap = list[i].t - list[i - 1].t
				spacingLo, spacingHi = math.min(spacingLo, gap), math.max(spacingHi, gap)
			end
		end
		-- each ridge's peaks over its floors, and its saddles within the pass window
		for k = 0, 10 do
			local peak = -math.huge
			for v = -R.PassWindow, R.PassWindow, R.PassStep do
				local c = Range.crest(f.range, k, v)
				local fl = math.min(Range.floor(f.range, k - 1, v), Range.floor(f.range, k, v))
				peak = math.max(peak, c)
				riseLo = math.min(riseLo, c - fl)
				riseHi = math.max(riseHi, c - fl)
			end
			local list = Range.saddles(f.range, k, -R.PassWindow, R.PassWindow)
			if #list == 0 then
				noSaddle += 1
			end
			for _, sd in list do
				saddles += 1
				-- a saddle is a dip: the crest is higher within 2 000 studs either way
				local hiL, hiR = -math.huge, -math.huge
				for dv = R.PassStep, 2000, R.PassStep do
					hiL = math.max(hiL, (Range.crest(f.range, k, sd[1] - dv)))
					hiR = math.max(hiR, (Range.crest(f.range, k, sd[1] + dv)))
				end
				if math.min(hiL, hiR) - sd[2] < 1 then
					saddleShallow += 1
				end
			end
		end
		-- the pass ahead of the start: on ridge 0, ahead, at a saddle or the window's lowest
		do
			local px, pz, py, k = Ground.passAhead(f, 0, 0)
			local t, v = Range.frame(f.range, px, pz)
			local w = Ground.where(f, px, pz)
			if k ~= 0 or t <= 0 or math.abs(v) > R.PassWindow or math.abs(Ground.base(f, px, pz) - py) > 1 or w.crest > 1 then
				passBad += 1
			end
		end
		-- where you are, and how steep, along a line across the range
		for t = -5000, 40000, 100 do
			local x, z = Range.world(f.range, t, (seed * 997) % 8000 - 4000)
			local w = Ground.where(f, x, z)
			kinds[w.kind] += 1
			slopeN += 1
			if w.slope >= 30 then
				steepN += 1
			elseif w.slope < 8 then
				shallowN += 1
			end
		end
		task.wait()
	end
	check(
		"the range stays in its band, well above the fall-kill height",
		lowest > KILL + 200 and highest < 1600,
		`{fmt(lowest)} to {fmt(highest)} studs on {seeds} seeds (kill {KILL})`
	)
	check(
		"ridges lie about 3 000 to 8 000 studs apart",
		spacingLo >= 2000 and spacingHi <= 9000,
		`{fmt(spacingLo, 0)} to {fmt(spacingHi, 0)} studs`
	)
	check(
		"peaks rise 600 to 1 200 studs over the valley floors",
		riseHi >= 600 and riseHi <= 1400 and riseLo >= 150,
		`crest over floor {fmt(riseLo, 0)} to {fmt(riseHi, 0)} studs`
	)
	check(
		"every ridge has a saddle in reach of the road",
		noSaddle == 0 and saddleShallow == 0,
		`{saddles} saddles; {noSaddle} ridges with none within {R.PassWindow} studs; {saddleShallow} not a dip`
	)
	check("the pass ahead of the start is on the first ridge, at its crest", passBad == 0, `{passBad} of {seeds} not`)
	check(
		"where you are: passes, ridges, valleys and faces all show",
		kinds.pass > 0 and kinds.ridge > 0 and kinds.valley > 0 and kinds.face > 0,
		`pass {kinds.pass}, ridge {kinds.ridge}, valley {kinds.valley}, face {kinds.face}`
	)
	check(
		"steep and shallow ground both",
		steepN > 0 and shallowN > 0,
		`over 30 degrees {fmt(100 * steepN / slopeN)}%, under 8 {fmt(100 * shallowN / slopeN)}% of {slopeN} points`
	)

	-- no seams: the range is continuous (a fifth of a stud never jumps half a stud)
	do
		local f = field(3)
		local worst, n = 0, 0
		for t = -3000, 20000, 37 do
			for v = -3000, 3000, 211 do
				local x, z = Range.world(f.range, t, v)
				local y = Ground.h(f, x, z)
				local x2, z2 = Range.world(f.range, t + 0.2, v)
				local x3, z3 = Range.world(f.range, t, v + 0.2)
				worst = math.max(worst, math.abs(Ground.h(f, x2, z2) - y), math.abs(Ground.h(f, x3, z3) - y))
				n += 1
			end
		end
		check("no seams: a fifth of a stud never jumps", worst < 0.5, `steepest step {fmt(worst, 3)} studs over {n} points`)
	end

	-- the belts are still the default, unchanged
	do
		local f = Ground.field(7, ORIGIN, FALL)
		check("runs keep the belts until the road can climb (step 2)", f.shape == R.Shape and (R.Shape ~= "range" or f.range ~= nil), `{f.shape}`)
	end

	-- cost
	do
		local f = field(5)
		local t0 = os.clock()
		local n = 0
		for i = 1, 4000 do
			Ground.h(f, (i * 7.3) % 9000, (i * 3.1) % 9000)
			n += 1
		end
		local us = (os.clock() - t0) * 1e6 / n
		check("h costs little", us < 10, `{fmt(us, 2)} microseconds a point`)
	end
end

function Tests.run(_, opts)
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local ok, err = pcall(run, check, opts)
	if not ok then
		check("the range tests ran", false, tostring(err))
	end
	local passed = true
	for _, c in checks do
		if not c.ok then
			passed = false
		end
	end
	return { passed = passed, checks = checks }
end

return Tests
