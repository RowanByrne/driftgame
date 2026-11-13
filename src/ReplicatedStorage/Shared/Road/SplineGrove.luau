--!strict
-- SplineGrove: the trees and bushes on a grove's wide runoff (features/mountain-road.md
-- "Groves", T-183). Pure maths and drawing callbacks: no instances of its own.
--
-- A GROVE is a section whose runoff on one side (sometimes both) the generator widened to
-- `Terrain.GroveRunoff` because the section is flat and gentle (`SplineGen._terrain`). The
-- section carries only a SEED per side (`gv`); every device places the same trees from it,
-- here, from the seed and the curve alone -- the server chooses, clients replay, and no
-- tree position ever goes over the wire.
--
-- PLACING: one item every `GroveSpacing` studs along the grove, a conifer, a broadleaf or a
-- bush, its offset past the tarmac random between its setback (`TreeSetback`, `BushSetback`)
-- and the grass's outer edge there, less its own size. Where the grass is still too narrow
-- (the runoff eases out at a quarter of a stud per stud) there is simply no item. Every spot
-- draws the same numbers from the stream whether it gets an item or not.
--
-- DRAWING (`draw`): very low poly, into the chunk's own mesh through two callbacks, so a
-- grove costs triangles, not parts: a conifer is a four-sided trunk and two five-sided
-- cones, a broadleaf a trunk and a faceted blob, a bush a squat faceted lump.
--
-- SOLID (`sweep`, `push`): a tree's trunk is a wall to the car, a circle of its trunk's
-- radius, as tall as the tree; `Drift/SplineWorld` asks. A bush is not.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)

local SplineGrove = {}

SplineGrove.CONIFER = 1
SplineGrove.BROADLEAF = 2
SplineGrove.BUSH = 3

export type Item = {
	s: number,
	side: number,
	e: number, -- studs past the tarmac's edge
	kind: number,
	h: number, -- height
	r: number, -- canopy radius
	trunk: number, -- trunk radius; 0 for a bush
	x: number, -- the foot, on the ground
	y: number,
	z: number,
	spin: number, -- radians, so no two trees face the same way
	shade: number, -- 0..1, which of the kind's colours
}

export type Sink = {
	vertex: (p: Vector3) -> number,
	tri: (a: number, b: number, c: number, pa: Vector3, pb: Vector3, pc: Vector3, colour: Color3, facing: Vector3) -> (),
}

-- the items of each grove run, by side and run index, made the first time they are asked for
local caches: { [any]: { [number]: { [number]: { Item } } } } = setmetatable({}, { __mode = "k" }) :: any

local function lerp(range: { number }, u: number): number
	return range[1] + (range[2] - range[1]) * u
end

local function runItems(spline: Spline.Spline, side: number, i: number): { Item }
	local cache = caches[spline]
	if not cache then
		cache = { [-1] = {}, [1] = {} }
		caches[spline] = cache
	end
	local bySide = cache[side]
	local found = bySide[i]
	if found then
		return found
	end
	local T = Config.Spline.Terrain
	local half = Config.Road.Width * 0.5
	local runs = spline:groves(side)
	local a, b = runs.a[i], runs.b[i]
	local rng = Random.new(runs.seed[i])
	local K = T.GroveKinds
	local total = K.conifer + K.broadleaf + K.bush
	local items: { Item } = {}
	local s = a + rng:NextNumber() * T.GroveSpacing[2]
	while s < b do
		local uKind, uE, uH, uR, uTrunk, uSpin, uShade = rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber()
		local pk = uKind * total
		local kind, h, r, trunk
		if pk < K.conifer then
			kind, h = SplineGrove.CONIFER, lerp(T.ConiferHeight, uH)
			r, trunk = h * (0.2 + 0.08 * uR), lerp(T.TrunkRadius, uTrunk)
		elseif pk < K.conifer + K.broadleaf then
			kind, h = SplineGrove.BROADLEAF, lerp(T.BroadleafHeight, uH)
			r, trunk = h * (0.3 + 0.1 * uR), lerp(T.TrunkRadius, uTrunk)
		else
			kind, h = SplineGrove.BUSH, lerp(T.BushHeight, uH)
			r, trunk = h * (0.9 + 0.5 * uR), 0
		end
		local lo = if kind == SplineGrove.BUSH then T.BushSetback else T.TreeSetback
		local hi = spline:runoffAt(s, side) - math.max(r * 0.5, 2)
		if hi - lo >= 1 then
			local e = lo + (hi - lo) * uE
			local x, y, z = spline:terrainXYZ(s, side * (half + e))
			table.insert(items, {
				s = s,
				side = side,
				e = e,
				kind = kind,
				h = h,
				r = r,
				trunk = trunk,
				x = x,
				y = y,
				z = z,
				spin = uSpin * 2 * math.pi,
				shade = uShade,
			})
		end
		s += lerp(T.GroveSpacing, rng:NextNumber())
	end
	bySide[i] = items
	return items
