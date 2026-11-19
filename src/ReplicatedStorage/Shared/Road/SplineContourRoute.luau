--!strict
--!native
-- Survey a corridor across the next mountainside. Layers advance into the range;
-- edges can traverse several cells sideways, including a return onto the other flank.
-- The spline generator still fits and clearance-checks every bend it actually lays.
local Config = require(game.ReplicatedStorage.Shared.Config)
local Ground = require(script.Parent.Ground)
local Range = require(script.Parent.Range)
local Gorge = require(script.Parent.SplineContourGorge)

local Route = {}
type Point = { t: number, v: number, s: number }
export type Route = { points: { Point }, ridge: number, endT: number, fromFace: number }

-- Lay out a broad bend across a long, straight approach while both flanks
-- are still available. The hill chooses the side and how far the road swings.
local function hillsideBends(f: Ground.Field, pts: { Point })
	local C = Config.Range
	local i = 1
	while i < #pts do
		local j = i + 1
		while j < #pts and pts[j].s - pts[i].s < C.TraverseSpan do j += 1 end
		local a, b = pts[i], pts[j]
		local span = b.s - a.s
		if span < C.TraverseSpan * 0.68 then break end
		local dt, dv = b.t - a.t, b.v - a.v
		local chord = math.sqrt(dt * dt + dv * dv)
		if dt < 0.55 * chord or span > 1.10 * chord then
			i += 1
			continue
		end
		local function offsetScore(offset: number): number
			local prevX, prevZ = Range.world(f.range, a.t, a.v)
			local prevH = Ground.h(f, prevX, prevZ)
			local sum, worst, count = 0, 0, 0
			for k = i + 1, j do
				local p = pts[k]
				local wave = math.sin(math.pi * (p.s - a.s) / span)
				local x, z = Range.world(f.range, p.t, p.v + offset * wave * wave)
				local h = Ground.h(f, x, z)
				local dx, dz = x - prevX, z - prevZ
				local len = math.sqrt(dx * dx + dz * dz)
				local pitch = math.abs(h - prevH) / len
				local banks = Gorge.along(f, x, z, dx / len, dz / len, h)
				local penalty = 480 * math.max(0, pitch - 0.13) + 1800 * math.max(0, pitch - 0.24) + 3 * banks
				sum += penalty
				worst = math.max(worst, penalty)
				count += 1
				prevX, prevZ, prevH = x, z, h
			end
			-- A low-cost, wide alternative makes room for a pair of flowing bends.
			local throw = math.abs(offset) * dt / chord
			return worst + 0.8 * sum / count + 125 * math.max(0, 1 - throw / 620) ^ 2
		end
		local best, chosen = offsetScore(0), 0
		for _, offset in C.TraverseOffsets do
			for side = -1, 1, 2 do
				local score = offsetScore(side * offset)
				if score < best then best, chosen = score, side * offset end
			end
		end
		if chosen ~= 0 then
			for k = i + 1, j - 1 do
				local p = pts[k]
				local wave = math.sin(math.pi * (p.s - a.s) / span)
				p.v += chosen * wave * wave
			end
		end
		i = j
	end
end

local function distances(points: { Point })
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		b.s = a.s + math.sqrt((b.t - a.t) ^ 2 + (b.v - a.v) ^ 2)
	end
end

