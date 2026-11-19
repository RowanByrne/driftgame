--!strict
--!native
-- Road/Range: the mountain range a ground run crosses (features/mountain-range.md, T-233).
-- Pure maths, no instances: the same on the server and on every client, from the seed.
--
-- THE RUN'S FRAME. `t` is studs on along the way the run goes (the old fall line's
-- downhill, so a range run sets off the same way a belts run did), `v` studs across it, to
-- the left of... whichever: `world` turns (t, v) back into x and z.
--
-- RIDGES lie across the way. Ridge k's crest runs along `ridgeT(k, v)`: about
-- `Spacing` studs after ridge k - 1, wandering a little across the range. Along its crest it
-- rises to peaks and dips to saddles (`crest`). VALLEY k lies between ridge k and ridge
-- k + 1, its floor `ValleyAt` of the way across (`floor`). A point belongs to one face: the
-- forward face of the ridge behind it, or the back face of the ridge ahead, whichever side
-- of the valley floor it is on, and its height is that face's profile between the crest and
-- the floor. So the range is continuous everywhere: two faces meet at a crest with the
-- crest's height (rounded over `CrestRound`), and at a valley floor with the floor's, both
-- flat there.
--
-- Heights are from the floor of valley -1, the one the run starts in (`Ground` adds the
-- road's start height). Its floor is at the start: `shift` moves the ridges along so the
-- start is on it, square across from where the road begins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Seed7Relief = require(script.Parent.Seed7Relief)

local Range = {}

export type Ridge = {
	t: number, -- where the crest is, before it wanders
	peak: number, -- its peaks' height, and how far its saddles dip below them
	depth: number,
	wob: number, -- noise offsets: the crest's wander, its saddles
	sad: number,
	-- valley k, after this ridge and before the next
	p: number, -- the floor, this much of the way from this ridge to the next
	base: number, -- the floor's height, and its noise offset
	flo: number,
	qa: number, -- this ridge's forward face, and the next one's back face: the exponent...
	qb: number,
	fa: number, -- ...and how much of each is flat at the floor
	fb: number,
}

export type Range = {
	seed: number,
	ox: number,
	oz: number,
	ux: number, -- the way on, a unit vector in plan
	uz: number,
	shift: number, -- added to `t`, so the start is on valley -1's floor
	ridges: { [number]: Ridge },
	basins: Seed7Relief.Cache?, -- the branching stream beds in the Studio seed 7 study
}

-- What `shape` says of a point: its height, how far up its face it is (0 on the valley
-- floor, 1 at the crest), how far it is from that crest (studs, along the way), which
-- ridge that is, and how near that ridge is to a saddle there (0 at a peak, 1 at a saddle).
-- Then the face's floor and crest heights.
export type Shape = {
	y: number,
	up: number,
	crest: number,
	ridge: number,
	saddle: number,
	floor: number,
	top: number,
}

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function ridge(r: Range, k: number): Ridge
	local got = r.ridges[k]
	if got then
		return got
	end
	local R = Config.Range
	local rng = Random.new((r.seed * 7919 + (k + 65536) * 104729) % 2147483647)
	local function between(a: { number }): number
		return a[1] + (a[2] - a[1]) * rng:NextNumber()
	end
	local rd: Ridge = {
		t = (k + 0.5) * R.Spacing + R.Jitter * (2 * rng:NextNumber() - 1),
		peak = between(R.Peak),
		depth = between(R.SaddleDepth),
		wob = rng:NextNumber() * 64, -- (small: math.noise steps visibly far from its origin)
		sad = rng:NextNumber() * 64,
		p = between(R.ValleyAt),
		base = between(R.ValleyBase),
		flo = rng:NextNumber() * 64,
		qa = between(R.Profile),
		qb = between(R.Profile),
		fa = between(R.Floor),
		fb = between(R.Floor),
	}
	if k == -1 then
		rd.base = 0 -- the start valley's floor is the range's zero
	end
	r.ridges[k] = rd
	return rd
end

-- Where ridge k's crest is at `v` across (in the range's own `t`, after `shift`).
function Range.ridgeT(r: Range, k: number, v: number): number
	local R = Config.Range
	local rd = ridge(r, k)
	return rd.t + R.Wobble[1] * 2 * math.noise(v / R.Wobble[2] + rd.wob, 0.37, 0.61)
end

