--!nonstrict
-- SplineGenTests: where the spline road's K-rails (drawn as metal crash barriers) stand
-- (features/mountain-road.md "Where the K-rails stand", T-306). Pure maths: no instances.
--
--   game.ServerStorage.DebugBridge:Invoke("DebugSplineGenTests", "run")
--   require(game.ServerScriptService.Tests.SplineGenTests).run()   -- pure: Edit works too
--   ...run({ seeds = { 31337 }, length = 10000 })                  -- fewer, shorter roads
--
-- Over each seed's road (30 000 studs, three seeds; about 20 s in all):
-- 1. ONLY THE DOWNHILL SIDE: every rail point has the DRAWN ground (`Road/Ground.query`, the
--    cut and fill and every other road included) below the grass's outer edge at the probe
--    (`KRailProbe` past it), and the generator's own measure of the drop is a fall there.
-- 2. CORNERS above a steep drop (`KRailCornerDrop` on the outside): railed the whole way
--    round wherever the ground falls.
-- 3. HAIRPINS (`Road/Hairpins`, 120 degrees within 250 studs) with a big drop either side
--    (`KRailHairpinDrop`): railed through the bend on that side wherever the ground falls.
-- 4. Runs: none shorter than `KRailMinRun`, a rail carried across a section's end is one run,
--    none on a grove's side; the same rails from the same seed, and in a client's replay.
--
-- `run()` returns `{ passed, checks, log }`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "SplineGenTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)

local SEEDS = { 31337, 101, 2024 }
local LENGTH = 30000
local STEP = 4 -- studs between the points read
local MARGIN = 2 -- studs: a drop this near a threshold is the generator's call (its knots are read straight)

local SplineGenTests = {}

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

-- The drop beside the laid road at `s` on `side`, as the generator reads it
-- (`SplineGen._sideDrops`), and the probe point it reads it at.
local function dropAt(sp, f, s: number, side: number): (number, number?, number?, number?)
	local T = Config.Spline.Terrain
	local half = Config.Road.Width * 0.5
	local k = sp:curvatureAt(s)
	local w = sp:runoffAt(s, side)
	local inside = k ~= 0 and (k > 0) == (side < 0)
	local edgeY = sp:terrainY(s, side * (half + w))
	local D = T.KRailProbe
	if inside then
		D = math.min(D, T.KRailInsideReach / math.abs(k) - half - w)
	end
	if D < T.KRailProbeMin then
		return -math.huge, nil, nil, nil
	end
	local x, z = sp:planAt(s)
	local yaw = sp:yawAt(s)
	local dist = side * (half + w + D)
	local px, pz = x + dist * math.cos(yaw), z - dist * math.sin(yaw)
	return (edgeY - Ground.h(f, px, pz)) * T.KRailProbe / D, edgeY, px, pz
end

