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
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "CollisionTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)

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
