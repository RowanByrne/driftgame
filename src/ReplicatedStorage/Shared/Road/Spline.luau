--!strict
-- Spline: the spline road's curve, as pure maths (features/spline-road.md, T-132).
-- No instances, no Workspace, no service: the server, every client and the tests all run
-- the same arithmetic on the same knots.
--
-- THE CURVE IS DESCRIBED BY WHAT IT DOES ALONG ITS OWN LENGTH, not by control points.
-- Three TRACKS, each a list of knots `(s, value)` joined by straight lines, where `s` is
-- PLAN arc length from the road's start:
--
--   curvature  1/radius, positive turning LEFT. Linear between knots, so a bend eases in
--              and out (a clothoid, as real roads are set out), and the heading -- its
--              integral -- is a piecewise quadratic with no kinks anywhere
--   grade      dy/ds. Linear between knots, so the height -- its integral -- is a
--              piecewise parabola: crests and dips with no creases
--   bank       radians, positive raising the RIGHT edge. Linear between knots
--
-- Because `s` IS arc length, "how far along am I" is the parameter itself. A car that
-- carries its own `s` finds the ground with a couple of Newton steps and a handful of
-- sums, never a search.
--
-- THE SURFACE is ruled along plan cross-sections: the point `d` studs to the right of the
-- centre line at `s` is
--
--     centre(s) + d * planRight(s) + (0, d * tan(bank(s)), 0)
--
-- That one formula is what the mesh is drawn from AND what the car stands on, so the two
-- can never disagree by more than how finely the mesh is cut.
--
-- Angles follow `Road/Pieces`: yaw 0 faces -Z, positive turns left,
-- forward(yaw) = (-sin yaw, -cos yaw) and planRight(yaw) = (cos yaw, -sin yaw).
--
-- THE MOUNTAINSIDE (features/mountain-road.md, T-140). Either side of the tarmac, at every
-- `s`: grass runoff, then an EDGE -- a rock face, a hedge or a cliff -- and here and there a
-- K-rail on the tarmac's edge. Each is a few more knots per section, replayed like the rest:
--
--   runoff     studs of grass past the tarmac, one eased track per side. On the inside of
--              a bend it is cut to `InsideShare` of the way to the bend's centre
--   edge       which edge, as spans `(sEnd, kind)` per side: ROCK, HEDGE or CLIFF
--   K-rails    runs `(s0, s1)` per side
--   gravel     runs `(s0, s1)` per side where the runoff is gravel, not grass: the tight
--              cliff edges, a strip of a few studs between a K-rail and the drop (T-181)
--   groves     runs `(s0, s1, seed)` per side, a whole section each (T-183): the trees on
--              that side's runoff, placed from the seed by `Road/SplineGrove`
--
-- A section that carries none of these (a test's hand-made road) gets no runoff and a hedge
-- on both sides: a wall exactly where the old barriers stood.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Spline = {}
Spline.__index = Spline

export type Origin = { x: number, y: number, z: number, yaw: number }

-- One generator step, in the form it is sent over the wire and replayed: its length, and
-- each track's knots inside it as a flat list `{ds1, v1, ds2, v2, ...}`, `ds` measured
-- from the section's start. Every track's last knot sits exactly at `len`.
export type Section = {
	len: number,
	k: { number }, -- curvature
	g: { number }, -- grade
	b: { number }, -- bank
	tag: string?, -- what the generator meant it as ("Hairpin", "Straight", ...); unread by the maths
	-- the mountainside, each optional (T-140):
	rl: { number }?, -- left runoff width knots {ds, w, ...}, the last at `len`
	rr: { number }?, -- right
	el: { number }?, -- left edge spans {dsEnd, kind, ...}, the last ending at `len`
	er: { number }?, -- right
	kr: { number }?, -- K-rail runs {ds0, ds1, side, ...}, side -1 left, 1 right
	gl: { number }?, -- gravel runoff runs {ds0, ds1, side, ...}, as `kr` (T-181)
	gv: { number }?, -- groves {side, seed, ...}: trees on that side's runoff, the whole section (T-183)
}

-- The edge kinds, as they go over the wire.
Spline.ROCK = 1
Spline.HEDGE = 2
Spline.CLIFF = 3

-- What is under a point, from `Spline.groundKind`.
Spline.TARMAC = 0
Spline.GRASS = 1
Spline.GRAVEL = 2 -- the runoff inside a gravel run (T-181)

type Spans = { e: { number }, t: { number } } -- span ends, increasing, and each span's kind
type Runs = { a: { number }, b: { number } } -- run starts (increasing) and ends
export type Groves = { a: { number }, b: { number }, seed: { number } } -- grove runs (T-183)

type Track = {
	s: { number }, -- knot positions, increasing
	v: { number }, -- knot values
	hint: number, -- last interval found
	ease: boolean, -- smoothstep between knots rather than a straight line
}

export type Spline = typeof(setmetatable(
	{} :: {
		origin: Origin,
		length: number, -- plan arc length laid so far
		sections: number,
		curv: Track,
		grade: Track,
		bank: Track,
		yawK: { number }, -- heading at each curvature knot
		yK: { number }, -- height at each grade knot
		step: number, -- SampleStep
		X: { [number]: number }, -- plan position every `step` studs, keyed by sample index
		Z: { [number]: number },
		lastSample: number,
		firstSample: number,
		checkStep: number,
		cell: number,
		hash: { [number]: { number } }, -- flat {s, x, z, s, x, z, ...} per cell
		lastCheck: number, -- the last s filed in the hash
		runL: Track?, -- runoff widths, made on the first section
		runR: Track?,
		edgeL: Spans,
		edgeR: Spans,
		railL: Runs,
		railR: Runs,
		gravL: Runs, -- gravel runoff runs (T-181)
		gravR: Runs,
		groveL: Groves,
		groveR: Groves,
	},
	Spline
))

local function newTrack(v0: number, ease: boolean?): Track
	return { s = { 0 }, v = { v0 }, hint = 1, ease = ease == true }
end

-- The knot interval holding `s`: the largest i with track.s[i] <= s, clamped so i and i+1
-- exist whenever there are two knots.
local function find(t: Track, s: number): number
	local ks = t.s
	local n = #ks
	if n < 2 then
		return 1
	end
	local i = t.hint
	if i < n and ks[i] <= s and s < ks[i + 1] then
		return i
	end
	if i + 1 < n and ks[i + 1] <= s and s < ks[i + 2] then
		t.hint = i + 1
		return i + 1
	end
	if s <= ks[1] then
		t.hint = 1
		return 1
	end
	if s >= ks[n] then
		t.hint = n - 1
		return n - 1
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if ks[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	t.hint = lo
	return lo
end

-- Value and slope of a track at `s`; beyond its last knot it holds the last value.
local function valueAt(t: Track, s: number): (number, number, number)
	local i = find(t, s)
	local ks, vs = t.s, t.v
	if i >= #ks then
		return vs[#vs], 0, i
	end
	local s0, s1 = ks[i], ks[i + 1]
	if s >= s1 then
		return vs[i + 1], 0, i
	end
	local L = s1 - s0
	local dv = vs[i + 1] - vs[i]
	if t.ease then
		-- smoothstep: the value AND its slope are continuous at every knot, so nothing
		-- that leans on the slope (the kerb's height along a banking road) has a crease
		if s <= s0 then
			return vs[i], 0, i
		end
		local u = (s - s0) / L
		return vs[i] + dv * u * u * (3 - 2 * u), dv / L * 6 * u * (1 - u), i
	end
	if s <= s0 then
		return vs[i], dv / L, i
	end
	local slope = dv / L
	return vs[i] + slope * (s - s0), slope, i
end

local function hashKey(cx: number, cz: number): number
	-- two signed cell indices in one number; a run never gets 2^20 cells from its start
	return (cx + 1048576) * 2097152 + (cz + 1048576)
end

function Spline.new(origin: Origin?): Spline
	local C = Config.Spline
	local o: Origin = origin
		or {
			x = Config.Road.Offset.X,
			y = Config.Road.SurfaceY,
			z = Config.Road.Offset.Z,
			yaw = math.rad(Config.Road.StartHeading),
		}
	local self = setmetatable({
		origin = o,
		length = 0,
		sections = 0,
		curv = newTrack(0),
		grade = newTrack(0),
		-- The bank EASES between knots. Curvature and grade are linear and that is right for
		-- them -- their integrals (heading, height) are what must be smooth, and are. The
		-- bank is used directly: a linear ramp would put a crease in the kerb where the
		-- ramp starts and stops, `d x bank'` of grade, 2.9 degrees at the kerb of a
		-- 10-degree bank laid at full rate.
		bank = newTrack(0, true),
		yawK = { o.yaw },
		yK = { o.y },
		step = C.SampleStep,
		X = { [0] = o.x },
		Z = { [0] = o.z },
		lastSample = 0,
		firstSample = 0,
		checkStep = C.CheckStep,
		cell = C.HashCell,
		hash = {},
		lastCheck = -math.huge,
		runL = nil,
		runR = nil,
		edgeL = { e = {}, t = {} },
		edgeR = { e = {}, t = {} },
		railL = { a = {}, b = {} },
		railR = { a = {}, b = {} },
		gravL = { a = {}, b = {} },
		gravR = { a = {}, b = {} },
		groveL = { a = {}, b = {}, seed = {} },
		groveR = { a = {}, b = {}, seed = {} },
	}, Spline)
	return self
end

--------------------------------------------------------------------------------
-- The analytic parts: heading, height, bank
--------------------------------------------------------------------------------

function Spline.curvatureAt(self: Spline, s: number): number
	return (valueAt(self.curv, s))
end

-- The heading is the integral of a piecewise-linear curvature: exact, no stepping.
function Spline.yawAt(self: Spline, s: number): number
	local t = self.curv
	local i = find(t, s)
	local ks, vs = t.s, t.v
	local ds = s - ks[i]
	if i >= #ks then
		return self.yawK[i] + vs[i] * ds
	end
	local L = ks[i + 1] - ks[i]
	if ds > L then
		-- past the last knot: the curvature holds
		return self.yawK[i + 1] + vs[i + 1] * (ds - L)
	end
	local slope = (vs[i + 1] - vs[i]) / L
	return self.yawK[i] + vs[i] * ds + 0.5 * slope * ds * ds
end

function Spline.gradeAt(self: Spline, s: number): number
	return (valueAt(self.grade, s))
end

-- Centre-line height: the integral of a piecewise-linear grade.
function Spline.heightAt(self: Spline, s: number): number
	local t = self.grade
	local i = find(t, s)
	local ks, vs = t.s, t.v
	local ds = s - ks[i]
	if i >= #ks then
		return self.yK[i] + vs[i] * ds
	end
	local L = ks[i + 1] - ks[i]
	if ds > L then
		return self.yK[i + 1] + vs[i + 1] * (ds - L)
	end
	local slope = (vs[i + 1] - vs[i]) / L
	return self.yK[i] + vs[i] * ds + 0.5 * slope * ds * ds
end

function Spline.bankAt(self: Spline, s: number): number
	return (valueAt(self.bank, s))
end

--------------------------------------------------------------------------------
-- The plan position: integrated once, kept every `step` studs
--------------------------------------------------------------------------------

-- Simpson's rule over [s0, s1] from (x0, z0). One step of it over `SampleStep` studs is
-- out by about L^5 * k'^2 -- far under a thousandth of a stud for any bend allowed.
local function simpson(self: Spline, x0: number, z0: number, s0: number, s1: number): (number, number)
	local y0 = self:yawAt(s0)
	local ym = self:yawAt((s0 + s1) * 0.5)
	local y1 = self:yawAt(s1)
	local h = (s1 - s0) / 6
	local x = x0 + h * (-math.sin(y0) - 4 * math.sin(ym) - math.sin(y1))
	local z = z0 + h * (-math.cos(y0) - 4 * math.cos(ym) - math.cos(y1))
	return x, z
end

-- Centre line in plan at `s`. The sample at or below `s`, then one Simpson step to `s`
-- itself: continuous, and equal to the next sample exactly at the next sample.
function Spline.planAt(self: Spline, s: number): (number, number)
	local step = self.step
	local i = math.floor(s / step)
	if i > self.lastSample then
		i = self.lastSample
	elseif i < self.firstSample then
		i = self.firstSample
	end
	local si = i * step
	local x, z = self.X[i], self.Z[i]
	if s == si then
		return x, z
	end
	return simpson(self, x, z, si, s)
end

local function addCheckPoints(self: Spline, upTo: number)
	local cs = self.checkStep
	local s = if self.lastCheck == -math.huge then 0 else self.lastCheck + cs
	while s <= upTo + 1e-9 do
		local x, z = self:planAt(s)
		local key = hashKey(math.floor(x / self.cell), math.floor(z / self.cell))
		local list = self.hash[key]
		if not list then
			list = {}
			self.hash[key] = list
		end
		local n = #list
		list[n + 1] = s
		list[n + 2] = x
		list[n + 3] = z
		self.lastCheck = s
		s += cs
	end
end

-- Lay one section on the end of the road. Its knots are appended to the three tracks, the
-- heading and height at each new knot are carried forward exactly, and the plan position
-- is integrated out to the new end.
-- `carry`, when given, is the track's integral at each knot (heading for curvature,
-- height for grade), carried forward exactly over each linear ramp.
local function appendTrack(t: Track, carry: { number }?, s0: number, knots: { number })
	local n = #t.s
	for j = 1, #knots, 2 do
		local s = s0 + knots[j]
		local v = knots[j + 1]
		local sPrev, vPrev = t.s[n], t.v[n]
		-- A knot never sits on or behind the last one: that would be a step in the value,
		-- and it would change road that has already been laid and sent.
		assert(s > sPrev + 1e-9, "Spline: a knot must lie after the last one")
		if carry then
			carry[n + 1] = carry[n] + 0.5 * (vPrev + v) * (s - sPrev)
		end
		n += 1
		t.s[n] = s
		t.v[n] = v
	end
end

local function appendSpans(sp: Spans, s0: number, len: number, spans: { number }?)
	if not spans then
		table.insert(sp.e, s0 + len)
		table.insert(sp.t, Spline.HEDGE)
		return
	end
	for j = 1, #spans, 2 do
		table.insert(sp.e, s0 + spans[j])
		table.insert(sp.t, spans[j + 1])
	end
end

local function appendRuns(sp: Spline, s0: number, runs: { number }?)
	if not runs then
		return
	end
	for j = 1, #runs, 3 do
		local list = if runs[j + 2] < 0 then sp.railL else sp.railR
		local a, b = s0 + runs[j], s0 + runs[j + 1]
		local n = #list.a
		list.a[n + 1], list.b[n + 1] = a, b
	end
end

local function appendGravel(sp: Spline, s0: number, runs: { number }?)
	if not runs then
		return
	end
	for j = 1, #runs, 3 do
		local list = if runs[j + 2] < 0 then sp.gravL else sp.gravR
		local n = #list.a
		list.a[n + 1], list.b[n + 1] = s0 + runs[j], s0 + runs[j + 1]
	end
end

-- A section's groves (T-183): each side's grove covers the whole section.
local function appendGroves(sp: Spline, s0: number, len: number, gv: { number }?)
	if not gv then
		return
	end
	for j = 1, #gv, 2 do
		local list = if gv[j] < 0 then sp.groveL else sp.groveR
		local n = #list.a
		list.a[n + 1], list.b[n + 1], list.seed[n + 1] = s0, s0 + len, gv[j + 1]
	end
end

-- Is a section's mountainside well formed? Its knots inside it, its spans ending at its
-- end, its edge kinds known, its runs inside it, in order and apart. Anything else is
-- refused before any of it is laid, so a half-appended section never exists.
local function checkTerrain(self: Spline, sec: Section)
	local len = sec.len
	for _, knots in { sec.rl, sec.rr } do
		if knots then
			assert(#knots >= 2 and #knots % 2 == 0 and math.abs(knots[#knots - 1] - len) < 1e-6, "Spline: runoff knots must end at the section's end")
			local last = 0
			for j = 1, #knots, 2 do
				assert(knots[j] > last - 1e-9 and knots[j + 1] >= 0, "Spline: runoff knots in order, never negative")
				last = knots[j]
			end
		end
	end
	for _, spans in { sec.el, sec.er } do
		if spans then
			assert(#spans >= 2 and #spans % 2 == 0 and math.abs(spans[#spans - 1] - len) < 1e-6, "Spline: edge spans must end at the section's end")
			local last = 0
			for j = 1, #spans, 2 do
				local kind = spans[j + 1]
				assert(spans[j] > last and (kind == Spline.ROCK or kind == Spline.HEDGE or kind == Spline.CLIFF), "Spline: edge spans in order, of a known kind")
				last = spans[j]
			end
		end
	end
	local kr = sec.kr
	if kr then
		assert(#kr % 3 == 0, "Spline: K-rail runs come in threes")
		local lastEnd = { [-1] = -math.huge, [1] = -math.huge }
		local railEnd = { [-1] = self.railL.b[#self.railL.b], [1] = self.railR.b[#self.railR.b] }
		for j = 1, #kr, 3 do
			local a, b, side = kr[j], kr[j + 1], kr[j + 2]
			assert(side == -1 or side == 1, "Spline: a K-rail run's side is -1 or 1")
			assert(a >= 0 and b > a and b <= len + 1e-6, "Spline: a K-rail run must lie inside its section")
			assert(a >= lastEnd[side] and (railEnd[side] == nil or self.length + a >= railEnd[side] - 1e-6), "Spline: K-rail runs on a side in order and apart")
			lastEnd[side] = b
		end
	end
	local gl = sec.gl
	if gl then
		assert(#gl % 3 == 0, "Spline: gravel runs come in threes")
		local lastEnd = { [-1] = -math.huge, [1] = -math.huge }
		for j = 1, #gl, 3 do
			local a, b, side = gl[j], gl[j + 1], gl[j + 2]
			assert(side == -1 or side == 1, "Spline: a gravel run's side is -1 or 1")
			assert(a >= 0 and b > a and b <= len + 1e-6 and a >= lastEnd[side], "Spline: gravel runs inside their section, in order")
			lastEnd[side] = b
		end
	end
	local gv = sec.gv
	if gv then
		assert(#gv % 2 == 0, "Spline: groves come in pairs")
		local seen = {}
		for j = 1, #gv, 2 do
			local side, seed = gv[j], gv[j + 1]
			assert((side == -1 or side == 1) and not seen[side], "Spline: a grove's side is -1 or 1, once each")
			assert(seed == math.floor(seed) and math.abs(seed) < 2 ^ 31, "Spline: a grove's seed is a whole number")
			seen[side] = true
		end
	end
end

function Spline.append(self: Spline, sec: Section)
	local s0 = self.length
	local s1 = s0 + sec.len
	for _, knots in { sec.k, sec.g, sec.b } do
		assert(#knots >= 2 and math.abs(knots[#knots - 1] - sec.len) < 1e-6, "Spline: every track must end on a knot at the section's end")
	end
	checkTerrain(self, sec)
	appendTrack(self.curv, self.yawK, s0, sec.k)
	appendTrack(self.grade, self.yK, s0, sec.g)
	appendTrack(self.bank, nil, s0, sec.b)
	-- the mountainside. A runoff track starts at whatever the first section asks for
	if not self.runL then
		self.runL = newTrack(if sec.rl then sec.rl[2] else 0, true)
	end
	if not self.runR then
		self.runR = newTrack(if sec.rr then sec.rr[2] else 0, true)
	end
	local runL, runR = self.runL :: Track, self.runR :: Track
	appendTrack(runL, nil, s0, sec.rl or { sec.len, runL.v[#runL.v] })
	appendTrack(runR, nil, s0, sec.rr or { sec.len, runR.v[#runR.v] })
	appendSpans(self.edgeL, s0, sec.len, sec.el)
	appendSpans(self.edgeR, s0, sec.len, sec.er)
	appendRuns(self, s0, sec.kr)
	appendGravel(self, s0, sec.gl)
	appendGroves(self, s0, sec.len, sec.gv)
	self.length = s1
	self.sections += 1
	local step = self.step
	local i = self.lastSample
	while (i + 1) * step <= s1 + 1e-9 do
		local x, z = simpson(self, self.X[i], self.Z[i], i * step, (i + 1) * step)
		i += 1
		self.X[i], self.Z[i] = x, z
	end
	self.lastSample = i
	addCheckPoints(self, s1)
end

-- Forget the plan samples behind `s`. Knots, heading and height are kept -- they are a few
-- numbers per section -- and so is the hash, which is what stops the road crossing road
-- it laid an hour ago.
function Spline.trim(self: Spline, s: number)
	local keep = math.floor(s / self.step) - 1
	if keep > self.lastSample - 1 then
		keep = self.lastSample - 1
	end
	for i = self.firstSample, keep - 1 do
		self.X[i] = nil
		self.Z[i] = nil
	end
	if keep > self.firstSample then
		self.firstSample = keep
	end
end

--------------------------------------------------------------------------------
-- The surface
--------------------------------------------------------------------------------

-- The surface point `d` studs right of the centre line at `s`, in full precision. A
-- Vector3 is single precision: 20 000 studs out, where the road starts, it holds a
-- position to about 0.002 studs, so anything that checks the maths uses this.
function Spline.surfaceXYZ(self: Spline, s: number, d: number): (number, number, number)
	local x, z = self:planAt(s)
	local yaw = self:yawAt(s)
	return x + d * math.cos(yaw), self:heightAt(s) + d * math.tan(self:bankAt(s)), z - d * math.sin(yaw)
end

function Spline.surface(self: Spline, s: number, d: number): Vector3
	return Vector3.new(self:surfaceXYZ(s, d))
end

-- The surface's height, gradient and normal at (s, d), from the formula itself.
--   along the plan right:   dh/dd = tan(bank)
--   along the plan forward: dh/dl = (grade + d * bank' * sec^2 bank) / (1 + k * d)
-- the denominator being how much the offset curve is stretched (k > 0 turns left, so the
-- right side is the outside and longer).
function Spline.normalAt(self: Spline, s: number, d: number): Vector3
	local yaw = self:yawAt(s)
	local fx, fz = -math.sin(yaw), -math.cos(yaw)
	local rx, rz = math.cos(yaw), -math.sin(yaw)
	local k = self:curvatureAt(s)
	local g = self:gradeAt(s)
	local b, bSlope = valueAt(self.bank, s)
	local tb = math.tan(b)
	local cb = math.cos(b)
	local along = (g + d * bSlope / (cb * cb)) / (1 + k * d)
	local gx = along * fx + tb * rx
	local gz = along * fz + tb * rz
	return Vector3.new(-gx, 1, -gz).Unit
end

-- A frame on the centre line at `s`, raised `lift` studs along the surface normal: what a
-- car is put down on and what a barrier is stood on. Forward runs up the grade.
function Spline.frame(self: Spline, s: number, lift: number?): CFrame
	local x, z = self:planAt(s)
	local yaw = self:yawAt(s)
	local g = self:gradeAt(s)
	local up = self:normalAt(s, 0)
	local fwd = Vector3.new(-math.sin(yaw), g, -math.cos(yaw)).Unit
	local right = fwd:Cross(up).Unit
	local pos = Vector3.new(x, self:heightAt(s), z) + up * (lift or 0)
	return CFrame.fromMatrix(pos, right, right:Cross(fwd))
end

--------------------------------------------------------------------------------
-- The mountainside: runoff, edges, K-rails, and the ground past the tarmac (T-140)
--------------------------------------------------------------------------------

-- Studs of grass past the tarmac on `side` (-1 left, 1 right) at `s`, as chosen.
function Spline.runoffRaw(self: Spline, s: number, side: number): number
	local t = if side < 0 then self.runL else self.runR
	if not t then
		return 0
	end
	return (valueAt(t, s))
end

-- The same, cut on the inside of a bend to `InsideShare` of the way to the bend's centre.
-- k > 0 turns left, so its inside is the left (-1).
function Spline.runoffAt(self: Spline, s: number, side: number): number
	local w = self:runoffRaw(s, side)
	local k = self:curvatureAt(s)
	if k ~= 0 and (k > 0) == (side < 0) then
		local limit = Config.Spline.Terrain.InsideShare / math.abs(k) - Config.Road.Width * 0.5
		if w > limit then
			w = math.max(limit, 0)
		end
	end
	return w
end

-- Which edge ends `side` at `s`: ROCK, HEDGE or CLIFF.
function Spline.edgeAt(self: Spline, s: number, side: number): number
	local sp = if side < 0 then self.edgeL else self.edgeR
	local e = sp.e
	local n = #e
	if n == 0 then
		return Spline.HEDGE
	end
	if s >= e[n] then
		return sp.t[n]
	end
	local lo, hi = 1, n
	while lo < hi do
		local mid = (lo + hi) // 2
		if e[mid] >= s then
			hi = mid
		else
			lo = mid + 1
		end
	end
	return sp.t[lo]
end

-- The K-rail run standing on `side` at `s`, as its start and end, or nil.
function Spline.kRailAt(self: Spline, s: number, side: number): (number?, number?)
	local r = if side < 0 then self.railL else self.railR
	local a = r.a
	local n = #a
	if n == 0 or s < a[1] then
		return nil, nil
	end
	local lo, hi = 1, n
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if a[mid] <= s then
			lo = mid
		else
			hi = mid - 1
		end
	end
	if s <= r.b[lo] then
		return a[lo], r.b[lo]
	end
	return nil, nil
end

-- Every K-rail run on `side` that overlaps [s0, s1], as a flat {a, b, a, b, ...}.
function Spline.kRailsIn(self: Spline, s0: number, s1: number, side: number): { number }
	local r = if side < 0 then self.railL else self.railR
	local out = {}
	for i = 1, #r.a do
		if r.a[i] > s1 then
			break
		end
		if r.b[i] >= s0 then
			table.insert(out, r.a[i])
			table.insert(out, r.b[i])
		end
	end
	return out
end

-- Is the runoff on `side` at `s` gravel rather than grass (T-181)?
function Spline.gravelAt(self: Spline, s: number, side: number): boolean
	local r = if side < 0 then self.gravL else self.gravR
	local a = r.a
	local lo, hi = 1, #a
	if hi == 0 or s < a[1] then
		return false
	end
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if a[mid] <= s then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return s <= r.b[lo]
end

-- The grove runs on `side` (T-183): starts (increasing), ends and seeds. Read, never change.
function Spline.groves(self: Spline, side: number): Groves
	return if side < 0 then self.groveL else self.groveR
end

-- The ground's height at (s, d), across the whole cross-section. On the tarmac it is the
-- road's own surface. Past it the grass FOLLOWS THE BANK AND EASES FLAT: its slope across
-- starts at the road's (tan bank) and falls away to nothing at the runoff's outer edge, so
-- a banked road's grass never lips up into a ramp. Past the runoff it holds that height:
-- the foot of a hedge or a rock face. (Past a cliff's lip there is nothing; that is
-- `groundKind`'s answer, not this one's.)
--
-- THE ROAD STANDS `RoadLip` PROUD OF ITS GRASS (T-184): past the tarmac's edge a straight
-- gravel bevel slopes down that far over `RoadLipWidth` (`lipWidth`: never more than
-- `LipShare` of a narrow runoff, so a tight cliff edge keeps flat gravel before its lip),
-- and everything out to the edges is that much lower. `lipDrop` is how far down a point is.
local function lipWidth(w: number): number
	local T = Config.Spline.Terrain
	return math.min(T.RoadLipWidth, w * T.LipShare)
end

local function lipDrop(e: number, w: number): number
	if e <= 0 or w <= 0 then
		return 0
	end
	local T = Config.Spline.Terrain
	local lw = lipWidth(w)
	if e >= lw then
		return T.RoadLip
	end
	return T.RoadLip * e / lw
end

-- The ground's height as if the road were not raised: the grass following the bank and
-- easing flat. `terrainNormal` reads its slope from this, so the step is a step to the car
-- and the walking tiles, never a slope that tilts the grass beside it.
local function groundY(self: Spline, s: number, d: number): (number, number, number)
	local half = Config.Road.Width * 0.5
	local tb = math.tan(self:bankAt(s))
	local a = math.abs(d)
	if a <= half then
		return self:heightAt(s) + d * tb, 0, 0
	end
	local side = if d < 0 then -1 else 1
	local w = self:runoffAt(s, side)
	local e = a - half
	local off
	if e >= w then
		off = w * 0.5
	else
		off = e - e * e / (2 * w)
	end
	return self:heightAt(s) + side * tb * (half + off), e, w
end

function Spline.terrainY(self: Spline, s: number, d: number): number
	local y, e, w = groundY(self, s, d)
	return y - lipDrop(e, w)
end

-- How far below the tarmac's edge the ground at (s, d) has dropped: 0 on the tarmac,
-- `RoadLip` once past the bevel.
function Spline.lipAt(self: Spline, s: number, d: number): number
	local _, e, w = groundY(self, s, d)
	return lipDrop(e, w)
end

-- How wide the gravel bevel is on `side` at `s`, in studs past the tarmac's edge.
function Spline.lipWidthAt(self: Spline, s: number, side: number): number
	local w = self:runoffAt(s, side)
	return if w > 0 then lipWidth(w) else 0
end

function Spline.terrainXYZ(self: Spline, s: number, d: number): (number, number, number)
	local x, z = self:planAt(s)
	local yaw = self:yawAt(s)
	return x + d * math.cos(yaw), self:terrainY(s, d), z - d * math.sin(yaw)
end

-- The ground's normal at (s, d). On the tarmac, the exact one (`normalAt`); past it, from
-- the ground half a stud either side of the point, along and across. THE ROAD'S STEP IS
-- LEFT OUT (T-184): it is a step, not a slope, so the grass at its foot and a wheel on its
-- face both get the grass's own normal.
function Spline.terrainNormal(self: Spline, s: number, d: number): Vector3
	if math.abs(d) <= Config.Road.Width * 0.5 then
		return self:normalAt(s, d)
	end
	local e = 0.5
	local function at(sa: number, da: number): (number, number, number)
		local x, z = self:planAt(sa)
		local yaw = self:yawAt(sa)
		return x + da * math.cos(yaw), (groundY(self, sa, da)), z - da * math.sin(yaw)
	end
	local ax, ay, az = at(s - e, d)
	local bx, by, bz = at(s + e, d)
	local cx, cy, cz = at(s, d - e)
	local dx, dy, dz = at(s, d + e)
	local along = Vector3.new(bx - ax, by - ay, bz - az)
	local across = Vector3.new(dx - cx, dy - cy, dz - cz)
	local n = across:Cross(along)
	if n.Magnitude < 1e-9 then
		return Vector3.yAxis
	end
	if n.Y < 0 then
		n = -n
	end
	return n.Unit
end

-- What is underfoot at (s, d): TARMAC, GRASS, GRAVEL (the runoff in a gravel run), or nil
-- past a cliff's lip, where there is nothing. Past a rock face or a hedge the grass carries
-- on under it.
function Spline.groundKind(self: Spline, s: number, d: number): number?
	local half = Config.Road.Width * 0.5
	local a = math.abs(d)
	if a <= half then
		return Spline.TARMAC
	end
	local side = if d < 0 then -1 else 1
	local w = self:runoffAt(s, side)
	if a - half <= w then
		-- the road's bevel down to the grass is gravel too (T-184)
		return if a - half <= lipWidth(w) or self:gravelAt(s, side) then Spline.GRAVEL else Spline.GRASS
	end
	if self:edgeAt(s, side) == Spline.CLIFF then
		return nil
	end
	return Spline.GRASS
end

--------------------------------------------------------------------------------
-- Where is a point: (x, z) -> (s, d)
--------------------------------------------------------------------------------

-- Newton's method on "the offset from the centre line has no forward part". From a hint
-- within a few tens of studs it lands in two or three steps. Returns nil if it wanders
-- off the laid road.
function Spline.projectFrom(self: Spline, x: number, z: number, sHint: number): (number?, number?)
	local s = sHint
	local first = self.firstSample * self.step
	for _ = 1, 8 do
		if s < first then
			s = first
		elseif s > self.length then
			s = self.length
		end
		local cx, cz = self:planAt(s)
		local yaw = self:yawAt(s)
		local fx, fz = -math.sin(yaw), -math.cos(yaw)
		local ex, ez = x - cx, z - cz
		local along = ex * fx + ez * fz
		local d = ex * math.cos(yaw) - ez * math.sin(yaw)
		local stretch = 1 + self:curvatureAt(s) * d
		if stretch < 0.2 then
			stretch = 0.2 -- past the centre of curvature: no road there anyway
		end
		local ds = along / stretch
		-- never jump further than the hint could be wrong by
		if ds > 40 then
			ds = 40
		elseif ds < -40 then
			ds = -40
		end
		s += ds
		if math.abs(ds) < 1e-6 then
			if s < first - 1e-6 or s > self.length + 1e-6 then
				return nil, nil
			end
			return s, d
		end
	end
	if s < first or s > self.length then
		return nil, nil
	end
	-- NOT CONVERGED IS NOT FOUND. A hint hundreds of studs out walks the clamped steps and
	-- runs out of them part way; the lateral at wherever it stopped is meaningless, and
	-- answering with it put the ground 21 studs out (measured). The caller searches instead.
	local cx, cz = self:planAt(s)
	local yaw = self:yawAt(s)
	local ex, ez = x - cx, z - cz
	if math.abs(ex * -math.sin(yaw) + ez * -math.cos(yaw)) > 1e-3 then
		return nil, nil
	end
	return s, ex * math.cos(yaw) - ez * math.sin(yaw)
end

-- With no hint: the nearest filed point in the cells round (x, z), then Newton from it.
-- `reach` is how far from the centre line a point may be and still be found.
function Spline.project(self: Spline, x: number, z: number, reach: number?): (number?, number?)
	local r = reach or Config.Road.Width
	local cell = self.cell
	local cx0, cx1 = math.floor((x - r) / cell), math.floor((x + r) / cell)
	local cz0, cz1 = math.floor((z - r) / cell), math.floor((z + r) / cell)
	local first = self.firstSample * self.step
	local best, bestS = math.huge, nil :: number?
	for cx = cx0, cx1 do
		for cz = cz0, cz1 do
			local list = self.hash[hashKey(cx, cz)]
			if list then
				for j = 1, #list, 3 do
					local s = list[j]
					if s >= first then
						local dx, dz = list[j + 1] - x, list[j + 2] - z
						local dd = dx * dx + dz * dz
						if dd < best then
							best, bestS = dd, s
						end
					end
				end
			end
		end
	end
	if not bestS then
		return nil, nil
	end
	local s, d = self:projectFrom(x, z, bestS)
	if s and d and math.abs(d) <= r then
		return s, d
	end
	return nil, nil
end

-- The ground under (x, z): where along, how far across, the surface height and its
-- normal. The question the car asks four times a step.
function Spline.ground(self: Spline, x: number, z: number, sHint: number?): (number?, number?, number?, Vector3?)
	local s, d
	if sHint then
		s, d = self:projectFrom(x, z, sHint)
	else
		s, d = self:project(x, z)
	end
	if not s or not d then
		return nil, nil, nil, nil
	end
	local y = self:heightAt(s) + d * math.tan(self:bankAt(s))
	return s, d, y, self:normalAt(s, d)
end

--------------------------------------------------------------------------------
-- Old road near a point, for the no-crossing test
--------------------------------------------------------------------------------

-- Is any filed point of the road within `clear` of (x, z), other than those within `sep`
-- of `s` along the road? Returns the s of the first offender.
function Spline.crowded(self: Spline, x: number, z: number, s: number, clear: number, sep: number): number?
	local cell = self.cell
	local c2 = clear * clear
	local cx0, cx1 = math.floor((x - clear) / cell), math.floor((x + clear) / cell)
	local cz0, cz1 = math.floor((z - clear) / cell), math.floor((z + clear) / cell)
	for cx = cx0, cx1 do
		for cz = cz0, cz1 do
			local list = self.hash[hashKey(cx, cz)]
			if list then
				for j = 1, #list, 3 do
					local so = list[j]
					if math.abs(s - so) > sep then
						local dx, dz = list[j + 1] - x, list[j + 2] - z
						if dx * dx + dz * dz < c2 then
							return so
						end
					end
				end
			end
		end
	end
	return nil
end

-- The state at the end of the road, which a generator plans the next section from.
function Spline.tip(self: Spline): (number, number, number, number, number, number, number)
	local s = self.length
	local x, z = self:planAt(s)
	return x, z, self:yawAt(s), self:curvatureAt(s), self:gradeAt(s), self:bankAt(s), self:heightAt(s)
end

return Spline
