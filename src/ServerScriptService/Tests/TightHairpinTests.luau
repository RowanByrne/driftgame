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
			local edgeY = sp:heightAt(s) - under
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
			for x = bx0 - 20, bx1 + 20, step do
				local y = Ground.at(ctx, x, z)
				-- (only the ground: on the tarmac the road draws itself)
				local s, dd = sp:project(x, z, 80)
				local onRoad = s and dd and math.abs(dd) < half
				-- (only where the island has a say: the cuts and fills beside the road are the
				-- mountain's, walls on steep ground by design, and GroundTests' to judge)
				local _, w = TightHairpin.islandAt(isl, x, z)
				local v = if onRoad or w <= 0 then nil else y
				table.insert(row, v)
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
