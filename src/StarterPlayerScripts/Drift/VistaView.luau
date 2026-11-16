--!strict
-- VistaView: the painted vista round the run, drawn on this device
-- (docs/game/features/painted-vista.md, T-266).
--
-- A STAGE SET: painted ridge layers stand in a ring round the camera and a cloud sea lies
-- below the road; Roblox's own sky stays above them. Every number is in `Config.Vista`, the
-- sums in `Shared/Vista`.
--
-- RIDGE PANELS are flat, invisible parts with the art as a Decal on the face that looks in
-- at the camera, so Roblox's real sun lights them: a panel facing the sun is lit, one with
-- the sun behind it is dark. Under each, a plain skirt in the colour of the art's base hides
-- the art's bottom edge. Each layer's parts are welded to one anchored, invisible part, and
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
	radius: number,
	centre: Vector3, -- flat, Y = 0
	anchor: Part,
	folder: Folder,
	decals: { Decal },
	skirts: { { part: BasePart, base: Color3 } },
	images: { string },
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
	self:_buildClouds(start)
	folder.Parent = parent or Workspace

	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		self:Update(dt)
	end)
	self:Update(0)
	return self
end

function VistaView._buildRidges(self: View, start: Vector3)
	for _, layer in Config.Vista.Layers do
		local sub = Instance.new("Folder")
		sub.Name = layer.Name
		local anchor = anchorPart(`{layer.Name}Anchor`, start + Vector3.yAxis * self.originY, sub)
		local ridge: Ridge = {
			name = layer.Name,
			lag = layer.Lag,
			maxLag = layer.MaxLag,
			radius = layer.Radius,
			centre = start,
			anchor = anchor,
			folder = sub,
			decals = {},
			skirts = {},
			images = {},
		}
		local at = anchor.CFrame
		for _, panel in Vista.panels(layer) do
			local p = Instance.new("Part")
			p.Name = `{layer.Name}_{panel.index}`
			p.Size = panel.size
			p.CFrame = at * panel.cframe
			p.Transparency = 1
			backdrop(p)
			weld(anchor, p)
			if panel.image ~= "" then
				local d = Instance.new("Decal")
				d.Face = Enum.NormalId.Front
				d.Texture = panel.image
				d.Parent = p
				table.insert(ridge.decals, d)
				if not table.find(ridge.images, panel.image) then
					table.insert(ridge.images, panel.image)
				end
			end
			p.Parent = sub
			self.parts += 1
			if panel.skirt then
				local s = Instance.new("Part")
				s.Name = `{layer.Name}_{panel.index}_Skirt`
				s.Size = panel.skirt.size
				s.CFrame = at * panel.skirt.cframe
				s.Material = Enum.Material.SmoothPlastic
				s.Color = layer.BaseColour
				s.TopSurface = Enum.SurfaceType.Smooth
				s.BottomSurface = Enum.SurfaceType.Smooth
				backdrop(s)
				weld(anchor, s)
				s.Parent = sub
				table.insert(ridge.skirts, { part = s, base = layer.BaseColour })
				self.parts += 1
			end
		end
		sub.Parent = self.folder
		table.insert(self.ridges, ridge)
	end
end

function VistaView._buildClouds(self: View, start: Vector3)
	local sea = Config.Vista.CloudSea
	local sub = Instance.new("Folder")
	sub.Name = "CloudSea"
	local cells = Vista.cloudParts(sea)
	for i, layer in sea.Layers do
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
	local level = self.originY + self.lift

	for _, ridge in self.ridges do
		ridge.centre = Vista.follow(ridge.centre, cam, dt, ridge.lag, ridge.maxLag)
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
