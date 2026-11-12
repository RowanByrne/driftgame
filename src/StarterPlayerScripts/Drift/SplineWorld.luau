--!strict
-- SplineWorld: the drift model's world questions answered from the spline road's own maths
-- (features/spline-road.md "Collision, from the curve", T-134).
--
-- The model asks four things of a world (`Model.World`): the ground under a point, how far
-- the car may move before a wall, which way is out of a wall it is in, and where a step's
-- face is. On the spline road NONE of them touches an instance. The road's mesh is purely
-- visual -- nothing collides with it, nothing can query it -- and every answer here is the
-- curve's arithmetic:
--
--   probe        the surface's height and normal at the point's (s, d) -- `Spline.ground`.
--                Nothing past the road's edge, so a car that leaves it falls
--   sweep        the barrier line is |d| = Width / 2 either side of the centre; the car's
--                footprint is six points (its corners and the middle of each long side),
--                and the step is cut where the first of them would cross it
--   penetration  the deepest point already past the line, and the way back in
--   edge         nothing: the road has no steps
--
-- WRAPPED ROUND ANOTHER WORLD, not instead of it: the live world (`World.live`) still
-- answers wherever the spline does not -- the playground, the track, the garage -- and its
-- walls still count on the road, so anything solid that is ever put there is still solid.
-- The spline answers first wherever the car is over the road.
--
-- IT KEEPS ITS OWN `s`, the car's distance along the road, and starts every lookup from
-- it: two or three Newton steps, a few microseconds (`Road/Spline`). Only when that fails
-- -- a respawn, a teleport, the first step -- does it search the road's grid.
--
-- THE TWO BARRIERS: the side barriers switch off (`setRails`), exactly as the piece road's
-- do (the TEST ONLY guardrail button); the closing barrier behind the window never does
-- (`setClosing`), as on the piece road.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)
local Model = require(script.Parent.Model)

local SplineWorld = {}

-- The same margin `Drift/World` keeps from a part it is pushed out of, for the same reason:
-- the car is held a hair clear of the line rather than exactly on it.
local PENETRATION_MARGIN = 0.05

-- How far either side of the road's edge a point may be and still be asked about. A point
-- further out than this is not near the road at all.
local REACH_PAST_EDGE = 30

export type Stats = {
	probes: number,
	hits: number,
	searches: number, -- lookups that fell back to the grid
	sweeps: number,
	wallStops: number,
	closingStops: number,
	pushes: number,
}

export type SplineWorld = Model.World & {
	spline: Spline.Spline,
	base: Model.World?,
	hint: number?,
	rails: boolean,
	closing: number?,
	stats: Stats,
	setRails: (on: boolean) -> (),
	setClosing: (s: number?) -> (),
	locate: (pos: Vector3) -> (number?, number?),
	destroy: () -> (),
}

