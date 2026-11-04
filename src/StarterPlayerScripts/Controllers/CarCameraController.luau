--!nonstrict
-- CarCameraController: the drift camera.
--
-- A port of the reference game's camera (docs/game/features/drift-model.md "Camera"),
-- written from a description of how it works. Three things happen at once, and all three
-- are driven by the one slip angle the model already publishes:
--
--   1. IT SWINGS toward where the car is going, not where it points. The resting place is
--      behind the nose; as the slip opens, the target slides toward a point directly
--      behind the VELOCITY, by an ease-in-out of |slip| / 180 deg. Then only
--      `CamVelocityBlend` of that swing is actually used -- and the reference's own value
--      is 0.05. That is not a mistake: the swing is a hint, not a side-on shot, and it is
--      most of why its camera reads as calm at 179 studs/s.
--   2. IT ROLLS about its own forward axis, to `CamRollMax` by `CamRollAtAngle` of slip.
--      The cheapest and largest part of the effect.
--   3. IT PULLS IN toward `CamDriftDistance` of its resting length, full in by
--      `CamZoomAtAngle`.
--
-- The position eases toward its target with a critically damped spring (`CamSmoothTime`);
-- the look-at eases SEPARATELY and more slowly (`CamLookRate`), as a rotation rather than
-- as a point, which is what keeps the horizon from jittering and what stops the car
-- sliding off centre at speed -- a lagged look POINT lags by speed/rate studs for ever,
-- a lagged look DIRECTION settles with no error at all in a straight line.
--
-- On a run ending the camera lets go (`Release`) and holds its last target.
--
-- Offsets are in the car's own flat axes: +x right, +y up, +z BEHIND. The car's pitch and
-- roll are deliberately NOT in that basis -- the camera follows the heading and the height
-- only, so a crest does not throw the view about.
--
-- THE TARGETS RUN ON A FIXED STEP, and they have to. The resting direction eases toward
-- the car's heading by a share of each step, while the swing knocks it off by a fixed
-- distance every step; the two balance at a deviation of roughly one over step times
-- `CamAngleRate`, which is to say the camera's whole geometry in a drift depended on frame
-- rate. Measured before this was fixed: at 45 deg of slip and 120 studs/s the camera sat
-- 16.25 studs above the car at 30 FPS, 13.09 at 60 and 10.12 at 120. The model is
-- deliberately frame-rate independent (Drift/Sim) and a camera that is not hands two
-- players different games, so the targets are stepped like the model is, and the rendered
-- camera is interpolated between steps. Everything downstream of the targets -- the
-- position spring, the look rotation, the field of view -- is already frame-rate
-- independent and still runs once a frame.
--
-- Every number is in Config.Drift; none is in here, with one exception noted at
-- `TARGET_STEP`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local DriftModel = require(DriftFolder.Model)

local DriftController = require(script.Parent.DriftController)

local CarCameraController = {}

CarCameraController.Priority = 5 -- after DriftController, so a state exists to follow

local STEP_NAME = "DriftCamera"
local EPS = 1e-4

-- The step the camera's targets run at, and the clamp on how many one frame may spend:
-- `CamTargetStep` and `CamMaxTargetSteps`, which say there why the camera's step is its
-- own and not the model's `FixedStep`. Read once -- Config is not reloaded at runtime.
local TARGET_STEP = Config.Drift.CamTargetStep
local MAX_TARGET_STEPS = Config.Drift.CamMaxTargetSteps

-- What the camera needs of the car, and nothing else. Built from the model's state, or
-- made up by DebugProbe, which is how the zoom curve and the roll curve are measured
-- without a car.
export type View = {
	position: Vector3,
	yaw: number, -- radians, Roblox sense
	velocity: Vector3, -- world studs/s
	slip: number, -- radians, signed: + means the car is travelling out to its LEFT
	speed: number, -- horizontal, studs/s
}

-- ---------------------------------------------------------------- the maths

-- Frame-rate independent form of the reference's `Lerp(a, b, dt * rate)`.
local function ease(dt: number, rate: number): number
	return 1 - math.exp(-dt * math.max(rate, 0))
end

