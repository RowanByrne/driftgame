--!strict
-- Drift/GroundTerrainView: the ground-first trial's option 2, Roblox Terrain
-- (features/ground-trial.md, T-218, step T-224). The mountain `Road/Ground` describes,
-- written as Roblox's own smooth terrain round the car, on this device only (terrain a client
-- writes is its own). Purely visual: the car drives on the spline maths.
--
-- SQUARE CHUNKS of `TerrainChunk` studs, written whole with one `WriteVoxels` each, nearest
-- the car first, out to `DrawTo`; cleared past `KeepTo`. Working out a chunk (its heights,
-- materials and occupancies) is spread over frames; the write itself is one call. A chunk new
-- road comes into is rewritten: its old voxels cleared and the new ones written in one frame.
--
-- ROUND THE ROAD: the terrain sinks `TerrainSink` under the road and its runoff, and is held
-- that far below a runoff's edge within `TerrainClamp` of it, since smooth terrain rounds off
-- between its 4-stud voxels. The road's skirt (`Road/SplineMesh`, a ground run) hides the gap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)

local GroundTerrainView = {}
GroundTerrainView.__index = GroundTerrainView

local VOXEL = 4

type Chunk = {
	cx: number, -- chunk index
	cz: number,
	y0: number, -- the voxel rows written, in studs
	y1: number,
	builtAt: number, -- the road's length when it was worked out
}

export type View = typeof(setmetatable(
	{} :: {
		spline: any,
		field: Ground.Field,
		chunks: { [number]: Chunk },
		stale: { [number]: boolean },
		dead: boolean,
		paused: boolean,
		running: boolean,
		failed: string?,
		carX: number,
		carZ: number,
		checkedTo: number,
		written: number,
		rewritten: number,
		cleared: number,
		voxels: number, -- written, in all
		lastMs: number, -- a chunk's work, not counting the frames between
		worstMs: number,
		worstWriteMs: number,
		worstSliceMs: number,
		slices: { number },
		events: { { number } },
		colours: { [Enum.Material]: Color3 }, -- the terrain's colours before, put back after
	},
	GroundTerrainView
))

