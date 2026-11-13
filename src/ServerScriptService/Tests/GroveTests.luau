--!nonstrict
-- GroveTests: the groves on the spline road's flatter stretches (features/mountain-road.md
-- "Groves", T-183). Pure maths, plus the car's world against a trunk:
--   game.ServerStorage.DebugBridge:Invoke("DebugGroveTests", "run")
-- Takes a few seconds: from execute_luau, run it in a task.spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "GroveTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local SplineGrove = require(ReplicatedStorage.Shared.Road.SplineGrove)

local Tests = {}

local SEEDS = { 101, 2024, 8080, 31337, 777 }
local LENGTH = 20000

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 2) .. "f", x)
end

local function run(check)
	local T = Config.Spline.Terrain
	local half = Config.Road.Width * 0.5
	local chunkL = Config.Spline.Mesh.ChunkLength

	-- 1. Where the groves go, over long roads
	local total, groveLen, stretches, sections, groveSections = 0, 0, 0, 0, 0
	local steep, short, tight, railed, wideMost = 0, 0, 0, 0, 0
	local trees, onTarmac, tooClose, pastEdge, conifers, broadleaves, bushes = 0, 0, 0, 0, 0, 0, 0
	local perChunk, chunksWith, chunkMost = 0, 0, 0
	local gens = {}
	for _, seed in SEEDS do
		local gen = SplineGen.new(seed)
		gen:extendTo(LENGTH)
		gens[seed] = gen
		local sp = gen.spline
		total += sp.length
		local s0 = 0
		local open = { [-1] = false, [1] = false }
		for _, sec in gen.sections do
			sections += 1
			local here = {}
			if sec.gv then
				groveSections += 1
				for j = 1, #sec.gv, 2 do
					here[sec.gv[j]] = true
				end
				-- flat and gentle, from the knots themselves
				local kMost, gMost = math.abs(sp:curvatureAt(s0 + 1e-6)), math.abs(sp:gradeAt(s0 + 1e-6))
				for j = 1, #sec.k, 2 do
					kMost = math.max(kMost, math.abs(sec.k[j + 1]))
				end
				for j = 1, #sec.g, 2 do
					gMost = math.max(gMost, math.abs(sec.g[j + 1]))
				end
				if kMost > 1 / T.GroveMinRadius + 1e-9 then
					tight += 1
				end
				if gMost > math.tan(math.rad(T.GroveMaxGrade)) + 1e-9 then
					steep += 1
				end
				if sec.len < T.GroveMinLength then
					short += 1
				end
				if sec.kr then
					for j = 1, #sec.kr, 3 do
						if here[sec.kr[j + 2]] then
							railed += 1
						end
					end
				end
			end
			for _, side in { -1, 1 } do
				if here[side] then
					groveLen += sec.len
					if not open[side] then
						stretches += 1
					end
					for u = s0, s0 + sec.len, 4 do
						wideMost = math.max(wideMost, sp:runoffAt(u, side))
					end
				end
				open[side] = here[side] == true
			end
			s0 += sec.len
		end
		-- the trees, chunk by chunk as a client draws them
		for c = 0, math.floor(sp.length / chunkL) - 1 do
			local a, b = c * chunkL, (c + 1) * chunkL
			local items = SplineGrove.items(sp, a, b, -1)
			SplineGrove.items(sp, a, b, 1, items)
			if #items > 0 then
				chunksWith += 1
				perChunk += #items
				chunkMost = math.max(chunkMost, #items)
			end
			for _, it in items do
				trees += 1
				if it.kind == SplineGrove.CONIFER then
					conifers += 1
				elseif it.kind == SplineGrove.BROADLEAF then
					broadleaves += 1
				else
					bushes += 1
				end
				local s, d = sp:project(it.x, it.z, half + 80)
				if s and d then
					local e = math.abs(d) - half
					if e <= 0 then
						onTarmac += 1
					end
					local setback = if it.kind == SplineGrove.BUSH then T.BushSetback else T.TreeSetback
					if e < setback - 0.01 then
						tooClose += 1
					end
					if e > sp:runoffAt(s, it.side) + 0.01 then
						pastEdge += 1
					end
				end
			end
		end
	end
	local per10k = stretches / total * 10000
	check(
		"groves on flatter stretches",
		groveSections > 0 and per10k >= 2,
		`{stretches} grove stretches over {math.floor(total)} studs: {fmt(per10k, 1)} per 10 000 studs; {fmt(groveLen / (2 * total) * 100, 1)}% of the road's sides; {groveSections} of {sections} sections`
	)
	check("only where the road is flat and gentle", steep == 0 and tight == 0 and short == 0, `{steep} too steep, {tight} too tight, {short} too short`)
	check(
		"the wide runoff never needs more clearance than the road keeps",
		T.GroveRunoff[2] <= T.RunoffMax + Config.Spline.ClearanceGap and wideMost <= T.RunoffMax + Config.Spline.ClearanceGap + 1e-6,
		`widest grove grass {fmt(wideMost, 1)} studs; the most the no-crossing gap allows {T.RunoffMax + Config.Spline.ClearanceGap}`
	)
	check("no K-rail on a grove's side", railed == 0, `{railed}`)
	check(
		"trees set back from the tarmac, on the grass",
		trees > 0 and onTarmac == 0 and tooClose == 0 and pastEdge == 0,
		`{trees} items ({conifers} conifers, {broadleaves} broadleaves, {bushes} bushes): {onTarmac} on the tarmac, {tooClose} inside their setback, {pastEdge} past the grass's edge. A chunk with a grove holds {fmt(perChunk / math.max(chunksWith, 1), 1)} on average, {chunkMost} at most; {chunksWith} of {math.floor(total / chunkL)} chunks have one`
	)

	-- 2. A client's replay places the same trees
	do
		local gen = gens[SEEDS[1]]
		local copy = SplineGen.replay(gen.sections)
		local a = SplineGrove.items(gen.spline, 0, LENGTH, -1)
		SplineGrove.items(gen.spline, 0, LENGTH, 1, a)
		local b = SplineGrove.items(copy, 0, LENGTH, -1)
		SplineGrove.items(copy, 0, LENGTH, 1, b)
		local worst = 0
		for i = 1, math.min(#a, #b) do
			worst = math.max(worst, math.abs(a[i].x - b[i].x) + math.abs(a[i].y - b[i].y) + math.abs(a[i].z - b[i].z) + math.abs(a[i].h - b[i].h))
		end
		check("a client's replay places the same trees", #a == #b and worst < 1e-6, `{#a} and {#b} items, worst difference {string.format("%.1e", worst)} studs`)
	end

	-- 3. Groves change nothing else the road chooses
	do
		local saved = T.GroveChance
		T.GroveChance = 0
		local ok, plain = pcall(function()
			local g = SplineGen.new(SEEDS[2])
			g:extendTo(LENGTH)
			return g
		end)
		T.GroveChance = saved
		local with = gens[SEEDS[2]]
		local differ, droppedRails = 0, 0
		if ok then
			for i = 1, math.min(#plain.sections, #with.sections) do
				local x, y = plain.sections[i], with.sections[i]
				for _, key in { "k", "g", "b", "el", "er" } do
					local p, q = x[key], y[key]
					if #p ~= #q then
						differ += 1
					else
						for j = 1, #p do
							if p[j] ~= q[j] then
								differ += 1
								break
							end
						end
					end
				end
				if x.kr and not y.kr then
					droppedRails += 1
				end
			end
		end
		check(
			"a grove changes nothing else the road chooses",
			ok and differ == 0 and #plain.sections == #with.sections,
			if ok then `{differ} sections' curve or edges differ, over {#with.sections}; {droppedRails} K-rails dropped on a grove's side` else tostring(plain)
		)
	end

	-- 4. The car's world: a trunk stops the car's box, and one inside it is pushed out
	do
		local SplineWorld = require(StarterPlayer.StarterPlayerScripts:WaitForChild("Drift"):WaitForChild("SplineWorld"))
		local Model = require(StarterPlayer.StarterPlayerScripts.Drift.Model)
		local gen = gens[SEEDS[1]]
		local sp = gen.spline
		local world = SplineWorld.new(sp, nil)
		local D = Config.Drift
		local tried, stopped, worstGap, pushedOut, pushTried = 0, 0, 0, 0, 0
		local all = SplineGrove.items(sp, 0, LENGTH, -1)
		SplineGrove.items(sp, 0, LENGTH, 1, all)
		local t0 = os.clock()
		local sweeps = 0
		for _, it in all do
			if it.trunk > 0 and tried < 60 then
				-- drive straight along the road at the trunk, from 12 studs back
				local yaw = sp:yawAt(it.s)
				local fwd = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
				local y = it.y + D.RideHeight
				local from = Vector3.new(it.x, y, it.z) - fwd * 12
				local to = from + fwd * 10
				world.locate(from)
				-- only from somewhere clear: in a dense grove the start may be inside another tree
				local f0, r0 = Model.axes(yaw)
				local startDepth = SplineGrove.push(sp, it.s, from, f0, r0, D.BodyWidth * 0.5 + 0.5, D.BodyLength * 0.5 + 0.5, 1, 0)
				if startDepth > 0 then
					continue
				end
				tried += 1
				local before = world.stats.treeStops
				local safe = world.sweep(from, to, yaw)
				sweeps += 1
				if safe and world.stats.treeStops > before then
					stopped += 1
					-- the box where it stopped: clear of the trunk, and close to it
					local f, r = Model.axes(yaw)
					local depth = SplineGrove.push(sp, it.s, Vector3.new(safe.X, y, safe.Z), f, r, D.BodyWidth * 0.5, D.BodyLength * 0.5, 1, 0)
					worstGap = math.max(worstGap, depth)
				end
				-- a box sat on the trunk is pushed out
				pushTried += 1
				local inside = Vector3.new(it.x, y, it.z) - fwd * (D.BodyLength * 0.5)
				world.locate(inside)
				local dir, depth = world.penetration(inside, yaw)
				if dir and depth > 0 then
					pushedOut += 1
				end
			end
		end
		local us = (os.clock() - t0) / math.max(sweeps, 1) * 1e6
		check(
			"a tree trunk stops the car",
			tried > 0 and stopped == tried and worstGap < 0.05,
			`{stopped} of {tried} drives at a trunk stopped by it; deepest the box ended inside one {fmt(worstGap, 3)} studs`
		)
		check("a car inside a trunk is pushed out", pushTried > 0 and pushedOut == pushTried, `{pushedOut} of {pushTried}`)
		check("a trunk check is cheap", us < 400, `{fmt(us, 0)} microseconds for a sweep and a push near a grove`)
	end

	-- 5. A malformed grove is refused
	do
		local bad = {
			{ len = 100, k = { 100, 0 }, g = { 100, 0 }, b = { 100, 0 }, gv = { 2, 5 } },
			{ len = 100, k = { 100, 0 }, g = { 100, 0 }, b = { 100, 0 }, gv = { 1, 5, 1, 6 } },
			{ len = 100, k = { 100, 0 }, g = { 100, 0 }, b = { 100, 0 }, gv = { 1 } },
			{ len = 100, k = { 100, 0 }, g = { 100, 0 }, b = { 100, 0 }, gv = { -1, 0.5 } },
		}
		local refused = 0
		for _, sec in bad do
			local sp = Spline.new()
			if not pcall(sp.append, sp, sec) then
				refused += 1
			end
		end
		check("a malformed grove is refused", refused == #bad, `{refused} of {#bad}`)
	end
end

function Tests.run(...)
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local ok, err = pcall(run, check)
	if not ok then
		check("groves ran", false, tostring(err))
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
