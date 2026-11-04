--!nonstrict
-- PlaygroundService: builds the open testing ground and hands out its named spots
-- (docs/game/features/drift-playground.md).
--
-- It builds at Init, before anything else, so the world exists before a car spawns into
-- it. Everything it builds is anchored and constraint-free except the cones, which live
-- in their own folder, are never tagged DriftSurface, and so never touch the car's
-- simulation (docs/game/DECISIONS.md, 2026-11-03).
--
-- What it builds, in order: the plate, the district of buildings, the yard blocks and
-- pillars, the banked circle, the ramp, the spots and their ground discs, the spawn pad,
-- and last of all the cones, which are rested on whatever a ray finds under them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(ServerScriptService.Playground.Build)
local Layout = require(ServerScriptService.Playground.Layout)
local Path = require(ServerScriptService.Playground.Path)

local SAMPLE_SPACING = 1 -- studs between the centre-line samples tests walk

local PlaygroundService = {}
PlaygroundService.Priority = 100 -- the world is built before anything spawns into it

PlaygroundService.Root = nil :: Folder?
PlaygroundService.Spots = {} :: { [string]: CFrame }

local tuning = Config.Playground
local palette = tuning.Palette

local features: { [string]: any } = {} -- id -> { segments, folder, samples }
local cones: { { part: BasePart, home: CFrame } } = {}
local partCount = 0

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function newFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function buildPlate(parent: Instance): Part
	local size = Layout.Plate.size
	local thickness = Layout.Plate.thickness
	return Build.surface(
		"Plate",
		Vector3.new(size, thickness, size),
		CFrame.new(0, -thickness * 0.5, 0),
		palette.Plate,
		parent
	)
end

-- The district and the two yard blocks. Untagged on purpose: a building is a wall.
local function buildBuildings(parent: Instance)
	local folder = newFolder("Buildings", parent)
	for _, list in { Layout.Buildings, Layout.Blocks } do
		for _, b in list do
			Build.block(b.id, b.x, b.z, b.sizeX, b.sizeZ, b.height, palette[b.colour], folder)
			partCount += 1
		end
	end
end

local function buildPillars(parent: Instance)
	local folder = newFolder("Pillars", parent)
	for _, p in Layout.Pillars do
		Build.pillar(p.id, p.x, p.z, p.radius, p.height, palette.Pillar, folder)
		partCount += 1
	end
end