local function measure(seed: number, length: number, log: { string })
	local T = Config.Spline.Terrain
	local gen = SplineGen.new(seed)
	local L = 0
	while L < length do
		L = math.min(L + 2000, length)
		gen:extendTo(L)
		task.wait()
	end
	local sp = gen.spline
	local f = sp.mountain
	local r = {
		seed = seed,
		length = sp.length,
		railPoints = 0,
		drawnFalls = 0,
		drawnWorst = math.huge, -- the least the drawn ground is below the edge under a rail
		ownFalls = 0,
		corners = 0,
		cornerCovered = 0,
		cornerCovSum = 0,
		hairpins = 0,
		hairpinSides = 0,
		hairpinRailed = 0,
		hairpinMissed = {},
		runs = {},
		railLen = 0,
		shortRuns = 0,
		abutting = 0,
		onGrove = 0,
	}
	-- 1. every rail point: on falling ground, drawn and by the generator's measure
	local railed = { [-1] = {}, [1] = {} }
	local drops = { [-1] = {}, [1] = {} }
	local ss = {}
	local n = 0
	for s = STEP, sp.length - STEP, STEP do
		n += 1
		ss[n] = s
		for _, side in { -1, 1 } do
			local d, edgeY, px, pz = dropAt(sp, f, s, side)
			drops[side][n] = d
			local on = sp:kRailAt(s, side) ~= nil
			railed[side][n] = on
			if on then
				r.railPoints += 1
				if d >= T.KRailFallDrop - MARGIN then
					r.ownFalls += 1
				end
				if px and edgeY then
					local drawn = Ground.query(f, sp, px, pz)
					local below = edgeY - drawn
					r.drawnWorst = math.min(r.drawnWorst, below)
					if below > 0 then
						r.drawnFalls += 1
					end
				end
			end
		end
		if n % 400 == 0 then
			task.wait()
		end
	end
	-- 2. corners: runs of road tighter than `KRailCornerRadius`, one way
	local kCorner = 1 / T.KRailCornerRadius
	local i = 1
	while i <= n do
		local k = sp:curvatureAt(ss[i])
		if math.abs(k) >= kCorner then
			local dir = if k > 0 then 1 else -1
			local j = i
			while j < n do
				local kn = sp:curvatureAt(ss[j + 1])
				if math.abs(kn) < kCorner or (kn > 0) ~= (dir > 0) then
					break
				end
				j += 1
			end
			local most, falling, covered = -math.huge, 0, 0
			for m = i, j do
				most = math.max(most, drops[dir][m])
				if drops[dir][m] >= T.KRailFallDrop + MARGIN then
					falling += 1
					if railed[dir][m] then
						covered += 1
					end
				end
			end
			if most >= T.KRailCornerDrop + MARGIN and falling > 0 then
				r.corners += 1
				local cov = covered / falling
				r.cornerCovSum += cov
				if cov >= 0.9 then
					r.cornerCovered += 1
				end
			end
			i = j + 1
		else
			i += 1
		end
	end
	-- 3. true hairpins with a big drop either side
	for _, h in Hairpins.find(sp, 0, sp.length) do
		if not h.open then
			r.hairpins += 1
			for _, side in { -1, 1 } do
				local most, falling, covered = -math.huge, 0, 0
				for s = h.entry, h.exit, STEP do
					local d = dropAt(sp, f, s, side)
					most = math.max(most, d)
					if d >= T.KRailFallDrop + MARGIN then
						falling += 1
						if sp:kRailAt(s, side) then
							covered += 1
						end
					end
				end
				if most >= T.KRailHairpinDrop + MARGIN and falling > 0 then
					r.hairpinSides += 1
					if covered / falling >= 0.9 then
						r.hairpinRailed += 1
					else
						table.insert(r.hairpinMissed, `{math.floor(h.entry)}{if side < 0 then "L" else "R"} {fmt(covered / falling * 100, 0)}%`)
					end
				end
			end
		end
	end
	-- 4. the runs
	for _, side in { -1, 1 } do
		local runs = sp:kRailsIn(0, sp.length, side)
		for j = 1, #runs, 2 do
			local len = runs[j + 1] - runs[j]
			table.insert(r.runs, len)
			r.railLen += len
			if len < T.KRailMinRun - 1e-6 then
				r.shortRuns += 1
			end
			if j > 1 and runs[j] <= runs[j - 1] + 1e-6 then
				r.abutting += 1
			end
			local gr = sp:groves(side)
			for s = runs[j] + 1, runs[j + 1] - 1, STEP do
				for g = 1, #gr.a do
					if s > gr.a[g] and s < gr.b[g] then
						r.onGrove += 1
					end
				end
			end
		end
	end
	table.sort(r.runs)
	-- the same from the same seed, and in a client's replay
	local again = SplineGen.new(seed)
	again:extendTo(math.min(length, 8000))
	local copy = SplineGen.replay(gen.sections, nil, sp.fall, seed)
	local differ = 0
	for s = 0, math.min(sp.length, again.spline.length) - 1, 2 do
		for _, side in { -1, 1 } do
			local a0, a1 = sp:kRailAt(s, side)
			local b0, b1 = again.spline:kRailAt(s, side)
			local c0, c1 = copy:kRailAt(s, side)
			if a0 ~= b0 or a1 ~= b1 or a0 ~= c0 or a1 ~= c1 then
				differ += 1
			end
		end
	end
	r.differ = differ
	local runs = r.runs
	table.insert(
		log,
		`seed {seed}: {math.floor(sp.length)} studs, {#runs} runs, {math.floor(r.railLen)} studs of rail ({fmt(r.railLen / sp.length * 100, 1)}% of the road's length), runs {fmt(runs[1] or 0, 0)} / {fmt(runs[(#runs + 1) // 2] or 0, 0)} / {fmt(r.railLen / math.max(#runs, 1), 0)} / {fmt(runs[#runs] or 0, 0)} studs (shortest, median, mean, longest); `
			.. `on falling drawn ground {r.drawnFalls} of {r.railPoints} points (least {fmt(r.drawnWorst, 1)} studs below the edge); `
			.. `steep corners {r.cornerCovered} of {r.corners} railed 90%+ (mean {fmt(r.cornerCovSum / math.max(r.corners, 1) * 100, 0)}%); `
			.. `hairpins {r.hairpins}, big-drop sides railed {r.hairpinRailed} of {r.hairpinSides}{if #r.hairpinMissed > 0 then " (missed " .. table.concat(r.hairpinMissed, ", ") .. ")" else ""}; tight edges {gen.stats.tight}`
	)
	return r
