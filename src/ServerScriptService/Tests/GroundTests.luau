--!nonstrict
-- GroundTests: the ground-first mountain and the road pressed into it
-- (features/ground-trial.md, T-218). Pure maths:
--   game.ServerStorage.DebugBridge:Invoke("DebugGroundTests", "run")
-- Takes a while: from execute_luau, run it in a task.spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "GroundTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)

local Tests = {}

local SEEDS = { 31337, 101, 2024 }
local LENGTH = 5000 -- studs: the 2 km trial stretch and the 5 000 the streaming check drives

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

local function run(check, opts)
	local G = Config.Spline.Ground
	local half = Config.Road.Width * 0.5
	local length = (opts and opts.length) or LENGTH
	local reach = Ground.reach()

	-- the same mountain from the same seed, and a different one from another
	do
		local o = { x = 100, y = 20, z = -300, yaw = 0.3 }
		local a = Ground.field(7, o, 1.1)
		local b = Ground.field(7, o, 1.1)
		local c = Ground.field(8, o, 1.1)
		local same, differ = 0, 0
		for i = 1, 200 do
			local x, z = o.x + (i * 37.3) % 3000 - 1500, o.z + (i * 91.7) % 3000 - 1500
			if Ground.h(a, x, z) == Ground.h(b, x, z) then
				same += 1
			end
			if math.abs(Ground.h(a, x, z) - Ground.h(c, x, z)) > 0.5 then
				differ += 1
			end
		end
		check("h is a pure function of the seed and the place", same == 200, `{same} of 200`)
		check("another seed is another mountain", differ > 150, `{differ} of 200 differ`)
		check("the road's start sits on the plane", math.abs(Ground.h(a, o.x, o.z) - o.y) < 1e-6, fmt(Ground.h(a, o.x, o.z) - o.y, 6))
		-- the relief's range over 4 km by 4 km
		local lo, hi = math.huge, -math.huge
		for x = -2000, 2000, 25 do
			for z = -2000, 2000, 25 do
				local r = Ground.relief(a, o.x + x, o.z + z)
				lo, hi = math.min(lo, r), math.max(hi, r)
			end
		end
		check("relief: ridges and gullies of tens of studs", hi - lo > 40 and hi - lo < 260, `{fmt(lo)} to {fmt(hi)}`)
		-- the plane rises up the fall line
		local up = Ground.base(a, o.x + a.ux * 100, o.z + a.uz * 100) - Ground.base(a, o.x, o.z)
		check("the plane rises Slope up the fall line", math.abs(up - G.Slope * 100) < 1e-6, fmt(up, 3))
	end

	-- "current" lays exactly the road it always has
	do
		local a = SplineGen.new(SEEDS[1])
		a:extendTo(3000)
		local b = SplineGen.new(SEEDS[1], nil, nil, "current")
		b:extendTo(3000)
		local x1, z1 = a.spline:planAt(3000)
		local x2, z2 = b.spline:planAt(3000)
		check(
			"current: the same road as before",
			#a.sections == #b.sections and x1 == x2 and z1 == z2 and a.spline:heightAt(3000) == b.spline:heightAt(3000) and b.ground == nil,
			`{#a.sections} / {#b.sections} sections`
		)
	end

	local totals = {
		onPlaneWorst = 0,
		onPlaneSum = 0,
		onPlaneN = 0,
		cutWorst = 0,
		fillWorst = 0,
		abovePoints = 0,
		aboveN = 0,
		aboveWorst = -math.huge,
		edgeN = 0,
		edgeWorst = 0,
		farN = 0,
		farOff = 0,
		seamsN = 0,
		seams = 0,
		steepest = 0,
		betweenN = 0,
		betweenOff = 0,
		replayN = 0,
		replayDiffer = 0,
		ctxMs = 0,
		ctxN = 0,
		atUs = 0,
		atN = 0,
		nearUs = 0,
		nearN = 0,
		genWorst = 0,
		turnFits = 0,
		relaxed = 0,
		turnarounds = 0,
		stalled = 0,
	}

	for _, seed in SEEDS do
		local gen = SplineGen.new(seed, nil, nil, "mesh")
		gen:extendTo(length)
		local sp = gen.spline
		local field = gen.ground
		check(`seed {seed}: a ground run carries its mountain`, field ~= nil and sp.mountain == field)
		if not field then
			continue
		end
		totals.genWorst = math.max(totals.genWorst, gen.stats.worstMs)
		totals.turnFits += #gen.turnFits
		totals.relaxed += gen.stats.hillRelaxed
		totals.turnarounds += gen.stats.turnarounds
		if gen.stats.stalled then
			totals.stalled += 1
		end

		-- the road follows the mountain itself (T-226)
		for s = 0, sp.length, 20 do
			local x, z = sp:planAt(s)
			local y = sp:heightAt(s)
			local off = y - Ground.h(field, x, z)
			totals.onPlaneWorst = math.max(totals.onPlaneWorst, math.abs(off))
			totals.onPlaneSum += math.abs(off)
			totals.onPlaneN += 1
			local cut = Ground.h(field, x, z) - y
			totals.cutWorst = math.max(totals.cutWorst, cut)
			totals.fillWorst = math.max(totals.fillWorst, -cut)
		end

		-- a client's replay, with its own field from the start message's numbers
		local copy = SplineGen.replay(gen.sections, sp.origin, gen.fall)
		copy.mountain = Ground.field(seed, copy.origin, gen.fall)

		-- box by box along the road, as a chunk would be drawn
		local step = 400
		local tick = 0
		for s0 = 0, sp.length - step, step do
			local xa, za = sp:planAt(s0)
			local xb, zb = sp:planAt(s0 + step)
			local x0, x1 = math.min(xa, xb) - 150, math.max(xa, xb) + 150
			local z0, z1 = math.min(za, zb) - 150, math.max(za, zb) + 150
			local t0 = os.clock()
			local ctx = Ground.context(field, sp, x0, z0, x1, z1)
			totals.ctxMs += (os.clock() - t0) * 1000
			totals.ctxN += 1
			local cctx = Ground.context(copy.mountain, copy, x0, z0, x1, z1)

			-- no ground above the road's surface or its runoff, and the edge meets it
			for s = s0, s0 + step, 8 do
				for _, side in { -1, 1 } do
					local w = half + sp:runoffAt(s, side)
					for _, share in { 0, 0.3, 0.6, 0.9, 1 } do
						local d = side * w * share
						local px, py, pz = sp:terrainXYZ(s, d)
						local t1 = os.clock()
						local y, a = Ground.at(ctx, px, pz)
						totals.nearUs += (os.clock() - t1) * 1e6
						totals.nearN += 1
						-- never above the surface; `Under` below it, give or take a little
						local over = y - py
						totals.aboveN += 1
						totals.aboveWorst = math.max(totals.aboveWorst, over)
						if over > 0 then
							totals.abovePoints += 1
						end
						if share == 1 then
							totals.edgeN += 1
							totals.edgeWorst = math.max(totals.edgeWorst, math.abs(over + G.Under))
						end
						local _ = a
					end
				end
			end

			-- a grid over the box: seams, the far ground, the replay
			for x = x0, x1, 12 do
				for z = z0, z1, 12 do
					local t1 = os.clock()
					local y, a = Ground.at(ctx, x, z)
					totals.atUs += (os.clock() - t1) * 1e6
					totals.atN += 1
					-- far from every road: the mountain itself
					-- (no filed point of any road within reach and a station's look)
					if not sp:crowded(x, z, -1e9, reach + G.Look + 8, 0) then
						totals.farN += 1
						totals.farOff = math.max(totals.farOff, math.abs(y - Ground.h(field, x, z)))
					end
					-- between two legs: the ground the blends leave is h
					if a == 0 then
						totals.betweenN += 1
						totals.betweenOff = math.max(totals.betweenOff, math.abs(y - Ground.h(field, x, z)))
					end
					-- no jumps: nothing changes more than half a stud over a twentieth of one
					-- (a slope of 10, far past any cut); and the steepest slope, for the record
					local yx = Ground.at(ctx, x + 0.05, z)
					local yz = Ground.at(ctx, x, z + 0.05)
					local jump = math.max(math.abs(yx - y), math.abs(yz - y))
					totals.seamsN += 1
					totals.steepest = math.max(totals.steepest, jump / 0.05)
					if jump > 0.5 then
						totals.seams += 1
					end
					-- the client's copy agrees
					tick += 1
					if tick % 4 == 0 then
						local cy = Ground.at(cctx, x, z)
						totals.replayN += 1
						if math.abs(cy - y) > 1e-6 then
							totals.replayDiffer += 1
						end
					end
				end
			end
		end
	end

	check("the generator lays every seed without stalling", totals.stalled == 0, `{totals.stalled} stalled`)
	check(
		"the road follows the mountain (h at the centre line)",
		totals.onPlaneSum / math.max(totals.onPlaneN, 1) <= 6,
		`mean {fmt(totals.onPlaneSum / math.max(totals.onPlaneN, 1))}, worst {fmt(totals.onPlaneWorst)} studs off it`
	)
	-- how it sits on the slope (T-226): few trenches and causeways, rarely 20 studs off h
	do
		local p = Tests.profile(nil, { length = length })
		local n = math.max(p.stations, 1)
		check(
			"trenches and causeways are rare",
			(p.trench + p.causeway) / n < 0.1,
			`{p.trench} trench and {p.causeway} causeway stations of {p.stations}`
		)
		check(
			"cut or fill at the centre line over 20 studs is rare",
			p.over20 / n < 0.05,
			`{p.over20} of {p.stations}; median {fmt(p.cutMedian)}, p95 {fmt(p.cutP95)}, within 6: {fmt(100 * p.within6 / n)}%`
		)
		check(
			"the road stays drivable",
			p.gradeWorstDeg <= Config.Spline.MaxGrade + 1e-6 and p.gradeRateWorst <= Config.Spline.MaxGradeRate + 1e-6,
			`steepest {fmt(p.gradeWorstDeg, 2)} degrees, grade change {fmt(p.gradeRateWorst, 5)} a stud`
		)
	end
	check("cuts and fills at the centre line", true, `deepest cut {fmt(totals.cutWorst)}, deepest fill {fmt(totals.fillWorst)} studs`)
	check(
		"no ground above the road or its runoff",
		totals.abovePoints == 0,
		`{totals.abovePoints} of {totals.aboveN} above it; the highest is {fmt(-totals.aboveWorst, 3)} studs under it (Under {G.Under})`
	)
	check("the ground meets the runoff's outer edge", totals.edgeWorst < G.Under, `worst {fmt(totals.edgeWorst, 3)} studs off Under, over {totals.edgeN}`)
	check("far from the road the ground is h", totals.farOff < 1e-6, `{totals.farN} points, worst {fmt(totals.farOff, 6)}`)
	check("between the legs the ground is h", totals.betweenOff < 1e-6, `{totals.betweenN} points, worst {fmt(totals.betweenOff, 6)}`)
	check(
		"no seams: no jump anywhere on the grid",
		totals.seams == 0,
		`{totals.seams} of {totals.seamsN} jump half a stud; steepest slope {fmt(totals.steepest, 2)}`
	)
	check("a client's replay draws the same ground", totals.replayDiffer == 0, `{totals.replayDiffer} of {totals.replayN} differ`)
	check(
		"turn checks sample the ground",
		totals.turnFits > 0,
		`{totals.turnFits} sharp turns fitted, {totals.relaxed} relaxed, {totals.turnarounds} turnarounds; worst generator step {fmt(totals.genWorst)} ms`
	)
	check(
		"cost of the maths",
		true,
		`context {fmt(totals.ctxMs / math.max(totals.ctxN, 1), 2)} ms per 400-stud box; a point {fmt(totals.atUs / math.max(totals.atN, 1), 1)} us on average, {fmt(totals.nearUs / math.max(totals.nearN, 1), 1)} us on the road`
	)
end

-- ROAD ON THE SLOPE (features/road-on-the-slope.md, T-226): how the road sits on the
-- mountain, measured the same way before and after. Every `step` studs along each seed's
-- road: the cut (+) or fill (-) at the centre line, h less the road; and each side's
-- ground `out` studs past the runoff's edge against the edge's own height. A TRENCH
-- station has that ground over `edge` studs above the edge on both sides; a CAUSEWAY one
-- under it by as much on both. Also the steepest grade and grade change laid.
--   DebugBridge:Invoke("DebugGroundTests", "profile", { seeds = {...}, length = 5000 })
function Tests.profile(_, opts)
	opts = opts or {}
	local seeds = opts.seeds or SEEDS
	local length = opts.length or LENGTH
	local step = opts.step or 16
	local out = opts.out or 20
	local edge = opts.edge or 8
	local half = Config.Road.Width * 0.5
	local cuts: { number } = {}
	local res = {
		seeds = #seeds,
		stations = 0,
		trench = 0,
		causeway = 0,
		within6 = 0,
		over20 = 0,
		cutWorst = 0,
		fillWorst = 0,
		gradeWorst = 0,
		gradeRateWorst = 0,
		climbStuds = 0,
		genMs = 0,
		genWorstMs = 0,
		stalled = 0,
		turnarounds = 0,
		relaxed = 0,
		offGround = 0,
		offGroundLaid = 0,
		sections = 0,
		perSeed = {},
	}
	for _, seed in seeds do
		local t0 = os.clock()
		local gen = SplineGen.new(seed, nil, nil, "mesh")
		gen:extendTo(length)
		res.genMs += (os.clock() - t0) * 1000
		res.genWorstMs = math.max(res.genWorstMs, gen.stats.worstMs)
		res.turnarounds += gen.stats.turnarounds
		res.relaxed += gen.stats.hillRelaxed
		res.offGround += gen.stats.offGround or 0
		res.offGroundLaid += gen.stats.offGroundLaid or 0
		res.sections += #gen.sections
		if gen.stats.stalled then
			res.stalled += 1
		end
		local sp, field = gen.spline, gen.ground
		local mine = { seed = seed, trench = 0, causeway = 0, stations = 0, drop = sp:heightAt(math.min(length, sp.length)) - sp:heightAt(0) }
		local lastG = sp:gradeAt(0)
		for s = step, math.min(length, sp.length), step do
			local x, z = sp:planAt(s)
			local y = sp:heightAt(s)
			local cut = Ground.h(field, x, z) - y
			table.insert(cuts, math.abs(cut))
			res.cutWorst = math.max(res.cutWorst, cut)
			res.fillWorst = math.max(res.fillWorst, -cut)
			if math.abs(cut) <= 6 then
				res.within6 += 1
			end
			if math.abs(cut) > 20 then
				res.over20 += 1
			end
			local g = sp:gradeAt(s)
			res.gradeWorst = math.max(res.gradeWorst, math.abs(g))
			res.gradeRateWorst = math.max(res.gradeRateWorst, math.abs(g - lastG) / step)
			if g > 0 then
				res.climbStuds += step
			end
			lastG = g
			local yaw = sp:yawAt(s)
			local rx, rz = math.cos(yaw), -math.sin(yaw)
			local above = {}
			for _, side in { -1, 1 } do
				local w = half + sp:runoffAt(s, side)
				local d = side * (w + out)
				above[side] = Ground.h(field, x + rx * d, z + rz * d) - sp:terrainY(s, side * w)
			end
			if above[-1] > edge and above[1] > edge then
				res.trench += 1
				mine.trench += 1
			elseif above[-1] < -edge and above[1] < -edge then
				res.causeway += 1
				mine.causeway += 1
			end
			res.stations += 1
			mine.stations += 1
		end
		table.insert(res.perSeed, mine)
	end
	table.sort(cuts)
	local function pct(p: number): number
		return cuts[math.clamp(math.floor(#cuts * p + 0.5), 1, #cuts)] or 0
	end
	res.cutMedian = pct(0.5)
	res.cutP95 = pct(0.95)
	res.gradeWorstDeg = math.deg(math.atan(res.gradeWorst))
	return res
end

function Tests.run(_, opts)
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local ok, err = pcall(run, check, opts)
	if not ok then
		check("the ground tests ran", false, tostring(err))
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
