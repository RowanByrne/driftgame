--!nonstrict
-- CollisionTests: is the world solid?
-- (docs/game/features/drift-model.md "Testing", docs/workflow/TESTING.md, T-018).
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugCollisionTests", "run")
--
-- The car is KINEMATIC: Roblox physics never moves it, so nothing but Drift/World and
-- Drift/Model stops it. These checks are the whole of the proof that a building is a
-- building. The one thing every one of them asks is the same thing, and it is the thing
-- the user reported going wrong -- "i can just go through buildings if i ram them":
--
--   AT THE END OF EVERY STEP, IS ANY PART OF THE CAR'S BODY INSIDE SOMETHING SOLID?
--
-- The geometry that answers it is written out below rather than asked of Drift/World, so
-- that a World that is wrong about its own shapes cannot pass its own test.
--
-- The rig is a plate, a wall, a pillar and a cone built 20,000 studs from the origin, so
-- it runs the same in an empty edit session and in the middle of a playtest, and takes
-- itself down again afterwards.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "CollisionTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(ServerScriptService.Playground.Build)
local Layout = require(ServerScriptService.Playground.Layout)
local Path = require(ServerScriptService.Playground.Path)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")

-- The model under test. Loaded on the first call rather than here, so an edit session can
-- hand in a freshly cloned `Drift` folder instead: Studio caches a ModuleScript's result
-- for the whole session, so an edit session that required the model before Lync synced a
-- change would otherwise be measuring the copy from before it. A playtest always starts
-- with an empty cache and never needs it.
local Model, Sim, World

local function load(folder: Instance?)
	local from = folder or DriftFolder
	Model = require(from.Model)
	Sim = require(from.Sim)
	World = require(from.World)
end

local CollisionTests = {}

local C = Config.Drift

local RIG_NAME = "__CollisionTestRig"
local BASE = Vector3.new(20000, 500, 20000) -- the top of the rig's plate
local WALL_HALF_Z = 10 -- the wall spans z = BASE.Z +/- this
-- Both stand well clear of the wall, so a car driven at one meets it and nothing else.
local PILLAR_AT = Vector3.new(400, 0, 300) -- from BASE
local PILLAR_RADIUS = 9 -- the playground's own
local CONE_AT = Vector3.new(-400, 0, 300)
local CONE_RADIUS = 1.2 -- the playground's own: a 2.4-stud cone
local FPS = 60 -- what the live game feeds Sim; two steps a frame

-- The second half of the rig: the two ELEVATED features, on their own plate well clear of
-- the first, built from the playground's own Layout and Build so the shapes under test are
-- the shapes the world is made of (T-026). The user drove the real ones and reported "some
-- odd interactions there with the physics"; these are what that turned into.
local FEATURES = BASE + Vector3.new(0, 0, 3000) -- the top of their plate
local FEATURE_PLATE = 2000
local BOWL_AT = Vector2.new(-500, 0) -- from FEATURES, in world XZ

-- The third part of the rig: ROAD WITH A GRADE AND A BANK, on its own again (T-073).
--
-- The car's box used to be swept flat, never pitched and never rolled, whatever it was
-- standing on. It rides 1.44 studs up with 7 studs of nose, so past atan(1.44 / 7) = 11.6
-- degrees of grade its nose was inside the hill it was climbing, and past
-- atan(1.44 / 3.2) = 24 degrees of bank its uphill side was inside the road it was leaning
-- on. The road is abutting slabs, so what the buried nose met was the END FACE of the next
-- one -- near-vertical, which the sweep calls a WALL -- and the car stopped dead against
-- its own road. That is what held `Config.Road.MaxGrade` to 8 degrees and `MaxBank` to 20.
--
-- These are built out of the same ribbon the playground's ramp is, at the road's own width
-- and thickness and cut at the road's own segment length, so the joint the nose used to
-- find is the joint that is here. 35 degrees is `Config.Road.MaxSurfaceTilt`, the steepest
-- surface the road may ever build.
local SLOPES = BASE + Vector3.new(0, 0, 6000)
local SLOPE_GRADES = { 8, 12, 20, 30, 35 }
local SLOPE_BANKS = { 20, 25, 30 }
local RAMP_RUNUP = 200 -- studs of level road before the climb starts
local RAMP_LENGTH = 900
local SLOPE_SEGMENT = 12 -- studs of plan length per slab, as a profiled road piece is cut
local BANK_RADIUS = 200
local RAMP_AT = Vector2.new(500, -400) -- where the ramp's climb starts; it runs +Z

--------------------------------------------------------------------------------
-- The geometry, written out: how far is the car's BODY from a thing?
--------------------------------------------------------------------------------

-- The car's own reach along a horizontal direction, from its centre to its skin.
local function reach(yaw: number, dir: Vector3): number
	local fwd, right = Model.axes(yaw)
	return math.abs(C.BodyLength * 0.5 * fwd:Dot(dir)) + math.abs(C.BodyWidth * 0.5 * right:Dot(dir))
end

-- Clear air between the car and a flat face: positive is outside, negative is inside.
local function gapToPlane(pos: Vector3, yaw: number, faceAt: Vector3, outward: Vector3): number
	return (pos - faceAt):Dot(outward) - reach(yaw, outward)
end

-- Clear air between the car and an upright circle, exactly: the nearest point of the
-- car's own rectangle to the circle's middle, less its radius.
local function gapToCircle(pos: Vector3, yaw: number, centre: Vector3, radius: number): number
	local fwd, right = Model.axes(yaw)
	local d = centre - pos
	local x = math.clamp(d:Dot(right), -C.BodyWidth * 0.5, C.BodyWidth * 0.5)
	local z = math.clamp(d:Dot(fwd), -C.BodyLength * 0.5, C.BodyLength * 0.5)
	local off = d - right * x - fwd * z
	return Vector3.new(off.X, 0, off.Z).Magnitude - radius
