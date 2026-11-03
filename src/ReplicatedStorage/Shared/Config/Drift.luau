--!strict
-- Every tuning number for the drift model, and none of them in the logic
-- (docs/game/features/drift-model.md "Rules and numbers").
--
-- These are starting values to tune in a playtest, not decisions. Change a number here
-- and the whole model changes: the logic in StarterPlayerScripts/Drift reads this table
-- and holds no constants of its own.
--
-- Units: studs, studs/s, studs/s^2, seconds, radians per second, and DEGREES wherever a
-- name says Angle or Slip, because degrees are what the tuning conversation uses.

return {
	-- ---------------------------------------------------------------- simulation
	FixedStep = 1 / 120, -- s. The simulation step, independent of frame rate
	MaxStepsPerFrame = 16, -- safety: never spend more than this many steps on one frame
	Gravity = 110, -- studs/s^2, falling only

	-- ---------------------------------------------------------------- speed
	TopSpeed = 90, -- studs/s, free speed on a straight
	Accel = 80, -- studs/s^2, how fast it reaches top speed. It has to cover what a slide
	-- scrubs off, or the car bleeds to a crawl and every drift becomes a donut.
	BrakeDecel = 90, -- studs/s^2, brake input
	CoastDecel = 12, -- studs/s^2, drag with no throttle
	AutoThrottle = true, -- the prototype drives itself; brake is the only throttle input
	ReverseSpeed = 25, -- studs/s, top speed backwards
	ReverseAccel = 25, -- studs/s^2, how fast it backs up
	SpeedCeiling = 1.15, -- guard: the most the whole velocity may reach, as a share of
	-- TopSpeed. A slide puts speed into the lateral axis, so the cap is
	-- on the total, not on the forward part alone.

	-- ---------------------------------------------------------------- steering
	SteerAngleMax = 32, -- deg, front wheel angle at full lock, at low speed
	SteerAngleMin = 12, -- deg, front wheel angle at full lock, at top speed
	SteerRate = 6, -- /s, how fast the wheels reach the commanded angle (full lock in 1/6 s)
	DriftAngleMax = 35, -- deg of slide the stick asks for at full lock while drifting. The
	-- car settles a little under it -- about 23 deg at these numbers --
	-- because the tyres fight it the whole way: a dial, not a promise.
	-- This and DriftYawAssist decide how sideways a drift looks.
	CounterSteer = 0.05, -- how far past the travel direction the front wheels are nudged,
	-- per radian the slide is short of the angle asked for. Small on
	-- purpose: the nudge is a TYRE SLIP angle, and the tyre is already
	-- making all its grip by 16 deg of slip. At 0.2 the front saturates,
	-- the nose is dragged round and the car spins -- measured, not guessed.

	-- ---------------------------------------------------------------- tyres
	GripFront = 1.6, -- front lateral grip coefficient
	GripRear = 1.5, -- rear lateral grip, gripping
	GripRearDrift = 0.4, -- rear lateral grip while the drift input is held
	GripAccel = 110, -- studs/s^2 of lateral grip per 1.0 of coefficient
	TyrePeakSlip = 8, -- deg of slip at which a tyre is making all the grip it has
	GripBlendIn = 0.08, -- s, grip fall-off when the drift input goes down
	GripBlendOut = 0.35, -- s, grip return when it is released: the catch
	SlipSpeedBleed = 0.35, -- studs/s^2 lost per degree of body slip angle
	DriftYawAssist = 18, -- /s. How hard the car is held to the yaw rate its slide needs.
	-- This is what turns the car into the slide; the tyres only hold it
	-- there. Higher is a car that answers the stick at once.
	DriftAngleTime = 0.3, -- s to swing from straight to the slide angle asked for. The feel
	-- knob for "snaps sideways" against "has to be coaxed round".
	AssistSpeed = 25, -- studs/s at which DriftYawAssist is at full
	SlipAngleMax = 55, -- deg; past this the car is spinning out and straightens itself
	SpinRecover = 5, -- rad/s^2 per radian past SlipAngleMax
	YawRateMax = 4, -- rad/s guard: the fastest the car may ever spin
	YawInertia = 25, -- studs^2, yaw inertia per unit mass. A box of the body's own size:
	-- (BodyLength^2 + BodyWidth^2) / 12. Change the body and change this.
	YawDamping = 1.2, -- /s, yaw rate bled off by the body
	MinSlipSpeed = 6, -- studs/s floor used for slip angles, so a standstill is not a divide by zero
	StepGuard = 0.3, -- solver guard, not a feel knob: the share of a contact point's slip
	-- velocity one step may cancel. Keeps the stiff low-speed tyre
	-- equations stable at FixedStep. Lower is safer and softer.
	BreakLooseSlip = 12, -- deg of body slip counted as "the rear is loose", for the readout

	-- ---------------------------------------------------------------- geometry
	-- The wheelbase is not decoration: with the steering lock it fixes the tightest circle
	-- the car can physically describe (radius = Wheelbase / tan(lock)). At the 6 studs the
	-- spec started from, full lock is a 10-stud circle on a car 8 studs long, so the car
	-- pirouettes instead of sliding and no amount of tyre tuning helps. 12 studs is a car,
	-- not a go-kart: 19 studs at full lock, 56 at top speed (features/drift-model.md).
	Wheelbase = 12, -- studs between the front and rear contact points
	TrackWidth = 5.6, -- studs between the left and right wheels
	RideHeight = 2, -- studs from the car's origin down to the ground
	BodyLength = 16,
	BodyWidth = 6.4,
	BodyHeight = 2.6,
	WheelDiameter = 4,
	WheelWidth = 1.6,

	-- ---------------------------------------------------------------- ground
	GroundFollow = 0.12, -- s, how fast height and tilt follow the surface
	AirborneMargin = 2, -- studs above RideHeight with no ground before the car is airborne
	GroundRayUp = 4, -- studs above the contact point each ray starts from
	GroundRayLength = 28, -- studs each ray reaches
	AirLevel = 0.25, -- s, how fast the car levels out while airborne
	AirYawRate = 1.2, -- rad/s of yaw at full lock while airborne
	AirYawTime = 0.3, -- s to reach it
	RespawnBelowY = -150, -- studs; below this the car is put back at its spawn
	SurfaceTag = "DriftSurface", -- the ground rays prefer parts with this tag; with none in
	-- the world they fall back to whatever solid they hit

	-- ---------------------------------------------------------------- walls
	WallScrub = 0.5, -- share of speed kept after hitting something
	WallStraighten = 0.7, -- share of the slide and spin killed by the hit
	WallPush = 0.2, -- studs the car is held off the surface it hit

	-- ---------------------------------------------------------------- network
	StateSendRate = 20, -- Hz, CarState to the server
	RemoteCarSmoothing = 0.08, -- s, how fast another player's car eases to its reported pose

	-- ---------------------------------------------------------------- camera
	CamDistance = 26, -- studs behind the car
	CamHeight = 8, -- studs above it
	CamLookAhead = 14, -- studs ahead of the car the camera looks at
	CamLookHeight = 2.5, -- studs above the car the camera looks at
	CamVelocityLead = 0.65, -- 0 follows the car's nose, 1 follows where it is actually going
	CamStiffness = 9, -- /s, how fast the camera position catches up
	CamYawStiffness = 5, -- /s, how fast the camera swings round
	CamFovBase = 70, -- deg at a standstill
	CamFovTop = 86, -- deg at top speed
	CamMinPitch = -32, -- deg, how far down the camera may look
	CamStandstillSeconds = 0.4, -- s of near-standstill before the camera stops leading

	-- ---------------------------------------------------------------- controls
	TouchScheme = "TwoThumb", -- "TwoThumb": left half steers, right half drifts.
	-- "OneFinger": one finger drags to steer and holds to drift
	-- (features/drift-model.md "Open questions")
	TouchStickRadius = 90, -- px, how far the thumb travels for full lock
	TouchDeadzone = 0.08, -- share of the stick ignored around centre
	HideCharacter = true, -- the player is the car: no Roblox character is spawned
	DebugReadout = true, -- build the debug readout at all
	DebugReadoutOpen = true, -- show it from the start
}
