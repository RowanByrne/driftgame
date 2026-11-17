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
-- ------------------------------------- the marks are ribbons now (T-265, T-269)
--
-- Every mark is a `Drift/GroundMarks` mesh ribbon, not a Trail: the grass and mud on the
-- drawn ground (T-265), and the rubber on the tarmac and the scuff on its gravel on the spline
-- road's own surface (T-269). A ribbon's darkness is per section, so it CAN follow how hard a
-- wheel is marking: the rubber's is its slip and its load (`markIntensity`, `loadShare`),
-- which a trail could never do, for the reason below.
--
-- ------------------------------------- ONE SHADE OF LINE: the ramp that was built on trails
--
-- Until T-269 a mark was one `Trail` per wheel per surface at ONE fixed darkness. The story
-- of why a trail could not carry a darkness ramp is worth keeping.
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
-- The grass marks are not trails either: they are `Drift/GroundMarks`, a lit mesh ribbon laid on
-- the drawn ground, one per wheel, with a shaped cross-section, a streak texture made in code,
-- soft ends and an age. A first build of three trails side by side was sent back by the user
-- as "kinda cheap" (flat bands, hard stepped corners, black at night); the ribbon's header has
-- why each of those happened and what replaced it. This module still decides WHEN a wheel
-- marks grass and WHICH look (the T-205 green-or-brown hysteresis), and hands the ribbon the
-- contact, the ground's up, the T-207 width share and the drawn ground (`Drift/GroundMeshView`,
-- passed into `Update`), which the ribbon's points are put on and take their colour from.
--
-- NOTHING IS CREATED OR DESTROYED WHILE DRIVING. 50 instances per car at one smoking
-- surface -- 4 wheels x (2 smoke ParticleEmitters, 4 off-road ParticleEmitters and 3 emitter
-- anchors), the grass ribbon's strips (two MeshParts a wheel), the rubber ribbon's (one a
-- wheel) and their two folders -- built once and switched or rewritten in place for ever
-- after. It was 20 before T-188, 64 before T-265, 88 with T-265's trail ruts, 57 with its
-- ribbon and the trails still on the tarmac.
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
local Debris = require(script.Parent.Debris)
local DriftModel = require(script.Parent.Model)
local GroundMarks = require(script.Parent.GroundMarks)
local Suspension = require(script.Parent.Suspension)

local Wheels = {}
Wheels.__index = Wheels

