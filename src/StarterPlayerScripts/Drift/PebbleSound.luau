--!strict
-- PebbleSound: stones kicked up into the wheel wells and the floor off the road (T-292,
-- docs/game/AUDIO.md, numbers in `Config.Pebbles`). The user's pick, round 2 (round 1's
-- pebble ticks were sent back as "pebbles on pebbles"):
--
--   THE HITS: stones on sheet metal -- heavy floor-pan and thin-metal clanks and light pings,
--   slices of Creator Store one-shots (the user's pick, "E: Floor-pan clanks") -- fired at
--   random times (a Poisson stream: no two seconds alike, nothing to hear loop), each at a
--   random pitch and loudness, its last `FadeTail` faded out, on `Voices` `Sound`s.
--   THE CRUNCH: one gravel loop under them, quiet, its rumble cut by an EQ, never restarted
--   while the car exists, so its loop point is never heard coming.
--
-- Both follow one ground value: the mean of the four wheels' grounds (`Config.Pebbles.Surfaces`,
-- gravel loudest, grass least, tarmac and a wheel in the air nothing), moved toward its target
-- over `FadeSeconds`, so a change of ground swells and fades and never clicks. Speed makes the
-- stream denser and louder, a slide more again; under `MinSpeed`, stopped or held, nothing.
--
-- WHICH GROUND A WHEEL IS ON is `Drift/Wheels.surfaceOf`, the one rule the game has, and the
-- slide is `Drift/SkidSound.slideSpeed`: this module owns no second copy of either.
--
-- IT DRIVES ITSELF (`PebbleSound.start(controller)`): one line in `DriftController` starts it,
-- and each frame it reads that controller's rig and state. A new body rebuilds it; a jump of
-- more than `JumpDistance` in a frame (spawn, respawn, teleport) silences it at once.
--
-- THE CLIENT ONLY, the local car only. Nothing is made while driving: 1 loop, 1 EQ and
-- `Voices` tick voices per body, made when the rig is caught. An agent's quiet playtest
-- never starts a sound, and everything is still computed and reported (`DebugState`).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)
local SkidSound = require(script.Parent.SkidSound)
local SoundLevels = require(script.Parent.SoundLevels)
local Wheels = require(script.Parent.Wheels)

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

local PebbleSound = {}
PebbleSound.__index = PebbleSound

export type PebbleSound = typeof(setmetatable(
	{} :: {
		body: BasePart?,
		bed: Sound?,
		voices: { Sound },
		voiceEnds: { number }, -- `clock` each voice's hit ends at (0: idle)
		voiceLevels: { number }, -- each voice's volume before its fade
		clock: number, -- seconds of `Update`, for the voices' ends
		enabled: boolean,
		ground: number, -- 0 .. 1, the heard ground value (faded)
		target: number, -- what it is heading for
		speedT: number,
		slideT: number,
		rate: number, -- ticks a second asked for this frame
		bedVolume: number, -- the crunch's logic volume (before the mute)
		phase: number, -- Poisson: work left before the next tick
		ticks: number, -- ticks fired since `ResetMeasure`
		clacks: number,
		maxStep: number, -- largest single-frame change of `ground` since `ResetMeasure`
		lastPosition: Vector3?,
		cuts: number,
		random: Random,
		connection: RBXScriptConnection?,
		tickList: { any },
		clackList: { any },
	},
	PebbleSound
))

--------------------------------------------------------------------------------
-- The numbers, pure
--------------------------------------------------------------------------------

-- The ground value this state asks for: the mean of the four wheels' `Surfaces` gains. 0
-- with no state, in the air, or on tarmac; a car with two wheels on the gravel verge gets
-- half the gravel.
function PebbleSound.groundOf(state: DriftModel.State?): number
	if not state or state.airborne then
		return 0
	end
	local gains = Config.Pebbles.Surfaces
	local sum = 0
	for i = 1, 4 do
		local surface = Wheels.surfaceOf(state, i, state.wheelsDown[i] == true)
		sum += (surface and gains[surface]) or 0
	end
	return sum / 4
end

-- How far up the speed range, 0 .. 1 (0 under `MinSpeed`).
function PebbleSound.speedT(state: DriftModel.State?): number
	if not state then
		return 0
	end
	local P = Config.Pebbles
	return math.clamp((DriftModel.speed(state) - P.MinSpeed) / (P.FullSpeed - P.MinSpeed), 0, 1)
