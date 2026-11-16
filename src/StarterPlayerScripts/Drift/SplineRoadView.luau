--!strict
-- SplineRoadView: the spline road drawn round the car, chunk by chunk, on this device
-- (features/spline-road.md "The mesh, purely visual", T-135).
--
-- The server makes no road parts at all. Each client draws its own copy of the curve as
-- meshes (`Road/SplineMesh`), `ChunkLength` studs at a time, from the player's "Road behind"
-- (`Drift/RoadBehind`, T-230) behind the car to the player's "Road ahead" (`Drift/RoadAhead`,
-- T-263) in front, and takes chunks down as the car leaves them. One chunk is built at a time,
-- nearest the car first, so a frame never pays for more than one.
--
-- OUT OF MESH BUDGET (T-230): the road ahead never pays for the road behind. A chunk that
-- cannot be made lets the furthest chunk behind the car go and tries again, and the window
-- behind stays that short (`behindCap`) until the player changes the setting.
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
local RoadAhead = require(script.Parent.RoadAhead)
local RoadBehind = require(script.Parent.RoadBehind)

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
		-- THE ROAD BEHIND (T-230): the car's chunk at the last update, chunks the budget made
		-- us let go of, how many whole chunks behind the car's own may stay since (nil: the
		-- setting's), each held chunk's triangles, and the setting's connection
		here: number,
		squeezed: number,
		behindCap: number?,
		tris: { [number]: number },
		far: { [number]: boolean }, -- chunk -> built at the far detail (T-263)
		behindConn: any,
		aheadConn: any, -- the player's "Road ahead" (T-263)
	},
	SplineRoadView
))

function SplineRoadView.new(spline: Spline.Spline, parent: Instance?): View
	local folder = Instance.new("Folder")
	folder.Name = "SplineRoad"
	folder.Parent = parent or Workspace
	local self = setmetatable({
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
		here = 0,
		squeezed = 0,
		behindCap = nil,
		tris = {},
		far = {},
		behindConn = nil,
		aheadConn = nil,
	}, SplineRoadView)
	-- a longer setting asks again, whatever the budget said before
	self.behindConn = RoadBehind.Changed:Connect(function()
		self.behindCap = nil
	end)
	-- and a shorter road ahead leaves room for the road behind again (T-263); a longer one is
	-- built on the next `Update`, nearest the car first, and pays for itself by letting the
	-- road behind go if it must
	self.aheadConn = RoadAhead.Changed:Connect(function()
		self.behindCap = nil
	end)
	return self
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

-- Take chunk `i` down and forget it.
function SplineRoadView._drop(self: View, i: number)
	local chunk = self.chunks[i]
	if chunk then
		removeChunk(chunk)
	end
	self.chunks[i] = nil
	self.short[i] = nil
	self.tris[i] = nil
	self.far[i] = nil
	self.removed += 1
end

-- The furthest chunk held behind both the car and chunk `i`, if any: the one to let go when
-- the device has no room for `i`.
function SplineRoadView._furthestBehind(self: View, i: number): number?
	local limit = math.min(i, self.here)
	local best: number? = nil
	for j in self.chunks do
		if j < limit and (not best or j < best) then
			best = j
		end
	end
	return best
end

