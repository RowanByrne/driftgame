--!strict
-- World: the only questions the drift model asks of the Workspace, so the model itself
-- stays pure maths (Drift/Model).
--
--   probe(pos)             the ground under a contact point, and what it is made of
--   sweep(from, to, yaw)   how far this step may actually get, and what stopped it
--   penetration(pos, yaw)  is the car inside something solid, and which way is out
--
-- Ground rays prefer parts tagged `DriftSurface` (docs/game/CONTRACTS.md), which is what
-- PlaygroundService tags the world with. While nothing in the world carries that tag --
-- a lane place with only a baseplate, before the playground exists -- they fall back to
-- whatever solid they hit and treat it as road, so the model can be driven and measured
-- anyway.
--
-- A surface carries its own grip and score multipliers, so the model never has to know
-- what a surface is called. A tagged part is tarmac unless its `Surface` attribute says
-- `dirt`; anything solid that is not tagged at all, in a world that does use the tag, is
-- "unspecified" and has almost no grip -- off the road the car barely corrects itself.
--
-- THE CAR IS KINEMATIC: Roblox physics never moves it, so "solid" is entirely what the
-- two queries below say it is. Both of them exist because of one fact about Blockcast
-- that is easy to walk into (T-018):
--
--   A Blockcast whose box ALREADY OVERLAPS a part does not report that part at all.
--
-- So a car a tenth of a stud inside a building is blind to that building and drives
-- straight out the far side. `sweep` is written to never let the car in -- it reports how
-- far the car's own box may travel, which is not where the surface is -- and
-- `penetration` is there to put the car back out when something else has got it in: its
-- own rotation against a wall, a cone rolling into it, a respawn on top of something.
--
-- And a sweep ALONE is not enough, which is the second thing to know (T-026): a Blockcast
-- only reaches as far as the car travels in that step, so a car crawling at a stud a
-- second closes a standoff without ever reporting a hit, and the moment it touches it is
-- blind. `penetration` is what holds the line at a walking pace.
--
-- NEITHER QUESTION TREATS THE ROAD AS SPECIAL. A ramp is 14 studs thick and the banked
-- circle's rim stands 8 studs out of the plate; those are walls, and leaving the road out
-- of both queries left them with no sides at all. What sorts ground from wall here is the
-- geometry -- a surface's normal for the sweep, a floor's top face for the overlap --
-- never whether the part is tagged.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Model = require(script.Parent.Model)

local World = {}

local EPSILON = 1e-4

-- A surface facing this far up or down is ground, not a wall: the ground rays own it.
-- Anything steeper than about 46 degrees is a wall, whether or not it is road -- the
-- banked circle's rim and the ramp's flanks are road, and they stand 8 and 9 studs out of
-- the plate (T-026).
local GROUND_NORMAL_Y = 0.7

-- How many surfaces one sweep may look PAST before it gives up. A Blockcast reports only
-- its nearest hit, so the road under the car can hide the wall beyond it for that whole
-- step; rather than throw the road out of the cast -- which is what used to happen, and
-- which left every drivable part without sides -- each ground-facing hit is dropped from
-- the cast and the cast is made again. Four is the road, a kerb, a slope and one spare:
-- nothing in a step at top speed needs a fifth.
local MAX_SWEEP_LOOKS = 4

-- The same for a ground ray, and for the same reason. A ribbon's end face leans back
-- under its own lip, so a wheel a hand's breadth past the end of the ramp finds that face
-- rather than the plate, and its normal -- 80 degrees off level -- poisons the average of
-- the four. Measured, that threw the car DOWN at 97 studs/s off the top of the ramp
-- (T-026). Each such hit is stepped past and the ray carries on down.
local MAX_PROBE_LOOKS = 3

-- How far below a face the ray restarts. Small enough never to skip a real floor under it.
local PROBE_STEP_DOWN = 0.05