-- Quadratic ease-in-out on 0..1: flat at both ends, steepest in the middle. This is what
-- makes a small slide barely move the camera and a big one move it properly.
local function easeInOut(t: number): number
	t = math.clamp(t, 0, 1)
	if t < 0.5 then
		return 2 * t * t
	end
	return -1 + (4 - 2 * t) * t
end

-- A critically damped spring, the shape Unity's SmoothDamp uses: `CamSmoothTime` is the
-- time it takes to cover most of the gap, and it never overshoots.
--
-- The decay is the real `exp(-x)`, not the cubic Unity substitutes for it. That
-- substitution is a speed trick with an error that grows with the step, and the error is a
-- frame-rate dependence by another name: with the cubic, the camera trailed 44.1 studs
-- behind a car at 120 studs/s at 30 FPS and 47.5 at 120. Exactly solved, the spring is the
-- same spring at any step.
local function smoothDamp(current: Vector3, target: Vector3, vel: Vector3, smoothTime: number, dt: number): (Vector3, Vector3)
	smoothTime = math.max(smoothTime, EPS)
	local omega = 2 / smoothTime
	local x = omega * dt
	local decay = math.exp(-x)
	local change = current - target
	local temp = (vel + change * omega) * dt
	local newVel = (vel - temp * omega) * decay
	return target + (change + temp) * decay, newVel
end

-- A point in the car's own flat axes: +x right, +y up, +z behind.
local function carPoint(view: View, offset: Vector3): Vector3
	local fwd, right = DriftModel.axes(view.yaw)
	return view.position + right * offset.X + Vector3.yAxis * offset.Y - fwd * offset.Z
end

