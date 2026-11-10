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
-- ground, the walls, the network, the respawn, the control, the score, the debug UI --
-- and `CarBody`, which is which SHAPE is drawn and is a separate axis from which car is
-- driven.
--
-- THE CAMERA'S NUMBERS ARE NOT HERE EITHER. The seventeen `Cam*` keys moved to
-- `Config/Camera.luau` (T-071, docs/game/features/drift-camera.md): they are a look, not
-- a model, and nothing in this file reads them. THE NAMES DID NOT CHANGE, so
-- `Config.Camera.CamOffset` is the key it always was. If a `Cam*` key turns up in this
-- table again, it is in the wrong file.
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
	GravityOnGround = 1, -- EXACT in effect, OURS in form (T-065,
	-- features/road-elevation.md "How the reference does gravity").
	-- Share of gravity that acts ALONG the surface while the car is on
	-- it. The reference never turns gravity off: it applies it every
	-- step and four suspension springs push back along the car's own up
	-- axis, so on a slope the part of gravity that is NOT into the
	-- surface survives and the car runs away downhill. Ours is
	-- kinematic and has no springs, so it does the springs' RESULT in
	-- one line:
	--     g_along = g - up * (g . up)      (`up` is the car's, smoothed)
	--     velocity += g_along * GravityOnGround * dt
	-- On flat ground `g_along` is EXACTLY zero, so this number cannot
	-- touch flat driving at any value. 1 is the reference's behaviour;
	-- 0 is the conditional gravity we shipped before T-065, kept as a
	-- switch because this is the first change to the model since the
	-- user approved the feel (DECISIONS.md, 2026-11-03)

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
	CarBody = "auto", -- OURS, and NOT the archetype: this is which SHAPE `Shared/CarModel`
	-- builds, and the two are deliberately different axes.
	--   "auto"   the ACTIVE archetype's own body, one each, assembled
	--            out of boxes and wedges by code (`Shared/Cars/Bodies`,
	--            T-028). Read when a car is BUILT, so a switched car
	--            brings its shape with it the next time one is built
	--            (`Shared/CarModel`, "when a switch lands")
	--   "balanced" / "gripper" / "slider" / "bruiser"
	--            one of those four bodies, on EVERY car, whichever is
	--            being driven
	--   "ae86"   the car the user added to the Main place, read out of
	--            it and written down in `Shared/Cars/AE86`. NOT
	--            APPROVED TO PUBLISH -- it is a real manufacturer's
	--            car from a third party's upload
	--            (`assets/car-ae86/MANIFEST.md`, features/drift-model.md
	--            "Platform risks") -- and it is kept because it is the
	--            shape the feel gate was passed on
	--   "block"  the box and four cylinders, which is also what a place
	--            whose meshes will not load falls back to
	-- ANY BODY MAY WEAR ANY ARCHETYPE'S NUMBERS: setting this to
	-- anything but "auto" overrides the shape and leaves the feel
	-- alone. Every body is built around the ACTIVE car's `Wheelbase`,
	-- `TrackWidth` and `WheelDiameter`, because that is where the
	-- ground rays go -- the art never moves the geometry

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
	FallBelowSurface = 150, -- studs BELOW THE LAST GROUND THE CAR TOUCHED: fall further than
	-- this and the car asks the server to put it back. It was
	-- `RespawnBelowY = -150`, a world Y, and that only worked because
	-- every surface in both flat worlds tops out at Y = 0. A road that
	-- descends about 14 studs a piece had every car on it "fallen" by
	-- piece eleven (features/road-elevation.md "The fall test stops
	-- being absolute"). Measured from the ground instead, the flat
	-- worlds catch a fall at exactly the same place they always did
	SurfaceTag = "DriftSurface", -- the ground rays prefer parts with this tag; in a place
	-- with nothing tagged at all they fall back to whatever
	-- solid they hit and treat it as road, so a bare plate is
	-- still drivable (docs/game/CONTRACTS.md)
	SurfaceAttribute = "Surface", -- attribute on a tagged part naming its surface
	SurfaceDirt = "dirt", -- the value that means dirt; anything else tagged is tarmac

	-- ---------------------------------------------------------------- suspension and the floor
	-- OURS, T-095 (features/car-v2.md "Rules and numbers", `Drift/Suspension`). Two layers:
	-- the drawn springs (each wheel's travel, the body's sprung offset), which nothing in the
	-- model reads; and the floor solve, which the model runs ONLY when a wheel has run out
	-- of travel or the floor is already resting on something. On flat ground and every road
	-- all four wheels are within their travel and neither layer touches the line.
	-- A WHEEL'S TRAVEL is measured up from fully hanging: 0 hangs, `Travel` is fully up.
	Suspension = {
		Travel = 0.6, -- studs a wheel moves, fully hanging to fully up
		Rest = 0.25, -- studs up from hanging a wheel sits at on flat ground. Where the wheels
		-- have always been drawn: a wheel at Rest is a wheel drawn where it was
		Stiffness = 300, -- 1/s^2. How hard the body's offset springs back (about 2.8 Hz)
		Damping = 22, -- 1/s. And how fast that dies away: 0.64 of critical, so a landing
		-- settles in about a third of a second and overshoots once, a little
		DropTime = 0.15, -- s a wheel takes to fall the whole of its travel with nothing under it
		LandingSquash = 0.15, -- share of a change in the car's vertical speed, on the ground,
		-- the body takes as a jolt into its springs: a landing at 30 studs/s
		-- dips it about a quarter of a stud. 0 turns it off
		MaxBodyTilt = 4, -- deg the body may pitch or roll on its springs off the car's frame
		ReachSlack = 0.05, -- studs past full hang a wheel still counts as touching (drawn)
		HangSlack = 0.75, -- studs past full hang before a wheel counts as out of travel and
		-- the floor solve runs (two wheels at least): a whole stud short of its ground. Over a
		-- step it takes a 2-stud drop under one axle; a kerb never does, and
		-- nor does the road. MEASURED: the touge pieces twist a car's four
		-- wheels up to 0.66 off one plane at a crawl, and at 0.25 that ran the
		-- floor solve on the road and cost RoadTests' drive 9 pieces
		HangHold = 0.25, -- studs. Once running, the floor solve lets go when the pose the
		-- wheels alone would give the car is no more than this below what the
		-- floor and the tyres' travel allow -- always true on a road. Holding on
		-- while the floor was merely NEAR the road never let a car go at all
		HangSpeed = 15, -- studs/s. The floor solve only starts below this ground speed. Faster
		-- than it a car is over an edge and gone before it could tip, and flies
		-- the line the approved model always flew -- the playground's ramp is
		-- launched from at 20 and up, and its jumps are unchanged
		TipAccel = 6, -- rad/s^2. How fast the car may START to tip toward where it would rest
		-- on its floor: gravity's share for a car pivoting on one axle. Off a
		-- ramp lip at speed the wheels are gone before it has turned a degree;
		-- rolled off a ledge at walking pace it settles in a fraction of a second
		MaxTilt = 30, -- deg. The most the floor solve will tip the car on its supports. A car
		-- whose supports are all on one side of its centre of mass tips this far
		-- and slides off whatever it is hanging from
		FloorTouch = 0.05, -- studs. A floor point this close to its ground is touching it
		EdgeDrop = 0.5, -- studs. Two floor points this far off each other's plane have an edge
		-- between them, and it is found by halving the gap
		EdgeSteps = 8, -- halvings: a floor segment 7 studs long pins the edge to 0.03, so a
		-- car tipped 30 degrees on it rests within 0.02 of it -- under
		-- `FloorTouch`. At 5 it rode up to 0.12 clear of the edge in steps
		SearchStep = 8, -- deg. The rest solve's first step, halved down to `SearchFinest`
		SearchFinest = 0.05, -- deg
		-- THE FLOOR, when a car's own is not known: `Drift/Render` reads the real one off
		-- the drawn body (its lower parts' boxes), or a v2 rig's `Floor*` points, the moment
		-- a car is drawn. These only stand in for it -- tests, and the first frame.
		FloorClearance = 0.5, -- studs above the road at ride height
		FloorWidth = 1, -- share of the active car's `BodyWidth`
		FloorLength = 1.05, -- share of its `BodyLength`
		FloorInset = 0.1, -- studs the read-off floor's corners are pulled in from the body's
		FloorCover = 0.3, -- studs of slack when asking which part a floor point is under
		LiftRange = 1, -- studs either way of zero a wheel's lift can be sent over `CarState`
	},

	-- ---------------------------------------------------------------- a hand-placed track
	-- The playground is built by code and is in git; a TRACK is a model someone placed in
	-- the place file by hand, which git never sees (AGENTS.md "Hand-built content"). A
	-- place now gets BOTH (T-026): the track stays where its author put it, and the
	-- playground, which is built from a layout and so can be built anywhere, is moved out
	-- of its way by `PlaygroundOffsetFromTrack` below.
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
	TrackFloorName = "Baseplate", -- the part kept under a track as the floor of last
	-- resort, tagged as dirt. A track is an island and off its
	-- edge there is otherwise nothing at all; the playground
	-- needs none of this because it builds its own plate

	-- ------------------------------------------------------------- both worlds at once
	-- WHERE THE PLAYGROUND IS BUILT WHEN THE PLACE ALSO HAS A TRACK, and nothing else: a
	-- place with no track builds it at the origin exactly as before, so every lane and
	-- every test place is unchanged (T-026).
	--
	-- THE TWO WORLDS SIT SIDE BY SIDE ON ONE CONTINUOUS FLOOR, and that is the whole point
	-- of the number. It was -12 000, then -2 200, and both left the playground an ISLAND
	-- ACROSS A VOID: the user drove to the edge, looked at the gap and said "how the fuck
	-- am i supposed to get there lol. put them on the same baseplate connected to eachtoher
	-- just one right next to the other". Quite right -- a world you can only teleport to is
	-- not in the same build, it is a second build.
	--
	-- Why -2 024 on X, and why only on X:
	--   * the playground's plate is 2 000 studs across, so it is +/-1 000 about wherever
	--     it is put. At -2 024 its plate runs x -3 024..-1 024, and the baseplate runs
	--     -1 024..1 024 -- so the two plates MEET EXACTLY, edge to edge. No overlap, so no
	--     z-fighting and no ambiguity about which surface a ground ray finds; no gap, so no
	--     step and no bump; and every surface tops out at Y = 0, so a car drives from one
	--     world into the other without noticing;
	--   * from the playground's edge at -1 024 to the track's at -560 is 464 studs of bare
	--     baseplate -- about three seconds at speed. Next door, with a short drive between,
	--     which is what was asked for;
	--   * it is HORIZONTAL only, so both worlds' ground is still Y = 0 and the one `FallY`
	--     is right for both. (A car's own fall is no longer absolute at all --
	--     `FallBelowSurface` -- but PlaygroundService's catcher still is.) Z is never
	--     offset, so Z never needs separating either;
	--   * -X is the empty quarter: the collision tests stand their own rig at
	--     (20 000, 500, 20 000) and the jitter tests probe at (2 000, 0, 0).
	-- `DebugCross()` is still there and still instant, but it is now a convenience rather
	-- than the only way across. `DebugPlaygroundTests` fails loudly if this is ever set
	-- small enough to overlap, so the value guards itself.
	PlaygroundOffsetFromTrack = Vector3.new(-2024, 0, 0),

	-- Which world a car SPAWNS in, and the world every respawn falls back to when the
	-- server cannot tell where the car was: "track" or "playground". Track by default,
	-- because that is the world being driven; a place with no track gets the playground
	-- whatever this says.
	StartWorld = "track",

	-- ---------------------------------------------------------------- walls
	WallScrub = 0.5, -- share of speed kept after hitting something
	WallPush = 0.2, -- studs the car is held off the surface it hit

	-- ---------------------------------------------------------------- pinned against a wall
	-- OURS, and the whole of it is OFF AT `UnstickSpeed = 0`, which gives back exactly the
	-- model the user approved on 2026-11-03 (T-074, features/drift-model.md "Pinned
	-- against a wall"). It adds no force and moves the car nowhere: while the car counts
	-- as pinned the grip is simply not applied, and nothing else changes.
	--
	-- WHAT IT IS FOR, as a measurement. Let `t` be the angle between the car's nose and
	-- the wall it is touching. Along that wall the drivetrain pushes
	-- `MaxAcceleration * cos(t)` and the grip pulls back `f(t) * sin(t)` -- the grip's
	-- pull is sideways in the CAR's frame, and with the nose into a wall "sideways" is
	-- along the wall and backwards. They cross at about 27 degrees of nose angle, and past
	-- it the car stops dead at 0.07 studs/s and never moves again. Measured on a banked
	-- plane with a barrier: identical at 10 degrees of bank and at 30, so the bank is not
	-- the cause -- it is only what keeps feeding the car back into the wall. And it is not
	-- the past-90-degree brake either: that was the suspicion and the numbers refused it.
	--
	-- The cost of the trap, before this: the test autopilot over 50 generated pieces spent
	-- 0.5 s stuck at 5 degrees of bank, 11.9 at 8, 40.2 at 10 and 113.8 at 15, and at 30
	-- it never finished the road at all (8 pieces of 50 in 400 s). That is why the
	-- showcase corner shipped at 10 degrees instead of the spec's 30.
	-- A car counts as PINNED when it has been slower than `UnstickSpeed` for
	-- `UnstickSeconds` and has touched a wall inside the last `UnstickSeconds`. While it
	-- is, the grip is not applied and the wall scrub is not charged. Nothing else changes,
	-- and nothing is ever added.
	--
	-- "TOUCHED A WALL INSIDE THE WINDOW", NOT "IS TOUCHING ONE", and the difference is the
	-- whole of whether this works. Measured on the real road: a car held against a barrier
	-- for 40 seconds reported a wall on 387 steps out of 4 824 -- one in twelve -- because
	-- `WallPush` holds it a fifth of a stud clear and gravity has to carry it back across
	-- that gap before the next Blockcast can reach anything. The first version of this
	-- asked for unbroken contact and never fired once.
	UnstickSpeed = 5, -- studs/s. Slower than this, with a wall about, the car is PINNED.
	-- ZERO TURNS THE WHOLE THING OFF and gives back the approved
	-- model exactly.
	-- FIVE, AND IT IS THE NUMBER THAT MATTERS: the pin's own
	-- equilibrium is 0.07 studs/s, so a car that is really stuck is
	-- far under this, and 5 is what `RoadTests` has always called
	-- stopped. MEASURED, 50 pieces at 10 degrees of bank: at 5 the
	-- car drives all 50 and is stuck 1.4 s; AT 15 IT DRIVES 37 AND IS
	-- STUCK 13.2. Fifteen is a hairpin's speed, not a pinned car's,
	-- so it takes the grip away where the car needs it to rotate and
	-- the car cannot make the tight corners at all. The honest
	-- reading is that this must only ever fire on a car that has
	-- genuinely stopped
	UnstickSeconds = 0.2, -- s, and it is BOTH clocks, which do two different jobs:
	--   as a DWELL, how long the car must have been that slow. A car
	--   that merely DIPS under the speed in a corner keeps its grip,
	--   and that matters -- without the dwell the 50-piece drive fell
	--   from 50 pieces to 37, because the grip is what rotates a car
	--   round a tight corner;
	--   as a WINDOW, how recently it must have touched a wall. It has
	--   to be at least as long as the gaps between touches (above) or
	--   nothing ever fires.
	-- TWO TENTHS, AND LONGER IS WORSE. Six seeds of 50 pieces at 10
	-- degrees of bank, seconds the autopilot spent stopped: at 0.2
	-- every seed is better than or equal to the unstick being off; at
	-- 0.5 seed 1 falls from 214 s to 0.7 but SEED 8080 CLIMBS FROM 40
	-- TO 173. Too generous and the grip comes off a car that is merely
	-- slow near a barrier, which is a hairpin

	UnstickRelease = 45, -- studs/s. The pin also ends once the car is going this fast
	-- again, even if it is still scraping the wall. Without it a car
	-- that escapes along a banked barrier keeps the grip off for the
	-- rest of the corner, because gravity never lets it leave the
	-- wall. 45 is under half what the road makes the car do on a
	-- straight, so a driving car always has its grip back

	-- ---------------------------------------------------------------- network
	StateSendRate = 20, -- Hz, CarState to the server
	RemoteCarSmoothing = 0.08, -- s, how fast another player's car eases to its reported pose
	StateRateLimit = 30, -- packets a second per UserId the server will take before dropping
	StateSpeedTolerance = 1.25, -- share of TopSpeed a reported horizontal speed may reach.
	-- SINCE T-033 THAT IS THE TOP SPEED OF THE CAR THAT PLAYER
	-- IS IN, not of one global car: the server is told which car
	-- each player is in over `CarSwitch` and keeps its own copy
	-- of that car's numbers, so the bruiser is bounded at 215 x
	-- 1.25 and the gripper at 150 x 1.25 in the same server, in
	-- the same second (docs/game/CONTRACTS.md, `CarState`)
	StateMoveTolerance = 1.5, -- slack on how far a car may have moved since its last packet
	StateMoveAllowance = 9, -- studs of slack on top, for a dropped packet or a jittery clock

	-- ---------------------------------------------------------------- the car a player is in
	-- The server owns it (`CarService`, docs/game/CONTRACTS.md `CarSwitch`). These are the
	-- limits on the asking, and they are the respawn's numbers in a different hat: a
	-- client may ask, a client may not insist, and a packet already on the wire when the
	-- answer lands is honest and must not be thrown away.
	CarSwitchRateLimit = 5, -- requests a second per UserId the server will take. Above it
	-- the ask is refused, counted and ANSWERED -- the answer is how
	-- a refused client is put back in the car the server believes
	CarSwitchGrace = 1, -- s after a switch in which a CarState that fails against the new
	-- car's numbers is also tried against the car the player was just
	-- in. A packet sent a moment before the switch lands after it --
	-- `CarState` is unreliable and the switch is a reliable round trip
	-- -- and bounding the bruiser's honest 215 studs/s against the
	-- gripper it has just become would drop it. Exactly `RespawnGrace`'s
	-- problem and exactly its answer, which is why the number matches

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
	DebugReadout = true, -- build the debug readout at all
	DebugReadoutOpen = false, -- but CLOSED from the start: the numbers are a measuring
	-- instrument, not part of the game, and the user driving
	-- for feel should see the car and the slider and nothing
	-- else. F3, DPad up or the DBG button brings them back
	DebugStatsOpen = false, -- and the car's stat panel is folded inside it, closed too.
	-- F5, or clicking its header, unfolds it; F4 switches car

	-- ---------------------------------------------------------------- the tuner
	-- The car tuner and its garage (`Drift/TunerUI`, `Services/GarageService`,
	-- features/car-tuner.md). A DEV TOOL, like the readout and the trajectory line: it
	-- moves the active car's numbers live and saves named sets of them, and none of it is
	-- a shop, a garage screen or anything a player will ever see.
	--
	-- NOT the stat panel. That is a READOUT of the car (`Drift/DebugHud`); this is the
	-- instrument that moves it. They are deliberately separate and both can be open.
	Tuner = true, -- build the tuner at all
	TunerOpen = false, -- but CLOSED from the start: the user driving for feel
	-- should see the car and nothing else. F7, the gamepad's Y,
	-- or the TUNE button opens it
	TunerKey = Enum.KeyCode.F8, -- opens and closes it. F3/F4/F5 are the readout's and F6
	-- is the trajectory line's, so F7 was the obvious next one --
	-- AND STUDIO EATS F7. It is Studio's own Client/Server view
	-- toggle and the keypress never reaches the game: measured in
	-- DR-Lane2, where F8, F10, G and T all arrived and F7 alone did
	-- not. Worth knowing before binding the next dev key
	TunerGamepadKey = Enum.KeyCode.ButtonY, -- the same, on a pad. DPad up/right/left are
	-- already the readout's, the car switch and the line's
	TunerWidth = 336, -- px. The panel's column, on the RIGHT: the readout owns the top
	-- left (measured 508 px wide) and both are often open at once
	TunerTop = 168, -- px from the top of the screen. Under the readout's DBG button and
	-- the tuner's own TUNE button, which share that corner
	TunerBottomGap = 190, -- px of screen the panel must leave clear at the bottom, so it
	-- never covers the handbrake (96 px at 28 from the corner). The
	-- panel is sized from the VIEWPORT rather than from its contents
	-- for this reason: a dev panel that grows over the STOP button
	-- on a phone is a dev panel that strands the car
	TunerRowHeight = 33, -- px per slider row: the label and value line, then the track
	TunerSendRate = 10, -- Hz the live tune is sent to the server while a slider is being
	-- dragged. The TUNE ITSELF IS INSTANT AND LOCAL -- the model reads
	-- the car every step -- and this is only so the server's speed bound
	-- keeps up with it (`GarageService`, "the ceiling"). Sent again on
	-- release, so the server always ends up with the final value

	-- ---------------------------------------------------------------- the garage
	-- The dev store behind the tuner. THE FIRST THING IN THIS GAME THAT SAVES ANYTHING,
	-- and deliberately not the start of the save system: `DataService` and `PlayerData`
	-- are still unbuilt (`ARCHITECTURE.md`), and this is one small server-owned store for
	-- tuned cars only, to be deleted when the real one arrives.
	GarageMaxCars = 12, -- saved cars a player may keep. A full garage refuses a NEW name
	-- and still overwrites an existing one, so a tuning session is
	-- never stuck with nowhere to put the car it is driving
	GarageNameMax = 24, -- characters in a car's name, after trimming
	GarageSaveRateLimit = 4, -- saves or deletes a second per UserId before the ask is
	-- ignored. A save is a DataStore write eventually, and a
	-- client that asks faster than a person can type is not a person
	GarageTuneRateLimit = 30, -- live tune packets a second per UserId. `TunerSendRate` is
	-- 10, so this is three times what an honest client sends
	GarageWriteInterval = 8, -- s between writes of a garage that has changed. NEVER on
	-- every slider move: the in-memory copy is the live one and the
	-- store catches up behind it (CODING.md "Data store limits")
	GarageWriteRetries = 3, -- attempts at a write before it is given up on and warned
	-- about. THE IN-MEMORY COPY IS KEPT EITHER WAY: a failed write
	-- must never cost the user the car they are driving
	GarageRetryBackoff = 2, -- s before the first retry, doubled each time after

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
	-- plane does not know they are there. False predicts against the
	-- live Workspace and pays four ground rays per step for a line
	-- that follows the ground.
	-- IT IS A COST DECISION AND IT DEPENDS ON THE WORLD, which is
	-- the thing to know before changing it. On the PLAYGROUND, which
	-- is built from a few hundred parts, the real world costs about
	-- 0.66 ms a frame against 0.4 flat and the two agree to within a
	-- stud -- so false is nearly free and strictly better there. On
	-- the Main place's hand-placed TRACK, 5580 parts of wedges and
	-- unions, the same setting measured 21.7 ms a frame average and
	-- 32.1 ms worst: a frame at 60 FPS is 16.7 ms, so it is not a
	-- trade, it is unusable. Flat on that track is 0.3 ms and some
	-- of its line is wrong where the ground rises (measured 56 studs
	-- out at one spot, against the real world's 24).
	-- SO: TRUE. This is a dev tool, and a line that costs the frame
	-- rate teaches nothing. Set it false on a cheap world, or when
	-- the ground under the line matters more than the frame does
	TrajectoryMaxSegments = 64, -- parts the line may use. The pool is created once and
	-- reused; spares are hidden, never destroyed
	TrajectoryWidth = 0.35, -- studs. Thin on purpose: it is an overlay, not scenery
	TrajectoryLift = 1, -- studs above the predicted path, so the line is not inside the road
	TrajectoryColour = Color3.fromRGB(94, 255, 162),
	TrajectoryTransparency = 0.25,
	-- The line fades ALONG ITSELF, not by distance from the camera: solid near the car,
	-- gone at the far tip, so the end reads as "this is where it ends" and not as a cut.
	TrajectoryFadeHold = 0.35, -- OURS. Fraction of the line held at
	-- `TrajectoryTransparency` before the fade starts at all.
	-- The near stretch is the one being read, so it stays solid
	TrajectoryFadeEnd = 1, -- OURS. Transparency at the far tip; 1 is fully invisible
	TrajectoryFadeShape = 1.15, -- OURS. Above 1 lingers a little longer before falling
	-- away, below 1 leaves sooner. Fed into a smoothstep,
	-- which is flat at both ends: no kink where the fade
	-- starts and no wall where it ends
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
-- (`DriftTests` does) never reaches this at all.
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
