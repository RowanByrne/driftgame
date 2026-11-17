--!strict
-- HangGrind: the two back wheels hanging in the air while the car's underside scrapes round
-- an edge (features/score-events.md, "The user's revision": difficult, a big boost; T-297).
--
-- A SUSTAINED event: it starts once the floor has rested on an edge with both rear wheels
-- off the ground (the model's floor solve: `hanging`, `floorContacts`, `wheelsDown`) for
-- `MinHold`, sliding at `MinSpeed` or more; it is fed a size every frame while held; and
-- when the condition lapses for `Grace` it ends:
--
--   banked (`finish(true)`)  the car is back on the ground at about the edge's height:
--                            it pulled itself back on, or slid clear along the edge
--   void (`finish(false)`)   it went over: it is in the air, or on ground more than
--                            `DropBelow` under the edge it hung from, or it fell (`fell`),
--                            or it was put back on the road
--
-- A car that leaves the edge in the air, or tips on over it on its floor, is not decided
-- until it is back on its wheels (or `Settle` has passed): the event is held open, earning
-- nothing, and banks or voids by where it ends up.
--
-- THE SIZE, 0 .. 1 each frame: how far out the car hangs (how much of its length is behind
-- the rearmost point its floor rests on, `HangFull` of the body for the full share) and how
-- fast its floor slides over the edge (`MinSpeed` to `FullSpeed`), half each.
--
-- THE FRONT AXLE: the user named the back wheels; `FrontAxle` lets a nose hanging over an
-- edge count too.
--
-- The interface every detector shares (features/score-events.md "The shared interface"):
-- `new(sink, rig)`, `:Update(dt, state)` each frame with the model's state, `:DebugState()`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HangGrind = {}
HangGrind.__index = HangGrind

HangGrind.KIND = "hangGrind"

-- Detection only: what counts as a hang grind, and how big a frame of it is. Points, caps
-- and repeats are the engine's (`Config/ScoreEvents`).
HangGrind.Tuning = {
	FrontAxle = false, -- a nose hanging over an edge counts too
	MinSpeed = 4, -- studs/s the floor slides over the edge, to start
	FullSpeed = 20, -- studs/s for the speed's full share
	HangFull = 0.45, -- share of the body's length behind the edge for the hang's full share
	MinHold = 0.15, -- s hanging before the event starts
	Grace = 0.2, -- s not hanging before it ends
	DropBelow = 2.5, -- studs under the edge's height that is a fall off it
	Settle = 2, -- s a car that left the edge in the air is waited for
	PutBack = 30, -- studs moved in one frame past where the car could get: a put-back
}

export type Sink = {
	oneOff: (kind: string, size: number, info: {}?) -> (),
	start: (kind: string, info: {}?) -> any,
}

function HangGrind.new(sink: Sink, rig: any?)
	local self = setmetatable({
		sink = sink,
		rig = rig,
		handle = nil :: any,
		phase = "idle", -- "idle" | "live" | "settling"
		held = 0,
		sinceGood = math.huge,
		live = 0,
		settling = 0,
		edgeY = 0, -- the height of the edge it hangs from
		axle = "",
		hang = 0, -- 0 .. 1 share of the body behind the edge
		slide = 0, -- studs/s, the floor's fastest point over the edge
		size = 0,
		info = nil :: { [string]: any }?,
		lastPos = nil :: Vector3?,
		started = 0,
		banked = 0,
		voided = 0,
		lastEnd = "",
	}, HangGrind)
	return self
end

export type HangGrind = typeof(HangGrind.new(nil :: any))

-- Which axle hangs: both its wheels off their ground while the floor rests on something.
-- "rear", "front", or "" for neither (or both: the whole car on its floor is not a hang).
function HangGrind.axle(state: any): string
	if not state.hanging or (state.floorTouching or 0) <= 0 or state.airborne then
		return ""
	end
	local w = state.wheelsDown
	local rearOff = not w[3] and not w[4]
	local frontOff = not w[1] and not w[2]
	if rearOff and not frontOff then
		return "rear"
	elseif frontOff and not rearOff then
		return "front"
	end
	return ""
end

-- How far out the car hangs past the edge its floor rests on, as a share of its length, and
-- the edge's height and the floor's fastest slide over it.
function HangGrind.measure(state: any, axle: string): (number, number, number)
	local fx, fz = -math.sin(state.yaw), -math.cos(state.yaw)
	local pos: Vector3 = state.position
	local least, most, ySum, n, fastest = math.huge, -math.huge, 0, 0, 0
	for _, c in state.floorContacts do
		local p: Vector3 = c.position
		local z = (p.X - pos.X) * fx + (p.Z - pos.Z) * fz -- + toward the nose
		least = math.min(least, z)
		most = math.max(most, z)
		ySum += p.Y
		n += 1
		fastest = math.max(fastest, c.speed)
	end
	if n == 0 then
		return 0, pos.Y, 0
	end
	local half = Config.Drift.BodyLength * 0.5
	-- the length of body beyond the last point it rests on, on the hanging end
	local out = if axle == "front" then half - most else least + half
	return math.clamp(out / Config.Drift.BodyLength, 0, 1), ySum / n, fastest
end

local function finish(self: HangGrind, completed: boolean, why: string)
	local handle = self.handle
	self.handle = nil
	self.phase = "idle"
	self.held = 0
	self.live = 0
	self.settling = 0
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

-- Off the edge for good: banked if the car is down near the edge's height, void if below it.
local function decide(self: HangGrind, state: any)
	local T = HangGrind.Tuning
	local feet = state.position.Y - Config.Drift.RideHeight
	if feet < self.edgeY - T.DropBelow then
		finish(self, false, "wentOver")
	else
		finish(self, true, "clear")
	end
end

function HangGrind.Update(self: HangGrind, dt: number, state: any)
	local T = HangGrind.Tuning
	if not state or dt <= 0 then
		return
	end
	local v: Vector3 = state.velocity
	local speed = math.sqrt(v.X * v.X + v.Z * v.Z)
	local pos: Vector3 = state.position
	local jumped = false
	if self.lastPos then
		jumped = (pos - self.lastPos :: Vector3).Magnitude > speed * dt * 2 + T.PutBack
	end
	self.lastPos = pos

	local axle = HangGrind.axle(state)
	if axle == "front" and not T.FrontAxle then
		axle = ""
	end
	if axle ~= "" then
		self.hang, self.edgeY, self.slide = HangGrind.measure(state, axle)
	else
		self.hang, self.slide = 0, 0
	end
	local need = T.MinSpeed * (if self.phase == "live" then 0.5 else 1)
	local good = axle ~= "" and self.slide >= need and not state.pinned
	if good then
		self.sinceGood = 0
	else
		self.sinceGood += dt
	end

	if self.phase ~= "idle" then
		self.live += dt
		if state.fell or jumped then
			finish(self, false, if jumped then "putBack" else "fell")
			return
		end
		if self.phase == "settling" then
			self.settling += dt
			self.size = 0
			if good then
				self.phase = "live" -- caught on the edge again
			elseif not state.airborne and not state.hanging then
				decide(self, state) -- back on its wheels: where?
				return
			elseif self.settling > T.Settle then
				decide(self, state)
				return
			else
				self.handle:update(0, dt)
				return
			end
		end
		if self.sinceGood > T.Grace then
			-- in the air, or still on its floor (tipping on over the edge, both axles off):
			-- not decided until it is back on its wheels
			if state.airborne or state.hanging then
				self.phase = "settling"
				self.settling = 0
				self.size = 0
				self.handle:update(0, dt)
			else
				decide(self, state)
			end
			return
		end
		local speedShare = math.clamp((self.slide - T.MinSpeed) / math.max(T.FullSpeed - T.MinSpeed, 1e-3), 0, 1)
		local hangShare = math.clamp(self.hang / math.max(T.HangFull, 1e-3), 0, 1)
		local size = if good then 0.5 * hangShare + 0.5 * speedShare else 0
		self.size = size
		self.handle:update(size, dt)
		return
	end

	self.size = 0
	if good and not state.fell and not jumped then
		self.held += dt
		if self.held >= T.MinHold then
			self.axle = axle
			self.info = { axle = axle }
			self.handle = self.sink.start(HangGrind.KIND, self.info)
			self.phase = "live"
			self.live = 0
			self.started += 1
		end
	else
		self.held = 0
	end
end

function HangGrind.DebugState(self: HangGrind)
	return {
		kind = HangGrind.KIND,
		phase = self.phase,
		held = self.held,
		sinceGood = self.sinceGood,
		hang = self.hang,
		slide = self.slide,
		edgeY = self.edgeY,
		size = self.size,
		live = self.live,
		info = self.info,
		started = self.started,
		banked = self.banked,
		voided = self.voided,
		lastEnd = self.lastEnd,
	}
end

return HangGrind
