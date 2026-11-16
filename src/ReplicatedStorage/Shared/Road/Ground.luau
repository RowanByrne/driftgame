--!strict
--!native
-- Road/Ground: the ground-first mountain (features/ground-trial.md, T-218). Pure maths, no
-- instances: the same on the server and on every client.
--
-- THE MOUNTAIN COMES FIRST. One height function of world position, `h(x, z)`: the mountain
-- range (`Road/Range`, T-233, features/mountain-range.md): ridges across the way the run
-- goes, passes, valleys, with seeded ridges and gullies on its faces that run down them
-- (`Config.Range.Octaves`, stretched along the fall line). It depends on the seed's origin
-- and fall line alone, so every device has the same mountain. (The single-slope "belts"
-- mountain of T-228 went in step 3 of features/legacy-removal.md.)
--
-- THE ROAD IS PRESSED INTO IT (`at`). Under the road and its runoff the ground sits just
-- below their surface (`Ground.Under`). Past the runoff's outer edge it blends back to `h`
-- over at most `BlendMax` studs: a CUT where the mountain is above the edge, a FILL where
-- it is below, as steep as the mountain is across the road there (`Ground.steepness`,
-- T-228): a slight lip and drop on shallow ground, a wall and a drop on steep. Between two
-- legs it is simply `h`, with nothing to negotiate.
--
-- HOW THE BLEND IS TAKEN, so it has no seams: every station of road near a point (the
-- points the road files for its no-crossing test, every `CheckStep` studs) answers for its
-- stretch of centre line to the next, from the point of it nearest (T-237): how far past
-- the edge the point is, and the road's height square beside it. The nearest edge wins,
-- smoothly (`Soft`), so the ground is continuous where two stretches meet (round a bend,
-- the inside of a hairpin, the gap between two legs), and the cut or fill ends an even
-- distance from the road all round a bend. A stretch's influence fades to nothing at the
-- end of its blend, so beyond it the ground is exactly `h`.
--
-- The road itself is unchanged: the car drives on the spline maths, and the road's height
-- follows h (`SplineGen._followGrade`), so the cuts and fills are the relief.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)
local Range = require(script.Parent.Range)

local Ground = {}

export type Octave = { size: number, amp: number, a: number, b: number, c: number, kind: string? }

export type Field = {
	seed: number,
	ox: number,
	oy: number,
	oz: number,
	ux: number, -- uphill, a unit vector in plan
	uz: number,
	stretch: number,
	oct: { Octave },
	baseZero: number, -- the range's height at the start, taken off so the start is on it
	zero: number, -- the relief at the origin, taken off so the road starts on the mountain
	-- THE RANGE (T-233, `Road/Range`): ridges across the way the run goes, passes, valleys
	range: Range.Range,
}

