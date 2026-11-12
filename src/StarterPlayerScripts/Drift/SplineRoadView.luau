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
-- (`Road/SplineParts`, nothing queryable), and `fallbacks` counts how often. Either way the
-- car drives on the maths, not on anything drawn here.
--
-- The side barriers vanish when the guardrails are off, as the piece road's do.

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
		rails: boolean,
		forceFallback: boolean,
		dead: boolean,
		built: number,
		fallbacks: number,
		removed: number,
		lastMs: number,
		worstMs: number,
		triangles: number,
		lastError: string?,
		closing: BasePart?,
		closingS: number?,
		short: { [number]: number }, -- chunk -> the road's length when it was built short
		rebuilt: number,
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
		rails = true,
		forceFallback = false,
		dead = false,
		built = 0,
		fallbacks = 0,
		removed = 0,
		lastMs = 0,
		worstMs = 0,
		triangles = 0,
		lastError = nil,
		closing = nil,
		closingS = nil,
		short = {},
		rebuilt = 0,
	}, SplineRoadView)
end

local function setBarriers(chunk: Instance, on: boolean)
	local t = if on then 0 else 1
	for _, d in chunk:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Barriers" or string.sub(d.Name, 1, 8) == "Barrier_") then
			d.Transparency = t
		end
	end
end

function SplineRoadView.SetRails(self: View, on: boolean)
	self.rails = on
	for _, chunk in self.chunks do
		setBarriers(chunk, on)
	end
end

-- THE CLOSING BARRIER (T-136): a wall across the road at `s`, the piece road's colour and
-- see-through, drawn here because the server builds nothing. It never switches off with the
-- guardrails; `Drift/SplineWorld` is what makes it solid.
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
	local wide = R.Width + 2 * R.BarrierThickness
	-- tall enough to cover the banked road edge to edge
	local bankRise = R.Width * 0.5 * math.abs(math.tan(spline:bankAt(s)))
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
	local t0 = os.clock()
	local model, info = SplineMesh.build(self.spline, s0, s1, self.folder, { forceFail = self.forceFallback })
	local chunk: Instance
	if model then
		chunk = model
		self.triangles += info.triangles
	else
		-- this device cannot make the mesh: draw the chunk as parts instead
		self.fallbacks += 1
		self.lastError = info
		local folder = Instance.new("Folder")
		folder.Name = `Chunk_{math.floor(s0)}_parts`
		SplineParts.build(self.spline, s0, s1, folder, { step = Config.Spline.Mesh.FallbackStep, queryable = false })
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
	setBarriers(chunk, self.rails)
	self.chunks[i] = chunk
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
			self.removed += 1
		end
	end
	-- a chunk drawn to the old end of a road that has since grown: take it down to redraw
	if not self.building then
		for i, builtTo in self.short do
			if self.spline.length > builtTo + 1e-6 and self.chunks[i] then
				removeChunk(self.chunks[i])
				self.chunks[i] = nil
				self.short[i] = nil
				self.rebuilt += 1
				break
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
		local i = want :: number
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
		trianglesBuilt = self.triangles,
		rails = self.rails,
		forceFallback = self.forceFallback,
		lastError = self.lastError,
		closingS = self.closingS,
		rebuilt = self.rebuilt,
		length = self.spline.length,
	}
end

return SplineRoadView