local function safeUnit(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > EPS then v.Unit else fallback
end

-- The short way round between two angles.
local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

-- Where the car was a fraction of the way through this frame. A frame that owes the
-- accumulator two steps must not hand both of them the same car pose: that samples the car
-- at frame rate inside a fixed-step loop, and it is how the camera's distance ends up
-- depending on frame rate even once its geometry does not.
local function lerpView(a: View, b: View, t: number): View
	return {
		position = a.position:Lerp(b.position, t),
		yaw = lerpAngle(a.yaw, b.yaw, t),
		velocity = a.velocity:Lerp(b.velocity, t),
		slip = lerpAngle(a.slip, b.slip, t),
		speed = a.speed + (b.speed - a.speed) * t,
	}
end

-- ---------------------------------------------------------------- the rig
--
-- Everything the camera remembers between frames, in one table, so DebugProbe can run a
-- second one against a made-up car without touching the live view.

local function newRig(view: View?)
	local rig = {
		ready = false,
		position = Vector3.zero,
		posVel = Vector3.zero,
		lookDir = Vector3.new(0, 0, -1),
		lookTarget = Vector3.zero,
		velTarget = Vector3.zero,
		fixedTarget = Vector3.zero, -- behind the nose: what the swing is measured from
		target = Vector3.zero, -- after the swing and the blend
		lastTarget = Vector3.zero,
		lastCarPos = Vector3.zero,
		distMult = 1,
		roll = 0,
		fov = Config.Drift.CamFovBase,
		released = false,
		-- The fixed-step accumulator, and the step before the current one, so a frame that
		-- lands between two steps is rendered between them rather than on whichever step
		-- happened last.
		accumulator = 0,
		prevTarget = Vector3.zero,
		prevLookTarget = Vector3.zero,
		prevRoll = 0,
		renderRoll = 0, -- the roll actually used this frame, interpolated
		steps = 0,
		lastView = nil, -- the car as the previous frame saw it, for the sub-step lerp
	}
	if view then
		CarCameraController._seed(rig, view)
	end
	return rig
end

-- Start where the camera would have settled, so the first frame of a run is not a swoop
-- in from the origin.
function CarCameraController._seed(rig, view: View)
	local C = Config.Drift
	rig.lookTarget = carPoint(view, C.CamLookAt)
	rig.fixedTarget = carPoint(view, C.CamOffset)
	rig.velTarget = rig.fixedTarget
	rig.target = rig.fixedTarget
	rig.position = rig.fixedTarget
	rig.posVel = Vector3.zero
	rig.lastTarget = rig.fixedTarget
	rig.lastCarPos = view.position
	rig.lookDir = safeUnit(rig.lookTarget - rig.position, Vector3.new(0, 0, -1))
	rig.distMult = 1
	rig.roll = 0
	rig.accumulator = 0
	rig.prevTarget = rig.target
	rig.prevLookTarget = rig.lookTarget
	rig.prevRoll = 0
	rig.renderRoll = 0
	rig.lastView = view
	rig.ready = true
end

-- One fixed step of the targets, and nothing else. `dt` here is always `TARGET_STEP`.
local function stepTargets(rig, view: View, dt: number)
	local C = Config.Drift
	if not rig.released then
		-- (3) THE ZOOM. The whole offset shrinks toward `CamDriftDistance` of itself,
		-- full in by `CamZoomAtAngle` of slip, and the shrink itself eases.
		local zoomT = math.clamp(math.abs(math.deg(view.slip)) / math.max(C.CamZoomAtAngle, EPS), 0, 1)
		local wantMult = 1 + (C.CamDriftDistance - 1) * zoomT
		rig.distMult += (wantMult - rig.distMult) * ease(dt, C.CamZoomRate)
		local offset = C.CamOffset * rig.distMult

		-- The look-at: ahead of the nose, with only its HEIGHT eased (`CamHeightRate`).
		-- A car cresting a jump therefore keeps the horizon still while the camera
		-- itself follows the car up.
		local wantLook = carPoint(view, C.CamLookAt)
		rig.lookTarget = Vector3.new(
			wantLook.X,
			rig.lookTarget.Y + (wantLook.Y - rig.lookTarget.Y) * ease(dt, C.CamHeightRate),
			wantLook.Z
		)

		-- The resting place: behind the nose, but the DIRECTION it sits in follows the
		-- car round at `CamAngleRate` rather than snapping to the new heading. The length
		-- is always the (zoomed) offset's own length, so easing the direction can never
		-- change how far away the camera is.
		local wantDir = safeUnit(carPoint(view, offset) - view.position, Vector3.yAxis)
		local haveDir = safeUnit(rig.lastTarget - rig.lastCarPos, wantDir)
		local dir = safeUnit(haveDir:Lerp(wantDir, ease(dt, C.CamAngleRate)), wantDir)
		rig.fixedTarget = view.position + dir * offset.Magnitude

		-- (1) THE SWING. A point the same height and the same distance behind, but behind
		-- the VELOCITY instead of the nose, hung off the look-at point rather than off the
		-- car. It follows at `CamSwingRate`, so it is always a little behind the truth.
		local flatVel = Vector3.new(view.velocity.X, 0, view.velocity.Z)
		local fwd = DriftModel.axes(view.yaw)
		local back = safeUnit(-flatVel, -fwd)
		local wantVel = rig.lookTarget + back * offset.Z + Vector3.yAxis * offset.Y
		rig.velTarget = rig.velTarget:Lerp(wantVel, ease(dt, C.CamSwingRate))

		-- ...and then only `CamVelocityBlend` of that swing is used. Small on purpose.
		local swingT = easeInOut(math.abs(math.deg(view.slip)) / 180)
		rig.target = rig.fixedTarget:Lerp(rig.fixedTarget:Lerp(rig.velTarget, swingT), C.CamVelocityBlend)

		-- (2) THE ROLL, about the camera's own forward axis.
		local rollT = math.clamp(math.deg(view.slip) / math.max(C.CamRollAtAngle, EPS), -1, 1)
		local wantRoll = math.rad(C.CamRollMax) * rollT
		rig.roll += (wantRoll - rig.roll) * ease(dt, C.CamRollRate)

		rig.lastTarget = rig.target
		rig.lastCarPos = view.position
	end
end

-- One frame. Returns the camera's CFrame, roll included.
function CarCameraController._advance(rig, view: View, dt: number): CFrame
	local C = Config.Drift
	if not rig.ready then
		CarCameraController._seed(rig, view)
	end
	dt = math.clamp(dt, 0, 0.25) -- a loading hitch must not teleport the camera

	-- The targets, in whole fixed steps (see the header). The car's own pose is whatever
	-- this frame says it is: the camera samples the car at frame rate, and only the
	-- camera's own feedback is held to the step.
	rig.accumulator = math.min(rig.accumulator + dt, TARGET_STEP * MAX_TARGET_STEPS)
	local steps = math.floor(rig.accumulator / TARGET_STEP)
	local from = rig.lastView or view
	for i = 1, steps do
		rig.prevTarget, rig.prevLookTarget, rig.prevRoll = rig.target, rig.lookTarget, rig.roll
		stepTargets(rig, lerpView(from, view, i / steps), TARGET_STEP)
		rig.accumulator -= TARGET_STEP
	end
	rig.steps = steps
	rig.lastView = view

	-- ...and the frame is rendered between the last two of them, so a 90 or a 144 Hz
	-- screen gets its own smooth motion out of a 60 Hz target.
	local alpha = math.clamp(rig.accumulator / TARGET_STEP, 0, 1)
	local target = rig.prevTarget:Lerp(rig.target, alpha)
	local lookTarget = rig.prevLookTarget:Lerp(rig.lookTarget, alpha)
	rig.renderRoll = rig.prevRoll + (rig.roll - rig.prevRoll) * alpha

	-- The position eases...
	rig.position, rig.posVel = smoothDamp(rig.position, target, rig.posVel, C.CamSmoothTime, dt)

	-- ...and the look-at eases separately and more slowly, as a ROTATION. In a straight
	-- line the wanted direction stops changing and this settles with no error, however
	-- fast the car is going; easing the look POINT instead would leave the car permanently
	-- off centre by speed / CamLookRate studs.
	local wantLookDir = safeUnit(lookTarget - rig.position, rig.lookDir)
	rig.lookDir = safeUnit(rig.lookDir:Lerp(wantLookDir, ease(dt, C.CamLookRate)), wantLookDir)

	local speedFrac = math.clamp(view.speed / math.max(C.TopSpeed, EPS), 0, 1)
	rig.fov = C.CamFovBase + (C.CamFovTop - C.CamFovBase) * speedFrac

	return CFrame.lookAt(rig.position, rig.position + rig.lookDir) * CFrame.Angles(0, 0, rig.renderRoll)
end

-- How far the swing actually moved the camera's target, in studs: the whole point of the
-- `CamVelocityBlend` question.
local function swingStuds(rig): number
	return (rig.target - rig.fixedTarget).Magnitude
end

-- ---------------------------------------------------------------- lifecycle

local function viewFrom(state): View?
	if not state then
		return nil
	end
	return {
		position = state.position,
		yaw = state.yaw,
		velocity = state.velocity,
		slip = state.slip,
		speed = DriftModel.speed(state),
	}
end

function CarCameraController:Init()
	self.rig = newRig()
end

function CarCameraController:Start()
	local camera = workspace.CurrentCamera
	if not camera then
		warn("[CarCameraController] there is no CurrentCamera")
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	self.camera = camera

	-- A new camera arrives on respawn and on some Studio actions; take it over again.
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CameraSubject = nil
			self.camera = cam
			self.rig.ready = false
		end
	end)

	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value, function(dt)
		self:_frame(dt)
	end)
