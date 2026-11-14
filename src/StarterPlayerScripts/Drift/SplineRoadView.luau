--!strict
-- SplineRoadView: the spline road drawn round the car, chunk by chunk, on this device
-- (features/spline-road.md "The mesh, purely visual", T-135).
--
-- The server makes no road parts at all. Each client draws its own copy of the curve as
-- meshes (`Road/SplineMesh`), `ChunkLength` studs at a time, from `Behind` studs behind the
-- car to `Ahead` in front, and takes chunks down as the car leaves them. One chunk is built
-- at a time, nearest the car first, so a frame never pays for more than one.
--
-- A DEVICE THAT CANNOT MAKE A MESH still sees the road: the chunk is drawn as parts instead
-- (`Road/SplineParts`, nothing queryable, tarmac only), and `fallbacks` counts how often.
-- Either way the car drives on the maths, not on anything drawn here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)
local SplineMesh = require(ReplicatedStorage.Shared.Road.SplineMesh)
local SplineParts = require(ReplicatedStorage.Shared.Road.SplineParts)

local SplineRoadView = {}
SplineRoadView.__index = SplineRoadView

export type View = typeof(setmetatable(
	{} :: {
		spline: Spline.Spline,
		folder: Folder,
		chunks: { [number]: Instance },
		building: number?,
		forceFallback: boolean,
		dead: boolean,
		built: number,
		fallbacks: number,
		removed: number,
		lastMs: number,
		worstMs: number,
		lastSliceMs: number, -- the most of the last build any one frame paid (T-193)
		worstSliceMs: number,
		lastSlices: number, -- frames the last build was spread over
		triangles: number,
		lastError: string?,
		closing: BasePart?,
		closingS: number?,
		short: { [number]: number }, -- chunk -> the road's length when it was built short
		rebuilt: number,
		-- THE HILLSIDE (T-190) is drawn from every stretch of road near a chunk, and the leg
		-- below a chunk is often laid after the chunk is drawn. So: the road's length when
		-- each chunk was built, how far the road has been checked against them, and the
		-- chunks new road has come beside since (`stale`), redrawn when nothing else is wanted
		builtAt: { [number]: number },
		checkedTo: number,
		stale: { [number]: boolean },
		redrawn: number,
	},
	SplineRoadView
))

function SplineRoadView.new(spline: Spline.Spline, parent: Instance?): View
	local folder = Instance.new("Folder")
	folder.Name = "SplineRoad"
	folder.Parent = parent or Workspace
	return setmetatable({
		spline = spline,
		folder = folder,
		chunks = {},
		building = nil,
		forceFallback = false,
		dead = false,
		built = 0,
		fallbacks = 0,
		removed = 0,
		lastMs = 0,
		worstMs = 0,
		lastSliceMs = 0,
		worstSliceMs = 0,
		lastSlices = 0,
		triangles = 0,
		lastError = nil,
		closing = nil,
		closingS = nil,
		short = {},
		rebuilt = 0,
		builtAt = {},
		checkedTo = spline.length,
		stale = {},
		redrawn = 0,
	}, SplineRoadView)
end

-- A new station can change a face cap or meeting height without shortening its ray.
-- Invalidate any chunk whose gathered station cells gained road, including one still
-- being built. Its old mesh stays up until the replacement is complete.
function SplineRoadView._checkNewRoad(self: View)
	local spline = self.spline
	local from, to = self.checkedTo, spline.length
	if to <= from + 1e-6 then
		return
	end
	self.checkedTo = to
	local H = Config.Spline.Hill
	local L, cell = Config.Spline.Mesh.ChunkLength, spline.cell
	local fresh = {}
	for s = math.floor(from / H.StationStep) * H.StationStep, to, H.StationStep do
		local x, z = spline:planAt(s)
		table.insert(fresh, { math.floor(x / cell), math.floor(z / cell) })
	end
	local candidates: { [number]: boolean } = {}
	for i in self.chunks do
		candidates[i] = true
	end
	if self.building then
		candidates[self.building] = true
	end
	for i in candidates do
		if not self.stale[i] and self.builtAt[i] and self.builtAt[i] < to then
			local s0, s1 = i * L, math.min((i + 1) * L, to)
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			local s = s0
			while true do
				local x, z = spline:planAt(math.min(s, s1))
				minX, maxX = math.min(minX, x), math.max(maxX, x)
				minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
				if s >= s1 then
					break
				end
				s += 16
			end
			local loX, hiX = math.floor((minX - H.Gather) / cell), math.floor((maxX + H.Gather) / cell)
			local loZ, hiZ = math.floor((minZ - H.Gather) / cell), math.floor((maxZ + H.Gather) / cell)
			for _, q in fresh do
				if q[1] >= loX and q[1] <= hiX and q[2] >= loZ and q[2] <= hiZ then
					self.stale[i] = true
					break
				end
			end
		end
	end
