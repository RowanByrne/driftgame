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
-- AMENDED 2026-11-04 (T-072), honestly: ONE OF THE THREE IS BACK, ON PURPOSE. The roll
-- returns at `CamRollMax = 4` degrees saturating at 45 degrees of slip and chased at rate
-- 6 -- against the predecessor's 45 at 20 chased at 20, which is about a ninth of the
-- gain. The sentence above still holds for the other two and for the SIZE of this one: the
-- shape was never what was wrong, the numbers were, and a roll anywhere near the old gain
-- is the wrong camera again. It is zeroable and zero is exactly the level horizon this
-- file shipped with, proved step for step. THE ZOOM AND THE POSITION SMOOTHING STAY OUT.
--
-- What it is, all four parts (and the two the rendered camera gets on top, below):
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
--      `CamVelocityBlend` of that lean is taken. A tenth is not a typo: the leaned target
--      is what the next step's resting direction is measured from, so it compounds, and
--      what it buys is the camera dropping and swinging wide through a drift.
--   4. THE FOV OPENS WITH SPEED: `CamFovBase + CamFovPerSpeed * speed`, eased at
--      `CamFovRate`.
--
-- T-071 moved three of those numbers, and nothing else: the camera is 9.5 studs closer and
-- 7 degrees steeper, the lean takes 0.12 of itself rather than 0.05, and the FOV's swing
-- was reshaped to fall inside the speeds a car is actually driven at. All three are in
-- Config.Camera with the measurements that chose them.
--
-- AND TWO THINGS SIT ON TOP OF ALL FOUR (T-072), the style the user asked for:
--
--   5. A TOUCH OF ROLL. The camera banks into the corner with the slide, by a clamped
--      linear reading of the slip angle eased at `CamRollRate`. See the amendment above:
--      this is the predecessor's formula at a ninth of its gain, and the gain is the
--      whole difference between a lean and the thing that was rejected.
--   6. THE SPEED SHAKE, the reference's own (`CameraShake.cs`): a new random rotation and
--      position kick every `ShakePeriod`, scaled by speed as a share of the car's top
--      speed, decaying toward zero between kicks at `ShakeRestoreRate`. Busy at speed,
--      invisible at a standstill.
--
-- BOTH ARE APPLIED TO THE RENDERED CAMERA, downstream of the fixed-step targets, exactly
-- as the pan is -- `rig.position` and `rig.lookPoint` never see either of them, so neither
-- can join the feedback loop in part 3. That is why they do not have to be stepped.
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
-- THE PAN (T-036) is the player's own hand on top of all of that, and it is an ORBIT, not
-- a second aim. The right mouse button held and dragged turns a yaw and a pitch offset
-- that the camera's placed position is rotated by ABOUT THE CAR, at the same fixed radius,
-- still looking at the same look-at point. So the car stays centred and followed, the lean
-- and the FOV keep doing exactly what they did, and the player is only moving round the
-- car to see something.
--
-- It is applied to the RENDERED position, after the fixed-step targets are done with, and
-- it is written nowhere the targets can read it. That is the whole reason it cannot
-- disturb the camera: part 3 feeds back into part 2, and the pan is downstream of both.
-- `_advance` with no pan argument -- which is how the tests call it -- is the camera
-- exactly as it was.
--
-- Let go and it comes back: a moment's grace (`CamPanReturnDelay`) so a nudge of the mouse
-- does not snap the view out of the player's hand, and then an ease home. The input itself
-- is eased too, lightly: "smoothened slightly ... a bit cinematic" is the brief, and this
-- camera is already calm, so a heavy filter here reads as lag rather than as cinema.
--
-- Every number is in Config.Camera; none is in here (T-071: they moved out of
-- Config.Drift, name for name, because the camera is a look and not the model).

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

-- EVERY NUMBER THE CAMERA USES IS IN HERE, and it is a different file from the model's
-- (T-071): the camera reads `Drift/Model`'s state and writes nothing, so its numbers are a
-- look rather than a simulation. The keys kept their `Cam` prefix when they moved, so
-- `Cam.CamOffset` reads oddly and every other line about this camera still says the thing
-- it always said. `Config.Drift` is still reached for the CAR's own numbers -- `TopSpeed`
-- and `RideHeight`, in the probes at the bottom -- and for nothing else.
local Cam = Config.Camera

local CarCameraController = {}

CarCameraController.Priority = 5 -- after DriftController, so a state exists to follow

local STEP_NAME = "DriftCamera"
local EPS = 1e-4

