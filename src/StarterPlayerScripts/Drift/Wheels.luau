--!strict
-- Wheels: the tyre marks and the smoke, per wheel, per surface
-- (docs/game/features/car-fx.md "Tyre marks and smoke").
--
-- A port of the reference game's wheel effects, written from a description of how they
-- work, with three things of our own on top of it that the user asked for after driving
-- it (T-062, round 2): the lean no longer buries the outside mark, there is a second
-- stylized smoke layer that builds per wheel. A third, a darkness that followed how much
-- rubber went down per stud of road, was built, driven and taken out again (round 4).
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
-- The patches are taken back through the body's full local transform each frame, so
-- the lean and sprung pitch/roll move neither their ground centres nor particle sources.
-- T-207 turns each span across its wheel's actual rendered ground travel and restores
-- the natural body-X projection, capped at Marks.MinWidthRatio so it cannot disappear.
-- Contact-centre deltas include yaw and Render's substep; velocity/yaw is the first-frame
-- fallback and endpoint order stays continuous through reversal. Particle sources have
-- their own fixed anchors so turning a ribbon does not move its smoke or debris.
--
-- ------------------------------------- ONE SHADE OF LINE, and the ramp that is not here
--
-- A mark is one `Trail` per wheel per surface at ONE fixed darkness, `Marks.Transparency`.
-- There is no darkness ramp, and there is a reason it is worth knowing that there was one.
--
-- A progressive ramp WAS built, driven and removed at the user's call (T-062, rounds two
-- and three; the whole story is in features/car-fx.md "The darkness ramp that was built
-- and removed"). It worked out how much rubber a wheel was laying per stud of road and
-- picked a darkness from it. The reason it could never be a single number is this:
--
--   `Trail.Transparency` APPLIES TO THE WHOLE LIVE RIBBON, not to the segment being laid.
--   Turn it down and the five seconds of mark already on the road behind you darken with
--   it, which is not what rubber does.
--
-- So the ramp had to be a LADDER OF TRAILS, one per darkness, switching between them -- and
-- every switch is a hole in the mark, because the incoming trail has no points yet and
-- draws nothing until the contact patch has moved. That cost a swap overlap, a hysteresis,
-- a sticky gate and two rounds, and the user's verdict on the result was *"didn't quite
-- work with the progressive shading -- roll that back so it's just one shade of line."*
--
-- IF SOMEBODY WANTS THE RAMP BACK, the ladder is the only shape that can carry it and the
-- holes are inherent to the ladder. Read the spec first.
--
-- `Gates.StopSlipDegrees` and `Marks.MinSegment = 0` SURVIVE the rollback and are not part
-- of that story: a car sitting on the slip threshold flicking its marks on and off is
-- wrong whether or not there are bands, and a trail that will not draw until the patch has
-- moved half a stud starts every mark late.
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
-- ------------------------------------------------------- off the road (T-188)
--
-- Each wheel reads its OWN ground (`state.wheelSurface`, named by the spline road's probe).
-- On grass and gravel the tarmac smoke fades out over `Ground.FadeSeconds` -- its rate scaled
-- by a per-wheel mix, not switched -- and debris fades in: grass clippings, and brown dirt
-- blending in as the slip grows; on gravel a dust cloud. The grass mark is a flattened green
-- line OR a brown trench past `Grass.TrenchSlipDegrees`, with hysteresis (T-205).
-- Only one grass mark emits per wheel; already-laid marks keep their normal lifetime.
--
-- ------------------------------------------------------- ruts cut into the ground (T-265)
--
-- A grass mark is THREE trails side by side -- an edge, the core, an edge -- strung across
-- four attachments (`c` outer left, `e` inner left, `f` inner right, `d` outer right), so
-- the rut has a dark wet core and churned, lighter edges, and the flattened line the same
-- shape in greens. The strips meet edge to edge and never overlap. Both grass marks share
-- the four attachments; only one of them emits (T-205), and each stays `Ground.MarkSeconds`.
--
-- AND THEY ARE PUT ON THE DRAWN GROUND, not on the car's plane. Since T-251 the ground mesh
-- draws the grass, and since T-258 the car drives on past it onto the mountainside. The
-- car's plane through its four contacts is not that ground a stud either side of a tyre,
-- and a mark hung off the car at `Marks.Lift` floated a quarter of a stud over it on the
-- runoff and sank a tenth under it where the ground bent (measured, DR-Lane2). So a
-- marking grass wheel asks the drawn ground (`Drift/GroundMeshView`, passed into `Update`)
-- for its height under the mark's two outer corners and its centre, puts them `Ground.Lift`
-- over it, and lays the inner two on the lines between. Three height lookups a marking
-- grass wheel a frame and none otherwise. A corner the ground would move more than
-- `Ground.MaxSnap` off the car's plane, or with no drawn ground under it, stays on the plane.
--
-- NOTHING IS CREATED OR DESTROYED WHILE DRIVING. 88 instances per car at one smoking
-- surface -- 4 wheels x (2 Attachments + 1 Trail + 2 ParticleEmitters, and the off-road
-- layer's 4 Attachments + 7 Trails + 3 ParticleEmitters + 3 emitter anchors) -- built
-- once and switched with `Enabled` for ever after. It was 20 before T-188, 64 before T-265.
-- There is no `Instance.new`, no `NumberSequence` and no `NumberRange` anywhere in `Update`:
-- a frame that allocates instances is the thing to fail on, and `FxTests` counts them
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
local Suspension = require(script.Parent.Suspension)

local Wheels = {}
Wheels.__index = Wheels

-- One smoking surface's instances on one wheel. `on` (the trail), `smoking` (the two
-- emitters), `diffuseRate` and `stylizedRate` are what was last WRITTEN, so a frame that
-- changes nothing writes nothing. The trail and the smoke are switched SEPARATELY since
-- T-188: the mark stops the moment the wheel is off this surface, the smoke fades.
type SurfaceFx = {
	surface: string,
	trail: Trail,
	diffuse: ParticleEmitter,
	stylized: ParticleEmitter,
	on: boolean,
	smoking: boolean,
	diffuseRate: number,
	stylizedRate: number,
}

-- One mark or one emitter, with what was last written to it. A mark is one trail on gravel,
-- and three side by side on grass (edge, core, edge: T-265), switched together.
type MarkFx = { trails: { Trail }, on: boolean }
type KickFx = { emitter: ParticleEmitter, on: boolean, rate: number }

-- The off-road layer on one wheel (T-188, `Config.Fx.Ground`): grass, trench and gravel
-- marks, and the three debris emitters.
type GroundFx = {
	flat: MarkFx,
	trench: MarkFx,
	gravel: MarkFx,
	clippings: KickFx,
	dirt: KickFx,
	dust: KickFx,
}

type WheelFx = {
	name: string,
	index: number, -- into `state.wheelsDown`: FL, FR, RL, RR
	front: boolean,
	a: Attachment,
	b: Attachment,
	c: Attachment, -- the grass marks' outer pair (T-188)
	d: Attachment,
	e: Attachment, -- and their inner pair, either side of the core (T-265)
	f: Attachment,
	sourceA: Attachment, -- fixed diffuse smoke / dust source, independent of mark span
	sourceB: Attachment, -- fixed stylized smoke source
	sourceC: Attachment, -- fixed clippings / dirt source
	previousPatch: Vector3?, -- rendered contact centre last frame, including yaw / substep
	span: Vector3?, -- world cross-track axis; keep endpoint ordering continuous
	patchA: Vector3, -- the FLAT contact patch, in the car's own frame, before the lean
	patchB: Vector3,
	patchC: Vector3,
	patchD: Vector3,
	heat: number, -- 0..1, this wheel's own
	marking: boolean, -- the gates said emit last frame: the slip gate's hysteresis
	-- How much of each surface's effect this wheel is showing, 0..1, each walked toward 1
	-- on its own surface and 0 off it over `Ground.FadeSeconds` (T-188). Held in the air.
	mixSmoke: number,
	mixGrass: number,
	mixGravel: number,
	smokeSurface: string, -- the smoking surface the smoke is fading from or to
	trench: boolean, -- past the trench threshold, with its hysteresis
	snapped: number, -- grass-mark corners put on the drawn ground this frame, 0..3 (T-265)
	fx: { SurfaceFx },
	ground: GroundFx,
}

export type Wheels = typeof(setmetatable(
	{} :: {
		body: BasePart?,
		wheels: { WheelFx },
		enabled: boolean,
		built: number, -- instances this object made for the body it holds
		-- What laying grass marks on the drawn ground has cost since `new` (T-265): lookups
		-- made and the seconds spent placing those wheels' corners. Read by `DebugState`.
		groundLookups: number,
		groundSeconds: number,
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
-- `marking` is whether this wheel was ALREADY laying a mark last frame, and it is only
-- used for the slip gate's hysteresis: a gate with one threshold chatters on anything that
-- sits on it, and chatter in this gate is a hole in the mark. Measured: a car at 44
-- studs/s with its slip hovering on half a degree switched its rear marks on and off
-- repeatedly while nothing about the slide had changed.
function Wheels.evaluate(
	state: DriftModel.State,
	handbrake: boolean,
	front: boolean,
	down: boolean,
	marking: boolean?
): (boolean, number, boolean, boolean, boolean)
	local F = Config.Fx
	local slip = math.abs(state.slip)

	-- Gate 2. The fronts are drawn pointing along the travel, so they are not sliding
	-- until the slip angle is past that drawn angle; the rears have no such head start.
	local threshold = if front then math.rad(F.Gates.MaxSteerDegrees) else 0
	local floor = if marking then F.Gates.StopSlipDegrees else F.Gates.MinSlipDegrees
	local slipPast = (slip - threshold) > math.rad(floor)
	-- And a wheel only STARTS marking above `Gates.MinMarkSpeed`: pulling away from rest
	-- the slip angle is noise on a velocity of a stud a second, and it laid marks (T-151).
	-- A wheel already marking is not held to it, so the hysteresis above is unchanged.
	if not marking and DriftModel.speed(state) < F.Gates.MinMarkSpeed then
		slipPast = false
	end

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

-- Which surface a wheel is standing on: `"grass"`, `"gravel"`, or a smoking surface
-- (`"tarmac"`). THE GAP IN THE PORT IS CLOSED (T-188): `Hit` names its ground on the spline
-- road and `Drift/Model` copies each wheel's name to `state.wheelSurface`. A hit with no name
-- -- the parts world, the playground -- and a name with no look are `Config.Fx.Default`.
-- nil in the air.
function Wheels.surfaceOf(state: DriftModel.State, index: number, down: boolean): string?
	if not down or state.airborne then
		return nil
	end
	local names = (state :: any).wheelSurface
	local name = names and names[index]
	if name == "grass" or name == "gravel" then
		return name
	end
	if name and name ~= "" and Config.Fx.Surfaces[name] then
		return name
	end
	return Config.Fx.Default
end

--------------------------------------------------------------------------------
-- Off the road, pure (T-188, `Config.Fx.Ground`)
--------------------------------------------------------------------------------

-- One surface mix one frame on: toward `target` (0 or 1) by `dt / FadeSeconds`, so a full
-- swing takes `FadeSeconds` whichever way it goes.
function Wheels.mixStep(mix: number, target: number, dt: number): number
	local step = dt / math.max(Config.Fx.Ground.FadeSeconds, 1e-4)
	if mix < target then
		return math.min(mix + step, target)
	end
	return math.max(mix - step, target)
end

-- Whether the grass is being cut to a trench, from |slip| in DEGREES and whether it was
-- already. Two thresholds, so a slide that sits on one cannot chatter.
function Wheels.trenchOn(slipDeg: number, was: boolean): boolean
	local G = Config.Fx.Ground.Grass
	return slipDeg >= (if was then G.TrenchStopDegrees else G.TrenchSlipDegrees)
end

-- How much of the dirt spray is in, 0..1, from |slip| in degrees: a smoothstep from
-- `DirtStartDegrees` to `DirtFullDegrees`, so it blends in around the trench.
function Wheels.dirtShare(slipDeg: number): number
	local G = Config.Fx.Ground.Grass
	local t = math.clamp((slipDeg - G.DirtStartDegrees) / math.max(G.DirtFullDegrees - G.DirtStartDegrees, 1e-4), 0, 1)
	return t * t * (3 - 2 * t)
end

-- One debris emitter's rate before its surface mix: `RateMin`..`RateMax` by
-- |slip| / `Grass.FullSlipDegrees`.
function Wheels.kickRate(S: any, slipDeg: number): number
	local t = math.clamp(slipDeg / math.max(Config.Fx.Ground.Grass.FullSlipDegrees, 1e-4), 0, 1)
	return lerp(S.RateMin, S.RateMax, t)
end

--------------------------------------------------------------------------------
-- Tyre heat, pure. It drives the STYLIZED SMOKE and nothing else now: the mark's darkness
-- used to read it too, through a rubber-per-stud curve that the user had taken out.
--------------------------------------------------------------------------------

-- The speed the contact patch is being dragged SIDEWAYS across the road, in studs/s.
-- `speed * |sin(slip)|`. This is the number a real tyre heats and wears on: a car fully
-- sideways at walking pace is shearing far less rubber than the same angle at 90 studs/s.
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
-- The tests use it to prove the roll-only inverse above really is one --
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
		groundLookups = 0,
		groundSeconds = 0,
	}, Wheels) :: any
end

-- Instances one wheel carries: its 2 attachments and 1 trail + 2 emitters per smoking
-- surface, plus the off-road layer's 4 attachments, 7 trails (3 flattened, 3 rut,
-- 1 gravel) and 3 emitters (T-188, T-265), and 3 fixed emitter anchors (T-207). 22 at
-- one smoking surface, so 88 a car.
function Wheels.perWheel(): number
	return 2 + #Config.Fx.Built * 3 + 4 + 7 + 3 + 3
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
-- ONE trail per wheel per surface, at ONE darkness. There used to be a ladder of them --
-- see the header -- and taking it out is most of this function.
-- `colour` and `flat` are the mark's look: the tarmac's from `Surfaces`, the off-road ones
-- from `Ground` (T-188). Everything else about a mark is the same on every surface.
-- `dry`, when given, is the colour at the old end of the mark: a trail's colour runs along
-- its length, so a grass mark dries out as it ages (T-265). `seconds` is its lifetime.
local function makeTrail(
	fullName: string,
	colour: Color3,
	flat: number,
	a: Attachment,
	b: Attachment,
	dry: Color3?,
	seconds: number?
): Trail
	local F = Config.Fx
	local trail = Instance.new("Trail")
	trail.Name = fullName
	trail.Attachment0 = a
	trail.Attachment1 = b
	trail.Lifetime = seconds or F.Marks.Seconds
	trail.Color = if dry then ColorSequence.new(colour, dry) else ColorSequence.new(colour)
	-- Flat for most of its life, then the last of it spent fading out -- which is what
	-- stops a mark ending in a hard edge the moment its lifetime is up. THIS IS THE ONLY
	-- transparency a mark ever has: it is a property of the whole live ribbon, which is
	-- exactly why a darkness that varies along the mark needed a ladder of trails.
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, flat),
		NumberSequenceKeypoint.new(F.Marks.FadeAt, flat),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.TextureLength = F.Marks.TextureLength
	trail.LightEmission = 0
	trail.LightInfluence = F.Marks.LightInfluence
	trail.FaceCamera = false
	-- ZERO, so a mark starts drawing on its very first frame (see `Marks.MinSegment`).
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
	-- Smoke fades IN over the first quarter of its life; debris (`FadeIn = 0`, T-188) is
	-- solid from birth and only fades at the end.
	if S.FadeIn == 0 then
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, S.Transparency),
			NumberSequenceKeypoint.new(0.7, S.Transparency),
			NumberSequenceKeypoint.new(1, 1),
		})
	else
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, S.Transparency),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
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
			fx.trail:Destroy()
			fx.diffuse:Destroy()
			fx.stylized:Destroy()
		end
		local g = w.ground
		for _, m in { g.flat, g.trench, g.gravel } do
			for _, trail in m.trails do
				trail:Destroy()
			end
		end
		for _, k in { g.clippings, g.dirt, g.dust } do
			k.emitter:Destroy()
		end
		w.a:Destroy()
		w.b:Destroy()
		w.c:Destroy()
		w.d:Destroy()
		w.e:Destroy()
		w.f:Destroy()
		w.sourceA:Destroy()
		w.sourceB:Destroy()
		w.sourceC:Destroy()
	end
	table.clear(self.wheels)
	self.body = nil
	self.built = 0
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
		-- The stylized source keeps its backward tilt. The source built below copies
		-- this frame independently of the mark span; diffuse smoke stays straight up.
		b.Orientation = Vector3.new(F.Stylized.EmitAngleDegrees, 0, 0)
		b.Parent = body

		-- The grass marks' four corners (T-188, T-265): an outer pair the whole mark wide
		-- and an inner pair either side of its core. Where they sit is worked out every
		-- frame in `Update`; these are only their starting places. The debris source below
		-- copies `c`'s backward `KickAngleDegrees` tilt.
		local G = F.Ground
		local outer, inner = G.Grass.Width * 0.5, G.Grass.CoreWidth * 0.5
		local patchC = patch - Vector3.new(outer, 0, 0)
		local patchD = patch + Vector3.new(outer, 0, 0)
		local function corner(side: string, at: Vector3): Attachment
			local x = Instance.new("Attachment")
			x.Name = string.format(F.Names.TrenchAttachment, name, side)
			x.Position = at
			x.Parent = body
			return x
		end
		local c = corner("L", patchC)
		c.Orientation = Vector3.new(G.Grass.KickAngleDegrees, 0, 0)
		local d = corner("R", patchD)
		local e = corner("IL", patch - Vector3.new(inner, 0, 0))
		local f = corner("IR", patch + Vector3.new(inner, 0, 0))

		-- Marks turn across the ground path, but particle sources keep their original
		-- positions and tilt. Built once: no source moves around a tyre with the slip.
		local function source(at: Attachment): Attachment
			local anchor = Instance.new("Attachment")
			anchor.Name = at.Name .. "_Emitter"
			anchor.CFrame = at.CFrame
			anchor.Parent = body
			return anchor
		end
		local sourceA, sourceB, sourceC = source(a), source(b), source(c)

		local fx: { SurfaceFx } = {}
		for _, surface in F.Built do
			local look = F.Surfaces[surface] or F.Surfaces[F.Default]
			table.insert(fx, {
				surface = surface,
				trail = makeTrail(string.format(F.Names.Trail, name, surface), look.MarkColour, F.Marks.Transparency, a, b),
				diffuse = makeEmitter(string.format(F.Names.Emitter, name, surface), look.SmokeColour, F.Smoke, sourceA),
				stylized = makeEmitter(string.format(F.Names.Stylized, name, surface), look.PuffColour, F.Stylized, sourceB),
				on = false,
				smoking = false,
				diffuseRate = 0,
				stylizedRate = 0,
			})
		end

		local function mark(kind: string, look: any, x: Attachment, y: Attachment): MarkFx
			return {
				trails = { makeTrail(string.format(F.Names.GroundTrail, name, kind), look.Colour, look.Transparency, x, y) },
				on = false,
			}
		end
		-- A grass mark (T-265): edge, core, edge across the four corners, each strip drying
		-- along its length and staying `Ground.MarkSeconds`.
		local function strips(kind: string, look: any): MarkFx
			local function strip(suffix: string, part: any, x: Attachment, y: Attachment): Trail
				local full = string.format(F.Names.GroundTrail, name, kind .. suffix)
				return makeTrail(full, part.Colour, part.Transparency, x, y, part.DryColour, G.MarkSeconds)
			end
			return {
				trails = { strip("_L", look.Edge, c, e), strip("", look.Core, e, f), strip("_R", look.Edge, f, d) },
				on = false,
			}
		end
		local function kick(kind: string, S: any, at: Attachment): KickFx
			return { emitter = makeEmitter(string.format(F.Names.GroundEmitter, name, kind), S.Colour, S, at), on = false, rate = 0 }
		end
		local ground: GroundFx = {
			flat = strips("grass", G.Grass.FlatMark),
			trench = strips("trench", G.Grass.TrenchMark),
			gravel = mark("gravel", G.Gravel.Mark, a, b),
			clippings = kick("grass", G.Grass.Clippings, sourceC),
			dirt = kick("dirt", G.Grass.Dirt, sourceC),
			dust = kick("dust", G.Gravel.Dust, sourceA),
		}

		table.insert(self.wheels, {
			name = name,
			index = index,
			front = CarModel.isFrontWheel(name),
			a = a,
			b = b,
			c = c,
			d = d,
			e = e,
			f = f,
			sourceA = sourceA,
			sourceB = sourceB,
			sourceC = sourceC,
			previousPatch = nil,
			span = nil,
			patchA = patchA,
			patchB = patchB,
			patchC = patchC,
			patchD = patchD,
			heat = 0,
			marking = false,
			mixSmoke = 1,
			mixGrass = 0,
			mixGravel = 0,
			smokeSurface = F.Default,
			trench = false,
			snapped = 0,
			fx = fx,
			ground = ground,
		})
	end

	if #self.wheels ~= #CarModel.WHEEL_NAMES then
		Wheels.Clear(self)
		return false
	end
	self.body = body
	self.built = #self.wheels * Wheels.perWheel()
	return true
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