-- The car's footprint is GROWN by this much on each side before anything is asked whether
-- the car is inside something, so what `penetration` actually keeps is a hair of clear
-- air rather than nothing at all. The car never has to reach zero clearance to be noticed,
-- which is the point: at exactly zero a Blockcast stops seeing the surface (measured --
-- a gap of 0.001 studs is still reported, a gap of 0 is not), and a car that cannot see a
-- wall drives through it. Small enough that restoring the standoff is never a visible
-- shove: a fifth of what one step at top speed covers.
local PENETRATION_MARGIN = 0.05

-- A flat plane at `y`, with no walls, and tarmac by default. Used by the automated tests
-- and by any DebugDrive that wants a line it can reason about without the world in the
-- way; pass a grip and a score to make it dirt instead.
function World.flat(y: number, grip: number?, score: number?): Model.World
	local C = Config.Drift
	local hit: Model.Hit = {
		y = y,
		normal = Vector3.yAxis,
		grip = grip or C.GripTarmac,
		score = score or C.ScoreTarmac,
	}
	return {
		probe = function(_pos: Vector3): Model.Hit?
			return hit
		end,
		sweep = nil,
		penetration = nil,
	}
end

--------------------------------------------------------------------------------
-- The car's footprint against one part, flat on the ground
--------------------------------------------------------------------------------
-- Everything below works in two dimensions on purpose: a car that is on the ground is
-- either beside a building or inside it, and height only ever decides whether the two are
-- at the same level at all.

type Footprint = {
	circle: boolean,
	centre: Vector2,
	radius: number, -- circles only
	u: Vector2, -- boxes only: the two horizontal axes...
	v: Vector2,
	hu: number, -- ...and the half-extent along each
	hv: number,
	low: number, -- world Y the part reaches down to
	high: number, -- and up to
}

local function flatten(axis: Vector3): Vector2
	local flat = Vector2.new(axis.X, axis.Z)
	if flat.Magnitude < EPSILON then
		return Vector2.xAxis
	end
	return flat.Unit
end

-- A part as a flat shape plus the band of height it occupies. Exact for an upright box
-- and for an upright cylinder (a pillar, a standing cone), which is everything the
-- playground builds; anything genuinely tilted falls back to its world bounding box,
-- which is never smaller than the part, so the car is kept out of it rather than let in.
local function footprint(part: BasePart): Footprint
	local cf = part.CFrame
	local size = part.Size
	local pos = cf.Position
	local axes = {
		{ dir = cf.RightVector, half = size.X * 0.5 },
		{ dir = cf.UpVector, half = size.Y * 0.5 },
		{ dir = cf.LookVector, half = size.Z * 0.5 },
	}

	local halfY = 0
	local vertical, verticality = 1, 0
	for i, a in axes do
		halfY += math.abs(a.dir.Y) * a.half
		local m = math.abs(a.dir.Y)
		if m > verticality then
			verticality, vertical = m, i
		end
	end

	local base: Footprint = {
		circle = false,
		centre = Vector2.new(pos.X, pos.Z),
		radius = 0,
		u = Vector2.xAxis,
		v = Vector2.yAxis,
		hu = 0,
		hv = 0,
		low = pos.Y - halfY,
		high = pos.Y + halfY,
	}

	if verticality < 0.999 then
		-- Tilted: its world bounding box, which is the conservative answer.
		local halfX = math.abs(cf.RightVector.X) * size.X * 0.5
			+ math.abs(cf.UpVector.X) * size.Y * 0.5
			+ math.abs(cf.LookVector.X) * size.Z * 0.5
		local halfZ = math.abs(cf.RightVector.Z) * size.X * 0.5
			+ math.abs(cf.UpVector.Z) * size.Y * 0.5
			+ math.abs(cf.LookVector.Z) * size.Z * 0.5
		base.hu, base.hv = halfX, halfZ
		return base
	end

	local shape = if part:IsA("Part") then part.Shape else nil
	if shape == Enum.PartType.Ball then
		base.circle = true
		base.radius = math.min(size.X, size.Y, size.Z) * 0.5
		return base
	end
	-- A Roblox cylinder's circular face is perpendicular to its LOCAL X. Standing on end
	-- -- a pillar, or a cone the right way up -- that is a circle on the ground; lying on
	-- its side it is a rectangle, and the box branch below gets it right.
	if shape == Enum.PartType.Cylinder and vertical == 1 then
		base.circle = true
		base.radius = math.max(size.Y, size.Z) * 0.5
		return base
	end

	local flat: { { dir: Vector3, half: number } } = {}
	for i, a in axes do
		if i ~= vertical then
			table.insert(flat, a)
		end
	end
	base.u, base.hu = flatten(flat[1].dir), flat[1].half
	base.v, base.hv = flatten(flat[2].dir), flat[2].half
	return base
