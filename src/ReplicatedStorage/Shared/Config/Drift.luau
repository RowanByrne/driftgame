--!nonstrict
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
-- THIS FILE IS THE MODEL. THE CAR IS IN `Shared/Cars` (T-027,
-- docs/game/features/car-archetypes.md). Every number that is a property of one CAR --
-- its rate of turn, its four grip numbers, its drivetrain, its downforce, its geometry --
-- was moved out of here into `Cars/Archetypes` and is resolved through the ACTIVE car by
-- the metatable at the bottom. So `Config.Drift.MaxSteeringSpeed` still answers, and
-- still answers in `Drift/Model`'s hot loop, but what it answers is whichever car is in
-- play. What is left here is the simulation itself: the step, gravity, the surfaces, the
-- ground, the walls, the network, the respawn, the control, the camera, the score, the
-- debug UI -- and `CarBody`, which is which SHAPE is drawn and is a separate axis from
-- which car is driven.
--
-- WRITING A CAR NUMBER INTO THIS TABLE ERRORS, on purpose: it would survive a car switch
-- and silently make every car the same. Use `Cars.tune(key, value)` / `Cars.untune(key)`,
-- or `Cars.withTuning({...}, fn)`.
--
-- Units: studs, studs/s, studs/s^2, seconds, radians per second, and DEGREES wherever a
-- name says Angle or Slip, because degrees are what the tuning conversation uses. The
-- reference is in metres; everything converted carries 1 stud = 0.28 m (x 3.571).
--
-- Every row of the spec's tables says where its number came from, and so does every
-- comment here: EXACT (written in the reference's own logic), FALLBACK (the value its
-- code declares when an editor asset does not override it, so a credible car but not the
-- shipped one) or OURS. The fallbacks are a starting point to tune from, not decisions.

local Cars = require(script.Parent.Parent.Cars)

