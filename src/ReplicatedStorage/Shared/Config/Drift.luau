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
	Accel = 80, -- studs/s^2, how fast it reaches top speed
	-- The slide is the car's speed control, and the only one it needs: a shallow drift is
	-- nearly free, a big one is ruinous, and full lock held is the brake and the panic
	-- button both. These two are the trade the whole game is made of.
	SlideDrag = 32, -- studs/s^2 scrubbed off at SlideAngleFull, along the car's TRAVEL
	SlideDragPower = 2.3, -- the shape of the trade. 1 is a straight line; above 1 a shallow
	-- drift costs almost nothing and a big one costs everything.
	DriveCutShape = 3, -- how much of the throttle the thrown weight takes away. At a full
	-- offset it takes all of it, whatever the car is doing, which is
	-- what makes full lock held a stop the car cannot drive out of.
	-- The exponent decides how far down the finger's travel that
	-- reaches: 1 takes it in proportion, higher leaves small offsets
	-- alone and only bites near the end.
	BrakeDecel = 90, -- studs/s^2, brake input
	CoastDecel = 12, -- studs/s^2, drag with no throttle
	AutoThrottle = true, -- the prototype drives itself; brake is the only throttle input
	ReverseSpeed = 25, -- studs/s, top speed backwards
	ReverseAccel = 25, -- studs/s^2, how fast it backs up
	BrakeToReverse = 0.5, -- studs/s below which the brake input starts backing up instead
	SpeedCeiling = 1.15, -- guard: the most the whole velocity may reach, as a share of
	-- TopSpeed. A slide puts speed into the lateral axis, so the cap is
	-- on the total, not on the forward part alone.

	-- ---------------------------------------------------------------- the finger
	-- THE THREE DIALS THE FEEL CONVERSATION STARTS WITH. The finger is on the car's rear,
	-- not its nose: its offset says how hard the car's weight is thrown across, and the
	-- slide that comes of it is a balance between the shove and the car's own grip
	-- (features/drift-model.md "How it plays"). Nothing here names an angle for the car to
	-- go to.
	--
	--   SlideKick / SlideBite -- their RATIO is how sideways the car gets for a given
	--     finger, and their SIZE is how violently it answers. Kick up or bite down for a
	--     looser, wilder car; the other way for a car that has to be bullied sideways.
	--   SlideDrag  -- what a slide costs in speed. Up for a car that is punished for
	--     staying sideways, down for one that carries speed through anything.
	SlideKick = 78, -- rad/s^2 of yaw the thrown weight shoves the tail round with, at a
	-- full offset. Measured against SlideBite, not on its own.
	SlideBite = 78, -- rad/s^2 the car's own grip hauls the tail back with, at
	-- SlideAngleFull
	SlideBiteShape = 1, -- how the fight grows with the slide. 1 is a straight line; above
	-- it, a small slide is easy to open and a big one is very hard, which
	-- is what spreads the ladder across the finger's travel instead of
	-- leaving the car stuck or gone with nothing in between.
	SlideAngleFull = 65, -- deg: as sideways as this car gets. Where SlideBite is at full,
	-- where the throttle has died completely and where SlideDrag is at
	-- full. "100% to the side" means this.
	SlideCurve = 0.75, -- how the finger's travel maps onto the car's range. 1 is straight;
	-- below 1 the near half of the travel buys more, which is what keeps
	-- a thumb's first inch from being wasted on a car that is still stuck.
	SlideKickSpeed = 8, -- studs/s at which the shove and the fight are both at full. Below
	-- it both fade together, so a car at a standstill does not pirouette.
	SlideSpeedFloor = 1, -- studs/s floor under the slide angle. A crawl, not a speed: it
	-- says a car barely moving has no slide, which is what lets one
	-- stopped sideways let go and drive off again.
	SlideHeldAt = 0.1, -- offset above which the readout counts the finger as asking for a
	-- slide at all (entry speed, how long to break loose)

	-- Weight has mass: it takes time to throw and time to settle, and that lag is the
	-- difference between a car and a cursor. Out is quicker than back, as a car is.
	WeightThrowRate = 3.5, -- /s, how fast the weight moves out (centre to full in 0.29 s)
	WeightSettleRate = 3, -- /s, how fast it gathers back in (0.33 s)

	-- ---------------------------------------------------------------- steering
	-- Nobody steers this car. The front wheels follow where the front axle is travelling,
	-- which IS counter-steer once the back is out; these only shape that.
	SteerAngleMax = 32, -- deg, front wheel angle at full lock, at low speed
	SteerAngleMin = 12, -- deg, front wheel angle at full lock, at top speed
	SteerRate = 6, -- /s, how fast the wheels reach the commanded angle (full lock in 1/6 s)
	CounterSteer = 0, -- how far PAST the travel direction the front wheels are carried, per
	-- radian of slide. Zero is the hands exactly on the travel, which is
	-- what measured best: the front tyre then makes no force of its own
	-- either way. Positive carries them further out, so the front fights
	-- the slide and the car corners wider the harder it is drifted -- the
	-- wrong way round, measured. Negative pulls them back into the corner,
	-- which tightens every radius and makes the car much more willing to
	-- swap ends. A small dial with a big reach: move it in hundredths.
	CrawlSpeed = 12, -- studs/s below which the wheels take the finger directly instead of
	-- following the travel, so the car can still be parked and reversed

	-- ---------------------------------------------------------------- tyres
	GripFront = 1.6, -- front lateral grip coefficient
	GripRear = 1.5, -- rear lateral grip, gripping
	GripRearDrift = 0.4, -- rear lateral grip with the weight fully thrown across
	GripAccel = 40, -- studs/s^2 of lateral grip per 1.0 of coefficient. It sets the circle
	-- the car can physically describe, and so how tight a drift looks: at
	-- the 110 this started from, two saturated tyres pull about 5g and the
	-- car pirouettes on a 13-stud radius the moment it slides, which no
	-- amount of input tuning reaches past. At 40 a held drift runs a
	-- 110-stud circle at half lock and a 24-stud one at three quarters.
	TyrePeakSlip = 8, -- deg of slip at which a tyre is making all the grip it has
	GripBlendIn = 0.08, -- s, grip fall-off as the weight goes across
	GripBlendOut = 0.35, -- s, grip return as it comes back: the catch
	SlipAngleMax = 88, -- deg; past square across the car is going round, not drifting, and
	-- it straightens itself. A wall above SlideAngleFull, not a feel knob.
	SpinRecover = 120, -- rad/s^2 per radian past SlipAngleMax. Stiff on purpose: a full
	-- offset must pin the car sideways, not spin it through.
	YawRateMax = 4, -- rad/s guard: the fastest the car may ever spin
	YawInertia = 25, -- studs^2, yaw inertia per unit mass. A box of the body's own size:
	-- (BodyLength^2 + BodyWidth^2) / 12. Change the body and change this.
	YawDamping = 11, -- /s, yaw rate bled off by the body. This is the car's mass answering
	-- the shove, and it is what decides how far the slide overshoots
	-- before it settles: at 1.2 a three-quarter offset threw the car to
	-- 91 deg on its way to 37, which is a spin, not a drift. At 11 the
	-- same offset leans to 48 and settles at 36. Lower it for a car that
	-- snaps and overshoots; raise it for one that leans in and holds.
	MinSlipSpeed = 6, -- studs/s floor used for slip angles, so a standstill is not a divide by zero
	StepGuard = 0.3, -- solver guard, not a feel knob: the share of a contact point's slip
	-- velocity one step may cancel. Keeps the stiff low-speed tyre
	-- equations stable at FixedStep. Lower is safer and softer.
	BreakLooseSlip = 12, -- deg of body slip counted as "the rear is loose", for the readout
	PhaseDriftingAt = 0.35, -- share of SlideAngleFull at or above which the car counts as
	-- drifting, for the readout and for the `drifting` flag the server
	-- is sent. Read off the slide, not off the input: with a continuous
	-- finger there is no mode to be in.
	PhaseCatchingAt = 0.05, -- and above which, on the way back, it says "catching"

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
	TerminalFall = 200, -- studs/s, the fastest a fall may get. Without it a car that has
	-- driven off the world accelerates without limit, and the state the
	-- server is sent stops being anything the server can check.
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
	StateRateLimit = 30, -- packets a second per UserId the server will take before dropping
	StateSpeedTolerance = 1.25, -- share of TopSpeed a reported horizontal speed may reach
	StateMoveTolerance = 1.5, -- slack on how far a car may have moved since its last packet
	StateMoveAllowance = 9, -- studs of slack on top, for a dropped packet or a jittery clock

	-- ---------------------------------------------------------------- respawning
	-- The server owns where a respawned car goes; the client only asks (CONTRACTS.md,
	-- `CarRespawn`). These are the limits on the asking.
	RespawnRateLimit = 5, -- requests a second per UserId the server will take before dropping
	RespawnCooldown = 0.5, -- s the server makes a player wait between respawns
	RespawnGrace = 1, -- s after a respawn in which a packet that fails against the new
	-- position is still checked against the old one. A CarState sent
	-- before the respawn can land after it -- unreliable packets and the
	-- request race each other -- and it is an honest packet from a place
	-- the server knows the car was. Past this the old track is gone.
	RespawnAnswerWait = 1.5, -- s the client waits for an answer before it asks again

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
	-- One gesture does the steering and the drift, on touch and on the mouse alike
	-- (DECISIONS.md, 2026-11-03). Everything it needs is here, so the feel of the control
	-- is tuned in this table and not in DragControl.
	DragFullLock = 140, -- px of horizontal travel from where the finger went down to full
	-- lock. Smaller is twitchier; it has to fit a thumb's reach on a phone
	-- without the hand covering the car.
	DragDeadzone = 0.06, -- share of full lock ignored around the origin, so resting a
	-- finger still is straight
	DriftOffset = 0.55, -- share of full lock past which the readout calls it a drift, and
	-- what one press of a DISCRETE drift input (keyboard, gamepad, a
	-- flick) is worth on the same scale. It is no longer a gate: the
	-- offset commands the slide continuously from nothing to full, so
	-- there is no edge here for a finger to fall over.
	KeySteerShare = 0.35, -- how much of a full finger a keyboard key or a stick is worth on
	-- its own, with no drift button held. A digital key is always at
	-- full travel, and a car that went fully sideways the moment a key
	-- went down would be undrivable; holding drift gives the rest.
	DriftFlickRate = 1400, -- px/s across the screen that breaks the rear loose whatever the
	-- offset. This is the quick way in: a flick. Which of the two a
	-- player ends up using is what these two numbers decide between.
	DriftFlickSmoothing = 0.06, -- s the flick rate is averaged over, so one jittery sample
	-- from a cheap touchscreen cannot start a drift on its own
	HideCharacter = true, -- the player is the car: no Roblox character is spawned
	DebugReadout = true, -- build the debug readout at all
	DebugReadoutOpen = true, -- show it from the start
}
