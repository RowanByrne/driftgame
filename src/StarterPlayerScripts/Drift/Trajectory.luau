--!nonstrict
-- Trajectory: where the car will go if the finger stays exactly where it is.
--
-- A DEV TOOL, not a player feature. Off by default (`Config.Drift.TrajectoryLine`), built
-- only when it is switched on, and destroyed again when it is switched off.
--
-- THE LINE IS NOT AN APPROXIMATION OF THE CAR -- IT IS THE CAR. `Drift/Model.step` is
-- pure maths plus two injected world queries, so the prediction is the real model run
-- forward from a COPY of the live state with the player's current input held constant.
-- Same code path, same numbers, same active car: switch car with F4 and the line changes
-- with it, for free, because `Config.Drift` resolves the car's numbers through
-- `Shared/Cars` on every read (Config/Drift, "the active car").
--
-- THE COPY IS THE ONE THING THAT MUST NOT BE GOT WRONG. Predicting must not touch the car
-- the player is driving. `Model.step` MUTATES the state it is handed -- that is its
-- contract -- so a shared table here would mean the act of drawing the line drove the car,
-- and the bug would look like the physics being haunted. `copyState` copies every nested
-- table as well, and `TrajectoryTests` checks that a drive with the line on and a drive
-- with it off end at the same point to a thousandth of a stud.
--
-- THE COST, AND THE THREE TRADES THAT PAY FOR IT. Ten car lengths is about 166 studs; at
-- 100 studs/s that is 1.7 s of simulation, which at the model's own 1/120 step would be
-- ~200 steps EVERY FRAME, each wanting four ground raycasts -- ~800 rays a frame, more
-- than the game itself costs. So:
--
--   1. A COARSER STEP (`TrajectoryStep`, 1/30 by default). The line only has to look
--      right, not be exact to a thousandth. Measured, the coarse step costs under a stud
--      of deviation over the whole line.
--   2. A CHEAPER WORLD. By default (`TrajectoryFlat`) the prediction runs against
--      `World.flat` at the car's own current ground height: a plane, no raycasts, no
--      walls. Honest and nearly free -- AND IT IS A TRADE, NOT A BUG: over a crest, down
--      a ramp or into a wall the line is wrong, because the plane does not know they are
--      there. Set `TrajectoryFlat = false` to predict against the live Workspace and pay
--      four rays per step for a line that follows the ground.
--   3. PREDICTING LESS OFTEN THAN EVERY FRAME (`TrajectoryHz`, 0 means every frame). The
--      drawn line is left alone between predictions. Measured it is cheap enough to run
--      every frame, so 0 is the default and this is the dial if that ever stops being
--      true.
--
-- THE LINE FADES ALONG ITSELF, not by distance from the camera: solid at the car, gone
-- at the far end, so the end of the prediction reads as "this is where it ends" rather
-- than as a line that was cut off. The ramp HOLDS near-solid over the first stretch and
-- then falls away on a smoothstep, which has no slope at either end: no kink where the
-- fade starts, and it settles into invisible rather than hitting it. It costs nothing
-- extra -- one number per segment, written when the segment is placed.
--
-- The line is drawn as a pool of thin anchored parts that is REUSED, never rebuilt: parts
-- are created once, up to `TrajectoryMaxSegments`, and spare ones are made invisible
-- rather than destroyed. They live in their own folder in Workspace, NEVER inside
-- `Workspace.Cars` where the ground rays or the car-claiming logic would find them, and
-- they are `CanQuery = false` so no raycast anywhere can see them either.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Model = require(script.Parent.Model)
local World = require(script.Parent.World)

local Trajectory = {}
Trajectory.__index = Trajectory

local TOGGLE_ACTION = "DriftTrajectoryToggle"

-- A deep copy of a simulation state. `Model.step` mutates what it is handed, so this is
-- what keeps the player's car out of the prediction (see the header). Every value in a
-- State is a number, a boolean, a Vector3 or a table of them, so one level of `clone` per
-- nested table is a full copy.
local function copyState(s: Model.State): Model.State
	local out = table.clone(s)
	for key, value in out do
		if type(value) == "table" then
			out[key] = table.clone(value)
		end
	end
	return out
end

-- The plane the cheap prediction runs on: the ground the car is standing on now, or the
-- height its own ride height implies if no ray has found ground yet.
local function groundUnder(s: Model.State): number
	return s.groundY or (s.position.Y - Config.Drift.RideHeight)
end

export type Prediction = {
	points: { Vector3 },
	length: number, -- studs of path walked
	steps: number,
	seconds: number, -- simulated
	endSpeed: number,
	stopped: boolean, -- it ran out of speed rather than out of distance
}

