--!nonstrict
-- SplineGenTests: where the spline road's K-rails (drawn as metal crash barriers) stand
-- (features/mountain-road.md "Where the K-rails stand", T-306), as the dressing layer stands
-- them (`Road/RoadDressing`, `Config.Dressing.Barrier`, T-327). Pure maths: no instances.
--
--   game.ServerStorage.DebugBridge:Invoke("DebugSplineGenTests", "run")
--   require(game.ServerScriptService.Tests.SplineGenTests).run()   -- pure: Edit works too
--   ...run({ seeds = { 31337 }, length = 10000 })                  -- fewer, shorter roads
--
-- Over each seed's road (30 000 studs, three seeds; about 20 s in all):
-- 1. ONLY THE DOWNHILL SIDE: every rail point has the DRAWN ground (`Road/Ground.query`, the
--    cut and fill and every other road included) below the grass's outer edge at the probe
--    (`Probe` past it), and the generator's own measure of the drop is a fall there.
-- 2. CORNERS above a steep drop (`CornerDrop` on the outside): railed the whole way
--    round wherever the ground falls.
-- 3. HAIRPINS (`Road/Hairpins`, 120 degrees within 250 studs) with a big drop either side
--    (`HairpinDrop`): railed through the bend on that side wherever the ground falls.
-- 5. CARVED APEXES (T-308): only where the ground rises beside the bend, never on a railed side.
-- 4. Runs: none shorter than `MinRun`, a rail carried across a section's end is one run,
--    none on a grove's side; the same rails from the same seed, and in a client's replay.
-- 6. THE DRESSING NEVER CHANGES THE ROAD (T-327): laid with no dressing, every section is the
--    same, field for field, and carries no rail.
-- 7. AFTER A HAIRPIN (T-334): its rail ends `HairpinRunOut` after the bend straightens.
--
-- `run()` returns `{ passed, checks, log }`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "SplineGenTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local RoadDressing = require(ReplicatedStorage.Shared.Road.RoadDressing)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)

