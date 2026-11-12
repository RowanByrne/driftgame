--!strict
-- HorizonView: the mountains round the endless run, drawn on this device
-- (docs/game/features/horizon.md, T-150).
--
-- `Shared/Horizon` gives the shapes as triangles; this draws each as two wedge parts
-- (`Road/Builder.triangleSlab`) and keeps every layer round the camera, each frame, after
-- the camera has moved. Nothing here collides, is touched or is hit by a query, and nothing
-- casts a shadow: it is backdrop only.
--
-- ONE ANCHOR A LAYER: each layer's parts are welded to one anchored, invisible part, and
-- only that part is moved. Measured in the lane with 496 parts: moving them all each frame
-- (`BulkMoveTo`) cost 0.33 ms a frame; moving one anchor costs nothing measurable. Welded
-- to an anchored part they are an anchored assembly, so they are never simulated and the
-- fall height does not take them (kept 3 s at 3 000 studs down, measured).
--
-- EACH LAYER TRAILS THE CAMERA by its own `Lag` (`Horizon.follow`), so the near ridges slide
-- a little as you drive and the snow peak holds its bearing. Their height is the road's start
-- (`originY`) plus `FollowHeight` of the camera's height above it, eased over `HeightLag`, so
-- they hold their place in the frame as the road climbs and falls, sinking a little.
--
-- BUILT A FEW PARTS A FRAME (`BuildPerFrame`), so the run's start never pays for all of it
-- at once. `DriftController:UseSpline` makes one with the road and destroys it with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Builder = require(ReplicatedStorage.Shared.Road.Builder)
local Config = require(ReplicatedStorage.Shared.Config)
local Horizon = require(ReplicatedStorage.Shared.Horizon)

local HorizonView = {}
HorizonView.__index = HorizonView

local STEP_NAME = "HorizonView"

type LayerState = {
	name: string,
	lag: number,
	maxLag: number,
	radius: number,
	centre: Vector3, -- flat, Y = 0
	placedAt: Vector3?, -- where its anchor was last put
	anchor: Part, -- the one part that moves; every other part is welded to it
	parts: { BasePart },
}

export type View = typeof(setmetatable(
	{} :: {
		folder: Folder,
		originY: number,
		camY: number, -- the camera's height, eased
		lift: number, -- how far the horizon stands above the road's start now
		layers: { LayerState },
		triangles: number,
		parts: number,
		building: boolean,
		dead: boolean,
		buildMs: number,
		worstMs: number,
		lastMs: number,
		moves: number,
	},
	HorizonView
))

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function cameraAt(): Vector3
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.zero
end

function HorizonView.new(originY: number, parent: Instance?): View
	local folder = Instance.new("Folder")
	folder.Name = "Horizon"
	folder.Parent = parent or Workspace

	local layout = Horizon.layout(Config.Horizon)
	local start = flat(cameraAt())
	local layers: { LayerState } = {}
	for _, layer in layout.layers do
		local anchor = Instance.new("Part")
		anchor.Name = `{layer.name}Anchor`
		anchor.Size = Vector3.one
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.CFrame = CFrame.new(start + Vector3.yAxis * originY)
		anchor.Parent = folder
		table.insert(layers, {
			name = layer.name,
			lag = layer.lag,
			maxLag = layer.maxLag,
			radius = layer.radius,
			centre = start,
			placedAt = start,
			anchor = anchor,
			parts = {},
		})
	end

	local self = setmetatable({
		folder = folder,
		originY = originY,
		camY = cameraAt().Y,
		lift = 0,
		layers = layers,
		triangles = layout.triangles,
		parts = 0,
		building = true,
		dead = false,
		buildMs = 0,
		worstMs = 0,
		lastMs = 0,
		moves = 0,
	}, HorizonView)

	task.spawn(function()
		self:_build(layout)
	end)
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		self:Update(dt)
	end)
	return self
end

function HorizonView._build(self: View, layout: Horizon.Layout)
	local H = Config.Horizon
	local perFrame: number = H.BuildPerFrame
	local made = 0
	for i, layer in layout.layers do
		local state = self.layers[i]
		local sub = Instance.new("Folder")
		sub.Name = layer.name
		for t, tri in layer.triangles do
			if self.dead then
				return
			end
			local t0 = os.clock()
			local out: { BasePart } = {}
			-- built round the world's origin at the road's start height; `Update` moves them
			local lift = Vector3.yAxis * self.originY
			Builder.triangleSlab(`{layer.name}_{t}`, tri.a + lift, tri.b + lift, tri.c + lift, H.Thickness, tri.colour, H.Material, sub, out :: any)
			for _, p in out do
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				-- onto the anchor wherever it is now, then welded to it
				p.CFrame = (p.CFrame - lift) + state.anchor.Position
				p.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = state.anchor
				weld.Part1 = p
				weld.Parent = p
				table.insert(state.parts, p)
				self.parts += 1
				made += 1
			end
			self.buildMs += (os.clock() - t0) * 1000
			if made >= perFrame then
				made = 0
				sub.Parent = self.folder
				task.wait()
			end
		end
		sub.Parent = self.folder
	end
	self.building = false
end

-- Move every layer round the camera. Called each frame after the camera.
function HorizonView.Update(self: View, dt: number)
	if self.dead then
		return
	end
	local t0 = os.clock()
	local H = Config.Horizon
	local at = cameraAt()
	local cam = flat(at)
	self.camY += (at.Y - self.camY) * (1 - math.exp(-dt / H.HeightLag))
	local lift = H.FollowHeight * (self.camY - self.originY)
	local lifted = math.abs(lift - self.lift) > 0.01
	self.lift = lift
	for _, layer in self.layers do
		layer.centre = Horizon.follow(layer.centre, cam, dt, layer.lag, layer.maxLag)
		local placed = layer.placedAt
		if lifted or not placed or (placed - layer.centre).Magnitude > 0.01 then
			layer.anchor.CFrame = CFrame.new(layer.centre + Vector3.yAxis * (self.originY + lift))
			layer.placedAt = layer.centre
			self.moves += 1
		end
	end
	self.lastMs = (os.clock() - t0) * 1000
	self.worstMs = math.max(self.worstMs, self.lastMs)
end

function HorizonView.Destroy(self: View)
	if self.dead then
		return
	end
	self.dead = true
	RunService:UnbindFromRenderStep(STEP_NAME)
	self.folder:Destroy()
end

-- Each layer's distance behind the camera and its part count; what the horizon costs.
function HorizonView.DebugState(self: View): { [string]: any }
	local cam = flat(cameraAt())
	local layers = {}
	for _, layer in self.layers do
		table.insert(layers, {
			name = layer.name,
			parts = #layer.parts,
			behind = (cam - layer.centre).Magnitude,
			nearest = layer.radius - (cam - layer.centre).Magnitude,
		})
	end
	return {
		building = self.building,
		triangles = self.triangles,
		parts = self.parts,
		originY = self.originY,
		lift = self.lift,
		layers = layers,
		buildMs = self.buildMs,
		lastMs = self.lastMs,
		worstMs = self.worstMs,
		moves = self.moves,
	}
end

-- Forget the worst frame so far (to measure a stretch of driving on its own).
function HorizonView.DebugResetCost(self: View)
	self.worstMs = 0
end

return HorizonView