-- Put one wheel's instances where this frame says they should be. `band` is 0 for nothing
-- marking; the diffuse and stylized rates are written only when they have moved.
-- Put one band's trail out, unless it is the one that is now being laid.
-- One wheel's instances, this frame. With one darkness there is nothing to choose between:
-- the trail and the two emitters go on and off together, and only the rates move.
-- `on` is the mark; `smoking` the two emitters, which since T-188 can still be fading out
-- after the mark has stopped (the wheel has left this surface) -- so they are two switches.
local function write(fx: SurfaceFx, on: boolean, smoking: boolean, diffuseRate: number, stylizedRate: number)
	if fx.on ~= on then
		fx.on = on
		fx.trail.Enabled = on
	end
	if fx.smoking ~= smoking then
		fx.smoking = smoking
		fx.diffuse.Enabled = smoking
		fx.stylized.Enabled = smoking
	end
	if smoking then
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

-- Stop or resume this mark without clearing the segments already behind the car.
-- Keep its trail and attachments across switches, so old history keeps its lifetime
-- instead of being erased or recoloured when the other grass mark takes over.
local function writeMark(m: MarkFx, on: boolean)
	if m.on ~= on then
		m.on = on
		for _, trail in m.trails do
			trail.Enabled = on
		end
	end
end