local function key(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

function GroundTerrainView.new(spline: any): View
	local G = Config.Spline.Ground
	local terrain = Workspace.Terrain
	local colours = {}
	for material, colour in { [Enum.Material.Grass] = G.TerrainGrassColour, [Enum.Material.Rock] = G.TerrainRockColour } do
		colours[material] = terrain:GetMaterialColor(material)
		terrain:SetMaterialColor(material, colour)
	end
	return setmetatable({
		spline = spline,
		field = spline.mountain,
		chunks = {},
		stale = {},
		dead = false,
		paused = false,
		running = false,
		failed = nil,
		carX = spline.origin.x,
		carZ = spline.origin.z,
		checkedTo = spline.length,
		written = 0,
		rewritten = 0,
		cleared = 0,
		voxels = 0,
		lastMs = 0,
		worstMs = 0,
		worstWriteMs = 0,
		worstSliceMs = 0,
		slices = {},
		events = {},
		colours = colours,
	}, GroundTerrainView)
end

local function region(c: Chunk): Region3
	local size = Config.Spline.Ground.TerrainChunk
	local x0, z0 = c.cx * size, c.cz * size
	return Region3.new(Vector3.new(x0, c.y0, z0), Vector3.new(x0 + size, c.y1, z0 + size))
end

-- Work one chunk out over a few frames, then write it (clearing what it held before).
function GroundTerrainView._write(self: View, cx: number, cz: number)
	local G = Config.Spline.Ground
	local size = G.TerrainChunk
	local n = size // VOXEL
	local budget = G.TerrainSliceMs / 1000
	local t0 = os.clock()
	local sliceStart, work = t0, 0
	local function slice()
		local now = os.clock()
		if now - sliceStart > budget then
			work += now - sliceStart
			local ms = (now - sliceStart) * 1000
			self.worstSliceMs = math.max(self.worstSliceMs, ms)
			if #self.slices < 4000 then
				table.insert(self.slices, ms)
			end
			task.wait()
			sliceStart = os.clock()
		end
	end
	local x0, z0 = cx * size, cz * size
	local builtAt = self.spline.length
	local ctx = Ground.context(self.field, self.spline, x0 - VOXEL, z0 - VOXEL, x0 + size + VOXEL, z0 + size + VOXEL)
	slice()
	-- the surface at each column's middle, with a ring round the chunk for the slopes
	local m = n + 2
	local heights = table.create(m * m)
	local lo, hi = math.huge, -math.huge
	for i = 0, n + 1 do
		local x = x0 + (i - 0.5) * VOXEL
		for j = 0, n + 1 do
			local z = z0 + (j - 0.5) * VOXEL
			local y, a, e, T = Ground.at(ctx, x, z)
			y -= G.TerrainSink * a
			if e < G.TerrainClamp then
				y = math.min(y, T - G.TerrainSink)
			end
			heights[i * m + j + 1] = y
			if i >= 1 and i <= n and j >= 1 and j <= n then
				lo, hi = math.min(lo, y), math.max(hi, y)
			end
		end
		slice()
	end
	local y0 = math.floor((lo - G.TerrainDepth) / VOXEL) * VOXEL
	local y1 = math.ceil((hi + VOXEL) / VOXEL) * VOXEL
	local ny = (y1 - y0) // VOXEL
	local rockSlope = math.tan(math.rad(G.RockAngle))
	local GRASS, ROCK, GROUND, AIR = Enum.Material.Grass, Enum.Material.Rock, Enum.Material.Ground, Enum.Material.Air
	local materials = table.create(n)
	local occupancy = table.create(n)
	for i = 1, n do
		local mi, oi = table.create(ny), table.create(ny)
		for yj = 1, ny do
			mi[yj], oi[yj] = table.create(n), table.create(n)
		end
		for j = 1, n do
			local h = heights[i * m + j + 1]
			local dx = (heights[(i + 1) * m + j + 1] - heights[(i - 1) * m + j + 1]) / (2 * VOXEL)
			local dz = (heights[i * m + j + 2] - heights[i * m + j]) / (2 * VOXEL)
			local steep = dx * dx + dz * dz > rockSlope * rockSlope
			for yj = 1, ny do
				local bottom = y0 + (yj - 1) * VOXEL
				local o = (h - bottom) / VOXEL
				if o >= 1 then
					oi[yj][j] = 1
					mi[yj][j] = if steep then ROCK elseif h - bottom > 2 * VOXEL then GROUND else GRASS
				elseif o > 0 then
					oi[yj][j] = o
					mi[yj][j] = if steep then ROCK else GRASS
				else
					oi[yj][j] = 0
					mi[yj][j] = AIR
				end
			end
		end
		materials[i], occupancy[i] = mi, oi
		slice()
	end
	work += os.clock() - sliceStart
	if self.dead then
		return
	end
	-- the write, in one frame: what the chunk held before cleared, the new voxels in
	local w0 = os.clock()
	local terrain = Workspace.Terrain
	local k = key(cx, cz)
	local old = self.chunks[k]
	if old then
		terrain:FillRegion(region(old):ExpandToGrid(VOXEL), VOXEL, AIR)
	end
	local c: Chunk = { cx = cx, cz = cz, y0 = y0, y1 = y1, builtAt = builtAt }
	terrain:WriteVoxels(region(c), VOXEL, materials, occupancy)
	local writeMs = (os.clock() - w0) * 1000
	self.chunks[k] = c
	self.worstWriteMs = math.max(self.worstWriteMs, writeMs)
	self.lastMs = work * 1000 + writeMs
	self.worstMs = math.max(self.worstMs, self.lastMs)
	self.voxels += n * n * ny
	if old then
		self.rewritten += 1
	else
		self.written += 1
	end
	if #self.events < 4000 then
		table.insert(self.events, { os.clock(), writeMs })
	end
end

-- New road laid since the last look: the chunks it comes near are rewritten.
function GroundTerrainView._checkNewRoad(self: View)
	local spline = self.spline
	local from, to = self.checkedTo, spline.length
	if to <= from + 1e-6 then
		return
	end
	self.checkedTo = to
	local size = Config.Spline.Ground.TerrainChunk
	local reach = Ground.reach()
	for s = math.max(0, from - 16), to, 16 do
		local x, z = spline:planAt(s)
		for cx = math.floor((x - reach) / size), math.floor((x + reach) / size) do
			for cz = math.floor((z - reach) / size), math.floor((z + reach) / size) do
				local k = key(cx, cz)
				if self.chunks[k] then
					self.stale[k] = true
				end
			end
		end
	end
end

-- The chunk to do next: one missing within `DrawTo`, nearest first; then a stale one.
function GroundTerrainView._wanted(self: View): (number?, number?)
	local G = Config.Spline.Ground
	local size = G.TerrainChunk
	local ccx, ccz = math.floor(self.carX / size), math.floor(self.carZ / size)
	local r = math.ceil(G.DrawTo / size)
	local best, bx, bz = math.huge, nil, nil
	for cx = ccx - r, ccx + r do
		for cz = ccz - r, ccz + r do
			local mx, mz = (cx + 0.5) * size - self.carX, (cz + 0.5) * size - self.carZ
			local d = mx * mx + mz * mz
			if d <= G.DrawTo * G.DrawTo and d < best then
				local k = key(cx, cz)
				if not self.chunks[k] then
					best, bx, bz = d, cx, cz
				end
			end
		end
	end
	if bx then
		return bx, bz
	end
	for k in self.stale do
		local c = self.chunks[k]
		self.stale[k] = nil
		if c then
			return c.cx, c.cz
		end
	end
	return nil, nil
end

-- Chunks past `KeepTo` are cleared.
function GroundTerrainView._clearFar(self: View)
	local G = Config.Spline.Ground
	local size = G.TerrainChunk
	local terrain = Workspace.Terrain
	for k, c in self.chunks do
		local mx, mz = (c.cx + 0.5) * size - self.carX, (c.cz + 0.5) * size - self.carZ
		if mx * mx + mz * mz > G.KeepTo * G.KeepTo then
			terrain:FillRegion(region(c):ExpandToGrid(VOXEL), VOXEL, Enum.Material.Air)
			self.chunks[k] = nil
			self.stale[k] = nil
			self.cleared += 1
		end
	end
end

function GroundTerrainView._run(self: View)
	while not self.dead and not self.paused do
		self:_checkNewRoad()
		self:_clearFar()
		local cx, cz = self:_wanted()
		if not cx or not cz then
			break
		end
		self:_write(cx, cz)
		task.wait()
	end
	self.running = false
end

-- Each frame, with the car's position.
function GroundTerrainView.Update(self: View, x: number, z: number)
	if self.dead or self.failed or self.paused then
		return
	end
	self.carX, self.carZ = x, z
	if not self.running then
		self.running = true
		task.spawn(function()
			local ok, err = pcall(self._run, self)
			if not ok then
				self.failed = tostring(err)
				self.running = false
				warn(`[GroundTerrainView] {err}`)
			end
		end)
	end
end

function GroundTerrainView.Destroy(self: View)
	self.dead = true
	local terrain = Workspace.Terrain
	for _, c in self.chunks do
		terrain:FillRegion(region(c):ExpandToGrid(VOXEL), VOXEL, Enum.Material.Air)
	end
	self.chunks = {}
	for material, colour in self.colours do
		terrain:SetMaterialColor(material, colour)
	end
end

function GroundTerrainView.DebugState(self: View)
	local n = 0
	for _ in self.chunks do
		n += 1
	end
	return {
		mode = "terrain",
		chunks = n,
		written = self.written,
		rewritten = self.rewritten,
		cleared = self.cleared,
		voxels = self.voxels,
		failed = self.failed,
		running = self.running,
		paused = self.paused,
		lastMs = self.lastMs,
		worstMs = self.worstMs,
		worstWriteMs = self.worstWriteMs,
		worstSliceMs = self.worstSliceMs,
		slices = self.slices,
		events = self.events,
	}
end

return GroundTerrainView