function SplineRoadView._build(self: View, i: number, far: boolean?)
	local L = Config.Spline.Mesh.ChunkLength
	local s0 = i * L
	local s1 = math.min((i + 1) * L, self.spline.length)
	local t0 = os.clock()
	local opts: any = { forceFail = self.forceFallback }
	if far then
		-- FAR AWAY (T-263): fewer cross-sections and one strip across, so the long settings fit
		-- the mesh budget; rebuilt whole as the car comes within `Near`
		local F = Config.Spline.Mesh.Far
		opts.tolerance, opts.maxStep, opts.across = F.Tolerance, F.MaxStep, F.Across
	end
	local model, info = SplineMesh.build(self.spline, s0, s1, self.folder, opts)
	-- out of budget: the road ahead never pays for the road behind (T-230). Let the furthest
	-- chunk behind go, keep the window behind that short, and try again
	while not model and not self.forceFallback and not self.dead do
		local victim = self:_furthestBehind(i)
		if not victim then
			break
		end
		self:_drop(victim)
		self.squeezed += 1
		self.behindCap = math.max(0, self.here - victim - 1)
		warn(`[SplineRoadView] out of mesh budget: let chunk {victim} behind the car go to draw chunk {i}`)
		model, info = SplineMesh.build(self.spline, s0, s1, self.folder, opts)
	end
	local chunk: Instance
	if model then
		chunk = model
		self.triangles += info.triangles
		self.tris[i] = info.triangles
		self.lastSliceMs = info.sliceMs or 0
		self.worstSliceMs = math.max(self.worstSliceMs, self.lastSliceMs)
		self.lastSlices = info.slices or 1
	else
		-- this device cannot make the mesh: draw the chunk as parts instead
		self.fallbacks += 1
		self.tris[i] = nil
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
	self.far[i] = far == true
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
	self.here = math.clamp(math.floor(at / L), 0, last)
	-- from the chunk the player's "Road behind" reaches back into (T-230), or fewer if this
	-- device ran out of room for them
	local lo = math.clamp(math.floor(RoadBehind.from(at) / L), 0, last)
	if self.behindCap then
		lo = math.max(lo, self.here - self.behindCap)
	end
	-- to the chunk the player's "Road ahead" reaches into (T-263), or the road's end
	local hi = math.clamp(math.floor((at + RoadAhead.studs()) / L), 0, last)
	for i in self.chunks do
		if i < lo or i > hi then
			self:_drop(i)
		end
	end
	-- the detail each chunk wants (T-263): whole within `Near` of the car, `Far` past it
	local N = M.Near
	local function far(i: number): boolean
		return (i + 1) * L <= at - N.Behind or i * L >= at + N.Ahead
	end
	-- a chunk drawn to the old end of a road that has since grown: take it down to redraw
	if not self.building then
		-- (the old one stays up until the new one is whole, T-193)
		for i, builtTo in self.short do
			if self.spline.length > builtTo + 1e-6 and self.chunks[i] then
				self.short[i] = nil
				self.rebuilt += 1
				self:_start(i, far(i))
				return
			end
		end
	end
	if self.building then
		return
	end
	-- nearest the car first: the chunk it is in, then ahead, then behind. A chunk is wanted
	-- if it is missing, or drawn far and now near (it is rebuilt whole, the far one staying up
	-- until then)
	local function wanted(i: number): boolean
		return not self.chunks[i] or (self.far[i] == true and not far(i))
	end
	local here = math.clamp(math.floor(at / L), lo, hi)
	local want: number? = nil
	for i = here, hi do
		if wanted(i) then
			want = i
			break
		end
	end
	if not want then
		for i = here - 1, lo, -1 do
			if wanted(i) then
				want = i
				break
			end
		end
	end
	-- and last, a chunk drawn whole that is now far (the road behind, mostly): drawn again at
	-- the far detail, the furthest first, so the long settings stay within the budget
	if not want then
		local best = nil
		for i in self.chunks do
			if self.far[i] == false and far(i) and self.chunks[i]:IsA("Model") then
				if not best or math.abs(i - self.here) > math.abs(best - self.here) then
					best = i
				end
			end
		end
		want = best
	end
	if want then
		self:_start(want :: number, far(want :: number))
	end
end

-- Build chunk `i` in its own thread: it takes a few frames (T-193).
function SplineRoadView._start(self: View, i: number, far: boolean?)
	self.building = i
	task.spawn(function()
		local ok, err = pcall(self._build, self, i, far)
		if not ok then
			self.lastError = tostring(err)
			warn(`[SplineRoadView] chunk {i} failed: {err}`)
		end
		self.building = nil
	end)
end

function SplineRoadView.Destroy(self: View)
	self.dead = true
	if self.behindConn then
		self.behindConn:Disconnect()
		self.behindConn = nil
	end
	if self.aheadConn then
		self.aheadConn:Disconnect()
		self.aheadConn = nil
	end
	for i, chunk in self.chunks do
		removeChunk(chunk)
		self.chunks[i] = nil
	end
	self.closing = nil
	self.folder:Destroy()
end

function SplineRoadView.DebugState(self: View)
	local n, meshes, parts, first, lastChunk = 0, 0, 0, nil, nil
	local L = Config.Spline.Mesh.ChunkLength
	local held = 0
	for _, k in self.tris do
		held += k
	end
	for i, chunk in self.chunks do
		n += 1
		first = if first then math.min(first, i) else i
		lastChunk = if lastChunk then math.max(lastChunk, i) else i
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
		length = self.spline.length,
		-- the road behind (T-230)
		behind = RoadBehind.get(),
		behindName = RoadBehind.name(),
		behindStuds = RoadBehind.studs(),
		-- the road ahead (T-263)
		ahead = RoadAhead.get(),
		aheadName = RoadAhead.name(),
		aheadStuds = RoadAhead.studs(),
		behindCap = self.behindCap,
		squeezed = self.squeezed,
		here = self.here,
		firstChunk = first,
		drawnFrom = if first then first * L else nil, -- where the drawn road starts
		lastChunk = lastChunk,
		-- where the drawn road ends (T-263): the last chunk's end, or the road's if it is shorter
		drawnTo = if lastChunk then math.min((lastChunk + 1) * L, self.spline.length) else nil,
		trianglesHeld = held, -- in the chunks drawn now
		farChunks = (function()
			local k = 0
			for _, v in self.far do
				if v then
					k += 1
				end
			end
			return k
		end)(), -- drawn at the far detail (T-263)
	}
end

return SplineRoadView
