--!nonstrict
-- TightHairpinTests: the touge hairpin with its legs side by side and the island between them
-- (features/tight-hairpins.md step 2, T-333; `Road/TightHairpin`).
--
--   require(game.ServerScriptService.Tests.TightHairpinTests).run()   -- pure: Edit works
--   ...run({ drive = false })                                          -- skip the drives
--
-- 1. THE SHAPE on a hand-laid road, both ways round: its tightest bend, the legs' centre lines
--    side by side, and the leg out clear of the leg in where the shape ends.
-- 2. THE ISLAND: its narrowest gap between the legs' edges and its steepest slope.
-- 3. ITS EDGES: the ground every 2 studs along both inner edges, just off the tarmac, meets
--    the tarmac's edge; just on the tarmac it is under it (no ground through the road).
-- 4. NO CLIFF: a grid over the island and where it hands back, each step between neighbours.
-- 5. REPLAY: the section sent as JSON and laid again keeps the island.
-- 6. THE CAR round it: the real drift model on the road's maths (`Drift/SplineWorld`),
--    TightTurnTests' driver, 58 ways from 60 and 90 studs/s.
-- 7. ON THE ROAD: the planner (`SplineGen`) over several seeds: every tight hairpin it lays,
--    how far apart they come, each island's narrowest and steepest, the legs' heights apart,
--    the ground at both inner edges, and the planner's time per section.
--
-- `run()` returns `{ passed, checks, log }`.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "TightHairpinTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)
local TightHairpin = require(ReplicatedStorage.Shared.Road.TightHairpin)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)

local SEEDS = { 7, 101, 2024, 8080, 777, 31337 }
local LENGTH = 30000

local Tests = {}

local SEED = 7
local GRADE = -0.06
local CLEAR = 158

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

-- A road: 300 studs falling at GRADE, the tight hairpin turning `dir`, 300 more.
local function road(dir: number)
	local origin = { x = 0, y = 500, z = 0, yaw = 0 }
	local sp = Spline.new(origin)
	sp.mountain = Ground.field(SEED, origin, 0)
	sp:append({ len = 300, k = { 300, 0 }, g = { 40, GRADE, 300, GRADE }, b = { 300, 0 } })
	local s0 = sp.length
	local sec = TightHairpin.build(0, GRADE, 0, dir, math.rad(30), GRADE, CLEAR)
	sp:append(sec)
	sp:append({ len = 300, k = { 300, 0 }, g = { 300, GRADE }, b = { 300, 0 } })
	return sp, sec, s0
end

