--!strict
-- Hairpins: the spline road's double-yellow bends and, among them, its true hairpins, known
-- ahead of the car, for the conditional score events (features/score-events.md, T-299):
-- lane drift and perfect lane drift on every bend, perfect hairpin on the hairpins, reverse
-- entry, and the Scandinavian flick. Pure maths, like `Road/Spline`.
--
-- A BEND. The road knows its tight stretches: wherever it is tighter than
-- `Config.Road.CentreLineRadius` (130 studs), which is where the double yellow is drawn
-- (`Road/RoadTexture.centreRuns`). A bend is ONE BEND of that: a run of points tighter than
-- that radius, all turning the same way, read on the double yellow's own grid
-- (`CentreLineStep` studs). A switchback's two bends share one double yellow but are two
-- bends here, one each way. Same-way tight runs closer than `MergeGap` are one bend, and a
-- run turning less than `MinTurnDegrees` inside its tight part is not one (a tight kink).
--
-- A HAIRPIN (the user, T-299 send-back: "to be a hairpin we need at least 120 degrees within
-- a certain stretch") is a bend where the road turns at least `HairpinDegrees` (120) the
-- bend's way within `HairpinStretch` (250) studs, the window overlapping the bend: a mean
-- radius of 119 or less. 200 studs (radius 95) was measured first and left out the
-- generator's own wide turnarounds (174 degrees at radius 98 turns 115 within 200 studs, 139
-- within 250). Measured at 250 on seeds 31337, 101, 2024, 8080 and 777: 12, 7, 13, 12 and 7
-- of 20 to 36 bends in 30 000 studs, one every ~3 000 studs.
--
--   zone    where the ENTRY ZONE starts: `EntryZone` studs before `entry`, cut short at the
--           tight point of a bend just before it (a switchback's first bend), so zones never
--           overlap another bend
--   entry   the first point tighter than the radius
--   apex    where half the bend's tight turn is done
--   exit    the last point tighter than the radius
--   dir     which way it turns: 1 LEFT, -1 RIGHT (the curve's own sign: curvature > 0 is left)
--   radius  the tightest radius in it, studs
--   turn    degrees turned from entry to exit
--   hairpin it is a true hairpin; `hairpinTurn` the most it turns within `HairpinStretch`
--   open    the road is not laid far enough past it yet to know it all; ask again
--
-- `bendAround` / `bends` answer every bend; `around` / `find` only the true hairpins.
--
-- THE SAME ANSWER FOR ANY CHUNK, ANY DEVICE. A bend is found by walking the fixed grid
-- outward from any one of its tight points to both ends, never from a window's edge, so
-- whatever point of it is asked about, the answer is the same numbers to the bit.
--
-- THE LINES. The double yellow is drawn about the centre line (`Road/SplineMesh`): two lines
-- of `CentreLineWidth`, `CentreLineGap` apart. `lineAt` is where its middle is across the
-- road (d, studs right of the centre line) at any distance, nil where none is drawn; `sideOf`
-- which side of it a point is on. `edgeLine` is how far out the white edge lines' outer
-- sides are (`Config.Road.EdgeLineInset` in from the tarmac's edge).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Hairpins = {}

Hairpins.Tuning = {
	EntryZone = 60, -- studs before a bend's entry where its entry zone starts
	MergeGap = 20, -- studs: same-way tight runs closer than this are one bend
	MinTurnDegrees = 45, -- a tight run turning less than this (inside its tight part) is not a bend
	HairpinDegrees = 120, -- a bend turning this much within `HairpinStretch` is a hairpin
	HairpinStretch = 250, -- studs
	MaxLength = 2000, -- studs: a walk along one bend stops here (a guard, not a tuning number)
}

export type Hairpin = {
	zone: number,
	entry: number,
	apex: number,
	exit: number,
	dir: number,
	radius: number,
	turn: number,
	hairpin: boolean,
	hairpinTurn: number,
	open: boolean,
}

-- Closed bends already worked out, per road, by their first grid point: the walk out to a
-- bend's ends is cheap, the rest (its turn, apex, zone, the hairpin test) is not.
local cache: { [any]: { [number]: Hairpin | false } } = setmetatable({}, { __mode = "k" }) :: any

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

-- The bend holding the tight grid point `i` (turning `dir`), or nil if that run is not one
-- (it turns too little). Walks out to both ends, closing same-way gaps under MergeGap.
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
	-- the hairpin test looks `HairpinStretch` past the exit: not known until that is laid
	if exit + T.HairpinStretch > spline.length then
		open = true
	end
	local known = cache[spline]
	if not open and known and known[a] ~= nil then
		return known[a] or nil
	end
	local y0, y1 = spline:yawAt(entry), spline:yawAt(exit)
	local turn = math.deg(math.abs(y1 - y0))
	if turn < T.MinTurnDegrees and not open then
		cache[spline] = known or {}
		cache[spline][a] = false
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
	-- the hairpin test: the most the road turns this bend's way within `HairpinStretch`, over
	-- windows on a fixed grid from `HairpinStretch` before the entry to the exit
	local L = T.HairpinStretch
	local best = 0
	local w = entry - L
	while w <= exit do
		local w0, w1 = math.max(w, 0), math.min(w + L, spline.length)
		best = math.max(best, (spline:yawAt(w1) - spline:yawAt(w0)) * dir)
		w += 2 * step
	end
	local hairpinTurn = math.deg(best)
	local h: Hairpin = {
		zone = z * step,
		entry = entry,
		apex = (lo + hi) * 0.5,
		exit = exit,
		dir = dir,
		radius = if kTop > 0 then 1 / kTop else math.huge,
		turn = turn,
		hairpin = hairpinTurn >= T.HairpinDegrees,
		hairpinTurn = hairpinTurn,
		open = open,
	}
	if not open then
		cache[spline] = known or {}
		cache[spline][a] = h
	end
	return h
end

-- The bend whose entry zone or tight stretch holds `s` (zone <= s <= exit), or nil.
function Hairpins.bendAround(spline: any, s: number): Hairpin?
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

-- The true hairpin whose entry zone or tight stretch holds `s`, or nil (a bend that is not
-- a hairpin answers nil). An open one is returned as such: ask again.
function Hairpins.around(spline: any, s: number): Hairpin?
	local h = Hairpins.bendAround(spline, s)
	if h and (h.hairpin or h.open) then
		return h
	end
	return nil
end

-- Every bend whose zone-to-exit overlaps [s0, s1], in order along the road. The same bends,
-- with the same numbers, whatever window is asked.
function Hairpins.bends(spline: any, s0: number, s1: number): { Hairpin }
	local step, kMin = grid()
	local nZone = math.round(Hairpins.Tuning.EntryZone / step)
	local out = {}
	local i = math.floor(s0 / step)
	-- a bend that started before s0 still counts: start from its own tight point
	local first = Hairpins.bendAround(spline, s0)
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
				-- not a bend: skip its tight run
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

-- Every true hairpin whose zone-to-exit overlaps [s0, s1] (and any open bend at the road's end).
function Hairpins.find(spline: any, s0: number, s1: number): { Hairpin }
	local out = {}
	for _, h in Hairpins.bends(spline, s0, s1) do
		if h.hairpin or h.open then
			table.insert(out, h)
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

-- How far out from the centre line the white edge lines' outer sides are (either side).
function Hairpins.edgeLine(): number
	local R = Config.Road
	return R.Width * 0.5 - R.EdgeLineInset
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
