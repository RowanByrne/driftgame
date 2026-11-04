--!nonstrict
-- RunTests: the run -- the start button, where you spawn, what a fall does, and getting
-- back to the other two worlds (docs/game/features/endless-run.md "Testing", T-044 step 3).
--
-- Run it from the server debug bridge, IN A PLAYTEST:
--   game.ServerStorage.DebugBridge:Invoke("DebugRunTests", "run")
--
-- IT NEEDS A PLAYER, and that is not an accident of the harness: every question this suite
-- asks is about a car being moved, and `CarService` will not move a car for somebody who
-- is not there. `RoadTests` is the suite that runs without one -- it is about the road,
-- which has no idea anybody exists. With no player in the place this returns one failing
-- check saying so rather than passing vacuously.
--
-- The second driver is `RoadService:DebugJoin`, a bare userId on the roster with no car
-- behind it, because Studio gives a test exactly one player. What that cannot prove --
-- somebody else's CAR moving -- is called out in the check's own detail rather than
-- quietly counted as proved.
--
-- It leaves the place as it found it: every road it builds it takes down, and the player
-- is put back in the world they were in when it started.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "RunTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Pieces = require(ReplicatedStorage.Shared.Road.Pieces)
local CarService = require(ServerScriptService.Services.CarService)
local RoadService = require(ServerScriptService.Services.RoadService)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")

local STAND_IN = -4044 -- the second driver's userId. Negative, so it can never be a real one
local DRIVE_PIECES = 30
local DRIVE_SECONDS = 300
local DRIVE_FPS = 60
local LOOK_SECONDS = 0.9 -- the autopilot's lookahead, and a property of the DRIVER, not the
-- road (`RoadTests`, which measured it). Copied rather than shared
-- because that file belongs to another task
local LOOK_MIN, LOOK_MAX = 30, 120
local BRAKE_LOOK = 1.6 -- seconds ahead the autopilot reads the corner it is about to meet
local BRAKE_LIMIT = 65 -- studs/s^2 of cornering it will ask of the car before it uses the
-- handbrake. NOT OPTIONAL, which this suite found out the hard way: with
-- the brake left out the car entered the first real corner at 113 studs/s,
-- ran wide to 10 studs off the centre line, wedged against the barrier at
-- piece 3 and sat there for the remaining 294 seconds. The same autopilot
-- with the brake drives the same road
local DRIVE_SEED = 8080 -- the road the drive is measured on. PINNED, and only here: the
-- button's own seed is the server's clock and check 2 is what proves it.
-- A measurement that quoted a different road every time would not be a
-- measurement -- and 8080 is the seed `RoadTests` published its numbers on,
-- so the two drives are comparable

-- THE DESCENDING ROAD, which the shipped piece set cannot lay: every one of its nine
-- pieces is flat (`features/road-elevation.md`). This is `RoadTests`' `Plunge` fixture --
-- a straight that loses 20 studs over its 220 and hands the next piece a level road -- and
-- it is spliced in for one drive and taken straight back out. 30 of them is 600 studs
-- below where the old absolute `RespawnBelowY = -150` sat, which is the only road on which
-- the difference between an absolute fall test and a relative one can be measured at all.
local OLD_RESPAWN_BELOW_Y = -150 -- what `Config.Drift.RespawnBelowY` was before T-067, and
-- it is in this suite for one reason: so a drive can say how many
-- of its own steps the old absolute test would have called a fall
local DESCENT_SEED = 8080
local DESCENT_PIECES = 30
local DESCENT_PIECE = {
	kind = "Descent",
	Shape = "straight",
	weight = 1,
	minPieces = 0,
	mirror = false,
	Length = 220,
	Height = { Drop = 20, EndGrade = 0 },
}

local Tests = {}

local Sim, World

-- The CLIENT's own modules, required on the server. The same trick `RoadTests` uses: the
-- model is pure Luau and does not care which side it runs on, so a test can drive the real
-- simulation down the real road with no client in the loop.
local function loadModel()
	if Sim then
		return
	end
	Sim = require(DriftFolder.Sim)
	World = require(DriftFolder.World)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function firstPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- Where the SERVER's own copy of a car is. It never moves between the places the server
-- puts it, which is exactly what this suite wants to read: every check here is about a
-- place the server chose.
local function carPivot(player: Player): Vector3?
	local folder = workspace:FindFirstChild("Cars")
	local car = folder and folder:FindFirstChild(`Car_{player.UserId}`)
	if not car or not car:IsA("Model") then
		return nil
	end
	return car:GetPivot().Position
end

-- The angle from a to b, signed the way the model's steering is. THE SIGN IS NOT
-- COSMETIC: with it the other way round the autopilot steers away from every corner, runs
-- wide, and this suite measured it spinning into the barrier at piece 2 and sitting there
-- for the remaining 294 seconds.
local function signedAngle(ax: number, az: number, bx: number, bz: number): number
	return math.atan2(bx * az - bz * ax, bx * ax + bz * az)
