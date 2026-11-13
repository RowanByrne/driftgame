--!nonstrict
-- SplineTests: the spline road's curve and its generator (features/spline-road.md
-- "Testing", T-132). Pure maths, no instances: run it from the server debug bridge, or
-- straight off the module.
--   game.ServerStorage.DebugBridge:Invoke("DebugSplineTests", "run")
--   require(game.ServerScriptService.Tests.SplineTests).run({ "limits", "crossing" })
--
-- `run(parts?)` runs the named parts, or all of them. The whole suite takes several
-- seconds, so a caller that must not block (execute_luau) runs it in a task.spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "SplineTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)

local Tests = {}

local SEEDS = { 101, 2024, 8080, 31337, 777 }
local LIMIT_LENGTH = 20000 -- studs of road per seed for the limits and crossing checks
local HEALTH_SEEDS = 20
local HEALTH_LENGTH = 30000

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 3) .. "f", x)
end

local function road(seed: number, length: number)
	local gen = SplineGen.new(seed)
	gen:extendTo(length)
	return gen
end

local parts = {}

-- how the height band's centre moves per stud, for the mode the config sets
local function gen0Drift(): number
	return SplineGen.new(1).drift
end

-- 1. Every limit, read off the knots themselves (exact) and sampled along the surface.
function parts.limits(check)
	local C = Config.Spline
	local W = Config.Road.Width
	local kMax = 1 / C.MinRadius
	local gMax = math.tan(math.rad(C.MaxGrade))
	local bMax = math.rad(C.MaxBank)
	local worst = { k = 0, kRate = 0, g = 0, gRate = 0, b = 0, bRate = 0, tilt = 0, yLo = 0, yHi = 0, stepErr = 0, yawRate = 0, minNy = 1 }
	local short = 0
	for _, seed in SEEDS do
		local gen = road(seed, LIMIT_LENGTH)
		local sp = gen.spline
		if sp.length < LIMIT_LENGTH then
			short += 1
		end
		for _, pair in { { sp.curv, "k", "kRate" }, { sp.grade, "g", "gRate" }, { sp.bank, "b", "bRate" } } do
			local t, vName, rName = pair[1], pair[2], pair[3]
			for i = 1, #t.s do
				worst[vName] = math.max(worst[vName], math.abs(t.v[i]))
				if i > 1 then
					-- an eased track (the bank) is steepest mid-ramp, at 1.5 times the average
					local rate = math.abs(t.v[i] - t.v[i - 1]) / (t.s[i] - t.s[i - 1]) * (if t.ease then 1.5 else 1)
					worst[rName] = math.max(worst[rName], rate)
				end
			end
		end
		local base = sp.origin.y
		local px, pz = sp:planAt(0)
		local pyaw = sp:yawAt(0)
		local s = 1
		while s <= sp.length do
			local x, z = sp:planAt(s)
			local yaw = sp:yawAt(s)
			-- one stud of road is one stud of plan: no jumps, no stalls
			local dist = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
			worst.stepErr = math.max(worst.stepErr, math.abs(dist - 1))
			worst.yawRate = math.max(worst.yawRate, math.abs(yaw - pyaw))
			px, pz, pyaw = x, z, yaw
			-- the band's centre moves with the road on a descent (T-166)
			local y = sp:heightAt(s) - (base + gen:bandAt(s))
			worst.yLo = math.min(worst.yLo, y)
			worst.yHi = math.max(worst.yHi, y)
			if s % 5 == 0 then
				for _, d in { -W / 2, 0, W / 2 } do
					local n = sp:normalAt(s, d)
					worst.minNy = math.min(worst.minNy, n.Y)
				end
			end
			s += 1
		end
	end
	local tiltDeg = math.deg(math.acos(worst.minNy))
	local R = Config.Road
	check(
		"the spline's limits sit inside the piece road's lids",
		C.MaxGrade <= R.MaxGrade and C.MaxBank <= R.MaxBank and C.MaxBankRate <= R.MaxBankStep / R.MaxSegmentChord + 1e-12 and math.deg(math.atan(C.MaxGradeRate * R.MaxSegmentChord)) <= R.MaxPitchStep + 1e-3,
		`grade {C.MaxGrade} of {R.MaxGrade} deg, bank {C.MaxBank} of {R.MaxBank} deg, bank rate {fmt(C.MaxBankRate, 4)} of {fmt(R.MaxBankStep / R.MaxSegmentChord, 4)} deg/stud, grade change {fmt(math.deg(math.atan(C.MaxGradeRate * R.MaxSegmentChord)), 3)} of {R.MaxPitchStep} deg per chord`
	)
	check("every road reached its length", short == 0, `{short} of {#SEEDS} seeds stalled short of {LIMIT_LENGTH} studs`)
	check("no bend tighter than MinRadius", worst.k <= kMax + 1e-12, `tightest radius {fmt(1 / worst.k, 1)} studs, limit {C.MinRadius}`)
	check("turn eases no faster than MaxCurvatureRate", worst.kRate <= C.MaxCurvatureRate * (1 + 1e-9), `worst {fmt(worst.kRate * 1e6, 2)}e-6 per stud, limit {fmt(C.MaxCurvatureRate * 1e6, 2)}e-6`)
	check("heading never kinks", worst.yawRate <= kMax + 1e-9, `worst heading change over 1 stud {fmt(math.deg(worst.yawRate), 4)} deg, the tightest bend's is {fmt(math.deg(kMax), 4)}`)
	check("plan is continuous", worst.stepErr < 1e-3, `1 stud of road was 1 stud of plan to within {string.format("%.2e", worst.stepErr)}`)
	check("grade within MaxGrade", worst.g <= gMax + 1e-12, `steepest {fmt(math.deg(math.atan(worst.g)), 2)} deg, limit {C.MaxGrade}`)
	check("grade changes no faster than MaxGradeRate", worst.gRate <= C.MaxGradeRate * (1 + 1e-9), `worst {fmt(worst.gRate * 1000, 4)}e-3 per stud, limit {fmt(C.MaxGradeRate * 1000, 4)}e-3`)
	-- the band moves with the road on a descent (T-166) and the generator plans each section
	-- against where it will be at the section's end, so a crest mid-section may sit a stud
	-- past it: 0.3 measured, and 1.7 where a climb begins at the floor. The grade limits above
	-- are the hard ones
	local slack = if gen0Drift() ~= 0 then 2 else 1e-6
	check("height stays in its band", worst.yLo >= C.MinHeight - slack and worst.yHi <= C.MaxHeight + slack, `{fmt(worst.yLo, 1)} .. {fmt(worst.yHi, 1)} studs, band {C.MinHeight} .. {C.MaxHeight} round a centre moving {fmt(gen0Drift() * 1000, 1)} studs per 1000 and climbing back`)
	check("bank within MaxBank", worst.b <= bMax + 1e-12, `most {fmt(math.deg(worst.b), 2)} deg, limit {C.MaxBank}`)
	check("bank changes no faster than MaxBankRate", worst.bRate <= math.rad(C.MaxBankRate) * (1 + 1e-9), `worst {fmt(math.deg(worst.bRate), 4)} deg/stud, limit {fmt(C.MaxBankRate, 4)}`)
	check(
		"no surface leans past MaxSurfaceTilt, or reads as a wall",
		tiltDeg <= Config.Road.MaxSurfaceTilt and worst.minNy > 0.7,
		`steepest lean {fmt(tiltDeg, 2)} deg at the kerb (normal Y {fmt(worst.minNy, 4)}), limit {Config.Road.MaxSurfaceTilt} deg and 0.7`
	)
