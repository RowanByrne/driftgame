--!strict
-- SkidSound: one looping clip per surface, volume by slip angle
-- (docs/game/features/car-fx.md "Skid sound: one loop per surface, volume by slip angle").
--
-- The squeal tells the player the back is out before the camera does, and HOW FAR out.
-- One `Sound` per surface in `Config.Fx.Built`, all of them alive at once, each one's
-- volume LERPED rather than switched -- which is the difference between a drift that
-- fades up and one that clicks on.
--
--   volume = lerp(MinVolume, 1, |slip| / MaxSlipDegrees)   while the car is drifting
--          = 0                                             when it is not, when it is
--                                                          airborne, or under MinSpeed
--
-- and that number is then lerped toward at `VolumeLerpSpeed` per second and scaled by
-- `Skid.Volume`, the master the mix sets (AUDIO.md "Mix": the squeal sits on top).
--
-- ONLY THE SURFACE THE WHEELS ARE ACTUALLY ON IS PLAYING; the others are stopped. The
-- game has one surface today (tarmac) and `dirt` specced but unbuilt, so this is one clip
-- now and a table that already has room for the second. Which surface a wheel is on is
-- `Drift/Wheels.surfaceOf` and not a second copy of that rule: the day `Drift/World`'s
-- `Hit` grows a surface name, both modules learn it at once.
--
-- NOTHING IS CREATED OR DESTROYED WHILE DRIVING. One `Sound` per built surface, made once
-- when the rig is caught, exactly as `Drift/Wheels`' sixteen are. `Update` holds no table
-- and makes no instance.
--
-- THE CLIENT ONLY, and the local car only. No remote, no packet field, no server
-- instance.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)
local Wheels = require(script.Parent.Wheels)

-- An agent's playtest makes no sound. Asked ONCE, at client start -- see the same block in
-- `Drift/EngineSound` for why it is not asked every frame, and for why the logic below is
-- computed and reported whether it is quiet or not.
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

local SkidSound = {}
SkidSound.__index = SkidSound

type SurfaceSound = {
	surface: string,
	sound: Sound,
	playing: boolean, -- what was last WRITTEN, so a frame that changes nothing writes nothing
}

export type SkidSound = typeof(setmetatable(
	{} :: {
		body: BasePart?,
		sounds: { SurfaceSound },
		enabled: boolean,
		volume: number, -- 0 .. 1, the lerped loudness BEFORE the master
		target: number, -- what it is heading for
		surface: string?, -- the surface the wheels are on, or nil
		maxStep: number, -- the largest single-frame change in volume since `ResetMeasure`
	},
	SkidSound
))

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--------------------------------------------------------------------------------
-- The gate, pure
--------------------------------------------------------------------------------

-- The volume this state ASKS for, before any lerp: the thing a test can check against the
-- config without a car, a place or a playtest. Four ways to be silent, and the first three
-- are the spec's: not drifting, airborne, too slow. The fourth is having no state at all.
--
-- `state.drifting` is `|slip| >= Config.Drift.MinSlipAngleForDrift`, which is 5 degrees:
-- the squeal and the drift start together on purpose, and this module does not own a
-- second drift threshold.
function SkidSound.volumeFor(state: DriftModel.State?): number
	if not state then
		return 0
	end
	local S = Config.Fx.Skid
	if state.airborne or not state.drifting then
		return 0
	end
	if DriftModel.speed(state) < S.MinSpeed then
		return 0
	end
	local t = math.clamp(math.abs(state.slip) / math.rad(S.MaxSlipDegrees), 0, 1)
	return lerp(S.MinVolume, 1, t)
end

-- Which surface the car is squealing on: the first wheel that is down, through
-- `Drift/Wheels.surfaceOf`, so there is exactly one rule in the game for what a wheel is
-- standing on. `nil` when the car is airborne or has no wheel on anything.
function SkidSound.surfaceOf(state: DriftModel.State?): string?
	if not state or state.airborne then
		return nil
	end
	for i, down in state.wheelsDown do
		if down == true then
			return Wheels.surfaceOf(state, i, true)
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The rig
--------------------------------------------------------------------------------

function SkidSound.new(): SkidSound
	return setmetatable({
		body = nil,
		sounds = {},
		enabled = true,
		volume = 0,
		target = 0,
		surface = nil,
		maxStep = 0,
	}, SkidSound) :: any
end

function SkidSound.Clear(self: SkidSound)
	for _, entry in self.sounds do
		entry.sound:Destroy()
	end
	table.clear(self.sounds)
	self.body = nil
	self.surface = nil
end

