--!strict
--!native
-- Road/Ground: the ground-first mountain (features/ground-trial.md, T-218). Pure maths, no
-- instances: the same on the server and on every client.
--
-- THE MOUNTAIN COMES FIRST. One height function of world position, `h(x, z)`: belts down
-- the fall line, shallow benches and steep scarps (`Ground.Belt...`, T-228), with broad
-- seeded ridges and gullies on them that run down the mountain (`Ground.Octaves`, stretched
-- along the fall line), taller where the belt is steeper. It depends on the seed's origin
-- and fall line alone, so every device has the same mountain.
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
-- follows `base` (`SplineGen`, in a ground run), so the cuts and fills are the relief.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)

local Ground = {}

export type Octave = { size: number, amp: number, a: number, b: number, c: number, kind: string? }

export type Field = {
	seed: number,
	ox: number,
	oy: number,
	oz: number,
	ux: number, -- uphill, a unit vector in plan
	uz: number,
	slope: number, -- the belt's slope at the start (for what still wants one number)
	stretch: number,
	oct: { Octave },
	-- the belts (T-228): the slope every `step` studs of fall line from `u0` up, and the
	-- height there, from the start's
	belt: { number },
	beltH: { number },
	u0: number,
	step: number,
	warp: { number }, -- {studs, studs across, noise offset, noise offset}
	baseZero: number, -- the belts' height at the start, taken off so the start is on them
	zero: number, -- the relief at the origin, taken off so the road starts on the mountain
	mode: string?, -- on a client: how it is drawn, "mesh" or "terrain"
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

local MODES = { current = true, mesh = true, terrain = true }

-- Is `mode` one of the ground modes ("current" is today's ground, no field).
function Ground.valid(mode: any): boolean
	return type(mode) == "string" and MODES[mode] == true
end

--------------------------------------------------------------------------------
-- The mountain: h(x, z)
--------------------------------------------------------------------------------

-- The belts down the fall line (T-228): going down from `BeltsUp`, a bench, a ramp, a scarp,
-- a ramp, and so on, each one's sizes from the seed's own stream. Returns the slope every
-- `BeltStep` studs, lowest first, and the u of the first.
local function belts(rng: Random): ({ number }, number)
	local G = Config.Spline.Ground
	local step = G.BeltStep
	local n = math.floor((G.BeltsUp + G.BeltsDown) / step) + 1
	local down: { number } = table.create(n)
	local function between(r: { number }): number
		return r[1] + (r[2] - r[1]) * rng:NextNumber()
	end
	while #down < n do
		local lo, hi = between(G.BeltLow), between(G.BeltHigh)
		for _, seg in { { between(G.BeltBench), lo, lo }, { G.BeltRamp, lo, hi }, { between(G.BeltScarp), hi, hi }, { G.BeltRamp, hi, lo } } do
			local count = math.max(1, math.floor(seg[1] / step))
			for j = 0, count - 1 do
				if #down >= n then
					break
				end
				local t = j / count
				t = t * t * (3 - 2 * t)
				table.insert(down, seg[2] + (seg[3] - seg[2]) * t)
			end
		end
	end
	-- lowest first
	local up: { number } = table.create(n)
	for i = n, 1, -1 do
		table.insert(up, down[i])
	end
	return up, G.BeltsUp - (n - 1) * step
end

-- The field for a road: its origin and its fall line (the uphill heading, as a yaw: forward
-- is (-sin, -cos)), the belts, and offsets into the noise, all from the seed.
function Ground.field(seed: number, origin: Spline.Origin, fall: number): Field
	local G = Config.Spline.Ground
	local rng = Random.new((seed * 29 + 5153) % 2 ^ 31)
	local oct: { Octave } = {}
	for _, o in G.Octaves do
		table.insert(oct, {
			size = o[1],
			amp = o[2],
			kind = o[3],
			a = rng:NextNumber() * 4096,
			b = rng:NextNumber() * 4096,
			c = rng:NextNumber() * 256 + 0.5, -- never a whole number: math.noise is 0 on the lattice
		})
	end
	local warp = { G.BeltWarp[1], G.BeltWarp[2], rng:NextNumber() * 4096, rng:NextNumber() * 256 + 0.5 }
	local belt, u0 = belts(Random.new((seed * 31 + 7177) % 2 ^ 31))
	-- the height up the belts: the slope's integral (it is straight between two samples)
	local step = G.BeltStep
	local beltH = table.create(#belt)
	beltH[1] = 0
	for i = 2, #belt do
		beltH[i] = beltH[i - 1] + 0.5 * (belt[i - 1] + belt[i]) * step
	end
	local f: Field = {
		seed = seed,
		ox = origin.x,
		oy = origin.y,
		oz = origin.z,
		ux = -math.sin(fall),
		uz = -math.cos(fall),
		slope = 0,
		stretch = G.Stretch,
		oct = oct,
		belt = belt,
		beltH = beltH,
		u0 = u0,
		step = step,
		warp = warp,
		baseZero = 0,
		zero = 0,
	}
	f.baseZero = Ground.base(f, origin.x, origin.z) - origin.y
	f.slope = Ground.beltSlope(f, origin.x, origin.z)
	f.zero = Ground.relief(f, origin.x, origin.z)
	return f
end

-- Where (x, z) is on the belts: up the fall line, after their curve across the mountain.
local function beltU(f: Field, x: number, z: number): (number, number)
	local dx, dz = x - f.ox, z - f.oz
	local u = dx * f.ux + dz * f.uz -- up the mountain
	local v = dx * f.uz - dz * f.ux -- across it
	local w = f.warp
	return u + w[1] * 2 * math.noise(v / w[2] + w[3], w[4], 0.37), v
end

-- The belts' slope and height at a u (between two samples the slope is straight, so the
-- height is its integral, smooth); past either end, straight on.
local function beltAt(f: Field, u: number): (number, number)
	local belt, H = f.belt, f.beltH
	local q = (u - f.u0) / f.step
	local n = #belt
	if q <= 0 then
		return belt[1], H[1] + belt[1] * q * f.step
	elseif q >= n - 1 then
		return belt[n], H[n] + belt[n] * (q - (n - 1)) * f.step
	end
	local i = math.floor(q)
	local t = (q - i) * f.step
	local s0, s1 = belt[i + 1], belt[i + 2]
	local k = (s1 - s0) / f.step
	return s0 + k * t, H[i + 1] + s0 * t + 0.5 * k * t * t
end

-- The mountain without its ridges and gullies: the belts.
function Ground.base(f: Field, x: number, z: number): number
	local u = beltU(f, x, z)
	local _, y = beltAt(f, u)
	return f.oy + y - f.baseZero
end

-- How steep the belt is at (x, z), up the fall line.
function Ground.beltSlope(f: Field, x: number, z: number): number
	local u = beltU(f, x, z)
	return (beltAt(f, u))
end

-- The ridges and gullies: noise in the fall line's own frame, stretched along it so they
-- run down the mountain, as tall as the belt there (its slope `bs`) is steep (T-228).
local function reliefAt(f: Field, x: number, z: number, bs: number): number
	local G = Config.Spline.Ground
	local dx, dz = x - f.ox, z - f.oz
	local u = dx * f.ux + dz * f.uz -- up the mountain
	local v = dx * f.uz - dz * f.ux -- across it
	local y = 0
	for _, o in f.oct do
		local n = math.noise(u / (o.size * f.stretch) + o.a, v / o.size + o.b, o.c)
		if o.kind == "ridge" then
			y += o.amp * (1 - 4 * math.abs(n))
		elseif o.kind == "gully" then
			y += o.amp * (4 * math.abs(n) - 1)
		else
			y += o.amp * 2 * n
		end
	end
	local r = G.ReliefSlopes
	local m = math.clamp((bs - r[1]) / (r[2] - r[1]), 0, 1)
	m = m * m * (3 - 2 * m)
	return y * (G.ReliefLow + (1 - G.ReliefLow) * m) - f.zero
end

function Ground.relief(f: Field, x: number, z: number): number
	return reliefAt(f, x, z, (beltAt(f, (beltU(f, x, z)))))
end

function Ground.h(f: Field, x: number, z: number): number
	local bs, by = beltAt(f, (beltU(f, x, z)))
	return f.oy + by - f.baseZero + reliefAt(f, x, z, bs)
end

-- The belt's grade at the start along a heading (a yaw); kept for what still wants the
-- mountain as one plane.
function Ground.grade(f: Field, yaw: number): number
	return f.slope * (-math.sin(yaw) * f.ux - math.cos(yaw) * f.uz)
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
	local soft, beyond = G.Soft, G.Beyond
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
						-- what the soft minimum weighs: the distance past the edge, plus how far
						-- beyond its own stretch the point lies along the road (`Beyond` times).
						-- Of the stations a point is beside, the one whose stretch it is square
						-- to counts most: at the runoff's edge a neighbour's nearest point is
						-- barely further off, but its height is that of road a few studs along,
						-- and round the inside of a bend a runoff wider a few stations back
						-- reaches over the point
						local score = e + beyond * math.max(0, -ds, ds - L)
						do
							local wl = 1
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
