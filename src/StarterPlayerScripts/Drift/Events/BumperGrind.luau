--!strict
-- BumperGrind: the bumper scraping along the barrier rail, held (features/score-events.md,
-- "The user's revision": sort of hard, a medium boost; T-297).
--
-- A SUSTAINED event: it starts once a front or rear corner of the car has been on a K-rail
-- for `MinHold`, sliding along it at `MinSpeed` or more after a gentle meeting (into the
-- rail at `MaxInto` or less); it is fed a size every frame while held; it ends cleanly
-- (`finish(true)`, banked) once the car has been off the rail for `Grace`, and is void
-- (`finish(false)`) on a crash -- a hard hit, or a big loss of speed -- or a fall or a
-- put-back.
--
-- WHAT IT READS, all from the drift model's state (`Drift/Model`): the wall the car met and
-- which part of it met it (`wallKind`, `wallPoint`, `wallSide`, `wallInto`, `wallAlong`,
-- `wallNormal`), held for `WallContactGrace` as `wallTouch`, and `sinceWall`. A car leaning
-- on a rail meets it on some steps and not others, so contact is "met it within `Grace`",
-- never "met it this step".
--
-- A BUMPER, NOT A DOOR: the point on the rail must be one end's corner (`wallPoint` "front"
-- or "rear"), and the car must sit at least `MinAngle` off the rail's line. A car square
-- along the rail touches it with its whole side, and a door scrape is not this event.
--
-- ROCK DOESN'T COUNT. The user's words are "the barrier rail", and a rock cut beside a
-- mountain road is a steep slope the car is stopped at, not a rail it can slide along
-- (`Kinds` is a switch; turning rock on is one line).
--
-- THE SIZE, 0 .. 1 each frame: the speed along the rail (`MinSpeed` gives `SizeFloor`,
-- `FullSpeed` gives 1) times how steadily the car stays on it (the share of the last
-- `SteadySeconds` the model read it as touching).
--
-- The interface every detector shares (features/score-events.md "The shared interface"):
-- `new(sink, rig)`, `:Update(dt, state)` each frame with the model's state, `:DebugState()`.
-- It calls only `sink.start` and the handle's `update` and `finish`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local BumperGrind = {}
BumperGrind.__index = BumperGrind

BumperGrind.KIND = "bumperGrind"

-- Detection only: what counts as a bumper grind, and how big a frame of it is. Points,
-- caps and repeats are the engine's (`Config/ScoreEvents`).
BumperGrind.Tuning = {
	Kinds = { krail = true, rock = false }, -- the walls that count
	MinAngle = 6, -- degrees between the car's nose and the rail's line: less is its door
	MinSpeed = 40, -- studs/s along the rail to start
	KeepSpeed = 30, -- studs/s along the rail to keep going once started
	FullSpeed = 100, -- studs/s along the rail for the speed's full share
	SizeFloor = 0.3, -- the size at `MinSpeed`, steadily on the rail
	MaxInto = 25, -- studs/s into the rail when it is met: harder is a crash
	MinHold = 0.12, -- s on the rail before the event starts
	MinContacts = 2, -- separate meetings with the rail within that, so one knock is not a grind
	Grace = 0.25, -- s off the rail before it ends
	CrashLoss = 0.4, -- a share of the speed lost within `CrashWindow` that is a crash
	CrashWindow = 0.35, -- s
	SteadySeconds = 0.4, -- s the steadiness is averaged over
	PutBack = 30, -- studs moved in one frame past where the car could get: a put-back
}

export type Sink = {
	oneOff: (kind: string, size: number, info: {}?) -> (),
	start: (kind: string, info: {}?) -> any,
}

local HISTORY = 64 -- frames of speed kept for the crash check

local function flatSpeed(v: Vector3): number
	return math.sqrt(v.X * v.X + v.Z * v.Z)
end

function BumperGrind.new(sink: Sink, rig: any?)
	local self = setmetatable({
		sink = sink,
		rig = rig,
		handle = nil :: any,
		phase = "idle", -- "idle" | "live"
		held = 0, -- s the start condition has held
		contacts = 0, -- meetings with the rail while it held
		sinceGood = math.huge, -- s since a frame that met the rail as a bumper grind wants
		steady = 0, -- 0 .. 1, the share of recent time read as touching
		size = 0,
		along = 0,
		angle = 0,
		live = 0, -- s the current event has run
		info = nil :: { [string]: any }?,
		lastPos = nil :: Vector3?,
		times = table.create(HISTORY, 0),
		speeds = table.create(HISTORY, 0),
		head = 0,
		clock = 0,
		-- what happened, for tests and the drive log
		started = 0,
		banked = 0,
		voided = 0,
		lastEnd = "",
	}, BumperGrind)
	return self
end

export type BumperGrind = typeof(BumperGrind.new(nil :: any))