-- The shake's random sequence is seeded (T-072), so the same drive shakes the same way
-- twice and a measurement means something. See `newRig`.
local SHAKE_SEED = 20261104

-- The pan's numbers are Config's, like everything else here: `CamPanSensitivity`,
-- `CamPanRate`, `CamPanReturnDelay`, `CamPanReturnRate`, and the four limits. The four
-- angles are DEGREES in Config, because degrees are what the tuning conversation uses, and
-- are converted here once rather than on every frame.
local PanPitchMin = math.rad(Cam.CamPanPitchMin)
local PanPitchMax = math.rad(Cam.CamPanPitchMax)
local PanElevationMin = math.rad(Cam.CamPanElevationMin)
local PanElevationMax = math.rad(Cam.CamPanElevationMax)

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
		fov = Cam.CamFovBase,
		released = false,
		-- The fixed-step accumulator, and the step before the current one, so a frame that
		-- lands between two steps is rendered between them rather than on whichever step
		-- happened last.
		accumulator = 0,
		prevTarget = Vector3.zero,
		prevLookTarget = Vector3.zero,
		steps = 0,
		lastView = nil, -- the car as the previous frame saw it, for the sub-step lerp
		-- The pan: where the player's hand has put the view (`panTarget*`) and where the
		-- view has eased to (`pan*`). Both are offsets, both are zero when nobody is
		-- panning, and NOTHING above this line ever reads them.
		panYaw = 0,
		panPitch = 0,
		panTargetYaw = 0,
		panTargetPitch = 0,
		panHeld = false,
		panIdle = 0, -- seconds since the button came up, for the grace
		-- The style (T-072), and the same rule as the pan: all of it is applied to the
		-- RENDERED camera and NOTHING ABOVE THIS LINE EVER READS IT.
		roll = 0, -- radians, signed, what the horizon is actually leaning by
		shakeRot = Vector3.zero, -- radians of pitch, yaw and roll, in the camera's axes
		shakePos = Vector3.zero, -- studs, in the camera's axes
		shakeTimer = 0, -- toward the next kick
		-- SEEDED, so a probe measures the same shake twice and 30, 60 and 120 FPS get the
		-- same kicks. Nobody can tell a fixed seed from a random one at twenty kicks a
		-- second, and a test can.
		shakeRng = Random.new(SHAKE_SEED),
	}
	if view then
		CarCameraController._seed(rig, view)
	end
	return rig
end

-- Start where the camera would have settled, so the first frame of a run is not a swoop
-- in from the origin.
function CarCameraController._seed(rig, view: View)
	rig.lookTarget = carPoint(view, Cam.CamLookAt)
	rig.restTarget = carPoint(view, Cam.CamOffset)
	rig.velTarget = rig.restTarget
	rig.target = rig.restTarget
	rig.position = rig.restTarget
	rig.lookPoint = rig.lookTarget
	rig.lastTarget = rig.restTarget
	rig.lastCarPos = view.position
	rig.fov = Cam.CamFovBase + Cam.CamFovPerSpeed * view.speed
	rig.accumulator = 0
	rig.prevTarget = rig.target
	rig.prevLookTarget = rig.lookTarget
	rig.lastView = view
	rig.panYaw, rig.panPitch = 0, 0
	rig.panTargetYaw, rig.panTargetPitch = 0, 0
	rig.panHeld, rig.panIdle = false, 0
	rig.roll = 0
	rig.shakeRot, rig.shakePos, rig.shakeTimer = Vector3.zero, Vector3.zero, 0
	rig.shakeRng = Random.new(SHAKE_SEED)
	rig.ready = true
end

-- ---------------------------------------------------------------- the pan

