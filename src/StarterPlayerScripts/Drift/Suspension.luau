--!strict
-- Suspension: the car's four wheels on their springs, and its floor on whatever it lands on
-- (docs/game/features/car-v2.md "Rules and numbers", T-095).
--
-- TWO LAYERS, and only the second one is ever drawn-only.
--
--   THE FLOOR, in the simulation. `Drift/Model` asks this module, and only when a wheel has
--   run out of travel -- its ground is further below it than the wheel can hang -- or when
--   the floor was already resting on something last step. Then the car rests on whatever
--   holds it up: the wheels that touch, and the floor's contact points (`floor`, below).
--   That is the one thing the model needs from all of this, and the reason it is in the
--   simulation at all: a car whose rear wheels have rolled off a ledge has to pitch, rest its
--   floor on the edge, grind across it and fall, and where it falls is where it is.
--
--   ON FLAT GROUND AND ON EVERY ROAD THIS NEVER RUNS. All four wheels are within their
--   travel there, so the model takes the path it always took and the line is the line the
--   user approved (DECISIONS.md, 2026-11-03). `DriftTests`, `TrajectoryTests` and
--   `JitterTests` say so with the numbers they always had.
--
--   THE SPRINGS, drawn. `step` runs at the end of every model step, after the pose is
--   settled, and nothing in the model reads what it writes: each wheel's travel (how far
--   up its hub is pushed), each wheel's drawn lift, and a small sprung offset of the body
--   on top of the car's frame -- heave, pitch and roll -- that follows the plane the four
--   wheels are actually standing on and takes the load on landing. `Drift/Render` draws all
--   of it; `pack` / `unpack` carry the lifts to other players.
--
-- THE FLOOR SOLVE IS A RIGID CAR DROPPED ON POINTS. Every support -- a wheel's contact at
-- ride height, a floor point, and the place an edge crosses the floor's outline -- must
-- stay at or above the ground under it. For a tilt, the height the car's origin must be at
-- is the largest of what each support asks (`need`); the tilt the car settles at is the one
-- that puts its centre of mass lowest (`rest`). That is exactly a body at rest on point
-- supports, and it answers stability for free: a car whose supports are all on one side of
-- its centre of mass has no lowest tilt short of the limit, so it tips to `MaxTilt` and
-- slides off. The model then moves the tilt toward that rest at a gravity-sized angular
-- acceleration (`TipAccel`), so a car taken off a ramp lip at speed does not have time to
-- nose over, and one rolled off a ledge at walking pace does.
--
-- WHY THE FLOOR CANNOT GO BELOW A LEDGE. The floor is the outline through its points (a
-- convex ring) plus the points themselves. Over a flat ledge top the lowest part of a
-- plane is at a corner of the region of it that is over the ledge, and those corners are
-- floor points or places the ledge's edge crosses the outline. Those crossings are found
-- by halving each outline segment `EdgeSteps` times, and the support put on the LOW side
-- of the last halving, with the ledge's own height: so the edge is treated as reaching a
-- hair further than it does, and the car floats that hair high rather than dips that hair
-- low. The floor supports are HARD -- after the model eases the height, it is still never
-- below what they ask -- while a wheel can be pushed up into its travel.
--
-- Pure maths plus the model's own `probe`, like `Drift/Model`: no Workspace, no car, no
-- player. Every number is in `Config.Drift.Suspension`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Archetypes = require(ReplicatedStorage.Shared.Cars.Archetypes)
local Config = require(ReplicatedStorage.Shared.Config)

local Suspension = {}

local EPS = 1e-4

-- The model's wheel order, which is also `CarModel.WHEEL_NAMES`: FL, FR, RL, RR.
Suspension.WHEEL_NAMES = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }
local FRONT = { 1, 1, -1, -1 } -- +1 front axle
local SIDE = { -1, 1, -1, 1 } -- +1 right side

export type FloorPoint = { name: string, at: Vector3 } -- in the car's frame (CONTRACTS.md "The car rig")

export type Contact = {
	name: string, -- the floor point, or the outline point an edge crossing was found next to
	position: Vector3, -- world, on the ground under it
	speed: number, -- studs/s the point is sliding across the ground
	edge: boolean, -- an edge crossing rather than a floor point itself
}

export type Body = { z: number, p: number, q: number, vz: number, vp: number, vq: number, kick: number }

export type Supports = {
	n: number,
	x: { number },
	y: { number },
	z: { number },
	g: { number }, -- ground height each must clear
	hard: { boolean }, -- a floor support, never allowed below its ground
	name: { string },
	edge: { boolean },
	nHard: number,
}

local EMPTY_CONTACTS: { Contact } = table.freeze({}) :: any
Suspension.EMPTY_CONTACTS = EMPTY_CONTACTS

local function S()
	return Config.Drift.Suspension
end

--------------------------------------------------------------------------------
-- The car's frame
--------------------------------------------------------------------------------

-- The car's flat forward and right from its yaw: `Drift/Model.axes`, written out again so
-- this module does not require the model that requires it.
local function axes(yaw: number): (Vector3, Vector3)
	local s, c = math.sin(yaw), math.cos(yaw)
	return Vector3.new(-s, 0, -c), Vector3.new(c, 0, -s)
