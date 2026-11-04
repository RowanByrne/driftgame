--!strict
-- Archetypes: the cars, as numbers (docs/game/features/car-archetypes.md).
--
-- A CAR IS NOT THE MODEL. `Config.Drift` holds the model -- the step, gravity, the
-- surfaces, the ground rays, the network, the camera, the score -- and every number that
-- is a property of THIS CAR lives here instead. `Config.Drift` resolves a car key through
-- `Shared/Cars`, so `C.MaxSteeringSpeed` in the model reads the ACTIVE car's rate of turn
-- and nothing in `Drift/Model` had to change to make that true.
--
-- A CAR IS NOT A BODY either, and the two are deliberately separate axes. `Config.Drift.
-- CarBody` picks the shape that is drawn (`ae86`, `block`); this picks how it drives. Any
-- body may wear any archetype's numbers, which is how an archetype is tested before its
-- art exists (T-028).
--
-- `Base` is every car field at the value the model was approved on
-- (docs/game/DECISIONS.md, 2026-11-03), and each archetype is a SPARSE table of overrides
-- on top of it. `balanced` overrides nothing on purpose: it IS the approved car, to the
-- bit, and the default. If a change here moves `balanced`, it has moved the car the user
-- said yes to.
--
-- Units are studs, as everywhere else: the reference is in metres and everything carries
-- 1 stud = 0.28 m (x 3.571). Angular rates are unitless in length and carry over as they
-- are.
--
-- THE THREE `Bars` ARE DISPLAY ONLY AND NOTHING COMPUTES THEM. They are hand-written
-- marketing, 0..10, exactly as the reference does it: nothing derives them from the
-- physics and nothing reads them back into the simulation. The honest numbers a player
-- can be shown are the four below them -- the rate of turn and the three grip terms --
-- and the grip curve they make, which is what the stat panel draws.

export type Car = {
	-- what the player is told
	Name: string?, -- placeholder: the user names anything a player sees (AGENTS.md)
	Character: string?, -- one line, for the panel and for the spec
	Bars: { Acceleration: number, Handling: number, TopSpeed: number }?, -- DISPLAY ONLY

	-- steering
	MaxSteeringSpeed: number?,
	SteeringSensitivity: number?,

	-- grip
	ConstantFriction: number?,
	SlipFriction: number?,
	SlipSqFriction: number?,
	MaxFriction: number?,
	FrictionMultiplier: number?,

	-- drivetrain
	MaxAcceleration: number?,
	AccelMultiplier: number?,
	TopSpeed: number?,
	SpeedMultiplier: number?,
	StartThrottle: number?,
	FullThrottleSeconds: number?,
	HandbrakeDecel: number?,

	-- downforce
	DownforcePerSpeed: number?,
	DownforceCutoff: number?,

	-- geometry and the cosmetics that hang off it
	Wheelbase: number?,
	TrackWidth: number?,
	WheelDiameter: number?,
	WheelWidth: number?,
	BodyLength: number?,
	BodyWidth: number?,
	BodyHeight: number?,
	RideHeight: number?,
	CenterOfMass: Vector3?,
	BodyRollMax: number?,
	BodyRollSpeed: number?,
	BodyRollRate: number?,
	WheelSteerMax: number?,
	WheelSteerRate: number?,
}

local Archetypes = {}

