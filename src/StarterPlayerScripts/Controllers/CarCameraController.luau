--!nonstrict
-- CarCameraController: the drift camera.
--
-- A port of the reference game's camera (docs/game/features/drift-model.md "Camera"),
-- written from a description of how it works.
--
-- CORRECTED 2026-11-03. The decompile holds TWO cameras and the first build was made
-- against the wrong one: the predecessor, with a 45-degree roll and a drift zoom, which
-- nothing in the reference runs. The user drove it -- "it spins/rotates wayyyyy to far" --
-- and that was the roll. The game's camera has NO ROLL, NO ZOOM and NO POSITION
-- SMOOTHING. If any of the three comes back, it is the wrong camera again.
--
-- What it is, all four parts:
--
--   1. IT LOOKS AT A POINT JUST AHEAD OF THE CAR (`CamLookAt`), with only that point's
--      HEIGHT eased (`CamHeightRate`), so a crest does not throw the horizon about. It
--      looks AT the car, which is why the horizon is always level.
--   2. IT KEEPS A FIXED RADIUS. The camera is placed at `|CamOffset|` from the car, in a
--      direction that eases toward the resting direction at `CamAngleRate`. The
--      DIRECTION eases, never the position: the camera swings around the car rather than
--      being dragged behind it. That is the dial that decides whether the car rotates in
--      front of the camera or stays pinned to it.
--   3. IT LEANS TOWARD WHERE THE CAR IS GOING as the slip opens, by an ease-in-out of
--      |slip| / 180 deg toward a point behind the car's TRAVEL, and then only
--      `CamVelocityBlend` of that lean is taken. 0.05 is not a typo: the leaned target is
--      what the next frame's resting direction is measured from, so the 5% compounds, and
--      what it buys is the camera dropping and swinging wide through a drift.
--   4. THE FOV OPENS WITH SPEED: `CamFovBase + CamFovPerSpeed * speed`, eased at
--      `CamFovRate`.
--
-- The camera is PLACED at its target each frame and told to look at the look-at point.
-- There is no spring and no look easing: all the easing there is lives inside how the
-- target is worked out. On a run ending the camera lets go (`Release`) and holds its last
-- target.
--
-- Offsets are in the car's own flat axes: +x right, +y up, +z BEHIND. The car's pitch and
-- roll are deliberately NOT in that basis -- the camera follows the heading and the height
-- only.
--
-- THE TARGETS RUN ON A FIXED STEP (`CamTargetStep`), and they have to. Part 3 feeds its
-- own output back in as part 2's input, so where the camera settles depends on how often
-- it is stepped; left at frame rate it sat 16.2 studs above a drifting car at 30 FPS and
-- 10.1 at 120, which is two players getting different games. The rendered camera is
-- interpolated between steps, so a 144 Hz screen still gets its own smooth motion. The FOV
-- has no feedback and is eased once a frame.
--
-- Every number is in Config.Drift; none is in here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local DriftModel = require(DriftFolder.Model)
-- The car is drawn at the frame's own moment rather than at the last completed step, and
-- the camera asks Render for that same carried-forward pose so the two never disagree
-- about where the car is (T-025).
local Render = require(DriftFolder.Render)

local DriftController = require(script.Parent.DriftController)

local CarCameraController = {}

CarCameraController.Priority = 5 -- after DriftController, so a state exists to follow

local STEP_NAME = "DriftCamera"
local EPS = 1e-4

-- What the camera needs of the car, and nothing else. Built from the model's state, or
-- made up by DebugProbe, which is how the curves below are measured without a car.
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
-- at frame rate inside a fixed-step loop, and it is how the camera ends up depending on
-- frame rate even once its geometry does not.
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

