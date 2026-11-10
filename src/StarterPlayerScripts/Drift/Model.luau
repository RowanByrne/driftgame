--!strict
-- Model: the drift model itself, and nothing else.
--
-- A port of the reference game's model (docs/game/features/drift-model.md), written from
-- a description of how its maths works. It is pure maths plus two injected world queries,
-- so it runs with no player, no car and no Workspace: that is what makes DebugDrive and
-- the determinism test possible.
--
-- THE WHOLE MODEL IN FIVE LINES, and the order is the step:
--
--   1. The finger IS the car's yaw rate.  yawRate = MaxSteeringSpeed * steer. Set, not
--      pushed. Centre the finger and the car stops turning on the next step.
--   2. Nothing moves the velocity when the car rotates, so the angle between the nose and
--      where the car is actually going -- the slip angle -- opens on its own. ROTATING IS
--      DRIFTING. There is no drift input, no threshold and no mode.
--   3. Grip pulls the velocity back toward the nose, growing as a quadratic in the slip
--      angle up to a ceiling. Past 90 degrees of slip it points against the travel
--      instead and becomes a brake: spinning the car round is how you stop it.
--   4. The drivetrain pushes along the NOSE, rear wheels only, with less to give the
--      faster the car already is. A car that is sideways has its engine pushing across
--      its own travel, so a drift costs speed without a number saying so.
--   5. Downforce, then our own gravity (Config.Drift.Gravity, not Roblox's) -- all of it
--      in the air, and on the ground the part of it that points ALONG the surface, which
--      is zero on the flat and is what makes a hill a hill (T-065).
--
-- There is NO yaw inertia, NO yaw damping, NO steering lock, NO bicycle-model tyre slip
-- and NO weight-throw in this model. Adding any of them breaks the feel this is for.
--
-- Signs, which are the only thing here that is easy to get wrong:
--   `yaw`  Roblox's, radians. POSITIVE TURNS LEFT, and `yaw += r * dt`.
--   `r`    the yaw rate, same sense: positive turns left.
--   `b`    the slip angle (`s.slip`), the signed angle FROM THE NOSE TO THE VELOCITY
--          about the car's up. POSITIVE means the car is travelling out to its LEFT,
--          which is a car whose tail has swung right. Grip then pulls the velocity to the
--          car's right -- `carRight * sign(b)` -- which is back toward the nose.
--   `v`    lateral speed, positive to the car's RIGHT. So `b` and `v` have opposite signs.
--
-- Every number comes from Config.Drift. There are no constants in here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Suspension = require(script.Parent.Suspension)

local Model = {}

local EPS = 1e-4

-- How many times one step may stop at a surface and spend what is left of itself sliding
-- along it. A loop guard, not a tuning number -- one is a wall, two is a corner, and
-- nothing the car can reach in 1/120 s needs a third.
local MAX_SLIDES = 3

-- A surface facing this far up is ground the car can be carried along by. Steeper than
-- that and a ground ray has found the side of something, which the car is never carried
-- up: Drift/World calls anything steeper a wall and stops the car against it.
local GROUND_NORMAL_Y = 0.7

export type Input = {
	-- NOT a steering wheel and NOT a weight to throw: this is the car's rate of turn, as a
	-- share of `MaxSteeringSpeed` (features/drift-model.md "Steering -- the control").
	steer: number, -- -1 .. +1
	-- Only to stop the car once a run is over. There is no brake in normal play, and the
	-- throttle is not an input at all.
	handbrake: boolean?,
}

-- What a ground ray found. `grip` and `score` are the surface's own multipliers, so the
-- model never has to know what a surface is called (Drift/World).
export type Hit = { y: number, normal: Vector3, grip: number, score: number }

-- The queries the model makes of the world. Drift/World builds them, for the live
-- Workspace and for a flat plane.
--
-- `sweep` answers WHERE THE CAR MAY GET TO, not where the surface is, and the difference
-- is the whole of whether a building is solid (Drift/World, T-018). `penetration` says
-- which way is out of anything the car is inside; both are optional, and a world without
-- them has no walls at all.
export type World = {
	probe: (pos: Vector3) -> Hit?,
	sweep: ((from: Vector3, to: Vector3, yaw: number) -> (Vector3?, Vector3?))?,
	penetration: ((pos: Vector3, yaw: number) -> (Vector3?, number))?,
}

export type State = {
	position: Vector3,
	yaw: number, -- radians, Roblox sense (+ turns left)
	velocity: Vector3, -- world, studs/s, vertical included. The one thing the model moves
	r: number, -- yaw rate, rad/s, + turns left. Set from the finger every step
	u: number, -- forward speed along the nose (+ forwards), read off `velocity`
	v: number, -- lateral speed (+ to the car's right), read off `velocity`
	vy: number, -- vertical speed, read off `velocity`
	slip: number, -- the slip angle `b`, radians, signed (see the header)
	steer: number, -- the finger this step, -1 .. 1
	throttle: number, -- 0 .. 1, eased in over `FullThrottleSeconds`; never an input
	gripAccel: number, -- studs/s^2 of lateral pull the grip made this step
	braking: boolean, -- past 90 degrees of slip: the grip is pointing against the travel
	drifting: boolean, -- |slip| >= MinSlipAngleForDrift, for the readout and the score
	wheelsDown: { boolean }, -- FL, FR, RL, RR
	rearDown: boolean, -- at least one driven wheel is on the ground
	surfaceGrip: number, -- mean of the four wheels' surface grip, 0 .. 1
	surfaceScore: number, -- the same for the score multiplier
	grounded: boolean,
	airborne: boolean,
	up: Vector3, -- smoothed surface normal
	groundY: number?, -- ground height under the car THIS step; nil over a void
	fallFrom: number, -- the last ground height the car had under it, kept after the ground
	-- is gone. A fall is measured from this, never from a world Y
	bodyRoll: number, -- radians of cosmetic lean, about the car's own forward axis
	wheelSteer: number, -- radians the front wheels are DRAWN at. Cosmetic: they follow
	-- the travel, which is opposite lock for free
	wheelSpin: number, -- radians, for drawing only
	wallHit: boolean,
	sinceWall: number, -- seconds since the car last touched a wall. TIME SINCE, not time
	-- in: contact is intermittent even when the car is held (T-074)
	crawlSeconds: number, -- seconds the car has been slower than `UnstickSpeed`
	pinned: boolean, -- held against a wall and crawling, so the grip and the wall scrub are
	-- both let go this step. Never true at `UnstickSpeed = 0`
	fell: boolean,
	time: number, -- seconds of simulation since the state was made

	-- THE SUSPENSION AND THE FLOOR (T-095, Drift/Suspension). The first three are drawn and
	-- nothing above reads them; the floor ones are the simulation's only while `hanging`.
	travel: { number }, -- each wheel's travel, FL FR RL RR: 0 hanging .. `Travel` fully up
	wheelLift: { number }, -- studs each wheel is drawn up off the car's frame
	body: Suspension.Body, -- the body's sprung offset on the car's frame
	hanging: boolean, -- a wheel ran out of travel or the floor was down: the floor solve ran
	tiltRate: Vector2, -- rad/s the floor solve is tipping the car at (pitch, roll)
	floor: { Suspension.FloorPoint }?, -- the car's floor points; nil is the config's box
	floorContacts: { Suspension.Contact }, -- floor points resting on something this step
	floorTouching: number, -- how many
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

-- Where the four ground rays go, in the car's own axes: front/back, then left/right.
-- Front is the look vector, which is Roblox's -Z, and the order is the one
-- Shared/CarModel draws: FL, FR, RL, RR. The last two are the driven pair.
local WHEELS = {
	{ front = 1, side = -1 },
	{ front = 1, side = 1 },
	{ front = -1, side = -1 },
	{ front = -1, side = 1 },
}
Model.WHEEL_COUNT = #WHEELS
Model.REAR_WHEELS = { 3, 4 }

-- The car's flat forward and right vectors, from its Roblox yaw. Used by anything that
-- only wants the heading (the camera, the network send).
function Model.axes(yaw: number): (Vector3, Vector3)
	local s, c = math.sin(yaw), math.cos(yaw)
	return Vector3.new(-s, 0, -c), Vector3.new(c, 0, -s)
end

-- The car's real basis, tilted onto the surface it is standing on: forward, right, up.
local function basis(s: State): (Vector3, Vector3, Vector3)
	local up = s.up
	if up.Magnitude < EPS then
		up = Vector3.yAxis
	end
	up = up.Unit
	local flat = Model.axes(s.yaw)
	local right = flat:Cross(up)
	if right.Magnitude < EPS then
		return flat, Vector3.new(flat.Z, 0, -flat.X), Vector3.yAxis
	end
	right = right.Unit
	return up:Cross(right), right, up
end

function Model.new(spawnCFrame: CFrame): State
	local _, yaw = spawnCFrame:ToEulerAnglesYXZ()
	return {
		position = spawnCFrame.Position,
		yaw = yaw,
		velocity = Vector3.zero,
		r = 0,
		u = 0,
		v = 0,
		vy = 0,
		slip = 0,
		steer = 0,
		throttle = Config.Drift.StartThrottle,
		gripAccel = 0,
		braking = false,
		drifting = false,
		-- A car is spawned standing on the road, and the first step's grip and drivetrain
		-- read these before the first ground ray has been cast. One step (1/120 s) later
		-- the rays own them, so a car spawned in the air corrects itself immediately.
		wheelsDown = { true, true, true, true },
		rearDown = true,
		surfaceGrip = Config.Drift.GripTarmac,
		surfaceScore = Config.Drift.ScoreTarmac,
		grounded = true,
		airborne = false,
		up = Vector3.yAxis,
		groundY = nil,
		-- A car is spawned standing on something, at ride height above it, so that is the
		-- ground a fall is measured from until the first ray finds the real one -- one step
		-- later. Without it a car spawned over a void could never be caught at all.
		fallFrom = spawnCFrame.Position.Y - Config.Drift.RideHeight,
		bodyRoll = 0,
		wheelSteer = 0,
		wheelSpin = 0,
		wallHit = false,
		sinceWall = math.huge,
		crawlSeconds = 0,
		pinned = false,
		fell = false,
		time = 0,
		travel = table.create(#WHEELS, Config.Drift.Suspension.Rest),
		wheelLift = table.create(#WHEELS, 0),
		body = Suspension.newBody(),
		hanging = false,
		tiltRate = Vector2.zero,
		floor = nil,
		floorContacts = Suspension.EMPTY_CONTACTS,
		floorTouching = 0,
	}
end

-- Speed across the ground: what the player reads off the HUD, and what the camera scales
-- its field of view by. The vertical is deliberately left out of it.
function Model.speed(s: State): number
	return math.sqrt(s.u * s.u + s.v * s.v)
end

-- The car's pose, built from its position, yaw and the surface it is following.
function Model.cframe(s: State): CFrame
	local _, right, up = basis(s)
	return CFrame.fromMatrix(s.position, right, up)
end

-- One fixed step. Mutates and returns `s`; the caller owns the state table.
function Model.step(s: State, input: Input, dt: number, world: World): State
	local C = Config.Drift

	local steer = clamp(input.steer or 0, -1, 1)
	local handbrake = input.handbrake == true
	s.steer = steer
	local vyBefore = s.vy -- the drawn springs feel a change in it (Drift/Suspension)

	---------------------------------------------------------------- the throttle
	-- Not an input. The car drives itself and eases in, so a first-time player is never
	-- handed a car at top speed (features/drift-model.md "How it plays", item 2).
	s.throttle = lerp(C.StartThrottle, 1, clamp(s.time / math.max(C.FullThrottleSeconds, EPS), 0, 1))

	---------------------------------------------------------------- the finger is the yaw rate
	-- The one line the whole feel rests on. Not a torque, not a wheel angle, not a target
	-- to ease toward: the rate of turn is SET, every step, from the finger. Centre it and
	-- the car stops turning on the very next step.
	--
	-- `InvertSteering` is which way round that reads. True -- the sense the user asked for
	-- -- is a finger to the right turning the car LEFT, because the gesture is on the
	-- car's rear: push the tail right and the nose goes left.
	s.r = C.MaxSteeringSpeed * steer * C.SteeringSensitivity * (if C.InvertSteering then 1 else -1)
	s.yaw += s.r * dt

	local fwd, right, up = basis(s)

	---------------------------------------------------------------- the slip angle
	-- Nothing above touched the velocity, so the nose has just moved out from under it:
	-- this is where the drift comes from, and it is the whole of where it comes from.
	local vel = s.velocity
	local flow = vel - up * vel:Dot(up) -- the velocity in the car's own plane
	local b = 0
	if flow.Magnitude > EPS then
		b = math.atan2(-flow:Dot(right), flow:Dot(fwd))
	end
	s.slip = b
	s.drifting = math.abs(b) >= math.rad(C.MinSlipAngleForDrift)

	---------------------------------------------------------------- pinned against a wall
	-- OURS, NOT THE REFERENCE'S, and `UnstickSpeed = 0` turns the whole of it off and
	-- gives back exactly the model the user approved (T-074). It adds no force and moves
	-- the car nowhere: all it ever does is WITHHOLD the grip, and only while the car is
	-- held against a wall and crawling.
	--
	-- WHY A CAR AGAINST A WALL CANNOT DRIVE AWAY, measured rather than guessed. Take the
	-- angle `t` between the car's nose and the wall it is touching. Along that wall:
	--
	--   the drivetrain pushes    MaxAcceleration * cos(t)
	--   the grip pulls BACK      f(t) * sin(t)       (f is the quadratic in the slip angle)
	--
	-- The grip's pull is `carRight * sign(b)`, which is sideways IN THE CAR'S FRAME -- so
	-- with the nose into a wall and the travel along it, "sideways" is ALONG THE WALL AND
	-- BACKWARDS. The wall deletes the into-the-wall half of both, and what is left is a
	-- brake against a push. They cross at about 27 degrees of nose angle: past it the
	-- brake wins, and the car stops dead at 0.07 studs/s and stays there for ever. The
	-- reference's per-axis clamp holds it exactly at what one step of drivetrain adds.
	--
	-- IT IS NOT THE PAST-90-DEGREE BRAKE. That was the suspicion; the measurement says
	-- otherwise. A car nose-ON to a wall scrapes along it at 120 studs/s on a 30-degree
	-- bank quite happily, and the trap bites from 27 degrees of nose, where the grip is
	-- still a sideways pull and nothing in it is braking by intent. Nor is it the bank:
	-- the equilibrium is 0.07 studs/s at 10 degrees of bank and at 30 alike. The bank's
	-- only job is to keep feeding the car back into the wall so the nose-in state lasts.
	--
	-- SO THE FIX IS TO STOP THE GRIP, not to push the car. A player gets out of this by
	-- pointing the nose along the wall and letting the engine pull them out -- measured,
	-- that works and reaches 50 studs/s -- but the window is about 25 degrees wide out of
	-- 360 and the car gives no feedback at all while it is stopped. With the grip let go,
	-- the drivetrain's along-the-wall share is unopposed at any nose angle but a right
	-- one, and the car drives itself out the same way.
	--
	-- WHAT PINNED MEANS, AND WHY IT IS NOT "TOUCHING A WALL". The first version of this
	-- asked for UNBROKEN wall contact and it never fired once on the real road: measured
	-- over a 50-piece drive, the car spent 4 824 steps stuck against a barrier and only
	-- 387 of them reporting a hit -- CONTACT IS ONE STEP IN TWELVE. `WallPush` holds the
	-- car a fifth of a stud off what it hit, so gravity has to carry it back across that
	-- gap before the next Blockcast can reach anything, and a clock that resets on a step
	-- without a wall is reset about ten times a second. A car held against a barrier does
	-- not touch it continuously; it rattles against it.
	--
	-- So it is TWO CLOCKS, both measured in `UnstickSeconds`, and they do two different
	-- jobs. Dropping either one was tried and both cost a measurement:
	--
	--   `crawlSeconds`  a DWELL: the car has been slower than `UnstickSpeed` for this
	--                   long. Without it a car that merely DIPS under the speed in a
	--                   corner loses its grip for the dip, and the grip is what rotates
	--                   it: the 50-piece drive fell from 50 pieces to 37.
	--   `sinceWall`     a WINDOW: a wall was touched inside this long. Without it being a
	--                   window -- the first version asked for contact on the step -- it
	--                   never fires at all, because of the gaps above.
	--
	-- WHAT KEEPS IT OUT OF NORMAL DRIVING: leaning on a barrier at speed is above
	-- `UnstickSpeed` and never qualifies; a car that is merely slow, in a hairpin, has
	-- touched nothing and never qualifies either -- it takes both. Between `UnstickSpeed`
	-- and `UnstickRelease` the flag HOLDS whatever it was, which is the hysteresis that
	-- lets an escaping car keep accelerating; it ends when the walls go quiet or the car
	-- is doing `UnstickRelease` again. On the flat road, where the car never meets a wall
	-- at a crawl, the flag is never set and the step is the step the user drove.
	local groundSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
	if groundSpeed < C.UnstickSpeed then
		s.crawlSeconds += dt
	else
		s.crawlSeconds = 0
	end
	if C.UnstickSpeed <= 0 then
		s.pinned = false
	elseif s.crawlSeconds >= C.UnstickSeconds and s.sinceWall <= C.UnstickSeconds then
		s.pinned = true
	elseif s.sinceWall > C.UnstickSeconds or groundSpeed >= C.UnstickRelease then
		s.pinned = false
	end

	---------------------------------------------------------------- grip closes it again
	-- A quadratic in the slip angle, capped, times the surface. The angle it is read at is
	-- capped at square-on, so the curve stops growing there and the ceiling is a real
	-- ceiling rather than something a spin can climb past.
	--
	-- Past 90 degrees the car is going backwards relative to its nose, and the pull stops
	-- being sideways: it points straight against the travel and becomes a brake. That is
	-- how a spun car stops, and nothing else in the model slows it down.
	s.gripAccel = 0
	s.braking = false
	-- `not s.pinned` is the whole of T-074's change to the model, and it is the only line
	-- in this block that is not the reference's. At `UnstickSpeed = 0` it is never true.
	if s.grounded and s.surfaceGrip > 0 and not s.pinned then
		local bc = math.min(math.abs(b), math.pi * 0.5)
		local f = math.min(C.ConstantFriction + C.SlipFriction * bc + C.SlipSqFriction * bc * bc, C.MaxFriction)
		f *= s.surfaceGrip * C.FrictionMultiplier

		local dir: Vector3
		if math.abs(b) > math.pi * 0.5 and flow.Magnitude > EPS then
			dir = -flow.Unit
			s.braking = true
		else
			dir = right * (if b >= 0 then 1 else -1)
		end

		-- The reference's own clamp, per WORLD axis: never pull an axis further in one
		-- step than that axis is actually going. It is what stops the pull overshooting
		-- through zero and juddering when the car is nearly stopped.
		local dv = dir * (f * dt)
		dv = Vector3.new(
			clamp(dv.X, -math.abs(vel.X), math.abs(vel.X)),
			clamp(dv.Y, -math.abs(vel.Y), math.abs(vel.Y)),
			clamp(dv.Z, -math.abs(vel.Z), math.abs(vel.Z))
		)
		vel += dv
		s.gripAccel = f
	end

	---------------------------------------------------------------- the drivetrain
	-- Along the NOSE, rear wheels only, with nothing left at top speed. `u` is a
	-- magnitude, so a car travelling backwards under power counts that as speed for the
	-- falloff: the reference's own quirk, and it only shows up in that rare case.
	if s.rearDown then
		local u = math.abs(vel:Dot(fwd)) / math.max(C.TopSpeed, EPS)
		local a = C.MaxAcceleration * C.AccelMultiplier * clamp(s.throttle, 0, 1) * clamp(1 - u * u, 0, 1)
		vel += fwd * (a * dt)
	end

	---------------------------------------------------------------- downforce, then gravity
	-- Downforce pins the car in proportion to its speed and switches off once the car is
	-- genuinely falling, so a jump is a jump. On a car that follows the ground it is only
	-- felt in the air -- it is what decides how far a jump carries.
	if vel.Y >= C.DownforceCutoff then
		vel -= Vector3.yAxis * (vel.Magnitude * C.DownforcePerSpeed * dt)
	end
	-- Our own gravity, not Roblox's. In the air it is the whole of it, straight down.
	--
	-- ON THE GROUND IT IS THE PART THAT POINTS ALONG THE SURFACE, and nothing else
	-- (T-065, features/road-elevation.md "How the reference does gravity"). The reference
	-- never turns gravity off: it applies it every step and four suspension springs push
	-- back along the CAR'S OWN UP AXIS. A spring pushes along that axis; gravity pulls
	-- straight down; on a slope those differ, and the difference is never cancelled -- so
	-- the car runs away downhill with no code anywhere that mentions a slope. A kinematic
	-- car has no spring to port, but it does not need one: it needs the spring's RESULT,
	-- which is that the into-the-surface part goes away and the along-the-surface part
	-- does not.
	--
	-- `up` is the SMOOTHED body up, not the raw normal the rays found, and that is
	-- deliberate twice over. It is the reference's own choice -- the springs cancel
	-- gravity along `transform.up`, the body's attitude, which lags the road because it is
	-- sprung -- and it is the axis the grip above already acts in (`basis`), so the model
	-- keeps ONE frame for both forces. The raw normal stays where it belongs, on the
	-- constraint: the ground follow below uses it to decide how fast the surface is
	-- climbing, as a raycast length does in the reference. Forces in the body frame, the
	-- constraint in the ray's -- and on a crest the lag means the pull downhill arrives as
	-- the car settles on to the new slope, rather than the instant a ray sees it.
	--
	-- This term carries a vertical part as well, and it is not double-counting `climb`
	-- below: while the car is grounded `climb` OVERWRITES vel.Y from the horizontal
	-- velocity and the surface, so only the horizontal part of `g_along` survives a
	-- grounded step -- and `|g_along| = g sin(t)` means that horizontal part is exactly
	-- `g sin(t) cos(t)`, which is what a velocity held in the surface's plane needs. The
	-- vertical part only survives on the one step the car leaves the ground, which is the
	-- step it should.
	--
	-- On flat ground `g_along` is EXACTLY zero (`up` is exactly yAxis and stays there), so
	-- flat driving is untouched at any value of `GravityOnGround` -- the guard below means
	-- the velocity is not even written. That is the check that protects the feel the user
	-- approved on 2026-11-03.
	if s.airborne then
		vel -= Vector3.yAxis * (C.Gravity * dt)
		if vel.Y < -C.TerminalFall then
			vel = Vector3.new(vel.X, -C.TerminalFall, vel.Z)
		end
	elseif C.GravityOnGround > 0 then
		local g = Vector3.yAxis * -C.Gravity
		local along = g - up * g:Dot(up)
		if along.Magnitude > EPS then
			vel += along * (C.GravityOnGround * dt)
		end
	end

	---------------------------------------------------------------- the handbrake
	-- Drag against the whole velocity, and never more of it than there is. Only used to
	-- stop the car once a run is over.
	if handbrake then
		local speed = vel.Magnitude
		if speed > EPS then
			vel -= vel.Unit * math.min(C.HandbrakeDecel * dt, speed)
		end
	end

	local target = s.position + vel * dt

	---------------------------------------------------------------- walls
	-- Ours, not the reference's: it ends a run on a hard hit, and what a run is has not
	-- been decided. Here a hit stops the car at the surface and spends what is left of the
	-- step sliding along it.
	--
	-- THE CAR IS KINEMATIC, so a building is solid only because of these few lines, and
	-- they are written around one fact: a Blockcast whose box already overlaps a part does
	-- not report that part at all. A car a tenth of a stud inside a building is blind to
	-- it and drives out the far side, which is exactly what it used to do -- the old code
	-- took the sweep's CONTACT POINT for the car's new centre and so buried the car half
	-- its own length in the first wall it touched (T-018). Hence two passes: `sweep` keeps
	-- the car out, and `penetration` puts it back out if anything else has got it in.
	s.wallHit = false
	local targetY = target.Y
	if world.sweep then
		local at = s.position
		for _ = 1, MAX_SLIDES do
			local safe, hitNormal = world.sweep(at, target, s.yaw)
			if not safe or not hitNormal then
				break
			end
			local n = (hitNormal :: Vector3).Unit
			s.wallHit = true

			-- The speed a hit costs is in proportion to how much of it was INTO the
			-- surface: a ram keeps `WallScrub` of what is left, a graze keeps all of it. A
			-- flat scrub on every step a wall is touched brings a car driving along one to
			-- a standstill in a fifth of a second, which is a car glued to the wall.
			--
			-- AND IT IS SUSPENDED WHILE THE CAR IS PINNED (T-074), which is the second
			-- half of that change and the same statement as the first: withhold, never
			-- push. A car whose nose is well into a wall has its own drivetrain as the
			-- biggest thing pointing into it, so `-into/speed` is near 1 on EVERY step and
			-- the car keeps half of what little it has, 120 times a second. Measured with
			-- only the grip let go: at 60 degrees of nose the car still sat at 0.1 studs/s
			-- for ever, and the scrub was the whole of what held it. The wall is still a
			-- wall -- `vel -= n * into` is untouched, so the car is still stopped at the
			-- surface -- it simply stops being charged a crash a step for leaning on it.
			local into = vel:Dot(n)
			if into < 0 then
				local speed = vel.Magnitude
				vel -= n * into -- slide along it instead of stopping dead
				if speed > EPS and not s.pinned then
					vel *= lerp(1, C.WallScrub, clamp(-into / speed, 0, 1))
				end
			end

			-- What is left of the step after stopping, with the part of it that pointed
			-- into the surface taken out, spent along the surface instead.
			local leftover = (target - (safe :: Vector3))
			leftover = Vector3.new(leftover.X, 0, leftover.Z)
			local dig = leftover:Dot(n)
			if dig < 0 then
				leftover -= n * dig
			end
			at = safe :: Vector3
			target = Vector3.new(at.X + leftover.X, targetY, at.Z + leftover.Z)
			if leftover.Magnitude < EPS then
				break
			end
		end
	end

	-- Out of anything the car is in, however it got in: its own rotation pressed against a
	-- wall, a cone rolling into it, a respawn on top of something. Without this one
	-- hundredth of a stud of overlap makes the car permanently blind to what it is in.
	if world.penetration then
		local push, depth = world.penetration(target, s.yaw)
		if push and depth > 0 and (push :: Vector3).Magnitude > EPS then
			local out = (push :: Vector3).Unit
			target += out * (depth + C.WallPush)
			local into = vel:Dot(out)
			if into < 0 then
				vel -= out * into
			end
			s.wallHit = true
		end
	end

	-- HOW LONG SINCE A WALL (T-074), read at the top of the NEXT step. Time since, not time
	-- in: contact on the real road is one step in twelve even when the car is held hard
	-- against a barrier, so "how long since one" is the only honest question.
	if s.wallHit then
		s.sinceWall = 0
	else
		s.sinceWall += dt
	end

	---------------------------------------------------------------- the ground
	-- One ray per wheel. Their surfaces are averaged over all four, so two wheels off the
	-- road is half the grip, and a wheel over nothing counts as nothing.
	local halfBase = C.Wheelbase * 0.5
	local halfTrack = C.TrackWidth * 0.5
	local sumY, sumGrip, sumScore = 0, 0, 0
	local normal = Vector3.zero
	local found: { boolean } = table.create(#WHEELS, false)
	local wheelHits: { Hit? } = table.create(#WHEELS, nil)
	local highest = -math.huge
	for i, wheel in WHEELS do
		local at = target + fwd * (halfBase * wheel.front) + right * (halfTrack * wheel.side)
		local hit = world.probe(at)
		if hit then
			found[i] = true
			wheelHits[i] = hit
			highest = math.max(highest, hit.y)
			sumGrip += hit.grip
			sumScore += hit.score
		end
	end

	-- The car's HEIGHT and TILT come only from the wheels that are carrying it. A wheel
	-- whose ground is more than a ride height below the highest is hanging over a drop --
	-- it is lower than the car's own floor, so it cannot be holding the car up -- and
	-- averaging it in dropped the body into the edge the other wheels were still on:
	-- measured, four tenths of a stud of the car inside the ramp when it ran off the side
	-- of it (T-026). Grip and score still count all four, so what a slide does at an edge
	-- is unchanged.
	--
	-- On any surface the car can actually drive, all four are within this of each other:
	-- the ramp at its steepest spreads them 1.8 studs, the banked circle 0.8.
	local carrying = 0
	for i = 1, #WHEELS do
		local hit = wheelHits[i]
		if hit and highest - hit.y <= C.RideHeight then
			carrying += 1
			sumY += hit.y
			normal += hit.normal
		end
	end

	local groundY: number? = if carrying > 0 then sumY / carrying else nil
	normal = if normal.Magnitude > EPS then normal.Unit else Vector3.yAxis
	s.groundY = groundY
	-- THE ONE LINE A FALL IS MEASURED FROM. `groundY` goes nil the moment the car is over
	-- nothing, which is exactly when a fall is being decided, so the last height it had is
	-- kept: the ground the car drove off. The model needs to know nothing about the road,
	-- the track or the playground to use it, and on ground that is flat at Y = 0 it IS zero,
	-- so the old absolute test and this one catch a fall in the same place (T-067).
	if groundY then
		s.fallFrom = groundY
	end

	---------------------------------------------------------------- out of travel: the floor
	-- OURS (T-095, Drift/Suspension, features/car-v2.md). Everything above put the car on
	-- the wheels that carry it, level with their mean and tilted to their normals. That is
	-- the car the user approved, and on flat ground and every road it is the whole story:
	-- all four wheels are within their travel of that pose. THIS BLOCK ONLY RUNS WHEN ONE
	-- IS NOT -- its ground is further below it than a wheel can hang (`Rest` and
	-- `HangSlack`), or there is no ground under it at all -- or when it ran last step and the
	-- floor is still near something. Then the car is a rigid body on point supports: the
	-- wheels that touch and its floor, which goes down on to whatever edge it is over. A
	-- rear axle rolled off a ledge drops, the floor lands on the edge, and the car grinds
	-- across it until it is clear and falls.
	--
	-- AND ONLY SLOWER THAN `HangSpeed`. A car that is going somewhere is over the edge and
	-- gone long before it could tip on to its floor -- off the ramp's lip at 20 studs/s the
	-- front axle is out over the drop for half a second -- and the line it flies is the one
	-- the user drove, so the model above keeps it. Once the floor solve has started it keeps
	-- going, at any speed, until the floor is clear.
	local P = C.Suspension
	local hang = false
	if carrying > 0 and groundY and groundSpeed < P.HangSpeed then
		local y0 = groundY + C.RideHeight
		local f0, r0, u0 = Suspension.basis(s.yaw, normal)
		for i = 1, #WHEELS do
			local hit = wheelHits[i]
			if not hit then
				hang = true -- nothing under this wheel at all
				break
			end
			local p = Suspension.wheelContact(i)
			if hit.y < y0 + r0.Y * p.X + u0.Y * p.Y - f0.Y * p.Z - (P.Rest + P.HangSlack) then
				hang = true
				break
			end
		end
	end
	-- Once in, it stays in for as long as the floor is near something: a car whose four
	-- wheels have all gone over the drop can still have its nose over the ledge.
	-- And while it is in, a wheel is its whole tread, not the one ray under its middle: a
	-- tyre rolling over the edge rides round the corner (`Suspension.treads`).
	local contactHits: { Hit? } = wheelHits
	if hang or s.hanging then
		contactHits = Suspension.treads(world, s.yaw, target, s.up)
	end
	local sup = if hang or s.hanging then Suspension.gather(world, s.yaw, target, s.up, contactHits, s.floor) else nil
	if sup and not hang then
		local _, _, nearY = Suspension.need(sup, s.yaw, s.up)
		if sup.nHard == 0 or nearY < target.Y - C.AirborneMargin then
			sup = nil -- clear of everything: it falls, as it always has
		end
	end
	if sup and sup.n == 0 then
		sup = nil -- nothing under any of it: it falls, as it always has
	end
	s.hanging = sup ~= nil

	local follow = 1 - math.exp(-dt / math.max(C.GroundFollow, EPS))
	if sup then
		-- Where the car would come to rest on what is under it, and the tilt moving toward
		-- that no faster than gravity could start to turn it (`TipAccel`). In the air as on
		-- the ground: a car tipping off an edge keeps tipping as it goes.
		local a0, b0 = Suspension.tiltOf(s.yaw, s.up)
		local aR, bR = Suspension.rest(sup, s.yaw, a0, b0)
		local a, ra = Suspension.approach(a0, aR, s.tiltRate.X, dt)
		local b, rb = Suspension.approach(b0, bR, s.tiltRate.Y, dt)
		local upH = Suspension.upOf(s.yaw, a, b)
		s.tiltRate = Vector2.new(ra, rb)
		s.up = upH
		local restY = Suspension.need(sup, s.yaw, upH)
		if target.Y - restY <= C.AirborneMargin then
			s.airborne = false
			target = Vector3.new(target.X, lerp(target.Y, restY, follow), target.Z)
			-- The same rule as on a road: the vertical speed is what the car's own plane
			-- makes of its travel, and nothing else.
			local flatSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
			local climb = 0
			if upH.Y > GROUND_NORMAL_Y then
				climb = clamp(-(upH.X * vel.X + upH.Z * vel.Z) / upH.Y, -flatSpeed, flatSpeed)
			end
			vel = Vector3.new(vel.X, clamp(climb, -C.TopSpeed, C.TopSpeed), vel.Z)
		else
			s.airborne = true
			if target.Y < restY then
				target = Vector3.new(target.X, restY, target.Z)
				s.airborne = false
				vel = Vector3.new(vel.X, 0, vel.Z)
			end
		end
		-- The floor is HARD: whatever the height eased to, no floor point is below its
		-- ground. A wheel may be pushed up into its travel, and no further; the floor has none.
		local _, hardY = Suspension.need(sup, s.yaw, s.up)
		if target.Y < hardY then
			target = Vector3.new(target.X, hardY, target.Z)
			if vel.Y < 0 then
				vel = Vector3.new(vel.X, 0, vel.Z)
			end
			s.airborne = false
		end
	elseif groundY and target.Y - (groundY + C.RideHeight) <= C.AirborneMargin then
		s.tiltRate = Vector2.zero
		s.airborne = false
		-- The height eases on to the surface, and that easing is ALL it does. The car's
		-- vertical speed is the speed the SURFACE is climbing under it -- the velocity's
		-- own component in the plane of the ground -- so cresting a ramp still launches the
		-- car, at exactly the angle the ramp left it at, and nothing else can.
		--
		-- It used to be `(newY - position.Y) / dt`, the suspension catching up, and that
		-- made the follow an UNDAMPED SPRING: a step in the ground became a vertical speed
		-- of `follow / dt` -- 8 per second -- times the error, with the old `vel.Y` still in
		-- it. Two things fell out of that, and both are what the user drove into (T-026):
		-- every landing rang at 5 Hz for about a second, and any kerb the rays found above
		-- the car threw it. Measured, the banked circle's 8.35-stud rim took the car from 0
		-- to 141 studs/s upward in two steps and 144 studs into the air.
		target = Vector3.new(target.X, lerp(target.Y, groundY + C.RideHeight, follow), target.Z)
		--
		-- Bounded twice, and both bounds are the same statement: a car cannot climb faster
		-- than it is travelling. A ray that comes back with a near-horizontal normal has
		-- found a FACE, not a floor -- the half-stud slot the two rings of the bowl used to
		-- leave between them had one, and `-(n.xz . v) / n.y` through it is nine times the
		-- car's speed, straight up.
		local flatSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
		local climb = 0
		if normal.Y > GROUND_NORMAL_Y then
			climb = clamp(-(normal.X * vel.X + normal.Z * vel.Z) / normal.Y, -flatSpeed, flatSpeed)
		end
		vel = Vector3.new(vel.X, clamp(climb, -C.TopSpeed, C.TopSpeed), vel.Z)
		s.up = s.up:Lerp(normal, follow)
	else
		s.tiltRate = Vector2.zero
		s.airborne = true
		s.up = s.up:Lerp(Vector3.yAxis, 1 - math.exp(-dt / math.max(C.AirLevel, EPS)))
		if groundY and target.Y < groundY + C.RideHeight then
			target = Vector3.new(target.X, groundY + C.RideHeight, target.Z)
			s.airborne = false
			vel = Vector3.new(vel.X, 0, vel.Z)
		end
	end
	s.up = if s.up.Magnitude > EPS then s.up.Unit else Vector3.yAxis
	s.grounded = not s.airborne

	if sup then
		-- Resting on the floor, a wheel is down only if it really reaches its ground: the
		-- rear pair hanging off a ledge drives nothing and grips nothing.
		local f1, r1, u1 = Suspension.basis(s.yaw, s.up)
		sumGrip, sumScore = 0, 0
		for i = 1, #WHEELS do
			local hit = contactHits[i]
			local down = false
			if hit and s.grounded then
				local p = Suspension.wheelContact(i)
				local h = target.Y + r1.Y * p.X + u1.Y * p.Y - f1.Y * p.Z
				down = hit.y >= h - (P.Rest + P.HangSlack)
			end
			found[i] = down
			if down and hit then
				sumGrip += hit.grip
				sumScore += hit.score
			end
		end
		s.floorContacts = Suspension.contacts(sup, s.yaw, target, s.up, vel, s.r)
		s.floorTouching = #s.floorContacts
	elseif s.floorTouching > 0 then
		s.floorContacts = Suspension.EMPTY_CONTACTS
		s.floorTouching = 0
	end

	for i = 1, #WHEELS do
		found[i] = found[i] and s.grounded
	end
	s.wheelsDown = found
	s.rearDown = false
	for _, i in Model.REAR_WHEELS do
		s.rearDown = s.rearDown or found[i]
	end
	s.surfaceGrip = if s.grounded then sumGrip / #WHEELS else 0
	s.surfaceScore = if s.grounded then sumScore / #WHEELS else 0

	---------------------------------------------------------------- the readout
	s.velocity = vel
	s.position = target
	s.u = vel:Dot(fwd)
	s.v = vel:Dot(right)
	s.vy = vel.Y
	s.fell = target.Y < s.fallFrom - C.FallBelowSurface
	s.wheelSpin += (s.u / math.max(C.WheelDiameter * 0.5, EPS)) * dt
	s.time += dt

	-- Cosmetic, both of them, and neither is read by anything above. The body leans
	-- outward, away from the way it is sliding; the front wheels point along where the car
	-- is actually travelling, which is opposite lock the moment the tail is out.
	local rollTo = -math.rad(C.BodyRollMax) * clamp(s.v / math.max(C.BodyRollSpeed, EPS), -1, 1)
	s.bodyRoll = lerp(s.bodyRoll, rollTo, clamp(C.BodyRollRate * dt, 0, 1))
	local steerTo = clamp(b, -math.rad(C.WheelSteerMax), math.rad(C.WheelSteerMax))
	s.wheelSteer = lerp(s.wheelSteer, steerTo, clamp(C.WheelSteerRate * dt, 0, 1))

	-- Cosmetic too, and last: each wheel on its spring and the body's sprung offset, from the
	-- same four rays and the pose just settled (Drift/Suspension). Nothing above reads it.
	Suspension.step(s, if sup then contactHits else wheelHits, dt, vyBefore)

	return s
end

return Model
