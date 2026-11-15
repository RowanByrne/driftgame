--!strict
-- SuspensionSound: a clunk when a wheel's strut knocks, and a big one when the car lands
-- (docs/game/features/car-fx.md "Suspension sounds", T-223).
--
-- READ OFF THE MODEL, NEVER WRITTEN BACK. Each simulation step (`Step`, from the
-- controller's step hook, so it is the same at every frame rate) it looks at three things the
-- model already publishes: each wheel's drawn `travel` (0 hanging .. `SuspensionTravel` fully
-- up, `Drift/Suspension.draw`), `wheelsDown`, and the car's vertical `velocity`.
--
--   THE CLUNK. A wheel that is down and whose travel CLOSED faster than `ClunkRate` this
--   step has been shoved up: a bump, a kerb, or the catch at the end of a drop (a wheel is
--   drawn falling no faster than `DropTime`, so the drop itself is silent and only the catch
--   is fast). Volume by how fast, from `ClunkMinVolume` to `ClunkMaxVolume`. Each wheel then
--   waits `ClunkCooldown`, and no two clunks are closer than `ClunkGap` -- so two wheels
--   hitting one kerb in one moment are one knock, at the harder one's volume. On flat ground
--   the travel never moves; on a smooth road it moves far slower than the threshold.
--
--   THE LANDING. No wheel down for at least `LandAirTime`, then one touches: the car has
--   landed, falling at whatever its vertical speed was on the last step in the air. At
--   `LandMinSpeed` or more the landing plays, by that speed; at any speed, no wheel clunks
--   for `LandQuiet` after it, so the four catches of a landing never stack on top of it.
--
-- THE SOUNDS are Creator Store slices (`Config.Fx.Suspension.Clunks`, `.Landing`), played
-- through `PlaybackRegion`. `Voices` clunk `Sound`s on the body, round-robin, each clunk a
-- random slice (never the one just played when there is a choice) a little faster or slower.
-- No clip configured: no `Sound`, no error, and everything below still runs and counts.
--
-- In an agent's playtest the instances are never played (ReplicatedFirst/QuietPlay), and
-- every count and volume below is computed exactly as it would be with sound on.
--
-- The player's own car only: another player's car arrives as four packed lifts a packet,
-- not as steps, and is silent.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)

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

local WHEELS = 4

type Clip = { Id: string, Start: number, Length: number, Gain: number }

local SuspensionSound = {}
SuspensionSound.__index = SuspensionSound

export type SuspensionSound = typeof(setmetatable(
	{} :: {
		body: BasePart?,
		voices: { Sound },
		nextVoice: number,
		landing: Sound?,
		enabled: boolean,
		clock: number, -- s of simulation stepped since `new`
		prevTravel: { number },
		havePrev: boolean,
		readyAt: { number }, -- per wheel: the clock at which it may clunk again
		gapUntil: number, -- the clock before which no wheel clunks (`ClunkGap`, `LandQuiet`)
		airTime: number, -- s with no wheel down, so far
		airSpeed: number, -- studs/s falling, on the last step in the air
		lastClip: number,
		-- the readout (`DebugState`, `ResetMeasure`)
		clunks: number,
		landings: number,
		touchdowns: number, -- landings that were too soft to play
		held: number, -- clunks that would have played but for a cooldown, the gap or a landing
		maxRate: { number }, -- per wheel, the fastest closing since `ResetMeasure`
		lastClunk: any,
		lastLanding: any,
	},
	SuspensionSound
))

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- The clunk's volume for a wheel closing at `rate` studs/s, before the master: 0 under the
-- threshold. Pure, for the readout and the tests.
function SuspensionSound.clunkVolume(rate: number): number
	local S = Config.Fx.Suspension
	if rate < S.ClunkRate then
		return 0
	end
	local t = clamp01((rate - S.ClunkRate) / math.max(S.ClunkRateForMax - S.ClunkRate, 1e-6))
	return lerp(S.ClunkMinVolume, S.ClunkMaxVolume, t)
end

