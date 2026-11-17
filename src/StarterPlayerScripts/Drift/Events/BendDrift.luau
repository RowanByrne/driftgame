--!strict
-- BendDrift: the one detector behind the bend events (features/score-events.md, T-299 and
-- its send-back): a drift held through a double-yellow bend or a hairpin (`Road/Hairpins`),
-- start to finish, inside some lines. Each event is a variant of it, set by a `spec`:
--
--   `Drift/Events/LaneDrift`         every bend; drifting into it on 2+ wheels; your own lane
--   `Drift/Events/PerfectLaneDrift`  every bend; all four wheels sliding the whole way; your lane
--   `Drift/Events/PerfectHairpin`    true hairpins only; any drift; between the white edge lines
--
-- A detector on the shared interface: `new(sink, rig, spec)`, `Update(dt, state)` each
-- simulation step with the drift model's state, `DebugState()`. It only ever calls
-- `sink.start` and the handle it gets back.
--
--   STARTS when the car crosses the bend's entry already holding the condition (within the
--   last `Grace`), with no more than `MaxWheelsOut` wheels out of its lines. One attempt per
--   bend; a put-back (the car `JumpStuds` along the road in one step) clears that.
--   HOLDS while the drift holds (`state.drifting`, on the ground, above the wheel marks'
--   `MinMarkSpeed`; with `intoBend`, turned into the bend; with `minWheels`, that many
--   sliding): a lapse up to `Grace` is forgiven. `needFour` also asks all four wheels to
--   slide, each by its own slip gate (`Drift/Wheels.evaluate`), with the same grace.
--   THE LINES: `lane = "own"` is your own lane, the double yellow's side the car's centre is
--   on at the entry, out to the white edge line; a wheel is OUT on the far side of the
--   double yellow (past its paint) or past the white line's outer side. `lane = "edges"` is
--   the tarmac between the two white edge lines. More than `MaxWheelsOut` wheels out at once
--   voids it: one wheel over a line is forgiven (the user's send-back).
--   COMPLETES (finish true) past the bend's exit; the handle is updated with size 1 each step.
--   ONE FEED LINE: every bend event on the same bend shares `info.group`, so the feed shows
--   one line for them (`Drift/ScoreEvents`), worded by `info.groupKind` while live.
--   VOIDS (finish false) on a broken drift, too many wheels out, a fall, a put-back, going
--   back out of the zone, or the road changing.
--
-- `rig` is anything with a `spline` field: the road (`Road/Spline`), or a function that
-- returns it (nil off the spline road, where nothing is detected).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)
local Wheels = require(script.Parent.Parent.Wheels)

local BendDrift = {}
BendDrift.__index = BendDrift

