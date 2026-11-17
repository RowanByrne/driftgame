--!strict
--!native
-- Drift/GroundTiles: which square tiles the mesh ground is drawn as (features/ground-trial.md,
-- T-225). Pure maths, no instances: `Drift/GroundMeshView` draws what this picks.
--
-- A QUADTREE OF TILES. The coarsest tiles (`Spacings[#Spacings]` studs between vertices,
-- `TileCells` cells across) cover everything within `Reach` of the car, and everything within
-- `RoadPad` of the drawn road. A tile splits into the four of the next finer spacing while it
-- is too coarse for where it is: nearer the car than its spacing times `Ratio`, or within
-- `RoadRange` times its spacing of a point of road that wants finer (each point of road says
-- how fine: 8 studs near the car, coarser further along). Of the tiles that want splitting,
-- the nearest the car splits first, until `Tiles` tiles show, so a device never draws more
-- than its share of the mesh budget whatever the road does, and what goes without is what
-- is furthest away.
--
-- Every tile sits on one world lattice (its corner a whole number of its own sides from the
-- origin), so a tile and its four children cover exactly the same ground, and two tiles
-- either nest or do not overlap at all.
--
-- INSIDE THE VISTA (T-281, the user: no art "cut or obscured by the terrain going through
-- it"): no tile's furthest corner passes `limit()` studs from the car, the nearest painted
-- ring's nearest point less the camera at its furthest behind the car and `VistaMargin`. A
-- root tile that would is drawn as those of its four children the ground wants (each one
-- again, down to the finest), and a finest tile that still would is left out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local IS_STUDIO = game:GetService("RunService"):IsStudio()

local GroundTiles = {}

export type Leaf = {
	key: number,
	level: number, -- 1 finest
	ix: number,
	iz: number,
	s: number, -- studs between vertices
	side: number, -- studs across
	x0: number, -- the corner with the least x and z
	z0: number,
}

export type Want = {
	x: number, -- the car
	z: number,
	-- x, z, w, x, z, w, ...: the points of road the detail follows, and the spacing each
	-- wants the ground round it finer than
	road: { number },
	tiles: number,
	ratio: number,
	reach: number,
	split: { [number]: boolean }?, -- keys of tiles split now, which stay split a little longer
	limit: number?, -- no tile's furthest corner further than this from the car (`limit()`)
}

local OFF = 524288 -- 2^19 tiles either way of the origin

function GroundTiles.key(level: number, ix: number, iz: number): number
	return (level * 1048576 + (ix + OFF)) * 1048576 + (iz + OFF)
end

function GroundTiles.sideOf(level: number): number
	local G = Config.Spline.Ground
	return G.TileCells * G.Spacings[level]
end

function GroundTiles.node(level: number, ix: number, iz: number): Leaf
	local G = Config.Spline.Ground
	local s = G.Spacings[level]
	local side = G.TileCells * s
	return {
		key = GroundTiles.key(level, ix, iz),
		level = level,
		ix = ix,
		iz = iz,
		s = s,
		side = side,
		x0 = ix * side,
		z0 = iz * side,
	}
end

function GroundTiles.parent(leaf: Leaf): Leaf?
	if leaf.level >= #Config.Spline.Ground.Spacings then
		return nil
	end
	return GroundTiles.node(leaf.level + 1, leaf.ix // 2, leaf.iz // 2)
end

function GroundTiles.children(leaf: Leaf): { Leaf }
	local l, ix, iz = leaf.level - 1, leaf.ix * 2, leaf.iz * 2
	return {
		GroundTiles.node(l, ix, iz),
		GroundTiles.node(l, ix + 1, iz),
		GroundTiles.node(l, ix, iz + 1),
		GroundTiles.node(l, ix + 1, iz + 1),
	}
end

-- How far (px, pz) is from a square (0 inside it).
local function distTo(x0: number, z0: number, side: number, px: number, pz: number): number
	local dx = math.max(x0 - px, 0, px - (x0 + side))
	local dz = math.max(z0 - pz, 0, pz - (z0 + side))
	return math.sqrt(dx * dx + dz * dz)
end
GroundTiles.distTo = distTo

-- How far (px, pz) is from a square's furthest corner.
local function farCorner(x0: number, z0: number, side: number, px: number, pz: number): number
	local dx = math.max(math.abs(px - x0), math.abs(px - (x0 + side)))
	local dz = math.max(math.abs(pz - z0), math.abs(pz - (z0 + side)))
	return math.sqrt(dx * dx + dz * dz)
end
GroundTiles.farCorner = farCorner

-- How far from the car the ground may reach (T-281): the nearest point of the nearest painted
-- ring (`Shared/Vista.ringSpan`: a panel's middle, the ring trailing its most), less the
-- camera at its furthest behind the car (`PlayerZoomMax`) and `Ground.VistaMargin`. No limit
-- with the vista off.
function GroundTiles.limit(): number
	local V = Config.Vista
	-- (in Studio, `workspace.__ground_no_limit = true` draws as before T-281, to compare)
	if not V or not V.Enabled or not V.Layers or #V.Layers == 0 or (IS_STUDIO and workspace:GetAttribute("__ground_no_limit") == true) then
		return math.huge
	end
	local Vista = require(ReplicatedStorage.Shared.Vista)
	local nearest = math.huge
	for _, layer in V.Layers do
		nearest = math.min(nearest, (Vista.ringSpan(layer)))
	end
	local C = Config.Camera
	local camBack = C.CamOffset.Magnitude * C.PlayerZoomMax
	return nearest - camBack - Config.Spline.Ground.VistaMargin
end

-- The points of road the ground's detail follows, from `s0` to `s1` along `spline`, for a car
-- at `along` (`Want.road`): 8 studs out to `fine` along it, then coarser; behind the car past
-- `Mesh.BehindSharp` only `RoadCoarsest`; far along it coarser still (`RoadFar`, T-263), and
-- its points as far apart as that allows (a tile's reach is `RoadRange` times its spacing).
function GroundTiles.roadPoints(spline: any, along: number, s0: number, s1: number, fine: number): { number }
	local G = Config.Spline.Ground
	local near = Config.Spline.Mesh.BehindSharp
	local road = {}
	local s = s0
	while s <= s1 do
		local x, z = spline:planAt(s)
		local w = if s < along - near
			then G.RoadCoarsest
			else math.min(G.Spacings[1] * math.max(1, math.abs(s - along) / fine), G.RoadCoarsest)
		local d = math.abs(s - along)
		for _, step in G.RoadFar do
			if d >= step.From then
				w = math.max(w, step.Coarsest)
			end
		end
		table.insert(road, x)
		table.insert(road, z)
		table.insert(road, w)
		s += math.max(G.RoadStep, w * 2)
	end
	return road
end

-- How much too coarse a tile is: over 1, it wants splitting.
local function need(nd: Leaf, want: Want): number
	if nd.level <= 1 then
		return 0
	end
	local s = nd.s
	local n = s * want.ratio / math.max(distTo(nd.x0, nd.z0, nd.side, want.x, want.z), 1)
	local road = want.road
	local range = s * Config.Spline.Ground.RoadRange
	for i = 1, #road, 3 do
		if distTo(nd.x0, nd.z0, nd.side, road[i], road[i + 1]) < range then
			-- splits while its spacing is twice what the road wants or more
			local r = s / (1.99 * road[i + 2])
			if r > n then
				n = r
			end
		end
	end
	if want.split and want.split[nd.key] then
		n *= Config.Spline.Ground.Hysteresis
	end
	return n
end

-- The tiles to draw, as a list and by key.
function GroundTiles.select(want: Want): ({ Leaf }, { [number]: Leaf })
	local G = Config.Spline.Ground
	local top = #G.Spacings
	local side = GroundTiles.sideOf(top)
	local leaves: { Leaf } = {}
	local needs: { number } = {}
	local seen: { [number]: boolean } = {}
	local x, z, reach = want.x, want.z, want.reach
	local pad = G.RoadPad
	local road = want.road
	local limit = want.limit or math.huge
	-- is a tile wanted at all: within `reach` of the car, or `RoadPad` of a point of road
	local function wanted(nd: Leaf): boolean
		if distTo(nd.x0, nd.z0, nd.side, x, z) <= reach then
			return true
		end
		for i = 1, #road, 3 do
			if distTo(nd.x0, nd.z0, nd.side, road[i], road[i + 1]) <= pad then
				return true
			end
		end
		return false
	end
	-- a tile reaching past `limit` is drawn as its wanted children instead (T-281)
	local function add(nd: Leaf)
		if farCorner(nd.x0, nd.z0, nd.side, x, z) > limit then
			if nd.level > 1 then
				for _, c in GroundTiles.children(nd) do
					if wanted(c) then
						add(c)
					end
				end
			end
			return
		end
		table.insert(leaves, nd)
		table.insert(needs, need(nd, want))
	end
	local function addRoot(ix: number, iz: number)
		local k = GroundTiles.key(top, ix, iz)
		if seen[k] then
			return
		end
		seen[k] = true
		add(GroundTiles.node(top, ix, iz))
	end
	for ix = math.floor((x - reach) / side), math.floor((x + reach) / side) do
		for iz = math.floor((z - reach) / side), math.floor((z + reach) / side) do
			if distTo(ix * side, iz * side, side, x, z) <= reach then
				addRoot(ix, iz)
			end
		end
	end
	for i = 1, #road, 3 do
		local rx, rz = road[i], road[i + 1]
		for ix = math.floor((rx - pad) / side), math.floor((rx + pad) / side) do
			for iz = math.floor((rz - pad) / side), math.floor((rz + pad) / side) do
				if distTo(ix * side, iz * side, side, rx, rz) <= pad then
					addRoot(ix, iz)
				end
			end
		end
	end
	local dists: { number } = {}
	for i, nd in leaves do
		dists[i] = distTo(nd.x0, nd.z0, nd.side, x, z)
	end
	local function split(bi: number)
		local nd = leaves[bi]
		local kids = GroundTiles.children(nd)
		local last = #leaves
		leaves[bi], needs[bi], dists[bi] = leaves[last], needs[last], dists[last]
		leaves[last], needs[last], dists[last] = nil :: any, nil :: any, nil :: any
		for _, c in kids do
			table.insert(leaves, c)
			table.insert(needs, need(c, want))
			table.insert(dists, distTo(c.x0, c.z0, c.side, x, z))
		end
	end
	-- first, whatever budget: no tile coarser than `RoadCoarsest` beside drawn road, so no
	-- coarse triangle can reach over it (`Clamps`)
	local coarsest, range = G.RoadCoarsest, G.RoadRange
	local function mustSplit(nd: Leaf): boolean
		if nd.s <= coarsest then
			return false
		end
		local r = nd.s * range
		for i = 1, #road, 3 do
			-- a point of road far from the car may allow coarser (`RoadFar`, T-263)
			if nd.s > math.max(coarsest, road[i + 2]) and distTo(nd.x0, nd.z0, nd.side, road[i], road[i + 1]) < r then
				return true
			end
		end
		return false
	end
	local i = 1
	while i <= #leaves and #leaves < want.tiles * 2 do
		if mustSplit(leaves[i]) then
			split(i) -- its children are appended, and checked in their turn
		else
			i += 1
		end
	end
	-- then, of the tiles that want splitting, the nearest the car first, while there is room
	-- for its three more: so when the budget runs out, what stays coarse is what is furthest
	while #leaves + 3 <= want.tiles do
		local best, bi = math.huge, 0
		for k, n in needs do
			if n > 1 and dists[k] < best then
				best, bi = dists[k], k
			end
		end
		if bi == 0 then
			break
		end
		split(bi)
	end
	local map: { [number]: Leaf } = {}
	for _, l in leaves do
		map[l.key] = l
	end
	return leaves, map
end

-- The tile of `map` holding (x, z), or nil.
function GroundTiles.leafAt(map: { [number]: Leaf }, x: number, z: number): Leaf?
	local G = Config.Spline.Ground
	for level = #G.Spacings, 1, -1 do
		local side = G.TileCells * G.Spacings[level]
		local l = map[GroundTiles.key(level, math.floor(x / side), math.floor(z / side))]
		if l then
			return l
		end
	end
	return nil
end

-- The tile of `map` that holds `leaf`'s square and is coarser than it, or nil.
function GroundTiles.above(map: { [number]: Leaf }, leaf: Leaf): Leaf?
	local G = Config.Spline.Ground
	for level = leaf.level + 1, #G.Spacings do
		local f = 2 ^ (level - leaf.level)
		local l = map[GroundTiles.key(level, leaf.ix // f, leaf.iz // f)]
		if l then
			return l
		end
	end
	return nil
end

-- The coarsest spacing among the tiles of `map` that touch the point (x, z): a vertex every
-- one of them shares takes its height the coarsest one's way. 0 if none.
function GroundTiles.spacingAround(map: { [number]: Leaf }, x: number, z: number): number
	local e = 0.01
	local s = 0
	for _, o in { { -e, -e }, { e, -e }, { -e, e }, { e, e } } do
		local l = GroundTiles.leafAt(map, x + o[1], z + o[2])
		if l and l.s > s then
			s = l.s
		end
	end
	return s
end

-- The finest and the coarsest spacing among the tiles of `map` that touch the point (x, z):
-- (math.huge, 0) if none. A vertex only tiles of one spacing touch can be moved (T-231).
function GroundTiles.spacingRange(map: { [number]: Leaf }, x: number, z: number): (number, number)
	local e = 0.01
	local lo, hi = math.huge, 0
	for _, o in { { -e, -e }, { e, -e }, { -e, e }, { e, e } } do
		local l = GroundTiles.leafAt(map, x + o[1], z + o[2])
		if l then
			lo = math.min(lo, l.s)
			hi = math.max(hi, l.s)
		end
	end
	return lo, hi
end

function GroundTiles.within(outer: Leaf, inner: Leaf): boolean
	return inner.x0 >= outer.x0 - 1e-6
		and inner.z0 >= outer.z0 - 1e-6
		and inner.x0 + inner.side <= outer.x0 + outer.side + 1e-6
		and inner.z0 + inner.side <= outer.z0 + outer.side + 1e-6
end

-- Do two squares touch or overlap (an edge or a corner in common counts)?
function GroundTiles.touches(a: Leaf, b: Leaf): boolean
	local e = 1e-6
	return a.x0 <= b.x0 + b.side + e
		and b.x0 <= a.x0 + a.side + e
		and a.z0 <= b.z0 + b.side + e
		and b.z0 <= a.z0 + a.side + e
end

return GroundTiles