-- Public so a test can settle a camera of its own against a made-up car without touching
-- the live one (ServerScriptService/Tests/JitterTests, DebugProbe).
function CarCameraController.newRig(view: View?)
	local rig = {
		ready = false,
		position = Vector3.zero,
		lookPoint = Vector3.zero, -- where it is actually looking this frame
		lookTarget = Vector3.zero,
		velTarget = Vector3.zero,
		restTarget = Vector3.zero, -- behind the nose: what the lean is measured from
		target = Vector3.zero, -- after the lean
		lastTarget = Vector3.zero,
		lastCarPos = Vector3.zero,
		fov = Config.Drift.CamFovBase,
		released = false,
		-- The fixed-step accumulator, and the step before the current one, so a frame that
		-- lands between two steps is rendered between them rather than on whichever step
		-- happened last.
		accumulator = 0,
		prevTarget = Vector3.zero,
		prevLookTarget = Vector3.zero,
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
	rig.restTarget = carPoint(view, C.CamOffset)
	rig.velTarget = rig.restTarget
	rig.target = rig.restTarget
	rig.position = rig.restTarget
	rig.lookPoint = rig.lookTarget
	rig.lastTarget = rig.restTarget
	rig.lastCarPos = view.position
	rig.fov = C.CamFovBase + C.CamFovPerSpeed * view.speed
	rig.accumulator = 0
	rig.prevTarget = rig.target
	rig.prevLookTarget = rig.lookTarget
	rig.lastView = view
	rig.ready = true
end

-- One fixed step of the targets, and nothing else. `dt` here is always `CamTargetStep`.
local function stepTargets(rig, view: View, dt: number)
	local C = Config.Drift
	if rig.released then
		return -- a run has ended: hold whatever the targets last were
	end

	-- (1) The look-at: ahead of the nose, with only its HEIGHT eased. A car cresting a
	-- jump keeps the horizon still while the camera itself follows the car up.
	local wantLook = carPoint(view, C.CamLookAt)
	rig.lookTarget = Vector3.new(
		wantLook.X,
		rig.lookTarget.Y + (wantLook.Y - rig.lookTarget.Y) * ease(dt, C.CamHeightRate),
		wantLook.Z
	)

	-- (2) The resting place: `|CamOffset|` from the car, in a direction that follows the
	-- car round at `CamAngleRate`. The length is always the offset's own length, so easing
	-- the direction can never change how far away the camera is -- it swings around the
	-- car instead of being dragged behind it.
	local wantDir = safeUnit(carPoint(view, C.CamOffset) - view.position, Vector3.yAxis)
	local haveDir = safeUnit(rig.lastTarget - rig.lastCarPos, wantDir)
	local dir = safeUnit(haveDir:Lerp(wantDir, ease(dt, C.CamAngleRate)), wantDir)
	rig.restTarget = view.position + dir * C.CamOffset.Magnitude

	-- (3) The lean. A point the same height and the same distance behind, but behind the
	-- VELOCITY instead of the nose, hung off the look-at point rather than off the car. It
	-- follows at `CamSwingRate`, so it is always a long way behind the truth at speed --
	-- which is part of why the blend below is small.
	local flatVel = Vector3.new(view.velocity.X, 0, view.velocity.Z)
	local fwd = DriftModel.axes(view.yaw)
	local back = safeUnit(-flatVel, -fwd)
	local wantVel = rig.lookTarget + back * C.CamOffset.Z + Vector3.yAxis * C.CamOffset.Y
	rig.velTarget = rig.velTarget:Lerp(wantVel, ease(dt, C.CamSwingRate))

	-- ...and only `CamVelocityBlend` of it is taken. Small because it compounds: the next
	-- line is what the next step's `haveDir` is measured from.
	local leanT = easeInOut(math.abs(math.deg(view.slip)) / 180)
	rig.target = rig.restTarget:Lerp(rig.restTarget:Lerp(rig.velTarget, leanT), C.CamVelocityBlend)

	rig.lastTarget = rig.target
	rig.lastCarPos = view.position
end

-- One frame. Returns the camera's CFrame.
function CarCameraController._advance(rig, view: View, dt: number): CFrame
	local C = Config.Drift
	if not rig.ready then
		CarCameraController._seed(rig, view)
	end
	dt = math.clamp(dt, 0, 0.25) -- a loading hitch must not teleport the camera

	-- The targets, in whole fixed steps (see the header). The car's own pose is whatever
	-- this frame says it is: the camera samples the car at frame rate, and only the
	-- camera's own feedback is held to the step.
	--
	-- EACH STEP IS FED THE CAR AS IT WAS AT THAT STEP'S OWN MOMENT (T-025). A step does not
	-- fall at an even share of the frame: it falls where the accumulator crosses the step,
	-- which depends on what was left over from the frame before. Feeding it `i / steps`
	-- instead -- an even share -- files the car's position under the wrong instant by up to
	-- a whole frame, and a target built at the wrong instant is a camera that creeps and
	-- snaps even when the car it is following is perfectly smooth. Measured on a 100 Hz
	-- clock: 1.07 studs of camera movement a frame that the car had not made.
	local step = math.max(C.CamTargetStep, EPS)
	local before = rig.accumulator
	rig.accumulator = math.min(rig.accumulator + dt, step * math.max(C.CamMaxTargetSteps, 1))
	-- What the frame actually contributed, which is `dt` unless the clamp above ate some
	-- of it; either way it is the span the fractions below are measured against.
	local span = math.max(rig.accumulator - before, EPS)
	local steps = math.floor(rig.accumulator / step)
	local from = rig.lastView or view
	for i = 1, steps do
		rig.prevTarget, rig.prevLookTarget = rig.target, rig.lookTarget
		stepTargets(rig, lerpView(from, view, math.clamp((i * step - before) / span, 0, 1)), step)
		rig.accumulator -= step
	end
	rig.steps = steps
	rig.lastView = view

	-- ...and the frame is rendered between the last two of them, so a 90 or a 144 Hz
	-- screen gets its own smooth motion out of a 60 Hz target.
	local alpha = math.clamp(rig.accumulator / step, 0, 1)
	rig.position = rig.prevTarget:Lerp(rig.target, alpha)
	rig.lookPoint = rig.prevLookTarget:Lerp(rig.lookTarget, alpha)

	-- The FOV has no feedback in it, so it is eased once a frame.
	local wantFov = C.CamFovBase + C.CamFovPerSpeed * view.speed
	rig.fov += (wantFov - rig.fov) * ease(dt, C.CamFovRate)

	-- Placed, not eased into place, and looking AT the car: the horizon is level because
	-- nothing ever rolls it.
	local toLook = rig.lookPoint - rig.position
	if toLook.Magnitude < EPS then
		return CFrame.new(rig.position)
	end
	return CFrame.lookAt(rig.position, rig.lookPoint)
end

-- How far the lean actually moved the camera's target, in studs.
local function leanStuds(rig): number
	return (rig.target - rig.restTarget).Magnitude
end

-- ---------------------------------------------------------------- lifecycle

-- The car as the camera sees it, AT THE FRAME'S OWN MOMENT -- the last completed step
-- carried across whatever the simulation's accumulator has left over, which is exactly the
-- pose Render draws the car at (T-025). Following `state.position` instead means the
-- camera chases a car that is quantised to 1/120 while the car on screen is not, and the
-- two disagree by up to 1.49 studs: the car shimmers against its own camera even though
-- both are individually smooth.
local function viewFrom(state, rem: number): View?
	if not state then
		return nil
	end
	local position, yaw = Render.subStep(state, rem)
	return {
		position = position,
		yaw = yaw,
		velocity = state.velocity,
		slip = state.slip,
		speed = DriftModel.speed(state),
	}
end

function CarCameraController:Init()
	self.rig = CarCameraController.newRig()
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
	local view = viewFrom(DriftController:CurrentState(), DriftController:SubStep())
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
	local cf = self.camera and self.camera.CFrame or nil
	return {
		hasCamera = self.camera ~= nil,
		cameraType = self.camera and self.camera.CameraType.Name or "none",
		ready = rig.ready,
		released = rig.released,
		position = rig.position,
		lookPoint = rig.lookPoint,
		fieldOfView = rig.fov,
		-- There is no roll in this camera. Measured off the real CFrame rather than
		-- asserted, so a test can prove it rather than take its word for it.
		rollDeg = if cf then math.deg(math.asin(math.clamp(cf.RightVector.Y, -1, 1))) else nil,
		leanStuds = leanStuds(rig),
		slipDeg = state and math.deg(state.slip) or nil,
		speed = state and DriftModel.speed(state) or nil,
		distanceToCar = carPos and (rig.position - carPos).Magnitude or nil,
		heightAboveCar = carPos and (rig.position.Y - carPos.Y) or nil,
		stepsLastFrame = rig.steps,
	}
end

-- Settle a throwaway rig against a car held at a fixed slip angle, and report what the
-- camera does there. This is how the curves are measured: no car, no Workspace and no
-- waiting.
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
	local view: View = {
		position = Vector3.new(0, C.RideHeight, 0),
		yaw = yaw,
		velocity = (CFrame.Angles(0, slip, 0) * fwd).Unit * speed,
		slip = slip,
		speed = speed,
	}

	local was = C.CamVelocityBlend
	if opts.blend then
		C.CamVelocityBlend = opts.blend
	end

	local rig = CarCameraController.newRig(view)
	local maxPosStep, maxLookStep, maxRollDeg = 0, 0, 0
	local prevPos, prevLook = rig.position, rig.lookPoint
	local steps = math.floor(seconds * fps)
	local settled = math.floor(steps * 0.75) -- the jitter numbers ignore the settling in
	local ok, err = pcall(function()
		for i = 1, steps do
			local s = slip
			if opts.sweepSeconds then
				s = slip * math.sin(2 * math.pi * (i * dt) / opts.sweepSeconds)
			end
			-- A FRESH table each frame, because the rig keeps the previous frame's view to
			-- interpolate its sub-steps from: handing it the same table mutated in place
			-- would make that interpolation a no-op and hide what it is there to fix.
			view = {
				position = view.position + view.velocity * dt,
				yaw = yaw,
				velocity = (CFrame.Angles(0, s, 0) * fwd).Unit * speed,
				slip = s,
				speed = speed,
			}
			local cf = CarCameraController._advance(rig, view, dt)
			maxRollDeg = math.max(maxRollDeg, math.abs(math.deg(math.asin(math.clamp(cf.RightVector.Y, -1, 1)))))
			if i > settled then
				maxPosStep = math.max(maxPosStep, (rig.position - prevPos - view.velocity * dt).Magnitude)
				maxLookStep = math.max(maxLookStep, (rig.lookPoint - prevLook - view.velocity * dt).Magnitude)
			end
			prevPos, prevLook = rig.position, rig.lookPoint
		end
	end)

	C.CamVelocityBlend = was
	if not ok then
		return { error = tostring(err) }
	end

	local toCar = rig.position - view.position
	-- Where the lean actually took the target, split into the car's own axes.
	local lean = rig.target - rig.restTarget
	local sFwd, sRight = DriftModel.axes(yaw)
	return {
		slipDeg = opts.slipDeg or 0,
		speed = speed,
		blend = opts.blend or was,
		distance = toCar.Magnitude,
		height = toCar.Y,
		flatDistance = Vector3.new(toCar.X, 0, toCar.Z).Magnitude,
		maxRollDeg = maxRollDeg, -- must be 0: this camera has no roll
		leanStuds = leanStuds(rig),
		leanSideways = lean:Dot(sRight), -- + is out to the car's right
		leanBackwards = -lean:Dot(sFwd), -- + is further behind the nose
		leanDown = -lean.Y,
		fullLeanStuds = (rig.velTarget - rig.restTarget).Magnitude, -- before the blend
		fov = rig.fov,
		-- Drift left over after the car's own motion is taken out: anything but ~0 means
		-- the camera has not settled, or is jittering.
		maxPosStep = maxPosStep,
		maxLookStep = maxLookStep,
	}
end

-- Watch the LIVE camera for `seconds` and report the worst frame of it: how far the
-- camera and its look point jumped between frames, how far the view turned, and how far
-- off the centre of the screen the car ever got. Studio only, and it yields.
--
-- It also carries the judder figures (T-025), because the real frame clock is the only
-- place they can honestly be taken -- a headless harness has to make its frame times up,
-- and on the clean ones (30, 60, 120 dead steady) every judder in this game measures zero:
--
--   `jumpStuds`    the car's drawn position, frame to frame, with the frame's own length
--                  divided out. Smooth motion on an uneven clock is zero here; a drawing
--                  that quantises to the simulation step is a whole step of it.
--   `shimmerDeg`   the same for the angle from the camera's look axis to the car, which is
--                  what the player actually watches. About 12 screen pixels a degree on a
--                  1080-line display at this game's field of view.
--   `drawnGapStuds` how far the drawn car is from where the simulation has it at that
--                  frame's moment: the proof that none of the above was bought with lag.
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
		maxRollDeg = 0, -- must stay 0: this camera has no roll
		maxScreenOffsetPx = 0,
		maxScreenOffsetFrac = 0, -- of half the screen's smaller side: 1 is the edge
		offScreenFrames = 0,
		minDistance = math.huge,
		maxDistance = 0,
		maxSlipDeg = 0,
		maxSpeed = 0,
		minFov = math.huge,
		maxFov = 0,
		-- the judder figures
		minDt = math.huge,
		maxDt = 0,
		meanDt = 0,
		maxJumpStuds = 0, -- the car's drawn position, frame length divided out
		maxCameraJumpStuds = 0, -- the camera's own
		maxShimmerDeg = 0, -- the car against the camera's look axis
		maxShimmerPx = 0,
		maxDrawnGapStuds = 0,
	}

	-- The previous frame's steps, kept so this frame can be compared with the frame
	-- length taken out: a long frame moving further is not a jump.
	local prevPos, prevLook, prevDir = nil, nil, nil
	local lastCar, lastCarStep, lastDt = nil, nil, nil
	local lastCamStep, lastAngle, lastAngleStep = nil, nil, nil
	local clock = 0
	while clock < seconds do
		local dt = RunService.RenderStepped:Wait()
		clock += dt
		out.frames += 1
		out.seconds = clock
		out.minDt = math.min(out.minDt, dt)
		out.maxDt = math.max(out.maxDt, dt)
		local cam = self.camera
		if not cam then
			break
		end
		local cf = cam.CFrame
		local pos = cf.Position
		local look = pos + cf.LookVector
		local dir = cf.LookVector
		local scale = if lastDt and lastDt > 1e-9 then dt / lastDt else 1
		if prevPos then
			out.maxPosStep = math.max(out.maxPosStep, (pos - prevPos).Magnitude)
			out.maxLookStep = math.max(out.maxLookStep, (look - prevLook).Magnitude)
			out.maxTurnDeg = math.max(out.maxTurnDeg, math.deg(math.acos(math.clamp(dir:Dot(prevDir), -1, 1))))
			local camStep = pos - prevPos
			if lastCamStep then
				out.maxCameraJumpStuds = math.max(out.maxCameraJumpStuds, (camStep - lastCamStep * scale).Magnitude)
			end
			lastCamStep = camStep
		end
		prevPos, prevLook, prevDir = pos, look, dir
		out.maxRollDeg = math.max(out.maxRollDeg, math.abs(math.deg(math.asin(math.clamp(cf.RightVector.Y, -1, 1)))))
		out.minFov = math.min(out.minFov, cam.FieldOfView)
		out.maxFov = math.max(out.maxFov, cam.FieldOfView)

		local state = DriftController:CurrentState()
		local car = DriftController:Car()
		local body = car and car:FindFirstChild(CarModel.BODY_NAME)
		-- Where the car is actually DRAWN, read off the part in the world rather than off
		-- the model: that is what the player is looking at.
		local drawn = if body and body:IsA("BasePart") then body.Position else state and state.position
		if state and drawn then
			local d = (pos - drawn).Magnitude
			out.minDistance = math.min(out.minDistance, d)
			out.maxDistance = math.max(out.maxDistance, d)
			out.maxSlipDeg = math.max(out.maxSlipDeg, math.abs(math.deg(state.slip)))
			out.maxSpeed = math.max(out.maxSpeed, DriftModel.speed(state))
			out.maxDrawnGapStuds = math.max(out.maxDrawnGapStuds, DriftController:DrawnGap())

			if lastCar then
				local carStep = drawn - lastCar
				if lastCarStep then
					out.maxJumpStuds = math.max(out.maxJumpStuds, (carStep - lastCarStep * scale).Magnitude)
				end
				lastCarStep = carStep
			end
			lastCar = drawn

			-- The angle from the camera's own look axis to the car: the shimmer the player
			-- sees, in degrees and then in pixels off this screen.
			local local3 = cf:PointToObjectSpace(drawn)
			local depth = math.max(-local3.Z, 1e-3)
			local angle = Vector2.new(math.deg(math.atan2(local3.X, depth)), math.deg(math.atan2(local3.Y, depth)))
			if lastAngle then
				local angleStep = angle - lastAngle
				if lastAngleStep then
					local shimmer = (angleStep - lastAngleStep * scale).Magnitude
					out.maxShimmerDeg = math.max(out.maxShimmerDeg, shimmer)
					local size = cam.ViewportSize
					if size.Y > 0 and cam.FieldOfView > 0 then
						out.maxShimmerPx = math.max(out.maxShimmerPx, shimmer * size.Y / cam.FieldOfView)
					end
				end
				lastAngleStep = angleStep
			end
			lastAngle = angle

			local point, onScreen = cam:WorldToViewportPoint(drawn)
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
		lastDt = dt
	end
	if out.minDistance == math.huge then
		out.minDistance = 0
	end
	if out.minFov == math.huge then
		out.minFov = 0
	end
	if out.minDt == math.huge then
		out.minDt = 0
	end
	out.meanDt = if out.frames > 0 then out.seconds / out.frames else 0
	return out
end

return CarCameraController