-- An angle brought back inside -pi .. pi, so the view always comes home the short way
-- round however far the player dragged it.
local function wrapPi(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- One frame of the player's hand. `pan` is `{ held, dx, dy }` in PIXELS, drained from
-- CarInputController, or nil for "nobody is panning" -- which is what every headless
-- caller passes, and which costs nothing once the offsets are home.
local function stepPan(rig, dt: number, pan)
	if pan and pan.held then
		rig.panHeld = true
		rig.panIdle = 0
		-- Mouse right turns the view right, mouse down looks down, the way Roblox's own
		-- camera does. The view turning right is the camera swinging the other way round
		-- the car, hence the minus.
		rig.panTargetYaw = wrapPi(rig.panTargetYaw - pan.dx * Cam.CamPanSensitivity)
		rig.panTargetPitch = math.clamp(rig.panTargetPitch + pan.dy * Cam.CamPanSensitivity, PanPitchMin, PanPitchMax)
	else
		rig.panHeld = false
		if rig.panTargetYaw ~= 0 or rig.panTargetPitch ~= 0 then
			rig.panIdle += dt
			if rig.panIdle >= Cam.CamPanReturnDelay then
				local home = ease(dt, Cam.CamPanReturnRate)
				rig.panTargetYaw -= rig.panTargetYaw * home
				rig.panTargetPitch -= rig.panTargetPitch * home
				-- Land exactly, so a rig that is home stops doing arithmetic for ever.
				if math.abs(rig.panTargetYaw) < 1e-5 and math.abs(rig.panTargetPitch) < 1e-5 then
					rig.panTargetYaw, rig.panTargetPitch = 0, 0
				end
			end
		end
	end

	local k = ease(dt, Cam.CamPanRate)
	rig.panYaw = wrapPi(rig.panYaw + wrapPi(rig.panTargetYaw - rig.panYaw) * k)
	rig.panPitch += (rig.panTargetPitch - rig.panPitch) * k
end

-- Swing the placed camera round the car by the pan, at the radius it already has. The
-- RADIUS IS PRESERVED EXACTLY -- the whole camera is built on a fixed distance from the
-- car -- and the look point is not touched, so the car stays centred.
local function applyPan(rig, carPos: Vector3)
	if math.abs(rig.panYaw) < 1e-5 and math.abs(rig.panPitch) < 1e-5 then
		return
	end
	local o = rig.position - carPos
	local radius = o.Magnitude
	if radius < EPS then
		return
	end
	local flat = Vector3.new(o.X, 0, o.Z)
	local dir = if flat.Magnitude > EPS then flat.Unit else Vector3.zAxis
	local elevation = math.atan2(o.Y, flat.Magnitude)
	-- The offset is clamped as the player drags it; the RESULT is clamped again here,
	-- because the camera's own elevation moves too (the lean drops it through a drift) and
	-- it is the sum that must never be under the road or straight down the roof.
	-- The guard never makes the shot worse than the camera had it on its own: if the lean
	-- has already taken it below the floor, that is where the floor is for this frame.
	-- Otherwise the first pixel of a pan would snap the view up to the limit.
	local floor = math.min(PanElevationMin, elevation)
	local ceiling = math.max(PanElevationMax, elevation)
	elevation = math.clamp(elevation + rig.panPitch, floor, ceiling)
	dir = CFrame.Angles(0, rig.panYaw, 0) * dir
	rig.position = carPos + dir * (radius * math.cos(elevation)) + Vector3.yAxis * (radius * math.sin(elevation))
end

-- -------------------------------------------------------- the roll and the shake (T-072)
--
-- Both live down here with the pan rather than up with the targets, and that is the whole
-- design: they are applied to the RENDERED camera, they are stored in fields nothing above
-- this line reads, and so they cannot feed back into where the camera sits. Anything that
-- fed back would have to be stepped (see the header); the cheapest way not to think about
-- it is not to feed back.

-- How far the camera should be leaning, in radians, signed.
--
-- The sign is the one thing here that is a judgement. `view.slip` positive is the car
-- travelling out to its LEFT -- which is a RIGHT-hand drift, because the nose is turned
-- into the corner while the tail goes out to the left -- and the camera banks RIGHT with
-- it, into the corner, the way a motorcycle or an aircraft does. A camera's right vector
-- going DOWN is a right bank, so the target is negative for a positive slip. A negative
-- `CamRollMax` is the other convention, and it is one character.
local function rollTarget(view: View): number
	local at = Cam.CamRollAtAngle
	if Cam.CamRollMax == 0 or at <= 0 then
		return 0
	end
	return -math.rad(Cam.CamRollMax) * math.clamp(math.deg(view.slip) / at, -1, 1)
end

local function stepRoll(rig, dt: number, view: View)
	local want = rollTarget(view)
	-- Zeroed, this is not an easing toward zero that takes a while: `rig.roll` was never
	-- anything but zero, so the camera is bit for bit the one that has no roll.
	if want == 0 and rig.roll == 0 then
		return
	end
	rig.roll += (want - rig.roll) * ease(dt, Cam.CamRollRate)
	if want == 0 and math.abs(rig.roll) < 1e-6 then
		rig.roll = 0 -- land exactly, so a car driven straight stops rolling for ever
	end
end

-- The shake decays by an EXACT exponential, `exp(-rate * dt)`, which composes: two half
-- steps leave it exactly where one whole step would. That is what makes the shake land in
-- the same place at 30, 60 and 120 FPS, and it is why the stepping below bothers to split
-- a frame at the moment a kick falls rather than kicking once a frame.
local function decayShake(rig, dt: number)
	local k = math.exp(-dt * math.max(Cam.ShakeRestoreRate, 0))
	rig.shakeRot *= k
	rig.shakePos *= k
end

-- A new kick, scaled by speed as a share of the CAR's top speed -- the reference scales by
-- its own car's max speed, so a faster car does not shake harder at the same speed.
local function kickShake(rig, speed: number)
	local top = Config.Drift.TopSpeed
	local t = if top and top > EPS then math.clamp(speed / top, 0, 1) else 0
	local rng = rig.shakeRng
	local rot = Cam.ShakeRotation * t
	local pos = Cam.ShakePosition * t
	rig.shakeRot = Vector3.new(
		math.rad(rot.X) * rng:NextNumber(-1, 1),
		math.rad(rot.Y) * rng:NextNumber(-1, 1),
		math.rad(rot.Z) * rng:NextNumber(-1, 1)
	)
	rig.shakePos =
		Vector3.new(pos.X * rng:NextNumber(-1, 1), pos.Y * rng:NextNumber(-1, 1), pos.Z * rng:NextNumber(-1, 1))
end

-- One frame of the shake, on its own clock. A frame longer than `ShakePeriod` takes every
-- kick it is owed, each at its own moment, so the sequence does not depend on the frame
-- rate -- and neither does what it has decayed to by the time the frame is drawn.
local function stepShake(rig, dt: number, speed: number)
	if Cam.ShakeRotation.Magnitude <= 0 and Cam.ShakePosition.Magnitude <= 0 then
		-- Zeroed: nothing to decay, nothing to choose, and the rendered camera is
		-- untouched. The random sequence is not advanced either, so a zeroed run is
		-- repeatable to the bit.
		rig.shakeRot, rig.shakePos, rig.shakeTimer = Vector3.zero, Vector3.zero, 0
		return
	end
	local period = math.max(Cam.ShakePeriod, EPS)
	local left = dt
	local guard = 0
	while rig.shakeTimer + left >= period and guard < 64 do
		guard += 1
		local toKick = period - rig.shakeTimer
		decayShake(rig, toKick)
		left -= toKick
		rig.shakeTimer = 0
		kickShake(rig, speed)
	end
	decayShake(rig, left)
	rig.shakeTimer += left
end

-- One fixed step of the targets, and nothing else. `dt` here is always `CamTargetStep`.
local function stepTargets(rig, view: View, dt: number)
	if rig.released then
		return -- a run has ended: hold whatever the targets last were
	end

	-- (1) The look-at: ahead of the nose, with only its HEIGHT eased. A car cresting a
	-- jump keeps the horizon still while the camera itself follows the car up.
	local wantLook = carPoint(view, Cam.CamLookAt)
	rig.lookTarget = Vector3.new(
		wantLook.X,
		rig.lookTarget.Y + (wantLook.Y - rig.lookTarget.Y) * ease(dt, Cam.CamHeightRate),
		wantLook.Z
	)

	-- (2) The resting place: `|CamOffset|` from the car, in a direction that follows the
	-- car round at `CamAngleRate`. The length is always the offset's own length, so easing
	-- the direction can never change how far away the camera is -- it swings around the
	-- car instead of being dragged behind it.
	local wantDir = safeUnit(carPoint(view, Cam.CamOffset) - view.position, Vector3.yAxis)
	local haveDir = safeUnit(rig.lastTarget - rig.lastCarPos, wantDir)
	local dir = safeUnit(haveDir:Lerp(wantDir, ease(dt, Cam.CamAngleRate)), wantDir)
	rig.restTarget = view.position + dir * Cam.CamOffset.Magnitude

	-- (3) The lean. A point the same height and the same distance behind, but behind the
	-- VELOCITY instead of the nose, hung off the look-at point rather than off the car. It
	-- follows at `CamSwingRate`, so it is always a long way behind the truth at speed --
	-- which is part of why the blend below is small.
	local flatVel = Vector3.new(view.velocity.X, 0, view.velocity.Z)
	local fwd = DriftModel.axes(view.yaw)
	local back = safeUnit(-flatVel, -fwd)
	local wantVel = rig.lookTarget + back * Cam.CamOffset.Z + Vector3.yAxis * Cam.CamOffset.Y
	rig.velTarget = rig.velTarget:Lerp(wantVel, ease(dt, Cam.CamSwingRate))

	-- ...and only `CamVelocityBlend` of it is taken. Small because it compounds: the next
	-- line is what the next step's `haveDir` is measured from. Measured, 0.12 settles the
	-- camera 93% of the way round to the travel in a sustained 60-degree drift and 52% of
	-- the way one second in, which is the figure that matters (Config.Camera).
	local leanT = easeInOut(math.abs(math.deg(view.slip)) / 180)
	rig.target = rig.restTarget:Lerp(rig.restTarget:Lerp(rig.velTarget, leanT), Cam.CamVelocityBlend)

	rig.lastTarget = rig.target
	rig.lastCarPos = view.position
end

-- One frame. Returns the camera's CFrame.
function CarCameraController._advance(rig, view: View, dt: number, pan): CFrame
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
	local step = math.max(Cam.CamTargetStep, EPS)
	local before = rig.accumulator
	rig.accumulator = math.min(rig.accumulator + dt, step * math.max(Cam.CamMaxTargetSteps, 1))
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

	-- The player's own hand, LAST: downstream of every target, so the fixed-step feedback
	-- above cannot see it and the camera is unchanged whenever nobody is panning.
	stepPan(rig, dt, pan)
	applyPan(rig, view.position)

	-- The FOV has no feedback in it, so it is eased once a frame.
	local wantFov = Cam.CamFovBase + Cam.CamFovPerSpeed * view.speed
	rig.fov += (wantFov - rig.fov) * ease(dt, Cam.CamFovRate)

	-- The style, LAST and on the rendered camera only (T-072): the roll leans the horizon
	-- with the slide and the shake buzzes at speed. Neither is written anywhere a target
	-- can read it, which is the whole reason they do not need the fixed step.
	stepRoll(rig, dt, view)
	stepShake(rig, dt, view.speed)

	-- Placed, not eased into place, and looking AT the car. The horizon is level until the
	-- roll leans it, and with `CamRollMax` at zero nothing below this line runs at all.
	local toLook = rig.lookPoint - rig.position
	if toLook.Magnitude < EPS then
		return CFrame.new(rig.position)
	end
	local cf = CFrame.lookAt(rig.position, rig.lookPoint)
	if rig.roll ~= 0 then
		cf *= CFrame.Angles(0, 0, rig.roll)
	end
	-- The shake's position is in the camera's OWN axes and is a rendered offset: it moves
	-- the picture, never `rig.position`, so the next step's geometry is untouched.
	if rig.shakePos ~= Vector3.zero then
		cf *= CFrame.new(rig.shakePos)
	end
	if rig.shakeRot ~= Vector3.zero then
		cf *= CFrame.Angles(rig.shakeRot.X, rig.shakeRot.Y, rig.shakeRot.Z)
	end
	return cf
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

	-- Required HERE and not at the top of the file: this is the client's own lifecycle,
	-- and JitterTests requires this module on the SERVER to settle a rig of its own. A
	-- top-level require would drag the whole input stack, its GUI and its WaitForChilds
	-- onto the server with it.
	self._input = require(script.Parent.CarInputController)

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
	-- Drained once a frame, here and nowhere else.
	local pan = if self._input then self._input:PanInput() else nil
	camera.CFrame = CarCameraController._advance(self.rig, view, dt, pan)
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
		-- The roll (T-072), MEASURED OFF THE REAL CFRAME rather than asserted, which is
		-- how `rollDeg` proved there was none before there was any. It reads a little
		-- under `rolledDeg` because the camera is pitched down and some of a roll about
		-- the look axis goes into the pitch rather than the horizon.
		rollDeg = if cf then math.deg(math.asin(math.clamp(cf.RightVector.Y, -1, 1))) else nil,
		rolledDeg = math.deg(rig.roll), -- what the camera was actually told to roll by
		-- The shake (T-072): the kick currently applied, decayed to where it is now.
		shakeRotDeg = Vector3.new(
			math.deg(rig.shakeRot.X),
			math.deg(rig.shakeRot.Y),
			math.deg(rig.shakeRot.Z)
		),
		shakePosStuds = rig.shakePos,
		leanStuds = leanStuds(rig),
		slipDeg = state and math.deg(state.slip) or nil,
		speed = state and DriftModel.speed(state) or nil,
		distanceToCar = carPos and (rig.position - carPos).Magnitude or nil,
		heightAboveCar = carPos and (rig.position.Y - carPos.Y) or nil,
		stepsLastFrame = rig.steps,
		-- The pan: what the hand asked for, what the view has eased to, and where that
		-- leaves the camera above the car.
		panHeld = rig.panHeld,
		panYawDeg = math.deg(rig.panYaw),
		panPitchDeg = math.deg(rig.panPitch),
		panTargetYawDeg = math.deg(rig.panTargetYaw),
		panTargetPitchDeg = math.deg(rig.panTargetPitch),
		panIdle = rig.panIdle,
		elevationDeg = if carPos
			then math.deg(
				math.atan2(
					rig.position.Y - carPos.Y,
					Vector3.new(rig.position.X - carPos.X, 0, rig.position.Z - carPos.Z).Magnitude
				)
			)
			else nil,
	}
