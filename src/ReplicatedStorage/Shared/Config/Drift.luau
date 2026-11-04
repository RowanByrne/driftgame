--!strict
-- Every tuning number for the drift model, and none of them in the logic
-- (docs/game/features/drift-model.md "Rules and numbers").
--
-- The model is a port of the reference game's: the finger IS the car's yaw rate, nothing
-- moves the velocity when the car rotates, so the slip angle opens on its own and
-- rotating is drifting. A lateral grip force closes it again, growing as a quadratic in
-- the slip angle up to a ceiling, and past 90 degrees of slip it turns into a brake.
-- There is no drift input, no threshold, no mode, no yaw inertia, no yaw damping, no
-- steering lock and no tyre model. If a number that implies one of those turns up in this
-- table, something has drifted from the spec.
--
-- Units: studs, studs/s, studs/s^2, seconds, radians per second, and DEGREES wherever a
-- name says Angle or Slip, because degrees are what the tuning conversation uses. The
-- reference is in metres; everything converted carries 1 stud = 0.28 m (x 3.571).
--
-- Every row of the spec's tables says where its number came from, and so does every
-- comment here: EXACT (written in the reference's own logic), FALLBACK (the value its
-- code declares when an editor asset does not override it, so a credible car but not the
-- shipped one) or OURS. The fallbacks are a starting point to tune from, not decisions.

