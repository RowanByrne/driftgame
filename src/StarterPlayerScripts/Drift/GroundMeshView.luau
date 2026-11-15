--!strict
-- Drift/GroundMeshView: the ground-first trial's option 1, our own mesh (features/ground-trial.md,
-- T-218, step T-220). The mountain `Road/Ground` describes, drawn round the car as nested
-- square grids, on this device only. Purely visual: the car drives on the spline maths.
--
-- EACH LEVEL IS ONE FIXED-SIZE MESH, copied from a flat grid made once: a client holds only
-- so many mesh vertices (measured in the lane: a fixed-size copy costs by its size, a
-- growable mesh far more, and the road's chunks are growable), so the grids are lean and
-- never change shape, only where their vertices are.
--
-- THE FINER GRID LIES OVER A HOLE in the coarser one. Its rim takes the coarser grid's
-- heights (sampled at the coarser vertices, straight lines between), and the coarser
-- vertices strictly inside it drop `HoleSink` studs, so the two meet without a crack. The
-- finer grid has two copies: one shown while the other is filled in over a few frames, then
-- they swap, so a recentre never shows half done.
--
-- ROUND THE ROAD: every vertex sinks `GridSink` under the road and its runoff, and one within
-- `Clamp` of a runoff's edge is held below the edge, so no triangle reaching over from a
-- cutting covers the road. The road's skirt (`Road/SplineMesh`, a ground run) hides the gap.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)

local GroundMeshView = {}
GroundMeshView.__index = GroundMeshView

type Copy = {
	em: EditableMesh,
	part: MeshPart,
	-- by grid index i * (n + 1) + j: the vertex and its own normal, colour and UV ids
	v: { number },
	nrm: { number },
	col: { number },
	uv: { number },
}

type Level = {
	index: number,
	spacing: number,
	cells: number,
	n: number, -- vertices along a side (cells + 1)
	recentre: number,
	clamp: number,
	copies: { Copy },
	shown: number, -- which copy is shown (0 none yet)
	cx: number, -- the shown copy's middle
	cz: number,
	heights: { number }, -- the shown copy's heights, by grid index (the coarse grid's, unsunk)
	stale: boolean, -- new road came into its square
	builds: number,
}

export type View = typeof(setmetatable(
	{} :: {
		spline: any,
		field: Ground.Field,
		folder: Folder,
		levels: { Level },
		dead: boolean,
		failed: string?,
		carX: number,
		carZ: number,
		checkedTo: number,
		running: boolean,
		lastMs: number, -- work in the last build, not counting the frames between
		worstMs: number,
		worstSliceMs: number,
		lastSlices: number,
		applyMs: number, -- the write into the hidden copy, start to end (frames between included)
		worstApplyMs: number,
		vertices: number,
		-- for the frame-time checks: when each grid swapped in, and its level, and the
		-- clock time of each slice's yield
		events: { { number } },
		paused: boolean, -- Studio checks only: build nothing
		slices: { number }, -- how long each slice of building took, ms (the last 4 000)
	},
	GroundMeshView
))

local HALF_SPAN = 400 -- studs: the template's height either way, so its box covers the mountain

local function makeCopy(level: Level, name: string): Copy?
	local n, sp, cells = level.n, level.spacing, level.cells
	local template = AssetService:CreateEditableMesh({ FixedSize = false })
	if not template then
		return nil
	end
	local ids = table.create(n * n)
	for i = 0, cells do
		for j = 0, cells do
			local y = 0
			if i == 0 and j == 0 then
				y = HALF_SPAN
			elseif i == cells and j == cells then
				y = -HALF_SPAN
			end
			ids[i * n + j + 1] = template:AddVertex(Vector3.new((i - cells / 2) * sp, y, (j - cells / 2) * sp))
		end
	end
	local nrm, col, uv = table.create(n * n), table.create(n * n), table.create(n * n)
	for k = 1, n * n do
		nrm[k] = template:AddNormal(Vector3.yAxis)
		col[k] = template:AddColor(Color3.new(1, 1, 1), 1)
		uv[k] = template:AddUV(Vector2.zero)
	end
	for i = 0, cells - 1 do
		for j = 0, cells - 1 do
			local a, b, c, d = i * n + j + 1, (i + 1) * n + j + 1, i * n + j + 2, (i + 1) * n + j + 2
			-- two triangles a cell, wound to face up
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
	if not ok or not em then
		template:Destroy()
		return nil
	end
	template:Destroy()
	local copy = em :: EditableMesh
	-- the copy's own ids, found by where each vertex is and what its faces name
	local v, cn, cc, cu = table.create(n * n), table.create(n * n), table.create(n * n), table.create(n * n)
	local function indexOf(id: number): number
		local p = copy:GetPosition(id)
		local i = math.round(p.X / sp + cells / 2)
		local j = math.round(p.Z / sp + cells / 2)
		return i * n + j + 1
	end
	for _, f in copy:GetFaces() do
		local vs = copy:GetFaceVertices(f)
		local ns = copy:GetFaceNormals(f)
		local cs = copy:GetFaceColors(f)
		local us = copy:GetFaceUVs(f)
		for q = 1, 3 do
			local k = indexOf(vs[q])
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
	mp.Name = name
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = false
	mp.Material = Enum.Material.Grass
	mp.Color = Color3.new(1, 1, 1)
	return { em = copy, part = mp, v = v, nrm = cn, col = cc, uv = cu }