end

-- Every item on `side` whose s is in [s0, s1), into `out` (made if not given).
function SplineGrove.items(spline: Spline.Spline, s0: number, s1: number, side: number, out: { Item }?): { Item }
	local list = out or {}
	local runs = spline:groves(side)
	local a = runs.a
	local n = #a
	if n == 0 or a[1] >= s1 then
		return list
	end
	-- the last run starting before s1; runs never overlap, so walk back while they reach s0
	local lo, hi = 1, n
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if a[mid] < s1 then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local first = lo
	while first > 1 and runs.b[first - 1] > s0 do
		first -= 1
	end
	for i = first, lo do
		if runs.b[i] > s0 then
			for _, it in runItems(spline, side, i) do
				if it.s >= s0 and it.s < s1 then
					table.insert(list, it)
				end
			end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function ring(sink: Sink, it: Item, y: number, radius: number, n: number, spin: number): ({ number }, { Vector3 })
	local ids, pts = table.create(n), table.create(n)
	for j = 1, n do
		local t = spin + (j - 1) * 2 * math.pi / n
		local p = Vector3.new(it.x + radius * math.cos(t), y, it.z + radius * math.sin(t))
		pts[j] = p
		ids[j] = sink.vertex(p)
	end
	return ids, pts
end

-- the sides from a ring to a point (a cone, or half a blob), facing away from the axis
local function cap(sink: Sink, it: Item, ids: { number }, pts: { Vector3 }, tipId: number, tip: Vector3, colour: Color3)
	local n = #ids
	local up = if tip.Y > pts[1].Y then 1 else -1
	for j = 1, n do
		local k = j % n + 1
		local mid = (pts[j] + pts[k] + tip) / 3
		local out = Vector3.new(mid.X - it.x, 0, mid.Z - it.z)
		sink.tri(ids[j], ids[k], tipId, pts[j], pts[k], tip, colour, out + Vector3.yAxis * (up * out.Magnitude * 0.5))
	end
end

-- the band between two rings of the same count, facing away from the axis
local function band(sink: Sink, it: Item, idsA: { number }, ptsA: { Vector3 }, idsB: { number }, ptsB: { Vector3 }, colour: Color3)
	local n = #idsA
	for j = 1, n do
		local k = j % n + 1
		local mid = (ptsA[j] + ptsA[k] + ptsB[j] + ptsB[k]) * 0.25
		local out = Vector3.new(mid.X - it.x, 0, mid.Z - it.z)
		sink.tri(idsA[j], idsA[k], idsB[j], ptsA[j], ptsA[k], ptsB[j], colour, out)
		sink.tri(idsA[k], idsB[k], idsB[j], ptsA[k], ptsB[k], ptsB[j], colour, out)
	end
end

local function point(sink: Sink, it: Item, y: number): (number, Vector3)
	local p = Vector3.new(it.x, y, it.z)
	return sink.vertex(p), p
end