end
-- THE CLOSING BARRIER (T-136): a wall across the road and its runoff at `s`, the piece
-- road's colour and see-through, drawn here because the server builds nothing.
-- `Drift/SplineWorld` is what makes it solid.
function SplineRoadView.SetClosing(self: View, s: number?)
	self.closingS = s
	if not s then
		if self.closing then
			self.closing:Destroy()
			self.closing = nil
		end
		return
	end
	local R = Config.Road
	local part = self.closing
	if not part then
		local p = Instance.new("Part")
		p.Name = "ClosingBarrier"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = R.BarrierMaterial
		p.Color = R.Colours.Closing
		p.Transparency = R.BarrierTransparency
		p.Parent = self.folder
		self.closing = p
		part = p
	end
	local spline = self.spline
	local x, y, z = spline:surfaceXYZ(s, 0)
	local height = R.BarrierHeight + R.Thickness
	local wider = math.max(spline:runoffAt(s, -1), spline:runoffAt(s, 1)) + Config.Spline.Terrain.EdgeDepth
	local wide = R.Width + 2 * wider
	-- tall enough to cover the banked road edge to edge
	local bankRise = wide * 0.5 * math.abs(math.tan(spline:bankAt(s)))
	local p = part :: BasePart
	p.Size = Vector3.new(wide, height + 2 * bankRise, 1)
	-- the slab `Drift/SplineWorld` makes solid: 1 stud deep, its front face at `s`
	p.CFrame = CFrame.new(x, y + (R.BarrierHeight - R.Thickness) * 0.5, z) * CFrame.Angles(0, spline:yawAt(s), 0) * CFrame.new(0, 0, 0.5)
end

local function removeChunk(chunk: Instance)
	if chunk:IsA("Model") then
		SplineMesh.destroy(chunk)
	else
		chunk:Destroy()
	end
end

function SplineRoadView._build(self: View, i: number)
	local L = Config.Spline.Mesh.ChunkLength
	local s0 = i * L
	local s1 = math.min((i + 1) * L, self.spline.length)
	self.builtAt[i] = self.spline.length
	self.stale[i] = nil
	local t0 = os.clock()
	local model, info = SplineMesh.build(self.spline, s0, s1, self.folder, { forceFail = self.forceFallback })
	local chunk: Instance
	if model then
		chunk = model
		self.triangles += info.triangles
		self.lastSliceMs = info.sliceMs or 0
		self.worstSliceMs = math.max(self.worstSliceMs, self.lastSliceMs)
		self.lastSlices = info.slices or 1
	else
		-- this device cannot make the mesh: draw the chunk as parts instead
		self.fallbacks += 1
		self.lastError = info
		local folder = Instance.new("Folder")
		folder.Name = `Chunk_{math.floor(s0)}_parts`
		SplineParts.build(self.spline, s0, s1, folder, { step = Config.Spline.Mesh.FallbackStep, queryable = false, barriers = false })
		folder:SetAttribute("Fallback", true)
		folder.Parent = self.folder
		chunk = folder
	end
	local ms = (os.clock() - t0) * 1000
	self.lastMs = ms
	self.worstMs = math.max(self.worstMs, ms)
	self.built += 1
	if self.dead then
		removeChunk(chunk)
		return
	end
	-- a chunk rebuilt to more road replaces the old one only now it is whole (T-193), so the
	-- road never has a hole while the new one is built over several frames
	local old = self.chunks[i]
	self.chunks[i] = chunk
	if old and old ~= chunk then
		removeChunk(old)
	end
	-- built up to where the road ended at the time: rebuild it once more road arrives
	if s1 < (i + 1) * L - 1e-6 then
		self.short[i] = s1
	else
		self.short[i] = nil
	end
