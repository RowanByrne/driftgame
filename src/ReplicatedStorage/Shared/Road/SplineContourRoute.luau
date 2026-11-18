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
type Cell = { cost: number, prev: number, dir: number }

function Route.new(f: Ground.Field, x: number, z: number, yaw: number, target: { x: number, z: number, k: number }): Route
	local r, C = f.range, Config.Range
	local t0, v0 = Range.frame(r, x, z)
	local tt, tv = Range.frame(r, target.x, target.z)
	local cols = math.clamp(math.ceil((tt - t0 + 360) / C.CorridorForward), 4, C.CorridorColumns)
	local dt, dv, half = C.CorridorForward, C.CorridorAcross, C.CorridorHalfWidth
	local grade = math.tan(math.rad(C.ContourGrade))
	local peak = math.tan(math.rad(Config.Spline.MaxGrade))
	local heights: { [number]: { [number]: number } } = {}
	local function height(i: number, j: number): number
		local row = heights[i]
		if not row then row = {}; heights[i] = row end
		local h = row[j]
		if h == nil then
			local wx, wz = Range.world(r, t0 + dt * i / 4, v0 + dv * j / 4)
			h = Ground.h(f, wx, wz)
			row[j] = h
		end
		return h
	end
	local sizes, directions = {}, {}
	for shift = -C.CorridorReach, C.CorridorReach do
		sizes[shift] = math.sqrt(dt * dt + (dv * shift) ^ 2)
		directions[shift] = math.atan2(dv * shift, dt)
	end
	local fx, fz = -math.sin(yaw), -math.cos(yaw)
	local initial = math.atan2(fx * r.uz - fz * r.ux, fx * r.ux + fz * r.uz)
	local layers: { [number]: { [number]: Cell } } = { [0] = { [0] = { cost = 0, prev = 0, dir = initial } } }
	for i = 1, cols do
		local row: { [number]: Cell } = {}
		layers[i] = row
		for a, cell in layers[i - 1] do
			for shift = -C.CorridorReach, C.CorridorReach do
				local b = a + shift
				if math.abs(b) > half then continue end
				local len = sizes[shift]
				local dir = directions[shift]
				local cost = cell.cost + len + C.CorridorBendCost * math.abs(dir - cell.dir)
				local old = row[b]
				if old and cost >= old.cost then continue end
				local h = height((i - 1) * 4, a * 4)
				for q = 1, 4 do
					local nextH = height((i - 1) * 4 + q, a * 4 + q * shift)
					local slope = math.abs(nextH - h) * 4 / len
					local excess = math.max(0, slope - grade)
					local rock = math.max(0, slope - peak)
					cost += (len / 4) * (C.CorridorPitchCost * excess + 400 * rock * rock)
					h = nextH
				end
				if not old or cost < old.cost then
					row[b] = { cost = cost, dir = dir, prev = a }
				end
			end
		end
	end
	local best, last = math.huge, 0
	local endT = t0 + cols * dt
	for j, cell in layers[cols] do
		local dist = math.sqrt((tt - endT) ^ 2 + (tv - v0 - j * dv) ^ 2)
		local cost = cell.cost + dist
		if cost < best then last, best = j, cost end
	end
	local points: { Point } = table.create(cols + 1)
	for i = cols, 0, -1 do
		points[i + 1] = { t = t0 + i * dt, v = v0 + last * dv, s = 0 }
		last = layers[i][last].prev
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		b.s = a.s + math.sqrt((b.t - a.t) ^ 2 + (b.v - a.v) ^ 2)
	end
	return { points = points, ridge = target.k, endT = endT }
end

-- Closest point on the corridor and a waypoint a little farther along it.
function Route.ahead(route: Route, t: number, v: number, look: number): (number, number, number)
	local pts = route.points
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
	for i = 2, #pts do
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