-- The landing's volume for a touchdown falling at `speed` studs/s, before the master.
function SuspensionSound.landingVolume(speed: number): number
	local S = Config.Fx.Suspension
	if speed < S.LandMinSpeed then
		return 0
	end
	local t = clamp01((speed - S.LandMinSpeed) / math.max(S.LandSpeedForMax - S.LandMinSpeed, 1e-6))
	return lerp(S.LandMinVolume, S.LandMaxVolume, t)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function SuspensionSound.new(): SuspensionSound
	return setmetatable({
		body = nil,
		voices = {},
		nextVoice = 1,
		landing = nil,
		enabled = true,
		clock = 0,
		prevTravel = table.create(WHEELS, 0),
		havePrev = false,
		readyAt = table.create(WHEELS, 0),
		gapUntil = 0,
		airTime = 0,
		airSpeed = 0,
		lastClip = 0,
		clunks = 0,
		landings = 0,
		touchdowns = 0,
		held = 0,
		maxRate = table.create(WHEELS, 0),
		lastClunk = nil,
		lastLanding = nil,
	}, SuspensionSound) :: any
end

function SuspensionSound.Clear(self: SuspensionSound)
	for _, sound in self.voices do
		sound:Destroy()
	end
	table.clear(self.voices)
	if self.landing then
		self.landing:Destroy()
		self.landing = nil
	end
	self.body = nil
end

local function newSound(name: string, parent: BasePart): Sound
	local S = Config.Fx.Suspension
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Looped = false
	sound.PlaybackRegionsEnabled = true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = S.RollOffMin
	sound.RollOffMaxDistance = S.RollOffMax
	sound.Volume = 0
	sound.Parent = parent
	return sound
end

-- Build the voices on the car's body, once per body: the same contract as `SkidSound`.
function SuspensionSound.Attach(self: SuspensionSound, rig: any): boolean
	local body = rig and rig.body
	if body and self.body == body then
		return true
	end
	SuspensionSound.Clear(self)
	if not body then
		return false
	end
	local S = Config.Fx.Suspension
	if #S.Clunks > 0 then
		for i = 1, math.max(S.Voices, 1) do
			table.insert(self.voices, newSound(string.format(S.ClunkName, i), body))
		end
	end
	if S.Landing then
		self.landing = newSound(S.LandingName, body)
	end
	self.body = body
	return true
end

-- Forget the wheels and the air: a respawn or a car handed out. Nothing carries across it.
function SuspensionSound.Cut(self: SuspensionSound)
	self.havePrev = false
	self.airTime = 0
	self.airSpeed = 0
	self.gapUntil = 0
	table.clear(self.readyAt)
	for i = 1, WHEELS do
		self.readyAt[i] = 0
	end
	for _, sound in self.voices do
		sound:Stop()
	end
	if self.landing then
		self.landing:Stop()
	end
end

function SuspensionSound.SetEnabled(self: SuspensionSound, on: boolean): boolean
	self.enabled = on == true
	if not self.enabled then
		SuspensionSound.Cut(self)
	end
	return self.enabled
end

--------------------------------------------------------------------------------
-- Playing
--------------------------------------------------------------------------------

local function play(sound: Sound, clip: Clip, volume: number, speed: number)
	if sound.SoundId ~= clip.Id then
		sound.SoundId = clip.Id
	end
	sound.PlaybackRegion = NumberRange.new(clip.Start, clip.Start + clip.Length)
	sound.PlaybackSpeed = speed
	sound.Volume = volume * (clip.Gain or 1) * Config.Fx.Suspension.Volume
	sound.TimePosition = clip.Start
	sound:Play()
end

