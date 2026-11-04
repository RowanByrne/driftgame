--!strict
-- EngineSound: one looping clip, pitched by a gearbox that does not exist
-- (docs/game/features/car-fx.md "Engine sound: one loop, pitched by a gearbox that does
-- not exist").
--
-- THERE IS NO ENGINE AND THERE IS NO RPM. Not in this module, not in `Drift/Model`, not
-- anywhere in the game: the throttle is eased in over `Config.Drift.FullThrottleSeconds`
-- and is never a finger, so ROAD SPEED is the only thing there is to hear and road speed
-- is all this needs. One `Sound` plays for ever and its `PlaybackSpeed` is lerped between
-- `MinPitch` and `MaxPitch` across the current gear's speed band.
--
-- The gearbox exists only to decide which band:
--
--   * GEAR TOPS ARE A GEOMETRIC SERIES. With `GearCount` gears and a length multiplier
--     `m`, the first gear's band is `TopSpeed / sum(m^i)` wide and each gear after it is
--     `m` times longer than the one before. At 5 gears and m = 1.5 the divisor is
--     13.1875, so the active car's 179 studs/s tops out of first at about 13.6 and the
--     four tops are 13.6, 33.9, 64.5, 110.3 and 179.
--   * BANDS OVERLAP by `GearOverlap` either side, so a gear is not left until the speed
--     is clear of its band, and a shift needs `MinTimeInGear` since the last one. Between
--     them a car hovering on a shift point cannot machine-gun between two gears.
--   * PITCH IS LERPED TOWARD ITS TARGET AND NEVER SNAPPED, at `PitchLerpSpeed` per
--     second. THAT LERP IS THE WHOLE REASON A SHIFT SOUNDS LIKE A SHIFT: at the upshift
--     the target falls by 0.76 of a pitch (at the 1-2; less higher up), and the sound
--     slides down across the gap instead of stepping.
--   * AIRBORNE PITCHES STRAIGHT TO THE CEILING -- wheels off the ground, engine free.
--     The gearbox is left running on the car's real speed underneath it, so coming down
--     lands in the right gear rather than in the one it took off in.
--
-- NOTHING IS CREATED OR DESTROYED WHILE DRIVING. One `Sound`, made once when the rig is
-- caught, exactly as `Drift/Wheels`' sixteen are, and written to for ever after. `Update`
-- holds no table and makes no instance.
--
-- A SHIFT FIRES NOTHING. The reference raises an event here and the only thing listening
-- is its backfire, which the user decided this game is not having (AUDIO.md). `self.shifts`
-- counts them for the tests and that is all a shift is.
--
-- THE CLIENT ONLY, and the local car only. No remote, no packet field, no server
-- instance; another player's car is silent this round (features/car-fx.md "Server and
-- client").

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)

-- An agent's playtest makes no sound (docs/workflow/TESTING.md "Studio test kit"). Asked
-- ONCE, here, at client start -- which is exactly what `QuietPlay` measures: a client that
-- started within 60 s of the `__agent_play` marker. Asking it every frame would turn the
-- sound on in the middle of an agent's test as the window expired.
--
-- The LOGIC is unaffected: the pitch, the gear and the volume this module decides are
-- computed and reported whether it is quiet or not, and only what reaches the `Sound` is
-- muted. So an agent can measure the whole state machine in a silent playtest.
local QUIET = (function(): boolean
	local module = ReplicatedFirst:FindFirstChild("QuietPlay")
	if not module or not module:IsA("ModuleScript") then
		return false
	end
	local ok, quiet = pcall(function()
		return (require(module) :: any).isQuiet()
	end)
	return ok and quiet == true
end)()

local EngineSound = {}
EngineSound.__index = EngineSound

export type EngineSound = typeof(setmetatable(
	{} :: {
		body: BasePart?,
		sound: Sound?,
		enabled: boolean,
		tops: { number }, -- the gear tops, in studs/s. PRE-ALLOCATED and written in place
		topsFor: number, -- the `TopSpeed` `tops` was built for
		gear: number, -- 1 .. GearCount
		sinceShift: number, -- s since the last shift
		shifts: number, -- how many there have been, for the tests
		lastShiftSpeed: number, -- studs/s the last one happened at
		pitch: number, -- what is on the sound now
		target: number, -- what it is heading for
		maxStep: number, -- the largest single-frame change in pitch since `ResetMeasure`
	},
	EngineSound
))

local EPS = 1e-4

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--------------------------------------------------------------------------------
-- The gearbox, pure
--------------------------------------------------------------------------------