end

-- The model's `basis`, from a yaw and an up: forward, right, up.
local function basis(yaw: number, up: Vector3): (Vector3, Vector3, Vector3)
	local flat = axes(yaw)
	local u = if up.Magnitude > EPS then up.Unit else Vector3.yAxis
	local right = flat:Cross(u)
	if right.Magnitude < EPS then
		return flat, Vector3.new(flat.Z, 0, -flat.X), Vector3.yAxis
	end
	right = right.Unit
	return u:Cross(right), right, u
end
Suspension.basis = basis

-- An up from a tilt: `a` pitches the nose up, `b` rolls the right side up, both radians.
function Suspension.upOf(yaw: number, a: number, b: number): Vector3
	local fwd, right = axes(yaw)
	local ca, sa, cb, sb = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
	return (Vector3.yAxis * (ca * cb) - fwd * (sa * cb) - right * sb).Unit
end

-- And back: the tilt an up is.
function Suspension.tiltOf(yaw: number, up: Vector3): (number, number)
	local fwd, right = axes(yaw)
	local u = if up.Magnitude > EPS then up.Unit else Vector3.yAxis
	local b = math.asin(math.clamp(-u:Dot(right), -1, 1))
	local a = math.atan2(-u:Dot(fwd), u.Y)
	return a, b
end

-- Where a point in the car's frame (x right, y up, z back -- front is -Z) is, relative to
-- the car's origin, for a car standing on `up`.
local function offsetOf(fwd: Vector3, right: Vector3, up: Vector3, p: Vector3): Vector3
	return right * p.X + up * p.Y - fwd * p.Z
end

-- A wheel's contact with the road, in the car's frame, with the wheel at `Rest`.
function Suspension.wheelContact(i: number): Vector3
	local C = Config.Drift
	return Vector3.new(SIDE[i] * C.TrackWidth * 0.5, -C.RideHeight, -FRONT[i] * C.Wheelbase * 0.5)
end

--------------------------------------------------------------------------------
-- The floor's points
--------------------------------------------------------------------------------

