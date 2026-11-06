--!strict
-- Wheels: the tyre marks and the smoke, per wheel, per surface
-- (docs/game/features/car-fx.md "Tyre marks and smoke").
--
-- A port of the reference game's wheel effects, written from a description of how they
-- work, with three things of our own on top of it that the user asked for after driving
-- it (T-062, round 2): the lean no longer buries the outside mark, there is a second
-- stylized smoke layer that builds per wheel, and a mark's darkness is how much rubber
-- went down per stud of road.
--
-- ------------------------------------------------------------------ the four gates
--
-- Each wheel asks four questions of the drift model's own state, every frame:
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
-- ------------------------------------------------------- cancelling the lean (the bug)
--
-- THE USER'S BUG, AND IT WAS NOT WHAT IT LOOKED LIKE. *"When you start to drift in one
-- direction, the outside tyre stops showing the tyre mark -- almost like it's being drawn
-- below the road surface."* It was being drawn below the road surface, and the reason is
-- the body's COSMETIC LEAN.
--
-- `Drift/Render` rolls the `Body` part about the car's centre of mass by `s.bodyRoll`, up
-- to `BodyRollMax` (10 degrees), to make the car lean out of a slide. The effects hang off
-- that part, 3.4 studs out from the centre of mass and 3.06 studs below it, so the roll
-- swings each contact patch through an arc. MEASURED in DR-Lane2, in a 40.3 degree slide
-- at 49.9 studs/s with only 2.99 degrees of roll on the body: the two left attachments sat
-- 0.133 and 0.071 studs BELOW the road and the two right ones 0.159 and 0.222 ABOVE it.
-- `Marks.Lift` is 0.05. At the full 10 degrees it reaches about six tenths of a stud. The
-- trails were `Enabled` the whole time; there was simply nothing to see.
--
-- So the patches are UN-ROLLED every frame. The body's transform about the centre of mass
-- is `C(com) * R(roll) * C(-com)`, and each attachment is given the local position that
-- transform maps back onto the flat contact patch -- which is `R(-roll)` about the same
-- point, two scalars of trigonometry per frame shared across all eight. The wheels
-- themselves are drawn flat by `Render` for exactly the same reason, so this makes the
-- marks agree with the wheels that leave them.
--
-- ------------------------------------------------------- how dark a mark is, and bands
--
-- `Trail.Transparency` applies to the WHOLE live ribbon and not to the segment being laid,
-- so turning it down darkens the five seconds of mark already on the road behind you.
-- Rubber does not change its mind, so instead each wheel carries ONE TRAIL PER BAND, all
-- strung between the same two attachments, and only the band matching this frame's density
-- is enabled. Each band's ribbon persists at its own fixed darkness and the line through a
-- corner genuinely darkens where the car was working hardest.
--
-- The density is the user's own: rubber laid per STUD OF ROAD, not per second. *"If the
-- drift continues as the car's speed lowers, more rubber is deposited per foot."*
--
-- ------------------------------------------------------- the two smoke layers
--
-- The DIFFUSE layer is unchanged and approved: soft, wide, driven by the car's slip angle.
-- The STYLIZED layer sits on top of it, is tight and bright and tilted back off the
-- contact patch so a glance can trace a puff to the wheel that threw it, and is driven by
-- that ONE WHEEL'S OWN HEAT rather than by the car. A wheel that has been sliding for
-- three seconds is visibly working harder than one that has just stepped out.
--
-- ------------------------------------------------------- what this must never do
--
-- NOTHING IS CREATED OR DESTROYED WHILE DRIVING. 32 instances per car at one surface and
-- four bands -- 4 wheels x (2 Attachments + 4 Trails + 2 ParticleEmitters) -- built once
-- when the rig is caught and switched with `Enabled` for ever after. There is no
-- `Instance.new`, no table, no `NumberSequence` and no `NumberRange` anywhere in `Update`:
-- a frame that allocates is the thing to fail on, and `FxTests` counts the instances
-- before and after a thousand frames because of it.
--
-- WHERE THE EFFECTS HANG, and why it is not the wheel part. `Drift/Render` spins each
-- wheel about its own axle (`CFrame.Angles(wheelSpin, 0, 0)`), so an attachment parented
-- to a wheel and offset down to the road would ORBIT the axle and draw a circle instead of
-- a line. Everything here therefore hangs off the car's `Body`, which never spins.
--
-- `Drift/Render` is not touched by any of this and does not know this module exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)