local SEEDS = { 31337, 101, 2024 }
local LENGTH = 30000
local STEP = 4 -- studs between the points read
local HAIRPIN_SEED = 2024 -- a road with many hairpins (19 in 30 000 studs), for the run-out check
local MARGIN = 2 -- studs: a drop this near a threshold is the generator's call (its knots are read straight)
-- (a point counts as railed with a rail within one `STEP` of it: the rail's ends are read on the
-- generator's own points, `Sample` apart)

local SplineGenTests = {}

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

-- The drop beside the laid road at `s` on `side`, as the generator reads it, and the probe
-- point it reads it at (`SplineGen.dropBeside`).
local function dropAt(sp, _f, s: number, side: number): (number, number?, number?, number?)
	return SplineGen.dropBeside(sp, s, side, Config.Dressing.Barrier)
end

local function measure(seed: number, length: number, log: { string })
	local T = Config.Spline.Terrain
	local B = Config.Dressing.Barrier
	local gen = SplineGen.new(seed)
	RoadDressing.attach(gen)
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
		apexes = 0,
		apexRising = 0,
		apexRailed = 0,
		apexWorst = -math.huge, -- the most the ground falls (negative: the least it rises) at any apex point
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
				if d >= B.FallDrop - MARGIN then
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
	-- 2. corners: runs of road tighter than `CornerRadius`, one way
	local kCorner = 1 / B.CornerRadius
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
				if drops[dir][m] >= B.FallDrop + MARGIN then
					falling += 1
					if railed[dir][m] or railed[dir][m - 1] or railed[dir][m + 1] then
						covered += 1
					end
				end
			end
			if most >= B.CornerDrop + MARGIN and falling > 0 then
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
				-- (a tight hairpin's island side takes no rail by design, T-333: TightHairpinTests)
				local island = false
				for _, e in sp.tight do
					if side == -e.dir and h.entry <= e.sOut and h.exit >= e.sIn then
						island = true
					end
				end
				if island then
					continue
				end
				local most, falling, covered = -math.huge, 0, 0
				for s = h.entry, h.exit, STEP do
					local d = dropAt(sp, f, s, side)
					most = math.max(most, d)
					if d >= B.FallDrop + MARGIN then
						falling += 1
						if sp:kRailAt(s, side) or sp:kRailAt(s - STEP, side) or sp:kRailAt(s + STEP, side) then
							covered += 1
						end
					end
				end
				if most >= B.HairpinDrop + MARGIN and falling > 0 then
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
	-- 5. CARVED APEXES (T-182, T-308): every stretch where a side's runoff is down to
	-- `CarvedGap`, the ground rising beside it all along, and no rail on that side
	for _, side in { -1, 1 } do
		local inA, a = false, 0
		for u = 0, sp.length, 2 do
			local carved = sp:runoffRaw(u, side) <= T.CarvedGap + 1e-6
			if carved and not inA then
				inA, a = true, u
			elseif not carved and inA then
				inA = false
				r.apexes += 1
				local worst, rail = -math.huge, false
				for v = a, u - 2, 2 do
					local d = dropAt(sp, f, v, side)
					worst = math.max(worst, if d == -math.huge then math.huge else d)
					rail = rail or sp:kRailAt(v, side) ~= nil
				end
				r.apexWorst = math.max(r.apexWorst, worst)
				if worst <= -(T.CarvedRise - MARGIN) then
					r.apexRising += 1
				end
				if rail then
					r.apexRailed += 1
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
			if len < B.MinRun - 1e-6 then
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
	RoadDressing.attach(again)
	again:extendTo(math.min(length, 8000))
	local copy = SplineGen.replay(gen.sections, nil, sp.fall, seed)
	local differ = 0
	for s = 0, math.min(sp.length, again.spline.length) - 1, 2 do
		for _, side in { -1, 1 } do
			local a0, a1 = sp:kRailAt(s, side)
			local b0, b1 = again.spline:kRailAt(s, side)
			local c0, c1 = copy:kRailAt(s, side)
			-- (the shorter road ends where it ends: a run still going there is cut at its tip)
			local tip = again.spline.length
			a1 = a1 and math.min(a1, tip)
			b1 = b1 and math.min(b1, tip)
			c1 = c1 and math.min(c1, tip)
			if a0 ~= b0 or a1 ~= b1 or a0 ~= c0 or a1 ~= c1 then
				differ += 1
			end
		end
	end
	r.differ = differ
	-- THE DRESSING NEVER CHANGES THE ROAD (T-327): the same seed laid with no dressing at all
	-- is the same road, field for field, and stands no barrier
	local bare = SplineGen.new(seed)
	bare:extendTo(math.min(length, 8000))
	local function same(a, b): boolean
		if a == nil or b == nil then
			return a == b
		end
		if #a ~= #b then
			return false
		end
		for i = 1, #a do
			if a[i] ~= b[i] then
				return false
			end
		end
		return true
	end
	local roadDiffer, bareRails = 0, 0
	for i, b in bare.sections do
		local a = gen.sections[i]
		local ok = a ~= nil and a.tag == b.tag and a.len == b.len
		for _, key in { "k", "g", "b", "rl", "rr", "up", "gl", "gv" } do
			ok = ok and same(a[key], b[key])
		end
		if not ok then
			roadDiffer += 1
		end
		if b.kr then
			bareRails += 1
		end
	end
	r.roadDiffer, r.bareSections, r.bareRails = roadDiffer, #bare.sections, bareRails
	local runs = r.runs
	table.insert(
		log,
		`seed {seed}: {math.floor(sp.length)} studs, {#runs} runs, {math.floor(r.railLen)} studs of rail ({fmt(r.railLen / sp.length * 100, 1)}% of the road's length), runs {fmt(runs[1] or 0, 0)} / {fmt(runs[(#runs + 1) // 2] or 0, 0)} / {fmt(r.railLen / math.max(#runs, 1), 0)} / {fmt(runs[#runs] or 0, 0)} studs (shortest, median, mean, longest); `
			.. `on falling drawn ground {r.drawnFalls} of {r.railPoints} points (least {fmt(r.drawnWorst, 1)} studs below the edge); `
			.. `steep corners {r.cornerCovered} of {r.corners} railed 90%+ (mean {fmt(r.cornerCovSum / math.max(r.corners, 1) * 100, 0)}%); `
			.. `hairpins {r.hairpins}, big-drop sides railed {r.hairpinRailed} of {r.hairpinSides}{if #r.hairpinMissed > 0 then " (missed " .. table.concat(r.hairpinMissed, ", ") .. ")" else ""}; tight edges {gen.stats.tight}; carved apexes {r.apexes}, on rising ground {r.apexRising}, on a railed side {r.apexRailed}`
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
		`{drawnFalls} of {points} rail points ({fmt(drawnFalls / math.max(points, 1) * 100, 1)}%); the drawn ground at least {fmt(worst, 1)} studs below the grass's edge {Config.Dressing.Barrier.Probe} studs out`
	)
	check(
		"K-rails only where the dressing reads a fall (FallDrop, read again off the laid road)",
		ownFalls >= points * 0.999,
		`{ownFalls} of {points} rail points (the generator reads the eased runoff and bank as straight lines: a point or two may differ by a few studs)`
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
	check("no run shorter than MinRun, none abutting another", short == 0 and abut == 0, `{short} short, {abut} abutting`)
	check("no K-rail on a grove's side", grove == 0, `{grove} rail points on a grove`)
	local apexes, apexRising, apexRailed = sum("apexes"), sum("apexRising"), sum("apexRailed")
	local apexWorst = -math.huge
	for _, r in all do
		apexWorst = math.max(apexWorst, r.apexWorst)
	end
	check(
		"carved apexes only where the ground rises, never on a railed side",
		apexes > 0 and apexRising == apexes and apexRailed == 0,
		`{apexes} apexes: {apexRising} with the ground rising {Config.Spline.Terrain.CarvedRise}+ studs all along (least rise {fmt(-apexWorst, 1)}), {apexRailed} on a railed side`
	)
	check("the same rails from the same seed and in a client's replay", differ == 0, `{differ} points differ`)
	local roadDiffer, bareSections, bareRails = sum("roadDiffer"), sum("bareSections"), sum("bareRails")
	check(
		"the dressing never changes the road: laid without it, every section is the same and unrailed",
		bareSections > 0 and roadDiffer == 0 and bareRails == 0,
		`{roadDiffer} of {bareSections} sections differ; {bareRails} railed with no dressing`
	)
	-- 7. AFTER A HAIRPIN (T-334): with only the tight-bend rule standing rails (no corner and no
	-- cliff rule), a hairpin's rail ends within `HairpinRunOut` of where the bend straightens
	-- (the road no tighter than `CornerRadius`), unless the next tight bend's lead-in reaches it
	do
		local B = Config.Dressing.Barrier
		local saved = { B.CliffDrop, B.CornerDrop }
		B.CliffDrop, B.CornerDrop = math.huge, math.huge
		local ok, gen = pcall(function()
			local g = SplineGen.new(HAIRPIN_SEED)
			RoadDressing.attach(g)
			g:extendTo(math.min(length, 30000))
			return g
		end)
		B.CliffDrop, B.CornerDrop = saved[1], saved[2]
		local sides, worst, over, detail = 0, -math.huge, 0, {}
		if ok then
			local sp = gen.spline
			local kCorner = 1 / B.CornerRadius
			local kTight = 0.95 / B.HairpinRadius -- (the dressing reads curvature off the knots, straight between them)
			for _, h in Hairpins.find(sp, 0, sp.length) do
				if not h.open then
					-- where it straightens, and whether another tight bend starts soon after
					local straight = h.exit
					while straight < sp.length and math.abs(sp:curvatureAt(straight)) >= kCorner and (sp:curvatureAt(straight) > 0) == (h.dir > 0) do
						straight += 1
					end
					local nextTight = false
					for u = straight, math.min(straight + B.LeadIn + B.HairpinRunOut + 30, sp.length), 2 do
						if math.abs(sp:curvatureAt(u)) >= kTight then
							nextTight = true
						end
					end
					for _, side in { -1, 1 } do
						local _, b = sp:kRailAt(h.exit, side)
						-- (a tight cliff edge's gravel just past the bend carries its own rail, the
						-- planner's (T-181): that is not the hairpin's run-out)
						local gravel = false
						if b then
							for u = straight, b, 2 do
								if sp:gravelAt(u, side) then
									gravel = true
									break
								end
							end
						end
						if b and not nextTight and not gravel and b < sp.length - 1 then
							sides += 1
							local past = b - straight
							worst = math.max(worst, past)
							if past > B.HairpinRunOut + B.Sample + 1 then
								over += 1
								table.insert(detail, `{math.floor(h.exit)}{if side < 0 then "L" else "R"} {fmt(past, 0)}`)
							end
						end
					end
				end
			end
		end
		check(
			"a hairpin's rail ends HairpinRunOut after the bend straightens",
			ok and sides > 0 and over == 0,
			if ok then `{sides} railed hairpin sides (seed {HAIRPIN_SEED}, corner and cliff rules off): at most {fmt(worst, 1)} studs past where the bend straightens (allowed {B.HairpinRunOut + B.Sample + 1}){if #detail > 0 then "; over: " .. table.concat(detail, ", ") else ""}` else tostring(gen)
		)
	end
	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = log }
end

return SplineGenTests
