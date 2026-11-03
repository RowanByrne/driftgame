--!nonstrict
-- Sim: the fixed-step accumulator, in one place.
--
-- Frame rate never reaches the model. A frame hands Sim however long it took; Sim spends
-- it in whole `FixedStep` steps and keeps the remainder for the next frame. That is why
-- 30, 60 and 120 FPS run the same line (docs/game/features/drift-model.md "Determinism"),
-- and why DebugDrive, the live loop and DriftTests all share one code path.
--
-- The live loop reads the player's sticks once a frame and hands Sim that one input, which
-- is honest: that is all the information a frame has. A recorded drive hands Sim a
-- function of simulation time instead, so the inputs land at the same simulated moments at
-- every frame rate and the only difference left between 30 and 120 FPS is the leftover in
-- the accumulator.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Model = require(script.Parent.Model)
local World = require(script.Parent.World)

local Sim = {}

export type Runner = {
	state: Model.State,
	accumulator: number,
	steps: number, -- steps spent on the last advance
	totalSteps: number,
}

-- One line of a recorded drive: from second `t`, hold these.
export type Keyframe = { t: number, steer: number?, drift: boolean?, brake: boolean? }

function Sim.newRunner(spawnCFrame: CFrame): Runner
	return {
		state = Model.new(spawnCFrame),
		accumulator = 0,
		steps = 0,
		totalSteps = 0,
	}
end

-- Spend `dt` of real time on whole steps. `input` is either one input held for the whole
-- of `dt`, or a function of simulation time. `onStep` runs after each step, which is how
-- the path and the summary are sampled at simulation time rather than at frame time.
function Sim.advance(runner: Runner, dt: number, input, world: Model.World, onStep): number
	local C = Config.Drift
	local step = C.FixedStep
	local fn = if type(input) == "function" then input else nil
	runner.accumulator = math.min(runner.accumulator + dt, step * C.MaxStepsPerFrame)
	local steps = 0
	while runner.accumulator >= step do
		Model.step(runner.state, if fn then fn(runner.state.time) else input, step, world)
		runner.accumulator -= step
		steps += 1
		if onStep then
			onStep(runner.state)
		end
	end
	runner.steps = steps
	runner.totalSteps += steps
	return steps
end

-- The input a recorded drive asks for at simulation time `t`: the last keyframe at or
-- before it. An empty list is no input at all.
function Sim.inputAt(inputs: { Keyframe }, t: number): Model.Input
	local chosen: Keyframe? = nil
	for _, kf in inputs do
		local kt = kf.t or 0
		if kt <= t and (chosen == nil or kt >= (chosen.t or 0)) then
			chosen = kf
		end
	end
	if not chosen then
		return { steer = 0, drift = false, brake = false }
	end
	return { steer = chosen.steer or 0, drift = chosen.drift == true, brake = chosen.brake == true }
end

export type Summary = {
	steps: number,
	simSeconds: number,
	endPosition: Vector3,
	endSpeed: number,
	maxSpeed: number,
	peakSlipDeg: number,
	peakYawRate: number, -- rad/s
	entrySpeed: number?, -- speed the moment the drift input went down
	exitSpeed: number?, -- speed the moment grip had fully come back after it
	breakLooseSeconds: number?, -- drift input down to the rear letting go
	airborneSeconds: number,
	wallHits: number,
	headingChangeDeg: number, -- how far round the car came: a corner, measured
}

export type DriveOptions = {
	fps: number?, -- frames a second to feed it; nil runs the whole thing in one frame
	sample: number?, -- seconds of simulation between path points
	start: CFrame?, -- where the car starts
	world: Model.World?, -- defaults to a flat plane under the start
}

-- Run the model with no player and return the path it took, plus the numbers the tuning
-- conversation uses. Deterministic: same inputs, same start, same path.
function Sim.drive(inputs: { Keyframe }, seconds: number, opts: DriveOptions?): ({ Vector3 }, Summary)
	local C = Config.Drift
	local o: DriveOptions = opts or {}
	local startCF = o.start or CFrame.new(0, C.RideHeight, 0)
	local world = o.world or World.flat(startCF.Position.Y - C.RideHeight)
	local sample = math.max(o.sample or 0.05, C.FixedStep)
	seconds = math.clamp(seconds, 0, 120)

	local runner = Sim.newRunner(startCF)
	local startYaw = runner.state.yaw
	local path: { Vector3 } = { runner.state.position }

	local summary: Summary = {
		steps = 0,
		simSeconds = 0,
		endPosition = runner.state.position,
		endSpeed = 0,
		maxSpeed = 0,
		peakSlipDeg = 0,
		peakYawRate = 0,
		entrySpeed = nil,
		exitSpeed = nil,
		breakLooseSeconds = nil,
		airborneSeconds = 0,
		wallHits = 0,
		headingChangeDeg = 0,
	}

	local nextSample = sample
	local heldBefore = false
	local everHeld = false

	local function observe(s: Model.State)
		local speed = Model.speed(s)
		local held = s.driftHeld >= 0
		if held and not heldBefore then
			summary.entrySpeed = speed
			everHeld = true
			summary.exitSpeed = nil
		end
		heldBefore = held
		if everHeld and not held and summary.exitSpeed == nil and s.gripBlend <= 0.02 then
			summary.exitSpeed = speed
		end

		summary.maxSpeed = math.max(summary.maxSpeed, speed)
		summary.peakSlipDeg = math.max(summary.peakSlipDeg, math.abs(math.deg(s.slip)))
		summary.peakYawRate = math.max(summary.peakYawRate, math.abs(s.r))
		if s.airborne then
			summary.airborneSeconds += C.FixedStep
		end
		if s.wallHit then
			summary.wallHits += 1
		end
		if s.breakLoose and not summary.breakLooseSeconds then
			summary.breakLooseSeconds = s.breakLoose
		end
		if s.time >= nextSample then
			table.insert(path, s.position)
			nextSample += sample
		end
	end

	local inputFn = function(t: number): Model.Input
		return Sim.inputAt(inputs, t)
	end

	local frameDt = if o.fps then 1 / o.fps else seconds
	local elapsed = 0
	while elapsed < seconds - 1e-9 do
		local dt = math.min(frameDt, seconds - elapsed)
		Sim.advance(runner, dt, inputFn, world, observe)
		elapsed += dt
	end

	summary.steps = runner.totalSteps
	summary.simSeconds = runner.state.time
	summary.endPosition = runner.state.position
	summary.endSpeed = Model.speed(runner.state)
	summary.headingChangeDeg = math.deg(runner.state.yaw - startYaw)
	table.insert(path, runner.state.position)

	return path, summary
end

return Sim
