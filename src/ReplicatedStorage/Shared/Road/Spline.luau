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
}

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

function Spline.append(self: Spline, sec: Section)
	local s0 = self.length
	local s1 = s0 + sec.len
	for _, knots in { sec.k, sec.g, sec.b } do
		assert(#knots >= 2 and math.abs(knots[#knots - 1] - sec.len) < 1e-6, "Spline: every track must end on a knot at the section's end")
	end
	appendTrack(self.curv, self.yawK, s0, sec.k)
	appendTrack(self.grade, self.yK, s0, sec.g)
	appendTrack(self.bank, nil, s0, sec.b)
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
	local cx, cz = self:planAt(s)
	local yaw = self:yawAt(s)
	return s, (x - cx) * math.cos(yaw) - (z - cz) * math.sin(yaw)
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
