--!strict
-- PerfectHairpin: the "perfect hairpin" conditional score event (features/score-events.md
-- "The user's revision", T-299). A detector on the shared interface ("The shared
-- interface"): `new(sink, rig)`, `Update(dt, state)` each frame with the drift model's
-- state, `DebugState()`. It only ever calls `sink.start` and the handle it gets back.
--
-- THE RULE (the user's): a sustained drift through the whole hairpin while staying on your
-- own side of the road, never crossing the double yellow. Two levels: a 2-wheel drift the
-- whole way, and a 4-wheel drift the whole way, worth twice as much.
--
--   STARTS when the car crosses a hairpin's entry (`Road/Hairpins`) drifting the hairpin's
--   way with at least 2 wheels sliding. Not drifting there: no attempt at this hairpin.
--   "YOUR OWN SIDE" is the side of the double yellow the car's centre is on at the entry
--   (a car on the paint there does not start). One attempt per hairpin.
--   HOLDS while it drifts the hairpin's way (`state.drifting`, the slip turned into the
--   bend) with at least 2 wheels sliding, above `MinSpeed`. A lapse of up to `Grace` is
--   forgiven, as the sustained events forgive one.
--   THE LEVEL starts at 4 if all four wheels slide at the entry, and drops to 2 for good
--   once fewer than four have slid for longer than `Grace`. The handle is updated each frame
--   with size 1 while the 4-wheel level holds and 0.5 at the 2-wheel level, so a 4-wheel
--   hairpin earns twice a 2-wheel one (the engine's points per kind times size).
--   COMPLETES (finish true) when the car passes the hairpin's exit still holding.
--   VOIDS (finish false) when the drift breaks, any wheel goes over the double yellow (its
--   centre past the paint's far edge), the car's centre leaves the tarmac, it falls, it is
--   put back (a jump along the road), it goes back out of the zone, or the road changes.
--
-- WHICH WHEELS SLIDE: each wheel's slip gate in `Drift/Wheels.evaluate` (the rears past
-- `Gates.MinSlipDegrees`, the fronts past `MaxSteerDegrees` more, with the marks' own
-- hysteresis), on the ground. The same gate that lays each wheel's tyre mark, so "4-wheel"
-- is the drift that marks with all four. Exported as `slidingWheels` for the other
-- hairpin detectors.
--
-- `rig` is anything with a `spline` field: the road (`Road/Spline`), or a function that
-- returns it (nil off the spline road, where nothing is detected).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)
local Wheels = require(script.Parent.Parent.Wheels)

local PerfectHairpin = {}
PerfectHairpin.__index = PerfectHairpin

PerfectHairpin.Kind = "perfectHairpin"

PerfectHairpin.Tuning = {
	Grace = 0.2, -- s a lapse of the drift (or of the fourth wheel) is forgiven
	JumpStuds = 80, -- studs along the road in one frame that can only be a put-back
	Size4 = 1, -- the handle's size at the 4-wheel level
	Size2 = 0.5, -- and at the 2-wheel level: half
}

-- Wheels FL FR RL RR, in the car's own axes (`Drift/Model`'s order)
local WHEELS = {
	{ front = 1, side = -1 },
	{ front = 1, side = 1 },
	{ front = -1, side = -1 },
	{ front = -1, side = 1 },
}

-- How many wheels are sliding, by each wheel's own slip gate (`Drift/Wheels.evaluate`),
-- on the ground. `marking` is four booleans kept by the caller between frames: the gate's
-- hysteresis, updated here.
function PerfectHairpin.slidingWheels(state: any, marking: { boolean }): number
	local n = 0
	for i, w in WHEELS do
		local down = state.wheelsDown[i] and not state.airborne
		local _, _, slipPast = Wheels.evaluate(state, false, w.front > 0, down, marking[i])
		local on = slipPast and down
		marking[i] = on
		if on then
			n += 1
		end
	end
	return n
end

-- The four wheels' distances across the road (d, studs right of the centre line), from
-- the car's (s, d) and its yaw: the smallest and the largest.
function PerfectHairpin.wheelSpan(state: any, spline: any, s: number, d: number): (number, number)
	local C = Config.Drift
	local hb, ht = C.Wheelbase * 0.5, C.TrackWidth * 0.5
	local sy, cy = math.sin(state.yaw), math.cos(state.yaw)
	local fx, fz = -sy, -cy -- the car's flat forward
	local rx, rz = cy, -sy -- and right
	local px, pz = Hairpins.rightAt(spline, s)
	local lo, hi = math.huge, -math.huge
	for _, w in WHEELS do
		local ox = fx * hb * w.front + rx * ht * w.side
		local oz = fz * hb * w.front + rz * ht * w.side
		local dw = d + ox * px + oz * pz
		lo = math.min(lo, dw)
		hi = math.max(hi, dw)
	end
	return lo, hi
end

function PerfectHairpin.speed(state: any): number
	return math.sqrt(state.u * state.u + state.v * state.v)
end

function PerfectHairpin.splineOf(rig: any): any?
	local sp = rig and rig.spline
	if type(sp) == "function" then
		sp = sp()
	end
	return sp
end