export type Spec = {
	kind: string,
	tuning: any, -- { Grace, JumpStuds, MaxWheelsOut }
	hairpinsOnly: boolean?, -- true hairpins (`Hairpins.around`), else every bend (`bendAround`)
	needFour: boolean?,
	intoBend: boolean?,
	minWheels: number?, -- sliding wheels the drift needs (default 0: the model's drift is enough)
	lane: "own" | "edges",
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
function BendDrift.slidingWheels(state: any, marking: { boolean }): number
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

-- Each wheel's distance across the road (d, studs right of the centre line), from the car's
-- (s, d) and its yaw, into `out` (four numbers, FL FR RL RR). Returns `out`.
function BendDrift.wheelsAcross(state: any, spline: any, s: number, d: number, out: { number }): { number }
	local C = Config.Drift
	local hb, ht = C.Wheelbase * 0.5, C.TrackWidth * 0.5
	local sy, cy = math.sin(state.yaw), math.cos(state.yaw)
	local fx, fz = -sy, -cy -- the car's flat forward
	local rx, rz = cy, -sy -- and right
	local px, pz = Hairpins.rightAt(spline, s)
	for i, w in WHEELS do
		local ox = fx * hb * w.front + rx * ht * w.side
		local oz = fz * hb * w.front + rz * ht * w.side
		out[i] = d + ox * px + oz * pz
	end
	return out
end

-- The smallest and largest of the four wheels' distances across the road.
function BendDrift.wheelSpan(state: any, spline: any, s: number, d: number): (number, number)
	local ds = BendDrift.wheelsAcross(state, spline, s, d, table.create(4, 0))
	return math.min(ds[1], ds[2], ds[3], ds[4]), math.max(ds[1], ds[2], ds[3], ds[4])
end

-- How many of the wheels at `ds` are out of the lines: `side` (-1, 1) is the own lane's side
-- of the double yellow, 0 for the white edge lines only.
function BendDrift.wheelsOut(ds: { number }, side: number): number
	local edge = Hairpins.edgeLine()
	local n = 0
	for _, dw in ds do
		local out = math.abs(dw) > edge
		if side ~= 0 and Hairpins.sideOf(dw) == -side then
			out = true
		end
		if out then
			n += 1
		end
	end
	return n
end

function BendDrift.speed(state: any): number
	return math.sqrt(state.u * state.u + state.v * state.v)
end

function BendDrift.splineOf(rig: any): any?
	local sp = rig and rig.spline
	if type(sp) == "function" then
		sp = sp()
	end
	return sp
end

function BendDrift.info(h: Hairpins.Hairpin?): any
	if not h then
		return nil
	end
	return {
		zone = h.zone,
		entry = h.entry,
		apex = h.apex,
		exit = h.exit,
		dir = h.dir,
		radius = h.radius,
		turn = h.turn,
		hairpin = h.hairpin,
		hairpinTurn = h.hairpinTurn,
		open = h.open,
	}
end

function BendDrift.new(sink: any, rig: any, spec: Spec)
	return setmetatable({
		sink = sink,
		rig = rig,
		spec = spec,
		spline = nil :: any,
		s = nil :: number?,
		d = nil :: number?,
		bend = nil :: Hairpins.Hairpin?, -- the one around the car (zone to exit), cached
		marking = { false, false, false, false },
		ds = { 0, 0, 0, 0 },
		sliding = 0,
		out = 0,
		badDrift = math.huge, -- s the drift has been off
		bad4 = math.huge, -- s fewer than four wheels have slid
		tried = {} :: { [number]: boolean }, -- bends (by entry) already attempted
		-- the live attempt
		handle = nil :: any,
		live = nil :: Hairpins.Hairpin?,
		side = 0,
		elapsed = 0,
		stats = { started = 0, completed = 0, voided = 0 },
		last = nil :: any,
	}, BendDrift)
end

function BendDrift._end(self: any, completed: boolean, reason: string)
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
	}
	self.handle = nil
	self.live = nil
end

function BendDrift.Update(self: any, dt: number, state: any)
	local spec: Spec = self.spec
	local T = spec.tuning
	local spline = BendDrift.splineOf(self.rig)
	if spline ~= self.spline then
		if self.live then
			self:_end(false, "road changed")
		end
		self.spline = spline
		self.s, self.d, self.bend = nil, nil, nil
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
		self.tried = {} -- put back on the road: every bend is a fresh attempt
	end

	-- the conditions, every step, so the entry can ask "holding it just now?"
	local n = BendDrift.slidingWheels(state, self.marking)
	self.sliding = n
	local h = self.bend
	if not h or h.open or s < h.zone or s > h.exit then
		h = if spec.hairpinsOnly then Hairpins.around(spline, s) else Hairpins.bendAround(spline, s)
		self.bend = h
	end
	local want = self.live or h
	local dir = if want then want.dir else 0
	local drifting = state.drifting
		and not state.airborne
		and BendDrift.speed(state) >= Config.Fx.Gates.MinMarkSpeed
		and n >= (spec.minWheels or 0)
		and (not spec.intoBend or (dir ~= 0 and state.slip * dir < 0))
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
	local ds = BendDrift.wheelsAcross(state, spline, s, d, self.ds)

	if self.live then
		local live = self.live
		self.elapsed += dt
		self.out = BendDrift.wheelsOut(ds, self.side)
		if state.fell then
			self:_end(false, "fell")
		elseif jumped then
			self:_end(false, "put back")
		elseif s < live.zone then
			self:_end(false, "went back")
		elseif self.badDrift > T.Grace then
			self:_end(false, "drift broken")
		elseif spec.needFour and self.bad4 > T.Grace then
			self:_end(false, "under four wheels")
		elseif self.out > T.MaxWheelsOut then
			self:_end(false, if spec.lane == "own" then "out of the lane" else "past the edge line")
		elseif s >= live.exit then
			self:_end(true, "through")
		else
			self.handle:update(1, dt)
		end
		return
	end

	-- not live: crossing a bend's entry this step?
	if h and not h.open and not jumped and prevS and prevS < h.entry and s >= h.entry and s <= h.exit and not self.tried[h.entry] then
		self.tried[h.entry] = true
		local side = 0
		if spec.lane == "own" then
			side = Hairpins.sideOf(d, Hairpins.lineAt(spline, s) or 0)
		end
		local out = BendDrift.wheelsOut(ds, side)
		local why = nil
		if spec.lane == "own" and side == 0 then
			why = "on the line"
		elseif self.badDrift > T.Grace then
			why = "not drifting"
		elseif spec.needFour and self.bad4 > T.Grace then
			why = "under four wheels"
		elseif out > T.MaxWheelsOut then
			why = "out of the lines"
		elseif state.fell then
			why = "fell"
		end
		if why then
			self.last = { result = "not started", reason = why, entry = h.entry }
			return
		end
		self.live = h
		self.side = side
		self.out = out
		self.elapsed = 0
		self.stats.started += 1
		self.handle = self.sink.start(spec.kind, {
			entry = h.entry,
			exit = h.exit,
			dir = h.dir,
			radius = h.radius,
			hairpin = h.hairpin,
			side = side,
			-- one feed line for every bend event on this bend (the engine's groups): PERFECT
			-- HAIRPIN on a true hairpin, LANE DRIFT on a plain bend, upgraded as it banks
			group = `bend:{h.entry}`,
			groupKind = if h.hairpin then "perfectHairpin" else "laneDrift",
		})
	end
end

function BendDrift.DebugState(self: any): any
	return {
		kind = self.spec.kind,
		s = self.s,
		d = self.d,
		bend = BendDrift.info(self.bend),
		live = self.live ~= nil,
		liveBend = BendDrift.info(self.live),
		side = self.side,
		sliding = self.sliding,
		out = self.out,
		badDrift = self.badDrift,
		bad4 = self.bad4,
		elapsed = self.elapsed,
		stats = table.clone(self.stats),
		last = self.last and table.clone(self.last),
	}
end

return BendDrift