end

function GroundMeshView.new(spline: any, parent: Instance?): View
	local G = Config.Spline.Ground
	local folder = Instance.new("Folder")
	folder.Name = "GroundMesh"
	folder.Parent = parent or Workspace
	local levels: { Level } = {}
	for index, L in G.Levels do
		table.insert(levels, {
			index = index,
			spacing = L.Spacing,
			cells = L.Cells,
			n = L.Cells + 1,
			recentre = L.Recentre,
			clamp = L.Clamp,
			copies = {},
			shown = 0,
			cx = 0,
			cz = 0,
			heights = {},
			stale = false,
			builds = 0,
		})
	end
	local self = setmetatable({
		spline = spline,
		field = spline.mountain,
		folder = folder,
		levels = levels,
		dead = false,
		failed = nil,
		carX = spline.origin.x,
		carZ = spline.origin.z,
		checkedTo = spline.length,
		running = false,
		lastMs = 0,
		worstMs = 0,
		worstSliceMs = 0,
		lastSlices = 0,
		applyMs = 0,
		worstApplyMs = 0,
		vertices = 0,
		events = {},
		paused = false,
		slices = {},
	}, GroundMeshView)
	return self
end

-- The height a level's vertex takes at (x, z): the ground, sunk under the road, and held
-- below the edge within `clamp` of it.
local function vertexHeight(ctx: Ground.Context, clamp: number, x: number, z: number): number
	local G = Config.Spline.Ground
	local y, a, e, T = Ground.at(ctx, x, z)
	y -= G.GridSink * a
	if e < clamp then
		y = math.min(y, T - G.GridSink)
	end
	return y
end

local function snap(v: number, step: number): number
	return math.round(v / step) * step
end

-- Is (x, z) strictly inside the shown finer grid's square?
local function insideFiner(finer: Level?, x: number, z: number): boolean
	if not finer or finer.shown == 0 then
		return false
	end
	local half = finer.cells * finer.spacing * 0.5 - 1e-3
	return math.abs(x - finer.cx) < half and math.abs(z - finer.cz) < half
end