-- Build one sound per built surface, once, for the car this rig holds. Called every frame
-- and does nothing at all once it has built for a body -- the same shape
-- `Drift/Wheels:Attach` uses.
--
-- A SURFACE WITH NO ID IN THE CONFIG GETS NO SOUND AND NO ERROR. `dirt` is specced and has
-- no clip, because a clip is a pick the user makes by ear and not a default an agent
-- chooses (AUDIO.md).
function SkidSound.Attach(self: SkidSound, rig: any): boolean
	local body = rig and rig.body
	if body and self.body == body then
		return true
	end
	SkidSound.Clear(self)
	if not body then
		return false
	end

	local S = Config.Fx.Skid
	for _, surface in Config.Fx.Built do
		local id = S.SoundIds[surface]
		if not id then
			continue
		end
		local sound = Instance.new("Sound")
		sound.Name = string.format(Config.Fx.Names.Skid, surface)
		sound.SoundId = id
		sound.Looped = true
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = S.RollOffMin
		sound.RollOffMaxDistance = S.RollOffMax
		sound.Volume = 0
		sound.Parent = body
		table.insert(self.sounds, { surface = surface, sound = sound, playing = false })
	end

	self.body = body
	return #self.sounds > 0
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

function SkidSound.Update(self: SkidSound, state: DriftModel.State?, _input: any, dt: number?)
	if #self.sounds == 0 then
		return
	end
	local S = Config.Fx.Skid
	local step = math.max(dt or 0, 0)

	if self.enabled then
		self.target = SkidSound.volumeFor(state)
		self.surface = SkidSound.surfaceOf(state)
	else
		self.target = 0
		self.surface = nil
	end

	-- LERPED AND NOT SWITCHED. `clamp` stops a long frame overshooting its target.
	local before = self.volume
	self.volume += (self.target - self.volume) * math.clamp(step * S.VolumeLerpSpeed, 0, 1)
	local moved = math.abs(self.volume - before)
	if moved > self.maxStep then
		self.maxStep = moved
	end

	local master = if QUIET then 0 else S.Volume
	for _, entry in self.sounds do
		local on = entry.surface == self.surface
		-- The one on this surface plays and the rest are stopped. `Play` and `Stop` are
		-- not allocations and this is written only when it changes, so a drive from one
		-- end of the road to the other writes nothing here at all.
		--
		-- IN AN AGENT'S QUIET PLAYTEST THE CLIP IS NEVER STARTED AT ALL, as well as being
		-- muted. Volume 0 is already silent; not starting it is the second lock, so a
		-- mistake in one line of volume arithmetic cannot put sound in the user's ears.
		-- `entry.playing` stays the LOGIC's answer either way, so a silent playtest still
		-- shows which surface the car would be squealing on.
		if entry.playing ~= on then
			entry.playing = on
			if on and not QUIET then
				entry.sound:Play()
			elseif not on then
				entry.sound:Stop()
			end
		end
		local want = if on then self.volume * master else 0
		if math.abs(entry.sound.Volume - want) > 1e-5 then
			entry.sound.Volume = want
		end
	end
end

--------------------------------------------------------------------------------
-- Switches and the readout
--------------------------------------------------------------------------------

-- Silent NOW, and remembered as silent. Used when the car JUMPS -- a spawn, a respawn, a
-- teleport -- so a squeal that was fading up does not carry across the jump into a car
-- standing still somewhere else.
function SkidSound.Cut(self: SkidSound)
	self.volume = 0
	self.target = 0
	self.surface = nil
	for _, entry in self.sounds do
		if entry.playing then
			entry.playing = false
			entry.sound:Stop()
		end
		entry.sound.Volume = 0
	end
end

function SkidSound.SetEnabled(self: SkidSound, on: boolean): boolean
	self.enabled = on == true
	if not self.enabled then
		SkidSound.Cut(self)
	end
	return self.enabled
end

function SkidSound.ResetMeasure(self: SkidSound): number
	local was = self.maxStep
	self.maxStep = 0
	return was
end

function SkidSound.CountInstances(self: SkidSound): number
	local n = 0
	for _, entry in self.sounds do
		n += if entry.sound.Parent then 1 else 0
	end
	return n
end

-- What the squeal is doing and WHY, so a playtest can say "it is silent because the slip
-- is 3 degrees and the drift threshold is 5" rather than "no squeal". Allocates, and is
-- called by tests and by hand -- never by `Update`.
function SkidSound.DebugState(self: SkidSound, state: DriftModel.State?)
	local S = Config.Fx.Skid
	local sounds = {}
	for _, entry in self.sounds do
		table.insert(sounds, {
			surface = entry.surface,
			soundId = entry.sound.SoundId,
			wants = entry.playing, -- what the LOGIC says: this is the surface, or it is not
			playing = entry.sound.IsPlaying, -- what the instance is doing: false in a quiet test
			volume = entry.sound.Volume, -- what the INSTANCE is at: 0 in a quiet playtest
			loopSeconds = entry.sound.TimeLength,
		})
	end
	return {
		quiet = QUIET, -- true means every instance volume above is muted to 0
		enabled = self.enabled,
		attached = self.body ~= nil,
		instances = SkidSound.CountInstances(self),
		master = S.Volume,
		volume = self.volume, -- THE LOGIC's volume, 0 .. 1, before the master and the mute
		target = self.target,
		maxStep = self.maxStep,
		surface = self.surface,
		slipDeg = if state then math.deg(state.slip) else nil,
		drifting = if state then state.drifting else nil,
		airborne = if state then state.airborne else nil,
		speed = if state then DriftModel.speed(state) else nil,
		minSpeed = S.MinSpeed,
		sounds = sounds,
	}
end

return SkidSound
