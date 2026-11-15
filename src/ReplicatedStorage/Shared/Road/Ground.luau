--!strict
--!native
-- Road/Ground: the ground-first mountain (features/ground-trial.md, T-218). Pure maths, no
-- instances: the same on the server and on every client.
--
-- THE MOUNTAIN COMES FIRST. One height function of world position, `h(x, z)`: a plane
-- falling along the fall line (`Ground.Slope`), with broad seeded ridges and gullies on it
-- that run down the mountain (`Ground.Octaves`, stretched along the fall line). It depends
-- on the seed's origin and fall line alone, so every device has the same mountain.
--
-- THE ROAD IS PRESSED INTO IT (`at`). Under the road and its runoff the ground sits just
-- below their surface (`Ground.Under`). Past the runoff's outer edge it blends back to `h`
-- over `BlendMin..BlendMax` studs: a CUT where the mountain is above the edge, a FILL where
-- it is below. Between two legs it is simply `h`, with nothing to negotiate.
--
-- HOW THE BLEND IS TAKEN, so it has no seams: every station of road near a point (the
-- points the road files for its no-crossing test, every `CheckStep` studs) gives its own
-- answer from its own straight cross-section, weighted by how near the point is to square
-- beside it (`Look`). Where two stretches are both near (the inside of a hairpin, the
-- gap between two legs), the nearer edge wins, smoothly (`Soft`), so the ground is
-- continuous across the line between them. A stretch's influence fades to nothing at the
-- end of its blend, so beyond it the ground is exactly `h`.
--
-- The road itself is unchanged: the car drives on the spline maths, and the road's height
-- follows `base` (`SplineGen`, in a ground run), so the cuts and fills are the relief.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)

local Ground = {}

export type Octave = { size: number, amp: number, a: number, b: number, c: number }

export type Field = {
	seed: number,
	ox: number,
	oy: number,
	oz: number,
	ux: number, -- uphill, a unit vector in plan
	uz: number,
	slope: number,
	stretch: number,
	oct: { Octave },
	zero: number, -- the relief at the origin, taken off so the road starts on the plane
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

-- The field for a road: its origin and its fall line (the uphill heading, as a yaw: forward
-- is (-sin, -cos)), and offsets into the noise from the seed.
function Ground.field(seed: number, origin: Spline.Origin, fall: number): Field
	local G = Config.Spline.Ground
	local rng = Random.new((seed * 29 + 5153) % 2 ^ 31)
	local oct: { Octave } = {}
	for _, o in G.Octaves do
		table.insert(oct, {
			size = o[1],
			amp = o[2],
			a = rng:NextNumber() * 4096,
			b = rng:NextNumber() * 4096,
			c = rng:NextNumber() * 256 + 0.5, -- never a whole number: math.noise is 0 on the lattice
		})
	end
	local f: Field = {
		seed = seed,
		ox = origin.x,
		oy = origin.y,
		oz = origin.z,
		ux = -math.sin(fall),
		uz = -math.cos(fall),
		slope = G.Slope,
		stretch = G.Stretch,
		oct = oct,
		zero = 0,
	}
	f.zero = Ground.relief(f, origin.x, origin.z)
	return f
end

-- The plane: the mountain without its relief. The road's height follows this.
function Ground.base(f: Field, x: number, z: number): number
	return f.oy + f.slope * ((x - f.ox) * f.ux + (z - f.oz) * f.uz)
end

-- The ridges and gullies: noise in the fall line's own frame, stretched along it so they
-- run down the mountain.
function Ground.relief(f: Field, x: number, z: number): number
	local dx, dz = x - f.ox, z - f.oz
	local u = dx * f.ux + dz * f.uz -- up the mountain
	local v = dx * f.uz - dz * f.ux -- across it
	local y = 0
	for _, o in f.oct do
		y += o.amp * 2 * math.noise(u / (o.size * f.stretch) + o.a, v / o.size + o.b, o.c)
	end
	return y - f.zero
end

function Ground.h(f: Field, x: number, z: number): number
	return Ground.base(f, x, z) + Ground.relief(f, x, z)
end

-- The plane's grade along a heading (a yaw): how fast `base` rises going that way.
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
local function surface(st: Station, d: number, ds: number?): number
	local half = Config.Road.Width * 0.5
	local yc, tb = st.yc, st.tb
	if ds then
		yc += ds * (st.g + 0.5 * st.gr * ds)
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

local function station(spline: Spline.Spline, s: number, x: number, z: number): Station
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
	}
	if s < spline.length - KEEP_SHORT then
		mine[s] = st
	end
	return st
end

local CELL = 64 -- studs: a point looks at 25 cells round it (32: 81, measured slower)

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
						local st = station(spline, s, x, z)
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
	local look, soft = G.Look, G.Soft
	local bMin, bMax = G.BlendMin, G.BlendMax
	local tanA = math.tan(math.rad(G.BlendAngle))
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
					local dx, dz = x - st.x, z - st.z
					local l = dx * st.fx + dz * st.fz
					if l > -look and l < look then
						local d = dx * st.rx + dz * st.rz
						local w = if d < 0 then st.wl else st.wr
						local e = math.abs(d) - w
						if e < bMax then
							-- how far along the road the point is square to: further than `l` on
							-- the inside of a bend, less on its outside
							local ds = l / math.max(1 + st.k * d, 0.2)
							local T, bw
							if e <= 0 then
								e = 0
								T = surface(st, d, ds) - G.Under
								bw = bMin
							else
								T = surface(st, if d < 0 then -w else w, ds) - G.Under
								bw = math.clamp(math.abs(hp - T) / tanA, bMin, bMax)
							end
							local q = l / look
							local wl = (1 - q * q)
							wl *= wl
							if e < emin then
								if emin < math.huge then
									local k = math.exp((e - emin) / soft)
									sw *= k
									swe *= k
									swb *= k
									swT *= k
								end
								emin = e
							end
							-- and fades out over the last `FADE` studs of the longest blend, so a
							-- station leaving the reckoning moves nothing
							local f = (bMax - e) / FADE
							if f < 1 then
								wl *= smooth(f)
							end
							local wgt = wl * math.exp((emin - e) / soft)
							sw += wgt
							swe += wgt * e
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
	local t = e / bw
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
