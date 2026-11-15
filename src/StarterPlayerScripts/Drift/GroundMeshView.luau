--!strict
-- Drift/GroundMeshView: the ground-first trial's option 1, our own mesh (features/ground-trial.md,
-- T-218; step T-220; drawn as tiles that follow the road since T-225). The mountain
-- `Road/Ground` describes, drawn round the car and along the road ahead, on this device only.
-- Purely visual: the car drives on the spline maths.
--
-- TILES. `Drift/GroundTiles` picks a quadtree of square tiles: fine near the car and along
-- the road ahead, coarser further out, as many as the player's "Ground detail" allows
-- (`Drift/GroundDetail`). Each tile is one fixed-size mesh of `TileCells` by `TileCells`
-- cells, copied from a flat one made once: a client holds only so many mesh triangles
-- (`Config.Spline.Ground` "THE BUDGET"), and a fixed-size copy costs only its size. A tile
-- never changes shape, only where its vertices are, so one pool of them serves every spacing.
--
-- A CHANGE IS SHOWN WHOLE. Each change (a tile splitting into four, four merging into one, a
-- new tile, one let go, tiles redrawn for new road) is built into hidden tiles over a few
-- frames, then swapped in within one frame, with its neighbours' edges put right in the same
-- frame.
--
-- NO CRACKS. Two tiles of one spacing share their edge's vertices, worked out the same way.
-- Where a tile meets a coarser one, its edge takes the coarser one's heights (straight lines
-- between the coarser vertices), and a vertex several tiles share takes its height the
-- coarsest one's way (`Clamps`, `Sinks`). So the edges agree exactly.
--
-- ROUND THE ROAD: every vertex sinks its spacing's `Sinks` under the road and its runoff, and one within
-- its spacing's `Clamp` of a runoff's edge is held below the edge, so no triangle reaching over
-- from a cutting covers the road. The road's skirt (`Road/SplineMesh`, a ground run) hides the
-- gap.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)
local GroundDetail = require(script.Parent.GroundDetail)
local GroundTiles = require(script.Parent.GroundTiles)

type Leaf = GroundTiles.Leaf

local GroundMeshView = {}
GroundMeshView.__index = GroundMeshView

type Tile = {
	em: EditableMesh,
	part: MeshPart,
	-- by grid index i * (n + 1) + j + 1 (i along x, j along z): the vertex and its own
	-- normal, colour and UV ids
	v: { number },
	nrm: { number },
	col: { number },
	uv: { number },
	leaf: Leaf?,
	heights: { number }, -- what is drawn, world y, by grid index
	cy: number, -- the part's height (vertices are written relative to it)
	stale: boolean,
}

type Op = {
	kind: string, -- "fill" | "split" | "merge" | "drop" | "stale"
	old: { Leaf },
	new: { Leaf },
	region: { Leaf },
}

type Master = { em: EditableMesh }

export type View = typeof(setmetatable(
	{} :: {
		spline: any,
		field: Ground.Field,
		folder: Folder,
		dead: boolean,
		failed: string?,
		paused: boolean, -- Studio checks only: build nothing
		running: boolean,
		carX: number,
		carZ: number,
		along: number?,
		checkedTo: number,
		master: Master?,
		pool: { Tile },
		free: { Tile },
		cap: number, -- tiles at most, shown and hidden
		failCap: number?, -- the device would make no more than this
		shown: { [number]: Leaf },
		tiles: { [number]: Tile }, -- by leaf key
		detail: number,
		dirty: boolean, -- the setting changed
		desired: { [number]: Leaf }?,
		desiredAt: Vector3?,
		desiredDetail: number,
		pending: { Op }, -- the changes still to make towards `desired`
		lastStale: boolean,
		sliceStart: number,
		work: number,
		changedConn: any,
		-- measured
		ops: { [string]: number },
		tilesBuilt: number,
		rimWrites: number,
		lastMs: number,
		worstMs: number,
		worstSliceMs: number,
		lastSlices: number,
		worstCommitMs: number,
		selectMs: number,
		totalWorkMs: number, -- all building and choosing, for the per-frame cost
		events: { { number } },
		slices: { number },
	},
	GroundMeshView
))

local HALF_SPAN = 400 -- studs: the template's height either way, so its box covers the mountain

local function cells(): number
	return Config.Spline.Ground.TileCells
end

local clampOf: { [number]: number } = {}
local sinkOf: { [number]: number } = {}
for k, s in Config.Spline.Ground.Spacings do
	clampOf[s] = Config.Spline.Ground.Clamps[k]
	sinkOf[s] = Config.Spline.Ground.Sinks[k]
end

