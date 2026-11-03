--!strict
-- Model: the drift model itself, and nothing else.
--
-- A bicycle model (docs/game/features/drift-model.md "Rules and numbers"): one front
-- contact point and one rear contact point, each making a lateral force from its slip
-- angle, integrated by hand at a fixed step. It is pure maths plus two injected world
-- queries, so it runs with no player, no car and no Workspace: that is what makes
-- DebugDrive and the determinism test possible.
--
-- Frames. The car's own frame is the usual car one:
--   u  forward speed            (+ forwards)
--   v  lateral speed            (+ to the car's right)
--   r  yaw rate                 (+ turning right)
-- Roblox's Y rotation runs the other way, so `yaw` (the Roblox one) loses r each step.
--
-- Every number comes from Config.Drift. There are no constants in here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Model = {}

export type Input = {
	steer: number, -- -1 full left .. +1 full right
	drift: boolean,
	brake: boolean,
}

export type Hit = { y: number, normal: Vector3 }

-- The two queries the model makes of the world. Drift/World builds both, for the live
-- Workspace and for a flat plane.
export type World = {
	probe: (pos: Vector3) -> Hit?,
	sweep: ((from: Vector3, to: Vector3, yaw: number) -> (Vector3?, Vector3?))?,
}

export type State = {
	position: Vector3,
	yaw: number, -- radians, Roblox sense (+ turns left)
	u: number,
	v: number,
	r: number,
	vy: number, -- vertical speed
	steer: number, -- where the steering input has got to, -1 .. 1
	wheelAngle: number, -- where the front wheels really point, radians, counter-steer included
	wantedSlip: number, -- the slide angle the stick is asking for while drifting, radians
	gripBlend: number, -- 0 gripping .. 1 drifting
	airborne: boolean,
	up: Vector3, -- smoothed surface normal
	groundY: number?, -- last ground height found under the car
	wheelSpin: number, -- radians, for drawing only
	slip: number, -- body slip angle, radians
	slipFront: number,
	slipRear: number,
	muRear: number,
	grounded: boolean,
	wallHit: boolean,
	fell: boolean,
	phase: string, -- gripping | breaking | drifting | catching | airborne
	time: number, -- seconds of simulation since the state was made
	driftHeld: number, -- seconds the drift input has been held, -1 when it is not
	breakLoose: number?, -- seconds from the drift input going down to the rear letting go
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function toward(current: number, target: number, maxDelta: number): number
	local d = target - current
	if math.abs(d) <= maxDelta then
		return target
	end
	return current + (d > 0 and maxDelta or -maxDelta)
end

-- The car's forward and right vectors, from its Roblox yaw.
function Model.axes(yaw: number): (Vector3, Vector3)
	local s, c = math.sin(yaw), math.cos(yaw)
	return Vector3.new(-s, 0, -c), Vector3.new(c, 0, -s)
end

function Model.new(spawnCFrame: CFrame): State
	local _, yaw = spawnCFrame:ToEulerAnglesYXZ()
	return {
		position = spawnCFrame.Position,
		yaw = yaw,
		u = 0,
		v = 0,
		r = 0,
		vy = 0,
		steer = 0,
		wheelAngle = 0,
		wantedSlip = 0,
		gripBlend = 0,
		airborne = false,
		up = Vector3.yAxis,
		groundY = nil,
		wheelSpin = 0,
		slip = 0,
		slipFront = 0,
		slipRear = 0,
		muRear = Config.Drift.GripRear,
		grounded = false,
		wallHit = false,
		fell = false,
		phase = "gripping",
		time = 0,
		driftHeld = -1,
		breakLoose = nil,
	}
end

function Model.speed(s: State): number
	return math.sqrt(s.u * s.u + s.v * s.v)
end

-- The car's pose, built from its position, yaw and the surface it is following.
function Model.cframe(s: State): CFrame
	local fwd = Model.axes(s.yaw)
	local up = s.up
	if up.Magnitude < 1e-3 then
		up = Vector3.yAxis
	end
	up = up.Unit
	local right = fwd:Cross(up)
	if right.Magnitude < 1e-3 then
		return CFrame.new(s.position) * CFrame.Angles(0, s.yaw, 0)
	end
	return CFrame.fromMatrix(s.position, right.Unit, up)
end

-- One tyre. The force is an acceleration (per unit mass), positive to the car's right.
-- `slipVel` is how fast the contact point is sliding sideways across the tyre; the solver
-- guard caps the force at the share of that slide one step may cancel, which is what keeps
-- the stiff low-speed equations from exploding at FixedStep.
local function tyreForce(slipAngle: number, mu: number, slipVel: number, dt: number): number
	local C = Config.Drift
	local peak = math.rad(C.TyrePeakSlip)
	local force = mu * C.GripAccel * math.tanh(math.abs(slipAngle) / peak)
	local cap = math.abs(slipVel) * C.StepGuard / dt
	force = math.min(force, cap)
	return slipAngle >= 0 and -force or force
end

-- One fixed step. Mutates and returns `s`; the caller owns the state table.
function Model.step(s: State, input: Input, dt: number, world: World): State
	local C = Config.Drift

	local steerIn = clamp(input.steer or 0, -1, 1)
	local brake = input.brake == true
	local drift = input.drift == true

	---------------------------------------------------------------- the drift input
	local blendSeconds = drift and C.GripBlendIn or C.GripBlendOut
	s.gripBlend = toward(s.gripBlend, drift and 1 or 0, dt / math.max(blendSeconds, 1e-4))
	if drift then
		s.driftHeld = (s.driftHeld >= 0 and s.driftHeld or 0) + dt
	else
		s.driftHeld = -1
		s.breakLoose = nil
	end

	---------------------------------------------------------------- slip
	local a = C.Wheelbase * 0.5
	local b = C.Wheelbase * 0.5
	local uRef = math.max(s.u, C.MinSlipSpeed)
	local latFront = s.v + a * s.r
	local latRear = s.v - b * s.r
	local beta = math.atan2(s.v, uRef)

	---------------------------------------------------------------- steering
	-- Gripping, the stick is the steering wheel: it points the front wheels.
	--
	-- Drifting, it is not (features/drift-model.md "How it plays", item 5). A real slide is
	-- an unstable balance held by the driver's own counter-steer, several corrections a
	-- second; a thumb on a phone cannot do that and should not have to. So while the drift
	-- input is held the stick asks for a *slide angle* -- full lock is `DriftAngleMax` of
	-- slide, half lock is half of it, centred is straight -- and the front wheels servo
	-- toward it on their own. Hard into the corner to break the rear loose, the wheels
	-- unwinding as the angle builds, and a real counter-steer the moment the car goes past
	-- the angle asked for, all fall out of one line.
	--
	-- `gripBlend` crossfades the two, so the catch is the servo handing the wheels back.
	--
	-- The wheels move at a rate, not instantly, and that lag is not cosmetic: a servo with
	-- no delay is a loop with no phase margin, and the car hunts lock to lock instead of
	-- settling.
	s.steer = toward(s.steer, steerIn, C.SteerRate * dt)
	local speedFrac = clamp(math.abs(s.u) / C.TopSpeed, 0, 1)
	local maxAngle = math.rad(lerp(C.SteerAngleMax, C.SteerAngleMin, speedFrac))
	local lock = math.rad(C.SteerAngleMax)

	local gripAngle = steerIn * maxAngle
	-- A right-hand slide (steer positive) runs with the velocity to the left of the nose,
	-- which is a negative body slip angle: hence the minus.
	local wantedSlip = -steerIn * math.rad(C.DriftAngleMax)
	s.wantedSlip = wantedSlip

	-- Point the front wheels where the front axle is really travelling, then nudge them by
	-- how far the slide is from the angle asked for. That one line is the whole of it:
	--   no slide yet, so the nudge is the whole angle and the wheels turn in hard;
	--   slide holding, so the nudge is nothing and the wheels sit along the travel, making
	--     no force either way -- which is exactly what a driver counter-steers *for*;
	--   slide gone too far, so the nudge goes the other way and the wheels catch it.
	-- Aiming at a fixed angle instead leaves the front tyre making a large force at a
	-- 30-degree attitude, and that force spins the car: measured, not guessed.
	local frontTravel = math.atan2(latFront, uRef)
	local driftAngle = frontTravel + C.CounterSteer * (beta - wantedSlip)

	local wanted = clamp(lerp(gripAngle, driftAngle, s.gripBlend), -lock, lock)
	s.wheelAngle = toward(s.wheelAngle, wanted, C.SteerRate * lock * dt)
	local delta = s.wheelAngle

	local slipFront = math.atan2(latFront, uRef) - delta
	local slipRear = math.atan2(latRear, uRef)

	s.slip = beta
	s.slipFront = slipFront
	s.slipRear = slipRear

	if s.driftHeld >= 0 and s.breakLoose == nil and math.abs(beta) >= math.rad(C.BreakLooseSlip) then
		s.breakLoose = s.driftHeld
	end

	---------------------------------------------------------------- tyres
	local muRear = lerp(C.GripRear, C.GripRearDrift, s.gripBlend)
	s.muRear = muRear

	local forceFront, forceRear = 0, 0
	if not s.airborne then
		forceFront = tyreForce(slipFront, C.GripFront, latFront - uRef * math.tan(delta), dt)
		forceRear = tyreForce(slipRear, muRear, latRear, dt)
	end

	---------------------------------------------------------------- yaw
	local rdot
	if s.airborne then
		-- Airborne, steering only rotates the car in yaw; nothing else touches it.
		local wanted = C.AirYawRate * s.steer
		rdot = (wanted - s.r) / math.max(C.AirYawTime, 1e-3)
	else
		rdot = (a * forceFront * math.cos(delta) - b * forceRear) / C.YawInertia
		rdot -= C.YawDamping * s.r
		-- The slide itself (features/drift-model.md "How it plays", item 4).
		--
		-- Two tyres at saturation hold whatever angle the car is already at and pick none
		-- of their own: with a tanh tyre the body's slip angle is a free mode at steady
		-- state, so no amount of grip tuning produces a slide by itself. The drift input
		-- has to drive it, and this is the one place the model is frankly an arcade one.
		--
		-- It drives the *yaw rate*, not the moment. The slip angle only moves when the nose
		-- turns faster than the velocity does, and the velocity turns at (lateral force /
		-- speed): so the yaw rate that holds the slide where it is is known exactly, and
		-- anything above it opens the slide further. Asking for that rate plus the error,
		-- over `DriftAngleTime`, is a loop that closes -- a moment proportional to the
		-- error alone leaves the car permanently short of the angle the stick asked for,
		-- by more the harder the tyres fight it.
		local lateral = forceFront * math.cos(delta) + forceRear
		local speed = math.max(math.sqrt(s.u * s.u + s.v * s.v), C.MinSlipSpeed)
		local holdRate = lateral / speed
		local openRate = (beta - wantedSlip) / math.max(C.DriftAngleTime, 1e-3)
		rdot += C.DriftYawAssist
			* s.gripBlend
			* (holdRate + openRate - s.r)
			* clamp(math.abs(s.u) / C.AssistSpeed, 0, 1)
		local betaMax = math.rad(C.SlipAngleMax)
		if math.abs(beta) > betaMax then
			-- Spinning out: the car straightens itself rather than carrying on round.
			rdot += C.SpinRecover * (math.abs(beta) - betaMax) * (beta >= 0 and 1 or -1)
		end
	end

	---------------------------------------------------------------- the rotating frame
	-- u and v are measured along axes that turn at `r`, so a velocity that is not changing
	-- in the world still moves between them. Both halves of that have to be here: with only
	-- the `-u*r` the car's velocity is dragged round with its nose, which pumps speed in
	-- until the model runs away. They also give the airborne case for free: with no tyre
	-- force, these two alone hold the world velocity still while the body yaws.
	local udot = s.v * s.r
	local vdot = -s.u * s.r

	---------------------------------------------------------------- the tyre forces
	-- The front tyre's force is square to the *wheel*, not to the body, so at a steering
	-- angle it has a backwards component as well as a sideways one. That component is
	-- cornering drag, and leaving it out is not a small error: without it the steered
	-- wheel does positive work on the car and a long corner accelerates past top speed.
	if not s.airborne then
		vdot += forceFront * math.cos(delta) + forceRear
		udot -= forceFront * math.sin(delta)
	end

	---------------------------------------------------------------- longitudinal
	if not s.airborne then
		if brake then
			if s.u > 0.5 then
				udot -= C.BrakeDecel
			else
				udot -= C.ReverseAccel * clamp(1 + s.u / C.ReverseSpeed, 0, 1)
			end
		elseif C.AutoThrottle then
			udot += C.Accel * clamp(1 - s.u / C.TopSpeed, 0, 1)
			if s.u < 0 then
				udot += C.CoastDecel
			end
		else
			udot -= C.CoastDecel * (s.u > 0 and 1 or (s.u < 0 and -1 or 0))
		end
		-- The slide itself bleeds speed: that is what makes a corner a drift, not a brake.
		local bleed = C.SlipSpeedBleed * math.deg(math.abs(beta)) * clamp(math.abs(s.u) / C.MinSlipSpeed, 0, 1)
		udot -= bleed * (s.u >= 0 and 1 or -1)
	end

	---------------------------------------------------------------- integrate
	s.u += udot * dt
	s.v += vdot * dt
	s.r = clamp(s.r + rdot * dt, -C.YawRateMax, C.YawRateMax)
	s.yaw -= s.r * dt -- Roblox yaw runs the other way to r

	-- A ceiling on the whole velocity, not on u alone: a slide puts speed into v, and a cap
	-- that held only u would let the total run away. A guard, not a feel knob: the throttle
	-- and the slip bleed are what set the speed a player actually sees.
	local planarSpeed = math.sqrt(s.u * s.u + s.v * s.v)
	local ceiling = C.TopSpeed * C.SpeedCeiling
	if planarSpeed > ceiling then
		local k = ceiling / planarSpeed
		s.u *= k
		s.v *= k
	end
	s.u = math.max(s.u, -C.ReverseSpeed)

	local fwd, right = Model.axes(s.yaw)
	local planar = fwd * s.u + right * s.v

	if s.airborne then
		s.vy -= C.Gravity * dt
	end

	local target = s.position + planar * dt + Vector3.yAxis * (s.vy * dt)

	---------------------------------------------------------------- walls
	s.wallHit = false
	if world.sweep then
		local hitPos, hitNormal = world.sweep(s.position, target, s.yaw)
		if hitPos and hitNormal then
			local n = Vector3.new(hitNormal.X, 0, hitNormal.Z)
			if n.Magnitude > 1e-3 then
				n = n.Unit
				local into = planar:Dot(n)
				if into < 0 then
					planar -= n * into -- slide along the surface instead of stopping dead
				end
				planar *= C.WallScrub
				s.u = planar:Dot(fwd)
				s.v = planar:Dot(right) * (1 - C.WallStraighten)
				s.r *= 1 - C.WallStraighten
				target = Vector3.new(hitPos.X, target.Y, hitPos.Z) + n * C.WallPush
				s.wallHit = true
			end
		end
	end

	---------------------------------------------------------------- ground
	local frontHit = world.probe(target + fwd * a)
	local rearHit = world.probe(target - fwd * b)

	local groundY: number? = nil
	local normal = Vector3.yAxis
	if frontHit and rearHit then
		groundY = (frontHit.y + rearHit.y) * 0.5
		local sum = frontHit.normal + rearHit.normal
		normal = sum.Magnitude > 1e-3 and sum.Unit or Vector3.yAxis
	elseif frontHit then
		groundY, normal = frontHit.y, frontHit.normal
	elseif rearHit then
		groundY, normal = rearHit.y, rearHit.normal
	end
	s.groundY = groundY

	local follow = 1 - math.exp(-dt / math.max(C.GroundFollow, 1e-4))
	if groundY then
		local desiredY = groundY + C.RideHeight
		if target.Y - desiredY > C.AirborneMargin then
			s.airborne = true
		else
			if s.airborne then
				s.vy = 0 -- landing
			end
			s.airborne = false
			local newY = lerp(target.Y, desiredY, follow)
			-- Vertical speed comes from the ground itself, so cresting a ramp launches the car.
			s.vy = clamp((newY - s.position.Y) / dt, -C.TopSpeed, C.TopSpeed)
			target = Vector3.new(target.X, newY, target.Z)
			s.up = s.up:Lerp(normal, follow)
		end
	else
		s.airborne = true
	end

	if s.airborne then
		s.up = s.up:Lerp(Vector3.yAxis, 1 - math.exp(-dt / math.max(C.AirLevel, 1e-4)))
		if groundY and target.Y < groundY + C.RideHeight then
			target = Vector3.new(target.X, groundY + C.RideHeight, target.Z)
			s.airborne = false
			s.vy = 0
		end
	end
	s.up = s.up.Magnitude > 1e-3 and s.up.Unit or Vector3.yAxis

	s.grounded = not s.airborne
	s.position = target
	s.fell = target.Y < C.RespawnBelowY
	s.wheelSpin += (s.u / math.max(C.WheelDiameter * 0.5, 0.1)) * dt
	s.time += dt

	---------------------------------------------------------------- readout
	if s.airborne then
		s.phase = "airborne"
	elseif s.gripBlend >= 0.95 then
		s.phase = "drifting"
	elseif drift then
		s.phase = "breaking"
	elseif s.gripBlend > 0.02 then
		s.phase = "catching"
	else
		s.phase = "gripping"
	end

	return s
end

return Model
