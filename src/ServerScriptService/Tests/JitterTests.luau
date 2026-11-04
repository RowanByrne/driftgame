--!nonstrict
-- JitterTests: where a visible wobble in the car comes from, measured (T-025).
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugJitterTests", "run")
--   game.ServerStorage.DebugBridge:Invoke("DebugJitterTests", "report")
--
-- THE EYE SEES THE SECOND DIFFERENCE. A camera panning smoothly and a car moving smoothly
-- both have a large first difference (studs per frame) and a tiny second one (the change
-- in that, frame to frame). Judder is the second difference: the thing creeps, then snaps.
-- So every number below is a second difference of something sampled ONCE A FRAME, which is
-- the only rate at which a player can see anything.
--
-- Four things are sampled each frame, and they answer different questions:
--
--   car      where Render would draw the car's body
--   camera   where CarCameraController would put the camera
--   screen   the angle from the camera's own look axis to the drawn car -- what the player
--            actually watches, and the only one of the four that can be zero while the
--            other two are not (car and camera juddering together cancel out)
--   lag      how far the drawn car is from where the simulation really has it at the
--            moment the frame is drawn, which is the chord between the two steps the
--            frame falls between. This is what says a smoothing has not been bought with
--            lateness.
--
-- THE TRAP IN MEASURING THIS AT 30, 60 AND 120 FPS. The model steps at 1/120, and those
-- three rates all divide it exactly: hand the accumulator a dead-steady 1/60 and it spends
-- exactly two steps every frame with nothing left over, for ever, and the worst judder in
-- the game measures a flat zero. No machine has a dead-steady frame clock, and no machine
-- runs at exactly 120 either. So every scenario is measured three ways -- exact frames, a
-- frame clock with real jitter in it, and a rate that does not divide the step -- and the
-- exact column is reported only to show that it is the liar.
--
-- Nothing here needs a car, a Workspace or a playtest: the frame loop is the live one
-- (DriftController:_frame) written out, with Sim, Render and the camera's own `_advance`
-- doing exactly what they do in the game. `live = true` runs it against the real
-- Workspace instead of a flat plane, which is how the ground rays get measured.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "JitterTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)

local PlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local DriftFolder = PlayerScripts:WaitForChild("Drift")
local ControllerFolder = PlayerScripts:WaitForChild("Controllers")

local JitterTests = {}

local C = Config.Drift

-- Loaded on the first call, not here, so an edit session can hand in a freshly cloned
-- `Drift` folder: Studio caches a ModuleScript's result for the whole session, so a
-- session that required the model before Lync synced a change would be measuring the old
-- copy. A playtest always starts with an empty cache and never needs it.
local Model, Sim, World, Render, Camera

local function load(driftFolder: Instance?)
	local from = driftFolder or DriftFolder
	Model = require(from.Model)
	Sim = require(from.Sim)
	World = require(from.World)
	Render = require(from.Render)
	Camera = require(ControllerFolder.CarCameraController)
end

--------------------------------------------------------------------------------
-- numbers
--------------------------------------------------------------------------------