-- An emitter is on while it has a rate; the rate is written only when it has moved.
local function writeKick(k: KickFx, rate: number)
	local on = rate > 0
	if k.on ~= on then
		k.on = on
		k.emitter.Enabled = on
	end
	if on and k.rate ~= rate then
		k.rate = rate
		k.emitter.Rate = rate
	end
end

local function groundOff(g: GroundFx)
	writeMark(g.flat, false)
	writeMark(g.trench, false)
	writeMark(g.gravel, false)
	writeKick(g.clippings, 0)
	writeKick(g.dirt, 0)
	writeKick(g.dust, 0)
end

-- Everything off and remembered as off. Used when the car jumps (spawn, respawn or
-- teleport), so no enabled trail draws across the jump. The tyres are put back cold too.
function Wheels.Cut(self: Wheels)
	for _, w in self.wheels do
		w.heat = 0
		w.previousPatch = nil
		w.span = nil
		w.marking = false
		w.trench = false
		w.snapped = 0
		for _, fx in w.fx do
			write(fx, false, false, fx.diffuseRate, fx.stylizedRate)
		end
		groundOff(w.ground)
	end
end

-- One grass-mark corner put on the drawn ground (T-265): `p` is where the car's plane has
-- it, and it comes back `lift` over the ground under it -- or as it was, and false, when
-- there is no drawn ground there or reaching it would move it more than `maxSnap`.
-- `ground` is anything with `_drawnAt(x, z) -> number?`: `Drift/GroundMeshView`, which
-- answers off the very triangles it drew, or a stand-in in `FxTests`.
function Wheels.onGround(ground: any, p: Vector3, lift: number, maxSnap: number): (Vector3, boolean)
	local y = ground:_drawnAt(p.X, p.Z)
	if type(y) == "number" and math.abs(y + lift - p.Y) <= maxSnap then
		return Vector3.new(p.X, y + lift, p.Z), true
	end
	return p, false
