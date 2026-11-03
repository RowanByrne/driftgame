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
-- The body slip angle beta = atan2(v, u) is the one number to keep straight here, because
-- everything the player feels is a function of it:
--   beta > 0  the velocity runs out to the car's RIGHT of its nose, which is the tail
--             hung out to the right, which is a car arcing LEFT.
--   beta < 0  the mirror of that.
-- A positive yaw rate r turns the car right, and turning right closes a positive beta, so
-- anything that opens the slide to the right is a NEGATIVE rdot. That one sentence is
-- behind every sign in the slide section.
--
-- Every number comes from Config.Drift. There are no constants in here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Model = {}

export type Input = {
	-- NOT a steering wheel. The finger is on the car's REAR: this is how hard, and which
	-- way, the car's weight is thrown across (features/drift-model.md "How it plays").
	-- +1 throws the tail fully to the car's right, which arcs the car left.
	steer: number, -- -1 .. +1
	drift: boolean, -- a discrete press (keyboard, gamepad, a flick): worth `DriftOffset`
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
	steer: number, -- what the finger is asking for this step, -1 .. 1 (see Input.steer)
	load: number, -- where the car's weight has actually got to, -1 .. 1. Lags `steer`
	wheelAngle: number, -- where the front wheels really point, radians, counter-steer included
	slideFrac: number, -- 0 straight .. 1 as sideways as the car gets (`SlideAngleFull`)
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
		load = 0,
		wheelAngle = 0,
		slideFrac = 0,
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

	---------------------------------------------------------------- the finger
	-- The finger is on the car's rear, and its offset is not an angle to point at: it is
	-- how hard the car's weight is thrown across (features/drift-model.md "How it plays").
	-- There is no drift mode to be in and out of -- a small offset is a small slide, a big
	-- one is a big slide, and the whole range is one continuous thing.
	local command = steerIn
	if drift and command ~= 0 then
		-- A keyboard, a gamepad and a flick have no analogue travel. A press is worth the
		-- offset at which a finger breaks the rear loose, so the discrete inputs land
		-- inside the same scale instead of beside it.
		command = (command > 0 and 1 or -1) * math.max(math.abs(command), C.DriftOffset)
	end
	-- The finger's travel and the car's range are not the same thing. A car left to its
	-- own tyres is nearly all-or-nothing -- stuck, then gone -- so a straight mapping
	-- spends the first half of a thumb's reach doing almost nothing. `SlideCurve` below 1
	-- gives the near half of the travel something to say.
	if command ~= 0 and C.SlideCurve ~= 1 then
		command = (command > 0 and 1 or -1) * math.abs(command) ^ C.SlideCurve
	end
	s.steer = command

	-- Weight has mass. It takes time to arrive and time to settle, and that lag is the
	-- whole difference between a car and a cursor: with no lag the car answers the finger
	-- on the same frame, which is what reads as steering rather than as weight. Thrown out
	-- is quicker than gathered back in, because that is how a car behaves.
	local throwing = math.abs(command) > math.abs(s.load)
	local weightRate = throwing and C.WeightThrowRate or C.WeightSettleRate
	s.load = toward(s.load, command, weightRate * dt)
	local loadMag = math.abs(s.load)

	-- The rear lets go in proportion to the weight taken off it, over the blend times: the
	-- short one going out, the long one coming back, which is the catch.
	local blendSeconds = loadMag > s.gripBlend and C.GripBlendIn or C.GripBlendOut
	s.gripBlend = toward(s.gripBlend, loadMag, dt / math.max(blendSeconds, 1e-4))

	if math.abs(command) >= C.SlideHeldAt then
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
	local speed = math.sqrt(s.u * s.u + s.v * s.v)

	-- The body slip angle, off the real velocity rather than off `uRef`. The tyres keep the
	-- `MinSlipSpeed` floor, which stops their stiff equations dividing by a standstill; the
	-- slide must not have it, for two reasons. A floor on `u` caps the angle at 90 degrees,
	-- so a car that has gone right round reads as merely sideways and the spin guard below
	-- never sees it. And it caps it well under 90 exactly when the car is slowest and most
	-- sideways -- the one moment the scrub needs the truth.
	--
	-- `SlideSpeedFloor` fades the whole angle out under a crawl instead, by walking the
	-- velocity back to straight ahead: a car barely moving has no slide worth the name,
	-- which is also what lets one stopped sideways let go of it and drive off again.
	local crawl = clamp(speed / math.max(C.SlideSpeedFloor, 1e-3), 0, 1)
	local beta = math.atan2(s.v * crawl, s.u * crawl + (1 - crawl) * C.SlideSpeedFloor)
	local slideFrac = clamp(math.abs(beta) / math.rad(C.SlideAngleFull), 0, 1)
	s.slideFrac = slideFrac

	---------------------------------------------------------------- steering
	-- Nobody steers this car. The finger is on the rear, so the front wheels are the
	-- driver's hands, and they do what a driver's hands do in a slide: follow where the
	-- front axle is actually going.
	--
	-- That one line is the whole of it. Straight, the travel is straight ahead and the
	-- wheels sit straight. Turning in, the front axle is tracking round the corner and the
	-- wheels follow it into the corner. Properly sideways, the travel is already across the
	-- nose, so following it IS counter-steer -- opposite lock, the right amount of it, for
	-- free. On the travel the front tyre makes no force either way, which is exactly what
	-- a driver counter-steers *for*; `CounterSteer` moves the hands off it in either
	-- direction, and measured, zero was the best of them (Config.Drift).
	--
	-- The wheels move at a rate, not instantly: a servo with no delay is a loop with no
	-- phase margin, and the car hunts lock to lock instead of settling.
	local speedFrac = clamp(math.abs(s.u) / C.TopSpeed, 0, 1)
	local maxAngle = math.rad(lerp(C.SteerAngleMax, C.SteerAngleMin, speedFrac))
	local lock = math.rad(C.SteerAngleMax)

	local frontTravel = math.atan2(latFront, uRef)
	local slideSteer = frontTravel + C.CounterSteer * beta
	-- At a crawl there is no travel to follow, and a car that cannot be pointed at all
	-- below walking pace is a car that cannot be parked. So the wheels take the weight
	-- directly down there -- opposite to it, because the tail goes one way and the nose
	-- the other, which keeps the finger meaning the same thing at every speed.
	local crawlSteer = -s.load * maxAngle
	local steerAuthority = clamp(speed / math.max(C.CrawlSpeed, 1e-3), 0, 1)

	local wanted = clamp(lerp(crawlSteer, slideSteer, steerAuthority), -lock, lock)
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
		-- Airborne, the finger only rotates the car in yaw; nothing else touches it. The
		-- minus keeps it meaning the same thing as on the ground: weight right, tail right,
		-- nose left.
		local wantedRate = -C.AirYawRate * s.load
		rdot = (wantedRate - s.r) / math.max(C.AirYawTime, 1e-3)
	else
		rdot = (a * forceFront * math.cos(delta) - b * forceRear) / C.YawInertia
		rdot -= C.YawDamping * s.r
		-- The slide itself: a shove and a fight, never a pose
		-- (features/drift-model.md "How it plays", item 4).
		--
		-- Two tyres at saturation hold whatever angle the car is already at and pick none
		-- of their own, so the slide has to be driven and this is the one place the model
		-- is frankly an arcade one. What it drives is a MOMENT, not a yaw rate: the thrown
		-- weight shoves the tail round at `SlideKick`, and the car's own grip hauls it back
		-- at `SlideBite`, harder the further out it is. The angle the player gets is where
		-- the two cancel. Nothing anywhere names an angle.
		--
		-- That is the whole of the rebuild. Driving the yaw *rate* -- the previous version,
		-- at the rate that held a commanded angle plus the error over a settling time --
		-- cancels the car's own dynamics on the way: the slide arrives at the number asked
		-- for, smoothly, from any speed, and nothing fights. A moment leaves the inertia,
		-- the damping and both tyres in the loop, so the car leans in, overshoots, sags
		-- when the tyres bite, and snaps home when the finger does.
		--
		-- `SlideBiteShape` is how the fight grows with the angle, and the reason it has to
		-- grow at all: the rear tyre's own pull is nearly flat in the slide angle once it
		-- is sliding -- a saturated tyre makes the same force at 20 degrees as at 60 -- so
		-- left to the tyres alone the car has two states, stuck and gone, and nothing in
		-- between for the middle of the finger's travel to live in.
		local slideAuthority = clamp(speed / math.max(C.SlideKickSpeed, 1e-3), 0, 1)
		local kick = C.SlideKick * s.load * slideAuthority
		local bite = C.SlideBite * slideFrac ^ C.SlideBiteShape * (beta >= 0 and 1 or -1) * slideAuthority
		rdot += bite - kick
		local betaMax = math.rad(C.SlipAngleMax)
		if math.abs(beta) > betaMax then
			-- Past square across the car is going round, not drifting, and nothing the
			-- player can do reaches it. A wall, not a feel knob: it has to be stiff enough
			-- that a full offset pins the car sideways instead of spinning it through.
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
			if s.u > C.BrakeToReverse then
				udot -= C.BrakeDecel
			else
				udot -= C.ReverseAccel * clamp(1 + s.u / C.ReverseSpeed, 0, 1)
			end
		elseif C.AutoThrottle then
			-- The throttle is cut by the weight, not by the angle. Thrown across, the car
			-- has nothing left on its driven wheels, and at a full offset it has nothing at
			-- all -- which is what makes "100% to the side, held" a dead stop rather than a
			-- fast donut, and makes it one the car cannot drive its way out of. Hanging it
			-- on the finger rather than on the slide matters: a car that spins back toward
			-- straight would otherwise get its engine back halfway through being stopped,
			-- and pull away again while the player is still holding the brake.
			local cut = 1 - loadMag ^ C.DriveCutShape
			udot += C.Accel * clamp(1 - s.u / C.TopSpeed, 0, 1) * cut
			if s.u < 0 then
				udot += C.CoastDecel
			end
		else
			udot -= C.CoastDecel * (s.u > 0 and 1 or (s.u < 0 and -1 or 0))
		end
		-- What a slide costs. Drifting makes friction, and the harder the drift the more
		-- friction and the more speed it takes off -- the whole trade the game is made of
		-- (features/drift-model.md "How it plays"). `SlideDragPower` is the shape of that
		-- trade: above 1, a shallow drift is nearly free and a big one is ruinous.
		--
		-- It acts along the car's TRAVEL, not along its nose. A car 70 degrees across is
		-- scrubbing almost entirely sideways, and taking the cost off `u` alone would
		-- leave the speed sitting in `v` where the player can still feel it.
		local scrub = C.SlideDrag * slideFrac ^ C.SlideDragPower
		-- The same solver guard the tyres use: never cancel more of the velocity in one
		-- step than there is, or a car at walking pace jitters about zero.
		scrub = math.min(scrub, speed * C.StepGuard / dt)
		if speed > 1e-3 then
			udot -= scrub * (s.u / speed)
			vdot -= scrub * (s.v / speed)
		end
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
		s.vy = math.max(s.vy - C.Gravity * dt, -C.TerminalFall)
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
	-- The phase is read off the slide the car is actually in, not off the input, because
	-- with a continuous finger there is no mode to be in: `PhaseDriftingAt` is a share of
	-- `SlideAngleFull`, so the readout says drifting when the car is.
	if s.airborne then
		s.phase = "airborne"
	elseif s.slideFrac >= C.PhaseDriftingAt then
		s.phase = "drifting"
	elseif loadMag > s.gripBlend and loadMag > C.PhaseCatchingAt then
		s.phase = "breaking"
	elseif s.gripBlend > C.PhaseCatchingAt or s.slideFrac > C.PhaseCatchingAt then
		s.phase = "catching"
	else
		s.phase = "gripping"
	end

	return s
end

return Model