end

-- Press the button, with the two guards that bound a real press stood down. They are
-- measured on their own below; everywhere else they would only be measuring a wait.
local function press(want: boolean?, player: Player)
	RoadService:DebugClearLimits()
	return RoadService:DebugPress(want, player.UserId)
end

-- Splice the descending straight into the live piece set and push every flat piece out of
-- reach, so the road the next drive lays goes nowhere but down. Hands back the undo, and
-- every caller calls it -- `Config.Road.Pieces` is the real config table.
local function useDescent()
	local was = {}
	for name, spec in Config.Road.Pieces do
		was[name] = spec.minPieces
		spec.minPieces = math.huge
	end
	Config.Road.Pieces.Descent = DESCENT_PIECE
	Pieces.rebuild()
	return function()
		Config.Road.Pieces.Descent = nil
		for name, value in was do
			Config.Road.Pieces[name].minPieces = value
		end
		Pieces.rebuild()
	end
end

-- Where a position is on the road, or nil off it entirely.
local function pieceAt(position: Vector3?)
	if not position then
		return nil
	end
	return RoadService:PieceAt(position)
end

--------------------------------------------------------------------------------
-- The drive
--------------------------------------------------------------------------------

-- The real model, driven down the real road by an autopilot, with the window following
-- the car THROUGH THE PATH IT FOLLOWS IN PLAY: the drive tells `CarService` where the
-- server believes the car is, and `RoadService`'s own tick reads that and moves the
-- window. Nothing here advances the road by hand.
--
-- `opts.fallAt` drops the car off the road at that piece on purpose, through the real
-- respawn, and the drive carries on from wherever the server put it back.
function Tests:drive(opts)
	opts = opts or {}
	loadModel()
	local player = assert(opts.player or firstPlayer(), "RunTests:drive needs a player")
	local C = Config.Road
	local D = Config.Drift
	local wantPieces = opts.pieces or DRIVE_PIECES

	local gen = RoadService:DebugGenerator()
	local world = World.live({ workspace:FindFirstChild("Cars") })
	-- Facing the way the road goes: the pose the SERVER put the car at, not a guess at it.
	local spawnCF = opts.startCFrame or CFrame.new(assert(carPivot(player), "no car to drive"))
	local runner = Sim.newRunner(spawnCF)
	runner.state.velocity = spawnCF.LookVector * (opts.startSpeed or 60)
	runner.state.time = 10 -- past the throttle's ease-in

	local r = {
		reached = 1,
		steps = 0,
		seconds = 0,
		offRoadSteps = 0,
		airSteps = 0,
		backwardsSteps = 0,
		minSpeed = math.huge,
		maxSpeed = 0,
		driftSteps = 0,
		wallSteps = 0,
		stuckSeconds = 0,
		fell = false,
		-- What the MODEL thought, as opposed to the fall this drive stages on purpose:
		-- how many steps it asked to be respawned on, and how far down the drive got.
		-- On a descending road these two together are the whole of T-067.
		modelFellSteps = 0,
		lowestY = math.huge,
		-- And the same question asked the OLD way, which is the only way to show the bug
		-- and the fix in one run: how many of those steps were below the world Y the fall
		-- test used to be a comparison against.
		oldWouldFallSteps = 0,
		recovered = false,
		recoveredAt = 0,
		furthestBefore = 0,
		furthestAfter = 0,
		endedByFall = false,
	}
	local lastN = 1
	local stuckSteps = 0

	local function observe(s)
		r.steps += 1
		if s.fell then
			r.modelFellSteps += 1
		end
		if s.position.Y < OLD_RESPAWN_BELOW_Y then
			r.oldWouldFallSteps += 1
		end
		r.lowestY = math.min(r.lowestY, s.position.Y)
		local speed = math.sqrt(s.velocity.X ^ 2 + s.velocity.Z ^ 2)
		r.minSpeed = math.min(r.minSpeed, speed)
		r.maxSpeed = math.max(r.maxSpeed, speed)
		if s.airborne then
			r.airSteps += 1
		end
		if s.drifting then
			r.driftSteps += 1
		end
		if s.wallHit then
			r.wallSteps += 1
		end
		if speed < 5 then
			stuckSteps += 1
			r.stuckSeconds = math.max(r.stuckSeconds, stuckSteps * Config.Drift.FixedStep)
		else
			stuckSteps = 0
		end
		local n, _, lateral = gen:locate(s.position)
		if n then
			if n < lastN then
				r.backwardsSteps += 1
			end
			lastN = n
			r.reached = math.max(r.reached, n)
			if lateral > C.Width * 0.5 then
				r.offRoadSteps += 1
			end
		end
	end

	local input = { steer = 0, handbrake = false }
	local elapsed, sinceWindow = 0, 0
	local fallDone = false
	while elapsed < DRIVE_SECONDS and r.reached < wantPieces do
		local s = runner.state

		-- The deliberate fall: off the side of the road and straight down, which is what a
		-- player who ran out of talent on a corner looks like. The client would ask for a
		-- respawn; this asks the same way, through `CarService`, and reads back where the
		-- server put it.
		if opts.fallAt and not fallDone and r.reached >= opts.fallAt then
			fallDone = true
			r.fell = true
			r.furthestBefore = gen.furthestN
			-- Below the road the car is on, not below a world Y: the same 210 studs the
			-- old `RespawnBelowY - 60` was from a road at zero, and still 210 from a road
			-- 600 studs down (T-067).
			local off = s.position - Vector3.new(0, D.FallBelowSurface + 60, 0)
			CarService:DebugBelieve(player.UserId, off)
			task.wait(D.RespawnCooldown + 0.05)
			local back = CarService:DebugRespawn(player.UserId)
			r.furthestAfter = gen.furthestN
			r.endedByFall = not RoadService:InRun(player)
			if back then
				local p = RoadService:PieceAt(back)
				r.recovered = p ~= nil and p.onRoad
				r.recoveredAt = p and p.n or 0
				-- Carry on from where the server put it, exactly as the client does.
				local cf = CFrame.new(back)
				local spawn = RoadService:SafeStart(off)
				if spawn then
					cf = spawn
				end
				runner = Sim.newRunner(cf)
				runner.state.velocity = cf.LookVector * 40
				runner.state.time = 10
				lastN = r.recoveredAt
			end
			continue
		end

		local speed = math.sqrt(s.velocity.X ^ 2 + s.velocity.Z ^ 2)
		local heading = if speed > 1
			then Vector3.new(s.velocity.X / speed, 0, s.velocity.Z / speed)
			else Pieces.forward(s.yaw)
		local look = math.clamp(speed * LOOK_SECONDS, LOOK_MIN, LOOK_MAX)
		local target = gen:ahead(s.position, look)
		if target then
			local dx, dz = target.X - s.position.X, target.Z - s.position.Z
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 1e-3 then
				local alpha = signedAngle(heading.X, heading.Z, dx / len, dz / len)
				local yawWanted = speed * (2 * math.sin(alpha) / look)
				input.steer = math.clamp(yawWanted / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
			end
		end
		-- Shed speed it cannot carry into a corner it can already see. The handbrake is
		-- the only brake the model has (`features/drift-model.md`), and it is the one thing
		-- between this autopilot and the outside barrier of the first real corner.
		local _, curvature = gen:ahead(s.position, math.max(speed * BRAKE_LOOK, LOOK_MIN))
		input.handbrake = speed * speed * math.abs(curvature) > BRAKE_LIMIT

		Sim.advance(runner, 1 / DRIVE_FPS, input, world, observe)
		elapsed += 1 / DRIVE_FPS
		sinceWindow += 1 / DRIVE_FPS
		if sinceWindow >= 0.25 then
			sinceWindow = 0
			if opts.trace then
				r.trace = r.trace or {}
				local n, _, lat = gen:locate(runner.state.position)
				table.insert(
					r.trace,
					string.format(
						"%.2fs pos %.0f,%.0f,%.0f spd %.0f steer %.2f n=%s lat=%.1f wall=%s window %d..%d leader %s believed %s",
						elapsed,
						runner.state.position.X,
						runner.state.position.Y,
						runner.state.position.Z,
						math.sqrt(runner.state.velocity.X ^ 2 + runner.state.velocity.Z ^ 2),
						input.steer,
						tostring(n),
						lat or -1,
						tostring(runner.state.wallHit),
						gen.first,
						gen.last,
						tostring(RoadService:DebugState().leaderN),
						tostring(CarService:BelievedPosition(player.UserId))
					)
				)
			end
			-- THE REAL PATH: tell the server where the car is, and let the service's own
			-- tick move the window off that.
			CarService:DebugBelieve(player.UserId, runner.state.position)
			RoadService:DebugTick()
			-- Yield so the tag-added signals `Drift/World` listens on actually run: a piece
			-- built inside a tight loop would otherwise not be in the ground rays' include
			-- list and the car would fall through the road it is on.
			task.wait()
		end
	end

	r.seconds = elapsed
	r.endPosition = runner.state.position
	r.endPiece = select(1, gen:locate(runner.state.position))
	r.windowFirst, r.windowLast = gen.first, gen.last
	r.driftShare = r.driftSteps / math.max(r.steps, 1)
	world.destroy()
	return r
end

--------------------------------------------------------------------------------
-- The suite
--------------------------------------------------------------------------------

function Tests:run(opts)
	opts = opts or {}
	local checks = {}
	local function check(name: string, ok: boolean, detail: string)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end

	local C = Config.Road
	local D = Config.Drift

	local player = firstPlayer()
	if not player then
		check(
			"there is a player to move",
			false,
			"RunTests is about a car being put places and there is nobody in the place. Start a playtest and run it on the Server datamodel"
		)
		return { passed = false, checks = checks }
	end

	-- Leave the place as we found it.
	local startedInWorld = CarService:WorldAt(CarService:BelievedPosition(player.UserId) or carPivot(player) or Vector3.zero)
	RoadService:Stop()
	RoadService:DebugClearLimits()
	task.wait(D.RespawnCooldown + 0.05)

	----------------------------------------------------------------------------
	-- 1. The road is off until somebody presses the button
	----------------------------------------------------------------------------
	do
		local worlds = CarService:Worlds()
		check(
			"nothing builds a road by itself, and nothing spawns on one",
			not RoadService:HasRoad()
				and workspace:FindFirstChild("Road") == nil
				and D.StartWorld == "track"
				and worlds.road == nil,
			`HasRoad {tostring(RoadService:HasRoad())}, Workspace.Road {tostring(workspace:FindFirstChild("Road"))}, `
				.. `StartWorld '{D.StartWorld}', CarService worlds know the road: {tostring(worlds.road ~= nil)}`
		)
	end

	----------------------------------------------------------------------------
	-- 2. Pressing start builds a road and puts the car on piece 1
	----------------------------------------------------------------------------
	local cameFrom = CarService:WorldAt(CarService:BelievedPosition(player.UserId) or carPivot(player) or Vector3.zero)
	do
		local before = carPivot(player)
		local state = press(true, player)
		local after = carPivot(player)
		local at = pieceAt(after)
		local wantY = C.SurfaceY + D.RideHeight
		check(
			"pressing start builds a road and puts the car on piece 1",
			RoadService:HasRoad()
				and workspace:FindFirstChild("Road") ~= nil
				and state ~= nil
				and state.inRun == true
				and at ~= nil
				and at.n == 1
				and at.onRoad
				and after ~= nil
				and math.abs(after.Y - wantY) < 1e-3,
			string.format(
				"the car was at %s in the %s; after the press it is at %s -- piece %s, %.2f studs off the centre line of a %d-stud road, Y %.3f against %.3f. The server says inRun=%s, %d driving",
				before and string.format("(%.0f, %.0f, %.0f)", before.X, before.Y, before.Z) or "nowhere",
				tostring(cameFrom),
				after and string.format("(%.0f, %.0f, %.0f)", after.X, after.Y, after.Z) or "nowhere",
				at and tostring(at.n) or "off the road",
				at and at.lateral or -1,
				C.Width,
				after and after.Y or -1,
				wantY,
				tostring(state and state.inRun),
				state and state.players or -1
			)
		)
	end

	----------------------------------------------------------------------------
	-- 3. Nothing the road builds is physics
	----------------------------------------------------------------------------
	do
		local root = workspace:FindFirstChild("Road")
		local parts, unanchored, physics, tagged = 0, 0, 0, 0
		local offenders = {}
		if root then
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					if not d.Anchored then
						unanchored += 1
						table.insert(offenders, `{d.Name} unanchored`)
					end
					if CollectionService:HasTag(d, D.SurfaceTag) then
						tagged += 1
					end
				elseif d:IsA("BodyMover") or d:IsA("Constraint") or d:IsA("BaseScript") then
					physics += 1
					table.insert(offenders, `{d.Name} ({d.ClassName})`)
				end
			end
		end
		check(
			"a road built by the start button has no mover, no constraint and nothing unanchored",
			root ~= nil and parts > 0 and unanchored == 0 and physics == 0,
			`{parts} parts, {tagged} of them drivable ground; {unanchored} unanchored, {physics} movers, constraints or scripts. {table.concat(offenders, ", ")}`
		)
	end

	----------------------------------------------------------------------------
	-- 4. A fall puts the car back ON THE ROAD, and does not end the run
	----------------------------------------------------------------------------
	do
		local gen = RoadService:DebugGenerator()
		-- Drive the window up the road the way play does, then fall off it.
		-- One piece at a time, because each tick is what builds the next ten: walking
		-- straight to piece 18 would be asking for a piece that does not exist yet.
		local target = 18
		for n = 2, target do
			local piece = gen:piece(n)
			if not piece then
				break
			end
			CarService:DebugBelieve(player.UserId, Pieces.poseAt(piece, 0.5, C.SurfaceY + D.RideHeight).Position)
			RoadService:DebugTick()
		end
		local atPiece = gen:piece(target)
		local onRoad = Pieces.poseAt(atPiece, 0.6, C.SurfaceY + D.RideHeight).Position
		CarService:DebugBelieve(player.UserId, onRoad)
		RoadService:DebugTick()
		local furthestBefore = gen.furthestN
		local roadPartsBefore = #workspace.Road:GetChildren()

		-- Straight down through the world, far enough below the road it fell off that
		-- `FallBelowSurface` catches it. 230 studs, which is what `RespawnBelowY - 80`
		-- came to when every road was at Y = 0 (T-067).
		local below = onRoad - Vector3.new(0, D.FallBelowSurface + 80, 0)
		CarService:DebugBelieve(player.UserId, below)
		task.wait(D.RespawnCooldown + 0.05)
		local back = CarService:DebugRespawn(player.UserId)
		local at = pieceAt(back)
		local furthestAfter = gen.furthestN
		check(
			"a fall straight down puts the car back on the road, and the run does not end",
			back ~= nil
				and at ~= nil
				and at.onRoad
				and at.n >= target - C.BehindPieces
				and RoadService:InRun(player)
				and RoadService:HasRoad()
				and furthestAfter >= furthestBefore,
			string.format(
				"fell from piece %d at Y %.0f, put back on piece %s (%.2f studs off the centre line, Y %.2f); still in the run: %s; the road is still up with %d children (was %d); furthest N %d -> %d",
				target,
				below.Y,
				at and tostring(at.n) or "NOT ON THE ROAD",
				at and at.lateral or -1,
				back and back.Y or -1,
				tostring(RoadService:InRun(player)),
				workspace:FindFirstChild("Road") and #workspace.Road:GetChildren() or 0,
				roadPartsBefore,
				furthestBefore,
				furthestAfter
			)
		)

		-- And off the SIDE and away, far enough that the road cannot locate the position at
		-- all. This is the path the roster answers rather than the position.
		local sideways = Pieces.poseAt(atPiece, 0.6, C.SurfaceY)
		local away = sideways.Position + sideways.RightVector * 4000 + Vector3.new(0, -400, 0)
		CarService:DebugBelieve(player.UserId, away)
		local locatedOut = RoadService:PieceAt(away)
		task.wait(D.RespawnCooldown + 0.05)
		local back2 = CarService:DebugRespawn(player.UserId)
		local at2 = pieceAt(back2)
		check(
			"a car that left the road altogether still comes back on to it",
			locatedOut == nil and back2 ~= nil and at2 ~= nil and at2.onRoad and RoadService:InRun(player),
			string.format(
				"4000 studs off the side and 400 down: the road locates that position as %s, and the respawn put the car on piece %s. Still in the run: %s. The roster answered, not the position",
				tostring(locatedOut),
				at2 and tostring(at2.n) or "NOT ON THE ROAD",
				tostring(RoadService:InRun(player))
			)
		)
	end

	----------------------------------------------------------------------------
	-- 5. A second driver joins THE SAME road, and cannot be stranded
	----------------------------------------------------------------------------
	do
		local gen = RoadService:DebugGenerator()
		local seedBefore, firstBefore, lastBefore = gen.seed, gen.first, gen.last
		local joinedAt = RoadService:DebugJoin(STAND_IN)
		local genAfter = RoadService:DebugGenerator()
		local at = pieceAt(joinedAt and joinedAt.Position)
		local barrierPiece = math.max(gen.first, (RoadService:DebugState().leaderN or 1) - C.BarrierBehind)
		check(
			"a second driver joins the same road, ahead of the closing barrier",
			joinedAt ~= nil
				and genAfter == gen
				and genAfter.seed == seedBefore
				and genAfter.first == firstBefore
				and genAfter.last == lastBefore
				and at ~= nil
				and at.onRoad
				and at.n > barrierPiece
				and RoadService:RunnerCount() == 2,
			string.format(
				"the road is the same object, seed %s, window %d..%d, unchanged by the join; the joiner lands on piece %s with the closing barrier at piece %d; %d on the roster. NOT PROVED HERE: a second CAR moving, which Studio gives no second player to move",
				tostring(seedBefore),
				firstBefore,
				lastBefore,
				at and tostring(at.n) or "off the road",
				barrierPiece,
				RoadService:RunnerCount()
			)
		)

		-- The real player ends their run while the stand-in is still on the road.
		local roadBefore = workspace:FindFirstChild("Road")
		local childrenBefore = roadBefore and #roadBefore:GetChildren() or 0
		task.wait(D.RespawnCooldown + 0.05)
		press(false, player)
		local roadAfter = workspace:FindFirstChild("Road")
		local world = CarService:WorldAt(carPivot(player) or Vector3.zero)
		check(
			"one player ending a run cannot strand another",
			roadAfter ~= nil
				and roadAfter == roadBefore
				and #roadAfter:GetChildren() == childrenBefore
				and RoadService:HasRoad()
				and RoadService:RunnerCount() == 1
				and not RoadService:InRun(player)
				and world ~= "road",
			string.format(
				"the player left and went back to the %s; the road is the same folder with %d children (was %d), still running, %d driver left on it",
				tostring(world),
				roadAfter and #roadAfter:GetChildren() or 0,
				childrenBefore,
				RoadService:RunnerCount()
			)
		)

		-- And when the last of them goes, the road goes.
		RoadService:DebugLeave(STAND_IN)
		check(
			"the last driver leaving takes the road down",
			not RoadService:HasRoad() and workspace:FindFirstChild("Road") == nil and RoadService:RunnerCount() == 0,
			`after the last driver left: HasRoad {tostring(RoadService:HasRoad())}, Workspace.Road {tostring(workspace:FindFirstChild("Road"))}, {RoadService:RunnerCount()} on the roster`
		)
	end

	----------------------------------------------------------------------------
	-- 6. Pressing it again ends the run and puts the car back where it came from
	----------------------------------------------------------------------------
	do
		task.wait(D.RespawnCooldown + 0.05)
		local from = CarService:WorldAt(CarService:BelievedPosition(player.UserId) or carPivot(player) or Vector3.zero)
		press(true, player)
		local onRoad = CarService:WorldAt(carPivot(player) or Vector3.zero)
		task.wait(D.RespawnCooldown + 0.05)
		local state = press(false, player)
		local back = carPivot(player)
		local world = CarService:WorldAt(back or Vector3.zero)
		local home = CarService:SpawnCFrameIn(from)
		check(
			"the same button ends the run, destroys the road and puts the car back where it started",
			onRoad == "road"
				and workspace:FindFirstChild("Road") == nil
				and not RoadService:HasRoad()
				and state ~= nil
				and state.inRun == false
				and world == from
				and back ~= nil
				and (back - home.Position).Magnitude < 1,
			string.format(
				"started in the %s, drove in the %s, ended in the %s, %.2f studs from that world's spawn; Workspace.Road is %s and the server says inRun=%s",
				tostring(from),
				tostring(onRoad),
				tostring(world),
				back and (back - home.Position).Magnitude or -1,
				tostring(workspace:FindFirstChild("Road")),
				tostring(state and state.inRun)
			)
		)
	end

	----------------------------------------------------------------------------
	-- 7. The remote refuses a forged request
	----------------------------------------------------------------------------
	do
		RoadService:Stop()
		RoadService:DebugClearLimits()
		local before = RoadService:DebugState()
		local refusedBefore = before.asksRefused

		-- Nothing but a boolean or nil is read, and none of these may start a run, name a
		-- place, name a seed or name a piece.
		local forgeries = {
			CFrame.new(0, 500, 0),
			Vector3.new(1, 2, 3),
			1234, -- a seed
			"true",
			{ seed = 1234, n = 9999, spawn = CFrame.new(0, 0, 0) },
			{ true },
			workspace,
			Enum.KeyCode.A,
			0 / 0,
		}
		local errored = nil
		for _, junk in forgeries do
			RoadService:DebugClearLimits()
			local ok, err = pcall(function()
				RoadService:DebugPress(junk, player.UserId)
			end)
			if not ok then
				errored = `{typeof(junk)}: {tostring(err)}`
			end
		end
		local after = RoadService:DebugState()
		check(
			"a forged request starts nothing and is counted, whatever it is",
			errored == nil
				and not RoadService:HasRoad()
				and workspace:FindFirstChild("Road") == nil
				and not RoadService:InRun(player)
				and after.asksRefused - refusedBefore == #forgeries,
			`{#forgeries} forgeries -- a CFrame, a Vector3, a seed, a string, a table naming a seed, a piece and a spawn, a list, an Instance, an Enum and a NaN -- `
				.. `started {if RoadService:HasRoad() then "A ROAD" else "nothing"}, were all refused and counted ({after.asksRefused - refusedBefore} of {#forgeries}), and raised {errored or "no error"}`
		)

		-- The one that matters most: a client that sends a position ALONGSIDE a real press
		-- does not get to choose where its car goes.
		RoadService:DebugClearLimits()
		task.wait(D.RespawnCooldown + 0.05)
		local forged = CFrame.new(12345, 678, -91011)
		RoadService:_onRun(player, true, forged, 999999, { n = 500 })
		local landed = carPivot(player)
		local want = RoadService:JoinCFrame()
		local at = pieceAt(landed)
		check(
			"a position, a seed and a progress sent with a real press are all ignored",
			RoadService:HasRoad()
				and landed ~= nil
				and want ~= nil
				and (landed - want.Position).Magnitude < 1
				and (landed - forged.Position).Magnitude > 1000
				and at ~= nil
				and at.n == 1,
			string.format(
				"pressed start with a CFrame, a seed and a progress table after it; the car went to the road's own piece 1 (%.2f studs from where the server computed it) and %.0f studs from the place the 'client' named",
				landed and want and (landed - want.Position).Magnitude or -1,
				landed and (landed - forged.Position).Magnitude or -1
			)
		)
	end

	----------------------------------------------------------------------------
	-- 8. The two guards on the button
	----------------------------------------------------------------------------
	do
		-- The cooldown. A run is going from the check above.
		RoadService:DebugClearLimits()
		local wasInRun = RoadService:InRun(player)
		local refusedBefore = RoadService:DebugState().asksRefused
		RoadService:DebugPress(false, player.UserId) -- lands: ends the run
		local endedOk = not RoadService:InRun(player)
		RoadService:DebugPress(true, player.UserId) -- inside the cooldown: refused
		local heldOff = not RoadService:InRun(player)
		check(
			`a second press inside the {D.RespawnCooldown}s cooldown is refused`,
			wasInRun and endedOk and heldOff and RoadService:DebugState().asksRefused > refusedBefore,
			`the run ended ({tostring(endedOk)}) and the press straight after it did not start one ({tostring(heldOff)}); refusals {refusedBefore} -> {RoadService:DebugState().asksRefused}`
		)

		-- The rate limit. Questions count against it too, which is the point: a flood is a
		-- flood whether or not it asks for anything.
		RoadService:DebugClearLimits()
		local limit = D.CarSwitchRateLimit
		local refused = RoadService:DebugState().asksRefused
		for _ = 1, limit + 6 do
			RoadService:DebugPress(nil, player.UserId)
		end
		local nowRefused = RoadService:DebugState().asksRefused
		check(
			`no more than {limit} asks a second per UserId get through`,
			nowRefused - refused == 6,
			`{limit + 6} asks in one window: {nowRefused - refused} refused, {limit} taken`
		)
		RoadService:Stop()
		RoadService:DebugClearLimits()
	end

	----------------------------------------------------------------------------
	-- 9. End to end: press start, drive it, fall off, recover, finish, come back
	----------------------------------------------------------------------------
	local driveDetail = ""
	if opts.skipDrive ~= true then
		task.wait(D.RespawnCooldown + 0.05)
		local from = CarService:WorldAt(CarService:BelievedPosition(player.UserId) or carPivot(player) or Vector3.zero)
		-- The road is laid with a PINNED seed and the button is pressed on to it -- which is
		-- the join path, the same `StartRun` a second driver takes -- so that the drive below
		-- is the same road every time it is run and its numbers mean something. That the
		-- button also MAKES a road, with a seed off the server's clock, is check 2's.
		RoadService:Generate(DRIVE_SEED)
		press(true, player)
		local startCFrame = RoadService:SpawnCFrame()
		local r = Tests:drive({
			player = player,
			pieces = DRIVE_PIECES,
			fallAt = math.floor(DRIVE_PIECES / 2),
			startCFrame = startCFrame,
		})
		local stillUp = RoadService:HasRoad()
		local stillIn = RoadService:InRun(player)
		task.wait(D.RespawnCooldown + 0.05)
		press(false, player)
		local back = carPivot(player)
		local world = CarService:WorldAt(back or Vector3.zero)

		driveDetail = string.format(
			"%d pieces in %.0f s of simulation (%d steps), %.0f..%.0f studs/s, drifting %.0f%%; %d steps off the road, %d airborne, %d backwards. Fell off at piece %d on purpose and the server put it back on piece %d (%s); the run survived it (%s) and furthest N went %d -> %d. Ended in the %s",
			r.reached,
			r.seconds,
			r.steps,
			r.minSpeed,
			r.maxSpeed,
			100 * r.driftShare,
			r.offRoadSteps,
			r.airSteps,
			r.backwardsSteps,
			math.floor(DRIVE_PIECES / 2),
			r.recoveredAt,
			tostring(r.recovered),
			tostring(not r.endedByFall),
			r.furthestBefore,
			r.furthestAfter,
			tostring(world)
		)
		check(
			`a run is started, driven {DRIVE_PIECES} pieces with a fall in it, and ended`,
			r.reached >= DRIVE_PIECES
				and r.fell
				and r.recovered
				and not r.endedByFall
				and r.furthestAfter >= r.furthestBefore
				and stillUp
				and stillIn
				and workspace:FindFirstChild("Road") == nil
				and world == from,
			driveDetail
		)
		check(
			"the drive never left the road, never went backwards, and never asked to be respawned",
			r.offRoadSteps == 0 and r.airSteps == 0 and r.backwardsSteps == 0 and r.modelFellSteps == 0,
			driveDetail .. string.format("; the model asked to be respawned on %d of %d steps", r.modelFellSteps, r.steps)
		)
	end

	----------------------------------------------------------------------------
	-- 10. A DESCENDING road: a fall is measured from the ground, not from Y = 0
	----------------------------------------------------------------------------
	-- The case the absolute test got wrong (`features/road-elevation.md`, "The fall test
	-- stops being absolute"). Two halves, and they pull in opposite directions:
	--
	--   * 600 studs down a hill, with road under the car the whole way, NOTHING is a fall;
	--   * one car width to the side of that same road, where there is no piece and no
	--     ground at all, a fall is still a fall and still comes back -- which is what the
	--     old test caught by accident and the easy thing to lose.
	--
	-- The second half is staged by moving the model sideways rather than by steering off,
	-- because there is a barrier in the way: a car cannot be driven off the side of this
	-- road at all. What is being measured is the model's own `fell`, from the ground it
	-- last had under it, so where it was put matters and how it got there does not.
	if opts.skipDrive ~= true and opts.skipDescent ~= true then
		loadModel()
		local restore = useDescent()
		local ok, err = pcall(function()
			RoadService:Stop()
			RoadService:DebugClearLimits()
			task.wait(D.RespawnCooldown + 0.05)
			RoadService:Generate(DESCENT_SEED)
			press(true, player)
			local r = Tests:drive({
				player = player,
				pieces = DESCENT_PIECES,
				startCFrame = RoadService:SpawnCFrame(),
			})
			local gen = RoadService:DebugGenerator()
			check(
				"a car driven to the bottom of a descending road never asks to be respawned",
				r.modelFellSteps == 0 and r.lowestY < -300 and r.reached >= 15 and r.oldWouldFallSteps > 0,
				string.format(
					"%d pieces of descent in %.0f s (%d steps), down to Y %.0f -- %.0f studs below the old RespawnBelowY of %d. THE OLD TEST WOULD HAVE CALLED %d OF THOSE %d STEPS A FALL; this one calls %d of them a fall. %.0f..%.0f studs/s, %d steps off the road, %d airborne",
					r.reached,
					r.seconds,
					r.steps,
					r.lowestY,
					OLD_RESPAWN_BELOW_Y - r.lowestY,
					OLD_RESPAWN_BELOW_Y,
					r.oldWouldFallSteps,
					r.steps,
					r.modelFellSteps,
					r.minSpeed,
					r.maxSpeed,
					r.offRoadSteps,
					r.airSteps
				)
			)

			-- ...and off the side of it, at that depth.
			local piece = assert(gen:piece(r.reached), "no piece to fall off")
			local pose = Pieces.poseAt(piece, 0.5, C.SurfaceY + D.RideHeight)
			local roadY = select(1, Pieces.surfaceAt(piece, 0.5))
			local world = World.live({ workspace:FindFirstChild("Cars") })
			local runner = Sim.newRunner(pose)
			runner.state.time = 10
			local input = { steer = 0, handbrake = false }
			-- One step ON the road, so the ground rays -- and nothing else -- say where the
			-- fall is measured from.
			Sim.advance(runner, 1 / DRIVE_FPS, input, world)
			local measuredFrom = runner.state.fallFrom
			local onRoadFell = runner.state.fell
			-- Over the void beside it, standing still: only gravity from here.
			runner.state.position = pose.Position + pose.RightVector * (C.Width * 0.5 + 60)
			runner.state.velocity = Vector3.zero
			local seconds = 0
			while seconds < 20 and not runner.state.fell do
				Sim.advance(runner, 1 / DRIVE_FPS, input, world)
				seconds += 1 / DRIVE_FPS
			end
			local fell = runner.state.fell
			local droppedBy = measuredFrom - runner.state.position.Y
			world.destroy()

			-- And the server puts it back, on the road, at the road's height.
			local furthestBefore = gen.furthestN
			CarService:DebugBelieve(player.UserId, runner.state.position)
			task.wait(D.RespawnCooldown + 0.05)
			local back = CarService:DebugRespawn(player.UserId)
			local at = pieceAt(back)
			local furthestAfter = gen.furthestN
			local backPiece = at and gen:piece(at.n)
			local backSurface = if backPiece then (select(1, Pieces.surfaceAt(backPiece, at.t))) else 0
			local offSurface = if back then math.abs(back.Y - (backSurface + D.RideHeight)) else math.huge
			check(
				"a fall off the side of a road 600 studs down is still a fall, and comes back on the road at that height",
				fell
					and not onRoadFell
					and math.abs(droppedBy - D.FallBelowSurface) < 12
					and back ~= nil
					and at ~= nil
					and at.onRoad
					and offSurface < 2
					and RoadService:InRun(player)
					and furthestAfter >= furthestBefore,
				string.format(
					"on the road at piece %d (Y %.0f) nothing was falling; beside it the car fell %.0f studs from the %.0f it last had ground at -- FallBelowSurface is %d -- in %.1f s, and reported fell=%s. The server put it back on piece %s at Y %.1f, %.2f studs above a road whose surface there is Y %.1f (%.2f off ride height); still in the run: %s; furthest N %d -> %d",
					r.reached,
					roadY,
					droppedBy,
					measuredFrom,
					D.FallBelowSurface,
					seconds,
					tostring(fell),
					at and tostring(at.n) or "NOT ON THE ROAD",
					back and back.Y or -1,
					back and (back.Y - backSurface) or -1,
					backSurface,
					offSurface,
					tostring(RoadService:InRun(player)),
					furthestBefore,
					furthestAfter
				)
			)
			press(false, player)
			RoadService:Stop()
		end)
		restore()
		if not ok then
			error(err, 0)
		end
	end

	----------------------------------------------------------------------------
	-- Put the place back
	----------------------------------------------------------------------------
	RoadService:Stop()
	RoadService:DebugClearLimits()
	task.wait(D.RespawnCooldown + 0.05)
	CarService:Place(player, CarService:SpawnCFrameIn(startedInWorld))

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
