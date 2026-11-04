--!strict
-- Wheels: the tyre marks and the smoke, per wheel, per surface
-- (docs/game/features/car-fx.md "Tyre marks and smoke").
--
-- A port of the reference game's wheel effects, written from a description of how they
-- work. Each wheel owns a `Trail` and a `ParticleEmitter` per surface, and every frame it
-- asks four questions of the drift model's own state:
--
--   1. IS THIS WHEEL ON A SURFACE AT ALL?  `s.wheelsDown[i]`, and not airborne. A wheel in
--      the air has no surface, so it marks nothing -- which is the whole of the airborne
--      rule.
--   2. IS THE SLIP ANGLE PAST THIS WHEEL'S THRESHOLD?  THE FRONTS AND THE REARS HAVE
--      DIFFERENT THRESHOLDS, AND THAT IS THE DETAIL THAT SELLS IT. The front wheels are
--      DRAWN pointing along the travel (`Drift/Render`: the model has no steering angle,
--      so the drawn angle is read off the slip angle), so a front tyre is not sliding
--      until the slip exceeds that drawn angle. The fronts' threshold is
--      `slip - MaxSteerDegrees`; the rears' is zero. The rears mark first and alone
--      through a small slide, and the fronts join in once it is a big one.
--   3. IS THE THROTTLE PAST `Gates.MinThrottle`?  A car coasting sideways does not light
--      up the road.
--   4. OR IS THE HANDBRAKE DOWN, above `Gates.MinHandbrakeSpeed`?  The handbrake marks
--      and smokes on its own, throttle or no throttle, slip or no slip.
--
-- Smoke's emission rate is lerped from `Smoke.RateMin` to `Smoke.RateMax` by
-- `slip / Gates.MaxSlipDegrees`, so a big angle is a big cloud.
--
-- NOTHING IS CREATED OR DESTROYED WHILE DRIVING. Sixteen instances per car -- 4 wheels x
-- (1 Trail + 1 ParticleEmitter + 2 Attachments) -- built once when the rig is caught and
-- switched with `Enabled` for ever after. There is no `Instance.new`, no table and no
-- `NumberSequence` anywhere in `Update`: a frame that allocates is the thing to fail on,
-- and `FxTests` counts the instances before and after a thousand frames because of it.
--
-- WHERE THE EFFECTS HANG, and why it is not the wheel part. `Drift/Render` spins each
-- wheel about its own axle (`CFrame.Angles(wheelSpin, 0, 0)`), so an attachment parented
-- to a wheel and offset down to the road would ORBIT the axle and draw a circle instead of
-- a line. Everything here therefore hangs off the car's `Body`, which never spins, at the
-- four contact patches read out of the rig's own wheel offsets. The body does LEAN
-- (`s.bodyRoll`, a couple of degrees at most, about the centre of mass), which moves a
-- contact patch by hundredths of a stud -- smaller than the mark is wide, and the honest
-- place for it anyway, since the body leaning is the car's weight moving.
--
-- `Drift/Render` is not touched by any of this and does not know this module exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)

local Wheels = {}
Wheels.__index = Wheels

-- One surface's pair of instances on one wheel. `on` and `rate` are what was last WRITTEN
-- to the instances, so a frame that changes nothing writes nothing.
type SurfaceFx = {
	surface: string,
	trail: Trail,
	emitter: ParticleEmitter,
	on: boolean,
	rate: number,
}

type WheelFx = {
	name: string,
	index: number, -- into `state.wheelsDown`: FL, FR, RL, RR
	front: boolean,
	a: Attachment,
	b: Attachment,
	fx: { SurfaceFx },
}

export type Wheels = typeof(setmetatable(
	{} :: {
		body: BasePart?,
		wheels: { WheelFx },
		enabled: boolean,
		built: number, -- instances this object made for the body it holds
	},
	Wheels
))

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--------------------------------------------------------------------------------
-- The gates, pure
--------------------------------------------------------------------------------