end

function CarCameraController:_frame(dt: number)
	local camera = self.camera
	if not camera then
		return
	end
	local view = viewFrom(DriftController:CurrentState())
	if not view then
		return
	end
	camera.CFrame = CarCameraController._advance(self.rig, view, dt)
	camera.FieldOfView = self.rig.fov
end

-- A run has ended: let go and hold the last target. `Follow` picks the car up again.
function CarCameraController:Release()
	self.rig.released = true
end

function CarCameraController:Follow()
	self.rig.released = false
end

-- ---------------------------------------------------------------- debug

function CarCameraController:DebugState()
	local rig = self.rig
	local state = DriftController:CurrentState()
	local carPos = state and state.position or nil
	return {
		hasCamera = self.camera ~= nil,
		cameraType = self.camera and self.camera.CameraType.Name or "none",
		ready = rig.ready,
		released = rig.released,
		position = rig.position,
		lookPoint = rig.lookTarget,
		fieldOfView = rig.fov,
		rollDeg = math.deg(rig.renderRoll),
		distanceMultiplier = rig.distMult,
		swingStuds = swingStuds(rig),
		slipDeg = state and math.deg(state.slip) or nil,
		speed = state and DriftModel.speed(state) or nil,
		distanceToCar = carPos and (rig.position - carPos).Magnitude or nil,
		heightAboveCar = carPos and (rig.position.Y - carPos.Y) or nil,
	}