-- The gear tops, written INTO `out` rather than returned in a new table, because this is
-- re-run whenever the active car's `TopSpeed` changes and an allocation on a car switch is
-- an allocation this module does not need. Returns `out`.
--
-- `out[i]` is the speed gear `i` runs up to. `out[GearCount]` is `topSpeed` exactly.
function EngineSound.gearTops(topSpeed: number, out: { number }): { number }
	local E = Config.Fx.Engine
	local m = E.GearLengthMultiplier
	local n = E.GearCount

	local divisor = 0
	local term = 1
	for _ = 1, n do
		divisor += term
		term *= m
	end
	local first = topSpeed / math.max(divisor, EPS)

	local running = 0
	term = 1
	for i = 1, n do
		running += first * term
		out[i] = running
		term *= m
	end
	-- Floating point, and the last top is the one a test compares against `TopSpeed`.
	out[n] = topSpeed
	return out
end

-- The bottom of a gear's band: the top of the gear below it, and zero for first.
function EngineSound.gearBottom(tops: { number }, gear: number): number
	return if gear <= 1 then 0 else tops[gear - 1]
end

-- Which gear `speed` asks for, given the gear we are in. ONE STEP AT A TIME: a car dropped
-- from 150 studs/s to a standstill by a wall walks down the box over `MinTimeInGear` each,
-- which is what the reference does and what stops a shift being a jump of four bands.
--
-- The band a gear holds on to is its own band grown by `GearOverlap` EITHER SIDE, so the
-- gear is not left until the speed is properly clear of it. Nothing about the debounce is
-- in here: the caller owns the clock.
function EngineSound.wanted(tops: { number }, gear: number, speed: number): number
	local E = Config.Fx.Engine
	local n = E.GearCount
	gear = math.clamp(gear, 1, n)
	if speed > tops[gear] + E.GearOverlap and gear < n then
		return gear + 1
	end
	if speed < EngineSound.gearBottom(tops, gear) - E.GearOverlap and gear > 1 then
		return gear - 1
	end
	return gear
end

-- Where in its band this speed sits, 0 .. 1, and therefore the pitch. Clamped at both
-- ends: a car held against the overlap above a gear's top sits at `MaxPitch` until it
-- shifts, which is the hang before a shift and not a bug.
function EngineSound.pitchFor(tops: { number }, gear: number, speed: number): number
	local E = Config.Fx.Engine
	local bottom = EngineSound.gearBottom(tops, gear)
	local top = tops[math.clamp(gear, 1, E.GearCount)]
	local t = math.clamp((speed - bottom) / math.max(top - bottom, EPS), 0, 1)
	return lerp(E.MinPitch, E.MaxPitch, t)
end

--------------------------------------------------------------------------------
-- The rig
--------------------------------------------------------------------------------

function EngineSound.new(): EngineSound
	local self = setmetatable({
		body = nil,
		sound = nil,
		enabled = true,
		tops = {},
		topsFor = -1,
		gear = 1,
		sinceShift = 0,
		shifts = 0,
		lastShiftSpeed = 0,
		pitch = Config.Fx.Engine.MinPitch,
		target = Config.Fx.Engine.MinPitch,
		maxStep = 0,
	}, EngineSound) :: any
	EngineSound.gearTops(Config.Drift.TopSpeed, self.tops)
	self.topsFor = Config.Drift.TopSpeed
	return self
end

-- Throw away the sound this object made, if it is still in the world. Only ever reached
-- when the SERVER has handed this client a different car; in normal play the old body has
-- already been destroyed and taken the sound with it.
function EngineSound.Clear(self: EngineSound)
	if self.sound then
		self.sound:Destroy()
	end
	self.sound = nil
	self.body = nil
end

-- Build the one sound, once, for the car this rig holds. Called every frame and does
-- nothing at all once it has built for a body -- an identity test on one field, the same
-- shape `Drift/Wheels:Attach` uses.
function EngineSound.Attach(self: EngineSound, rig: any): boolean
	local body = rig and rig.body
	if body and self.body == body then
		return true
	end
	EngineSound.Clear(self)
	if not body then
		return false
	end

	local E = Config.Fx.Engine
	local sound = Instance.new("Sound")
	sound.Name = Config.Fx.Names.Engine
	sound.SoundId = E.SoundId
	sound.Looped = true
	-- 3D, and tapered rather than linear, so another player's car is heard WHERE IT IS.
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = E.RollOffMin
	sound.RollOffMaxDistance = E.RollOffMax
	sound.PlaybackSpeed = self.pitch
	sound.Volume = if QUIET then 0 else E.Volume
	sound.Parent = body
	if not QUIET then
		sound:Play()
	end
	self.sound = sound
	self.body = body
	return true
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

