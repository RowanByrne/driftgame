--!strict
-- VistaView: the painted vista round the run, drawn on this device
-- (docs/game/features/painted-vista.md, T-266).
--
-- A STAGE SET: painted ridge layers stand in a ring round the camera and a cloud sea lies
-- below the road; Roblox's own sky stays above them. Every number is in `Config.Vista`, the
-- sums in `Shared/Vista`.
--
-- RIDGE PANELS are curved: one arc mesh built on this device (`Config.Vista.Mesh`), shaded
-- smooth, with the art as a see-through SurfaceAppearance from `ReplicatedStorage.VistaSurfaces`, so Roblox's real sun lights the ring with no
-- step where two panels meet (flat ones showed seams: T-267, the user). Ridges facing the sun
-- are lit, ones with the sun behind them dark. The mesh's own skirt, in the art's bottom
-- row, hides its bottom edge. Until the mesh loads, or if it can't, the layers are flat
-- invisible parts with a Decal and a plain skirt. Each layer's parts are welded to one anchored, invisible part, and
-- only that part moves (measured for the old horizon: one anchor costs nothing measurable).
--
-- THE CLOUD SEA is stacked layers of invisible parts, each with the cloud as a Texture on
-- its top face. The parts move in whole tiles, so the cloud stays where it is in the world
-- while they follow the car; each layer drifts by moving its textures' offsets.
--
-- THE TIME OF DAY: `getLook` gives the sky's look now (`Controllers/SkyController`); its
-- `VistaTint` tints the panels and skirts, `CloudSeaColour` the cloud. Set only when they
-- change.
--
-- Nothing here collides, is touched or hit by a query, or casts a shadow: backdrop only.
-- `DriftController:UseSpline` makes one with the road and destroys it with it.

local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Vista = require(ReplicatedStorage.Shared.Vista)

local VistaView = {}
VistaView.__index = VistaView

local STEP_NAME = "VistaView"
local COST_SAMPLES = 240

type Look = { VistaTint: Color3?, CloudSeaColour: Color3? }

type Ridge = {
	name: string,
	lag: number,
	maxLag: number,
	slide: number,
	radius: number,
	centre: Vector3, -- flat, Y = 0
	anchor: Part,
	folder: Folder,
	decals: { any }, -- Decals, or Textures showing a slice (T-278)
	surfaces: { SurfaceAppearance },
	skirts: { { part: BasePart, base: Color3 } },
	images: { string },
	kind: string, -- "curved", "flat", or "loading"
}

type Cloud = {
	anchor: Part,
	folder: Folder,
	textures: { Texture },
	drift: number,
	heading: number,
	depth: number, -- studs under the top layer
}

export type View = typeof(setmetatable(
	{} :: {
		folder: Folder,
		originY: number,
		camY: number,
		lift: number,
		cloudTop: number,
		ridges: { Ridge },
		clouds: { Cloud },
		getLook: (() -> Look?)?,
		tint: Color3?,
		cloudColour: Color3?,
		t: number,
		parts: number,
		dead: boolean,
		lastMs: number,
		worstMs: number,
		costs: { number },
		costAt: number,
	},
	VistaView
))

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function cameraAt(): Vector3
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.zero
end