-- Ridge k's crest height at `v` across, and how near a saddle it is there (0 to 1).
function Range.crest(r: Range, k: number, v: number): (number, number)
	local R = Config.Range
	local rd = ridge(r, k)
	-- a saddle every `SaddleEvery` or so: a wave along the crest, its spacing wandering
	-- (`SaddleWarp`), each dip as deep as `depth` give or take 30% (noise alone left some
	-- ridges with no saddle for 8 000 studs)
	local phase = 2 * math.pi * (v / R.SaddleEvery + R.SaddleWarp * math.noise(v / (2 * R.SaddleEvery) + rd.sad, 0.13, 0.77))
	local s = smooth(math.clamp(0.5 + 0.5 * R.SaddleSharp * math.sin(phase), 0, 1))
	local deep = 1 + 0.6 * math.noise(v / (0.7 * R.SaddleEvery) + rd.sad * 1.7, 0.51, 0.23)
	-- no lower than `SaddleMin`, eased into it over `SaddleEase` (a hard floor left flat crests)
	local tall = rd.peak * (1 + R.PeakVary[1] * 2 * math.noise(v / R.PeakVary[2] + rd.wob * 0.7, 0.83, 0.17))
	local a, b, e = tall - rd.depth * deep * s, R.SaddleMin, R.SaddleEase
	local y = 0.5 * (a + b + math.sqrt((a - b) * (a - b) + e * e))
	return if r.basins then Seed7Relief.crest(y) else y, s
end

-- Valley k's floor (between ridge k and ridge k + 1) at `v` across.
function Range.floor(r: Range, k: number, v: number): number
	local R = Config.Range
	local rd = ridge(r, k)
	return rd.base + R.FloorVary * 2 * math.noise(v / R.FloorEvery + rd.flo, 0.29, 0.43)
end

function Range.new(seed: number, ox: number, oz: number, ux: number, uz: number): Range
	local r: Range = { seed = seed, ox = ox, oz = oz, ux = ux, uz = uz, shift = 0, ridges = {} }
	if seed == 7 and RunService:IsStudio() and Config.Road.StudioSeed7Drive then
		r.basins = {}
	end
	-- the start square across from valley -1's floor
	local a, b = Range.ridgeT(r, -1, 0), Range.ridgeT(r, 0, 0)
	r.shift = a + ridge(r, -1).p * (b - a)
	return r
end

-- (x, z) in the run's frame, and back.
function Range.frame(r: Range, x: number, z: number): (number, number)
	local dx, dz = x - r.ox, z - r.oz
	return dx * r.ux + dz * r.uz, dx * r.uz - dz * r.ux
end

function Range.world(r: Range, t: number, v: number): (number, number)
	return r.ox + t * r.ux + v * r.uz, r.oz + t * r.uz - v * r.ux
end

-- Which valley a point is in: the ridge behind it (k), where that crest is and where the
-- next one is. `tt` is in the range's own `t` (after `shift`).
local function locate(r: Range, tt: number, v: number): (number, number, number)
	local S = Config.Range.Spacing
	local k = math.floor(tt / S - 0.5)
	local t0 = Range.ridgeT(r, k, v)
	while t0 > tt do
		k -= 1
		t0 = Range.ridgeT(r, k, v)
	end
	local t1 = Range.ridgeT(r, k + 1, v)
	while t1 <= tt do
		k += 1
		t0 = t1
		t1 = Range.ridgeT(r, k + 1, v)
	end
	return k, t0, t1
end

type Column = { floor: number, left: number, leftSaddle: number, right: number, rightSaddle: number }

local function face(r: Range, tt: number, v: number, k: number, t0: number, t1: number, col: Column?): (number, number, number, number, number, number, number)
	local R = Config.Range
	local rd = ridge(r, k)
	local gap = t1 - t0
	local a = tt - t0
	local F = if col then col.floor else Range.floor(r, k, v)
	local kc, d, L, q, fl
	if a <= rd.p * gap then
		kc, d, L, q, fl = k, a, rd.p * gap, rd.qa, rd.fa
	else
		kc, d, L, q, fl = k + 1, t1 - tt, (1 - rd.p) * gap, rd.qb, rd.fb
	end
	local C, s
	if col then
		if kc == k then C, s = col.left, col.leftSaddle else C, s = col.right, col.rightSaddle end
	else
		C, s = Range.crest(r, kc, v)
	end
	local c = R.CrestRound
	local dr = math.sqrt(d * d + c * c) - c
	local x = math.clamp(dr / math.max(L * (1 - fl), 1), 0, 1)
	local up = (1 - x) ^ q
	if r.basins and up > 0 then
		local side = if kc == k then 1 else -1
		local y, incisedUp = Seed7Relief.face(r.basins, r.seed, kc, side, v, d, up, s, F, C)
		return y, incisedUp, d, kc, s, F, C
	end
	return F + (C - F) * up, up, d, kc, s, F, C