end

-- Keep the chunks round `s` (the car's distance along the road) and no others.
function SplineRoadView.Update(self: View, s: number?)
	if self.dead then
		return
	end
	local M = Config.Spline.Mesh
	local L = M.ChunkLength
	local at = s or 0
	local last = math.max(0, math.ceil(self.spline.length / L) - 1)
	local lo = math.clamp(math.floor((at - M.Behind) / L), 0, last)
	local hi = math.clamp(math.floor((at + M.Ahead) / L), 0, last)
	for i, chunk in self.chunks do
		if i < lo or i > hi then
			removeChunk(chunk)
			self.chunks[i] = nil
			self.short[i] = nil
			self.builtAt[i] = nil
			self.stale[i] = nil
			self.removed += 1
		end
	end
	self:_checkNewRoad()
	-- a chunk drawn to the old end of a road that has since grown: take it down to redraw
	if not self.building then
		-- (the old one stays up until the new one is whole, T-193)
		for i, builtTo in self.short do
			if self.spline.length > builtTo + 1e-6 and self.chunks[i] then
				self.short[i] = nil
				self.rebuilt += 1
				self:_start(i)
				return
			end
		end
	end
	if self.building then
		return
	end
	-- nearest the car first: the chunk it is in, then ahead, then behind
	local here = math.clamp(math.floor(at / L), lo, hi)
	local want: number? = nil
	for i = here, hi do
		if not self.chunks[i] then
			want = i
			break
		end
	end
	if not want then
		for i = here - 1, lo, -1 do
			if not self.chunks[i] then
				want = i
				break
			end
		end
	end
	if want then
		self:_start(want :: number)
		return
	end
	-- nothing missing: redraw a chunk new road has come beside (T-190), nearest the car
	-- first. The old one stays up until the new one is whole
	-- (not one still far ahead: more road will come beside it before the car does, and it
	-- would be redrawn for each stretch of it)
	local best: number? = nil
	for i in self.stale do
		if self.chunks[i] and i * L <= at + M.RedrawWithin and (not best or math.abs(i - here) < math.abs(best - here)) then
			best = i
		end
	end
	if best then
		self.redrawn += 1
		self:_start(best)
	end
end

-- Build chunk `i` in its own thread: it takes a few frames (T-193).
function SplineRoadView._start(self: View, i: number)
	self.building = i
	task.spawn(function()
		local ok, err = pcall(self._build, self, i)
		if not ok then
			self.lastError = tostring(err)
			warn(`[SplineRoadView] chunk {i} failed: {err}`)
		end
		self.building = nil
	end)
end

function SplineRoadView.Destroy(self: View)
	self.dead = true
	for i, chunk in self.chunks do
		removeChunk(chunk)
		self.chunks[i] = nil
	end
	self.closing = nil
	self.folder:Destroy()
end

function SplineRoadView.DebugState(self: View)
	local n, meshes, parts = 0, 0, 0
	for _, chunk in self.chunks do
		n += 1
		if chunk:IsA("Model") then
			meshes += 1
		else
			parts += #chunk:GetDescendants()
		end
	end
	return {
		chunks = n,
		meshChunks = meshes,
		fallbackParts = parts,
		built = self.built,
		removed = self.removed,
		fallbacks = self.fallbacks,
		building = self.building,
		lastMs = self.lastMs,
		worstMs = self.worstMs,
		lastSliceMs = self.lastSliceMs,
		worstSliceMs = self.worstSliceMs,
		lastSlices = self.lastSlices,
		trianglesBuilt = self.triangles,
		forceFallback = self.forceFallback,
		lastError = self.lastError,
		closingS = self.closingS,
		rebuilt = self.rebuilt,
		redrawn = self.redrawn, -- chunks redrawn because new road came beside them (T-190)
		length = self.spline.length,
	}
end

return SplineRoadView