-- Everything one wheel needs to decide, with no instance in sight, so the thresholds can
-- be tested without a car, a place or a playtest (`Tests/FxTests`).
--
-- Returns, in order: whether this wheel emits at all, the smoke rate it would emit at,
-- and the three gates that decided it. MULTIPLE RETURNS AND NOT A TABLE: this is called
-- four times a frame and a table would be four allocations a frame.
--
-- `down` is this wheel's own `state.wheelsDown` entry. `front` picks the threshold.
function Wheels.evaluate(
	state: DriftModel.State,
	handbrake: boolean,
	front: boolean,
	down: boolean
): (boolean, number, boolean, boolean, boolean)
	local F = Config.Fx
	local slip = math.abs(state.slip)

	-- Gate 2. The fronts are drawn pointing along the travel, so they are not sliding
	-- until the slip angle is past that drawn angle; the rears have no such head start.
	local threshold = if front then math.rad(F.Gates.MaxSteerDegrees) else 0
	local slipPast = (slip - threshold) > math.rad(F.Gates.MinSlipDegrees)

	-- Gate 3, and gate 4 beside it. The handbrake is an OR over the whole thing, not just
	-- over the throttle: it marks and smokes on a car going dead straight.
	local throttleOk = state.throttle >= F.Gates.MinThrottle
	local handbrakeOk = handbrake and DriftModel.speed(state) >= F.Gates.MinHandbrakeSpeed

	-- Gate 1 is the caller's `down`, and the airborne check that goes with it.
	local onGround = down and not state.airborne
	local emit = onGround and ((slipPast and throttleOk) or handbrakeOk)

	local t = math.clamp(slip / math.rad(F.Gates.MaxSlipDegrees), 0, 1)
	return emit, lerp(F.Smoke.RateMin, F.Smoke.RateMax, t), slipPast, throttleOk, handbrakeOk
end

-- Which surface a wheel is standing on. THE ONE GAP IN THE PORT, and a small one:
-- `Drift/World`'s `Hit` carries a grip multiplier and not a surface name, and
-- `state.surfaceGrip` is the MEAN of four wheels' grip -- so there is no per-wheel surface
-- to read. The game has exactly one surface, so every wheel on the ground is told
-- `Config.Fx.Default` and the per-surface table below is built and fed from that one
-- value. The day `dirt` is laid, `Hit` grows a name, this reads it, and nothing else here
-- changes (features/car-fx.md "What our model already publishes").
function Wheels.surfaceOf(state: DriftModel.State, _index: number, down: boolean): string?
	if not down or state.airborne then
		return nil
	end
	return Config.Fx.Default
end

--------------------------------------------------------------------------------
-- The rig
--------------------------------------------------------------------------------

function Wheels.new(): Wheels
	return setmetatable({
		body = nil,
		wheels = {},
		enabled = true,
		built = 0,
	}, Wheels) :: any
end

local function wheelIndex(name: string): number?
	for i, n in CarModel.WHEEL_NAMES do
		if n == name then
			return i
		end
	end
	return nil
end

