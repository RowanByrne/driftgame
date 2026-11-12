--!strict
-- EngineSound: the engine note, following a fake engine (docs/game/features/engine-sound.md,
-- docs/game/features/car-fx.md "Engine sound").
--
-- THE RPM IS `Drift/Engine`'s. This module owns the sound and nothing else: each frame it
-- feeds the drift model's state to the engine, and turns the engine's rpm and load into
-- what the sounds play. The physics still has no engine and never reads any of this.
--
-- TWO WAYS TO SOUND, and the config picks:
--
--   * LAYERED (`Config.Fx.Engine.Layers.SoundId` set). Our own synthesized loops at six rev
--     points, each on and off throttle: twelve `Sound`s, all slices of ONE uploaded file
--     (`PlaybackRegion` and `LoopRegion`). Each frame the two loops either side of the rpm
--     are crossfaded, equal power, by where the rpm sits between them on a log scale, and
--     each is pitched `rpm / its own rpm` -- never more than `MaxPitchShift` either way, so
--     no loop squeaks the way the one clip did at 2.2x. The load crossfades on and off
--     throttle, and a limiter cut ducks the lot to `LimiterDuck`: the stutter.
--   * ONE CLIP (`SoundId` nil, the fallback until the sheet is uploaded). Today's clip,
--     `MinPitch` at idle to `MaxPitch` at the redline, quieter off throttle.
--
-- NO SMOOTHING OF ITS OWN in either: the engine's rpm already has inertia, and a second
-- smoothing would blur the limiter's stutter into a hum.
--
-- NOTHING IS CREATED OR DESTROYED WHILE DRIVING, and NO LOOP IS EVER RESTARTED. Every
-- `Sound` is made once when the rig is caught and plays for ever; silence is a volume of 0,
-- so a loop's seam is never re-heard at the moment a layer fades in. `Update` holds no table
-- and makes no instance: the mix is written into two arrays made at `new`.
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
-- ONCE, here, at client start. The LOGIC is unaffected: the rpm, the gear, the pitches and
-- the volumes are computed and reported whether it is quiet or not, and only what reaches
-- the `Sound`s is muted.
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
		sound: Sound?, -- the one clip (fallback mode)
		layers: { Sound }, -- the twelve slices (layered mode): on, off, on, off ... by rev point
		layered: boolean, -- which mode this rig was built in
		enabled: boolean,
		engine: Engine.Engine,
		feed: Engine.Feed,
		pitch: number, -- the rpm as the one clip's pitch: also the "is it continuous" measure
		volume: number, -- the one clip's volume, or the layered mix's total, before QUIET
		mixVolumes: { number }, -- what each layer is being given, PRE-ALLOCATED
		mixSpeeds: { number },
		maxStep: number, -- the largest single-frame change in `pitch` since `ResetMeasure`
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

-- The one clip's pitch for an rpm share (0 idle .. 1 redline).
function EngineSound.pitchForShare(share: number): number
	local E = Config.Fx.Engine
	return lerp(E.MinPitch, E.MaxPitch, math.clamp(share, 0, 1))
end

-- The one clip's volume for a load (0 off throttle .. 1 on).
function EngineSound.volumeForLoad(load: number): number
	local E = Config.Fx.Engine
	return E.Volume * lerp(E.OffLoadVolume, 1, math.clamp(load, 0, 1))
end

-- Whether the layered sound is configured (the sheet uploaded).
function EngineSound.isLayered(): boolean
	local L = Config.Fx.Engine.Layers
	return L ~= nil and type(L.SoundId) == "string" and L.SoundId ~= "" and #L.Loops >= 2
end

