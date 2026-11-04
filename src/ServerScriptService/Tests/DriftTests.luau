--!nonstrict
-- DriftTests: the drift model's automated checks
-- (docs/game/features/drift-model.md "Testing", docs/workflow/TESTING.md).
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugDriftTests", "run")
--
-- Everything here is pure: the model is maths plus two injected world queries, so these
-- run with no player, no car and no playtest. The one check that needs the Workspace
-- (`no physics`) builds its own car and also looks at any live ones.
--
-- None of this is a feel judgement -- that is the user's, and it is the gate. These catch
-- a model that has stopped being the one the spec describes: the finger that is a rate of
-- turn, the slip angle that opens by itself, the quadratic that closes it, the brake past
-- square-on, and the speed a drift costs.
--
-- The model lives in StarterPlayerScripts because the client that drives a car owns its
-- simulation. The server can still require it -- it is a ModuleScript in a container the
-- server can see -- and that is deliberate: one code path, tested where the test kit is.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "DriftTests only runs in Studio")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Sim = require(DriftFolder.Sim)
local World = require(DriftFolder.World)

local DriftTests = {}

-- The scripted corner the checks below measure: already moving, straight for a moment,
-- then one steady finger, then let go. Changing it changes what every number means, so it
-- lives here as one named thing rather than inline in three checks.
local CORNER = {
	{ t = 0, steer = 0 },
	{ t = 1, steer = 0.6 },
	{ t = 2.6, steer = 0 },
}
local CORNER_SECONDS = 5
local CORNER_ENTRY = 120 -- studs/s the corner is entered at

-- Every check that measures GRIP starts the car on this heading rather than on a world
-- axis. The reference clamps each step's pull per world axis against that axis's own
-- speed -- its guard against overshooting through zero at a standstill, and the spec's
-- (features/drift-model.md "Grip -- the drift") -- so a car travelling exactly along -Z
-- has no X speed for the clamp to allow, and the sideways pull is suppressed until the
-- car has yawed far enough to build one. That is a measurement artefact of a perfectly
-- axis-aligned start, not something a player can ever be in; 15 degrees is off it.
local TEST_YAW = math.rad(15)

local function startCF(yaw: number?): CFrame
	local cf = CFrame.new(0, Config.Drift.RideHeight, 0)
	return if yaw then cf * CFrame.Angles(0, yaw, 0) else cf
end

-- Straight ahead at speed, on a heading.
local function ahead(speed: number, yaw: number?): Vector3
	local fwd = Model.axes(yaw or 0)
	return fwd * speed
end

-- Hold one finger from a rolling start and report what the car settles at: the slip angle
-- it reaches, the speed it keeps, the circle it describes. The means are over the last
-- second, so one wobble is not the answer.
local function hold(steer: number, speed: number, seconds: number, world)
	local C = Config.Drift
	local runner = Sim.newRunner(startCF(TEST_YAW))
	runner.state.velocity = ahead(speed, TEST_YAW)
	world = world or World.flat(0)

	local samples = {}
	local peak = 0
	local function observe(s)
		peak = math.max(peak, math.abs(math.deg(s.slip)))
		table.insert(samples, {
			t = s.time,
			slip = math.deg(s.slip),
			speed = Model.speed(s),
			r = s.r,
			grip = s.gripAccel,
		})
	end

	local elapsed = 0
	while elapsed < seconds - 1e-9 do
		local dt = math.min(1 / 60, seconds - elapsed)
		Sim.advance(runner, dt, { steer = steer }, world, observe)
		elapsed += dt
	end

	local n, slipSum, speedSum, gripSum = 0, 0, 0, 0
	for _, s in samples do
		if s.t >= seconds - 1 then
			n += 1
			slipSum += math.abs(s.slip)
			speedSum += s.speed
			gripSum += s.grip
		end
	end
	n = math.max(n, 1)
	local settledSpeed = speedSum / n
	local yaw = math.abs(runner.state.r)
	return {
		entry = speed,
		peakSlip = peak,
		slip = slipSum / n,
		speed = settledSpeed,
		grip = gripSum / n,
		share = settledSpeed / math.max(speed, 1e-3),
		radius = if yaw > 1e-3 then settledSpeed / yaw else math.huge,
		state = runner.state,
	}
end