end

-- The range at a point in its frame (`t` before `shift`).
function Range.at(r: Range, t: number, v: number): (number, number, number, number, number, number, number)
	local tt = t + r.shift
	local k, t0, t1 = locate(r, tt, v)
	return face(r, tt, v, k, t0, t1, nil)
end

-- Along one line of a terrain survey, ridge positions, crest and floor heights
-- stay the same until the line enters the next valley. Evaluate the same profile.
function Range.column(r: Range, v: number): (number) -> (number, number)
	local k, t0, t1 = 0, math.huge, -math.huge
	local col: Column = { floor = 0, left = 0, leftSaddle = 0, right = 0, rightSaddle = 0 }
	return function(t: number): (number, number)
		local tt = t + r.shift
		if tt < t0 or tt >= t1 then
			k, t0, t1 = locate(r, tt, v)
			col.floor = Range.floor(r, k, v)
			col.left, col.leftSaddle = Range.crest(r, k, v)
			col.right, col.rightSaddle = Range.crest(r, k + 1, v)
		end
		local y, up = face(r, tt, v, k, t0, t1, col)
		return y, up
	end
end

-- The same, from x and z, as a table (for what wants every part of it).
function Range.shape(r: Range, x: number, z: number): Shape
	local t, v = Range.frame(r, x, z)
	local y, up, d, kc, s, F, C = Range.at(r, t, v)
	return { y = y, up = up, crest = d, ridge = kc, saddle = s, floor = F, top = C }
end

-- Ridge k's saddles between `v0` and `v1` across: each low point of its crest with the crest
-- rising at least `SaddleRise` studs on both sides within `SaddleSpan`, as {v, y}.
function Range.saddles(r: Range, k: number, v0: number, v1: number): { { number } }
	local R = Config.Range
	local step = R.PassStep
	local span = math.ceil(R.SaddleSpan / step)
	local first = v0 - span * step
	local ys = {}
	local n = math.floor((v1 - v0) / step) + 2 * span + 1
	for i = 1, n do
		ys[i] = (Range.crest(r, k, first + (i - 1) * step))
	end
	local out = {}
	for i = span + 1, n - span do
		local y = ys[i]
		if y < ys[i - 1] and y <= ys[i + 1] then
			local hl, hr = -math.huge, -math.huge
			for j = 1, span do
				hl = math.max(hl, ys[i - j])
				hr = math.max(hr, ys[i + j])
			end
			if math.min(hl, hr) - y >= R.SaddleRise then
				table.insert(out, { first + (i - 1) * step, y })
			end
		end
	end
	return out
end

-- The ridge ahead of (x, z): the next crest on along the way.
function Range.ridgeAhead(r: Range, x: number, z: number): number
	local t, v = Range.frame(r, x, z)
	return locate(r, t + r.shift, v) + 1
end

-- The pass the road should head for from (x, z): on the next ridge ahead, the saddle within
-- `PassWindow` studs either way across whose height plus `PassLean` a stud off to the side is
-- least (the lowest of the crest there, if it has no saddle in the window). Returns where it
-- is (x, z), its height and which ridge it is on.
function Range.passAhead(r: Range, x: number, z: number): (number, number, number, number)
	local R = Config.Range
	local t, v = Range.frame(r, x, z)
	local k = locate(r, t + r.shift, v)
	local ahead = k + 1
	local best, bv, by = math.huge, v, 0
	local list = Range.saddles(r, ahead, v - R.PassWindow, v + R.PassWindow)
	if #list == 0 then
		local step = R.PassStep
		for q = v - R.PassWindow, v + R.PassWindow, step do
			table.insert(list, { q, (Range.crest(r, ahead, q)) })
		end
	end
	for _, sd in list do
		local cost = sd[2] + R.PassLean * math.abs(sd[1] - v)
		if cost < best then
			best, bv, by = cost, sd[1], sd[2]
		end
	end
	local px, pz = Range.world(r, Range.ridgeT(r, ahead, bv) - r.shift, bv)
	return px, pz, by, ahead
end

return Range