end

--------------------------------------------------------------------------------
-- The rig
--------------------------------------------------------------------------------

-- The bowl and the ramp, on a plate of their own. `Path` gives nodes at y = 0 and the
-- ribbon's `baseY` puts the whole feature where it belongs, so the only thing that moves
-- is the origin: the geometry is the playground's, to the stud.
local function buildFeatures(rig: Folder)
	local plate = Instance.new("Part")
	plate.Name = "FeaturePlate"
	plate.Anchored = true
	plate.Size = Vector3.new(FEATURE_PLATE, Layout.Plate.thickness, FEATURE_PLATE)
	plate.CFrame = CFrame.new(FEATURES - Vector3.new(0, Layout.Plate.thickness * 0.5, 0))
	plate.Parent = rig
	CollectionService:AddTag(plate, C.SurfaceTag)

	local baseY = FEATURES.Y + Layout.Surface.height

	local bowl = Layout.Circle
	local bankAt, heightAt, skirtBankAt, skirtHeightAt = Build.circleProfiles(bowl)
	local centre = Vector3.new(FEATURES.X + BOWL_AT.X, 0, FEATURES.Z + BOWL_AT.Y)
	for _, ring in {
		{ name = "RigBand", radius = bowl.radius, segments = bowl.segments, width = bowl.width, height = heightAt, bank = bankAt },
		{
			name = "RigApron",
			radius = bowl.skirt.radius,
			segments = bowl.skirt.segments,
			width = bowl.skirt.width,
			height = skirtHeightAt,
			bank = skirtBankAt,
		},
	} do
		Build.ribbon(Path.ring(centre, ring.radius, ring.segments), {
			name = ring.name,
			width = ring.width,
			thickness = bowl.thickness,
			colour = Color3.new(0.4, 0.4, 0.4),
			baseY = baseY,
			heightAt = ring.height,
			bankAt = ring.bank,
			closed = true,
			parent = rig,
		})
	end

	local ramp = Layout.Ramp
	local climbAt, lipAt = Build.rampProfiles(ramp)
	local cursor = Path.cursor(FEATURES.X + RAMP_AT.X, FEATURES.Z + RAMP_AT.Y, ramp.heading)
	local flat = Build.bankProfile(nil, 1)
	for _, piece in {
		{ name = "RigRamp", length = ramp.length, segments = ramp.segments, height = climbAt },
		{ name = "RigRampLip", length = ramp.lip.length, segments = ramp.lip.segments, height = lipAt },
	} do
		Build.ribbon(Path.straight(cursor, piece.length, piece.segments), {
			name = piece.name,
			width = ramp.width,
			thickness = ramp.thickness,
			colour = Color3.new(0.5, 0.5, 0.5),
			baseY = baseY,
			heightAt = piece.height,
			bankAt = flat,
			parent = rig,
		})
	end
end

-- A straight that runs level for `RAMP_RUNUP` studs and then climbs at `deg`, with the
-- grade blended in no faster than the road's own `MaxPitchStep` per segment. The height is
-- the integral of that grade, which is how `Road/Pieces` sets a piece's height out too.
local function rampHeight(deg: number): ((number) -> number, number)
	local g = math.tan(math.rad(deg))
	local blend = math.max(120, math.ceil(deg / Config.Road.MaxPitchStep) * SLOPE_SEGMENT)
	return function(t: number): number
		local s = t * RAMP_LENGTH - RAMP_RUNUP
		if s <= 0 then
			return 0
		end
		if s >= blend then
			return g * (s - blend * 0.5)
		end
		local u = s / blend
		return g * blend * (u * u * u - 0.5 * u * u * u * u) -- the integral of smoothstep
	end,
		blend
end

local function buildRamp(deg: number): (Folder, { Part })
	local rig = Instance.new("Folder")
	rig.Name = RIG_NAME .. "_Ramp"
	local heightAt = rampHeight(deg)
	local parts = Build.ribbon(
		Path.straight(Path.cursor(SLOPES.X, SLOPES.Z, 180), RAMP_LENGTH, math.floor(RAMP_LENGTH / SLOPE_SEGMENT)),
		{
			name = "Ramp",
			width = Config.Road.Width,
			thickness = Config.Road.Thickness,
			colour = Color3.new(0.5, 0.5, 0.5),
			baseY = SLOPES.Y,
			heightAt = heightAt,
			bankAt = function(): number
				return 0
			end,
			parent = rig,
		}
	)
	rig.Parent = workspace
	return rig, parts
end

local function buildBankedRing(deg: number): (Folder, { Part })
	local rig = Instance.new("Folder")
	rig.Name = RIG_NAME .. "_Bank"
	local bank = math.rad(deg)
	local segments = math.ceil(2 * math.pi * BANK_RADIUS / SLOPE_SEGMENT)
	local parts = Build.ribbon(Path.ring(Vector3.new(SLOPES.X, 0, SLOPES.Z + 1500), BANK_RADIUS, segments), {
		name = "Bank",
		width = Config.Road.Width,
		thickness = Config.Road.Thickness,
		colour = Color3.new(0.5, 0.5, 0.5),
		baseY = SLOPES.Y,
		heightAt = function(): number
			return 0
		end,
		bankAt = function(): number
			return bank
		end,
		closed = true,
		parent = rig,
	})
	rig.Parent = workspace
	return rig, parts
end