local function hairpinInfo(h: Hairpins.Hairpin?): any
	if not h then
		return nil
	end
	return { zone = h.zone, entry = h.entry, apex = h.apex, exit = h.exit, dir = h.dir, radius = h.radius, turn = h.turn, open = h.open }
end

function PerfectHairpin.new(sink: any, rig: any)
	local self = setmetatable({
		sink = sink,
		rig = rig,
		spline = nil :: any,
		s = nil :: number?,
		d = nil :: number?,
		hairpin = nil :: Hairpins.Hairpin?, -- the one around the car (zone to exit), cached
		marking = { false, false, false, false },
		sliding = 0,
		badDrift = math.huge, -- s the drift condition has been off
		bad4 = math.huge, -- s fewer than four wheels have slid
		tried = {} :: { [number]: boolean }, -- hairpins (by entry) already attempted
		-- the live attempt
		handle = nil :: any,
		live = nil :: Hairpins.Hairpin?,
		level = 0,
		side = 0,
		elapsed = 0,
		stats = { started = 0, completed = 0, voided = 0, level4 = 0 },
		last = nil :: any,
	}, PerfectHairpin)
	return self
end

function PerfectHairpin._end(self: any, completed: boolean, reason: string)
	local h = self.live
	if self.handle then
		self.handle:finish(completed)
	end
	if completed then
		self.stats.completed += 1
		if self.level == 4 then
			self.stats.level4 += 1
		end
	else
		self.stats.voided += 1
	end
	self.last = {
		result = if completed then "completed" else "void",
		reason = reason,
		level = self.level,
		entry = h and h.entry,
		seconds = self.elapsed,
	}
	self.handle = nil
	self.live = nil
end

function PerfectHairpin.Update(self: any, dt: number, state: any)
	local T = PerfectHairpin.Tuning
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

	-- the conditions, every frame, so the entry can ask "drifting just now?"
	local n = PerfectHairpin.slidingWheels(state, self.marking)
	self.sliding = n
	local h = self.hairpin
	if not h or h.open or s < h.zone or s > h.exit then
		h = Hairpins.around(spline, s)
		self.hairpin = h
	end
	local want = self.live or h
	local dir = if want then want.dir else 0
	local speedOk = PerfectHairpin.speed(state) >= Config.Fx.Gates.MinMarkSpeed
	local drifting = state.drifting and not state.airborne and speedOk and n >= 2 and dir ~= 0 and state.slip * dir < 0
	if drifting then
		self.badDrift = 0
	else
		self.badDrift += dt
	end
	if drifting and n == 4 then
		self.bad4 = 0
	else
		self.bad4 += dt
	end

	if self.live then
		local live = self.live
		self.elapsed += dt
		if state.fell then
			self:_end(false, "fell")
		elseif jumped then
			self:_end(false, "put back")
		elseif s < live.zone then
			self:_end(false, "went back")
		elseif self.badDrift > T.Grace then
			self:_end(false, "drift broken")
		elseif math.abs(d) > Config.Road.Width * 0.5 then
			self:_end(false, "off the tarmac")
		else
			local lo, hi = PerfectHairpin.wheelSpan(state, spline, s, d)
			local lineD = 0
			local crossed = if self.side > 0 then Hairpins.sideOf(lo, lineD) < 0 else Hairpins.sideOf(hi, lineD) > 0
			if crossed then
				self:_end(false, "crossed the line")
			else
				if self.level == 4 and self.bad4 > T.Grace then
					self.level = 2
				end
				if s >= live.exit then
					self:_end(true, "through")
				else
					self.handle:update(if self.level == 4 then T.Size4 else T.Size2, dt)
				end
			end
		end
		return
	end

	-- not live: crossing a hairpin's entry this frame?
	if h and not h.open and not jumped and prevS and prevS < h.entry and s >= h.entry and s <= h.exit and not self.tried[h.entry] then
		self.tried[h.entry] = true
		local lineD = Hairpins.lineAt(spline, s) or 0
		local side = Hairpins.sideOf(d, lineD)
		if self.badDrift <= T.Grace and side ~= 0 and math.abs(d) <= Config.Road.Width * 0.5 and not state.fell then
			self.live = h
			self.side = side
			self.level = if self.bad4 <= T.Grace then 4 else 2
			self.elapsed = 0
			self.stats.started += 1
			self.handle = self.sink.start(PerfectHairpin.Kind, {
				entry = h.entry,
				exit = h.exit,
				dir = h.dir,
				radius = h.radius,
				level = self.level,
				side = side,
			})
		else
			self.last = {
				result = "not started",
				reason = if side == 0 then "on the line" elseif self.badDrift > T.Grace then "not drifting" else "off the tarmac",
				entry = h.entry,
			}
		end
	end
end

function PerfectHairpin.DebugState(self: any): any
	return {
		s = self.s,
		d = self.d,
		hairpin = hairpinInfo(self.hairpin),
		live = self.live ~= nil,
		liveHairpin = hairpinInfo(self.live),
		level = self.level,
		side = self.side,
		sliding = self.sliding,
		badDrift = self.badDrift,
		elapsed = self.elapsed,
		stats = table.clone(self.stats),
		last = self.last and table.clone(self.last),
	}
end

return PerfectHairpin
