--!strict
--!native
-- SplineHill: the ground between the legs of the spline road, as pure maths
-- (features/continuous-mountain.md, T-190). No instances.
--
-- THE MOUNTAIN IS ONE SURFACE. Past a rock face's top the hillside carries on up, and past a
-- cliff's foot it carries on down, until it meets the ground of whatever road is next to it:
-- the leg above, the leg below, the other arm of a hairpin. `Road/SplineMesh` draws it, in
-- the chunk's own mesh.
--
-- WHO DRAWS WHICH GROUND: every point of the hillside belongs to the stretch of road whose
-- EDGE it is nearest. A cross-section's ray runs out from the road until some other stretch
-- is as near (`clip`): the middle of the gap between two legs, or the centre of a bend on
-- its inside. So no two stretches draw the same ground, and the lines where they meet are
-- the gullies and ridges of the mountain.
--
-- HOW HIGH IT IS. Each station of the road has its own idea of the ground beside it
-- (`own`): its rock face up or its cliff down, then a plane tilted along the mountain's fall
-- line (`Hill.Slope`). Along a ray the ground starts as the ray's own idea and ends, where
-- it meets its neighbour, at a height both agree on: the ideas of every station round that
-- point, weighted by how near they are (`meet`). That height is a function of the place
-- alone, so both sides of a meeting line compute the same one.
--
-- FACES FIT THE ROOM THERE IS. Two legs close together (near a hairpin) are only a few studs
-- apart in height: a 60-stud rock face under an 80-stud cliff cannot both stand between
-- them. So each face is CAPPED (`cap`): by its share of the height there really is between
-- the two roads, less a gentle slope across the gap; and down to nothing where the mountain
-- changes sides in a turn, so the rock on one side ends level where the drop begins.
-- `SplineMesh.profile` draws a face no taller than its cap.
--
-- STATIONS are the points the road files for its no-crossing test (`Spline.hash`), every
-- `Hill.StationStep` studs: wherever the road has been, however long ago, so the leg above
-- is known even when it is not drawn. A chunk gathers the stations round it once
-- (`context`).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)

local SplineHill = {}

-- by side: index 1 is the left (-1), 2 the right (1)
export type Station = {
	s: number,
	x: number,
	z: number,
	rx: number, -- the plan right
	rz: number,
	c: number, -- how far the right points up the fall line, -1..1 (0 with no fall line)
	w: { number }, -- half the tarmac and the runoff: where the edge is
	y0: { number }, -- the ground's height at the edge
	kind: { number }, -- the edge
	nat: { number }, -- the face's own height: a rock body's rise, a cliff's drop
	run: { number }, -- how far the face reaches out past the edge
	taper: { number }, -- the cap from the nearest change of sides
	cap: { number }?, -- the face's allowed height, once solved
	yEnd: { number }?, -- the height where the face ends and the hillside begins
	tEnd: { number }?, -- how far from the centre line that is
	clip: { number }?, -- how far from the centre line its ground ends
	met: { boolean }?, -- whether another stretch ended it (not the end of its reach)
}

export type Ray = {
	st: Station,
	side: number, -- -1 or 1
	clip: number, -- from the centre line, where this station's ground ends
	free: boolean, -- nothing met: it ends at `Reach`
	meet: number?, -- the height at `clip`, once `finish`ed
}

export type Context = {
	spline: Spline.Spline,
	stations: { Station },
	profile: (Spline.Spline, number, number, number) -> { Vector3 },
	tick: () -> (),
	cuts: { [number]: Station }, -- the stations made for rays, by `s`
}

local function idx(side: number): number
	return if side < 0 then 1 else 2
end

-- Studs along the road from `s` to where the edge on `side` next changes kind, either way.
local function toChange(spline: Spline.Spline, s: number, side: number): number
	local sp = if side < 0 then spline.edgeL else spline.edgeR
	local e, t = sp.e, sp.t
	local n = #e
	if n == 0 then
		return math.huge
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
	local kind = t[lo]
	local best = math.huge
	local i = lo - 1
	while i >= 1 and t[i] == kind and s - e[i] < 500 do
		i -= 1
	end
	if i >= 1 and t[i] ~= kind then
		best = s - e[i]
	end
	local j = lo
	while j < n and t[j + 1] == kind and e[j] - s < 500 do
		j += 1
	end
	if j < n and t[j + 1] ~= kind then
		best = math.min(best, e[j] - s)
	end
	return math.max(best, 0)