-- STANDING ANYWHERE ON IT, POINTING ANY WAY: does one step's sweep read a WALL?
--
-- This asks the question the drive asks, exhaustively and without a driver: a car at ride
-- height all over every slab, at five places across the road and five headings, and a
-- sweep as long as one step at 120 studs/s. A drive can only ever say that it did not
-- happen to meet one.
--
-- WALKING ALONG EACH SLAB MATTERS AS MUCH AS WALKING ACROSS IT, and sampling slab centres
-- alone would have found nothing at all: the car is 14 studs long and a slab is 12, so
-- from a slab's middle the nose is already INSIDE the next slab -- and a Blockcast never
-- reports a part its box already overlaps. The flat box only ever met a wall from the
-- places where its nose was still just short of the next joint.
local AUDIT_ALONG = { -0.4, -0.2, 0, 0.2, 0.4 } -- share of a slab's own length
local AUDIT_ACROSS = { -18, -9, 0, 9, 18 } -- studs from the centre line
local AUDIT_HEADINGS = { 0, 20, -20, 90, 180 } -- degrees off the road's direction

local function sweepAudit(world, parts: { Part }): (number, number, string)
	local travel = 120 * C.FixedStep
	local walls, tried = 0, 0
	local where = ""
	for i, p in parts do
		local cf = p.CFrame
		local top = cf.Position + cf.UpVector * (p.Size.Y * 0.5)
		local heading = math.atan2(-cf.LookVector.X, -cf.LookVector.Z)
		for _, along in AUDIT_ALONG do
			for _, off in AUDIT_ACROSS do
				local at = top + cf.RightVector * off + cf.LookVector * (along * p.Size.Z)
				local hit = world.probe(at + Vector3.new(0, 1, 0))
				if not hit then
					continue
				end
				local pos = Vector3.new(at.X, hit.y + C.RideHeight, at.Z)
				for _, deg in AUDIT_HEADINGS do
					local yaw = heading + math.rad(deg)
					local fwd = Model.axes(yaw)
					tried += 1
					local _, normal = world.sweep(pos, pos + fwd * travel, yaw)
					if normal then
						walls += 1
						if where == "" then
							where = string.format(
								"first on %s, %.1f along it, %d studs across it, %d degrees off it",
								p.Name,
								along,
								off,
								deg
							)
						end
					end
				end
			end
		end
		if i % 20 == 0 then
			task.wait()
		end
	end
	return walls, tried, where
end

