--!strict
--!native
-- Survey a corridor across the next mountainside. Layers advance into the range;
-- edges can traverse several cells sideways, including a return onto the other flank.
-- The spline generator still fits and clearance-checks every bend it actually lays.
local Config = require(game.ReplicatedStorage.Shared.Config)
local Ground = require(script.Parent.Ground)
local Range = require(script.Parent.Range)

local Route = {}
type Point = { t: number, v: number, s: number }
export type Route = { points: { Point }, ridge: number, endT: number }

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
		for b = math.max(1, mid - i * reach), math.min(width, mid + i * reach) do
			local endH = columns[(b - 1) * 4 + 1](endT)
			heights[b] = endH
			local best, parent, heading = math.huge, 0, 0
			for _, shift: number in offsets do
				local a = b - shift
				if a < 1 or a > width then continue end
				local len, dir = lengths[shift], directions[shift]
				local cost = previousCosts[a] + len + bendCost * math.abs(dir - previousDirections[a])
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
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		b.s = a.s + math.sqrt((b.t - a.t) ^ 2 + (b.v - a.v) ^ 2)
	end
	return { points = points, ridge = target.k, endT = endT }
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
