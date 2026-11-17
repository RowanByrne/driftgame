--!strict
-- Hairpins: the spline road's hairpins, known ahead of the car, for the conditional score
-- events (features/score-events.md "The user's revision", T-299): perfect hairpin, reverse
-- entry, and the Scandinavian flick built on this next. Pure maths, like `Road/Spline`.
--
-- WHAT A HAIRPIN IS HERE. The road already knows its tight stretches: wherever it is
-- tighter than `Config.Road.CentreLineRadius` (130 studs), which is where the double yellow
-- is drawn (`Road/RoadTexture.centreRuns`). A hairpin is ONE BEND of that: a run of points
-- tighter than that radius, all turning the same way, read on the double yellow's own grid
-- (`CentreLineStep` studs). A switchback's two bends share one double yellow but are two
-- hairpins here, one each way. Two same-way tight runs closer than `MergeGap` are one
-- hairpin (a bend whose curvature wavers on the line), and a bend turning less than
-- `MinTurnDegrees` inside its tight part is not a hairpin at all (a short tight kink).
--
--   zone    where the ENTRY ZONE starts: `EntryZone` studs before `entry`, cut short at the
--           tight point of a bend just before it (a switchback's first bend), so zones never
--           overlap another hairpin
--   entry   the first point tighter than the radius
--   apex    where half the hairpin's turn is done
--   exit    the last point tighter than the radius
--   dir     which way it turns: 1 LEFT, -1 RIGHT (the curve's own sign: curvature > 0 is left)
--   radius  the tightest radius in it, studs
--   turn    degrees turned from entry to exit
--   open    the road is not laid far enough past it yet to know where it ends; ask again
--
-- THE SAME ANSWER FOR ANY CHUNK, ANY DEVICE. A hairpin is found by walking the fixed grid
-- outward from any one of its tight points to both ends, never from a window's edge, so
-- whatever point of it is asked about, the answer is the same numbers to the bit.
--
-- THE DOUBLE YELLOW is drawn about the centre line (`Road/SplineMesh`): two lines of
-- `CentreLineWidth`, `CentreLineGap` apart. `lineAt` is where its middle is across the road
-- (d, studs right of the centre line) at any distance, nil where none is drawn; `sideOf`
-- which side of it a point is on.
--
-- The tuning numbers below are the module's own defaults until `Config/ScoreEvents` exists
-- (T-295); they are read through `Hairpins.Tuning` so a config can replace them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Hairpins = {}

Hairpins.Tuning = {
	EntryZone = 60, -- studs before a hairpin's entry where its entry zone starts
	MergeGap = 20, -- studs: same-way tight runs closer than this are one hairpin
	MinTurnDegrees = 45, -- a tight bend turning less than this (inside its tight part) is not a hairpin
	MaxLength = 2000, -- studs: a walk along one hairpin stops here (a guard, not a tuning number)
}

export type Hairpin = {
	zone: number,
	entry: number,
	apex: number,
	exit: number,
	dir: number,
	radius: number,
	turn: number,
	open: boolean,
}

local function grid(): (number, number)
	local R = Config.Road
	return R.CentreLineStep, 1 / R.CentreLineRadius
end

-- 0 if the grid point `i` is not tight (or off the laid road), else which way it turns
local function tightAt(spline: any, i: number, step: number, kMin: number): number
	local s = i * step
	if s < 0 or s > spline.length then
		return 0
	end
	local k = spline:curvatureAt(s)
	if k >= kMin then
		return 1
	elseif k <= -kMin then
		return -1
	end
	return 0
end

-- The hairpin holding the tight grid point `i` (turning `dir`), or nil if that bend is not
-- one (it turns too little). Walks out to both ends, closing same-way gaps under MergeGap.
local function component(spline: any, i: number, dir: number): Hairpin?
	local T = Hairpins.Tuning
	local step, kMin = grid()
	local nMerge = math.max(1, math.round(T.MergeGap / step))
	local nMax = math.ceil(T.MaxLength / step)
	local open = false
	-- backward
	local a = i
	while i - a < nMax do
		local found = nil
		for g = 1, nMerge do
			local j = a - g
			if j * step < 0 then
				break
			end
			local t = tightAt(spline, j, step, kMin)
			if t == dir then
				found = j
				break
			elseif t ~= 0 then
				break
			end
		end
		if not found then
			break
		end
		a = found
	end
	-- forward
	local b = i
	while b - i < nMax do
		local found = nil
		for g = 1, nMerge do
			local j = b + g
			if j * step > spline.length then
				open = true -- the road ends inside the look: it may yet go on
				break
			end
			local t = tightAt(spline, j, step, kMin)
			if t == dir then
				found = j
				break
			elseif t ~= 0 then
				break
			end
		end
		if not found then
			break
		end
		b = found
	end
	local entry, exit = a * step, b * step
	local y0, y1 = spline:yawAt(entry), spline:yawAt(exit)
	local turn = math.deg(math.abs(y1 - y0))
	if turn < T.MinTurnDegrees and not open then
		return nil
	end
	local kTop = 0
	for j = a, b do
		kTop = math.max(kTop, math.abs(spline:curvatureAt(j * step)))
	end
	-- the apex: half the turn done (bisection on the heading)
	local half = (y0 + y1) * 0.5
	local lo, hi = entry, exit
	for _ = 1, 24 do
		local m = (lo + hi) * 0.5
		local y = spline:yawAt(m)
		if (y - half) * dir < 0 then
			lo = m
		else
			hi = m
		end
	end
	-- the entry zone: back `EntryZone`, but not onto another bend's tight point
	local nZone = math.round(T.EntryZone / step)
	local z = math.max(a - nZone, 0)
	for j = a - 1, a - nZone, -1 do
		if j < 0 then
			break
		end
		if tightAt(spline, j, step, kMin) ~= 0 then
			z = j + 1
			break
		end
	end
	return {
		zone = z * step,
		entry = entry,
		apex = (lo + hi) * 0.5,
		exit = exit,
		dir = dir,
		radius = if kTop > 0 then 1 / kTop else math.huge,
		turn = turn,
		open = open,
	}
end

-- The hairpin whose entry zone or bend holds `s` (zone <= s <= exit), or nil.
function Hairpins.around(spline: any, s: number): Hairpin?
	local step, kMin = grid()
	local i = math.round(s / step)
	local t = tightAt(spline, i, step, kMin)
	if t ~= 0 then
		return component(spline, i, t)
	end
	-- not on a tight point: the next one ahead, if `s` is in its zone (or in a merged gap
	-- inside it). The zone is never longer than `EntryZone`, so that is as far as to look.
	local nZone = math.round(Hairpins.Tuning.EntryZone / step)
	for g = 1, nZone do
		local tg = tightAt(spline, i + g, step, kMin)
		if tg ~= 0 then
			local h = component(spline, i + g, tg)
			if h and h.zone <= s and s <= h.exit then
				return h
			end
			return nil
		end
	end
	return nil
end

-- Every hairpin whose zone-to-exit overlaps [s0, s1], in order along the road. The same
-- hairpins, with the same numbers, whatever window is asked.
function Hairpins.find(spline: any, s0: number, s1: number): { Hairpin }
	local step, kMin = grid()
	local nZone = math.round(Hairpins.Tuning.EntryZone / step)
	local out = {}
	local i = math.floor(s0 / step)
	-- a hairpin whose bend started before s0 still counts: start from its own tight point
	local first = Hairpins.around(spline, s0)
	if first then
		table.insert(out, first)
		i = math.floor(first.exit / step) + 1
	end
	local i1 = math.ceil(s1 / step) + nZone
	while i <= i1 do
		local t = tightAt(spline, i, step, kMin)
		if t ~= 0 then
			local h = component(spline, i, t)
			if h then
				if h.zone <= s1 and h.exit >= s0 then
					table.insert(out, h)
				end
				i = math.floor(h.exit / step) + 1
			else
				-- not a hairpin: skip its tight run
				while tightAt(spline, i, step, kMin) == t do
					i += 1
				end
			end
		else
			i += 1
		end
	end
	return out
end

-- The double yellow's middle across the road at `s` (d, studs right of the centre line),
-- or nil where no double yellow is drawn.
function Hairpins.lineAt(spline: any, s: number): number?
	local R = Config.Road
	if R.CentreLineStyle ~= "tight" then
		return nil
	end
	local step = R.CentreLineStep
	local RoadTexture = require(script.Parent.RoadTexture) :: any
	local runs = RoadTexture.centreRuns(spline, s - step, s + step)
	for r = 1, #runs, 2 do
		if s >= runs[r] and s <= runs[r + 1] then
			return 0
		end
	end
	return nil
end

-- Half the double yellow's painted width: its middle to the outer edge of either line.
function Hairpins.lineHalfWidth(): number
	local R = Config.Road
	return R.CentreLineGap * 0.5 + R.CentreLineWidth
end

-- Which side of the double yellow a point `d` studs right of the centre line is on, at a
-- line whose middle is at `lineD`: -1 left of it, 1 right of it, 0 on the paint.
function Hairpins.sideOf(d: number, lineD: number?): number
	local off = d - (lineD or 0)
	local hw = Hairpins.lineHalfWidth()
	if off > hw then
		return 1
	elseif off < -hw then
		return -1
	end
	return 0
end

-- Where a world point is along and across the road: (s, d), from a hint when there is one
-- (`Spline.projectFrom`), else by search. nil off the road's reach.
function Hairpins.locate(spline: any, pos: Vector3, hint: number?): (number?, number?)
	local s, d
	if hint then
		s, d = spline:projectFrom(pos.X, pos.Z, hint)
	end
	local reach = Config.Road.Width * 0.5 + 60
	if not s or not d or math.abs(d) > reach then
		s, d = spline:project(pos.X, pos.Z, reach)
	end
	return s, d
end

-- The road's plan right at `s`, (x, z): what turns a world offset into studs across.
function Hairpins.rightAt(spline: any, s: number): (number, number)
	local yaw = spline:yawAt(s)
	return math.cos(yaw), -math.sin(yaw)
end

return Hairpins
