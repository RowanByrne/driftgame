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
--   5. Downforce, then our own gravity (Config.Drift.Gravity, not Roblox's).
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

local Model = {}

local EPS = 1e-4

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

-- The two queries the model makes of the world. Drift/World builds both, for the live
-- Workspace and for a flat plane.
export type World = {
	probe: (pos: Vector3) -> Hit?,
	sweep: ((from: Vector3, to: Vector3, yaw: number) -> (Vector3?, Vector3?))?,
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
	groundY: number?, -- last ground height found under the car
	bodyRoll: number, -- radians of cosmetic lean, about the car's own forward axis
	wheelSteer: number, -- radians the front wheels are DRAWN at. Cosmetic: they follow
	-- the travel, which is opposite lock for free
	wheelSpin: number, -- radians, for drawing only
	wallHit: boolean,
	fell: boolean,
	time: number, -- seconds of simulation since the state was made
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
		bodyRoll = 0,
		wheelSteer = 0,
		wheelSpin = 0,
		wallHit = false,
		fell = false,
		time = 0,
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
	if s.grounded and s.surfaceGrip > 0 then
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
	-- Our own gravity, not Roblox's, and only while the car is off the ground: on it, the
	-- height and the vertical speed both come from the surface below.
	if s.airborne then
		vel -= Vector3.yAxis * (C.Gravity * dt)
		if vel.Y < -C.TerminalFall then
			vel = Vector3.new(vel.X, -C.TerminalFall, vel.Z)
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
	-- been decided. Here a hit slides the car along the surface and scrubs its speed.
	s.wallHit = false
	if world.sweep then
		local hitPos, hitNormal = world.sweep(s.position, target, s.yaw)
		if hitPos and hitNormal then
			local n = Vector3.new(hitNormal.X, 0, hitNormal.Z)
			if n.Magnitude > EPS then
				n = n.Unit
				local into = vel:Dot(n)
				if into < 0 then
					vel -= n * into -- slide along it instead of stopping dead
				end
				vel *= C.WallScrub
				target = Vector3.new(hitPos.X, target.Y, hitPos.Z) + n * C.WallPush
				s.wallHit = true
			end
		end
	end

	---------------------------------------------------------------- the ground
	-- One ray per wheel. Their surfaces are averaged over all four, so two wheels off the
	-- road is half the grip, and a wheel over nothing counts as nothing.
	local halfBase = C.Wheelbase * 0.5
	local halfTrack = C.TrackWidth * 0.5
	local hits = 0
	local sumY, sumGrip, sumScore = 0, 0, 0
	local normal = Vector3.zero
	local found: { boolean } = table.create(#WHEELS, false)
	for i, wheel in WHEELS do
		local at = target + fwd * (halfBase * wheel.front) + right * (halfTrack * wheel.side)
		local hit = world.probe(at)
		if hit then
			found[i] = true
			hits += 1
			sumY += hit.y
			sumGrip += hit.grip
			sumScore += hit.score
			normal += hit.normal
		end
	end

	local groundY: number? = if hits > 0 then sumY / hits else nil
	normal = if normal.Magnitude > EPS then normal.Unit else Vector3.yAxis
	s.groundY = groundY

	local follow = 1 - math.exp(-dt / math.max(C.GroundFollow, EPS))
	if groundY and target.Y - (groundY + C.RideHeight) <= C.AirborneMargin then
		s.airborne = false
		local newY = lerp(target.Y, groundY + C.RideHeight, follow)
		-- The vertical speed comes from the ground itself, so cresting a ramp launches the
		-- car rather than pinning it to the far side.
		vel = Vector3.new(vel.X, clamp((newY - s.position.Y) / dt, -C.TopSpeed, C.TopSpeed), vel.Z)
		target = Vector3.new(target.X, newY, target.Z)
		s.up = s.up:Lerp(normal, follow)
	else
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
	s.fell = target.Y < C.RespawnBelowY
	s.wheelSpin += (s.u / math.max(C.WheelDiameter * 0.5, EPS)) * dt
	s.time += dt

	-- Cosmetic, both of them, and neither is read by anything above. The body leans
	-- outward, away from the way it is sliding; the front wheels point along where the car
	-- is actually travelling, which is opposite lock the moment the tail is out.
	local rollTo = -math.rad(C.BodyRollMax) * clamp(s.v / math.max(C.BodyRollSpeed, EPS), -1, 1)
	s.bodyRoll = lerp(s.bodyRoll, rollTo, clamp(C.BodyRollRate * dt, 0, 1))
	local steerTo = clamp(b, -math.rad(C.WheelSteerMax), math.rad(C.WheelSteerMax))
	s.wheelSteer = lerp(s.wheelSteer, steerTo, clamp(C.WheelSteerRate * dt, 0, 1))

	return s
end

return Model