-- One step with the car held at a known slip angle, and what the grip did about it.
-- The car's nose is at `yaw`, its velocity `slipDeg` round from that, and the measurement
-- is the velocity change along the car's RIGHT -- which is where the grip points, and
-- which the drivetrain (along the nose) and the downforce (straight down) cannot reach.
-- `yaw` is deliberately off the world axes: the reference's per-axis clamp would hide the
-- pull on an axis the car happens to have no speed along.
local function gripAt(slipDeg: number, speed: number, world)
	local C = Config.Drift
	local yaw = TEST_YAW
	local runner = Sim.newRunner(startCF(yaw))
	local travel = Model.axes(yaw + math.rad(slipDeg))
	world = world or World.flat(0)

	-- One step to let the ground rays find the surface under the car -- a fresh state has
	-- not cast one yet -- then the state is put back exactly where the measurement wants
	-- it and the step that follows is the one that is read.
	runner.state.velocity = travel * speed
	Sim.advance(runner, C.FixedStep, { steer = 0 }, world)
	runner.state.velocity = travel * speed
	runner.state.yaw = yaw

	local _, right = Model.axes(yaw)
	local before = runner.state.velocity
	Sim.advance(runner, C.FixedStep, { steer = 0 }, world)
	local after = runner.state.velocity

	local b = math.abs(math.rad(slipDeg))
	local bc = math.min(b, math.pi * 0.5)
	local expected = math.min(C.ConstantFriction + C.SlipFriction * bc + C.SlipSqFriction * bc * bc, C.MaxFriction)
	return {
		measured = math.abs((after - before):Dot(right)) / C.FixedStep,
		expected = expected,
		slipRead = math.deg(runner.state.slip),
		before = before,
		after = after,
		travel = travel,
	}
end

local function check(checks, name, ok, detail)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
	return ok == true
end

-- Every physics object a car must not have, wherever it came from.
local function offenderReport(model: Instance): (boolean, string)
	local offenders = CarModel.physicsOffenders(model)
	if #offenders == 0 then
		local parts = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		return true, `{model.Name}: {parts} parts, all anchored, nothing that moves them`
	end
	return false, `{model.Name}: {table.concat(offenders, "; ")}`
end