-- Fill a copy with the level's ground round (cx, cz), over as many frames as it takes.
-- Returns the heights, unsunk.
function GroundMeshView._fill(self: View, level: Level, copy: Copy, cx: number, cz: number, coarser: Level?, finer: Level?): { number }?
	local G = Config.Spline.Ground
	local budget = G.MeshSliceMs / 1000
	local t0 = os.clock()
	local sliceStart, slices, work = t0, 1, 0
	local function slice()
		local now = os.clock()
		if now - sliceStart > budget then
			work += now - sliceStart
			self.worstSliceMs = math.max(self.worstSliceMs, (now - sliceStart) * 1000)
			if #self.slices < 4000 then
				table.insert(self.slices, (now - sliceStart) * 1000)
			end
			task.wait()
			slices += 1
			sliceStart = os.clock()
		end
	end
	local n, sp, cells = level.n, level.spacing, level.cells
	local halfW = cells * sp * 0.5
	local ctx = Ground.context(self.field, self.spline, cx - halfW, cz - halfW, cx + halfW, cz + halfW)
	slice()
	local heights = table.create(n * n)
	-- the coarser level's heights along this one's rim, sampled at its own vertices
	local ratio = if coarser then math.round(coarser.spacing / sp) else 1
	local rim: { [number]: number } = {}
	local function coarseAt(x: number, z: number): number
		local key = math.round(x) * 1e6 + math.round(z)
		local y = rim[key]
		if not y then
			y = vertexHeight(ctx, (coarser :: Level).clamp, x, z)
			rim[key] = y
		end
		return y
	end
	for i = 0, cells do
		if self.dead then
			return nil
		end
		local x = cx + (i - cells / 2) * sp
		for j = 0, cells do
			local z = cz + (j - cells / 2) * sp
			local y
			local onRim = coarser and (i == 0 or i == cells or j == 0 or j == cells)
			if onRim then
				-- along the rim: straight between the coarser grid's vertices
				local along = if i == 0 or i == cells then j else i
				local r = along % ratio
				if r == 0 then
					y = coarseAt(x, z)
				else
					local a0 = along - r
					local f = r / ratio
					if i == 0 or i == cells then
						local za, zb = cz + (a0 - cells / 2) * sp, cz + (a0 + ratio - cells / 2) * sp
						y = coarseAt(x, za) * (1 - f) + coarseAt(x, zb) * f
					else
						local xa, xb = cx + (a0 - cells / 2) * sp, cx + (a0 + ratio - cells / 2) * sp
						y = coarseAt(xa, z) * (1 - f) + coarseAt(xb, z) * f
					end
				end
			else
				y = vertexHeight(ctx, level.clamp, x, z)
			end
			heights[i * n + j + 1] = y
		end
		slice()
	end
	-- normals from the grid, colours by slope, then write it all
	local cy = Ground.base(self.field, cx, cz)
	local rockY = math.cos(math.rad(G.RockAngle))
	local g1, g2, rock = G.GrassColours[1], G.GrassColours[2], G.GroundRockColour
	local uvStuds = G.UVStuds
	local em = copy.em
	local positions = table.create(n * n)
	local normals = table.create(n * n)
	local colours = table.create(n * n)
	for i = 0, cells do
		local x = cx + (i - cells / 2) * sp
		for j = 0, cells do
			local k = i * n + j + 1
			local z = cz + (j - cells / 2) * sp
			local y = heights[k]
			if finer and insideFiner(finer, x, z) then
				y -= G.HoleSink
			end
			positions[k] = Vector3.new(x - cx, y - cy, z - cz)
			local il, ih = math.max(i - 1, 0), math.min(i + 1, cells)
			local jl, jh = math.max(j - 1, 0), math.min(j + 1, cells)
			local dydx = (heights[ih * n + j + 1] - heights[il * n + j + 1]) / ((ih - il) * sp)
			local dydz = (heights[i * n + jh + 1] - heights[i * n + jl + 1]) / ((jh - jl) * sp)
			local nv = Vector3.new(-dydx, 1, -dydz).Unit
			normals[k] = nv
			if nv.Y < rockY then
				colours[k] = rock
			else
				local blotch = math.clamp(0.5 + 1.6 * math.noise(x / 70, z / 70, 3.37), 0, 1)
				colours[k] = g1:Lerp(g2, blotch)
			end
		end
		slice()
	end
	-- the write, into the hidden copy, a slice at a time like the rest
	local w0 = os.clock()
	for k = 1, n * n do
		local p = positions[k]
		em:SetPosition(copy.v[k], p)
		em:SetNormal(copy.nrm[k], normals[k])
		em:SetColor(copy.col[k], colours[k])
		em:SetUV(copy.uv[k], Vector2.new((p.X + cx) / uvStuds, (p.Z + cz) / uvStuds))
		if k % 256 == 0 then
			slice()
		end
	end
	copy.part.CFrame = CFrame.new(cx, cy, cz)
	work += os.clock() - sliceStart
	local applyMs = (os.clock() - w0) * 1000
	self.applyMs = applyMs
	self.worstApplyMs = math.max(self.worstApplyMs, applyMs)
	self.lastMs = work * 1000
	self.worstMs = math.max(self.worstMs, self.lastMs)
	self.lastSlices = slices
	return heights
end

