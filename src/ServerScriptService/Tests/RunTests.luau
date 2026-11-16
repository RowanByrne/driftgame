--!nonstrict
-- RunTests: the run -- the start button, where you spawn, what a fall does, and getting
-- back to the other two worlds (docs/game/features/endless-run.md "Testing", T-044 step 3),
-- ON THE SPLINE ROAD every run lays, cut into the mountain (T-250, features/legacy-removal.md).
--
-- Run it from the server debug bridge, IN A PLAYTEST:
--   game.ServerStorage.DebugBridge:Invoke("DebugRunTests", "run")
-- It takes about a minute, so call it from a task and read the result afterwards.
--
-- IT NEEDS A PLAYER, and that is not an accident of the harness: every question this suite
-- asks is about a car being moved, and `CarService` will not move a car for somebody who
-- is not there. With no player in the place this returns one failing check saying so
-- rather than passing vacuously.
--
-- The second driver is `RoadService:DebugJoin`, a bare userId on the roster with no car
-- behind it, because Studio gives a test exactly one player. What that cannot prove --
-- somebody else's CAR moving -- is called out in the check's own detail rather than
-- quietly counted as proved.
--
-- THE ROAD IS THE SPLINE ROAD (`Road/SplineSequence`): the server builds no part of it, and
-- a "piece" here is one section of the curve, a span of arc length `s0..s1`. Heights and
-- poses come from the live generator's own curve (`RoadService:DebugGenerator().spline`),
-- never from a part, and the closing barrier is a NUMBER -- an arc length, `closingS` in
-- `DebugState`, sent to the runners as `{ kind = "closing", s }`. "Ahead of the barrier" is
-- measured as a position's own `s` against it.
--
-- DETERMINISTIC: every road whose shape a number depends on is laid with a pinned seed
-- (`ROAD_SEED`). The two presses that start a FRESH road through the real button (checks 2
-- and 7) get the server's clock seed, because that is what the button does and check 2 is
-- what proves it; nothing they assert depends on the road's shape.
--
-- WHAT WENT WITH THE PIECE ROAD (T-249), and why:
--   * "a road built by the start button has no mover, no constraint and nothing unanchored"
--     -- it counted the parts in `Workspace.Road`. The spline road has no parts on the
--     server at all, so in its place: a run adds no part to the server's workspace.
--   * every `Workspace.Road` folder check (it exists while a run is up, it is the SAME
--     folder with the same children when one of two drivers leaves, it is gone when the
--     road comes down) -- there is no folder. The same questions are asked of the road
--     itself: `HasRoad`, the generator being the same object with the same seed, window and
--     closing barrier, and `DebugGenerator()` being nil once it is down.
--   * the closing barrier as a piece number (`leaderN - BarrierBehind`) -- it is an arc
--     length now, read from `DebugState().closingS`.
--   * THE DESCENT FIXTURE: a straight that dropped 20 studs, spliced into
--     `Config.Road.Pieces` so the piece road would go downhill at all. Every spline road is
--     cut into the mountain and descends (`Config.Spline.Mountain.Mode = "descent"`), so the
--     ordinary drive on the pinned seed IS the descending road: the two descent checks are
--     now asked of it, with no fixture.
--   * the `onPieces` wrapper that switched each run to the piece road and back -- there is
--     only one road.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "RunTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local CarService = require(ServerScriptService.Services.CarService)
local RoadService = require(ServerScriptService.Services.RoadService)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")

local STAND_IN = -4044 -- the second driver's userId. Negative, so it can never be a real one
local DRIVE_PIECES = 30
local DRIVE_SECONDS = 300
local DRIVE_FPS = 60
local LOOK_SECONDS = 0.9 -- the autopilot's lookahead, and a property of the DRIVER, not the
-- road. The same autopilot `SplineWorldTests` drives with (copied, not shared)
local LOOK_MIN, LOOK_MAX = 30, 120
local BRAKE_LOOK = 1.6 -- seconds ahead the autopilot reads the corner it is about to meet
local BRAKE_LIMIT = 65 -- studs/s^2 of cornering it will ask of the car before it uses the
-- handbrake. NOT OPTIONAL: with the brake left out the car entered the
-- first real corner of the old piece road at 113 studs/s, ran wide and
-- wedged against the barrier for the rest of the drive
local ROAD_SEED = 8080 -- the road the fall, the join and the drive are measured on. PINNED,
-- and only for those: the button's own seed is the server's clock and
-- check 2 is what proves it. A measurement that quoted a different road
-- every time would not be a measurement
local OLD_RESPAWN_BELOW_Y = -150 -- what `Config.Drift.RespawnBelowY` was before T-067, and
-- it is in this suite for one reason: so the drive can say how many of
-- its own steps the old absolute test would have called a fall
local FALL_PIECE = 18 -- how far up the road the straight-down fall is staged