end

function PebbleSound.slideT(state: DriftModel.State?): number
	return math.clamp(SkidSound.slideSpeed(state) / Config.Pebbles.SlideFull, 0, 1)
end

-- Ticks a second at this ground, speed and slide.
function PebbleSound.rateFor(ground: number, speedT: number, slideT: number): number
	local P = Config.Pebbles
	return P.MaxRate * ground * speedT * (1 + P.SlideRateBoost * slideT)
end

-- The crunch's volume, before the mute.
function PebbleSound.bedVolumeFor(ground: number, speedT: number, slideT: number): number
	local P = Config.Pebbles
	return P.BedVolume * ground * speedT ^ P.BedSpeedPower * (1 + P.BedSlideBoost * slideT)
end

-- One tick's volume before its random factor and its own gain.
function PebbleSound.tickLevelFor(ground: number, speedT: number): number
	local P = Config.Pebbles
	return P.TickVolume * ground * (P.TickSpeedFloor + (1 - P.TickSpeedFloor) * speedT)
end

-- `ground` one frame on, toward `target` by `dt / FadeSeconds`.
function PebbleSound.fadeStep(ground: number, target: number, dt: number): number
	local step = dt / math.max(Config.Pebbles.FadeSeconds, 1e-4)
	if ground < target then
		return math.min(ground + step, target)
	end
	return math.max(ground - step, target)
end

--------------------------------------------------------------------------------
-- The rig
--------------------------------------------------------------------------------

function PebbleSound.new(seed: number?): PebbleSound
	local self = setmetatable({
		body = nil,
		bed = nil,
		voices = {},
		voiceEnds = {},
		voiceLevels = {},
		clock = 0,
		enabled = true,
		ground = 0,
		target = 0,
		speedT = 0,
		slideT = 0,
		rate = 0,
		bedVolume = 0,
		phase = 0,
		ticks = 0,
		clacks = 0,
		maxStep = 0,
		lastPosition = nil,
		cuts = 0,
		random = if seed then Random.new(seed) else Random.new(),
		connection = nil,
		tickList = {},
		clackList = {},
	}, PebbleSound) :: any
	self.phase = PebbleSound._exp(self)
	PebbleSound.split(self)
	return self
end

-- The slices in two lists, ticks and clacks, so a pick is one random index.
function PebbleSound.split(self: PebbleSound)
	table.clear(self.tickList)
	table.clear(self.clackList)
	for _, tick in Config.Pebbles.Ticks do
		table.insert(if tick.clack then self.clackList else self.tickList, tick)
	end
end

function PebbleSound._exp(self: PebbleSound): number
	return -math.log(math.max(1 - self.random:NextNumber(), 1e-9))
end

function PebbleSound.Clear(self: PebbleSound)
	if self.bed then
		self.bed:Destroy()
		self.bed = nil
	end
	for _, voice in self.voices do
		voice:Destroy()
	end
	table.clear(self.voices)
	table.clear(self.voiceEnds)
	table.clear(self.voiceLevels)
	self.body = nil
end

local function makeSound(name: string): Sound
	local P = Config.Pebbles
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = P.RollOffMin
	sound.RollOffMaxDistance = P.RollOffMax
	sound.Volume = 0
	SoundLevels.apply(sound, "OffRoad")
	return sound
end