-- The coarser level's hole follows the finer grid: re-sink only the vertices that moved in
-- or out of it, from the heights it was drawn with.
function GroundMeshView._hole(self: View, coarse: Level, finer: Level, oldCx: number?, oldCz: number?)
	if coarse.shown == 0 then
		return
	end
	local G = Config.Spline.Ground
	local copy = coarse.copies[coarse.shown]
	local n, sp, cells = coarse.n, coarse.spacing, coarse.cells
	local cy = Ground.base(self.field, coarse.cx, coarse.cz)
	local fh = finer.cells * finer.spacing * 0.5 - 1e-3
	local function inside(cx: number?, cz: number?, x: number, z: number): boolean
		return cx ~= nil and cz ~= nil and math.abs(x - cx) < fh and math.abs(z - cz) < fh
	end
	for i = 0, cells do
		local x = coarse.cx + (i - cells / 2) * sp
		for j = 0, cells do
			local z = coarse.cz + (j - cells / 2) * sp
			local was = inside(oldCx, oldCz, x, z)
			local now = inside(finer.cx, finer.cz, x, z)
			if was ~= now then
				local k = i * n + j + 1
				local y = coarse.heights[k] - (if now then G.HoleSink else 0)
				copy.em:SetPosition(copy.v[k], Vector3.new(x - coarse.cx, y - cy, z - coarse.cz))
			end
		end
	end
end

-- New road laid since the last look: does it come into a level's square?
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
		for _, level in self.levels do
			if level.shown ~= 0 and not level.stale then
				local half = level.cells * level.spacing * 0.5 + reach
				if math.abs(x - level.cx) < half and math.abs(z - level.cz) < half then
					level.stale = true
				end
			end
		end
	end
end

-- The next level that wants building: the coarsest first (the finer one's rim reads it).
function GroundMeshView._wanted(self: View): Level?
	for li = #self.levels, 1, -1 do
		local level = self.levels[li]
		if level.shown == 0 or level.stale then
			return level
		end
		local dx, dz = self.carX - level.cx, self.carZ - level.cz
		if math.max(math.abs(dx), math.abs(dz)) > level.recentre then
			return level
		end
	end
	return nil
end

function GroundMeshView._run(self: View)
	self.running = true
	while not self.dead and not self.paused do
		self:_checkNewRoad()
		local level = self:_wanted()
		if not level then
			break
		end
		local li = level.index
		local coarser = self.levels[li + 1]
		local finer = self.levels[li - 1]
		-- two copies a level: one filled, hidden, while the other shows
		local want = 2
		while #level.copies < want do
			local copy = makeCopy(level, `Ground_{li}_{#level.copies + 1}`)
			if not copy then
				self.failed = `level {li}: this device would not make the mesh`
				self.running = false
				return
			end
			self.vertices += level.n * level.n
			table.insert(level.copies, copy)
		end
		local snapTo = if coarser then coarser.spacing else level.spacing
		local cx, cz = snap(self.carX, snapTo), snap(self.carZ, snapTo)
		level.stale = false
		local target = if level.shown == 1 then 2 else 1
		local copy = level.copies[target]
		local heights = self:_fill(level, copy, cx, cz, coarser, finer)
		if not heights or self.dead then
			break
		end
		local oldCx, oldCz = if level.shown ~= 0 then level.cx else nil, if level.shown ~= 0 then level.cz else nil
		-- swap in, in this frame: the new copy shown, the old one hidden, the hole moved
		local old = level.copies[level.shown]
		level.cx, level.cz, level.heights = cx, cz, heights
		copy.part.Parent = self.folder
		if old and old ~= copy then
			old.part.Parent = nil
		end
		level.shown = target
		level.builds += 1
		if coarser then
			self:_hole(coarser, level, oldCx, oldCz)
		end
		if #self.events < 2000 then
			table.insert(self.events, { os.clock(), li })
		end
		task.wait()
	end
	self.running = false
end

-- Each frame, with the car's position.
function GroundMeshView.Update(self: View, x: number, z: number)
	if self.dead or self.failed or self.paused then
		return
	end
	self.carX, self.carZ = x, z
	if not self.running then
		self:_checkNewRoad()
		if self:_wanted() then
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
	for _, level in self.levels do
		for _, copy in level.copies do
			copy.part:Destroy()
			copy.em:Destroy()
		end
		level.copies = {}
	end
	self.folder:Destroy()
end

function GroundMeshView.DebugState(self: View)
	local levels = {}
	for _, level in self.levels do
		table.insert(levels, {
			spacing = level.spacing,
			cells = level.cells,
			shown = level.shown,
			cx = level.cx,
			cz = level.cz,
			builds = level.builds,
			copies = #level.copies,
		})
	end
	return {
		levels = levels,
		failed = self.failed,
		running = self.running,
		vertices = self.vertices,
		lastMs = self.lastMs,
		worstMs = self.worstMs,
		worstSliceMs = self.worstSliceMs,
		lastSlices = self.lastSlices,
		applyMs = self.applyMs,
		worstApplyMs = self.worstApplyMs,
		events = self.events,
		slices = self.slices,
		paused = self.paused,
	}
end

return GroundMeshView
