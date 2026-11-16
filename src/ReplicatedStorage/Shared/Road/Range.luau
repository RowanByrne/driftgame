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

local Config = require(ReplicatedStorage.Shared.Config)

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
		wob = rng:NextNumber() * 4096,
		sad = rng:NextNumber() * 4096,
		p = between(R.ValleyAt),
		base = between(R.ValleyBase),
		flo = rng:NextNumber() * 4096,
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
	local n = math.noise(v / R.SaddleEvery + rd.sad, 0.13, 0.77)
	local s = smooth(math.clamp(0.5 + R.SaddleSharp * n, 0, 1))
	return math.max(rd.peak - rd.depth * s, R.SaddleMin), s
end

-- Valley k's floor (between ridge k and ridge k + 1) at `v` across.
function Range.floor(r: Range, k: number, v: number): number
	local R = Config.Range
	local rd = ridge(r, k)
	return rd.base + R.FloorVary * 2 * math.noise(v / R.FloorEvery + rd.flo, 0.29, 0.43)
end

function Range.new(seed: number, ox: number, oz: number, ux: number, uz: number): Range
	local r: Range = { seed = seed, ox = ox, oz = oz, ux = ux, uz = uz, shift = 0, ridges = {} }
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

-- The range at a point in its frame (`t` before `shift`).
function Range.at(r: Range, t: number, v: number): (number, number, number, number, number, number, number)
	local R = Config.Range
	local tt = t + r.shift
	local k, t0, t1 = locate(r, tt, v)
	local rd = ridge(r, k)
	local gap = t1 - t0
	local a = tt - t0
	local F = Range.floor(r, k, v)
	local kc, d, L, q, fl
	if a <= rd.p * gap then
		kc, d, L, q, fl = k, a, rd.p * gap, rd.qa, rd.fa
	else
		kc, d, L, q, fl = k + 1, t1 - tt, (1 - rd.p) * gap, rd.qb, rd.fb
	end
	local C, s = Range.crest(r, kc, v)
	local c = R.CrestRound
	local dr = math.sqrt(d * d + c * c) - c
	local x = math.clamp(dr / math.max(L * (1 - fl), 1), 0, 1)
	local up = (1 - x) ^ q
	return F + (C - F) * up, up, d, kc, s, F, C
end

-- The same, from x and z, as a table (for what wants every part of it).
function Range.shape(r: Range, x: number, z: number): Shape
	local t, v = Range.frame(r, x, z)
	local y, up, d, kc, s, F, C = Range.at(r, t, v)
	return { y = y, up = up, crest = d, ridge = kc, saddle = s, floor = F, top = C }
end

-- Ridge k's saddles between `v0` and `v1` across: each low point of its crest, as {v, y}.
function Range.saddles(r: Range, k: number, v0: number, v1: number): { { number } }
	local step = Config.Range.PassStep
	local out = {}
	local prev2, prev = math.huge, math.huge
	local v = v0 - step
	while v <= v1 + step do
		local y = Range.crest(r, k, v)
		if prev < prev2 and prev <= y and v - step >= v0 and v - step <= v1 then
			table.insert(out, { v - step, prev })
		end
		prev2, prev = prev, y
		v += step
	end
	return out
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