-- The maxima the stat panel draws each real number as a fraction of. They are the
-- reference's own, converted, and they are the DESIGN SPACE rather than a limit the code
-- enforces: the approved car sits at 50% of the steering max and 12.5%, 6.3% and 12.5% of
-- the three grip maxima, so there is a great deal of room above it in every direction.
Archetypes.StatMax = {
	MaxSteeringSpeed = 4, -- rad/s (the reference's own max)
	ConstantFriction = 114.3, -- studs/s^2 (32 m/s^2)
	SlipFriction = 228.6, -- studs/s^2 per rad (64)
	SlipSqFriction = 114.3, -- studs/s^2 per rad^2 (32)
}

-- Every car field, at the approved car's value. Nothing here is new: each number was in
-- `Config.Drift` before this split and is unchanged, comments and all
-- (docs/game/features/drift-model.md "Rules and numbers").
Archetypes.Base = {
	Name = "Balanced",
	Character = "the car the feel gate was passed on",
	Bars = { Acceleration = 5, Handling = 5, TopSpeed = 7 },

	MaxSteeringSpeed = 2, -- rad/s. FALLBACK. 115 deg/s at a full finger
	SteeringSensitivity = 1, -- EXACT. The per-car multiplier on it

	ConstantFriction = 14.3, -- studs/s^2. FALLBACK (4 m/s^2). Grip dead straight
	SlipFriction = 14.3, -- studs/s^2 per rad. FALLBACK. How fast grip builds
	SlipSqFriction = 14.3, -- studs/s^2 per rad^2. FALLBACK. The bite in a big slide
	MaxFriction = 107, -- studs/s^2. FALLBACK (30 m/s^2, 3 g). The ceiling
	FrictionMultiplier = 1, -- EXACT. The per-car multiplier on the whole curve

	MaxAcceleration = 14.3, -- studs/s^2. FALLBACK (4 m/s^2)
	AccelMultiplier = 1, -- EXACT
	TopSpeed = 179, -- studs/s. FALLBACK (50 m/s)
	SpeedMultiplier = 1, -- EXACT. Nothing reads it yet; it is the reference's fourth
	-- per-car multiplier and is here so a car can carry one
	StartThrottle = 0.5, -- FALLBACK
	FullThrottleSeconds = 5, -- s. FALLBACK
	HandbrakeDecel = 36, -- studs/s^2. FALLBACK (10 m/s^2)

	DownforcePerSpeed = 0.2, -- per second. A GUESS, and the only one
	DownforceCutoff = -3.6, -- studs/s. FALLBACK (-1 m/s)

	-- GEOMETRY IS A CAR FIELD AND EVERY ARCHETYPE SHARES IT, for now: the four of them
	-- wear the same body until T-028 draws them, and `Shared/CarModel` scales that body
	-- onto `Wheelbase` and `WheelDiameter` once, when a car is built. Changing geometry
	-- per car is therefore legitimate but only takes effect on the NEXT car built -- a
	-- respawn -- and the live switch in the debug panel would leave the shell mismatched
	-- until then. None of it reaches the drift: the model has no bicycle geometry.
	Wheelbase = 9.6, -- studs. FALLBACK
	TrackWidth = 5.6, -- studs. FALLBACK
	WheelDiameter = 2.3, -- studs. FALLBACK
	WheelWidth = 1.6, -- studs. OURS
	BodyLength = 14, -- studs. OURS (only sizes the block body)
	BodyWidth = 6.4, -- studs. OURS
	BodyHeight = 3.2, -- studs. OURS
	RideHeight = 2.4, -- studs. OURS
	CenterOfMass = Vector3.new(0, 0.71, 0), -- studs. FALLBACK. Only the cosmetic roll
	BodyRollMax = 10, -- deg. FALLBACK
	BodyRollSpeed = 107, -- studs/s. FALLBACK
	BodyRollRate = 10, -- per second. FALLBACK
	WheelSteerMax = 30, -- deg. EXACT. Cosmetic opposite lock
	WheelSteerRate = 4, -- per second. EXACT
}

-- The order the panel cycles them in, and the order they are reported in.
Archetypes.Order = { "balanced", "gripper", "slider", "bruiser" }

-- Four cars, each a sparse table of overrides on `Base`. The keys are internal; the
-- `Name` is a placeholder the user replaces when a car is something a player buys.
--
-- TOP SPEED IS NO LONGER CAPPED BY THE SERVER'S SLACK. Until T-033 every archetype had to
-- stay under `179 * 1.25 = 223.75` studs/s, because the server bounded every packet
-- against the top speed of the car IT happened to have active and the switch was
-- client-side. The server is now told which car each player is in (`CarSwitch`,
-- `CarService:SetCar`) and bounds each player against THEIR car, so a car here may be as
-- fast as it deserves to be. The thing that still binds is taste, not the wire.
Archetypes.Cars = {
	-- -------------------------------------------------------------- balanced
	-- THE DEFAULT, AND IT OVERRIDES NOTHING. The car on `main`, approved 2026-11-03.
	balanced = {} :: Car,

	-- -------------------------------------------------------------- gripper
	-- Point and shoot. It does not want to slide: four times the straight-line grip
	-- means a quarter-finger at speed is simply a corner, not a drift, and six times the
	-- squared term means the slide you do provoke snaps itself straight. Slower to
	-- rotate, so it cannot be whipped sideways, and it reaches its ceiling at 48 deg of
	-- slip where the approved car never reaches its at all. Quick off the line, short on
	-- top end. Rewards aiming the car.
	gripper = {
		Name = "Gripper",
		Character = "corners on rails; a slide has to be provoked and it tidies itself up",
		Bars = { Acceleration = 7, Handling = 9, TopSpeed = 5 },
		MaxSteeringSpeed = 1.6,
		ConstantFriction = 57.2, -- 4x
		SlipFriction = 28.6, -- 2x
		SlipSqFriction = 85.8, -- 6x: the bite that catches it
		MaxFriction = 143, -- 4 g, and unlike the others this one is REACHED
		MaxAcceleration = 21.5,
		TopSpeed = 150,
		DownforcePerSpeed = 0.3,
	} :: Car,

	-- -------------------------------------------------------------- slider
	-- Tail-happy and hard to hold. Almost no straight-line grip, so the tail is out the
	-- instant the finger moves, and a LOW squared term, so a big slide never bites back
	-- -- the car keeps going round and the player has to catch it with the finger. The
	-- fastest to rotate of the four. Skill expressed as whether you can hold it.
	slider = {
		Name = "Slider",
		Character = "slides at a touch and never catches itself; holding it is the skill",
		Bars = { Acceleration = 6, Handling = 3, TopSpeed = 6 },
		MaxSteeringSpeed = 2.6,
		ConstantFriction = 4.3, -- 0.3x: nothing tidies a small slide
		SlipFriction = 17.2,
		SlipSqFriction = 7.2, -- 0.5x: a big slide does NOT haul itself round
		MaxFriction = 71, -- 2 g, and never reached either
		MaxAcceleration = 16,
		TopSpeed = 170,
		DownforcePerSpeed = 0.15,
	} :: Car,

	-- -------------------------------------------------------------- bruiser
	-- Fast, heavy, and it has to be planned. The slowest to rotate by a long way and
	-- two and a half times the straight-line grip, so the slip angle opens slowly enough
	-- that a corner has to be started early; once it is out, a low squared term means it
	-- does not snap back either. Carries far more speed in a straight line than anything
	-- else here and takes the longest to get there.
	bruiser = {
		Name = "Bruiser",
		Character = "carries speed in a straight line and has to be turned early",
		Bars = { Acceleration = 3, Handling = 4, TopSpeed = 10 },
		MaxSteeringSpeed = 1.2,
		ConstantFriction = 35.8, -- 2.5x: it holds a line, and a twitch does not unstick it
		SlipFriction = 42.9, -- 3x: a lot of mid-angle grip, which is why it keeps half
		-- its entry speed through a corner where the approved car keeps a quarter
		SlipSqFriction = 7.2, -- 0.5x: and NO snap back. Once it is properly out it goes
		-- round, and only the constant term hauls it in again
		MaxFriction = 107, -- reached at 78 deg of slip
		MaxAcceleration = 10,
		TopSpeed = 215, -- the fastest of the four, and since T-033 the server bounds it against
		-- this number rather than the default car's (see the note above)
		DownforcePerSpeed = 0.35,
	} :: Car,
}

Archetypes.Default = "balanced"

return Archetypes