end

-- Where the top face of a box-shaped floor is, at one horizontal point: the height a car
-- standing on it sits at. Extrapolated beyond the part's own edges, which is what makes it
-- the right question to ask beside a part as well as on top of one.
local function topOf(part: BasePart, at: Vector2): number
	local cf = part.CFrame
	local up = cf.UpVector
	local c = cf.Position
	return c.Y + (part.Size.Y * 0.5 - (at.X - c.X) * up.X - (at.Y - c.Z) * up.Z) / up.Y
end

-- The shortest shove that gets the car's footprint out of a circle, in world XZ.
local function pushFromCircle(
	centre: Vector2,
	right: Vector2,
	fwd: Vector2,
	hw: number,
	hl: number,
	shape: Footprint
): (Vector2?, number)
	local d = shape.centre - centre
	local x = d:Dot(right)
	local z = d:Dot(fwd)
	local nx = math.clamp(x, -hw, hw)
	local nz = math.clamp(z, -hl, hl)
	local dx, dz = x - nx, z - nz
	local gap = math.sqrt(dx * dx + dz * dz)
	if gap >= shape.radius then
		return nil, 0
	end
	if gap > EPSILON then
		-- The circle's middle is outside the car: straight away from the nearest point.
		local depth = shape.radius - gap
		return (right * (-dx / gap) + fwd * (-dz / gap)), depth
	end
	-- The circle's middle is inside the car: out of whichever side is nearest.
	local sides: { { out: Vector2, by: number } } = {
		{ out = -right, by = hw + shape.radius - x },
		{ out = right, by = hw + shape.radius + x },
		{ out = -fwd, by = hl + shape.radius - z },
		{ out = fwd, by = hl + shape.radius + z },
	}
	local best = sides[1]
	for _, side in sides do
		if side.by < best.by then
			best = side
		end
	end
	return best.out, best.by
end

-- The same for a box, by separating axes: four of them in two dimensions, and the
-- smallest overlap among them is the way out.
local function pushFromBox(
	centre: Vector2,
	right: Vector2,
	fwd: Vector2,
	hw: number,
	hl: number,
	shape: Footprint
): (Vector2?, number)
	local d = shape.centre - centre
	local axes = { right, fwd, shape.u, shape.v }
	local best = math.huge
	local dir: Vector2? = nil
	for _, axis in axes do
		local reachCar = hw * math.abs(right:Dot(axis)) + hl * math.abs(fwd:Dot(axis))
		local reachPart = shape.hu * math.abs(shape.u:Dot(axis)) + shape.hv * math.abs(shape.v:Dot(axis))
		local gap = d:Dot(axis)
		local overlap = reachCar + reachPart - math.abs(gap)
		if overlap <= 0 then
			return nil, 0 -- a gap on one axis is a gap: they are apart
		end
		if overlap < best then
			best = overlap
			dir = if gap >= 0 then -axis else axis
		end
	end
	return dir, best
end

export type Live = Model.World & {
	usingTag: boolean,
	surfaceCount: number,
	carBox: Vector3,
	destroy: () -> (),
}

