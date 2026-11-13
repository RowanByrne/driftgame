--!strict
-- SplineWorld: the drift model's world questions answered from the spline road's own maths
-- (features/spline-road.md "Collision, from the curve", T-134; features/mountain-road.md
-- "Driving on it, from the maths", T-140).
--
-- The model asks four things of a world (`Model.World`): the ground under a point, how far
-- the car may move before a wall, which way is out of a wall it is in, and where a step's
-- face is. On the spline road NONE of them touches an instance. The road's mesh is purely
-- visual -- nothing collides with it, nothing can query it -- and every answer here is the
-- curve's arithmetic:
--
--   probe        the ground at the point's (s, d): the tarmac (`GripTarmac`), the grass
--                runoff either side (`GripGrass`, `ScoreGrass`), and NOTHING past a
--                cliff's lip, so a car that goes over falls
--   sweep        the walls: a rock face or a hedge at the runoff's outer edge, and a K-rail
--                on the tarmac's edge where one stands. The car's footprint is six points
--                (its corners and the middle of each long side), and the step is cut where
--                the first of them would cross a wall. A cliff is not a wall. A grove's
--                tree trunks (T-183) are circles met by the whole box (`Road/SplineGrove`)
--   penetration  the deepest point already past a wall, and the way back out
--   edge         nothing: the road has no steps
--
-- THERE ARE NO SIDE BARRIERS ANY MORE (T-140): running wide costs grip on the grass, then
-- the edge decides. The closing barrier behind the window stays, across the tarmac and both
-- runoffs, so nobody drives round it on the grass.
--
-- WRAPPED ROUND ANOTHER WORLD, not instead of it: the live world (`World.live`) still
-- answers wherever the spline does not -- the playground, the track, the garage -- and its
-- walls still count on the road, so anything solid that is ever put there is still solid.
-- The spline answers first wherever the car is over the road.
--
-- IT KEEPS ITS OWN `s`, the car's distance along the road, and starts every lookup from
-- it: two or three Newton steps, a few microseconds (`Road/Spline`). Only when that fails
-- -- a respawn, a teleport, the first step -- does it search the road's grid.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)
local SplineGrove = require(ReplicatedStorage.Shared.Road.SplineGrove)
local Model = require(script.Parent.Model)

local SplineWorld = {}

-- The same margin `Drift/World` keeps from a part it is pushed out of, for the same reason:
-- the car is held a hair clear of the line rather than exactly on it.
local PENETRATION_MARGIN = 0.05

-- How far past the widest runoff a point may be and still be asked about. A point further
-- out than this is not near the road at all.
local REACH_PAST_EDGE = 30

-- How a wall stop is counted.
local KIND_SIDE, KIND_KRAIL, KIND_CLOSING, KIND_TREE = 1, 2, 3, 4

export type Stats = {
	probes: number,
	hits: number,
	grass: number, -- probes that found grass
	gravel: number, -- probes that found gravel (a tight cliff stretch, T-181)
	overCliff: number, -- probes past a cliff's lip: nothing under them
	searches: number, -- lookups that fell back to the grid
	sweeps: number,
	wallStops: number, -- a rock face or a hedge
	kRailStops: number,
	closingStops: number,
	treeStops: number, -- a grove's tree trunk (T-183)
	pushes: number,
}

export type SplineWorld = Model.World & {
	spline: Spline.Spline,
	base: Model.World?,
	hint: number?,
	closing: number?,
	stats: Stats,
	setClosing: (s: number?) -> (),
	locate: (pos: Vector3) -> (number?, number?),
	destroy: () -> (),
}