local Tests = {}

local Sim, World, SplineWorld

-- The CLIENT's own modules, required on the server: the model is pure Luau and does not
-- care which side it runs on, so a test can drive the real simulation down the real road's
-- maths (`Drift/SplineWorld`, as the client does on a run) with no client in the loop.
local function loadModel()
	if Sim then
		return
	end
	Sim = require(DriftFolder.Sim)
	World = require(DriftFolder.World)
	SplineWorld = require(DriftFolder.SplineWorld)
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
-- COSMETIC: with it the other way round the autopilot steers away from every corner.
local function signedAngle(ax: number, az: number, bx: number, bz: number): number
	return math.atan2(bx * az - bz * ax, bx * ax + bz * az)
end

-- Press the button, with the two guards that bound a real press stood down. They are
-- measured on their own below; everywhere else they would only be measuring a wait.
local function press(want: boolean?, player: Player)
	RoadService:DebugClearLimits()
	return RoadService:DebugPress(want, player.UserId)
end

-- Where a position is on the road, or nil off it entirely.
local function pieceAt(position: Vector3?)
	if not position then
		return nil
	end
	return RoadService:PieceAt(position)
end

-- How far the live road's own projection reaches: the road, its widest runoff and a margin,
-- the same reach `SplineSequence.locate` and `Drift/SplineWorld` use.
local function reach(): number
	return Config.Road.Width * 0.5 + Config.Spline.Terrain.RunoffMax + 30
end

-- Where a position is ALONG the live road (its arc length `s`) and across it (`d`), from
-- the curve itself. nil off the road.
local function along(position: Vector3?): (number?, number?)
	local gen = RoadService:DebugGenerator()
	if not gen or not position then
		return nil, nil
	end
	return gen.spline:project(position.X, position.Z, reach())
end

-- The road's surface height under a position, from the curve. nil off the road.
local function surfaceUnder(position: Vector3?): number?
	local gen = RoadService:DebugGenerator()
	local s, d = along(position)
	if not gen or not s then
		return nil
	end
	local _, y = gen.spline:surfaceXYZ(s, d)
	return y
end

-- A pose on piece `n`'s centre line, `share` of the way along it, at ride height.
local function poseOnPiece(n: number, share: number): CFrame?
	local gen = RoadService:DebugGenerator()
	local piece = gen and gen:piece(n)
	if not piece then
		return nil
	end
	return gen:poseOn(piece, piece.length * share, Config.Drift.RideHeight)
end

local function closingS(): number?
	return RoadService:DebugState().closingS
end

local function fmtV(v: Vector3?): string
	return if v then string.format("(%.0f, %.1f, %.0f)", v.X, v.Y, v.Z) else "nowhere"
end

-- Every part in the server's workspace that is not a car or a character: what a run would
-- have to add to if it built anything.
local function worldParts(): number
	local skip = {}
	local cars = workspace:FindFirstChild("Cars")
	if cars then
		table.insert(skip, cars)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local count = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			local skipped = false
			for _, root in skip do
				if d:IsDescendantOf(root) then
					skipped = true
					break
				end
			end
			if not skipped then
				count += 1
			end
		end
	end
	return count
end

--------------------------------------------------------------------------------
-- The drive
--------------------------------------------------------------------------------

