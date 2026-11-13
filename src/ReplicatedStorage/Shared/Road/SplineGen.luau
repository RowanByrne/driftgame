--!strict
-- SplineGen: chooses the spline road, one section at a time, from a seed
-- (features/spline-road.md, T-132). Pure maths: no instances.
--
-- A SECTION is one decision: a bend (a radius, a direction, how far it turns) or a
-- straight, with the grade and bank that go with it. It eases in from whatever curvature
-- the road had, holds, and hands its curvature on to the next section, so there is never
-- a kink. What it emits is a `Spline.Section`: a few knots, which is also exactly what is
-- sent to clients, who replay them through `Spline.append` and so draw the same road
-- without ever making a choice of their own.
--
-- THE RULES IT KEEPS, each by construction or by a check before a section is accepted:
--   * no bend tighter than `MinRadius`, no easing faster than `MaxCurvatureRate`
--   * no grade past `MaxGrade` or changing faster than `MaxGradeRate`; height kept in band
--   * no bank past `MaxBank` or changing faster than `MaxBankRate`
--   * NO CROSSING: every point of a new section keeps `clearance` from every point of
--     road that is not its neighbour along the curve -- including road a long way behind
--   * NO TRAPS: a section is accepted only if the road could straighten up after it and
--     run `EscapeLength` clear. If nothing random passes, that escape IS the next section,
--     and it was checked when the section before it was accepted.
--
-- THE MOUNTAINSIDE (features/mountain-road.md, T-140) is chosen for each section once its
-- curve is accepted, from a random stream of its own so it never changes which curves are
-- tried: the runoff either side, the edge each side ends in, and any K-rails. The mountain
-- follows the heading against the fall line: it is on the side the uphill direction is on,
-- and changes only where the road turns back through a hairpin (T-166, below).
-- Clearance (`limits`) is wide enough for the widest runoff and an
-- edge either side, whatever is chosen.
--
-- THE MOUNTAIN'S DIRECTION (features/mountain-direction.md, T-166). The road has a fall
-- line, fixed for its whole length (`fall`, the uphill heading), and on a descent it is
-- laid to a PLAN: legs across the slope, each a stretch of random sections that keep within
-- `LegHeadingLimit` of the leg's heading, joined by planned turns -- a hairpin or a
-- switchback at the end of each leg, and now and then a double hairpin or a sideways
-- stretch in the middle of one. A planned turn is built to land exactly on the heading it
-- is for, and is checked for crossings and its escape like any other section; refused, the
-- stretch before it runs on `RetryAfter` and it is tried again. The height band's centre
-- moves with the road (`DescentRate`), so the run works its way down.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)

local SplineGen = {}
SplineGen.__index = SplineGen

export type Stats = {
	sections: number,
	tries: number, -- candidates built
	rejectedCrowded: number,
	rejectedHeading: number,
	escapes: number, -- times nothing random passed and the escape was laid
	cornered: number, -- escapes whose own escape was not clear
	stalled: boolean,
	kinds: { [string]: number },
	worstMs: number,
	totalMs: number,
	-- the plan (T-166)
	legs: number,
	turnarounds: number,
	doubles: number,
	sideways: number,
	straightens: number,
	turnsRefused: number, -- a planned turn that would have crowded old road, run on and retried
	climbs: number, -- times the descent bottomed out and a climb began
	cliffSwaps: number, -- times the mountain changed sides
	tight: number, -- tight cliff edges laid: gravel and a rail at the lip (T-181)
}

-- One step of the plan: a STRETCH of random sections kept within `limit` of `aim` for
-- `left` studs, or a planned TURN onto heading `to`, turning `dir` (1 left, -1 right) on a
-- radius from `radius`. `window` is the heading the road must be near before the turn.
export type Item = {
	turn: boolean,
	what: string,
	aim: number?,
	limit: number?,
	left: number?,
	to: number?,
	dir: number?,
	radius: { number }?,
	tag: string?,
	window: number?,
	started: boolean?,
}

export type Gen = typeof(setmetatable(
	{} :: {
		spline: Spline.Spline,
		rng: Random,
		seed: number,
		sections: { Spline.Section },
		recent: { string },
		lastDir: number,
		lastWasBend: boolean,
		-- the mountain (T-166)
		mode: string, -- "descent", "ascent" or "traverse"
		fall: number, -- the uphill heading (a yaw), fixed for the road
		sense: number, -- 1 descending, -1 climbing
		drift: number, -- how the height band's centre moves per stud of road, going down
		centre: number, -- the band's centre at the road's end, relative to the start
		climbing: boolean, -- in one of the short climbs that win the height back
		band: { number }, -- the centre's knots, {s, centre, ...}: what the band was, for tests
		legSide: number, -- which way across the slope the current leg runs (1 or -1)
		tilt: number?, -- the next leg's tilt, chosen with the turnaround onto it
		prng: Random, -- the plan's own stream
		plan: { Item },
		turns: { { any } }, -- every planned turn laid, {s0, s1, what}: the server's record, for tests
		aim: number, -- the heading random sections keep near...
		limit: number, -- ...and how far off it they may go
		upSign: number, -- which way off `aim` (1 left, -1 right) is up the slope; 0 none
		limitUp: number, -- the limit that way
		lineX: number?, -- where the stretch began: its line runs from here along `aim`
		lineZ: number?,
		trng: Random, -- the mountainside's own stream
		uphill: number, -- the side the mountain is on: -1 left, 1 right
		inBand: boolean, -- heading within `AlongFallLine` of the fall line: the side holds
		lowUntil: number, -- s: the uphill side stays hedge to here after the mountain changes sides
		runoff: { [number]: number }, -- the last runoff width chosen, by side
		clearance: number,
		separation: number,
		stats: Stats,
	},
	SplineGen
))

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function sign(x: number): number
	return if x > 0 then 1 elseif x < 0 then -1 else 0