-- The car's angle off the rail's line, degrees: 0 square along it, 90 nose-on.
local function angleOff(state: any): number
	local n: Vector3 = state.wallNormal
	local fx, fz = -math.sin(state.yaw), -math.cos(state.yaw)
	local nn = math.sqrt(n.X * n.X + n.Z * n.Z)
	if nn < 1e-6 then
		return 0
	end
	return math.deg(math.asin(math.clamp(math.abs(fx * n.X + fz * n.Z) / nn, 0, 1)))
end

local function finish(self: BumperGrind, completed: boolean, why: string)
	local handle = self.handle
	self.handle = nil
	self.phase = "idle"
	self.held = 0
	self.contacts = 0
	self.live = 0
	self.info = nil
	self.lastEnd = why
	if handle then
		handle:finish(completed)
		if completed then
			self.banked += 1
		else
			self.voided += 1
		end
	end
end

-- The most speed the car had within `CrashWindow`.
local function recentPeak(self: BumperGrind, window: number): number
	local peak = 0
	for k = 1, HISTORY do
		if self.clock - self.times[k] <= window then
			peak = math.max(peak, self.speeds[k])
		end
	end
	return peak
end

function BumperGrind.Update(self: BumperGrind, dt: number, state: any)
	local T = BumperGrind.Tuning
	if not state or dt <= 0 then
		return
	end
	self.clock += dt
	local speed = flatSpeed(state.velocity)
	self.head = self.head % HISTORY + 1
	self.times[self.head] = self.clock
	self.speeds[self.head] = speed

	-- a put-back or a teleport: further in one frame than the car could have gone
	local pos: Vector3 = state.position
	local jumped = false
	if self.lastPos then
		jumped = (pos - self.lastPos :: Vector3).Magnitude > speed * dt * 2 + T.PutBack
	end
	self.lastPos = pos

	-- what this frame met: a wall, during this frame's steps
	local met = state.sinceWall <= dt + 1e-6
	local touching = state.wallTouch == true
	local kindOk = T.Kinds[state.wallKind] == true
	local bumper = state.wallPoint == "front" or state.wallPoint == "rear"
	self.angle = if touching then angleOff(state) else 0
	self.along = if touching then state.wallAlong else 0
	local forward = state.u > 0 and not state.pinned
	local need = if self.phase == "live" then T.KeepSpeed else T.MinSpeed
	local good = touching and kindOk and bumper and forward and self.angle >= T.MinAngle and self.along >= need
	if met and good then
		self.sinceGood = 0
	else
		self.sinceGood += dt
	end
	local a = math.clamp(dt / math.max(T.SteadySeconds, 1e-3), 0, 1)
	self.steady += ((if touching and kindOk then 1 else 0) - self.steady) * a

	if self.phase == "live" then
		self.live += dt
		-- void: a fall, a put-back, a hard hit, or a big loss of speed
		if state.fell or jumped then
			finish(self, false, if jumped then "putBack" else "fell")
			return
		end
		if met and state.wallInto > T.MaxInto then
			finish(self, false, "crash")
			return
		end
		local peak = recentPeak(self, T.CrashWindow)
		if peak > 0 and speed < peak * (1 - T.CrashLoss) then
			finish(self, false, "crash")
			return
		end
		if self.sinceGood > T.Grace then
			finish(self, true, "clear")
			return
		end
		local share = math.clamp((self.along - T.MinSpeed) / math.max(T.FullSpeed - T.MinSpeed, 1e-3), 0, 1)
		local size = (T.SizeFloor + (1 - T.SizeFloor) * share) * math.clamp(self.steady, 0, 1)
		if self.sinceGood > 0 and not touching then
			size = 0 -- in a gap: nothing earned until it is back on the rail
		end
		self.size = size
		self.handle:update(size, dt)
		return
	end

	-- idle: has the start condition held long enough?
	self.size = 0
	if state.fell or jumped then
		self.held, self.contacts = 0, 0
		return
	end
	if self.sinceGood <= T.Grace and (self.held > 0 or (met and good)) then
		if met and good then
			if state.wallInto > T.MaxInto then
				self.held, self.contacts = 0, 0 -- met it hard: a crash, not a grind
				return
			end
			self.contacts += 1
		end
		self.held += dt
		if self.held >= T.MinHold and self.contacts >= T.MinContacts then
			self.info = { wall = state.wallKind, point = state.wallPoint, side = state.wallSide }
			self.handle = self.sink.start(BumperGrind.KIND, self.info)
			self.phase = "live"
			self.live = 0
			self.started += 1
		end
	else
		self.held, self.contacts = 0, 0
	end
end

function BumperGrind.DebugState(self: BumperGrind)
	return {
		kind = BumperGrind.KIND,
		phase = self.phase,
		held = self.held,
		contacts = self.contacts,
		sinceGood = self.sinceGood,
		steady = self.steady,
		size = self.size,
		along = self.along,
		angle = self.angle,
		live = self.live,
		info = self.info,
		started = self.started,
		banked = self.banked,
		voided = self.voided,
		lastEnd = self.lastEnd,
	}
end

return BumperGrind