function Route.new(f: Ground.Field, x: number, z: number, yaw: number, target: { x: number, z: number, k: number }): Route
	local r, C = f.range, Config.Range
	local t0, v0 = Range.frame(r, x, z)
	local tt, tv = Range.frame(r, target.x, target.z)
	local cols = math.clamp(math.ceil((tt - t0 + 360) / C.CorridorForward), 4, C.CorridorColumns)
	local dt, dv, half = C.CorridorForward, C.CorridorAcross, C.CorridorHalfWidth
	local grade = math.tan(math.rad(C.ContourGrade))
	local peak = math.tan(math.rad(Config.Spline.MaxGrade))
	local reach, pitchCost, bendCost = C.CorridorReach, C.CorridorPitchCost, C.CorridorBendCost
	local width = 2 * half + 1
	local mid = half + 1
	local offsets, lengths, directions = { 0 }, {}, {}
	for shift = -reach, reach do
		lengths[shift] = math.sqrt(dt * dt + (dv * shift) ^ 2)
		directions[shift] = math.atan2(dv * shift, dt)
	end
	for n = 1, reach do
		table.insert(offsets, n)
		table.insert(offsets, -n)
	end

	-- In this layer all incoming edges to the same cell share their endpoint.
	-- Walk the central edges first to get a cheaper bound for steep detours.
	local quarterWidth = (width - 1) * 4 + 1
	local columns = table.create(quarterWidth)
	for j = 1, quarterWidth do
		columns[j] = Ground.column(f, v0 + dv * (j - (mid - 1) * 4 - 1) / 4)
	end
	-- Coarse elevations are shared by the bank probes of neighbouring cells.
	local low, high = -5, width + 6
	local coarseColumns, coarseRows = {}, {}
	for j = low, high do
		coarseColumns[j] = columns[(j - 1) * 4 + 1] or Ground.column(f, v0 + dv * (j - mid))
	end
	local function coarse(i: number): { [number]: number }
		local row = coarseRows[i]
		if row then return row end
		row = {}
		local t = t0 + dt * i
		for j = low, high do row[j] = coarseColumns[j](t) end
		coarseRows[i] = row
		return row
	end
	local across, onward = {}, {}
	for shift = -reach, reach do
		local a = math.abs(dv * shift) / lengths[shift]
		across[shift], onward[shift] = a * a, 1 - a * a
	end
	local previousCosts = table.create(width, math.huge)
	local previousDirections = table.create(width, 0)
	local previousHeights = table.create(width, 0)
	local fx, fz = -math.sin(yaw), -math.cos(yaw)
	previousCosts[mid] = 0
	previousDirections[mid] = math.atan2(fx * r.uz - fz * r.ux, fx * r.ux + fz * r.uz)
	previousHeights[mid] = columns[(mid - 1) * 4 + 1](t0)
	local layers: { { number } } = table.create(cols)
	for i = 1, cols do
		local parents = table.create(width, 0)
		layers[i] = parents
		local costs = table.create(width, math.huge)
		local headings = table.create(width, 0)
		local heights = table.create(width, 0)
		local quarter = dt / 4
		local endT = t0 + dt * i
		local interior = { table.create(quarterWidth), table.create(quarterWidth), table.create(quarterWidth) }
		local row, nearL, nearR, farL, farR = coarse(i), coarse(i - 2), coarse(i + 2), coarse(i - 4), coarse(i + 4)
		local bankT, bankV = {}, {}
		for j = -1, width + 2 do
			local acrossBanks = Gorge.pressure(math.min(row[j-2], row[j+2]) - row[j], math.min(row[j-4], row[j+4]) - row[j])
			local forwardBanks = Gorge.pressure(math.min(nearL[j], nearR[j]) - row[j], math.min(farL[j], farR[j]) - row[j])
			bankT[j] = math.max(0, acrossBanks - forwardBanks)
			bankV[j] = math.max(0, forwardBanks - acrossBanks)
		end
		for b = math.max(1, mid - i * reach), math.min(width, mid + i * reach) do
			local endH = row[b]
			-- A strip narrower than a drivable bend cannot hold a hillside road.
			-- Include adjacent stream beds so a steerable corridor clears the lip.
			local alongT = C.GorgeCost * math.max(bankT[b], 0.9*bankT[b-1], 0.9*bankT[b+1], 0.55*bankT[b-2], 0.55*bankT[b+2])
			local alongV = C.GorgeCost * bankV[b]
			heights[b] = endH
			local best, parent, heading = math.huge, 0, 0
			for _, shift: number in offsets do
				local a = b - shift
				if a < 1 or a > width then continue end
				local len, dir = lengths[shift], directions[shift]
				local cost = previousCosts[a] + len + bendCost * math.abs(dir - previousDirections[a])
				cost += len * (alongT * onward[shift] + alongV * across[shift])
				if cost > best or cost == math.huge then continue end
				local h = previousHeights[a]
				local slope = math.abs(endH - h) / len
				-- Convex pitch penalties cannot cost less than constant pitch over this edge.
				local floorCost = len * (pitchCost * math.max(0, slope - grade) + 400 * math.max(0, slope - peak) ^ 2)
				if cost + floorCost > best + 1e-8 then continue end
				local quarterLen = len / 4
				local j = (a - 1) * 4 + 1
				for q = 1, 4 do
					j += shift
					local nextH = endH
					if q < 4 then
						local row = interior[q]
						nextH = row[j]
						if nextH == nil then
							nextH = columns[j](endT - quarter * (4 - q))
							row[j] = nextH
						end
					end
					slope = math.abs(nextH - h) / quarterLen
					local excess, rock = math.max(0, slope - grade), math.max(0, slope - peak)
					cost += quarterLen * (pitchCost * excess + 400 * rock * rock)
					if cost > best then break end
					h = nextH
				end
				if cost < best or (cost == best and a < parent) then
					best, parent, heading = cost, a, dir
				end
			end
			costs[b], parents[b], headings[b] = best, parent, heading
		end
		previousCosts, previousDirections, previousHeights = costs, headings, heights
	end
	local best, last = math.huge, mid
	local endT = t0 + cols * dt
	for j = 1, width do
		local dist = math.sqrt((tt - endT) ^ 2 + (tv - v0 - (j - mid) * dv) ^ 2)
		local cost = previousCosts[j] + dist
		if cost < best then last, best = j, cost end
	end
	local points: { Point } = table.create(cols + 1)
	for i = cols, 1, -1 do
		points[i + 1] = { t = t0 + i * dt, v = v0 + (last - mid) * dv, s = 0 }
		last = layers[i][last]
	end
	points[1] = { t = t0, v = v0, s = 0 }
	distances(points)
	hillsideBends(f, points)
	distances(points)
	local _, _, _, face = Range.at(r, t0, v0)
	return { points = points, ridge = target.k, endT = endT, fromFace = face }