local function buildCircle(parent: Instance)
	local spec = Layout.Circle
	local centre = Vector3.new(spec.centre.x, 0, spec.centre.z)
	local bankAt = Build.bankProfile({ shape = "flat", degrees = spec.bank }, -1) -- a right-hand turn
	local heightAt = Build.levelInnerEdge(function()
		return 0
	end, bankAt, spec.width * 0.5)

	local folder = newFolder(spec.id, parent)
	local nodes = Path.ring(centre, spec.radius, spec.segments)
	local parts = Build.ribbon(nodes, {
		name = spec.id,
		width = spec.width,
		thickness = spec.thickness,
		colour = palette[spec.colour],
		baseY = Layout.Surface.height,
		heightAt = heightAt,
		bankAt = bankAt,
		closed = true,
		parent = folder,
	})
	partCount += #parts

	local circumference = 2 * math.pi * spec.radius
	local dense = Path.ring(centre, spec.radius, math.max(8, math.ceil(circumference / SAMPLE_SPACING)))
	local samples = {}
	for i, node in dense do
		local pos, right = Build.frame(node, Layout.Surface.height + heightAt(0), bankAt(0))
		samples[i] = { pos = pos, right = right }
	end

	features[spec.id] = { id = spec.id, segments = #parts, folder = folder, samples = samples }
end

local function denseStraight(cursor, length: number, heightAt, baseY: number)
	local n = math.max(2, math.ceil(length / SAMPLE_SPACING))
	local nodes = Path.straight(Path.clone(cursor), length, n)
	local out = {}
	for i, node in nodes do
		local t = (i - 1) / (#nodes - 1)
		local pos, right = Build.frame(node, baseY + heightAt(t), 0)
		out[i] = { pos = pos, right = right }
	end
	return out
end

-- The ramp and its lip, as one chain: the lip starts exactly where the climb ended, so
-- the two share their endpoint and a ground ray reads no step between them.
local function buildRamp(parent: Instance)
	local spec = Layout.Ramp
	local folder = newFolder(spec.id, parent)
	local cursor = Path.cursor(spec.x, spec.z, spec.heading)
	local flat = Build.bankProfile(nil, 1)

	local climbAt = Build.heightProfile({ shape = "ramp", to = spec.rise }, 0)
	local startCursor = Path.clone(cursor)
	local climbNodes = Path.straight(cursor, spec.length, spec.segments)
	local climbParts = Build.ribbon(climbNodes, {
		name = spec.id,
		width = spec.width,
		thickness = spec.thickness,
		colour = palette[spec.colour],
		baseY = Layout.Surface.height,
		heightAt = climbAt,
		bankAt = flat,
		parent = folder,
	})
	partCount += #climbParts
	features[spec.id] = {
		id = spec.id,
		segments = #climbParts,
		folder = folder,
		samples = denseStraight(startCursor, spec.length, climbAt, Layout.Surface.height),
	}

	local lipCursor = Path.clone(cursor)
	local lipNodes = Path.straight(cursor, spec.lip.length, spec.lip.segments)
	local lipParts = Build.ribbon(lipNodes, {
		name = `{spec.id}Lip`,
		width = spec.width,
		thickness = spec.thickness,
		colour = palette[spec.colour],
		baseY = Layout.Surface.height,
		heightAt = function()
			return spec.rise
		end,
		bankAt = flat,
		parent = folder,
	})
	partCount += #lipParts
	features[`{spec.id}Lip`] = {
		id = `{spec.id}Lip`,
		segments = #lipParts,
		folder = folder,
		samples = denseStraight(lipCursor, spec.lip.length, function()
			return spec.rise
		end, Layout.Surface.height),
	}
end

local function buildSpots()
	local spots: { [string]: CFrame } = {}
	local lift = Vector3.new(0, Layout.Spot.height, 0)

	-- A spot on the flat plate: the given heading, the plate's top, and the spot's lift.
	for _, s in Layout.Spots do
		local at = Vector3.new(s.x, Layout.Spot.height, s.z)
		spots[s.name] = CFrame.new(at) * CFrame.Angles(0, math.rad(s.heading), 0)
	end

	-- The circle's spot is its middle, which is bare plate: you drive on to the band.
	local circle = Layout.Circle
	spots[circle.spot.name] = CFrame.new(circle.centre.x, Layout.Spot.height, circle.centre.z)
		* CFrame.Angles(0, math.rad(circle.spot.heading), 0)

	-- The ramp's spot sits on the ramp itself, facing the way it is driven.
	local ramp = features[Layout.Ramp.id]
	local n = #ramp.samples
	local i = math.clamp(math.floor((Layout.Ramp.spot.at or 0) * (n - 1)) + 1, 1, n - 1)
	local a, b = ramp.samples[i].pos, ramp.samples[i + 1].pos
	spots[Layout.Ramp.spot.name] = CFrame.lookAt(a + lift, Vector3.new(b.X, a.Y + lift.Y, b.Z))

	PlaygroundService.Spots = spots
end

-- A spot is shown by a flat disc lying on the ground, never a pillar: a marker standing
-- in the driving line blocks the view, which is what made the old course unreadable.
local function buildSpotMarkers(parent: Instance)
	local folder = newFolder("SpotMarkers", parent)
	local d = Layout.Spot.markerDiameter
	for name, cf in PlaygroundService.Spots do
		local at = cf.Position - Vector3.new(0, Layout.Spot.height, 0) + Vector3.new(0, 0.4, 0)
		local part = Build.part(
			`Spot_{name}`,
			Vector3.new(Layout.Spot.markerThickness, d, d),
			CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
			palette.SpotMarker,
			folder
		)
		part.Shape = Enum.PartType.Cylinder
		part.CanCollide = false -- a marker is to see, never to hit
		part.CanQuery = false
		part.Transparency = 0.4
		partCount += 1
	end
end

local function buildSpawnLocation(parent: Instance)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlaygroundSpawn"
	spawn.Size = Vector3.new(24, 1, 12)
	spawn.CFrame = PlaygroundService.Spots.Spawn * CFrame.new(0, -Layout.Spot.height + 0.5, 0)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false -- a ground ray must find the plate under it, not the pad
	spawn.Transparency = 0.6
	spawn.Color = palette.SpotMarker
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = parent
	partCount += 1
end

local function buildCones(parent: Instance)
	local folder = newFolder("Cones", parent)

	local spec = Layout.Cones
	local rng = Random.new(spec.seed)
	local size = Vector3.new(spec.size.x, spec.size.y, spec.size.z)

	-- A cone is scattered round a cluster's centre, which may be over the plate or over a
	-- raised feature, so rest each one on whatever is actually under it rather than on an
	-- assumed height: otherwise it hangs in the air, falls, and is put back in the air by
	-- every reset.
	local ground = RaycastParams.new()
	ground.FilterType = Enum.RaycastFilterType.Exclude
	ground.FilterDescendantsInstances = { folder, parent:FindFirstChild("SpotMarkers") }

	local index = 0
	for _, cluster in spec.clusters do
		for _ = 1, cluster.count do
			index += 1
			local angle = rng:NextNumber() * math.pi * 2
			local radius = cluster.radius * math.sqrt(rng:NextNumber())
			local at = Vector3.new(
				cluster.x + math.cos(angle) * radius,
				size.Y * 0.5 + 0.1,
				cluster.z + math.sin(angle) * radius
			)
			local below = workspace:Raycast(at + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), ground)
			if below then
				at = Vector3.new(at.X, below.Position.Y + size.Y * 0.5 + 0.1, at.Z)
			end

			local cone = Instance.new("Part")
			cone.Name = `Cone_{index}`
			cone.Shape = Enum.PartType.Cylinder -- a stand-in; no art is made for this world
			cone.Size = Vector3.new(size.Y, size.X, size.Z)
			cone.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
			cone.Color = palette.Cone
			cone.Material = Enum.Material.SmoothPlastic
			cone.CastShadow = false
			cone.Anchored = false -- the one thing physics may touch
			cone.CanCollide = true
			cone.Massless = false
			cone.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.3, 0.2)
			cone.Parent = folder

			table.insert(cones, { part = cone, home = cone.CFrame })
			partCount += 1
		end
	end