-- THE MIX, pure. Writes each layer's volume and playback speed into `vols` and `speeds`
-- (index `2i - 1` is loop i on throttle, `2i` off), and returns the total volume.
--
--   * The two loops either side of `rpm` share it, equal power, by where it sits between
--     their rev points on a LOG scale (pitch is a ratio, so the halfway point between
--     3 190 and 4 860 is 3 937, not 4 025). Every other loop is at 0.
--   * Each loop is pitched `rpm / its rpm`, clamped to `1 +- MaxPitchShift`. Below the
--     lowest rev point the lowest loop plays alone, pitched down; above the highest, the
--     highest, pitched up -- both inside the clamp.
--   * On and off throttle share the load, equal power, the off loops `OffLoadVolume` under.
--   * A limiter cut ducks the lot to `LimiterDuck`.
function EngineSound.mix(rpm: number, load: number, cut: boolean, vols: { number }, speeds: { number }): number
	local L = Config.Fx.Engine.Layers
	local loops = L.Loops
	local n = #loops
	local shift = L.MaxPitchShift

	-- Which pair, and how far between them.
	local lo, w = 1, 0
	if rpm <= loops[1].Rpm then
		lo, w = 1, 0
	elseif rpm >= loops[n].Rpm then
		lo, w = n - 1, 1
	else
		for i = 1, n - 1 do
			if rpm < loops[i + 1].Rpm then
				lo = i
				w = math.log(rpm / loops[i].Rpm) / math.log(loops[i + 1].Rpm / loops[i].Rpm)
				break
			end
		end
	end
	local gLo = math.cos(w * math.pi * 0.5)
	local gHi = math.sin(w * math.pi * 0.5)

	local l = math.clamp(load, 0, 1)
	local on = math.sqrt(l)
	local off = math.sqrt(1 - l) * L.OffLoadVolume
	local duck = if cut then L.LimiterDuck else 1
	local master = L.Volume * duck

	local total = 0
	for i = 1, n do
		local g = if i == lo then gLo elseif i == lo + 1 then gHi else 0
		local speed = math.clamp(rpm / loops[i].Rpm, 1 - shift, 1 + shift)
		vols[2 * i - 1] = g * on * master
		vols[2 * i] = g * off * master
		speeds[2 * i - 1] = speed
		speeds[2 * i] = speed
		total += vols[2 * i - 1] + vols[2 * i]
	end
	return total
end