export type Station = {
	s: number,
	x: number,
	z: number,
	fx: number,
	fz: number,
	rx: number,
	rz: number,
	k: number, -- curvature
	yc: number, -- centre-line height
	g: number, -- grade, and how fast it changes per stud
	gr: number,
	tb: number, -- tan of the bank, and how fast it changes per stud
	tbr: number,
	wl: number, -- half the tarmac and the runoff, left
	wr: number,
	rl: number, -- the runoff alone, left
	rr: number,
	steep: number, -- how steep the mountain is across the road here, 0 to 1 (T-228)
	-- the next station's centre and half widths: this station answers for the centre line
	-- between the two (T-237)
	nx: number,
	nz: number,
	nwl: number,
	nwr: number,
	bmin: number, -- so the cut or fill past its runoff: no narrower than this...
	tanA: number, -- ...at about this slope
	-- the centre line `HEIGHT_STEP` studs apart, from `HEIGHT_REACH` before the station to as
	-- far after it: its height, where it is and which way it heads. A ground run's grade
	-- changes often and steeply (T-226), so how far along the road a point beside the station
	-- is, and the height there, are read from these, not carried on from the station alone
	-- (made the first time a point needs them: a turn's check asks few points of many stations)
	ys: { number }?,
	cxs: { number }?,
	czs: { number }?,
	fxs: { number }?,
	fzs: { number }?,
	spline: Spline.Spline,
}

export type Context = {
	field: Field,
	spline: Spline.Spline,
	cell: number,
	grid: { [number]: { Station } },
	count: number,
}

-- Who draws the runoff (T-251): `Config.Spline.Ground.RunoffBy`, "road" or "ground". In Studio
-- the workspace attribute `__runoff_by` overrides it, so the two can be compared in one
-- session: read when a road's drawing starts (a new run).
function Ground.runoffBy(): string
	if RunService:IsStudio() then
		local v = workspace:GetAttribute("__runoff_by")
		if v == "road" or v == "ground" then
			return v
		end
	end
	return Config.Spline.Ground.RunoffBy
end

--------------------------------------------------------------------------------
-- The mountain: h(x, z)
--------------------------------------------------------------------------------

-- The field for a road: its origin and its fall line (the uphill heading, as a yaw: forward
-- is (-sin, -cos)), the range, and offsets into the noise, all from the seed.
function Ground.field(seed: number, origin: Spline.Origin, fall: number): Field
	local R = Config.Range
	local rng = Random.new((seed * 29 + 5153) % 2 ^ 31)
	local oct: { Octave } = {}
	for _, o in R.Octaves do
		table.insert(oct, {
			size = o[1],
			amp = o[2],
			kind = o[3],
			-- (within 64: far from its origin math.noise steps, a tenth of a stud every third
			-- of a stud on the finest octave)
			a = rng:NextNumber() * 64,
			b = rng:NextNumber() * 64,
			c = rng:NextNumber() * 256 + 0.5, -- never a whole number: math.noise is 0 on the lattice
		})
	end
	local ux, uz = -math.sin(fall), -math.cos(fall)
	local f: Field = {
		seed = seed,
		ox = origin.x,
		oy = origin.y,
		oz = origin.z,
		ux = ux,
		uz = uz,
		stretch = R.Stretch,
		oct = oct,
		baseZero = 0,
		zero = 0,
		-- the way on is down the fall line
		range = Range.new(seed, origin.x, origin.z, -ux, -uz),
	}
	f.baseZero = Ground.base(f, origin.x, origin.z) - origin.y
	f.zero = Ground.relief(f, origin.x, origin.z)
	return f
end

-- The mountain without its ridges and gullies: the range.
function Ground.base(f: Field, x: number, z: number): number
	local r = f.range
	local t, v = Range.frame(r, x, z)
	return f.oy + (Range.at(r, t, v)) - f.baseZero
end

-- How much of the ridges and gullies there are: little on a valley floor, all of them from
-- `ReliefRise` up a face (`q`, 0 on the floor to 1 at the crest).
local function reliefShare(q: number): number
	local R = Config.Range
	local m = math.clamp(q / R.ReliefRise, 0, 1)
	return R.ReliefFloor + (1 - R.ReliefFloor) * m * m * (3 - 2 * m)
end

-- The ridges and gullies: noise in the fall line's own frame, stretched along it so they
-- run down the range's faces, which fall along it; `share` of them.
local function reliefAt(f: Field, x: number, z: number, share: number): number
	local dx, dz = x - f.ox, z - f.oz
	local u = dx * f.ux + dz * f.uz -- up the mountain
	local v = dx * f.uz - dz * f.ux -- across it
	local y = 0
	-- (each octave within its height either way: a ridge octave's trough went three times as
	-- deep as its crest stood, holes 300 studs deep on the lower faces)
	local cap = 0.5
	for _, o in f.oct do
		local n = math.noise(u / (o.size * f.stretch) + o.a, v / o.size + o.b, o.c)
		n = math.clamp(n, -cap, cap)
		if o.kind == "ridge" then
			y += o.amp * (1 - 4 * math.abs(n))
		elseif o.kind == "gully" then
			y += o.amp * (4 * math.abs(n) - 1)
		else
			y += o.amp * 2 * n
		end
	end
	return y * share - f.zero
end

function Ground.relief(f: Field, x: number, z: number): number
	local r = f.range
	local t, v = Range.frame(r, x, z)
	local _, up = Range.at(r, t, v)
	return reliefAt(f, x, z, reliefShare(up))
end

function Ground.h(f: Field, x: number, z: number): number
	local r = f.range
	local t, v = Range.frame(r, x, z)
	local y, up = Range.at(r, t, v)
	return f.oy + y - f.baseZero + reliefAt(f, x, z, reliefShare(up))
end

--------------------------------------------------------------------------------
-- Where you are on the range (T-233)
--------------------------------------------------------------------------------

export type Where = {
	kind: string, -- "pass", "ridge", "valley" or "face"
	height: number, -- 0 at the lowest valley floor to 1 at the highest peak the range can have
	slope: number, -- degrees, the steepest way across h here (over 24 studs)
	crest: number, -- studs to the nearest crest, along the way the run goes
	ridge: number, -- which ridge that is
	up: number, -- how far up its face, 0 on the valley floor to 1 at the crest
	saddle: number, -- how near that ridge is to a saddle here, 0 at a peak to 1 at a saddle
}

-- Where (x, z) is on the range: a pure function of the place, the same on every device, for
-- what later chooses the scenery from it (biomes: not built yet).
function Ground.where(f: Field, x: number, z: number): Where
	local e = 12
	local gx = (Ground.h(f, x + e, z) - Ground.h(f, x - e, z)) / (2 * e)
	local gz = (Ground.h(f, x, z + e) - Ground.h(f, x, z - e)) / (2 * e)
	local slope = math.deg(math.atan(math.sqrt(gx * gx + gz * gz)))
	local r = f.range
	local R = Config.Range
	local sh = Range.shape(r, x, z)
	local lo = R.ValleyBase[1] - R.FloorVary
	local hi = R.Peak[2]
	local kind = "face"
	if sh.crest <= R.PassReach and sh.saddle >= R.PassShare then
		kind = "pass"
	elseif sh.crest <= R.RidgeReach then
		kind = "ridge"
	elseif sh.up <= R.ValleyShare then
		kind = "valley"
	end
	return {
		kind = kind,
		height = math.clamp((sh.y - lo) / (hi - lo), 0, 1),
		slope = slope,
		crest = sh.crest,
		ridge = sh.ridge,
		up = sh.up,
		saddle = sh.saddle,
	}
end

-- The pass ahead of (x, z) the road should head for: where it is (x, z), its height (world)
-- and which ridge it is on.
function Ground.passAhead(f: Field, x: number, z: number): (number, number, number, number)
	local px, pz, py, k = Range.passAhead(f.range, x, z)
	return px, pz, f.oy + py - f.baseZero, k
end

--------------------------------------------------------------------------------
-- The road pressed in
--------------------------------------------------------------------------------

-- How far from a centre line the road can still change the ground: the widest runoff (a
-- grove's), the tarmac and the longest blend.
function Ground.reach(): number
	local G, T = Config.Spline.Ground, Config.Spline.Terrain
	return Config.Road.Width * 0.5 + math.max(T.RunoffMax, T.GroveRunoff[2]) + G.BlendMax
end

-- What a station is by itself is kept: only stations well short of the road's end, where
-- nothing laid later can change the runoff there.
local kept: { [Spline.Spline]: { [number]: Station } } = setmetatable({}, { __mode = "k" }) :: any
local KEEP_SHORT = 300 -- studs

local function lipWidth(w: number): number
	local T = Config.Spline.Terrain
	return math.min(T.RoadLipWidth, w * T.LipShare)
end

-- The road's own surface at `d` across a station: the tarmac, the gravel bevel, the
-- runoff easing flat (as `Spline.terrainY`, from the station's numbers).
-- `ds` studs along the road from the station: its height and bank carried on (to second
-- order), since a point beside a bend may be square to road some way along from it.
local HEIGHT_STEP = 8 -- studs
local HEIGHT_REACH = 64 -- studs
local HEIGHT_MID = HEIGHT_REACH // HEIGHT_STEP + 1

-- The centre line kept round a station (`ys`...), made the first time it is asked for.
local function line(st: Station): Station
	if st.ys then
		return st
	end
	local spline = st.spline
	local n = 2 * HEIGHT_MID - 1
	local ys, cxs, czs, fxs, fzs = table.create(n), table.create(n), table.create(n), table.create(n), table.create(n)
	local first = spline.firstSample * spline.step
	for i = 1, n do
		local at = st.s + (i - HEIGHT_MID) * HEIGHT_STEP
		-- past either end of the road (or of what is kept of it), carried on straight
		local c = math.clamp(at, first, spline.length)
		local cyaw = spline:yawAt(c)
		local cfx, cfz = -math.sin(cyaw), -math.cos(cyaw)
		local cx, cz = spline:planAt(c)
		ys[i] = spline:heightAt(c) + (at - c) * spline:gradeAt(c)
		cxs[i] = cx + (at - c) * cfx
		czs[i] = cz + (at - c) * cfz
		fxs[i] = cfx
		fzs[i] = cfz
	end
	st.ys, st.cxs, st.czs, st.fxs, st.fzs = ys, cxs, czs, fxs, fzs
	return st
end

local function surface(st: Station, d: number, ds: number?, near: boolean?): number
	local half = Config.Road.Width * 0.5
	local yc, tb = st.yc, st.tb
	if ds and near then
		-- within a station's own stretch (`CheckStep` studs): its grade carried on is within a
		-- hundredth of a stud there
		yc += ds * (st.g + 0.5 * st.gr * ds)
		tb += ds * st.tbr
	elseif ds then
		local q = ds / HEIGHT_STEP + HEIGHT_MID
		local i = math.floor(q)
		local ys = line(st).ys :: { number }
		if i >= 1 and i < #ys then
			-- between two of the heights kept round the station (a straight line between them
			-- is within a hundredth of a stud of the road at the steepest change of grade)
			yc = ys[i] + (ys[i + 1] - ys[i]) * (q - i)
		else
			yc += ds * (st.g + 0.5 * st.gr * ds)
		end
		tb += ds * st.tbr
	end
	local a = math.abs(d)
	if a <= half then
		return yc + d * tb
	end
	local side = if d < 0 then -1 else 1
	local w = if side < 0 then st.rl else st.rr
	local e = a - half
	local off
	if e >= w then
		off = w * 0.5
	else
		off = e - e * e / (2 * w)
	end
	local drop = 0
	if e > 0 and w > 0 then
		local lw = lipWidth(w)
		local lip = Config.Spline.Terrain.RoadLip
		drop = if e >= lw then lip else lip * e / lw
	end
	return yc + side * tb * (half + off) - drop
end
Ground._surface = surface

-- How steep the mountain is across a road at (x, z) heading right along (rx, rz): 0 on
-- shallow ground (under `SlopeShallow`), 1 on steep (over `SlopeSteep`), eased between
-- (T-228). The road's runoff and the cut and fill beside it both read this.
function Ground.steepness(f: Field, x: number, z: number, rx: number, rz: number): number
	local G = Config.Spline.Ground
	local D = G.SideSpan
	local t = math.abs(Ground.h(f, x + rx * D, z + rz * D) - Ground.h(f, x - rx * D, z - rz * D)) / (2 * D)
	local u = math.clamp((math.deg(math.atan(t)) - G.SlopeShallow) / (G.SlopeSteep - G.SlopeShallow), 0, 1)
	return u * u * (3 - 2 * u)
end

local function station(spline: Spline.Spline, s: number, x: number, z: number, field: Field): Station
	local mine = kept[spline]
	if not mine then
		mine = {}
		kept[spline] = mine
	end
	local old = mine[s]
	if old then
		return old
	end
	local half = Config.Road.Width * 0.5
	local yaw = spline:yawAt(s)
	local e = 2 -- studs either way, for the rates (the tracks are piecewise linear)
	local sa, sb = math.max(s - e, 0), math.min(s + e, spline.length)
	local span = math.max(sb - sa, 1e-6)
	local rl, rr = spline:runoffAt(s, -1), spline:runoffAt(s, 1)
	local st: Station = {
		s = s,
		x = x,
		z = z,
		fx = -math.sin(yaw),
		fz = -math.cos(yaw),
		rx = math.cos(yaw),
		rz = -math.sin(yaw),
		k = spline:curvatureAt(s),
		yc = spline:heightAt(s),
		g = spline:gradeAt(s),
		gr = (spline:gradeAt(sb) - spline:gradeAt(sa)) / span,
		tb = math.tan(spline:bankAt(s)),
		tbr = (math.tan(spline:bankAt(sb)) - math.tan(spline:bankAt(sa))) / span,
		wl = half + rl,
		wr = half + rr,
		rl = rl,
		rr = rr,
		steep = Ground.steepness(field, x, z, math.cos(yaw), -math.sin(yaw)),
		bmin = 0,
		tanA = 1,
		spline = spline,
		nx = x,
		nz = z,
		nwl = half + rl,
		nwr = half + rr,
	}
	do
		-- the stretch of centre line this station answers for: to the next one (T-237)
		local sn = math.min(s + spline.checkStep, spline.length)
		if sn > s then
			st.nx, st.nz = spline:planAt(sn)
			st.nwl, st.nwr = half + spline:runoffAt(sn, -1), half + spline:runoffAt(sn, 1)
		end
	end
	do
		local G = Config.Spline.Ground
		local q = st.steep
		st.bmin = G.BlendMins[1] + (G.BlendMins[2] - G.BlendMins[1]) * q
		st.tanA = math.tan(math.rad(G.BlendAngles[1] + (G.BlendAngles[2] - G.BlendAngles[1]) * q))
	end
	if s < spline.length - KEEP_SHORT then
		mine[s] = st
	end
	return st
end

local CELL = 64 -- studs: a point looks at the 25 cells round it (at 32, 81)

local function key(cx: number, cz: number): number
	return (cx + 1048576) * 2097152 + (cz + 1048576)
end

-- Gather the stations that can reach the box (x0, z0)..(x1, z1), filed in a grid of their
-- own so a point looks only at the few round it.
function Ground.context(field: Field, spline: Spline.Spline, x0: number, z0: number, x1: number, z1: number): Context
	local reach = Ground.reach()
	local ctx: Context = { field = field, spline = spline, cell = CELL, grid = {}, count = 0 }
	local hc = spline.cell
	local first = spline.firstSample * spline.step
	local seen: { [number]: boolean } = {}
	for cx = math.floor((x0 - reach) / hc), math.floor((x1 + reach) / hc) do
		for cz = math.floor((z0 - reach) / hc), math.floor((z1 + reach) / hc) do
			local list = spline.hash[(cx + 1048576) * 2097152 + (cz + 1048576)] -- `Spline`'s own key
			if list then
				for j = 1, #list, 3 do
					local s, x, z = list[j], list[j + 1], list[j + 2]
					if s >= first and not seen[s] and x >= x0 - reach and x <= x1 + reach and z >= z0 - reach and z <= z1 + reach then
						seen[s] = true
						local st = station(spline, s, x, z, field)
						local k = key(math.floor(x / CELL), math.floor(z / CELL))
						local cellList = ctx.grid[k]
						if not cellList then
							cellList = {}
							ctx.grid[k] = cellList
						end
						table.insert(cellList, st)
						ctx.count += 1
					end
				end
			end
		end
	end
	return ctx
end

local FADE = 12 -- studs

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- The ground's height at (x, z), and how much the road decides it there: 1 under the road
-- and its runoff, falling to 0 at the end of the blend (and wherever no road is near). Then
-- how far the point is past the nearest runoff's edge (0 on the road, huge with none near),
-- and the height the road would have the ground at there (the edge's, less `Under`).
function Ground.at(ctx: Context, x: number, z: number): (number, number, number, number)
	local G = Config.Spline.Ground
	local field = ctx.field
	local hp = Ground.h(field, x, z)
	local reach = Ground.reach()
	local soft = G.Soft
	-- (each station's own blend, from the mountain's side slope there: T-228)
	local bMax = G.BlendMax
	-- Running sums, rescaled whenever a nearer edge turns up (a soft minimum). What is
	-- averaged is each station's distance past its edge, its blend width and its target:
	-- the blend is taken once, from the averaged distance, so where neighbouring stations
	-- disagree a little about where the edge is (a bend, a runoff changing width) the
	-- smoothstep's flat foot absorbs it, and the ground never rises onto the runoff.
	local emin = math.huge
	local sw, swe, swb, swT = 0, 0, 0, 0
	local cell = ctx.cell
	local grid = ctx.grid
	for cx = math.floor((x - reach) / cell), math.floor((x + reach) / cell) do
		for cz = math.floor((z - reach) / cell), math.floor((z + reach) / cell) do
			local list = grid[key(cx, cz)]
			if list then
				for _, st in list do
					-- THE NEAREST POINT OF THE ROAD (T-237): each station answers for its stretch
					-- of centre line to the next, from the point on it nearest (x, z). So the
					-- distance past the edge is the true one all round a bend: the cut or fill
					-- ends an even distance from the road, and the inside of a tight hairpin is
					-- one bowl. (Until T-237 a station answered for the points square beside it,
					-- within `Look`: inside a hairpin the bend's reach ended in an arc and the
					-- legs' in straight lines, with a notch where they met.)
					-- The distance (`r`, so `e`, signed: under 0 on the road) is to the nearest
					-- point of the stretch; the height (`T`) is the road's square beside the point,
					-- along the stretch carried on (`ds`, `d`), so a station a little way along
					-- whose stretch ends short of the point still gives the road's height there.
					local vx, vz = st.nx - st.x, st.nz - st.z
					local L2 = vx * vx + vz * vz
					local dx, dz = x - st.x, z - st.z
					-- (across and along from the station's own heading: the stretch is a chord,
					-- a turn's half angle off it, which far out on a wide runoff is studs)
					local ds, d = dx * st.fx + dz * st.fz, dx * st.rx + dz * st.rz
					local L, u = 0, 0
					if L2 > 1e-9 then
						L = math.sqrt(L2)
						u = math.clamp((dx * vx + dz * vz) / L2, 0, 1)
					end
					local px, pz = dx - vx * u, dz - vz * u
					local r = math.sqrt(px * px + pz * pz)
					-- how far along the road the point really is: further than its square on
					-- the stretch on the inside of a bend, less on the outside (as `d` from a
					-- centre of turn `1 / k` off); this, not the square, says which runoff
					-- width and which height of road it is beside
					ds /= math.max(1 + st.k * d, 0.3)
					local ua = if L > 0 then math.clamp(ds / L, 0, 1) else 0
					local side = if d < 0 then -1 else 1
					local w = if side < 0 then st.wl + (st.nwl - st.wl) * ua else st.wr + (st.nwr - st.wr) * ua
					local e = r - w
					if e < bMax then
						local T, bw, past
						-- (a stretch's own grade carried on is close enough within two stretches;
						-- further, the centre line kept round the station)
						local near = math.abs(ds) <= 2 * L + 1
						if e <= 0 then
							past = 0
							T = surface(st, math.clamp(d, -w, w), ds, near) - G.Under
							bw = st.bmin
						else
							past = e
							T = surface(st, side * w, ds, near) - G.Under
							bw = math.clamp(math.abs(hp - T) / st.tanA, st.bmin, bMax)
						end
						-- WHICH STATIONS COUNT: along one stretch of road, each station by how near
						-- the point is to square beside it (a quadratic B-spline over a stretch and
						-- a half either way, so the answers hand over smoothly from one station to
						-- the next and the runoff's profile, which each station draws from its own
						-- width, never lifts the ground above it); between two stretches of road
						-- (two legs, the far side of a hairpin), the nearer edge, softly. Being
						-- further in on a runoff makes a station no nearer
						local q = if L > 0 then math.abs(ds) / L else 0
						local hat = if q < 0.5 then 0.75 - q * q elseif q < 1.5 then 0.5 * (1.5 - q) * (1.5 - q) else 0
						local score = past
						if hat > 0 then
							local wl = hat
							if score < emin then
								if emin < math.huge then
									local k = math.exp((score - emin) / soft)
									sw *= k
									swe *= k
									swb *= k
									swT *= k
								end
								emin = score
							end
							-- and fades out over the last `FADE` studs of the longest blend, so a
							-- station leaving the reckoning moves nothing
							local f = (bMax - e) / FADE
							if f < 1 then
								wl *= smooth(f)
							end
							local wgt = wl * math.exp((emin - score) / soft)
							sw += wgt
							swe += wgt * past
							swb += wgt * bw
							swT += wgt * T
						end
					end
				end
			end
		end
	end
	if sw <= 1e-12 then
		return hp, 0, math.huge, hp
	end
	local e, bw, T = swe / sw, swb / sw, swT / sw
	-- (a flat foot of `BlendFoot` first, T-228: a wall at 65 degrees right at the edge
	-- rose over the runoff where neighbouring stations disagree a little about the edge)
	local t = math.max(e - G.BlendFoot, 0) / bw
	if t >= 1 then
		return hp, 0, e, T
	end
	local A = 1 - smooth(t)
	return hp + (T - hp) * A, A, e, T
end

-- One point, with no context made beforehand: for the turn checks' few samples.
function Ground.query(field: Field, spline: Spline.Spline, x: number, z: number): (number, number, number, number)
	return Ground.at(Ground.context(field, spline, x, z, x, z), x, z)
end

return Ground