end

-- One frame. `input` is what `CarInputController:Get()` handed the model this frame: the
-- handbrake is an INPUT and not model state, which is why it is passed in rather than read
-- off `state` (`Drift/Model`'s `Input`). `dt` is the frame, and the heat needs it.
-- `ground` is the drawn ground (`Drift/GroundMeshView`), nil where there is none: the grass
-- marks are laid on it (T-265, see the header).
function Wheels.Update(self: Wheels, state: DriftModel.State?, input: any, dt: number?, ground: any?)
	if #self.wheels == 0 then
		return
	end
	if not state or not self.enabled then
		Wheels.Cut(self)
		return
	end
	local step = math.max(dt or 0, 0)
	local handbrake = input ~= nil and input.handbrake == true
	local slipSpeed = Wheels.slipSpeed(state)

	-- Recover the road pose actually drawn by Render.apply, including its fractional
	-- simulation step. Cancel suspension and cosmetic lean before placing the patch.
	local bodyCF = (self.body :: BasePart).CFrame
	local bodyLocal = Suspension.bodyLocal(state)
	local unbody = bodyLocal:Inverse()
	local road = bodyCF * unbody
	local normal = state.groundUp
	local normalLength = normal.Magnitude
	if normalLength > 1e-4 and normalLength < math.huge then
		normal /= normalLength
	else
		normal = road.UpVector
	end
	local lifts = state.wheelLift
	local F = Config.Fx
	local G = F.Ground
	local half = F.Marks.Width * 0.5
	local outer = G.Grass.Width * 0.5
	local inner = G.Grass.CoreWidth * 0.5
	local innerShare = inner / math.max(outer, 1e-4)
	local drawn = ground ~= nil and type(ground._drawnAt) == "function"

	local slipDeg = math.deg(math.abs(state.slip))
	local dirt = Wheels.dirtShare(slipDeg)
	local clipShare = 1 - (1 - G.Grass.ClippingsAtFullDirt) * dirt
	local clipBase = Wheels.kickRate(G.Grass.Clippings, slipDeg) * clipShare
	local dirtBase = Wheels.kickRate(G.Grass.Dirt, slipDeg) * dirt
	local dustBase = Wheels.kickRate(G.Gravel.Dust, slipDeg)

	for _, w in self.wheels do
		local down = state.wheelsDown[w.index] == true
		-- The slip gate is sticky once a wheel is marking (`Gates.StopSlipDegrees`): a
		-- gate that chatters is a hole in the mark, and this one was chattering. Kept on the
		-- wheel, not read off the trails, so it holds across a change of surface (T-188).
		local emit, diffuseRate = Wheels.evaluate(state, handbrake, w.front, down, w.marking)
		w.marking = emit
		w.heat = Wheels.heatStep(w.heat, emit, slipSpeed, step)
		local surface = Wheels.surfaceOf(state, w.index, down)
		local grass, gravel = surface == "grass", surface == "gravel"

		-- The mixes walk toward this wheel's surface (T-188). In the air there is no surface
		-- and they hold, so a wheel that lands where it took off picks up where it was.
		if surface then
			local smokes = not grass and not gravel
			w.mixSmoke = Wheels.mixStep(w.mixSmoke, if smokes then 1 else 0, step)
			w.mixGrass = Wheels.mixStep(w.mixGrass, if grass then 1 else 0, step)
			w.mixGravel = Wheels.mixStep(w.mixGravel, if gravel then 1 else 0, step)
			if smokes then
				w.smokeSurface = surface
			end
		end
		w.trench = Wheels.trenchOn(slipDeg, w.trench)

		-- Where the marks go: across this wheel's own path over the ground (T-207).
		local lift = Vector3.new(0, if lifts then lifts[w.index] or 0 else 0, 0)
		local patch = (w.patchA + w.patchB) * 0.5 + lift
		local centre = road:PointToWorldSpace(patch)
		local previous = w.previousPatch
		local flow = if previous then centre - previous else Vector3.zero
		flow -= normal * flow:Dot(normal)
		if flow.Magnitude < 1e-4 or not (flow.Magnitude < math.huge) then
			-- First frame / stopped: use velocity plus this contact's yaw motion, then
			-- retain the previous axis at rest. Never divide by cos(slip) near sideways.
			flow = state.velocity + (Vector3.yAxis * state.r):Cross(centre - road.Position)
			flow -= normal * flow:Dot(normal)
		end
		local span = flow:Cross(normal)
		if span.Magnitude < 1e-4 or not (span.Magnitude < math.huge) then
			span = w.span or road.RightVector
			span -= normal * span:Dot(normal)
			if span.Magnitude < 1e-4 then
				span = road.LookVector:Cross(normal)
			end
		end
		span = span.Unit
		local oldSpan = w.span
		if oldSpan and span:Dot(oldSpan) < 0 then
			span = -span -- the same undirected width, with no endpoint swap on reversing
		end
		w.previousPatch, w.span = centre, span
		-- Keep the original angle-dependent projection until the configured floor,
		-- while spanning across the path avoids an unbounded 1/cos expansion sideways.
		local ratio = math.clamp(math.abs(road.RightVector:Dot(span)), F.Marks.MinWidthRatio, 1)
		local localSpan = road:VectorToObjectSpace(span) * ratio
		w.a.Position = unbody:PointToWorldSpace(patch - localSpan * half)
		w.b.Position = unbody:PointToWorldSpace(patch + localSpan * half)
		w.sourceA.Position = unbody:PointToWorldSpace(w.patchA + lift)
		w.sourceB.Position = unbody:PointToWorldSpace(w.patchB + lift)
		w.sourceC.Position = unbody:PointToWorldSpace(w.patchC + lift)

		-- The grass mark's four corners (T-265). Marking on grass with the drawn ground
		-- there: the outer two and the centre are put on that ground and the inner two on
		-- the lines between, so each strip lies on the ground under it. Otherwise on the
		-- car's plane, as every mark was before.
		local mid = (w.patchC + w.patchD) * 0.5 + lift
		w.snapped = 0
		if drawn and emit and grass then
			local started = os.clock()
			local at = road:PointToWorldSpace(mid)
			local across = span * (ratio * outer)
			local l, onL = Wheels.onGround(ground, at - across, G.Lift, G.MaxSnap)
			local m, onM = Wheels.onGround(ground, at, G.Lift, G.MaxSnap)
			local r, onR = Wheels.onGround(ground, at + across, G.Lift, G.MaxSnap)
			w.snapped = (if onL then 1 else 0) + (if onM then 1 else 0) + (if onR then 1 else 0)
			w.c.Position = bodyCF:PointToObjectSpace(l)
			w.e.Position = bodyCF:PointToObjectSpace(m:Lerp(l, innerShare))
			w.f.Position = bodyCF:PointToObjectSpace(m:Lerp(r, innerShare))
			w.d.Position = bodyCF:PointToObjectSpace(r)
			self.groundLookups += 3
			self.groundSeconds += os.clock() - started
		else
			w.c.Position = unbody:PointToWorldSpace(mid - localSpan * outer)
			w.e.Position = unbody:PointToWorldSpace(mid - localSpan * inner)
			w.f.Position = unbody:PointToWorldSpace(mid + localSpan * inner)
			w.d.Position = unbody:PointToWorldSpace(mid + localSpan * outer)
		end

		-- Tarmac: the MARK is this surface or nothing, at once (a mark is on the ground it is
		-- on); the SMOKE is scaled by the mix and fades.
		local stylizedRate = Wheels.stylizedRate(w.heat)
		local mix = w.mixSmoke
		for _, fx in w.fx do
			local smoking = emit and mix > 0 and fx.surface == w.smokeSurface
			write(fx, emit and fx.surface == surface, smoking, diffuseRate * mix, stylizedRate * mix)
		end

		-- Off the road. Each grass-marking wheel chooses green OR brown using the
		-- existing trench hysteresis; never emit both at the same contact patch (T-205).
		local g = w.ground
		writeMark(g.flat, emit and grass and not w.trench)
		writeMark(g.trench, emit and grass and w.trench)
		writeMark(g.gravel, emit and gravel)
		writeKick(g.clippings, if emit then clipBase * w.mixGrass else 0)
		writeKick(g.dirt, if emit then dirtBase * w.mixGrass else 0)
		writeKick(g.dust, if emit then dustBase * w.mixGravel else 0)
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
		-- The grass marks keep their longer life, in proportion (T-265).
		local grass = seconds * Config.Fx.Ground.MarkSeconds / math.max(Config.Fx.Marks.Seconds, 1e-4)
		for _, m in { w.ground.flat, w.ground.trench } do
			for _, trail in m.trails do
				trail.Lifetime = grass
			end
		end
		w.ground.gravel.trails[1].Lifetime = seconds
	end
end

-- What every wheel is doing and WHY, so a playtest can say which gate is wrong rather
-- than "no smoke", and so the heat can be watched building over a slide.
-- Allocates, and is called by tests and by hand -- never by `Update`.
function Wheels.DebugState(self: Wheels, state: DriftModel.State?, input: any)
	local F = Config.Fx
	local out = {
		enabled = self.enabled,
		attached = self.body ~= nil,
		instances = self.built,
		surfaces = F.Built,
		-- Laying grass marks on the drawn ground (T-265): lookups so far, and the mean
		-- microseconds a marking grass wheel spent on it (its three lookups and four corners).
		groundLookups = self.groundLookups,
		groundMicros = if self.groundLookups > 0 then self.groundSeconds / (self.groundLookups / 3) * 1e6 else 0,
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
	local bodyLocal = Suspension.bodyLocal(state)
	for _, w in self.wheels do
		local down = state.wheelsDown[w.index] == true
		local emit, diffuseRate, slipPast, throttleOk, handbrakeOk =
			Wheels.evaluate(state, handbrake, w.front, down)
		-- `lit` is how many of this wheel's trails are actually drawing. It is 1 while the
		-- wheel marks and 0 otherwise -- and **0 WHILE `emitting` IS TRUE IS A GAP IN THE
		-- MARK**, which is the number the band ladder was removed over. Keep it.
		-- Count every alternative, including the trench (T-205), so a double grass mark
		-- reports 2 instead of being hidden from this readout.
		local emitting, lit = w.marking, 0
		for _, fx in w.fx do
			if fx.trail.Enabled then
				lit += 1
			end
		end
		-- A grass mark is three strips and counts as ONE mark (T-265). `split` counts the
		-- strips of a mark that disagree with its first, which nothing should ever cause.
		local g = w.ground
		local split = 0
		for _, m in { g.flat, g.trench, g.gravel } do
			local on = m.trails[1].Enabled
			if on then
				lit += 1
			end
			for _, trail in m.trails do
				if trail.Enabled ~= on then
					split += 1
				end
			end
		end
		local smokeRate = 0
		for _, fx in w.fx do
			if fx.diffuse.Enabled then
				smokeRate += fx.diffuse.Rate
			end
		end
		local function live(k: KickFx): number
			return if k.emitter.Enabled then k.emitter.Rate else 0
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
			lit = lit, -- trails drawing: 1 while marking, 0 otherwise. 0 while `emitting`
			-- is a gap, and there is no longer anything that can cause one
			rate = diffuseRate,
			stylizedRate = Wheels.stylizedRate(w.heat),
			-- Off the road (T-188): the surface mixes, and what the instances are set to.
			smokeMix = w.mixSmoke,
			grassMix = w.mixGrass,
			gravelMix = w.mixGravel,
			trench = w.trench,
			smokeRate = smokeRate, -- the diffuse smoke's live Rate, 0 when off
			grassMark = g.flat.trails[1].Enabled,
			trenchMark = g.trench.trails[1].Enabled,
			gravelMark = g.gravel.trails[1].Enabled,
			split = split, -- strips of one mark disagreeing: always 0 (T-265)
			-- The grass mark's corners put on the drawn ground last frame (T-265): 3 while
			-- marking on drawn grass, 0 when not marking grass or with no drawn ground.
			onGround = w.snapped,
			clippingsRate = live(g.clippings),
			dirtRate = live(g.dirt),
			dustRate = live(g.dust),
			-- How far the lean had to be pushed back on this wheel this frame, in studs.
			-- This IS the bug, in one number: before the fix the attachment sat here and
			-- the mark went with it, up to six tenths of a stud under a road with five
			-- hundredths of clearance.
			leanOffsetY = w.sourceA.Position.Y - w.patchA.Y,
			-- Undo the full body-local offset on the fixed source, not the turning mark
			-- endpoint. Include suspension lift so pitch / roll do not fake a residual.
			patchResidualY = bodyLocal:PointToWorldSpace(w.sourceA.Position).Y
				- w.patchA.Y - (if state.wheelLift then state.wheelLift[w.index] or 0 else 0),
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
		n += (if w.c.Parent then 1 else 0) + (if w.d.Parent then 1 else 0)
		n += (if w.e.Parent then 1 else 0) + (if w.f.Parent then 1 else 0)
		n += (if w.sourceA.Parent then 1 else 0) + (if w.sourceB.Parent then 1 else 0) + (if w.sourceC.Parent then 1 else 0)
		for _, fx in w.fx do
			n += (if fx.trail.Parent then 1 else 0)
				+ (if fx.diffuse.Parent then 1 else 0)
				+ (if fx.stylized.Parent then 1 else 0)
		end
		local g = w.ground
		for _, m in { g.flat, g.trench, g.gravel } do
			for _, trail in m.trails do
				n += if trail.Parent then 1 else 0
			end
		end
		for _, inst in { g.clippings.emitter, g.dirt.emitter, g.dust.emitter } do
			n += if (inst :: Instance).Parent then 1 else 0
		end
	end
	return n
end

return Wheels