function EngineSound.new(): EngineSound
	local self = setmetatable({
		body = nil,
		sound = nil,
		layers = {},
		layered = false,
		enabled = true,
		engine = Engine.new(),
		feed = Engine.newFeed(),
		pitch = Config.Fx.Engine.MinPitch,
		volume = 0,
		mixVolumes = table.create(2 * #Config.Fx.Engine.Layers.Loops, 0),
		mixSpeeds = table.create(2 * #Config.Fx.Engine.Layers.Loops, 1),
		maxStep = 0,
	}, EngineSound) :: any
	return self
end

function EngineSound.Clear(self: EngineSound)
	if self.sound then
		self.sound:Destroy()
	end
	for _, s in self.layers do
		s:Destroy()
	end
	table.clear(self.layers)
	self.sound = nil
	self.body = nil
end

local function makeSound(name: string, id: string): Sound
	local E = Config.Fx.Engine
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Looped = true
	-- 3D, and tapered rather than linear, so a car is heard WHERE IT IS.
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = E.RollOffMin
	sound.RollOffMaxDistance = E.RollOffMax
	sound.Volume = 0
	return sound
end

-- Build the sounds, once, for the car this rig holds. Called every frame and does nothing
-- at all once it has built for a body.
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
	self.layered = EngineSound.isLayered()
	if self.layered then
		local L = E.Layers
		for i, loop in L.Loops do
			for k, region in { loop.On, loop.Off } do
				local sound = makeSound(
					("%s_%d_%s"):format(Config.Fx.Names.Engine, loop.Rpm, if k == 1 then "On" else "Off"),
					L.SoundId :: string
				)
				-- The slice of the sheet this loop is, played and looped inside it.
				local range = NumberRange.new(region[1], region[1] + region[2])
				sound.PlaybackRegionsEnabled = true
				sound.PlaybackRegion = range
				sound.LoopRegion = range
				sound.PlaybackSpeed = 1
				sound.Parent = body
				if not QUIET then
					sound:Play()
				end
				self.layers[2 * i - 2 + k] = sound
			end
		end
	else
		local sound = makeSound(Config.Fx.Names.Engine, E.SoundId)
		sound.PlaybackSpeed = self.pitch
		sound.Parent = body
		if not QUIET then
			sound:Play()
		end
		self.sound = sound
	end
	self.body = body
	return true
end

-- One frame. `state` nil means no car: the engine idles down and the note fades out.
function EngineSound.Update(self: EngineSound, state: DriftModel.State?, input: any, dt: number?)
	local step = math.max(dt or 0, 0)
	local live = state ~= nil and self.enabled

	if state and self.enabled then
		Engine.feedFrom(state, input, self.feed)
		Engine.step(self.engine, self.feed, step)
	else
		-- No car, or switched off: the engine settles to idle and the note goes quiet.
		local feed = self.feed
		feed.speed, feed.slip, feed.drifting, feed.airborne = 0, 0, false, false
		feed.braking, feed.handbrake, feed.throttle = false, false, 0
		feed.topSpeed = Config.Drift.TopSpeed
		Engine.step(self.engine, feed, step)
	end

	local engine = self.engine
	local before = self.pitch
	self.pitch = EngineSound.pitchForShare(Engine.rpmShare(engine))
	local moved = math.abs(self.pitch - before)
	if moved > self.maxStep then
		self.maxStep = moved
	end

	if self.layered then
		local vols, speeds = self.mixVolumes, self.mixSpeeds
		local total = EngineSound.mix(engine.rpm, engine.load, engine.cut, vols, speeds)
		if not live then
			for i = 1, #vols do
				vols[i] = 0
			end
			total = 0
		end
		self.volume = total
		for i, sound in self.layers do
			local want = if QUIET then 0 else vols[i]
			if math.abs(sound.Volume - want) > 1e-4 then
				sound.Volume = want
			end
			if math.abs(sound.PlaybackSpeed - speeds[i]) > 1e-5 then
				sound.PlaybackSpeed = speeds[i]
			end
		end
		return
	end

	self.volume = if live then EngineSound.volumeForLoad(engine.load) else 0
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

-- The engine note on or off wholesale. It creates and destroys nothing: the sounds keep
-- playing at zero volume, because stopping and starting a loop is a click.
function EngineSound.SetEnabled(self: EngineSound, on: boolean): boolean
	self.enabled = on == true
	if QUIET or not self.enabled then
		if self.sound then
			self.sound.Volume = 0
		end
		for _, s in self.layers do
			s.Volume = 0
		end
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

-- How many sounds this module has in the world right now.
function EngineSound.CountInstances(self: EngineSound): number
	local n = if self.sound and self.sound.Parent then 1 else 0
	for _, s in self.layers do
		if s.Parent then
			n += 1
		end
	end
	return n
end

-- How many it builds per car, in the mode the config is in: 12 layered, 1 otherwise.
function EngineSound.expectedInstances(): number
	return if EngineSound.isLayered() then 2 * #Config.Fx.Engine.Layers.Loops else 1
end

-- What the engine and the note are doing. Allocates; called by tests and by hand.
function EngineSound.DebugState(self: EngineSound, state: DriftModel.State?)
	local d = Engine.debug(self.engine)
	local first = self.sound or self.layers[1]
	local layers = {}
	for i, s in self.layers do
		layers[i] = {
			name = s.Name,
			volume = self.mixVolumes[i],
			speed = self.mixSpeeds[i],
			playing = s.IsPlaying,
			loaded = s.IsLoaded,
		}
	end
	return {
		quiet = QUIET,
		enabled = self.enabled,
		layered = self.layered,
		attached = self.body ~= nil,
		instances = EngineSound.CountInstances(self),
		soundId = if first then first.SoundId else nil,
		playing = if first then first.IsPlaying else false,
		volume = self.volume,
		soundVolume = if self.sound then self.sound.Volume else 0,
		speed = if state then DriftModel.speed(state) else 0,
		airborne = if state then state.airborne else nil,
		pitch = self.pitch,
		playbackSpeed = if self.sound then self.sound.PlaybackSpeed else 0,
		maxStep = self.maxStep,
		layers = layers,
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
