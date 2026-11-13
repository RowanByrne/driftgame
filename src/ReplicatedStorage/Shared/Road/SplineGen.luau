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
	carved: number, -- bends whose inside rock face was carved to the tarmac's edge (T-182)
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
		grng: Random, -- the groves' own stream (T-183), so they never change the rest
		xrng: Random, -- the tight cliff edges' own stream (T-181), so they never change the rest
		crng: Random, -- the carved apexes' own stream, so they move no other choice (T-182)
		uphill: number, -- the side the mountain is on: -1 left, 1 right
		inBand: boolean, -- heading within `AlongFallLine` of the fall line: the side holds
		crossAt: number, -- s: where the heading last crossed the fall line, inside the band (T-189)
		runoff: { [number]: number }, -- the last runoff width chosen, by side
		-- grand cliffs (T-185)
		lastTurnEnd: number, -- s where the last turnaround ended (the road's start before any)
		turning: string?, -- the planned turn being laid, if the section is one
		lastGrand: number, -- the grandeur the last section ended on
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
		grng = Random.new((seed * 11 + 2027) % 2 ^ 31),
		xrng = Random.new((seed * 17 + 2311) % 2 ^ 31),
		crng = Random.new((seed * 19 + 3089) % 2 ^ 31), -- not the groves' seed: a stream of its own
		uphill = 1,
		inBand = false,
		crossAt = 0,
		runoff = { [-1] = Config.Spline.Terrain.StartRunoff, [1] = Config.Spline.Terrain.StartRunoff },
		lastTurnEnd = 0,
		turning = nil,
		lastGrand = 0,
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
			carved = 0,
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

	-- THE GROVES (T-183): on a flat, gentle section, a side's runoff widens and is dressed
	-- with trees. Their own stream, always the same four draws, so a grove changes nothing
	-- else the road chooses: only that side's runoff widths are drawn from a wider range.
	local grove: { [number]: number } = {} -- side -> seed
	do
		local g = self.grng
		local roll, pick, both, seed = g:NextNumber(), g:NextNumber(), g:NextNumber(), g:NextInteger(1, 2 ^ 30)
		local _, _, _, k0, g0 = self.spline:tip()
		local kMost, gMost = math.abs(k0), math.abs(g0)
		for j = 2, #sec.k, 2 do
			kMost = math.max(kMost, math.abs(sec.k[j]))
		end
		for j = 2, #sec.g, 2 do
			gMost = math.max(gMost, math.abs(sec.g[j]))
		end
		local flat = kMost <= 1 / T.GroveMinRadius and gMost <= math.tan(math.rad(T.GroveMaxGrade))
		if tag ~= "Start" and len >= T.GroveMinLength and flat and roll < T.GroveChance then
			local first = if pick < 0.5 then -1 else 1
			grove[first] = seed
			if both < T.GroveBothChance then
				grove[-first] = (seed * 31 + 7) % 2 ^ 30
			end
		end
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
		local range = if grove[side] then T.GroveRunoff else { T.RunoffMin, T.RunoffMax }
		local function knot(at: number)
			local w = between(range)
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
	-- through a hairpin -- the mountain changes sides, AT ONE POINT: where the heading last
	-- crossed the fall line itself, the middle of the turn (or the section's start, if that
	-- was in a section already laid). There the rock face ends on one side as it starts on
	-- the other, and the drop the same, so the mountain carries on through the turn with no
	-- gap (T-189).
	-- NO HEDGES (T-189, the user 2026-11-13): the uphill side is always rock and the downhill
	-- side always the drop. The two draws that used to choose a hedge are still made and
	-- thrown away, so every other choice from this stream (the K-rails) is the road it was.
	-- `Spline.HEDGE` and its drawing stay, for hedges coming back as decoration.
	r:NextNumber()
	r:NextNumber()
	local upKind, downKind = Spline.ROCK, Spline.CLIFF
	local band = math.sin(math.rad(Config.Spline.Mountain.AlongFallLine))
	local _, _, yaw0, k0 = self.spline:tip()
	local s0 = self.spline.length
	local spans: { { number } } = {} -- {dsEnd, up side}
	local cur = self.uphill
	local from = 0 -- where the current span began
	local inBand = self.inBand
	local crossAt = math.max(self.crossAt - s0, 0) -- the last fall-line crossing in the band
	local lastAcross: number?, lastU = nil, 0
	local function close(at: number, side: number)
		if at > from + 1e-6 then
			table.insert(spans, { at, side })
			from = at
		end
	end
	local u = 0
	while true do
		local yaw = yawAlong(yaw0, k0, sec.k, u)
		local across = math.sin(yaw - self.fall)
		if lastAcross and (across > 0) ~= (lastAcross > 0) then
			-- crossed the fall line between the last sample and this one: where, linearly
			crossAt = math.clamp(u - (u - lastU) * across / (across - lastAcross), lastU, u)
		end
		lastAcross, lastU = across, u
		if math.abs(across) < band then
			if not inBand then
				inBand = true
				crossAt = u
			end
		else
			local side = if across > 0 then 1 else -1
			if inBand and side ~= cur then
				close(math.max(crossAt, from), cur)
				cur = side
				self.stats.cliffSwaps += 1
			end
			inBand = false
		end
		if u >= len then
			break
		end
		u = math.min(u + 4, len)
	end
	close(len, cur)
	self.uphill = cur
	self.inBand = inBand
	self.crossAt = s0 + crossAt
	local el, er = {}, {}
	for _, sp in spans do
		local kinds = { [sp[2]] = upKind, [-sp[2]] = downKind }
		table.insert(el, sp[1])
		table.insert(el, kinds[-1])
		table.insert(er, sp[1])
		table.insert(er, kinds[1])
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
	-- a K-rail on a grove's side would keep the car off the very grass the grove widened:
	-- drawn as usual (the stream stays the same), then dropped
	if #kr > 0 and grove[kr[3]] then
		kr = {}
	end

	-- TIGHT CLIFF EDGES (T-181): now and then, on a side with a cliff the whole way along,
	-- the runoff closes in to a few studs of gravel with a crash barrier on the tarmac's
	-- edge and the lip just past it. Its width eases in and out at `TightRate` on the
	-- runoff's own smoothstep knots, so nothing steps; the rail and the gravel reach
	-- `TightLead` past the narrow part into the easing. A K-rail already chosen on that side
	-- gives way to this one. A GROVE IS CHOSEN FIRST (T-183) and wins: a side with a grove
	-- never gets a tight edge (nor a K-rail).
	-- ITS OWN STREAM, always the same four draws a section, so a tight edge (or a grove
	-- blocking one) changes nothing else the road chooses: with `TightChance = 0` the road is
	-- exactly the one before T-181.
	if tag ~= "Start" then
		local x = self.xrng
		local roll, uWidth, uCore, uAt = x:NextNumber(), x:NextNumber(), x:NextNumber(), x:NextNumber()
		local side = if edgeOver(1, 0, len) == Spline.CLIFF and not grove[1] then 1 elseif edgeOver(-1, 0, len) == Spline.CLIFF and not grove[-1] then -1 else 0
		if side ~= 0 and roll < T.TightChance then
			local w0, w1 = startRun[side], self.runoff[side]
			local wt = T.TightRunoff[1] + (T.TightRunoff[2] - T.TightRunoff[1]) * uWidth
			local rampIn = math.max(T.TightRamp, math.abs(w0 - wt) / T.TightRate)
			local rampOut = math.max(T.TightRamp, math.abs(w1 - wt) / T.TightRate)
			local room = len - rampIn - rampOut - 2
			if room >= T.TightRun[1] then
				local core = math.min(T.TightRun[1] + (T.TightRun[2] - T.TightRun[1]) * uCore, room)
				local a = rampIn + 1 + (room - core) * uAt
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
				sec.gl = { ga, gb, side }
				self.stats.tight += 1
			end
		end
	end
	if #kr > 0 then
		sec.kr = kr
	end
	if grove[-1] or grove[1] then
		local gv = {}
		for _, side in { -1, 1 } do
			if grove[side] then
				table.insert(gv, side)
				table.insert(gv, grove[side])
			end
		end
		sec.gv = gv
	end
	-- GRAND CLIFFS (T-185): how grand its rock and cliff faces are drawn, from no random
	-- stream at all, so it changes nothing else the road chooses
	sec.gd = self:_grand(sec)
	self.turning = nil
end

-- A CARVED APEX (T-182): the road cut into the cliff. On some sharp bends whose inside is
-- the rock face and whose outside is the drop, the inside runoff narrows to `CarvedGap` at
-- the apex -- the middle of the bend's held arc -- so the rock rises right at the tarmac's
-- edge, then widens again. Only that side's runoff knots change, eased (smoothstep) in and
-- out no faster than `CarvedRate` a stud, so the wall leans in gently enough to grind along.
-- Its own random stream, so no other choice moves. After `_terrain`, before the commit.
function SplineGen._carve(self: Gen, sec: Spline.Section)
	local T = Config.Spline.Terrain
	local tag = sec.tag
	if tag == "Straight" or tag == "Escape" or tag == "Start" or not (sec.rl and sec.rr and sec.el and sec.er) then
		return
	end
	local k = sec.k
	local kEnd = k[#k]
	if kEnd == 0 or 1 / math.abs(kEnd) > T.CarvedMaxRadius + 1e-6 then
		return
	end
	local r = self.crng
	if r:NextNumber() >= T.CarvedChance then
		return
	end
	local len = sec.len
	local inside = if kEnd > 0 then -1 else 1 -- a left turn's inside is the left
	-- the held arc: the run of the section at the bend's own curvature
	local _, _, _, kv = self.spline:tip()
	local holdFrom: number?, at = nil, 0
	for j = 1, #k, 2 do
		if math.abs(kv - kEnd) < 1e-12 and math.abs(k[j + 1] - kEnd) < 1e-12 then
			holdFrom = at
			break
		end
		at, kv = k[j], k[j + 1]
	end
	if not holdFrom or len - holdFrom < 20 then
		return
	end
	local function all(list: { number }, kind: number, a: number, b: number): boolean
		local s0 = 0
		for j = 1, #list, 2 do
			if list[j] > a and s0 < b and list[j + 1] ~= kind then
				return false
			end
			s0 = list[j]
		end
		return true
	end
	local hold = math.min(T.CarvedHold[1] + (T.CarvedHold[2] - T.CarvedHold[1]) * r:NextNumber(), (len - holdFrom) * 0.5)
	local gap, rate = T.CarvedGap, T.CarvedRate
	local old = if inside < 0 then sec.rl else sec.rr
	-- never on a grove's side (T-183); a tight edge (T-181) is on the cliff side, the other
	-- one, so the two can share a bend. In from the width the section starts at and out to
	-- the width it ends at, each no faster than `rate`
	if sec.gv then
		for j = 1, #sec.gv, 2 do
			if sec.gv[j] == inside then
				return
			end
		end
	end
	local prev = self.spline:runoffRaw(self.spline.length, inside)
	local eIn = math.max(T.CarvedEase, (prev - gap) / rate)
	-- out to the width the section already ends at, so the next section (and every other
	-- choice) is the same with or without the carve
	local vEnd = old[#old]
	local eOut = math.max(T.CarvedEase, (vEnd - gap) / rate)
	-- the apex is the middle of the held arc, or as near it as the easing allows (a bend
	-- is short: often the rock meets the road late, toward the exit)
	local lo, hi = math.max(eIn, holdFrom), len - eOut - hold
	if lo > hi + 1e-6 then
		return
	end
	local b = math.min(math.max((holdFrom + len - hold) * 0.5, lo), hi)
	local c = b + hold
	-- the rock all along the inside, the drop on the outside through the apex
	if not all(if inside < 0 then sec.el else sec.er, Spline.ROCK, 0, len) or not all(if inside < 0 then sec.er else sec.el, Spline.CLIFF, b, c) then
		return
	end
	local knots = {}
	local function knot(s: number, w: number)
		table.insert(knots, s)
		table.insert(knots, w)
	end
	if b - eIn > 1e-6 then
		knot(b - eIn, prev)
	end
	knot(b, gap)
	knot(c, gap)
	if c + eOut < len - 1e-6 then
		knot(c + eOut, vEnd)
	end
	knot(len, vEnd)
	if inside < 0 then
		sec.rl = knots
	else
		sec.rr = knots
	end
	self.stats.carved += 1
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
-- Grand cliffs (T-185)
--------------------------------------------------------------------------------

-- The planned turns the mountain changes sides through: a turnaround, by either of the
-- switchback's two bends, and the double hairpin's two.
local TURNAROUNDS = { turnaround = true, switchbackOut = true, double = true, doubleOut = true }

-- Studs from the road's end to the next turnaround the plan holds: the stretches still to
-- run before it (a detour's own turns counted as nothing). It can only come later than
-- this (a turn refused runs the stretch on, a turn takes room), never sooner.
function SplineGen._toTurnaround(self: Gen): number
	local ahead = 0
	for _, item in self.plan do
		if item.turn then
			if TURNAROUNDS[item.what] then
				return ahead
			end
		else
			ahead += math.max(item.left or 0, 0)
		end
	end
	return math.huge
end

-- How grand a rock body may be at grandeur `g`: its tallest (its crest), and how far it
-- reaches out past the grass at its least steep (`Road/SplineMesh`'s profile, at its largest).
local function bodyAt(g: number): (number, number)
	local T = Config.Spline.Terrain
	local h = T.RockHeight[2] + (T.GrandRockHeight[2] - T.RockHeight[2]) * g
	local lean = math.rad(T.RockSlope[1] + (T.GrandRockSlope[1] - T.RockSlope[1]) * g)
	local top = T.RockTop[1] + (T.RockTop[2] - T.RockTop[1]) * g
	local jag = (2.5 + 7 * g) * 0.5
	return h + 4 + 6 * g, h / math.tan(lean) + top + T.RockBack * h + jag
end

-- A section's grandeur knots {ds, g, ...}: 0 within `GrandNear` of a turnaround, either
-- way along the road, rising (smoothstep) to 1 over `GrandRamp`. Then cut back wherever a
-- rock body that grand would stand up through older road on its uphill side, so the leg
-- above stays on top of the mountain.
function SplineGen._grand(self: Gen, sec: Spline.Section): { number }
	local T = Config.Spline.Terrain
	local sp = self.spline
	local len = sec.len
	local s0 = sp.length
	local n = math.max(1, math.ceil(len / T.GrandKnotEvery - 1e-9))
	local out = table.create(2 * n)
	if self.turning and TURNAROUNDS[self.turning] then
		-- a turnaround itself: low all through, and the distance counts from its end
		self.lastTurnEnd = s0 + len
		self.lastGrand = 0
		for i = 1, n do
			out[2 * i - 1], out[2 * i] = if i == n then len else i * len / n, 0
		end
		return out
	end
	local ahead = self:_toTurnaround()
	if self.turning then
		ahead += len -- a straightening bend or a detour's turn, laid before the plan's next stretch
	end
	-- the points along the section a knot goes at, from the plan's own walk
	local x0, z0, yaw0, k0, g0, _, y0 = sp:tip()
	local pts: { { number } } = {}
	walk(x0, z0, yaw0, k0, sec.k, len / n, len / n, function(u, x, z)
		table.insert(pts, { u, x, z })
		return true
	end)
	local half = Config.Road.Width * 0.5
	local w = half + math.max(T.RunoffMax, T.GroveRunoff[2]) -- the foot of the rock, at its furthest
	local foot = half + math.max(T.RunoffMax, T.GroveRunoff[2]) + T.EdgeDepth + T.GrandKnotEvery * 0.5 -- old road's own width, and between knots
	local _, reachMax = bodyAt(1)
	local cell = sp.cell
	local values = table.create(n)
	for i = 1, n do
		local ds = if i == n then len else i * len / n
		local p = pts[i] or pts[#pts] or { ds, x0, z0 }
		local d = math.min(s0 + ds - self.lastTurnEnd, ahead - ds)
		local t = math.clamp((d - T.GrandNear) / T.GrandRamp, 0, 1)
		local g = t * t * (3 - 2 * t)
		if g > 0 then
			-- the side the rock is on here (or would be): the side across from a cliff
			local function kindAt(list: { number }): number
				for j = 1, #list, 2 do
					if list[j] >= ds - 1e-6 then
						return list[j + 1]
					end
				end
				return list[#list]
			end
			local l, r = kindAt(sec.el :: { number }), kindAt(sec.er :: { number })
			local side = if l == Spline.ROCK or r == Spline.CLIFF then -1 elseif r == Spline.ROCK or l == Spline.CLIFF then 1 else self.uphill
			local yaw = yawAlong(yaw0, k0, sec.k, ds)
			local y = yawAlong(y0, g0, sec.g, ds) -- the height: the grade's integral, as the heading is the curvature's
			local rx, rz = side * math.cos(yaw), -side * math.sin(yaw)
			local px, pz = p[2], p[3]
			-- old road near enough to matter, and not this stretch's own neighbours
			local hMax = bodyAt(g)
			local reach = w + reachMax + foot + hMax / math.max(T.GrandAbove, 0.1)
			local near: { number } = {}
			for cx = math.floor((px - reach) / cell), math.floor((px + reach) / cell) do
				for cz = math.floor((pz - reach) / cell), math.floor((pz + reach) / cell) do
					local list = sp.hash[(cx + 1048576) * 2097152 + (cz + 1048576)]
					if list then
						for j = 1, #list, 3 do
							local so = list[j]
							if s0 + ds - so > self.separation then
								local ox, oz = list[j + 1] - px, list[j + 2] - pz
								local along = ox * rx + oz * rz -- how far out on the rock's side
								local across = ox * rz - oz * rx
								if along > 0 and along < reach and math.abs(across) < reach then
									local yo = sp:heightAt(so)
									if yo - T.GrandMargin < y + hMax then
										table.insert(near, along)
										table.insert(near, across)
										table.insert(near, yo)
									end
								end
							end
						end
					end
				end
			end
			-- the grandest that stands clear: under each such road, or, short of it, no
			-- higher above it than it is far off (so no pinnacle towers over the leg above)
			while g > 0 do
				local h, reachG = bodyAt(g)
				local clear = true
				for j = 1, #near, 3 do
					local along, across, yo = near[j], near[j + 1], near[j + 2]
					-- distance from the old road to the body's footprint, a line from `w` out
					-- to `w + reachG`, past the old road's own width
					local da = if along < w then w - along elseif along > w + reachG then along - w - reachG else 0
					local off = math.max(0, math.sqrt(da * da + across * across) - foot) * T.GrandAbove
					if y + h > yo - T.GrandMargin + off then
						clear = false
						break
					end
				end
				if clear then
					break
				end
				g = math.max(0, g - 0.05)
			end
		end
		values[i] = g
	end
	-- never faster than 1 over `GrandRate` studs: rising after a cut-back point (from where
	-- the last section left off), and easing down to one in good time
	local rate = (len / n) / T.GrandRate
	for i = 1, n do
		values[i] = math.min(values[i], (if i == 1 then self.lastGrand else values[i - 1]) + rate)
	end
	for i = n - 1, 1, -1 do
		values[i] = math.min(values[i], values[i + 1] + rate)
	end
	for i = 1, n do
		out[2 * i - 1] = if i == n then len else i * len / n
		out[2 * i] = math.floor(values[i] * 1000 + 0.5) / 1000
	end
	self.lastGrand = out[2 * n]
	return out
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
			self.turning = "straighten"
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
				self.turning = item.what
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
	self:_carve(chosen)
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