-- Nine points on a box under the car: front, middle and rear, each left, centre and
-- right. The names are the rig's own (`FloorFL` ... `FloorRR`, `FloorMC` in the middle).
function Suspension.floorBox(minX: number, maxX: number, minZ: number, maxZ: number, y: number): { FloorPoint }
	local midX, midZ = (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
	local rows = { { "F", minZ }, { "M", midZ }, { "R", maxZ } }
	local cols = { { "L", minX }, { "C", midX }, { "R", maxX } }
	local out: { FloorPoint } = {}
	for _, row in rows do
		for _, col in cols do
			table.insert(out, { name = "Floor" .. row[1] .. col[1], at = Vector3.new(col[2] :: number, y, row[2] :: number) })
		end
	end
	return out
end

-- The floor a car has when nothing better is known: the config's box under the active
-- car's body. `Drift/Render` replaces it with the drawn body's real underside, or with the
-- rig's own `Floor*` points, the moment a car is drawn.
function Suspension.defaultFloor(): { FloorPoint }
	local C = Config.Drift
	local P = S()
	local hw = C.BodyWidth * 0.5 * P.FloorWidth
	local hl = C.BodyLength * 0.5 * P.FloorLength
	return Suspension.floorBox(-hw, hw, -hl, hl, P.FloorClearance - C.RideHeight)
end

-- A rig's `Floor*` points (`CarParts.describe(...).floor`), in a fixed order so a drive is
-- the same drive every time.
function Suspension.floorFromRig(points: { [string]: Vector3 }): { FloorPoint }?
	local out: { FloorPoint } = {}
	for name, at in points do
		table.insert(out, { name = name, at = at })
	end
	if #out == 0 then
		return nil
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- The underside of a drawn body, from its parts' boxes in the car's frame: `boxes` is a
-- list of `{ cf, size }`. Only the parts that reach below the wheels' hubs count -- the
-- lower body -- and each of the nine points takes the lowest bottom of any of those whose
-- footprint covers it, so a splitter pulls the front down and a high hull does not pull
-- the middle up. Boxes rather than meshes, so a point is never higher than the part over it.
function Suspension.floorFromBoxes(boxes: { { cf: CFrame, size: Vector3 } }): { FloorPoint }?
	local C = Config.Drift
	local hub = C.WheelDiameter * 0.5 - C.RideHeight
	type Box = { x0: number, x1: number, z0: number, z1: number, y0: number }
	local low: { Box } = {}
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local lowest = math.huge
	for _, b in boxes do
		local h = b.size * 0.5
		local x0, x1, y0, z0, z1 = math.huge, -math.huge, math.huge, math.huge, -math.huge
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = b.cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
					x0, x1 = math.min(x0, w.X), math.max(x1, w.X)
					z0, z1 = math.min(z0, w.Z), math.max(z1, w.Z)
					y0 = math.min(y0, w.Y)
				end
			end
		end
		if y0 < hub then
			table.insert(low, { x0 = x0, x1 = x1, z0 = z0, z1 = z1, y0 = y0 })
			minX, maxX = math.min(minX, x0), math.max(maxX, x1)
			minZ, maxZ = math.min(minZ, z0), math.max(maxZ, z1)
			lowest = math.min(lowest, y0)
		end
	end
	if #low == 0 then
		return nil
	end
	local inset = S().FloorInset
	local points = Suspension.floorBox(minX + inset, maxX - inset, minZ + inset, maxZ - inset, lowest)
	local slack = S().FloorCover
	for _, point in points do
		local y = math.huge
		for _, b in low do
			if
				point.at.X >= b.x0 - slack
				and point.at.X <= b.x1 + slack
				and point.at.Z >= b.z0 - slack
				and point.at.Z <= b.z1 + slack
			then
				y = math.min(y, b.y0)
			end
		end
		if y < math.huge then
			point.at = Vector3.new(point.at.X, y, point.at.Z)
		end
	end
	return points
end

-- The floor's outline: the convex ring through its points, in order. Cached per floor
-- table, which never changes once made.
local rings: { [any]: { FloorPoint } } = setmetatable({}, { __mode = "k" }) :: any

local function ringOf(floor: { FloorPoint }): { FloorPoint }
	local cached = rings[floor]
	if cached then
		return cached
	end
	local pts = table.clone(floor)
	table.sort(pts, function(a, b)
		if a.at.X ~= b.at.X then
			return a.at.X < b.at.X
		end
		return a.at.Z < b.at.Z
	end)
	local function cross(o: FloorPoint, a: FloorPoint, b: FloorPoint): number
		return (a.at.X - o.at.X) * (b.at.Z - o.at.Z) - (a.at.Z - o.at.Z) * (b.at.X - o.at.X)
	end
	local hull: { FloorPoint } = {}
	for _, p in pts do
		while #hull >= 2 and cross(hull[#hull - 1], hull[#hull], p) <= 0 do
			table.remove(hull)
		end
		table.insert(hull, p)
	end
	local lower = #hull + 1
	for i = #pts - 1, 1, -1 do
		local p = pts[i]
		while #hull >= lower and cross(hull[#hull - 1], hull[#hull], p) <= 0 do
			table.remove(hull)
		end
		table.insert(hull, p)
	end
	table.remove(hull) -- the first point, again
	rings[floor] = hull
	return hull
end

Suspension.outline = ringOf

-- The floor's segments: every pair of its points with no third point on the line between
-- them -- on the nine-point box, its rows, its columns and the short diagonals. A floor is
-- not flat (a body's middle is lower than its bumpers), so an edge is looked for along all
-- of them and not only round the outline: the outline alone would hold the car up by its
-- bumpers' height across a middle that hangs lower. Cached per floor table.
local segments: { [any]: { { FloorPoint } } } = setmetatable({}, { __mode = "k" }) :: any

local function segmentsOf(floor: { FloorPoint }): { { FloorPoint } }
	local cached = segments[floor]
	if cached then
		return cached
	end
	local out = {}
	for i = 1, #floor do
		for j = i + 1, #floor do
			local a, b = floor[i].at, floor[j].at
			local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
			local len = ab.Magnitude
			local blocked = len < EPS
			for k = 1, #floor do
				if blocked then
					break
				end
				if k ~= i and k ~= j then
					local c = floor[k].at
					local ac = Vector2.new(c.X - a.X, c.Z - a.Z)
					local t = ac:Dot(ab) / (len * len)
					local off = math.abs(ac.X * ab.Y - ac.Y * ab.X) / len
					blocked = t > 0 and t < 1 and off < 0.05
				end
			end
			if not blocked then
				table.insert(out, { floor[i], floor[j] })
			end
		end
	end
	segments[floor] = out
	return out
end
Suspension.segments = segmentsOf

-- HOW MUCH LOWER THIS CAR'S BODY SITS THAN STOCK (T-109), in studs: a car whose wheels sit
-- further into their travel at rest (`SuspensionRest`, which a Suspension part moves) has
-- its body that much nearer the road, and its floor with it. Zero on every stock car.
function Suspension.rideDrop(): number
	return S().Rest - Archetypes.Base.SuspensionRest
end

-- The floor, lowered with the body. The same table back when nothing is lowered, and one
-- copy per floor and drop otherwise, so the segment cache keeps working.
local lowered: { [any]: { drop: number, list: { FloorPoint } } } = setmetatable({}, { __mode = "k" }) :: any

local function floorAt(points: { FloorPoint }, drop: number): { FloorPoint }
	if drop == 0 then
		return points
	end
	local cached = lowered[points]
	if cached and cached.drop == drop then
		return cached.list
	end
	local list = {}
	for _, point in points do
		table.insert(list, { name = point.name, at = point.at - Vector3.new(0, drop, 0) })
	end
	lowered[points] = { drop = drop, list = list }
	return list
end

--------------------------------------------------------------------------------
-- The floor solve, for Drift/Model
--------------------------------------------------------------------------------

local function newSupports(): Supports
	return { n = 0, x = {}, y = {}, z = {}, g = {}, hard = {}, name = {}, edge = {}, nHard = 0 }
end

local function add(sup: Supports, p: Vector3, g: number, hard: boolean, name: string, edge: boolean)
	local n = sup.n + 1
	sup.n = n
	sup.x[n], sup.y[n], sup.z[n], sup.g[n] = p.X, p.Y, p.Z, g
	sup.hard[n], sup.name[n], sup.edge[n] = hard, name, edge
	if hard then
		sup.nHard += 1
	end
end

-- The ground a hit's own plane puts at a world point.
local function planeAt(hit: any, hx: number, hz: number, x: number, z: number): number
	local n = hit.normal
	if n.Y < EPS then
		return hit.y
	end
	return hit.y - (n.X * (x - hx) + n.Z * (z - hz)) / n.Y
end

-- WHERE AN EDGE IS, in ONE ray (T-095 perf). The ground rays say there is a step between
-- a low point and a high one; a ray cast sideways from over the low ground toward the high
-- point, a hair under the high surface, stops exactly on the step's face. That is one query
-- where halving the gap took `EdgeSteps` of them, and it is exact rather than quantised.
-- Returns how far along from `low` to `high` the face is, 0..1, or nil when the world has
-- no sideways ray (a made-up test world) or the ray finds no face (a slope, not a step), and
-- the caller halves instead.
local EDGE_DIP = 0.05 -- studs under the high surface the sideways ray runs

local function edgeAlong(world: any, low: Vector3, high: Vector3, highY: number): number?
	local cast = world.edge
	if not cast then
		return nil
	end
	local from = Vector3.new(low.X, highY - EDGE_DIP, low.Z)
	local to = Vector3.new(high.X, highY - EDGE_DIP, high.Z)
	local span = (to - from).Magnitude
	if span < EPS then
		return nil
	end
	local at = cast(from, to)
	if not at then
		return nil
	end
	return math.clamp((Vector3.new(at.X, from.Y, at.Z) - from).Magnitude / span, 0, 1)
end

-- Each wheel's ground as its whole tread meets it: where its contact would have to be for
-- no part of the tread to be inside anything, so a wheel rolling over an edge rides round
-- the corner as a circle does instead of dropping through it the moment the ray under its
-- middle is past. The tread is asked at three places round its lower half (`TREAD`, in
-- degrees off the bottom, + forward); wherever two neighbours stand on different levels the
-- edge between them is found by one sideways ray (`edgeAlong`) -- or by halving
-- `EdgeSteps` times where the world has none -- and the tread either side of it held over
-- the higher ground: a hair more lift than it needs, never less. Each answer is measured in the world, along the car's own tilt, so a car
-- tipped on its floor still gets its tyres right. Only while the floor solve runs, and into
-- a NEW table, so the model's own hits are left alone.
local TREAD = { -60, 0, 60 }

function Suspension.treads(world: any, yaw: number, pos: Vector3, up: Vector3): { any }
	local C = Config.Drift
	local P = S()
	local r = C.WheelDiameter * 0.5
	local fwd, right, u = basis(yaw, up)
	local out = table.create(4)
	for i = 1, 4 do
		local p = Suspension.wheelContact(i)
		local contactY = (pos + offsetOf(fwd, right, u, p)).Y
		local best: any = nil
		-- A point `deg` round the tread (0 is the bottom, + forward), `w` across.
		local function pointAt(deg: number, w: number): Vector3
			local a = math.rad(deg)
			return pos + offsetOf(fwd, right, u, p + Vector3.new(w, r - r * math.cos(a), -r * math.sin(a)))
		end
		-- What ground `hit` asks of the contact, held under the tread at `at`.
		local function offer(hit: any, at: Vector3)
			if hit then
				local y = contactY + (hit.y - at.Y)
				if not best or y > best.y then
					best = { y = y, normal = hit.normal, grip = hit.grip, score = hit.score }
				end
			end
		end
		local hits = table.create(#TREAD)
		local ats = table.create(#TREAD)
		for k, deg in TREAD do
			ats[k] = pointAt(deg, 0)
			hits[k] = world.probe(ats[k])
			offer(hits[k], ats[k])
		end
		for k = 1, #TREAD - 1 do
			local ha, hb = hits[k], hits[k + 1]
			local high, lo, hi
			if ha and (not hb or ha.y - hb.y > P.EdgeDrop) then
				high, lo, hi = ha, TREAD[k + 1], TREAD[k] -- `hi` is on the high side
			elseif hb and (not ha or hb.y - ha.y > P.EdgeDrop) then
				high, lo, hi = hb, TREAD[k], TREAD[k + 1]
			else
				continue
			end
			local lowAt, highAt = pointAt(lo, 0), pointAt(hi, 0)
			local t = edgeAlong(world, lowAt, highAt, high.y)
			if t then
				-- The face is `t` of the way across the chord: find the angle on the tread
				-- over it by halving in maths alone, no more rays.
				local face = lowAt:Lerp(highAt, t)
				local dir = Vector3.new(highAt.X - lowAt.X, 0, highAt.Z - lowAt.Z)
				for _ = 1, 12 do
					local m = (lo + hi) * 0.5
					local q = pointAt(m, 0)
					if Vector3.new(q.X - face.X, 0, q.Z - face.Z):Dot(dir) >= 0 then
						hi = m
					else
						lo = m
					end
				end
			else
				for _ = 1, P.EdgeSteps do
					local m = (lo + hi) * 0.5
					local mh = world.probe(pointAt(m, 0))
					if mh and math.abs(mh.y - high.y) <= P.EdgeDrop * 0.5 then
						hi = m
					else
						lo = m
					end
				end
			end
			offer(high, pointAt(lo, 0))
			offer(high, pointAt(hi, 0))
		end
		out[i] = best
	end
	return out
end

-- Everything that could hold the car up this step: the wheels that found ground (at ride
-- height, soft), every floor point over ground, and every place an edge crosses the
-- floor's outline (hard). Probed where the car is now, standing on `up`.
function Suspension.gather(
	world: any,
	yaw: number,
	pos: Vector3,
	up: Vector3,
	wheelHits: { any },
	floor: { FloorPoint }?
): Supports
	local P = S()
	local sup = newSupports()
	for i = 1, 4 do
		local hit = wheelHits[i]
		if hit then
			add(sup, Suspension.wheelContact(i), hit.y, false, Suspension.WHEEL_NAMES[i], false)
		end
	end

	local points = floorAt(floor or Suspension.defaultFloor(), Suspension.rideDrop())
	local fwd, right, u = basis(yaw, up)
	local hits: { [FloorPoint]: any } = {}
	local worldAt: { [FloorPoint]: Vector3 } = {}
	for _, point in points do
		local at = pos + offsetOf(fwd, right, u, point.at)
		worldAt[point] = at
		local hit = world.probe(at)
		if hit then
			hits[point] = hit
			add(sup, point.at, hit.y, true, point.name, false)
		end
	end

	-- Where an edge crosses the floor. Two neighbours on one surface agree with each
	-- other's plane; two that do not have a step between them, or a drop.
	local drop = P.EdgeDrop
	for _, pair in segmentsOf(points) do
		local a, b = pair[1], pair[2]
		local ha, hb = hits[a], hits[b]
		local high: FloorPoint, low: FloorPoint
		if ha and hb then
			local wa, wb = worldAt[a], worldAt[b]
			local predB = planeAt(ha, wa.X, wa.Z, wb.X, wb.Z)
			if math.abs(hb.y - predB) <= drop then
				continue -- one surface
			end
			if hb.y < predB then
				high, low = a, b
			else
				high, low = b, a
			end
		elseif ha then
			high, low = a, b
		elseif hb then
			high, low = b, a
		else
			continue
		end
		local hHit = hits[high]
		local hw = worldAt[high]
		local lw = worldAt[low]
		local lo, hi = 0, 1
		local t = edgeAlong(world, lw, hw, planeAt(hHit, hw.X, hw.Z, lw.X, lw.Z))
		if t then
			-- `t` is measured from the low end. The support goes `ReuseMove` (and a hair)
			-- further out over the drop than the face: the model reuses what it found until
			-- the car has moved that far, and the edge must not be under the car's floor
			-- anywhere it could be in the meantime. It costs the floor riding at most that
			-- far times the tip high -- 0.06 at 30 degrees, inside `FloorTouch`.
			local len = (high.at - low.at).Magnitude
			hi = math.clamp(1 - t + (P.ReuseMove + 0.01) / math.max(len, EPS), 0, 1)
		else
			for _ = 1, P.EdgeSteps do
				local m = (lo + hi) * 0.5
				local local_ = high.at:Lerp(low.at, m)
				local at = pos + offsetOf(fwd, right, u, local_)
				local hit = world.probe(at)
				if hit and math.abs(hit.y - planeAt(hHit, hw.X, hw.Z, at.X, at.Z)) <= drop * 0.5 then
					lo = m
				else
					hi = m
				end
			end
		end
		local edgeLocal = high.at:Lerp(low.at, hi)
		local edgeAt = pos + offsetOf(fwd, right, u, edgeLocal)
		-- Named after whichever of the two outline points it is nearer.
		local nearest = if hi < 0.5 then high.name else low.name
		add(sup, edgeLocal, planeAt(hHit, hw.X, hw.Z, edgeAt.X, edgeAt.Z), true, nearest, true)
	end
	return sup
end

-- The height the car's origin must be at, standing on `up`, for every support to clear its
-- ground; and the least it may be at all -- no floor point below its ground, and no wheel
-- pushed past the top of its travel; and what the floor alone asks. `-math.huge` when
-- there are none.
function Suspension.need(sup: Supports, yaw: number, up: Vector3): (number, number, number)
	local fwd, right, u = basis(yaw, up)
	local rx, uy, fy = right.Y, u.Y, fwd.Y
	local P = S()
	local give = P.Travel - P.Rest
	local all, hard, floor = -math.huge, -math.huge, -math.huge
	for k = 1, sup.n do
		local y = sup.g[k] - (rx * sup.x[k] + uy * sup.y[k] - fy * sup.z[k])
		if y > all then
			all = y
		end
		local least = if sup.hard[k] then y else y - give
		if least > hard then
			hard = least
		end
		if sup.hard[k] and y > floor then
			floor = y
		end
	end
	return all, hard, floor
end

-- How high the centre of mass is for a tilt, with the car standing on its supports.
local function comHeight(sup: Supports, yaw: number, a: number, b: number, com: Vector3): number
	local fwd, right, u = basis(yaw, Suspension.upOf(yaw, a, b))
	local rx, uy, fy = right.Y, u.Y, fwd.Y
	local all = -math.huge
	for k = 1, sup.n do
		local y = sup.g[k] - (rx * sup.x[k] + uy * sup.y[k] - fy * sup.z[k])
		if y > all then
			all = y
		end
	end
	return all + rx * com.X + uy * com.Y - fy * com.Z
end

local DIRS = {
	{ 1, 0 },
	{ -1, 0 },
	{ 0, 1 },
	{ 0, -1 },
	{ 1, 1 },
	{ 1, -1 },
	{ -1, 1 },
	{ -1, -1 },
}

-- The tilt the car settles at: the one that puts its centre of mass lowest. A pattern
-- search from where it is now (eight directions, the step halving when none is better),
-- which is enough because the height is a maximum of near-planes; every tilt it tries is
-- one the car can stand at, so even a search stopped early is a pose with nothing below
-- its ground.
function Suspension.rest(sup: Supports, yaw: number, a0: number, b0: number): (number, number)
	local P = S()
	local limit = math.rad(P.MaxTilt)
	local com = Config.Drift.CenterOfMass
	local a, b = math.clamp(a0, -limit, limit), math.clamp(b0, -limit, limit)
	local best = comHeight(sup, yaw, a, b, com)
	local step = math.rad(P.SearchStep)
	local finest = math.rad(P.SearchFinest)
	local guard = 0
	while step > finest and guard < 400 do
		guard += 1
		local bestA, bestB, bestV = a, b, best
		for _, d in DIRS do
			local na = math.clamp(a + d[1] * step, -limit, limit)
			local nb = math.clamp(b + d[2] * step, -limit, limit)
			local v = comHeight(sup, yaw, na, nb, com)
			if v < bestV - 1e-7 then
				bestA, bestB, bestV = na, nb, v
			end
		end
		if bestV < best then
			a, b, best = bestA, bestB, bestV
		else
			step *= 0.5
		end
	end
	return a, b
end

-- One axis of the tilt moving toward where it would rest, never faster than `TipAccel`
-- lets it start, and slowing so it stops there rather than overshooting.
function Suspension.approach(cur: number, target: number, rate: number, dt: number): (number, number)
	local acc = S().TipAccel
	local d = target - cur
	if math.abs(d) < 1e-6 then
		return target, 0
	end
	local stop = math.sqrt(2 * acc * math.abs(d)) * math.sign(d)
	local r = rate + math.clamp(stop - rate, -acc * dt, acc * dt)
	if d > 0 then
		r = math.min(r, stop)
	else
		r = math.max(r, stop)
	end
	local nxt = cur + r * dt
	if (target - nxt) * d <= 0 then
		return target, 0
	end
	return nxt, r
end

-- Which floor supports touch, for a car whose origin is at `y` standing on `up`, as world
-- contacts with the speed each one slides at. Allocates; only reached while the floor is
-- in play.
function Suspension.contacts(
	sup: Supports,
	yaw: number,
	pos: Vector3,
	up: Vector3,
	velocity: Vector3,
	yawRate: number
): { Contact }
	local touch = S().FloorTouch
	local fwd, right, u = basis(yaw, up)
	local out: { Contact }? = nil
	for k = 1, sup.n do
		if not sup.hard[k] then
			continue
		end
		local off = offsetOf(fwd, right, u, Vector3.new(sup.x[k], sup.y[k], sup.z[k]))
		local at = pos + off
		if at.Y - sup.g[k] > touch then
			continue
		end
		-- The point's own velocity: the car's, plus the yaw rate swinging it round.
		local v = velocity + Vector3.yAxis:Cross(off) * yawRate
		local list = out or {}
		out = list
		table.insert(list, {
			name = sup.name[k],
			position = Vector3.new(at.X, sup.g[k], at.Z),
			speed = math.sqrt(v.X * v.X + v.Z * v.Z),
			edge = sup.edge[k],
		})
	end
	return out or EMPTY_CONTACTS
end

--------------------------------------------------------------------------------
-- The springs, drawn
--------------------------------------------------------------------------------

function Suspension.newBody(): Body
	return { z = 0, p = 0, q = 0, vz = 0, vp = 0, vq = 0, kick = 0 }
end

local function spring(x: number, v: number, target: number, dt: number): (number, number)
	local P = S()
	local acc = P.Stiffness * (target - x) - P.Damping * v
	v += acc * dt
	return x + v * dt, v
end

-- One step of the drawn suspension, after the model has settled the pose. Mutates the
-- state's `travel`, `wheelLift` and `body` in place and allocates nothing.
--
-- `hits` are the model's own four ground rays this step. A wheel is ON THE GROUND when its
-- ground is within its hang of where it sits; its travel is then whatever puts it there
-- (pushed up at once, dropped no faster than `DropTime`), and the body's offset springs
-- toward the plane the touching wheels are on. With nothing under it a wheel falls to the
-- bottom of its travel in `DropTime`, and hangs there.
function Suspension.step(s: any, hits: { any }, dt: number, vyBefore: number)
	local C = Config.Drift
	local P = S()
	local travel, lift, body = s.travel, s.wheelLift, s.body
	local fwd, right, u = basis(s.yaw, s.up)
	local uy = math.max(u.Y, 0.3)
	local rest, full = P.Rest, P.Travel
	local dropRate = full / math.max(P.DropTime, EPS)
	local halfBase, halfTrack = C.Wheelbase * 0.5, C.TrackWidth * 0.5
	-- On the floor solve the car's frame IS where it rests, so the body is not sprung off it.
	local holdBody = s.airborne or s.hanging

	-- Where each wheel's ground is, up the car's own axis from where a wheel at `Rest` would
	-- touch: positive is a bump to climb, negative a dip to drop into.
	local g1, g2, g3, g4 = 0, 0, 0, 0
	local t1, t2, t3, t4 = false, false, false, false
	local count = 0
	for i = 1, 4 do
		local hit = hits[i]
		local g = 0
		local touching = false
		if hit and not s.airborne then
			local p = Suspension.wheelContact(i)
			local h = s.position.Y + right.Y * p.X + u.Y * p.Y - fwd.Y * p.Z
			g = (hit.y - h) / uy
			if math.abs(g) < 1e-6 then
				g = 0
			end
			touching = g >= -rest - P.ReachSlack
		end
		if i == 1 then
			g1, t1 = g, touching
		elseif i == 2 then
			g2, t2 = g, touching
		elseif i == 3 then
			g3, t3 = g, touching
		else
			g4, t4 = g, touching
		end
		if touching then
			count += 1
		end
	end

	-- What the body springs toward: the plane through the touching wheels.
	local zT, pT, qT = 0, 0, 0
	if count > 0 and not holdBody then
		local sum = (if t1 then g1 else 0) + (if t2 then g2 else 0) + (if t3 then g3 else 0) + (if t4 then g4 else 0)
		zT = sum / count
		local nf = (if t1 then 1 else 0) + (if t2 then 1 else 0)
		local nr = (if t3 then 1 else 0) + (if t4 then 1 else 0)
		if nf > 0 and nr > 0 then
			local front = ((if t1 then g1 else 0) + (if t2 then g2 else 0)) / nf
			local rear = ((if t3 then g3 else 0) + (if t4 then g4 else 0)) / nr
			pT = (front - rear) / (2 * halfBase)
		end
		local nl = (if t1 then 1 else 0) + (if t3 then 1 else 0)
		local nrt = (if t2 then 1 else 0) + (if t4 then 1 else 0)
		if nl > 0 and nrt > 0 then
			local leftG = ((if t1 then g1 else 0) + (if t3 then g3 else 0)) / nl
			local rightG = ((if t2 then g2 else 0) + (if t4 then g4 else 0)) / nrt
			qT = (rightG - leftG) / (2 * halfTrack)
		end
		local tilt = math.tan(math.rad(P.MaxBodyTilt))
		zT = math.clamp(zT, -full, full)
		pT = math.clamp(pT, -tilt, tilt)
		qT = math.clamp(qT, -tilt, tilt)
	end
	-- And sitting lower or higher than stock, whatever the wheels are doing (T-109).
	zT -= Suspension.rideDrop()

	-- Taking the load: a change in the car's vertical speed while it is on the ground --
	-- a landing, the foot of a ramp, a crest -- throws the body against its springs.
	--
	-- The model calls a car landed while it is still settling the last of the way down on to
	-- its wheels, so a jolt that arrives before any wheel touches is held until one does:
	-- the body takes the load when the tyres do.
	if holdBody then
		body.kick = 0
	else
		local dvy = s.velocity.Y - vyBefore
		if dvy ~= 0 then
			body.kick -= dvy * P.LandingSquash
		end
		if count > 0 and body.kick ~= 0 then
			body.vz += body.kick
			body.kick = 0
		end
	end

	body.z, body.vz = spring(body.z, body.vz, zT, dt)
	body.p, body.vp = spring(body.p, body.vp, pT, dt)
	body.q, body.vq = spring(body.q, body.vq, qT, dt)

	-- The bump stops: no touching wheel is pushed past the top of its travel, so the body
	-- is lifted off any that would be.
	local lowest = -math.huge
	for i = 1, 4 do
		local touching = if i == 1 then t1 elseif i == 2 then t2 elseif i == 3 then t3 else t4
		if touching then
			local g = if i == 1 then g1 elseif i == 2 then g2 elseif i == 3 then g3 else g4
			local c = body.p * FRONT[i] * halfBase + body.q * SIDE[i] * halfTrack
			lowest = math.max(lowest, g + rest - full - c)
		end
	end
	if body.z < lowest then
		body.z = lowest
		if body.vz < 0 then
			body.vz = 0
		end
	end
	if math.abs(body.z) < 1e-7 and math.abs(body.vz) < 1e-7 then
		body.z, body.vz = 0, 0
	end
	if math.abs(body.p) < 1e-9 and math.abs(body.vp) < 1e-9 then
		body.p, body.vp = 0, 0
	end
	if math.abs(body.q) < 1e-9 and math.abs(body.vq) < 1e-9 then
		body.q, body.vq = 0, 0
	end

	-- Each wheel's travel, then where it is drawn: up from the car's frame by the body's
	-- offset over it plus its own travel off `Rest`.
	local fall = dropRate * dt
	for i = 1, 4 do
		local touching = if i == 1 then t1 elseif i == 2 then t2 elseif i == 3 then t3 else t4
		local g = if i == 1 then g1 elseif i == 2 then g2 elseif i == 3 then g3 else g4
		local c = body.z + body.p * FRONT[i] * halfBase + body.q * SIDE[i] * halfTrack
		local t = travel[i]
		if touching then
			local want = math.clamp(rest + g - c, 0, full)
			if want >= t then
				t = want
			else
				t = math.max(want, t - fall)
			end
		else
			t = math.max(0, t - fall)
		end
		travel[i] = t
		local l = c + t - rest
		lift[i] = if math.abs(l) < 1e-6 then 0 else l
	end
end

-- The body's place relative to the car's frame -- the sprung offset, then the cosmetic lean
-- about the centre of mass -- which is what `Drift/Render` draws the body at and what
-- `Drift/Wheels` cancels to keep the tyre marks on the road.
function Suspension.bodyLocal(state: any): CFrame
	local cf = CFrame.identity
	local body = state.body
	if body and (body.z ~= 0 or body.p ~= 0 or body.q ~= 0) then
		cf = CFrame.new(0, body.z, 0) * CFrame.Angles(body.p, 0, 0) * CFrame.Angles(0, 0, body.q)
	end
	local roll = state.bodyRoll or 0
	if roll ~= 0 then
		local com = Config.Drift.CenterOfMass
		cf = cf * CFrame.new(com) * CFrame.Angles(0, 0, roll) * CFrame.new(-com)
	end
	return cf
end

-- Is the body sitting exactly on the car's frame (nothing sprung)?
function Suspension.bodyAtRest(state: any): boolean
	local body = state.body
	return body == nil or (body.z == 0 and body.p == 0 and body.q == 0)
end

--------------------------------------------------------------------------------
-- Over the wire (CONTRACTS.md, `CarState`)
--------------------------------------------------------------------------------

-- The four drawn lifts in one number: a byte each, FL lowest, `LiftRange` studs either way
-- of zero. Exact in a double, cheap on an unreliable remote, and 128 is zero.
function Suspension.pack(lifts: { number }): number
	local range = S().LiftRange
	local n = 0
	for i = 4, 1, -1 do
		local q = math.clamp(math.round((lifts[i] or 0) / range * 127) + 128, 1, 255)
		n = n * 256 + q
	end
	return n
end

-- And back, into `out` if one is handed in. Anything that is not a whole number in range
-- unpacks to four zeros: this arrives off the wire.
function Suspension.unpack(n: any, out: { number }?): { number }
	local lifts = out or table.create(4, 0)
	local range = S().LiftRange
	if type(n) ~= "number" or n ~= n or n < 0 or n >= 4294967296 or n % 1 ~= 0 then
		for i = 1, 4 do
			lifts[i] = 0
		end
		return lifts
	end
	for i = 1, 4 do
		local q = n % 256
		n = (n - q) / 256
		lifts[i] = if q == 0 then 0 else (q - 128) / 127 * range
	end
	return lifts
end

--------------------------------------------------------------------------------
-- The readout
--------------------------------------------------------------------------------

-- Everything the suspension and the floor are doing, by name, for `DebugState`s and the
-- tests. Allocates.
function Suspension.DebugState(state: any): { [string]: any }
	if not state or not state.travel then
		return { hasSuspension = false }
	end
	local wheels = {}
	for i, name in Suspension.WHEEL_NAMES do
		wheels[name] = { travel = state.travel[i], lift = state.wheelLift[i] }
	end
	local touching = {}
	local contacts = {}
	for _, c in state.floorContacts or EMPTY_CONTACTS do
		touching[c.name] = true
		table.insert(contacts, { name = c.name, position = c.position, speed = c.speed, edge = c.edge })
	end
	local names = {}
	for name in touching do
		table.insert(names, name)
	end
	table.sort(names)
	local body = state.body
	return {
		hasSuspension = true,
		hanging = state.hanging == true, -- the floor solve ran this step
		wheels = wheels, -- travel 0 hanging .. Travel fully up; lift studs up off the car's frame
		bodyHeave = body and body.z or 0,
		bodyPitchDeg = body and math.deg(body.p) or 0,
		bodyRollDeg = body and math.deg(body.q) or 0,
		floorTouching = names, -- which floor points rest on something
		contacts = contacts, -- each with its world position and slide speed
		floorPoints = if state.floor then #state.floor else 0,
	}
end

return Suspension