-- The flat tile every tile is copied from: never shown, never moved. It spans the coarsest
-- tile, so every tile's bounds hold whatever it draws.
local function makeMaster(): Master?
	local G = Config.Spline.Ground
	local C = cells()
	local n = C + 1
	local sp = G.Spacings[#G.Spacings]
	local template = AssetService:CreateEditableMesh({ FixedSize = false })
	if not template then
		return nil
	end
	local ids = table.create(n * n)
	for i = 0, C do
		for j = 0, C do
			local y = 0
			if i == 0 and j == 0 then
				y = HALF_SPAN
			elseif i == C and j == C then
				y = -HALF_SPAN
			end
			ids[i * n + j + 1] = template:AddVertex(Vector3.new((i - C / 2) * sp, y, (j - C / 2) * sp))
		end
	end
	local nrm, col, uv = table.create(n * n), table.create(n * n), table.create(n * n)
	for k = 1, n * n do
		nrm[k] = template:AddNormal(Vector3.yAxis)
		col[k] = template:AddColor(Color3.new(1, 1, 1), 1)
		uv[k] = template:AddUV(Vector2.zero)
	end
	for i = 0, C - 1 do
		for j = 0, C - 1 do
			local a, b, c, d = i * n + j + 1, (i + 1) * n + j + 1, i * n + j + 2, (i + 1) * n + j + 2
			-- two triangles a cell, wound to face up, split along b-c
			for _, t in { { a, c, b }, { b, c, d } } do
				local f = template:AddTriangle(ids[t[1]], ids[t[2]], ids[t[3]])
				template:SetFaceNormals(f, { nrm[t[1]], nrm[t[2]], nrm[t[3]] })
				template:SetFaceColors(f, { col[t[1]], col[t[2]], col[t[3]] })
				template:SetFaceUVs(f, { uv[t[1]], uv[t[2]], uv[t[3]] })
			end
		end
	end
	local ok, em = pcall(function()
		return AssetService:CreateEditableMeshAsync(Content.fromObject(template), { FixedSize = true })
	end)
	template:Destroy()
	if not ok or not em then
		return nil
	end
	return { em = em :: EditableMesh }
end

local function makeTile(master: Master): Tile?
	local G = Config.Spline.Ground
	local C = cells()
	local n = C + 1
	local sp = G.Spacings[#G.Spacings]
	local ok, em = pcall(function()
		return AssetService:CreateEditableMeshAsync(Content.fromObject(master.em), { FixedSize = true })
	end)
	if not ok or not em then
		return nil
	end
	local copy = em :: EditableMesh
	-- the copy's own ids, found by where each vertex is and what its faces name
	local v, cn, cc, cu = table.create(n * n), table.create(n * n), table.create(n * n), table.create(n * n)
	for _, f in copy:GetFaces() do
		local vs = copy:GetFaceVertices(f)
		local ns = copy:GetFaceNormals(f)
		local cs = copy:GetFaceColors(f)
		local us = copy:GetFaceUVs(f)
		for q = 1, 3 do
			local p = copy:GetPosition(vs[q])
			local k = math.round(p.X / sp + C / 2) * n + math.round(p.Z / sp + C / 2) + 1
			v[k], cn[k], cc[k], cu[k] = vs[q], ns[q], cs[q], us[q]
		end
	end
	local ok2, part = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(copy), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)
	if not ok2 or not part then
		copy:Destroy()
		return nil
	end
	local mp = part :: MeshPart
	mp.Name = "GroundTile"
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = false
	mp.Material = Enum.Material.Grass
	mp.Color = Color3.new(1, 1, 1)
	return {
		em = copy,
		part = mp,
		v = v,
		nrm = cn,
		col = cc,
		uv = cu,
		leaf = nil,
		heights = table.create(n * n, 0),
		cy = 0,
		stale = false,
	}
end

function GroundMeshView.new(spline: any, parent: Instance?): View
	local folder = Instance.new("Folder")
	folder.Name = "GroundMesh"
	folder.Parent = parent or Workspace
	local self = setmetatable({
		spline = spline,
		field = spline.mountain,
		folder = folder,
		dead = false,
		failed = nil,
		paused = false,
		running = false,
		carX = spline.origin.x,
		carZ = spline.origin.z,
		along = nil,
		checkedTo = spline.length,
		master = nil,
		pool = {},
		free = {},
		cap = 0,
		failCap = nil,
		shown = {},
		tiles = {},
		detail = GroundDetail.get(),
		dirty = false,
		desired = nil,
		desiredAt = nil,
		desiredDetail = 0,
		pending = {},
		lastStale = false,
		sliceStart = 0,
		work = 0,
		changedConn = nil,
		ops = { fill = 0, split = 0, merge = 0, drop = 0, stale = 0 },
		tilesBuilt = 0,
		rimWrites = 0,
		lastMs = 0,
		worstMs = 0,
		worstSliceMs = 0,
		lastSlices = 0,
		worstCommitMs = 0,
		selectMs = 0,
		totalWorkMs = 0,
		events = {},
		slices = {},
	}, GroundMeshView)
	self:_setCap()
	self.changedConn = GroundDetail.Changed:Connect(function(value: number)
		self.detail = value
		self.dirty = true
		self:_setCap()
	end)
	return self
end

function GroundMeshView._setCap(self: View)
	local G = Config.Spline.Ground
	local cap = GroundDetail.preset(self.detail).Tiles + G.Spare
	if self.failCap then
		cap = math.min(cap, self.failCap)
	end
	self.cap = cap
end

-- How many tiles may show: the setting's, or fewer if this device would not make that many.
function GroundMeshView._leafBudget(self: View): number
	return math.max(4, math.min(GroundDetail.preset(self.detail).Tiles, self.cap - Config.Spline.Ground.Spare))
end

--------------------------------------------------------------------------------
-- Building, a few ms a frame
--------------------------------------------------------------------------------

function GroundMeshView._slice(self: View)
	local G = Config.Spline.Ground
	local now = os.clock()
	local budget = (if next(self.shown) == nil then G.FirstSliceMs else G.MeshSliceMs) / 1000
	if now - self.sliceStart > budget then
		local ms = (now - self.sliceStart) * 1000
		self.work += now - self.sliceStart
		self.worstSliceMs = math.max(self.worstSliceMs, ms)
		if #self.slices < 4000 then
			table.insert(self.slices, ms)
		end
		self.lastSlices += 1
		task.wait()
		self.sliceStart = os.clock()
	end
end

-- The height a vertex takes at (x, z), done the way tiles of spacing `s` do it: the ground,
-- sunk under the road, and held below the edge within that spacing's clamp of it.
local function vertexHeight(ctx: Ground.Context, s: number, x: number, z: number): number
	local y, a, e, T = Ground.at(ctx, x, z)
	local sink = sinkOf[s]
	y -= sink * a
	if e < clampOf[s] then
		y = math.min(y, T - sink)
	end
	return y
end

-- The heights of a tile's rim, given the tiles round it (`map`): {grid index -> y}.
-- Along an edge that meets a coarser tile, straight between that tile's vertices; every rim
-- vertex clamped the way the coarsest tile touching it is.
local function rimHeights(ctx: Ground.Context, leaf: Leaf, map: { [number]: Leaf }, own: { number }?): { [number]: number }
	local C = cells()
	local n = C + 1
	local s, x0, z0, side = leaf.s, leaf.x0, leaf.z0, leaf.side
	local e = 0.5
	local mid = side * 0.5
	-- the spacing across each edge, if coarser than this tile's
	local function across(px: number, pz: number): number
		local l = GroundTiles.leafAt(map, px, pz)
		return if l and l.s > s then l.s else 0
	end
	local west, east = across(x0 - e, z0 + mid), across(x0 + side + e, z0 + mid)
	local south, north = across(x0 + mid, z0 - e), across(x0 + mid, z0 + side + e)
	local cache: { [number]: number } = {}
	local function H(x: number, z: number): number
		local key = math.round(x * 2) * 4194304 + math.round(z * 2)
		local y = cache[key]
		if y then
			return y
		end
		local sm = GroundTiles.spacingAround(map, x, z)
		if sm < s then
			sm = s
		end
		y = vertexHeight(ctx, sm, x, z)
		cache[key] = y
		return y
	end
	local out: { [number]: number } = {}
	local function vertex(i: number, j: number)
		local x, z = x0 + i * s, z0 + j * s
		local S = 0
		local along, alongStart = 0, 0
		if i == 0 then
			S, along, alongStart = west, j * s, z0
		elseif i == C then
			S, along, alongStart = east, j * s, z0
		elseif j == 0 then
			S, along, alongStart = south, i * s, x0
		else
			S, along, alongStart = north, i * s, x0
		end
		local y
		local r = if S > 0 then along % S else 0
		if S > 0 and r > 1e-6 and (i ~= 0 and i ~= C or j ~= 0 and j ~= C) then
			local a0 = alongStart + along - r
			local f = r / S
			if i == 0 or i == C then
				y = H(x, a0) * (1 - f) + H(x, a0 + S) * f
			else
				y = H(a0, z) * (1 - f) + H(a0 + S, z) * f
			end
		else
			local sm = GroundTiles.spacingAround(map, x, z)
			if sm <= s and own then
				y = own[(i + 1) * (n + 2) + (j + 1) + 1]
			else
				y = H(x, z)
			end
		end
		out[i * n + j + 1] = y
	end
	for t = 0, C do
		vertex(0, t)
		vertex(C, t)
		if t > 0 and t < C then
			vertex(t, 0)
			vertex(t, C)
		end
	end
	return out
end

-- Fill a hidden tile with `leaf`'s ground, given the tiles it will sit among (`map`).
function GroundMeshView._fill(self: View, tile: Tile, leaf: Leaf, map: { [number]: Leaf }): boolean
	local G = Config.Spline.Ground
	local C = cells()
	local n = C + 1
	local m = n + 2 -- with a row of apron each side, for the normals
	local s, x0, z0 = leaf.s, leaf.x0, leaf.z0
	local ctx = Ground.context(self.field, self.spline, x0 - s, z0 - s, x0 + leaf.side + s, z0 + leaf.side + s)
	self:_slice()
	-- every vertex and the apron, this tile's own way
	local own = table.create(m * m)
	for i = -1, C + 1 do
		if self.dead then
			return false
		end
		local x = x0 + i * s
		for j = -1, C + 1 do
			own[(i + 1) * m + (j + 1) + 1] = vertexHeight(ctx, s, x, z0 + j * s)
		end
		self:_slice()
	end
	local heights = table.create(n * n)
	for i = 0, C do
		for j = 0, C do
			heights[i * n + j + 1] = own[(i + 1) * m + (j + 1) + 1]
		end
	end
	for k, y in rimHeights(ctx, leaf, map, own) do
		heights[k] = y
	end
	self:_slice()
	-- normals from the tile's own heights (the apron gives the edge ones), colours by slope
	local cx, cz = x0 + leaf.side * 0.5, z0 + leaf.side * 0.5
	local cy = Ground.base(self.field, cx, cz)
	local rockY = math.cos(math.rad(G.RockAngle))
	local g1, g2, rock = G.GrassColours[1], G.GrassColours[2], G.GroundRockColour
	local uvStuds = G.UVStuds
	local em = tile.em
	for i = 0, C do
		local x = x0 + i * s
		for j = 0, C do
			local k = i * n + j + 1
			local z = z0 + j * s
			local q = (i + 1) * m + (j + 1) + 1
			local dydx = (own[q + m] - own[q - m]) / (2 * s)
			local dydz = (own[q + 1] - own[q - 1]) / (2 * s)
			local nv = Vector3.new(-dydx, 1, -dydz).Unit
			local colour
			if nv.Y < rockY then
				colour = rock
			else
				local blotch = math.clamp(0.5 + 1.6 * math.noise(x / 70, z / 70, 3.37), 0, 1)
				colour = g1:Lerp(g2, blotch)
			end
			em:SetPosition(tile.v[k], Vector3.new(x - cx, heights[k] - cy, z - cz))
			em:SetNormal(tile.nrm[k], nv)
			em:SetColor(tile.col[k], colour)
			em:SetUV(tile.uv[k], Vector2.new(x / uvStuds, z / uvStuds))
		end
		self:_slice()
	end
	tile.part.CFrame = CFrame.new(cx, cy, cz)
	tile.leaf = leaf
	tile.heights = heights
	tile.cy = cy
	tile.stale = false
	self.tilesBuilt += 1
	return true
end

-- A shown tile's rim, worked out again among `map`: the vertices that would move.
function GroundMeshView._rimChanges(self: View, tile: Tile, map: { [number]: Leaf }): { { number } }
	local leaf = tile.leaf :: Leaf
	local s = leaf.s
	local ctx = Ground.context(self.field, self.spline, leaf.x0 - s, leaf.z0 - s, leaf.x0 + leaf.side + s, leaf.z0 + leaf.side + s)
	self:_slice()
	local changes = {}
	for k, y in rimHeights(ctx, leaf, map, nil) do
		if math.abs(y - tile.heights[k]) > 1e-4 then
			table.insert(changes, { k, y })
		end
	end
	self:_slice()
	return changes
end

-- A tile from the pool, or a new one; nil if the device will make no more. `over`: a change
-- that lets go of more tiles than it takes may go past the cap for a moment (a lower
-- setting turns the pool into merges, each needing one tile before it frees four).
function GroundMeshView._take(self: View, over: boolean?): Tile?
	local t = table.remove(self.free)
	if t then
		return t
	end
	if #self.pool >= self.cap and not over then
		return nil
	end
	if not self.master then
		self.master = makeMaster()
		if not self.master then
			self.failed = "this device would not make the ground's mesh"
			return nil
		end
	end
	local tile = makeTile(self.master :: Master)
	if not tile then
		-- the budget is full: hold what there is, less a few for the road
		local G = Config.Spline.Ground
		self.failCap = math.max(G.Spare + 4, #self.pool - G.ReleaseOnFail)
		self:_setCap()
		return nil
	end
	table.insert(self.pool, tile)
	return tile
end

-- Let go of hidden tiles past the cap (a lower setting, or a full budget), for the road.
function GroundMeshView._trim(self: View)
	while #self.pool > self.cap and #self.free > 0 do
		local t = table.remove(self.free) :: Tile
		local i = table.find(self.pool, t)
		if i then
			table.remove(self.pool, i)
		end
		t.part:Destroy()
		t.em:Destroy()
	end
end

--------------------------------------------------------------------------------
-- What to change next
--------------------------------------------------------------------------------

-- The car's place along the road, followed from frame to frame.
function GroundMeshView._locate(self: View)
	local spline = self.spline
	local s
	if self.along then
		s = spline:projectFrom(self.carX, self.carZ, self.along)
	end
	if not s then
		s = spline:project(self.carX, self.carZ, 200)
	end
	if s then
		self.along = s
	end
end

function GroundMeshView._want(self: View): GroundTiles.Want
	local G = Config.Spline.Ground
	local M = Config.Spline.Mesh
	local P = GroundDetail.preset(self.detail)
	local road = {}
	local along = self.along
	local spline = self.spline
	if along then
		-- as far as the road is drawn: 8 studs out to `Fine` along it, then coarser
		local first = spline.firstSample * spline.step
		local s0 = math.max(first, along - M.Behind)
		local s1 = math.min(spline.length, along + M.Ahead)
		local s = s0
		while s <= s1 do
			local x, z = spline:planAt(s)
			local w = math.min(G.Spacings[1] * math.max(1, math.abs(s - along) / P.Fine), G.RoadCoarsest)
			table.insert(road, x)
			table.insert(road, z)
			table.insert(road, w)
			s += G.RoadStep
		end
	end
	local split: { [number]: boolean } = {}
	for _, leaf in self.shown do
		local p = GroundTiles.parent(leaf)
		while p and not split[p.key] do
			split[p.key] = true
			p = GroundTiles.parent(p)
		end
	end
	return {
		x = self.carX,
		z = self.carZ,
		road = road,
		tiles = self:_leafBudget(),
		ratio = P.Ratio,
		reach = P.Reach,
		split = split,
	}
end

function GroundMeshView._desired(self: View): { [number]: Leaf }
	local at = Vector3.new(self.carX, 0, self.carZ)
	local G = Config.Spline.Ground
	if not self.desired or self.dirty or self.desiredDetail ~= self.detail or not self.desiredAt or (at - self.desiredAt).Magnitude > G.Reselect then
		local t0 = os.clock()
		local _, map = GroundTiles.select(self:_want())
		self.selectMs = (os.clock() - t0) * 1000
		self.totalWorkMs += self.selectMs
		self.desired = map
		self.desiredAt = at
		self.desiredDetail = self.detail
		self.dirty = false
		self.pending = {}
	end
	return self.desired :: { [number]: Leaf }
end

-- Every place the shown tiles differ from the wanted ones, as one change each (the coarsest
-- tile round it), nearest the car first. They never overlap, so they can be done in turn.
function GroundMeshView._diff(self: View, desired: { [number]: Leaf }): { Op }
	local G = Config.Spline.Ground
	local shown = self.shown
	local roots: { [number]: Leaf } = {}
	for k, leaf in desired do
		if not shown[k] then
			local r = GroundTiles.above(shown, leaf) or leaf
			roots[r.key] = r
		end
	end
	for k, leaf in shown do
		if not desired[k] then
			local r = GroundTiles.above(desired, leaf) or leaf
			roots[r.key] = r
		end
	end
	local list: { Op } = {}
	for _, root in roots do
		local old, new = {}, {}
		for _, l in shown do
			if GroundTiles.within(root, l) then
				table.insert(old, l)
			end
		end
		for _, l in desired do
			if GroundTiles.within(root, l) then
				table.insert(new, l)
			end
		end
		local kind = if #old == 0 then "fill" elseif #new == 0 then "drop" elseif shown[root.key] then "split" else "merge"
		if kind == "split" and #new > G.Spare then
			new = GroundTiles.children(root) -- a step at a time
		end
		table.insert(list, { kind = kind, old = old, new = new, region = { root } })
	end
	local cx, cz = self.carX, self.carZ
	local function dist(l: Leaf): number
		return GroundTiles.distTo(l.x0, l.z0, l.side, cx, cz)
	end
	table.sort(list, function(a, b)
		return dist(a.region[1]) < dist(b.region[1])
	end)
	return list
end

function GroundMeshView._nextOp(self: View): Op?
	local G = Config.Spline.Ground
	local desired = self:_desired()
	local room = #self.free + math.max(0, self.cap - #self.pool)
	-- tiles to redraw for new road, between the changes
	local stale = {}
	for k, tile in self.tiles do
		if tile.stale and desired[k] then
			table.insert(stale, tile.leaf :: Leaf)
		end
	end
	if #self.pending == 0 then
		self.pending = self:_diff(desired)
	end
	local list = self.pending
	if #stale > 0 and (self.lastStale == false or #list == 0) and room >= 1 then
		local cx, cz = self.carX, self.carZ
		table.sort(stale, function(a, b)
			return GroundTiles.distTo(a.x0, a.z0, a.side, cx, cz) < GroundTiles.distTo(b.x0, b.z0, b.side, cx, cz)
		end)
		local batch = {}
		for i = 1, math.min(#stale, room, G.Spare) do
			batch[i] = stale[i]
		end
		self.lastStale = true
		return { kind = "stale", old = batch, new = batch, region = batch }
	end
	self.lastStale = false
	for i, op in list do
		if #op.new <= room then
			table.remove(list, i)
			return op
		end
	end
	-- nothing that adds tiles fits: free some first
	for i, op in list do
		if #op.new <= 1 and #op.old >= #op.new then
			table.remove(list, i)
			return op
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------------

function GroundMeshView._do(self: View, op: Op): boolean
	local t0 = os.clock()
	self.work = 0
	self.lastSlices = 1
	self.sliceStart = t0
	local length = self.spline.length
	-- what will show once it is done
	local future: { [number]: Leaf } = table.clone(self.shown)
	for _, l in op.old do
		future[l.key] = nil
	end
	local newKeys: { [number]: boolean } = {}
	for _, l in op.new do
		future[l.key] = l
		newKeys[l.key] = true
	end
	-- the new tiles, hidden
	local built: { Tile } = {}
	for _, leaf in op.new do
		local tile = self:_take(#op.old > #op.new)
		if not tile then
			for _, t in built do
				table.insert(self.free, t)
			end
			return false
		end
		table.insert(built, tile)
		if not self:_fill(tile, leaf, future) then
			for _, t in built do
				table.insert(self.free, t)
			end
			return false
		end
	end
	-- the tiles round it whose edges change
	local pending: { { any } } = {}
	for k, leaf in future do
		if not newKeys[k] then
			local touching = false
			for _, r in op.region do
				if GroundTiles.touches(leaf, r) then
					touching = true
					break
				end
			end
			local tile = self.tiles[k]
			if touching and tile then
				local changes = self:_rimChanges(tile, future)
				if #changes > 0 then
					table.insert(pending, { tile, changes })
				end
			end
		end
		if self.dead then
			return false
		end
	end
	if self.dead then
		return false
	end
	-- swap it in, all in this frame
	local c0 = os.clock()
	local oldTiles: { Tile } = {}
	for _, l in op.old do
		local t = self.tiles[l.key]
		if t then
			table.insert(oldTiles, t)
			self.tiles[l.key] = nil
		end
	end
	for _, tile in built do
		local leaf = tile.leaf :: Leaf
		self.tiles[leaf.key] = tile
		tile.part.Parent = self.folder
		if self.spline.length ~= length then
			tile.stale = true -- road arrived while it was built
		end
	end
	for _, t in oldTiles do
		t.part.Parent = nil
		t.leaf = nil
		t.stale = false
		table.insert(self.free, t)
	end
	local C = cells()
	local n = C + 1
	for _, p in pending do
		local tile, changes = p[1] :: Tile, p[2] :: { { number } }
		local leaf = tile.leaf :: Leaf
		local cx, cz = leaf.x0 + leaf.side * 0.5, leaf.z0 + leaf.side * 0.5
		for _, ch in changes do
			local k, y = ch[1], ch[2]
			local i, j = (k - 1) // n, (k - 1) % n
			tile.heights[k] = y
			tile.em:SetPosition(tile.v[k], Vector3.new(leaf.x0 + i * leaf.s - cx, y - tile.cy, leaf.z0 + j * leaf.s - cz))
			self.rimWrites += 1
		end
	end
	self.shown = future
	self.worstCommitMs = math.max(self.worstCommitMs, (os.clock() - c0) * 1000)
	self.work += os.clock() - self.sliceStart
	self.lastMs = self.work * 1000
	self.totalWorkMs += self.lastMs
	self.worstMs = math.max(self.worstMs, self.lastMs)
	self.ops[op.kind] += 1
	if #self.events < 4000 then
		table.insert(self.events, { os.clock(), #op.new, #op.old })
	end
	return true
end

-- New road laid since the last look: the shown tiles it comes near are redrawn.
function GroundMeshView._checkNewRoad(self: View)
	local spline = self.spline
	local from, to = self.checkedTo, spline.length
	if to <= from + 1e-6 then
		return
	end
	self.checkedTo = to
	local reach = Ground.reach()
	for s = math.max(0, from - 16), to, 16 do
		local x, z = spline:planAt(s)
		for _, tile in self.tiles do
			local l = tile.leaf
			if l and not tile.stale and GroundTiles.distTo(l.x0, l.z0, l.side, x, z) < reach then
				tile.stale = true
			end
		end
	end
	self.desired = nil -- the road ahead may reach further now
end

function GroundMeshView._run(self: View)
	self.running = true
	while not self.dead and not self.paused do
		self:_checkNewRoad()
		local op = self:_nextOp()
		if not op then
			break
		end
		if not self:_do(op) then
			if self.failed then
				break
			end
			-- no tile to be had: settle for fewer, and try again next frame
			self.desired = nil
		end
		self:_trim()
		task.wait()
	end
	self:_trim()
	self.running = false
end

-- Each frame, with the car's position.
function GroundMeshView.Update(self: View, x: number, z: number)
	if self.dead or self.failed or self.paused then
		return
	end
	self.carX, self.carZ = x, z
	self:_locate()
	if not self.running then
		self:_checkNewRoad()
		local at = self.desiredAt
		local moved = not at or (Vector3.new(x, 0, z) - at).Magnitude > 8
		local stale = false
		for _, tile in self.tiles do
			if tile.stale then
				stale = true
				break
			end
		end
		if moved or stale or self.dirty or self.desired == nil or #self.pool > self.cap then
			self.running = true
			task.spawn(function()
				local ok, err = pcall(self._run, self)
				if not ok then
					self.failed = tostring(err)
					self.running = false
					warn(`[GroundMeshView] {err}`)
				end
			end)
		end
	end
end

function GroundMeshView.Destroy(self: View)
	self.dead = true
	if self.changedConn then
		self.changedConn:Disconnect()
	end
	for _, tile in self.pool do
		tile.part:Destroy()
		tile.em:Destroy()
	end
	self.pool, self.free, self.tiles, self.shown = {}, {}, {}, {}
	if self.master then
		self.master.em:Destroy()
		self.master = nil
	end
	self.folder:Destroy()
end

--------------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------------

-- The drawn ground's height at (x, z) in a tile, as its triangles have it.
local function surfaceAt(tile: Tile, x: number, z: number): number
	local leaf = tile.leaf :: Leaf
	local C = cells()
	local n = C + 1
	local fx, fz = (x - leaf.x0) / leaf.s, (z - leaf.z0) / leaf.s
	local i = math.clamp(math.floor(fx), 0, C - 1)
	local j = math.clamp(math.floor(fz), 0, C - 1)
	local u, w = fx - i, fz - j
	local h = tile.heights
	local ha, hb, hc, hd = h[i * n + j + 1], h[(i + 1) * n + j + 1], h[i * n + j + 2], h[(i + 1) * n + j + 2]
	if u + w <= 1 then
		return ha + (hb - ha) * u + (hc - ha) * w
	end
	return hd + (hc - hd) * (1 - u) + (hb - hd) * (1 - w)
end

function GroundMeshView._tileAt(self: View, x: number, z: number): Tile?
	local l = GroundTiles.leafAt(self.shown, x, z)
	return if l then self.tiles[l.key] else nil
end

-- How far along the road ahead of the car its middle (and points `side` studs either way of
-- it) lie in tiles of `level` or finer.
function GroundMeshView.DebugReach(self: View, level: number, side: number?): number
	local spline = self.spline
	local along = self.along
	if not along then
		return 0
	end
	local s = along
	while s < spline.length do
		local x, z = spline:planAt(s)
		local yaw = spline:yawAt(s)
		for _, d in { 0, side or 0, -(side or 0) } do
			local l = GroundTiles.leafAt(self.shown, x + d * math.cos(yaw), z - d * math.sin(yaw))
			if not l or l.level > level then
				return s - along
			end
		end
		s += 8
	end
	return s - along
end

-- Where two shown tiles meet: the biggest height difference along their shared edges, sampled
-- every stud; and the drawn ground's highest point above the road or runoff, sampled along it.
function GroundMeshView.DebugSeams(self: View, roadAhead: number?)
	local list = {}
	for _, tile in self.tiles do
		if tile.leaf then
			table.insert(list, tile)
		end
	end
	local worst, edgePairs, samples = 0, 0, 0
	local worstAt = nil
	for a = 1, #list do
		local A = list[a]
		local la = A.leaf :: Leaf
		for b = a + 1, #list do
			local B = list[b]
			local lb = B.leaf :: Leaf
			-- a shared vertical edge (x) or horizontal (z), with some length in common
			local shared = nil
			if math.abs(la.x0 + la.side - lb.x0) < 1e-6 or math.abs(lb.x0 + lb.side - la.x0) < 1e-6 then
				local x = if math.abs(la.x0 + la.side - lb.x0) < 1e-6 then lb.x0 else la.x0
				local z0, z1 = math.max(la.z0, lb.z0), math.min(la.z0 + la.side, lb.z0 + lb.side)
				if z1 > z0 then
					shared = { x, z0, x, z1 }
				end
			elseif math.abs(la.z0 + la.side - lb.z0) < 1e-6 or math.abs(lb.z0 + lb.side - la.z0) < 1e-6 then
				local z = if math.abs(la.z0 + la.side - lb.z0) < 1e-6 then lb.z0 else la.z0
				local x0, x1 = math.max(la.x0, lb.x0), math.min(la.x0 + la.side, lb.x0 + lb.side)
				if x1 > x0 then
					shared = { x0, z, x1, z }
				end
			end
			if shared then
				edgePairs += 1
				local len = math.max(math.abs(shared[3] - shared[1]), math.abs(shared[4] - shared[2]))
				for t = 0, len do
					local f = t / len
					local x = shared[1] + (shared[3] - shared[1]) * f
					local z = shared[2] + (shared[4] - shared[2]) * f
					local d = math.abs(surfaceAt(A, x, z) - surfaceAt(B, x, z))
					samples += 1
					if d > worst then
						worst = d
						worstAt = { x, z, la.s, lb.s }
					end
				end
			end
		end
	end
	-- the road: centre line, tarmac edges and runoff edges, every 4 studs ahead
	local spline = self.spline
	local half = Config.Road.Width * 0.5
	local above, roadSamples = -math.huge, 0
	local aboveBySpacing: { [string]: number } = {}
	local aboveAt = nil
	if self.along then
		local s = math.max(self.along - 300, spline.firstSample * spline.step)
		local s1 = math.min(spline.length, self.along + (roadAhead or 1600))
		while s <= s1 do
			for _, side in { -1, 1 } do
				local w = spline:runoffAt(s, side)
				for _, d in { 0, half, half + w * 0.5, half + w - 0.05 } do
					local x, y, z = spline:terrainXYZ(s, side * d)
					local tile = self:_tileAt(x, z)
					if tile then
						local g = surfaceAt(tile, x, z)
						local sk = tostring((tile.leaf :: Leaf).s)
						aboveBySpacing[sk] = math.max(aboveBySpacing[sk] or -math.huge, g - y)
						roadSamples += 1
						if g - y > above then
							above = g - y
							aboveAt = { s - self.along, side * d, (tile.leaf :: Leaf).s }
						end
					end
				end
			end
			s += 4
		end
	end
	return {
		tilePairs = edgePairs,
		edgeSamples = samples,
		worstStep = worst,
		worstAt = worstAt,
		roadSamples = roadSamples,
		highestAboveRoad = above,
		highestAboveRoadBySpacing = aboveBySpacing,
		highestAt = aboveAt,
	}
end

function GroundMeshView.DebugState(self: View)
	local byLevel = {}
	local count = 0
	for _, l in self.shown do
		byLevel[l.s] = (byLevel[l.s] or 0) + 1
		count += 1
	end
	local perTile = cells() * cells() * 2
	local nv = (cells() + 1) ^ 2
	return {
		detail = self.detail,
		detailName = GroundDetail.name(self.detail),
		shown = count,
		bySpacing = byLevel,
		pool = #self.pool,
		free = #self.free,
		cap = self.cap,
		failCap = self.failCap,
		trianglesShown = count * perTile,
		trianglesHeld = #self.pool * perTile,
		verticesShown = count * nv,
		verticesHeld = #self.pool * nv,
		along = self.along,
		fineAhead = self:DebugReach(1, 0),
		fineAheadCorridor = self:DebugReach(1, 40),
		mediumAhead = self:DebugReach(2, 40),
		coarseAhead = self:DebugReach(3, 100),
		seams = self:DebugSeams(Config.Spline.Mesh.Ahead),
		failed = self.failed,
		running = self.running,
		paused = self.paused,
		ops = self.ops,
		tilesBuilt = self.tilesBuilt,
		rimWrites = self.rimWrites,
		lastMs = self.lastMs,
		worstMs = self.worstMs,
		worstSliceMs = self.worstSliceMs,
		lastSlices = self.lastSlices,
		worstCommitMs = self.worstCommitMs,
		selectMs = self.selectMs,
		totalWorkMs = self.totalWorkMs,
		events = self.events,
		slices = self.slices,
	}
end

return GroundMeshView