end

-- 2. No crossing, by brute force rather than through the hash the generator uses.
function parts.crossing(check)
	local clear, sep = SplineGen.limits()
	local worstDist, worstAt = math.huge, ""
	local pairsChecked = 0
	for _, seed in SEEDS do
		local gen = road(seed, LIMIT_LENGTH)
		local sp = gen.spline
		local xs, zs, ss = {}, {}, {}
		local s = 0
		while s <= sp.length do
			local x, z = sp:planAt(s)
			table.insert(xs, x)
			table.insert(zs, z)
			table.insert(ss, s)
			s += 4
		end
		local n = #ss
		for i = 1, n do
			local xi, zi, si = xs[i], zs[i], ss[i]
			for j = i + 1, n do
				if ss[j] - si > sep then
					local dx, dz = xs[j] - xi, zs[j] - zi
					local d2 = dx * dx + dz * dz
					pairsChecked += 1
					if d2 < worstDist * worstDist then
						worstDist = math.sqrt(d2)
						worstAt = `seed {seed}, s {math.floor(si)} and {math.floor(ss[j])}`
					end
				end
			end
		end
	end
	-- the generator files points every CheckStep, so between two of them the true curve can
	-- come up to half a step closer: that is the tolerance, and it is stated
	local tol = Config.Spline.CheckStep / 2
	check(
		"the road never comes near itself",
		worstDist >= clear - tol,
		`closest approach of non-neighbouring road {fmt(worstDist, 1)} studs ({worstAt}); clearance {fmt(clear, 0)}, {pairsChecked} pairs checked every 4 studs`
	)
end