function SplineWorld.new(spline: Spline.Spline, base: Model.World?): SplineWorld
	local C = Config.Drift
	local R = Config.Road
	local half = R.Width * 0.5
	local reach = half + REACH_PAST_EDGE
	local rayTop = C.GroundRayUp
	local rayBottom = C.GroundRayUp - C.GroundRayLength
	-- the car's box, as `Drift/World` has it: its body, not its track
	local bw, bl = C.BodyWidth * 0.5, C.BodyLength * 0.5
	local bh = C.BodyHeight * 0.6 * 0.5

	local self: any = {
		spline = spline,
		base = base,
		hint = nil,
		rails = true,
		closing = nil,
		stats = { probes = 0, hits = 0, searches = 0, sweeps = 0, wallStops = 0, closingStops = 0, pushes = 0 },
	}
	local stats: Stats = self.stats

	-- (s, d) of a plan point, from the hint when there is one, else by search. Returns nil
	-- for a point not within `reach` of the centre line.
	local function locate(x: number, z: number, hint: number?): (number?, number?)
		local s, d
		if hint then
			s, d = spline:projectFrom(x, z, hint)
		end
		if not s or not d or math.abs(d) > reach then
			stats.searches += 1
			s, d = spline:project(x, z, reach)
		end
		if not s or not d or math.abs(d) > reach then
			return nil, nil
		end
		return s, d
	end

	function self.locate(pos: Vector3): (number?, number?)
		local s, d = locate(pos.X, pos.Z, self.hint)
		if s then
			self.hint = s
		end
		return s, d
	end

	function self.setRails(on: boolean)
		self.rails = on == true
	end

	function self.setClosing(s: number?)
		self.closing = s
	end

	------------------------------------------------------------------ the ground
	function self.probe(pos: Vector3): Model.Hit?
		stats.probes += 1
		local s, d = locate(pos.X, pos.Z, self.hint)
		if s and d and math.abs(d) <= half then
			self.hint = s
			local y = spline:heightAt(s) + d * math.tan(spline:bankAt(s))
			-- the same window a ground ray has: from GroundRayUp above the point down
			-- GroundRayLength. A car far under the road does not find it over its head.
			local dy = y - pos.Y
			if dy <= rayTop and dy >= rayBottom then
				stats.hits += 1
				return { y = y, normal = spline:normalAt(s, d), grip = C.GripTarmac, score = C.ScoreTarmac }
			end
		end
		if base then
			return base.probe(pos)
		end
		return nil
	end

	------------------------------------------------------------------ the walls
	-- THE CAR'S BOX IS TILTED ON TO THE SURFACE, as `Drift/World` tilts it (T-073), so its
	-- shadow on the ground is what meets a barrier: on a 10-degree bank its top corner leans
	-- out past its wheels by `bh x sin(10)`. Same two numbers `World.penetration` uses, from
	-- the spline's own normal; flat in the air, as there.
	local function reach(pos: Vector3, yaw: number): (number, number)
		local flatFwd, flatRight = Model.axes(yaw)
		local s, d = locate(pos.X, pos.Z, self.hint)
		if not s or not d or math.abs(d) > half then
			return bw, bl
		end
		local y = spline:heightAt(s) + d * math.tan(spline:bankAt(s))
		if pos.Y - (y + C.RideHeight) > C.AirborneMargin then
			return bw, bl
		end
		local up = spline:normalAt(s, d)
		local right = flatFwd:Cross(up)
		if right.Magnitude < 1e-4 then
			return bw, bl
		end
		right = right.Unit
		local fwd = up:Cross(right)
		local hw = bw * math.sqrt(right.X * right.X + right.Z * right.Z) + bh * math.abs(up:Dot(flatRight))
		local hl = bl * math.sqrt(fwd.X * fwd.X + fwd.Z * fwd.Z) + bh * math.abs(up:Dot(flatFwd))
		return hw, hl
	end

	-- The six points of the car's footprint at a position: corners and side middles.
	local SIDES = { { 1, 1 }, { 1, 0 }, { 1, -1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }
	local function footprint(pos: Vector3, yaw: number, out: { number })
		local fwd, right = Model.axes(yaw)
		local hw, hl = reach(pos, yaw)
		for i, p in SIDES do
			local ox = right.X * hw * p[1] + fwd.X * hl * p[2]
			local oz = right.Z * hw * p[1] + fwd.Z * hl * p[2]
			out[i * 2 - 1] = pos.X + ox
			out[i * 2] = pos.Z + oz
		end
	end

	-- Is a barrier standing at this height? A car well above the road (a jump) or well
	-- under it (falling) is not beside a wall.
	local function wallAt(s: number, d: number, carY: number): boolean
		local edgeY = spline:heightAt(s) + d * math.tan(spline:bankAt(s))
		return carY - bh < edgeY + R.BarrierHeight and carY + bh > edgeY - R.Thickness
	end

	-- How far a footprint point is inside each constraint (positive is clear), and the
	-- wall's normal. Side barriers: |d| <= half. Closing barrier: ahead of its plane.
	local function sideMargin(s: number, d: number): (number, Vector3)
		local yaw = spline:yawAt(s)
		local rx, rz = math.cos(yaw), -math.sin(yaw)
		local sign = if d >= 0 then 1 else -1
		return half - math.abs(d), Vector3.new(-sign * rx, 0, -sign * rz)
	end

	-- THE CLOSING BARRIER IS A SLAB, `CLOSING_DEPTH` studs thick, its front face at `closing`:
	-- solid from both sides, as the piece road's box is. A car in front of it cannot reverse
	-- through it, and a car left behind it (the slower of two players: the barrier follows
	-- whoever is furthest) is stopped at its back face rather than being pushed through to
	-- the front. Measured from the front face, positive ahead.
	local CLOSING_DEPTH = 1
	local function closingMargin(x: number, z: number): (number?, Vector3?)
		local sc = self.closing
		if not sc then
			return nil, nil
		end
		local cx, cz = spline:planAt(sc)
		local yaw = spline:yawAt(sc)
		local fx, fz = -math.sin(yaw), -math.cos(yaw)
		local ex, ez = x - cx, z - cz
		-- only across the road and its barriers: the plane is not infinite
		local lateral = ex * math.cos(yaw) - ez * math.sin(yaw)
		if math.abs(lateral) > half + R.BarrierThickness + 1 then
			return nil, nil
		end
		return ex * fx + ez * fz, Vector3.new(fx, 0, fz)
	end

	local fromPts: { number } = table.create(12, 0)
	local toPts: { number } = table.create(12, 0)

	-- The first moment, as a share of the step, at which any footprint point crosses a
	-- constraint, and that constraint's normal.
	local function firstContact(from: Vector3, to: Vector3, yaw: number): (number?, Vector3?)
		footprint(from, yaw, fromPts)
		footprint(to, yaw, toPts)
		local hint = self.hint
		local best, bestN = math.huge, nil :: Vector3?
		local function consider(m0: number, m1: number, n: Vector3)
			if m1 >= 0 then
				return
			end
			local t
			if m0 <= 0 then
				if m1 >= m0 then
					return -- already in, and coming out: penetration's business
				end
				t = 0
			else
				t = m0 / (m0 - m1)
			end
			if t < best then
				best, bestN = t, n
			end
		end
		for i = 1, 6 do
			local x0, z0 = fromPts[i * 2 - 1], fromPts[i * 2]
			local x1, z1 = toPts[i * 2 - 1], toPts[i * 2]
			if self.rails then
				local s0, d0 = locate(x0, z0, hint)
				local s1, d1 = locate(x1, z1, s0 or hint)
				if s0 and d0 and s1 and d1 and wallAt(s1, d1, to.Y) then
					local m0 = sideMargin(s0, d0)
					local m1, n = sideMargin(s1, d1)
					-- the same side of the road at both ends, or it is not one wall
					if (d0 >= 0) == (d1 >= 0) then
						consider(m0, m1, n)
					end
				end
			end
			local c0 = closingMargin(x0, z0)
			local c1, cn = closingMargin(x1, z1)
			if c0 and c1 and cn then
				if c0 > -CLOSING_DEPTH * 0.5 then
					consider(c0, c1, cn) -- in front of it (or in its front half)
				else
					-- behind it: its back face is the wall, facing back down the road
					consider(-CLOSING_DEPTH - c0, -CLOSING_DEPTH - c1, -cn)
				end
			end
		end
		if bestN then
			return best, bestN
		end
		return nil, nil
	end

	function self.sweep(from: Vector3, to: Vector3, yaw: number): (Vector3?, Vector3?)
		stats.sweeps += 1
		local delta = to - from
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local travel = flat.Magnitude
		local safe: Vector3?, normal: Vector3? = nil, nil
		if travel > 1e-4 then
			local t, n = firstContact(from, Vector3.new(to.X, from.Y, to.Z), yaw)
			if t and n then
				local allowed = math.max(t * travel - C.WallPush, 0)
				safe, normal = from + (flat / travel) * allowed, n
				if self.closing and n:Dot(Vector3.new(-math.sin(spline:yawAt(self.closing)), 0, -math.cos(spline:yawAt(self.closing)))) > 0.999 then
					stats.closingStops += 1
				else
					stats.wallStops += 1
				end
			end
		end
		-- anything solid in the live world still counts: the nearer stop wins
		if base and base.sweep then
			local bSafe, bNormal = base.sweep(from, to, yaw)
			if bSafe and bNormal then
				if not safe or (bSafe - from).Magnitude < ((safe :: Vector3) - from).Magnitude then
					safe, normal = bSafe, bNormal
				end
			end
		end
		return safe, normal
	end

	function self.penetration(pos: Vector3, yaw: number): (Vector3?, number)
		footprint(pos, yaw, toPts)
		local worst, worstN = 0, nil :: Vector3?
		local hint = self.hint
		for i = 1, 6 do
			local x, z = toPts[i * 2 - 1], toPts[i * 2]
			if self.rails then
				local s, d = locate(x, z, hint)
				if s and d and wallAt(s, d, pos.Y) then
					local m, n = sideMargin(s, d)
					local depth = PENETRATION_MARGIN - m
					if depth > worst then
						worst, worstN = depth, n
					end
				end
			end
			local c, cn = closingMargin(x, z)
			-- inside the slab: out of whichever face is nearer
			if c and cn and c < PENETRATION_MARGIN and c > -CLOSING_DEPTH - PENETRATION_MARGIN then
				local forward = PENETRATION_MARGIN - c
				local back = c + CLOSING_DEPTH + PENETRATION_MARGIN
				local depth, dir = forward, cn
				if back < forward then
					depth, dir = back, -cn
				end
				if depth > worst then
					worst, worstN = depth, dir
				end
			end
		end
		local dir: Vector3?, depth = worstN, worst
		if base and base.penetration then
			local bDir, bDepth = base.penetration(pos, yaw)
			if bDir and bDepth > depth then
				dir, depth = bDir, bDepth
			end
		end
		if dir and depth > 0 then
			if dir == worstN then
				stats.pushes += 1
			end
			return dir, depth
		end
		return nil, 0
	end

	function self.edge(from: Vector3, to: Vector3): Vector3?
		if base and base.edge then
			return base.edge(from, to)
		end
		return nil
	end

	function self.destroy()
		local b: any = base
		if b and b.destroy then
			b.destroy()
		end
	end

	return self :: SplineWorld
end

return SplineWorld