end

-- Settle a throwaway rig against a car held at a fixed slip angle, and report what the
-- camera does there. This is how the curves are measured: no car, no Workspace and no
-- waiting.
--
-- `opts`: { slipDeg, speed, seconds, fps, blend, config, yawDeg, sweepSeconds }. `config`
-- is a table of Camera numbers to use for this run only, which is how the zeroed camera is
-- measured beside the shipped one. `blend` overrides
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

	local was = Cam.CamVelocityBlend
	if opts.blend then
		Cam.CamVelocityBlend = opts.blend
	end
	-- Any other camera number, for the length of this run only (T-072): `config =
	-- { CamRollMax = 0, ShakeRotation = Vector3.zero }` is how the zeroed camera is
	-- measured beside the shipped one without editing a file between the two.
	local saved = {}
	if opts.config then
		for key, value in opts.config do
			saved[key] = Cam[key]
			Cam[key] = value
		end
	end

	local rig = CarCameraController.newRig(view)
	local maxPosStep, maxLookStep, maxRollDeg, maxRollStepDeg = 0, 0, 0, 0
	local prevRollDeg = 0
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
			local rollDeg = math.deg(math.asin(math.clamp(cf.RightVector.Y, -1, 1)))
			if math.abs(rollDeg) > math.abs(maxRollDeg) then
				maxRollDeg = rollDeg -- SIGNED, so the probe says which way it leans
			end
			if i > 1 then
				maxRollStepDeg = math.max(maxRollStepDeg, math.abs(rollDeg - prevRollDeg))
			end
			prevRollDeg = rollDeg
			if i > settled then
				maxPosStep = math.max(maxPosStep, (rig.position - prevPos - view.velocity * dt).Magnitude)
				maxLookStep = math.max(maxLookStep, (rig.lookPoint - prevLook - view.velocity * dt).Magnitude)
			end
			prevPos, prevLook = rig.position, rig.lookPoint
		end
	end)

	Cam.CamVelocityBlend = was
	for key, value in saved do
		Cam[key] = value
	end
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
		maxRollDeg = maxRollDeg, -- the furthest the horizon leaned (T-072). Zero with
		-- `CamRollMax` at zero, which is what it measured before
		-- the roll came back
		maxRollStepDeg = maxRollStepDeg, -- the worst single frame of it: the proof that
		-- the roll is a lean and not a flick
		rollDeg = math.deg(rig.roll), -- where it settled, for a slip held steady
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