-- One frame. `input` is unused and is in the signature because every effect module in
-- `Drift/` takes `(state, input, dt)` and one shape is worth more than one saved argument.
function EngineSound.Update(self: EngineSound, state: DriftModel.State?, _input: any, dt: number?)
	local sound = self.sound
	if not sound then
		return
	end
	local E = Config.Fx.Engine
	local step = math.max(dt or 0, 0)

	-- The active car can change under us (`Shared/Cars`, an archetype switch), and its
	-- top speed is the whole of the gearbox. Rebuilt IN PLACE and only when it moves.
	local topSpeed = Config.Drift.TopSpeed
	if topSpeed ~= self.topsFor then
		EngineSound.gearTops(topSpeed, self.tops)
		self.topsFor = topSpeed
		self.gear = math.clamp(self.gear, 1, E.GearCount)
	end

	if state and self.enabled then
		local speed = DriftModel.speed(state)
		self.sinceShift += step

		-- The debounce. The gear the speed WANTS is worked out every frame; whether it is
		-- allowed yet is this clock's business alone.
		local wanted = EngineSound.wanted(self.tops, self.gear, speed)
		if wanted ~= self.gear and self.sinceShift >= E.MinTimeInGear then
			self.gear = wanted
			self.sinceShift = 0
			self.shifts += 1
			self.lastShiftSpeed = speed
		end

		self.target = if state.airborne then E.MaxPitch else EngineSound.pitchFor(self.tops, self.gear, speed)
	else
		-- No car, or switched off: the note falls to its floor rather than holding
		-- whatever it was at when the car went away.
		self.target = E.MinPitch
	end

	-- NEVER SNAPPED. `clamp` keeps a long frame -- the first few, while the place loads --
	-- from overshooting the target rather than reaching it.
	local before = self.pitch
	self.pitch += (self.target - self.pitch) * math.clamp(step * E.PitchLerpSpeed, 0, 1)
	local moved = math.abs(self.pitch - before)
	if moved > self.maxStep then
		self.maxStep = moved
	end
	if math.abs(sound.PlaybackSpeed - self.pitch) > 1e-5 then
		sound.PlaybackSpeed = self.pitch
	end
end

--------------------------------------------------------------------------------
-- Switches and the readout
--------------------------------------------------------------------------------

-- The engine note on or off wholesale, the same switch `Wheels:SetEnabled` is. It creates
-- and destroys nothing: the sound keeps playing at zero volume, because stopping and
-- starting a loop is a click.
function EngineSound.SetEnabled(self: EngineSound, on: boolean): boolean
	self.enabled = on == true
	if self.sound then
		self.sound.Volume = if QUIET or not self.enabled then 0 else Config.Fx.Engine.Volume
	end
	return self.enabled
end

-- The gearbox put back to a standing start. Called when the car JUMPS -- a spawn, a
-- respawn, a teleport -- so the box does not walk down five gears, half a second each,
-- from wherever the car was before it was picked up and put down.
function EngineSound.Cut(self: EngineSound)
	self.gear = 1
	self.sinceShift = Config.Fx.Engine.MinTimeInGear -- free to shift at once
	self.target = Config.Fx.Engine.MinPitch
end

-- The largest single-frame change in pitch since this was last called, and the counter
-- reset. The number the "pitch is continuous" check reads: it must stay under
-- `(MaxPitch - MinPitch) * PitchLerpSpeed * dt`, and a jump means the lerp is not doing
-- its job.
function EngineSound.ResetMeasure(self: EngineSound): number
	local was = self.maxStep
	self.maxStep = 0
	return was
end

function EngineSound.CountInstances(self: EngineSound): number
	return if self.sound and self.sound.Parent then 1 else 0
end

-- What the gearbox is doing and why. Allocates, and is called by tests and by hand --
-- never by `Update`.
function EngineSound.DebugState(self: EngineSound, state: DriftModel.State?)
	local E = Config.Fx.Engine
	local speed = if state then DriftModel.speed(state) else 0
	local tops = {}
	for i, v in self.tops do
		tops[i] = v
	end
	return {
		quiet = QUIET, -- true means the `Sound` is muted; everything below is live anyway
		enabled = self.enabled,
		attached = self.body ~= nil,
		instances = EngineSound.CountInstances(self),
		soundId = if self.sound then self.sound.SoundId else nil,
		playing = if self.sound then self.sound.IsPlaying else false,
		volume = if self.sound then self.sound.Volume else 0,
		loopSeconds = if self.sound then self.sound.TimeLength else 0,
		topSpeed = self.topsFor,
		gearTops = tops,
		gear = self.gear,
		gearBottom = EngineSound.gearBottom(self.tops, self.gear),
		gearTop = self.tops[math.clamp(self.gear, 1, E.GearCount)],
		wanted = EngineSound.wanted(self.tops, self.gear, speed),
		sinceShift = self.sinceShift,
		shifts = self.shifts,
		lastShiftSpeed = self.lastShiftSpeed,
		speed = speed,
		airborne = if state then state.airborne else nil,
		pitch = self.pitch, -- what is on the sound
		target = self.target,
		playbackSpeed = if self.sound then self.sound.PlaybackSpeed else 0,
		maxStep = self.maxStep,
	}
end

return EngineSound