end

--------------------------------------------------------------------------------
-- Keeping it tidy
--------------------------------------------------------------------------------

local function somethingNearby(position: Vector3, radius: number): boolean
	local carFolder = workspace:FindFirstChild("Cars")
	if carFolder then
		for _, car in carFolder:GetChildren() do
			if car:IsA("Model") then
				local ok, pivot = pcall(function()
					return car:GetPivot().Position
				end)
				if ok and (pivot - position).Magnitude < radius then
					return true
				end
			end
		end
	end
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude < radius then
			return true
		end
	end
	return false
end

local function resetCones()
	local tilt = math.cos(math.rad(tuning.ConeResetTiltDegrees))
	for _, entry in cones do
		local part = entry.part
		if not part.Parent then
			continue
		end
		-- A cylinder on its side: its own X axis is the cone's up.
		local upright = part.CFrame.RightVector.Y
		local moved = (part.Position - entry.home.Position).Magnitude
		if moved > tuning.ConeResetDistance or upright < tilt then
			if not somethingNearby(entry.home.Position, tuning.ConeResetClearance) then
				part.CFrame = entry.home
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

local function catchFallers()
	local spawnCF = PlaygroundService.Spots.Spawn
	if not spawnCF then
		return
	end
	local carFolder = workspace:FindFirstChild("Cars")
	if carFolder then
		for _, car in carFolder:GetChildren() do
			if car:IsA("Model") then
				local ok, pivot = pcall(function()
					return car:GetPivot()
				end)
				if ok and pivot.Position.Y < tuning.FallY then
					car:PivotTo(spawnCF)
				end
			end
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Y < tuning.FallY then
			character:PivotTo(spawnCF * CFrame.new(0, 2, 0))
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function PlaygroundService:Build()
	-- Studio's default plate goes, so every lane and the Main place look the same.
	local default = workspace:FindFirstChild("Baseplate")
	if default and default:IsA("BasePart") then
		default:Destroy()
	end
	local existing = workspace:FindFirstChild("Playground")
	if existing then
		existing:Destroy()
	end

	table.clear(features)
	table.clear(cones)
	partCount = 0

	local root = Instance.new("Folder")
	root.Name = "Playground"

	buildPlate(root)
	partCount += 1
	buildBuildings(root)
	buildPillars(root)
	buildCircle(root)
	buildRamp(root)
	buildSpots()
	buildSpotMarkers(root)
	buildSpawnLocation(root)

	root.Parent = workspace
	PlaygroundService.Root = root

	-- The cones come last, with the world already in Workspace: each is rested on the
	-- ground by a ray, and a ray needs the surfaces to be there to hit.
	buildCones(root)

	if not RunService:IsStudio() then
		-- The fine samples are only there for the Studio tests.
		for _, feature in features do
			feature.samples = nil
		end
	end
