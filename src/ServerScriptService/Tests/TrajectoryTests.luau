--!nonstrict
-- TrajectoryTests: is the projected line actually where the car goes, and what does it
-- cost (T-032)?
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugTrajectoryTests", "run")
--
-- THE CHECK THAT MATTERS IS THE FIRST TWO. A prediction that does not match the car is
-- worse than no prediction at all, so the line predicted at t=0 is measured against where
-- the car really went over the following second or two -- straight and mid-drift -- and
-- the deviation is reported in studs two ways:
--
--   along-track  the predicted point at `d` studs of path against the ACTUAL point at `d`
--                studs of path. Shape and progress together: this is the honest number
--   cross-track  the shortest distance from the predicted point to the actual path. Shape
--                only, and it is the one a player's eye judges the line by
--
-- The deviation is not zero and cannot be: the prediction runs at `TrajectoryStep`
-- (1/30) where the car runs at `FixedStep` (1/120), which is the trade that makes drawing
-- it affordable at all (Drift/Trajectory header). What these checks pin is how much that
-- trade costs.
--
-- Nothing here needs a car, a player or a playtest for the flat-world checks: the model
-- is pure. The live-Workspace check uses whatever world the place has, and is skipped in
-- an edit session with nothing in it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "TrajectoryTests only runs in Studio")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)

local PlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local DriftFolder = PlayerScripts:WaitForChild("Drift")

local TrajectoryTests = {}

local C = Config.Drift

-- A car travelling exactly along a world axis has no speed on the perpendicular axis for
-- the model's per-axis clamp to allow, which suppresses the sideways pull until it has
-- yawed far enough to build one (features/drift-model.md "Grip"). A player is never in
-- that state; a test that starts at a heading of zero is. So every run starts at 15 deg,
-- exactly as DriftTests does.
local TEST_YAW = math.rad(15)

-- Loaded on the first call, not here: Studio caches a ModuleScript's result for the whole
-- session, so a session that required these before Lync synced a change would measure the
-- old copy (the same reason JitterTests does it).
local Model, Sim, World, Trajectory

local function load()
	Model = require(DriftFolder.Model)
	Sim = require(DriftFolder.Sim)
	World = require(DriftFolder.World)
	Trajectory = require(DriftFolder.Trajectory)
end

local function check(checks, name, ok, detail)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
	return ok == true
end

local function startCF(yaw: number?): CFrame
	local cf = CFrame.new(0, C.RideHeight, 0)
	return if yaw then cf * CFrame.Angles(0, yaw, 0) else cf
end

local function ahead(speed: number, yaw: number?): Vector3
	return Model.axes(yaw or 0) * speed
end

--------------------------------------------------------------------------------
-- comparing two paths
--------------------------------------------------------------------------------