end

-- What a station is by itself (not its caps, which depend on the road round it) is kept from
-- one chunk to the next: most of a chunk's stations were its neighbour's too. Only stations
-- well short of the road's end, where nothing the road lays later can change them.
local kept: { [Spline.Spline]: { [number]: Station } } = setmetatable({}, { __mode = "k" }) :: any
local KEEP_SHORT = 700 -- studs: past how far an edge's change, or a tight bend, is looked for

-- A station at `s`, whose plan position is (x, z).
local function station(ctx: Context, s: number, x: number, z: number): Station
	local H = Config.Spline.Hill
	local spline = ctx.spline
	local mine = kept[spline]
	if not mine then
		mine = {}
		kept[spline] = mine
	end
	local old = mine[s]
	if old then
		return table.clone(old)
	end
	local yaw = spline:yawAt(s)
	local fall = spline.fall
	local half = Config.Road.Width * 0.5
	local st: Station = {
		s = s,
		x = x,
		z = z,
		rx = math.cos(yaw),
		rz = -math.sin(yaw),
		c = if fall then math.sin(yaw - fall) else 0,
		w = { 0, 0 },
		y0 = { 0, 0 },
		kind = { 0, 0 },
		nat = { 0, 0 },
		run = { 0, 0 },
		taper = { 0, 0 },
	}
	for i, side in { -1, 1 } do
		local w = half + spline:runoffAt(s, side)
		local kind = spline:edgeAt(s, side)
		st.w[i] = w
		st.y0[i] = spline:terrainY(s, side * w)
		st.kind[i] = kind
		if kind == Spline.ROCK or kind == Spline.CLIFF then
			local pts = ctx.profile(spline, s, side, kind)
			local a, b = pts[1], pts[5]
			st.nat[i] = math.abs(b.Y - a.Y)
			st.run[i] = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
			st.taper[i] = H.TaperRate * toChange(spline, s, side)
		end
	end
	if s < spline.length - KEEP_SHORT and s % H.StationStep < 1e-6 then
		mine[s] = table.clone(st)
	end
	return st
end

