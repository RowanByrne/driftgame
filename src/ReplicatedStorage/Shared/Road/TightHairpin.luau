--!strict
--!native
-- Road/TightHairpin: the touge hairpin whose two legs run side by side with a narrow island
-- of ground between them, laid as a FIXED SHAPE rather than found by search
-- (features/tight-hairpins.md, T-329). Pure maths: no instances.
--
-- THE SHAPE, one section, from the road's tip:
--
--   ease straight      if the road is still bending, back to straight at the road's own rate
--   lead               straight, so no older road lies beside the leg out (`build`)
--   leg in             `Parallel` studs straight: the upper leg's side by side run
--   the turn           ease to 1 / `Radius` over `Ease`, hold, ease out over `Ease`: exactly a
--                      half turn, so the leg out comes back parallel to the leg in
--   leg out            `Parallel` studs straight, beside the leg in
--   diverge            a bend of `DivergeRadius` back the other way, away from the leg in, by
--                      how far short of a half turn the next leg's heading is (within
--                      `DivergeDegrees`): a hairpin through the downhill side ends short of
--                      a half turn by twice the legs' tilt down the face
--   run on             straight until the leg out is `clear` from the leg in's line, and the
--                      island has handed back to the mountain
--
-- with the grade eased to `Grade` (signed by the caller: falling on a descent) and the bank
-- to flat, and both held. Section tag "TightHairpin"; its `th` field says where the island
-- is: { sIn, sA, sB, sOut, dir } along the section (the leg in's side by side run starts, the
-- turn starts, the turn ends, the leg out's run ends; `dir` 1 turns left, -1 right).
--
-- THE ISLAND (`island`, `islandAt`): the ground between the legs is a BANK, straight across
-- from the leg in's inner edge to the leg out's, at each distance from the tip, down a rung
-- square to the legs. Round the tip the rungs shorten to nothing at the apex, so the bank is
-- continuous there; past the side by side run it hands back to the mountain over
-- `IslandGone` apart. Nothing between the legs is read off the mountain: that is what "pre-planned"
-- means here, and why the two legs' edges meet the island cleanly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TightHairpin = {}

export type Th = { number } -- { sIn, sA, sB, sOut, dir }, along the section

-- One tight hairpin on a laid road, in the road's own `s` (`Spline.append` keeps these).
export type Entry = { sIn: number, sA: number, sB: number, sOut: number, dir: number, sStart: number, sEnd: number }

-- What `island` makes of an entry: the island's frame and its two inner edges, sampled.
export type Island = {
	entry: Entry,
	ox: number,
	oz: number,
	xx: number, -- across, from the leg in toward the leg out
	xz: number,
	yx: number, -- along, from the tip toward the open end
	yz: number,
	yFull: number, -- the side by side run ends here
	yEnd: number, -- the edges are sampled this far
	ly: { number }, -- the leg in's inner edge: local y (rising), x, ground height
	lx: { number },
	lh: { number },
	ry: { number }, -- the leg out's
	rx: { number },
	rh: { number },
	minX: number, -- world box
	maxX: number,
	minZ: number,
	maxZ: number,
}

local function sign(x: number): number
	return if x > 0 then 1 elseif x < 0 then -1 else 0
end

-- The road's own easing length from k0 to k1 (`SplineGen`'s `transition`).
local function transition(k0: number, k1: number): number
	local C = Config.Spline
	local dk = math.abs(k1 - k0)
	if dk < 1e-12 then
		return 0
	end
	return math.max(C.MinTransition, dk / C.MaxCurvatureRate)
end

-- A track ramped from v0 to `target` no faster than `rate` a stud, then held to `len`.
local function ramp(v0: number, target: number, rate: number, len: number): { number }
	local dv = target - v0
	if math.abs(dv) < 1e-9 then
		return { len, target }
	end
	local L = math.min(math.max(math.abs(dv) / rate, 1), len - 1)
	return { L, target, len, target }
end