-- One smoking surface's smoke on one wheel. `smoking` (the two emitters), `diffuseRate` and
-- `stylizedRate` are what was last WRITTEN, so a frame that changes nothing writes nothing.
-- (Its mark is the rubber ribbon's since T-269.)
type SurfaceFx = {
	surface: string,
	diffuse: ParticleEmitter,
	stylized: ParticleEmitter,
	smoking: boolean,
	diffuseRate: number,
	stylizedRate: number,
}

-- One debris emitter, with what was last written to it.
type KickFx = { emitter: ParticleEmitter, on: boolean, rate: number }

-- The off-road layer on one wheel (T-188, `Config.Fx.Ground`): the three debris emitters.
-- Its marks are the ribbons'.
type GroundFx = {
	clippings: KickFx, -- the fine spray of grass (T-283)
	dust: KickFx,
	spray: KickFx, -- the soft billows on grass (T-279)
}

type WheelFx = {
	name: string,
	index: number, -- into `state.wheelsDown`: FL, FR, RL, RR
	front: boolean,
	sourceA: Attachment, -- fixed diffuse smoke / dust source, independent of mark span
	sourceB: Attachment, -- fixed stylized smoke source
	sourceC: Attachment, -- fixed clippings / dirt source
	previousPatch: Vector3?, -- rendered contact centre last frame, including yaw / substep
	span: Vector3?, -- world cross-track axis; keep endpoint ordering continuous
	ratio: number, -- the T-207 width share this frame
	markA: Vector3, -- this frame's mark ends across the path, world: the T-207 geometry
	markB: Vector3,
	patchA: Vector3, -- the FLAT contact patch, in the car's own frame, before the lean
	patchB: Vector3,
	patchC: Vector3, -- where the clippings and dirt are thrown from, in the car's frame
	heat: number, -- 0..1, this wheel's own
	marking: boolean, -- the gates said emit last frame: the slip gate's hysteresis
	intensity: number, -- how hard it lays rubber, 0..1, eased (T-269)
	-- How much of each surface's effect this wheel is showing, 0..1, each walked toward 1
	-- on its own surface and 0 off it over `Ground.FadeSeconds` (T-188). Held in the air.
	mixSmoke: number,
	mixGrass: number,
	mixGravel: number,
	smokeSurface: string, -- the smoking surface the smoke is fading from or to
	trench: boolean, -- past the trench threshold, with its hysteresis
	fx: { SurfaceFx },
	ground: GroundFx,
	clodDue: number, -- 3D clods owed and not yet thrown (T-283)
}

export type Wheels = typeof(setmetatable(
	{} :: {
		body: BasePart?,
		wheels: { WheelFx },
		enabled: boolean,
		built: number, -- instances this object made for the body it holds
		marks: GroundMarks.GroundMarks, -- the grass ribbon (T-265), built once, in the world
		rubber: GroundMarks.GroundMarks, -- the tarmac and gravel ribbon (T-269), likewise
		-- What the ribbon has cost since `new`: frames it did work in, and the seconds spent
		-- there (its ground lookups included). Read by `DebugState`.
		marksFrames: number,
		marksSeconds: number,
		debris: any, -- the 3D clods' pool (`Drift/Debris`, T-283)
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
-- How hard a wheel marks the tarmac (T-269), pure
--------------------------------------------------------------------------------

-- Each wheel's share of the load, 0..1: 0.5 at the four wheels' average suspension travel,
-- toward 1 the further it is pressed up past it (`Marks.Ribbon.LoadSpread` studs is all of
-- it), toward 0 the more it hangs. In a drift the outside wheels are pressed hardest.
function Wheels.loadShare(state: DriftModel.State, index: number): number
	local travel = (state :: any).travel
	if type(travel) ~= "table" or #travel == 0 then
		return 0.5
	end
	local sum = 0
	for _, t in travel do
		sum += t
	end
	local mean = sum / #travel
	local mine = travel[index] or mean
	return math.clamp(0.5 + 0.5 * (mine - mean) / math.max(Config.Fx.Marks.Ribbon.LoadSpread, 1e-4), 0, 1)
end

-- How strongly a wheel lays rubber, 0..1: its slip past its own threshold (the fronts'
-- `Gates.MaxSteerDegrees`, the rears' none), `MinIntensity` at the first degree and all of
-- it `IntensitySlipDegrees` past; at least `HandbrakeIntensity` on the handbrake; then up or
-- down by its load, so the wheel pressed hardest into the road leaves the darkest rubber.
function Wheels.markIntensity(slipDeg: number, front: boolean, handbrake: boolean, load: number): number
	local R = Config.Fx.Marks.Ribbon
	local past = slipDeg - (if front then Config.Fx.Gates.MaxSteerDegrees else 0)
	local base = 0
	if past > 0 then
		local t = math.clamp(past / math.max(R.IntensitySlipDegrees, 1e-4), 0, 1)
		base = R.MinIntensity + (1 - R.MinIntensity) * t * t * (3 - 2 * t)
	end
	if handbrake then
		base = math.max(base, R.HandbrakeIntensity)
	end
	return math.clamp(base * (1 + R.LoadWeight * (2 * math.clamp(load, 0, 1) - 1)), 0, 1)
end

--------------------------------------------------------------------------------
-- The rig
--------------------------------------------------------------------------------

-- `marksParent` is where the two ribbons' folders go: Workspace unless said (the tests put
-- them in ServerStorage). Their meshes are made in their own thread, because making a mesh
-- yields; until they are ready, nothing marks (`Ready`).
function Wheels.new(marksParent: Instance?): Wheels
	local marks = GroundMarks.new(GroundMarks.grassSpec())
	local rubber = GroundMarks.new(GroundMarks.rubberSpec())
	task.spawn(function()
		GroundMarks.Build(rubber, marksParent)
		GroundMarks.Build(marks, marksParent)
	end)
	-- The mud's 3D clods (T-283): a pool of built-in wedge parts, made now.
	local debris = Debris.new(marksParent)
	Debris.Build(debris)
	return setmetatable({
		body = nil,
		wheels = {},
		enabled = true,
		built = 0,
		marks = marks,
		rubber = rubber,
		marksFrames = 0,
		marksSeconds = 0,
		debris = debris,
	}, Wheels) :: any
end

-- Whether both ribbons have been built (false while they are being made, or if one failed:
-- its `failed` says why).
function Wheels.Ready(self: Wheels): boolean
	return self.marks.ready and self.rubber.ready
end

-- Instances one wheel carries: 2 smoke emitters per smoking surface, the 3 off-road emitters
-- (the grass's fine spray and the gravel dust, T-188; the grass's earthy cloud, T-279; the
-- mud is 3D clods since T-283, `Drift/Debris`) and 3 fixed emitter anchors (T-207). 8 at one
-- smoking surface. Its marks are the ribbons' (T-265, T-269), not the wheel's.
function Wheels.perWheel(): number
	return #Config.Fx.Built * 2 + 3 + 3
end

-- And a car: its four wheels; the grass ribbon, a strip a wheel of two MeshParts (T-265);
-- the rubber ribbon, a strip a wheel of one (T-269); and their two folders. 46. (The 3D
-- clods' pool is the client's, not the car's: `Drift/Debris`.)
function Wheels.perCar(): number
	return #CarModel.WHEEL_NAMES * Wheels.perWheel()
		+ Config.Fx.Ground.Ribbon.Wheels * 2
		+ Config.Fx.Marks.Ribbon.Wheels
		+ 2
end

local function wheelIndex(name: string): number?
	for i, n in CarModel.WHEEL_NAMES do
		if n == name then
			return i
		end
	end
	return nil
end

-- Every emitter shares a builder: `S` is its table in `Config.Fx` (`Smoke`, `Stylized`, or
-- one of `Ground`'s). Each is drawn from one painted sheet, a random still frame a particle,
-- under the one lighting rule (T-279).
local function dress(e: ParticleEmitter, colour: Color3, S: any)
	local F = Config.Fx
	local sheet = F.Sheets[S.Sheet]
	e.Texture = sheet.Texture
	e.FlipbookLayout = sheet.Layout
	e.FlipbookMode = F.Flipbook.Mode
	e.FlipbookFramerate = NumberRange.new(F.Flipbook.Framerate)
	e.FlipbookStartRandom = F.Flipbook.StartRandom
	e.Orientation = S.Orientation
	e.ZOffset = S.ZOffset
	e.Squash = NumberSequence.new(S.Squash or 0)
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
	-- `Instance.new` makes LightInfluence 0 (Studio makes it 1): always set it.
	e.LightEmission = S.LightEmission or F.Light.Emission
	e.LightInfluence = F.Light.Influence
end

local function makeEmitter(fullName: string, colour: Color3, S: any, at: Attachment): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = fullName
	dress(e, colour, S)
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
			fx.diffuse:Destroy()
			fx.stylized:Destroy()
		end
		local g = w.ground
		for _, k in { g.clippings, g.dust, g.spray } do
			k.emitter:Destroy()
		end
		w.sourceA:Destroy()
		w.sourceB:Destroy()
		w.sourceC:Destroy()
	end
	table.clear(self.wheels)
	self.body = nil
	self.built = 0
	Debris.Clear(self.debris)
	-- The ribbons are the world's, not the car's: they stay built, but their marks go.
	for _, ribbon in { self.marks, self.rubber } do
		if ribbon.ready then
			GroundMarks.Clear(ribbon)
		end
	end
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
		-- centre, so the road is one radius below it; the smoke's sources sit `Marks.Lift`
		-- over it. The body's lean is cancelled against these every frame -- see the header.
		local patch = wheel.offset - Vector3.new(0, radius - F.Marks.Lift, 0)
		local patchA = patch - Vector3.new(half, 0, 0)
		local patchB = patch + Vector3.new(half, 0, 0)

		-- The particle sources, at fixed places off the contact (T-207): the diffuse smoke
		-- and the dust straight up from the left; the stylized smoke from the right, tilted
		-- back; the clippings and dirt from `DebrisOffset` left, thrown back (T-188).
		local function source(fullName: string, at: Vector3, tilt: number): Attachment
			local anchor = Instance.new("Attachment")
			anchor.Name = fullName
			anchor.Position = at
			anchor.Orientation = Vector3.new(tilt, 0, 0)
			anchor.Parent = body
			return anchor
		end
		local G = F.Ground
		local patchC = patch - Vector3.new(G.Grass.DebrisOffset, 0, 0)
		local sourceA = source(string.format(F.Names.Attachment, name, "L") .. "_Emitter", patchA, 0)
		local sourceB = source(string.format(F.Names.Attachment, name, "R") .. "_Emitter", patchB, F.Stylized.EmitAngleDegrees)
		local sourceC = source(string.format(F.Names.TrenchAttachment, name, "L") .. "_Emitter", patchC, G.Grass.KickAngleDegrees)

		local fx: { SurfaceFx } = {}
		for _, surface in F.Built do
			local look = F.Surfaces[surface] or F.Surfaces[F.Default]
			table.insert(fx, {
				surface = surface,
				diffuse = makeEmitter(string.format(F.Names.Emitter, name, surface), look.SmokeColour, F.Smoke, sourceA),
				stylized = makeEmitter(string.format(F.Names.Stylized, name, surface), look.PuffColour, F.Stylized, sourceB),
				smoking = false,
				diffuseRate = 0,
				stylizedRate = 0,
			})
		end

		local function kick(kind: string, S: any, at: Attachment): KickFx
			return { emitter = makeEmitter(string.format(F.Names.GroundEmitter, name, kind), S.Colour, S, at), on = false, rate = 0 }
		end
		local ground: GroundFx = {
			clippings = kick("grass", G.Grass.Clippings, sourceC),
			dust = kick("dust", G.Gravel.Dust, sourceA),
			spray = kick("spray", G.Grass.Spray, sourceA),
		}

		table.insert(self.wheels, {
			name = name,
			index = index,
			front = CarModel.isFrontWheel(name),
			sourceA = sourceA,
			sourceB = sourceB,
			sourceC = sourceC,
			previousPatch = nil,
			span = nil,
			ratio = 1,
			markA = Vector3.zero,
			markB = Vector3.zero,
			patchA = patchA,
			patchB = patchB,
			patchC = patchC,
			heat = 0,
			marking = false,
			intensity = 0,
			mixSmoke = 1,
			mixGrass = 0,
			mixGravel = 0,
			smokeSurface = F.Default,
			trench = false,
			fx = fx,
			ground = ground,
			clodDue = 0, -- clods owed but not yet thrown (T-283)
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

-- One wheel's smoke, this frame: the two emitters go on and off together, and only the
-- rates move, written only when they have.
local function write(fx: SurfaceFx, smoking: boolean, diffuseRate: number, stylizedRate: number)
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
	writeKick(g.clippings, 0)
	writeKick(g.dust, 0)
	writeKick(g.spray, 0)
end

-- Everything off and remembered as off. Used when the car jumps (spawn, respawn or
-- teleport), so no mark joins across the jump. The tyres are put back cold too.
function Wheels.Cut(self: Wheels)
	for _, w in self.wheels do
		w.heat = 0
		w.previousPatch = nil
		w.span = nil
		w.marking = false
		w.trench = false
		w.intensity = 0
		for _, fx in w.fx do
			write(fx, false, fx.diffuseRate, fx.stylizedRate)
		end
		groundOff(w.ground)
		w.clodDue = 0
	end
	Debris.Clear(self.debris)
	-- And every mark ends where it is: the next one must not join across a jump.
	GroundMarks.Cut(self.marks)
	GroundMarks.Cut(self.rubber)
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
-- marks are laid on it (T-265), and the rubber on its spline road's own surface (T-269).
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
	local drawn = if ground ~= nil and type(ground._drawnAt) == "function" then ground else nil
	local marks, rubber = self.marks, self.rubber
	local spent, worked = 0, false
	local ease = 1 - math.exp(-step / math.max(F.Marks.Ribbon.IntensitySeconds, 1e-4))

	local slipDeg = math.deg(math.abs(state.slip))
	local dirt = Wheels.dirtShare(slipDeg)
	local clipShare = 1 - (1 - G.Grass.ClippingsAtFullDirt) * dirt
	local clipBase = Wheels.kickRate(G.Grass.Clippings, slipDeg) * clipShare
	local clodBase = Wheels.kickRate(G.Chunks, slipDeg) * dirt
	local dustBase = Wheels.kickRate(G.Gravel.Dust, slipDeg)
	local sprayBase = Wheels.kickRate(G.Grass.Spray, slipDeg)

	for _, w in self.wheels do
		local down = state.wheelsDown[w.index] == true
		-- The slip gate is sticky once a wheel is marking (`Gates.StopSlipDegrees`): a
		-- gate that chatters is a hole in the mark, and this one was chattering. Kept on the
		-- wheel, so it holds across a change of surface (T-188).
		local emit, diffuseRate, _, _, handbrakeOk = Wheels.evaluate(state, handbrake, w.front, down, w.marking)
		w.marking = emit
		w.heat = Wheels.heatStep(w.heat, emit, slipSpeed, step)
		local surface = Wheels.surfaceOf(state, w.index, down)
		local grass, gravel = surface == "grass", surface == "gravel"
		local smokes = surface ~= nil and not grass and not gravel

		-- The mixes walk toward this wheel's surface (T-188). In the air there is no surface
		-- and they hold, so a wheel that lands where it took off picks up where it was.
		if surface then
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
		w.ratio = ratio
		w.markA = centre - span * (ratio * half)
		w.markB = centre + span * (ratio * half)
		w.sourceA.Position = unbody:PointToWorldSpace(w.patchA + lift)
		w.sourceB.Position = unbody:PointToWorldSpace(w.patchB + lift)
		w.sourceC.Position = unbody:PointToWorldSpace(w.patchC + lift)

		-- The marks: the tyre's contact on the ground (the patch less `Marks.Lift`), handed
		-- to the ribbon for the ground it is on. The rubber on the tarmac and the scuff on the
		-- gravel are one strip (T-269); the grass and mud another (T-265).
		local contact = road:PointToWorldSpace(patch - Vector3.new(0, F.Marks.Lift, 0))
		local onRoad = emit and (smokes or gravel)
		local target = if onRoad
			then Wheels.markIntensity(slipDeg, w.front, handbrakeOk, Wheels.loadShare(state, w.index))
			else 0
		w.intensity += (target - w.intensity) * ease
		if rubber.ready and (onRoad or rubber.strips[w.index] ~= nil and rubber.strips[w.index].on) then
			worked = true
			local t0 = os.clock()
			GroundMarks.Wheel(rubber, w.index, onRoad, contact, normal, span, ratio, gravel, drawn, step, w.intensity)
			spent += os.clock() - t0
		end
		if marks.ready and (emit and grass or marks.strips[w.index] ~= nil and marks.strips[w.index].on) then
			worked = true
			local t0 = os.clock()
			GroundMarks.Wheel(marks, w.index, emit and grass, contact, normal, span, ratio, w.trench, drawn, step)
			spent += os.clock() - t0
		end

		-- The smoke, scaled by the mix: it fades rather than cuts (T-188).
		local stylizedRate = Wheels.stylizedRate(w.heat)
		local mix = w.mixSmoke
		for _, fx in w.fx do
			write(fx, emit and mix > 0 and fx.surface == w.smokeSurface, diffuseRate * mix, stylizedRate * mix)
		end

		-- Off the road: the debris.
		local g = w.ground
		writeKick(g.clippings, if emit then clipBase * w.mixGrass else 0)
		if emit and w.mixGrass > 0 and clodBase > 0 then
			-- The mud: owed clods build up at the rate and are thrown whole (T-283).
			w.clodDue += clodBase * w.mixGrass * step
			if w.clodDue >= 1 then
				local from = w.sourceC.WorldCFrame
				while w.clodDue >= 1 do
					w.clodDue -= 1
					Debris.Spawn(self.debris, from, contact, normal, state.velocity)
				end
			end
		else
			w.clodDue = 0
		end
		writeKick(g.dust, if emit then dustBase * w.mixGravel else 0)
		writeKick(g.spray, if emit then sprayBase * w.mixGrass else 0)
	end

	-- The clods in the air fly on, and the ones on the ground sink, whatever the wheels do.
	Debris.Step(self.debris, step)

	-- The laid marks dry and fade with age, and go when their life is up.
	local t0 = os.clock()
	GroundMarks.Age(rubber, step)
	GroundMarks.Age(marks, step)
	if worked then
		self.marksFrames += 1
		self.marksSeconds += spent + os.clock() - t0
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
-- a huge number here leaves the whole run's marks on the road to be photographed. The
-- grass keeps its longer life, in proportion (T-265).
function Wheels.SetMarkSeconds(self: Wheels, seconds: number)
	GroundMarks.SetLife(self.rubber, seconds)
	GroundMarks.SetLife(self.marks, seconds * Config.Fx.Ground.MarkSeconds / math.max(Config.Fx.Marks.Seconds, 1e-4))
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
		-- The two ribbons: built or not, sections live and laid, ground lookups, mesh
		-- vertices, and each wheel's look, blend, width share and points found on the ground.
		marks = GroundMarks.DebugState(self.marks),
		rubber = GroundMarks.DebugState(self.rubber),
		-- Microseconds a frame the ribbons cost, over the frames a wheel was marking.
		marksMicros = if self.marksFrames > 0 then self.marksSeconds / self.marksFrames * 1e6 else 0,
		-- The mud's 3D clods (T-283): ready, pool, shapes, triangles, live, flying, spawned.
		debris = Debris.DebugState(self.debris),
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
		-- `lit` is how many marks this wheel is laying: 1 while it marks and 0 otherwise --
		-- and **0 WHILE `emitting` IS TRUE IS A GAP IN THE MARK**, the number the band ladder
		-- was removed over. Both ribbons count, so a double mark reports 2.
		local emitting, lit = w.marking, 0
		local rubberKind = GroundMarks.Kind(self.rubber, w.index)
		local kind = GroundMarks.Kind(self.marks, w.index)
		if rubberKind then
			lit += 1
		end
		if kind then
			lit += 1
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
			emitting = emitting, -- what the gates were set to last frame
			heat = w.heat,
			lit = lit, -- marks being laid: 1 while marking, 0 otherwise
			rate = diffuseRate,
			stylizedRate = Wheels.stylizedRate(w.heat),
			-- Off the road (T-188): the surface mixes, and what the instances are set to.
			smokeMix = w.mixSmoke,
			grassMix = w.mixGrass,
			gravelMix = w.mixGravel,
			trench = w.trench,
			smokeRate = smokeRate, -- the diffuse smoke's live Rate, 0 when off
			-- The marks being laid: rubber or scuff (T-269), flattened grass or rut (T-265).
			rubberMark = rubberKind == "rubber",
			gravelMark = rubberKind == "scuff",
			grassMark = kind == "flat",
			trenchMark = kind == "rut",
			intensity = w.intensity, -- how hard it lays rubber: slip and load (T-269)
			ratio = w.ratio, -- the T-207 width share
			-- The ribbons' newest section's points found on what they lie on: 3 while marking
			-- there, 0 off it.
			onGround = self.marks.strips[w.index] and self.marks.strips[w.index].snapped or 0,
			onRoad = self.rubber.strips[w.index] and self.rubber.strips[w.index].snapped or 0,
			clippingsRate = live(w.ground.clippings),
			clodRate = if w.mixGrass > 0 and emit then Wheels.kickRate(F.Ground.Chunks, math.deg(math.abs(state.slip)))
				* Wheels.dirtShare(math.deg(math.abs(state.slip))) * w.mixGrass else 0, -- clods a second (T-283)
			dustRate = live(w.ground.dust),
			sprayRate = live(w.ground.spray),
			-- How far the lean had to be pushed back on this wheel this frame, in studs.
			-- This IS the bug, in one number: before the fix the attachment sat here and
			-- the mark went with it, up to six tenths of a stud under a road with five
			-- hundredths of clearance.
			leanOffsetY = w.sourceA.Position.Y - w.patchA.Y,
			-- Undo the full body-local offset on the fixed source. Include suspension lift so
			-- pitch / roll do not fake a residual.
			patchResidualY = bodyLocal:PointToWorldSpace(w.sourceA.Position).Y
				- w.patchA.Y - (if state.wheelLift then state.wheelLift[w.index] or 0 else 0),
		})
	end
	return out
end

-- How many instances this object has on the car right now, counted rather than remembered.
-- The number the "it allocates nothing" check compares. (The ribbons' are in their own
-- folders, built once: `GroundMarks.DebugState`.)
function Wheels.CountInstances(self: Wheels): number
	local n = 0
	for _, w in self.wheels do
		n += (if w.sourceA.Parent then 1 else 0) + (if w.sourceB.Parent then 1 else 0) + (if w.sourceC.Parent then 1 else 0)
		for _, fx in w.fx do
			n += (if fx.diffuse.Parent then 1 else 0) + (if fx.stylized.Parent then 1 else 0)
		end
		local g = w.ground
		for _, inst in { g.clippings.emitter, g.dust.emitter, g.spray.emitter } do
			n += if (inst :: Instance).Parent then 1 else 0
		end
	end
	return n
end

return Wheels
