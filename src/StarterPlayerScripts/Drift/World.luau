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
--
-- AND BOTH ASK ABOUT A BOX THAT FOLLOWS THE SURFACE (T-073). The box used to be swept
-- flat -- yawed and never pitched, never rolled -- whatever the road was doing, and that
-- was the binding limit on how steep a road could be. It rides `RideHeight` up with 1.44
-- studs of air under it, 7 studs of nose in front and 3.2 studs either side, so above
-- atan(1.44 / 7) = 11.6 degrees of grade its nose is inside the hill it is climbing, and
-- above atan(1.44 / 3.2) = 24 degrees of bank its uphill side is inside the road it is
-- leaning on. The road is built of abutting slabs, so what the buried nose meets is the
-- END FACE of the next slab -- near-vertical, which is a WALL -- and the car stops dead
-- against its own road. Measured before this change: a straight ramp stopped the car dead
-- at 12 degrees, and a 30-degree bank read as a wall 17 times in two drives.
--
-- So the box is tilted on to the surface under it, exactly as `Drift/Model`'s `basis`
-- tilts the car: the ground ray's own normal, the same ray `probe` makes. The model keeps
-- a smoothed `up` on its state but hands this module only a yaw, so the tilt is read off
-- the ground here rather than passed in -- and read off it fresh, which is if anything
-- more current than the state's own `up` (the model updates that AFTER the wall pass).
--
-- ON LEVEL GROUND THE TILTED FRAME IS THE FLAT ONE, and the flat path below is kept as
-- the exact expression it always was, so the playground, the buildings, the cones and the
-- flat road are bit-for-bit what they were. In the air there is no tilt either: a car more
-- than `AirborneMargin` above the surface gets the flat box, which is what it had.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Model = require(script.Parent.Model)

local World = {}

-- SET THIS FALSE AND THE BOX IS SWEPT FLAT AGAIN, exactly as it was before T-073: both
-- queries take their flat path, which is the expression they always had. It is here so
-- that the measurement behind this change can be repeated -- a ramp at each grade, a
-- corner at each bank, with and without -- rather than taken on trust. It is not a tuning
-- number and nothing in the game reads it.
World.DebugTilt = true

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
-- The car's own frame, tilted on to the surface it is standing on
--------------------------------------------------------------------------------
-- The same three vectors `Drift/Model`'s `basis` builds, from the same two things: the
-- car's yaw, and the up it is standing on. Written out here rather than borrowed because
-- `basis` is the model's own private function and takes a whole State.

local function tiltedFrame(yaw: number, up: Vector3): (Vector3, Vector3, Vector3)
	local flat, flatRight = Model.axes(yaw)
	local right = flat:Cross(up)
	if right.Magnitude < EPSILON then
		return flat, flatRight, Vector3.yAxis -- the car is on its side: nothing to tilt to
	end
	right = right.Unit
	return up:Cross(right), right, up
end

-- The car's box, posed. `Vector3.yAxis` is passed through as the EXACT expression the
-- flat sweep always used, so level ground stays bit-for-bit what it was.
local function carPose(pos: Vector3, yaw: number, up: Vector3): CFrame
	if up == Vector3.yAxis then
		return CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	end
	local _, right = tiltedFrame(yaw, up)
	return CFrame.fromMatrix(pos, right, up)
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
-- WHICH WAY IS UP OUT OF A GROUND PART, and how far its top face is from its middle.
--
-- For a box that is `UpVector` and half the Y size, which is what it always was. NOT for a
-- WedgePart: `Road/Builder` builds a segment of road as triangles wherever a box cannot
-- lie in the surface (T-066), and a wedge's triangular faces are its +/-X ones, so the
-- road is its `RightVector` face and its thickness is X. Reading `UpVector` off one of
-- those gives a near-horizontal vector, and everything downstream then decides the car is
-- INSIDE the road rather than standing on it. Measured before this existed: the car was
-- shoved sideways into the barrier and the 50-piece drive got 2 pieces in at 5 studs/s.
--
-- The branch is explicit rather than "whichever axis is most vertical" so that nothing
-- about a BOX changes by even a bit.
local function surfaceAxis(part: BasePart): (Vector3, number)
	if part:IsA("WedgePart") then
		return part.CFrame.RightVector, part.Size.X * 0.5
	end
	return part.CFrame.UpVector, part.Size.Y * 0.5
end

