--!nonstrict
-- SplineHillTests: the ground between the legs of the spline road
-- (features/continuous-mountain.md, T-190). Pure maths:
--   game.ServerStorage.DebugBridge:Invoke("DebugSplineHillTests", "run")
-- Takes a few seconds: from execute_luau, run it in a task.spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "SplineHillTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local SplineHill = require(ReplicatedStorage.Shared.Road.SplineHill)
local SplineMesh = require(ReplicatedStorage.Shared.Road.SplineMesh)

local Tests = {}

local SEEDS = { 31337, 101, 2024 }
local LENGTH = 12000
local TURNS = { turnaround = true, switchbackOut = true, double = true, doubleOut = true }
local WALL = 15 -- studs of ground over the driver's eye: a wall ahead, not a rise
local views -- (gen, into): the view ahead in each turnaround, below

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

local function run(check)
	local H = Config.Spline.Hill
	local half = Config.Road.Width * 0.5
	local L = Config.Spline.Mesh.ChunkLength

	local rays, met, alone = 0, 0, 0
	local seamWorst, seamOver, seams, eased = 0, 0, 0, 0
	local points, inRoad, poke, pokeFirst = 0, 0, 0, ""
	local capped, cappedLow = 0, 0
	local aboveLeg, facingRock = 0, 0
	local ctxMs, ctxN, stationsMost = 0, 0, 0
	local differ, compared = 0, 0
	-- the view ahead in a turnaround: is there a wall within 150 studs?
	local looks = { "as it begins", "45 degrees off the fall line", "pointing down the mountain" }
	local function tally()
		return { walled = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }, turns = { 0, 0, 0 }, tall = { 0, 0, 0 } }
	end
	local now = tally()

	for _, seed in SEEDS do
		local gen = SplineGen.new(seed)
		gen:extendTo(LENGTH)
		local sp = gen.spline
		local copy = SplineGen.replay(gen.sections, nil, gen.fall)
		for c = 0, math.floor(sp.length / L) - 1 do
			local s0, s1 = c * L, (c + 1) * L
			local t0 = os.clock()
			local ctx = SplineHill.context(sp, s0, s1, SplineMesh.profile)
			ctxMs += (os.clock() - t0) * 1000
			ctxN += 1
			stationsMost = math.max(stationsMost, #ctx.stations)
			local ctxCopy = if c % 6 == 0 then SplineHill.context(copy, s0, s1, SplineMesh.profile) else nil
			for s = s0, s1 - 1, 24 do
				for _, side in { -1, 1 } do
					local i = if side < 0 then 1 else 2
					local ray = SplineHill.ray(ctx, s, side)
					local kind = ray.st.kind[i]
					if kind == Spline.ROCK or kind == Spline.CLIFF then
						SplineHill.finish(ctx, ray)
						rays += 1
						local tEnd = SplineHill.faceEnd(ray)
						local cap = SplineHill.cap(ray)
						if cap < ray.st.nat[i] - 0.5 then
							capped += 1
							if cap < 12 then
								cappedLow += 1
							end
						end
						if ray.free then
							alone += 1
						else
							met += 1
						end
						-- 1. THE SEAM: where this ray's ground ends, the stretch on the other side
						-- of the line has the ground at the same height
						-- (the other stretch's own ray through that point, where it ends too). Not
						-- within `MeetOver` of the end of a ray's reach: two stretches that far
						-- apart each ease into the ground they would have alone, and the two sheets
						-- pass one over the other (counted, `eased`)
						if not ray.free and ray.clip - ray.st.w[i] >= H.Reach - H.MeetOver then
							eased += 1
						elseif not ray.free then
							local mine = SplineHill.at(ray, ray.clip)
							local past = SplineHill.at(ray, ray.clip + 1)
							local _, so, d = SplineHill.heightAt(ctx, past.X, past.Z)
							if so and d and math.abs(so - s) > 30 then
								local other = SplineHill.ray(ctx, so, if d < 0 then -1 else 1)
								if math.abs(math.abs(d) - other.clip) < 3 then
									SplineHill.finish(ctx, other)
									seams += 1
									local gap = math.abs(SplineHill.at(other, other.clip).Y - mine.Y)
									seamWorst = math.max(seamWorst, gap)
									if gap > 4 then
										seamOver += 1
									end
								end
							end
						end
						-- 2. NO GROUND ON A ROAD: no vertex of the hillside lies over any road's
						-- tarmac or runoff, this stretch's or another's
						local span = math.max(ray.clip - tEnd, 0)
						for _, share in H.Rings do
							local p = SplineHill.at(ray, tEnd + span * share)
							points += 1
							local so, d = sp:project(p.X, p.Z, half + 70)
							if so and d then
								local w = half + sp:runoffAt(so, if d < 0 then -1 else 1)
								if math.abs(d) < w - 0.5 then
									inRoad += 1
									if p.Y > sp:terrainY(so, d) - 0.25 then
										poke += 1
										if pokeFirst == "" then
											pokeFirst = `; first seed {seed} ray at {s} side {side}, over the road at {math.floor(so)}`
										end
									end
								end
							end
						end
						-- 3. A ROCK FACE NEVER STANDS OVER THE LEG ABOVE IT: where it faces
						-- another stretch's drop within 150 studs, its crest is no higher than that
						-- road's edge (but for the few studs it always keeps)
						if kind == Spline.ROCK and not ray.free and ray.clip < 150 then
							local edge = SplineHill.at(ray, ray.clip + 1)
							local _, so, d = SplineHill.heightAt(ctx, edge.X, edge.Z)
							local theirSide = if d and d < 0 then -1 else 1
							if so and d and math.abs(so - s) > 30 and sp:edgeAt(so, theirSide) == Spline.CLIFF then
								facingRock += 1
								local crest = ray.st.yEnd[i]
								local w = half + sp:runoffAt(so, theirSide)
								local theirEdge = sp:terrainY(so, theirSide * w)
								if crest > math.max(theirEdge, ray.st.y0[i]) + H.MinRock + 0.5 then
									aboveLeg += 1
								end
							end
						end
						-- 4. A client's replay draws the same hillside
						if ctxCopy then
							local other = SplineHill.ray(ctxCopy, s, side)
							SplineHill.finish(ctxCopy, other)
							compared += 1
							if other.clip ~= ray.clip or other.meet ~= ray.meet or SplineHill.cap(other) ~= cap then
								differ += 1
							end
						end
					end
				end
			end
			task.wait()
		end
		-- 5. THE VIEW AHEAD IN A TURNAROUND
		-- From three places in each: where it begins, where the road is 45 degrees off the
		-- fall line, and where it points straight along it. Ground off the road, more than
		-- `WALL` studs over the eye, within 150 studs straight ahead. A turn the mountain
		-- changes sides in (a valley's floor, a pass) is counted apart: at a valley's floor
		-- the far side does rise ahead
		views(gen, now)
	end
	-- and the same roads with every face at its full height right through the turn, as they
	-- were drawn before T-190: for the comparison
	local wasPower, wasTaper = H.AcrossPower, H.TaperRate
	H.AcrossPower, H.TaperRate = 0, 1e9
	local before = tally()
	local okBefore, errBefore = pcall(function()
		for _, seed in SEEDS do
			local gen = SplineGen.new(seed)
			gen:extendTo(LENGTH)
			views(gen, before)
		end
	end)
	H.AcrossPower, H.TaperRate = wasPower, wasTaper
	if not okBefore then
		error(errBefore)
	end

	check("the hillside is drawn", rays > 0 and met > 0 and alone > 0, `{rays} rays: {met} meet another stretch, {alone} run their whole reach`)
	check(
		"two stretches' ground meets at the same height",
		seams > 0 and seamOver <= seams * 0.02,
		`{seams} seams: worst {fmt(seamWorst)} studs apart, {seamOver} more than 4; {eased} more rays end within {H.MeetOver} studs of their reach, easing apart`
	)
	check("no hillside over a road", points > 0 and poke == 0, `{points} vertices: {inRoad} over a road's ground, {poke} above it{pokeFirst}`)
	check("a rock face stays under the leg above", facingRock > 0 and aboveLeg == 0, `{aboveLeg} of {facingRock} rock faces under a drop within 150 studs stand above its edge`)
	check("faces are capped near another leg", capped > 0, `{capped} of {rays} faces capped, {cappedLow} of them under 12 studs`)
	check("a client's replay has the same hillside", compared > 0 and differ == 0, `{differ} of {compared} rays differ`)
	check(
		"gathering a chunk's stations is cheap",
		ctxMs / math.max(ctxN, 1) < 15,
		`{fmt(ctxMs / math.max(ctxN, 1))} ms a chunk on average, {stationsMost} stations at most`
	)
	-- a measure, not a rule: reported so each change can be compared with the last
	local names = { "on the way down the mountain", "climbing the far side of a valley", "where the mountain changes sides (a valley's floor, a pass)" }
	local rows = {}
	for class, name in names do
		local parts = {}
		for li, look in looks do
			table.insert(parts, `{look} {now.walled[class][li]} (before {before.walled[class][li]})`)
		end
		table.insert(rows, `of {now.turns[class]} {name}: {table.concat(parts, ", ")}; tallest {fmt(now.tall[class], 0)} (before {fmt(before.tall[class], 0)})`)
	end
	check(
		"the view ahead in a turnaround (measured)",
		now.turns[1] > 0,
		`turnarounds with ground more than {WALL} studs over the eye within 150 studs straight ahead, off the road; "before" is with every face at full height through the turn. {table.concat(rows, ". ")}`
	)
end

-- 5. THE VIEW AHEAD IN A TURNAROUND, tallied into `into`.
function views(gen, into)
	local sp = gen.spline
	local half = Config.Road.Width * 0.5
	do
		for _, t in gen.turns do
			if TURNS[t[3]] then
				local floor = false
				for _, f in gen.flips do
					if f[1] >= t[1] and f[1] <= t[2] then
						floor = true
					end
				end
				local sCross, least, s45 = t[1], math.huge, nil
				for s = t[1], t[2], 2 do
					local a = math.abs(math.sin(sp:yawAt(s) - gen.fall))
					if a < least then
						sCross, least = s, a
					end
					if not s45 and a < 0.707 then
						s45 = s
					end
				end
				local at = { t[1], s45 or t[1], sCross }
				-- which kind of turnaround: 1 on the way down the mountain, 2 on the climb up
				-- the far side of a valley (the mountain it climbs is ahead), 3 the turn the
				-- mountain changes sides in
				local flip = 1
				for _, f in gen.flips do
					if f[1] <= t[1] then
						flip = f[2]
					end
				end
				local class = if floor then 3 elseif flip < 0 then 2 else 1
				into.turns[class] += 1
				for li = 1, 3 do
					local s = at[li]
					local ctx = SplineHill.context(sp, s - 60, s + 60, SplineMesh.profile)
					local x, z = sp:planAt(s)
					local yaw = sp:yawAt(s)
					local eye = sp:heightAt(s) + 5
					local fx, fz = -math.sin(yaw), -math.cos(yaw)
					local tall = 0
					for dist = 8, 150, 6 do
						local y, so, d = SplineHill.heightAt(ctx, x + fx * dist, z + fz * dist)
						if y and so and d and math.abs(d) > half + sp:runoffAt(so, if d < 0 then -1 else 1) then
							tall = math.max(tall, y - eye)
						end
					end
					if tall > WALL then
						into.walled[class][li] += 1
						into.tall[class] = math.max(into.tall[class], tall)
					end
				end
			end
		end
	end
end

function Tests.run(...)
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local ok, err = pcall(run, check)
	if not ok then
		check("the hillside tests ran", false, tostring(err))
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