-- 3. The server's road and a client's replay of its sections are the same road.
function parts.replay(check)
	local a = road(8080, 8000)
	local b = road(8080, 8000)
	local same = #a.sections == #b.sections
	for i = 1, math.min(#a.sections, #b.sections) do
		local x, y = a.sections[i], b.sections[i]
		if x.len ~= y.len or #x.k ~= #y.k or #x.g ~= #y.g or #x.b ~= #y.b then
			same = false
		else
			for _, key in { "k", "g", "b" } do
				for j = 1, #x[key] do
					if x[key][j] ~= y[key][j] then
						same = false
					end
				end
			end
		end
	end
	check("the same seed lays the same road", same, `{#a.sections} sections, every knot identical`)
	local copy = SplineGen.replay(a.sections)
	local worst = 0
	local rng = Random.new(5)
	for _ = 1, 2000 do
		local s = rng:NextNumber() * a.spline.length
		local p = a.spline:surface(s, 20)
		local q = copy:surface(s, 20)
		worst = math.max(worst, (p - q).Magnitude)
	end
	check("a client's replay of the sections is the same road", worst == 0, `worst gap {worst} studs over 2000 points`)
	local other = road(8081, 8000)
	local differs = other.spline:surface(4000, 0) ~= a.spline:surface(4000, 0)
	check("another seed lays another road", differs, "seed 8081 is elsewhere at 4000 studs")
end

-- 4. The generator never boxes itself in, and what it costs.
function parts.health(check)
	local stalls, escapes, cornered, sections, worstMs, totalMs = 0, 0, 0, 0, 0, 0
	local kinds = {}
	local rejectsCrowded, rejectsHeading, tries = 0, 0, 0
	local minR, maxR = math.huge, 0
	for i = 1, HEALTH_SEEDS do
		local gen = road(1000 + i * 37, HEALTH_LENGTH)
		local st = gen.stats
		if st.stalled then
			stalls += 1
		end
		escapes += st.escapes
		cornered += st.cornered
		sections += st.sections
		worstMs = math.max(worstMs, st.worstMs)
		totalMs += st.totalMs
		rejectsCrowded += st.rejectedCrowded
		rejectsHeading += st.rejectedHeading
		tries += st.tries
		for k, n in st.kinds do
			kinds[k] = (kinds[k] or 0) + n
		end
		for _, sec in gen.sections do
			local k = math.abs(sec.k[#sec.k])
			if k > 0 then
				minR = math.min(minR, 1 / k)
				maxR = math.max(maxR, 1 / k)
			end
		end
	end
	local mix = {}
	for k, n in kinds do
		table.insert(mix, `{k} {n}`)
	end
	table.sort(mix)
	check("never boxed in", stalls == 0, `{stalls} of {HEALTH_SEEDS} roads of {HEALTH_LENGTH} studs stalled; {escapes} escapes laid in {sections} sections, {cornered} cornered`)
	check(
		"a section costs little",
		worstMs < 20,
		`mean {fmt(totalMs / sections, 2)} ms, worst {fmt(worstMs, 2)} ms; {tries} candidates for {sections} sections ({rejectsCrowded} too close to old road, {rejectsHeading} off heading)`
	)
	check("bends of every radius", minR <= 80 and maxR >= 600, `radii {fmt(minR, 0)} .. {fmt(maxR, 0)} studs. Mix: {table.concat(mix, ", ")}`)
end

-- 5. Finding the ground: (x, z) back to (s, d), the height, and the normal.
function parts.project(check)
	local gen = road(31337, 6000)
	local sp = gen.spline
	local W = Config.Road.Width
	local rng = Random.new(9)
	local worstS, worstD, worstY, misses, worstN = 0, 0, 0, 0, 0
	local hintMisses = 0
	for _ = 1, 3000 do
		local s = 50 + rng:NextNumber() * (sp.length - 100)
		local d = (rng:NextNumber() * 2 - 1) * W / 2
		-- full precision throughout: a Vector3 this far out is only good to ~0.002 studs
		local px, py, pz = sp:surfaceXYZ(s, d)
		local hint = s + (rng:NextNumber() * 2 - 1) * 30
		local s1, d1, y1, n1 = sp:ground(px, pz, hint)
		local s2 = sp:ground(px, pz)
		if not s1 then
			hintMisses += 1
		else
			worstS = math.max(worstS, math.abs(s1 - s))
			worstD = math.max(worstD, math.abs(d1 - d))
			worstY = math.max(worstY, math.abs(y1 - py))
			-- the normal against the surface's own slope, by finite differences
			local e = 0.01
			local function v(ss, dd)
				local x, y, z = sp:surfaceXYZ(ss, dd)
				return { x, y, z }
			end
			local a, b, c, f = v(s + e, d), v(s - e, d), v(s, d + e), v(s, d - e)
			local u = Vector3.new(a[1] - b[1], a[2] - b[2], a[3] - b[3])
			local w = Vector3.new(f[1] - c[1], f[2] - c[2], f[3] - c[3])
			local fd = u:Cross(w).Unit
			if fd.Y < 0 then
				fd = -fd
			end
			worstN = math.max(worstN, math.deg(math.acos(math.clamp(fd:Dot(n1), -1, 1))))
		end
		if not s2 or math.abs(s2 - s) > 1e-4 then
			misses += 1
		end
	end
	check("ground from a hint finds the right spot", hintMisses == 0 and worstS < 1e-4 and worstD < 1e-4, `3000 points across the road, hint up to 30 studs out: {hintMisses} lost, worst along {string.format("%.1e", worstS)}, across {string.format("%.1e", worstD)}`)
	check("ground height is the surface's height", worstY < 1e-4, `worst {string.format("%.1e", worstY)} studs`)
	check("ground normal is the surface's normal", worstN < 0.05, `worst {fmt(worstN, 4)} deg against finite differences`)
	check("ground with no hint finds it too", misses == 0, `{misses} of 3000 missed`)
	-- against a brute-force search: points scattered anywhere within the barriers, not built
	-- from a known (s, d), and the nearest centre-line point found by scanning every 0.02 studs
	local worstBrute = 0
	for _ = 1, 300 do
		local s = 200 + rng:NextNumber() * (sp.length - 400)
		local d = (rng:NextNumber() * 2 - 1) * W / 2
		local cx, _, cz = sp:surfaceXYZ(s, 0)
		local yaw = sp:yawAt(s)
		-- step off the cross-section too, so the point is not on one by construction
		local jitter = (rng:NextNumber() * 2 - 1) * 6
		local px = cx + d * math.cos(yaw) - jitter * math.sin(yaw)
		local pz = cz - d * math.sin(yaw) - jitter * math.cos(yaw)
		local sFound, dFound = sp:ground(px, pz, s + 20)
		local best, bestS = math.huge, s
		local t = s - 60
		while t <= s + 60 do
			local x, z = sp:planAt(t)
			local dd = (x - px) ^ 2 + (z - pz) ^ 2
			if dd < best then
				best, bestS = dd, t
			end
			t += 0.02
		end
		if sFound and dFound then
			local x, z = sp:planAt(sFound)
			local mine = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
			worstBrute = math.max(worstBrute, mine - math.sqrt(best), math.abs(math.abs(dFound) - math.sqrt(best)))
		else
			worstBrute = math.huge
		end
	end
	check("the nearest point agrees with a brute-force search", worstBrute < 0.01, `300 scattered points: worst {string.format("%.1e", worstBrute)} studs from scanning the centre line every 0.02 studs`)

	-- off the road: nothing
	local x, z = sp:planAt(3000)
	local yaw = sp:yawAt(3000)
	local farS = sp:ground(x + math.cos(yaw) * 400, z - math.sin(yaw) * 400)
	check("a point well off the road is not on it", farS == nil, "400 studs to the side of s = 3000")

	-- cost: what the car pays, four wheels a step
	local t0 = os.clock()
	local hint = 2000
	local N = 20000
	for i = 1, N do
		local s = 2000 + i * 0.05
		local qx, _, qz = sp:surfaceXYZ(s, 10)
		local sOut = sp:ground(qx, qz, hint)
		hint = sOut or hint
	end
	local us = (os.clock() - t0) / N * 1e6
	check("ground is cheap", us < 40, `{fmt(us, 1)} microseconds a query, including making the point (four wheels at 120 steps is {fmt(us * 480 / 1000, 2)} ms a second)`)
end

-- 6. The stored samples are the true curve: against an integration 16 times finer.
function parts.accuracy(check)
	local gen = road(2024, 3000)
	local sp = gen.spline
	local worst = 0
	local x, z = sp.origin.x, sp.origin.z
	local h = 0.25
	local s = 0
	while s + h <= sp.length do
		local y0, ym, y1 = sp:yawAt(s), sp:yawAt(s + h / 2), sp:yawAt(s + h)
		x += h / 6 * (-math.sin(y0) - 4 * math.sin(ym) - math.sin(y1))
		z += h / 6 * (-math.cos(y0) - 4 * math.cos(ym) - math.cos(y1))
		s += h
		if math.abs(s % 1) < 1e-9 then
			local px, pz = sp:planAt(s)
			worst = math.max(worst, math.sqrt((px - x) ^ 2 + (pz - z) ^ 2))
		end
	end
	check("the curve is integrated accurately", worst < 1e-3, `worst {string.format("%.2e", worst)} studs from a 0.25-stud integration over {math.floor(sp.length)} studs`)
end

-- 7. The mountainside (features/mountain-road.md, T-140): what each section chose, the
-- cross-section it makes, and a client's replay of it.
function parts.terrain(check)
	local T = Config.Spline.Terrain
	local half = Config.Road.Width * 0.5
	local names = { "rock", "hedge", "cliff" }

	-- What the generator chose, over long roads
	local missing, badWidth, worstRate, mixes, swaps, badSwaps, sameSides = 0, 0, 0, {}, 0, 0, 0
	local rails, railsOnBendCliff, badRails, bendsOverCliff = 0, 0, 0, 0
	local insideWorst, insideN = -math.huge, 0
	local stretches = {}
	local hedgePoints, swapApart, swapOutOfBand = 0, 0, 0 -- no hedges, and the mountain joined through a change of sides (T-189)
	-- carved apexes (T-182): how many, how close, and what is either side of each
	local worstCarveRate, carves, carveLen, carveWorstGap, carveBad = 0, 0, 0, 0, 0
	local wrongSide, sideChecked, swapLen = 0, 0, 0
	for _, seed in SEEDS do
		local gen = road(seed, LIMIT_LENGTH)
		local sp = gen.spline
		local s = 0
		for _, sec in gen.sections do
			if not (sec.rl and sec.rr and sec.el and sec.er) then
				missing += 1
			else
				for i, knots in { sec.rl, sec.rr } do
					-- a tight cliff edge's side (T-181) narrows to gravel faster: `parts.tight`
					local tight = sec.gl ~= nil and sec.gl[3] == (if i == 1 then -1 else 1)
					local prevV, prevS = nil, 0
					for j = 1, #knots, 2 do
						local w = knots[j + 1]
						-- a grove (T-183) widens it to `GroveRunoff`, and the next section eases back; a tight
						-- cliff edge (T-181) narrows it to `TightRunoff`; a carved apex (T-182) narrows
						-- the rock side to `CarvedGap`, at up to `CarvedRate`
						local carved = math.abs(w - T.CarvedGap) < 1e-9
						if (w < (if tight then T.TightRunoff[1] else T.RunoffMin) - 1e-9 and not carved) or w > math.max(T.RunoffMax, T.GroveRunoff[2]) + 1e-9 then
							badWidth += 1
						end
						if prevV and not tight then
							local rate = math.abs(w - prevV) / math.max(knots[j] - prevS, 1e-9)
							if carved or math.abs(prevV - T.CarvedGap) < 1e-9 then
								worstCarveRate = math.max(worstCarveRate, rate)
							else
								worstRate = math.max(worstRate, rate)
							end
						end
						prevV, prevS = w, knots[j]
					end
				end
				local l, r = sec.el[2], sec.er[2]
				local key = `{names[l]}/{names[r]}`
				mixes[key] = (mixes[key] or 0) + 1
				-- one side the mountain, the other the drop: never rock both sides, never a
				-- cliff both sides
				if (l == Spline.ROCK and r == Spline.ROCK) or (l == Spline.CLIFF and r == Spline.CLIFF) then
					sameSides += 1
				end
				local bend = sec.tag ~= "Straight" and sec.tag ~= "Escape" and sec.tag ~= "Start"
				local kEnd = sec.k[#sec.k]
				local outside = if kEnd > 0 then 1 else -1
				local outsideKind = if outside < 0 then l else r
				if bend and outsideKind == Spline.CLIFF and sec.len >= T.KRailRun[1] then
					bendsOverCliff += 1
				end
				if sec.kr then
					for j = 1, #sec.kr, 3 do
						rails += 1
						local len = sec.kr[j + 1] - sec.kr[j]
						if len < T.KRailRun[1] - 1e-6 or len > T.KRailRun[2] + 1e-6 then
							badRails += 1
						end
						if bend and sec.kr[j + 2] == outside and outsideKind == Spline.CLIFF then
							railsOnBendCliff += 1
						end
					end
				end
			end
			s += sec.len
		end
		-- the inside of every bend keeps its grass short of the bend's centre
		for u = 0, sp.length, 3 do
			local k = sp:curvatureAt(u)
			if math.abs(k) > 1 / 400 then
				local inside = if k > 0 then -1 else 1
				local reach = (half + sp:runoffAt(u, inside)) * math.abs(k)
				insideWorst = math.max(insideWorst, reach)
				insideN += 1
			end
		end
		-- CARVED APEXES (T-182): wherever the inside grass is down to `CarvedGap`, the rock is
		-- that side, the drop the other, and the road is bending toward the rock
		carves += gen.stats.carved
		carveLen += sp.length
		for u = 0, sp.length, 2 do
			for _, side in { -1, 1 } do
				local w = sp:runoffRaw(u, side)
				if w < T.RunoffMin - 0.01 then
					carveWorstGap = math.max(carveWorstGap, if w <= T.CarvedGap + 1e-6 then sp:runoffAt(u, side) else 0)
					local k = sp:curvatureAt(u)
					if w <= T.CarvedGap + 1e-6 and (sp:edgeAt(u, side) ~= Spline.ROCK or sp:edgeAt(u, -side) ~= Spline.CLIFF or (k > 0) ~= (side < 0) or k == 0) then
						carveBad += 1
					end
				end
			end
		end
		-- WHICH SIDE THE MOUNTAIN IS ON, along the road (T-166): the side the uphill direction
		-- is on, outside the band along the fall line; and it changes only inside a planned
		-- turn (a hairpin, a switchback or a double hairpin), never on an ordinary bend.
		-- NO HEDGES (T-189): every point is rock one side and the drop the other, and a change
		-- of sides happens at one point, both sides at once, inside the band: the rock face
		-- ends on one side where it starts on the other, so the mountain has no gap
		local band = math.sin(math.rad(Config.Spline.Mountain.AlongFallLine))
		local upPrev, runFrom, lastS = nil, 0, 0
		for u = 0, sp.length, 4 do
			local l, r = sp:edgeAt(u, -1), sp:edgeAt(u, 1)
			if (l == Spline.ROCK and r == Spline.ROCK) or (l == Spline.CLIFF and r == Spline.CLIFF) then
				sameSides += 1
			end
			if l == Spline.HEDGE or r == Spline.HEDGE then
				hedgePoints += 1
			end
			local up = if l == Spline.ROCK or r == Spline.CLIFF then -1 elseif r == Spline.ROCK or l == Spline.CLIFF then 1 else nil
			local across = math.sin(sp:yawAt(u) - gen.fall)
			if up and math.abs(across) >= band + 0.02 then
				sideChecked += 1
				if up ~= (if across > 0 then 1 else -1) then
					wrongSide += 1
				end
			end
			if up then
				if upPrev and up ~= upPrev then
					swaps += 1
					local planned = false
					for _, t in gen.turns do
						if t[1] <= u and t[2] >= lastS and t[3] ~= "straighten" and t[3] ~= "sideways" and t[3] ~= "sidewaysOut" then
							planned = true
							break
						end
					end
					if not planned then
						badSwaps += 1
					end
					-- where each side changed, to a quarter of a stud: the same point, in the band
					local at = { [-1] = u, [1] = u }
					for _, side in { -1, 1 } do
						local was = sp:edgeAt(lastS, side)
						for v = lastS, u, 0.25 do
							if sp:edgeAt(v, side) ~= was then
								at[side] = v
								break
							end
						end
					end
					swapApart = math.max(swapApart, math.abs(at[-1] - at[1]))
					if math.abs(math.sin(sp:yawAt(at[1]) - gen.fall)) > band + 1e-3 then
						swapOutOfBand += 1
					end
					table.insert(stretches, u - runFrom)
					runFrom = u
				end
				upPrev, lastS = up, u
			end
		end
		swapLen += sp.length
	end
	local mixList = {}
	for k, n in mixes do
		table.insert(mixList, `{k} {n}`)
	end
	table.sort(mixList)
	table.sort(stretches)
	local median = stretches[math.max(1, #stretches // 2)] or 0
	check("every section carries its mountainside", missing == 0, `{missing} sections without runoff or edges`)
	check("runoff 12 to 40 studs (58 on a grove), and it never changes fast", badWidth == 0 and worstRate <= 0.25 + 1e-9, `{badWidth} widths outside {T.RunoffMin}..{math.max(T.RunoffMax, T.GroveRunoff[2])}; steepest change {fmt(worstRate, 3)} stud per stud between knots (limit 0.25)`)
	check(
		"some sharp bends carve the rock to the tarmac's edge at the apex, eased in and out",
		carves > 0 and carveBad == 0 and carveWorstGap <= T.CarvedGap + 1e-6 and worstCarveRate <= T.CarvedRate + 1e-9,
		`{carves} carved apexes ({fmt(carves / carveLen * 10000, 2)} per 10 000 studs); rock to tarmac at the apex at most {fmt(carveWorstGap, 2)} studs; {carveBad} points carved without rock inside the bend and a cliff outside; steepest easing {fmt(worstCarveRate, 3)} stud per stud (limit {T.CarvedRate})`
	)
	check("the mountain on one side, the drop on the other", sameSides == 0, `{sameSides} points with rock or cliff both sides. Left/right mix of sections' first edges: {table.concat(mixList, ", ")}`)
	check("the mountain is on the uphill side of the road", wrongSide == 0 and sideChecked > 0, `{wrongSide} of {sideChecked} points away from the fall line have it on the wrong side`)
	check(
		"the mountain changes sides only inside a hairpin, switchback or double hairpin",
		badSwaps == 0 and swaps > 0,
		`{swaps} changes of side ({fmt(swaps / swapLen * 10000, 1)} per 10 000 studs; 3.5 before T-166, measured), {badSwaps} anywhere else; the mountain stayed on one side for {fmt(median, 0)} studs (median)`
	)
	check(
		"no hedge edges, and the mountain joined through every change of sides",
		hedgePoints == 0 and swapApart <= 0.25 + 1e-6 and swapOutOfBand == 0,
		`{hedgePoints} points with a hedge; the two sides change at most {fmt(swapApart, 2)} studs apart (rock ends one side where it starts the other); {swapOutOfBand} changes outside the band along the fall line`
	)
	check(
		"K-rails 60 to 300 studs, on most bends above a cliff",
		badRails == 0 and rails > 0 and railsOnBendCliff >= bendsOverCliff * 0.3,
		`{rails} runs, {badRails} the wrong length; {railsOnBendCliff} of {bendsOverCliff} bends with a cliff outside have one (about half wanted)`
	)
	check("the inside of a bend keeps its grass short of the bend's centre", insideWorst <= T.InsideShare + 1e-6, `furthest the inside edge reaches: {fmt(insideWorst * 100, 1)}% of the way to the centre (limit {T.InsideShare * 100}%), {insideN} points on bends`)

	-- The cross-section at a point
	local gen = road(31337, 8000)
	local sp = gen.spline
	local rng = Random.new(11)
	local wrongKind, worstJoin, worstSlope, worstFlat, n = 0, 0, 0, 0, 0
	local worstLip, lipNormal = 0, 1
	local cliffNil, cliffTried, wallGrass, wallTried = 0, 0, 0, 0
	for _ = 1, 3000 do
		local s = 50 + rng:NextNumber() * (sp.length - 100)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local w = sp:runoffAt(s, side)
		local edge = sp:edgeAt(s, side)
		-- tarmac, grass, and past the edge
		local dT = side * rng:NextNumber() * half
		local dG = side * (half + 0.01 + rng:NextNumber() * math.max(0, w - 0.02))
		local dP = side * (half + w + 0.5 + rng:NextNumber() * 10)
		if sp:groundKind(s, dT) ~= Spline.TARMAC or (w > 0.05 and sp:groundKind(s, dG) ~= (if sp:gravelAt(s, side) or math.abs(dG) - half <= sp:lipWidthAt(s, side) then Spline.GRAVEL else Spline.GRASS)) then
			wrongKind += 1
		end
		if edge == Spline.CLIFF then
			cliffTried += 1
			if sp:groundKind(s, dP) == nil then
				cliffNil += 1
			end
		else
			wallTried += 1
			if sp:groundKind(s, dP) == Spline.GRASS then
				wallGrass += 1
			end
		end
		-- the grass meets the tarmac without a gap or a crease, and is flat at its edge: read
		-- off the ground as if the road were not raised (`terrainY` + `lipAt`)
		local function baseY(d: number): number
			return sp:terrainY(s, d) + sp:lipAt(s, d)
		end
		local yRoad = sp:heightAt(s) + side * half * math.tan(sp:bankAt(s))
		worstJoin = math.max(worstJoin, math.abs(sp:terrainY(s, side * half) - yRoad), math.abs(sp:terrainY(s, side * (half + 1e-4)) - yRoad))
		if w > 2 then
			local e = 1e-3
			local inner = (baseY(side * (half + e)) - baseY(side * half)) / e
			worstSlope = math.max(worstSlope, math.abs(inner - side * math.tan(sp:bankAt(s))))
			local outer = (sp:terrainY(s, side * (half + w)) - sp:terrainY(s, side * (half + w - e))) / e
			worstFlat = math.max(worstFlat, math.abs(outer))
			-- the raised road (T-184): `RoadLip` down by the step's foot and all the way out,
			-- and the step's face, to the car, has the grass's own normal
			local lw = sp:lipWidthAt(s, side)
			for _, d in { half + lw, half + lw + rng:NextNumber() * (w - lw), half + w } do
				worstLip = math.max(worstLip, math.abs(baseY(side * d) - sp:terrainY(s, side * d) - T.RoadLip))
			end
			-- (not on a runoff narrowed to a few studs, as at a carved apex: there the ground's
			-- normal turns a few degrees across the narrow strip, 3.3 measured. More carved apexes since T-189,
			-- with rock on every uphill side, put one of the sampled points there)
			if w >= 6 then
				lipNormal = math.min(lipNormal, sp:terrainNormal(s, side * (half + lw * 0.5)):Dot(sp:terrainNormal(s, side * (half + lw + 0.05))))
			end
		end
		n += 1
	end
	check("tarmac, then grass, at the right offsets", wrongKind == 0, `{wrongKind} of {n} points read the wrong surface`)
	check("past a cliff's lip there is nothing", cliffTried > 0 and cliffNil == cliffTried, `{cliffNil} of {cliffTried} points past a cliff found nothing under them`)
	check("past a rock face or a hedge the ground carries on", wallTried > 0 and wallGrass == wallTried, `{wallGrass} of {wallTried}`)
	check("the grass meets the tarmac with no gap: the step starts at its edge", worstJoin < 1e-3, `worst {string.format("%.1e", worstJoin)} studs`)
	check(
		"the road stands RoadLip above its grass",
		worstLip < 1e-6 and lipNormal > 0.999,
		`grass off {T.RoadLip} studs below the unraised ground by {string.format("%.1e", worstLip)} at worst, past a gravel bevel up to {T.RoadLipWidth} across; the bevel's normal to the car against the grass at its foot, dot {fmt(lipNormal, 4)} at worst (1: the forces never read it as a slope)`
	)
	check("the grass leaves the road at its bank and eases flat", worstSlope < 0.01 and worstFlat < 0.01, `slope at the tarmac's edge off the bank's by {fmt(worstSlope, 4)}; at the grass's outer edge {fmt(worstFlat, 4)} (flat is 0)`)

	-- A client's replay has the same mountainside, exactly
	local copy = SplineGen.replay(gen.sections)
	local differ = 0
	for _ = 1, 2000 do
		local s = rng:NextNumber() * sp.length
		for _, side in { -1, 1 } do
			local a0, a1 = sp:kRailAt(s, side)
			local b0, b1 = copy:kRailAt(s, side)
			if sp:runoffAt(s, side) ~= copy:runoffAt(s, side) or sp:edgeAt(s, side) ~= copy:edgeAt(s, side) or a0 ~= b0 or a1 ~= b1 or sp:terrainY(s, side * 40) ~= copy:terrainY(s, side * 40) then
				differ += 1
			end
		end
	end
	check("a client's replay has the same grass, edges and K-rails", differ == 0, `{differ} of 4000 side samples differ`)

	-- A malformed section is refused whole
	local refused = 0
	local bad = {
		{ len = 100, k = { 100, 0 }, g = { 100, 0 }, b = { 100, 0 }, el = { 100, 9 } },
		{ len = 100, k = { 100, 0 }, g = { 100, 0 }, b = { 100, 0 }, rl = { 100, -5 } },
		{ len = 100, k = { 100, 0 }, g = { 100, 0 }, b = { 100, 0 }, er = { 50, 1 } },
		{ len = 100, k = { 100, 0 }, g = { 100, 0 }, b = { 100, 0 }, kr = { 20, 140, 1 } },
		{ len = 100, k = { 100, 0 }, g = { 100, 0 }, b = { 100, 0 }, kr = { 20, 40, 0 } },
	}
	for _, sec in bad do
		local fresh = SplineGen.replay(table.move(gen.sections, 1, 3, 1, {}))
		local before = fresh.length
		local ok = pcall(fresh.append, fresh, sec)
		if not ok and fresh.length == before then
			refused += 1
		end
	end
	check("a malformed mountainside is refused before any of it is laid", refused == #bad, `{refused} of {#bad} refused`)
end

-- 8. How much less twisty the wider clearance makes the road (the spec asks the build to
-- say). The same seeds, laid with the old clearance (74 studs, barriers) and the new.
function parts.twist(check)
	local old = Config.Road.Width + 2 * Config.Road.BarrierThickness + Config.Spline.ClearanceGap
	local function measure(clear: number?)
		local hairpins, turn, length, rejected, tries, escapes = 0, 0, 0, 0, 0, 0
		for i = 1, HEALTH_SEEDS do
			local gen = SplineGen.new(1000 + i * 37, nil, clear)
			gen:extendTo(HEALTH_LENGTH)
			local sp = gen.spline
			hairpins += gen.stats.kinds.Hairpin or 0
			rejected += gen.stats.rejectedCrowded
			tries += gen.stats.tries
			escapes += gen.stats.escapes
			length += sp.length
			-- total turning: the integral of |curvature|, sampled every 2 studs
			for u = 0, sp.length, 2 do
				turn += math.abs(sp:curvatureAt(u)) * 2
			end
		end
		local km = length / 1000
		return { hairpins = hairpins / km, turn = math.deg(turn) / km, rejected = rejected / tries, escapes = escapes / km }
	end
	local a = measure(old)
	local b = measure(nil)
	local newClear = SplineGen.limits()
	check(
		"how much less twisty (measured, not a limit)",
		b.turn >= a.turn * 0.75,
		`clearance {old} -> {newClear} studs. Turning per 1000 studs {fmt(a.turn, 0)} -> {fmt(b.turn, 0)} degrees ({fmt((b.turn / a.turn - 1) * 100, 1)}%); hairpins per 1000 studs {fmt(a.hairpins, 2)} -> {fmt(b.hairpins, 2)}; candidates too close to old road {fmt(a.rejected * 100, 1)}% -> {fmt(b.rejected * 100, 1)}%; escapes per 1000 studs {fmt(a.escapes, 2)} -> {fmt(b.escapes, 2)}`
	)
end

-- 9. The mountain's direction (features/mountain-direction.md, T-166): a fixed fall line,
-- legs across it joined by planned turns, and a descent.
function parts.mountain(check)
	local C = Config.Spline
	local M = C.Mountain
	local neutral = math.sin(math.rad(M.AlongFallLine))
	local flips, badFlips, length, drop, stalls = 0, 0, 0, 0, 0
	local downLen, climbLen, climbs, lowest = 0, 0, 0, math.huge
	local legs, turnarounds, doubles, sideways, refused, straightens = 0, 0, 0, 0, 0, 0
	local fallOk = 0
	local seeds = 0
	for i = 1, HEALTH_SEEDS do
		local gen = road(1000 + i * 37, HEALTH_LENGTH)
		local sp = gen.spline
		seeds += 1
		if gen.stats.stalled then
			stalls += 1
		end
		-- the fall line is square to the start heading
		if math.abs(math.cos(gen.fall - sp.origin.yaw)) < 1e-6 then
			fallOk += 1
		end
		-- which way across the slope the road runs, outside the band along the fall line;
		-- it may change only where a planned turn was laid
		local lastSign, lastS = 0, 0
		local turns = gen.turns
		for s = 0, sp.length, 4 do
			local a = sp:yawAt(s) - gen.fall
			local across = math.sin(a)
			if math.abs(across) >= neutral then
				local sg = if across > 0 then 1 else -1
				if lastSign ~= 0 and sg ~= lastSign then
					flips += 1
					local covered = false
					for _, t in turns do
						if t[1] <= s and t[2] >= lastS and t[3] ~= "straighten" then
							covered = true
							break
						end
					end
					if not covered then
						badFlips += 1
					end
				end
				lastSign, lastS = sg, s
			end
		end
		length += sp.length
		-- the height lost while the band is going down, and the road it took
		local b = gen.band
		for j = 3, #b, 2 do
			if b[j + 1] < b[j - 1] then
				drop += sp:heightAt(b[j - 2]) - sp:heightAt(b[j])
				downLen += b[j] - b[j - 2]
			else
				climbLen += b[j] - b[j - 2]
			end
		end
		climbs += gen.stats.climbs
		for s = 0, sp.length, 8 do
			lowest = math.min(lowest, sp:heightAt(s) - sp.origin.y)
		end
		local st = gen.stats
		legs += st.legs
		turnarounds += st.turnarounds
		doubles += st.doubles
		sideways += st.sideways
		refused += st.turnsRefused
		straightens += st.straightens
	end
	local per = 10000 / length
	local perK = drop / downLen * 1000
	check("the fall line is square to the start heading, every seed", fallOk == seeds, `{fallOk} of {seeds}`)
	check("never boxed in, on a descent", stalls == 0, `{stalls} of {seeds} roads of {HEALTH_LENGTH} studs stalled`)
	check(
		"the road turns back across the slope only through a planned turn",
		badFlips == 0 and flips > 0,
		`{flips} changes of direction across the slope, {badFlips} outside a hairpin, switchback or double hairpin`
	)
	check(
		"legs, turnarounds and detours (measured)",
		legs * per >= 2 and legs * per <= 8,
		`per 10 000 studs: {fmt(legs * per, 1)} legs, {fmt(turnarounds * per, 1)} turnarounds, {fmt(doubles * per, 2)} double hairpins, {fmt(sideways * per, 2)} sideways stretches, {fmt(straightens * per, 1)} straightening bends, {fmt(refused * per, 2)} turns refused and retried`
	)
	check(
		"the run works its way down",
		perK >= M.DescentRate * 1000 * 0.75 and perK <= M.DescentRate * 1000 * 1.25,
		`net drop {fmt(perK, 1)} studs per 1000 of road while descending (DescentRate is {fmt(M.DescentRate * 1000, 1)}); {climbs} climbs, {fmt(climbLen / length * 100, 1)}% of the road`
	)
	-- hours of running: one very long road never sinks past the fall-kill height
	local long = road(5151, 150000)
	local low, ups = math.huge, long.stats.climbs
	for s = 0, long.spline.length, 8 do
		low = math.min(low, long.spline:heightAt(s))
	end
	lowest = math.min(lowest, low - long.spline.origin.y)
	check(
		"a run of hours stays above the fall-kill height",
		long.spline.length >= 150000 and low > -500 + 20,
		`one road of {math.floor(long.spline.length)} studs: lowest point Y {fmt(low, 1)}, {ups} climbs; lowest over all {seeds + 1} roads {fmt(lowest, 1)} below the start (kill height Y -500)`
	)

	-- "traverse" is the road as it was: no plan, the start heading kept within HeadingLimit
	local was = M.Mode
	M.Mode = "traverse"
	local ok, res = pcall(function()
		local gen = road(4242, LIMIT_LENGTH)
		local worstOff = 0
		for s = 0, gen.spline.length, 8 do
			local off = math.abs((gen.spline:yawAt(s) - gen.spline.origin.yaw + math.pi) % (2 * math.pi) - math.pi)
			worstOff = math.max(worstOff, off)
		end
		return { len = gen.spline.length, legs = gen.stats.legs, off = math.deg(worstOff), y = gen.spline:heightAt(gen.spline.length) - gen.spline.origin.y }
	end)
	M.Mode = was
	check(
		"traverse still lays the old road",
		ok and res.len >= LIMIT_LENGTH and res.legs == 0 and res.off <= C.HeadingLimit + 1,
		if ok then `{math.floor(res.len)} studs, {res.legs} legs, furthest off the start heading {fmt(res.off, 1)} deg (limit {C.HeadingLimit})` else tostring(res)
	)
end

-- 10. TIGHT CLIFF EDGES (T-181): now and then on a cliff side the runoff closes in to a few
-- studs of gravel with a crash barrier on the tarmac's edge.
function parts.tight(check)
	local T = Config.Spline.Terrain
	local half = Config.Road.Width * 0.5
	local count, length, gravelLen, rate = 0, 0, 0, 0
	local notCliff, unrailed, wrongKind, samples = 0, 0, 0, 0
	local narrowest, widestCore = math.huge, 0
	local differ, clash = 0, 0
	for _, seed in SEEDS do
		local gen = road(seed, LIMIT_LENGTH)
		local sp = gen.spline
		length += sp.length
		local copy = SplineGen.replay(gen.sections)
		local s0 = 0
		for _, sec in gen.sections do
			if sec.gl then
				local a, b, side = s0 + sec.gl[1], s0 + sec.gl[2], sec.gl[3]
				count += 1
				gravelLen += b - a
				-- a grove (T-183) is chosen first and keeps its side
				if sec.gv then
					for j = 1, #sec.gv, 2 do
						if sec.gv[j] == side then
							clash += 1
						end
					end
				end
				local knots = if side < 0 then sec.rl else sec.rr
				-- the narrow part is between the two knots at the gravel's width
				widestCore = math.max(widestCore, knots[4], knots[6])
				local prevV, prevS = nil, 0
				for j = 1, #knots, 2 do
					if prevV then
						rate = math.max(rate, math.abs(knots[j + 1] - prevV) / (knots[j] - prevS))
					end
					prevV, prevS = knots[j + 1], knots[j]
				end
				for u = a, b, 2 do
					samples += 1
					local w = sp:runoffAt(u, side)
					narrowest = math.min(narrowest, w)
					if sp:edgeAt(u, side) ~= Spline.CLIFF then
						notCliff += 1
					end
					if not sp:kRailAt(u, side) then
						unrailed += 1
					end
					if sp:groundKind(u, side * (half + w * 0.5)) ~= Spline.GRAVEL or sp:groundKind(u, side * (half + w + 0.3)) ~= nil then
						wrongKind += 1
					end
					if copy:gravelAt(u, side) ~= true or copy:runoffAt(u, side) ~= w then
						differ += 1
					end
				end
			end
			s0 += sec.len
		end
	end
	check(
		"tight cliff edges: gravel a few studs wide, now and then",
		count > 0 and widestCore <= T.TightRunoff[2] + 1e-9 and narrowest >= T.TightRunoff[1] - 1e-6,
		`{count} in {math.floor(length)} studs ({fmt(count / length * 10000, 2)} per 10 000 studs, {fmt(gravelLen / length * 100, 1)}% of the road's length); gravel {fmt(narrowest, 2)} to {fmt(widestCore, 2)} studs at its narrowest part`
	)
	check("tight cliff edges ease in and out", rate <= T.TightRate + 1e-9, `steepest change {fmt(rate, 3)} stud per stud between knots (limit {T.TightRate})`)
	check(
		"tight cliff edges: a cliff past the gravel and a rail on the tarmac's edge all the way",
		notCliff == 0 and unrailed == 0 and wrongKind == 0 and samples > 0,
		`{samples} points: {notCliff} not over a cliff, {unrailed} without a rail, {wrongKind} not gravel then nothing`
	)
	check("a client's replay has the same gravel", differ == 0, `{differ} of {samples} differ`)
	check("a tight cliff edge never shares a side with a grove", clash == 0, `{clash} of {count} on a grove's side`)
end

-- 11. Grand cliffs (features/mountain-road.md "Grand cliffs", T-185): the faces' grandeur,
-- low near a turnaround and huge mid-leg, never standing up through the leg above.
function parts.grand(check)
	local T = Config.Spline.Terrain
	local SplineMesh = require(ReplicatedStorage.Shared.Road.SplineMesh)
	local half = Config.Road.Width * 0.5
	local TURNS = { turnaround = true, switchbackOut = true, double = true, doubleOut = true }
	local buckets = { { 0, T.GrandNear }, { T.GrandNear, T.GrandNear + T.GrandRamp * 0.5 }, { T.GrandNear + T.GrandRamp * 0.5, T.GrandNear + T.GrandRamp }, { T.GrandNear + T.GrandRamp, math.huge } }
	local sums = {}
	for i = 1, #buckets do
		sums[i] = { n = 0, g = 0, rock = 0, rockN = 0, rockMax = 0, cliff = 0, cliffN = 0 }
	end
	local bad, badKnots, nearHigh, nearN, poke, pokeFirst, under, differ = 0, 0, 0, 0, 0, "", 0, 0
	local besideWorst = -math.huge
	local worstRise, fastDrops, knotsN = -math.huge, 0, 0
	local perSeed = {}
	for _, seed in SEEDS do
		local gen = road(seed, LIMIT_LENGTH)
		local sp = gen.spline
		local prevG, prevS, s0 = 0, 0, 0
		for _, sec in gen.sections do
			if not sec.gd then
				bad += 1
			else
				for j = 2, #sec.gd, 2 do
					if sec.gd[j] < -1 or sec.gd[j] > 1 then -- below 0: lower, under the leg above (T-189)
						badKnots += 1
					end
					-- how fast it changes, knot to knot (the last knot rounded to 0.001)
					local s = s0 + sec.gd[j - 1]
					local dg, ds = sec.gd[j] - prevG, s - prevS
					if dg > 0 then
						-- past what the rate allows, in grandeur (knots are rounded to 0.001)
						worstRise = math.max(worstRise, dg - ds / T.GrandRate)
					elseif -dg > ds / T.GrandRate + 0.0011 then
						fastDrops += 1
					end
					knotsN += 1
					prevG, prevS = sec.gd[j], s
				end
			end
			s0 += sec.len
		end
		-- the turnarounds actually laid, as [s0, s1]
		local turns = {}
		for _, t in gen.turns do
			if TURNS[t[3]] then
				table.insert(turns, t)
			end
		end
		local seedMax = 0
		for u = 0, sp.length, 8 do
			local d = math.huge
			for _, t in turns do
				d = math.min(d, if u < t[1] then t[1] - u elseif u > t[2] then u - t[2] else 0)
			end
			d = math.min(d, u) -- the road's start counts as one
			local gr = sp:grandAt(u)
			if d < T.GrandNear - T.GrandKnotEvery then
				nearN += 1
				if gr > 1e-6 then
					nearHigh += 1
				end
			end
			for i, b in buckets do
				if d >= b[1] and d < b[2] then
					local sm = sums[i]
					sm.n += 1
					sm.g += gr
					for _, side in { -1, 1 } do
						local kind = sp:edgeAt(u, side)
						if kind == Spline.ROCK then
							local pts = SplineMesh.profile(sp, u, side, kind)
							local top = -math.huge
							for _, p in pts do
								top = math.max(top, p.Y - pts[1].Y)
							end
							sm.rock += top
							sm.rockN += 1
							sm.rockMax = math.max(sm.rockMax, top)
							seedMax = math.max(seedMax, top)
						elseif kind == Spline.CLIFF then
							local pts = SplineMesh.profile(sp, u, side, kind)
							sm.cliff += pts[1].Y - pts[#pts].Y
							sm.cliffN += 1
						end
					end
				end
			end
		end
		table.insert(perSeed, `{seed}: {fmt(seedMax, 0)}`)
		-- NO ROCK BODY STANDS UP THROUGH OLDER ROAD: every drawn point of a rock body that
		-- lies under the grass or tarmac of road laid before it is below that road. Brute
		-- force over the centre line every 8 studs, not the generator's hash
		local cell = 64
		local grid = {}
		for so = 0, sp.length, 8 do
			local x, z = sp:planAt(so)
			local key = math.floor(x / cell) * 100000 + math.floor(z / cell)
			grid[key] = grid[key] or {}
			table.insert(grid[key], so)
		end
		for u = 0, sp.length, 8 do
			for _, side in { -1, 1 } do
				if sp:edgeAt(u, side) == Spline.ROCK then
					for _, p in SplineMesh.profile(sp, u, side, Spline.ROCK) do
						local cx, cz = math.floor(p.X / cell), math.floor(p.Z / cell)
						for ix = cx - 6, cx + 6 do
							for iz = cz - 6, cz + 6 do
								for _, so in grid[ix * 100000 + iz] or {} do
									if u - so > gen.separation then
										local x, z = sp:planAt(so)
										local dist = math.sqrt((p.X - x) ^ 2 + (p.Z - z) ^ 2)
										local wo = half + math.max(sp:runoffAt(so, -1), sp:runoffAt(so, 1)) + T.EdgeDepth
										if dist >= wo and dist < wo + 300 then
											-- beside it: how far above the road, against how far off
											besideWorst = math.max(besideWorst, p.Y - sp:heightAt(so) - T.GrandAbove * (dist - wo))
										end
										if dist < wo then
											under += 1
											if p.Y > sp:heightAt(so) - 1 then
												poke += 1
												if pokeFirst == "" then
													pokeFirst = `; first seed {seed} at {math.floor(u)}, {fmt(p.Y - sp:heightAt(so), 1)} studs above the road at {math.floor(so)}`
												end
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
		-- a client's replay has the same grandeur
		local copy = SplineGen.replay(gen.sections)
		for u = 0, sp.length, 37 do
			if copy:grandAt(u) ~= sp:grandAt(u) then
				differ += 1
			end
		end
	end
	check("every section carries its grandeur, -1 to 1", bad == 0 and badKnots == 0, `{bad} sections without, {badKnots} knots out of range`)
	check(
		"grandeur rises no faster than GrandRate",
		worstRise <= 0.0011,
		`steepest rise {fmt(worstRise, 4)} past the limit (rounding is 0.001); {fastDrops} of {knotsN} knots fall faster, where older road above cuts it back as a section begins (a knot laid before cannot ease down for it)`
	)
	check("low within GrandNear of a turnaround", nearN > 0 and nearHigh == 0, `{nearHigh} of {nearN} points within {T.GrandNear - T.GrandKnotEvery} studs of a hairpin, switchback or double hairpin are grand at all`)
	local rows = {}
	for i, b in buckets do
		local sm = sums[i]
		table.insert(
			rows,
			`{b[1]}-{if b[2] == math.huge then "" else tostring(b[2])}: grandeur {fmt(sm.g / math.max(1, sm.n), 2)}, rock {fmt(sm.rock / math.max(1, sm.rockN), 0)} (most {fmt(sm.rockMax, 0)}), cliff {fmt(sm.cliff / math.max(1, sm.cliffN), 0)} [{sm.n} points]`
		)
	end
	local nearRock = sums[1].rock / math.max(1, sums[1].rockN)
	local farRock = sums[#sums].rock / math.max(1, sums[#sums].rockN)
	check("rock rises with distance from a turnaround (measured, studs from the nearest)", farRock > nearRock * 2.5, table.concat(rows, "; ") .. `. Tallest per seed: {table.concat(perSeed, ", ")}`)
	-- the generator keeps a body's footprint (with a knot's spacing) `foot` clear of older
	-- road before it lets it rise above it, wider than the road's own grass checked here, so
	-- `beside` may come out a few tens of studs over; a pinnacle would be a hundred or more
	check(
		"no rock body stands up through the leg above",
		poke == 0 and besideWorst < 80,
		`{poke} of {under} rock points under older road stand above it{pokeFirst}; beside older road, the most a rock point stands above it past {T.GrandAbove} studs per stud off its grass: {fmt(besideWorst, 1)}`
	)
	check("a client's replay has the same grandeur", differ == 0, `{differ} samples differ`)

	-- the grandeur changes nothing else the road chooses
	local was = T.GrandNear
	T.GrandNear = 1e9
	local ok, flat = pcall(road, 31337, 8000)
	T.GrandNear = was
	local same = ok
	if ok then
		local a = road(31337, 8000)
		same = #a.sections == #flat.sections
		for i = 1, math.min(#a.sections, #flat.sections) do
			local x, y = a.sections[i], flat.sections[i]
			for _, key in { "k", "g", "b", "rl", "rr", "el", "er", "kr", "gv", "gl" } do
				local p, q = x[key] or {}, y[key] or {}
				if #p ~= #q then
					same = false
				else
					for j = 1, #p do
						if p[j] ~= q[j] then
							same = false
						end
					end
				end
			end
		end
	end
	check("the grandeur changes nothing else the road chooses", same, "seed 31337, 8000 studs, with and without grand faces: every curve, runoff, edge, K-rail and grove knot the same")
end

function Tests.run(which: { string }?, ...)
	-- The DebugBridge calls a member as a method, so the module itself comes first.
	if which == Tests then
		which = ...
	end
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local order = { "limits", "crossing", "replay", "health", "project", "accuracy", "terrain", "twist", "mountain", "tight", "grand" }
	for _, name in which or order do
		local ok, err = pcall(parts[name], check)
		if not ok then
			check(name .. " ran", false, tostring(err))
		end
	end
	local passed = 0
	for _, c in checks do
		if c.ok then
			passed += 1
		end
	end
	return { passed = passed, total = #checks, checks = checks }
end

return Tests
