--!strict
--!native
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
--   * no grade past `MaxGrade` or changing faster than `MaxGradeRate`; height following the
--     mountain (`_followGrade`)
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
-- THE MOUNTAIN RANGE (features/mountain-range.md, T-238; the only road since T-247,
-- features/legacy-removal.md). Every road is cut into the range (`Road/Ground`): its height
-- follows the mountain (`_followGrade`), and it is laid to a PLAN toward the pass ahead
-- (`_planRange`): legs across the face, each a stretch of random sections that keep within
-- `LegHeadingLimit` of the heading the mountain gives (`_slopeAim`), joined by planned
-- hairpins. A planned turn is built to land exactly on the heading it is for, and is checked
-- for crossings and its escape like any other section; refused, the stretch before it runs
-- on `RetryAfter` and it is tried again. `fall` (the uphill heading) is the old fall line:
-- the range's way on is down it, and the edges' sides are read against it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)
local SplineTurnFit = require(script.Parent.SplineTurnFit)
local Ground = require(script.Parent.Ground)
local Range = require(script.Parent.Range)
local Seed7Drive = require(script.Parent.Seed7Drive)
local ContourRoute = require(script.Parent.SplineContourRoute)
local Gorge = require(script.Parent.SplineContourGorge)
local Traverse = require(script.Parent.SplineContourTraverse)
local TightHairpin = require(script.Parent.TightHairpin)

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
	straightens: number,
	hillChecked: number,
	hillRejected: number,
	hillRelaxed: number,
	hillTurns: number,
	turnsRefused: number, -- a planned turn that would have crowded old road, run on and retried
	cliffSwaps: number, -- times the mountain changed sides
	tight: number, -- tight cliff edges laid: gravel and a rail at the lip (T-181)
	carved: number, -- bends whose inside rock face was carved to the tarmac's edge (T-182)
	offGround: number, -- a ground run: candidates passed over for leaving the road off h (T-226)
	offGroundLaid: number, -- ...and sections laid off it all the same, none following it
	follows: number, -- on the range: sections laid by `_follow`, the bend that best follows h (T-242)
	traverses: number, -- preemptive turns away from a forecast cut or fill
	tracked: number, -- sections laid along a descent's leg (T-326)
	tightHairpins: number, -- tight hairpins laid in place of a descent's hairpin (T-333)
	tightRefused: number, -- ...and ones tried that did not fit (gentle face, off h, crowded)
	tightWhy: { [string]: number }, -- why, by reason
	tightTurns: { number }, -- degrees each turnaround tried asked for (a half turn is 180)
	tightNotes: { string }, -- what refused each one that got as far as the mountain
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
	hillRetries: number?, -- bounded location retries for terrain fit (T-190)
	-- the heading this stretch keeps, or this turn lands on, read from the mountain where the
	-- road is when it gets there, not planned ahead (T-226)
	slope: Slope?,
	autoDir: boolean?, -- the turn's direction is toward that heading, whichever way
	-- on the range (T-238): a leg ends once the road is this far across (`Range` v), going
	-- `untilDir` (1 or -1), whatever is left of it
	untilV: number?,
	untilDir: number?,
	refused: number?, -- times this turn was refused
	nextDirV: number?, -- a turnaround after a traverse (T-326): which way across the next leg runs
	traverse: boolean?, -- ...and it ends a descent's surveyed leg
	climb: boolean?, -- a turnaround on a climb (T-333: a tight hairpin there climbs)
	-- T-337: a descent's hairpin planned as a tight one (on steeper ground), the leg's own
	-- heading kept to run on by if it is refused, and the leg's stretch ending this far short
	-- of its end (else `Range.TraverseArrive`)
	tightWanted: boolean?,
	legSlope: Slope?,
	arrive: number?,
}

