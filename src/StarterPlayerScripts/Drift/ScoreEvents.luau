--!strict
-- ScoreEvents: the score event engine (docs/game/features/score-events.md, T-295). Events
-- that add to the run's score on top of the drift: a jump, a wheel lift, a grind, a near
-- miss, a perfect hairpin. This module turns each into points and a push on the multiplier
-- bar ("the meter"); detectors in `Drift/Events/` decide when one happens, and reach it only
-- through the `sink` they are given, so each is built and tested without it.
--
-- THE SHARED INTERFACE (the spec's "The shared interface"; four tasks build against it):
--   ScoreEvents.oneOff(kind, size, info?)        a one-off; size 0..1 (how big, how close)
--   ScoreEvents.start(kind, info?) -> Handle     a sustained or conditional event begins
--     Handle:update(size, dt)                    held this step: size 0..1, dt seconds
--     Handle:finish(completed)                   true banks it, false voids it
--   ScoreEvents.feed                             a Signal, fired with an entry
--     { id, kind, label, points, state = "live" | "banked" | "void", rung }
--     whenever an event starts, grows (at most every `FeedEvery`) or ends
--   ScoreEvents.sink() -> { oneOff, start }      what detectors are given
-- Kinds and every number: `Config.ScoreEvents`. An unknown kind warns once and does nothing.
-- `info` may carry `label` (the line's text instead of the kind's words).
--
-- ONE LINE FOR SEVERAL EVENTS (T-299 send-back: "instead of showing multiple perfect hairpins
-- on the UI - just show perfect hairpin, then upgrade it on completion if it was one of the
-- better versions"). Events started with the same `info.group` while one of them is live
-- share ONE feed entry: its own id, worded by `info.groupKind`'s first word while live, its
-- points the sum of the members still live or banked (a member that fails drops out of it).
-- When the last member ends: banked if any member banked, worded and kinded as the banked
-- member with the highest `Static` (the best version), with the banked members' points;
-- else void, once, with what was shown. Each member still scores as its own kind (repeats,
-- counts, static, kick); only what the feed and the log see is merged.
--
-- THE MODULE IS ONE ENGINE, the client's, which `DriftController` steps and binds to
-- `ScoreController`'s score; `ScoreEvents.new` makes a separate one (tests). Each engine:
--   engine:step(dt, state)    once per simulation step, BEFORE the detectors and before
--                             `Score:Step`: the clock, the car (speed, forward, pinned, where),
--                             and a fall or put-back losing every live event
--   engine:bind(provider)     `provider()` -> the `Drift/Score` to feed, or nil outside a run.
--                             Outside a run nothing scores and no line starts; a run ending
--                             loses what is live
--
-- HOW EACH KIND SCORES (`Config.ScoreEvents` header has the formulas):
--   one-off      points into the score at once (`Score:Award`), the bar kicked, a banked line
--   sustained    points collect on the line each step, times the rung then; the bar fills
--                and does not drain (`Score:Hold`); banked on finish(true) (`Score:Bank`)
--   conditional  the same, banking only on finish(true), plus its `Static` and `Kick` then
--
-- ANTI-FARMING, all here so no detector has to: repeats of a kind within its window are
-- worth less and less; the same spot again scores nothing; nothing counts going backwards,
-- too slow or pinned on a wall; and a points-a-second ceiling over all of them together.
-- "Too slow" is the ground the car really covered, not its velocity, and a held line that
-- runs past `MaxSeconds` without leaving its spot scores nothing more (T-301: a car bouncing
-- in place against a rail banked an uncut "HUGE AIR" every 8 s).
--
-- PURE apart from the feed's Signal and the Studio print: no instance, no remote, no clock of
-- its own (its time is the steps it is handed), so the same drive scores the same at every
-- frame rate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

export type Entry = {
	id: number,
	kind: string,
	label: string,
	points: number, -- whole points earned, rung included; float
	state: string, -- "live" | "banked" | "void"
	rung: number, -- the rung the latest points were earned at
}

export type Sink = {
	oneOff: (kind: string, size: number, info: { [string]: any }?) -> (),
	start: (kind: string, info: { [string]: any }?) -> any,
}

local ScoreEvents = {}

local Engine = {}
Engine.__index = Engine

local Handle = {}
Handle.__index = Handle

local function cfg()
	return Config.ScoreEvents
end

local function kindOf(kind: string): any
	return cfg().Kinds[kind]
end

local function scaleOf(k: any, size: number): number
	local floor = k.SizeFloor or 0
	return floor + (1 - floor) * math.clamp(size, 0, 1)
end

local function labelOf(k: any, info: any, peakSize: number, seconds: number): string
	if info and type(info.label) == "string" then
		return info.label
	end
	local value = if k.WordsBy == "seconds" then seconds else peakSize
	local text = ""
	for _, w in k.Words or {} do
		if value >= w.at then
			text = w.text
		end
	end
	return text
end

-- ------------------------------------------------------------------------- engine

function ScoreEvents.new(): any
	local C = cfg()
	local bins = math.max(1, math.floor(C.RateWindow / C.RateBin + 0.5))
	local self = setmetatable({
		feed = Signal.new(),
		provider = nil :: (() -> any)?,
		boundScore = nil :: any, -- the score the last step fed
		clock = 0,
		state = nil :: any,
		nextId = 0,
		live = {} :: { [any]: boolean },
		history = {} :: { [string]: { { t: number, x: number, z: number } } },
		bins = table.create(bins, 0),
		binCount = bins,
		binAt = 0, -- the bin index the clock is in
		binSum = 0,
		counts = {} :: { [string]: any },
		groups = {} :: { [any]: any }, -- live groups by `info.group`: one feed line each
		log = {} :: { Entry },
		warned = {} :: { [string]: boolean },
		print = RunService:IsStudio() and C.PrintInStudio == true,
		cut = 0, -- points (x1) the ceiling refused this engine's life
		allowed = 0, -- points (x1) it let through
	}, Engine)
	return self
end

-- The score to feed while a run is on: `provider()` returns it, or nil when there is none.
function Engine.bind(self: any, provider: (() -> any)?)
	self.provider = provider
end

function Engine._score(self: any): any
	local p = self.provider
	if not p then
		return nil
	end
	local ok, score = pcall(p)
	return if ok then score else nil
end

function Engine._count(self: any, kind: string): any
	local c = self.counts[kind]
	if not c then
		c = { started = 0, banked = 0, void = 0, empty = 0, spent = 0, gated = 0, points = 0, seconds = 0, best = 0 }
		self.counts[kind] = c
	end
	return c
end

function Engine._emit(self: any, entry: Entry)
	local copy = table.clone(entry)
	if entry.state ~= "live" then
		table.insert(self.log, copy)
		if #self.log > cfg().LogSize then
			table.remove(self.log, 1)
		end
		if self.print then
			print(`[ScoreEvents] {entry.label} +{math.floor(entry.points)} x{entry.rung} {entry.state}`)
		end
	end
	self.feed:Fire(copy)
end

-- THE CEILING. Points before the rung pass through here, and what the last `RateWindow`
-- seconds have already had is kept in a ring of `RateBin`-second bins.
function Engine._advanceBins(self: any)
	local C = cfg()
	local at = math.floor(self.clock / C.RateBin)
	local n = self.binCount
	if at - self.binAt >= n then
		table.clear(self.bins)
		for i = 1, n do
			self.bins[i] = 0
		end
		self.binSum = 0
	else
		for b = self.binAt + 1, at do
			local i = b % n + 1
			self.binSum -= self.bins[i]
			self.bins[i] = 0
		end
	end
	self.binAt = at
end

function Engine._allow(self: any, points: number): number
	if points <= 0 then
		return 0
	end
	local C = cfg()
	local room = math.max(C.MaxEventRate * C.RateWindow - self.binSum, 0)
	local take = math.min(points, room)
	if take < points then
		self.cut += points - take
	end
	local i = self.binAt % self.binCount + 1
	self.bins[i] += take
	self.binSum += take
	self.allowed += take
	return take
end

-- Whether the car, as last stepped, may score `k` now, and its speed. No state yet (a test
-- that never stepped) is allowed.
--
-- THE SPEED IS THE GROUND THE CAR REALLY COVERED (T-301): the smaller of its velocity and
-- how far its position moved over the last step. A car held against a rail, or bouncing in
-- place, can read 20+ studs/s of velocity while going nowhere (measured: 23 studs/s of
-- velocity, 16 studs moved in 12 s), and that velocity used to pay a jump or a lift.
function Engine._moving(self: any, k: any): (boolean, number)
	local s = self.state
	if not s then
		return true, 0
	end
	local u, v = s.u or 0, s.v or 0
	local speed = math.sqrt(u * u + v * v)
	if self.travel then
		speed = math.min(speed, self.travel)
	end
	if s.pinned then
		return false, speed
	end
	if speed < (k.MinSpeed or cfg().MinSpeed) then
		return false, speed
	end
	if k.Forward ~= false and u <= 0 then
		return false, speed
	end
	return true, speed
end

function Engine._where(self: any): (number?, number?)
	local s = self.state
	local p = s and s.position
	if typeof(p) == "Vector3" then
		return p.X, p.Z
	end
	return nil, nil
end

-- Repeats and the same spot, for a kind starting now: the factor its points are worth, or
-- nil when this is the same spot again. Records the start.
function Engine._admit(self: any, kind: string, k: any): number?
	local C = cfg()
	local list = self.history[kind]
	if not list then
		list = {}
		self.history[kind] = list
	end
	local now = self.clock
	local keep = math.max(C.SameSpotWindow, k.RepeatWindow or C.RepeatWindow)
	while #list > 0 and now - list[1].t > keep do
		table.remove(list, 1)
	end
	local x, z = self:_where()
	local repeats = 0
	local spot = k.SameSpot or C.SameSpot
	local gap = k.SameSpotGap or C.SameSpotGap
	for _, h in list do
		local age = now - h.t
		if x and z and age >= gap and age <= C.SameSpotWindow then
			local dx, dz = h.x - x, h.z - z
			if dx * dx + dz * dz <= spot * spot then
				return nil
			end
		end
		if age <= (k.RepeatWindow or C.RepeatWindow) then
			repeats += 1
		end
	end
	table.insert(list, { t = now, x = x or math.huge, z = z or math.huge })
	return C.RepeatFactor ^ repeats
end

function Engine._newEntry(self: any, kind: string, label: string, rung: number): Entry
	self.nextId += 1
	return { id = self.nextId, kind = kind, label = label, points = 0, state = "live", rung = rung }
end

function Engine.oneOff(self: any, kind: string, size: number, info: { [string]: any }?)
	local k = kindOf(kind)
	if not k then
		self:_unknown(kind)
		return nil
	end
	local score = self:_score()
	if not score then
		return nil
	end
	local c = self:_count(kind)
	if not self:_moving(k) then
		c.gated += 1
		return nil
	end
	local factor = self:_admit(kind, k)
	if not factor then
		c.spent += 1
		return nil
	end
	local scale = scaleOf(k, size)
	local base = self:_allow((k.Base or 0) * scale * factor)
	if base <= 0 then
		c.empty += 1 -- the ceiling took all of it: no line
		return nil
	end
	local points = score:Award(base, (k.Kick or 0) * scale)
	local entry = self:_newEntry(kind, labelOf(k, info, math.clamp(size, 0, 1), 0), score.multiplier)
	entry.points = points
	entry.state = "banked"
	c.started += 1
	c.banked += 1
	c.points += points
	c.best = math.max(c.best, points)
	self:_emit(entry)
	return entry
end

local INERT = setmetatable({ live = false }, Handle)

function Engine.start(self: any, kind: string, info: { [string]: any }?): any
	local k = kindOf(kind)
	if not k then
		self:_unknown(kind)
		return INERT
	end
	local score = self:_score()
	if not score then
		return INERT
	end
	local factor = self:_admit(kind, k)
	if not factor then
		self:_count(kind).spent += 1
		return INERT
	end
	local h = setmetatable({
		engine = self,
		kind = kind,
		k = k,
		info = info,
		factor = factor,
		live = true,
		entry = self:_newEntry(kind, labelOf(k, info, 0, 0), score.multiplier),
		seconds = 0, -- this line's seconds held
		totalSeconds = 0, -- the whole event's, across `MaxSeconds` restarts
		scaleSeconds = 0, -- the size's scale integrated over the hold, for the static part
		peak = 0, -- the line's largest size
		lastFed = self.clock,
		dirty = false,
		-- A sustained line shows once it has earned `ShowPoints`, so a lift or a jump that
		-- earns next to nothing (a flick of a wheel, sliding backwards) never puts a +0 line
		-- in the feed; what it earned still banks. A conditional shows at once: the player
		-- must see it is on.
		shown = k.Mode ~= "sustained",
		from = self.lastPos, -- where this line started, for a `MaxSeconds` restart
	}, Handle)
	self.live[h] = true
	self:_count(kind).started += 1
	local key = info and info.group
	if key ~= nil then
		local g = self.groups[key]
		if not g then
			local gk = if info and info.groupKind and kindOf(info.groupKind) then info.groupKind else kind
			g = {
				key = key,
				entry = self:_newEntry(gk, labelOf(kindOf(gk), nil, 0, 0), score.multiplier),
				members = {},
				lastFed = self.clock,
				dirty = false,
			}
			self.groups[key] = g
		end
		h.group = g
		table.insert(g.members, h)
	end
	if h.shown then
		self:_show(h, true)
	end
	return h
end

-- A handle's line to the feed: its own entry, or its group's (`now`: at once, else at the
-- next `FeedEvery`). A group whose last member has ended goes out banked or void, once.
function Engine._show(self: any, h: any, now: boolean)
	local g = h.group
	if not g then
		self:_emit(h.entry)
		return
	end
	local points, rung, live = 0, g.entry.rung, false
	local best, bestStatic = nil, -math.huge
	local banked, lost = 0, 0
	for _, m in g.members do
		local e = m.entry
		if m.live then
			live = true
			points += e.points
			rung = math.max(rung, e.rung)
		elseif e.state == "banked" then
			points += e.points
			banked += e.points
			rung = math.max(rung, e.rung)
			local s = m.k.Static or 0
			if s >= bestStatic then
				best, bestStatic = m, s
			end
		else
			lost += e.points
		end
	end
	local entry = g.entry
	entry.rung = rung
	if live then
		entry.points = points
		if now then
			g.dirty = false
			g.lastFed = self.clock
			self:_emit(entry)
		else
			g.dirty = true
		end
		return
	end
	if self.groups[g.key] == g then
		self.groups[g.key] = nil
	end
	if best then
		entry.state = "banked"
		entry.kind = best.kind
		entry.label = best.entry.label
		entry.points = banked
	else
		entry.state = "void"
		entry.points = lost
	end
	self:_emit(entry)
end

function Engine.sink(self: any): Sink
	return {
		oneOff = function(kind, size, info)
			self:oneOff(kind, size, info)
		end,
		start = function(kind, info)
			return self:start(kind, info)
		end,
	}
end

function Engine._unknown(self: any, kind: string)
	if not self.warned[kind] then
		self.warned[kind] = true
		warn(`[ScoreEvents] no kind '{kind}' in Config.ScoreEvents.Kinds`)
	end
end

-- Lose every live event: a fall, the car put back, the run over.
function Engine.voidAll(self: any)
	local list = {}
	for h in self.live do
		table.insert(list, h)
	end
	table.sort(list, function(a, b)
		return a.entry.id < b.entry.id
	end)
	for _, h in list do
		h:finish(false)
	end
end

function Engine.step(self: any, dt: number, state: any)
	if dt <= 0 then
		return
	end
	local C = cfg()
	self.clock += dt
	self:_advanceBins()
	-- The car put back: a new state, from a new runner (`Sim.newRunner`). A stand-in with
	-- no clock of its own is never taken for one.
	local old = self.state
	local putBack = old ~= nil and state ~= old and old.time ~= nil and state.time ~= nil
	if putBack then
		self:voidAll()
	end
	self.state = state
	-- How fast the car really covered ground this step (T-301, `_moving`): unknown on the
	-- first step and across a put-back.
	local p = state.position
	local last = self.lastPos
	if typeof(p) == "Vector3" and last and not putBack then
		local dx, dz = p.X - last.X, p.Z - last.Z
		self.travel = math.sqrt(dx * dx + dz * dz) / dt
	else
		self.travel = nil
	end
	self.lastPos = if typeof(p) == "Vector3" then p else nil
	if C.VoidOnFall and state.fell then
		self:voidAll()
	end
	-- The run over (or the score gone): what is live is lost.
	-- A run starting begins with no repeats or spots behind it.
	local score = self:_score()
	if score ~= self.boundScore then
		if self.boundScore ~= nil then
			self:voidAll()
		end
		if score ~= nil then
			table.clear(self.history)
		end
		self.boundScore = score
	end
	-- The live lines' growth to the feed, at most every `FeedEvery`. A grouped handle's growth
	-- is its group's, sent once for all its members.
	local due = {}
	local dueGroups = {}
	for h in self.live do
		if h.dirty and h.shown then
			local g = h.group
			if g then
				h.dirty = false
				if self.clock - g.lastFed >= C.FeedEvery and not dueGroups[g] then
					dueGroups[g] = h
				end
			elseif self.clock - h.lastFed >= C.FeedEvery then
				table.insert(due, h)
			end
		end
	end
	for _, h in due do
		h.dirty = false
		h.lastFed = self.clock
		self:_emit(h.entry)
	end
	for _, h in dueGroups do
		self:_show(h, true)
	end
end

-- Back to nothing: a new run. What is live is lost first.
function Engine.reset(self: any)
	self:voidAll()
	table.clear(self.history)
	table.clear(self.counts)
	table.clear(self.log)
	table.clear(self.groups)
	for i = 1, self.binCount do
		self.bins[i] = 0
	end
	self.binSum = 0
	self.cut = 0
	self.allowed = 0
end

-- Counts and points per kind, what is live, and the last finished lines.
function Engine.debug(self: any): any
	local live = {}
	for h in self.live do
		table.insert(live, { id = h.entry.id, kind = h.kind, label = h.entry.label, points = h.entry.points, seconds = h.seconds })
	end
	return {
		bound = self:_score() ~= nil,
		clock = self.clock,
		counts = table.clone(self.counts),
		live = live,
		log = table.clone(self.log),
		windowPoints = self.binSum,
		ceilingCut = self.cut,
		allowed = self.allowed,
	}
end

-- ------------------------------------------------------------------------- handles

function Handle.update(self: any, size: number, dt: number)
	if not self.live or dt <= 0 then
		return
	end
	local engine = self.engine
	local k = self.k
	local score = engine:_score()
	if not score then
		return
	end
	size = math.clamp(size, 0, 1)
	local entry: Entry = self.entry
	self.seconds += dt
	self.totalSeconds += dt
	local scale = scaleOf(k, size)
	self.scaleSeconds += scale * dt
	if size > self.peak then
		self.peak = size
	end
	local c = engine:_count(self.kind)
	c.seconds += dt
	local label = labelOf(k, self.info, self.peak, self.seconds)
	if label ~= entry.label then
		entry.label = label
		self.dirty = true
	end

	local ok, speed = engine:_moving(k)
	if ok then
		local units = if k.Per == "stud" then speed * dt else dt
		local rate = (k.Rate or 0) * (1 + (k.Ramp or 0) * self.seconds)
		local base = engine:_allow(rate * units * scale * self.factor)
		if base > 0 then
			entry.points += base * score.multiplier
			entry.rung = score.multiplier
			self.dirty = true
		end
		score:Hold((k.Fill or 0) * scale * dt)
	end
	if not self.shown and entry.points >= cfg().ShowPoints then
		self.shown = true
		self.dirty = false
		self.lastFed = engine.clock
		engine:_show(self, true)
	end

	-- Held too long: bank this line and carry on in a fresh one, so nothing runs up
	-- unbounded points unseen.
	if k.MaxSeconds and k.Mode == "sustained" and self.seconds >= k.MaxSeconds then
		self:_bank(score)
		self.entry = engine:_newEntry(self.kind, labelOf(k, self.info, 0, 0), score.multiplier)
		self.seconds = 0
		self.peak = 0
		self.dirty = false
		self.shown = false
		engine:_count(self.kind).started += 1
		-- A held event that has not left the spot it started on is not going anywhere: the
		-- fresh line scores nothing (T-301). This used to be the way round the repeat and
		-- same-spot rules: a car bouncing in place held one endless "jump" that banked a
		-- fresh, uncut line every `MaxSeconds`.
		local here, from = engine.lastPos, self.from
		if here and from then
			local dx, dz = here.X - from.X, here.Z - from.Z
			local spot = k.SameSpot or cfg().SameSpot
			if dx * dx + dz * dz < spot * spot then
				self.factor = 0
				engine:_count(self.kind).spent += 1
			end
		end
		self.from = here
	end
end

function Handle._bank(self: any, score: any)
	local entry: Entry = self.entry
	if not self.shown then
		-- it earned less than a line is worth showing: what it has goes in quietly
		score:Bank(entry.points)
		local c = self.engine:_count(self.kind)
		c.empty += 1
		c.points += entry.points
		return
	end
	score:Bank(entry.points)
	entry.state = "banked"
	local c = self.engine:_count(self.kind)
	c.banked += 1
	c.points += entry.points
	c.best = math.max(c.best, entry.points)
	self.engine:_show(self, true)
end

function Handle.finish(self: any, completed: boolean)
	if not self.live then
		return
	end
	self.live = false
	local engine = self.engine
	engine.live[self] = nil
	local entry: Entry = self.entry
	local score = engine:_score()
	if completed and score then
		local k = self.k
		if k.Mode == "conditional" then
			-- What collected while held banks, then the finish's own boost: its static points
			-- and kick, scaled by the mean size held, through `Award` (times the rung now).
			score:Bank(entry.points)
			local mean = if self.totalSeconds > 0 then self.scaleSeconds / self.totalSeconds else scaleOf(k, self.peak)
			local base = engine:_allow((k.Static or 0) * mean * self.factor)
			entry.points += score:Award(base, (k.Kick or 0) * mean)
			entry.rung = score.multiplier
			entry.state = "banked"
			local c = engine:_count(self.kind)
			c.banked += 1
			c.points += entry.points
			c.best = math.max(c.best, entry.points)
			engine:_show(self, true)
		else
			self:_bank(score)
		end
	elseif self.shown then
		entry.state = "void"
		engine:_count(self.kind).void += 1
		engine:_show(self, true)
	else
		engine:_count(self.kind).empty += 1 -- lost before it earned anything: no line
		if self.group then
			engine:_show(self, true) -- the group may have been waiting on this one
		end
	end
end

-- ------------------------------------------------------------------- the module's own

local default = ScoreEvents.new()

ScoreEvents.engine = default
ScoreEvents.feed = default.feed

function ScoreEvents.oneOff(kind: string, size: number, info: { [string]: any }?)
	default:oneOff(kind, size, info)
end

function ScoreEvents.start(kind: string, info: { [string]: any }?): any
	return default:start(kind, info)
end

function ScoreEvents.sink(): Sink
	return default:sink()
end

function ScoreEvents.step(dt: number, state: any)
	default:step(dt, state)
end

function ScoreEvents.bind(provider: (() -> any)?)
	default:bind(provider)
end

function ScoreEvents.reset()
	default:reset()
end

function ScoreEvents.debug(): any
	return default:debug()
end

return ScoreEvents