function SuspensionSound._playClunk(self: SuspensionSound, volume: number)
	local S = Config.Fx.Suspension
	local clips = S.Clunks
	if QUIET or #self.voices == 0 or #clips == 0 then
		return
	end
	local pick = math.random(1, #clips)
	if #clips > 1 and pick == self.lastClip then
		pick = pick % #clips + 1
	end
	self.lastClip = pick
	local sound = self.voices[self.nextVoice]
	self.nextVoice = self.nextVoice % #self.voices + 1
	local jitter = S.PitchJitter
	play(sound, clips[pick], volume, 1 + (math.random() * 2 - 1) * jitter)
end

function SuspensionSound._playLanding(self: SuspensionSound, volume: number)
	local S = Config.Fx.Suspension
	if QUIET or not self.landing or not S.Landing then
		return
	end
	-- Whatever clunk is still ringing is the landing's now.
	for _, sound in self.voices do
		sound:Stop()
	end
	play(self.landing, S.Landing, volume, 1)
end

--------------------------------------------------------------------------------
-- The step
--------------------------------------------------------------------------------

-- One simulation step of the player's car: `dt` is `FixedStep`.
function SuspensionSound.Step(self: SuspensionSound, dt: number, state: DriftModel.State?)
	if not state or not self.enabled or dt <= 0 then
		return
	end
	local S = Config.Fx.Suspension
	local s: any = state
	local travel: { number }? = s.travel
	local down: { boolean } = s.wheelsDown
	if not travel then
		return
	end
	self.clock += dt
	local now = self.clock

	local anyDown = false
	for i = 1, WHEELS do
		if down[i] == true then
			anyDown = true
			break
		end
	end

	-- THE LANDING, first: when it plays, it is the only sound of this moment.
	if not anyDown then
		self.airTime += dt
		self.airSpeed = math.max(0, -s.velocity.Y)
	else
		if self.airTime >= S.LandAirTime then
			local volume = SuspensionSound.landingVolume(self.airSpeed)
			if volume > 0 then
				self.landings += 1
				self:_playLanding(volume)
			else
				self.touchdowns += 1
			end
			self.lastLanding = {
				at = now,
				speed = self.airSpeed,
				airTime = self.airTime,
				volume = volume,
				played = volume > 0,
			}
			self.gapUntil = math.max(self.gapUntil, now + S.LandQuiet)
		end
		self.airTime = 0
	end

	-- THE CLUNKS: the hardest-closing wheel of this step that is free to clunk, if any.
	local bestRate, bestWheel = 0, 0
	if self.havePrev then
		for i = 1, WHEELS do
			local rate = (travel[i] - self.prevTravel[i]) / dt
			if down[i] == true and rate > 0 then
				if rate > self.maxRate[i] then
					self.maxRate[i] = rate
				end
				if rate >= S.ClunkRate then
					if now < self.readyAt[i] or now < self.gapUntil then
						self.held += 1
					elseif rate > bestRate then
						bestRate, bestWheel = rate, i
					end
				end
			end
		end
	end
	if bestWheel > 0 then
		local volume = SuspensionSound.clunkVolume(bestRate)
		self.clunks += 1
		self.readyAt[bestWheel] = now + S.ClunkCooldown
		self.gapUntil = math.max(self.gapUntil, now + S.ClunkGap)
		self.lastClunk = { at = now, wheel = bestWheel, rate = bestRate, volume = volume }
		self:_playClunk(volume)
	end

	for i = 1, WHEELS do
		self.prevTravel[i] = travel[i]
	end
	self.havePrev = true
end

--------------------------------------------------------------------------------
-- Readout
--------------------------------------------------------------------------------

-- The counts and the fastest closings since the last call, and back to zero.
function SuspensionSound.ResetMeasure(self: SuspensionSound)
	local out = {
		clunks = self.clunks,
		landings = self.landings,
		touchdowns = self.touchdowns,
		held = self.held,
		maxRate = table.clone(self.maxRate),
		lastClunk = self.lastClunk,
		lastLanding = self.lastLanding,
	}
	self.clunks, self.landings, self.touchdowns, self.held = 0, 0, 0, 0
	for i = 1, WHEELS do
		self.maxRate[i] = 0
	end
	self.lastClunk, self.lastLanding = nil, nil
	return out
end

function SuspensionSound.DebugState(self: SuspensionSound)
	local S = Config.Fx.Suspension
	return {
		quiet = QUIET, -- true: nothing is ever played, everything is still counted
		enabled = self.enabled,
		attached = self.body ~= nil,
		voices = #self.voices,
		hasLanding = self.landing ~= nil,
		clips = #S.Clunks,
		clunks = self.clunks,
		landings = self.landings,
		touchdowns = self.touchdowns,
		held = self.held,
		maxRate = table.clone(self.maxRate),
		airTime = self.airTime,
		lastClunk = self.lastClunk,
		lastLanding = self.lastLanding,
		clunkRate = S.ClunkRate,
		landAirTime = S.LandAirTime,
		landMinSpeed = S.LandMinSpeed,
	}
end

return SuspensionSound