local function build(): Folder
	local old = workspace:FindFirstChild(RIG_NAME)
	if old then
		old:Destroy()
	end
	local rig = Instance.new("Folder")
	rig.Name = RIG_NAME

	-- Tagged, so the ground rays find it whether or not a playground exists: with a
	-- playground the rays are an INCLUDE list of tagged parts, and an untagged plate here
	-- would leave the test car with nothing under it at all.
	local plate = Instance.new("Part")
	plate.Name = "Plate"
	plate.Anchored = true
	plate.Size = Vector3.new(4000, 24, 1600)
	plate.CFrame = CFrame.new(BASE - Vector3.new(0, 12, 0))
	plate.Parent = rig
	CollectionService:AddTag(plate, C.SurfaceTag)

	-- A long wall across the car's path, untagged: a building is a wall, never road.
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Anchored = true
	wall.Size = Vector3.new(3000, 60, WALL_HALF_Z * 2)
	wall.CFrame = CFrame.new(BASE + Vector3.new(0, 30, 0))
	wall.Parent = rig

	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Anchored = true
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(44, PILLAR_RADIUS * 2, PILLAR_RADIUS * 2)
	pillar.CFrame = CFrame.new(BASE + PILLAR_AT + Vector3.new(0, 22, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = rig

	-- The playground's cone, built the same way PlaygroundService builds one, but
	-- anchored: what is being measured is the geometry, not what physics does to it.
	local cone = Instance.new("Part")
	cone.Name = "Cone"
	cone.Anchored = true
	cone.Shape = Enum.PartType.Cylinder
	cone.Size = Vector3.new(4, CONE_RADIUS * 2, CONE_RADIUS * 2)
	cone.CFrame = CFrame.new(BASE + CONE_AT + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	cone.Parent = rig

	buildFeatures(rig)

	rig.Parent = workspace
	return rig
end

--------------------------------------------------------------------------------
-- Driving at it
--------------------------------------------------------------------------------

-- One run: start the car somewhere, moving somehow, and watch the gap every step.
--   start     where the car's centre begins
--   yaw       where its nose points
--   velocity  what it is doing when the run starts
--   gap       the clear air between car and obstacle, from the helpers above
--   steer     held for the whole run, if any
local function run(o): any
	local runner = Sim.newRunner(CFrame.new(o.start) * CFrame.Angles(0, o.yaw, 0))
	runner.state.velocity = o.velocity
	-- Past `FullThrottleSeconds`, so the drivetrain is at full and the run is not being
	-- measured during the ease-in.
	runner.state.time = 10

	local worstGap = math.huge
	local worstMove = 0
	local hits = 0
	local previous = runner.state.position
	local steps = 0
	local path = {}

	local function observe(s)
		steps += 1
		worstGap = math.min(worstGap, o.gap(s.position, s.yaw))
		worstMove = math.max(worstMove, (s.position - previous).Magnitude)
		previous = s.position
		if s.wallHit then
			hits += 1
		end
		if o.keepPath then
			table.insert(path, { t = s.time - 10, pos = s.position, speed = Model.speed(s), hit = s.wallHit })
		end
	end

	local input = { steer = o.steer or 0 }
	local elapsed = 0
	while elapsed < o.seconds - 1e-9 do
		local dt = math.min(1 / FPS, o.seconds - elapsed)
		Sim.advance(runner, dt, input, o.world, observe)
		elapsed += dt
	end

	return {
		state = runner.state,
		steps = steps,
		worstGap = worstGap,
		finalGap = o.gap(runner.state.position, runner.state.yaw),
		worstMove = worstMove,
		hits = hits,
		endSpeed = Model.speed(runner.state),
		path = path,
	}
end

local function check(checks, name, ok, detail)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
	return ok == true
end

--------------------------------------------------------------------------------
-- The checks
--------------------------------------------------------------------------------

-- Drive at the wall from the far side, at `speed`, with the nose `angleDeg` off the
-- wall's normal (0 is head on, 85 is a graze), the car travelling where it points.
local function atWall(world, speed: number, angleDeg: number, noseOffset: number?, seconds: number?)
	-- Nose along -Z is yaw 0; turning the nose away from square-on turns the car.
	local yaw = math.rad(angleDeg)
	local fwd = Model.axes(yaw)
	local travel = 90
	local start = BASE + Vector3.new(0, C.RideHeight, WALL_HALF_Z) - fwd * travel
	local outward = Vector3.new(0, 0, 1) -- the wall's near face points at the car
	local faceAt = BASE + Vector3.new(0, 0, WALL_HALF_Z)
	return run({
		world = world,
		start = Vector3.new(start.X, BASE.Y + C.RideHeight, start.Z),
		yaw = yaw + math.rad(noseOffset or 0),
		velocity = fwd * speed,
		seconds = seconds or 3,
		gap = function(pos, carYaw)
			return gapToPlane(pos, carYaw, faceAt, outward)
		end,
	})
end

--------------------------------------------------------------------------------
-- The bowl and the ramp
--------------------------------------------------------------------------------

-- The car's own body, as a part, so Roblox can be asked its own exact question: is any of
-- it inside anything? It is CanQuery false, so the model's rays and sweeps never see it.
local function bodyProbe(rig: Folder): BasePart
	local probe = Instance.new("Part")
	probe.Name = "CarBody"
	probe.Size = Vector3.new(C.BodyWidth, C.BodyHeight * 0.6, C.BodyLength)
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanQuery = false
	probe.Transparency = 1
	probe.Parent = rig
	return probe
end

-- How far the car's body is inside a floor, in studs: the deepest of its eight corners
-- below that floor's top face, counting only corners the floor is actually under. A
-- corner hanging over an edge is measured against nothing, which is what it is over.
local function depthInto(pose: CFrame, box: Vector3, part: BasePart): number
	local cf, size = part.CFrame, part.Size
	if cf.UpVector.Y <= 0.7 then
		return math.huge -- not a floor at all: being inside it is never all right
	end
	local worst = 0
	for dx = -1, 1, 2 do
		for dy = -1, 1, 2 do
			for dz = -1, 1, 2 do
				local corner = (pose * CFrame.new(dx * box.X * 0.5, dy * box.Y * 0.5, dz * box.Z * 0.5)).Position
				local local_ = cf:PointToObjectSpace(corner)
				if math.abs(local_.X) <= size.X * 0.5 and math.abs(local_.Z) <= size.Z * 0.5 then
					worst = math.max(worst, size.Y * 0.5 - local_.Y)
				end
			end
		end
	end
	return worst
end

-- One drive at an elevated feature, with everything the complaint needs answering read off
-- it: how high the car got and for how long, where it came down, what its vertical speed
-- did, and whether its body was ever inside the world.
--
-- The car is DROPPED ON TO the surface under `start` rather than placed at a height, so a
-- run never begins with the car half inside the ground it starts on.
local function drive(o): any
	local groundAt = RaycastParams.new()
	groundAt.FilterType = Enum.RaycastFilterType.Exclude
	groundAt.FilterDescendantsInstances = { o.probe }
	local below = workspace:Raycast(o.start + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0), groundAt)
	local start = Vector3.new(o.start.X, (if below then below.Position.Y else o.start.Y) + C.RideHeight, o.start.Z)

	local runner = Sim.newRunner(CFrame.new(start) * CFrame.Angles(0, o.yaw, 0))
	runner.state.velocity = o.velocity
	runner.state.time = 10 -- past the throttle's ease-in

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { o.probe }
	overlap.MaxParts = 4
	local box = o.probe.Size

	local r = {
		start = start,
		apex = -math.huge,
		lowest = math.huge,
		airSeconds = 0,
		longestAir = 0,
		landedAt = -1,
		landedPos = nil,
		takeoffAt = -1,
		maxVy = 0,
		minVy = 0,
		overVy = 0, -- vertical speed the ground cannot explain, while grounded
		insideSteps = 0,
		insideDepth = 0,
		insideWhere = "",
		wallSteps = 0,
	}
	local curAir, airStart = 0, 0

	local function observe(s)
		r.apex = math.max(r.apex, s.position.Y)
		r.lowest = math.min(r.lowest, s.position.Y)
		r.maxVy = math.max(r.maxVy, s.velocity.Y)
		r.minVy = math.min(r.minVy, s.velocity.Y)
		if s.wallHit then
			r.wallSteps += 1
		end
		if s.grounded then
			-- On the ground the car's vertical speed is the surface climbing under it, and
			-- a surface it can stand on is never steeper than 45 degrees: anything past the
			-- horizontal speed is the old spring, or a wall being read as a floor (T-026).
			local flat = math.sqrt(s.velocity.X * s.velocity.X + s.velocity.Z * s.velocity.Z)
			r.overVy = math.max(r.overVy, math.abs(s.velocity.Y) - flat)
		end
		if s.airborne then
			if curAir == 0 then
				airStart = s.time
			end
			curAir += C.FixedStep
			r.airSeconds += C.FixedStep
		else
			if curAir > r.longestAir then
				r.longestAir, r.landedAt, r.landedPos, r.takeoffAt = curAir, s.time, s.position, airStart
				r.landedGround = s.groundY
			end
			curAir = 0
		end

		local pose = Model.cframe(s)
		o.probe.CFrame = pose
		for _, part in workspace:GetPartsInPart(o.probe, overlap) do
			local depth = depthInto(pose, box, part)
			if depth > 0 then
				r.insideSteps += 1
				if depth > r.insideDepth then
					r.insideDepth = depth
					r.insideWhere = string.format(
						"%s, %.3f studs, at (%.1f, %.2f, %.1f)",
						part.Name,
						depth,
						s.position.X,
						s.position.Y,
						s.position.Z
					)
				end
			end
		end
	end

	local input = { steer = o.steer or 0 }
	local elapsed = 0
	while elapsed < o.seconds - 1e-9 do
		local dt = math.min(1 / FPS, o.seconds - elapsed)
		Sim.advance(runner, dt, input, o.world, observe)
		elapsed += dt
	end
	r.state = runner.state
	r.endSpeed = Model.speed(runner.state)
	r.landedAt -= 10
	r.takeoffAt -= 10
	return r
end

-- The three numbers every one of these runs has to come back with.
local function sane(r, plateY: number): (boolean, string)
	-- Down on the ground UNDER it (T-196): a car thrown by the bowl's bank can come down on the
	-- bank, which is not the plate.
	local landed = r.longestAir == 0
		or (r.landedPos ~= nil and math.abs(r.landedPos.Y - (r.landedGround or plateY) - C.RideHeight) < 3)
	return r.insideDepth <= 0 and r.overVy <= 1e-6 and landed and r.lowest > plateY - 1,
		string.format(
			"apex %.2f, %.2f s of air, landed %s, vy %.1f..%.1f (%.3f past what the ground can explain), lowest %.2f, inside %d steps%s",
			r.apex - plateY,
			r.longestAir,
			if r.landedPos then string.format("%.1f studs up", r.landedPos.Y - plateY) else "never left",
			r.minVy,
			r.maxVy,
			r.overVy,
			r.lowest - plateY,
			r.insideSteps,
			if r.insideWhere ~= "" then " (" .. r.insideWhere .. ")" else ""
		)
end

function CollisionTests:run(driftFolder: Instance?)
	load(driftFolder)
	local checks = {}
	local rig = build()
	-- Whatever the car must never see. In a playtest that includes the live cars; the
	-- rig's own plate is tagged, so the sweep drops it anyway.
	local ignore: { Instance } = {}
	local cars = workspace:FindFirstChild("Cars")
	if cars then
		table.insert(ignore, cars)
	end
	local world = World.live(ignore)

	local clear = C.BodyLength * 0.5

	------------------------------------------------------------------ the ram
	local ram = atWall(world, C.TopSpeed, 0)
	check(
		checks,
		"a head-on ram at top speed does not go through",
		ram.finalGap > 0 and ram.worstGap > -1e-6,
		string.format(
			"%.0f studs/s square on: %d steps, %d of them touching; worst gap %.4f studs, final gap %.4f studs clear of the face (a solid car's centre stops %.1f studs out), ended at %.2f studs/s",
			C.TopSpeed,
			ram.steps,
			ram.hits,
			ram.worstGap,
			ram.finalGap,
			clear,
			ram.endSpeed
		)
	)

	------------------------------------------------------------------ the other angles
	local angles = {
		{ label = "a glancing hit (30 degrees off square)", deg = 30 },
		{ label = "a shallow hit (75 degrees off square)", deg = 75 },
		{ label = "a graze (85 degrees off square)", deg = 85 },
	}
	for _, a in angles do
		local r = atWall(world, C.TopSpeed, a.deg)
		check(
			checks,
			a.label .. " does not go through",
			r.finalGap > 0 and r.worstGap > -1e-6,
			string.format(
				"worst gap %.4f studs, final %.4f, %d touching steps, ended at %.1f studs/s (entered at %.0f)",
				r.worstGap,
				r.finalGap,
				r.hits,
				r.endSpeed,
				C.TopSpeed
			)
		)
	end

	------------------------------------------------------------------ sideways into it
	-- Travelling square at the wall with the nose turned 90 degrees across the travel:
	-- the car arrives on its side, which is the shape a drift ends in.
	local sideways = atWall(world, C.TopSpeed, 0, 90)
	check(
		checks,
		"a sideways slide into a wall does not go through",
		sideways.finalGap > 0 and sideways.worstGap > -1e-6,
		string.format(
			"nose across the travel at %.0f studs/s: worst gap %.4f studs, final %.4f, %d touching steps",
			C.TopSpeed,
			sideways.worstGap,
			sideways.finalGap,
			sideways.hits
		)
	)

	------------------------------------------------------------------ the slowest nudge
	-- Barely moving, from close enough that a step is a fraction of the standoff: the
	-- case a sweep that only ever acts on a long cast would miss.
	local faceAt = BASE + Vector3.new(0, 0, WALL_HALF_Z)
	local nudge = run({
		world = world,
		start = BASE + Vector3.new(0, C.RideHeight, WALL_HALF_Z + clear + 1),
		yaw = 0,
		velocity = Vector3.new(0, 0, -0.25),
		seconds = 6,
		gap = function(pos, carYaw)
			return gapToPlane(pos, carYaw, faceAt, Vector3.new(0, 0, 1))
		end,
	})
	check(
		checks,
		"the slowest nudge does not creep through",
		nudge.finalGap > 0 and nudge.worstGap > -1e-6,
		string.format(
			"from 1 stud out at 0.25 studs/s, 6 s of the drivetrain pushing: worst gap %.4f studs, final %.4f, ended at %.2f studs/s",
			nudge.worstGap,
			nudge.finalGap,
			nudge.endSpeed
		)
	)

	------------------------------------------------------------------ the pillar and the cone
	-- A post is the hard case for a sweep: there is very little of it to find, and a step
	-- at top speed covers more than a cone is wide. `offset` moves the line sideways, so
	-- the second of each pair is clipped with a corner rather than met square.
	local posts = {
		{ label = "a pillar", centre = BASE + PILLAR_AT, radius = PILLAR_RADIUS, offset = 0 },
		{ label = "a pillar, clipped with a corner", centre = BASE + PILLAR_AT, radius = PILLAR_RADIUS, offset = 11 },
		{ label = "a cone", centre = BASE + CONE_AT, radius = CONE_RADIUS, offset = 0 },
		{ label = "a cone, clipped with a corner", centre = BASE + CONE_AT, radius = CONE_RADIUS, offset = 4 },
	}
	for _, post in posts do
		local centre = post.centre
		local radius = post.radius
		local r = run({
			world = world,
			start = centre + Vector3.new(post.offset, C.RideHeight, 150),
			yaw = 0,
			velocity = Vector3.new(0, 0, -C.TopSpeed),
			seconds = 3,
			gap = function(pos, carYaw)
				return gapToCircle(pos, carYaw, centre, radius)
			end,
		})
		check(
			checks,
			`a ram at top speed into {post.label} does not go through`,
			r.finalGap > 0 and r.worstGap > -1e-6,
			string.format(
				"%.1f studs across, %.0f studs/s, line offset %.0f studs (a step covers %.2f): worst gap %.4f studs, final %.4f, %d touching steps, ended at %.1f studs/s",
				radius * 2,
				C.TopSpeed,
				post.offset,
				C.TopSpeed * C.FixedStep,
				r.worstGap,
				r.finalGap,
				r.hits,
				r.endSpeed
			)
		)
	end

	------------------------------------------------------------------ scraping along it
	-- Five seconds held five degrees into the wall at speed: the car must slide, not
	-- stick, not climb, and not chatter. `worstMove` is the biggest a single step moved
	-- it, against the 1.49 studs a free step at top speed covers.
	local scrapeFace = BASE + Vector3.new(0, 0, WALL_HALF_Z)
	local scrape = run({
		world = world,
		start = BASE + Vector3.new(-700, C.RideHeight, WALL_HALF_Z + C.BodyWidth * 0.5 + 2),
		yaw = math.rad(-85), -- nose down +X, leaned five degrees into the wall
		velocity = Vector3.new(150, 0, 0),
		seconds = 5,
		gap = function(pos, carYaw)
			return gapToPlane(pos, carYaw, scrapeFace, Vector3.new(0, 0, 1))
		end,
	})
	local free = C.TopSpeed * C.FixedStep
	check(
		checks,
		"a car driven along a wall slides, and does not stick, jitter or climb",
		scrape.worstGap > -1e-6 and scrape.worstMove <= free + 1e-6 and scrape.endSpeed > 40,
		string.format(
			"5 s at five degrees into it: worst gap %.4f studs, worst step %.4f studs (a free step at top speed is %.4f), %d of %d steps touching, speed %.0f -> %.0f studs/s, height %.4f studs off the plate (ride height %.2f)",
			scrape.worstGap,
			scrape.worstMove,
			free,
			scrape.hits,
			scrape.steps,
			150,
			scrape.endSpeed,
			scrape.state.position.Y - BASE.Y,
			C.RideHeight
		)
	)

	------------------------------------------------------------------ out of a wall again
	-- The recovery path on its own, started from EXACTLY where the bug used to put the
	-- car: the old step took the sweep's contact point for the car's new centre, which
	-- buried it half its own length, less `WallPush`, in the first wall it touched. One
	-- step must have it outside again.
	local sunk = C.BodyLength * 0.5 - C.WallPush
	local buried = Sim.newRunner(CFrame.new(BASE + Vector3.new(200, C.RideHeight, WALL_HALF_Z - sunk + clear)))
	buried.state.time = 10
	local before = gapToPlane(buried.state.position, buried.state.yaw, scrapeFace, Vector3.new(0, 0, 1))
	Sim.advance(buried, C.FixedStep, { steer = 0 }, world)
	local after = gapToPlane(buried.state.position, buried.state.yaw, scrapeFace, Vector3.new(0, 0, 1))
	check(
		checks,
		"a car that starts inside a wall is put outside it",
		before < 0 and after > 0,
		string.format("%.2f studs inside the face -> %.4f studs clear of it, in one step", -before, after)
	)

	------------------------------------------------------------------ the sweep still sees it
	-- The fact the whole bug came from, pinned down so it cannot come back: a Blockcast
	-- whose box overlaps a part never reports that part, so a car allowed to touch a wall
	-- is blind to it from then on. These are Roblox's answers, not ours.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rig.Plate }
	local box = Vector3.new(C.BodyWidth, C.BodyHeight * 0.6, C.BodyLength)
	local at = BASE + Vector3.new(0, C.RideHeight, WALL_HALF_Z + clear)
	local touching = workspace:Blockcast(CFrame.new(at), box, Vector3.new(0, 0, -2), params)
	local standing = workspace:Blockcast(
		CFrame.new(at + Vector3.new(0, 0, C.WallPush)),
		box,
		Vector3.new(0, 0, -2),
		params
	)
	check(
		checks,
		"the standoff is what keeps the sweep able to see the wall",
		touching == nil and standing ~= nil,
		string.format(
			"a box touching the wall reports %s; the same box held %.2f studs off it (WallPush) reports a hit at %.3f studs",
			touching == nil and "nothing at all" or "a hit",
			C.WallPush,
			standing and standing.Distance or -1
		)
	)

	------------------------------------------------------------------ the bowl and the ramp
	-- What the user reported: "when i go over to the bowl ramp thing, there's some odd
	-- interactions there with the physics" (T-026). Before these, the bowl's rim threw the
	-- car 144 studs into the air and the ramp was not a jump at all.
	local probe = bodyProbe(rig)
	local plateY = FEATURES.Y
	local rampZ = FEATURES.Z + RAMP_AT.Y
	local rampX = FEATURES.X + RAMP_AT.X
	local bowl = Vector3.new(FEATURES.X + BOWL_AT.X, plateY, FEATURES.Z + BOWL_AT.Y)
	local bowlOuter = Layout.Circle.skirt.radius + Layout.Circle.skirt.width * 0.5

	-- A line into a feature: `yaw` is where the nose points, and the car travels that way.
	local function at(from: Vector3, yaw: number, speed: number, seconds: number, steer: number?)
		return drive({
			world = world,
			probe = probe,
			start = from,
			yaw = yaw,
			velocity = Model.axes(yaw) * speed,
			steer = steer,
			seconds = seconds,
		})
	end

	-- The ramp, square on, from a crawl to top speed. It has to leave the ground and come
	-- down on it, every time, and never end a step inside itself.
	local jumps = {}
	for _, speed in { 20, 60, 100, 140, 179 } do
		-- Long enough that even a car that arrives at the ramp at a crawl has climbed it,
		-- flown and come down again inside the run.
		local r = at(Vector3.new(rampX, plateY, rampZ - 60), math.pi, speed, 7)
		table.insert(jumps, r)
		local ok, detail = sane(r, plateY)
		check(
			checks,
			`the ramp jumps the car at {speed} studs/s and lands it on the ground`,
			ok and r.longestAir > 0.5,
			detail
		)
		task.wait()
	end
	check(
		checks,
		"the faster the ramp is taken, the further the car goes",
		(function()
			for i = 2, #jumps do
				if jumps[i].apex <= jumps[i - 1].apex or jumps[i].longestAir <= jumps[i - 1].longestAir then
					return false
				end
			end
			return true
		end)(),
		(function()
			local parts = {}
			for _, r in jumps do
				table.insert(parts, string.format("%.2f studs / %.2f s", r.apex - plateY, r.longestAir))
			end
			return "20 to 179 studs/s, apex and air time: " .. table.concat(parts, ", ")
		end)()
	)

	-- And taken at an angle, including off the side of it.
	for _, deg in { -25, -15, 15, 25 } do
		local r = at(Vector3.new(rampX, plateY, rampZ + 5), math.pi + math.rad(deg), 140, 5)
		local ok, detail = sane(r, plateY)
		check(checks, `the ramp taken {deg} degrees off square keeps the car out of itself`, ok, detail)
		task.wait()
	end

	-- The ramp's flank is 9 studs of road standing out of the plate, and road or not it is
	-- a wall: this is the one the car used to be thrown 43 studs into the air by.
	for _, speed in { 0.25, 20, 179 } do
		local r = at(Vector3.new(rampX - 70, plateY, rampZ + 60), -math.pi * 0.5, speed, 6)
		local ok, detail = sane(r, plateY)
		check(
			checks,
			`the ramp's flank stops a car at {speed} studs/s instead of launching it`,
			ok and r.airSeconds == 0 and r.apex - plateY < C.RideHeight + 0.5,
			detail .. string.format(", %d touching steps, ended at %.1f studs/s", r.wallSteps, r.endSpeed)
		)
		task.wait()
	end

	-- The bowl: across it, round it, and out of the middle of it. `miss` is how far from
	-- the middle the line is aimed, so 0 is dead across and 150 is a chord through the
	-- band -- the car crossing the rim at an angle rather than square to it.
	local approach = bowlOuter + 90
	for _, speed in { 60, 120, 179 } do
		for _, miss in { 0, 150 } do
			local off = math.asin(miss / approach)
			local yaw = math.pi * 0.5 + off
			local r = at(bowl + Vector3.new(approach, 0, 0), yaw, speed, math.min(6, 760 / speed))
			local ok, detail = sane(r, plateY)
			check(
				checks,
				`the bowl is crossed at {speed} studs/s, aimed {miss} studs off the middle`,
				ok and not r.state.airborne,
				detail
			)
			task.wait()
		end
	end
	for _, speed in { 60, 179 } do
		local r = at(bowl, math.pi * 0.5, speed, math.min(5, 450 / speed))
		local ok, detail = sane(r, plateY)
		check(checks, `the bowl is driven out of the middle at {speed} studs/s`, ok and not r.state.airborne, detail)
		task.wait()
	end
	local around = at(bowl + Vector3.new(Layout.Circle.radius, 0, 0), math.pi, 90, 6, -0.3)
	local aroundOk, aroundDetail = sane(around, plateY)
	check(checks, "the bowl is driven round, on the band, with a finger held", aroundOk, aroundDetail)
	task.wait()

	-- The slowest possible approach to the rim, which a sweep alone cannot hold: a
	-- Blockcast only reaches as far as the step travels, so at a crawl it never reports a
	-- hit at all and the standoff closes without one (T-026).
	local creep = at(bowl + Vector3.new(bowlOuter + 10, 0, 0), math.pi * 0.5, 0.25, 8)
	local creepOk, creepDetail = sane(creep, plateY)
	check(checks, "a crawl into the bowl's edge does not creep into it", creepOk, creepDetail)
	task.wait()

	------------------------------------------------------------------ grade and bank
	-- The road's third dimension (T-073). The audit is the real check -- it asks every
	-- slab, from five places across the road and seven headings, rather than hoping a
	-- drive happens to meet the bad one -- and the drives are there because "stopped dead
	-- on the hill" is what the player would actually see.
	for _, deg in SLOPE_GRADES do
		local ramp, ribbon = buildRamp(deg)
		task.wait() -- let the tag signals run, so the ground rays can see it
		local walls, tried, where = sweepAudit(world, ribbon)
		check(
			checks,
			`a {deg} degree climb never reads as a wall`,
			walls == 0,
			string.format(
				"%d of %d sweeps, from 25 places on each of %d slabs at five headings%s",
				walls,
				tried,
				#ribbon,
				if where ~= "" then " -- " .. where else ""
			)
		)
		ramp:Destroy()
		task.wait()
	end

	-- Driven, at the three grades the car has the power to climb. Above about 24 degrees
	-- it runs out of drivetrain and stops, which is gravity and not the sweep: the audit
	-- above is what covers the steep end.
	for _, deg in { 8, 12, 20 } do
		local ramp = buildRamp(deg)
		task.wait()
		local yaw = math.pi
		local r = drive({
			world = world,
			probe = probe,
			start = Vector3.new(SLOPES.X, SLOPES.Y, SLOPES.Z + 40),
			yaw = yaw,
			velocity = Model.axes(yaw) * 90,
			seconds = 9,
		})
		local ok, detail = sane(r, SLOPES.Y)
		check(
			checks,
			`a car driven at a {deg} degree climb climbs it instead of stopping dead`,
			ok and r.wallSteps == 0 and r.endSpeed > 40,
			string.format(
				"entered at 90 studs/s, no steering: climbed %.1f studs in 9 s and left at %.1f studs/s, %d touching steps; %s",
				r.apex - SLOPES.Y - C.RideHeight,
				r.endSpeed,
				r.wallSteps,
				detail
			)
		)
		ramp:Destroy()
		task.wait()
	end

	for _, deg in SLOPE_BANKS do
		local ring, ribbon = buildBankedRing(deg)
		task.wait()
		local walls, tried, where = sweepAudit(world, ribbon)
		check(
			checks,
			`a {deg} degree bank never reads as a wall`,
			walls == 0,
			string.format(
				"%d of %d sweeps, from 25 places on each of %d slabs at five headings%s",
				walls,
				tried,
				#ribbon,
				if where ~= "" then " -- " .. where else ""
			)
		)
		ring:Destroy()
		task.wait()
	end

	-- Determinism: the same approach twice, within a stud. There is nothing random in any
	-- of this, and a drift is only learnable if that stays true.
	local repeats = {
		{ label = "the ramp at top speed", from = Vector3.new(rampX, plateY, rampZ - 60), yaw = math.pi, speed = 179, steer = 0 },
		{
			label = "the ramp at 15 degrees",
			from = Vector3.new(rampX, plateY, rampZ + 5),
			yaw = math.pi + math.rad(15),
			speed = 140,
			steer = 0,
		},
		{
			label = "the bowl with a finger held",
			from = bowl + Vector3.new(bowlOuter + 90, 0, 0),
			yaw = math.pi * 0.5,
			speed = 120,
			steer = -0.3,
		},
	}
	for _, c in repeats do
		local a = at(c.from, c.yaw, c.speed, 5, c.steer)
		local b = at(c.from, c.yaw, c.speed, 5, c.steer)
		local apart = (a.state.position - b.state.position).Magnitude
		check(
			checks,
			`{c.label}, twice, is the same line`,
			apart < 1,
			string.format(
				"%.6f studs apart after 5 s, ending at (%.1f, %.2f, %.1f)",
				apart,
				a.state.position.X,
				a.state.position.Y,
				a.state.position.Z
			)
		)
		task.wait()
	end

	world.destroy()
	rig:Destroy()

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

-- The ram, step by step, for a report: every position through the wall rather than the
-- verdict. `angle` is degrees off square, `speed` studs/s.
function CollisionTests:trace(speed: number?, driftFolder: Instance?)
	load(driftFolder)
	local rig = build()
	local world = World.live({})
	local lines = {}
	local faceAt = BASE + Vector3.new(0, 0, WALL_HALF_Z)
	local runner = Sim.newRunner(CFrame.new(BASE + Vector3.new(0, C.RideHeight, WALL_HALF_Z + 100)))
	runner.state.velocity = Vector3.new(0, 0, -(speed or C.TopSpeed))
	runner.state.time = 10
	local n = 0
	local function observe(s)
		n += 1
		local gap = gapToPlane(s.position, s.yaw, faceAt, Vector3.new(0, 0, 1))
		if gap < 20 then
			table.insert(
				lines,
				string.format(
					"step %3d  z=%9.3f  gap=%8.4f  speed=%7.2f  hit=%s",
					n,
					s.position.Z - BASE.Z,
					gap,
					Model.speed(s),
					tostring(s.wallHit)
				)
			)
		end
	end
	local elapsed = 0
	while elapsed < 2 - 1e-9 do
		Sim.advance(runner, 1 / FPS, { steer = 0 }, world, observe)
		elapsed += 1 / FPS
	end
	world.destroy()
	rig:Destroy()
	return lines
end

return CollisionTests