local Drift = {
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
	-- THE DIAL THE FEEL CONVERSATION STARTS WITH, and it is the CAR's:
	-- `MaxSteeringSpeed` and `SteeringSensitivity` are in `Cars/Archetypes`. Every step
	-- the car's yaw rate is SET:
	--     yawRate = MaxSteeringSpeed * steer * SteeringSensitivity
	-- Not a torque, not a wheel angle, not a target to ease toward. Centre the finger and
	-- the car stops turning on the next step. Nothing moves the velocity when the car
	-- rotates, so the slip angle opens by itself: rotating IS drifting.
	InvertSteering = true, -- OURS. Which way a finger turns the car. True is the sense the
	-- user asked for in T-007: a finger to the right swings the
	-- car's REAR right and the nose left, which reads as holding
	-- the car's weight rather than steering its front wheels.
	-- A SETTING, not a car: every car reads the finger the same

	-- ---------------------------------------------------------------- grip: the drift
	-- With any wheel on the ground, and `b` the slip angle (signed, nose to velocity):
	--     f   = min(ConstantFriction + SlipFriction*|b| + SlipSqFriction*|b|^2, MaxFriction)
	--     f   = f * surfaceGrip * FrictionMultiplier            (|b| capped at 90 deg)
	--     dir = |b| > 90 deg and -travel or carRight*sign(b)
	--     velocity += f * dt * dir, each world axis clamped to that axis's own speed
	-- THE FOUR NUMBERS IN THAT CURVE ARE THE CAR'S and live in `Cars/Archetypes`: they are
	-- the whole of how one car drifts differently from another, and the stat panel draws
	-- them. What is left here is the SURFACE, which is the world's, not the car's.
	MinSlipAngleForDrift = 5, -- deg. EXACT. Below this the car does not count as drifting,
	-- for the readout and for the score. Not a threshold in the
	-- model: the grip and the slide are continuous through it,
	-- and it is the same for every car
	GripTarmac = 1, -- FALLBACK. Surface grip on the road
	GripDirt = 0.5, -- FALLBACK. On dirt: half the pull and half the score
	GripUnspecified = 0.1, -- FALLBACK. Anything solid that is not a tagged surface.
	-- Nearly nothing: off the road the car barely corrects itself
	-- and a slide there is a passenger

	-- ---------------------------------------------------------------- drivetrain
	-- Rear-wheel drive, every car: the push happens only when a rear wheel is down, and it
	-- is always along the car's NOSE. A car that is sideways has its engine pushing across
	-- its own travel, so a drift costs speed without a single number saying so -- the cost
	-- falls out of the geometry.
	--     u = |velocity along the nose|
	--     a = MaxAcceleration * AccelMultiplier * throttle * clamp01(1 - (u/TopSpeed)^2)
	-- All five of those numbers are the CAR's (`Cars/Archetypes`). Which wheels drive is
	-- not a number at all yet -- it is `Model.REAR_WHEELS` -- and the reference does vary
	-- it per car (see the spec's "Open questions").

	-- ---------------------------------------------------------------- the car
	CarBody = "ae86", -- OURS, and NOT the archetype: this is which SHAPE `Shared/CarModel`
	-- builds, and the two are deliberately different axes. "ae86" is
	-- the car the user added to the Main place, read out of it and
	-- written down in `Shared/Cars/AE86`; "block" is the box and four
	-- cylinders, which is also what a place whose meshes will not load
	-- falls back to. ANY BODY MAY WEAR ANY ARCHETYPE'S NUMBERS, which
	-- is how an archetype is driven before its art exists (T-028).
	-- The real car is scaled onto the active car's `Wheelbase` and
	-- `WheelDiameter`, because that is where the ground rays go.
	-- NOT APPROVED TO PUBLISH -- it is a real manufacturer's car from
	-- a third party's upload (`assets/car-ae86/MANIFEST.md`,
	-- features/drift-model.md "Platform risks")

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

	-- ---------------------------------------------------------------- a hand-placed track
	-- The playground is built by code and is in git; a TRACK is a model someone placed in
	-- the place file by hand, which git never sees (AGENTS.md "Hand-built content"). Both
	-- sit at the origin, so a place gets one or the other and `TrackService` decides which.
	-- A track carries none of our tags, so its road has to be recognised -- by COLOUR,
	-- because its part names are whatever its author typed. Tarmac is grey: its channels
	-- sit close together and it is neither black nor white.
	TrackName = "Track", -- the model's name in Workspace. No track by that name, no track
	TrackRoadColourSpread = 0.1, -- how far a part's R, G and B may differ and still read as
	-- grey. Up if road is being missed, down if grass is being
	-- taken for road -- and taking grass for road is the worse
	-- failure, because the edge of the track is where a drift is
	-- won or lost
	TrackRoadMinBrightness = 0.2, -- darker than this is shadow, tyre marks or a tunnel
	TrackRoadMaxBrightness = 0.88, -- brighter is a kerb, a line or a building
	TrackSpawnSearchSteps = 60, -- grid resolution of the hunt for somewhere on the road to
	-- start. 60 x 60 rays, once, at startup
	TrackMinRoadRun = 4, -- studs of continuous road below which a crossing is a scan line
	-- clipping a corner rather than a road worth measuring

	-- ---------------------------------------------------------------- walls
	WallScrub = 0.5, -- share of speed kept after hitting something
	WallPush = 0.2, -- studs the car is held off the surface it hit

	-- ---------------------------------------------------------------- network
	StateSendRate = 20, -- Hz, CarState to the server
	RemoteCarSmoothing = 0.08, -- s, how fast another player's car eases to its reported pose
	StateRateLimit = 30, -- packets a second per UserId the server will take before dropping
	StateSpeedTolerance = 1.25, -- share of TopSpeed a reported horizontal speed may reach.
	-- The server bounds it against the TopSpeed of the car IT
	-- thinks is active, and the panel's car switch is
	-- client-side, so every archetype's top speed stays under
	-- the default car's 179 x 1.25 = 223.75
	-- (features/car-archetypes.md "Open questions")
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
	-- A SETTING, not a car: the gesture is the player's, the car is what it drives.
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
	-- Owned by the camera task. CORRECTED 2026-11-03: the decompile holds two cameras and
	-- the spec described the predecessor, which nothing in the reference runs. The game's
	-- camera has NO ROLL, NO ZOOM and NO POSITION SMOOTHING -- it is placed at its target
	-- each frame and looks at the car, so the horizon is always level. `CamRollMax`,
	-- `CamRollAtAngle`, `CamRollRate`, `CamDriftDistance`, `CamZoomAtAngle`, `CamZoomRate`,
	-- `CamSmoothTime`, `CamLookRate` and `CamFovTop` were that predecessor's and are gone;
	-- if one turns up in this table again, something has drifted back to the wrong camera.
	-- Offsets are in the CAR's own axes, Roblox sense: +x right, +y up, +z BEHIND the car
	-- (the spec quotes the reference's Unity figures, where behind is -z).
	CamOffset = Vector3.new(0, 14.3, 53.6), -- studs. FALLBACK (0, 4, -15 m), from the
	-- camera-mode setting's own default. Its LENGTH is the
	-- radius the camera keeps from the car and its direction
	-- is the resting direction. Low and well back, which is
	-- most of why the reference reads flat and fast rather
	-- than like a drone shot
	CamLookAt = Vector3.new(0, 0, -10.7), -- studs. EXACT. What it looks at, AHEAD of the
	-- car. Only its HEIGHT is eased (`CamHeightRate`)
	CamVelocityBlend = 0.05, -- EXACT, and small on purpose: how much of the lean toward
	-- where the car is actually going is taken each frame. It is
	-- small because it COMPOUNDS -- the leaned target is what the
	-- next frame's resting direction is measured from, so the 5%
	-- is applied again every frame. What the player sees is the
	-- camera dropping and swinging wide through a drift, not a
	-- side-on shot. Raise it for a more dramatic camera
	CamSwingRate = 1, -- per second. FALLBACK. How fast the behind-the-travel point follows
	CamAngleRate = 1, -- per second. FALLBACK. How fast the resting DIRECTION follows the
	-- car round -- the camera swings around the car at a fixed radius
	-- rather than being dragged behind it. THE MAIN FEEL DIAL: low is
	-- a camera that lags and lets the car rotate in front of it, high
	-- is one glued behind the nose
	CamHeightRate = 1, -- per second. FALLBACK. How fast the look-at height follows
	CamFovBase = 60, -- deg at a standstill. FALLBACK
	CamFovPerSpeed = 0.14, -- deg per stud/s. FALLBACK (0.5 per m/s): 85 deg at top speed
	CamFovRate = 0.5, -- per second. FALLBACK. How fast the FOV follows. Slow on purpose
	CamTargetStep = 1 / 60, -- s. OURS, and NOT `FixedStep`. The camera's targets feed back
	-- into themselves (the swung target is what the next frame's resting
	-- direction is measured from), so where they settle depends on how
	-- often they are stepped: left at frame rate, the camera sat 16.2
	-- studs above a drifting car at 30 FPS and 10.1 at 120. They run on
	-- this fixed step instead, interpolated between, and 60 is the rate
	-- the reference ran at -- so this number reproduces its look, and
	-- changing it changes how the camera sits in a drift at every frame
	-- rate at once. The model's own step is finer and deliberately
	-- separate: the camera does not need 120 and the feedback is why.
	CamMaxTargetSteps = 8, -- safety, as `MaxStepsPerFrame` is for the model: a stalled
	-- frame must not be paid back as a burst of camera steps

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
	DebugReadoutOpen = false, -- but CLOSED from the start: the numbers are a measuring
	-- instrument, not part of the game, and the user driving
	-- for feel should see the car and the slider and nothing
	-- else. F3, DPad up or the DBG button brings them back
	DebugStatsOpen = false, -- and the car's stat panel is folded inside it, closed too.
	-- F5, or clicking its header, unfolds it; F4 switches car

	-- ---------------------------------------------------------------- the trajectory line
	-- Where the car will go if the finger stays exactly where it is (`Drift/Trajectory`).
	-- A DEV TOOL, like the readout: off by default, built only when switched on (F6, or
	-- `DriftController:DebugTrajectory(true)`), and destroyed again when switched off.
	--
	-- The line is the real model run forward from a COPY of the live state, so it is the
	-- car rather than a guess at it -- which also means it costs what the model costs, and
	-- these numbers are what keeps that cost in hand (`Drift/Trajectory` header).
	--
	-- MODEL NUMBERS, NOT THE CAR'S: a trajectory is a thing we draw, not a property of a
	-- car. The one car number it uses it reads -- `BodyLength` -- so ten car lengths is ten
	-- lengths of whichever car is active.
	TrajectoryLine = false, -- OURS. Draw the line at all. OFF: it is a measuring
	-- instrument, not part of the game
	TrajectoryCarLengths = 10, -- OURS. How far ahead to draw, in the active car's own
	-- `BodyLength`. Walked by DISTANCE, not by time, so the
	-- line stays the same length as the car speeds up
	TrajectoryStep = 1 / 30, -- s. OURS, and DELIBERATELY COARSER than `FixedStep`: the
	-- line only has to look right, not be exact to a thousandth,
	-- and at 1/120 this would be ~200 steps every frame. Measured,
	-- the coarse step costs well under a stud over the whole line
	TrajectoryPointSpacing = 5, -- studs between the points the line is drawn through. Not
	-- the simulation's resolution -- it steps at
	-- `TrajectoryStep` and only marks a point this often
	TrajectoryMaxSteps = 200, -- safety: a car crawling forward must not walk the full ten
	-- lengths one millimetre at a time
	TrajectoryMinSpeed = 1, -- studs/s. Stop the walk early once the car has stopped
	TrajectoryHz = 0, -- predictions a second. 0 is EVERY FRAME, which is what it is
	-- measured cheap enough to do; raise it off zero to predict less
	-- often and leave the drawn line alone in between
	TrajectoryFlat = true, -- OURS, and the big one. True predicts against a flat plane at
	-- the car's current ground height: no raycasts at all, nearly
	-- free -- and WRONG OVER A CREST, A RAMP OR A WALL, because the
	-- plane does not know they are there. That is a trade, not a
	-- bug. False predicts against the live Workspace and pays four
	-- ground rays per step for a line that follows the ground
	TrajectoryMaxSegments = 64, -- parts the line may use. The pool is created once and
	-- reused; spares are hidden, never destroyed
	TrajectoryWidth = 0.35, -- studs. Thin on purpose: it is an overlay, not scenery
	TrajectoryLift = 1, -- studs above the predicted path, so the line is not inside the road
	TrajectoryColour = Color3.fromRGB(94, 255, 162),
	TrajectoryTransparency = 0.25,
	TrajectoryFolder = "DriftTrajectory", -- its folder in Workspace. NEVER inside
	-- `Workspace.Cars`, where the ground rays and the
	-- car-claiming logic both look
}

-- ---------------------------------------------------------------------- the active car
--
-- Every CAR key is absent from the table above, so reading one misses and lands here, and
-- `Shared/Cars` answers with whatever car is active. That is the whole mechanism, and it
-- is why `Drift/Model` reads the active car without one line of it changing.
--
-- `__index` is the hot path -- the model makes about twenty of these a step, 120 times a
-- second -- and it is one function call and one table index. The alternative, copying a
-- car's numbers into this table on a switch, was rejected: it leaves two copies of every
-- number and nothing to stop them drifting apart.
--
-- `__newindex` refuses a car key outright. `Config.Drift.MaxSteeringSpeed = 1` would
-- write a RAW key here, which from then on shadows every car and makes them all the same:
-- the one failure this split exists to prevent, so it is an error with the answer in it
-- rather than something to notice later. Model keys are all present raw, so writing one
-- (the camera test does) never reaches this at all.
setmetatable(Drift, {
	__index = function(_, key: string): any
		return Cars.value(key)
	end,
	__newindex = function(self, key: string, value: any)
		if Cars.isField(key) then
			error(
				`Config.Drift.{key} belongs to the CAR, not the model: `
					.. `use Cars.tune("{key}", v) / Cars.untune("{key}"), or Cars.withTuning (Shared/Cars)`,
				2
			)
		end
		rawset(self, key, value)
	end,
})

return Drift