-- The live Workspace. `ignore` is what the rays must never see: the cars.
function World.live(ignore: { Instance }): Live
	local C = Config.Drift

	local groundParams = RaycastParams.new()
	local sweepParams = RaycastParams.new()
	local overlapParams = OverlapParams.new()
	groundParams.IgnoreWater = true
	sweepParams.IgnoreWater = true
	overlapParams.MaxParts = 16

	-- The box the car is solid as. Its own body, not its track: the player reads the car
	-- going through a wall off what they can see of it.
	local carBox = Vector3.new(C.BodyWidth, C.BodyHeight * 0.6, C.BodyLength)

	local self: any = { usingTag = false, surfaceCount = 0, carBox = carBox }

	local function refresh()
		local tagged = CollectionService:GetTagged(C.SurfaceTag)
		self.surfaceCount = #tagged
		-- The ONLY thing hidden from the sweep and the overlap is the cars themselves. The
		-- road used to be hidden from both -- a Blockcast reports only its nearest hit, so
		-- the road under the car hid the building beyond it -- and the price of that
		-- blindness was that no drivable part had any sides at all: the car drove through
		-- the circle's rim and the ramp's flanks and was thrown into the air by the ground
		-- rays on the far side (T-026). The sweep looks past a ground-facing hit instead
		-- (`MAX_SWEEP_LOOKS`); the overlap asks whether the car is above the floor it has
		-- found (`topOf`) before it calls it something to be pushed out of.
		if #tagged > 0 then
			self.usingTag = true
			groundParams.FilterType = Enum.RaycastFilterType.Include
			groundParams.FilterDescendantsInstances = tagged
		else
			-- Nothing is tagged yet: hit whatever is solid, minus the cars.
			self.usingTag = false
			groundParams.FilterType = Enum.RaycastFilterType.Exclude
			groundParams.FilterDescendantsInstances = ignore
		end
		sweepParams.FilterType = Enum.RaycastFilterType.Exclude
		sweepParams.FilterDescendantsInstances = ignore
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = ignore
	end

	refresh()

	local added = CollectionService:GetInstanceAddedSignal(C.SurfaceTag):Connect(refresh)
	local removed = CollectionService:GetInstanceRemovedSignal(C.SurfaceTag):Connect(refresh)

	local up = Vector3.yAxis * C.GroundRayUp
	local down = Vector3.yAxis * -C.GroundRayLength

	-- What the car is standing on. In a world with nothing tagged every solid is the road,
	-- because there is nothing else it could be; in a world that tags its road, anything
	-- untagged the rays reach is "unspecified" and nearly frictionless.
	local function surfaceOf(part: BasePart): (number, number)
		local tagged = CollectionService:HasTag(part, C.SurfaceTag)
		if not tagged then
			if self.usingTag then
				return C.GripUnspecified, C.ScoreUnspecified
			end
			return C.GripTarmac, C.ScoreTarmac
		end
		if part:GetAttribute(C.SurfaceAttribute) == C.SurfaceDirt then
			return C.GripDirt, C.ScoreDirt
		end
		return C.GripTarmac, C.ScoreTarmac
	end

	function self.probe(pos: Vector3): Model.Hit?
		local from = pos + up
		local bottom = from.Y + down.Y
		for _ = 1, MAX_PROBE_LOOKS do
			local reach = from.Y - bottom
			if reach <= EPSILON then
				return nil
			end
			local result = workspace:Raycast(from, Vector3.yAxis * -reach, groundParams)
			if not result then
				return nil
			end
			if math.abs(result.Normal.Y) > GROUND_NORMAL_Y then
				local grip, score = surfaceOf(result.Instance)
				return { y = result.Position.Y, normal = result.Normal, grip = grip, score = score }
			end
			-- The SIDE of something, not a floor (`MAX_PROBE_LOOKS`): drop below it and keep
			-- looking down for the floor it is standing on.
			from = Vector3.new(from.X, result.Position.Y - PROBE_STEP_DOWN, from.Z)
		end
		return nil
	end

	-- WHERE THE CAR MAY GET TO, and the surface that stopped it -- not where the surface
	-- is. Blockcast's `Position` is the point of contact ON THE SURFACE; putting the car's
	-- centre there buries it half its own length in the wall, after which the box overlaps
	-- and Blockcast stops reporting that wall at all. `Distance` is the honest number: how
	-- far the car's own box may travel before it touches. We stop it `WallPush` short of
	-- that, so the next step's cast starts with a gap and can still see the wall.
	--
	-- Every solid is cast against, the road included, and a hit is sorted by its NORMAL:
	-- facing up or down it is ground and the ground rays own it, so it is dropped from the
	-- cast and the cast is made again to see what is behind it. Facing sideways it is a
	-- wall, and a wall made of road -- a rim, a ramp's flank -- is as solid as a building.
	local sweepSkip: { Instance } = {}
	function self.sweep(from: Vector3, to: Vector3, yaw: number): (Vector3?, Vector3?)
		local delta = to - from
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local travel = flat.Magnitude
		if travel < EPSILON then
			return nil, nil
		end
		local box = CFrame.new(from) * CFrame.Angles(0, yaw, 0)
		table.clear(sweepSkip)
		table.move(ignore, 1, #ignore, 1, sweepSkip)
		for _ = 1, MAX_SWEEP_LOOKS do
			sweepParams.FilterDescendantsInstances = sweepSkip
			local result = workspace:Blockcast(box, carBox, flat, sweepParams)
			if not result then
				return nil, nil
			end
			if math.abs(result.Normal.Y) > GROUND_NORMAL_Y then
				table.insert(sweepSkip, result.Instance) -- ground: look past it
				continue
			end
			local n = Vector3.new(result.Normal.X, 0, result.Normal.Z)
			if n.Magnitude < EPSILON then
				return nil, nil
			end
			local allowed = math.max(result.Distance - C.WallPush, 0)
			return from + (flat / travel) * allowed, n.Unit
		end
		return nil, nil
	end

	-- IS THE CAR INSIDE SOMETHING, AND WHICH WAY IS OUT. The sweep keeps the car out of
	-- walls it drives at; this catches everything else, and it is not optional -- once the
	-- car's box overlaps a part by any amount at all, every Blockcast ignores that part
	-- and the car is free to drive through it.
	--
	-- `GetPartBoundsInBox` is only the broad question (it measures parts by their bounding
	-- boxes, so a pillar's corners answer yes when the pillar itself does not); the flat
	-- shapes above are the exact one.
	function self.penetration(pos: Vector3, yaw: number): (Vector3?, number)
		local hw = carBox.X * 0.5 + PENETRATION_MARGIN
		local hl = carBox.Z * 0.5 + PENETRATION_MARGIN
		local halfY = carBox.Y * 0.5
		local grown = Vector3.new(hw * 2, carBox.Y, hl * 2)
		local nearby =
			workspace:GetPartBoundsInBox(CFrame.new(pos) * CFrame.Angles(0, yaw, 0), grown, overlapParams)
		if #nearby == 0 then
			return nil, 0
		end

		local sin, cos = math.sin(yaw), math.cos(yaw)
		local right = Vector2.new(cos, -sin)
		local fwd = Vector2.new(-sin, -cos)
		local centre = Vector2.new(pos.X, pos.Z)
		local low, high = pos.Y - halfY, pos.Y + halfY

		local bestDir: Vector2? = nil
		local bestDepth = 0
		for _, part in nearby do
			local shape = footprint(part)
			if shape.high <= low or shape.low >= high then
				continue -- the car is over it or under it, not in it
			end
			-- A FLOOR the car's underside is above is something it is standing on, not
			-- something it is inside, and the flat shapes above cannot tell the two apart:
			-- a banked band's box reaches as high as its outer edge all the way across, and
			-- the shortest way out of it is sideways off the road. Its SIDES are still
			-- solid -- below the top face this test does not fire -- and so are a
			-- building's, while a car that lands on a building's roof is left on the roof
			-- instead of being thrown half the building's width sideways in one step.
			local up = part.CFrame.UpVector
			if up.Y > GROUND_NORMAL_Y and low >= topOf(part, centre) - EPSILON then
				continue
			end
			local dir, depth
			if shape.circle then
				dir, depth = pushFromCircle(centre, right, fwd, hw, hl, shape)
			else
				dir, depth = pushFromBox(centre, right, fwd, hw, hl, shape)
			end
			if dir and depth > bestDepth then
				bestDir, bestDepth = dir, depth
			end
		end

		if not bestDir or bestDepth <= 0 then
			return nil, 0
		end
		local out = bestDir :: Vector2
		return Vector3.new(out.X, 0, out.Y), bestDepth
	end

	function self.destroy()
		added:Disconnect()
		removed:Disconnect()
	end

	return self :: Live
end

return World