local function topOf(part: BasePart, at: Vector2): number
	local up, half = surfaceAxis(part)
	local c = part.CFrame.Position
	return c.Y + (half - (at.X - c.X) * up.X - (at.Y - c.Z) * up.Z) / up.Y
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
	-- How many times the ground-ray include list has actually been rebuilt. It exists so
	-- that "one rebuild a piece, not five hundred" (T-088, below) is a number a test can
	-- read rather than a claim; nothing in the game reads it.
	refreshes: number,
	carBox: Vector3,
	-- The pose `sweep` and `penetration` ask about: the car's box, tilted on to the
	-- surface under it. Exposed so a test can rebuild the same box rather than guess at it.
	carFrame: (pos: Vector3, yaw: number) -> CFrame,
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

	local self: any = { usingTag = false, surfaceCount = 0, carBox = carBox, refreshes = 0 }

	local function refresh()
		local tagged = CollectionService:GetTagged(C.SurfaceTag)
		self.refreshes += 1
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

	-- ONE REBUILD PER BURST OF TAGS, NOT ONE PER TAG (T-088). `refresh` above is not a
	-- cheap function: it is a `GetTagged` over every tagged part in the place plus a whole
	-- `FilterDescendantsInstances` assignment, measured at 0.243 ms with 3 196 tags in the
	-- world and 0.600 ms with 5 599. The two CollectionService signals below fire
	-- SYNCHRONOUSLY, once per tagged descendant, inside the single `.Parent` write that
	-- replicates a road piece and inside the `Destroy()` that retires one -- and a piece is
	-- up to 403 parts carrying 256 tagged slabs. Wired straight to `refresh`, as they were,
	-- one piece changing cost about 512 rebuilds of the same list, and the bill grew with
	-- the road: measured on the client, every piece the window moved spiked a frame to
	-- 43-322 ms against an 8.4 ms median, and the SAME piece replicated with its tags
	-- stripped spiked 10.6 ms instead of 159.6 ms (T-085). That was the whole of the freeze
	-- the user felt in a run.
	--
	-- So a tag arriving or leaving only sets a flag. The list is rebuilt once, at the first
	-- moment either of the two things that can read it happens:
	--
	--   `ensure()` at the top of `probe`, which is the ONLY place `groundParams` is read.
	--     This is what makes the coalescing safe rather than merely fast: the include list
	--     is rebuilt before the question is asked, in the same call, so it is never stale
	--     when the car asks. `sweepParams` and `overlapParams` depend only on `ignore`,
	--     which never changes, so nothing else needs the guard.
	--   a `task.defer`, so `usingTag` and `surfaceCount` -- which `DriftController` reports
	--     and which nothing calls `probe` to read -- are as fresh as they were before, even
	--     on a frame where the model never runs.
	--
	-- THE FIRST ONE IS STILL SYNCHRONOUS, below, so a car that spawns into an
	-- already-tagged world has a correct filter on its very first step.
	local dirty = false
	local dead = false

	local function ensure()
		if not dirty or dead then
			return
		end
		dirty = false
		refresh()
	end

	local function touched()
		if dirty then
			return
		end
		dirty = true
		task.defer(ensure)
	end

	refresh()

	local added = CollectionService:GetInstanceAddedSignal(C.SurfaceTag):Connect(touched)
	local removed = CollectionService:GetInstanceRemovedSignal(C.SurfaceTag):Connect(touched)

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
		ensure() -- the include list, if any tag has moved since it was last built
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

	-- THE UP THE CAR'S BOX IS TILTED ON TO (T-073): the normal of the ground under it, or
	-- straight up when there is nothing under it to follow. Nothing is smoothed and
	-- nothing is remembered -- the same position and yaw always give the same box, which
	-- is what keeps a drive repeatable.
	--
	-- A CAR IN THE AIR IS NOT TILTED, by the model's own test (`AirborneMargin`): over a
	-- jump its body levels out, the ground below it is nothing to do with its attitude,
	-- and a flat box there is exactly what it had before this change.
	local function surfaceUp(pos: Vector3): Vector3
		if not World.DebugTilt then
			return Vector3.yAxis
		end
		local hit = self.probe(pos)
		if not hit then
			return Vector3.yAxis
		end
		if pos.Y - (hit.y + C.RideHeight) > C.AirborneMargin then
			return Vector3.yAxis
		end
		local n = hit.normal
		if n.Y <= 0 or n.Magnitude < EPSILON then
			return Vector3.yAxis -- the underside of something: not an attitude
		end
		return n.Unit
	end

	-- WHERE A STEP'S FACE IS, for the floor solve (`Drift/Suspension`, T-095): one ray cast
	-- sideways at the height just under a ledge's top, from over the drop toward the ledge,
	-- against the same surfaces the ground rays see. Its hit is the face; a hit on anything
	-- facing up or down is a slope or a floor, not a step, and answers nothing.
	function self.edge(from: Vector3, to: Vector3): Vector3?
		ensure()
		local result = workspace:Raycast(from, to - from, groundParams)
		if not result or math.abs(result.Normal.Y) > GROUND_NORMAL_Y then
			return nil
		end
		return result.Position
	end

	function self.carFrame(pos: Vector3, yaw: number): CFrame
		return carPose(pos, yaw, surfaceUp(pos))
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
	--
	-- The box is POSED ON THE SURFACE (T-073) and then cast HORIZONTALLY, which is what the
	-- model asks for: the wall pass works in the flat and puts the height back afterwards.
	-- The two are compatible as long as a step's travel cannot climb through the 1.44 studs
	-- of air under the box, and it cannot: at top speed a step covers 1.49 studs, which on
	-- a 35-degree surface -- the steepest `Config.Road.MaxSurfaceTilt` allows -- eats 0.86
	-- of the 1.18 that is there. It would only run out at about 45 degrees.
	local sweepSkip: { Instance } = {}
	function self.sweep(from: Vector3, to: Vector3, yaw: number): (Vector3?, Vector3?)
		local delta = to - from
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local travel = flat.Magnitude
		if travel < EPSILON then
			return nil, nil
		end
		local box = carPose(from, yaw, surfaceUp(from))
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
	--
	-- THE CAR'S BOX IS TILTED HERE TOO (T-073), and the tilt reaches three numbers. Its
	-- FOOTPRINT is the box's shadow, which a tilt barely changes -- at 30 degrees of bank
	-- the car is 6.50 studs wide instead of 6.40 -- but its BAND OF HEIGHT grows a lot: a
	-- box pitched 12 degrees reaches 2.39 studs above and below its middle where a flat one
	-- reaches 0.96. And the test that leaves a floor alone has to grow with it, or a car
	-- climbing a hill would read its own road as something to be shoved sideways out of.
	--
	-- The horizontal AXES are untouched, and that is exact rather than near enough: tilting
	-- about the car's own right or forward axis leaves both of their shadows pointing
	-- exactly where they did. Only the reaches along them change.
	function self.penetration(pos: Vector3, yaw: number): (Vector3?, number)
		local bw, bh, bl = carBox.X * 0.5, carBox.Y * 0.5, carBox.Z * 0.5
		local sin, cos = math.sin(yaw), math.cos(yaw)
		local right = Vector2.new(cos, -sin)
		local fwd = Vector2.new(-sin, -cos)

		local up = surfaceUp(pos)
		local carFwd, carRight = tiltedFrame(yaw, up)
		local hw, hl, halfY
		if up == Vector3.yAxis then
			-- Level ground: the expressions the flat overlap always used, to the bit.
			hw = bw + PENETRATION_MARGIN
			hl = bl + PENETRATION_MARGIN
			halfY = bh
		else
			-- The box's shadow on the ground, along each of the two axes above, and the
			-- band of world height it occupies. Each is the box's three half-extents
			-- projected on to the direction being asked about.
			local rightH = math.sqrt(carRight.X * carRight.X + carRight.Z * carRight.Z)
			local fwdH = math.sqrt(carFwd.X * carFwd.X + carFwd.Z * carFwd.Z)
			hw = bw * rightH + bh * math.abs(up.X * right.X + up.Z * right.Y) + PENETRATION_MARGIN
			hl = bl * fwdH + bh * math.abs(up.X * fwd.X + up.Z * fwd.Y) + PENETRATION_MARGIN
			halfY = bw * math.abs(carRight.Y) + bl * math.abs(carFwd.Y) + bh * math.abs(up.Y)
		end

		-- The broad question is asked about exactly the region the exact one covers: the
		-- box's shadow, upright, through the band of height it occupies. Tilting this one
		-- would make it SMALLER than what is tested against it. Flat, it is the same box
		-- it always was -- `halfY * 2` is `carBox.Y`.
		local grown = Vector3.new(hw * 2, halfY * 2, hl * 2)
		local nearby =
			workspace:GetPartBoundsInBox(CFrame.new(pos) * CFrame.Angles(0, yaw, 0), grown, overlapParams)
		if #nearby == 0 then
			return nil, 0
		end

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
			--
			-- ASKED ALONG THE FLOOR'S OWN NORMAL, not straight down, and against the car's
			-- UNTILTED half-height: the question is whether the car is STANDING on this
			-- floor, not whether a corner of its box grazes it. Those are not the same
			-- question, and asking the second one is a trap -- a box pitched 12 degrees at
			-- ride height reaches 2.394 studs below its middle and the ride height is 2.4,
			-- so a car at the foot of a ramp would be six thousandths of a stud from being
			-- "inside" the plate it is driving off, and the way out of a plate is half a
			-- plate sideways. On level ground this is the plain `low >= topOf` it always
			-- was, to the bit.
			local n = (surfaceAxis(part))
			if n.Y > GROUND_NORMAL_Y and (pos.Y - topOf(part, centre)) * n.Y >= bh - EPSILON then
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

	-- TORN DOWN MEANS TORN DOWN: a `task.defer` queued by the last tag to arrive can only
	-- run after this, so `dead` is what stops it rebuilding a filter for a world nobody
	-- holds any more.
	function self.destroy()
		dead = true
		dirty = false
		added:Disconnect()
		removed:Disconnect()
	end

	return self :: Live
end

return World