end

function SplineGenTests.run(opts: { seeds: { number }?, length: number? }?)
	local seeds = (opts and opts.seeds) or SEEDS
	local length = (opts and opts.length) or LENGTH
	local checks, log = {}, {}
	local function check(name: string, ok: boolean, detail: string)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local all = {}
	for _, seed in seeds do
		table.insert(all, measure(seed, length, log))
	end
	local function sum(key: string): number
		local t = 0
		for _, r in all do
			t += r[key]
		end
		return t
	end
	local points, drawnFalls, ownFalls = sum("railPoints"), sum("drawnFalls"), sum("ownFalls")
	local worst = math.huge
	for _, r in all do
		worst = math.min(worst, r.drawnWorst)
	end
	check(
		"K-rails only on the downhill side: the drawn ground falls away below every rail",
		points > 0 and drawnFalls == points,
		`{drawnFalls} of {points} rail points ({fmt(drawnFalls / math.max(points, 1) * 100, 1)}%); the drawn ground at least {fmt(worst, 1)} studs below the grass's edge {Config.Spline.Terrain.KRailProbe} studs out`
	)
	check(
		"K-rails only where the generator reads a fall (KRailFallDrop)",
		ownFalls == points,
		`{ownFalls} of {points} rail points`
	)
	local corners, covered, covSum = sum("corners"), sum("cornerCovered"), sum("cornerCovSum")
	check(
		"corners above a steep drop are railed the whole way round",
		corners > 0 and covSum / corners >= 0.9,
		`{covered} of {corners} corners railed over 90%+ of their falling outside; mean {fmt(covSum / math.max(corners, 1) * 100, 1)}%`
	)
	local sides, railedSides = sum("hairpinSides"), sum("hairpinRailed")
	check("every hairpin side with a big drop is railed", sides > 0 and railedSides == sides, `{railedSides} of {sides} sides ({sum("hairpins")} hairpins)`)
	local short, abut, grove, differ = sum("shortRuns"), sum("abutting"), sum("onGrove"), sum("differ")
	check("no run shorter than KRailMinRun, none abutting another", short == 0 and abut == 0, `{short} short, {abut} abutting`)
	check("no K-rail on a grove's side", grove == 0, `{grove} rail points on a grove`)
	check("the same rails from the same seed and in a client's replay", differ == 0, `{differ} points differ`)
	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = log }
end

return SplineGenTests
