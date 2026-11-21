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
--
-- A CLIMB (T-332) is surveyed the same way, mirrored: its face falls from the crest ahead, the
-- one the pass is on, so a stud of height GAINED up to the sustained grade earns, and height
-- lost costs `ClimbLoss` times what it would have earned. FORWARD PROGRESS FIRST: a climb's
-- leg may drop no more than `ClimbBack` back down the face (a gorge's head is up the face, the
-- way on), comes no nearer the crest than `ClimbCrestMargin` (the last stretch heads straight
-- for the pass), and ends only where it has gained at least `ClimbMinGain`, and on average
-- `ClimbMinGrade` along its length. A face where no leg does that hands back to the old legs.
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
	siteSlope: number, -- the hillside's fall across the hairpin site, rise over run (T-337: a tight hairpin on steeper ground)
	climb: boolean, -- a climb's leg (T-332), up the face of the ridge ahead
	crest: number, -- the ridge whose crest the leg's frame is from: the one behind on a descent, ahead on a climb
}

-- One direction across: the best leg from (x0, z0), or nil. The survey's frame is the face's
-- own: a layer every `TraverseLayer` studs across the range (`dirV`), and on each layer, the
-- places a whole number of `TraverseCell` studs on down from the leg's start, measured from
-- the crest the face falls from (ridge `k`). A face's contours lie along that crest, which
-- wanders across the range, so a leg that holds its place below the crest holds its height:
-- straight across, or square to the crest where the leg starts, would run aslant of a face
-- that curves.
-- (`climb`, T-332: up the face of ridge `k`, the one ahead, rather than down from ridge `k`, the
-- one behind. Either way the places run on along the range, `t`, the way on: down a descent's
-- face and up a climb's)
local function survey(f: Ground.Field, x0: number, z0: number, y0: number, yaw: number, dirV: number, pv: number, k: number, blocked: (number, number) -> boolean, climb: boolean, passY: number): Leg?
	local C = Config.Range
	local r = f.range
	local t0, v0 = Range.frame(r, x0, z0)
	local dv, dt = C.TraverseLayer, C.TraverseCell
	local function crest(v: number): number
		return Range.ridgeT(r, k, v) - r.shift
	end
	-- (height lost on a descent, gained on a climb)
	local sgn = if climb then -1 else 1
	local below = t0 - crest(v0)
	local back = math.floor((if climb then C.ClimbBack else C.TraverseBack) / dt)
	local ahead = math.floor(C.TraverseAhead / dt)
	local width = back + ahead + 1
	local j0 = back + 1
	local layers = math.floor(C.TraverseMax / dv)
	local maxShift = C.TraverseShift
	local gStar = math.tan(math.rad(if climb then C.ClimbGrade else C.TraverseGrade))
	local loss = if climb then C.ClimbLoss else 1
	local minGrade = math.tan(math.rad(C.ClimbMinGrade))
	-- (a climb's leg toward the pass, with less than twice `ClimbMinGain` left to climb under it,
	-- need gain only half what is left)
	local lastLeg = if climb and dirV * (pv - v0) > 0 then math.max(0, passY - C.ClimbPassBelow - y0) * 0.5 else math.huge
	local gRock = math.tan(math.rad(Config.Spline.MaxGrade))
	local reward = C.TraverseReward / gStar
	local steep, tol, earth, deep = C.TraverseSteep, C.TraverseEarthTol, C.TraverseEarth, C.TraverseDeep
	local bendCost = C.TraverseBendCost
	local band = C.TraverseBand
	-- where each layer's places are on along the range: its crest, plus how far below it
	-- (a climb's, T-332, from the range's own contour through the start instead: toward a peak
	-- the crest rises along the face, so a steady depth below it climbs as steeply as the
	-- crest does, and a leg holding its grade drops below it all the way. Each layer's contour
	-- is found within `ClimbFrameDrift` of the last's, a half layer at a time)
	local origin: (number) -> number
	if climb and C.ClimbContourFrame then
		local b0 = Ground.base(f, x0, z0)
		local anchors: { [number]: number } = { [0] = t0 }
		local function anchor(i: number): number
			local got = anchors[i]
			if got then
				return got
			end
			local before = anchor(i - 0.5)
			local v, vb = v0 + dirV * i * dv, v0 + dirV * (i - 0.5) * dv
			local guess = before + crest(v) - crest(vb)
			local lo, hi = guess - C.ClimbFrameDrift, guess + C.ClimbFrameDrift
			local function base(t: number): number
				return Ground.base(f, Range.world(r, t, v))
			end
			local t
			if base(lo) >= b0 then
				t = lo
			elseif base(hi) <= b0 then
				t = hi
			else
				for _ = 1, 10 do
					local m = 0.5 * (lo + hi)
					if base(m) < b0 then
						lo = m
					else
						hi = m
					end
				end
				t = 0.5 * (lo + hi)
			end
			anchors[i] = t
			return t
		end
		origin = anchor
	else
		origin = function(i: number): number
			return crest(v0 + dirV * i * dv) + below
		end
	end
	local function tAt(i: number, j: number): number
		return origin(i) + (j - j0) * dt
	end
	-- heights: a line on along the range at each layer, and halfway to the next
	local function columnAt(i: number): { number }
		local v = v0 + dirV * i * dv
		local col = Ground.column(f, v)
		local top = origin(i)
		local out = table.create(width)
		for j = 1, width do
			out[j] = col(top + (j - j0) * dt)
		end
		return out
	end
	local H: { { number } } = {}
	local M: { { number } } = {}
	H[0] = columnAt(0)
	H[1] = columnAt(1)
	-- the road's own height at the start, and the heading it has, in the range's frame
	local fx, fz = -math.sin(yaw), -math.cos(yaw)
	local startAngle = math.atan2(fx * r.ux + fz * r.uz, (fx * r.uz - fz * r.ux) * dirV)
	-- a leg that would first have to turn round is not this one (the way the road is going)
	if math.abs(startAngle) > math.rad(C.TraverseStartTurn) then
		return nil
	end
	local lengths: { [number]: number }, angles: { [number]: number } = {}, {}
	local cost = table.create(width, math.huge)
	local angle = table.create(width, 0)
	local Y = table.create(width, 0)
	local L = table.create(width, 0)
	cost[j0], angle[j0], Y[j0] = 0, startAngle, y0
	local refund = C.TraverseRefund
	local parents: { { number } } = {}
	local frees: { { boolean } } = {}
	local costs: { { number } } = {}
	local heights: { { number } } = {}
	local best, bestI, bestJ = math.huge, 0, 0
	local siteSlope = 0
	local minLayers = math.ceil((if climb then C.ClimbMin else C.TraverseMin) / dv)
	for i = 1, layers do
		local v = v0 + dirV * i * dv
		H[i + 1] = columnAt(i + 1)
		M[i] = columnAt(i - 0.5)
		-- each shift's length and heading over this layer, with the crest's own run
		local lean = origin(i) - origin(i - 1)
		for s = -maxShift, maxShift do
			local run = lean + s * dt
			lengths[s] = math.sqrt(dv * dv + run * run)
			angles[s] = math.atan2(run, dv)
		end
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
		-- old road: no leg runs where the road already is; nor over the crest, onto the face
		-- behind (a leg may turn up toward a gorge's head, back toward the mountain, no further)
		-- (old road is read every other place, over the places the leg can reach by now: the
		-- clearance asked for is wider than two places)
		-- (a climb's leg: nor nearer the crest ahead than `ClimbCrestMargin`, nor higher than
		-- `ClimbPassBelow` under the pass, T-332: height above the pass is lost again before the
		-- road crosses it, and up there a leg is climbing the flank of a peak)
		local free = table.create(width, false)
		local top = if climb then t0 - C.TraverseBackOn else math.max(crest(v) + C.TraverseCrestMargin, t0 - C.TraverseBackOn)
		local ceiling = if climb then crest(v) - C.ClimbCrestMargin else math.huge
		local cap = if climb then passY - C.ClimbPassBelow else math.huge
		local lo, hi = math.max(1, j0 - i * maxShift - 1), math.min(width, j0 + i * maxShift + 1)
		local lastPair, lastFree = -1, false
		for b = lo, hi do
			local tb = tAt(i, b)
			if tb >= top and tb <= ceiling and h1[b] <= cap then
				local pair = b // 2
				if pair ~= lastPair then
					lastPair, lastFree = pair, not blocked(Range.world(r, tAt(i, pair * 2), v))
				end
				free[b] = lastFree
			end
		end
		frees[i] = free
		for b = 1, width do
			if not free[b] then
				continue
			end
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
				local fall = sgn * (Y[a] - yb)
				local slope = math.abs(fall) / len
				local c = c0 + len + nodeCost + bendCost * math.abs(angles[s] - angle[a])
				-- height lost up to the sustained grade earns; faster is steep; regained costs
				-- (on a climb: height gained earns, and lost costs `ClimbLoss` times as much)
				if fall >= 0 then
					c -= reward * math.min(fall, gStar * len)
				else
					c -= loss * reward * fall
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
			for j = 3, width - 2 do
				local c = cost[j]
				if c == math.huge then
					continue
				end
				-- (a hairpin swings out down the fall line: room for it, clear of old road; and the
				-- leg comes into it level or falling, or its way back runs into the leg itself)
				if blocked(Range.world(r, tAt(i, j) + C.TraverseHairpinRoom, v)) then
					continue
				end
				-- FORWARD PROGRESS FIRST (a climb's leg, T-332): it ends only once it has gained
				-- `ClimbMinGain`, and `ClimbMinGrade` on average along its length
				-- (bar the last leg, toward the pass, which may run on level under it)
				if climb and Y[j] - y0 < math.min(math.max(C.ClimbMinGain, minGrade * L[j]), lastLeg) then
					continue
				end
				local level, at = true, j
				-- (a climb's over `ClimbApproach` layers, T-332: toward a peak, where the crest rises
				-- along the face, a leg holding its grade drops below the crest, and levels out late)
				-- (and may drop `ClimbApproachSlack` places in all over them, less than the hairpin's width)
				local slack = if climb then C.ClimbApproachSlack else 0
				for back = i, math.max(1, i - (if climb then C.ClimbApproach else C.TraverseApproach) + 1), -1 do
					local from = parents[back][at]
					if from > at then
						slack -= from - at
						if slack < 0 then
							level = false
							break
						end
					end
					at = from
				end
				if not level then
					continue
				end
				-- a hairpin site: as gentle as the hillside offers here
				-- (the leg's length is refunded here: within the path it keeps the leg from
				-- wandering, but a long leg that holds its grade is what a descent wants, so
				-- the leg ends where the ground stops paying, not where the length mounts)
				local sl = math.abs(h1[j + 2] - h1[j - 2]) / (4 * dt)
				local site = C.TraverseHairpin + C.TraverseSiteCost * math.max(0, sl - 0.15)
				-- and the way back from it: the next leg sets off a hairpin's width down the
				-- face, back across; ground there that falls away faster than the sustained
				-- grade would start that leg on a steep pitch
				local radius = math.clamp(C.TraverseRadiusSlope / math.max(sl, 1e-3), C.SteepHairpinRadius[1], C.TraverseRadiusMax)
				local jo = math.min(width, j + math.ceil(2 * radius / dt))
				-- (a climb's over `ClimbExitLayers`, T-332: the way back may run toward a peak)
				local m = math.min(i - 1, if climb then C.ClimbExitLayers else C.TraverseExitLayers)
				local clearWay = true
				for back = i, i - m, -1 do
					if not frees[back][jo] then
						clearWay = false
						break
					end
				end
				if not clearWay then
					continue
				end
				local exitFall = (H[i][jo] - H[i - m][jo]) / (math.max(m, 1) * dv)
				site += steep * m * dv * math.max(0, math.abs(exitFall) - gStar)
				-- and the hairpin itself: the ground falls across its width, the road round its
				-- half circle at no more than a comfortable pitch; what it cannot fall is fill
				-- (on a climb the ground rises across it, and what the road cannot climb is cut)
				local footFill = sgn * (H[i][j] - H[i][jo]) - C.TraverseHairpinFall * math.pi * radius
				site += 3 * earth * math.max(0, footFill - tol)
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
		points[i + 1] = { t = tAt(i, j), v = v0 + dirV * i * dv, s = 0, y = heights[i][j] }
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
		-- (a climb's leg always ends in one, T-332: on the valley floor too, so a leg that set off
		-- away from the pass comes back toward it)
		hairpin = climb or up > Config.Range.ValleyShare,
		radius = { radius, radius * 1.15 },
		siteSlope = siteSlope,
		score = best,
		ridge = 0,
		climb = climb,
		crest = k,
	}
end

-- The leg from the road's end at (x, z), heading `yaw`, height `y`. `dirV` forces which way
-- across (after a hairpin, the other way); nil tries both and keeps the better. `climb`
-- (T-332): a leg up the face of the ridge ahead, toward its pass.
function Traverse.plan(f: Ground.Field, x: number, z: number, y: number, yaw: number, dirV: number?, target: { x: number, z: number, y: number, k: number }, blocked: (number, number) -> boolean, climb: boolean?): Leg?
	-- (the face the descent is on falls from the ridge behind the one ahead; a climb's, from
	-- the one ahead)
	local r = f.range
	local _, pv = Range.frame(r, target.x, target.z)
	local leg: Leg? = nil
	for _, d in if dirV then { dirV } else { 1, -1 } do
		local l = survey(f, x, z, y, yaw, d, pv, if climb then target.k else target.k - 1, blocked, climb == true, target.y)
		if l and (not leg or l.score < (leg :: Leg).score) then
			leg = l
		end
	end
	-- (a leg that scores this badly has found no way across the face it can drive: the
	-- generator's own legs take over from here)
	if leg and leg.score > Config.Range.TraverseHopeless then
		return nil
	end
	if leg then
		leg.ridge = target.k
	end
	return leg
end

-- The nearest point on the leg to (t, v), and a waypoint `look` studs farther along it; past
-- the end, on along the leg's last direction. Also returns how far off the leg (t, v) is, and
-- how far along it the nearest point is.
function Traverse.ahead(leg: Leg, t: number, v: number, look: number): (number, number, number, number)
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
			return a.t + u * (b.t - a.t), a.v + u * (b.v - a.v), math.sqrt(best), at
		end
	end
	local a, b = pts[#pts - 1], pts[#pts]
	local l = math.max(b.s - a.s, 1e-6)
	local over = want - b.s
	return b.t + (b.t - a.t) / l * over, b.v + (b.v - a.v) / l * over, math.sqrt(best), at
end

return Traverse
