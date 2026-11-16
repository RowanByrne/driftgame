--!strict
--!native
-- OffRoadGround: the drawn ground past the road's runoff, as the car feels it (T-258,
-- features/car-edges.md).
--
-- Past the grass the car drives on the same ground the player sees: the mountain with the
-- road pressed into it (`Road/Ground.at`), which is what `Drift/GroundMeshView` draws. It is
-- read off a LATTICE of that ground, every `Config.Drift.OffRoad.Lattice` studs, worked out
-- the first time a point near it is asked for and kept: a car on the grass asks for a few
-- dozen new points a second, where asking `Ground.at` itself for every wheel and every corner
-- of the car every step would cost milliseconds a frame. Between lattice points the height is
-- bilinear, so it is continuous, and its slope is the one of that bilinear patch.
--
-- WHAT IS KEPT IS DROPPED when the road changes near it: a section laid, or the road behind
-- trimmed, within `Ground.reach()` of a kept point (the ground near a road depends on every
-- station of it within reach, and a station within `KEEP_SHORT` of the road's end can still
-- change, so that much before the old end is checked too). And when it grows past `Keep`
-- points. The ground asked for again costs a millisecond or so, once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)

local OffRoadGround = {}

export type Stats = {
	points: number, -- lattice points worked out (`Ground.at` calls), this session
	contexts: number, -- station gatherings (`Ground.context`)
	drops: number, -- times everything kept was dropped
	kept: number, -- points held now
}

export type OffRoadGround = {
	-- the ground's height at (x, z), and its slope there: dy/dx and dy/dz
	sample: (x: number, z: number) -> (number, number, number),
	stats: Stats,
}

-- How often along new road its distance to what is kept is checked, in studs.
local CHECK_STEP = 16
-- Stations this near the road's end can still change (`Road/Ground` keeps none of them).
local KEEP_SHORT = 300

local function key(i: number, j: number): number
	return (i + 1048576) * 2097152 + (j + 1048576)
end

function OffRoadGround.new(spline: Spline.Spline, field: Ground.Field): OffRoadGround
	local O = Config.Drift.OffRoad
	local step = O.Lattice
	local box = O.ContextBox
	local keep = O.Keep

	local heights: { [number]: number } = {}
	local count = 0
	local ctx: Ground.Context? = nil
	local cx0, cz0, cx1, cz1 = 0, 0, 0, 0
	-- what the road was when the points were worked out
	local length, first = spline.length, spline.firstSample

	-- the box round every kept point
	local bx0, bz0, bx1, bz1 = math.huge, math.huge, -math.huge, -math.huge

	local stats: Stats = { points = 0, contexts = 0, drops = 0, kept = 0 }

	local function drop()
		table.clear(heights)
		count = 0
		ctx = nil
		bx0, bz0, bx1, bz1 = math.huge, math.huge, -math.huge, -math.huge
		stats.drops += 1
		stats.kept = 0
	end

	-- Does the road between s0 and s1 come within reach of anything kept?
	local function touches(s0: number, s1: number): boolean
		if count == 0 then
			return false
		end
		local reach = Ground.reach() + CHECK_STEP
		local s = math.max(s0, 0)
		while true do
			local x, z = spline:planAt(math.min(s, s1))
			if x > bx0 - reach and x < bx1 + reach and z > bz0 - reach and z < bz1 + reach then
				return true
			end
			if s >= s1 then
				return false
			end
			s += CHECK_STEP
		end
	end

	-- Has the road changed near what is kept since it was worked out?
	local function stale(): boolean
		local len, fst = spline.length, spline.firstSample
		if len == length and fst == first then
			return false
		end
		-- the stations gathered are the old road's, whatever is kept
		ctx = nil
		local changed = false
		if len ~= length and touches(math.min(length, len) - KEEP_SHORT, math.max(length, len)) then
			changed = true
		end
		if not changed and fst ~= first then
			local a, b = math.min(fst, first) * spline.step, math.max(fst, first) * spline.step
			changed = touches(a - CHECK_STEP, b + CHECK_STEP)
		end
		length, first = len, fst
		return changed
	end

	local function point(i: number, j: number): number
		local k = key(i, j)
		local y = heights[k]
		if y then
			return y
		end
		local x, z = i * step, j * step
		local c = ctx
		if not c or x < cx0 or x > cx1 or z < cz0 or z > cz1 then
			cx0, cz0, cx1, cz1 = x - box, z - box, x + box, z + box
			c = Ground.context(field, spline, cx0, cz0, cx1, cz1)
			ctx = c
			stats.contexts += 1
		end
		local h = Ground.at(c :: Ground.Context, x, z)
		heights[k] = h
		count += 1
		bx0, bz0 = math.min(bx0, x), math.min(bz0, z)
		bx1, bz1 = math.max(bx1, x), math.max(bz1, z)
		stats.points += 1
		stats.kept = count
		return h
	end

	local function sample(x: number, z: number): (number, number, number)
		if count > keep or stale() then
			drop()
		end
		local fx, fz = x / step, z / step
		local i, j = math.floor(fx), math.floor(fz)
		local u, v = fx - i, fz - j
		local a = point(i, j)
		local b = point(i + 1, j)
		local c = point(i, j + 1)
		local d = point(i + 1, j + 1)
		local y = a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
		local gx = ((b - a) + (a - b - c + d) * v) / step
		local gz = ((c - a) + (a - b - c + d) * u) / step
		return y, gx, gz
	end

	return {
		sample = sample,
		stats = stats,
	}
end

return OffRoadGround