-- What the shake actually does to the picture, at a speed (T-072). The only honest unit
-- for it is SCREEN PIXELS, because a rotation of the camera and a sideways shift of it an
-- arm's length behind the car are the same thing to the player: both move the whole image.
-- So everything below is reported in degrees of arc AND in pixels of a 1080-line screen at
-- the FOV the camera is actually running at that speed.
--
-- `opts`: { speed, seconds, fps, viewportY, config }. The car is driven straight, because
-- the shake does not care about the slip and a drift would only add the camera's own
-- movement to what is being measured.
function CarCameraController:DebugShakeProbe(opts)
	opts = opts or {}
	local C = Config.Drift
	local speed = opts.speed or C.TopSpeed
	local fps = math.max(opts.fps or 60, 1)
	local dt = 1 / fps
	local seconds = math.clamp(opts.seconds or 10, 0, 60)
	local viewportY = opts.viewportY or 1080
	local yaw = math.rad(15)

	local saved = {}
	if opts.config then
		for key, value in opts.config do
			saved[key] = Cam[key]
			Cam[key] = value
		end
	end

	local fwd = DriftModel.axes(yaw)
	local function viewAt(position)
		return { position = position, yaw = yaw, velocity = fwd * speed, slip = 0, speed = speed }
	end
	local view = viewAt(Vector3.new(0, C.RideHeight, 0))
	local rig = CarCameraController.newRig(view)

	-- The picture's own movement, with the camera's geometry taken out: the angle from the
	-- look axis to a point fixed to the car, which is what the player watches.
	local function aimDeg(cf: CFrame, point: Vector3): Vector2
		local p = cf:PointToObjectSpace(point)
		local depth = math.max(-p.Z, 1e-3)
		return Vector2.new(math.deg(math.atan2(p.X, depth)), math.deg(math.atan2(p.Y, depth)))
	end

	local maxKickDeg, maxKickStuds = 0, 0
	local maxAimStepDeg, meanAimStepDeg, n = 0, 0, 0
	local maxAimDeg = 0
	local prevAim = nil
	local frames = math.floor(seconds * fps)
	for i = 1, frames do
		view = viewAt(view.position + view.velocity * dt)
		local cf = CarCameraController._advance(rig, view, dt)
		maxKickDeg = math.max(maxKickDeg, math.deg(rig.shakeRot.Magnitude))
		maxKickStuds = math.max(maxKickStuds, rig.shakePos.Magnitude)
		-- The car's own point, against the camera: the shake is the only thing moving it,
		-- because a car driven straight sits still on screen once the camera has settled.
		local aim = aimDeg(cf, view.position)
		if i > fps then -- past the settling
			maxAimDeg = math.max(maxAimDeg, aim.Magnitude)
			if prevAim then
				local stepDeg = (aim - prevAim).Magnitude
				maxAimStepDeg = math.max(maxAimStepDeg, stepDeg)
				meanAimStepDeg += stepDeg
				n += 1
			end
		end
		prevAim = aim
	end

	for key, value in saved do
		Cam[key] = value
	end

	local pxPerDeg = viewportY / math.max(rig.fov, 1)
	return {
		speed = speed,
		speedFraction = speed / math.max(C.TopSpeed, 1),
		fps = fps,
		fov = rig.fov,
		pxPerDeg = pxPerDeg,
		maxKickDeg = maxKickDeg, -- the biggest rotation kick that survived to a frame
		maxKickPx = maxKickDeg * pxPerDeg,
		maxKickStuds = maxKickStuds, -- and the biggest position kick
		maxAimStepDeg = maxAimStepDeg, -- how far the car moved on screen in one frame
		maxAimStepPx = maxAimStepDeg * pxPerDeg,
		meanAimStepPx = (if n > 0 then meanAimStepDeg / n else 0) * pxPerDeg,
		maxAimDeg = maxAimDeg, -- and how far off centre it ever got
		maxAimPx = maxAimDeg * pxPerDeg,
	}