end

-- Closest point on the corridor and a waypoint a little farther along it.
function Route.ahead(route: Route, t: number, v: number, look: number): (number, number, number)
	local pts = route.points
	local best, at, nearest = math.huge, 0, 2
	local start = math.clamp(2 + math.floor((t - pts[1].t) / (pts[2].t - pts[1].t)), 2, #pts)
	local function test(i: number)
		local a, b = pts[i - 1], pts[i]
		local dt, dv = b.t - a.t, b.v - a.v
		local u = math.clamp(((t - a.t) * dt + (v - a.v) * dv) / (dt * dt + dv * dv), 0, 1)
		local miss = (a.t + u * dt - t) ^ 2 + (a.v + u * dv - v) ^ 2
		if miss < best or (miss == best and i < nearest) then
			best, at, nearest = miss, a.s + (b.s - a.s) * u, i
		end
	end
	test(start)
	for i = start - 1, 2, -1 do
		if t > pts[i].t and (t - pts[i].t) ^ 2 > best then break end
		test(i)
	end
	for i = start + 1, #pts do
		if pts[i - 1].t > t and (pts[i - 1].t - t) ^ 2 > best then break end
		test(i)
	end
	for i = nearest, #pts do
		local a, b = pts[i - 1], pts[i]
		if at + look <= b.s then
			local u = (at + look - a.s) / (b.s - a.s)
			return a.t + u * (b.t - a.t), a.v + u * (b.v - a.v), math.sqrt(best)
		end
	end
	local last = pts[#pts]
	return last.t, last.v, math.sqrt(best)
end

return Route