-- Where the ground of a station at (x, z) ends along (dx, dz), a unit vector out from it:
-- the nearest point as near some other stretch's edge as its own, at most `Reach`. For
-- road close by along the curve that is the centre of the bend (centre lines compared); for
-- a stretch FACING this one -- far along the road, near in space -- the edges are compared,
-- so the line runs down the middle of the gap between them. Returns the distance from the
-- centre line, and the facing station that set it, if one did.
local function clipOf(ctx: Context, s: number, x: number, z: number, dx: number, dz: number, w: number): (number, Station?, number)
	local H = Config.Spline.Hill
	local best = w + H.Reach
	-- the nearest FACING stretch, whether or not it is what ends the ground (on the inside
	-- of a hairpin the bend's own centre may come a little sooner than the other arm)
	local bestFacing = best
	local by: Station? = nil
	local byDist = 0
	local facingRatio = H.Facing
	for _, q in ctx.stations do
		local qx, qz = q.x - x, q.z - z
		local dot = qx * dx + qz * dz
		if dot > 0 then
			local d2 = qx * qx + qz * qz
			local reach = 2 * bestFacing + 140
			if d2 < reach * reach then
				local along = math.abs(q.s - s)
				local facing = along > facingRatio * math.sqrt(d2)
				local delta = 0
				if facing then
					-- the side of `q` this station is on
					local qSide = if -qx * q.rx - qz * q.rz >= 0 then 2 else 1
					delta = q.w[qSide] - w
				end
				local den = 2 * (dot + delta)
				local num = d2 - delta * delta
				if den > 1e-6 and num > 0 then
					local t = num / den
					if t < best then
						best = t
					end
					if facing and t < bestFacing then
						bestFacing = t
						by = q
						byDist = math.sqrt(d2)
					end
				end
			end
		end
	end
	return best, by, byDist, bestFacing <= best + 1e-9
end

-- A ray's end against a facing stretch, exactly. `clipOf` measures to that stretch's
-- stations, 16 studs apart, and the stretch measures back to this one's: near enough to cap
-- a face by, but the two ends could be a stud or two apart, and the meeting height changes
-- fast across the line. Measured to the road itself, both sides end on the one line.
local function exact(ctx: Context, st: Station, i: number, side: number, clip: number, q: Station): number
	local spline = ctx.spline
	local half = Config.Road.Width * 0.5
	local dx, dz = side * st.rx, side * st.rz
	local t, hint = clip, q.s
	for _ = 1, 3 do
		local s2, d2 = spline:projectFrom(st.x + dx * t, st.z + dz * t, hint)
		if not s2 or not d2 then
			return clip
		end
		hint = s2
		local x2, z2 = spline:planAt(s2)
		local qx, qz = x2 - st.x, z2 - st.z
		local delta = half + spline:runoffAt(s2, if d2 < 0 then -1 else 1) - st.w[i]
		local den = 2 * (qx * dx + qz * dz + delta)
		local num = qx * qx + qz * qz - delta * delta
		if den <= 1e-6 or num <= 0 then
			return clip
		end
		t = num / den
	end
	-- (a few studs at most: anything more is another part of the road, not a better answer)
	return if math.abs(t - clip) < 12 then t else clip
end

-- Solve a station's faces: the cap each may stand to, and where each then ends. `precise`
-- is for a station whose rays are drawn: its ends against facing stretches are made exact.
local function solve(ctx: Context, st: Station, precise: boolean?)
	if st.cap then
		return
	end
	local H = Config.Spline.Hill
	local cap, yEnd, tEnd = { 0, 0 }, { 0, 0 }, { 0, 0 }
	local clips, mets = { 0, 0 }, { false, false }
	for i, side in { -1, 1 } do
		local kind = st.kind[i]
		local nat = st.nat[i]
		local c = math.huge
		local clip, q, dist, byFacing = clipOf(ctx, st.s, st.x, st.z, side * st.rx, side * st.rz, st.w[i])
		if precise and q and byFacing then
			clip = math.min(exact(ctx, st, i, side, clip, q), st.w[i] + H.Reach)
		end
		clips[i] = clip
		mets[i] = clip < st.w[i] + H.Reach - 1e-6
		if kind == Spline.ROCK or kind == Spline.CLIFF then
			local sgn = if kind == Spline.ROCK then 1 else -1
			-- never reaching past its own ground: on the inside of a bend, where the ground
			-- ends at the bend's centre, a face that would reach further is drawn smaller
			local run = st.run[i]
			if run > 1e-6 then
				local fit = math.max(H.FaceShare * (clip - st.w[i]), 0) / run
				if fit < 1 then
					c = nat * (if kind == Spline.ROCK then fit else fit * fit)
				end
			end
			-- nor taller than the ground it stands in is wide: no pit or pinnacle in a pocket
			c = math.min(c, H.Aspect * math.max(clip - st.w[i], 0))
			-- and by how squarely the side faces up (or down) the fall line: a road cut across
			-- a slope has its full face; one heading straight down it has none, neither side
			-- being uphill. So round the outside of a hairpin the rock comes down steadily to
			-- nothing where the road points down the mountain, and the view ahead opens
			-- (never under `MinRock` or `MinCliff`: to the car a rock face is a wall and a
			-- drop a fall, wherever they are, so there is always a low one to see)
			if ctx.spline.fall then
				c = math.min(c, math.max(nat * math.abs(st.c) ^ H.AcrossPower, if kind == Spline.ROCK then H.MinRock else H.MinCliff))
			end
			if q then
				local qi = if (st.x - q.x) * q.rx + (st.z - q.z) * q.rz >= 0 then 2 else 1
				local gap = math.max(dist - st.w[i] - q.w[qi], 1)
				local other = q.kind[qi]
				local near
				if other ~= kind and (other == Spline.ROCK or other == Spline.CLIFF) then
					-- a rock face under a drop: they share the height there is between the
					-- two roads, less a gentle slope across the gap
					local room = math.max(0, sgn * (q.y0[qi] - st.y0[i]) - H.MinSlope * gap)
					local both = nat + q.nat[qi]
					near = room * (if both > 1e-6 then nat / both else 0.5)
				else
					-- two rock faces (or two drops) facing each other: a low ridge (or a
					-- shallow gully) between them, no taller than the gap can carry
					near = H.SameShare * gap
				end
				near += math.max(0, dist - H.RelaxFrom) * H.RelaxRate
				c = math.min(c, math.max(near, if kind == Spline.ROCK then H.MinRock else H.MinCliff))
			end
			c = math.min(c, st.taper[i])
			local f = if nat > 1e-6 then math.min(1, c / nat) else 1
			yEnd[i] = st.y0[i] + sgn * nat * f
			tEnd[i] = st.w[i] + st.run[i] * (if kind == Spline.ROCK then f else math.sqrt(f))
		else
			yEnd[i] = st.y0[i]
			tEnd[i] = st.w[i]
		end
		cap[i] = c
	end
	st.cap, st.yEnd, st.tEnd = cap, yEnd, tEnd
	st.clip, st.met = clips, mets
end

-- A station's own idea of the ground `dist` studs from its centre line on side index `i`:
-- level with where its face ends, then a plane tilted along the fall line.
local function own(st: Station, i: number, dist: number): number
	local H = Config.Spline.Hill
	local tEnd = (st.tEnd :: { number })[i]
	-- up past a rock face, down past a drop, by how squarely the ray points along the fall
	-- line. The side's own edge says which way, not the compass: where the road climbs the
	-- far side of a valley, the mountain is on the other side of it
	local kind = st.kind[i]
	local way = if kind == Spline.ROCK then 1 elseif kind == Spline.CLIFF then -1 else 0
	return (st.yEnd :: { number })[i] + H.Slope * way * math.abs(st.c) * math.max(0, dist - tEnd)
end

-- Gather the stations round [s0, s1] of the road. `profile` is `SplineMesh.profile` (handed
-- in: that module requires this one). `tick`, if given, is called now and then through the
-- long loops, so a build can hand the frame back.
function SplineHill.context(spline: Spline.Spline, s0: number, s1: number, profile: (Spline.Spline, number, number, number) -> { Vector3 }, tick: (() -> ())?): Context
	local H = Config.Spline.Hill
	local ctx: Context = { spline = spline, stations = {}, profile = profile, tick = tick or function() end, cuts = {} }
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local u = s0
	while true do
		local x, z = spline:planAt(math.min(u, s1))
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
		if u >= s1 then
			break
		end
		u += 16
	end
	local pad = H.Gather
	local cell = spline.cell
	local step = H.StationStep
	local first = spline.firstSample * spline.step
	for cx = math.floor((minX - pad) / cell), math.floor((maxX + pad) / cell) do
		for cz = math.floor((minZ - pad) / cell), math.floor((maxZ + pad) / cell) do
			local list = spline.hash[(cx + 1048576) * 2097152 + (cz + 1048576)]
			if list then
				for j = 1, #list, 3 do
					local s = list[j]
					if s % step < 1e-6 and s >= first and s <= spline.length then
						table.insert(ctx.stations, station(ctx, s, list[j + 1], list[j + 2]))
					end
				end
			end
		end
		ctx.tick()
	end
	return ctx
end

-- The ray of the cross-section at `s` on `side`: its station (with its faces solved, so
-- `SplineHill.cap` can be read) and where its ground ends.
function SplineHill.ray(ctx: Context, s: number, side: number): Ray
	-- one station serves both sides' rays
	local st = ctx.cuts[s]
	if not st then
		local x, z = ctx.spline:planAt(s)
		st = station(ctx, s, x, z)
		solve(ctx, st, true)
		ctx.cuts[s] = st
	end
	local i = idx(side)
	return { st = st, side = side, clip = (st.clip :: { number })[i], free = not (st.met :: { boolean })[i] }
end

-- The height its face may stand to (`SplineMesh.profile`'s cap): math.huge for no cap.
function SplineHill.cap(ray: Ray): number
	return (ray.st.cap :: { number })[idx(ray.side)]
end

-- The broad ridges and gullies: noise over the world, a function of the place alone, so two
-- stretches' ground has the same at the line they meet on. (`at` eases it in from where a
-- face ends.)
local function relief(x: number, z: number): number
	local H = Config.Spline.Hill
	return H.NoiseHeight * 2 * math.noise(x / H.NoiseSize, z / H.NoiseSize, 37.7)
end

-- Work out the height where a ray's ground ends (`meet`): what every station round that
-- point thinks the ground there is, the nearest counting most. A function of the place, so
-- the stretch on the other side of the line gets the same.
function SplineHill.finish(ctx: Context, ray: Ray)
	if ray.meet then
		return
	end
	local H = Config.Spline.Hill
	local st, side = ray.st, ray.side
	local i = idx(side)
	local mine = own(st, i, ray.clip)
	-- with nothing below, a drop's hillside steepens away at its rim
	local alone = mine - (if st.kind[i] == Spline.CLIFF then H.RimDrop else 0)
	if ray.free then
		ray.meet = alone
		return
	end
	local bx, bz = st.x + side * st.rx * ray.clip, st.z + side * st.rz * ray.clip
	-- how far the nearest station's edge is from the point: from the stations themselves,
	-- not from this ray, so every ray that ends here weighs them the same
	local eMin = math.huge
	for _, q in ctx.stations do
		local qx, qz = bx - q.x, bz - q.z
		local e = math.sqrt(qx * qx + qz * qz) - q.w[if qx * q.rx + qz * q.rz >= 0 then 2 else 1]
		if e < eMin then
			eMin = e
		end
	end
	eMin = math.max(eMin, 4)
	local sum, total = 0, 0
	for _, q in ctx.stations do
		local qx, qz = bx - q.x, bz - q.z
		local d = math.sqrt(qx * qx + qz * qz)
		local qi = if qx * q.rx + qz * q.rz >= 0 then 2 else 1
		local e = d - q.w[qi]
		if e < 1.5 * eMin + 8 then
			solve(ctx, q)
			-- the nearest count most, but smoothly: a stud's move changes no weight much
			local wgt = (eMin / math.max(e, eMin * 0.5)) ^ 4
			sum += wgt * own(q, qi, d)
			total += wgt
		end
	end
	ctx.tick()
	local met = if total > 0 then sum / total else mine
	-- a ray that only just meets another stretch, at the end of its reach, eases into what
	-- it would be alone
	-- (by its distance past the edge, which is the same from both sides of the line)
	local near = math.clamp((H.Reach - (ray.clip - st.w[i])) / H.MeetOver, 0, 1)
	ray.meet = alone + (met - alone) * near
end

-- The ground on a `finish`ed ray, `t` studs from the centre line (from where its face ends
-- out to `clip`; past it, the height at `clip`).
function SplineHill.at(ray: Ray, t: number): Vector3
	local st, side = ray.st, ray.side
	local i = idx(side)
	local tEnd = (st.tEnd :: { number })[i]
	local span = ray.clip - tEnd
	local tt = math.min(t, ray.clip)
	local u = if span > 1e-6 then math.clamp((tt - tEnd) / span, 0, 1) else 1
	local y = own(st, i, tt) + ((ray.meet :: number) - own(st, i, ray.clip)) * u ^ 1.5
	local x, z = st.x + side * st.rx * t, st.z + side * st.rz * t
	-- (and none right at the face's end, where the ground joins the face's own vertices)
	-- (full by the ray's end, however short it is, so both sides of a meeting line agree)
	local join = math.clamp((tt - tEnd) / math.max(math.min(Config.Spline.Hill.NoiseFrom, span), 1e-6), 0, 1)
	return Vector3.new(x, y + relief(x, z) * join * join * (3 - 2 * join), z)
end

-- The mountain's height at a place: whose ground it is (the station whose edge is nearest),
-- then that stretch's own ray through it. On a road it is the road's ground; on a face, a
-- straight line from its foot to its end. For tests and measurements: a ray is solved per
-- call, so it is not for anything that runs every frame.
function SplineHill.heightAt(ctx: Context, x: number, z: number): (number?, number?, number?)
	local best: Station?, bestE = nil, math.huge
	for _, q in ctx.stations do
		local qx, qz = x - q.x, z - q.z
		local qi = if qx * q.rx + qz * q.rz >= 0 then 2 else 1
		local e = math.sqrt(qx * qx + qz * qz) - q.w[qi]
		if e < bestE then
			best, bestE = q, e
		end
	end
	if not best then
		return nil, nil, nil
	end
	local spline = ctx.spline
	local s, d = spline:projectFrom(x, z, best.s)
	if not s or not d then
		return nil, nil, nil
	end
	local side = if d < 0 then -1 else 1
	local t = math.abs(d)
	local ray = SplineHill.ray(ctx, s, side)
	local i = idx(side)
	local st = ray.st
	if t <= st.w[i] then
		return spline:terrainY(s, d), s, d
	end
	local tEnd = (st.tEnd :: { number })[i]
	if t < tEnd then
		local u = (t - st.w[i]) / math.max(tEnd - st.w[i], 1e-6)
		return st.y0[i] + ((st.yEnd :: { number })[i] - st.y0[i]) * u, s, d
	end
	SplineHill.finish(ctx, ray)
	return SplineHill.at(ray, math.min(t, ray.clip)).Y, s, d
end

-- Where a ray's face ends: studs from the centre line.
function SplineHill.faceEnd(ray: Ray): number
	return (ray.st.tEnd :: { number })[idx(ray.side)]
end

return SplineHill