end

-- Drag the pan by a measured number of pixels against a car held at a fixed slip, let go,
-- and report what the view did: the angles reached, the limits holding, how long the
-- return takes and its worst single frame. No car, no Workspace, no waiting, and nothing
-- made up -- it runs the same `_advance` the live camera runs, through the same pan input
-- shape CarInputController hands it.
--
-- `opts`: { dxPx, dyPx, dragSeconds, fps, seconds, slipDeg, speed, yawDeg }. The drag is
-- spread evenly over `dragSeconds`, exactly as a real mouse would deliver it.
function CarCameraController:DebugPanProbe(opts)
	opts = opts or {}
	local C = Config.Drift
	local fps = math.max(opts.fps or 60, 1)
	local dt = 1 / fps
	local seconds = math.clamp(opts.seconds or 8, 0, 60)
	local dragSeconds = math.clamp(opts.dragSeconds or 0.5, dt, seconds)
	local dragFrames = math.max(math.floor(dragSeconds * fps), 1)
	local frames = math.floor(seconds * fps)
	local dxPx, dyPx = opts.dxPx or 0, opts.dyPx or 0
	local slip = math.rad(opts.slipDeg or 0)
	local speed = opts.speed or C.TopSpeed
	local yaw = math.rad(opts.yawDeg or 15)

	local fwd = DriftModel.axes(yaw)
	local function viewAt(position)
		return {
			position = position,
			yaw = yaw,
			velocity = (CFrame.Angles(0, slip, 0) * fwd).Unit * speed,
			slip = slip,
			speed = speed,
		}
	end
	local view = viewAt(Vector3.new(0, C.RideHeight, 0))
	local rig = CarCameraController.newRig(view)
	-- A settling second before the drag, so what follows is the camera at rest and not
	-- the seed working itself out.
	for _ = 1, math.floor(fps) do
		view = viewAt(view.position + view.velocity * dt)
		CarCameraController._advance(rig, view, dt, nil)
	end

	local out = {
		dxPx = dxPx,
		dyPx = dyPx,
		fps = fps,
		dragFrames = dragFrames,
		elevationRest = 0,
		yawAtRelease = 0,
		pitchAtRelease = 0,
		yawPeak = 0, -- the furthest the view actually got, after the easing caught up
		pitchPeak = 0,
		targetYaw = 0,
		targetPitch = 0,
		elevationPeak = 0,
		radiusError = 0, -- the pan must never change how far away the camera is
		maxDragStepDeg = 0,
		returnSeconds = -1, -- until both offsets are inside 0.5 deg
		maxReturnStepDeg = 0, -- worst frame-to-frame movement of the view on the way home
		maxReturnStepStuds = 0, -- the same in studs, the car's own motion taken out
		endYawDeg = 0,
		endPitchDeg = 0,
		-- How far the view moved on each of the first frames of the way home. This is the
		-- proof that the return is not a snap: it has to RAMP, because the applied angle
		-- only ever eases toward the target at `CamPanRate`.
		returnTrace = {},
	}

	local before = rig.position - view.position
	out.elevationRest =
		math.deg(math.atan2(before.Y, Vector3.new(before.X, 0, before.Z).Magnitude))
	local restRadius = before.Magnitude

	local prevYaw, prevPitch = 0, 0
	local prevOffset = before
	local released = -1
	for i = 1, frames do
		local pan = nil
		if i <= dragFrames then
			pan = { held = true, dx = dxPx / dragFrames, dy = dyPx / dragFrames }
		end
		view = viewAt(view.position + view.velocity * dt)
		CarCameraController._advance(rig, view, dt, pan)

		local o = rig.position - view.position
		out.radiusError = math.max(out.radiusError, math.abs(o.Magnitude - restRadius))
		local elevation = math.deg(math.atan2(o.Y, Vector3.new(o.X, 0, o.Z).Magnitude))
		out.elevationPeak = math.max(out.elevationPeak, elevation)
		out.elevationFloor = math.min(out.elevationFloor or elevation, elevation)
		if math.abs(rig.panYaw) > math.abs(math.rad(out.yawPeak)) then
			out.yawPeak = math.deg(rig.panYaw)
		end
		if math.abs(rig.panPitch) > math.abs(math.rad(out.pitchPeak)) then
			out.pitchPeak = math.deg(rig.panPitch)
		end
		out.targetYaw = math.max(out.targetYaw, math.abs(math.deg(rig.panTargetYaw)))
		out.targetPitch = if math.abs(math.deg(rig.panTargetPitch)) > math.abs(out.targetPitch)
			then math.deg(rig.panTargetPitch)
			else out.targetPitch

		local stepDeg = Vector2.new(
			math.deg(wrapPi(rig.panYaw - prevYaw)),
			math.deg(rig.panPitch - prevPitch)
		).Magnitude
		-- The camera's own movement with the car's taken out, so a fast car is not
		-- mistaken for a jumpy view.
		local stepStuds = (o - prevOffset).Magnitude
		if i <= dragFrames then
			out.maxDragStepDeg = math.max(out.maxDragStepDeg, stepDeg)
		else
			if released < 0 then
				released = i
				out.yawAtRelease = math.deg(rig.panYaw)
				out.pitchAtRelease = math.deg(rig.panPitch)
			end
			out.maxReturnStepDeg = math.max(out.maxReturnStepDeg, stepDeg)
			out.maxReturnStepStuds = math.max(out.maxReturnStepStuds, stepStuds)
			if #out.returnTrace < 24 then
				table.insert(out.returnTrace, math.floor(stepDeg * 1000 + 0.5) / 1000)
			end
			if
				out.returnSeconds < 0
				and math.abs(math.deg(rig.panYaw)) < 0.5
				and math.abs(math.deg(rig.panPitch)) < 0.5
			then
				out.returnSeconds = (i - released + 1) * dt
			end
		end
		prevYaw, prevPitch, prevOffset = rig.panYaw, rig.panPitch, o
	end
	out.endYawDeg = math.deg(rig.panYaw)
	out.endPitchDeg = math.deg(rig.panPitch)
	return out
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
		maxRollDeg = 0, -- the furthest the horizon leaned (T-072). It was 0 before the
		-- roll came back, and `CamRollMax` at zero puts it back to 0
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