local function cumulative(points: { Vector3 }): { number }
	local out = { 0 }
	for i = 2, #points do
		out[i] = out[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	return out
end

-- The point `d` studs along a path, interpolated between its samples.
local function along(points: { Vector3 }, cum: { number }, d: number): Vector3
	if d <= 0 then
		return points[1]
	end
	for i = 2, #points do
		if cum[i] >= d then
			local span = cum[i] - cum[i - 1]
			local t = if span > 1e-9 then (d - cum[i - 1]) / span else 0
			return points[i - 1]:Lerp(points[i], t)
		end
	end
	return points[#points]
end

-- The shortest distance from `p` to the polyline, by projection onto each segment.
local function nearest(points: { Vector3 }, p: Vector3): number
	local best = math.huge
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local ab = b - a
		local len2 = ab:Dot(ab)
		local t = if len2 > 1e-9 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
		best = math.min(best, (p - (a + ab * t)).Magnitude)
	end
	return best
end

-- Predicted against actual: worst along-track and worst cross-track deviation, in studs.
-- Only the part of the predicted line the actual drive is long enough to cover is
-- compared -- comparing past the end of the actual path would measure the test's own
-- length, not the prediction.
local function deviation(predicted: { Vector3 }, actual: { Vector3 })
	local pc, ac = cumulative(predicted), cumulative(actual)
	local reach = ac[#ac]
	local worstAlong, worstCross, compared = 0, 0, 0
	for i = 1, #predicted do
		if pc[i] > reach then
			break
		end
		compared += 1
		worstAlong = math.max(worstAlong, (predicted[i] - along(actual, ac, pc[i])).Magnitude)
		worstCross = math.max(worstCross, nearest(actual, predicted[i]))
	end
	return {
		along = worstAlong,
		cross = worstCross,
		compared = compared,
		points = #predicted,
		predictedLength = pc[#pc],
		actualLength = reach,
	}
end

-- The radius of the circle through the first, middle and last point of a line: how tightly
-- the car is predicted to come round. Infinite for a line with no curve in it at all.
local function radiusOf(points: { Vector3 }): number
	if #points < 3 then
		return math.huge
	end
	local a, b, c = points[1], points[(#points + 1) // 2], points[#points]
	local ab, bc, ca = (b - a).Magnitude, (c - b).Magnitude, (a - c).Magnitude
	-- Twice the triangle's area, in the horizontal plane
	local area2 = math.abs((b.X - a.X) * (c.Z - a.Z) - (c.X - a.X) * (b.Z - a.Z))
	if area2 < 1e-6 then
		return math.huge
	end
	return (ab * bc * ca) / (2 * area2)
end

-- How far round a line comes, in degrees: the angle from its first segment to its last.
-- A better question than the radius for "is this line straight", because a line that is
-- straight has no circle through it to measure.
local function turnOf(points: { Vector3 }): number
	if #points < 3 then
		return 0
	end
	local a = points[2] - points[1]
	local b = points[#points] - points[#points - 1]
	if a.Magnitude < 1e-6 or b.Magnitude < 1e-6 then
		return 0
	end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

--------------------------------------------------------------------------------
-- running the real car
--------------------------------------------------------------------------------

-- Drive the live model with `steer` held, from a rolling start, and return the runner and
-- the path it took at full simulation resolution (every step, 1/120). This is THE CAR;
-- everything else here is measured against it.
local function drive(steer: number, seconds: number, speed: number, world, state)
	local runner = Sim.newRunner(startCF(TEST_YAW))
	if state then
		runner.state = state
	else
		runner.state.velocity = ahead(speed, TEST_YAW)
	end
	local path = { runner.state.position }
	local input = { steer = steer, handbrake = false }
	local elapsed = 0
	local frame = C.FixedStep * C.MaxStepsPerFrame
	while elapsed < seconds - 1e-9 do
		local dt = math.min(frame, seconds - elapsed)
		Sim.advance(runner, dt, input, world, function(s)
			path[#path + 1] = s.position
		end)
		elapsed += dt
	end
	return runner, path
end

-- Copy a state the way the test wants to copy it, which is NOT the way Trajectory does:
-- this one is only ever used to hand the same starting point to two drives.
local function copyState(s)
	local out = table.clone(s)
	for key, value in out do
		if type(value) == "table" then
			out[key] = table.clone(value)
		end
	end
	return out
end

-- Is this state the same as that one, field for field?
local function sameState(a, b): (boolean, string?)
	for key, value in a do
		local other = b[key]
		if type(value) == "table" then
			for i, v in value do
				if other[i] ~= v then
					return false, `{key}[{i}]`
				end
			end
		elseif typeof(value) == "Vector3" then
			if (value - other).Magnitude > 1e-9 then
				return false, key
			end
		elseif type(value) == "number" then
			if math.abs(value - other) > 1e-9 then
				return false, key
			end
		elseif value ~= other then
			return false, key
		end
	end
	return true, nil
end

-- Milliseconds one prediction costs, averaged over `n` of them.
local function costMs(state, input, n: number, world): number
	local began = os.clock()
	for _ = 1, n do
		Trajectory.predict(state, input, { world = world })
	end
	return (os.clock() - began) * 1000 / n
end

--------------------------------------------------------------------------------

function TrajectoryTests:run()
	load()
	local checks = {}
	local flat = World.flat(0)
	local target = C.TrajectoryCarLengths * C.BodyLength

	------------------------------------------------------------------ straight
	-- The simplest case, and the one with nowhere to hide: the line is the car's own
	-- future, so with the finger centred it has to lie on top of where the car goes.
	do
		local warm = drive(0, 0.5, 100, flat)
		local at = copyState(warm.state)
		local prediction = Trajectory.predict(at, { steer = 0 })
		local _, actual = drive(0, 4, 0, flat, copyState(at))
		local d = deviation(prediction.points, actual)
		check(
			checks,
			"the line is the car, straight",
			d.along < 1 and d.cross < 0.5 and d.compared >= 2,
			string.format(
				"%.3f studs worst along-track, %.3f cross-track, over %.1f studs of line (%d of %d points compared, %.0f studs/s)",
				d.along,
				d.cross,
				d.predictedLength,
				d.compared,
				d.points,
				Model.speed(at)
			)
		)
	end

	------------------------------------------------------------------ mid-drift
	-- The case that could go wrong: the car is sideways, the grip is hauling the velocity
	-- round, and the prediction is taking it four times as coarsely as the car does.
	local driftDeviation
	do
		local warm = drive(0.5, 1.2, 140, flat)
		local at = copyState(warm.state)
		local prediction = Trajectory.predict(at, { steer = 0.5 })
		local _, actual = drive(0.5, 8, 0, flat, copyState(at))
		driftDeviation = deviation(prediction.points, actual)
		check(
			checks,
			"the line is the car, mid-drift",
			driftDeviation.along < 6 and driftDeviation.cross < 3 and driftDeviation.compared >= 2,
			string.format(
				"%.2f studs worst along-track, %.2f cross-track, over %.1f studs of line (%d points, %.1f deg of slip, %.0f studs/s at the start of it)",
				driftDeviation.along,
				driftDeviation.cross,
				driftDeviation.predictedLength,
				driftDeviation.points,
				math.deg(at.slip),
				Model.speed(at)
			)
		)
	end

	------------------------------------------------------------------ the same step, no error
	-- Proof that the deviation above IS the coarse step and nothing else: predict at the
	-- model's own `FixedStep` and the line and the car are the same thing to a thousandth.
	do
		local warm = drive(0.5, 1.2, 140, flat)
		local at = copyState(warm.state)
		local prediction = Trajectory.predict(at, { steer = 0.5, handbrake = false }, { step = C.FixedStep })
		local _, actual = drive(0.5, 8, 0, flat, copyState(at))
		local d = deviation(prediction.points, actual)
		check(
			checks,
			"the coarse step is the whole of the error",
			d.along < 0.01,
			string.format(
				"at FixedStep (1/120) the same drift predicts to %.5f studs along-track and %.5f cross-track; at TrajectoryStep (1/%.0f) it is %.2f and %.2f",
				d.along,
				d.cross,
				1 / C.TrajectoryStep,
				driftDeviation.along,
				driftDeviation.cross
			)
		)
	end

	------------------------------------------------------------------ it does not touch the car
	-- The one bug in here that would be a nightmare to find: `Model.step` mutates what it
	-- is handed, so a prediction that shared the live state would drive the car.
	do
		local warm = drive(0.4, 1, 120, flat)
		local before = copyState(warm.state)
		Trajectory.predict(warm.state, { steer = 0.4 })
		local same, field = sameState(before, warm.state)

		-- And the same thing the way a player would meet it: a scripted drive with a
		-- prediction taken every frame against one with none.
		local quiet = drive(0.4, 3, 120, flat)
		local loud = Sim.newRunner(startCF(TEST_YAW))
		loud.state.velocity = ahead(120, TEST_YAW)
		local input = { steer = 0.4, handbrake = false }
		local elapsed = 0
		while elapsed < 3 - 1e-9 do
			local dt = math.min(1 / 60, 3 - elapsed)
			Sim.advance(loud, dt, input, flat)
			Trajectory.predict(loud.state, input)
			elapsed += dt
		end
		local gap = (quiet.state.position - loud.state.position).Magnitude
		check(
			checks,
			"predicting does not disturb the car",
			same and gap < 1e-3,
			string.format(
				"every field of the live state unchanged by a prediction (%s), and a 3 s drive with the line on ends %.6f studs from the same drive with it off",
				field or "no field moved",
				gap
			)
		)
	end

	------------------------------------------------------------------ ten car lengths
	do
		local warm = drive(0, 0.5, 100, flat)
		local prediction = Trajectory.predict(copyState(warm.state), { steer = 0 })
		local overshoot = prediction.length - target
		check(
			checks,
			"ten car lengths of path, not a fixed time",
			overshoot >= 0 and overshoot < C.TrajectoryPointSpacing + 2 and not prediction.stopped,
			string.format(
				"%.1f studs of line against a target of %.1f (%d x BodyLength %.1f), %d steps, %.2f s simulated at %.0f studs/s",
				prediction.length,
				target,
				C.TrajectoryCarLengths,
				C.BodyLength,
				prediction.steps,
				prediction.seconds,
				Model.speed(warm.state)
			)
		)
	end

	------------------------------------------------------------------ length is distance, not time
	-- Two speeds, one length: that is what walking by distance buys.
	do
		local slow = drive(0, 0.5, 40, flat)
		local fast = drive(0, 0.5, 160, flat)
		local a = Trajectory.predict(copyState(slow.state), { steer = 0 })
		local b = Trajectory.predict(copyState(fast.state), { steer = 0 })
		check(
			checks,
			"the line is the same length at any speed",
			math.abs(a.length - b.length) < C.TrajectoryPointSpacing + 2,
			string.format(
				"%.1f studs at %.0f studs/s (%.2f s of simulation) against %.1f studs at %.0f (%.2f s)",
				a.length,
				Model.speed(slow.state),
				a.seconds,
				b.length,
				Model.speed(fast.state),
				b.seconds
			)
		)
	end

	------------------------------------------------------------------ a stopped car
	do
		local still = Model.new(startCF(TEST_YAW))
		local prediction = Trajectory.predict(still, { steer = 0, handbrake = true })
		check(
			checks,
			"a stopped car stops the walk",
			prediction.stopped and prediction.steps <= 3 and prediction.length < 1,
			string.format(
				"%d steps, %.3f studs of line, stopped early: %s",
				prediction.steps,
				prediction.length,
				tostring(prediction.stopped)
			)
		)
	end

	------------------------------------------------------------------ it follows the finger
	-- Centring the finger straightens the line, on the very next prediction: the model's
	-- yaw rate IS the finger, so there is nothing to ease.
	do
		-- From a car going straight: push the finger and the line bends, centre it and the
		-- line is straight again -- in the very next prediction, because the model's yaw
		-- rate IS the finger and there is nothing to ease.
		local straight = copyState(drive(0, 1, 140, flat).state)
		local pushed = Trajectory.predict(straight, { steer = 0.6 })
		local centred = Trajectory.predict(straight, { steer = 0 })
		local pushedTurn, centredTurn = turnOf(pushed.points), turnOf(centred.points)
		local straightGap = (pushed.points[#pushed.points] - centred.points[#centred.points]).Magnitude

		-- And from mid-drift, which is where it matters: the line is not a straight-line
		-- guess, so centring in the middle of a slide has to change it too.
		local sliding = copyState(drive(0.5, 1.2, 140, flat).state)
		local held = Trajectory.predict(sliding, { steer = 0.5 })
		local let = Trajectory.predict(sliding, { steer = 0 })
		local driftGap = (held.points[#held.points] - let.points[#let.points]).Magnitude

		check(
			checks,
			"centring the finger straightens the line",
			-- The LINE's own bend, not the car's heading: at a finger of 0.6 the car's nose
			-- comes round 60 deg over this line and its travel only 10, because that gap IS
			-- the drift. So the test is that the pushed line bends and the centred one does
			-- not, by an order of magnitude, not that either turns some absolute amount.
			centredTurn < 2
				and pushedTurn > 10 * centredTurn
				and straightGap > C.BodyLength * 0.5
				and driftGap > C.BodyLength * 0.5,
			string.format(
				"from a car going straight, the same state predicted twice: %.1f deg of turn in the line with the finger at 0.6, %.2f deg with it centred, and the two end %.1f studs apart. Mid-drift (%.0f deg of slip) they end %.1f studs apart",
				pushedTurn,
				centredTurn,
				straightGap,
				math.deg(sliding.slip),
				driftGap
			)
		)
	end

	------------------------------------------------------------------ it follows the car
	-- The archetype is read through `Config.Drift` on every step, so the line changes with
	-- F4 without one line of Trajectory knowing cars exist (Shared/Cars).
	do
		local was = Cars.activeKey()
		local radii, turns, ends = {}, {}, {}
		for _, key in { "gripper", "slider" } do
			Cars.setActive(key)
			-- Each car warmed up straight at the same speed, then handed the same finger:
			-- what is left between them is the car.
			local warm = drive(0, 1, 140, flat)
			local prediction = Trajectory.predict(copyState(warm.state), { steer = 0.4 })
			radii[key] = radiusOf(prediction.points)
			turns[key] = turnOf(prediction.points)
			ends[key] = prediction.points[#prediction.points]
		end
		Cars.setActive(was)
		local apart = (ends.gripper - ends.slider).Magnitude
		check(
			checks,
			"the line follows the active car",
			apart > C.BodyLength and math.abs(radii.gripper - radii.slider) > 2,
			string.format(
				"the same finger from the same straight run: gripper draws a %.1f stud radius turning %.1f deg, slider %.1f studs turning %.1f deg -- the two lines end %.1f studs apart",
				radii.gripper,
				turns.gripper,
				radii.slider,
				turns.slider,
				apart
			)
		)
	end

	------------------------------------------------------------------ the live Workspace
	-- The expensive mode, and the measurement of what the cheap one costs. A flat plane
	-- does not know about a crest, a ramp or a wall, so the gap between the two lines IS
	-- the trade `TrajectoryFlat` makes (Drift/Trajectory header).
	do
		local cars = workspace:FindFirstChild("Cars")
		local live = World.live(if cars then { cars } else {})
		local warm = drive(0.3, 1, 120, live)
		local at = copyState(warm.state)
		local input = { steer = 0.3, handbrake = false }
		local predictedLive = Trajectory.predict(at, input, { world = live })
		local predictedFlat = Trajectory.predict(at, input)
		local _, actual = drive(0.3, 8, 0, live, copyState(at))
		local d = deviation(predictedLive.points, actual)
		local trade = deviation(predictedFlat.points, actual)
		live.destroy()
		check(
			checks,
			"against the live Workspace it is the car too",
			d.along < 15 and d.cross < 8,
			string.format(
				"predicting against the real world: %.2f studs along-track, %.2f cross-track. The same line predicted against a flat plane (the default): %.2f and %.2f -- that gap is what TrajectoryFlat costs in this place",
				d.along,
				d.cross,
				trade.along,
				trade.cross
			)
		)
	end

	------------------------------------------------------------------ what it costs
	-- A debug line that costs more than a millisecond a frame is not worth having.
	local costs = {}
	do
		local still = Model.new(startCF(TEST_YAW))
		local straight = drive(0, 0.5, 100, flat)
		local drifting = drive(0.5, 1.2, 140, flat)
		costs.standstill = costMs(still, { steer = 0 }, 200)
		costs.straight = costMs(straight.state, { steer = 0 }, 200)
		costs.drifting = costMs(drifting.state, { steer = 0.5 }, 200)

		local cars = workspace:FindFirstChild("Cars")
		local live = World.live(if cars then { cars } else {})
		costs.liveWorld = costMs(straight.state, { steer = 0 }, 50, live)
		live.destroy()

		check(
			checks,
			"it costs under a millisecond a frame",
			costs.straight < 1 and costs.drifting < 1 and costs.standstill < 1,
			string.format(
				"%.3f ms a prediction at a standstill, %.3f driving straight, %.3f mid-drift -- and %.3f against the live Workspace, which is what TrajectoryFlat = false costs",
				costs.standstill,
				costs.straight,
				costs.drifting,
				costs.liveWorld
			)
		)
	end

	------------------------------------------------------------------ off by default
	do
		local line = Trajectory.new()
		local before = #workspace:GetChildren()
		local still = drive(0, 0.5, 100, flat)
		line:Update(still.state, { steer = 0 }, 1 / 60)
		local whileOff = #workspace:GetChildren()
		line:SetEnabled(true)
		line:Update(still.state, { steer = 0 }, 1 / 60)
		local folder = workspace:FindFirstChild(C.TrajectoryFolder)
		local parts = if folder then #folder:GetChildren() else 0
		local reported = line:DebugState()
		line:SetEnabled(false)
		local after = #workspace:GetChildren()
		local gone = workspace:FindFirstChild(C.TrajectoryFolder) == nil
		line:Destroy()
		check(
			checks,
			"off by default, and it leaves nothing behind",
			C.TrajectoryLine == false
				and whileOff == before
				and parts > 0
				and gone
				and after == before
				and reported.segments > 0,
			string.format(
				"TrajectoryLine is %s; switched off it draws nothing (%d children of Workspace, unchanged); on it draws %d parts in %s for %d segments; off again the folder is gone and Workspace is back to %d",
				tostring(C.TrajectoryLine),
				whileOff,
				parts,
				C.TrajectoryFolder,
				reported.segments,
				after
			)
		)
	end

	------------------------------------------------------------------ the pool is reused
	do
		local line = Trajectory.new()
		line:SetEnabled(true)
		local straight = drive(0, 0.5, 100, flat)
		local drifting = drive(0.6, 1.2, 140, flat)
		line:Update(straight.state, { steer = 0 }, 1 / 60)
		local folder = workspace:FindFirstChild(C.TrajectoryFolder)
		local first = #folder:GetChildren()
		local identity = folder:GetChildren()[1]
		for _ = 1, 30 do
			line:Update(drifting.state, { steer = 0.6 }, 1 / 60)
			line:Update(straight.state, { steer = 0 }, 1 / 60)
		end
		local grown = #folder:GetChildren()
		local same = folder:GetChildren()[1] == identity
		local sane = true
		for _, part in folder:GetChildren() do
			sane = sane
				and part.Anchored
				and not part.CanCollide
				and not part.CanQuery
				and not part.CanTouch
				and part:IsDescendantOf(workspace)
				and not part:IsDescendantOf(workspace:FindFirstChild("Cars") or workspace)
		end
		line:Destroy()
		check(
			checks,
			"the parts are reused, not rebuilt",
			same and grown <= C.TrajectoryMaxSegments and sane,
			string.format(
				"%d parts after the first draw, %d after 60 more, the same instances throughout (%s); every one anchored, CanCollide/CanQuery/CanTouch off and outside Workspace.Cars (%s)",
				first,
				grown,
				tostring(same),
				tostring(sane)
			)
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, costs = costs }
end

return TrajectoryTests
