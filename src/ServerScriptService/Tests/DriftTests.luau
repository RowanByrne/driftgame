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

local Bodies = require(ReplicatedStorage.Shared.Cars.Bodies)
local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Render = require(DriftFolder.Render)
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
	-- When the car first counts as drifting. With the finger held from a rolling start
	-- this is "how long it takes to get the tail out", and it is the number that tells
	-- two archetypes apart fastest: a grippy car can hold a finger at speed for ever and
	-- never slide at all, which comes back as nil (T-027).
	local slideAt: number? = nil
	local function observe(s)
		local slipDeg = math.abs(math.deg(s.slip))
		peak = math.max(peak, slipDeg)
		if not slideAt and slipDeg >= C.MinSlipAngleForDrift then
			slideAt = s.time
		end
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
		slideAt = slideAt,
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

-- Every physics object a car must not have, wherever it came from -- and, since the car
-- is now a stripped Creator Store vehicle, everything else that came with it and was
-- thrown away: scripts, sounds, lights, emitters, a seat (T-020, the user's "ditch all
-- the scripts attached to it").
local function offenderReport(model: Instance): (boolean, string)
	local offenders = CarModel.physicsOffenders(model)
	local strays = CarModel.strayOffenders(model)
	if #offenders == 0 and #strays == 0 then
		local parts = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		return true, `{model.Name}: {parts} parts, all anchored, nothing that moves them and nothing that runs`
	end
	local all = {}
	table.move(offenders, 1, #offenders, 1, all)
	table.move(strays, 1, #strays, #all + 1, all)
	return false, `{model.Name}: {table.concat(all, "; ")}`
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

	-- And it halves when the dial halves: the numbers are in the car, not in the logic
	-- (T-027 -- `MaxSteeringSpeed` is the CAR's, so it is moved with `Cars.withTuning`,
	-- which puts it back however this ends. Writing it into `Config.Drift` now errors).
	local maxSteer = C.MaxSteeringSpeed
	local _, fullTurn = Sim.drive({ { t = 0, steer = 1 } }, 1, { fps = 60, start = startCF(TEST_YAW), velocity = ahead(80, TEST_YAW) })
	local halfTurn = Cars.withTuning({ MaxSteeringSpeed = maxSteer * 0.5 }, function()
		return (select(2, Sim.drive({ { t = 0, steer = 1 } }, 1, { fps = 60, start = startCF(TEST_YAW), velocity = ahead(80, TEST_YAW) })))
	end)
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
	local capped = Cars.withTuning({
		ConstantFriction = c0 * 3,
		SlipFriction = c1 * 3,
		SlipSqFriction = c2 * 3,
	}, function()
		return gripAt(89, 80).measured
	end)
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
	local spun = Cars.withTuning({ MaxAcceleration = 0 }, function()
		return gripAt(135, 80)
	end)
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

	------------------------------------------------------------------ the cars (T-027)
	-- `Config.Drift` is the model and `Shared/Cars` is the car: everything above measured
	-- whichever car is active, which is `balanced` -- the one the user approved on
	-- 2026-11-03 -- and the first check here is that it still is, to the number. If this
	-- one fails, somebody has retuned the approved car while adding a new one, which is
	-- the one thing the archetypes were not allowed to do.
	local APPROVED = {
		MaxSteeringSpeed = 2,
		SteeringSensitivity = 1,
		ConstantFriction = 14.3,
		SlipFriction = 14.3,
		SlipSqFriction = 14.3,
		MaxFriction = 107,
		FrictionMultiplier = 1,
		MaxAcceleration = 14.3,
		AccelMultiplier = 1,
		TopSpeed = 179,
		StartThrottle = 0.5,
		FullThrottleSeconds = 5,
		HandbrakeDecel = 36,
		DownforcePerSpeed = 0.2,
		DownforceCutoff = -3.6,
		Wheelbase = 9.6,
		TrackWidth = 5.6,
		WheelDiameter = 2.3,
		RideHeight = 2.4,
		BodyRollMax = 10,
		BodyRollSpeed = 107,
		BodyRollRate = 10,
		WheelSteerMax = 30,
		WheelSteerRate = 4,
	}
	local wasCar = Cars.activeKey()
	Cars.setActive("balanced")
	local approvedOk, approvedBad, approvedCount = true, {}, 0
	for key, want in APPROVED do
		approvedCount += 1
		local got = C[key]
		if got ~= want then
			approvedOk = false
			table.insert(approvedBad, string.format("%s is %s, was %s", key, tostring(got), tostring(want)))
		end
	end
	check(
		checks,
		"the default car is still the car the user approved",
		approvedOk and Cars.activeKey() == "balanced",
		if approvedOk
			then string.format(
				"all %d of the approved car's numbers unchanged, and `balanced` is still the default",
				approvedCount
			)
			else table.concat(approvedBad, "; ")
	)

	------------------------------------------------------------------ four different cars
	-- The proof that these are four cars and not one car with four labels: the SAME
	-- rolling start and the SAME held finger, and what each settles at. Two strict
	-- orderings have to survive -- how much speed a car keeps through the corner, and how
	-- far round its tail comes -- plus how long each takes to get the tail out at all.
	local HELD = 0.5
	local ENTRY = 140
	local carRows, carRow = {}, {}
	for _, key in Cars.Order do
		Cars.setActive(key)
		local half = hold(HELD, ENTRY, 8)
		local quarter = hold(0.25, ENTRY, 8)
		carRow[key] = { half = half, quarter = quarter }
		table.insert(
			carRows,
			string.format(
				"%s: half finger -> %.1f deg (peak %.1f), %.1f studs/s (%.0f%%), circle %.0f studs, sliding after %s; quarter finger -> %.1f deg, %.1f studs/s, circle %.0f, sliding after %s",
				key,
				half.slip,
				half.peakSlip,
				half.speed,
				100 * half.share,
				math.min(half.radius, 9999),
				if half.slideAt then string.format("%.2f s", half.slideAt) else "NEVER",
				quarter.slip,
				quarter.speed,
				math.min(quarter.radius, 9999),
				if quarter.slideAt then string.format("%.2f s", quarter.slideAt) else "NEVER"
			)
		)
	end
	Cars.setActive(wasCar)

	local keptOrder = { "slider", "balanced", "bruiser", "gripper" } -- least speed kept to most
	local slipOrder = { "bruiser", "gripper", "balanced", "slider" } -- least sideways to most
	local distinct = true
	for i = 2, #keptOrder do
		distinct = distinct and carRow[keptOrder[i]].half.speed > carRow[keptOrder[i - 1]].half.speed + 5
	end
	for i = 2, #slipOrder do
		distinct = distinct and carRow[slipOrder[i]].half.slip > carRow[slipOrder[i - 1]].half.slip + 2
	end
	-- And at a quarter finger the grippy car does not slide at all, where the loose one is
	-- sideways in under a fifth of a second. That gap is the archetypes in one number.
	local function slideTime(key: string): number
		return carRow[key].quarter.slideAt or math.huge
	end
	distinct = distinct
		and carRow.gripper.quarter.slideAt == nil
		and carRow.slider.quarter.slideAt ~= nil
		and slideTime("bruiser") > slideTime("balanced") * 2
		and slideTime("balanced") > slideTime("slider")
	check(
		checks,
		"four archetypes that settle somewhere different from the same start",
		distinct,
		table.concat(carRows, " | ")
	)

	------------------------------------------------------------------ each car's own curve
	-- The grip curve the panel draws is the same `f(b)` the model steps with, for every
	-- car: sampled through the model itself and fitted against that car's own four
	-- numbers. A car whose panel and whose physics disagree is worse than no panel.
	-- Measured through the model at 15 to 89 degrees: a car dead straight has no lateral
	-- axis to read a pull on, and 90 exactly is the edge the model's own cap sits at, so
	-- the two ends of the reported curve are the curve's own values and the five in
	-- between are measured against them.
	local curveOk, curveWorst, curveParts = true, 0, {}
	for _, key in Cars.Order do
		Cars.setActive(key)
		for _, slipDeg in { 15, 30, 45, 60, 89 } do
			local err = math.abs(gripAt(slipDeg, 80).measured - Cars.gripAt(slipDeg))
			curveWorst = math.max(curveWorst, err)
			curveOk = curveOk and err < 0.5
		end
		local sampled = {}
		for _, slipDeg in { 0, 15, 30, 45, 60, 90 } do
			table.insert(sampled, string.format("%d:%.1f", slipDeg, Cars.gripAt(slipDeg)))
		end
		table.insert(curveParts, string.format("%s %s", key, table.concat(sampled, " ")))
	end
	Cars.setActive(wasCar)
	check(
		checks,
		"every car's grip curve is its own four numbers, through the model",
		curveOk,
		string.format(
			"studs/s^2 at 0/15/30/45/60/90 deg of slip -- %s -- worst gap between the drawn curve and the measured pull %.3f",
			table.concat(curveParts, " | "),
			curveWorst
		)
	)

	------------------------------------------------------------------ switching car
	-- It has to take effect on the next step, and switching back has to put the car back
	-- exactly: the model holds nothing from the step before, so the same inputs after a
	-- round trip have to draw the same line to the bit.
	local switchOpts = { fps = 60, start = startCF(TEST_YAW), velocity = ahead(CORNER_ENTRY, TEST_YAW) }
	Cars.setActive("balanced")
	local beforeSwitch = Sim.drive(CORNER, CORNER_SECONDS, switchOpts)
	Cars.setActive("gripper")
	local switched = Sim.drive(CORNER, CORNER_SECONDS, switchOpts)
	local gripperSteer = C.MaxSteeringSpeed
	Cars.setActive("balanced")
	local afterSwitch = Sim.drive(CORNER, CORNER_SECONDS, switchOpts)
	local roundTrip, changed = 0, 0
	for i = 1, math.min(#beforeSwitch, #afterSwitch) do
		roundTrip = math.max(roundTrip, (beforeSwitch[i] - afterSwitch[i]).Magnitude)
		changed = math.max(changed, (beforeSwitch[i] - switched[i]).Magnitude)
	end
	Cars.setActive(wasCar)
	check(
		checks,
		"switching car changes the car, and switching back puts it back",
		changed > 10 and roundTrip < 1e-6 and gripperSteer ~= APPROVED.MaxSteeringSpeed,
		string.format(
			"the same corner moved %.1f studs on the gripper (its rate of turn %.2f rad/s against the default's %.2f) and came back to within %.9f studs of itself",
			changed,
			gripperSteer,
			APPROVED.MaxSteeringSpeed,
			roundTrip
		)
	)

	------------------------------------------------------------------ the bars are marketing
	-- The three display bars are hand-written and NOTHING computes them. The proof is
	-- that they cannot be seen from where the model reads its numbers, and that moving
	-- them to the top of their scale changes not one stud of the line the car draws.
	Cars.setActive("gripper")
	local barsBefore = Sim.drive(CORNER, CORNER_SECONDS, switchOpts)
	local realBars = Cars.Archetypes.Cars.gripper.Bars
	Cars.Archetypes.Cars.gripper.Bars = { Acceleration = 10, Handling = 10, TopSpeed = 10 }
	Cars.setActive("gripper") -- rebuild with the lie in it
	local barsAfter = Sim.drive(CORNER, CORNER_SECONDS, switchOpts)
	Cars.Archetypes.Cars.gripper.Bars = realBars
	Cars.setActive(wasCar)
	local barsMoved = 0
	for i = 1, math.min(#barsBefore, #barsAfter) do
		barsMoved = math.max(barsMoved, (barsBefore[i] - barsAfter[i]).Magnitude)
	end
	check(
		checks,
		"the three display bars reach nothing in the simulation",
		barsMoved == 0 and C.Bars == nil and C.Name == nil and not Cars.isField("Bars"),
		string.format(
			"acceleration, handling and top speed all set to 10 on the gripper: the same corner moved %.9f studs, and Config.Drift cannot see them at all",
			barsMoved
		)
	)

	------------------------------------------------------------------ the split holds
	-- A car number written into the model's table would survive a car switch and quietly
	-- make every car the same, so it is refused outright. A model number still writes.
	local wrote = pcall(function()
		C.MaxSteeringSpeed = 1
	end)
	local modelWrote = pcall(function()
		C.CamVelocityBlend = C.CamVelocityBlend
	end)
	Cars.tune("MaxSteeringSpeed", 1)
	local tunedTo = C.MaxSteeringSpeed
	Cars.untune("MaxSteeringSpeed")
	check(
		checks,
		"a car number cannot be written into the model's table, and tuning puts itself back",
		not wrote and modelWrote and tunedTo == 1 and C.MaxSteeringSpeed == APPROVED.MaxSteeringSpeed and rawget(C, "MaxSteeringSpeed") == nil,
		string.format(
			"Config.Drift.MaxSteeringSpeed = 1 refused, a model number still writes, Cars.tune moved it to %.1f and untune put it back to %.1f",
			tunedTo,
			C.MaxSteeringSpeed
		)
	)

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

	------------------------------------------------------------------ the car is the AE86
	-- The body the simulation drives is the car the user added to the Main place, read out
	-- of it and written down in `Shared/Cars/AE86` (T-020). None of the checks above knows
	-- or cares: the simulation only ever sees five parts at `wheelOffsets()`, and these
	-- are the checks that the shell riding on them is right.
	--
	-- IT IS NO LONGER THE DEFAULT (T-028): `CarBody = "auto"` draws the active
	-- archetype's own body instead, so these checks ask for the AE86 by name. That the
	-- ask still works IS the check that a body can override an archetype's own.
	CarModel.setBody("ae86")
	local ae86 = CarModel.build()
	local shell = ae86:FindFirstChild(CarModel.SHELL_NAME)
	local shellParts = 0
	if shell then
		for _, d in shell:GetDescendants() do
			if d:IsA("BasePart") then
				shellParts += 1
			end
		end
	end
	local simParts = 0
	for _, d in ae86:GetChildren() do
		if d:IsA("BasePart") then
			simParts += 1
		end
	end
	check(
		checks,
		"the car is the AE86, on the five parts the model drives",
		shell ~= nil and shellParts == 98 and simParts == 5,
		if shell
			then `{shellParts} shell parts on {simParts} simulation parts (a body and four wheels), body '{CarModel.bodyName()}'`
			else `no shell: the car fell back to the block (body '{CarModel.bodyName()}'). The meshes would not load`
	)

	-- The config is the car's truth and the model is not: a real car's proportions and
	-- `BodyLength`/`Width`/`Height` cannot both be honoured, so the WHEELS win -- that is
	-- where the ground rays go. The box those three describe is only ever the fallback's
	-- shape, and the numbers below say how far from it the real car is.
	local AE86Data = require(ReplicatedStorage.Shared.Cars.AE86)
	local bodyScale = C.Wheelbase / AE86Data.measured.wheelbase
	local wheelScale = C.WheelDiameter / AE86Data.measured.wheelDiameter
	local shellBody = shell and shell:FindFirstChild(CarModel.BODY_NAME)
	local lo, hi = Vector3.new(1e9, 1e9, 1e9), Vector3.new(-1e9, -1e9, -1e9)
	if shellBody then
		local root = ae86:GetPivot()
		for _, p in shellBody:GetChildren() do
			if p:IsA("BasePart") then
				local local_ = root:ToObjectSpace(p.CFrame)
				local h = p.Size * 0.5
				for i = -1, 1, 2 do
					for j = -1, 1, 2 do
						for k = -1, 1, 2 do
							local pt = local_ * Vector3.new(h.X * i, h.Y * j, h.Z * k)
							lo, hi = lo:Min(pt), hi:Max(pt)
						end
					end
				end
			end
		end
	end
	local size = hi - lo
	check(
		checks,
		"the model is scaled onto the config, not the config onto the model",
		shellBody ~= nil
			and math.abs(size.Z - AE86Data.measured.bodyLength * bodyScale) < 0.01
			and math.abs(bodyScale - wheelScale) < 0.05,
		string.format(
			"wheelbase %.1f / %.4f = x%.5f on the body, wheel %.1f / %.4f = x%.5f on the wheels; "
				.. "the car comes out %.2f x %.2f x %.2f against the config's box of %.1f x %.1f x %.1f (W x H x L)",
			C.Wheelbase,
			AE86Data.measured.wheelbase,
			bodyScale,
			C.WheelDiameter,
			AE86Data.measured.wheelDiameter,
			wheelScale,
			size.X,
			size.Y,
			size.Z,
			C.BodyWidth,
			C.BodyHeight,
			C.BodyLength
		)
	)

	-- Placed by `Render`, exactly as the game places it, on a road at y = 0.
	local rig = Render.rig(ae86)
	local onRoad = CFrame.new(0, C.RideHeight, 0)
	Render.place(rig, onRoad, 0, 0, 0)
	local gaps, worstGap = {}, 0
	for _, name in CarModel.WHEEL_NAMES do
		local group = shell and shell:FindFirstChild(name)
		local tyre = group and group:FindFirstChild("Tire")
		if tyre and tyre:IsA("BasePart") then
			-- the tyre's thin axis is its own Y; its diameter is X and Z, and the axle is
			-- horizontal, so the lowest point is the centre less the radius
			local gap = tyre.Position.Y - tyre.Size.X * 0.5
			table.insert(gaps, string.format("%s %+.4f", string.sub(name, 6), gap))
			worstGap = math.max(worstGap, math.abs(gap))
		end
	end
	check(
		checks,
		"every wheel sits on the road",
		#gaps == 4 and worstGap < 0.01,
		`gap in studs at each corner, road at y = 0: {table.concat(gaps, ", ")}`
	)

	-- The wheels turn, and only the front pair points anywhere. Read back off the shell
	-- parts themselves, not off anything the placement was told.
	local byName = {}
	for _, wheel in rig.wheels do
		byName[wheel.part.Name] = wheel
	end
	local steerRead, spinRead = {}, {}
	local steerOk, steerSeen = true, 0
	for _, angle in { -25, 0, 25 } do
		Render.place(rig, onRoad, math.rad(angle), 0, 0)
		local reads = {}
		for _, name in CarModel.WHEEL_NAMES do
			local frame = byName[name] and Render.shellFrame(byName[name].shell)
			if frame then
				local _, yaw = onRoad:ToObjectSpace(frame):ToOrientation()
				local want = if CarModel.isFrontWheel(name) then angle else 0
				steerOk = steerOk and math.abs(math.deg(yaw) - want) < 0.1
				steerSeen += 1
				table.insert(reads, string.format("%s %+.1f", string.sub(name, 6), math.deg(yaw)))
			end
		end
		table.insert(steerRead, string.format("asked %+d deg -> %s", angle, table.concat(reads, " ")))
	end
	check(
		checks,
		"the front wheels steer and the rear pair does not",
		steerOk and steerSeen == 12,
		table.concat(steerRead, " | ")
	)

	-- Spin is read as the pitch of the wheel about its own axle, so it is measured inside
	-- a quarter turn either way -- past that the Euler read-back folds and says nothing.
	local spinOk, spinSeen = true, 0
	for _, spin in { 0, 45, 85 } do
		Render.place(rig, onRoad, 0, math.rad(spin), 0)
		local frame = byName.WheelRL and Render.shellFrame(byName.WheelRL.shell)
		if frame then
			local pitch = select(1, onRoad:ToObjectSpace(frame):ToOrientation())
			spinOk = spinOk and math.abs(math.deg(pitch) - spin) < 0.1
			spinSeen += 1
			table.insert(spinRead, string.format("spin %+d deg -> RL reads %+.1f", spin, math.deg(pitch)))
		end
	end
	check(
		checks,
		"the wheels turn with the car's travel",
		spinOk and spinSeen == 3,
		table.concat(spinRead, ", ")
	)
	ae86:Destroy()
	CarModel.setBody(nil)

	-- And the block is still buildable, because a place whose meshes will not load still
	-- has to run.
	CarModel.setBody("block")
	local block = CarModel.build()
	local blockParts = 0
	for _, d in block:GetDescendants() do
		if d:IsA("BasePart") then
			blockParts += 1
		end
	end
	local blockOk, blockDetail = offenderReport(block)
	local blockHasShell = block:FindFirstChild(CarModel.SHELL_NAME) ~= nil
	block:Destroy()
	CarModel.setBody(nil)
	check(
		checks,
		"the block car is still there as the fallback",
		blockParts == 5 and not blockHasShell and blockOk,
		`setBody("block") builds {blockParts} parts and no shell -- {blockDetail}`
	)

	------------------------------------------------------------------ a body per archetype
	-- Four shapes, one builder, no assets: `Shared/Cars/Bodies` turns a table of boxes and
	-- wedges into the same `Shell` the AE86 makes, one per archetype, and `CarBody =
	-- "auto"` draws whichever archetype is being driven (T-028). A fifth body is a table.
	--
	-- THE ART NEVER MOVES THE MODEL. `Wheelbase`, `TrackWidth`, `WheelDiameter` and
	-- `RideHeight` are the archetype's and are where the ground rays go; a body is built
	-- around them. The checks below measure that from the other end -- the wheels, on the
	-- road, at the offsets the simulation rays from -- rather than trusting it.
	local function lowestY(g: Instance?): number
		local low = 1e9
		if g then
			for _, p in g:GetDescendants() do
				if p:IsA("BasePart") then
					local h = p.Size * 0.5
					for i = -1, 1, 2 do
						for j = -1, 1, 2 do
							for k = -1, 1, 2 do
								low = math.min(low, (p.CFrame * Vector3.new(h.X * i, h.Y * j, h.Z * k)).Y)
							end
						end
					end
				end
			end
		end
		return low
	end

	local dims, shapeRows = {}, {}
	local shapesOk, cleanOk, gapOk = true, true, true
	local cleanRows, gapRows = {}, {}
	local onRoadAt = CFrame.new(0, C.RideHeight, 0)
	for _, key in Bodies.Order do
		CarModel.setBody(key)
		local car = CarModel.build()
		local carShell = car:FindFirstChild(CarModel.SHELL_NAME)
		local group = carShell and carShell:FindFirstChild(CarModel.BODY_NAME)
		local lo, hi = Bodies.bounds(group)
		local parts = 0
		for _, p in car:GetDescendants() do
			if p:IsA("BasePart") then
				parts += 1
			end
		end
		local roofPart = group and group:FindFirstChild("Roof")
		local roof = hi.Y + C.RideHeight
		if roofPart and roofPart:IsA("BasePart") then
			roof = roofPart.Position.Y + roofPart.Size.Y * 0.5 + C.RideHeight
		end
		local row = {
			key = key,
			length = hi.Z - lo.Z,
			width = hi.X - lo.X,
			height = hi.Y - lo.Y,
			top = hi.Y + C.RideHeight,
			roof = roof,
			parts = parts,
		}
		table.insert(dims, row)
		shapesOk = shapesOk and carShell ~= nil and group ~= nil and parts >= 20
		table.insert(
			shapeRows,
			string.format(
				"%s %.2f x %.2f x %.2f (L x W x H), roof %.2f, %d parts",
				key,
				row.length,
				row.width,
				row.height,
				row.roof,
				parts
			)
		)

		-- anchored, nothing that moves it, nothing that runs
		local ok, detail = offenderReport(car)
		cleanOk = cleanOk and ok
		table.insert(cleanRows, if ok then `{key}: {parts} parts clean` else `{key}: {detail}`)

		-- and on the road, placed exactly as the game places it
		local rig = Render.rig(car)
		Render.place(rig, onRoadAt, 0, 0, 0)
		local worst = 0
		local corners = {}
		for _, name in CarModel.WHEEL_NAMES do
			local gap = lowestY(carShell and carShell:FindFirstChild(name))
			worst = math.max(worst, math.abs(gap))
			table.insert(corners, string.format("%s %+.4f", string.sub(name, 6), gap))
		end
		gapOk = gapOk and worst < 0.01
		table.insert(gapRows, `{key}: {table.concat(corners, " ")}`)

		car:Destroy()
	end
	CarModel.setBody(nil)

	-- No two of them are the same shape, and you could tell them apart from behind: every
	-- pair differs by at least half a stud in length, width or roof height.
	local closest, closestPair = 1e9, ""
	for i = 1, #dims do
		for j = i + 1, #dims do
			local a, b = dims[i], dims[j]
			local apart = math.max(
				math.abs(a.length - b.length),
				math.abs(a.width - b.width),
				math.abs(a.roof - b.roof)
			)
			if apart < closest then
				closest, closestPair = apart, `{a.key}/{b.key}`
			end
		end
	end
	check(
		checks,
		"every archetype has a body of its own, and no two are the same shape",
		shapesOk and #dims == 4 and closest > 0.5,
		`{table.concat(shapeRows, " | ")} -- the closest pair is {closestPair}, {string.format("%.2f", closest)} studs apart`
	)

	check(checks, "a parts body holds no physics object and nothing that runs", cleanOk, table.concat(cleanRows, " | "))

	check(
		checks,
		"every wheel sits on the road, on all four bodies",
		gapOk,
		`gap in studs at each corner, road at y = 0: {table.concat(gapRows, " | ")}`
	)

	-- The geometry is the model's. Stretch the wheelbase and the BODY follows it, because
	-- the wheels it has to sit between have moved; the body never asks the wheels to move
	-- to suit it. (Geometry is read when a car MODEL is built, so this only ever lands on
	-- the next respawn -- `Shared/Cars`, `setActive`.)
	CarModel.setBody("balanced")
	local baseShell = CarModel.shell()
	local baseLo, baseHi = Bodies.bounds(baseShell:FindFirstChild(CarModel.BODY_NAME))
	baseShell:Destroy()
	local stretchedZ, stretchedX = 0, 0
	local stretchedWheel = Vector3.zero
	Cars.withTuning({ Wheelbase = C.Wheelbase * 1.5, TrackWidth = C.TrackWidth * 1.25 }, function()
		local s = CarModel.shell()
		local lo2, hi2 = Bodies.bounds(s:FindFirstChild(CarModel.BODY_NAME))
		stretchedZ, stretchedX = hi2.Z - lo2.Z, hi2.X - lo2.X
		s:Destroy()
		stretchedWheel = CarModel.wheelOffsets().WheelRR
	end)
	CarModel.setBody(nil)
	local wantZ = (baseHi.Z - baseLo.Z) * 1.5
	local wantX = (baseHi.X - baseLo.X) * 1.25
	check(
		checks,
		"a body is built around the model's geometry, not the other way round",
		math.abs(stretchedZ - wantZ) < 0.01 and math.abs(stretchedX - wantX) < 0.01,
		string.format(
			"wheelbase %.1f -> %.1f stretches the body %.2f -> %.2f studs long (wanted %.2f); "
				.. "track %.1f -> %.1f widens it %.2f -> %.2f (wanted %.2f); the rear wheel the rays go from is at %s",
			C.Wheelbase,
			C.Wheelbase * 1.5,
			baseHi.Z - baseLo.Z,
			stretchedZ,
			wantZ,
			C.TrackWidth,
			C.TrackWidth * 1.25,
			baseHi.X - baseLo.X,
			stretchedX,
			wantX,
			tostring(stretchedWheel)
		)
	)

	-- And the switch itself: the car the player picks picks the shape, unless the config
	-- says otherwise.
	local wasCar = Cars.activeKey()
	local wasBody = C.CarBody
	local autoRows, autoOk = {}, true
	C.CarBody = CarModel.AUTO
	for _, key in Bodies.Order do
		Cars.setActive(key)
		local drawn = CarModel.bodyName()
		autoOk = autoOk and drawn == key
		table.insert(autoRows, `{key} -> {drawn}`)
	end
	C.CarBody = "ae86"
	local overrideRows, overrideOk = {}, true
	for _, key in Bodies.Order do
		Cars.setActive(key)
		local drawn = CarModel.bodyName()
		overrideOk = overrideOk and drawn == "ae86"
		table.insert(overrideRows, `{key} -> {drawn}`)
	end
	C.CarBody = wasBody
	Cars.setActive(wasCar)
	check(
		checks,
		"switching car switches the shape, and CarBody still overrides it",
		autoOk and overrideOk and CarModel.bodyName() == Cars.activeKey(),
		`CarBody "auto": {table.concat(autoRows, ", ")} | CarBody "ae86": {table.concat(overrideRows, ", ")} | `
			.. `back to "{tostring(wasBody)}" on '{Cars.activeKey()}', drawing '{CarModel.bodyName()}'`
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

-- Studio only, and no part of `run()`: switch the SERVER's active car and re-dress every
-- live car with that archetype's body, so a playtest can be driven on more than one shape
-- without rejoining (T-028).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugDriftTests", "useCar", "bruiser")
--
-- The client keeps its own active car, because the two are deliberately separate
-- (features/car-archetypes.md, "Server and client"): this moves the SHAPE a tester sees
-- and leaves the feel to F4. Re-dressing from the SERVER is the half that holds -- the
-- client's own copy does not, because the server pivots each car as its state arrives and
-- that restores anything the client deleted.
function DriftTests:useCar(key: string): string
	Cars.setActive(key)
	local cars = workspace:FindFirstChild("Cars")
	local n = 0
	if cars then
		for _, car in cars:GetChildren() do
			if car:IsA("Model") then
				CarModel.dress(car, CarModel.shell())
				n += 1
			end
		end
	end
	return `{key}: {n} live car(s) now wearing '{CarModel.bodyName()}'`
end

return DriftTests
