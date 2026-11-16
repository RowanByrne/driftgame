--!strict
-- SuspensionSound: a clunk when the ground knocks a wheel up, and a big one when the car lands
-- (docs/game/features/car-fx.md "Suspension sounds", T-223, T-252).
--
-- READ OFF THE MODEL, NEVER WRITTEN BACK. Each simulation step (`Step`, from the
-- controller's step hook, so it is the same at every frame rate) it looks at what the model
-- already publishes: each wheel's drawn `travel` (`Drift/Suspension.draw`), `wheelsDown`, the
-- car's height, yaw, body `up`, ground frame `groundUp` and `velocity`.
--
--   THE GROUND UNDER EACH WHEEL, NOT ITS TRAVEL (T-252). A wheel's travel also closes when
--   the BODY moves -- roll and pitch while drifting push the outside wheels up into their
--   arches -- and clunking on that was clunking on weight transfer. So each step it works
--   out the height of the ground each wheel stands on, in the world: `draw` puts a wheel that
--   is down at exactly `Rest + (ground - corner)` of travel, so the corner's height (from the
--   car's height and its body's tilt) plus the travel off `Rest` IS that wheel's ground. The
--   body rolling moves the corner and the travel by the same amount, and the ground it gives
--   does not move at all.
--
--   THE CLUNK. That ground rising under a wheel faster than the ground plane the car is on
--   says it should (`groundUp`, along the way that wheel moved this step) by more than
--   `ClunkRate`: a kerb, a bump, the edge of the gravel bevel up onto the tarmac. A hill or a
--   cambered road rises under the wheels as fast as its plane says, so it never counts. The
--   volume is that excess, from `ClunkMinVolume` to `ClunkMaxVolume`, times the car's speed
--   as a share of `ClunkSpeedForFull` (never under `ClunkSlowShare`) -- the same kerb is a
--   tap at walking pace and a knock at speed. Each wheel has its own clunk and its own
--   `ClunkCooldown`: the front pair over the bevel's edge, then the rear pair, are four.
--
--   THE CATCH, stepping down. A wheel whose ground falls away faster than it may drop
--   (`DropTime`) is drawn falling; once it is back on its ground, if that ground is at least
--   `CatchMin` lower (over its plane) than the ground it left, it knocks: the same clunk as a
--   step up of that height, times `CatchShare`. A wheel the BODY lifted off its ground (the
--   rebound off a bump) comes back to the ground it left, and is silent.
--
--   THE LANDING. No wheel down for at least `LandAirTime`, then one touches: the car has
--   landed, falling at the fastest its vertical speed reached in the air. At
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
local SoundLevels = require(script.Parent.SoundLevels)
local Suspension = require(script.Parent.Suspension)

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
-- The model's wheel order: FL, FR, RL, RR (`Drift/Suspension`).
local FRONT = { 1, 1, -1, -1 }
local SIDE = { -1, 1, -1, 1 }
local LOG_MAX = 32 -- the readout's list of recent clunks
local OLD_CLUNK_RATE = 12 -- studs/s: T-223's threshold on the travel closing, for the readout