local Wheels = {}
Wheels.__index = Wheels

-- One surface's instances on one wheel. `band`, `diffuseRate` and `stylizedRate` are what
-- was last WRITTEN, so a frame that changes nothing writes nothing. `band` is an index
-- into `trails`, or 0 for "nothing is marking".
type SurfaceFx = {
	surface: string,
	trails: { Trail }, -- one per `Marks.Bands`, lightest first
	diffuse: ParticleEmitter,
	stylized: ParticleEmitter,
	band: number,
	diffuseRate: number,
	stylizedRate: number,
}

type WheelFx = {
	name: string,
	index: number, -- into `state.wheelsDown`: FL, FR, RL, RR
	front: boolean,
	a: Attachment,
	b: Attachment,
	patchA: Vector3, -- the FLAT contact patch, in the car's own frame, before the lean
	patchB: Vector3,
	heat: number, -- 0..1, this wheel's own, and the one thing kept between frames
	fx: { SurfaceFx },
}

export type Wheels = typeof(setmetatable(
	{} :: {
		body: BasePart?,
		wheels: { WheelFx },
		enabled: boolean,
		built: number, -- instances this object made for the body it holds
		roll: number, -- the lean the attachment positions were last written for
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
-- Returns, in order: whether this wheel emits at all, the DIFFUSE smoke rate it would emit
-- at, and the three gates that decided it. MULTIPLE RETURNS AND NOT A TABLE: this is
-- called four times a frame and a table would be four allocations a frame.
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
-- `Config.Fx.Default` and the per-surface table is built and fed from that one value. The
-- day `dirt` is laid, `Hit` grows a name, this reads it, and nothing else here changes
-- (features/car-fx.md "What our model already publishes").
function Wheels.surfaceOf(state: DriftModel.State, _index: number, down: boolean): string?
	if not down or state.airborne then
		return nil
	end
	return Config.Fx.Default
end

--------------------------------------------------------------------------------
-- Heat, density and the band, all pure
--------------------------------------------------------------------------------

-- The speed the contact patch is being dragged SIDEWAYS across the road, in studs/s.
-- `speed * |sin(slip)|`. This is the number a real tyre heats and wears on, and it is what
-- both the heat and the rubber density are built from: a car fully sideways at walking
-- pace is shearing far less rubber than the same angle at 90 studs/s.
function Wheels.slipSpeed(state: DriftModel.State): number
	return DriftModel.speed(state) * math.abs(math.sin(state.slip))
end

-- One wheel's heat, one step on. Rises while that wheel is actually sliding, at a rate set
-- by how hard it is sliding; falls when it is not. Clamped 0..1 and nothing else reads or
-- writes it.
-- `sliding` is the wheel's four gates; `slipSpeed` is how hard it is actually working.
--
-- IT TAKES BOTH, AND THAT IS MEASURED. Heating on the gates alone leaves a wheel stuck
-- hot: measured in DR-Lane2, a car that had caught a slide and rolled to a crawl still had
-- a residual slip angle of a few degrees, so its rear gates stayed open at a slip speed of
-- 0.1 studs/s -- the heat could not rise (nothing was happening) and could not fall (the
-- gate said it was sliding), and it sat at 0.56 four seconds after the drift ended. A tyre
-- that is not being dragged across anything is cooling, whatever the gate says, so below
-- `Heat.IdleSlipSpeed` this cools.
function Wheels.heatStep(heat: number, sliding: boolean, slipSpeed: number, dt: number): number
	local H = Config.Fx.Heat
	if sliding and slipSpeed > H.IdleSlipSpeed then
		local hard = math.clamp(slipSpeed / math.max(H.FullSlipSpeed, 1e-4), 0, 1)
		heat += dt * hard / math.max(H.RiseSeconds, 1e-4)
	else
		heat -= dt / math.max(H.FallSeconds, 1e-4)
	end
	return math.clamp(heat, 0, 1)
end

-- HOW MUCH RUBBER WENT DOWN PER STUD OF ROAD, 0..1 -- which is how dark the mark is.
--
-- The `/speed` is the whole point and it is the user's own reasoning: the same slide laid
-- over less ground is a darker line, so a drift that is still going as the car slows gets
-- darker rather than fainter. `MinSpeedForDensity` is the floor under that division, so a
-- car that has nearly stopped does not divide its way to a black stripe.
--
-- `heat` lifts it on top, up to `Marks.HeatGain`: a tyre that has been working for three
-- seconds lays more rubber than one that has just stepped out.
function Wheels.density(speed: number, slip: number, heat: number): number
	local M = Config.Fx.Marks
	local speedTerm = (M.RefSpeed / math.max(speed, M.MinSpeedForDensity)) ^ M.SpeedExponent
	local angleTerm = math.abs(math.sin(slip)) ^ M.AngleExponent
	return math.clamp(speedTerm * angleTerm * lerp(1, M.HeatGain, math.clamp(heat, 0, 1)), 0, 1)
end

-- Which band a density falls in: 1 is the lightest mark, `#Marks.Bands` the darkest. The
-- bands are even slices of 0..1, so the ladder is read straight off the number.
function Wheels.bandFor(density: number): number
	local bands = Config.Fx.Marks.Bands
	local n = #bands
	if n == 0 then
		return 0
	end
	return math.clamp(math.floor(density * n) + 1, 1, n)
end

-- The same, but refusing to leave the band it is already in until the density is clear of
-- the boundary by `Marks.BandHysteresis`. WITHOUT THIS a density sitting on a boundary
-- swaps trails every other frame, and every swap ends one ribbon and starts another --
-- which is a dotted line down the road instead of a mark. `previous` of 0 means the wheel
-- was not marking, and then there is nothing to be sticky about.
function Wheels.bandWith(density: number, previous: number): number
	local n = #Config.Fx.Marks.Bands
	local raw = Wheels.bandFor(density)
	if previous < 1 or previous > n or raw == previous then
		return raw
	end
	-- The boundary the two bands share, as a density.
	local boundary = (if raw > previous then previous else raw) / n
	if math.abs(density - boundary) < Config.Fx.Marks.BandHysteresis then
		return previous
	end
	return raw
end

-- The stylized layer's rate for one wheel, from that wheel's own heat. `RateMin` is zero
-- by default, so the layer is visibly the thing that BUILDS rather than a second cloud
-- that is always there.
function Wheels.stylizedRate(heat: number): number
	local S = Config.Fx.Stylized
	return lerp(S.RateMin, S.RateMax, math.clamp(heat, 0, 1))
end

-- Where an attachment has to sit IN THE BODY'S OWN FRAME for its world position to land on
-- the flat contact patch, given that `Drift/Render` has rolled the body by `roll` about
-- `com`. This is `C(com) * R(-roll) * C(-com) * patch`, written out in scalars so a frame
-- costs two trig calls and no CFrame.
--
-- `Render` rolls about the car's local Z (`CFrame.Angles(0, 0, roll)`), which moves X and
-- Y and leaves Z alone -- so this does too. See the header for what it is fixing.
function Wheels.patchLocal(patch: Vector3, com: Vector3, cosR: number, sinR: number): Vector3
	local dx, dy = patch.X - com.X, patch.Y - com.Y
	return Vector3.new(com.X + dx * cosR + dy * sinR, com.Y - dx * sinR + dy * cosR, patch.Z)
end

-- The roll itself, forward: what `Drift/Render`'s body transform does to a local point.
-- Only the tests and `DebugState` use it, to prove the inverse above really is one --
-- `applyRoll(patchLocal(p)) == p` for every roll, which is the one way a sign error in
-- this pair shows up as a number rather than as a mark nobody can see.
function Wheels.applyRoll(p: Vector3, com: Vector3, cosR: number, sinR: number): Vector3
	local dx, dy = p.X - com.X, p.Y - com.Y
	return Vector3.new(com.X + dx * cosR - dy * sinR, com.Y + dx * sinR + dy * cosR, p.Z)
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
		roll = math.huge, -- nothing written yet, so the first frame always writes
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

-- One band's trail. Every band is identical but for its transparency, and they all hang
-- between the same two attachments: only one is ever enabled, so they cannot overdraw.
local function makeTrail(name: string, surface: string, band: number, a: Attachment, b: Attachment): Trail
	local F = Config.Fx
	local look = F.Surfaces[surface] or F.Surfaces[F.Default]
	local flat = F.Marks.Bands[band]
	local trail = Instance.new("Trail")
	trail.Name = string.format(F.Names.Trail, name, surface, band)
	trail.Attachment0 = a
	trail.Attachment1 = b
	trail.Lifetime = F.Marks.Seconds
	trail.Color = ColorSequence.new(look.MarkColour)
	-- Flat at this band's darkness, then the last of its life spent fading out -- which is
	-- what stops a mark ending in a hard edge the moment its lifetime is up.
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, flat),
		NumberSequenceKeypoint.new(F.Marks.FadeAt, flat),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.TextureLength = F.Marks.TextureLength
	trail.LightEmission = 0
	trail.LightInfluence = F.Marks.LightInfluence
	trail.FaceCamera = false
	-- NOT ZERO. A ribbon 1.2 studs wide that advances 0.675 studs in a frame is a stack of
	-- quads wider than they are long, and the mark comes out as a ladder of rungs with
	-- road showing between them (measured; see `Marks.MinSegment`).
	trail.MinLength = F.Marks.MinSegment
	trail.Enabled = false
	trail.Parent = a
	return trail
end

-- The two smoke layers share a shape, so they share a builder: `S` is `Config.Fx.Smoke`
-- for the diffuse one and `Config.Fx.Stylized` for the one on top.
local function makeEmitter(fullName: string, colour: Color3, S: any, at: Attachment): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = fullName
	e.Texture = S.Texture
	e.Color = ColorSequence.new(colour)
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
	e.Rate = 0
	e.Enabled = false
	e.Parent = at
	return e
end

-- Throw away whatever this object built last, if it is still in the world. Only ever
-- reached when the SERVER has handed this client a different car (`CarService:Spawn`
-- again, or a re-dress on an archetype switch): in normal play the old body has already
-- been destroyed and taken its instances with it.
function Wheels.Clear(self: Wheels)
	for _, w in self.wheels do
		for _, fx in w.fx do
			for _, trail in fx.trails do
				trail:Destroy()
			end
			fx.diffuse:Destroy()
			fx.stylized:Destroy()
		end
		w.a:Destroy()
		w.b:Destroy()
	end
	table.clear(self.wheels)
	self.body = nil
	self.built = 0
	self.roll = math.huge
end

-- Build them all, once, for the car this rig holds. Called every frame and does nothing at
-- all once it has built for a body -- an identity test on one field.
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
		-- The FLAT contact patch, in the car's own frame. `wheel.offset` is the wheel's
		-- centre, so the road is one radius below it, and `Marks.Lift` keeps the mark a
		-- hair clear of the surface it is drawn on. These two are kept and the body's lean
		-- is cancelled against them every frame -- see the header.
		local patch = wheel.offset - Vector3.new(0, radius - F.Marks.Lift, 0)
		local patchA = patch - Vector3.new(half, 0, 0)
		local patchB = patch + Vector3.new(half, 0, 0)

		local a = Instance.new("Attachment")
		a.Name = string.format(F.Names.Attachment, name, "L")
		a.Position = patchA
		a.Parent = body

		local b = Instance.new("Attachment")
		b.Name = string.format(F.Names.Attachment, name, "R")
		b.Position = patchB
		-- The stylized layer is thrown BACKWARD off the patch, and this is the tilt. It is
		-- on `b` and not on `a` precisely so the diffuse layer, which the user approved as
		-- it is, keeps emitting straight up. A rotation does not move a `Trail`, which
		-- reads the two attachments' positions, so the mark is untouched.
		b.Orientation = Vector3.new(F.Stylized.EmitAngleDegrees, 0, 0)
		b.Parent = body

		local fx: { SurfaceFx } = {}
		for _, surface in F.Built do
			local look = F.Surfaces[surface] or F.Surfaces[F.Default]
			local trails: { Trail } = {}
			for bandIndex = 1, #F.Marks.Bands do
				table.insert(trails, makeTrail(name, surface, bandIndex, a, b))
			end
			table.insert(fx, {
				surface = surface,
				trails = trails,
				diffuse = makeEmitter(string.format(F.Names.Emitter, name, surface), look.SmokeColour, F.Smoke, a),
				stylized = makeEmitter(string.format(F.Names.Stylized, name, surface), look.PuffColour, F.Stylized, b),
				band = 0,
				diffuseRate = 0,
				stylizedRate = 0,
			})
		end

		table.insert(self.wheels, {
			name = name,
			index = index,
			front = CarModel.isFrontWheel(name),
			a = a,
			b = b,
			patchA = patchA,
			patchB = patchB,
			heat = 0,
			fx = fx,
		})
	end

	if #self.wheels ~= #CarModel.WHEEL_NAMES then
		Wheels.Clear(self)
		return false
	end
	self.body = body
	self.built = #self.wheels * (2 + #F.Built * (#F.Marks.Bands + 2))
	return true
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

-- Put one wheel's instances where this frame says they should be. `band` is 0 for nothing
-- marking; the diffuse and stylized rates are written only when they have moved.
local function write(fx: SurfaceFx, band: number, diffuseRate: number, stylizedRate: number)
	if fx.band ~= band then
		local wasOn, on = fx.band > 0, band > 0
		if wasOn then
			fx.trails[fx.band].Enabled = false
		end
		if on then
			fx.trails[band].Enabled = true
		end
		if wasOn ~= on then
			-- Only when the wheel starts or stops marking. A band change is a change of
			-- trail and nothing else: the smoke does not blink with it.
			fx.diffuse.Enabled = on
			fx.stylized.Enabled = on
		end
		fx.band = band
	end
	if band > 0 then
		if fx.diffuseRate ~= diffuseRate then
			fx.diffuseRate = diffuseRate
			fx.diffuse.Rate = diffuseRate
		end
		if fx.stylizedRate ~= stylizedRate then
			fx.stylizedRate = stylizedRate
			fx.stylized.Rate = stylizedRate
		end
	end
end

-- Everything off, now, and remembered as off. Used when the car JUMPS -- a spawn, a
-- respawn, a teleport -- because a trail that is still enabled across a jump draws one
-- straight black line from where the car was to where it now is, right across the world.
-- The heat is cleared with it: a car that has just been put down has cold tyres.
function Wheels.Cut(self: Wheels)
	for _, w in self.wheels do
		w.heat = 0
		for _, fx in w.fx do
			write(fx, 0, fx.diffuseRate, fx.stylizedRate)
		end
	end
end

-- One frame. `input` is what `CarInputController:Get()` handed the model this frame: the
-- handbrake is an INPUT and not model state, which is why it is passed in rather than read
-- off `state` (`Drift/Model`'s `Input`). `dt` is the frame, and the heat needs it.
function Wheels.Update(self: Wheels, state: DriftModel.State?, input: any, dt: number?)
	if #self.wheels == 0 then
		return
	end
	if not state or not self.enabled then
		Wheels.Cut(self)
		return
	end
	local step = math.max(dt or 0, 0)
	local handbrake = input ~= nil and input.handbrake == true
	local speed = DriftModel.speed(state)
	local slipSpeed = Wheels.slipSpeed(state)

	-- Cancel the body's lean, once for all eight attachments: two trig calls a frame.
	-- Written only when the lean has actually moved, which it has not while the car is
	-- standing still or running dead straight.
	local roll = state.bodyRoll
	if roll ~= self.roll then
		self.roll = roll
		local com = Config.Drift.CenterOfMass
		local cosR, sinR = math.cos(roll), math.sin(roll)
		for _, w in self.wheels do
			w.a.Position = Wheels.patchLocal(w.patchA, com, cosR, sinR)
			w.b.Position = Wheels.patchLocal(w.patchB, com, cosR, sinR)
		end
	end

	for _, w in self.wheels do
		local down = state.wheelsDown[w.index] == true
		local emit, diffuseRate = Wheels.evaluate(state, handbrake, w.front, down)
		w.heat = Wheels.heatStep(w.heat, emit, slipSpeed, step)
		local surface = Wheels.surfaceOf(state, w.index, down)
		local density = Wheels.density(speed, state.slip, w.heat)
		local stylizedRate = Wheels.stylizedRate(w.heat)
		for _, fx in w.fx do
			local band = 0
			if emit and fx.surface == surface then
				band = Wheels.bandWith(density, fx.band)
			end
			write(fx, band, diffuseRate, stylizedRate)
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
			for _, trail in fx.trails do
				trail.Lifetime = seconds
			end
		end
	end
end

-- What every wheel is doing and WHY, so a playtest can say which gate is wrong rather
-- than "no smoke", and so the heat and the density can be watched building over a slide.
-- Allocates, and is called by tests and by hand -- never by `Update`.
function Wheels.DebugState(self: Wheels, state: DriftModel.State?, input: any)
	local F = Config.Fx
	local out = {
		enabled = self.enabled,
		attached = self.body ~= nil,
		instances = self.built,
		bands = #F.Marks.Bands,
		surfaces = F.Built,
		rollDeg = if state then math.deg(state.bodyRoll) else nil,
		slipDeg = if state then math.deg(state.slip) else nil,
		throttle = if state then state.throttle else nil,
		handbrake = input ~= nil and input.handbrake == true,
		speed = if state then DriftModel.speed(state) else nil,
		slipSpeed = if state then Wheels.slipSpeed(state) else nil,
		airborne = if state then state.airborne else nil,
		wheels = {},
	}
	if not state then
		return out
	end
	local handbrake = out.handbrake
	local speed = DriftModel.speed(state)
	local com = Config.Drift.CenterOfMass
	local cosR, sinR = math.cos(state.bodyRoll), math.sin(state.bodyRoll)
	for _, w in self.wheels do
		local down = state.wheelsDown[w.index] == true
		local emit, diffuseRate, slipPast, throttleOk, handbrakeOk =
			Wheels.evaluate(state, handbrake, w.front, down)
		local density = Wheels.density(speed, state.slip, w.heat)
		local emitting, bandOn = false, 0
		for _, fx in w.fx do
			for i, trail in fx.trails do
				if trail.Enabled then
					emitting, bandOn = true, i
				end
			end
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
			heat = w.heat,
			density = density,
			band = Wheels.bandFor(density),
			bandOn = bandOn, -- the band actually enabled, 0 for none
			rate = diffuseRate,
			stylizedRate = Wheels.stylizedRate(w.heat),
			-- How far the lean had to be pushed back on this wheel this frame, in studs.
			-- This IS the bug, in one number: before the fix the attachment sat here and
			-- the mark went with it, up to six tenths of a stud under a road with five
			-- hundredths of clearance.
			leanOffsetY = w.a.Position.Y - w.patchA.Y,
			-- And the proof the cancelling is exact: roll the written position forward
			-- again, the way `Render` will, and it must land back on the flat patch.
			patchResidualY = Wheels.applyRoll(w.a.Position, com, cosR, sinR).Y - w.patchA.Y,
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
			for _, trail in fx.trails do
				n += if trail.Parent then 1 else 0
			end
			n += (if fx.diffuse.Parent then 1 else 0) + (if fx.stylized.Parent then 1 else 0)
		end
	end
	return n
end

return Wheels