-- What a heading on the mountain is (T-226, T-238): "leg" across the face toward the pass
-- ahead, tilted enough to descend (or climb) `gd` a stud; "pass" straight for the pass.
-- `side` is which way across the face (the fall line's sides). `swapped` (T-242): the leg
-- has gone over to the other way along its level line.
-- "traverse" (T-326): along the surveyed descent leg (`leg`); "return": the way back across
-- after the hairpin that ends it, `dirV` across the range, falling `gd` a stud.
export type Slope = { kind: string, side: number, gd: number?, swapped: boolean?, dirV: number? }

export type Gen = typeof(setmetatable(
	{} :: {
		spline: Spline.Spline,
		rng: Random,
		seed: number,
		excessClimb: number, -- rise and fall already used above the sustained approach grade
		excessDescent: number,
		pitchUsed: number, -- the steep pitch's allowance spent (T-326)
		corridor: ContourRoute.Route?,
		-- THE DESCENT (T-326): the leg across the face the road is following, which way the
		-- next leg runs after the hairpin that ends it, and the way the road must make headway
		-- while it follows one (across the range, not on along it)
		leg: Traverse.Leg?,
		nextDirV: number?,
		descending: boolean?, -- coming down from a crest, in legs, until the climb begins
		headway: { number }?,
		setback: { number }?, -- ...and the way a descent's hairpin must not fall back along
		turning: boolean?, -- laying a planned turn (no steep pitch allowance in a hairpin)
		sections: { Spline.Section },
		recent: { string },
		lastDir: number,
		lastWasBend: boolean,
		fall: number, -- the uphill heading (a yaw), fixed for the road: the range's way on is down it
		-- THE GROUND (T-218): the mountain the road is cut into, the range (T-238); every run's
		ground: Ground.Field,
		legSide: number, -- which way across the slope the current leg runs (1 or -1)
		lastSlope: Slope?, -- the heading the last stretch kept, for a wait (T-226)
		prng: Random, -- the plan's own stream
		plan: { Item },
		turns: { { any } }, -- every planned turn laid, {s0, s1, what}: the server's record, for tests
		turnFits: { any }, -- accepted preflight measurements, server only
		aim: number, -- the heading random sections keep near...
		limit: number, -- ...and how far off it they may go
		upSign: number, -- which way off `aim` (1 left, -1 right) is up the slope; 0 none
		limitUp: number, -- the limit that way
		trng: Random, -- the mountainside's own stream
		grng: Random, -- the groves' own stream (T-183), so they never change the rest
		xrng: Random, -- the tight cliff edges' own stream (T-181), so they never change the rest
		crng: Random, -- the carved apexes' own stream, so they move no other choice (T-182)
		hrng: Random, -- the tight hairpins' own stream (T-333), so they move no other choice
		wrng: Random, -- the descent legs' weave (T-337), its own stream
		-- the weave of the leg the road is on (T-337): how far either side of the leg, which side
		-- it leans to now, and where along the leg it is gone by
		weave: { amp: number, side: number, upTo: number }?,
		tightNext: number, -- s: no tight hairpin is laid before here (T-333)
		tightLast: number, -- s: where the last tight hairpin's shape ended (T-337: `Gap` from it)
		uphill: number, -- the side the mountain is on: -1 left, 1 right
		inBand: boolean, -- heading within `AlongFallLine` of the fall line: the side holds
		crossAt: number, -- s: where the heading last crossed the fall line, inside the band (T-189)
		runoff: { [number]: number }, -- the last runoff width chosen, by side
		-- THE DRESSING (T-327, `Road/RoadDressing.attach`): called with each section once it is
		-- final, before it is laid, to stand what goes beside it. Never by a turn's preview.
		dress: ((Spline.Section) -> ())?,
		clearance: number,
		separation: number,
		stats: Stats,
		-- THE RANGE (T-238): the pass the road heads for, on the ridge ahead, and which way
		-- the planned stretches go to reach it
		target: { x: number, z: number, y: number, k: number }?,
	},
	SplineGen
))

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function sign(x: number): number
	return if x > 0 then 1 elseif x < 0 then -1 else 0
end

-- A fitted turn ends straight; its held bend still determines its outside and carved apex.
local function bendCurvature(knots: {number}): number
	for j=#knots,2,-2 do if knots[j]~=0 then return knots[j] end end
	return 0
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
	local M = Config.Spline.Mountain
	local prng = Random.new((seed * 13 + 4099) % 2 ^ 31)
	-- THE FALL LINE: the start heading turned `FallLineTurn` to a side chosen from the seed,
	-- so the first leg runs across the slope
	local q = if prng:NextNumber() < 0.5 then -1 else 1
	local fall = wrap(spline.origin.yaw + q * math.rad(M.FallLineTurn))
	spline.fall = fall -- for the turns' fit (`Road/SplineTurnFit`, T-190)
	-- THE GROUND (T-218, the only ground since T-247): the mountain the road is cut into,
	-- drawn by each client as its own mesh (`Drift/GroundMeshView`)
	local ground = Ground.field(seed, spline.origin, fall)
	spline.mountain = ground
	local self = setmetatable({
		spline = spline,
		rng = Random.new(seed),
		seed = seed,
		excessClimb = 0,
		excessDescent = 0,
		pitchUsed = 0,
		sections = {},
		recent = {},
		lastDir = 0,
		lastWasBend = false,
		fall = fall,
		ground = ground,
		legSide = -q,
		prng = prng,
		plan = {},
		turns = {},
		turnFits = {},
		-- (the first stretch sets both before any section is chosen)
		aim = spline.origin.yaw,
		limit = math.rad(M.LegHeadingLimit),
		upSign = 0,
		limitUp = math.rad(M.LegHeadingLimit),
		trng = Random.new((seed * 7 + 1013) % 2 ^ 31),
		grng = Random.new((seed * 11 + 2027) % 2 ^ 31),
		xrng = Random.new((seed * 17 + 2311) % 2 ^ 31),
		crng = Random.new((seed * 19 + 3089) % 2 ^ 31), -- not the groves' seed: a stream of its own
		hrng = Random.new((seed * 23 + 4099) % 2 ^ 31),
		wrng = Random.new((seed * 29 + 5101) % 2 ^ 31),
		tightNext = 0,
		tightLast = -math.huge,
		-- the mountain starts on the side the uphill direction is on (with the fall line square
		-- to the start heading, it is never inside the band)
		uphill = if math.sin(spline.origin.yaw - fall) > 0 then 1 else -1,
		inBand = false,
		crossAt = 0,
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
			straightens = 0,
			turnsRefused = 0,
			hillChecked = 0,
			hillRejected = 0,
			hillRelaxed = 0,
			hillTurns = 0,
			cliffSwaps = 0,
			tight = 0,
			carved = 0,
			offGround = 0,
			offGroundLaid = 0,
			follows = 0,
			traverses = 0,
			tracked = 0,
			tightHairpins = 0,
			tightRefused = 0,
			tightWhy = {},
			tightTurns = {},
			tightNotes = {},
		},
	}, SplineGen)
	if ground.range.basins then
		-- The first recorded section includes the lead-in from the normal spawn.
		self:step()
		return self
	end
	-- the start straight follows the mountain too (T-226), level where it begins
	local L = Config.Spline.StartStraight
	local start: Spline.Section = { len = L, k = { L, 0 }, g = { L, 0 }, b = { L, 0 }, tag = "Start" }
	start.g = (self:_followGrade(start.k, 0, spline.origin.y))
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

	-- THE RUNOFF (T-228): from the mountain's side slope, wide on shallow ground and thin on
	-- steep (`_slopeRunoff`), not at random. A grove only where it is shallow the whole way:
	-- its wide runoff on a steep slope would be a deep cut
	local slope = if tag ~= "Start" then self:_slopeRunoff(sec) else nil
	if slope then
		local G = Config.Spline.Ground
		for _, kn in slope do
			if kn[2] < G.RunoffWide - 1 then
				grove[-1], grove[1] = nil, nil
				break
			end
		end
	end

	-- Each side on its own, never changing faster than a quarter of a stud per stud, so the
	-- grass's edge never runs at the car faster than about 14 degrees (smoothstep's steepest
	-- is 1.5 times that)
	local function runoff(side: number): { number }
		if not slope then
			self.runoff[side] = T.StartRunoff
			return { len, T.StartRunoff }
		end
		local out = {}
		local prev, prevAt = self.runoff[side], 0
		for _, kn in slope do
			local at = kn[1]
			local w = if grove[side] then between(T.GroveRunoff) else kn[2]
			local most = 0.25 * (at - prevAt)
			w = math.clamp(w, prev - most, prev + most)
			table.insert(out, at)
			table.insert(out, w)
			prev, prevAt = w, at
		end
		self.runoff[side] = prev
		return out
	end
	local startRun = { [-1] = self.runoff[-1], [1] = self.runoff[1] } -- for a tight edge (T-181)
	sec.rl = runoff(-1)
	sec.rr = runoff(1)

	-- THE UPHILL SIDE: the mountain on one side, the drop on the other, and WHICH SIDE follows
	-- from the heading against the fall line (T-166): the side the uphill direction is on.
	-- Heading within `AlongFallLine` of straight up or down the slope counts as neither and
	-- the side holds. Coming out of that band on the other side -- the road has turned back
	-- through a hairpin -- the mountain changes sides, AT ONE POINT: where the heading last
	-- crossed the fall line itself, the middle of the turn (or the section's start, if that
	-- was in a section already laid) (T-189).
	-- IT CHOOSES NOTHING AT THE EDGE (T-261): until then the uphill side was a rock face and
	-- the downhill one a cliff, hidden walls and holes the car met; now past the runoff is the
	-- drawn ground (T-258, features/car-edges.md). It is kept for what is placed by it: the
	-- K-rails above the drop, the tight edges and the carved apexes. The two draws that once
	-- chose a hedge are still made and thrown away, so every choice from this stream (the
	-- K-rails) is the road it was.
	r:NextNumber()
	r:NextNumber()
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
	local up = {}
	for _, sp in spans do
		table.insert(up, sp[1])
		table.insert(up, sp[2])
	end
	sec.up = up
	-- is `side` the downhill one over the whole of [a, b] of the section?
	local function downhillOver(side: number, a: number, b: number): boolean
		return SplineGen._uphillOver(up, -side, a, b)
	end

	-- CRASH BARRIERS are not chosen here: the dressing layer stands them beside the finished
	-- section (`Road/RoadDressing`, T-327). Until T-306 they were drawn from this stream
	-- (half the bends whose outside the fall line called downhill, and the odd stretch
	-- anywhere); those draws are still made and thrown away, so everything else this stream
	-- chooses (a grove's widths) is the road it was.
	if len >= 60 then
		if bend then
			r:NextNumber()
		elseif r:NextNumber() < 0.08 then
			r:NextNumber()
			r:NextNumber()
			r:NextNumber()
		end
	end

	-- TIGHT CLIFF EDGES (T-181): now and then, on a side with a cliff the whole way along,
	-- the runoff closes in to a few studs of gravel, the lip just past it. Its width eases in
	-- and out at `TightRate` on the runoff's own smoothstep knots, so nothing steps; the
	-- gravel reaches `TightLead` past the narrow part into the easing (`sec.gl`), and the
	-- dressing stands a crash barrier on the tarmac's edge all along it. A GROVE IS CHOSEN
	-- FIRST (T-183) and wins: a side with a grove never gets a tight edge.
	-- WHICH SIDE (T-306): one where the ground really falls away (`TightFallDrop`) all along
	-- the stretch; the side the fall line calls downhill the whole section is tried first
	-- (until T-306 the only one tried, and it is the rising one about half the time), then
	-- the other.
	-- ITS OWN STREAM, always the same four draws a section, so a tight edge (or a grove
	-- blocking one) changes nothing else the road chooses: with `TightChance = 0` the road is
	-- exactly the one before T-181.
	if tag ~= "Start" then
		local x = self.xrng
		local roll, uWidth, uCore, uAt = x:NextNumber(), x:NextNumber(), x:NextNumber(), x:NextNumber()
		local first = if downhillOver(1, 0, len) then 1 elseif downhillOver(-1, 0, len) then -1 else 1
		local drops: Drops? = nil -- read once, before either side closes in
		for _, side in { first, -first } do
			-- (never on a tight hairpin's island side, T-333: that side is the island's bank, with
			-- no runoff at all, not a cliff)
			if roll >= T.TightChance or grove[side] or sec.gl or (sec.th and side == -sec.th[5]) then
				continue
			end
			drops = drops or self:sideDrops(sec, startRun)
			local w0, w1 = startRun[side], self.runoff[side]
			local wt = T.TightRunoff[1] + (T.TightRunoff[2] - T.TightRunoff[1]) * uWidth
			local rampIn = math.max(T.TightRamp, math.abs(w0 - wt) / T.TightRate)
			local rampOut = math.max(T.TightRamp, math.abs(w1 - wt) / T.TightRate)
			local room = len - rampIn - rampOut - 2
			if room >= T.TightRun[1] then
				local core = math.min(T.TightRun[1] + (T.TightRun[2] - T.TightRun[1]) * uCore, room)
				local a = rampIn + 1 + (room - core) * uAt
				local b = a + core
				local ga = a - math.min(T.TightLead, rampIn * 0.5)
				local gb = b + math.min(T.TightLead, rampOut * 0.5)
				-- b + rampOut is at most len - 1, so the last knot is always its own
				local knots = { a - rampIn, w0, a, wt, b, wt, b + rampOut, w1, len, w1 }
				local was = if side < 0 then sec.rl else sec.rr
				if side < 0 then
					sec.rl = knots
				else
					sec.rr = knots
				end
				-- (falling from the grass's edge as it is, and from the lip once it closes in)
				if not (SplineGen._fallsOver(drops :: Drops, side, ga, gb) and SplineGen._fallsOver(self:sideDrops(sec, startRun), side, ga, gb)) then
					if side < 0 then
						sec.rl = was
					else
						sec.rr = was
					end
				else
					sec.gl = { ga, gb, side }
					self.stats.tight += 1
				end
			end
		end
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
end

-- Is the mountain on `side` over the whole of [a, b] of a section, by its uphill spans
-- `{dsEnd, side, ...}` (T-261)?
function SplineGen._uphillOver(up: { number }, side: number, a: number, b: number): boolean
	local s0 = 0
	for j = 1, #up, 2 do
		if up[j] > a and s0 < b and up[j + 1] ~= side then
			return false
		end
		s0 = up[j]
	end
	return true
end

-- A CARVED APEX (T-182): the road cut into the cliff. On some sharp bends whose inside is
-- the rising ground (T-308: as read off the mountain), the inside runoff narrows to `CarvedGap` at
-- the apex -- the middle of the bend's held arc -- so the rock rises right at the tarmac's
-- edge, then widens again. Only that side's runoff knots change, eased (smoothstep) in and
-- out no faster than `CarvedRate` a stud, so the wall leans in gently enough to grind along.
-- Its own random stream, so no other choice moves. After `_terrain`, before the commit.
function SplineGen._carve(self: Gen, sec: Spline.Section)
	local T = Config.Spline.Terrain
	local tag = sec.tag
	if tag == "Straight" or tag == "Escape" or tag == "Start" or not (sec.rl and sec.rr and sec.up) then
		return
	end
	local k = sec.k
	local kEnd = bendCurvature(k)
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
	local holdFrom: number?, holdTo: number?, at = nil, nil, 0
	for j = 1, #k, 2 do
		if math.abs(kv - kEnd) < 1e-12 and math.abs(k[j + 1] - kEnd) < 1e-12 then
			holdFrom = holdFrom or at
			holdTo = k[j]
		end
		at, kv = k[j], k[j + 1]
	end
	if not holdFrom or not holdTo or holdTo - holdFrom < 20 then
		return
	end
	local hold = math.min(T.CarvedHold[1] + (T.CarvedHold[2] - T.CarvedHold[1]) * r:NextNumber(), (holdTo - holdFrom) * 0.5)
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
	-- nor on a tight edge's side (T-306: its side is the one the ground falls on, which the
	-- fall line can call the rock's)
	if sec.gl and sec.gl[3] == inside then
		return
	end
	local prev = self.spline:runoffRaw(self.spline.length, inside)
	local eIn = math.max(T.CarvedEase, (prev - gap) / rate)
	-- out to the width the section already ends at, so the next section (and every other
	-- choice) is the same with or without the carve
	local vEnd = old[#old]
	local eOut = math.max(T.CarvedEase, (vEnd - gap) / rate)
	-- the apex is the middle of the held arc, or as near it as the easing allows (a bend
	-- is short: often the rock meets the road late, toward the exit)
	local lo, hi = math.max(eIn, holdFrom), math.min(holdTo - hold, len - eOut - hold)
	if lo > hi + 1e-6 then
		return
	end
	local b = math.min(math.max((holdFrom + holdTo - hold) * 0.5, lo), hi)
	local c = b + hold
	-- (No rail is read here: the dressing stands barriers only where the ground falls, and
	-- the carve needs it to rise, below. Until T-327 a rail on the inside was a guard.)
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
	-- THE GROUND RISES on the inside, all along the carve, read from the carved edge
	-- (T-308): the bend is cut into the hill, never into a side that falls away. Until T-308
	-- the side the fall line calls the mountain's (`up`) was taken for it, and that is the
	-- falling side about half the time. Read off the ground (`sideDrops`), so the draws
	-- above are the same and no other choice moves.
	local startRun = { [-1] = self.spline:runoffRaw(self.spline.length, -1), [1] = self.spline:runoffRaw(self.spline.length, 1) }
	if not SplineGen._risesOver(self:sideDrops(sec, startRun), inside, b - eIn, c + eOut) then
		if inside < 0 then
			sec.rl = old
		else
			sec.rr = old
		end
		return
	end
	self.stats.carved += 1
end

-- A client's copy: the same road from the same sections, with no choosing.
-- `fall` is the mountain's uphill heading and `seed` the run's, as the server sent them with
-- the road (T-190): with both, the copy carries the same mountain (`Road/Ground`, T-218).
function SplineGen.replay(sections: { Spline.Section }, origin: Spline.Origin?, fall: number?, seed: number?): Spline.Spline
	local spline = Spline.new(origin)
	spline.fall = fall
	if fall and seed then
		spline.mountain = Ground.field(seed, spline.origin, fall)
	end
	for _, sec in sections do
		spline:append(sec)
	end
	return spline
end

-- A STEEP PITCH'S ALLOWANCE (T-326): height gained or lost faster than `PitchSustain`
-- spends it, `PitchRecover` of the shortfall below that pays it back, `PitchBudget` at most.
local function pitchSpend(used: number, ga: number, gb: number, ds: number): number
	local R = Config.Range
	local sustain = math.tan(math.rad(R.PitchSustain))
	local over = 0.5 * (math.abs(ga) + math.abs(gb)) - sustain
	return math.clamp(used + (if over > 0 then over else R.PitchRecover * over) * ds, 0, R.PitchBudget)
end

function SplineGen._commit(self: Gen, sec: Spline.Section)
	local prevU, grade = 0, self.spline:gradeAt(self.spline.length)
	local cruise = math.tan(math.rad(Config.Range.ContourGrade))
	for i = 1, #sec.g, 2 do
		local u, nextGrade = sec.g[i], sec.g[i + 1]
		local ds = u - prevU
		local rise = 0.5 * (grade + nextGrade) * ds
		self.excessClimb = math.clamp(self.excessClimb + rise - cruise * ds, 0, Config.Range.ContourPitchRise)
		self.excessDescent = math.clamp(self.excessDescent - rise - cruise * ds, 0, Config.Range.ContourPitchRise)
		self.pitchUsed = pitchSpend(self.pitchUsed, grade, nextGrade, ds)
		prevU, grade = u, nextGrade
	end
	-- dressed (T-327) once it is final, before it is laid, so what stands beside it travels
	-- in it; the dressing reads the section and the road so far, and writes nothing else
	if self.dress then
		self.dress(sec)
	end
	self.spline:append(sec)
	table.insert(self.sections, sec)
	local st = self.stats
	st.sections += 1
	local tag = sec.tag or "?"
	st.kinds[tag] = (st.kinds[tag] or 0) + 1
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
local function walk(x: number, z: number, yaw0: number, k0: number, knots: { number }, every: number, first: number, emit: (number, number, number) -> boolean?, survey: boolean?): boolean
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
		local s1 = math.min(knots[j], total, nextEmit)
		if survey and kA == knots[j + 1] then
			-- Survey points are farther apart. Integrate a straight/circular arc directly.
			local y0 = yawAt(s)
			if math.abs(kA) < 1e-10 then
				x -= (s1 - s) * math.sin(y0)
				z -= (s1 - s) * math.cos(y0)
			else
				local y1 = yawAt(s1)
				x += (math.cos(y1) - math.cos(y0)) / kA
				z += (math.sin(y0) - math.sin(y1)) / kA
			end
		else
			s1 = math.min(s + step, s1)
			local y0, ym, y1 = yawAt(s), yawAt((s + s1) * 0.5), yawAt(s1)
			local h = (s1 - s) / 6
			x += h * (-math.sin(y0) - 4 * math.sin(ym) - math.sin(y1))
			z += h * (-math.cos(y0) - 4 * math.cos(ym) - math.cos(y1))
		end
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

-- A ground run's runoff along a section, from the mountain's side slope (T-228): {ds, width}
-- every `RunoffSlopeEvery` studs or so, the last at its end, the width `RunoffWide` on
-- shallow ground to `RunoffThin` on steep (`Ground.steepness`). The same both sides.
function SplineGen._slopeRunoff(self: Gen, sec: Spline.Section): { { number } }
	local G = Config.Spline.Ground
	local f = self.ground :: Ground.Field
	local len = sec.len
	local n = math.max(1, math.ceil(len / G.RunoffSlopeEvery - 1e-9))
	local x0, z0, yaw0, k0 = self.spline:tip()
	local out: { { number } } = {}
	walk(x0, z0, yaw0, k0, sec.k, len / n, len / n, function(u, x, z)
		if #out < n then
			local yaw = yawAlong(yaw0, k0, sec.k, u)
			local q = Ground.steepness(f, x, z, math.cos(yaw), -math.sin(yaw))
			table.insert(out, { if #out == n - 1 then len else u, G.RunoffWide + (G.RunoffThin - G.RunoffWide) * q })
		end
		return true
	end)
	if #out == 0 then
		table.insert(out, { len, self.runoff[1] })
	elseif out[#out][1] < len then
		out[#out][1] = len
	end
	return out
end

--------------------------------------------------------------------------------
-- The drop beside the road: what a tight cliff edge and a carved apex are read by, and
-- (with its own settings) what the dressing stands its barriers by (T-306, T-327)
--------------------------------------------------------------------------------

-- The drop beside a section, read every `Sample` studs or so from its start to its end:
-- `u` the points, `k` the curvature there, `drop[side]` how far the mountain is below the
-- grass's outer edge `Probe` studs past it (on the inside of a bend scaled from nearer,
-- `InsideReach`; -huge where the bend encloses that side). Negative: the ground rises.
export type Drops = { u: { number }, k: { number }, drop: { [number]: { number } } }
-- How it is read: the planner's own (`Config.Spline.Terrain.Drop*`), or the dressing's.
export type DropReading = { Probe: number, ProbeMin: number, InsideReach: number, Sample: number }

local function plannerReading(): DropReading
	local T = Config.Spline.Terrain
	return { Probe = T.DropProbe, ProbeMin = T.DropProbeMin, InsideReach = T.DropInsideReach, Sample = T.DropSample }
end

-- A knotted value `u` studs into a section, from `v0` as it starts: straight between its
-- knots (the curvature's own way; the runoff and the bank are eased, near enough for this).
local function knotAlong(v0: number, knots: { number }, u: number): number
	local s, v = 0, v0
	for j = 1, #knots, 2 do
		local s1, v1 = knots[j], knots[j + 1]
		if u <= s1 then
			local L = s1 - s
			return if L > 0 then v + (v1 - v) * (u - s) / L else v1
		end
		s, v = s1, v1
	end
	return v
end

-- The drop beside `sec`, a section about to be laid at the road's tip. `startRun`: each
-- side's runoff as the section starts (its knots carry on from it). `P`: how to read it
-- (the planner's own when nil).
function SplineGen.sideDrops(self: Gen, sec: Spline.Section, startRun: { [number]: number }, P: DropReading?): Drops
	local T = Config.Spline.Terrain
	local R = P or plannerReading()
	local half = Config.Road.Width * 0.5
	local f = self.ground
	local len = sec.len
	local n = math.max(1, math.ceil(len / R.Sample - 1e-9))
	local x0, z0, yaw0, k0, g0, b0, y0 = self.spline:tip()
	local us, xs, zs = { 0 }, { x0 }, { z0 }
	walk(x0, z0, yaw0, k0, sec.k, len / n, len / n, function(u, x, z)
		if #us <= n then
			table.insert(us, u)
			table.insert(xs, x)
			table.insert(zs, z)
		end
		return true
	end)
	if #us > 1 then
		us[#us] = len
	end
	local ks: { number } = {}
	local drop: { [number]: { number } } = { [-1] = {}, [1] = {} }
	for i, u in us do
		local k = knotAlong(k0, sec.k, u)
		ks[i] = k
		local yaw = yawAlong(yaw0, k0, sec.k, u)
		local y = yawAlong(y0, g0, sec.g, u) -- (the height is the grade's integral, as the yaw is the curvature's)
		local tb = math.tan(knotAlong(b0, sec.b, u))
		local rx, rz = math.cos(yaw), -math.sin(yaw)
		for _, side in { -1, 1 } do
			local w = knotAlong(startRun[side], (if side < 0 then sec.rl else sec.rr) :: { number }, u)
			local inside = k ~= 0 and (k > 0) == (side < 0)
			if inside then
				w = math.min(w, math.max(T.InsideShare / math.abs(k) - half, 0)) -- as `Spline.runoffAt`
			end
			-- the grass's outer edge, as `Spline.terrainY` has it
			local edgeY = y + side * tb * (half + w * 0.5) - T.RoadLip
			local D = R.Probe
			if inside then
				D = math.min(D, R.InsideReach / math.abs(k) - half - w)
			end
			if D < R.ProbeMin then
				drop[side][i] = -math.huge
			else
				local dist = side * (half + w + D)
				drop[side][i] = (edgeY - Ground.h(f, xs[i] + dist * rx, zs[i] + dist * rz)) * R.Probe / D
			end
		end
	end
	return { u = us, k = ks, drop = drop }
end

-- The same drop read off a LAID road with a mountain, at `s` on `side`, and the grass's edge
-- height and the point it is read at (nil where the bend encloses that side): for the tests.
-- Within a few studs of `sideDrops` (which reads the eased runoff and bank as straight lines).
function SplineGen.dropBeside(sp: Spline.Spline, s: number, side: number, P: DropReading?): (number, number?, number?, number?)
	local T = Config.Spline.Terrain
	local R = P or plannerReading()
	local half = Config.Road.Width * 0.5
	local k = sp:curvatureAt(s)
	local w = sp:runoffAt(s, side)
	local inside = k ~= 0 and (k > 0) == (side < 0)
	local edgeY = sp:terrainY(s, side * (half + w))
	local D = R.Probe
	if inside then
		D = math.min(D, R.InsideReach / math.abs(k) - half - w)
	end
	if D < R.ProbeMin or not sp.mountain then
		return -math.huge, nil, nil, nil
	end
	local x, z = sp:planAt(s)
	local yaw = sp:yawAt(s)
	local dist = side * (half + w + D)
	local px, pz = x + dist * math.cos(yaw), z - dist * math.sin(yaw)
	return (edgeY - Ground.h(sp.mountain, px, pz)) * R.Probe / D, edgeY, px, pz
end

-- Does the ground fall away (`TightFallDrop`) on `side` all along [a, b] of the section,
-- the points either side of each end included? (A tight cliff edge's test.)
function SplineGen._fallsOver(drops: Drops, side: number, a: number, b: number): boolean
	local step = Config.Spline.Terrain.DropSample + 1e-6
	local need = Config.Spline.Terrain.TightFallDrop
	for i, u in drops.u do
		if u > a - step and u < b + step and drops.drop[side][i] < need then
			return false
		end
	end
	return true
end

-- Does the ground RISE at least `CarvedRise` on `side` all along [a, b] of the section, the
-- points either side of each end included (T-308)? A side the bend encloses (no reading) does not.
function SplineGen._risesOver(drops: Drops, side: number, a: number, b: number): boolean
	local step = Config.Spline.Terrain.DropSample + 1e-6
	local need = -Config.Spline.Terrain.CarvedRise
	for i, u in drops.u do
		if u > a - step and u < b + step then
			local d = drops.drop[side][i]
			if d == -math.huge or d > need then
				return false
			end
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

--------------------------------------------------------------------------------
-- The road on the slope (T-226): in a ground run the mountain leads
--------------------------------------------------------------------------------

-- h's slope at a place: its gradient (uphill), from h `span` studs either side.
local function gradient(f: Ground.Field, x: number, z: number, span: number): (number, number)
	local e = span * 0.5
	return (Ground.h(f, x + e, z) - Ground.h(f, x - e, z)) / span, (Ground.h(f, x, z + e) - Ground.h(f, x, z - e)) / span
end

-- h as the road follows it: the mean of a point and four round it, `r` studs off.
local function followH(f: Ground.Field, x: number, z: number, r: number): number
	local h = Ground.h
	return (2 * h(f, x, z) + h(f, x + r, z) + h(f, x - r, z) + h(f, x, z + r) + h(f, x, z - r)) / 6
end

-- The height gained `u` studs into a ramp from grade `ga` toward `gb` at `rate` a stud, then held.
local function rampRise(u: number, ga: number, gb: number, rate: number): number
	local dg = gb - ga
	local L = math.abs(dg) / rate
	local a = sign(dg) * rate
	if u <= L then
		return ga * u + 0.5 * a * u * u
	end
	return ga * L + 0.5 * a * L * L + gb * (u - L)
end

-- A steep pitch spends height above the sustained grade. Keep enough height in
-- reserve to round back to that grade at the road's existing vertical-curve rate.
local function pitchLimit(used: number, span: number, cruise: number, peak: number): number
	local remaining = math.max(0, Config.Range.ContourPitchRise - used)
	return math.min(peak, cruise + math.min(remaining / span, math.sqrt(2 * Config.Spline.MaxGradeRate * remaining)))
end

-- A ground run's grade for a section whose curvature knots are `knots`, and the furthest
-- its centre line then is from h (studs). Chosen a piece at a time, `FollowSegment` studs
-- each: the grade whose road best fits h over that piece (least squares), and on
-- `FollowAhead` past it (counted `FollowAheadWeight` as much), where the road is taken to ease
-- on toward h's own grade there; past the section's end it is taken to carry on straight.
-- The grade eases at `MaxGradeRate` and never passes `MaxGrade`, as every section's does, so
-- the road stays drivable: it cuts or fills only where h changes faster than that allows.
-- `fill` (T-238): how much more a stud of road ABOVE h counts than one below it (1 unless
-- given): a hairpin on a steep face sits in a cut, a wall on its inside, not out on fill.
-- Returns the grade's knots, the furthest the centre line is from h, and of that, the most it
-- is above h (fill) and below it (cut); and how far above h it ends (below it: negative).
function SplineGen._followGrade(self: Gen, knots: { number }, g0: number, y0: number, fill: number?, gradeLimit: number?): ({ number }, number, number, number, number)
	local C = Config.Spline
	local G = C.Ground
	local f = self.ground :: Ground.Field
	local gMax = math.tan(math.rad(gradeLimit or C.MaxGrade))
	local rate = C.MaxGradeRate
	local len = knots[#knots - 1]
	local ahead = G.FollowAhead
	local path = table.clone(knots)
	table.insert(path, len + ahead)
	table.insert(path, 0)
	local x0, z0, yaw0, k0 = self.spline:tip()
	local us: { number }, hs: { number } = {}, {}
	walk(x0, z0, yaw0, k0, path, G.FollowStep, G.FollowStep, function(u, x, z)
		table.insert(us, u)
		table.insert(hs, followH(f, x, z, G.FollowRadius))
		return true
	end)
	if #us == 0 then
		return ramp(g0, 0, rate, 0, len), 0, 0, 0
	end
	local wAhead = G.FollowAheadWeight
	local seg = G.FollowSegment
	local out: { number } = {}
	local yA, gA, a = y0, g0, 0
	-- along a descent's leg (T-326) a steep pitch lasts only as long as its allowance: the
	-- grade then eases back toward `PitchSustain` and the leg's survey keeps the road on ground
	-- that allows it
	local budget = if self.headway and not self.turning then Config.Range.PitchBudget else nil
	local sustain = math.tan(math.rad(Config.Range.PitchSustain))
	local used = self.pitchUsed
	local worst, worstFill, worstCut = 0, 0, 0
	while a < len - 1e-6 do
		local b = math.min(a + seg, len)
		if len - b < seg * 0.5 then
			b = len
		end
		-- the samples this piece answers for, and h's own grade over the look past it
		local i0, iB, i1 = nil, nil, nil
		for i, u in us do
			if u > a + 1e-6 and not i0 then
				i0 = i
			end
			if u <= b + 1e-6 then
				iB = i
			end
			if u <= b + ahead + 1e-6 then
				i1 = i
			end
		end
		local hB = if iB then hs[iB] else yA
		local uB = if iB then us[iB] else a
		local gAhead = if i1 and iB and us[i1] > uB then (hs[i1] - hB) / (us[i1] - uB) else gA
		gAhead = math.clamp(gAhead, -gMax, gMax)
		local span = b - a
		local function cost(gt: number): number
			local gB = gA + sign(gt - gA) * math.min(math.abs(gt - gA), rate * span)
			local yB = yA + rampRise(span, gA, gB, rate)
			local sum = 0
			if i0 and i1 then
				for i = i0, i1 do
					local u = us[i]
					local y, w
					if u <= b + 1e-6 then
						y, w = yA + rampRise(u - a, gA, gB, rate), 1
					else
						y, w = yB + rampRise(u - b, gB, gAhead, rate), wAhead
					end
					local e = y - hs[i]
					if fill and e > 0 then
						w *= fill
					end
					sum += w * e * e
				end
			end
			return sum
		end
		-- a coarse sweep, then a finer one round the best
		-- (past the allowance, a stud of height the steeper grade gains counts as a stud off
		-- h at every sample: so the grade eases where it can, and still follows a face that
		-- falls away faster rather than leaving a trench or a causeway)
		local lim = gMax
		if budget then
			local remaining = math.max(0, budget - used)
			lim = math.min(gMax, sustain + math.min(remaining / span, math.sqrt(2 * rate * remaining)))
		end
		local nSamples = if i0 and i1 then i1 - i0 + 1 else 1
		local function scored(gt: number): number
			local over = (math.abs(gt) - lim) * span
			return cost(gt) + (if over > 0 then Config.Range.PitchSoft * nSamples * over * over else 0)
		end
		local best, bestCost = gA, math.huge
		local n = 32
		for i = 0, n do
			local gt = -gMax + 2 * gMax * i / n
			local c = scored(gt)
			if c < bestCost then
				best, bestCost = gt, c
			end
		end
		local d = 2 * gMax / n
		local centre = best
		for i = -8, 8 do
			local gt = math.clamp(centre + d * i / 8, -gMax, gMax)
			local c = scored(gt)
			if c < bestCost then
				best, bestCost = gt, c
			end
		end
		-- the piece's knots: ease to the grade, then hold it (or as far as the piece allows)
		local L = math.abs(best - gA) / rate
		local gB
		if L > 1e-6 and L < span - 1e-6 then
			table.insert(out, a + L)
			table.insert(out, best)
			gB = best
		else
			gB = gA + sign(best - gA) * math.min(math.abs(best - gA), rate * span)
		end
		table.insert(out, b)
		table.insert(out, gB)
		if i0 and iB then
			for i = i0, iB do
				local e = yA + rampRise(us[i] - a, gA, gB, rate) - hs[i]
				worst = math.max(worst, math.abs(e))
				worstFill = math.max(worstFill, e)
				worstCut = math.max(worstCut, -e)
			end
		end
		yA += rampRise(span, gA, gB, rate)
		if budget then
			used = pitchSpend(used, gA, gB, span)
		end
		gA, a = gB, b
	end
	-- and how far off h the road ends: above it (+) or below it (-) (T-242)
	local endOff = 0
	for i = #us, 1, -1 do
		if us[i] <= len + 1e-6 then
			endOff = yA - gA * (len - us[i]) - hs[i]
			break
		end
	end
	return out, worst, worstFill, worstCut, endOff
end

-- The heading for a stretch or a planned turn, from the mountain's slope where the road is
-- (T-226, T-238). Returns the heading (a yaw), how far a bend may stray off it down the slope
-- and up it, and which way up is (1 left, -1 right; 0 for no side).
-- `stretch` (T-242): the heading is for the stretch the road is on now, not a turn's target:
-- a leg's way along its level line is then kept from one section to the next, and checked
-- against h itself.
function SplineGen._slopeAim(self: Gen, slope: Slope, stretch: boolean?): (number, number, number, number)
	local C = Config.Spline
	local G, M, R = C.Ground, C.Mountain, Config.Range
	local f = self.ground
	local r = f.range
	local x, z, _, _, _, _, y = self.spline:tip()
	-- CATCHING UP (T-228): a road above the mountain heads more across it, so the mountain
	-- comes back up to it; one below heads more down it. The road's own
	-- grade can't do it alone: it may fall 8 degrees at most, a scarp falls 30 and more
	local catch = (y - followH(f, x, z, G.FollowRadius)) * G.CatchUp
	-- the face's own slope where the road is (not ahead along the way it heads now: a
	-- turnaround's next leg goes the other way), over `AimSpan` of the range, with only
	-- `AimRelief` of the spurs' and gullies': the spurs are as big as a leg is long, and a leg
	-- read on them alone climbed a spur's flank and came down the face
	local e = R.AimSpan * 0.5
	local bx = (Ground.base(f, x + e, z) - Ground.base(f, x - e, z)) / R.AimSpan
	local bz = (Ground.base(f, x, z + e) - Ground.base(f, x, z - e)) / R.AimSpan
	local ax, az = gradient(f, x, z, G.AimSpan)
	local q = R.AimRelief
	local gx, gz = bx + q * (ax - bx), bz + q * (az - bz)
	local S = math.sqrt(gx * gx + gz * gz)
	-- THE WAY ON is the way to the pass ahead: down the slope where the road is coming down to
	-- a valley, UP it where it is climbing to the pass (`sc`, read where the road is now: a leg
	-- that crosses a valley floor turns from coming down to climbing there), and on flat ground
	-- toward the pass itself; "down" below means that way on, and a leg's grade is a climb when
	-- it is up
	-- along a descent's surveyed leg (T-326): a point `TraverseLook` studs on along it
	local leg = self.leg
	if slope.kind == "traverse" and leg then
		local t, v = Range.frame(r, x, z)
		local at, av = Traverse.ahead(leg, t, v, R.TraverseLook)
		local wx, wz = Range.world(r, at, av)
		local lim = math.rad(R.TraverseLimit)
		return math.atan2(x - wx, z - wz), lim, lim, 0
	end
	if slope.kind == "return" then
		-- back across the face after a descent's hairpin (T-326): along the crest the face
		-- falls from, `dirV` across the range (the frame its legs are surveyed in), turned
		-- down the fall line enough to fall `gd` a stud
		local d = slope.dirV or 1
		local tgt = self:_target()
		local t, v = Range.frame(r, x, z)
		local e = R.TraverseFrameSpan * 0.5
		local lean = (Range.ridgeT(r, tgt.k - 1, v + e) - Range.ridgeT(r, tgt.k - 1, v - e)) / (2 * e)
		local n = math.sqrt(1 + lean * lean)
		local ct, cv = d * lean / n, d / n
		local dt, dv = 1 / n, -lean / n
		-- how steeply the face falls down that line, over the range's own shape
		local h0 = Ground.base(f, Range.world(r, t - dt * e, v - dv * e))
		local h1 = Ground.base(f, Range.world(r, t + dt * e, v + dv * e))
		local S = math.max((h0 - h1) / (2 * e), 1e-6)
		local tilt = math.asin(math.clamp((slope.gd or 0) / S, 0, math.sin(math.rad(60))))
		local ht, hv = ct * math.cos(tilt) + dt * math.sin(tilt), cv * math.cos(tilt) + dv * math.sin(tilt)
		local hx, hz = ht * r.ux + hv * r.uz, ht * r.uz - hv * r.ux
		return math.atan2(-hx, -hz), math.rad(R.TraverseLimit), math.rad(R.TraverseLimit), 0
	end
	local tgt = self:_target()
	local corridor = self.corridor
	if stretch and corridor and corridor.ridge == tgt.k then
		local t, v = Range.frame(r, x, z)
		if t < corridor.endT - 400 then
			local at, av = ContourRoute.ahead(corridor, t, v, 430)
			local wx, wz = Range.world(r, at, av)
			return math.atan2(x - wx, z - wz), math.rad(40), math.rad(40), 0
		end
	end
	local sc = if Ground.where(f, x, z).ridge == tgt.k then -1 else 1
	local wx, wz = tgt.x - x, tgt.z - z
	local wl = math.max(math.sqrt(wx * wx + wz * wz), 1e-6)
	local dx, dz = -sc * gx + wx / wl * R.TowardBias, -sc * gz + wz / wl * R.TowardBias
	catch *= sc
	if slope.kind == "pass" then
		-- straight for the pass: up to it as steeply as the road may climb; past that, the
		-- legs take over (`_planRange`)
		local aim = math.atan2(-wx, -wz)
		return aim, 0, 0, 0
	end
	-- a leg
	local dl = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
	dx, dz = dx / dl, dz / dl
	local cy = self.fall + slope.side * math.pi * 0.5
	local cx, cz = -dz, dx
	if cx * -math.sin(cy) + cz * -math.cos(cy) < 0 then
		cx, cz = dz, -dx
	end
	-- the furthest off across the road can head and still keep its grade followable
	local gFollow = math.tan(math.rad(C.CruiseGrade)) * G.FollowGrade
	local steepest = if S > gFollow then math.asin(gFollow / S) else math.pi * 0.5
	-- the tilt down the slope off straight across that makes the mountain fall `gd` a stud
	-- along the road (negative: up it)
	local function tilt(gd: number): number
		if S <= 1e-9 then
			return if gd >= 0 then math.pi * 0.5 else -math.pi * 0.5
		end
		return math.asin(math.clamp(gd / S, -1, 1))
	end
	-- On a steep hillside, take a longer traverse to gain the same altitude.
	local gd = (slope.gd or 0) / (1 + G.LegGradeEase * S)
	-- (never up the slope: toward the leg above, it boxed the road in after a hairpin)
	local t = math.clamp(tilt(gd - catch), 0, math.rad(G.LegTiltMax))
	local hx, hz = cx * math.cos(t) + dx * math.sin(t), cz * math.cos(t) + dz * math.sin(t)
	-- every leg makes headway along the way on, at least `LegOnward` degrees of it (T-238):
	-- near a pass the slope runs sideways toward the peaks either side, and a leg across it
	-- there doubled back down below the one before and boxed the road in
	local on = hx * r.ux + hz * r.uz
	local least = math.sin(math.rad(R.LegOnward))
	-- WHERE THE SLOPE'S LEVEL LINE CURLS BACK (a bowl under a pass, the flank of a peak),
	-- the leg follows it the other way, forward, before forcing a heading up the slope.
	-- For the stretch the road is on (T-242) the leg goes over to the other way only when
	-- the way it is going heads back by `LegOnward` and the other on by as much, and stays
	-- there: until T-242 it took whichever way headed on further, section by section, and
	-- where the level line ran square to the way on that flickered, the heading jumping
	-- 100 to 180 degrees, no bend could follow it, and the road ran on straight, back the
	-- way it came and into the face (a jump in a quarter of the legs' sections)
	local ox, oz = -cx * math.cos(t) + dx * math.sin(t), -cz * math.cos(t) + dz * math.sin(t)
	local oon = ox * r.ux + oz * r.uz
	local swap
	if stretch then
		local sw = slope.swapped == true
		local mine, other = if sw then oon else on, if sw then on else oon
		if mine < -least and other > least then
			sw = not sw
		end
		slope.swapped = sw
		swap = sw
	else
		swap = on < least and oon > on
	end
	if swap then
		hx, hz, on = ox, oz, oon
	end
	if on < least then
		local px, pz = hx - on * r.ux, hz - on * r.uz
		local pl = math.max(math.sqrt(px * px + pz * pz), 1e-9)
		local c = math.cos(math.rad(R.LegOnward))
		hx, hz = r.ux * least + px / pl * c, r.uz * least + pz / pl * c
	end
	local aim = math.atan2(-hx, -hz)
	if stretch then
		-- CHECKED AGAINST h ITSELF (T-242): the heading above reads the face smoothed, with a
		-- third of its spurs, and where a spur's flank is steep that heading ran the road into
		-- it. Every heading `AimLocalStep` degrees apart within `AimLocalSwing` of it is tried
		-- on h, half and all of `AimLocalAhead` studs on: how far the road would still be off
		-- h there, climbing or falling as steeply as it may, plus `AimLocalTurnCost` studs a
		-- degree off the heading and `AimLocalBackCost` for heading straight back the way on
		local L = R.AimLocalAhead
		local best, bestCost = aim, math.huge
		local n = math.floor(R.AimLocalSwing / R.AimLocalStep + 0.5)
		for i = -n, n do
			local a = aim + math.rad(i * R.AimLocalStep)
			local ex, ez = -math.sin(a), -math.cos(a)
			local miss = 0
			for _, k in { 0.5, 1 } do
				local need = (followH(f, x + ex * L * k, z + ez * L * k, G.FollowRadius) - y) / (L * k)
				miss += math.max(0, math.abs(need) - gFollow) * L * k
			end
			local back = math.max(0, -(ex * r.ux + ez * r.uz))
			local cost = miss + R.AimLocalTurnCost * math.abs(i * R.AimLocalStep) + R.AimLocalBackCost * back
			if cost < bestCost then
				best, bestCost = a, cost
			end
		end
		aim = wrap(best)
	end
	local minLimit = math.rad(G.AimMinLimit)
	local down = math.clamp(steepest - t, minLimit, math.rad(M.LegHeadingLimit))
	local up = math.clamp(steepest + t, minLimit, math.rad(M.LegUphillLimit))
	-- the side the leg before is on: back from the way on (below, climbing)
	local upSign = if -dx * -math.cos(aim) + -dz * math.sin(aim) > 0 then 1 else -1
	return aim, down, up, upSign
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
function SplineGen._clear(self: Gen, knots: { number }, limitSetback: boolean?): boolean
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
	local high = 0
	local range = self.ground.range
	-- (along a descent's leg, T-326, the setback is measured across the range, the way the
	-- leg makes headway: the leg itself may turn up toward a gorge's head. Its hairpin turns
	-- through the downhill side, on along the range, as every turn did)
	local ux, uz = range.ux, range.uz
	if self.headway and not self.turning then
		ux, uz = self.headway[1], self.headway[2]
	elseif self.setback then
		ux, uz = self.setback[1], self.setback[2]
	end
	return walk(x0, z0, yaw0, k0, knots, cs, first, function(u, x, z)
		local s = s0 + u
		if limitSetback then
			local on = (x - x0) * ux + (z - z0) * uz
			high = math.max(high, on)
			if high - on > Config.Range.ContourSetback then return false end
		end
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

-- Check the same exit the terrain survey sees. A turn may briefly wind back around
-- its apex. Its exit must lead onto fresh hillside, away from earlier switchbacks.
function SplineGen._exitClear(self: Gen, knots: { number }, kt: number): boolean
	local exit = withEscape(knots, kt)
	local _, _, yaw, k0 = self.spline:tip()
	local heading = yawAfter(yaw, k0, exit)
	local range = self.ground.range
	-- (along a descent's leg, T-326, headway is across the range: the leg may turn up toward a
	-- gorge's head, back toward the mountain, to cross where it is shallow)
	local wx, wz = range.ux, range.uz
	if self.headway then
		wx, wz = self.headway[1], self.headway[2]
	end
	if -math.sin(heading) * wx - math.cos(heading) * wz < -math.sin(math.rad(Config.Range.LegOnward)) then
		return false
	end
	-- (a descent's hairpin needs less straight road clear past it: the next leg is surveyed
	-- clear of old road from its exit, T-326)
	exit[#exit - 1] = exit[#exit - 3] + (if self.turning and self.setback then Config.Range.TraverseExit else Config.Range.ContourExit)
	return self:_clear(exit, true)
end

-- Survey a bend and its exit while there is still room to turn. Simulate a vertical
-- curve on the natural ground. A short steep patch fits within the pitch allowance;
-- a long ascent at that pitch still incurs a cost, as does a cut on BOTH shoulders.
local function contourCost(self: Gen, knots: { number }, best: number?, bearing: (({ number }, number, number) -> number)?): (number, number, number)
	local C, R = Config.Spline, Config.Range
	local f = self.ground
	local x, z, yaw, k0, grade, _, y = self.spline:tip()
	local step = R.ContourSample
	local peakGrade = math.tan(math.rad(C.MaxGrade))
	local cruise = math.tan(math.rad(R.ContourGrade))
	local shoulder = Config.Road.Width * 0.5 + 12
	local path = withEscape(knots, knots[#knots])
	path[#path - 1] = path[#path - 3] + R.ContourLook
	local positions = table.create(2 * math.floor(path[#path - 1] / step))
	local endX, endZ = x, z
	walk(x, z, yaw, k0, path, step, step, function(u, px, pz)
		if u <= knots[#knots - 1] + step * 0.5 then endX, endZ = px, pz end
		table.insert(positions, px)
		table.insert(positions, pz)
		return true
	end, true)
	local direction = if bearing then bearing(knots, endX, endZ) else 0
	local limit = (best or math.huge) - direction
	if limit <= 0 then return math.huge, endX, endZ end
	local previous = Ground.h(f, x, z)
	local climb, descent, worst, sum = 0, 0, 0, 0
	local lastBanks, bankCost = 0, 0
	local usedClimb, usedDescent = self.excessClimb, self.excessDescent
	local n = math.max(1, #positions / 2)
	for i = 1, #positions, 2 do
		local u = (i + 1) * 0.5 * step
		local px, pz = positions[i], positions[i + 1]
		local terrain = Ground.h(f, px, pz)
		local lo = -pitchLimit(usedDescent, step, cruise, peakGrade)
		local hi = pitchLimit(usedClimb, step, cruise, peakGrade)
		local want = math.clamp(2 * (terrain - y) / step - grade, lo, hi)
		local nextGrade = grade + math.clamp(want - grade, -C.MaxGradeRate * step, C.MaxGradeRate * step)
		local roadRise = 0.5 * (grade + nextGrade) * step
		usedClimb = math.max(0, usedClimb + roadRise - cruise * step)
		usedDescent = math.max(0, usedDescent - roadRise - cruise * step)
		y += roadRise
		grade = nextGrade
		local rise = terrain - previous
		previous = terrain
		climb = math.max(0, climb + rise - step * cruise)
		descent = math.max(0, descent - rise - step * cruise)
		local heading = yawAlong(yaw, k0, path, u)
		if ((i - 1) / 2 + 1) % 5 == 0 then
			local banks = Gorge.along(f, px, pz, -math.sin(heading), -math.cos(heading), terrain)
			-- A brief cross-cut can be clear again on its far bank. A curve aimed
			-- into the bed meets walls on consecutive soundings along its exit.
			bankCost += R.GorgeLocalCost * (0.25 * banks + math.min(lastBanks, banks)) * (200 / path[#path - 1])
			lastBanks = banks
		end
		local dx, dz = shoulder * math.cos(heading), -shoulder * math.sin(heading)
		local both = math.min(Ground.h(f, px - dx, pz - dz), Ground.h(f, px + dx, pz + dz)) - y
		local excavation = math.max(math.abs(terrain - y), both - 12)
		local cost = excavation + 0.8 * math.max(0, math.max(climb, descent) - 16)
		-- A bend farther ahead can still steer away. Give its warning enough weight
		-- to turn before the approach, while protecting the road being laid now.
		local weight = 1 - 0.45 * math.clamp((u - knots[#knots - 1]) / R.ContourLook, 0, 1)
		worst = math.max(worst, weight * cost)
		sum += weight * cost
		if bankCost + worst + 0.3 * sum / n >= limit then return math.huge, endX, endZ end
	end
	return direction + bankCost + worst + 0.3 * sum / n, endX, endZ
end

-- Compare actual drivable curves at the current tip. Each has to clear the old road
-- with room for its escape, including the far leg of a switchback.
function SplineGen._contour(self: Gen, original: Spline.Section): Spline.Section
	local C, R = Config.Spline, Config.Range
	local originalCost, originalX, originalZ = contourCost(self, original.k)
	local x, z, yaw, k0, g0, b0, y0 = self.spline:tip()
	local range = self.ground.range
	local t, v = Range.frame(range, x, z)
	local target = self:_target()
	local corridor = self.corridor
	local _, _, _, face = Range.at(range, t, v)
	if corridor and (corridor.ridge ~= target.k or t >= corridor.endT - 400 or corridor.fromFace ~= face) then
		corridor = nil
		self.corridor = nil
	end
	-- (along a descent's leg, T-326, the leg is the route: no corridor)
	local leg = if self.headway then self.leg else nil
	if leg then
		corridor = nil
	end
	local gorge = 0
	if not corridor and not leg then
		local fx, fz = -math.sin(yaw), -math.cos(yaw)
		for _, ahead in { 350, 850, 1350 } do
			local px, pz = x + fx * ahead, z + fz * ahead
			gorge = math.max(gorge, Gorge.along(self.ground, px, pz, fx, fz, Ground.h(self.ground, px, pz)))
		end
	end
	if not corridor and not leg and (gorge > 3 or originalCost > 2 * R.ContourTrigger) then
		corridor = ContourRoute.new(self.ground, x, z, yaw, target)
		self.corridor = corridor
	end
	local function headingCost(knots: { number }, endX: number, endZ: number): number
		local endYaw = yawAfter(yaw, k0, knots)
		local onward = -math.sin(endYaw) * range.ux - math.cos(endYaw) * range.uz
		if leg then
			local et, ev = Range.frame(range, endX, endZ)
			local at, av, miss = Traverse.ahead(leg, et, ev, R.TraverseLook)
			local wx, wz = Range.world(range, at, av)
			local aim = math.atan2(endX - wx, endZ - wz)
			return 0.48 * miss + 0.55 * math.deg(math.abs(wrap(endYaw - aim)))
		end
		if corridor then
			local et, ev = Range.frame(range, endX, endZ)
			local at, av, miss = ContourRoute.ahead(corridor, et, ev, 350)
			local wx, wz = Range.world(range, at, av)
			local aim = math.atan2(endX - wx, endZ - wz)
			return 0.48 * miss + 0.55 * math.deg(math.abs(wrap(endYaw - aim)))
		end
		return 50 * math.max(0, -onward) + 0.09 * math.deg(math.abs(wrap(endYaw - self.aim)))
	end
	local bestScore = originalCost + headingCost(original.k, originalX, originalZ)
	if bestScore <= R.ContourTrigger then return original end
	bestScore -= R.ContourGain
	local best: { number }?, bestK, bestRadius = nil, 0, nil
	local function try(knots: { number }?, kt: number, radius: number?)
		if not knots then return end
		local score = contourCost(self, knots, bestScore, headingCost)
		if score < bestScore and self:_exitClear(knots, kt) then
			best, bestK, bestRadius, bestScore = knots, kt, radius, score
		end
	end
	try((curvatureKnots(k0, 0, nil, R.FollowStraight)), 0, nil)
	for _, degrees in R.ContourTurns do
		for _, radius in R.ContourRadii do
			for dir = -1, 1, 2 do
				local kt = dir / radius
				try((curvatureKnots(k0, kt, dir * math.rad(degrees), nil)), kt, radius)
			end
		end
	end
	if not best then return original end
	local kn = best :: { number }
	local len = kn[#kn - 1]
	self.stats.traverses += 1
	return {
		k = kn, len = len, g = (self:_followGrade(kn, g0, y0)),
		b = pickBank(bestK, bestRadius, b0, math.min(transition(k0, bestK), len), len, false),
		tag = if not bestRadius then "Straight" elseif bestRadius < 95 then "Hairpin" elseif bestRadius <= 340 then "Medium" else "Sweeper",
	}
end

-- One random candidate: a bend or a straight, its curvature knots, and whether its
-- heading (with its escape) stays inside the limit.
function SplineGen._candidate(self: Gen): (Spline.Section?, string?, number?, number?)
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
			-- lean back toward the stretch's heading the further it has strayed
			local pLeft = 0.5 - 0.45 * math.clamp(rel / limit, -1, 1)
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
	if not self:_exitClear(knots, kt) then
		return nil, "crowded"
	end
	local T = transition(k0, kt)
	local flat = rng:NextNumber() < C.UnbankedChance
	-- the grade follows the mountain (T-226), and how far off it the road still ends up goes
	-- back with the candidate, so one that follows it can be preferred (and how far off it
	-- the road ends, T-242)
	local g, off, _, _, endOff = self:_followGrade(knots, g0, y0)
	return {
		len = len,
		k = knots,
		g = g,
		b = pickBank(kt, radius, b0, math.min(T, len), len, flat),
		tag = tag,
	},
		nil,
		off,
		endOff
end

--------------------------------------------------------------------------------
-- The range: the road crosses its passes (T-238, features/mountain-range.md)
--------------------------------------------------------------------------------

-- The pass the road is heading for: on the ridge ahead of its end, the one `Ground.passAhead`
-- picks the first time the road is in front of that ridge, and kept until it has crossed it.
function SplineGen._target(self: Gen): { x: number, z: number, y: number, k: number }
	local f = self.ground :: Ground.Field
	local r = f.range :: Range.Range
	local x, z = self.spline:tip()
	local k = Range.ridgeAhead(r, x, z)
	local tgt = self.target
	if not tgt or tgt.k ~= k then
		local px, pz, py, pk = Ground.passAhead(f, x, z)
		tgt = { x = px :: number, z = pz :: number, y = py :: number, k = pk :: number }
		self.target = tgt
	end
	return tgt :: any
end

-- Plan the way to the pass ahead, a stretch and a turn at a time:
--   * CLIMBING (the road is on the face of the ridge the pass is on): if the pass is near
--     enough to climb to straight, at `DirectGrade` or less, head for it ("pass"); otherwise
--     a leg across the face, climbing, toward the pass's side, until it is `PassBand / 2`
--     past it across, then a turnaround onto the next leg the other way: switchbacks stacked
--     below the pass, as real passes have.
--   * COMING DOWN (the road is on the far face of the ridge behind, or on a valley floor):
--     legs coming down the same way, toward the next pass across.
-- A turnaround on a climb turns through the uphill side, and on a descent the downhill side.
-- Hairpins on steep ground are as tight as the road allows (`SteepHairpinRadius`), so it
-- spends as little as it can heading straight down or up the face (DECISIONS.md
-- 2026-11-15: hairpins hug the steep face).
function SplineGen._planRange(self: Gen)
	local M, G, R = Config.Spline.Mountain, Config.Spline.Ground, Config.Range
	local f = self.ground :: Ground.Field
	local r = f.range :: Range.Range
	local rng = self.prng
	local function between(range: { number }): number
		return range[1] + (range[2] - range[1]) * rng:NextNumber()
	end
	local plan = self.plan
	local x, z, _, _, _, _, y = self.spline:tip()
	local tgt = self:_target()
	local t, v = Range.frame(r, x, z)
	local pt, pv = Range.frame(r, tgt.x, tgt.z)
	local where = Ground.where(f, x, z)
	-- (past the valley floor, on the target ridge's own face: from the floor on, it is a climb)
	local climbing = where.ridge == tgt.k
	local sc = if climbing then -1 else 1
	self.stats.legs += 1
	local function stretch(len: number, what: string, sl: Slope, untilV: number?)
		table.insert(plan, { turn = false, what = what, aim = self.aim, limit = math.rad(M.LegHeadingLimit), left = len, slope = sl, untilV = untilV })
	end
	-- (a turnaround turns the short way round onto the next leg: legs tilt toward the way on,
	-- so that is through the uphill side on a climb and the downhill side coming down)
	local function turn(what: string, dir: number, radius: { number }, tag: string, sl: Slope)
		table.insert(plan, { turn = true, what = what, to = self.aim, dir = dir, radius = radius, tag = tag, window = self.aim, slope = sl, autoDir = true })
	end
	-- straight for the pass, when it is in reach
	local dist = math.sqrt((pt - t) ^ 2 + (pv - v) ^ 2)
	if climbing and dist <= R.DirectReach and tgt.y - y <= dist * R.DirectGrade then
		stretch(dist + R.PassOver, "pass", { kind = "pass", side = self.legSide })
		return
	end
	-- which way across: toward the pass, or once within the band, the way the last leg did not go
	local function across(side: number): number
		-- how far a leg running `side` straight across the slope goes across the range (v) a stud
		local yaw = wrap(self.fall + side * (math.pi * 0.5))
		local _, dv = Range.frame(r, x - math.sin(yaw), z - math.cos(yaw))
		return dv - v
	end
	-- COMING DOWN (T-326): a leg surveyed across the face, ending in a hairpin where the
	-- hillside offers one; after that hairpin, the next leg the other way, down to the valley
	-- floor and across it. (A road that starts on a valley floor has come down nothing: its
	-- legs below head for the pass, as before.)
	if climbing then
		self.descending = false
	elseif where.kind ~= "valley" then
		self.descending = true
	end
	if self.descending then
		local _, _, yaw = self.spline:tip()
		local dirV = self.nextDirV
		self.nextDirV = nil
		-- (old road, bar the last few hundred studs the leg starts from, is out of bounds)
		local sp, s0 = self.spline, self.spline.length
		local clear = self.clearance + R.TraverseClear
		local function blocked(px: number, pz: number): boolean
			return sp:crowded(px, pz, s0, clear, R.TraverseFromTip) ~= nil
		end
		local leg = Traverse.plan(f, x, z, y, yaw, dirV, tgt, blocked)
		if leg then
			self.leg = leg
			local legSide = if across(1) * leg.dirV > 0 then 1 else -1
			local legSlope: Slope = { kind = "traverse", side = legSide }
			stretch(leg.length * 1.5, "traverse", legSlope)
			if leg.hairpin then
				local nextLeg: Slope = { kind = "return", side = -legSide, gd = math.tan(math.rad(R.TraverseGrade)), dirV = -leg.dirV }
				turn("turnaround", legSide, leg.radius, "Hairpin", nextLeg)
				plan[#plan].nextDirV = -leg.dirV
				plan[#plan].traverse = true
				-- ON STEEPER GROUND, A TIGHT ONE (T-337): the leg is left its lead and side by side
				-- run short of its end, so the shape's turn lands where the survey put the hairpin
				local TH = Config.TightHairpin
				if leg.siteSlope >= math.tan(math.rad(TH.DescentFace)) and s0 + leg.length - self.tightLast >= TH.Gap then
					plan[#plan].tightWanted = true
					plan[#plan].legSlope = legSlope
					plan[#plan - 1].arrive = R.TraverseArrive + self:_tightReach()
				end
				self.legSide = -legSide
			else
				self.legSide = legSide
			end
			-- the leg's weave (T-337), gone short of where its stretch ends
			do
				local w = self.wrng
				local amp = R.TraverseWeave[1] + (R.TraverseWeave[2] - R.TraverseWeave[1]) * w:NextNumber()
				local legItem = if leg.hairpin then plan[#plan - 1] else plan[#plan]
				local arrive = legItem.arrive or R.TraverseArrive
				self.weave = { amp = amp, side = if w:NextNumber() < 0.5 then -1 else 1, upTo = leg.length - arrive - R.TraverseWeaveOut }
			end
			return
		end
	end
	local side = self.legSide
	local half = R.PassBand * 0.5
	if math.abs(pv - v) > half then
		side = if across(1) * (pv - v) > 0 then 1 else -1
	end
	local dirV = if across(side) > 0 then 1 else -1
	local untilV = pv + dirV * half
	local len = math.clamp(math.abs(untilV - v) * 1.15, R.LegMin, R.LegMax)
	local gd = between(G.LegGrade)
	stretch(len, "leg", { kind = "leg", side = side, gd = gd }, untilV)
	plan[#plan].untilDir = dirV
	-- the turnaround, onto the next leg the other way: up through the uphill side on a climb
	local steep = where.slope >= Config.Spline.Ground.SlopeSteep
	local radius = if steep then R.SteepHairpinRadius else M.HairpinRadius
	local nextLeg: Slope = { kind = "leg", side = -side, gd = between(G.LegGrade) }
	turn("turnaround", sc * side, radius, "Hairpin", nextLeg)
	plan[#plan].climb = climbing
	self.legSide = -side
end

-- The way out when the road is about to box itself in on the range (T-238): every bend from
-- `RescueTurns` either way, on each of `RescueRadii`, the first (least turn, the end heading
-- most along the way on) that is clear with its escape. nil when none is.
function SplineGen._rescue(self: Gen): Spline.Section?
	local C, R = Config.Spline, Config.Range
	local f = self.ground :: Ground.Field
	local r = f.range :: Range.Range
	local _, _, yaw0, k0, g0, b0, y0 = self.spline:tip()
	local best: { number }?, bestKt, bestScore = nil, 0, -math.huge
	for _, deg in R.RescueTurns do
		for _, dir in { 1, -1 } do
			for _, radius in R.RescueRadii do
				local kt = dir / math.max(radius, C.MinRadius)
				local knots = curvatureKnots(k0, kt, dir * math.rad(deg), nil)
				if knots and self:_exitClear(knots, kt) then
					local yaw = yawAfter(yaw0, k0, knots) + 0.5 * kt * transition(kt, 0)
					local on = -math.sin(yaw) * r.ux - math.cos(yaw) * r.uz
					local score = on - deg / 360
					if score > bestScore then
						best, bestKt, bestScore = knots, kt, score
					end
					break
				end
			end
		end
	end
	if not best then
		return nil
	end
	local knots = best :: { number }
	local len = knots[#knots - 1]
	self.stats.escapes += 1
	return {
		len = len,
		k = knots,
		g = (self:_followGrade(knots, g0, y0)),
		b = pickBank(bestKt, 1 / math.abs(bestKt), b0, math.min(transition(k0, bestKt), len), len, false),
		tag = "Medium",
	}
end

-- THE MOUNTAIN FIRST (T-242): on the range, when no random section keeps the road within
-- `FollowMaxOff` of h, the one that best brings it back: a straight of `FollowStraight` studs,
-- every bend of `FollowTurns` either way on each of `FollowRadii`, and the random one that
-- came nearest (`nearest`: `nearOff` the furthest it strays, `nearEnd` how far off h it ends).
-- Each is judged on where it leads, running on straight `FollowLook` studs past it: how far
-- off h the road is there, half the furthest it strays on the way, `FollowAimCost` studs a
-- degree it ends past its aim's limit, and `FollowBackCost` for heading straight back the way
-- on (in proportion). Until T-242 the random one nearest h was laid, however far it strayed,
-- and when none was within its heading's limit an escape ran straight on: 1 000 studs and
-- more, back the way the road came and 100 to 290 studs into the face.
function SplineGen._follow(self: Gen, nearest: Spline.Section?, nearOff: number?, nearEnd: number?): Spline.Section?
	local C, R = Config.Spline, Config.Range
	local f = self.ground :: Ground.Field
	local r = f.range :: Range.Range
	local _, _, yaw0, k0, g0, b0, y0 = self.spline:tip()
	-- (along a descent's leg, T-326: headway is across the range, and every degree off the
	-- leg counts, so the road keeps to the leg rather than running down a spur's crest)
	local hw = self.headway
	local wx, wz = if hw then hw[1] else r.ux, if hw then hw[2] else r.uz
	local function headingCost(yaw: number): number
		local on = -math.sin(yaw) * wx - math.cos(yaw) * wz
		local off = math.deg(math.abs(wrap(yaw - self.aim)))
		local past = off - math.deg(self.limit)
		return R.FollowAimCost * math.max(0, past) + R.FollowBackCost * math.max(0, -on) + (if hw then R.TraverseFollowCost * off else 0)
	end
	-- how far off h the road is `FollowLook` on past a section with these knots (ending on
	-- curvature `kt`), and the furthest it strays on the way
	local function lead(knots: { number }, kt: number): (number, number)
		local ext = withEscape(knots, kt)
		ext[#ext - 1] = ext[#ext - 3] + R.FollowLook
		local _, worst, _, _, endOff = self:_followGrade(ext, g0, y0)
		return endOff, worst
	end
	local best: Spline.Section?, bestScore = nil, math.huge
	if nearest and nearOff and nearEnd then
		local kn = nearest.k
		local kt = kn[#kn]
		local e, w = lead(kn, kt)
		best = nearest
		bestScore = headingCost(yawAfter(yaw0, k0, kn) + 0.5 * kt * transition(kt, 0)) + math.abs(e) + 0.5 * math.max(w, nearOff)
	end
	local function try(knots: { number }?, kt: number, radius: number?)
		if not knots then
			return
		end
		local cost = headingCost(yawAfter(yaw0, k0, knots) + 0.5 * kt * transition(kt, 0))
		if cost >= bestScore then
			return
		end
		-- one fit for the section and the way on past it: the section's grade is its start
		local len = knots[#knots - 1]
		local ext = withEscape(knots, kt)
		ext[#ext - 1] = ext[#ext - 3] + R.FollowLook
		local gx, worst, _, _, e = self:_followGrade(ext, g0, y0)
		cost += math.abs(e) + 0.5 * worst
		if cost >= bestScore or not self:_exitClear(knots, kt) then
			return
		end
		-- (the grade's knots up to `len`, the last one cut there)
		local g: { number } = {}
		local s, v = 0, g0
		for j = 1, #gx, 2 do
			local s1, v1 = gx[j], gx[j + 1]
			if s1 >= len - 1e-6 then
				table.insert(g, len)
				table.insert(g, if s1 - s > 1e-9 then v + (v1 - v) * (len - s) / (s1 - s) else v1)
				break
			end
			table.insert(g, s1)
			table.insert(g, v1)
			s, v = s1, v1
		end
		if #g == 0 or g[#g - 1] < len - 1e-6 then
			table.insert(g, len)
			table.insert(g, v)
		end
		best = {
			len = len,
			k = knots,
			g = g,
			b = pickBank(kt, radius, b0, math.min(transition(k0, kt), len), len, false),
			tag = if radius then "Medium" else "Straight",
		}
		bestScore = cost
	end
	try((curvatureKnots(k0, 0, nil, R.FollowStraight)), 0, nil)
	for _, deg in R.FollowTurns do
		for _, dir in { 1, -1 } do
			for _, radius in R.FollowRadii do
				local kt = dir / math.max(radius, C.MinRadius)
				try((curvatureKnots(k0, kt, dir * math.rad(deg), nil)), kt, radius)
			end
		end
	end
	if best and best ~= nearest then
		self.stats.follows += 1
	end
	return best
end

-- How much of its weave a leg's road has at `along` studs of the leg (T-337): grown in from
-- the leg's start and gone by `upTo`, 0 to 1. 0 with no weave.
function SplineGen._weaveAt(self: Gen, along: number): number
	local w = self.weave
	if not w then
		return 0
	end
	local R = Config.Range
	local function ease(x: number): number
		local t = math.clamp(x / R.TraverseWeaveIn, 0, 1)
		return t * t * (3 - 2 * t)
	end
	return ease(along) * ease(w.upTo - along)
end

-- ALONG A DESCENT'S LEG (T-326): the leg was surveyed against the hillside already, so the
-- road keeps to it. Every curvature of `TrackRadii` either way (and straight), eased into and
-- held for each of `TrackHolds`, is judged where it ends: how far off the leg, how far its
-- heading is from a point `TraverseLook` on along the leg, and how sharply it still turns.
-- The best that is clear of old road with room for its escape is laid; nil when none is.
function SplineGen._track(self: Gen): Spline.Section?
	local C, R = Config.Spline, Config.Range
	local leg = self.leg :: Traverse.Leg
	local r = self.ground.range
	local x0, z0, yaw0, k0, g0, b0, y0 = self.spline:tip()
	local options = {}
	-- THE WEAVE (T-337): the road holds a heading `TraverseWeaveLean` off the leg, toward one
	-- side of the face, until it is the weave's width off the leg that way, then turns to lean
	-- the other way: S-bends either side of the surveyed line. The width is held in on steep
	-- ground, where the swing would leave the road further than `TraverseWeaveOff` off the
	-- hillside (the face's fall over it), and both lean and width grow in and fade out along
	-- the leg. Not weaving, the road keeps to the leg as before.
	local target: number? = nil -- the heading the road leans to, while it weaves
	local width = 0
	if self.weave then
		local w = self.weave
		local tt, tv = Range.frame(r, x0, z0)
		local nt, nv, _, along = Traverse.ahead(leg, tt, tv, 0)
		local fade = self:_weaveAt(along)
		if fade > 0 then
			local fall = math.tan(math.rad(Ground.where(self.ground, x0, z0).slope))
			width = w.amp * fade * math.min(1, R.TraverseWeaveOff / math.max(w.amp * fall, 1e-6))
			if (tt - nt) * w.side > width then
				w.side = -w.side
			end
			-- (the leg's own way on here, in the range's frame, and square to it toward +t)
			local at, av = Traverse.ahead(leg, tt, tv, 60)
			local lt, lv = at - nt, av - nv
			local ll = math.max(math.sqrt(lt * lt + lv * lv), 1e-6)
			lt, lv = lt / ll, lv / ll
			local pt, pv = lv, -lt
			if pt < 0 then
				pt, pv = -pt, -pv
			end
			local a = math.rad(R.TraverseWeaveLean) * fade
			local dt, dv = math.cos(a) * lt + math.sin(a) * w.side * pt, math.cos(a) * lv + math.sin(a) * w.side * pv
			local wx, wz = Range.world(r, tt + dt * 100, tv + dv * 100)
			target = math.atan2(x0 - wx, z0 - wz)
		end
	end
	local function consider(kt: number, hold: number, radius: number?)
		local knots = curvatureKnots(k0, kt, nil, hold)
		if not knots then
			return
		end
		local ex, ez = x0, z0
		walk(x0, z0, yaw0, k0, knots, knots[#knots - 1], knots[#knots - 1], function(_, px, pz)
			ex, ez = px, pz
			return true
		end, true)
		local ye = yawAfter(yaw0, k0, knots)
		local et, ev = Range.frame(r, ex, ez)
		local score
		if target then
			-- (weaving: how near the lean it ends, and never far past the weave's width off the leg)
			local nt = Traverse.ahead(leg, et, ev, 0)
			local err = math.deg(math.abs(wrap(ye - target)))
			score = R.TrackHeadingCost * err + R.TrackCurveCost * math.abs(kt) * 1000
			score += R.TrackStrayCost * math.max(0, math.abs(et - nt) - (width + R.TrackStrayTol))
		else
			local at, av, miss = Traverse.ahead(leg, et, ev, R.TraverseLook)
			local wx, wz = Range.world(r, at, av)
			local err = math.deg(math.abs(wrap(ye - math.atan2(ex - wx, ez - wz))))
			score = miss + R.TrackHeadingCost * err + R.TrackCurveCost * math.abs(kt) * 1000
		end
		-- (and, weaving, how far off the hillside the section leaves the road, past `TrackOffTol`,
		-- T-337: not otherwise, where it outweighed the leg and the road wandered off it)
		local g, off = self:_followGrade(knots, g0, y0)
		if target then
			score += R.TrackOffCost * math.max(0, off - R.TrackOffTol)
		end
		table.insert(options, { score = score, knots = knots, kt = kt, radius = radius, g = g })
	end
	for _, hold in R.TrackHolds do
		consider(0, hold, nil)
		for _, radius in R.TrackRadii do
			consider(1 / radius, hold, radius)
			consider(-1 / radius, hold, radius)
		end
	end
	table.sort(options, function(a, b)
		return a.score < b.score
	end)
	for _, o in options do
		if self:_exitClear(o.knots, o.kt) then
			local kn = o.knots
			local len = kn[#kn - 1]
			self.stats.tracked += 1
			return {
				k = kn,
				len = len,
				g = o.g,
				b = pickBank(o.kt, o.radius, b0, math.min(transition(k0, o.kt), len), len, false),
				tag = if not o.radius then "Straight" elseif o.radius < 95 then "Hairpin" elseif o.radius <= 340 then "Medium" else "Sweeper",
			}
		end
	end
	return nil
end

-- Detached tables prevent speculative append/terrain choices from touching live state.
local function copyTables(value: any): any
	if type(value) ~= "table" then return value end
	local out=table.clone(value)
	for k,v in value do if type(v)=="table" then out[k]=copyTables(v) end end
	return out
end

-- Plan samples are immutable before the candidate; overlay them instead of copying an
-- hour of road for each radius. Hash buckets are copied on first read, before append
-- can add to one. All other tracks/spans are small mutable tables and get their own copy.
local function forkSpline(source: Spline.Spline): Spline.Spline
	local out=table.clone(source)
	for k,v in source do
		if type(v)=="table" and k~="X" and k~="Z" and k~="hash" and k~="mountain" then out[k]=copyTables(v) end
	end
	out.X=setmetatable({}, {__index=source.X})
	out.Z=setmetatable({}, {__index=source.Z})
	out.hash=setmetatable({}, {__index=function(t,key)
		local old=source.hash[key]
		if old then local bucket=table.clone(old);rawset(t,key,bucket);return bucket end
		return nil
	end})
	return out
end
-- Decorate and append to a detached copy, using cloned scenery streams. The real
-- generator consumes these draws only after a turn has been selected. Global s, the
-- incoming curvature/grade/bank and edge hysteresis are all preserved.
function SplineGen._fitTurn(self: Gen, sec: Spline.Section, item: Item)
	local preview=table.clone(self)
	preview.spline=forkSpline(self.spline)
	preview.stats=table.clone(self.stats)
	preview.runoff=table.clone(self.runoff)
	preview.trng=self.trng:Clone(); preview.grng=self.grng:Clone()
	preview.xrng=self.xrng:Clone(); preview.crng=self.crng:Clone()
	preview.dress=nil -- the preview is the road only: nothing is dressed (T-327)
	local proposed=copyTables(sec)
	preview:_terrain(proposed)
	preview:_carve(proposed)
	preview.spline:append(proposed)
	return SplineTurnFit.measure(preview.spline,self.spline.length,preview.spline.length)
end

-- A TIGHT HAIRPIN (T-333, features/tight-hairpins.md) in place of a turnaround, now and then
-- (a descent's hairpin, or a climb's, which then climbs): the fixed shape `Road/TightHairpin` lays from the tip, its two legs side by side
-- with the island between them. Only where the face is steep enough to want one, far enough
-- from the last, near enough a half turn for its legs to run side by side, within
-- `MaxOff` of h, and clear of old road (its own legs are side by side on purpose: the shape
-- is checked against old road only, and its escape against everything). nil otherwise, and
-- the ordinary hairpin is laid as before.
-- How far a tight hairpin's turn starts past where its shape does (its lead and side by side
-- run, from a straight road), worked out once.
local tightReach: { [number]: number } = {}
function SplineGen._tightReach(self: Gen): number
	local r = tightReach[self.clearance]
	if not r then
		r = TightHairpin.build(0, 0, 0, 1, math.rad(30), 0, self.clearance).th[2] :: number
		tightReach[self.clearance] = r
	end
	return r
end

function SplineGen._tight(self: Gen, item: Item, needed: number): Spline.Section?
	local T = Config.TightHairpin
	local sp = self.spline
	local s0 = sp.length
	local function between(range: { number }): number
		return range[1] + (range[2] - range[1]) * self.hrng:NextNumber()
	end
	-- (a descent's leg planned to end in one, T-337, is held only to `Gap` from the last; the
	-- rest come now and then)
	if item.tightWanted then
		if s0 - self.tightLast < T.Gap then
			return nil
		end
	else
		if self.tightNext <= 0 then
			self.tightNext = between(T.First)
		end
		if s0 < self.tightNext then
			return nil
		end
	end
	-- (the next leg's heading: a half turn, or short of one by its tilt down the face)
	local short = math.pi - needed
	table.insert(self.stats.tightTurns, math.floor(math.deg(needed) + 0.5))
	local function refuse(why: string): nil
		self.stats.tightRefused += 1
		self.stats.tightWhy[why] = (self.stats.tightWhy[why] or 0) + 1
		return nil
	end
	if short < -math.rad(T.ShortOfHalf[1]) or short > math.rad(T.ShortOfHalf[2]) then
		return refuse("turn")
	end
	if item.climb and not T.OnClimbs then
		return refuse("climb")
	end
	local x0, z0, yaw0, k0, g0, b0, y0 = sp:tip()
	local face = Ground.where(self.ground, x0, z0).slope
	if face < T.MinFaceSlope then
		table.insert(self.stats.tightNotes, `gentle {math.floor(face)} deg`)
		return refuse("gentle")
	end
	-- (the grade it is built with is replaced below, from the mountain)
	local sec = TightHairpin.build(k0, g0, b0, item.dir :: number, short, g0, self.clearance)
	-- THE GRADE FOLLOWS THE MOUNTAIN except where the legs are side by side. There it is held at
	-- the face's own: the height between where the two legs run beside each other, over the road
	-- between them, within `Grade` (the island is the bank between their heights, so this keeps
	-- it a bank). Before that, along the lead, and after it, past the side by side run, it eases
	-- toward the hillside `FollowLook` studs ahead, as every section's grade does, at
	-- `MaxGradeRate` and never past `MaxGrade`; it starts easing into the held grade in time
	-- to be on it where the legs come side by side.
	do
		local SC = Config.Spline
		local sIn, sOut = sec.th[1], sec.th[4]
		local pts: { { number } } = {}
		walk(x0, z0, yaw0, k0, sec.k, 8, 8, function(u, x, z)
			table.insert(pts, { u, Ground.h(self.ground, x, z) })
			return true
		end)
		local function hAt(u: number): number
			local i = math.clamp(math.floor(u / 8), 1, #pts)
			return pts[i][2]
		end
		local face = (hAt(sOut) - hAt(sIn)) / math.max(sOut - sIn, 1)
		local gt = math.clamp(face, -T.Grade, T.Grade)
		local rate = SC.MaxGradeRate
		local step, look = 16, T.FollowLook
		local lim = math.tan(math.rad(SC.MaxGrade))
		local knots: { number } = {}
		local u, y, g = 0, y0, g0
		local function go(gn: number, du: number)
			y += (g + gn) * 0.5 * du
			u += du
			g = gn
			table.insert(knots, u)
			table.insert(knots, g)
		end
		local function follow(du: number)
			local want = math.clamp((hAt(math.min(u + look, sec.len)) - y) / look, -lim, lim)
			go(g + math.clamp(want - g, -rate * du, rate * du), du)
		end
		-- along the lead, until it is time to ease into the held grade
		while u + step + math.abs(gt - g) / rate < sIn do
			follow(step)
		end
		if sIn - u > 1e-6 then
			local L = sIn - u
			-- (as near the held grade as the road can get by the side by side run)
			gt = g + math.clamp(gt - g, -rate * L, rate * L)
			go(gt, L)
		end
		go(gt, sOut - u)
		while u < sec.len - 1e-6 do
			follow(math.min(step, sec.len - u))
		end
		sec.g = knots
	end
	-- the mountain: how far the shape leaves the road off h, either way
	local G = Config.Spline.Ground
	local gk = sec.g
	local function yAt(u: number): number
		local y, s, g = y0, 0, g0
		for j = 1, #gk, 2 do
			local s1, g1 = gk[j], gk[j + 1]
			if u <= s1 then
				local gu = g + (g1 - g) * (u - s) / math.max(s1 - s, 1e-9)
				return y + (g + gu) * 0.5 * (u - s)
			end
			y += (g + g1) * 0.5 * (s1 - s)
			s, g = s1, g1
		end
		return y + g * (u - s)
	end
	local worst, worstU = 0, 0
	walk(x0, z0, yaw0, k0, sec.k, 8, 8, function(u, x, z)
		local d = yAt(u) - Ground.h(self.ground, x, z)
		local off = math.abs(d)
		if off > worst then
			worst, worstU = off, u
		end
		return true
	end)
	-- (a descent's, as far as its ordinary hairpin may be, T-337: on steeper ground the face
	-- falls further between the legs than the road can round the turn)
	if worst > (if item.traverse then Config.Range.TraverseTurnMaxOff else T.MaxOff) then
		table.insert(self.stats.tightNotes, `off h {math.floor(worst)} at {math.floor(worstU)} of {math.floor(sec.len)} (turn {math.floor(sec.th[2])}-{math.floor(sec.th[3])})`)
		return refuse("off h")
	end
	-- old road, and the escape past the shape against everything
	local clear, sep = self.clearance, self.separation
	local c2 = clear * clear
	local cs = Config.Spline.CheckStep
	local first = cs * (math.floor(s0 / cs + 1e-9) + 1) - s0
	local knots = table.clone(sec.k)
	table.insert(knots, sec.len + Config.Spline.EscapeLength)
	table.insert(knots, 0)
	local own: { number } = {}
	-- (the shape's legs are close only to each other, by its lead: old road keeps the whole
	-- clearance from all of it, and the escape past it from everything)
	local ok = walk(x0, z0, yaw0, k0, knots, cs, first, function(u, x, z)
		local s = s0 + u
		local hit = sp:crowded(x, z, s, clear, sep)
		if hit then
			table.insert(self.stats.tightNotes, `crowded at {math.floor(u)} of {math.floor(sec.len)} by road {math.floor(s0 - hit)} back`)
			return false
		end
		if u > sec.len then
			for j = 1, #own, 3 do
				if s - own[j] > sep then
					local dx, dz = own[j + 1] - x, own[j + 2] - z
					if dx * dx + dz * dz < c2 then
						return false
					end
				end
			end
		end
		local n = #own
		own[n + 1], own[n + 2], own[n + 3] = s, x, z
		return true
	end)
	if not ok then
		return refuse("crowded")
	end
	self.stats.tightHairpins += 1
	self.tightNext = s0 + sec.len + between(T.Every)
	self.tightLast = s0 + sec.len
	return sec
end

-- A planned turn lands on its heading and keeps the crossing/escape safety checks.
-- Sharp turns sample the final candidate hillside. Try the clear radii, choose the best
-- fit, or run on and try again at a new location. Location retries are bounded: when no
-- shape fits there either, retain the least obstructed clear turn and report that limit.
function SplineGen._turn(self: Gen, item: Item): (Spline.Section | string)?
	local C, M = Config.Spline, Config.Spline.Mountain
	local sp = self.spline
	local _, _, yaw0, k0, g0, b0, y0 = sp:tip()
	local dir, to = item.dir :: number, item.to :: number
	local needed = (dir * (to-yaw0)) % (2*math.pi)
	if needed>2*math.pi-math.rad(20) then needed-=2*math.pi end
	if needed<math.rad(3) then return "done" end
	-- now and then a turnaround is a tight hairpin (T-333). One a descent's leg was planned to
	-- end in (T-337) is tried where its turn lands at the leg's end, its lead and side by side
	-- run short of it; refused there, the road runs on to the leg's end for the ordinary one
	if item.what == "turnaround" then
		local tight = self:_tight(item, needed)
		if tight then
			return tight
		end
		if item.tightWanted then
			item.tightWanted = false
			return "later"
		end
	end
	local range=item.radius :: {number}
	local fit = M.TurnChecks and needed>=math.rad(M.TurnCheckAngle)
	local totalTries = if fit then M.TurnFitTries else M.TurnTries
	local best: Spline.Section? = nil
	local reading: any = nil
	for try=1,totalTries do
		local lo=if try>totalTries//2 then math.min(C.MinRadius,range[1]) else range[1]
		local radius=lo*(range[2]/lo)^self.rng:NextNumber()
		local kt=dir/radius
		local esc=.5*math.abs(kt)*transition(kt,0)
		local knots,len=curvatureKnots(k0,kt,dir*(needed-esc),nil)
		self.stats.tries+=1
		if knots then
			local yawEnd=yawAfter(yaw0,k0,knots)+dir*esc
			if math.abs(wrap(yawEnd-to))<math.rad(3) then
				local emitted = if fit then withEscape(knots,kt) else knots
				local emittedLen = emitted[#emitted-1]
				if self:_exitClear(emitted,if fit then 0 else kt) then
					local T=transition(k0,kt)
					local flat=self.rng:NextNumber()<C.UnbankedChance
					local bank=pickBank(kt,radius,b0,math.min(T,len),len,flat)
					if fit then
						-- Make the safe continuation real road, so its effect on the hill is
						-- present during fitting and cannot change just after the turn arrives.
						local tail=ramp(bank[#bank],0,math.rad(C.MaxBankRate)/1.5,0,emittedLen-len)
						for j=1,#tail,2 do table.insert(bank,len+tail[j]);table.insert(bank,tail[j+1]) end
					end
					-- the grade follows the mountain (T-228), and how far off it the turn leaves the
					-- road counts in its fit, so a turn a steep face would leave stranded is laid
					-- further on, where it fits. A turnaround is fitted to sit in a cut rather than on
					-- fill, and judged so (T-238, hairpins hug the steep face)
					local hug = item.what == "turnaround"
					local g, off, worstFill, worstCut = self:_followGrade(emitted, g0, y0, if hug then C.Ground.TurnFill else nil)
					if hug then
						off = math.max(worstFill, worstCut * C.Ground.TurnMaxOff / C.Ground.TurnMaxCut)
					end
					local sec={len=emittedLen,k=emitted,g=g,b=bank,tag=item.tag}
					-- Avoid committing a turnaround whose run-out already heads into rock.
					-- (a hairpin ending a descent's leg, T-326, sits where the leg's survey put it,
					-- and the next leg is surveyed from its exit)
					if not item.traverse and contourCost(self, emitted) > Config.Range.ContourTrigger * 3 then
						self.stats.hillChecked += 1
						self.stats.hillRejected += 1
						continue
					end
					if not fit then return sec end
					local r=self:_fitTurn(sec,item)
					r.off=off
					if off>C.Ground.TurnMaxOff then r.ok=false end
					r.score+=off
					self.stats.hillChecked+=1
					if not r.ok then self.stats.hillRejected+=1 end
					if not reading or (r.ok and not reading.ok) or (r.ok==reading.ok and r.score<reading.score) then best,reading=sec,r end
				else
					self.stats.rejectedCrowded+=1
				end
			end
		end
	end
	if best and reading then
		-- (a descent's hairpin, T-326, sits where its leg's survey put it: past the site the
		-- road runs onto ground nobody chose, so the best clear one is laid there unless it
		-- leaves the road more than `TraverseTurnMaxOff` off h; that one is refused)
		if item.traverse then
			if not reading.ok and (reading.off or 0) > Config.Range.TraverseTurnMaxOff then
				item.hillRetries=(item.hillRetries or 0)+1
				return nil
			end
		elseif not reading.ok and (item.hillRetries or 0)<C.Ground.TurnRetries then
			item.hillRetries=(item.hillRetries or 0)+1
			return nil
		end
		table.insert(self.turnFits,{s0=sp.length,s1=sp.length+best.len,what=item.what,view=reading.view,cut=reading.cut,fill=reading.fill,retries=item.hillRetries or 0,relaxed=not reading.ok})
		self.stats.hillTurns+=1
		if not reading.ok then self.stats.hillRelaxed+=1 end
		return best
	end
	return nil
end
-- The next planned turn, or a bend that first brings the road back near the heading the
-- turn is planned from. nil when it is refused: the stretch before it then runs on.
function SplineGen._planned(self: Gen, item: Item): Spline.Section?
	local M = Config.Spline.Mountain
	local st = self.stats
	local yaw0 = select(3, self.spline:tip())
	-- the turn lands on the heading the mountain gives here (T-226), from the heading the
	-- stretch before it kept
	if item.slope then
		item.to = (self:_slopeAim(item.slope))
		if item.traverse then
			-- a descent's hairpin turns through the downhill side, the way on down the range,
			-- however near half a turn it is (T-326): through the uphill side it met the leg above
			local r = self.ground.range
			local bestDown = -math.huge
			for _, d in { 1, -1 } do
				local mid = yaw0 + d * ((d * ((item.to :: number) - yaw0)) % (2 * math.pi)) * 0.5
				local down = -math.sin(mid) * r.ux - math.cos(mid) * r.uz
				if down > bestDown then
					bestDown, item.dir = down, d
				end
			end
		elseif item.autoDir then
			local d = sign(wrap((item.to :: number) - yaw0))
			if d ~= 0 then
				item.dir = d
			end
		end
		if item.window then
			item.window = self.aim
		end
	end
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
		-- (only if it keeps the road within `StraightenMaxOff` of h: unchecked, one ran the
		-- road 100 studs into the face just before a hairpin, T-242; the hairpin turns from
		-- whatever heading the road has)
		if typeof(fix) == "table" then
			local _, _, _, _, g0, _, y0 = self.spline:tip()
			local _, off = self:_followGrade((fix :: Spline.Section).k, g0, y0)
			if off > Config.Range.StraightenMaxOff then
				fix = nil
			end
		end
		if typeof(fix) == "table" then
			st.straightens += 1
			return fix :: Spline.Section
		end
	end
	do
		local sec = self:_turn(item)
		if sec == "later" then
			-- (a descent's tight hairpin refused short of the leg's end, T-337: on along the leg to
			-- its end, where the ordinary hairpin is laid as before)
			table.insert(self.plan, 1, { turn = false, what = "traverse", aim = self.aim, limit = self.limit, left = math.huge, slope = item.legSlope })
			return nil
		end
		if sec == "done" or typeof(sec) == "table" then
			table.remove(self.plan, 1)
			if item.what == "turnaround" then
				st.turnarounds += 1
				self.nextDirV = item.nextDirV
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
	-- (a turn refused `GiveUp` times is dropped with the rest of the plan, and the way to the
	-- pass planned again from where the road has got to)
	item.refused = (item.refused or 0) + 1
	-- (a descent's hairpin is given up sooner: past its site the leg's survey has nothing to
	-- say, and the next leg is surveyed from where the road has got to, T-326)
	if item.refused >= (if item.traverse then Config.Range.TraverseGiveUp else Config.Range.GiveUp) then
		table.clear(self.plan)
		return nil
	end
	table.insert(self.plan, 1, { turn = false, what = "wait", aim = self.aim, limit = self.limit, left = M.RetryAfter })
	return nil
end

-- Both the recorded drive and the range planner lay ordinary sections. Keep the
-- edge, runoff, bend history and clearance grid continuous when the recording ends.
local function lay(self: Gen, chosen: Spline.Section, started: number)
	self:_terrain(chosen)
	self:_carve(chosen)
	self:_commit(chosen)
	local bend = chosen.tag ~= "Straight" and chosen.tag ~= "Escape" and chosen.tag ~= "Start"
	if bend then
		table.insert(self.recent, chosen.tag :: string)
		if #self.recent > Config.Spline.RecentBends then
			table.remove(self.recent, 1)
		end
		for j = #chosen.k, 2, -2 do
			if chosen.k[j] ~= 0 then
				self.lastDir = sign(chosen.k[j])
				break
			end
		end
	end
	self.lastWasBend = bend and chosen.k[#chosen.k] ~= 0
	local ms = (os.clock() - started) * 1000
	self.stats.totalMs += ms
	self.stats.worstMs = math.max(self.stats.worstMs, ms)
end

-- Lay the next section. Returns it, or nil if the road is stalled.
function SplineGen.step(self: Gen): Spline.Section?
	local st = self.stats
	if st.stalled then
		return nil
	end
	local t0 = os.clock()
	if self.ground.range.basins then
		local _, _, _, _, grade, bank, height = self.spline:tip()
		local recorded = Seed7Drive.section(self.spline.length, bank)
		if recorded then
			recorded.g = (self:_followGrade(recorded.k, grade, height))
			lay(self, recorded, t0)
			return recorded
		end
	end
	local C = Config.Spline
	local sec: Spline.Section? = nil
	local planned = false
	-- once the road has crossed the ridge it was heading for (T-238), what was planned to reach
	-- that pass is dropped and the way to the next one planned
	if self.target then
		local x, z = self.spline:tip()
		if Range.ridgeAhead(self.ground.range, x, z) ~= self.target.k then
			table.clear(self.plan)
		end
	end
	if #self.plan == 0 then
		self:_planRange()
	end
	local item = self.plan[1]
	-- (a planned turn makes headway on along the range, as every turn did before T-326; the
	-- hairpin ending a descent's leg, across the range the way the next leg goes)
	self.headway = nil
	self.turning = item.turn
	self.setback = nil
	if item.turn and item.traverse and item.nextDirV then
		local r = self.ground.range
		self.headway = { item.nextDirV * r.uz, -item.nextDirV * r.ux }
		-- (its setback is measured down the face, square to the crest it falls from: on a face
		-- whose crest runs aslant, the way back across runs back along the range)
		local x, z = self.spline:tip()
		local t, v = Range.frame(r, x, z)
		local k = self:_target().k - 1
		local e = Config.Range.TraverseFrameSpan * 0.5
		local lean = (Range.ridgeT(r, k, v + e) - Range.ridgeT(r, k, v - e)) / (2 * e)
		local n = math.sqrt(1 + lean * lean)
		local dt, dv = 1 / n, -lean / n
		self.setback = { dt * r.ux + dv * r.uz, dt * r.uz - dv * r.ux }
	end
	if item.turn then
		local wasTraverse = item.traverse == true
		sec = self:_planned(item)
		planned = sec ~= nil
		item = self.plan[1]
		-- (a descent's next leg is surveyed from its hairpin's exit, next step, T-326)
		if not item and not (planned and wasTraverse) then
			self:_planRange()
			item = self.plan[1]
		end
	end
	if not planned and not item.turn then
		self.aim, self.limit = item.aim :: number, item.limit :: number
		-- the heading, and how far bends stray off it, from the mountain where the road is now
		-- (T-226); a wait keeps the stretch before it's kind. Across the slope the bends may
		-- stray less far uphill than down: toward the leg above is where the road would crowd
		-- itself
		local sl = item.slope or self.lastSlope
		if sl then
			self.lastSlope = sl
			local aim, down, up, upSign = self:_slopeAim(sl, true)
			self.aim = aim
			local leg = self.leg
			if sl.kind == "traverse" and leg then
				-- headway along a descent's leg is across the range (T-326)
				local r = self.ground.range
				self.headway = { leg.dirV * r.uz, -leg.dirV * r.ux }
			end
			if sl.kind == "leg" or sl.kind == "traverse" then
				self.limit, self.limitUp, self.upSign = down, up, upSign
			else
				self.limitUp, self.upSign = self.limit, 0
			end
		end
	end
	-- a candidate that leaves the road more than `FollowMaxOff` off the mountain gives way to
	-- one that follows it (T-226)
	local nearest: Spline.Section?, nearestOff, nearEnd = nil, math.huge, nil
	-- along a descent's leg, the section that keeps to it (T-326)
	local tracked = false
	if not planned and self.headway and self.leg then
		sec = self:_track()
		tracked = sec ~= nil
	end
	for _ = 1, if planned or tracked then 0 else C.CandidateTries do
		st.tries += 1
		local cand, why, off, endOff = self:_candidate()
		if cand and off and off > C.Ground.FollowMaxOff then
			st.offGround += 1
			if off < nearestOff then
				nearest, nearestOff, nearEnd = cand, off, endOff
			end
		elseif cand then
			sec = cand
			break
		elseif why == "crowded" then
			st.rejectedCrowded += 1
		else
			st.rejectedHeading += 1
		end
	end
	-- if none does, the section that best brings the road back to h (`_follow`, T-242)
	if not sec and not planned then
		sec = self:_follow(nearest, if nearest then nearestOff else nil, nearEnd)
		if sec and sec == nearest then
			st.offGroundLaid += 1
		end
	end
	if not sec and nearest then
		sec = nearest
		st.offGroundLaid += 1
	end
	if not sec then
		-- the escape: checked when the section before this one was accepted
		local sp = self.spline
		local _, _, _, k0, g0, b0, y0 = sp:tip()
		local Te = transition(k0, 0)
		local len = Te + C.EscapeLength
		local knots = if Te > 0 then { Te, 0, len, 0 } else { len, 0 }
		-- an escape that is not clear, or whose own escape is not, is the road about to box
		-- itself in (T-238): any bend that gets it clear is taken first, and the way to the
		-- pass planned again from there
		local rescue: Spline.Section? = nil
		if not self:_exitClear(knots, 0) then
			rescue = self:_rescue()
		end
		if rescue then
			sec = rescue
			table.clear(self.plan)
		elseif not self:_clear(knots) then
			st.stalled = true
			warn(`SplineGen: the road is boxed in at {math.floor(sp.length)} studs (seed {self.seed}); it stops growing here`)
			return nil
		else
			st.escapes += 1
			-- a detour that has run into old road ends here, and the turn back onto the leg
			-- comes next (a sideways climb toward the leg above can otherwise box itself in)
			local head = self.plan[1]
			if head and not head.turn and head.what ~= "leg" and head.what ~= "traverse" then
				head.left = 0
			end
			if not self:_clear(withEscape(knots, 0)) then
				st.cornered += 1
			end
			sec = {
				len = len,
				k = knots,
				g = (self:_followGrade(knots, g0, y0)),
				b = pickBank(0, nil, b0, math.min(Te, len), len, true),
				tag = "Escape",
			}
		end
	end
	local chosen = if planned or tracked then sec :: Spline.Section else self:_contour(sec :: Spline.Section)
	lay(self, chosen, t0)
	-- a random section counts toward the stretch it was laid in
	local head = self.plan[1]
	if not planned and head and not head.turn then
		head.left = (head.left :: number) - chosen.len
		if head.untilV then
			local x, z = self.spline:tip()
			local _, v = Range.frame(self.ground.range, x, z)
			if (v - head.untilV) * (head.untilDir or 1) >= 0 then
				head.left = 0
			end
		end
		-- a descent's leg ends where the road reaches its end (T-326)
		local leg = self.leg
		if head.what == "traverse" and leg then
			local x, z = self.spline:tip()
			local t, v = Range.frame(self.ground.range, x, z)
			local _, _, _, at = Traverse.ahead(leg, t, v, 0)
			if at >= leg.length - (head.arrive or Config.Range.TraverseArrive) then
				head.left = 0
			end
		end
		if (head.left :: number) <= 0 then
			table.remove(self.plan, 1)
		end
	end
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