end

-- Settle a throwaway rig against a car held at a fixed slip angle, and report what the
-- camera does there. This is how the zoom curve, the roll curve and the swing are
-- measured: no car, no Workspace and no waiting.
--
-- `opts`: { slipDeg, speed, seconds, fps, blend, yawDeg, sweepSeconds }. `blend` overrides
-- `CamVelocityBlend` for the run only (it is put back afterwards) so the same drift can be
-- measured at 0.05 and at anything else. `sweepSeconds` swings the slip from +slipDeg to
-- -slipDeg and back over that long instead of holding it, which is what the jitter numbers
-- want: a target that never moves cannot catch an interpolation that judders.
function CarCameraController:DebugProbe(opts)
	opts = opts or {}
	local C = Config.Drift
	local slip = math.rad(opts.slipDeg or 0)
	local speed = opts.speed or C.TopSpeed
	local yaw = math.rad(opts.yawDeg or 15) -- never a world axis: see the spec's note
	local fps = math.max(opts.fps or 60, 1)
	local seconds = math.clamp(opts.seconds or 12, 0, 60)
	local dt = 1 / fps

	local fwd = DriftModel.axes(yaw)
	-- + slip means the car is travelling out to its LEFT, so the velocity is the nose
	-- rotated by +slip about the world up.
	local velDir = (CFrame.Angles(0, slip, 0) * fwd).Unit
	local view: View = {
		position = Vector3.new(0, C.RideHeight, 0),
		yaw = yaw,
		velocity = velDir * speed,
		slip = slip,
		speed = speed,
	}

	local was = C.CamVelocityBlend
	if opts.blend then
		C.CamVelocityBlend = opts.blend
	end

	local rig = newRig(view)
	local maxPosStep, maxLookStep = 0, 0
	local prevPos, prevLook = rig.position, rig.position + rig.lookDir
	local steps = math.floor(seconds * fps)
	local settled = math.floor(steps * 0.75) -- the jitter numbers ignore the settling in
	local ok, err = pcall(function()
		for i = 1, steps do
			-- A FRESH table each frame, because the rig keeps the previous frame's view to
			-- interpolate its sub-steps from: handing it the same table mutated in place
			-- would make that interpolation a no-op and hide what it is there to fix.
			local s = slip
			if opts.sweepSeconds then
				s = slip * math.sin(2 * math.pi * (i * dt) / opts.sweepSeconds)
			end
			view = {
				position = view.position + view.velocity * dt,
				yaw = yaw,
				velocity = (CFrame.Angles(0, s, 0) * fwd).Unit * speed,
				slip = s,
				speed = speed,
			}
			CarCameraController._advance(rig, view, dt)
			local look = rig.position + rig.lookDir
			if i > settled then
				maxPosStep = math.max(maxPosStep, (rig.position - prevPos - view.velocity * dt).Magnitude)
				maxLookStep = math.max(maxLookStep, (look - prevLook - view.velocity * dt).Magnitude)
			end
			prevPos, prevLook = rig.position, look
		end
	end)

	C.CamVelocityBlend = was
	if not ok then
		return { error = tostring(err) }
	end

	local toCar = rig.position - view.position
	-- Where the swing actually took the target, split into the car's own axes: how much
	-- of it is sideways (the "side-on shot") and how much is simply further back.
	local swing = rig.target - rig.fixedTarget
	local sFwd, sRight = DriftModel.axes(yaw)
	return {
		slipDeg = opts.slipDeg or 0,
		speed = speed,
		blend = opts.blend or was,
		distance = toCar.Magnitude,
		height = toCar.Y,
		flatDistance = Vector3.new(toCar.X, 0, toCar.Z).Magnitude,
		rollDeg = math.deg(rig.renderRoll),
		distanceMultiplier = rig.distMult,
		swingStuds = swingStuds(rig), -- how far the blend actually moved the target
		swingSideways = swing:Dot(sRight), -- + is out to the car's right
		swingBackwards = -swing:Dot(sFwd), -- + is further behind the nose
		swingDown = -swing.Y,
		fullSwingStuds = (rig.velTarget - rig.fixedTarget).Magnitude, -- before the blend
		fov = rig.fov,
		-- Drift left over after the car's own motion is taken out: anything but ~0 means
		-- the camera has not settled, or is jittering.
		maxPosStep = maxPosStep,
		maxLookStep = maxLookStep,
	}
