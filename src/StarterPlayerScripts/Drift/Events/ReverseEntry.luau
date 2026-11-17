--!strict
-- ReverseEntry: the "reverse entry" conditional score event (features/score-events.md
-- "The user's revision", T-299). A detector on the shared interface: `new(sink, rig)`,
-- `Update(dt, state)`, `DebugState()`; it only calls `sink.start` and its handle.
--
-- THE RULE (the user's): going into a hairpin, the car turns past 90 degrees towards the
-- hairpin, so it is going backwards; it must then carry on in a drift (at least 2 wheels)
-- through the rest of the hairpin to complete.
--
--   STARTS when the slip angle passes `AngleDegrees` (90) turned INTO the hairpin (the
--   nose swung toward the bend's inside, past square to the travel), above `MinSpeed`, on
--   the ground, anywhere from the hairpin's entry zone to its exit (`Road/Hairpins`). One
--   attempt per hairpin.
--   HOLDS while it drifts (`state.drifting`) with at least 2 wheels sliding
--   (`PerfectHairpin.slidingWheels`), above `MinSpeed`, either way round: once it is past
--   90 the drift may swing back. A lapse of up to `Grace` is forgiven.
--   COMPLETES (finish true) when the car passes the hairpin's exit still holding. The handle
--   is updated each frame with size 1.
--   VOIDS (finish false) when the drift breaks, the car falls, is put back, leaves the road's
--   reach, goes back out of the zone, takes longer than `MaxSeconds`, or the road changes.
--   Leaving the tarmac does NOT void it: only the perfect hairpin asks for a side.
--
-- `rig` as `PerfectHairpin`'s: anything with a `spline` field (a Spline or a function).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)
local PerfectHairpin = require(script.Parent.PerfectHairpin)

local ReverseEntry = {}
ReverseEntry.__index = ReverseEntry

ReverseEntry.Kind = "reverseEntry"

-- The numbers: `Config.ScoreEvents.Detectors.ReverseEntry`.
ReverseEntry.Tuning = Config.ScoreEvents.Detectors.ReverseEntry

local function hairpinInfo(h: Hairpins.Hairpin?): any
	if not h then
		return nil
	end
	return { zone = h.zone, entry = h.entry, apex = h.apex, exit = h.exit, dir = h.dir, radius = h.radius, turn = h.turn, open = h.open }
end

function ReverseEntry.new(sink: any, rig: any)
	return setmetatable({
		sink = sink,
		rig = rig,
		spline = nil :: any,
		s = nil :: number?,
		d = nil :: number?,
		hairpin = nil :: Hairpins.Hairpin?,
		marking = { false, false, false, false },
		sliding = 0,
		badDrift = math.huge,
		peakDegrees = 0, -- the largest slip into the hairpin during the live attempt
		tried = {} :: { [number]: boolean },
		handle = nil :: any,
		live = nil :: Hairpins.Hairpin?,
		elapsed = 0,
		stats = { started = 0, completed = 0, voided = 0 },
		last = nil :: any,
	}, ReverseEntry)
end

function ReverseEntry._end(self: any, completed: boolean, reason: string)
	local h = self.live
	if self.handle then
		self.handle:finish(completed)
	end
	if completed then
		self.stats.completed += 1
	else
		self.stats.voided += 1
	end
	self.last = {
		result = if completed then "completed" else "void",
		reason = reason,
		entry = h and h.entry,
		seconds = self.elapsed,
		peakDegrees = self.peakDegrees,
	}
	self.handle = nil
	self.live = nil
end

function ReverseEntry.Update(self: any, dt: number, state: any)
	local T = ReverseEntry.Tuning
	local spline = PerfectHairpin.splineOf(self.rig)
	if spline ~= self.spline then
		if self.live then
			self:_end(false, "road changed")
		end
		self.spline = spline
		self.s, self.d, self.hairpin = nil, nil, nil
		self.tried = {}
	end
	if not spline then
		return
	end
	local prevS = self.s
	local s, d = Hairpins.locate(spline, state.position, prevS)
	self.s, self.d = s, d
	if not s or not d then
		if self.live then
			self:_end(false, "off the road")
		end
		return
	end
	local jumped = prevS ~= nil and math.abs(s - prevS) > T.JumpStuds
	if jumped then
		self.tried = {} -- put back on the road: every hairpin is a fresh attempt
	end

	local n = PerfectHairpin.slidingWheels(state, self.marking)
	self.sliding = n
	local speedOk = PerfectHairpin.speed(state) >= Config.Fx.Gates.MinMarkSpeed
	local drifting = state.drifting and not state.airborne and speedOk and n >= 2
	if drifting then
		self.badDrift = 0
	else
		self.badDrift += dt
	end

	if self.live then
		local live = self.live
		self.elapsed += dt
		if -state.slip * live.dir > 0 then
			self.peakDegrees = math.max(self.peakDegrees, math.deg(math.abs(state.slip)))
		end
		if state.fell then
			self:_end(false, "fell")
		elseif jumped then
			self:_end(false, "put back")
		elseif s < live.zone then
			self:_end(false, "went back")
		elseif self.badDrift > T.Grace then
			self:_end(false, "drift broken")
		elseif self.elapsed > T.MaxSeconds then
			self:_end(false, "too long")
		elseif s >= live.exit then
			self:_end(true, "through")
		else
			self.handle:update(1, dt)
		end
		return
	end

	local h = self.hairpin
	if not h or h.open or s < h.zone or s > h.exit then
		h = Hairpins.around(spline, s)
		self.hairpin = h
	end
	if not h or h.open or jumped or self.tried[h.entry] or s >= h.exit then
		return
	end
	-- past 90, turned into the hairpin: the nose toward the bend's inside
	local into = -state.slip * h.dir
	if into > math.rad(T.AngleDegrees) and speedOk and not state.airborne and not state.fell then
		self.tried[h.entry] = true
		self.live = h
		self.elapsed = 0
		self.peakDegrees = math.deg(into)
		self.badDrift = 0
		self.stats.started += 1
		self.handle = self.sink.start(ReverseEntry.Kind, {
			entry = h.entry,
			exit = h.exit,
			dir = h.dir,
			radius = h.radius,
			at = s,
			angle = math.deg(into),
		})
	end
end

function ReverseEntry.DebugState(self: any): any
	return {
		s = self.s,
		d = self.d,
		hairpin = hairpinInfo(self.hairpin),
		live = self.live ~= nil,
		liveHairpin = hairpinInfo(self.live),
		sliding = self.sliding,
		badDrift = self.badDrift,
		elapsed = self.elapsed,
		peakDegrees = self.peakDegrees,
		stats = table.clone(self.stats),
		last = self.last and table.clone(self.last),
	}
end

return ReverseEntry