function DriftTests.run()
	local checks = {}
	local C = Config.Drift

	------------------------------------------------------------------ determinism
	local driveOpts = { fps = 60, start = startCF(TEST_YAW), velocity = ahead(CORNER_ENTRY, TEST_YAW) }
	local pathA, cornerA = Sim.drive(CORNER, CORNER_SECONDS, driveOpts)
	local pathB = Sim.drive(CORNER, CORNER_SECONDS, driveOpts)
	local worst = 0
	for i = 1, math.min(#pathA, #pathB) do
		worst = math.max(worst, (pathA[i] - pathB[i]).Magnitude)
	end
	check(
		checks,
		"a repeatable line",
		#pathA == #pathB and worst < 1,
		`{#pathA} points, worst deviation {string.format("%.6f", worst)} studs (same inputs, same start)`
	)

	------------------------------------------------------------------ frame independence
	local ends, spread = {}, 0
	for _, fps in { 30, 60, 120 } do
		local _, summary = Sim.drive(CORNER, CORNER_SECONDS, { fps = fps, start = startCF(TEST_YAW), velocity = ahead(CORNER_ENTRY, TEST_YAW) })
		ends[fps] = summary.endPosition
	end
	for _, a in ends do
		for _, b in ends do
			spread = math.max(spread, (a - b).Magnitude)
		end
	end
	check(
		checks,
		"the same line at 30, 60 and 120 FPS",
		spread < 2,
		string.format(
			"worst gap between the three end points %.3f studs; the corner turned %.1f deg and went in at %.0f studs/s",
			spread,
			cornerA.headingChangeDeg,
			CORNER_ENTRY
		)
	)

	------------------------------------------------------------------ a drive without `fps` is a real drive
	-- `DebugDrive` is the tool every tuning conversation uses, so it must not quietly
	-- simulate less than it was asked for. `advance` clamps one frame to
	-- `FixedStep * MaxStepsPerFrame`; a drive handed to it as a single frame of `seconds`
	-- therefore used to run for 0.133 s and report `simSeconds` to match, and every
	-- measurement taken without `fps` was of a drive that never happened.
	local noFps, withFps = select(2, Sim.drive(CORNER, CORNER_SECONDS, {
		start = startCF(TEST_YAW),
		velocity = ahead(CORNER_ENTRY, TEST_YAW),
	})), select(2, Sim.drive(CORNER, CORNER_SECONDS, {
		fps = 60,
		start = startCF(TEST_YAW),
		velocity = ahead(CORNER_ENTRY, TEST_YAW),
	}))
	check(
		checks,
		"a drive with no frame rate runs for as long as it was asked to",
		math.abs(noFps.simSeconds - CORNER_SECONDS) < 0.05
			and math.abs(noFps.headingChangeDeg - withFps.headingChangeDeg) < 2,
		string.format(
			"asked for %.1f s: ran %.3f s and turned %.1f deg, against %.3f s and %.1f deg at 60 FPS",
			CORNER_SECONDS,
			noFps.simSeconds,
			noFps.headingChangeDeg,
			withFps.simSeconds,
			withFps.headingChangeDeg
		)
	)

	------------------------------------------------------------------ the finger IS the rate of turn
	-- The thing the whole port is for (features/drift-model.md "Steering -- the control").
	-- Not a torque, not a wheel angle, not a target: the heading change over a hold is the
	-- finger times `MaxSteeringSpeed` times the time, at any speed, and the two speeds
	-- here are there to prove the car's own state does not get a say.
	local turnOk, turnParts = true, {}
	for _, speed in { 40, 150 } do
		local steerHeld = 0.5
		local seconds = 1
		local _, summary = Sim.drive({ { t = 0, steer = steerHeld } }, seconds, {
			fps = 60,
			start = startCF(TEST_YAW),
			velocity = ahead(speed, TEST_YAW),
		})
		local wanted = math.deg(C.MaxSteeringSpeed * steerHeld * C.SteeringSensitivity * seconds)
		local got = math.abs(summary.headingChangeDeg)
		turnOk = turnOk and math.abs(got - wanted) <= 1
		table.insert(turnParts, string.format("from %d studs/s: %.2f deg, asked for %.2f", speed, got, wanted))
	end
	check(checks, "the finger is the car's rate of turn, at any speed", turnOk, table.concat(turnParts, " | "))

	-- And it halves when the dial halves: the numbers are in Config, not in the logic.
	local maxSteer = C.MaxSteeringSpeed
	local _, fullTurn = Sim.drive({ { t = 0, steer = 1 } }, 1, { fps = 60, start = startCF(TEST_YAW), velocity = ahead(80, TEST_YAW) })
	C.MaxSteeringSpeed = maxSteer * 0.5
	local _, halfTurn = Sim.drive({ { t = 0, steer = 1 } }, 1, { fps = 60, start = startCF(TEST_YAW), velocity = ahead(80, TEST_YAW) })
	C.MaxSteeringSpeed = maxSteer
	check(
		checks,
		"halving MaxSteeringSpeed halves the rate of turn",
		math.abs(math.abs(halfTurn.headingChangeDeg) * 2 - math.abs(fullTurn.headingChangeDeg)) < 0.5,
		string.format(
			"a second of full finger turned %.1f deg at %.1f rad/s and %.1f deg at %.1f",
			math.abs(fullTurn.headingChangeDeg),
			maxSteer,
			math.abs(halfTurn.headingChangeDeg),
			maxSteer * 0.5
		)
	)

	------------------------------------------------------------------ centring stops the turn at once
	-- No yaw inertia and no damping anywhere, so there is nothing left to spin down.
	local centring = Sim.newRunner(startCF(TEST_YAW))
	centring.state.velocity = ahead(100, TEST_YAW)
	local world = World.flat(0)
	Sim.advance(centring, 1, { steer = 1 }, world)
	local turningRate = centring.state.r
	local yawBefore = centring.state.yaw
	Sim.advance(centring, C.FixedStep, { steer = 0 }, world)
	local yawAfter = centring.state.yaw
	check(
		checks,
		"centring the finger stops the turn on the next step",
		turningRate ~= 0 and centring.state.r == 0 and yawAfter == yawBefore,
		string.format(
			"turning at %.2f rad/s, then one step with the finger centred: %.4f rad/s, heading moved %.6f deg",
			turningRate,
			centring.state.r,
			math.deg(yawAfter - yawBefore)
		)
	)

	------------------------------------------------------------------ rotating is drifting
	-- No drift input exists to use. A steady finger from speed opens the slip angle on its
	-- own, because nothing moves the velocity when the car rotates.
	local opener = hold(0.5, 140, 6)
	check(
		checks,
		"rotating is drifting: a steady finger opens the slip angle by itself",
		opener.peakSlip > C.MinSlipAngleForDrift * 2 and opener.slip > C.MinSlipAngleForDrift,
		string.format(
			"half a finger from 140 studs/s, no drift input anywhere: slip peaked at %.1f deg and settled at %.1f, speed settled at %.0f studs/s on a %.0f stud circle",
			opener.peakSlip,
			opener.slip,
			opener.speed,
			math.min(opener.radius, 9999)
		)
	)

	------------------------------------------------------------------ grip is a quadratic
	-- Held at a known angle, one step, and the pull measured along the car's right, which
	-- is the only axis the grip acts on and neither the drivetrain nor the downforce can
	-- reach. The fit is the spec's own curve, capped at `MaxFriction`.
	local quadOk, quadParts, quadWorst = true, {}, 0
	for _, slipDeg in { 15, 30, 45, 60, 80 } do
		local g = gripAt(slipDeg, 80)
		local err = math.abs(g.measured - g.expected)
		quadWorst = math.max(quadWorst, err)
		quadOk = quadOk and err < 0.5
		table.insert(quadParts, string.format("%d deg: %.1f (curve %.1f)", slipDeg, g.measured, g.expected))
	end
	check(
		checks,
		"grip grows as a quadratic in the slip angle, to its ceiling",
		quadOk,
		string.format(
			"%s studs/s^2, worst gap %.3f; ceiling %.0f",
			table.concat(quadParts, " | "),
			quadWorst,
			C.MaxFriction
		)
	)

	-- And the ceiling is wired, which the starting numbers alone cannot show: the three
	-- terms top out at 72 studs/s^2 at square-on, well under `MaxFriction`, so the cap is
	-- inert as the car is tuned today. Tripling them proves it binds, and the detail says
	-- what the shipped curve actually reaches -- a number worth knowing before anyone
	-- tunes `MaxFriction` expecting it to do something.
	local uncapped = gripAt(89, 80).measured
	local c0, c1, c2 = C.ConstantFriction, C.SlipFriction, C.SlipSqFriction
	C.ConstantFriction, C.SlipFriction, C.SlipSqFriction = c0 * 3, c1 * 3, c2 * 3
	local capped = gripAt(89, 80).measured
	C.ConstantFriction, C.SlipFriction, C.SlipSqFriction = c0, c1, c2
	check(
		checks,
		"the grip ceiling holds",
		math.abs(capped - C.MaxFriction) < 0.5 and uncapped < C.MaxFriction,
		string.format(
			"89 deg of slip pulls %.1f studs/s^2 as tuned -- the ceiling of %.0f is never reached -- and %.1f with the three terms tripled, which is the ceiling exactly",
			uncapped,
			C.MaxFriction,
			capped
		)
	)

	------------------------------------------------------------------ surfaces matter
	local onTarmac = gripAt(45, 80, World.flat(0, C.GripTarmac, C.ScoreTarmac))
	local onDirt = gripAt(45, 80, World.flat(0, C.GripDirt, C.ScoreDirt))
	check(
		checks,
		"dirt makes half the grip tarmac does",
		math.abs(onDirt.measured - onTarmac.measured * (C.GripDirt / C.GripTarmac)) < 0.5,
		string.format(
			"45 deg of slip pulls %.1f studs/s^2 on tarmac and %.1f on dirt",
			onTarmac.measured,
			onDirt.measured
		)
	)

	------------------------------------------------------------------ past 90 degrees it brakes
	-- The car is going backwards relative to its nose, so the pull stops being sideways
	-- and points straight against the travel. The drivetrain is turned off for this one,
	-- so what is left is only the grip and it can be read along the travel directly.
	local maxAccel = C.MaxAcceleration
	C.MaxAcceleration = 0
	local spun = gripAt(135, 80)
	C.MaxAcceleration = maxAccel
	local dir = spun.travel
	local alongBefore = spun.before:Dot(dir)
	local alongAfter = spun.after:Dot(dir)
	-- Across the travel, and only across the ground: the vertical is the ground follow
	-- writing the car's height back, which is not the grip and is not sideways.
	local delta = spun.after - spun.before
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local across = flat - dir * flat:Dot(dir)
	check(
		checks,
		"past 90 degrees the grip brakes instead of steering",
		alongAfter < alongBefore and across.Magnitude / C.FixedStep < 0.5,
		string.format(
			"spun to 135 deg at 80 studs/s, engine off: speed along its travel %.2f -> %.2f studs/s (%.1f studs/s^2 of braking), sideways %.3f studs/s^2",
			alongBefore,
			alongAfter,
			(alongBefore - alongAfter) / C.FixedStep,
			across.Magnitude / C.FixedStep
		)
	)

	------------------------------------------------------------------ a drift costs speed
	-- Nothing in the model says so: the engine pushes along the nose, and a car that is
	-- sideways is pushing across its own travel. The cost falls out of the geometry, and
	-- it has to grow with the finger or the player has a switch rather than a dial.
	local rungs = {}
	for _, steer in { 0.25, 0.5, 1 } do
		table.insert(rungs, { steer = steer, r = hold(steer, 140, 8) })
	end
	local costs, parts = true, {}
	for i, rung in rungs do
		if i > 1 then
			costs = costs and rung.r.speed < rungs[i - 1].r.speed
		end
		table.insert(
			parts,
			string.format(
				"%.0f%%: %.0f deg of slip, %.0f studs/s kept (%.0f%% of entry), circle %.0f studs",
				rung.steer * 100,
				rung.r.slip,
				rung.r.speed,
				100 * rung.r.share,
				math.min(rung.r.radius, 9999)
			)
		)
	end
	check(checks, "every notch of finger costs more speed than the last", costs, table.concat(parts, " | "))

	------------------------------------------------------------------ nothing runs away
	-- The whole model rests on being able to trust the numbers it produces. The yaw rate
	-- cannot run away by construction -- it is set, not integrated -- so this is really a
	-- check on the speed, which no term in the model caps directly: the drivetrain's
	-- falloff is what holds it, and the grip is what takes it away.
	local abuse = {
		{ t = 0, steer = 1 },
		{ t = 2, steer = -1 },
		{ t = 4, steer = 1 },
		{ t = 6, steer = -1 },
		{ t = 8, steer = 1 },
		{ t = 10, steer = -1 },
	}
	local _, abused = Sim.drive(abuse, 12, { fps = 60, start = startCF(TEST_YAW), velocity = ahead(C.TopSpeed, TEST_YAW) })
	local speedCeiling = C.TopSpeed * C.StateSpeedTolerance
	check(
		checks,
		"no runaway over 12 s lock to lock",
		abused.maxSpeed <= speedCeiling and abused.peakYawRate <= C.MaxSteeringSpeed + 1e-6,
		string.format(
			"12 s of lock to lock from top speed: fastest %.1f studs/s (the server drops anything over %.0f), top yaw %.3f rad/s (the finger's own %.2f), ended at %.1f",
			abused.maxSpeed,
			speedCeiling,
			abused.peakYawRate,
			C.MaxSteeringSpeed,
			abused.endSpeed
		)
	)

	------------------------------------------------------------------ no physics
	-- The rule the whole model rests on, and the one most easily broken later
	-- (docs/game/DECISIONS.md, 2026-11-03).
	local built = CarModel.build()
	local builtOk, builtDetail = offenderReport(built)
	built:Destroy()
	check(checks, "a fresh car model holds no physics object", builtOk, builtDetail)

	local live, liveDetails, liveCount = true, {}, 0
	local cars = workspace:FindFirstChild("Cars")
	if cars then
		for _, car in cars:GetChildren() do
			if car:IsA("Model") then
				liveCount += 1
				local ok, detail = offenderReport(car)
				live = live and ok
				table.insert(liveDetails, detail)
			end
		end
	end
	check(
		checks,
		"every live car holds no physics object",
		live,
		if liveCount == 0
			then "no cars spawned yet (nothing to check: start a playtest to cover this)"
			else table.concat(liveDetails, " | ")
	)

	------------------------------------------------------------------ the ground
	-- The model must drive on a bare plate, with nothing tagged, as well as on the
	-- playground (docs/game/CONTRACTS.md, tag `DriftSurface`).
	local _, flat = Sim.drive({ { t = 0, steer = 0 } }, 6, { fps = 60, world = World.flat(0) })
	check(
		checks,
		"a bare plate is drivable",
		flat.airborneSeconds == 0 and flat.endSpeed > 0 and flat.peakSlipDeg < C.MinSlipAngleForDrift,
		string.format(
			"6 s on a flat plane with nothing tagged: %.1f studs/s from a standing start, %.2f s airborne, straight to within %.2f deg, %d surfaces tagged in this place",
			flat.endSpeed,
			flat.airborneSeconds,
			flat.peakSlipDeg,
			#CollectionService:GetTagged(C.SurfaceTag)
		)
	)

	------------------------------------------------------------------ the throttle is not an input
	-- It eases in, so a first-time player is never handed a car at top speed.
	local easing = Sim.newRunner(startCF())
	local throttleAtStart = easing.state.throttle
	local easeWorld = World.flat(0)
	local easeElapsed = 0
	while easeElapsed < C.FullThrottleSeconds - 1e-9 do
		local dt = math.min(1 / 60, C.FullThrottleSeconds - easeElapsed)
		Sim.advance(easing, dt, { steer = 0 }, easeWorld)
		easeElapsed += dt
	end
	check(
		checks,
		"the throttle eases itself in",
		math.abs(throttleAtStart - C.StartThrottle) < 1e-6 and easing.state.throttle > 0.99,
		string.format(
			"%.3f at the start of a run, %.3f after %.0f s, and no input anywhere feeds it",
			throttleAtStart,
			easing.state.throttle,
			C.FullThrottleSeconds
		)
	)

	------------------------------------------------------------------ the server owns respawns
	-- What the server owning respawns buys, checked where it lives: the movement check
	-- (docs/game/CONTRACTS.md, `CarState` and `CarRespawn`). A respawn is a position the
	-- server chose, so the first packet after it follows from something the server knows;
	-- a jump the server did not choose is rejected, and stays rejected however often it is
	-- repeated, because a rejected packet never becomes what the next one is measured
	-- against.
	local CarService = require(ServerScriptService.Services.CarService)
	local spawnAt = Vector3.new(0, C.RideHeight, 0)
	local period = 1 / C.StateSendRate
	local clock = 0

	-- A car at top speed, one send period at a time: honest across the ground.
	local track = CarService.track(spawnAt, clock)
	clock += period
	local driving = spawnAt + Vector3.new(C.TopSpeed * period, 0, 0)
	local drivingOk = CarService.fits(track, driving, clock)

	-- Off the edge: honest down the vertical axis too, at the fastest a fall may get.
	track = CarService.track(driving, clock)
	clock += period
	local falling = driving + Vector3.new(C.TopSpeed * period, -C.TerminalFall * period, 0)
	local fallingOk = CarService.fits(track, falling, clock)
	local fallenTrack = CarService.track(falling, clock)

	-- The server puts it back and records where: the next packet checks against that.
	local respawned = CarService.track(spawnAt, clock)
	local afterOk = CarService.fits(respawned, spawnAt + Vector3.new(C.TopSpeed * period, 0, 0), clock + period)
	-- And a packet sent before the respawn, landing after it, still has the old track
	-- (`RespawnGrace`), which is why a respawn costs no dropped packets at all.
	local inFlightOk =
		CarService.fits(fallenTrack, falling + Vector3.new(0, -C.TerminalFall * period, 0), clock + period)
	check(
		checks,
		"a respawn the server decided is not a teleport",
		drivingOk and fallingOk and afterOk and inFlightOk,
		string.format(
			"driving %s, falling at %.0f studs/s %s, the packet after the respawn %s, one in flight over it %s",
			drivingOk and "fits" or "FAILS",
			C.TerminalFall,
			fallingOk and "fits" or "FAILS",
			afterOk and "fits" or "FAILS",
			inFlightOk and "fits" or "FAILS"
		)
	)

	-- A jump nobody asked for. The track it is measured against never moves, so repeating
	-- it does not wear the server down.
	local jumped = spawnAt + Vector3.new(500, 0, 500)
	local cheat = CarService.track(spawnAt, clock)
	local rejected = 0
	local tries = 20
	for i = 1, tries do
		if not CarService.fits(cheat, jumped, clock + i * period) then
			rejected += 1
		end
	end
	check(
		checks,
		"a jump the server did not decide stays rejected",
		rejected == tries and C.StateResyncDrops == nil,
		string.format(
			"%d of %d packets %.0f studs from where the server put the car rejected, over %.1f s",
			rejected,
			tries,
			(jumped - spawnAt).Magnitude,
			tries * period
		)
	)

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return DriftTests