local function pick(colours: { Color3 }, u: number): Color3
	return colours[math.clamp(math.floor(u * #colours) + 1, 1, #colours)]
end

local function trunk(sink: Sink, it: Item, top: number)
	local T = Config.Spline.Terrain
	local idsA, ptsA = ring(sink, it, it.y - 1, it.trunk, 4, it.spin)
	local idsB, ptsB = ring(sink, it, it.y + top, it.trunk * 0.7, 4, it.spin)
	band(sink, it, idsA, ptsA, idsB, ptsB, T.TrunkColour)
end

-- Draw every item in [s0, s1), both sides. Returns how many.
function SplineGrove.draw(spline: Spline.Spline, s0: number, s1: number, sink: Sink): number
	local T = Config.Spline.Terrain
	local all: { Item } = {}
	SplineGrove.items(spline, s0, s1, -1, all)
	SplineGrove.items(spline, s0, s1, 1, all)
	for _, it in all do
		local y, h, r = it.y, it.h, it.r
		if it.kind == SplineGrove.CONIFER then
			local colour = pick(T.ConiferColours, it.shade)
			trunk(sink, it, h * 0.3)
			-- two tiers, each a five-sided cone; only the lower one shows its underside
			for tier = 1, 2 do
				local base = if tier == 1 then y + h * 0.18 else y + h * 0.46
				local apex = if tier == 1 then y + h * 0.72 else y + h
				local radius = if tier == 1 then r else r * 0.7
				local ids, pts = ring(sink, it, base, radius, 5, it.spin + tier * 0.5)
				local tipId, tip = point(sink, it, apex)
				cap(sink, it, ids, pts, tipId, tip, colour)
				if tier == 1 then
					local underId, under = point(sink, it, base)
					cap(sink, it, ids, pts, underId, under, colour)
				end
			end
		elseif it.kind == SplineGrove.BROADLEAF then
			local colour = pick(T.BroadleafColours, it.shade)
			trunk(sink, it, h * 0.55)
			-- a faceted blob: two rings, a point above and below
			local idsA, ptsA = ring(sink, it, y + h * 0.5, r * 0.85, 5, it.spin)
			local idsB, ptsB = ring(sink, it, y + h * 0.74, r, 5, it.spin + 0.6)
			local botId, bot = point(sink, it, y + h * 0.32)
			local topId, top = point(sink, it, y + h)
			cap(sink, it, idsA, ptsA, botId, bot, colour)
			band(sink, it, idsA, ptsA, idsB, ptsB, colour)
			cap(sink, it, idsB, ptsB, topId, top, colour)
		else
			local colour = pick(T.BushColours, it.shade)
			local ids, pts = ring(sink, it, y + h * 0.35, r, 5, it.spin)
			local topId, top = point(sink, it, y + h)
			local botId, bot = point(sink, it, y - 0.5)
			cap(sink, it, ids, pts, topId, top, colour)
			cap(sink, it, ids, pts, botId, bot, colour)
		end
	end
	return #all
end

--------------------------------------------------------------------------------
-- Solid trunks
--------------------------------------------------------------------------------

-- How far along the road either side of the car trunks are looked for. Generous: on the
-- inside of a gentle bend, far out on the grass, a stud across is more than a stud of s.
local REACH_S = 40

local function sgn(v: number): number
	return if v < 0 then -1 else 1
end

-- The gap between the car's box (centre px, pz; right and forward axes; half width and
-- length) and a trunk (tx, tz, radius): positive clear, negative overlapping; and the way
-- the car goes to get clear (unit, flat).
local function gap(px: number, pz: number, rx: number, rz: number, fx: number, fz: number, hw: number, hl: number, tx: number, tz: number, tr: number): (number, number, number)
	local ex, ez = tx - px, tz - pz
	local lx, lz = ex * rx + ez * rz, ex * fx + ez * fz
	local qx, qz = math.abs(lx) - hw, math.abs(lz) - hl
	local gx, gz, dist
	if qx > 0 or qz > 0 then
		local ox, oz = math.max(qx, 0), math.max(qz, 0)
		local m = math.sqrt(ox * ox + oz * oz)
		dist = m - tr
		gx, gz = ox / m * sgn(lx), oz / m * sgn(lz)
	elseif qx > qz then
		dist, gx, gz = qx - tr, sgn(lx), 0
	else
		dist, gx, gz = qz - tr, 0, sgn(lz)
	end
	-- from the car toward the trunk, in the world; the car goes the other way
	return dist, -(gx * rx + gz * fx), -(gx * rz + gz * fz)
end

local near: { Item } = {}
local function trunksNear(spline: Spline.Spline, s: number)
	table.clear(near)
	SplineGrove.items(spline, s - REACH_S, s + REACH_S, -1, near)
	SplineGrove.items(spline, s - REACH_S, s + REACH_S, 1, near)
end

local function stands(it: Item, carY: number, bh: number): boolean
	return it.trunk > 0 and carY - bh < it.y + it.h and carY + bh > it.y - 1
end

-- The first trunk the car's box meets moving from `from` to `to` (flat), facing `fwd` with
-- `right`: as SplineWorld's margins (`m0`, `m1`: a share-of-the-step crossing, already
-- solved) and the way out. nil when it meets none. `s` is the car's s.
function SplineGrove.sweep(spline: Spline.Spline, s: number, from: Vector3, to: Vector3, fwd: Vector3, right: Vector3, hw: number, hl: number, bh: number): (number?, number?, Vector3?)
	trunksNear(spline, s)
	if #near == 0 then
		return nil, nil, nil
	end
	local rx, rz, fx, fz = right.X, right.Z, fwd.X, fwd.Z
	local dx, dz = to.X - from.X, to.Z - from.Z
	local far = hw + hl + math.sqrt(dx * dx + dz * dz) + 2
	local bestT, bestM0, bestM1, bestN = math.huge, nil, nil, nil
	for _, it in near do
		local cx, cz = it.x - from.X, it.z - from.Z
		if cx * cx + cz * cz < (far + it.trunk) ^ 2 and stands(it, from.Y, bh) then
			local g0, ox0, oz0 = gap(from.X, from.Z, rx, rz, fx, fz, hw, hl, it.x, it.z, it.trunk)
			local g1 = gap(to.X, to.Z, rx, rz, fx, fz, hw, hl, it.x, it.z, it.trunk)
			if g0 <= 0 then
				-- already touching: going in further is stopped at once; coming out is free
				if g1 < g0 and 0 < bestT then
					bestT, bestM0, bestM1, bestN = 0, g0, g1, Vector3.new(ox0, 0, oz0)
				end
			elseif g1 < 0 then
				-- the moment it touches, by halving: the gap along a straight move is convex
				local a, b = 0, 1
				for _ = 1, 12 do
					local m = (a + b) * 0.5
					if gap(from.X + dx * m, from.Z + dz * m, rx, rz, fx, fz, hw, hl, it.x, it.z, it.trunk) > 0 then
						a = m
					else
						b = m
					end
				end
				if a < bestT then
					local _, ox, oz = gap(from.X + dx * b, from.Z + dz * b, rx, rz, fx, fz, hw, hl, it.x, it.z, it.trunk)
					bestT, bestM0, bestM1, bestN = a, a, a - 1, Vector3.new(ox, 0, oz)
				end
			end
		end
	end
	return bestM0, bestM1, bestN
end

-- The deepest trunk the car's box at `pos` is already in, `margin` included: how deep, and
-- the way out. 0 and nil when it is in none.
function SplineGrove.push(spline: Spline.Spline, s: number, pos: Vector3, fwd: Vector3, right: Vector3, hw: number, hl: number, bh: number, margin: number): (number, Vector3?)
	trunksNear(spline, s)
	local worst, worstN = 0, nil
	for _, it in near do
		if stands(it, pos.Y, bh) then
			local g, ox, oz = gap(pos.X, pos.Z, right.X, right.Z, fwd.X, fwd.Z, hw, hl, it.x, it.z, it.trunk)
			if margin - g > worst then
				worst, worstN = margin - g, Vector3.new(ox, 0, oz)
			end
		end
	end
	return worst, worstN
end

return SplineGrove