end

-- How far apart two centre-line points must be, and how far along the road two points
-- must be before that applies at all. On the tightest bend allowed, two points `sep`
-- apart along it are already `clear` apart in a straight line, so anything closer along
-- the road is a neighbour, not a crossing.
-- `clearOverride` is for the tests' before-and-after measure only (the old road kept 74).
function SplineGen.limits(clearOverride: number?): (number, number)
	local C = Config.Spline
	local R = Config.Road
	local T = C.Terrain
	-- the tarmac, the widest runoff and an edge either side, and a gap (T-140)
	local clear = clearOverride or (R.Width + 2 * (T.RunoffMax + T.EdgeDepth) + C.ClearanceGap)
	local rmin = C.MinRadius
	local ratio = math.min(1, clear / (2 * rmin))
	local sep = 2 * rmin * math.asin(ratio) + 2 * C.CheckStep
	return clear, sep
end

function SplineGen.new(seed: number, origin: Spline.Origin?, clearOverride: number?): Gen
	local clear, sep = SplineGen.limits(clearOverride)
	local spline = Spline.new(origin)
	local self = setmetatable({
		spline = spline,
		rng = Random.new(seed),
		seed = seed,
		sections = {},
		recent = {},
		lastDir = 0,
		lastWasBend = false,
		mode = Config.Spline.Mountain.Mode,
		fall = 0,
		sense = 1,
		drift = 0,
		centre = 0,
		climbing = false,
		band = { 0, 0 },
		legSide = 1,
		tilt = nil,
		prng = Random.new((seed * 13 + 4099) % 2 ^ 31),
		plan = {},
		turns = {},
		aim = spline.origin.yaw,
		limit = math.rad(Config.Spline.HeadingLimit),
		upSign = 0,
		limitUp = math.rad(Config.Spline.HeadingLimit),
		trng = Random.new((seed * 7 + 1013) % 2 ^ 31),
		uphill = 1,
		inBand = false,
		lowUntil = 0,
		runoff = { [-1] = Config.Spline.Terrain.StartRunoff, [1] = Config.Spline.Terrain.StartRunoff },
		clearance = clear,
		separation = sep,
		stats = {
			sections = 0,
			tries = 0,
			rejectedCrowded = 0,
			rejectedHeading = 0,
			escapes = 0,
			cornered = 0,
			stalled = false,
			kinds = {},
			worstMs = 0,
			totalMs = 0,
			legs = 0,
			turnarounds = 0,
			doubles = 0,
			sideways = 0,
			straightens = 0,
			turnsRefused = 0,
			climbs = 0,
			cliffSwaps = 0,
			tight = 0,
		},
	}, SplineGen)
	-- THE FALL LINE: the start heading turned `FallLineTurn` to a side chosen from the seed,
	-- so the first leg runs across the slope, tilted down (or up) it
	local M = Config.Spline.Mountain
	local q = if self.prng:NextNumber() < 0.5 then -1 else 1
	self.fall = wrap(spline.origin.yaw + q * math.rad(M.FallLineTurn))
	self.legSide = -q
	self.sense = if self.mode == "ascent" then -1 else 1
	self.drift = if self.mode == "descent" then -M.DescentRate elseif self.mode == "ascent" then M.DescentRate else 0
	-- the mountain starts on the side the uphill direction is on (with the fall line square
	-- to the start heading, it is never inside the band)
	self.uphill = if math.sin(spline.origin.yaw - self.fall) > 0 then 1 else -1
	local L = Config.Spline.StartStraight
	local start: Spline.Section = { len = L, k = { L, 0 }, g = { L, 0 }, b = { L, 0 }, tag = "Start" }
	self:_terrain(start)
	self:_commit(start)
	return self
end

--------------------------------------------------------------------------------
-- The mountainside (T-140)
--------------------------------------------------------------------------------

-- The heading `u` studs into a section whose curvature knots are `knots`, from yaw0 and k0.
local function yawAlong(yaw0: number, k0: number, knots: { number }, u: number): number
	local yaw, k, s = yaw0, k0, 0
	for j = 1, #knots, 2 do
		local s1, k1 = knots[j], knots[j + 1]
		if u <= s1 then
			local L = s1 - s
			local kU = if L > 0 then k + (k1 - k) * (u - s) / L else k1
			return yaw + 0.5 * (k + kU) * (u - s)
		end
		yaw += 0.5 * (k + k1) * (s1 - s)
		s, k = s1, k1
	end
	return yaw
end