-- Build the crunch and the voices once per body. Called every frame; nothing once built.
function PebbleSound.Attach(self: PebbleSound, rig: any): boolean
	local body = rig and rig.body
	if body and self.body == body then
		return true
	end
	PebbleSound.Clear(self)
	if not body then
		return false
	end
	local P = Config.Pebbles

	local bed = makeSound("FxPebbleCrunch")
	bed.SoundId = P.Bed.SoundId
	bed.Looped = true
	bed.PlaybackRegionsEnabled = true
	bed.PlaybackRegion = NumberRange.new(P.Bed.RegionStart, P.Bed.RegionEnd)
	bed.LoopRegion = NumberRange.new(P.Bed.RegionStart, P.Bed.RegionEnd)
	bed.TimePosition = P.Bed.RegionStart
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain = P.Bed.LowGain
	eq.MidGain = 0
	eq.HighGain = 0
	eq.Parent = bed
	bed.Parent = body
	self.bed = bed

	local ids = {}
	for i = 1, P.Voices do
		local voice = makeSound("FxPebbleTick" .. i)
		voice.Looped = false
		voice.PlaybackRegionsEnabled = true
		voice.SoundId = "rbxassetid://" .. P.Ticks[1 + (i - 1) % #P.Ticks].id
		voice.Parent = body
		table.insert(self.voices, voice)
		table.insert(self.voiceEnds, 0)
		table.insert(self.voiceLevels, 0)
	end
	-- Every tick file loaded now, so the first tick on each is not late.
	local seen = {}
	for _, tick in P.Ticks do
		if not seen[tick.id] then
			seen[tick.id] = true
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. tick.id
			table.insert(ids, s)
		end
	end
	table.insert(ids, bed)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(ids)
		end)
	end)

	self.body = body
	return true
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

