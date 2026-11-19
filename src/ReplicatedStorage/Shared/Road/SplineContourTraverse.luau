--!strict
--!native
-- Plan one leg of a descent across the mountainside (T-326). The leg runs across the face
-- (along the range's `v`), one layer every `TraverseLayer` studs, and may drift down or back
-- up the face (`t`) between layers. Each layer is a column of natural ground, so a survey
-- reads a few thousand heights.
--
-- The leg is scored as a road would be driven: every stud of length costs a stud, every stud
-- of height lost up to the sustained grade (`TraverseGrade`) earns back a little more than
-- the length it took, height lost faster than that earns nothing and costs `TraverseSteep`,
-- and height regained costs what it would have earned. Cut and fill past `TraverseEarthTol`
-- cost by depth, steeply past `TraverseDeep`. So a leg holds the sustained grade across the
-- face, crosses a gully where its banks are close in height, and where a gorge is deep it
-- turns up toward its head (back toward the mountain) to cross where it is shallow.
--
-- The leg ends where carrying on stops paying: the band either side of the next pass, a
-- gorge too deep to cross, ground that rises ahead, or the valley floor. Its end is the
-- hairpin site, chosen with the hillside's slope there, and the hillside's slope also sets
-- the hairpin's radius. The spline generator still fits and clearance-checks every section.
local Config = require(game.ReplicatedStorage.Shared.Config)
local Ground = require(script.Parent.Ground)
local Range = require(script.Parent.Range)

local Traverse = {}

export type Point = { t: number, v: number, s: number, y: number }
export type Leg = {
	points: { Point },
	dirV: number, -- 1 or -1: which way across the range the leg runs
	endT: number,
	endV: number,
	length: number,
	drop: number, -- studs of natural ground the leg descends
	hairpin: boolean, -- false when the leg ends on the valley floor
	radius: { number }, -- the hairpin's radius range, from the hillside at its site
	score: number,
	ridge: number, -- the ridge the descent heads for (the plan is dropped past it)
}

-- One direction across: the best leg from (t0, v0), or nil.
local function survey(f: Ground.Field, t0: number, v0: number, y0: number, yaw: number, dirV: number, pv: number): Leg?
	local C = Config.Range
	local r = f.range
	local dv, dt = C.TraverseLayer, C.TraverseCell
	local back = math.floor(C.TraverseBack / dt)
	local ahead = math.floor(C.TraverseAhead / dt)
	local width = back + ahead + 1
	local j0 = back + 1
	local layers = math.floor(C.TraverseMax / dv)
	local maxShift = C.TraverseShift
	local gStar = math.tan(math.rad(C.TraverseGrade))
	local gRock = math.tan(math.rad(Config.Spline.MaxGrade))
	local reward = C.TraverseReward / gStar
	local steep, tol, earth, deep = C.TraverseSteep, C.TraverseEarthTol, C.TraverseEarth, C.TraverseDeep
	local bendCost = C.TraverseBendCost
	local band = C.TraverseBand
	local lengths, angles = {}, {}
	for s = -maxShift, maxShift do
		lengths[s] = math.sqrt(dv * dv + (s * dt) ^ 2)
		angles[s] = math.atan2(s * dt, dv)
	end
	-- heights: the column at each layer, and halfway to the next
	local function columnAt(v: number): { number }
		local col = Ground.column(f, v)
		local out = table.create(width)
		for j = 1, width do
			out[j] = col(t0 + (j - j0) * dt)
		end
		return out
	end
	local H: { { number } } = {}
	local M: { { number } } = {}
	H[0] = columnAt(v0)
	H[1] = columnAt(v0 + dirV * dv)
	-- the road's own height at the start, and the heading it has, in the leg's frame
	local fx, fz = -math.sin(yaw), -math.cos(yaw)
	local ht, hv = fx * r.ux + fz * r.uz, fx * r.uz - fz * r.ux
	local startAngle = math.atan2(ht, hv * dirV)
	local cost = table.create(width, math.huge)
	local angle = table.create(width, 0)
	local Y = table.create(width, 0)
	local L = table.create(width, 0)
	cost[j0], angle[j0], Y[j0] = 0, startAngle, y0
	local refund = C.TraverseRefund
	local parents: { { number } } = {}
	local costs: { { number } } = {}
	local heights: { { number } } = {}
	local best, bestI, bestJ = math.huge, 0, 0
	local siteSlope = 0
	local minLayers = math.ceil(C.TraverseMin / dv)
	for i = 1, layers do
		local v = v0 + dirV * i * dv
		H[i + 1] = columnAt(v + dirV * dv)
		M[i] = columnAt(v - dirV * dv * 0.5)
		local h0, h1, h2, mid = H[i - 1], H[i], H[i + 1], M[i]
		-- the road over this layer follows the ground eased across the layers either side,
		-- so it bridges a narrow gully and cuts a narrow spur; what it leaves is earthwork
		local smooth = table.create(width)
		for j = 1, width do
			smooth[j] = 0.25 * h0[j] + 0.5 * h1[j] + 0.25 * h2[j]
		end
		-- beyond the band either side of the next pass, the leg goes no further
		local beyond = math.max(0, (v - pv) * dirV - band)
		local nextCost = table.create(width, math.huge)
		local nextAngle = table.create(width, 0)
		local nextY = table.create(width, 0)
		local nextL = table.create(width, 0)
		local parent = table.create(width, 0)
		for b = 1, width do
			local yb = smooth[b]
			local nodeEarth = math.abs(h1[b] - yb)
			local nodeCost = earth * math.max(0, nodeEarth - tol) + 2 * math.max(0, nodeEarth - deep) ^ 2 + 3 * beyond
			local bestHere, from, heading = math.huge, 0, 0
			for s = -maxShift, maxShift do
				local a = b - s
				if a < 1 or a > width then
					continue
				end
				local c0 = cost[a]
				if c0 == math.huge then
					continue
				end
				local len = lengths[s]
				local fall = Y[a] - yb
				local slope = math.abs(fall) / len
				local c = c0 + len + nodeCost + bendCost * math.abs(angles[s] - angle[a])
				-- height lost up to the sustained grade earns; faster is steep; regained costs
				if fall >= 0 then
					c -= reward * math.min(fall, gStar * len)
				else
					c -= reward * fall
				end
				c += steep * len * math.max(0, slope - gStar) + 400 * len * math.max(0, slope - gRock) ^ 2
				if c >= bestHere then
					continue
				end
				-- what the road leaves between the layers: the ground halfway, against the road
				local dev = math.abs(mid[(a + b) // 2] - 0.5 * (Y[a] + yb))
				c += earth * math.max(0, dev - tol) + 2 * math.max(0, dev - deep) ^ 2
				if c < bestHere then
					bestHere, from, heading = c, a, angles[s]
				end
			end
			nextCost[b], nextAngle[b], nextY[b], parent[b] = bestHere, heading, yb, from
			nextL[b] = if from > 0 then L[from] + lengths[b - from] else 0
		end
		cost, angle, Y, L = nextCost, nextAngle, nextY, nextL
		parents[i], costs[i], heights[i] = parent, cost, Y
		if i >= minLayers then
			for j = 2, width - 1 do
				local c = cost[j]
				if c == math.huge then
					continue
				end
				-- a hairpin site: as gentle as the hillside offers here
				-- (the leg's length is refunded here: within the path it keeps the leg from
				-- wandering, but a long leg that holds its grade is what a descent wants, so
				-- the leg ends where the ground stops paying, not where the length mounts)
				local sl = math.abs(h1[j + 1] - h1[j - 1]) / (2 * dt)
				local site = C.TraverseHairpin + C.TraverseSiteCost * math.max(0, sl - 0.15)
				local score = c - refund * L[j] + site
				if score < best then
					best, bestI, bestJ, siteSlope = score, i, j, sl
				end
			end
		end
	end
	if bestI == 0 then
		return nil
	end
	-- the path, back from the site
	local points: { Point } = table.create(bestI + 1)
	local j = bestJ
	for i = bestI, 1, -1 do
		points[i + 1] = { t = t0 + (j - j0) * dt, v = v0 + dirV * i * dv, s = 0, y = heights[i][j] }
		j = parents[i][j]
	end
	points[1] = { t = t0, v = v0, s = 0, y = y0 }
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		b.s = a.s + math.sqrt((b.t - a.t) ^ 2 + (b.v - a.v) ^ 2)
	end
	local last = points[#points]
	local _, up = Range.at(r, last.t, last.v)
	local radius = math.clamp(C.TraverseRadiusSlope / math.max(siteSlope, 1e-3), C.SteepHairpinRadius[1], C.TraverseRadiusMax)
	return {
		points = points,
		dirV = dirV,
		endT = last.t,
		endV = last.v,
		length = last.s,
		drop = y0 - last.y,
		hairpin = up > Config.Range.ValleyShare,
		radius = { radius, radius * 1.15 },
		score = best,
		ridge = 0,
	}
end

-- The leg from the road's end at (x, z), heading `yaw`, height `y`. `dirV` forces which way
-- across (after a hairpin, the other way); nil tries both and keeps the better.
function Traverse.plan(f: Ground.Field, x: number, z: number, y: number, yaw: number, dirV: number?, target: { x: number, z: number, k: number }): Leg?
	local r = f.range
	local t0, v0 = Range.frame(r, x, z)
	local _, pv = Range.frame(r, target.x, target.z)
	local leg: Leg? = nil
	for _, d in if dirV then { dirV } else { 1, -1 } do
		local l = survey(f, t0, v0, y, yaw, d, pv)
		if l and (not leg or l.score < (leg :: Leg).score) then
			leg = l
		end
	end
	if leg then
		leg.ridge = target.k
	end
	return leg
end

-- The nearest point on the leg to (t, v), and a waypoint `look` studs farther along it; past
-- the end, on along the leg's last direction. Also returns how far off the leg (t, v) is.
function Traverse.ahead(leg: Leg, t: number, v: number, look: number): (number, number, number)
	local pts = leg.points
	local best, at = math.huge, 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local dt, dv = b.t - a.t, b.v - a.v
		local u = math.clamp(((t - a.t) * dt + (v - a.v) * dv) / (dt * dt + dv * dv), 0, 1)
		local miss = (a.t + u * dt - t) ^ 2 + (a.v + u * dv - v) ^ 2
		if miss < best then
			best, at = miss, a.s + (b.s - a.s) * u
		end
	end
	local want = at + look
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if want <= b.s then
			local u = (want - a.s) / math.max(b.s - a.s, 1e-6)
			return a.t + u * (b.t - a.t), a.v + u * (b.v - a.v), math.sqrt(best)
		end
	end
	local a, b = pts[#pts - 1], pts[#pts]
	local l = math.max(b.s - a.s, 1e-6)
	local over = want - b.s
	return b.t + (b.t - a.t) / l * over, b.v + (b.v - a.v) / l * over, math.sqrt(best)
end

return Traverse