local function backdrop(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
end

local function anchorPart(name: string, at: Vector3, parent: Instance): Part
	local a = Instance.new("Part")
	a.Name = name
	a.Size = Vector3.one
	a.Transparency = 1
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.CastShadow = false
	a.CFrame = CFrame.new(at)
	a.Parent = parent
	return a
end

local function weld(anchor: BasePart, p: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = anchor
	w.Part1 = p
	w.Parent = p
end

-- The arc mesh, made once and cloned for every panel of every run.
-- IT IS KEPT AS OPAQUE CONTENT (T-274), which costs none of the client's mesh memory
-- (`Config.Spline.Mesh.Budget`): the growable mesh it is made in holds about 80 tiles however
-- little is in it, and was kept for the whole session until T-273, when the road ran out; a
-- fixed-size copy (T-273) its own size, 1 tile. That copy is kept only where the content
-- cannot be made opaque, since a MeshPart made from an EditableMesh reads its shape from it.
-- One per slice of a picture (`Config.Vista.Mesh.Slices`, T-278): each shows its share.
local arcTemplates: { MeshPart } = {}
local arcMeshes: { EditableMesh } = {}
local arcOpaque = false
local arcError: string? = nil

local function loadSlice(slice: number): MeshPart
	local ok, res = pcall(function()
		local g = Vista.arcGeometry(Config.Vista.Mesh, slice)
		local em = AssetService:CreateEditableMesh({ FixedSize = false })
		assert(em, "this device would not make an EditableMesh (out of its budget)")
		local vs, ns, us = {}, {}, {}
		for i, p in g.positions do
			vs[i] = em:AddVertex(p)
			ns[i] = em:AddNormal(g.normals[i])
			us[i] = em:AddUV(g.uvs[i])
		end
		for _, t in g.triangles do
			local a, b, c = t[1], t[2], t[3]
			local f = em:AddTriangle(vs[a], vs[b], vs[c])
			em:SetFaceNormals(f, { ns[a], ns[b], ns[c] })
			em:SetFaceUVs(f, { us[a], us[b], us[c] })
		end
		local okOpaque, result, opaque = pcall(function()
			return AssetService:CreateDataModelContentAsync(Content.fromObject(em))
		end)
		local content: Content
		local fixed: EditableMesh? = nil
		if okOpaque and result == Enum.CreateContentResult.Success then
			em:Destroy()
			content = opaque
		else
			local okCopy, copy = pcall(function()
				return AssetService:CreateEditableMeshAsync(Content.fromObject(em), { FixedSize = true })
			end)
			em:Destroy()
			assert(okCopy and copy, "this device would not copy the arc into a fixed-size mesh (out of its budget)")
			fixed = copy
			content = Content.fromObject(copy)
		end
		local okPart, part = pcall(function()
			return AssetService:CreateMeshPartAsync(content, {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Precise,
			})
		end)
		if not okPart then
			if fixed then
				fixed:Destroy()
			end
			error(part)
		end
		if fixed then
			table.insert(arcMeshes, fixed)
		end
		return part
	end)
	if not ok then
		error(res)
	end
	return res
end

-- Every slice's mesh, or nil if any could not be made (then the layers are flat).
local function loadArc(): { MeshPart }?
	if arcError then
		return nil
	end
	if #arcTemplates == 0 then
		local ok, res = pcall(function()
			local made = {}
			for j = 0, (Config.Vista.Mesh.Slices or 1) - 1 do
				made[j + 1] = loadSlice(j)
			end
			return made
		end)
		if not ok then
			arcError = tostring(res)
			return nil
		end
		arcTemplates = res
		arcOpaque = #arcMeshes == 0
	end
	return arcTemplates
end

local function surfaceFor(image: string): SurfaceAppearance?
	local folder = ReplicatedStorage:FindFirstChild("VistaSurfaces")
	local id = string.match(image, "%d+$")
	local sa = if folder and id then folder:FindFirstChild(id) else nil
	return if sa and sa:IsA("SurfaceAppearance") then sa else nil
end

local function times(a: Color3, b: Color3): Color3
	return Color3.new(a.R * b.R, a.G * b.G, a.B * b.B)
end

-- `getLook`: the sky's look now, or nil before the sky has one.
function VistaView.new(originY: number, getLook: (() -> Look?)?, parent: Instance?): View
	local folder = Instance.new("Folder")
	folder.Name = "Vista"

	local start = flat(cameraAt())
	local camY = cameraAt().Y
	local self = setmetatable({
		folder = folder,
		originY = originY,
		camY = camY,
		lift = 0,
		cloudTop = 0,
		ridges = {},
		clouds = {},
		getLook = getLook,
		tint = nil,
		cloudColour = nil,
		t = 0,
		parts = 0,
		dead = false,
		lastMs = 0,
		worstMs = 0,
		costs = {},
		costAt = 0,
	}, VistaView)

	self:_buildRidges(start)
	if Config.Vista.CloudSea.Enabled ~= false then
		self:_buildClouds(start)
	end
	folder.Parent = parent or Workspace

	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		self:Update(dt)
	end)
	self:Update(0)
	return self
end

function VistaView._buildRidges(self: View, start: Vector3)
	local layers = {}
	for _, layer in Config.Vista.Layers do
		if #(layer.Images or {}) > 0 then
			table.insert(layers, layer)
		end
	end
	for _, layer in layers do
		local sub = Instance.new("Folder")
		sub.Name = layer.Name
		local anchor = anchorPart(`{layer.Name}Anchor`, start + Vector3.yAxis * self.originY, sub)
		sub.Parent = self.folder
		table.insert(self.ridges, {
			name = layer.Name,
			lag = layer.Lag,
			maxLag = layer.MaxLag,
			slide = layer.Slide or Config.Vista.FollowHeight,
			radius = layer.Radius,
			centre = start,
			anchor = anchor,
			folder = sub,
			decals = {},
			surfaces = {},
			skirts = {},
			images = {},
			kind = "loading",
		})
	end
	local mesh = Config.Vista.Mesh
	if not mesh.Build then
		for i, layer in layers do
			self:_fillFlat(self.ridges[i], layer)
		end
		return
	end
	-- the mesh loads off the frame: the road is up meanwhile, the ridges a moment after
	task.spawn(function()
		local arc = loadArc()
		if self.dead then
			return
		end
		for i, layer in layers do
			if arc then
				self:_fillCurved(self.ridges[i], layer, arc)
			else
				self:_fillFlat(self.ridges[i], layer)
			end
		end
		self.tint = nil -- colour the new panels
	end)
end

local function noteImage(ridge: Ridge, image: string)
	if not table.find(ridge.images, image) then
		table.insert(ridge.images, image)
	end
end

function VistaView._fillCurved(self: View, ridge: Ridge, layer: any, arcs: { MeshPart })
	local at = ridge.anchor.CFrame
	for _, panel in Vista.arcs(layer, Config.Vista.Mesh) do
		local p = arcs[(panel.slice or 0) + 1]:Clone()
		p.Name = `{layer.Name}_{panel.index}`
		p.Size = panel.size
		p.CFrame = at * panel.cframe
		p.DoubleSided = false
		backdrop(p)
		weld(ridge.anchor, p)
		local made = if panel.image ~= "" then surfaceFor(panel.image) else nil
		if made then
			local sa = made:Clone()
			sa.Parent = p
			table.insert(ridge.surfaces, sa)
			noteImage(ridge, panel.image)
		else
			p.Transparency = 1
		end
		p.Parent = ridge.folder
		self.parts += 1
	end
	ridge.kind = "curved"
end

function VistaView._fillFlat(self: View, ridge: Ridge, layer: any)
	local at = ridge.anchor.CFrame
	for _, panel in Vista.panels(layer) do
		local p = Instance.new("Part")
		p.Name = `{layer.Name}_{panel.index}`
		p.Size = panel.size
		p.CFrame = at * panel.cframe
		p.Transparency = 1
		backdrop(p)
		weld(ridge.anchor, p)
		if panel.image ~= "" then
			-- a slice of its picture (T-278): a Texture as wide as the whole picture, shifted
			local slices = panel.slices or 1
			local d: any = if slices > 1 then Instance.new("Texture") else Instance.new("Decal")
			d.Face = Enum.NormalId.Front
			d.Texture = panel.image
			if slices > 1 then
				d.StudsPerTileU = panel.size.X * slices
				d.StudsPerTileV = panel.size.Y
				d.OffsetStudsU = panel.size.X * (panel.slice or 0)
			end
			d.Parent = p
			table.insert(ridge.decals, d)
			noteImage(ridge, panel.image)
		end
		p.Parent = ridge.folder
		self.parts += 1
		if panel.skirt then
			local sk = Instance.new("Part")
			sk.Name = `{layer.Name}_{panel.index}_Skirt`
			sk.Size = panel.skirt.size
			sk.CFrame = at * panel.skirt.cframe
			sk.Material = Enum.Material.SmoothPlastic
			sk.Color = layer.BaseColour
			sk.TopSurface = Enum.SurfaceType.Smooth
			sk.BottomSurface = Enum.SurfaceType.Smooth
			backdrop(sk)
			weld(ridge.anchor, sk)
			sk.Parent = ridge.folder
			table.insert(ridge.skirts, { part = sk, base = layer.BaseColour })
			self.parts += 1
		end
	end
	ridge.kind = "flat"
end

function VistaView._buildClouds(self: View, start: Vector3)
	local sea = Config.Vista.CloudSea
	local sub = Instance.new("Folder")
	sub.Name = "CloudSea"
	for i, layer in sea.Layers do
		local cells = Vista.cloudParts(sea, layer.Grid)
		local lf = Instance.new("Folder")
		lf.Name = `Cloud_{i}`
		local anchor = anchorPart(`Cloud_{i}_Anchor`, Vista.snap(start, sea.Tile), lf)
		local cloud: Cloud = {
			anchor = anchor,
			folder = lf,
			textures = {},
			drift = layer.Drift,
			heading = layer.Heading,
			depth = (i - 1) * sea.Gap,
		}
		for c, offset in cells do
			local p = Instance.new("Part")
			p.Name = `Cloud_{i}_{c}`
			p.Size = Vector3.new(sea.PartSize, 1, sea.PartSize)
			p.CFrame = anchor.CFrame + offset
			p.Transparency = 1
			backdrop(p)
			weld(anchor, p)
			if sea.Image ~= "" then
				local tex = Instance.new("Texture")
				tex.Face = Enum.NormalId.Top
				tex.Texture = sea.Image
				tex.StudsPerTileU = sea.Tile
				tex.StudsPerTileV = sea.Tile
				tex.Transparency = layer.Transparency
				tex.Parent = p
				table.insert(cloud.textures, tex)
			end
			p.Parent = lf
			self.parts += 1
		end
		lf.Parent = sub
		table.insert(self.clouds, cloud)
	end
	sub.Parent = self.folder
end

function VistaView._colour(self: View)
	local get = self.getLook
	local look = if get then get() else nil
	if not look then
		return
	end
	local tint = look.VistaTint
	if tint and tint ~= self.tint then
		self.tint = tint
		for _, ridge in self.ridges do
			for _, d in ridge.decals do
				d.Color3 = tint
			end
			for _, sa in ridge.surfaces do
				sa.Color = tint
			end
			for _, s in ridge.skirts do
				s.part.Color = times(s.base, tint)
			end
		end
	end
	local colour = look.CloudSeaColour
	if colour and colour ~= self.cloudColour then
		self.cloudColour = colour
		for _, cloud in self.clouds do
			for _, tex in cloud.textures do
				tex.Color3 = colour
			end
		end
	end
end

-- Move everything round the camera. Called each frame after the camera.
function VistaView.Update(self: View, dt: number)
	if self.dead then
		return
	end
	local t0 = os.clock()
	local V = Config.Vista
	local sea = V.CloudSea
	local at = cameraAt()
	local cam = flat(at)
	self.t += dt
	self.camY += (at.Y - self.camY) * (if dt > 0 then 1 - math.exp(-dt / V.HeightLag) else 1)
	self.lift = Vista.lift(V, self.originY, self.camY)

	for _, ridge in self.ridges do
		ridge.centre = Vista.follow(ridge.centre, cam, dt, ridge.lag, ridge.maxLag)
		local level = self.originY + Vista.lift(V, self.originY, self.camY, ridge.slide)
		ridge.anchor.CFrame = CFrame.new(ridge.centre + Vector3.yAxis * level)
	end

	self.cloudTop = Vista.cloudTop(V, self.originY, self.camY)
	local snapped = Vista.snap(cam, sea.Tile)
	for _, cloud in self.clouds do
		local want = snapped + Vector3.yAxis * (self.cloudTop - cloud.depth)
		if (cloud.anchor.Position - want).Magnitude > 0.01 then
			cloud.anchor.CFrame = CFrame.new(want)
		end
		local u, v = Vista.drift(self.t, cloud.drift, cloud.heading, sea.Tile)
		for _, tex in cloud.textures do
			tex.OffsetStudsU = u
			tex.OffsetStudsV = v
		end
	end

	self:_colour()

	local ms = (os.clock() - t0) * 1000
	self.lastMs = ms
	self.worstMs = math.max(self.worstMs, ms)
	self.costAt = self.costAt % COST_SAMPLES + 1
	self.costs[self.costAt] = ms
end

-- Show or hide the whole vista, or one part of it: a layer's name, or "CloudSea".
function VistaView.SetShown(self: View, shown: boolean, part: string?)
	if not part then
		self.folder.Parent = if shown then Workspace else nil
		return
	end
	for _, ridge in self.ridges do
		if ridge.name == part then
			ridge.folder.Parent = if shown then self.folder else nil
		end
	end
	if part == "CloudSea" then
		local sea = self.folder:FindFirstChild("CloudSea")
		for _, cloud in self.clouds do
			cloud.folder.Parent = if shown then sea else nil
		end
	end
end

function VistaView.Destroy(self: View)
	if self.dead then
		return
	end
	self.dead = true
	RunService:UnbindFromRenderStep(STEP_NAME)
	self.folder:Destroy()
end

local function fetched(id: string): boolean
	local ok, status = pcall(function()
		return ContentProvider:GetAssetFetchStatus(id)
	end)
	return ok and status == Enum.AssetFetchStatus.Success
end

-- Each layer's parts and trail behind the camera; the cloud sea's height; the cost.
function VistaView.DebugState(self: View): { [string]: any }
	local at = cameraAt()
	local cam = flat(at)
	local layers = {}
	local images, loaded = 0, 0
	for _, ridge in self.ridges do
		local panels = 0
		for _, child in ridge.folder:GetChildren() do
			if child:IsA("BasePart") and child ~= ridge.anchor then
				panels += 1
			end
		end
		for _, id in ridge.images do
			images += 1
			if fetched(id) then
				loaded += 1
			end
		end
		table.insert(layers, {
			name = ridge.name,
			kind = ridge.kind,
			level = ridge.anchor.Position.Y,
			parts = panels,
			radius = ridge.radius,
			behind = (cam - ridge.centre).Magnitude,
			shown = ridge.folder.Parent ~= nil,
		})
	end
	local sea = Config.Vista.CloudSea
	if sea.Image ~= "" then
		images += 1
		if fetched(sea.Image) then
			loaded += 1
		end
	end
	local sorted = table.clone(self.costs)
	table.sort(sorted)
	return {
		parts = self.parts,
		meshError = arcError,
		-- the arc's mesh holds none of the client's mesh memory (T-274), or a fixed-size copy
		arcOpaque = arcOpaque,
		arcFixed = #arcMeshes > 0,
		originY = self.originY,
		lift = self.lift,
		layers = layers,
		cloudTop = self.cloudTop,
		cloudBelowCamera = at.Y - self.cloudTop,
		cloudLayers = #self.clouds,
		tint = if self.tint then self.tint:ToHex() else nil,
		cloudColour = if self.cloudColour then self.cloudColour:ToHex() else nil,
		images = images,
		imagesLoaded = loaded,
		lastMs = self.lastMs,
		medianMs = if #sorted > 0 then sorted[math.ceil(#sorted / 2)] else 0,
		worstMs = self.worstMs,
		shown = self.folder.Parent ~= nil,
	}
end

-- Forget the cost so far (to measure a stretch of driving on its own).
function VistaView.DebugResetCost(self: View)
	self.worstMs = 0
	self.costs = {}
	self.costAt = 0
end

return VistaView