local function run(check, log, opts)
	local C = Config.TightHairpin
	local half = Config.Road.Width * 0.5
	local under = Config.Spline.Ground.Under
	for _, dir in { 1, -1 } do
		local way = if dir > 0 then "left" else "right"
		local sp, sec, s0 = road(dir)
		local e = sp.tight[1]
		check(`{way}: the road keeps the hairpin`, #sp.tight == 1 and e ~= nil and math.abs(e.sA - (s0 + sec.th[2])) < 1e-6, `{#sp.tight} kept`)

		-- 1. the shape
		local kmax = 0
		for s = s0, s0 + sec.len, 1 do
			kmax = math.max(kmax, math.abs(sp:curvatureAt(s)))
		end
		local lo, hi = math.huge, 0
		for u = 0, C.Parallel, 4 do
			local ax, az = sp:planAt(e.sA - u)
			local bx, bz = sp:planAt(e.sB + u)
			local d = math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
			lo, hi = math.min(lo, d), math.max(hi, d)
		end
		check(`{way}: the turn is {C.Radius} studs`, math.abs(1 / kmax - C.Radius) < 0.5, `tightest {fmt(1 / kmax, 2)} studs, {fmt(sec.len, 0)} studs of shape`)
		check(`{way}: the legs run side by side`, hi - lo < 1 and lo > 2 * C.Radius - 2 and lo < 2 * C.Radius + 6, `centre lines {fmt(lo, 1)} to {fmt(hi, 1)} apart over {C.Parallel} studs`)
		-- the leg out at the shape's end, from the leg in's line
		local ax, az = sp:planAt(e.sIn)
		local bx, bz = sp:planAt(e.sA)
		local lx, lz = bx - ax, bz - az
		local ll = math.sqrt(lx * lx + lz * lz)
		local ex, ez = sp:planAt(s0 + sec.len)
		local across = math.abs((ex - ax) * lz / ll - (ez - az) * lx / ll)
		check(`{way}: the leg out ends clear of the leg in`, across >= math.max(CLEAR, Config.Road.Width + C.IslandGone) - 1, `{fmt(across, 0)} studs from its line (clearance {CLEAR})`)

		-- 2. the island
		local isl = TightHairpin.island(sp, e)
		local steep, narrow = TightHairpin.measure(isl)
		check(`{way}: the island is at least 10 studs across`, narrow >= 10, `narrowest {fmt(narrow, 1)} studs between the legs' edges`)
		check(`{way}: the island is a bank, not a wall`, steep <= C.IslandMaxSlope, `steepest {fmt(steep, 1)} degrees (bar {C.IslandMaxSlope})`)
		local tipDrop = sp:heightAt(e.sA) - sp:heightAt(e.sB)
		local farDrop = sp:heightAt(e.sIn) - sp:heightAt(e.sOut)
		table.insert(log, `{way}: legs {fmt(tipDrop, 1)} studs apart in height at the turn, {fmt(farDrop, 1)} at the end of the side by side run`)

		-- 3. the edges
		local ctx = Ground.context(sp.mountain, sp, isl.minX - 80, isl.minZ - 80, isl.maxX + 80, isl.maxZ + 80)
		local worstEdge, worstThrough, edgeAt, n = 0, -math.huge, "", 0
		local d = -dir * half
		for s = e.sIn, e.sOut, 2 do
			local cx, cz = sp:planAt(s)
			local yaw = sp:yawAt(s)
			local rx, rz = math.cos(yaw), -math.sin(yaw)
			local edgeY = sp:surface(s, d).Y - under
			-- just off the tarmac, on the island
			local ox, oz = cx + rx * (d - dir * 0.3), cz + rz * (d - dir * 0.3)
			local y = Ground.at(ctx, ox, oz)
			local gap = math.abs(y - edgeY)
			n += 1
			if gap > worstEdge then
				worstEdge, edgeAt = gap, fmt(s - e.sA, 0)
			end
			-- just on the tarmac
			local ix, iz = cx + rx * (d + dir * 1), cz + rz * (d + dir * 1)
			local yi = Ground.at(ctx, ix, iz)
			worstThrough = math.max(worstThrough, yi - (sp:heightAt(s) - under))
		end
		check(`{way}: the island meets the tarmac's edge`, worstEdge < 0.6, `worst {fmt(worstEdge, 2)} studs off the edge, {fmt(edgeAt)} studs from the turn ({n} points)`)
		check(`{way}: no ground through the tarmac beside the island`, worstThrough < 0.05, `highest {fmt(worstThrough, 3)} studs above the road's underside`)
		-- 3b. drawn as ground, not runoff: the client's mesh classes a point by how far past the
		-- runoff's edge `Ground.at` says it is (its third answer) and puts a point it takes for
		-- runoff level with the nearer edge. Across the island, from a quarter to three
		-- quarters of the way, that is the distance to the nearer leg's tarmac (no runoff on
		-- the island side), never 0
		do
			local worstE, eAt, m = math.huge, "", 0
			for s = e.sIn + 4, e.sA, 8 do
				local cx, cz = sp:planAt(s)
				local yaw = sp:yawAt(s)
				local rx, rz = math.cos(yaw), -math.sin(yaw)
				local ex, ez = cx + rx * d, cz + rz * d
				for _, f in { 0.25, 0.5, 0.75 } do
					-- (toward the other leg, square to this one: the island is about 31 across)
					local across = 31.2 * f
					local px, pz = ex - rx * dir * across, ez - rz * dir * across
					local _, w = TightHairpin.islandAt(isl, px, pz)
					if w >= 1 then
						local _, _, past = Ground.at(ctx, px, pz)
						local want = math.min(across, 31.2 - across)
						m += 1
						local ratio = past / want
						if ratio < worstE then
							worstE, eAt = ratio, `{fmt(s - e.sA, 0)} from the turn, {fmt(across, 0)} across: {fmt(past, 1)} past the edge for {fmt(want, 1)}`
						end
					end
				end
			end
			check(`{way}: the island is drawn as ground, not runoff`, m > 0 and worstE > 0.7, `{m} points; worst {eAt}`)
		end

		-- 4. no cliff: neighbours on a grid over the island, its hand-back and round it
		local bx0, bx1, bz0, bz1 = math.huge, -math.huge, math.huge, -math.huge
		for _, side in { { isl.ly, isl.lx }, { isl.ry, isl.rx } } do
			for i, ly in side[1] do
				if ly <= isl.yFull + 220 then
					local wx = isl.ox + side[2][i] * isl.xx + ly * isl.yx
					local wz = isl.oz + side[2][i] * isl.xz + ly * isl.yz
					bx0, bx1, bz0, bz1 = math.min(bx0, wx), math.max(bx1, wx), math.min(bz0, wz), math.max(bz1, wz)
				end
			end
		end
		local step, worstJump, jumpAt = 1.5, 0, ""
		local prevRow = nil
		for z = bz0 - 20, bz1 + 20, step do
			local row = {}
			local prev = nil
			local col = 0
			for x = bx0 - 20, bx1 + 20, step do
				local y = Ground.at(ctx, x, z)
				-- (only the ground: on the tarmac the road draws itself)
				local s, dd = sp:project(x, z, 80)
				local onRoad = s and dd and math.abs(dd) < half
				-- (only where the island has a say: the cuts and fills beside the road are the
				-- mountain's, walls on steep ground by design, and GroundTests' to judge)
				-- (wholly the island only: this road is laid by hand, not fitted to the mountain,
				-- so where the island hands back the mountain can be anywhere; on the planner's
				-- roads, below, the hand-back is judged too)
				local _, w = TightHairpin.islandAt(isl, x, z)
				local v = if onRoad or w < 1 then nil else y
				col += 1
				row[col] = v
				if v and prev then
					local j = math.abs(v - prev) / step
					if j > worstJump then
						worstJump, jumpAt = j, `({fmt(x, 0)}, {fmt(z, 0)})`
					end
				end
				prev = v
			end
			if prevRow then
				for i, v in row do
					local u = prevRow[i]
					if v and u and math.abs(v - u) / step > worstJump then
						worstJump = math.abs(v - u) / step
						jumpAt = `({fmt(bx0 - 20 + (i - 1) * step, 0)}, {fmt(z, 0)}) across`
					end
				end
			end
			prevRow = row
			task.wait()
		end
		local bar = math.tan(math.rad(math.max(C.IslandMaxSlope, Config.Spline.Ground.SlopeSteep) + 15))
		check(`{way}: no cliff in the ground round the island`, worstJump <= bar, `steepest step {fmt(worstJump, 2)} studs a stud at {jumpAt} (bar {fmt(bar, 2)})`)

		-- 5. replay
		local again = Spline.new(sp.origin)
		for _, s in { { len = 300, k = { 300, 0 }, g = { 40, GRADE, 300, GRADE }, b = { 300, 0 } }, HttpService:JSONDecode(HttpService:JSONEncode(sec)) } do
			again:append(s)
		end
		local f = again.tight[1]
		check(`{way}: a client laying the section again has the same island`, f ~= nil and math.abs(f.sA - e.sA) < 1e-6 and math.abs(f.sOut - e.sOut) < 1e-6 and f.dir == e.dir, if f then `sA {fmt(f.sA, 2)} vs {fmt(e.sA, 2)}` else "none")
	end

	-- 7. on the road
	if opts.seeds ~= false then
		local total, lines, gaps, worstSteep, minNarrow, worstEdge, worstMs, sumMs, secs = 0, {}, {}, 0, math.huge, 0, 0, 0, 0
		local islandRails, outsideRailed = 0, 0
		local worstStep, stepAt = 0, ""
		local stepBar = math.tan(math.rad(math.max(C.IslandMaxSlope, Config.Spline.Ground.SlopeSteep) + 15))
		for _, seed in opts.seedList or SEEDS do
			local gen = SplineGen.new(seed)
			gen:extendTo(opts.length or LENGTH)
			local sp = gen.spline
			local st = gen.stats
			worstMs = math.max(worstMs, st.worstMs)
			sumMs += st.totalMs
			secs += st.sections
			local why = {}
			for k, n in st.tightWhy do
				table.insert(why, `{n} {k}`)
			end
			local at = {}
			local prev = nil
			for _, e in sp.tight do
				total += 1
				if prev then
					table.insert(gaps, e.sIn - prev)
				end
				prev = e.sOut
				local isl = TightHairpin.island(sp, e)
				local steep, narrow = TightHairpin.measure(isl)
				-- the rails: none on the island's side; the turn's outside as any hairpin's
				islandRails += #sp:kRailsIn(e.sIn + 1, e.sFree - 1, -e.dir) // 2
				-- no cliff where the island has a say, its hand-back included: a 2-stud grid. A step
				-- counts only where the island makes it, steeper than the same step in the ground
				-- the road would have without the island (the legs' own cuts and fills are any
				-- road's, and steep where the mountain is: a cut past an island's faded edge is not
				-- the island's)
				do
					local gctx = Ground.context(gen.ground, sp, isl.minX, isl.minZ, isl.maxX, isl.maxZ)
					local bare = Ground.context(gen.ground, sp, isl.minX, isl.minZ, isl.maxX, isl.maxZ)
					bare.islands = {}
					local prevRow = nil
					local function step(v, u, gx, gz)
						local s1 = math.abs(v[1] - u[1]) / 2
						if s1 > worstStep and s1 > math.abs(v[2] - u[2]) / 2 + 0.1 then
							worstStep, stepAt = s1, ` at ({fmt(gx, 0)}, {fmt(gz, 0)}) seed {seed}`
						end
					end
					for gz = isl.minZ, isl.maxZ, 2 do
						local row, prev = {}, nil
						local i = 0
						for gx = isl.minX, isl.maxX, 2 do
							i += 1
							local _, w = TightHairpin.islandAt(isl, gx, gz)
							local v = nil
							if w > 0 then
								local ps, pd = sp:project(gx, gz, 80)
								if not (ps and pd and math.abs(pd) < half) then
									v = { (Ground.at(gctx, gx, gz)), (Ground.at(bare, gx, gz)) }
								end
							end
							row[i] = v
							if v and prev then
								step(v, prev, gx, gz)
							end
							local u = prevRow and prevRow[i]
							if v and u then
								step(v, u, gx, gz)
							end
							prev = v
						end
						prevRow = row
						if gz % 40 < 2 then
							task.wait()
						end
					end
				end
				if #sp:kRailsIn(e.sA, e.sB, e.dir) > 0 then
					outsideRailed += 1
				end
				worstSteep, minNarrow = math.max(worstSteep, steep), math.min(minNarrow, narrow)
				local ctx = Ground.context(gen.ground, sp, isl.minX - 20, isl.minZ - 20, isl.maxX + 20, isl.maxZ + 20)
				local d = -e.dir * half
				for s = e.sIn, e.sOut, 4 do
					local cx, cz = sp:planAt(s)
					local yaw = sp:yawAt(s)
					local rx, rz = math.cos(yaw), -math.sin(yaw)
					local y = Ground.at(ctx, cx + rx * (d - e.dir * 0.3), cz + rz * (d - e.dir * 0.3))
					worstEdge = math.max(worstEdge, math.abs(y - (sp:surface(s, d).Y - under)))
				end
				table.insert(at, `{fmt(e.sA, 0)} ({if e.dir > 0 then "L" else "R"}, {fmt(sp:heightAt(e.sA) - sp:heightAt(e.sB), 1)}/{fmt(sp:heightAt(e.sIn) - sp:heightAt(e.sOut), 1)} high, {fmt(steep, 0)} deg, {fmt(narrow, 0)} wide)`)
				task.wait()
			end
			table.insert(lines, `seed {seed}: {#sp.tight} tight at {table.concat(at, ", ")}; {st.turnarounds} turnarounds; refused {st.tightRefused} ({table.concat(why, ", ")}); turns asked {table.concat(st.tightTurns, " ")}; {table.concat(st.tightNotes, "; ")}; {if st.stalled then "STALLED" else "ran"} to {fmt(sp.length, 0)}`)
			task.wait()
		end
		for _, l in lines do
			table.insert(log, l)
		end
		local minGap = math.huge
		for _, g in gaps do
			minGap = math.min(minGap, g)
		end
		check("the planner lays tight hairpins", total > 0, `{total} over {#(opts.seedList or SEEDS)} seeds of {opts.length or LENGTH} studs`)
		check("never within 1 500 studs of another", minGap >= 1500, if #gaps > 0 then `closest {fmt(minGap, 0)} studs apart` else "none two on one road")
		check("every island on the road is a bank at least 10 across", total == 0 or (worstSteep <= C.IslandMaxSlope and minNarrow >= 10), `steepest {fmt(worstSteep, 1)} degrees, narrowest {fmt(minNarrow, 1)} studs`)
		check("every island meets both legs' inner edges", worstEdge < 0.6, `worst {fmt(worstEdge, 2)} studs off`)
		check("no cliff the island makes, round it or where it hands back", worstStep <= stepBar, `steepest step {fmt(worstStep, 2)} studs a stud{stepAt} (bar {fmt(stepBar, 2)})`)
		check("no rail on an island's side", islandRails == 0, `{islandRails} rail runs on islands; {outsideRailed} of {total} turns railed on their outside`)
		check("the planner's time per section stays near today's", worstMs < 60, `mean {fmt(sumMs / math.max(secs, 1), 2)} ms, worst {fmt(worstMs, 1)} ms`)
	end

	-- 6. the car
	if opts.drive ~= false then
		local Turn = require(ServerScriptService.Tests.TightTurnTests)
		local SplineWorld = require(StarterPlayer.StarterPlayerScripts:WaitForChild("Drift").SplineWorld)
		local sp, _, _ = road(1)
		local e = sp.tight[1]
		local world = SplineWorld.new(sp, nil)
		for _, v0 in { 60, 90 } do
			local okN, of, best = 0, 0, nil
			for _, w in Turn.ways() do
				of += 1
				local wc = table.clone(w)
				wc.world = world
				local r = Turn.drive(sp, e.sA, e.sB, 1, v0, wc, Config.TightHairpin.Radius)
				if r.ok then
					okN += 1
					if not best or r.t < best.t then
						best = r
					end
				end
			end
			check(`the car gets round from {v0} studs/s`, okN > 0, `{okN} of {of} ways` .. (if best then `, apex {fmt(best.apexSpeed or 0, 0)} studs/s` else ""))
			task.wait()
		end
	end
end

function Tests.run(opts)
	opts = opts or {}
	local checks, log = {}, {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok == true, detail = detail })
	end
	local ok, err = pcall(run, check, log, opts)
	if not ok then
		check("the tests ran", false, tostring(err))
	end
	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = table.concat(log, "\n") }
end

return Tests