-- Plan positions along curvature knots from (0, 0) heading -Z (yaw 0), every stud.
local function trace(k0: number, knots: { number }): ({ number }, { number })
	local xs, zs = { 0 }, { 0 }
	local x, z, yaw = 0, 0, 0
	local s, k, j = 0, k0, 1
	local len = knots[#knots - 1]
	local i = 0
	while i < len do
		local u = i + 0.5
		while knots[j] < u and j < #knots - 1 do
			s, k = knots[j], knots[j + 1]
			j += 2
		end
		local s1, k1 = knots[j], knots[j + 1]
		local km = k + (k1 - k) * (u - s) / math.max(s1 - s, 1e-9)
		local ym = yaw + km * 0.5
		x -= math.sin(ym)
		z -= math.cos(ym)
		yaw += km
		i += 1
		xs[i + 1], zs[i + 1] = x, z
	end
	return xs, zs
end

-- The shape, from the road's tip: its curvature `k0`, grade `g0` and bank `b0` there.
-- `dir` 1 turns left, -1 right; `extra` (radians) is how far short of a half turn the next
-- leg's heading is; `grade` the signed grade to hold; `clear` the road's clearance. Returns the
-- section.
--
-- THE LEAD: the leg in starts with a straight of its own, as long as it takes for no road
-- before the shape to lie beside the leg out until the leg out is clear of the leg in's line
-- and the island has handed back (`need`, and `LeadMargin`).
-- So the shape's legs are close only to each other: every road laid before it, and everything
-- on that road (its groves' trees), keeps the road's whole clearance from it.
function TightHairpin.build(k0: number, g0: number, b0: number, dir: number, extra: number, grade: number, clear: number): any
	local C, S = Config.TightHairpin, Config.Spline
	local lo, hi = math.rad(C.DivergeDegrees[1]), math.rad(C.DivergeDegrees[2])
	local theta = math.clamp(extra, lo, hi)
	local kd = 1 / C.DivergeRadius
	local Td = transition(0, kd)
	local Hd = theta / kd - Td
	local kp = kd
	if Hd < 0 then
		Hd = 0
		kp = theta / Td
	end
	-- (and far enough for the island to hand back to the mountain inside the shape)
	local need = math.max(clear, Config.Road.Width + C.IslandGone + 10)
	local function knotsFor(lead: number)
		local k: { number } = {}
		local u = 0
		local T0 = transition(k0, 0)
		if T0 > 0 then
			u = T0
			table.insert(k, u)
			table.insert(k, 0)
		end
		u += lead
		local sIn = u
		u += C.Parallel
		table.insert(k, u)
		table.insert(k, 0)
		local sA = u
		local kt = dir / C.Radius
		local E = C.Ease
		local H = math.pi * C.Radius - E -- the two easings turn E / R between them
		u += E
		table.insert(k, u)
		table.insert(k, kt)
		u += H
		table.insert(k, u)
		table.insert(k, kt)
		u += E
		table.insert(k, u)
		table.insert(k, 0)
		local sB = u
		u += C.Parallel
		table.insert(k, u)
		table.insert(k, 0)
		local sOut = u
		-- away from the leg in: back the other way round
		u += Td
		table.insert(k, u)
		table.insert(k, -dir * kp)
		if Hd > 0 then
			u += Hd
			table.insert(k, u)
			table.insert(k, -dir * kp)
		end
		u += Td
		table.insert(k, u)
		table.insert(k, 0)
		-- run on until clear of the leg in's line (traced: the shape is its own, so is its check)
		local xs, zs = trace(k0, k)
		local ia, ib = math.floor(sIn) + 1, math.floor(sA) + 1
		local ax, az = xs[ia], zs[ia]
		local lx, lz = xs[ib] - ax, zs[ib] - az
		local ll = math.max(math.sqrt(lx * lx + lz * lz), 1e-9)
		lx, lz = lx / ll, lz / ll
		local n = #xs
		local ex, ez = xs[n], zs[n]
		local px, pz = xs[n - 1], zs[n - 1]
		local fx, fz = ex - px, ez - pz
		local fl = math.max(math.sqrt(fx * fx + fz * fz), 1e-9)
		fx, fz = fx / fl, fz / fl
		local across = math.abs((ex - ax) * lz - (ez - az) * lx)
		local opening = math.abs(fx * lz - fz * lx) -- how fast the leg out leaves the line a stud
		local run = math.max((need - across) / math.max(opening, 0.05), 0) + 20
		u += run
		table.insert(k, u)
		table.insert(k, 0)
		-- how far back past the side by side run the leg out still lies within `clear` of the
		-- leg in's line: the lead that keeps the road before the shape out of its way
		local back = 0
		for i = math.floor(sOut) + 1, n + math.floor(run) do
			local qx, qz
			if i <= n then
				qx, qz = xs[i], zs[i]
			else
				qx, qz = ex + fx * (i - n), ez + fz * (i - n)
			end
			local rx, rz = qx - ax, qz - az
			-- (the island's whole hand-back too, and a margin for a road that was still bending)
			if math.abs(rx * lz - rz * lx) < need + C.LeadMargin then
				back = math.max(back, -(rx * lx + rz * lz))
			end
		end
		return k, sIn, sA, sB, sOut, u, back
	end
	local _, _, _, _, _, _, back = knotsFor(0)
	local lead = if back > 0 then back + 2 * S.CheckStep else 0
	local k, sIn, sA, sB, sOut, len = knotsFor(lead)
	return {
		len = len,
		k = k,
		g = ramp(g0, grade, S.MaxGradeRate, len),
		-- (the bank track eases between knots: its steepest is 1.5 times a straight ramp's)
		b = ramp(b0, 0, math.rad(S.MaxBankRate) / 1.5, len),
		tag = "TightHairpin",
		th = { sIn, sA, sB, sOut, dir },
	}
end

--------------------------------------------------------------------------------
-- The island
--------------------------------------------------------------------------------

local SAMPLE = 2 -- studs along each leg's inner edge


-- The island's frame and its two inner edges, sampled once (the road under it never changes).
-- `spline` is the laid road (`Road/Spline`).
function TightHairpin.island(spline: any, e: Entry): Island
	local C = Config.TightHairpin
	local half = Config.Road.Width * 0.5
	local under = Config.Spline.Ground.Under
	local ax, az = spline:planAt(e.sA)
	local bx, bz = spline:planAt(e.sB)
	local ox, oz = (ax + bx) * 0.5, (az + bz) * 0.5
	local dx, dz = bx - ax, bz - az
	local D = math.max(math.sqrt(dx * dx + dz * dz), 1e-6)
	local xx, xz = dx / D, dz / D
	local yaw = spline:yawAt(e.sA)
	local yx, yz = math.sin(yaw), math.cos(yaw) -- back along the leg in: away from the tip
	local d = -e.dir * (half + C.IslandRunoff) -- the inside of the turn, both legs
	local apex = (e.sA + e.sB) * 0.5
	local isl: any = {
		entry = e,
		ox = ox,
		oz = oz,
		xx = xx,
		xz = xz,
		yx = yx,
		yz = yz,
		ly = {},
		lx = {},
		lh = {},
		ry = {},
		rx = {},
		rh = {},
		minX = math.huge,
		maxX = -math.huge,
		minZ = math.huge,
		maxZ = -math.huge,
	}
	local function edge(s: number, ys: { number }, xs: { number }, hs: { number })
		local cx, cz = spline:planAt(s)
		local yw = spline:yawAt(s)
		local px, pz = cx + d * math.cos(yw), cz - d * math.sin(yw)
		local rx, rz = px - ox, pz - oz
		local ly = rx * yx + rz * yz
		-- (only while the edge keeps moving away from the tip: a rung meets each edge once)
		if #ys > 0 and ly <= ys[#ys] then
			return false
		end
		table.insert(ys, ly)
		table.insert(xs, rx * xx + rz * xz)
		table.insert(hs, spline:heightAt(s) + d * math.tan(spline:bankAt(s)) - under)
		isl.minX = math.min(isl.minX, px)
		isl.maxX = math.max(isl.maxX, px)
		isl.minZ = math.min(isl.minZ, pz)
		isl.maxZ = math.max(isl.maxZ, pz)
		return true
	end
	-- (each edge over the shape's whole section: the lead and the run on are as long as the
	-- island takes to hand back, and the road either side of the shape is the mountain's)
	local s = apex
	while s >= e.sStart and s >= 0 do
		if not edge(s, isl.ly, isl.lx, isl.lh) and s < e.sA then
			break
		end
		s -= SAMPLE
	end
	s = apex
	while s <= e.sEnd and s <= spline.length do
		if not edge(s, isl.ry, isl.rx, isl.rh) and s > e.sB then
			break
		end
		s += SAMPLE
	end
	-- the side by side run, in the frame's y: the shorter leg's
	local function yOf(sv: number): number
		local cx, cz = spline:planAt(sv)
		return (cx - ox) * yx + (cz - oz) * yz
	end
	isl.yFull = math.min(yOf(e.sIn), yOf(e.sOut))
	isl.yEnd = math.min(isl.ly[#isl.ly] or 0, isl.ry[#isl.ry] or 0)
	return isl :: Island
end

-- (x and h on an edge at local y, rising; nil past either end)
local function along(ys: { number }, xs: { number }, hs: { number }, y: number): (number?, number?)
	local n = #ys
	if n < 2 or y < ys[1] or y > ys[n] then
		return nil, nil
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if ys[mid] <= y then
			lo = mid
		else
			hi = mid
		end
	end
	local t = (y - ys[lo]) / math.max(ys[hi] - ys[lo], 1e-9)
	return xs[lo] + (xs[hi] - xs[lo]) * t, hs[lo] + (hs[hi] - hs[lo]) * t
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- The island's ground at (x, z): its height, and how much the island decides it there (1 on
-- the side by side run, easing to 0 by `yEnd`). nil off the island.
function TightHairpin.islandAt(isl: Island, x: number, z: number): (number?, number)
	if x < isl.minX or x > isl.maxX or z < isl.minZ or z > isl.maxZ then
		return nil, 0
	end
	local rx, rz = x - isl.ox, z - isl.oz
	local ly = rx * isl.yx + rz * isl.yz
	local lx = rx * isl.xx + rz * isl.xz
	local xl, hl = along(isl.ly, isl.lx, isl.lh, ly)
	local xr, hr = along(isl.ry, isl.rx, isl.rh, ly)
	if not xl or not xr or not hl or not hr then
		return nil, 0
	end
	local a, b = math.min(xl, xr), math.max(xl, xr)
	if lx < a or lx > b then
		return nil, 0
	end
	local t = if b - a > 1e-6 then (lx - xl) / (xr - xl) else 0.5
	local h = hl + (hr - hl) * t
	-- the bank wholly while the legs are close, handing back to the mountain as they part:
	-- by `IslandGone` apart each leg's own cut or fill has room to reach h before the other's
	local C = Config.TightHairpin
	local w = 1 - smooth(math.clamp((b - a - C.IslandFull) / (C.IslandGone - C.IslandFull), 0, 1))
	if w <= 0 then
		return nil, 0
	end
	return h, w
end

-- The steepest the island gets, and its narrowest gap between the legs' inner edges on the side
-- by side run: what the tests hold it to.
function TightHairpin.measure(isl: Island): (number, number)
	local steep, narrow = 0, math.huge
	local y = math.max(isl.ly[1], isl.ry[1])
	while y <= isl.yFull do
		local xl, hl = along(isl.ly, isl.lx, isl.lh, y)
		local xr, hr = along(isl.ry, isl.rx, isl.rh, y)
		if xl and xr and hl and hr then
			local gap = math.abs(xr - xl)
			if y > 1 then
				narrow = math.min(narrow, gap)
			end
			if gap > 1 then
				steep = math.max(steep, math.deg(math.atan(math.abs(hr - hl) / gap)))
			end
		end
		y += 1
	end
	return steep, narrow
end

TightHairpin.sign = sign

return TightHairpin