local function makeTrail(name: string, surface: string, a: Attachment, b: Attachment): Trail
	local F = Config.Fx
	local look = F.Surfaces[surface] or F.Surfaces[F.Default]
	local trail = Instance.new("Trail")
	trail.Name = string.format(F.Names.Trail, name, surface)
	trail.Attachment0 = a
	trail.Attachment1 = b
	trail.Lifetime = F.Marks.Seconds
	trail.Color = ColorSequence.new(look.MarkColour)
	-- Flat to begin with, then the last of its life spent fading out -- which is what
	-- stops a mark ending in a hard edge the moment its lifetime is up.
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, F.Marks.Transparency),
		NumberSequenceKeypoint.new(F.Marks.FadeAt, F.Marks.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.TextureLength = F.Marks.TextureLength
	trail.LightEmission = 0
	trail.LightInfluence = F.Marks.LightInfluence
	trail.FaceCamera = false
	trail.MinLength = 0
	trail.Enabled = false
	trail.Parent = a
	return trail
end

local function makeEmitter(name: string, surface: string, a: Attachment): ParticleEmitter
	local F = Config.Fx
	local look = F.Surfaces[surface] or F.Surfaces[F.Default]
	local S = F.Smoke
	local e = Instance.new("ParticleEmitter")
	e.Name = string.format(F.Names.Emitter, name, surface)
	e.Texture = S.Texture
	e.Color = ColorSequence.new(look.SmokeColour)
	e.Size = NumberSequence.new(S.SizeStart, S.SizeEnd)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, S.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(S.Lifetime[1], S.Lifetime[2])
	e.Speed = NumberRange.new(S.Speed[1], S.Speed[2])
	e.SpreadAngle = Vector2.new(S.SpreadDegrees, S.SpreadDegrees)
	e.Rotation = NumberRange.new(S.RotationDegrees[1], S.RotationDegrees[2])
	e.RotSpeed = NumberRange.new(S.RotationSpeed[1], S.RotationSpeed[2])
	e.Acceleration = Vector3.new(0, S.RiseAcceleration, 0)
	e.Drag = S.Drag
	e.LightEmission = S.LightEmission
	e.LightInfluence = S.LightInfluence
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = S.RateMin
	e.Enabled = false
	e.Parent = a
	return e
end

-- Throw away whatever this object built last, if it is still in the world. Only ever
-- reached when the SERVER has handed this client a different car (`CarService:Spawn`
-- again, or a re-dress on an archetype switch): in normal play the old body has already
-- been destroyed and taken its sixteen with it.
function Wheels.Clear(self: Wheels)
	for _, w in self.wheels do
		for _, fx in w.fx do
			fx.trail:Destroy()
			fx.emitter:Destroy()
		end
		w.a:Destroy()
		w.b:Destroy()
	end
	table.clear(self.wheels)
	self.body = nil
	self.built = 0
end

-- Build the sixteen, once, for the car this rig holds. Called every frame and does
-- nothing at all once it has built for a body -- an identity test on one field.
--
-- Returns whether there is something to drive.
function Wheels.Attach(self: Wheels, rig: any): boolean
	local body = rig and rig.body
	if body and self.body == body then
		return true
	end
	Wheels.Clear(self)
	-- `rig.complete` is deliberately NOT required: it is false until a shelled car's shell
	-- has replicated, and the effects hang off the five simulation parts and never touch
	-- the shell. A car that draws is a car that marks.
	if not body or #rig.wheels ~= #CarModel.WHEEL_NAMES then
		return false
	end

	local F = Config.Fx
	local half = F.Marks.Width * 0.5
	local radius = Config.Drift.WheelDiameter * 0.5

	for _, wheel in rig.wheels do
		local name = wheel.part.Name
		local index = wheelIndex(name)
		if not index then
			continue
		end
		-- The contact patch, in the BODY's frame -- which is the car's own frame, since
		-- `Render` writes the body part's CFrame as the car pose itself. `wheel.offset` is
		-- the wheel's centre, so the road is one radius below it, and `Marks.Lift` keeps
		-- the mark a hair clear of the surface it is drawn on.
		local patch = wheel.offset - Vector3.new(0, radius - F.Marks.Lift, 0)

		local a = Instance.new("Attachment")
		a.Name = string.format(F.Names.Attachment, name, "L")
		a.Position = patch - Vector3.new(half, 0, 0)
		a.Parent = body

		local b = Instance.new("Attachment")
		b.Name = string.format(F.Names.Attachment, name, "R")
		b.Position = patch + Vector3.new(half, 0, 0)
		b.Parent = body

		local fx: { SurfaceFx } = {}
		for _, surface in F.Built do
			-- The emitter hangs off `a`, which is half a mark's width to the car's left of
			-- the contact patch: 0.6 studs, against a cloud that is metres across.
			table.insert(fx, {
				surface = surface,
				trail = makeTrail(name, surface, a, b),
				emitter = makeEmitter(name, surface, a),
				on = false,
				rate = F.Smoke.RateMin,
			})
		end

		table.insert(self.wheels, {
			name = name,
			index = index,
			front = CarModel.isFrontWheel(name),
			a = a,
			b = b,
			fx = fx,
		})
	end

	if #self.wheels ~= #CarModel.WHEEL_NAMES then
		Wheels.Clear(self)
		return false
	end
	self.body = body
	self.built = #self.wheels * (2 + #F.Built * 2)
	return true
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

local function write(fx: SurfaceFx, on: boolean, rate: number)
	if fx.on ~= on then
		fx.on = on
		fx.trail.Enabled = on
		fx.emitter.Enabled = on
	end
	if on and fx.rate ~= rate then
		fx.rate = rate
		fx.emitter.Rate = rate
	end
end

-- Everything off, now, and remembered as off. Used when the car JUMPS -- a spawn, a
-- respawn, a teleport -- because a trail that is still enabled across a jump draws one
-- straight black line from where the car was to where it now is, right across the world.
function Wheels.Cut(self: Wheels)
	for _, w in self.wheels do
		for _, fx in w.fx do
			write(fx, false, fx.rate)
		end
	end
end

-- One frame. `input` is what `CarInputController:Get()` handed the model this frame: the
-- handbrake is an INPUT and not model state, which is why it is passed in rather than read
-- off `state` (`Drift/Model`'s `Input`). `dt` is unused today and is in the signature
-- because the next thing to land here -- a sound, or a rate that eases rather than snaps
-- -- needs it.
function Wheels.Update(self: Wheels, state: DriftModel.State?, input: any, _dt: number?)
	if #self.wheels == 0 then
		return
	end
	if not state or not self.enabled then
		Wheels.Cut(self)
		return
	end
	local handbrake = input ~= nil and input.handbrake == true
	for _, w in self.wheels do
		local down = state.wheelsDown[w.index] == true
		local emit, rate = Wheels.evaluate(state, handbrake, w.front, down)
		local surface = Wheels.surfaceOf(state, w.index, down)
		for _, fx in w.fx do
			write(fx, emit and fx.surface == surface, rate)
		end
	end
end

--------------------------------------------------------------------------------
-- Switches and the readout
--------------------------------------------------------------------------------

-- The effects on or off wholesale. This is where a `show effects` setting lands
-- (`SETTINGS.md`, features/car-fx.md "UI"), and it is also how the frame cost is measured:
-- the same drive with it true and with it false. It creates and destroys nothing.
function Wheels.SetEnabled(self: Wheels, on: boolean): boolean
	self.enabled = on == true
	if not self.enabled then
		Wheels.Cut(self)
	end
	return self.enabled
end

-- How long a mark stays. The hook the reference keeps for its end-of-run replay shot:
-- a huge number here leaves the whole run's marks on the road to be photographed.
function Wheels.SetMarkSeconds(self: Wheels, seconds: number)
	for _, w in self.wheels do
		for _, fx in w.fx do
			fx.trail.Lifetime = seconds
		end
	end
end

-- What every wheel is doing and WHY, so a playtest can say which gate is wrong rather
-- than "no smoke". Allocates, and is called by tests and by hand -- never by `Update`.
function Wheels.DebugState(self: Wheels, state: DriftModel.State?, input: any)
	local F = Config.Fx
	local out = {
		enabled = self.enabled,
		attached = self.body ~= nil,
		instances = self.built,
		surfaces = F.Built,
		slipDeg = if state then math.deg(state.slip) else nil,
		throttle = if state then state.throttle else nil,
		handbrake = input ~= nil and input.handbrake == true,
		speed = if state then DriftModel.speed(state) else nil,
		airborne = if state then state.airborne else nil,
		wheels = {},
	}
	if not state then
		return out
	end
	local handbrake = out.handbrake
	for _, w in self.wheels do
		local down = state.wheelsDown[w.index] == true
		local emit, rate, slipPast, throttleOk, handbrakeOk = Wheels.evaluate(state, handbrake, w.front, down)
		local emitting = false
		for _, fx in w.fx do
			emitting = emitting or fx.trail.Enabled
		end
		table.insert(out.wheels, {
			name = w.name,
			front = w.front,
			down = down,
			surface = Wheels.surfaceOf(state, w.index, down),
			thresholdDeg = if w.front then F.Gates.MaxSteerDegrees else 0,
			slipPast = slipPast,
			throttleOk = throttleOk,
			handbrakeOk = handbrakeOk,
			emit = emit,
			emitting = emitting, -- what the instances are actually set to
			rate = rate,
		})
	end
	return out
end

-- How many instances this object has in the world right now, counted off the car rather
-- than remembered. The number the "it allocates nothing" check compares.
function Wheels.CountInstances(self: Wheels): number
	local n = 0
	for _, w in self.wheels do
		n += (if w.a.Parent then 1 else 0) + (if w.b.Parent then 1 else 0)
		for _, fx in w.fx do
			n += (if fx.trail.Parent then 1 else 0) + (if fx.emitter.Parent then 1 else 0)
		end
	end
	return n
end

return Wheels
