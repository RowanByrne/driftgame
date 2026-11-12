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
			local y = sp:heightAt(s) - base
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
	check("every road reached its length", short == 0, `{short} of {#SEEDS} seeds stalled short of {LIMIT_LENGTH} studs`)
	check("no bend tighter than MinRadius", worst.k <= kMax + 1e-12, `tightest radius {fmt(1 / worst.k, 1)} studs, limit {C.MinRadius}`)
	check("turn eases no faster than MaxCurvatureRate", worst.kRate <= C.MaxCurvatureRate * (1 + 1e-9), `worst {fmt(worst.kRate * 1e6, 2)}e-6 per stud, limit {fmt(C.MaxCurvatureRate * 1e6, 2)}e-6`)
	check("heading never kinks", worst.yawRate <= kMax + 1e-9, `worst heading change over 1 stud {fmt(math.deg(worst.yawRate), 4)} deg, the tightest bend's is {fmt(math.deg(kMax), 4)}`)
	check("plan is continuous", worst.stepErr < 1e-3, `1 stud of road was 1 stud of plan to within {string.format("%.2e", worst.stepErr)}`)
	check("grade within MaxGrade", worst.g <= gMax + 1e-12, `steepest {fmt(math.deg(math.atan(worst.g)), 2)} deg, limit {C.MaxGrade}`)
	check("grade changes no faster than MaxGradeRate", worst.gRate <= C.MaxGradeRate * (1 + 1e-9), `worst {fmt(worst.gRate * 1000, 4)}e-3 per stud, limit {fmt(C.MaxGradeRate * 1000, 4)}e-3`)
	check("height stays in its band", worst.yLo >= C.MinHeight - 1e-6 and worst.yHi <= C.MaxHeight + 1e-6, `{fmt(worst.yLo, 1)} .. {fmt(worst.yHi, 1)} studs, band {C.MinHeight} .. {C.MaxHeight}`)
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

function Tests.run(which: { string }?)
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local order = { "limits", "crossing", "replay", "health", "project", "accuracy" }
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