return {
	-- ---------------------------------------------------------------- the step
	FixedStep = 1 / 120, -- s. OURS. The simulation step, independent of frame rate. The
	-- reference runs 1/60; every term below is written per
	-- second and multiplied by the step, so the two agree
	MaxStepsPerFrame = 16, -- OURS. Safety: never spend more than this many steps on one
	-- frame, so a hitch cannot turn into a spiral
	Gravity = 35, -- studs/s^2. EXACT (9.8 m/s^2). NOT Roblox's 196: the reference turns
	-- the engine's gravity off and applies its own, and the whole feel --
	-- how long a jump hangs, how a crest unloads the car -- is built on it

	-- ---------------------------------------------------------------- steering: the control
	-- THE DIAL THE FEEL CONVERSATION STARTS WITH. Every step the car's yaw rate is SET:
	--     yawRate = MaxSteeringSpeed * steer * SteeringSensitivity
	-- Not a torque, not a wheel angle, not a target to ease toward. Centre the finger and
	-- the car stops turning on the next step. Nothing moves the velocity when the car
	-- rotates, so the slip angle opens by itself: rotating IS drifting.
	MaxSteeringSpeed = 2, -- rad/s. FALLBACK. The car's rate of turn at a full finger:
	-- 115 deg/s. Up for a car that whips round, down for one that
	-- has to be led into a slide. The single biggest feel dial
	SteeringSensitivity = 1, -- OURS/EXACT. Per-car multiplier on the rate of turn, so a
	-- future car list can move one car without moving the model
	InvertSteering = true, -- OURS. Which way a finger turns the car. True is the sense the
	-- user asked for in T-007: a finger to the right swings the
	-- car's REAR right and the nose left, which reads as holding
	-- the car's weight rather than steering its front wheels

	-- ---------------------------------------------------------------- grip: the drift
	-- With any wheel on the ground, and `b` the slip angle (signed, nose to velocity):
	--     f   = min(ConstantFriction + SlipFriction*|b| + SlipSqFriction*|b|^2, MaxFriction)
	--     f   = f * surfaceGrip * FrictionMultiplier            (|b| capped at 90 deg)
	--     dir = |b| > 90 deg and -travel or carRight*sign(b)
	--     velocity += f * dt * dir, each world axis clamped to that axis's own speed
	-- The whole feel of the car is in these four numbers: a small slide is tidied gently,
	-- a big one is hauled round hard, and past the ceiling the car cannot pull any harder.
	ConstantFriction = 14.3, -- studs/s^2. FALLBACK (4 m/s^2). Grip with the car dead
	-- straight: how quickly a tiny slide tidies itself up
	SlipFriction = 14.3, -- studs/s^2 per radian. FALLBACK. How fast grip builds with the
	-- angle: the straight-line part of the curve
	SlipSqFriction = 14.3, -- studs/s^2 per radian^2. FALLBACK. The squared term, and what
	-- makes a big slide bite far harder than a small one. RAISE
	-- it for a car that catches itself, DROP it for one that
	-- keeps going round
	MaxFriction = 107, -- studs/s^2. FALLBACK (30 m/s^2, about 3 g). The ceiling on all of
	-- it, which is the tightest circle the car can hold. Reached at
	-- about 65 deg of slip with the three terms above
	MinSlipAngleForDrift = 5, -- deg. EXACT. Below this the car does not count as drifting,
	-- for the readout and for the score. Not a threshold in the
	-- model: the grip and the slide are continuous through it
	FrictionMultiplier = 1, -- EXACT. Per-car multiplier on the whole grip curve
	GripTarmac = 1, -- FALLBACK. Surface grip on the road
	GripDirt = 0.5, -- FALLBACK. On dirt: half the pull and half the score
	GripUnspecified = 0.1, -- FALLBACK. Anything solid that is not a tagged surface.
	-- Nearly nothing: off the road the car barely corrects itself
	-- and a slide there is a passenger

	-- ---------------------------------------------------------------- drivetrain
	-- Rear-wheel drive: the push happens only when a rear wheel is down, and it is always
	-- along the car's NOSE. A car that is sideways has its engine pushing across its own
	-- travel, so a drift costs speed without a single number saying so -- the cost falls
	-- out of the geometry.
	--     u = |velocity along the nose|
	--     a = MaxAcceleration * AccelMultiplier * throttle * clamp01(1 - (u/TopSpeed)^2)
	MaxAcceleration = 14.3, -- studs/s^2. FALLBACK (4 m/s^2). The push off the line
	AccelMultiplier = 1, -- EXACT. Per-car multiplier on it
	TopSpeed = 179, -- studs/s. FALLBACK (50 m/s). Where the push reaches zero
	StartThrottle = 0.5, -- FALLBACK. Throttle at the start of a run. The throttle is NOT
	-- an input: the car drives itself, and it eases in so a
	-- first-time player is never handed a car at top speed
	FullThrottleSeconds = 5, -- s. FALLBACK. How long the ease-in takes
	HandbrakeDecel = 36, -- studs/s^2. FALLBACK (10 m/s^2). Only used to stop the car once
	-- a run is over; there is no brake in normal play

	-- ---------------------------------------------------------------- downforce
	-- `velocity += down * speed * DownforcePerSpeed * dt`, unless the car is already
	-- falling faster than the cutoff, so a real fall is a real fall. On a kinematic car
	-- that follows the ground this is only felt in the air: it is what decides how far a
	-- jump carries and how hard a crest throws the car.
	DownforcePerSpeed = 0.2, -- per second. NEITHER EXACT NOR FALLBACK -- the one number in
	-- the spec that is a guess (features/drift-model.md "Open
	-- questions"). At top speed it is one extra gravity. Up for
	-- a car pinned to the road over crests, down for one that
	-- flies. TUNE THIS FIRST
	DownforceCutoff = -3.6, -- studs/s. FALLBACK (-1 m/s). Vertical speed below which
	-- downforce switches off, so a jump is a jump

	-- ---------------------------------------------------------------- the car
	-- The model has no bicycle geometry and no steering lock: the wheelbase and the track
	-- are where the four ground rays go and where the wheels are drawn, and nothing else.
	Wheelbase = 9.6, -- studs between the front and rear contact points. FALLBACK
	-- (1.42 m front + 1.28 m rear of centre)
	TrackWidth = 5.6, -- studs between the left and right wheels. FALLBACK (1.56 / 1.6 m)
	WheelDiameter = 2.3, -- studs. FALLBACK (0.65 m)
	WheelWidth = 1.6, -- studs. OURS, for drawing a cylinder that reads as a tyre
	BodyLength = 14, -- studs. OURS: a 4 m car around the reference's wheelbase
	BodyWidth = 6.4, -- studs. OURS
	BodyHeight = 3.2, -- studs. OURS
	RideHeight = 2.4, -- studs from the car's origin down to the ground. OURS: the wheel
	-- centres sit one wheel radius up from there and the body clears
	-- the road
	CenterOfMass = Vector3.new(0, 0.71, 0), -- studs from the origin. FALLBACK
	-- (0, 0.2, 0 m). Nothing in a kinematic car takes a
	-- force at a point, so this is only the pivot the
	-- cosmetic body roll leans about
	BodyRollMax = 10, -- deg. FALLBACK. Cosmetic lean, outward, at `BodyRollSpeed` of
	-- sideways speed. Nothing in the model reads it
	BodyRollSpeed = 107, -- studs/s. FALLBACK (30 m/s) of lateral speed for a full lean
	BodyRollRate = 10, -- per second. FALLBACK. How fast the lean follows
	WheelSteerMax = 30, -- deg. EXACT. The front wheels are drawn pointing along where the
	-- car is actually TRAVELLING, capped here. That is opposite lock
	-- for free, and on a box with four cylinders it is the one thing
	-- that reads as a drift. Cosmetic: no wheel angle is in the model
	WheelSteerRate = 4, -- per second. EXACT. How fast the drawn wheels follow

	-- ---------------------------------------------------------------- ground
	-- One downward ray per wheel each step; the car's height and tilt follow the surface.
	-- The reference runs a spring-and-damper suspension per wheel, which a kinematic car
	-- cannot have; the only part of it a player feels is the tilt, and this is that.
	GroundFollow = 0.12, -- s, how fast height and tilt follow the surface
	AirborneMargin = 2, -- studs above RideHeight with no ground before the car is airborne
	GroundRayUp = 4, -- studs above the contact point each ray starts from
	GroundRayLength = 28, -- studs each ray reaches
	AirLevel = 0.25, -- s, how fast the car levels out while airborne
	TerminalFall = 200, -- studs/s, the fastest a fall may get. Without it a car that has
	-- driven off the world accelerates without limit and the state the
	-- server is sent stops being anything the server can check
	RespawnBelowY = -150, -- studs; below this the car asks the server to put it back
	SurfaceTag = "DriftSurface", -- the ground rays prefer parts with this tag; in a place
	-- with nothing tagged at all they fall back to whatever
	-- solid they hit and treat it as road, so a bare plate is
	-- still drivable (docs/game/CONTRACTS.md)
	SurfaceAttribute = "Surface", -- attribute on a tagged part naming its surface
	SurfaceDirt = "dirt", -- the value that means dirt; anything else tagged is tarmac

	-- ---------------------------------------------------------------- walls
	WallScrub = 0.5, -- share of speed kept after hitting something
	WallPush = 0.2, -- studs the car is held off the surface it hit

	-- ---------------------------------------------------------------- network
	StateSendRate = 20, -- Hz, CarState to the server
	RemoteCarSmoothing = 0.08, -- s, how fast another player's car eases to its reported pose
	StateRateLimit = 30, -- packets a second per UserId the server will take before dropping
	StateSpeedTolerance = 1.25, -- share of TopSpeed a reported horizontal speed may reach
	StateMoveTolerance = 1.5, -- slack on how far a car may have moved since its last packet
	StateMoveAllowance = 9, -- studs of slack on top, for a dropped packet or a jittery clock

	-- ---------------------------------------------------------------- respawning
	-- The server owns where a respawned car goes; the client only asks (CONTRACTS.md,
	-- `CarRespawn`). These are the limits on the asking.
	RespawnRateLimit = 5, -- requests a second per UserId the server will take
	RespawnCooldown = 0.5, -- s the server makes a player wait between respawns
	RespawnGrace = 1, -- s after a respawn in which a packet that fails against the new
	-- position is still checked against the old one. A CarState sent
	-- before the respawn can land after it -- unreliable packets and the
	-- request race each other -- and it is an honest packet from a place
	-- the server knows the car was. Past this the old track is gone
	RespawnAnswerWait = 1.5, -- s the client waits for an answer before it asks again

	-- ---------------------------------------------------------------- the control
	-- One finger, held, is the whole control (features/drift-model.md "The control").
	-- Owned by the gesture task, not by the model: the model only ever wanted one number.
	InputMode = "dynamic", -- EXACT. "centred": the offset is measured from the middle of
	-- the screen. "dynamic": from where the finger went down. The
	-- reference ships both as a setting and they feel different
	SliderWidthMin = 0.5, -- FALLBACK. Full travel as a share of half the screen width, at
	-- the HIGHEST sensitivity
	SliderWidthMax = 1.2, -- FALLBACK. The same at the lowest. Sensitivity lerps between
	-- them BACKWARDS: more sensitivity means a shorter travel
	Sensitivity = 5, -- OURS, 1..10. Where that starts, until there is a settings screen
	KeySensitivity = 0.75, -- FALLBACK. What a keyboard key or a stick at full deflection
	-- is worth, as a share of full travel

	-- ---------------------------------------------------------------- camera
	-- Owned by the camera task. All three of its effects are driven by the same slip angle
	-- the model already has, and together they are most of why a drift reads as a drift.
	-- Offsets are in the CAR's own axes, Roblox sense: +x right, +y up, +z BEHIND the car
	-- (the spec quotes the reference's Unity figures, where behind is -z).
	CamOffset = Vector3.new(0, 28.6, 35.7), -- studs. FALLBACK. The resting place, behind
	-- and above the car
	CamLookAt = Vector3.new(0, 0, -10.7), -- studs. FALLBACK. What it looks at, AHEAD of
	-- the car
	CamVelocityBlend = 0.05, -- EXACT, and small on purpose: how much of the swing toward
	-- where the car is actually going is used. The reference's own
	-- value -- the swing is a hint, not a side-on shot, and it is
	-- why its camera looks calm. Worth raising to taste
	CamSwingRate = 1, -- per second. FALLBACK. How fast the velocity-based target follows
	CamAngleRate = 1, -- per second. FALLBACK. How fast the resting direction follows the
	-- car round
	CamHeightRate = 1, -- per second. FALLBACK. How fast the look-at height follows
	CamRollMax = 45, -- deg. FALLBACK. The whole view tilts about its own forward axis: the
	-- cheapest and largest part of the effect
	CamRollAtAngle = 20, -- deg of slip that reaches the full roll. FALLBACK
	CamRollRate = 20, -- per second. FALLBACK. How fast the roll follows
	CamDriftDistance = 0.5, -- FALLBACK. Share of the resting distance at a full drift: the
	-- camera pulls in as the slip opens
	CamZoomAtAngle = 90, -- deg of slip that reaches it. FALLBACK
	CamZoomRate = 1, -- per second. FALLBACK. How fast the zoom follows
	CamSmoothTime = 0.1, -- s. FALLBACK. Position easing
	CamLookRate = 8, -- per second. FALLBACK. Look-at easing, separate and slower than the
	-- position, which is what keeps the horizon from jittering
	CamFovBase = 70, -- deg at a standstill. OURS
	CamFovTop = 86, -- deg at top speed. OURS

	-- ---------------------------------------------------------------- score
	-- Owned by the score task. Points only while the car is drifting and making forward
	-- progress; the multiplier climbs while it is sideways and bleeds while it is not,
	-- faster the higher it already is, so the ladder gets harder every rung.
	ScoreRate = 0.2864789, -- points per radian of slip per stud travelled. EXACT (the
	-- reference's constant is per metre; this is it converted)
	MaxMultiplier = 9, -- FALLBACK. The top of the ladder
	ProgressRate = 0.06, -- FALLBACK. How fast drifting fills the next rung
	MultiplierDecay = 0.15, -- per second per rung, on the ground. FALLBACK (its 3 x 0.05)
	MaxProgressUp = 1, -- per second. FALLBACK. Ceiling on how fast the bar fills
	MaxProgressDown = 0.75, -- per second. FALLBACK. And empties
	MinProgress = -0.25, -- FALLBACK. How far below empty before a rung is lost
	ScoreTarmac = 1, -- FALLBACK. Score multiplier by surface, averaged over four wheels
	ScoreDirt = 0.5, -- FALLBACK
	ScoreUnspecified = 0.1, -- FALLBACK. Anything solid that is not a tagged surface, for
	-- the score as well as for the grip: a slide in the gutter is
	-- worth almost nothing
	ReverseDriftBonus = 400, -- FALLBACK. A drift held past 90 deg: floor(ln(t+1) * this)
	AirTimeBonusMin = 10, -- FALLBACK. Airborne and forward: an exponential in the air
	-- time, ignored below this

	-- ---------------------------------------------------------------- the prototype's UI
	HideCharacter = true, -- the player is the car: no Roblox character is spawned
	DebugReadout = true, -- build the debug readout at all
	DebugReadoutOpen = true, -- show it from the start

	-- ---------------------------------------------------------------- not the model's
	-- Read by the three modules this port has not reached yet -- the gesture
	-- (Drift/DragControl, Controllers/CarInputController) and the camera
	-- (Controllers/CarCameraController) -- each of which is its own task behind this one.
	-- NOTHING in the drift model reads anything below this line. Delete the block with the
	-- task that replaces the last of those modules.
	DragFullLock = 140, -- px of travel from where the finger went down to a full input
	DragDeadzone = 0.06, -- share of it ignored around the origin
	DriftOffset = 0.55, -- share of full travel the old readout called a drift
	DriftFlickRate = 1400, -- px/s counted as a flick
	DriftFlickSmoothing = 0.06, -- s the flick rate is averaged over
	KeySteerShare = 0.35, -- what a keyboard key was worth before `KeySensitivity`
	CamDistance = 26, -- studs behind the car
	CamHeight = 8, -- studs above it
	CamLookAhead = 14, -- studs ahead of the car the camera looks at
	CamLookHeight = 2.5, -- studs above the car the camera looks at
	CamVelocityLead = 0.65, -- 0 follows the nose, 1 follows where the car is going
	CamStiffness = 9, -- per second, how fast the camera position catches up
	CamYawStiffness = 5, -- per second, how fast it swings round
	CamMinPitch = -32, -- deg, how far down it may look
	CamStandstillSeconds = 0.4, -- s of near-standstill before it stops leading
	MinSlipSpeed = 6, -- studs/s floor the old camera uses for its slip angle
}