end

function PlaygroundService:Init()
	-- A place with a hand-placed track gets that instead. Both sit at the origin, so
	-- building the plate as well would bury the track inside it (TrackService, T-031).
	local services = script.Parent
	local trackModule = services and services:FindFirstChild("TrackService")
	if trackModule and trackModule:IsA("ModuleScript") then
		local ok, track = pcall(require, trackModule)
		if ok and type(track) == "table" and type(track.HasTrack) == "function" and track:HasTrack() then
			PlaygroundService.SkippedForTrack = true
			return
		end
	end
	self:Build()
end

function PlaygroundService:Start()
	task.spawn(function()
		while true do
			task.wait(tuning.FallCheckSeconds)
			catchFallers()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(tuning.ConeResetSeconds)
			resetCones()
		end
	end)
end

--------------------------------------------------------------------------------
-- Contract (docs/game/CONTRACTS.md)
--------------------------------------------------------------------------------

function PlaygroundService:GetSpot(name: string): CFrame
	local cf = PlaygroundService.Spots[name]
	if not cf then
		local names = {}
		for spot in PlaygroundService.Spots do
			table.insert(names, spot)
		end
		table.sort(names)
		error(`PlaygroundService: no spot '{tostring(name)}'. There is: {table.concat(names, ", ")}`, 2)
	end
	return cf
end

function PlaygroundService:DebugState()
	local spots = {}
	for name, cf in PlaygroundService.Spots do
		local p = cf.Position
		spots[name] = { x = math.round(p.X * 100) / 100, y = math.round(p.Y * 100) / 100, z = math.round(p.Z * 100) / 100 }
	end
	local segments = {}
	for id, feature in features do
		segments[id] = feature.segments
	end
	return {
		built = PlaygroundService.Root ~= nil and PlaygroundService.Root.Parent ~= nil,
		partCount = partCount,
		coneCount = #cones,
		buildingCount = #Layout.Buildings + #Layout.Blocks,
		pillarCount = #Layout.Pillars,
		spots = spots,
		segments = segments,
		plate = { size = Layout.Plate.size, topY = 0 },
		open = Layout.Open,
	}