-- Choose a section's runoff, edges and K-rails, and write them into it.
function SplineGen._terrain(self: Gen, sec: Spline.Section)
	local T = Config.Spline.Terrain
	local r = self.trng
	local len = sec.len
	local tag = sec.tag
	local bend = tag ~= "Straight" and tag ~= "Escape" and tag ~= "Start"
	local function between(range: { number }): number
		return range[1] + (range[2] - range[1]) * r:NextNumber()
	end

	-- THE RUNOFF: a width every `RunoffKnotEvery` studs, each side on its own, never
	-- changing faster than a quarter of a stud per stud, so the grass's edge never runs at
	-- the car faster than about 14 degrees (smoothstep's steepest is 1.5 times that)
	local function runoff(side: number): { number }
		if tag == "Start" then
			self.runoff[side] = T.StartRunoff
			return { len, T.StartRunoff }
		end
		local out = {}
		local prev, prevAt = self.runoff[side], 0
		local function knot(at: number)
			local w = between({ T.RunoffMin, T.RunoffMax })
			local most = 0.25 * (at - prevAt)
			w = math.clamp(w, prev - most, prev + most)
			table.insert(out, at)
			table.insert(out, w)
			prev, prevAt = w, at
		end
		local lo = T.RunoffKnotEvery[1]
		local at = between(T.RunoffKnotEvery)
		while at < len - lo * 0.5 do
			knot(at)
			at += between(T.RunoffKnotEvery)
		end
		knot(len)
		self.runoff[side] = prev
		return out
	end
	local startRun = { [-1] = self.runoff[-1], [1] = self.runoff[1] } -- for a tight edge (T-181)
	sec.rl = runoff(-1)
	sec.rr = runoff(1)

	-- THE EDGES: the mountain on one side, the drop on the other, and WHICH SIDE follows
	-- from the heading against the fall line (T-166): the side the uphill direction is on.
	-- Heading within `AlongFallLine` of straight up or down the slope counts as neither and
	-- the side holds. Coming out of that band on the other side -- the road has turned back
	-- through a hairpin -- the mountain changes sides, with hedge both sides through the
	-- band in this section, the road crossing the spur.
	local upKind = if r:NextNumber() < T.UphillHedgeChance then Spline.HEDGE else Spline.ROCK
	local downKind = if r:NextNumber() < T.DownhillHedgeChance then Spline.HEDGE else Spline.CLIFF
	local band = math.sin(math.rad(Config.Spline.Mountain.AlongFallLine))
	local _, _, yaw0, k0 = self.spline:tip()
	local s0 = self.spline.length
	local spans: { { number } } = {} -- {dsEnd, up side, hedged, uphill hedge to}
	local lowEnd = self.lowUntil - s0 -- after a change of sides, the uphill side stays low to here
	local cur = self.uphill
	local from = 0 -- where the current span began
	local enteredAt: number? = if self.inBand then 0 else nil
	local function close(at: number, side: number, hedged: boolean)
		if at > from + 1e-6 then
			table.insert(spans, { at, side, if hedged then 1 else 0, lowEnd })
			from = at
		end
	end
	local u = 0
	while true do
		local yaw = yawAlong(yaw0, k0, sec.k, u)
		local across = math.sin(yaw - self.fall)
		if math.abs(across) < band then
			if enteredAt == nil then
				enteredAt = u
			end
		else
			local side = if across > 0 then 1 else -1
			if enteredAt ~= nil and side ~= cur then
				close(enteredAt, cur, false)
				close(u, 0, true)
				cur = side
				self.stats.cliffSwaps += 1
				lowEnd = u + T.UphillLowAfterTurn
			end
			enteredAt = nil
		end
		if u >= len then
			break
		end
		u = math.min(u + 4, len)
	end
	close(len, cur, false)
	self.uphill = cur
	self.inBand = enteredAt ~= nil
	self.lowUntil = s0 + lowEnd
	-- Just past a hairpin the leg you came down is right above you, only a few studs higher:
	-- a tall rock face there makes no sense (the user, 2026-11-13). So the uphill side stays
	-- hedge for `UphillLowAfterTurn` studs after the mountain changes sides.
	local el, er = {}, {}
	local function add(at: number, l: number, r: number)
		table.insert(el, at)
		table.insert(el, l)
		table.insert(er, at)
		table.insert(er, r)
	end
	local spanFrom = 0
	for _, sp in spans do
		local side = sp[2]
		if sp[3] == 1 then
			add(sp[1], Spline.HEDGE, Spline.HEDGE)
		else
			local kinds = { [side] = upKind, [-side] = downKind }
			local low = sp[4]
			if low > spanFrom + 1e-6 then
				local cut = math.min(low, sp[1])
				local lowKinds = { [side] = Spline.HEDGE, [-side] = downKind }
				add(cut, lowKinds[-1], lowKinds[1])
			end
			if sp[1] > low + 1e-6 then
				add(sp[1], kinds[-1], kinds[1])
			end
		end
		spanFrom = sp[1]
	end
	sec.el = el
	sec.er = er
	-- the edge on one side over a run of the section, if it is the same all the way
	local function edgeOver(side: number, a: number, b: number): number?
		local list = if side < 0 then el else er
		local s0, kind = 0, nil
		for j = 1, #list, 2 do
			local s1 = list[j]
			if s1 > a and s0 < b then
				if kind and kind ~= list[j + 1] then
					return nil
				end
				kind = list[j + 1]
			end
			s0 = s1
		end
		return kind
	end

	-- K-RAILS: on the outside of a bend above a cliff about half the time, the body of the
	-- bend; now and then a stretch anywhere else
	local runMin, runMax = T.KRailRun[1], T.KRailRun[2]
	local kr: { number } = {}
	if bend then
		local kEnd = sec.k[#sec.k]
		local outside = if kEnd > 0 then 1 else -1 -- a left turn's outside is the right
		if len >= runMin and r:NextNumber() < T.KRailBendChance then
			local run = math.clamp(len * 0.8, runMin, math.min(runMax, len))
			local a = (len - run) * 0.5
			if edgeOver(outside, a, a + run) == Spline.CLIFF then
				kr = { a, a + run, outside }
			end
		end
	elseif len >= runMin and r:NextNumber() < T.KRailOtherChance then
		local side = if r:NextNumber() < 0.5 then -1 else 1
		local run = between({ runMin, math.min(runMax, len) })
		local a = (len - run) * r:NextNumber()
		kr = { a, a + run, side }
	end

	-- TIGHT CLIFF EDGES (T-181): now and then, on a side with a cliff the whole way along,
	-- the runoff closes in to a few studs of gravel with a crash barrier on the tarmac's
	-- edge and the lip just past it. Its width eases in and out at `TightRate` on the
	-- runoff's own smoothstep knots, so nothing steps; the rail and the gravel reach
	-- `TightLead` past the narrow part into the easing. A K-rail already chosen on that side
	-- gives way to this one.
	if tag ~= "Start" then
		local side = if edgeOver(1, 0, len) == Spline.CLIFF then 1 elseif edgeOver(-1, 0, len) == Spline.CLIFF then -1 else 0
		-- (no draw at all when TightChance is 0: the road is then exactly the one before T-181)
		if side ~= 0 and T.TightChance > 0 and r:NextNumber() < T.TightChance then
			local w0, w1 = startRun[side], self.runoff[side]
			local wt = between(T.TightRunoff)
			local rampIn = math.max(T.TightRamp, math.abs(w0 - wt) / T.TightRate)
			local rampOut = math.max(T.TightRamp, math.abs(w1 - wt) / T.TightRate)
			local room = len - rampIn - rampOut - 2
			if room >= T.TightRun[1] then
				local core = math.min(between(T.TightRun), room)
				local a = rampIn + 1 + (room - core) * r:NextNumber()
				local b = a + core
				-- b + rampOut is at most len - 1, so the last knot is always its own
				local knots = { a - rampIn, w0, a, wt, b, wt, b + rampOut, w1, len, w1 }
				if side < 0 then
					sec.rl = knots
				else
					sec.rr = knots
				end
				local ga = a - math.min(T.TightLead, rampIn * 0.5)
				local gb = b + math.min(T.TightLead, rampOut * 0.5)
				if #kr > 0 and kr[3] == side then
					kr = {}
				end
				table.insert(kr, ga)
				table.insert(kr, gb)
				table.insert(kr, side)
				sec.gv = { ga, gb, side }
				self.stats.tight += 1
			end
		end
	end
	if #kr > 0 then
		sec.kr = kr
	end
end

-- A client's copy: the same road from the same sections, with no choosing.
function SplineGen.replay(sections: { Spline.Section }, origin: Spline.Origin?): Spline.Spline
	local spline = Spline.new(origin)
	for _, sec in sections do
		spline:append(sec)
	end
	return spline
end

function SplineGen._commit(self: Gen, sec: Spline.Section)
	self.spline:append(sec)
	table.insert(self.sections, sec)
	local st = self.stats
	st.sections += 1
	local tag = sec.tag or "?"
	st.kinds[tag] = (st.kinds[tag] or 0) + 1
	-- the height band's centre moves on with the road: down at `DescentRate` until it is
	-- `DescentFloor` below the start, then up at `ClimbRate` until it is back at
	-- `ClimbTop`, so a run can go on for hours and never sink out of the world (T-166)
	local M = Config.Spline.Mountain
	local move = self:_bandRate()
	local c = self.centre + move * sec.len
	if self.drift ~= 0 then
		local floor, top = M.DescentFloor * self.sense, M.ClimbTop * self.sense
		if not self.climbing and (c - floor) * self.sense <= 0 then
			c, self.climbing = floor, true
			st.climbs += 1
		elseif self.climbing and (c - top) * self.sense >= 0 then
			c, self.climbing = top, false
		end
	end
	self.centre = c
	table.insert(self.band, self.spline.length)
	table.insert(self.band, c)
end

-- How the height band's centre moves per stud of road just now.
function SplineGen._bandRate(self: Gen): number
	if self.climbing then
		return Config.Spline.Mountain.ClimbRate * self.sense
	end
	return self.drift
end


-- Where the band's centre will be `ds` studs on from the road's end, stopping where a
-- climb or the descent stops.
function SplineGen._centreAfter(self: Gen, ds: number): number
	local M = Config.Spline.Mountain
	local c = self.centre + self:_bandRate() * ds
	if self.drift == 0 then
		return c
	end
	if self.climbing then
		local top = M.ClimbTop * self.sense
		return if (c - top) * self.sense > 0 then top else c
	end
	local floor = M.DescentFloor * self.sense
	return if (c - floor) * self.sense < 0 then floor else c
end
-- The band's centre at `s`, relative to the road's start: for tests.
function SplineGen.bandAt(self: Gen, s: number): number
	local b = self.band
	for j = 3, #b, 2 do
		if b[j] >= s then
			local s0, c0 = b[j - 2], b[j - 1]
			local t = if b[j] > s0 then (s - s0) / (b[j] - s0) else 1
			return c0 + (b[j + 1] - c0) * t
		end
	end
	return b[#b]
end

--------------------------------------------------------------------------------
-- Building one candidate
--------------------------------------------------------------------------------

-- The easing between two curvatures: never shorter than `MinTransition`, never faster
-- than `MaxCurvatureRate`; nothing at all when they are the same.
local function transition(k0: number, k1: number): number
	local C = Config.Spline
	local dk = math.abs(k1 - k0)
	if dk < 1e-12 then
		return 0
	end
	return math.max(C.MinTransition, dk / C.MaxCurvatureRate)
end

-- A ramp of a track's value from v0 toward `target`, no faster than `rate` per stud and
-- no sooner than over `minLen`, inside a section of length `len`. If the section is too
-- short to get there, it gets as far as it can. Knots relative to the section's start.
local function ramp(v0: number, target: number, rate: number, minLen: number, len: number): ({ number }, number)
	local dv = target - v0
	if math.abs(dv) < 1e-12 then
		return { len, v0 }, v0
	end
	local L = math.max(minLen, math.abs(dv) / rate, 1)
	if L >= len - 1e-6 then
		-- reach only what the section allows, at the full rate
		local reach = math.min(math.abs(dv), rate * len)
		local v = v0 + sign(dv) * reach
		return { len, v }, v
	end
	return { L, target, len, target }, target
end

type Plan = {
	sec: Spline.Section,
	kt: number,
	yawEnd: number,
}

-- The curvature knots of a section that eases from k0 to kt and turns `turn` radians in
-- all (signed), or holds kt for `hold` studs when `turn` is nil (a straight).
local function curvatureKnots(k0: number, kt: number, turn: number?, hold: number?): ({ number }?, number)
	local T = transition(k0, kt)
	local H: number
	if turn then
		local byEasing = 0.5 * (k0 + kt) * T
		H = (turn - byEasing) / kt
		if H < 0.5 then
			H = 0
		end
	else
		H = hold or 0
	end
	local len = T + H
	if len < 1 then
		return nil, 0
	end
	if T > 0 and H > 0 then
		return { T, kt, len, kt }, len
	end
	return { len, kt }, len
end

-- Heading reached by the end of a section with these curvature knots, from yaw0 and k0.
local function yawAfter(yaw0: number, k0: number, knots: { number }): number
	local yaw, k, s = yaw0, k0, 0
	for j = 1, #knots, 2 do
		local s1, k1 = knots[j], knots[j + 1]
		yaw += 0.5 * (k + k1) * (s1 - s)
		s, k = s1, k1
	end
	return yaw
end

-- Walk a run of curvature knots from a plan state, calling `emit(sLocal, x, z)` every
-- `every` studs, the first at `first`. Simpson steps of `SampleStep`, the same accuracy as
-- the spline itself, and a step always ends exactly on an emit, so the points emitted are
-- exactly the points the road's own grid will hold once it is laid (T-140: a check that
-- sampled 4 studs off them passed a hairpin it later failed, and the road boxed itself in).
local function walk(x: number, z: number, yaw0: number, k0: number, knots: { number }, every: number, first: number, emit: (number, number, number) -> boolean?): boolean
	local step = Config.Spline.SampleStep
	local j = 1
	local sA, kA, yawA = 0, k0, yaw0
	local function yawAt(u: number): number
		-- u within [sA, sB] of the current interval
		local sB, kB = knots[j], knots[j + 1]
		local L = sB - sA
		local slope = if L > 0 then (kB - kA) / L else 0
		local du = u - sA
		return yawA + kA * du + 0.5 * slope * du * du
	end
	local total = knots[#knots - 1]
	local s = 0
	local nextEmit = first
	while s < total - 1e-9 do
		-- advance the interval so that s lies in [sA, knots[j]]
		while s >= knots[j] - 1e-9 and j + 2 <= #knots do
			yawA = yawAt(knots[j])
			sA, kA = knots[j], knots[j + 1]
			j += 2
		end
		local s1 = math.min(s + step, knots[j], total, nextEmit)
		local y0, ym, y1 = yawAt(s), yawAt((s + s1) * 0.5), yawAt(s1)
		local h = (s1 - s) / 6
		x += h * (-math.sin(y0) - 4 * math.sin(ym) - math.sin(y1))
		z += h * (-math.cos(y0) - 4 * math.cos(ym) - math.cos(y1))
		s = s1
		if s >= nextEmit - 1e-9 then
			if emit(s, x, z) == false then
				return false
			end
			nextEmit += every
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Choosing
--------------------------------------------------------------------------------

local function pickKind(self: Gen, s0: number): any
	local C = Config.Spline
	local counts: { [string]: number } = {}
	local most = 0
	for _, name in self.recent do
		counts[name] = (counts[name] or 0) + 1
		most = math.max(most, counts[name])
	end
	local total = 0
	local weights = {}
	for i, b in C.Bends do
		local w = 0
		if s0 >= b.minS then
			w = (1 + most - (counts[b.name] or 0)) * b.weight
		end
		weights[i] = w
		total += w
	end
	local r = self.rng:NextNumber() * total
	for i, b in C.Bends do
		r -= weights[i]
		if r <= 0 and weights[i] > 0 then
			return b
		end
	end
	return C.Bends[#C.Bends]
end

-- The grade a section heads for, keeping the road's height inside its band: the height
-- it would reach by the end, plus what it would take to level off from there, must stay
-- inside `MinHeight..MaxHeight` of where the road began -- or, on a descent, of where the
-- band's centre has dropped to by the end of the section (T-166).
local function pickGrade(self: Gen, g0: number, y0: number, len: number): { number }
	local C = Config.Spline
	local gMax = math.tan(math.rad(C.MaxGrade))
	local rate = C.MaxGradeRate
	local move = self:_bandRate()
	local function ends(gt: number): number
		local knots, gEnd = ramp(g0, gt, rate, 0, len)
		-- the height at the section's end: integrate the ramp
		local y, s, g = y0, 0, g0
		for j = 1, #knots, 2 do
			y += 0.5 * (g + knots[j + 1]) * (knots[j] - s)
			s, g = knots[j], knots[j + 1]
		end
		-- and what levelling off from gEnd would add
		-- (on a descent the band goes on moving while the road levels off)
		return y + sign(gEnd) * gEnd * gEnd / (2 * rate) - (self.spline.origin.y + self:_centreAfter(len + math.abs(gEnd) / rate))
	end
	local gt: number
	if self.rng:NextNumber() < C.KeepGradeChance then
		gt = math.clamp(g0, -gMax, gMax)
	else
		-- centred on the way the band is moving (T-166), so the local ups and downs stay but
		-- the road follows the descent, and climbs hard when the band climbs
		gt = math.clamp(move + (self.rng:NextNumber() * 2 - 1) * gMax, -gMax, gMax)
	end
	local e = ends(gt)
	if e > C.MaxHeight or e < C.MinHeight then
		-- head back toward the middle of the band
		local back = if e > C.MaxHeight then -1 else 1
		gt = back * (0.3 + 0.7 * self.rng:NextNumber()) * gMax
		e = ends(gt)
		if e > C.MaxHeight or e < C.MinHeight then
			gt = back * gMax
		end
	end
	local knots = ramp(g0, gt, rate, 0, len)
	return knots
end

local function pickBank(kt: number, radius: number?, b0: number, T: number, len: number, flat: boolean): { number }
	local C = Config.Spline
	local bt = 0
	if radius and not flat then
		bt = sign(kt) * math.rad(C.MaxBank) * math.min(1, C.FullBankRadius / radius)
	end
	-- the bank eases (smoothstep), whose steepest point is 1.5 times its average slope
	local knots = ramp(b0, bt, math.rad(C.MaxBankRate) / 1.5, T, len)
	return knots
end

-- Is this run of road clear of everything laid, and of itself? `knots` is the candidate
-- followed by its escape, relative to the road's current end.
function SplineGen._clear(self: Gen, knots: { number }): boolean
	local sp = self.spline
	local x0, z0, yaw0, k0 = sp:tip()
	local s0 = sp.length
	local clear, sep = self.clearance, self.separation
	local c2 = clear * clear
	local own: { number } = {}
	-- on the grid's own spacing from the road's start (`Spline` files a point every
	-- `CheckStep` of s), so a section's points here are the ones it will be filed with
	local cs = Config.Spline.CheckStep
	local first = cs * (math.floor(s0 / cs + 1e-9) + 1) - s0
	return walk(x0, z0, yaw0, k0, knots, cs, first, function(u, x, z)
		local s = s0 + u
		if sp:crowded(x, z, s, clear, sep) then
			return false
		end
		for j = 1, #own, 3 do
			if s - own[j] > sep then
				local dx, dz = own[j + 1] - x, own[j + 2] - z
				if dx * dx + dz * dz < c2 then
					return false
				end
			end
		end
		local n = #own
		own[n + 1], own[n + 2], own[n + 3] = s, x, z
		return true
	end)
end

-- Append the escape to a section's curvature knots: ease to straight, then run straight.
local function withEscape(knots: { number }, kt: number): { number }
	local out = table.clone(knots)
	local len = knots[#knots - 1]
	local Te = transition(kt, 0)
	if Te > 0 then
		table.insert(out, len + Te)
		table.insert(out, 0)
	end
	table.insert(out, len + Te + Config.Spline.EscapeLength)
	table.insert(out, 0)
	return out
end

-- One random candidate: a bend or a straight, its curvature knots, and whether its
-- heading (with its escape) stays inside the limit.
function SplineGen._candidate(self: Gen): (Spline.Section?, string?)
	local C = Config.Spline
	local rng = self.rng
	local sp = self.spline
	local _, _, yaw0, k0, g0, b0, y0 = sp:tip()
	local s0 = sp.length
	local limit = self.limit
	local rel = wrap(yaw0 - self.aim)

	local kt: number, knots: { number }?, len: number, radius: number?, tag: string
	if self.lastWasBend and rng:NextNumber() < C.StraightChance then
		local lo, hi = C.StraightLength[1], C.StraightLength[2]
		kt = 0
		knots, len = curvatureKnots(k0, 0, nil, lo + (hi - lo) * rng:NextNumber())
		tag = "Straight"
	else
		local kind = pickKind(self, s0)
		local dir: number
		if self.lastWasBend and rng:NextNumber() < C.SwitchbackChance then
			dir = -self.lastDir
		else
			-- lean back toward the road's general direction the further it has strayed; on a
			-- planned stretch, toward its line too, so a leg keeps its place on the slope and
			-- does not drift up into the leg above (T-166)
			local want = 0
			local x0, z0 = sp:tip()
			if self.lineX then
				local off = (x0 - self.lineX :: number) * -math.cos(self.aim) + (z0 - self.lineZ :: number) * math.sin(self.aim)
				want = -math.clamp(off / Config.Spline.Mountain.LineReach, -1, 1) * limit * 0.5
			end
			local pLeft = 0.5 - 0.45 * math.clamp((rel - want) / limit, -1, 1)
			dir = if rng:NextNumber() < pLeft then 1 else -1
		end
		local r0, r1 = kind.radius[1], kind.radius[2]
		radius = r0 * (r1 / r0) ^ rng:NextNumber() -- even across the range in log terms
		local t0, t1 = kind.turn[1], kind.turn[2]
		local turn = math.rad(t0 + (t1 - t0) * rng:NextNumber())
		kt = dir / (radius :: number)
		-- keep the heading, with the escape's own easing, inside the limit
		local escapeTurn = 0.5 * kt * transition(kt, 0)
		local room = (if dir == self.upSign then self.limitUp else limit) - dir * (rel + escapeTurn)
		if turn > room then
			turn = room
		end
		if turn < math.rad(t0) * 0.5 then
			return nil, "heading"
		end
		knots, len = curvatureKnots(k0, kt, dir * turn, nil)
		tag = kind.name
	end
	if not knots then
		return nil, "heading"
	end
	-- the final word on the heading, from the knots themselves
	local yawEnd = yawAfter(yaw0, k0, knots)
	local escYaw = 0.5 * kt * transition(kt, 0)
	local off = wrap(yawEnd + escYaw - self.aim)
	if math.abs(off) > (if sign(off) == self.upSign then self.limitUp else limit) + 1e-6 then
		return nil, "heading"
	end
	if not self:_clear(withEscape(knots, kt)) then
		return nil, "crowded"
	end
	local T = transition(k0, kt)
	local flat = rng:NextNumber() < C.UnbankedChance
	return {
		len = len,
		k = knots,
		g = pickGrade(self, g0, y0, len),
		b = pickBank(kt, radius, b0, math.min(T, len), len, flat),
		tag = tag,
	},
		nil
end

--------------------------------------------------------------------------------
-- The plan: legs, turnarounds, double hairpins, sideways stretches (T-166)
--------------------------------------------------------------------------------

-- The heading of a leg running `side` across the slope, tilted `tilt` down it (up it on
-- an ascent).
function SplineGen._legAim(self: Gen, side: number, tilt: number): number
	return wrap(self.fall + side * (math.pi * 0.5 + self.sense * tilt))
end

-- Plan the next leg: its stretches, anything in the middle of it, and the turnaround at
-- its end onto the leg after it, which runs the other way across the slope.
function SplineGen._planLeg(self: Gen)
	local M = Config.Spline.Mountain
	local r = self.prng
	local function between(range: { number }): number
		return range[1] + (range[2] - range[1]) * r:NextNumber()
	end
	local plan = self.plan
	local side = self.legSide
	local tilt = self.tilt or math.rad(between(M.LegTilt))
	local aim = self:_legAim(side, tilt)
	local limit = math.rad(M.LegHeadingLimit)
	local length = between(M.LegLength)
	local down = if self.sense > 0 then wrap(self.fall + math.pi) else self.fall
	local turnDir = self.sense * side -- a turnaround turns through the downhill side
	self.stats.legs += 1

	local function stretch(len: number, what: string, a: number?, lim: number?)
		table.insert(plan, { turn = false, what = what, aim = a or aim, limit = lim or limit, left = len })
	end
	local function turn(what: string, to: number, dir: number, radius: { number }, tag: string, window: number)
		table.insert(plan, { turn = true, what = what, to = to, dir = dir, radius = radius, tag = tag, window = window })
	end

	local events = {}
	-- no hairpin before the road is `minS` of the Hairpin bend in (the warm-up the random
	-- bends keep too): the first leg runs at least that far, and has no double hairpin
	local hairpinFrom = 0
	for _, b in Config.Spline.Bends do
		if b.name == "Hairpin" then
			hairpinFrom = b.minS
		end
	end
	length = math.max(length, hairpinFrom - self.spline.length)
	if self.spline.length >= hairpinFrom and r:NextNumber() < M.DoubleHairpinChance then
		table.insert(events, "double")
	end
	if r:NextNumber() < M.SidewaysChance then
		table.insert(events, "sideways")
	end
	if #events == 2 and r:NextNumber() < 0.5 then
		events[1], events[2] = events[2], events[1]
	end
	local used = 0
	for i, ev in events do
		local run = length / (#events + 1) * (0.75 + 0.5 * r:NextNumber())
		-- a climb only comes last, in the leg's later part, where the leg above is furthest
		-- off (the two legs spread apart from the hairpin that joins them)
		local up = ev == "sideways" and i == #events and r:NextNumber() < M.SidewaysUpShare
		if up then
			run = math.max(run, length * 0.6 - used)
		end
		stretch(run, "leg")
		used += run
		if ev == "double" then
			-- back the way it came, a level lower, then on along the leg another level down
			local back = self:_legAim(-side, tilt)
			turn("double", back, turnDir, M.HairpinRadius, "Hairpin", aim)
			stretch(between(M.DoubleHairpinBack), "back", back, limit * 0.5)
			turn("doubleOut", aim, -turnDir, M.HairpinRadius, "Hairpin", back)
		else
			local sAim = if up then wrap(down + math.pi) else down
			local d = sign(wrap(sAim - aim))
			turn("sideways", sAim, d, M.SidewaysRadius, "Sideways", aim)
			local span = between(if up then M.SidewaysUpLength else M.SidewaysLength)
			stretch(span, "sideways", sAim, math.rad(M.SidewaysLimit))
			turn("sidewaysOut", aim, -d, M.SidewaysRadius, "Sideways", sAim)
		end
	end
	stretch(math.max(length - used, 200), "leg")

	-- the turnaround, onto the next leg
	local nextTilt = math.rad(between(M.LegTilt))
	local nextAim = self:_legAim(-side, nextTilt)
	if r:NextNumber() < M.TurnaroundSwitchbackChance then
		turn("turnaround", down, turnDir, M.SwitchbackRadius, "Switchback", aim)
		stretch(between(M.SwitchbackGap), "gap", down, math.rad(10))
		turn("switchbackOut", nextAim, turnDir, M.SwitchbackRadius, "Switchback", down)
	else
		turn("turnaround", nextAim, turnDir, M.HairpinRadius, "Hairpin", aim)
	end
	self.legSide = -side
	self.tilt = nextTilt
end

-- A planned turn, built to land on its heading: the turn eases in from the road's present
-- curvature, holds, and (with the easing the next section will need to straighten out)
-- leaves the road on `item.to`. "done" if there is nothing to turn; nil if every radius
-- tried would crowd old road or could not land on the heading.
function SplineGen._turn(self: Gen, item: Item): (Spline.Section | string)?
	local C = Config.Spline
	local M = C.Mountain
	local sp = self.spline
	local _, _, yaw0, k0, g0, b0, y0 = sp:tip()
	local dir = item.dir :: number
	local to = item.to :: number
	local needed = (dir * (to - yaw0)) % (2 * math.pi)
	if needed > 2 * math.pi - math.rad(20) then
		needed -= 2 * math.pi -- already a little past it
	end
	if needed < math.rad(3) then
		return "done"
	end
	local range = item.radius :: { number }
	for try = 1, M.TurnTries do
		-- the planned radii first, then anything down to the tightest bend allowed
		local lo = if try > M.TurnTries // 2 then math.min(C.MinRadius, range[1]) else range[1]
		local radius = lo * (range[2] / lo) ^ self.rng:NextNumber()
		local kt = dir / radius
		local esc = 0.5 * math.abs(kt) * transition(kt, 0)
		local knots, len = curvatureKnots(k0, kt, dir * (needed - esc), nil)
		self.stats.tries += 1
		if knots then
			local yawEnd = yawAfter(yaw0, k0, knots) + dir * esc
			if math.abs(wrap(yawEnd - to)) < math.rad(3) then
				if self:_clear(withEscape(knots, kt)) then
					local T = transition(k0, kt)
					local flat = self.rng:NextNumber() < C.UnbankedChance
					return {
						len = len,
						k = knots,
						g = pickGrade(self, g0, y0, len),
						b = pickBank(kt, radius, b0, math.min(T, len), len, flat),
						tag = item.tag,
					}
				end
				self.stats.rejectedCrowded += 1
			end
		end
	end
	return nil
end

-- The next planned turn, or a bend that first brings the road back near the heading the
-- turn is planned from. nil when it is refused: the stretch before it then runs on.
function SplineGen._planned(self: Gen, item: Item): Spline.Section?
	local M = Config.Spline.Mountain
	local st = self.stats
	local yaw0 = select(3, self.spline:tip())
	local window = item.window
	if window and math.abs(wrap(yaw0 - window)) > math.rad(M.TurnWindow) then
		local fix = self:_turn({
			turn = true,
			what = "straighten",
			to = window,
			dir = sign(wrap(window - yaw0)),
			radius = M.StraightenRadius,
			tag = "Medium",
		})
		if typeof(fix) == "table" then
			st.straightens += 1
			return fix :: Spline.Section
		end
	end
	do
		local sec = self:_turn(item)
		if sec == "done" or typeof(sec) == "table" then
			table.remove(self.plan, 1)
			if item.what == "turnaround" then
				st.turnarounds += 1
			elseif item.what == "double" then
				st.doubles += 1
			elseif item.what == "sideways" then
				st.sideways += 1
			end
			if typeof(sec) == "table" then
				local s0 = self.spline.length
				table.insert(self.turns, { s0, s0 + (sec :: Spline.Section).len, item.what })
				return sec :: Spline.Section
			end
			return nil
		end
	end
	-- refused: run on along the stretch before it, and try again further on
	st.turnsRefused += 1
	table.insert(self.plan, 1, { turn = false, what = "wait", aim = self.aim, limit = self.limit, left = M.RetryAfter })
	return nil
end

-- Lay the next section. Returns it, or nil if the road is stalled.
function SplineGen.step(self: Gen): Spline.Section?
	local st = self.stats
	if st.stalled then
		return nil
	end
	local t0 = os.clock()
	local C = Config.Spline
	local sec: Spline.Section? = nil
	local planned = false
	if self.mode ~= "traverse" then
		if #self.plan == 0 then
			self:_planLeg()
		end
		local item = self.plan[1]
		if item.turn then
			sec = self:_planned(item)
			planned = sec ~= nil
			item = self.plan[1]
			if not item then
				self:_planLeg()
				item = self.plan[1]
			end
		end
		if not planned and not item.turn then
			self.aim, self.limit = item.aim :: number, item.limit :: number
			-- across the slope, the bends may stray less far uphill than down: toward the
			-- leg above is where the road would crowd itself
			local across = math.abs(math.cos(wrap(self.aim - self.fall))) < 0.7
			self.upSign = if across then self.sense * sign(wrap(self.fall - self.aim)) else 0
			self.limitUp = math.min(self.limit, math.rad(Config.Spline.Mountain.LegUphillLimit))
			-- a stretch's line runs from where it began; a wait carries on the line before it
			if not item.started then
				item.started = true
				if item.what ~= "wait" or not self.lineX then
					self.lineX, self.lineZ = self.spline:tip()
				end
			end
		end
	end
	for _ = 1, if planned then 0 else C.CandidateTries do
		st.tries += 1
		local cand, why = self:_candidate()
		if cand then
			sec = cand
			break
		elseif why == "crowded" then
			st.rejectedCrowded += 1
		else
			st.rejectedHeading += 1
		end
	end
	if not sec then
		-- the escape: checked when the section before this one was accepted
		local sp = self.spline
		local _, _, _, k0, g0, b0, y0 = sp:tip()
		local Te = transition(k0, 0)
		local len = Te + C.EscapeLength
		local knots = if Te > 0 then { Te, 0, len, 0 } else { len, 0 }
		if not self:_clear(knots) then
			st.stalled = true
			warn(`SplineGen: the road is boxed in at {math.floor(sp.length)} studs (seed {self.seed}); it stops growing here`)
			return nil
		end
		st.escapes += 1
		-- a detour that has run into old road ends here, and the turn back onto the leg
		-- comes next (a sideways climb toward the leg above can otherwise box itself in)
		local head = self.plan[1]
		if head and not head.turn and head.what ~= "leg" then
			head.left = 0
		end
		if not self:_clear(withEscape(knots, 0)) then
			st.cornered += 1
		end
		sec = {
			len = len,
			k = knots,
			g = pickGrade(self, g0, y0, len),
			b = pickBank(0, nil, b0, math.min(Te, len), len, true),
			tag = "Escape",
		}
	end
	local chosen = sec :: Spline.Section
	self:_terrain(chosen)
	self:_commit(chosen)
	-- a random section counts toward the stretch it was laid in
	local head = self.plan[1]
	if not planned and head and not head.turn then
		head.left = (head.left :: number) - chosen.len
		if (head.left :: number) <= 0 then
			table.remove(self.plan, 1)
		end
	end
	local bend = chosen.tag ~= "Straight" and chosen.tag ~= "Escape" and chosen.tag ~= "Start"
	if bend then
		table.insert(self.recent, chosen.tag :: string)
		if #self.recent > C.RecentBends then
			table.remove(self.recent, 1)
		end
		self.lastDir = sign(chosen.k[#chosen.k])
	end
	self.lastWasBend = bend
	local ms = (os.clock() - t0) * 1000
	st.totalMs += ms
	st.worstMs = math.max(st.worstMs, ms)
	return chosen
end

-- Lay sections until the road reaches `s`. Returns how many were laid.
function SplineGen.extendTo(self: Gen, s: number): number
	local n = 0
	while self.spline.length < s do
		if not self:step() then
			break
		end
		n += 1
	end
	return n
end

return SplineGen
