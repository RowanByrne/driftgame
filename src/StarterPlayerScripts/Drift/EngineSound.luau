--!strict
-- EngineSound: the engine note, following a fake engine (docs/game/features/engine-sound.md,
-- docs/game/features/car-fx.md "Engine sound").
--
-- THE RPM IS `Drift/Engine`'s. This module owns the sound and nothing else: each frame it
-- feeds the drift model's state to the engine, and turns the engine's rpm and load into
-- what the `Sound` plays. The physics still has no engine and never reads any of this.
--
-- FOR NOW, ONE CLIP. Until the layered loops are picked (T-123's third step), the rpm is
-- heard through today's single clip: its `PlaybackSpeed` is the rpm's share of the range,
-- `MinPitch` at idle to `MaxPitch` at the redline, and the load moves the volume between
-- `OffLoadVolume` and full. NO LERP ON THE PITCH: the engine's rpm already has inertia
-- (`RevUpRate`, `RevDownRate`), and a second smoothing on top would blur the limiter's
-- stutter into a hum.
--
-- NOTHING IS CREATED OR DESTROYED WHILE DRIVING. One `Sound`, made once when the rig is
-- caught, and written to for ever after. `Update` holds no table and makes no instance.
--
-- THE CLIENT ONLY, and the local car only. No remote, no packet field, no server
-- instance; another player's car is silent this round (features/car-fx.md "Server and
-- client").

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)
local Engine = require(script.Parent.Engine)

-- An agent's playtest makes no sound (docs/workflow/TESTING.md "Studio test kit"). Asked
-- ONCE, here, at client start. The LOGIC is unaffected: the rpm, the gear, the pitch and
-- the volume are computed and reported whether it is quiet or not, and only what reaches
-- the `Sound` is muted.
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
		engine: Engine.Engine,
		feed: Engine.Feed,
		pitch: number, -- what is on the sound now
		volume: number, -- what the module wants on it (before QUIET)
		maxStep: number, -- the largest single-frame change in pitch since `ResetMeasure`
	},
	EngineSound
))

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- The gearbox lives in `Drift/Engine` now; these stay so anything that asked here still can.
EngineSound.gearTops = Engine.gearTops
EngineSound.gearBottom = Engine.gearBottom
EngineSound.wanted = Engine.wanted

-- The clip's pitch for an rpm share (0 idle .. 1 redline).
function EngineSound.pitchForShare(share: number): number
	local E = Config.Fx.Engine
	return lerp(E.MinPitch, E.MaxPitch, math.clamp(share, 0, 1))
end

-- The clip's volume for a load (0 off throttle .. 1 on).
function EngineSound.volumeForLoad(load: number): number
	local E = Config.Fx.Engine
	return E.Volume * lerp(E.OffLoadVolume, 1, math.clamp(load, 0, 1))
end

function EngineSound.new(): EngineSound
	local self = setmetatable({
		body = nil,
		sound = nil,
		enabled = true,
		engine = Engine.new(),
		feed = Engine.newFeed(),
		pitch = Config.Fx.Engine.MinPitch,
		volume = 0,
		maxStep = 0,
	}, EngineSound) :: any
	return self
end

function EngineSound.Clear(self: EngineSound)
	if self.sound then
		self.sound:Destroy()
	end
	self.sound = nil
	self.body = nil
end

-- Build the one sound, once, for the car this rig holds. Called every frame and does
-- nothing at all once it has built for a body.
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
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = E.RollOffMin
	sound.RollOffMaxDistance = E.RollOffMax
	sound.PlaybackSpeed = self.pitch
	sound.Volume = 0
	sound.Parent = body
	if not QUIET then
		sound:Play()
	end
	self.sound = sound
	self.body = body
	return true
end

-- One frame. `state` nil means no car: the engine idles down and the note fades out.
function EngineSound.Update(self: EngineSound, state: DriftModel.State?, input: any, dt: number?)
	local step = math.max(dt or 0, 0)

	if state and self.enabled then
		Engine.feedFrom(state, input, self.feed)
		Engine.step(self.engine, self.feed, step)
		self.volume = EngineSound.volumeForLoad(self.engine.load)
	else
		-- No car, or switched off: the engine settles to idle and the note goes quiet.
		local feed = self.feed
		feed.speed, feed.slip, feed.drifting, feed.airborne = 0, 0, false, false
		feed.braking, feed.handbrake, feed.throttle = false, false, 0
		feed.topSpeed = Config.Drift.TopSpeed
		Engine.step(self.engine, feed, step)
		self.volume = 0
	end

	local before = self.pitch
	self.pitch = EngineSound.pitchForShare(Engine.rpmShare(self.engine))
	local moved = math.abs(self.pitch - before)
	if moved > self.maxStep then
		self.maxStep = moved
	end

	local sound = self.sound
	if not sound then
		return
	end
	if math.abs(sound.PlaybackSpeed - self.pitch) > 1e-5 then
		sound.PlaybackSpeed = self.pitch
	end
	local want = if QUIET then 0 else self.volume
	if math.abs(sound.Volume - want) > 1e-4 then
		sound.Volume = want
	end
end

-- The engine note on or off wholesale. It creates and destroys nothing: the sound keeps
-- playing at zero volume, because stopping and starting a loop is a click.
function EngineSound.SetEnabled(self: EngineSound, on: boolean): boolean
	self.enabled = on == true
	if self.sound and (QUIET or not self.enabled) then
		self.sound.Volume = 0
	end
	return self.enabled
end

-- Back to a standing start, for a spawn, a respawn or a teleport.
function EngineSound.Cut(self: EngineSound)
	Engine.reset(self.engine)
end

-- The largest single-frame change in pitch since this was last called, and the counter reset.
function EngineSound.ResetMeasure(self: EngineSound): number
	local was = self.maxStep
	self.maxStep = 0
	return was
end

function EngineSound.CountInstances(self: EngineSound): number
	return if self.sound and self.sound.Parent then 1 else 0
end

-- What the engine and the note are doing. Allocates; called by tests and by hand.
function EngineSound.DebugState(self: EngineSound, state: DriftModel.State?)
	local d = Engine.debug(self.engine)
	return {
		quiet = QUIET,
		enabled = self.enabled,
		attached = self.body ~= nil,
		instances = EngineSound.CountInstances(self),
		soundId = if self.sound then self.sound.SoundId else nil,
		playing = if self.sound then self.sound.IsPlaying else false,
		volume = self.volume,
		soundVolume = if self.sound then self.sound.Volume else 0,
		speed = if state then DriftModel.speed(state) else 0,
		airborne = if state then state.airborne else nil,
		pitch = self.pitch,
		playbackSpeed = if self.sound then self.sound.PlaybackSpeed else 0,
		maxStep = self.maxStep,
		rpm = d.rpm,
		target = d.target,
		gear = d.gear,
		load = d.load,
		inDrift = d.inDrift,
		cut = d.cut,
		cuts = d.cuts,
		shifts = d.shifts,
		upshifts = d.upshifts,
		downshifts = d.downshifts,
	}
end

return EngineSound
