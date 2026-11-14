--!nonstrict
-- T-203: bounded random lengths, physical transition budgets, stable streamed replay.
assert(game:GetService("RunService"):IsStudio(), "SplineBiomeTests is Studio only")
local Config = require(game.ReplicatedStorage.Shared.Config)
local Biome = require(game.ReplicatedStorage.Shared.Road.SplineBiome)
local Spline = require(game.ReplicatedStorage.Shared.Road.Spline)
local Gen = require(game.ReplicatedStorage.Shared.Road.SplineGen)
local Http = game:GetService("HttpService")
local Tests = {}

function Tests.run()
	local checks = {}
	local function check(name, ok, detail)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local C = Config.Spline.Biomes
	local a, b, different = Biome.new(31337), Biome.new(31337), Biome.new(101)
	a:extend(400000); b:extend(400000); different:extend(400000)
	check("one seed fixes the whole schedule", Http:JSONEncode(a.list) == Http:JSONEncode(b.list), "two independent schedules")
	check("different seeds change lengths and order", Http:JSONEncode(a.list) ~= Http:JSONEncode(different.list), "31337 versus 101")
	local lo, hi, plateau, worstRate = math.huge, 0, math.huge, 0
	local seen, transitions, repeated = {}, {}, 0
	for _, schedule in {a, different, Biome.new(2024)} do
		schedule:extend(400000)
		local list = schedule.list
		for i = 4, #list, 3 do
			local length, blend = list[i] - list[i - 3], list[i + 2]
			lo, hi = math.min(lo, length), math.max(hi, length)
			plateau = math.min(plateau, length - (list[i - 1] + blend) * 0.5)
			seen[math.floor(length)] = true
			local from, to = list[i - 2], list[i + 1]
			transitions[tostring(from) .. ":" .. tostring(to)] = true
			if from == to then repeated += 1 end
			for _, p in { {C.Rise, C.RiseRate}, {C.Drop, C.DropRate}, {C.Width, C.WidthRate} } do
				worstRate = math.max(worstRate, 1.5 * math.abs(p[1][to] - p[1][from]) / blend / p[2])
			end
		end
		task.wait()
	end
	local unique, directions = 0, 0
	for _ in seen do unique += 1 end
	for _ in transitions do directions += 1 end
	check("every semi-random length stays inside configured bounds", lo >= C.Length[1] and hi <= C.Length[2], `observed {lo} to {hi}`)
	check("lengths vary instead of repeating the sketch", unique > 200, `{unique} distinct whole-stud length bins`)
	check("every transition finishes with established ground before the next", plateau >= C.PlateauMin - 1e-6, `smallest plateau {plateau}`)
	check("real profile envelopes respect their change-rate budgets", worstRate <= 1 + 1e-6, `largest share of permitted rate {worstRate}`)
	check("all six category changes occur without identical neighbours", directions == 6 and repeated == 0, `{directions} directions, {repeated} duplicate neighbours`)
	local mix = {}
	local mixOk = true
	for kind = 1, 3 do
		mix[kind] = a.distance[kind] / a.total
		mixOk = mixOk and math.abs(mix[kind] - C.Weights[kind]) < 0.025
	end
	check("long-run distance remains near the intended mix", mixOk, Http:JSONEncode(mix))

	-- Cut sections deliberately through transition centres; appended road must retain
	-- exactly the same phase as the unsplit schedule, including on already emitted land.
	local streaming, received, s0, phaseGap = Biome.new(8080), nil, 0, 0
	local slices = { 37, 71, 193, 53, 211 }
	local count = 0
	while s0 < 12000 do
		count += 1
		local s1 = s0 + slices[(count - 1) % #slices + 1]
		received = Biome.merge(received, streaming:records(s0, s1), s0)
		for s = 0, s1, 31 do
			local f1, t1, u1 = Biome.at(received, s)
			local f2, t2, u2 = Biome.at(streaming.list, s)
			if f1 ~= f2 or t1 ~= t2 then phaseGap = math.huge end
			phaseGap = math.max(phaseGap, math.abs(u1 - u2))
		end
		s0 = s1
		if count % 20 == 0 then task.wait() end
	end
	check("streaming never restarts a transition or changes emitted ground", phaseGap == 0, `{count} irregular sections, phase difference {phaseGap}`)
	local boundary, blend = a.list[4], a.list[6]
	local maxJump = 0
	for _, s in { boundary - blend * 0.5, boundary, boundary + blend * 0.5 } do
		local left = Biome.mix(a.list, s - 1e-4, C.Rise, 0)
		local right = Biome.mix(a.list, s + 1e-4, C.Rise, 0)
		maxJump = math.max(maxJump, math.abs(right - left))
	end
	check("profile height is continuous at transition entry, centre and exit", maxJump < 0.001, `largest two-sided height difference {maxJump}`)
	local cloned = streaming:clone()
	local before = Http:JSONEncode(streaming.list)
	cloned:extend(streaming.total + 10000)
	check("speculative extension cannot consume the live schedule", before == Http:JSONEncode(streaming.list), "cloned records, counters and random streams")
	local snapshot = Http:JSONEncode(received)
	local bad = table.clone(received)
	bad[#bad] = 1
	local ok = pcall(Biome.merge, received, bad, s0)
	check("conflicting repeated records are refused without mutation", not ok and snapshot == Http:JSONEncode(received), "invalid replay leaves the prior schedule unchanged")
	local future = { received[#received - 2] + C.Length[2], 1, C.MaxBlend }
	if future[2] == received[#received - 1] then future[2] = 2 end
	local retro = pcall(Biome.merge, received, future, future[1])
	check("a newly arriving blend cannot reach back under a car", not retro, "new boundary introduced after its transition has started")
	local old = Spline.new()
	old:append({len=200,k={200,0},g={200,0},b={200,0}})
	check("older sections retain their explicit legacy default", old.biomes == nil and old:biomeAt(100) == nil, "no bm means unchanged pre-biome terrain")

	local gen = Gen.new(101)
	gen:extendTo(4000)
	local replay = Gen.replay(gen.sections, gen.spline.origin, gen.fall)
	local replayGap = 0
	for s = 0, gen.spline.length, 19 do
		local f1,t1,u1 = gen.spline:biomeAt(s)
		local f2,t2,u2 = replay:biomeAt(s)
		if f1 ~= f2 or t1 ~= t2 then replayGap = math.huge end
		replayGap = math.max(replayGap, math.abs(u1-u2))
	end
	check("server sections and late-join replay retain identical biome phase", replayGap == 0 and replay.biomes ~= nil, `phase gap {replayGap}, {#gen.sections} sections`)
	local passed = 0
	for _, c in checks do if c.ok then passed += 1 end end
	return { passed = passed, total = #checks, checks = checks }
end

return Tests