function PebbleSound._fire(self: PebbleSound)
	local P = Config.Pebbles
	local r = self.random
	local clack = r:NextNumber() < P.ClackShare
	-- pick among the ticks of the wanted kind (both lists are made once, in `split`)
	local list = if clack and #self.clackList > 0 then self.clackList else self.tickList
	if #list == 0 then
		list = P.Ticks
	end
	local tick = list[r:NextInteger(1, #list)]
	self.ticks += 1
	if tick.clack then
		self.clacks += 1
	end
	if QUIET or #self.voices == 0 then
		return
	end
	-- An idle voice, else the one nearest the end of its hit: a ring is cut only when every
	-- voice is busy, and then the quietest-by-now one.
	local index, soonest = 1, math.huge
	for i, ends in self.voiceEnds do
		if ends <= self.clock then
			index = i
			break
		end
		if ends < soonest then
			index, soonest = i, ends
		end
	end
	local voice = self.voices[index]
	local id = "rbxassetid://" .. tick.id
	if voice.SoundId ~= id then
		voice.SoundId = id
	end
	voice:Stop()
	voice.PlaybackRegion = NumberRange.new(tick.start, tick.start + tick.length)
	voice.TimePosition = tick.start
	local pitch = r:NextNumber(P.PitchMin, P.PitchMax)
	voice.PlaybackSpeed = pitch
	local level = math.min(PebbleSound.tickLevelFor(self.ground, self.speedT) * tick.gain * r:NextNumber(P.TickRandomVolume, 1), 10)
	voice.Volume = level
	self.voiceLevels[index] = level
	self.voiceEnds[index] = self.clock + tick.length / pitch
	voice:Play()
end

-- Silent now, and remembered as silent: the car jumped.
function PebbleSound.Cut(self: PebbleSound)
	self.ground = 0
	self.target = 0
	self.rate = 0
	self.bedVolume = 0
	self.cuts += 1
	if self.bed then
		self.bed.Volume = 0
	end
	for i, voice in self.voices do
		voice:Stop()
		self.voiceEnds[i] = 0
	end
end

-- Each hit's last `FadeTail` fades to nothing, a step a frame: a metal ring cut dead clicks.
-- The volume a voice should be at `remaining` seconds before its hit ends, pure.
function PebbleSound.fadeLevel(level: number, remaining: number): number
	local tail = Config.Pebbles.FadeTail
	if remaining >= tail then
		return level
	end
	return level * math.max(remaining, 0) / math.max(tail, 1e-4)
end

function PebbleSound.Update(self: PebbleSound, state: DriftModel.State?, dt: number)
	local P = Config.Pebbles
	local step = math.max(dt or 0, 0)
	self.clock += step

	-- The hits' fades, before any new hit takes a voice
	for i, voice in self.voices do
		local ends = self.voiceEnds[i]
		if ends > 0 then
			local remaining = ends - self.clock
			if remaining <= 0 then
				self.voiceEnds[i] = 0
				if voice.IsPlaying then
					voice:Stop()
				end
			elseif remaining < P.FadeTail then
				voice.Volume = PebbleSound.fadeLevel(self.voiceLevels[i], remaining)
			end
		end
	end

	if state and self.lastPosition and (state.position - self.lastPosition).Magnitude > P.JumpDistance then
		PebbleSound.Cut(self)
	end
	self.lastPosition = if state then state.position else nil

	if self.enabled and state then
		self.target = PebbleSound.groundOf(state)
		self.speedT = PebbleSound.speedT(state)
		self.slideT = PebbleSound.slideT(state)
	else
		self.target = 0
		self.speedT = 0
		self.slideT = 0
	end
	local before = self.ground
	self.ground = PebbleSound.fadeStep(self.ground, self.target, step)
	self.maxStep = math.max(self.maxStep, math.abs(self.ground - before))

	-- The ticks: a Poisson stream at `rate`.
	self.rate = PebbleSound.rateFor(self.ground, self.speedT, self.slideT)
	if self.rate > 0 and step > 0 then
		self.phase -= self.rate * step
		local fired = 0
		while self.phase <= 0 do
			if fired < P.MaxPerFrame then
				PebbleSound._fire(self)
				fired += 1
			end
			self.phase += PebbleSound._exp(self)
		end
	end

	-- The crunch: always running once built (volume 0 when silent), never restarted.
	self.bedVolume = PebbleSound.bedVolumeFor(self.ground, self.speedT, self.slideT)
	local bed = self.bed
	if bed then
		local run = self.enabled and not QUIET
		if run and not bed.IsPlaying then
			bed:Play()
		elseif not run and bed.IsPlaying then
			bed:Stop()
		end
		local want = if QUIET then 0 else self.bedVolume
		if math.abs(bed.Volume - want) > 1e-5 then
			bed.Volume = want
		end
		local pitch = P.BedPitchMin + (P.BedPitchMax - P.BedPitchMin) * self.speedT
		if math.abs(bed.PlaybackSpeed - pitch) > 1e-3 then
			bed.PlaybackSpeed = pitch
		end
	end
end

function PebbleSound.SetEnabled(self: PebbleSound, on: boolean): boolean
	self.enabled = on == true
	if not self.enabled then
		PebbleSound.Cut(self)
	end
	return self.enabled
end

function PebbleSound.ResetMeasure(self: PebbleSound)
	local out = { ticks = self.ticks, clacks = self.clacks, maxStep = self.maxStep }
	self.ticks, self.clacks, self.maxStep = 0, 0, 0
	return out
end

function PebbleSound.DebugState(self: PebbleSound, state: DriftModel.State?)
	local surfaces = {}
	if state then
		for i = 1, 4 do
			surfaces[i] = Wheels.surfaceOf(state, i, state.wheelsDown[i] == true) or "air"
		end
	end
	return {
		quiet = QUIET,
		enabled = self.enabled,
		attached = self.body ~= nil,
		voices = #self.voices,
		busyVoices = (function()
			local n = 0
			for _, ends in self.voiceEnds do
				n += if ends > self.clock then 1 else 0
			end
			return n
		end)(),
		bedPlaying = if self.bed then self.bed.IsPlaying else false,
		bedInstanceVolume = if self.bed then self.bed.Volume else 0,
		bedPitch = if self.bed then self.bed.PlaybackSpeed else 0,
		bedTime = if self.bed then self.bed.TimePosition else 0,
		ground = self.ground, -- heard, faded
		target = self.target,
		speedT = self.speedT,
		slideT = self.slideT,
		rate = self.rate, -- ticks a second
		bedVolume = self.bedVolume, -- logic volume, before the mute
		tickLevel = PebbleSound.tickLevelFor(self.ground, self.speedT),
		ticks = self.ticks,
		clacks = self.clacks,
		maxStep = self.maxStep,
		cuts = self.cuts,
		speed = if state then DriftModel.speed(state) else nil,
		wheels = surfaces,
	}
end

--------------------------------------------------------------------------------
-- Started by one line in DriftController
--------------------------------------------------------------------------------

-- Make one, keep it on `controller.pebbleSound`, and drive it every frame from the
-- controller's rig and state (nil while the player is out of the car).
function PebbleSound.start(controller: any): PebbleSound
	local self = PebbleSound.new()
	controller.pebbleSound = self
	self.connection = RunService.Heartbeat:Connect(function(dt)
		local rig = controller.rig
		if rig then
			PebbleSound.Attach(self, rig)
		end
		local driving = controller.IsDriving and controller:IsDriving()
		local state = if driving then controller:CurrentState() else nil
		PebbleSound.Update(self, state, dt)
	end)
	return self
end

return PebbleSound