end

-- Walks the ideal centre line of a feature, raycasting down at every sample, and
-- reports how the surface height moves between samples: the fidelity check that
-- matters most (features/drift-playground.md "Rules and numbers").
-- `lateral` offsets the walk sideways from the centre line, in studs.
function PlaygroundService:DebugWalk(featureId: string, lateral: number?, every: number?)
	local feature = features[featureId]
	if not feature or not feature.samples then
		error(`PlaygroundService: no walkable samples for '{tostring(featureId)}'`, 2)
	end
	local offset = lateral or 0
	local stride = math.max(1, math.floor(every or 1))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		PlaygroundService.Root.Cones,
		PlaygroundService.Root.SpotMarkers,
	}

	local heights: { number } = {}
	local misses = 0
	local untagged = 0
	for i = 1, #feature.samples, stride do
		local s = feature.samples[i]
		local from = s.pos + s.right * offset + Vector3.new(0, 20, 0)
		local hit = workspace:Raycast(from, Vector3.new(0, -60, 0), params)
		if not hit then
			misses += 1
			continue
		end
		if not CollectionService:HasTag(hit.Instance, Build.SurfaceTag) then
			untagged += 1
		end
		table.insert(heights, hit.Position.Y)
	end

	local maxStep, total = 0, 0
	for i = 2, #heights do
		local d = math.abs(heights[i] - heights[i - 1])
		maxStep = math.max(maxStep, d)
		total += d
	end

	local minY, maxY = math.huge, -math.huge
	for _, y in heights do
		minY = math.min(minY, y)
		maxY = math.max(maxY, y)
	end

	return {
		feature = featureId,
		samples = #heights,
		spacingStuds = SAMPLE_SPACING * stride,
		lateral = offset,
		misses = misses,
		untagged = untagged,
		maxStepStuds = math.round(maxStep * 10000) / 10000,
		meanStepStuds = if #heights > 1 then math.round((total / (#heights - 1)) * 10000) / 10000 else 0,
		minY = math.round(minY * 1000) / 1000,
		maxY = math.round(maxY * 1000) / 1000,
	}
end

-- The world-space box every built part sits in, so a test can check it is on the plate.
function PlaygroundService:DebugBounds()
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in PlaygroundService.Root:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Plate" then
			minV = minV:Min(part.Position - part.Size * 0.5)
			maxV = maxV:Max(part.Position + part.Size * 0.5)
		end
	end
	return { min = minV, max = maxV }
end

-- Every obstacle as a flat footprint: {x, z, halfX, halfZ, kind, id}. The tests use it to
-- prove the streets are open, nothing drivable runs through a wall, and the yard round
-- the spawn is clear. Measured from the built parts, not from the layout, so it catches a
-- builder that places something differently from what the layout says.
function PlaygroundService:DebugObstacles()
	local out = {}
	for _, kind in { "Buildings", "Pillars" } do
		local folder = PlaygroundService.Root:FindFirstChild(kind)
		if not folder then
			continue
		end
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") then
				local size = part.Size
				local halfX, halfZ
				if part.Shape == Enum.PartType.Cylinder then
					-- Laid on its side: Y and Z are the diameter, X is the height.
					halfX, halfZ = size.Y * 0.5, size.Z * 0.5
				else
					halfX, halfZ = size.X * 0.5, size.Z * 0.5
				end
				table.insert(out, {
					id = part.Name,
					kind = kind,
					x = part.Position.X,
					z = part.Position.Z,
					halfX = halfX,
					halfZ = halfZ,
					top = part.Position.Y + (if part.Shape == Enum.PartType.Cylinder then size.X * 0.5 else size.Y * 0.5),
					bottom = part.Position.Y - (if part.Shape == Enum.PartType.Cylinder then size.X * 0.5 else size.Y * 0.5),
				})
			end
		end
	end
	return out
end

return PlaygroundService