-- WHERE THE CAR GOES FROM HERE, with `input` held constant. Pure: it never touches `s`.
--
-- Walked by DISTANCE, not by time, because the user asked for ten car lengths and the
-- car's speed varies: a fixed number of seconds would be a line that grows and shrinks
-- with the throttle. It stops early if the car stops.
--
-- `opts`: { step, world, lengths, spacing, maxSteps, minSpeed } -- all optional, and all
-- of them default to their `Config.Drift.Trajectory*` number.
function Trajectory.predict(s: Model.State, input: Model.Input, opts): Prediction
	local C = Config.Drift
	opts = opts or {}

	local step = math.max(opts.step or C.TrajectoryStep, 1e-3)
	local spacing = math.max(opts.spacing or C.TrajectoryPointSpacing, 0.1)
	local maxSteps = math.max(opts.maxSteps or C.TrajectoryMaxSteps, 1)
	local minSpeed = opts.minSpeed or C.TrajectoryMinSpeed
	local lengths = opts.lengths or C.TrajectoryCarLengths
	-- Ten CAR lengths, and `BodyLength` is the active car's, so a longer car gets a longer
	-- line without a number here knowing it happened.
	local target = lengths * C.BodyLength
	local world = opts.world or World.flat(groundUnder(s))

	-- The copy, and a copy of the input too: holding the player's own table would let a
	-- later input edit reach into a prediction that is already running.
	local sim = copyState(s)
	local held: Model.Input = { steer = input.steer or 0, handbrake = input.handbrake == true }

	local points: { Vector3 } = { sim.position }
	local last = sim.position
	local travelled, sinceMark = 0, 0
	local steps, stopped = 0, false

	while steps < maxSteps do
		Model.step(sim, held, step, world)
		steps += 1
		local moved = (sim.position - last).Magnitude
		last = sim.position
		travelled += moved
		sinceMark += moved
		if sinceMark >= spacing then
			points[#points + 1] = sim.position
			sinceMark = 0
		end
		if travelled >= target then
			break
		end
		if Model.speed(sim) < minSpeed then
			stopped = true
			break
		end
	end

	-- The tail end, so the line always reaches where the walk actually stopped.
	if sinceMark > 1e-3 then
		points[#points + 1] = sim.position
	end

	return {
		points = points,
		length = travelled,
		steps = steps,
		seconds = steps * step,
		endSpeed = Model.speed(sim),
		stopped = stopped,
	}
end

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

function Trajectory.new()
	local self = setmetatable({}, Trajectory)
	self.enabled = false
	self.folder = nil :: Folder?
	self.parts = {} :: { BasePart }
	self.shown = 0
	self.clock = 0
	self.lastMs = 0
	self.avgMs = 0
	self.worstMs = 0
	self.predictions = 0
	self.last = nil :: Prediction?
	self.world = nil :: Model.World? -- the live world, when `TrajectoryFlat` is off
	return self
end

-- The live Workspace queries, for the honest-but-expensive mode. Handed in by
-- DriftController, which already owns one.
function Trajectory:SetWorld(world)
	self.world = world
end

function Trajectory:_folder(): Folder
	if self.folder and self.folder.Parent then
		return self.folder
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.Drift.TrajectoryFolder
	folder.Parent = workspace
	self.folder = folder
	return folder
end

-- One reused segment. Created once, then only ever written to.
function Trajectory:_segment(i: number): BasePart
	local part = self.parts[i]
	if part and part.Parent then
		return part
	end
	local C = Config.Drift
	part = Instance.new("Part")
	part.Name = ("Seg%03d"):format(i)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- so no ground ray, sweep or bounds query can ever see it
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = C.TrajectoryColour
	part.Transparency = C.TrajectoryTransparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(C.TrajectoryWidth, C.TrajectoryWidth, 1)
	part.Parent = self:_folder()
	self.parts[i] = part
	return part
end

-- How transparent segment `i` of `count` should be: `TrajectoryTransparency` (`near`) over
-- the first `TrajectoryFadeHold` of the path, then a smoothstep out to `TrajectoryFadeEnd`
-- at the tip. All three numbers are Config's.
local function fadeAt(i: number, count: number, near: number): number
	if count < 2 then
		return near
	end
	-- the segment's CENTRE along the path, so the first segment is not already fading
	local t = (i - 0.5) / count
	if t <= Config.Drift.TrajectoryFadeHold then
		return near
	end
	local f = math.clamp((t - Config.Drift.TrajectoryFadeHold) / (1 - Config.Drift.TrajectoryFadeHold), 0, 1) ^ Config.Drift.TrajectoryFadeShape
	local eased = f * f * (3 - 2 * f) -- smoothstep: flat at both ends, no kink, no wall
	return near + (Config.Drift.TrajectoryFadeEnd - near) * eased
end

function Trajectory:_draw(points: { Vector3 })
	local C = Config.Drift
	local lift = Vector3.yAxis * C.TrajectoryLift
	local used = 0
	-- Counted first, so the fade knows how long the line is before it places the first
	-- segment. A pass over points, not over parts: no instance is touched.
	local total = 0
	for i = 2, math.min(#points, C.TrajectoryMaxSegments + 1) do
		if (points[i] - points[i - 1]).Magnitude > 1e-3 then
			total += 1
		end
	end
	for i = 2, math.min(#points, C.TrajectoryMaxSegments + 1) do
		local a, b = points[i - 1] + lift, points[i] + lift
		local delta = b - a
		local len = delta.Magnitude
		if len > 1e-3 then
			used += 1
			local part = self:_segment(used)
			part.Size = Vector3.new(C.TrajectoryWidth, C.TrajectoryWidth, len)
			part.CFrame = CFrame.lookAt(a + delta * 0.5, b)
			part.Transparency = fadeAt(used, total, C.TrajectoryTransparency)
		end
	end
	-- Spare segments are HIDDEN, not destroyed: the pool is the whole point.
	for i = used + 1, #self.parts do
		local part = self.parts[i]
		if part and part.Parent then
			part.Transparency = 1
		end
	end
	self.shown = used
end

-- Called once a frame by DriftController while the line is on. `state` is the live
-- simulation state and `input` is this frame's finger.
function Trajectory:Update(state: Model.State?, input: Model.Input?, dt: number)
	if not self.enabled then
		return
	end
	if not state or not input then
		self:_draw({})
		return
	end

	local C = Config.Drift
	local hz = C.TrajectoryHz
	if hz > 0 then
		self.clock += dt
		if self.clock < 1 / hz then
			return -- the drawn line is left where it is between predictions
		end
		self.clock = 0
	end

	local began = os.clock()
	local world = if C.TrajectoryFlat then nil else self.world
	local prediction = Trajectory.predict(state, input, { world = world })
	self:_draw(prediction.points)
	local ms = (os.clock() - began) * 1000

	self.last = prediction
	self.predictions += 1
	self.lastMs = ms
	self.worstMs = math.max(self.worstMs, ms)
	-- An exponential mean, so the number in the readout is this second's cost and not the
	-- average of everything since the place loaded.
	self.avgMs = if self.predictions == 1 then ms else self.avgMs + (ms - self.avgMs) * 0.05
end

function Trajectory:SetEnabled(on: boolean): boolean
	on = on == true
	if on == self.enabled then
		return self.enabled
	end
	self.enabled = on
	if not on then
		-- NOTHING LEFT BEHIND: the parts, the folder and the measurements all go.
		if self.folder then
			self.folder:Destroy()
		end
		self.folder = nil
		self.parts = {}
		self.shown = 0
		self.last = nil
		self.clock = 0
		self.predictions = 0
		self.lastMs, self.avgMs, self.worstMs = 0, 0, 0
	end
	return self.enabled
end

function Trajectory:Toggle(): boolean
	return self:SetEnabled(not self.enabled)
end

-- F6 (or gamepad DPad left) turns the line on and off in a playtest, so it can be reached
-- without editing the config. Bound next to the readout's own F3/F4/F5 (Drift/DebugHud).
function Trajectory:BindToggle()
	ContextActionService:BindAction(TOGGLE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:Toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F6, Enum.KeyCode.DPadLeft)
end

function Trajectory:Destroy()
	ContextActionService:UnbindAction(TOGGLE_ACTION)
	self:SetEnabled(false)
end

-- The drawn transparency of every visible segment, near end to far end. The fade is a
-- look, and this is how a look is proved with numbers rather than a screenshot.
function Trajectory:SegmentTransparencies(): { number }
	local out = {}
	for i = 1, self.shown do
		local part = self.parts[i]
		if part and part.Parent then
			out[i] = part.Transparency
		end
	end
	return out
end

-- What it is costing and what it drew, for the tests and for an agent playtest.
function Trajectory:DebugState()
	local last = self.last
	return {
		enabled = self.enabled,
		flat = Config.Drift.TrajectoryFlat,
		hz = Config.Drift.TrajectoryHz,
		stepSeconds = Config.Drift.TrajectoryStep,
		carLengths = Config.Drift.TrajectoryCarLengths,
		targetStuds = Config.Drift.TrajectoryCarLengths * Config.Drift.BodyLength,
		points = if last then #last.points else 0,
		segments = self.shown,
		parts = #self.parts,
		pathLength = if last then last.length else 0,
		simSeconds = if last then last.seconds else 0,
		simSteps = if last then last.steps else 0,
		endSpeed = if last then last.endSpeed else 0,
		stoppedEarly = if last then last.stopped else false,
		predictions = self.predictions,
		lastMs = self.lastMs,
		avgMs = self.avgMs,
		worstMs = self.worstMs,
		folder = if self.folder then self.folder:GetFullName() else nil,
		-- near end to far end: the fade curve, for the readout and for a test
		transparencies = self:SegmentTransparencies(),
	}
end

return Trajectory