end

-- Watch the LIVE camera for `seconds` and report the worst frame of it: how far the
-- camera and its look point jumped between frames, and how far off the centre of the
-- screen the car ever got. Studio only, and it yields.
function CarCameraController:DebugRecord(seconds: number)
	seconds = math.clamp(seconds or 5, 0, 30)
	local camera = self.camera
	if not camera then
		return { error = "no camera" }
	end
	local out = {
		frames = 0,
		seconds = 0,
		maxPosStep = 0, -- studs the camera moved between two frames, car's own motion included
		maxLookStep = 0,
		maxTurnDeg = 0, -- degrees the view direction turned between two frames
		maxRollStepDeg = 0,
		maxScreenOffsetPx = 0,
		maxScreenOffsetFrac = 0, -- of half the screen's smaller side: 1 is the edge
		offScreenFrames = 0,
		minDistance = math.huge,
		maxDistance = 0,
		maxSlipDeg = 0,
		maxSpeed = 0,
		maxRollDeg = 0,
	}
	local prevPos, prevLook, prevDir, prevRoll = nil, nil, nil, nil
	local clock = 0
	while clock < seconds do
		local dt = RunService.RenderStepped:Wait()
		clock += dt
		out.frames += 1
		out.seconds = clock
		local cam = self.camera
		if not cam then
			break
		end
		local pos = cam.CFrame.Position
		local look = pos + cam.CFrame.LookVector
		local dir = cam.CFrame.LookVector
		if prevPos then
			out.maxPosStep = math.max(out.maxPosStep, (pos - prevPos).Magnitude)
			out.maxLookStep = math.max(out.maxLookStep, (look - prevLook).Magnitude)
			out.maxTurnDeg = math.max(out.maxTurnDeg, math.deg(math.acos(math.clamp(dir:Dot(prevDir), -1, 1))))
			out.maxRollStepDeg = math.max(out.maxRollStepDeg, math.abs(math.deg(self.rig.renderRoll) - prevRoll))
		end
		prevPos, prevLook, prevDir = pos, look, dir
		prevRoll = math.deg(self.rig.renderRoll)
		out.maxRollDeg = math.max(out.maxRollDeg, math.abs(math.deg(self.rig.renderRoll)))

		local state = DriftController:CurrentState()
		if state then
			local d = (pos - state.position).Magnitude
			out.minDistance = math.min(out.minDistance, d)
			out.maxDistance = math.max(out.maxDistance, d)
			out.maxSlipDeg = math.max(out.maxSlipDeg, math.abs(math.deg(state.slip)))
			out.maxSpeed = math.max(out.maxSpeed, DriftModel.speed(state))
			local point, onScreen = cam:WorldToViewportPoint(state.position)
			local size = cam.ViewportSize
			local centre = Vector2.new(size.X, size.Y) / 2
			local offset = (Vector2.new(point.X, point.Y) - centre).Magnitude
			if point.Z > 0 then
				out.maxScreenOffsetPx = math.max(out.maxScreenOffsetPx, offset)
				out.maxScreenOffsetFrac = math.max(out.maxScreenOffsetFrac, offset / math.min(centre.X, centre.Y))
			end
			if not onScreen then
				out.offScreenFrames += 1
			end
		end
	end
	if out.minDistance == math.huge then
		out.minDistance = 0
	end
	return out
end

return CarCameraController