type Clip = { Id: string, Start: number, Length: number, Gain: number, Speed: number? }

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
		-- per wheel, last step: its ground's height and where it stood (nil: not to be trusted)
		prevGround: { number },
		prevX: { number },
		prevZ: { number },
		havePrev: { boolean },
		prevTravel: { number },
		-- per wheel, while it is off its ground (drawn falling, or hanging): the ground it left
		-- and where it stood then. A catch is measured against it
		leftGround: { number },
		leftX: { number },
		leftZ: { number },
		away: { boolean },
		readyAt: { number }, -- per wheel: the clock at which it may clunk again
		armed: { boolean }, -- per wheel: its ground has eased off since its last clunk
		gapUntil: number, -- the clock before which no wheel clunks (`ClunkGap`)
		quietUntil: number, -- the clock before which no wheel clunks (`LandQuiet`)
		airTime: number, -- s with no wheel down, so far
		airSpeed: number, -- studs/s, the fastest fall of this time in the air
		lastClip: number,
		-- the readout (`DebugState`, `ResetMeasure`)
		clunks: number,
		catches: number, -- of `clunks`, the ones that were a wheel stepping down
		perWheel: { number }, -- clunks per wheel
		landings: number,
		touchdowns: number, -- landings that were too soft to play
		held: number, -- clunks that would have played but for a cooldown, the gap or a landing
		maxRate: { number }, -- per wheel, the most its ground rose over its plane, studs/s
		maxDrop: { number }, -- per wheel, the furthest its ground fell while it was off it, studs
		notes: { any }, -- the steps a wheel's ground rose at half `ClunkRate` or more
		-- THE OLD RULE, counted and never played (T-252's before-and-after): a down wheel's
		-- travel closing faster than T-223's 12 studs/s, each wheel on its own cooldown
		maxClose: { number },
		closeClunks: number,
		closeReadyAt: { number },
		log: { any },
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

-- The clunk's volume for a wheel's ground rising `rate` studs/s over its plane, on a car going
-- `speed` studs/s, before the master: 0 under the threshold. Pure, for the readout and tests.
function SuspensionSound.clunkVolume(rate: number, speed: number): number
	local S = Config.Fx.Suspension
	if rate < S.ClunkRate then
		return 0
	end
	local t = clamp01((rate - S.ClunkRate) / math.max(S.ClunkRateForMax - S.ClunkRate, 1e-6))
	local share = math.clamp(speed / math.max(S.ClunkSpeedForFull, 1e-6), S.ClunkSlowShare, 1)
	return lerp(S.ClunkMinVolume, S.ClunkMaxVolume, t) * share
end

-- A wheel caught on ground `drop` studs lower than it left: the clunk of a step up that high,
-- made in one step of `dt`, times `CatchShare`; 0 under `CatchMin`.
function SuspensionSound.catchVolume(drop: number, speed: number, dt: number): number
	local S = Config.Fx.Suspension
	if drop < S.CatchMin or S.CatchShare <= 0 then
		return 0
	end
	local rate = math.max(drop / math.max(dt, 1e-6), S.ClunkRate)
	return SuspensionSound.clunkVolume(rate, speed) * S.CatchShare
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
		prevGround = table.create(WHEELS, 0),
		prevX = table.create(WHEELS, 0),
		prevZ = table.create(WHEELS, 0),
		havePrev = table.create(WHEELS, false),
		prevTravel = { -1, 0, 0, 0 }, -- -1: no travel yet, `Step` takes the first as it is
		leftGround = table.create(WHEELS, 0),
		leftX = table.create(WHEELS, 0),
		leftZ = table.create(WHEELS, 0),
		away = table.create(WHEELS, false),
		readyAt = table.create(WHEELS, 0),
		armed = table.create(WHEELS, true),
		gapUntil = 0,
		quietUntil = 0,
		airTime = 0,
		airSpeed = 0,
		lastClip = 0,
		clunks = 0,
		catches = 0,
		perWheel = table.create(WHEELS, 0),
		landings = 0,
		touchdowns = 0,
		held = 0,
		maxRate = table.create(WHEELS, 0),
		maxDrop = table.create(WHEELS, 0),
		notes = {},
		maxClose = table.create(WHEELS, 0),
		closeClunks = 0,
		closeReadyAt = table.create(WHEELS, 0),
		log = {},
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
	-- The player's Suspension level on top of the mix (Settings, Sound; T-256).
	SoundLevels.apply(sound, "Suspension")
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
			local sound = newSound(string.format(S.ClunkName, i), body)
			-- The id now, so the file is loading before the first knock rather than on it.
			sound.SoundId = S.Clunks[(i - 1) % #S.Clunks + 1].Id
			table.insert(self.voices, sound)
		end
	end
	if S.Landing then
		self.landing = newSound(S.LandingName, body)
		self.landing.SoundId = S.Landing.Id
	end
	self.body = body
	return true
end

-- Forget the wheels and the air: a respawn or a car handed out. Nothing carries across it.
function SuspensionSound.Cut(self: SuspensionSound)
	self.airTime = 0
	self.airSpeed = 0
	self.gapUntil = 0
	self.quietUntil = 0
	for i = 1, WHEELS do
		self.havePrev[i] = false
		self.readyAt[i] = 0
		self.armed[i] = true
		self.away[i] = false
	end
	self.prevTravel[1] = -1 -- no travel yet: `Step` takes the first one as it is
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
	sound.PlaybackSpeed = speed * (clip.Speed or 1)
	-- Roblox caps a Sound's Volume at 10; said here rather than left to the engine.
	sound.Volume = math.min(volume * (clip.Gain or 1) * Config.Fx.Suspension.Volume, 10)
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

-- One wheel's clunk, if it is free to: its own cooldown, the gap, a landing's quiet.
function SuspensionSound._clunk(
	self: SuspensionSound,
	i: number,
	rate: number,
	volume: number,
	speed: number,
	catch: boolean,
	surface: string?
)
	local S = Config.Fx.Suspension
	local now = self.clock
	if volume <= 0 then
		return
	end
	if now < self.readyAt[i] or now < self.gapUntil or now < self.quietUntil then
		self.held += 1
		return
	end
	self.clunks += 1
	self.perWheel[i] += 1
	if catch then
		self.catches += 1
	end
	self.readyAt[i] = now + S.ClunkCooldown
	self.gapUntil = math.max(self.gapUntil, now + S.ClunkGap)
	local entry = { at = now, wheel = i, rate = rate, speed = speed, volume = volume, catch = catch, surface = surface }
	self.lastClunk = entry
	if #self.log < LOG_MAX then
		table.insert(self.log, entry)
	end
	self:_playClunk(volume)
end

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
	-- The FASTEST fall of the air, not the last step's: the step a wheel reaches its bump
	-- stop, the stop takes the closing speed out of the body (`Suspension.ride`) before the
	-- model counts that wheel as down, so the last airborne step already reads near zero.
	if not anyDown then
		self.airTime += dt
		self.airSpeed = math.max(self.airSpeed, -s.velocity.Y)
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
			self.quietUntil = math.max(self.quietUntil, now + S.LandQuiet)
		end
		self.airTime = 0
		self.airSpeed = 0
	end

	-- THE CAR'S FRAME, as `Suspension.draw` placed the wheels in it this step.
	local D = Config.Drift
	local P = D.Suspension
	local rest, full = P.Rest, P.Travel
	local fall = full / math.max(P.DropTime, 1e-4) * dt
	local fwd, right, u = Suspension.basis(s.yaw, s.up)
	local uy = math.max(u.Y, 0.3)
	local halfBase, halfTrack = D.Wheelbase * 0.5, D.TrackWidth * 0.5
	local y = s.position.Y
	local flatF, flatR = DriftModel.axes(s.yaw)
	local px, pz = s.position.X, s.position.Z
	local n: Vector3 = s.groundUp
	local speed = DriftModel.speed(state)
	local firstTravel = self.prevTravel[1] < 0

	for i = 1, WHEELS do
		local t = travel[i]
		local pt = if firstTravel then t else self.prevTravel[i]
		-- Drawn FALLING: the travel opened by all `DropTime` lets it, so the wheel is not on
		-- its ground this step, wherever that is.
		local falling = pt - t >= fall * 0.9 and t < pt
		local onGround = down[i] == true and not falling and t < full - 1e-3

		-- The old rule, for the readout only.
		if not firstTravel and down[i] == true and t > pt then
			local close = (t - pt) / dt
			if close > self.maxClose[i] then
				self.maxClose[i] = close
			end
			if close >= OLD_CLUNK_RATE and now >= self.closeReadyAt[i] and now >= self.quietUntil then
				self.closeClunks += 1
				self.closeReadyAt[i] = now + S.ClunkCooldown
			end
		end

		-- Where the wheel stands, flat, and the height of its ground in the world.
		local wx = px + flatF.X * (halfBase * FRONT[i]) + flatR.X * (halfTrack * SIDE[i])
		local wz = pz + flatF.Z * (halfBase * FRONT[i]) + flatR.Z * (halfTrack * SIDE[i])
		local corner = y + right.Y * (SIDE[i] * halfTrack) - u.Y * D.RideHeight + fwd.Y * (FRONT[i] * halfBase)
		local ground = corner + (t - rest) * uy

		-- THE CATCH: a wheel back on its ground after being off it. Off it is drawn falling
		-- or hanging, which the BODY rising off a bump does too -- so what knocks is how far
		-- the GROUND fell meanwhile, against the plane the car is on: a bouncing body comes
		-- back down to the ground it left and is silent.
		if falling or down[i] ~= true then
			if not self.away[i] and self.havePrev[i] then
				self.away[i] = true
				self.leftGround[i] = self.prevGround[i]
				self.leftX[i], self.leftZ[i] = self.prevX[i], self.prevZ[i]
			end
		elseif self.away[i] then
			self.away[i] = false
			local dx, dz = wx - self.leftX[i], wz - self.leftZ[i]
			local planeRise = if n.Y > 0.3 then -(n.X * dx + n.Z * dz) / n.Y else 0
			local drop = self.leftGround[i] + planeRise - ground
			if drop > self.maxDrop[i] then
				self.maxDrop[i] = drop
			end
			local volume = SuspensionSound.catchVolume(drop, speed, dt)
			if volume > 0 then
				self:_clunk(i, drop / dt, volume, speed, true, s.wheelSurface[i])
			end
		end

		-- THE CLUNK: this wheel's ground rose faster than the plane the car is on says it should.
		if onGround and self.havePrev[i] then
			local dx, dz = wx - self.prevX[i], wz - self.prevZ[i]
			local planeRise = 0
			if n.Y > 0.3 then
				planeRise = -(n.X * dx + n.Z * dz) / n.Y
			end
			local rate = (ground - self.prevGround[i] - planeRise) / dt
			if rate > self.maxRate[i] then
				self.maxRate[i] = rate
			end
			if rate >= S.ClunkRate * 0.5 and #self.notes < LOG_MAX * 2 then
				table.insert(self.notes, {
					at = now,
					wheel = i,
					rate = rate,
					speed = speed,
					surface = s.wheelSurface[i],
					x = wx,
					z = wz,
				})
			end
			-- ONE knock a rise: the bevel lifts a wheel over several steps, so a wheel that has
			-- knocked waits for its ground to ease off (`ClunkRearm`) before it may again.
			if rate >= S.ClunkRate and self.armed[i] then
				self.armed[i] = false
				self:_clunk(i, rate, SuspensionSound.clunkVolume(rate, speed), speed, false, s.wheelSurface[i])
			elseif rate < S.ClunkRate * S.ClunkRearm then
				self.armed[i] = true
			end
		elseif not (down[i] == true and t >= full - 1e-3) then
			self.armed[i] = true -- off its ground; but not on its bump stop, mid-knock
		end

		self.havePrev[i] = onGround
		self.prevGround[i] = ground
		self.prevX[i], self.prevZ[i] = wx, wz
		self.prevTravel[i] = t
	end
end

--------------------------------------------------------------------------------
-- Readout
--------------------------------------------------------------------------------

-- The counts and the most each wheel's ground rose since the last call, and back to zero.
function SuspensionSound.ResetMeasure(self: SuspensionSound)
	local out = {
		clunks = self.clunks,
		catches = self.catches,
		perWheel = table.clone(self.perWheel),
		landings = self.landings,
		touchdowns = self.touchdowns,
		held = self.held,
		maxRate = table.clone(self.maxRate),
		maxDrop = table.clone(self.maxDrop),
		maxClose = table.clone(self.maxClose),
		closeClunks = self.closeClunks,
		log = self.log,
		notes = self.notes,
		lastClunk = self.lastClunk,
		lastLanding = self.lastLanding,
	}
	self.clunks, self.catches, self.landings, self.touchdowns, self.held = 0, 0, 0, 0, 0
	for i = 1, WHEELS do
		self.maxRate[i] = 0
		self.maxDrop[i] = 0
		self.maxClose[i] = 0
		self.perWheel[i] = 0
	end
	self.closeClunks = 0
	self.log = {}
	self.notes = {}
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
		catches = self.catches,
		perWheel = table.clone(self.perWheel),
		landings = self.landings,
		touchdowns = self.touchdowns,
		held = self.held,
		maxRate = table.clone(self.maxRate),
		maxDrop = table.clone(self.maxDrop),
		maxClose = table.clone(self.maxClose), -- the old rule's signal: travel closing, studs/s
		closeClunks = self.closeClunks, -- the old rule's clunks: counted, never played
		ground = table.clone(self.prevGround),
		airTime = self.airTime,
		lastClunk = self.lastClunk,
		lastLanding = self.lastLanding,
		clunkRate = S.ClunkRate,
		landAirTime = S.LandAirTime,
		landMinSpeed = S.LandMinSpeed,
	}
end

return SuspensionSound
