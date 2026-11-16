--!nonstrict
-- RangeTests: the mountain range a ground run crosses (features/mountain-range.md, T-233).
-- Pure maths:
--   require(game.ServerScriptService.Tests.RangeTests).run()
-- Takes about half a minute with the road's checks (`opts.road = false` skips them): from
-- execute_luau, run it in a task.spawn.

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

-- THE ROAD ON THE RANGE (T-242): the checks run on `ROAD_SEEDS`, each laid to `ROAD_LENGTH`.
-- DOUBLING BACK: the road falls back more than `BACK` studs along the way on (the range's t)
-- behind the furthest it has reached. A switchback is not one: its legs climb the face one
-- above the other, each further on than the one before, and a hairpin's loop reaches back
-- less than its width (2 x 80 studs). A TRENCH: the centre line more than `TRENCH` studs
-- below h, deeper than a hairpin is fitted into the face (`Spline.Ground.TurnMaxCut`, 45)
-- with room for a spur the road cuts through; the one the user drove down went 150 to 290
-- studs deep for a kilometre and more. Before T-242, on these seeds: 2.3% of the road over
-- `TRENCH` deep, a stretch of 1 300 studs, 290 at the deepest; after it, 0.6%, 510 and 140.
-- T-245 doubled the range, so a road twice as long crosses as many ridges as it did.
local ROAD_SEEDS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
local ROAD_LENGTH = 50000 -- studs (25 000 until T-245)
local BACK = 300 -- studs
local TRENCH = 60 -- studs below h
local TRENCH_SHARE = 0.01 -- of the road at most that deep...
local TRENCH_RUN = 600 -- ...no stretch longer than this, studs...
local TRENCH_WORST = 150 -- ...and never deeper than this, studs

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
		-- the band: a 180 000 by 80 000 stud box, every 500 studs (T-245 doubled the range)
		for t = -60000, 120000, 500 do
			for v = -40000, 40000, 500 do
				local x, z = Range.world(f.range, t, v)
				local y = Ground.h(f, x, z)
				lowest = math.min(lowest, y)
				highest = math.max(highest, y)
			end
		end
		-- ridges ahead of the start, along three lines across
		for _, v in { -12000, 0, 12000 } do
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
				-- a saddle is a dip: the crest is higher within `SaddleSpan` studs either way
				local hiL, hiR = -math.huge, -math.huge
				for dv = R.PassStep, R.SaddleSpan, R.PassStep do
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
		for t = -10000, 80000, 200 do
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
		lowest > KILL + 200 and highest < 3200,
		`{fmt(lowest)} to {fmt(highest)} studs on {seeds} seeds (kill {KILL})`
	)
	-- SPACING: `Spacing` either way `2 x Jitter` between two ridges' middles, and each ridge
	-- wanders `Wobble[1]` either way, so along one line across they can be up to `2 x Wobble`
	-- nearer or further. Until T-238 the range was 5 500 apart (the check said 3 000 to 8 000,
	-- bounded 2 000 to 9 000); T-238 made it wider for the road, 6 500 apart (mountain-range.md
	-- "step 2"), measured 3 166 to 9 898 on 20 seeds (T-244), so the bounds are the maths' own.
	-- T-245 doubled the range: 13 000 apart.
	local spMin = R.Spacing - 2 * R.Jitter - 2 * R.Wobble[1]
	local spMax = R.Spacing + 2 * R.Jitter + 2 * R.Wobble[1]
	check(
		"ridges lie about 8 000 to 18 000 studs apart",
		spacingLo >= spMin and spacingHi <= spMax and spacingLo <= R.Spacing and spacingHi >= R.Spacing,
		`{fmt(spacingLo, 0)} to {fmt(spacingHi, 0)} studs (the most the maths allows: {spMin} to {spMax})`
	)
	-- (twice T-238's 600 to 1 200 since T-245)
	check(
		"peaks rise 1 200 to 2 400 studs over the valley floors",
		riseHi >= 1200 and riseHi <= 2800 and riseLo >= 300,
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

	-- no seams: the range is continuous (a fiftieth of a stud never jumps a tenth: 79 degrees)
	do
		local f = field(3)
		local worst, n = 0, 0
		for t = -3000, 20000, 37 do
			for v = -3000, 3000, 211 do
				local x, z = Range.world(f.range, t, v)
				local y = Ground.h(f, x, z)
				local x2, z2 = Range.world(f.range, t + 0.02, v)
				local x3, z3 = Range.world(f.range, t, v + 0.02)
				worst = math.max(worst, math.abs(Ground.h(f, x2, z2) - y), math.abs(Ground.h(f, x3, z3) - y))
				n += 1
			end
		end
		check("no seams: a fiftieth of a stud never jumps a tenth", worst < 0.1, `steepest step {fmt(worst, 3)} studs over {n} points`)
	end

	-- runs get the shape `Config.Range.Shape` says (the range since T-238)
	do
		local f = Ground.field(7, ORIGIN, FALL)
		check("runs get the shape the config names", f.shape == R.Shape and (R.Shape ~= "range" or f.range ~= nil), `{f.shape}`)
	end

	-- THE ROAD ON THE RANGE (T-242): it climbs to the passes and crosses them, with no trench
	-- and without doubling back
	if not (opts and opts.road == false) then
		local res = Tests.road(nil, { seeds = ROAD_SEEDS, length = ROAD_LENGTH })
		local t = res.totals
		local n = math.max(t.n, 1)
		check("the road on the range never boxes itself in", t.stalls == 0, `{t.stalls} of {#ROAD_SEEDS} roads stalled`)
		check(
			"the road crosses the range's passes, climbing as much as it comes down",
			t.crossings >= #ROAD_SEEDS and math.abs(t.climb - t.fall) / n < 0.15,
			`{t.crossings} ridges crossed; climbing {fmt(100 * t.climb / n, 0)}%, descending {fmt(100 * t.fall / n, 0)}%`
		)
		check(
			"no doubling back: the road never falls back along the way on",
			t.backs == 0,
			`{t.backs} times more than {BACK} studs back (furthest {fmt(t.backWorst, 0)}) over {fmt(t.length, 0)} studs`
		)
		check(
			"no deep trench",
			t.deep / n <= TRENCH_SHARE and t.deepRun <= TRENCH_RUN and t.cutWorst <= TRENCH_WORST,
			`over {TRENCH} studs below h: {fmt(100 * t.deep / n, 2)}% of the road (at most {fmt(100 * TRENCH_SHARE, 0)}%), longest {fmt(t.deepRun, 0)} studs (at most {TRENCH_RUN}); deepest {fmt(t.cutWorst, 0)} (at most {TRENCH_WORST})`
		)
		check("the road's report", true, res.lines[#res.lines])
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

-- THE ROAD ON THE RANGE (T-238): each seed's road laid to `length` studs, and how it went:
-- stalls, height, how much of it climbs, how far its centre line is from h, the ridges it
-- crossed and at what height against the crest there. Returns the lines and the totals.
function Tests.road(_, opts)
	local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
	local seeds = (opts and opts.seeds) or { 1, 2, 3, 4, 5, 6, 7, 8 }
	local length = (opts and opts.length) or 25000
	local lines = {}
	local tot = {
		n = 0,
		over = 0,
		climb = 0,
		fall = 0,
		stalls = 0,
		crossings = 0,
		length = 0,
		lowest = math.huge,
		crossOff = 0,
		worstMs = 0,
		-- (T-242) the deepest cut, the road deeper than `TRENCH`, its longest stretch, and the
		-- times it fell back more than `BACK` along the way on (and the furthest)
		cutWorst = 0,
		deep = 0,
		deepRun = 0,
		backs = 0,
		backWorst = 0,
		follows = 0,
	}
	for _, seed in seeds do
		local gen = SplineGen.new(seed, { x = 0, y = 0, z = 0, yaw = 0 }, nil, "mesh")
		local t0 = os.clock()
		gen:extendTo(length)
		local ms = (os.clock() - t0) * 1000
		local sp, f = gen.spline, gen.ground
		local lo, hi, climb, n, over = math.huge, -math.huge, 0, 0, 0
		local offs = {}
		local lastK, crossings, cross = nil, 0, {}
		local cutWorst, deep, run, runFrom, backs, tMax, falling = 0, 0, 0, nil, {}, -math.huge, false
		for s = 0, sp.length, 16 do
			local x, z = sp:planAt(s)
			local y = sp:heightAt(s)
			lo, hi = math.min(lo, y), math.max(hi, y)
			local g = sp:gradeAt(s)
			if g > 0.005 then
				climb += 1
			elseif g < -0.005 then
				tot.fall += 1
			end
			n += 1
			local cut = Ground.h(f, x, z) - y
			local off = math.abs(cut)
			table.insert(offs, off)
			if off > 20 then
				over += 1
			end
			cutWorst = math.max(cutWorst, cut)
			if cut > TRENCH then
				deep += 1
				runFrom = runFrom or s
				run = math.max(run, s - runFrom)
			else
				runFrom = nil
			end
			if f.range then
				-- falling back along the way on
				local t = Range.frame(f.range, x, z)
				if t > tMax then
					tMax, falling = t, false
				elseif tMax - t > BACK then
					if not falling then
						table.insert(backs, { s, 0 })
						falling = true
					end
					backs[#backs][2] = math.max(backs[#backs][2], tMax - t)
				end
				local k = Range.ridgeAhead(f.range, x, z)
				if lastK and k > lastK then
					crossings += 1
					local _, v = Range.frame(f.range, x, z)
					local c = Range.crest(f.range, lastK, v)
					tot.crossOff = math.max(tot.crossOff, math.abs(y - c))
					table.insert(cross, `{fmt(s / 1000, 1)}k y{fmt(y, 0)}/crest {fmt(c, 0)}`)
				end
				lastK = k
			end
		end
		table.sort(offs)
		local st = gen.stats
		tot.n += n
		tot.over += over
		tot.climb += climb
		tot.length += sp.length
		tot.crossings += crossings
		tot.lowest = math.min(tot.lowest, lo)
		tot.worstMs = math.max(tot.worstMs, st.worstMs)
		if st.stalled then
			tot.stalls += 1
		end
		tot.cutWorst = math.max(tot.cutWorst, cutWorst)
		tot.deep += deep
		tot.deepRun = math.max(tot.deepRun, run)
		tot.backs += #backs
		tot.follows += st.follows or 0
		local backText = {}
		for _, b in backs do
			tot.backWorst = math.max(tot.backWorst, b[2])
			table.insert(backText, `{fmt(b[1] / 1000, 1)}k ({fmt(b[2], 0)})`)
		end
		table.insert(
			lines,
			`seed {seed}: {fmt(sp.length, 0)} studs{if st.stalled then " STALLED" else ""} in {fmt(ms, 0)} ms (worst step {fmt(st.worstMs)}) | y {fmt(lo, 0)} to {fmt(hi, 0)}, climbing {fmt(100 * climb / n, 0)}% | off h: median {fmt(offs[n // 2 + 1] or 0)}, p95 {fmt(offs[math.floor(n * 0.95) + 1] or 0)}, over 20 {fmt(100 * over / n)}% | deepest cut {fmt(cutWorst, 0)}, over {TRENCH} {fmt(100 * deep / n, 1)}% (longest {fmt(run, 0)}) | fell back {#backs}{if #backs > 0 then ": " .. table.concat(backText, ", ") else ""} | hairpins {st.turnarounds}, refused {st.turnsRefused}, escapes {st.escapes}, follows {st.follows or 0} | crossed {crossings}: {table.concat(cross, ", ")}`
		)
		task.wait()
	end
	table.insert(
		lines,
		`ALL: {fmt(tot.length, 0)} studs, {tot.stalls} stalled, climbing {fmt(100 * tot.climb / math.max(tot.n, 1), 0)}% and descending {fmt(100 * tot.fall / math.max(tot.n, 1), 0)}%, over 20 off h {fmt(100 * tot.over / math.max(tot.n, 1))}%, deepest cut {fmt(tot.cutWorst, 0)}, over {TRENCH} deep {fmt(100 * tot.deep / math.max(tot.n, 1), 2)}% (longest {fmt(tot.deepRun, 0)}), fell back {tot.backs} times (furthest {fmt(tot.backWorst, 0)}), lowest {fmt(tot.lowest, 0)}, {tot.crossings} ridges crossed (worst {fmt(tot.crossOff, 0)} studs from the crest), worst step {fmt(tot.worstMs)} ms`
	)
	return { lines = lines, totals = tot, text = table.concat(lines, "\n") }
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
