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
		trend: number,
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
function SplineGen.limits(): (number, number)
	local C = Config.Spline
	local R = Config.Road
	local clear = R.Width + 2 * R.BarrierThickness + C.ClearanceGap
	local rmin = C.MinRadius
	local ratio = math.min(1, clear / (2 * rmin))
	local sep = 2 * rmin * math.asin(ratio) + 2 * C.CheckStep
	return clear, sep
end

function SplineGen.new(seed: number, origin: Spline.Origin?): Gen
	local clear, sep = SplineGen.limits()
	local spline = Spline.new(origin)
	local self = setmetatable({
		spline = spline,
		rng = Random.new(seed),
		seed = seed,
		sections = {},
		recent = {},
		lastDir = 0,
		lastWasBend = false,
		trend = spline.origin.yaw,
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
		},
	}, SplineGen)
	local L = Config.Spline.StartStraight
	self:_commit({ len = L, k = { L, 0 }, g = { L, 0 }, b = { L, 0 }, tag = "Start" })
	return self
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
-- `every` studs. Simpson steps of `SampleStep`, the same accuracy as the spline itself.
local function walk(x: number, z: number, yaw0: number, k0: number, knots: { number }, every: number, emit: (number, number, number) -> boolean?): boolean
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
	local nextEmit = every
	while s < total - 1e-9 do
		-- advance the interval so that s lies in [sA, knots[j]]
		while s >= knots[j] - 1e-9 and j + 2 <= #knots do
			yawA = yawAt(knots[j])
			sA, kA = knots[j], knots[j + 1]
			j += 2
		end
		local s1 = math.min(s + step, knots[j], total)
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
-- inside `MinHeight..MaxHeight` of where the road began.
local function pickGrade(self: Gen, g0: number, y0: number, len: number): { number }
	local C = Config.Spline
	local gMax = math.tan(math.rad(C.MaxGrade))
	local rate = C.MaxGradeRate
	local base = self.spline.origin.y
	local function ends(gt: number): number
		local knots, gEnd = ramp(g0, gt, rate, 0, len)
		-- the height at the section's end: integrate the ramp
		local y, s, g = y0, 0, g0
		for j = 1, #knots, 2 do
			y += 0.5 * (g + knots[j + 1]) * (knots[j] - s)
			s, g = knots[j], knots[j + 1]
		end
		-- and what levelling off from gEnd would add
		return y + sign(gEnd) * gEnd * gEnd / (2 * rate) - base
	end
	local gt: number
	if self.rng:NextNumber() < C.KeepGradeChance then
		gt = math.clamp(g0, -gMax, gMax)
	else
		gt = (self.rng:NextNumber() * 2 - 1) * gMax
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
	return walk(x0, z0, yaw0, k0, knots, Config.Spline.CheckStep, function(u, x, z)
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
	local limit = math.rad(C.HeadingLimit)
	local rel = wrap(yaw0 - self.trend)

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
			-- lean back toward the road's general direction the further it has strayed
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
		local room = limit - dir * (rel + escapeTurn)
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
	if math.abs(wrap(yawEnd + escYaw - self.trend)) > limit + 1e-6 then
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

-- Lay the next section. Returns it, or nil if the road is stalled.
function SplineGen.step(self: Gen): Spline.Section?
	local st = self.stats
	if st.stalled then
		return nil
	end
	local t0 = os.clock()
	local C = Config.Spline
	local sec: Spline.Section? = nil
	for _ = 1, C.CandidateTries do
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
	self:_commit(chosen)
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