function SplineWorld.new(spline: Spline.Spline, base: Model.World?): SplineWorld
	local C = Config.Drift
	local R = Config.Road
	local T = Config.Spline.Terrain
	local half = R.Width * 0.5
	local reach = half + T.RunoffMax + REACH_PAST_EDGE
	local rayTop = C.GroundRayUp
	local rayBottom = C.GroundRayUp - C.GroundRayLength
	-- the car's box, as `Drift/World` has it: its body, not its track
	local bw, bl = C.BodyWidth * 0.5, C.BodyLength * 0.5
	local bh = C.BodyHeight * 0.6 * 0.5
	local railT = T.KRailThickness

	local self: any = {
		spline = spline,
		base = base,
		hint = nil,
		closing = nil,
		stats = {
			probes = 0,
			hits = 0,
			grass = 0,
			gravel = 0,
			overCliff = 0,
			searches = 0,
			sweeps = 0,
			wallStops = 0,
			kRailStops = 0,
			closingStops = 0,
			treeStops = 0,
			pushes = 0,
		},
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

	function self.setClosing(s: number?)
		self.closing = s
	end

	------------------------------------------------------------------ the ground
	function self.probe(pos: Vector3): Model.Hit?
		stats.probes += 1
		local s, d = locate(pos.X, pos.Z, self.hint)
		if s and d then
			local kind = spline:groundKind(s, d)
			if kind == nil then
				stats.overCliff += 1
			else
				self.hint = s
				local y = spline:terrainY(s, d)
				-- the same window a ground ray has: from GroundRayUp above the point down
				-- GroundRayLength. A car far under the road does not find it over its head.
				local dy = y - pos.Y
				if dy <= rayTop and dy >= rayBottom then
					stats.hits += 1
					if kind == Spline.TARMAC then
						return { y = y, normal = spline:normalAt(s, d), grip = C.GripTarmac, score = C.ScoreTarmac }
					end
					if kind == Spline.GRAVEL then
						stats.gravel += 1
						return { y = y, normal = spline:terrainNormal(s, d), grip = C.GripGravel, score = C.ScoreGravel }
					end
					stats.grass += 1
					return { y = y, normal = spline:terrainNormal(s, d), grip = C.GripGrass, score = C.ScoreGrass }
				end
			end
		end
		if base then
			return base.probe(pos)
		end
		return nil
	end

	------------------------------------------------------------------ the walls
	-- THE CAR'S BOX IS TILTED ON TO THE SURFACE, as `Drift/World` tilts it (T-073), so its
	-- shadow on the ground is what meets a wall: on a 10-degree bank its top corner leans
	-- out past its wheels by `bh x sin(10)`. Same two numbers `World.penetration` uses, from
	-- the ground's own normal; flat in the air, as there.
	local function boxReach(pos: Vector3, yaw: number): (number, number)
		local flatFwd, flatRight = Model.axes(yaw)
		local s, d = locate(pos.X, pos.Z, self.hint)
		if not s or not d or not spline:groundKind(s, d) then
			return bw, bl
		end
		local y = spline:terrainY(s, d)
		if pos.Y - (y + C.RideHeight) > C.AirborneMargin then
			return bw, bl
		end
		local up = spline:terrainNormal(s, d)
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
		local hw, hl = boxReach(pos, yaw)
		for i, p in SIDES do
			local ox = right.X * hw * p[1] + fwd.X * hl * p[2]
			local oz = right.Z * hw * p[1] + fwd.Z * hl * p[2]
			out[i * 2 - 1] = pos.X + ox
			out[i * 2] = pos.Z + oz
		end
	end

	-- Is a wall `height` tall, standing on the ground at (s, d), beside a car at `carY`? A
	-- car well above it (a jump) or well under it (falling past a cliff) is not.
	local function standsBeside(s: number, d: number, height: number, carY: number): boolean
		local footY = spline:terrainY(s, d)
		return carY - bh < footY + height and carY + bh > footY - R.Thickness
	end

	-- THE SIDE WALL at (s, d): a rock face or a hedge on d's side, at the runoff's outer
	-- edge. Its line is |d| = half + runoff(s); how far a point is inside it (positive is
	-- clear) and the way back toward the road. The runoff narrows and widens along the
	-- road, so the wall line leans: its normal carries that lean, which is what lets a car
	-- grind along a narrowing runoff rather than stick in it.
	local function sideWall(s: number, d: number): (number, Vector3)
		local side = if d >= 0 then 1 else -1
		local edge = half + spline:runoffAt(s, side)
		local yaw = spline:yawAt(s)
		local rx, rz = math.cos(yaw), -math.sin(yaw)
		local fx, fz = -math.sin(yaw), -math.cos(yaw)
		local lean = (spline:runoffAt(s + 0.5, side) - spline:runoffAt(s - 0.5, side)) / math.max(0.2, 1 + spline:curvatureAt(s) * d)
		local n = Vector3.new(-side * rx + lean * fx, 0, -side * rz + lean * fz).Unit
		return edge - math.abs(d), n
	end

	local function sideWallStands(s: number, d: number, carY: number): boolean
		local side = if d >= 0 then 1 else -1
		local kind = spline:edgeAt(s, side)
		if kind == Spline.CLIFF then
			return false
		end
		local height = if kind == Spline.ROCK then T.RockHeight[1] else T.HedgeHeight
		return standsBeside(s, side * (half + spline:runoffAt(s, side)), height, carY)
	end

	-- A K-RAIL is a slab on the tarmac's edge, `railT` thick: solid from both sides, as the
	-- closing barrier is. Is one standing at (s, d) for a car at `carY`?
	local function kRailStands(s: number, d: number, carY: number): (number?, number?)
		local side = if d >= 0 then 1 else -1
		local a, b = spline:kRailAt(s, side)
		if not a then
			return nil, nil
		end
		if not standsBeside(s, side * half, T.KRailHeight, carY) then
			return nil, nil
		end
		return a, b
	end

	local function lateralNormal(s: number, side: number): Vector3
		local yaw = spline:yawAt(s)
		return Vector3.new(side * math.cos(yaw), 0, side * -math.sin(yaw))
	end

	-- THE CLOSING BARRIER IS A SLAB, `CLOSING_DEPTH` studs thick, its front face at `closing`:
	-- solid from both sides, as the piece road's box is. A car in front of it cannot reverse
	-- through it, and a car left behind it (the slower of two players: the barrier follows
	-- whoever is furthest) is stopped at its back face rather than being pushed through to
	-- the front. Measured from the front face, positive ahead. It reaches across the tarmac
	-- and the runoff either side, to the edges.
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
		-- only across the road and its runoff: the plane is not infinite
		local lateral = ex * math.cos(yaw) - ez * math.sin(yaw)
		local side = if lateral >= 0 then 1 else -1
		if math.abs(lateral) > half + spline:runoffAt(sc, side) + T.EdgeDepth + 1 then
			return nil, nil
		end
		return ex * fx + ez * fz, Vector3.new(fx, 0, fz)
	end

	local fromPts: { number } = table.create(12, 0)
	local toPts: { number } = table.create(12, 0)

	-- The first moment, as a share of the step, at which any footprint point crosses a
	-- wall, that wall's normal, and what kind of wall it was.
	local function firstContact(from: Vector3, to: Vector3, yaw: number): (number?, Vector3?, number)
		footprint(from, yaw, fromPts)
		footprint(to, yaw, toPts)
		local hint = self.hint
		local best, bestN, bestKind = math.huge, nil :: Vector3?, 0
		local function consider(m0: number, m1: number, n: Vector3, kind: number)
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
				best, bestN, bestKind = t, n, kind
			end
		end
		for i = 1, 6 do
			local x0, z0 = fromPts[i * 2 - 1], fromPts[i * 2]
			local x1, z1 = toPts[i * 2 - 1], toPts[i * 2]
			local s0, d0 = locate(x0, z0, hint)
			local s1, d1 = locate(x1, z1, s0 or hint)
			-- the same side of the road at both ends, or it is not one wall
			if s0 and d0 and s1 and d1 and (d0 >= 0) == (d1 >= 0) then
				local side = if d1 >= 0 then 1 else -1
				if sideWallStands(s1, d1, to.Y) then
					local m0 = sideWall(s0, d0)
					local m1, n = sideWall(s1, d1)
					consider(m0, m1, n, KIND_SIDE)
				end
				-- a K-rail standing at both ends: whichever face the point started on
				if kRailStands(s1, d1, to.Y) and spline:kRailAt(s0, side) then
					local a0, a1 = math.abs(d0), math.abs(d1)
					if a0 < half + railT * 0.5 then
						consider(half - a0, half - a1, lateralNormal(s1, -side), KIND_KRAIL)
					else
						consider(a0 - half - railT, a1 - half - railT, lateralNormal(s1, side), KIND_KRAIL)
					end
				end
			end
			local c0 = closingMargin(x0, z0)
			local c1, cn = closingMargin(x1, z1)
			if c0 and c1 and cn then
				if c0 > -CLOSING_DEPTH * 0.5 then
					consider(c0, c1, cn, KIND_CLOSING) -- in front of it (or in its front half)
				else
					-- behind it: its back face is the wall, facing back down the road
					consider(-CLOSING_DEPTH - c0, -CLOSING_DEPTH - c1, -cn, KIND_CLOSING)
				end
			end
		end
		-- A GROVE'S TREE TRUNKS (T-183): circles against the car's whole box, not its six points
		if hint then
			local hw, hl = boxReach(from, yaw)
			local fwd, right = Model.axes(yaw)
			local m0, m1, n = SplineGrove.sweep(spline, hint, from, to, fwd, right, hw, hl, bh)
			if m0 and m1 and n then
				consider(m0, m1, n, KIND_TREE)
			end
		end
		if bestN then
			return best, bestN, bestKind
		end
		return nil, nil, 0
	end

	function self.sweep(from: Vector3, to: Vector3, yaw: number): (Vector3?, Vector3?)
		stats.sweeps += 1
		local delta = to - from
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local travel = flat.Magnitude
		local safe: Vector3?, normal: Vector3? = nil, nil
		if travel > 1e-4 then
			local t, n, kind = firstContact(from, Vector3.new(to.X, from.Y, to.Z), yaw)
			if t and n then
				local allowed = math.max(t * travel - C.WallPush, 0)
				safe, normal = from + (flat / travel) * allowed, n
				if kind == KIND_CLOSING then
					stats.closingStops += 1
				elseif kind == KIND_KRAIL then
					stats.kRailStops += 1
				elseif kind == KIND_TREE then
					stats.treeStops += 1
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
		local function take(depth: number, n: Vector3)
			if depth > worst then
				worst, worstN = depth, n
			end
		end
		for i = 1, 6 do
			local x, z = toPts[i * 2 - 1], toPts[i * 2]
			local s, d = locate(x, z, hint)
			if s and d then
				local side = if d >= 0 then 1 else -1
				if sideWallStands(s, d, pos.Y) then
					local m, n = sideWall(s, d)
					take(PENETRATION_MARGIN - m, n)
				end
				-- inside a K-rail: out of whichever of its four faces is nearest
				local a, b = kRailStands(s, d, pos.Y)
				local ad = math.abs(d)
				if a and b and ad > half - PENETRATION_MARGIN and ad < half + railT + PENETRATION_MARGIN then
					local stretch = math.max(0.2, 1 + spline:curvatureAt(s) * d)
					local yawS = spline:yawAt(s)
					local fwd = Vector3.new(-math.sin(yawS), 0, -math.cos(yawS))
					local depth, dir = ad - half + PENETRATION_MARGIN, lateralNormal(s, -side)
					local out = half + railT - ad + PENETRATION_MARGIN
					if out < depth then
						depth, dir = out, lateralNormal(s, side)
					end
					local back = (s - a) * stretch + PENETRATION_MARGIN
					if back < depth then
						depth, dir = back, -fwd
					end
					local ahead = (b - s) * stretch + PENETRATION_MARGIN
					if ahead < depth then
						depth, dir = ahead, fwd
					end
					take(depth, dir)
				end
			end
			local c, cn = closingMargin(x, z)
			-- inside the slab: out of whichever face is nearer
			if c and cn and c < PENETRATION_MARGIN and c > -CLOSING_DEPTH - PENETRATION_MARGIN then
				local forward = PENETRATION_MARGIN - c
				local back = c + CLOSING_DEPTH + PENETRATION_MARGIN
				if back < forward then
					take(back, -cn)
				else
					take(forward, cn)
				end
			end
		end
		-- inside a tree's trunk (T-183): out the nearest way
		if hint then
			local hw, hl = boxReach(pos, yaw)
			local fwd, right = Model.axes(yaw)
			local depth, n = SplineGrove.push(spline, hint, pos, fwd, right, hw, hl, bh, PENETRATION_MARGIN)
			if n then
				take(depth, n)
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