local function stats(list: { number })
	if #list == 0 then
		return { worst = 0, p95 = 0, p50 = 0, mean = 0, n = 0 }
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	local sum = 0
	for _, v in sorted do
		sum += v
	end
	local function at(q: number)
		return sorted[math.clamp(math.ceil(q * #sorted), 1, #sorted)]
	end
	return { worst = sorted[#sorted], p95 = at(0.95), p50 = at(0.5), mean = sum / #sorted, n = #sorted }
end

-- |(x[i] - x[i-1]) - (x[i-1] - x[i-2])|, for a series sampled once a frame: the plain
-- second difference, which is what the eye sees as long as the frames are evenly spaced.
local function secondDiffs(series: { any }, size: (any) -> number, from: number?): { number }
	local out = {}
	for i = math.max(from or 1, 3), #series do
		out[#out + 1] = size(series[i] - 2 * series[i - 1] + series[i - 2])
	end
	return out
end

-- THE SAME THING WITH THE FRAME'S OWN LENGTH TAKEN OUT, and it is the honest one.
--
-- A real frame clock is uneven, and a perfectly smooth motion sampled at uneven moments
-- has a second difference of its own: the car moved further this frame because this frame
-- was longer. That is not judder and no player can see it. So the previous frame's step is
-- scaled to this frame's length before the two are compared, which is exactly zero for
-- anything moving at a steady rate however uneven the sampling, and is the full step a
-- frame gained or lost when the drawing jumps.
local function stepErrors(series: { any }, dts: { number }, size: (any) -> number, from: number?): { number }
	local out = {}
	for i = math.max(from or 1, 3), #series do
		local scale = if dts[i - 1] > 1e-9 then dts[i] / dts[i - 1] else 1
		out[#out + 1] = size((series[i] - series[i - 1]) - (series[i - 1] - series[i - 2]) * scale)
	end
	return out
end

local function vecSize(v: Vector3): number
	return v.Magnitude
end

local function numSize(x: number): number
	return math.abs(x)
end

-- Degrees of arc from the camera's own look axis to a world point, as a pair: across the
-- screen and up it. The second difference of this is the wobble the player watches, and a
-- degree is about 12 screen pixels tall on a 1080-line display at the FOV this game uses.
local function screenAngle(cf: CFrame, point: Vector3): Vector3
	local p = cf:PointToObjectSpace(point)
	local depth = math.max(-p.Z, 1e-3)
	return Vector3.new(math.deg(math.atan2(p.X, depth)), math.deg(math.atan2(p.Y, depth)), 0)
end

--------------------------------------------------------------------------------
-- the frame clock
--------------------------------------------------------------------------------

-- Three kinds, and the difference between them is the whole of why this is hard to see:
--   exact    1/fps every frame. At 30, 60 and 120 this divides the step exactly and the
--            accumulator never has anything left over: the judder measures zero.
--   jitter   1/fps with `jitter` of proportional noise, seeded, which is what a real
--            frame clock looks like.
--   replay   a recorded list of real frame times from a playtest.
local function frameClock(opts)
	if opts.dts and #opts.dts > 0 then
		local dts, i = opts.dts, 0
		return function()
			i += 1
			return dts[(i - 1) % #dts + 1]
		end
	end
	local base = 1 / math.max(opts.fps or 60, 1)
	local jitter = opts.jitter or 0
	if jitter <= 0 then
		return function()
			return base
		end
	end
	local rng = Random.new(opts.seed or 20261103)
	return function()
		return base * (1 + rng:NextNumber(-jitter, jitter))
	end
end

--------------------------------------------------------------------------------
-- the scenarios
--------------------------------------------------------------------------------

-- Never a heading of zero: a car travelling exactly along a world axis has no speed on
-- the perpendicular axis for the grip's per-axis clamp to allow, which is a state no
-- player can be in (features/drift-model.md "Grip -- the drift").
local START_YAW = math.rad(15)

local SCENARIOS = {
	-- The car drives itself, so standing still means holding the handbrake.
	still = { speed = 0, steer = 0, handbrake = true },
	-- Top speed in a straight line: the worst case for the drawn POSITION, because that
	-- is where a step of the simulation covers the most ground.
	straight = { speed = C.TopSpeed, steer = 0, handbrake = false },
	-- A drift the car can actually hold. A quarter finger from 140 studs/s settles at
	-- about 12 degrees of slip and 40 studs/s round a 79-stud circle, which is what this
	-- car can sustain (features/drift-model.md "What it measured"). A bigger finger is a
	-- SPIN: the car stops, and at a standstill the slip angle is the direction of a
	-- velocity near zero, which is noise -- the camera then chases that noise, and what
	-- gets measured is the scenario rather than the drawing.
	drift = { speed = 140, steer = 0.25, handbrake = false },
	-- Rotating AND fast, for the worst case of the drawn HEADING: a brief hold at top
	-- speed, before the grip has taken the speed away.
	turn = { speed = C.TopSpeed, steer = 1, handbrake = false },
}

--------------------------------------------------------------------------------
-- one measured run
--------------------------------------------------------------------------------

-- `opts`: { scenario, fps, jitter, dts, seconds, at (Vector3 start), live, driftFolder }
--
-- Runs the live client frame loop headless and reports, for each of the two ways the car
-- can be drawn, what a player would see:
--   `old`  drawn at the last completed step -- what the code did before T-025
--   `new`  carried forward across the accumulator's leftover -- what it does now
-- Both come out of the SAME simulation in the SAME run, so the two columns are the same
-- car and the same frames, and nothing but the drawing differs.
function JitterTests:measure(opts)
	opts = opts or {}
	load(opts.driftFolder)

	local name = opts.scenario or "straight"
	local s = SCENARIOS[name] or SCENARIOS.straight
	local seconds = math.clamp(opts.seconds or 6, 0.5, 30)
	local at = opts.at or Vector3.zero
	local step = C.FixedStep

	local startCF = CFrame.new(at + Vector3.new(0, C.RideHeight, 0)) * CFrame.Angles(0, START_YAW, 0)
	local world = if opts.live then World.live({ workspace:FindFirstChild("Cars") }) else World.flat(at.Y)
	local runner = Sim.newRunner(startCF)
	local fwd = Model.axes(START_YAW)
	-- `speed` overrides the scenario's, so a measurement can be taken at exactly the speed
	-- a live run was measured at and the two compared without arithmetic.
	runner.state.velocity = fwd * (opts.speed or s.speed)
	-- Past the throttle ease-in, so the drive being measured is a steady one.
	runner.state.time = C.FullThrottleSeconds

	local input = { steer = s.steer, handbrake = s.handbrake }

	-- The simulation's own trajectory, one entry per step, so a frame can be asked what
	-- the truth was at the moment it was drawn.
	local stepPos: { Vector3 } = { runner.state.position }
	local stepYaw: { number } = { runner.state.yaw }
	local function onStep(st)
		stepPos[#stepPos + 1] = st.position
		stepYaw[#stepYaw + 1] = st.yaw
	end

	local nextDt = frameClock(opts)
	local rigOld = Camera.newRig()
	local rigNew = Camera.newRig()

	local series = {
		old = { car = {}, cam = {}, screen = {}, yaw = {}, y = {}, lag = {}, swing = {}, gap = {} },
		new = { car = {}, cam = {}, screen = {}, yaw = {}, y = {}, lag = {}, swing = {}, gap = {} },
	}
	local frameTimes: { number } = {}
	local frameDts: { number } = {}
	local stepsPerFrame: { number } = {}
	local remainders: { number } = {}

	-- The camera is seeded on its first frame and settles over a second or so. That
	-- settling is not judder and must not be counted as any: every statistic below starts
	-- at the first frame past `settle`.
	local settle = opts.settle or 1
	local firstCounted = 1

	local clock = 0
	while clock < seconds do
		local dt = nextDt()
		clock += dt
		if clock <= settle then
			firstCounted = #frameTimes + 2
		end
		local steps = Sim.advance(runner, dt, input, world, onStep)
		local state = runner.state
		local rem = runner.accumulator

		-- The simulation's own idea of now: whole steps taken, plus what is left over.
		-- Taken from the runner rather than from the sum of `dt`, so the accumulator's
		-- clamp cannot make the two disagree.
		local simNow = runner.totalSteps * step + rem
		frameTimes[#frameTimes + 1] = simNow
		frameDts[#frameDts + 1] = dt
		stepsPerFrame[#stepsPerFrame + 1] = steps
		remainders[#remainders + 1] = rem

		for _, which in { "old", "new" } do
			local use = if which == "old" then 0 else rem
			local cf = Render.pose(state, use)
			local drawnPos, drawnYaw = Render.subStep(state, use)
			local view = {
				position = drawnPos,
				yaw = drawnYaw,
				velocity = state.velocity,
				slip = state.slip,
				speed = Model.speed(state),
			}
			local rig = if which == "old" then rigOld else rigNew
			local camCF = Camera._advance(rig, view, dt)

			local out = series[which]
			out.car[#out.car + 1] = cf.Position
			out.yaw[#out.yaw + 1] = drawnYaw
			out.y[#out.y + 1] = cf.Position.Y
			out.cam[#out.cam + 1] = camCF.Position
			out.screen[#out.screen + 1] = screenAngle(camCF, cf.Position)
			out.gap[#out.gap + 1] = (cf.Position - state.position).Magnitude
		end
	end

	-- THE LAG, after the fact. Where the simulation really had the car at a frame's own
	-- moment is the chord between the two steps that moment falls between -- and that needs
	-- the step AFTER the frame, which only exists once the run is over.
	--
	-- This is the measurement that settles the whole question, because it is immune to how
	-- evenly the frames were spaced: a drawn car sitting ON that chord every frame cannot
	-- judder, whatever the frame clock does, and one that wanders on and off it by a
	-- varying amount is juddering by exactly that amount.
	local residual = { old = {}, new = {} }
	for i, simNow in frameTimes do
		local k = math.floor(simNow / step + 1e-9)
		local frac = math.clamp(simNow / step - k, 0, 1)
		if k + 2 <= #stepPos then
			local truth = stepPos[k + 1]:Lerp(stepPos[k + 2], frac)
			for _, which in { "old", "new" } do
				residual[which][i] = series[which].car[i] - truth
			end
		end
	end
	for _, which in { "old", "new" } do
		local out, res = series[which], residual[which]
		for i = 1, #frameTimes do
			if res[i] then
				out.lag[#out.lag + 1] = res[i].Magnitude
				-- How much that error CHANGED from the frame before: the studs the car
				-- visibly jumps, with everything honest about its motion removed.
				if res[i - 1] and i >= firstCounted then
					out.swing[#out.swing + 1] = (res[i] - res[i - 1]).Magnitude
				end
			end
		end
	end

	local function degrees(x: number): number
		return math.abs(math.deg(x))
	end

	local function summarise(which)
		local out = series[which]
		local f = firstCounted
		return {
			-- The plain second difference, which is what the brief asks for and what the
			-- eye sees on an even frame clock...
			car = stats(secondDiffs(out.car, vecSize, f)),
			carY = stats(secondDiffs(out.y, numSize, f)),
			yawDeg = stats(secondDiffs(out.yaw, degrees, f)),
			camera = stats(secondDiffs(out.cam, vecSize, f)),
			screenDeg = stats(secondDiffs(out.screen, vecSize, f)),
			-- ...and the same with the frame's own length divided out, which is the one to
			-- read when the clock is uneven.
			carStep = stats(stepErrors(out.car, frameDts, vecSize, f)),
			yawStepDeg = stats(stepErrors(out.yaw, frameDts, degrees, f)),
			cameraStep = stats(stepErrors(out.cam, frameDts, vecSize, f)),
			screenStepDeg = stats(stepErrors(out.screen, frameDts, vecSize, f)),
			-- And the two that need no frame clock at all.
			lag = stats(out.lag),
			lagSwing = stats(out.swing),
			gapToStep = stats(out.gap),
		}
	end

	local final = runner.state
	return {
		scenario = name,
		fps = opts.fps,
		jitter = opts.jitter or 0,
		replayed = opts.dts ~= nil,
		at = at,
		live = opts.live == true,
		frames = #frameTimes,
		steps = runner.totalSteps,
		stepsPerFrame = stats(stepsPerFrame),
		remainder = stats(remainders),
		endSpeed = Model.speed(final),
		endSlipDeg = math.deg(final.slip),
		endPosition = final.position,
		old = summarise("old"),
		new = summarise("new"),
	}
end

--------------------------------------------------------------------------------
-- the other candidates
--------------------------------------------------------------------------------

-- Float precision far from the origin, measured rather than assumed. A CFrame holds
-- 32-bit floats, so the spacing between representable positions doubles with every
-- doubling of the distance: this writes the car's own shell offsets out at each distance
-- the way `Render.place` does and reports how far each part lands from where the maths
-- says it should be, and how much that answer MOVES when the car turns a degree -- which
-- is what a shimmer between parts would be.
function JitterTests:precision(distances: { number }?, driftFolder: Instance?)
	load(driftFolder)
	local offsets = {}
	-- A spread of shell offsets the size of a real car: the AE86's parts reach about 7
	-- studs from the origin.
	for _, o in
		{
			Vector3.new(0, 0, 0),
			Vector3.new(3.2, 1.6, -7),
			Vector3.new(-3.2, 1.6, 7),
			Vector3.new(2.8, -1.2, 4.8),
			Vector3.new(-2.8, 2.4, -4.8),
		}
	do
		offsets[#offsets + 1] = CFrame.new(o)
	end

	local rows = {}
	for _, d in distances or { 0, 500, 2000, 20000 } do
		local worst, worstTurn = 0, 0
		for i = 0, 64 do
			local yaw = math.rad(i * 5.625)
			local base = CFrame.new(d, 2.4, 0) * CFrame.Angles(0, yaw, 0)
			local turned = CFrame.new(d, 2.4, 0) * CFrame.Angles(0, yaw + math.rad(1), 0)
			for _, L in offsets do
				-- Where the part is written, against the same sum in doubles.
				local got = (base * L).Position
				local want = base.Position
					+ base.RightVector * L.Position.X
					+ base.UpVector * L.Position.Y
					+ base.LookVector * -L.Position.Z
				worst = math.max(worst, (got - want).Magnitude)
				-- And how much the error itself moves when the car turns: a fixed error is
				-- invisible, a moving one is a shimmer.
				local gotTurn = (turned * L).Position
				local wantTurn = turned.Position
					+ turned.RightVector * L.Position.X
					+ turned.UpVector * L.Position.Y
					+ turned.LookVector * -L.Position.Z
				worstTurn = math.max(worstTurn, ((gotTurn - wantTurn) - (got - want)).Magnitude)
			end
		end
		rows[#rows + 1] = { distance = d, worstStuds = worst, worstChangePerDegree = worstTurn }
	end
	return rows
end

-- What the ground rays do under a car, step by step: how much the height the four rays
-- agree on moves from one step to the next, and from one FRAME to the next. A ray
-- flickering between two surfaces, or a seam, shows up here as a height that jumps when
-- nothing about the car has.
function JitterTests:ground(opts)
	opts = opts or {}
	load(opts.driftFolder)
	local at = opts.at or Vector3.zero
	local world = if opts.live then World.live({ workspace:FindFirstChild("Cars") }) else World.flat(at.Y)
	local s = SCENARIOS[opts.scenario or "straight"]
	local startCF = CFrame.new(at + Vector3.new(0, C.RideHeight, 0)) * CFrame.Angles(0, START_YAW, 0)
	local runner = Sim.newRunner(startCF)
	runner.state.velocity = Model.axes(START_YAW) * (opts.speed or s.speed)
	runner.state.time = C.FullThrottleSeconds

	local groundY: { number } = {}
	local tiltDeg: { number } = {}
	local rollDeg: { number } = {}
	local steerDeg: { number } = {}
	local function onStep(st)
		groundY[#groundY + 1] = st.groundY or 0
		tiltDeg[#tiltDeg + 1] = math.deg(math.acos(math.clamp(st.up.Y, -1, 1)))
		-- The two cosmetic easings Render deliberately does NOT carry across the
		-- sub-step: this is what their quantisation to the step is worth.
		rollDeg[#rollDeg + 1] = math.deg(st.bodyRoll)
		steerDeg[#steerDeg + 1] = math.deg(st.wheelSteer)
	end

	local nextDt = frameClock(opts)
	local clock = 0
	local seconds = math.clamp(opts.seconds or 6, 0.5, 30)
	while clock < seconds do
		local dt = nextDt()
		clock += dt
		Sim.advance(runner, dt, { steer = s.steer, handbrake = s.handbrake }, world, onStep)
	end

	local jumps, tilts, rolls, steers = {}, {}, {}, {}
	for i = 2, #groundY do
		jumps[#jumps + 1] = math.abs(groundY[i] - groundY[i - 1])
		tilts[#tilts + 1] = math.abs(tiltDeg[i] - tiltDeg[i - 1])
		rolls[#rolls + 1] = math.abs(rollDeg[i] - rollDeg[i - 1])
		steers[#steers + 1] = math.abs(steerDeg[i] - steerDeg[i - 1])
	end
	return {
		steps = #groundY,
		groundStepStuds = stats(jumps),
		tiltStepDeg = stats(tilts),
		rollStepDeg = stats(rolls),
		wheelSteerStepDeg = stats(steers),
		endPosition = runner.state.position,
		airborneAtEnd = runner.state.airborne,
	}
end

--------------------------------------------------------------------------------
-- the report
--------------------------------------------------------------------------------

local function row(r)
	return {
		scenario = r.scenario,
		clock = if r.replayed then "replay" else string.format("%d fps%s", r.fps or 0, if r.jitter > 0 then " jittered" else " exact"),
		at = string.format("%.0f studs out", r.at.Magnitude),
		stepsPerFrame = string.format("%.2f avg, %d worst", r.stepsPerFrame.mean, r.stepsPerFrame.worst),
		-- studs
		carBefore = r.old.car.worst,
		carAfter = r.new.car.worst,
		carBeforeP95 = r.old.car.p95,
		carAfterP95 = r.new.car.p95,
		-- degrees
		yawBefore = r.old.yawDeg.worst,
		yawAfter = r.new.yawDeg.worst,
		camBefore = r.old.camera.worst,
		camAfter = r.new.camera.worst,
		screenBefore = r.old.screenDeg.worst,
		screenAfter = r.new.screenDeg.worst,
		lagBefore = r.old.lag.worst,
		lagAfter = r.new.lag.worst,
		gapBefore = r.old.gapToStep.worst,
		gapAfter = r.new.gapToStep.worst,
	}
end

-- Every scenario at every frame clock, as rows ready to read. This is the measurement the
-- report quotes; `run` below is the same numbers turned into pass or fail.
function JitterTests:report(opts)
	opts = opts or {}
	load(opts.driftFolder)
	local out = {}
	local clocks = opts.clocks
		or {
			{ fps = 30, jitter = 0 },
			{ fps = 60, jitter = 0 },
			{ fps = 120, jitter = 0 },
			{ fps = 30, jitter = 0.08 },
			{ fps = 60, jitter = 0.08 },
			{ fps = 120, jitter = 0.08 },
			{ fps = 72, jitter = 0 },
			{ fps = 100, jitter = 0 },
			{ fps = 144, jitter = 0 },
		}
	local places = opts.places or { Vector3.zero, Vector3.new(2000, 0, 0) }
	for _, scenario in opts.scenarios or { "still", "straight", "drift", "turn" } do
		for _, place in places do
			for _, clock in clocks do
				out[#out + 1] = row(self:measure({
					scenario = scenario,
					fps = clock.fps,
					jitter = clock.jitter,
					dts = clock.dts,
					at = place,
					seconds = opts.seconds or 5,
					driftFolder = opts.driftFolder,
				}))
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- pass or fail
--------------------------------------------------------------------------------

-- What a frame may move differently from the frame BEFORE it, with the frame's own length
-- divided out, once the sub-step is on. One simulation step at top speed is 1.49 studs and
-- that is what the drawing used to gain or lose in a frame; these limits are a tenth of it
-- or better. What is left at 30 FPS is not judder at all but the car's own acceleration
-- over a thirtieth of a second, which is why the limits are not tighter still.
local CAR_LIMIT = 0.15 -- studs
local YAW_LIMIT = 0.02 -- degrees
local SCREEN_LIMIT = 0.1 -- degrees of arc; about a pixel on a 1080-line screen
local LAG_LIMIT = 0.02 -- studs off where the simulation really has the car

-- The frame clocks a real machine actually has. NOT a dead-steady 30, 60 or 120: those
-- divide the simulation step exactly, leave the accumulator empty every frame, and make
-- the worst judder in this game measure zero (see the header). `DR-Lane1` measured
-- 0.0060 to 0.0106 s a frame around a 120 Hz mean, which is the 8 per cent jitter below.
local REAL_CLOCKS = {
	{ fps = 100, jitter = 0 }, -- a rate that does not divide the step
	{ fps = 30, jitter = 0.08 },
	{ fps = 60, jitter = 0.08 },
	{ fps = 120, jitter = 0.08 },
	{ fps = 144, jitter = 0.08 },
}

function JitterTests:run(driftFolder: Instance?)
	load(driftFolder)
	local checks = {}
	local function check(name: string, ok: boolean, detail: string)
		checks[#checks + 1] = { name = name, ok = ok, detail = detail }
	end

	-- The worst of every real clock, per scenario, for both ways of drawing the car.
	local worst = {}
	for _, scenario in { "still", "straight", "drift", "turn" } do
		local w = { car = { 0, 0 }, yaw = { 0, 0 }, screen = { 0, 0 }, lag = { 0, 0 }, swing = { 0, 0 }, at = "" }
		for _, clock in REAL_CLOCKS do
			local r = self:measure({
				scenario = scenario,
				fps = clock.fps,
				jitter = clock.jitter,
				seconds = if scenario == "turn" then 3 else 5,
				driftFolder = driftFolder,
			})
			if r.old.carStep.worst > w.car[1] then
				w.at = string.format("%d fps", clock.fps)
			end
			w.car[1] = math.max(w.car[1], r.old.carStep.worst)
			w.car[2] = math.max(w.car[2], r.new.carStep.worst)
			w.yaw[1] = math.max(w.yaw[1], r.old.yawStepDeg.worst)
			w.yaw[2] = math.max(w.yaw[2], r.new.yawStepDeg.worst)
			w.screen[1] = math.max(w.screen[1], r.old.screenStepDeg.worst)
			w.screen[2] = math.max(w.screen[2], r.new.screenStepDeg.worst)
			w.lag[1] = math.max(w.lag[1], r.old.lag.worst)
			w.lag[2] = math.max(w.lag[2], r.new.lag.worst)
			w.swing[1] = math.max(w.swing[1], r.old.lagSwing.worst)
			w.swing[2] = math.max(w.swing[2], r.new.lagSwing.worst)
		end
		worst[scenario] = w
	end

	-- 1. The drawn car does not jump, in any of the four things a car can be doing. The
	-- "before" half of each is the judder the user reported, in studs.
	for _, scenario in { "still", "straight", "drift", "turn" } do
		local w = worst[scenario]
		local moving = scenario ~= "still"
		check(
			`the drawn car does not jump: {scenario}`,
			w.car[2] <= CAR_LIMIT and (not moving or w.car[1] > 10 * w.car[2]),
			string.format(
				"worst %.4f studs a frame, against %.4f drawing at the last completed step (%s)",
				w.car[2],
				w.car[1],
				w.at
			)
		)
	end

	-- 2. The heading too. A full finger is 2 rad/s, so one step of it is 0.95 degrees, and
	-- that is what the drawn heading used to gain or lose in a frame.
	check(
		"the drawn heading does not jump",
		worst.turn.yaw[2] <= YAW_LIMIT and worst.turn.yaw[1] > 10 * YAW_LIMIT,
		string.format("worst %.4f deg a frame at full lock, against %.4f before", worst.turn.yaw[2], worst.turn.yaw[1])
	)

	-- 3. What the player actually watches: the angle from the camera's look axis to the
	-- car. The car and the camera can each be smooth and still shimmer against each other,
	-- and before T-025 they did -- they were drawn from two different instants.
	local shimmerOk, shimmerBefore, shimmerAfter = true, 0, 0
	for _, scenario in { "straight", "drift", "turn" } do
		shimmerBefore = math.max(shimmerBefore, worst[scenario].screen[1])
		shimmerAfter = math.max(shimmerAfter, worst[scenario].screen[2])
		shimmerOk = shimmerOk and worst[scenario].screen[2] <= SCREEN_LIMIT
	end
	check(
		"the car does not shimmer against its own camera",
		shimmerOk and shimmerBefore > 5 * shimmerAfter,
		string.format(
			"worst %.4f deg of arc a frame (about %.1f px on a 1080-line screen), against %.4f deg before",
			shimmerAfter,
			shimmerAfter * 1080 / 70,
			shimmerBefore
		)
	)

	-- 4. NOT BOUGHT WITH LAG. The drawn car sits on the simulation's own trajectory at the
	-- moment the frame is drawn, which is more than drawing at the last step ever did: that
	-- was a lag of up to a whole step, and a lag that VARIES is exactly what judder is.
	local lagOk, lagBefore, lagAfter, swingBefore, swingAfter = true, 0, 0, 0, 0
	for _, scenario in { "straight", "drift", "turn" } do
		lagBefore = math.max(lagBefore, worst[scenario].lag[1])
		lagAfter = math.max(lagAfter, worst[scenario].lag[2])
		swingBefore = math.max(swingBefore, worst[scenario].swing[1])
		swingAfter = math.max(swingAfter, worst[scenario].swing[2])
		lagOk = lagOk and worst[scenario].lag[2] <= LAG_LIMIT
	end
	check(
		"the smoothing costs nothing in lag",
		lagOk and lagAfter < lagBefore and swingAfter < swingBefore,
		string.format(
			"drawn %.4f studs off the simulation's own position at the frame's moment, against %.4f before; "
				.. "that error swings %.4f studs a frame, against %.4f before",
			lagAfter,
			lagBefore,
			swingAfter,
			swingBefore
		)
	)

	-- 5. The same anywhere in the world: float precision is not what is wobbling.
	local near = self:measure({ scenario = "drift", fps = 100, seconds = 5, driftFolder = driftFolder })
	local far = self:measure({
		scenario = "drift",
		fps = 100,
		seconds = 5,
		at = Vector3.new(2000, 0, 0),
		driftFolder = driftFolder,
	})
	check(
		"2 000 studs out is the same as at the spawn",
		math.abs(far.new.carStep.worst - near.new.carStep.worst) < 0.01
			and math.abs(far.new.screenStepDeg.worst - near.new.screenStepDeg.worst) < 0.01,
		string.format(
			"car %.4f studs and shimmer %.4f deg at 2 000 studs, against %.4f and %.4f at the spawn",
			far.new.carStep.worst,
			far.new.screenStepDeg.worst,
			near.new.carStep.worst,
			near.new.screenStepDeg.worst
		)
	)

	local worstShell = 0
	for _, p in self:precision(nil, driftFolder) do
		if p.distance <= 2000 then
			worstShell = math.max(worstShell, p.worstChangePerDegree)
		end
	end
	check(
		"the shell's parts do not shimmer against each other",
		worstShell < 0.002,
		string.format(
			"a part's placement error moves at most %.6f studs per degree the car turns, out to 2 000 studs -- "
				.. "under a hundredth of what one simulation step covers",
			worstShell
		)
	)

	-- 6. The ground follow is not a bob of its own.
	local g = self:ground({ scenario = "straight", fps = 100, seconds = 5, driftFolder = driftFolder })
	check(
		"the ground follow is steady on a flat surface",
		g.groundStepStuds.worst < 1e-6 and g.tiltStepDeg.worst < 1e-6,
		string.format(
			"over %d steps the ground height moves %.8f studs and the tilt %.8f deg",
			g.steps,
			g.groundStepStuds.worst,
			g.tiltStepDeg.worst
		)
	)

	-- 7. And the trap, stated as a check so nobody measures this on a clean clock again.
	local clean = self:measure({ scenario = "straight", fps = 60, jitter = 0, seconds = 3, driftFolder = driftFolder })
	check(
		"a dead-steady 60 FPS hides this bug entirely",
		clean.old.carStep.worst < 0.01,
		string.format(
			"drawing at the last step measures %.4f studs on a perfect 60 Hz clock and %.4f on a real one: "
				.. "60 divides the 1/120 step exactly, so the accumulator never has anything left over",
			clean.old.carStep.worst,
			worst.straight.car[1]
		)
	)

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return JitterTests