-- The real model, driven down the real road's maths by an autopilot, with the window
-- following the car THROUGH THE PATH IT FOLLOWS IN PLAY: the drive tells `CarService` where
-- the server believes the car is, and `RoadService`'s own tick reads that and moves the
-- window and the closing barrier. Nothing here advances the road by hand. The car's world is
-- the one the client builds on a run: `SplineWorld` on the live curve, wrapped round the
-- live world, with the closing barrier the server last sent.
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

	local gen = assert(RoadService:DebugGenerator(), "RunTests:drive needs a road: press start first")
	local spline = gen.spline
	local live = World.live({ workspace:FindFirstChild("Cars") })
	local world = SplineWorld.new(spline, live)
	world.setClosing(closingS())
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
		worstLateral = 0,
		fell = false,
		-- What the MODEL thought, as opposed to the fall this drive stages on purpose: how
		-- many steps it asked to be respawned on, and how far down the mountain it got.
		modelFellSteps = 0,
		startY = spawnCF.Position.Y,
		lowestY = math.huge,
		-- And the same question asked the OLD way: how many of those steps were below the
		-- world Y the fall test used to be a comparison against.
		oldWouldFallSteps = 0,
		recovered = false,
		recoveredAt = 0,
		recoveredAhead = false,
		recoveredS = 0,
		closingAtFall = nil,
		furthestBefore = 0,
		furthestAfter = 0,
		endedByFall = false,
		closingMoves = 0,
	}
	local lastN = 1
	local lastS = select(1, spline:project(spawnCF.Position.X, spawnCF.Position.Z, reach())) or 0
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
			r.stuckSeconds = math.max(r.stuckSeconds, stuckSteps * D.FixedStep)
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
			r.worstLateral = math.max(r.worstLateral, lateral)
			if lateral > C.Width * 0.5 then
				r.offRoadSteps += 1
			end
		else
			r.offRoadSteps += 1
		end
	end

	local function locateS(pos: Vector3): number?
		local s = spline:projectFrom(pos.X, pos.Z, lastS)
		if not s then
			s = spline:project(pos.X, pos.Z, reach())
		end
		return s
	end

	local input = { steer = 0, handbrake = false }
	local elapsed, sinceWindow = 0, 0
	local fallDone = false
	local lastClosing = closingS()
	while elapsed < DRIVE_SECONDS and r.reached < wantPieces do
		local s = runner.state

		-- The deliberate fall: straight down off the road, which is what a player who ran out
		-- of talent on a corner looks like by the time they ask. The client would ask for a
		-- respawn; this asks the same way, through `CarService`, and reads back where the
		-- server put it.
		if opts.fallAt and not fallDone and r.reached >= opts.fallAt then
			fallDone = true
			r.fell = true
			r.furthestBefore = gen.furthestN
			r.closingAtFall = closingS()
			-- Below the road the car is on, not below a world Y (T-067).
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
				local sBack = along(back)
				r.recoveredS = sBack or -1
				r.recoveredAhead = sBack ~= nil and r.closingAtFall ~= nil and sBack > r.closingAtFall
				-- Carry on from where the server put it, exactly as the client does.
				local cf = RoadService:SafeStart(off) or CFrame.new(back)
				runner = Sim.newRunner(cf)
				runner.state.velocity = cf.LookVector * 40
				runner.state.time = 10
				lastN = r.recoveredAt
				lastS = sBack or lastS
				world.hint = nil
			end
			continue
		end

		local speed = math.sqrt(s.velocity.X ^ 2 + s.velocity.Z ^ 2)
		local heading = if speed > 1
			then Vector3.new(s.velocity.X / speed, 0, s.velocity.Z / speed)
			else Vector3.new(-math.sin(s.yaw), 0, -math.cos(s.yaw))
		local look = math.clamp(speed * LOOK_SECONDS, LOOK_MIN, LOOK_MAX)
		local here = locateS(s.position) or lastS
		lastS = here
		local tx, tz = spline:planAt(math.min(here + look, spline.length))
		local dx, dz = tx - s.position.X, tz - s.position.Z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 1e-3 then
			local alpha = signedAngle(heading.X, heading.Z, dx / len, dz / len)
			local yawWanted = speed * (2 * math.sin(alpha) / look)
			input.steer = math.clamp(yawWanted / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
		end
		-- Shed speed it cannot carry into a corner it can already see: the sharpest curvature
		-- within the braking look. The handbrake is the only brake the model has.
		local kMax = 0
		local ahead = math.max(speed * BRAKE_LOOK, LOOK_MIN)
		for u = 0, ahead, 8 do
			kMax = math.max(kMax, math.abs(spline:curvatureAt(math.min(here + u, spline.length))))
		end
		input.handbrake = speed * speed * kMax > BRAKE_LIMIT

		Sim.advance(runner, 1 / DRIVE_FPS, input, world, observe)
		elapsed += 1 / DRIVE_FPS
		sinceWindow += 1 / DRIVE_FPS
		if sinceWindow >= 0.25 then
			sinceWindow = 0
			-- THE REAL PATH: tell the server where the car is, and let the service's own
			-- tick move the window and the closing barrier off that.
			CarService:DebugBelieve(player.UserId, runner.state.position)
			local state = RoadService:DebugTick()
			-- and the barrier to the car's world, as `RoadSpline` tells the client
			if state.closingS ~= lastClosing then
				lastClosing = state.closingS
				r.closingMoves += 1
				world.setClosing(state.closingS)
			end
			if opts.trace then
				r.trace = r.trace or {}
				local n, _, lat = gen:locate(runner.state.position)
				table.insert(
					r.trace,
					string.format(
						"%.2fs pos %.0f,%.0f,%.0f spd %.0f steer %.2f n=%s lat=%.1f wall=%s window %d..%d leader %s closing %s",
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
						tostring(state.leaderN),
						tostring(state.closingS)
					)
				)
			end
			task.wait()
		end
	end

	r.seconds = elapsed
	r.endPosition = runner.state.position
	r.endPiece = select(1, gen:locate(runner.state.position))
	r.windowFirst, r.windowLast = gen.first, gen.last
	r.driftShare = r.driftSteps / math.max(r.steps, 1)
	world.destroy()
	live.destroy()
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

	local ok, err = pcall(function()
		------------------------------------------------------------------------
		-- 1. The road is off until somebody presses the button
		------------------------------------------------------------------------
		do
			local worlds = CarService:Worlds()
			check(
				"nothing builds a road by itself, and nothing spawns on one",
				not RoadService:HasRoad()
					and RoadService:DebugGenerator() == nil
					and D.StartWorld == "track"
					and worlds.road == nil,
				`HasRoad {tostring(RoadService:HasRoad())}, generator {tostring(RoadService:DebugGenerator() ~= nil)}, `
					.. `StartWorld '{D.StartWorld}', CarService worlds know the road: {tostring(worlds.road ~= nil)}`
			)
		end

		------------------------------------------------------------------------
		-- 2. Pressing start lays a road and puts the car on piece 1, ON the curve
		-- 3. ...and builds no part on the server
		------------------------------------------------------------------------
		do
			local cameFrom = CarService:WorldAt(CarService:BelievedPosition(player.UserId) or carPivot(player) or Vector3.zero)
			local before = carPivot(player)
			local partsBefore = worldParts()
			local state = press(true, player)
			local partsAfter = worldParts()
			local after = carPivot(player)
			local at = pieceAt(after)
			local gen = RoadService:DebugGenerator()
			local s, d = along(after)
			local surface = surfaceUnder(after)
			local wantY = surface and surface + D.RideHeight
			local piece1 = gen and gen:piece(1)
			check(
				"pressing start lays a road and puts the car on piece 1, on the curve at ride height",
				RoadService:HasRoad()
					and gen ~= nil
					and state ~= nil
					and state.inRun == true
					and at ~= nil
					and at.n == 1
					and at.onRoad
					and after ~= nil
					and s ~= nil
					and piece1 ~= nil
					and s >= piece1.s0
					and s <= piece1.s1
					and math.abs(d) < 1e-3
					and math.abs(after.Y - wantY) < 1e-3,
				string.format(
					"the car was at %s in the %s; after the press it is at %s -- piece %s, s %.2f, %.3f studs off the centre line of a %d-stud road, Y %.3f against the curve's %.3f + ride height %.2f. Seed %s (the server's clock). The server says inRun=%s, %d driving",
					fmtV(before),
					tostring(cameFrom),
					fmtV(after),
					at and tostring(at.n) or "off the road",
					s or -1,
					d or -1,
					C.Width,
					after and after.Y or -1,
					surface or -1,
					D.RideHeight,
					tostring(gen and gen.seed),
					tostring(state and state.inRun),
					state and state.players or -1
				)
			)
			check(
				"a run builds no part on the server: the road is the curve's maths, drawn by the clients",
				partsAfter == partsBefore and workspace:FindFirstChild("Road") == nil,
				`{partsBefore} parts in the server's workspace (cars and characters aside) before the press, {partsAfter} after; Workspace.Road {tostring(workspace:FindFirstChild("Road"))}`
			)
			-- End that one: the rest is measured on the pinned road.
			task.wait(D.RespawnCooldown + 0.05)
			press(false, player)
		end

		------------------------------------------------------------------------
		-- 4. A fall puts the car back ON THE ROAD, ahead of the barrier, and does not end the run
		------------------------------------------------------------------------
		do
			task.wait(D.RespawnCooldown + 0.05)
			RoadService:Generate(ROAD_SEED)
			press(true, player)
			local gen = RoadService:DebugGenerator()
			-- Drive the window up the road the way play does, then fall off it. One piece at a
			-- time, because each tick is what lays the next ten.
			for n = 2, FALL_PIECE do
				local pose = poseOnPiece(n, 0.5)
				if not pose then
					break
				end
				CarService:DebugBelieve(player.UserId, pose.Position)
				RoadService:DebugTick()
			end
			local onRoadCF = assert(poseOnPiece(FALL_PIECE, 0.6), `no piece {FALL_PIECE} on the road`)
			local onRoad = onRoadCF.Position
			CarService:DebugBelieve(player.UserId, onRoad)
			RoadService:DebugTick()
			local furthestBefore = gen.furthestN
			local closing = closingS()

			-- Straight down through the world, far enough below the road it fell off that
			-- `FallBelowSurface` catches it.
			local below = onRoad - Vector3.new(0, D.FallBelowSurface + 80, 0)
			CarService:DebugBelieve(player.UserId, below)
			task.wait(D.RespawnCooldown + 0.05)
			local back = CarService:DebugRespawn(player.UserId)
			local at = pieceAt(back)
			local sBack, dBack = along(back)
			local surface = surfaceUnder(back)
			local furthestAfter = gen.furthestN
			check(
				"a fall straight down puts the car back on the road it fell from, ahead of the closing barrier, and the run does not end",
				back ~= nil
					and at ~= nil
					and at.onRoad
					and at.n == FALL_PIECE
					and closing ~= nil
					and sBack ~= nil
					and sBack > closing
					and surface ~= nil
					and math.abs(back.Y - (surface + D.RideHeight)) < 1e-3
					and RoadService:InRun(player)
					and RoadService:HasRoad()
					and RoadService:DebugGenerator() == gen
					and furthestAfter >= furthestBefore,
				string.format(
					"fell from piece %d at Y %.0f (the road there is at Y %.0f), put back on piece %s at s %.0f, %.2f studs off the centre line, Y %.2f against the curve's %.2f + ride height; the closing barrier at s %s; still in the run: %s; the road is still up and the same: %s; furthest N %d -> %d",
					FALL_PIECE,
					below.Y,
					onRoad.Y - D.RideHeight,
					at and tostring(at.n) or "NOT ON THE ROAD",
					sBack or -1,
					dBack and math.abs(dBack) or -1,
					back and back.Y or -1,
					surface or -1,
					closing and string.format("%.0f", closing) or "none",
					tostring(RoadService:InRun(player)),
					tostring(RoadService:DebugGenerator() == gen),
					furthestBefore,
					furthestAfter
				)
			)

			-- And off the SIDE and away, far enough that the road cannot locate the position at
			-- all. This is the path the roster answers rather than the position.
			local away = onRoad + onRoadCF.RightVector * 4000 + Vector3.new(0, -400, 0)
			CarService:DebugBelieve(player.UserId, away)
			local locatedOut = RoadService:PieceAt(away)
			task.wait(D.RespawnCooldown + 0.05)
			local back2 = CarService:DebugRespawn(player.UserId)
			local at2 = pieceAt(back2)
			local s2 = along(back2)
			local closing2 = closingS()
			check(
				"a car that left the road altogether still comes back on to it, ahead of the closing barrier",
				locatedOut == nil
					and back2 ~= nil
					and at2 ~= nil
					and at2.onRoad
					and s2 ~= nil
					and closing2 ~= nil
					and s2 > closing2
					and RoadService:InRun(player),
				string.format(
					"4000 studs off the side and 400 down: the road locates that position as %s, and the respawn put the car on piece %s at s %.0f, the closing barrier at s %s. Still in the run: %s. The roster answered, not the position",
					tostring(locatedOut),
					at2 and tostring(at2.n) or "NOT ON THE ROAD",
					s2 or -1,
					closing2 and string.format("%.0f", closing2) or "none",
					tostring(RoadService:InRun(player))
				)
			)
		end

		------------------------------------------------------------------------
		-- 5. A second driver joins THE SAME road, and cannot be stranded
		------------------------------------------------------------------------
		do
			local gen = RoadService:DebugGenerator()
			local seedBefore, firstBefore, lastBefore = gen.seed, gen.first, gen.last
			local closing = closingS()
			local joinedAt = RoadService:DebugJoin(STAND_IN)
			local genAfter = RoadService:DebugGenerator()
			local at = pieceAt(joinedAt and joinedAt.Position)
			local sJoin = along(joinedAt and joinedAt.Position)
			check(
				"a second driver joins the same road, ahead of the closing barrier",
				joinedAt ~= nil
					and genAfter == gen
					and genAfter.seed == seedBefore
					and genAfter.first == firstBefore
					and genAfter.last == lastBefore
					and at ~= nil
					and at.onRoad
					and closing ~= nil
					and sJoin ~= nil
					and sJoin > closing
					and RoadService:RunnerCount() == 2,
				string.format(
					"the road is the same object, seed %s, window %d..%d, unchanged by the join; the joiner lands on piece %s at s %.0f with the closing barrier at s %s (leader on piece %s); %d on the roster. NOT PROVED HERE: a second CAR moving, which Studio gives no second player to move",
					tostring(seedBefore),
					firstBefore,
					lastBefore,
					at and tostring(at.n) or "off the road",
					sJoin or -1,
					closing and string.format("%.0f", closing) or "none",
					tostring(RoadService:DebugState().leaderN),
					RoadService:RunnerCount()
				)
			)

			-- The real player ends their run while the stand-in is still on the road.
			task.wait(D.RespawnCooldown + 0.05)
			press(false, player)
			local genLeft = RoadService:DebugGenerator()
			local world = CarService:WorldAt(carPivot(player) or Vector3.zero)
			check(
				"one player ending a run cannot strand another",
				genLeft ~= nil
					and genLeft == gen
					and genLeft.first == firstBefore
					and genLeft.last == lastBefore
					and closingS() == closing
					and RoadService:HasRoad()
					and RoadService:RunnerCount() == 1
					and not RoadService:InRun(player)
					and world ~= "road",
				string.format(
					"the player left and went back to the %s; the road is the same generator, window %s..%s (was %d..%d), closing barrier at s %s (was %s), still running, %d driver left on it",
					tostring(world),
					tostring(genLeft and genLeft.first),
					tostring(genLeft and genLeft.last),
					firstBefore,
					lastBefore,
					tostring(closingS()),
					tostring(closing),
					RoadService:RunnerCount()
				)
			)

			-- And when the last of them goes, the road goes.
			RoadService:DebugLeave(STAND_IN)
			check(
				"the last driver leaving takes the road down",
				not RoadService:HasRoad() and RoadService:DebugGenerator() == nil and RoadService:RunnerCount() == 0,
				`after the last driver left: HasRoad {tostring(RoadService:HasRoad())}, generator {tostring(RoadService:DebugGenerator() ~= nil)}, {RoadService:RunnerCount()} on the roster`
			)
		end

		------------------------------------------------------------------------
		-- 6. Pressing it again ends the run and puts the car back where it came from
		------------------------------------------------------------------------
		do
			task.wait(D.RespawnCooldown + 0.05)
			local from = CarService:WorldAt(CarService:BelievedPosition(player.UserId) or carPivot(player) or Vector3.zero)
			RoadService:Generate(ROAD_SEED)
			press(true, player)
			local onRoad = CarService:WorldAt(carPivot(player) or Vector3.zero)
			task.wait(D.RespawnCooldown + 0.05)
			local state = press(false, player)
			local back = carPivot(player)
			local world = CarService:WorldAt(back or Vector3.zero)
			local home = CarService:SpawnCFrameIn(from)
			check(
				"the same button ends the run, takes the road down and puts the car back where it started",
				onRoad == "road"
					and not RoadService:HasRoad()
					and RoadService:DebugGenerator() == nil
					and state ~= nil
					and state.inRun == false
					and world == from
					and back ~= nil
					and (back - home.Position).Magnitude < 1,
				string.format(
					"started in the %s, drove in the %s, ended in the %s, %.2f studs from that world's spawn; the road is %s and the server says inRun=%s",
					tostring(from),
					tostring(onRoad),
					tostring(world),
					back and (back - home.Position).Magnitude or -1,
					if RoadService:HasRoad() then "STILL UP" else "down",
					tostring(state and state.inRun)
				)
			)
		end

		------------------------------------------------------------------------
		-- 7. The remote refuses a forged request
		------------------------------------------------------------------------
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
				local okPress, errPress = pcall(function()
					RoadService:DebugPress(junk, player.UserId)
				end)
				if not okPress then
					errored = `{typeof(junk)}: {tostring(errPress)}`
				end
			end
			local after = RoadService:DebugState()
			check(
				"a forged request starts nothing and is counted, whatever it is",
				errored == nil
					and not RoadService:HasRoad()
					and RoadService:DebugGenerator() == nil
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
			local genNow = RoadService:DebugGenerator()
			check(
				"a position, a seed and a progress sent with a real press are all ignored",
				RoadService:HasRoad()
					and landed ~= nil
					and want ~= nil
					and (landed - want.Position).Magnitude < 1
					and (landed - forged.Position).Magnitude > 1000
					and at ~= nil
					and at.n == 1
					and genNow ~= nil
					and genNow.seed ~= 999999,
				string.format(
					"pressed start with a CFrame, a seed and a progress table after it; the car went to the road's own piece 1 (%.2f studs from where the server computed it) and %.0f studs from the place the 'client' named; the road's seed is %s",
					landed and want and (landed - want.Position).Magnitude or -1,
					landed and (landed - forged.Position).Magnitude or -1,
					tostring(genNow and genNow.seed)
				)
			)
		end

		------------------------------------------------------------------------
		-- 8. The two guards on the button
		------------------------------------------------------------------------
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

		------------------------------------------------------------------------
		-- 9. End to end: press start, drive it down the mountain, fall off, recover, finish
		-- 10. ...and a fall is measured from the ground, not from Y = 0
		------------------------------------------------------------------------
		if opts.skipDrive ~= true then
			loadModel()
			task.wait(D.RespawnCooldown + 0.05)
			local from = CarService:WorldAt(CarService:BelievedPosition(player.UserId) or carPivot(player) or Vector3.zero)
			-- The road is laid with the PINNED seed and the button is pressed on to it -- the
			-- join path, the same `StartRun` a second driver takes -- so the drive is the same
			-- road every time and its numbers mean something.
			RoadService:Generate(ROAD_SEED)
			press(true, player)
			local gen = RoadService:DebugGenerator()
			local r = Tests:drive({
				player = player,
				pieces = DRIVE_PIECES,
				fallAt = math.floor(DRIVE_PIECES / 2),
				startCFrame = RoadService:SpawnCFrame(),
			})
			local stillUp = RoadService:HasRoad()
			local stillIn = RoadService:InRun(player)

			-- THE MOUNTAIN ROAD DESCENDS, and the model's fall test is relative to the ground
			-- it last had (T-067). Two halves that pull opposite ways: hundreds of studs down
			-- with road under the car the whole way, nothing is a fall (the drive, above); off
			-- the side of that same road, past everything the curve answers for, a fall is
			-- still a fall and still comes back.
			local piece = assert(gen:piece(r.reached), "no piece to fall off")
			local pose = gen:poseOn(piece, piece.length * 0.5, D.RideHeight)
			local roadY = pose.Position.Y - D.RideHeight
			local liveWorld = World.live({ workspace:FindFirstChild("Cars") })
			local world = SplineWorld.new(gen.spline, liveWorld)
			world.setClosing(closingS())
			local runner = Sim.newRunner(pose)
			runner.state.time = 10
			local input = { steer = 0, handbrake = false }
			-- One step ON the road, so the ground -- and nothing else -- says where the fall is
			-- measured from.
			Sim.advance(runner, 1 / DRIVE_FPS, input, world)
			local measuredFrom = runner.state.fallFrom
			local onRoadFell = runner.state.fell
			-- Over nothing beside it, standing still: past the road, its widest runoff and the
			-- margin the curve answers for, on whichever side is clear of other road.
			local void = nil
			for _, side in { 1, -1 } do
				local p = pose.Position + pose.RightVector * side * (reach() + 60)
				if gen:locate(p) == nil then
					void = p
					break
				end
			end
			local seconds = 0
			if void then
				runner.state.position = void
				runner.state.velocity = Vector3.zero
				while seconds < 20 and not runner.state.fell do
					Sim.advance(runner, 1 / DRIVE_FPS, input, world)
					seconds += 1 / DRIVE_FPS
				end
			end
			local fell = void ~= nil and runner.state.fell
			local droppedBy = measuredFrom - runner.state.position.Y
			world.destroy()
			liveWorld.destroy()

			-- And the server puts it back, on the road, at the road's height.
			local furthestBefore = gen.furthestN
			CarService:DebugBelieve(player.UserId, runner.state.position)
			task.wait(D.RespawnCooldown + 0.05)
			local back = CarService:DebugRespawn(player.UserId)
			local at = pieceAt(back)
			local sBack = along(back)
			local closing = closingS()
			local backSurface = surfaceUnder(back)
			local offSurface = if back and backSurface then math.abs(back.Y - (backSurface + D.RideHeight)) else math.huge
			local furthestAfter = gen.furthestN
			local stillInAfterSide = RoadService:InRun(player)

			task.wait(D.RespawnCooldown + 0.05)
			press(false, player)
			local backHome = carPivot(player)
			local endedIn = CarService:WorldAt(backHome or Vector3.zero)

			local driveDetail = string.format(
				"seed %d: %d pieces in %.0f s of simulation (%d steps), %.0f..%.0f studs/s, drifting %.0f%%; %d steps off the road (widest %.1f from the centre), %d airborne, %d backwards, %d touching a wall; the closing barrier moved up %d times. Fell off at piece %d on purpose and the server put it back on piece %s at s %.0f, ahead of the barrier at s %s: %s; the run survived it (%s) and furthest N went %d -> %d. Ended in the %s",
				ROAD_SEED,
				r.reached,
				r.seconds,
				r.steps,
				r.minSpeed,
				r.maxSpeed,
				100 * r.driftShare,
				r.offRoadSteps,
				r.worstLateral,
				r.airSteps,
				r.backwardsSteps,
				r.wallSteps,
				r.closingMoves,
				math.floor(DRIVE_PIECES / 2),
				tostring(r.recoveredAt),
				r.recoveredS,
				r.closingAtFall and string.format("%.0f", r.closingAtFall) or "none",
				tostring(r.recoveredAhead),
				tostring(not r.endedByFall),
				r.furthestBefore,
				r.furthestAfter,
				tostring(endedIn)
			)
			check(
				`a run is started, driven {DRIVE_PIECES} pieces with a fall in it, and ended`,
				r.reached >= DRIVE_PIECES
					and r.fell
					and r.recovered
					and r.recoveredAhead
					and r.recoveredAt == math.floor(DRIVE_PIECES / 2)
					and not r.endedByFall
					and r.furthestAfter >= r.furthestBefore
					and r.closingMoves > 0
					and stillUp
					and stillIn
					and not RoadService:HasRoad()
					and endedIn == from,
				driveDetail
			)
			check(
				"the drive never left the road, never went backwards, and never asked to be respawned",
				r.offRoadSteps == 0 and r.airSteps == 0 and r.backwardsSteps == 0 and r.modelFellSteps == 0,
				driveDetail .. string.format("; the model asked to be respawned on %d of %d steps", r.modelFellSteps, r.steps)
			)
			check(
				"a car driven down the mountain, below where the old absolute fall test sat, never asks to be respawned",
				r.modelFellSteps == 0 and r.lowestY < OLD_RESPAWN_BELOW_Y and r.oldWouldFallSteps > 0,
				string.format(
					"from Y %.0f down to Y %.0f -- %.0f studs below the old RespawnBelowY of %d. THE OLD TEST WOULD HAVE CALLED %d OF THOSE %d STEPS A FALL; this one calls %d of them a fall",
					r.startY,
					r.lowestY,
					OLD_RESPAWN_BELOW_Y - r.lowestY,
					OLD_RESPAWN_BELOW_Y,
					r.oldWouldFallSteps,
					r.steps,
					r.modelFellSteps
				)
			)
			check(
				"a fall off the side of the road far down the mountain is still a fall, and comes back on the road at that height, ahead of the barrier",
				void ~= nil
					and fell
					and not onRoadFell
					and math.abs(droppedBy - D.FallBelowSurface) < 12
					and back ~= nil
					and at ~= nil
					and at.onRoad
					and offSurface < 1e-3
					and sBack ~= nil
					and closing ~= nil
					and sBack > closing
					and stillInAfterSide
					and furthestAfter >= furthestBefore,
				string.format(
					"on the road at piece %d (Y %.0f) nothing was falling; %.0f studs to the side, over nothing (%s), the car fell %.0f studs from the %.0f it last had ground at -- FallBelowSurface is %d -- in %.1f s, and reported fell=%s. The server put it back on piece %s at s %.0f (closing barrier at s %s), Y %.2f, %.4f off the curve's surface + ride height; still in the run: %s; furthest N %d -> %d",
					r.reached,
					roadY,
					reach() + 60,
					tostring(void ~= nil),
					droppedBy,
					measuredFrom,
					D.FallBelowSurface,
					seconds,
					tostring(fell),
					at and tostring(at.n) or "NOT ON THE ROAD",
					sBack or -1,
					closing and string.format("%.0f", closing) or "none",
					back and back.Y or -1,
					offSurface,
					tostring(stillInAfterSide),
					furthestBefore,
					furthestAfter
				)
			)
		end
	end)
	if not ok then
		check("the suite ran to the end", false, tostring(err))
	end

	----------------------------------------------------------------------------
	-- Put the place back
	----------------------------------------------------------------------------
	RoadService:Stop()
	RoadService:DebugClearLimits()
	task.wait(D.RespawnCooldown + 0.05)
	CarService:Place(player, CarService:SpawnCFrameIn(startedInWorld))

	local passed = true
	local count = 0
	for _, c in checks do
		passed = passed and c.ok
		if c.ok then
			count += 1
		end
	end
	return { passed = passed, count = count, total = #checks, checks = checks }
end

return Tests
