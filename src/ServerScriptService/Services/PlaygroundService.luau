--!nonstrict
-- PlaygroundService: builds the prototype playground and hands out its named spots
-- (docs/game/features/drift-playground.md).
--
-- It builds at Init, before anything else, so the world exists before a car spawns into
-- it. Everything it builds is anchored and constraint-free except the cones, which live
-- in their own folder, are never tagged DriftSurface, and so never touch the car's
-- simulation (docs/game/DECISIONS.md, 2026-11-03).

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

local steps: { [string]: any } = {} -- id -> { samples, segments, parts }
local cones: { { part: BasePart, home: CFrame } } = {}
local partCount = 0

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function sign(n: number): number
	return n >= 0 and 1 or -1
end

-- Walks one course step at a fine spacing, so tests can raycast the ideal curve rather
-- than the polygon that was built from it.
local function denseSamples(step: any, startCursor: any, heightAt, bankAt, baseY): { any }
	local length = Path.length(step.kind, step)
	local n = math.max(2, math.ceil(length / SAMPLE_SPACING))
	local cursor = Path.clone(startCursor)
	local nodes = if step.kind == "arc"
		then Path.arc(cursor, step.angle, step.radius, n)
		else Path.straight(cursor, step.length, n)

	local out = {}
	for i, node in nodes do
		local t = (i - 1) / (#nodes - 1)
		local bank = bankAt(t)
		local pos, right = Build.frame(node, baseY + heightAt(t), bank)
		out[i] = { pos = pos, right = right }
	end
	return out
end

local function buildPlate(parent: Instance): Part
	local size = Layout.Plate.size
	local thickness = Layout.Plate.thickness
	local plate = Build.surface(
		"Plate",
		Vector3.new(size, thickness, size),
		CFrame.new(0, -thickness * 0.5, 0),
		palette.Plate,
		parent
	)
	return plate
end

local function buildCourse(parent: Instance)
	local cursor = Path.cursor(Layout.Start.x, Layout.Start.z, Layout.Start.heading)
	local runningHeight = 0

	for _, step in Layout.Course do
		local startCursor = Path.clone(cursor)
		local heightAt, endHeight = Build.heightProfile(step.height, runningHeight)
		local turn = if step.kind == "arc" then sign(step.angle) else 1
		local bankAt = Build.bankProfile(step.bank, turn)
		if step.bank then
			heightAt = Build.levelInnerEdge(heightAt, bankAt, Layout.Road.width * 0.5)
		end

		local nodes = if step.kind == "arc"
			then Path.arc(cursor, step.angle, step.radius, step.segments)
			else Path.straight(cursor, step.length, step.segments)

		local folder = Instance.new("Folder")
		folder.Name = step.id
		folder.Parent = parent

		local parts = Build.ribbon(nodes, {
			name = step.id,
			width = Layout.Road.width,
			thickness = Layout.Road.thickness,
			colour = palette[step.colour] or palette.Road,
			baseY = Layout.Road.height,
			heightAt = heightAt,
			bankAt = bankAt,
			parent = folder,
		})
		partCount += #parts

		steps[step.id] = {
			id = step.id,
			segments = #parts,
			folder = folder,
			samples = denseSamples(step, startCursor, heightAt, bankAt, Layout.Road.height),
		}

		runningHeight = endHeight
	end
end

local function buildCircle(parent: Instance)
	local spec = Layout.Circle
	local centre = Vector3.new(spec.centre.x, 0, spec.centre.z)
	local bankAt = Build.bankProfile({ shape = "flat", degrees = spec.bank }, -1) -- a right-hand turn
	local heightAt = Build.levelInnerEdge(function()
		return 0
	end, bankAt, spec.width * 0.5)

	local folder = Instance.new("Folder")
	folder.Name = spec.id
	folder.Parent = parent

	local nodes = Path.ring(centre, spec.radius, spec.segments)
	local parts = Build.ribbon(nodes, {
		name = spec.id,
		width = spec.width,
		thickness = Layout.Road.thickness,
		colour = palette[spec.colour],
		baseY = Layout.Road.height,
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
		local pos, right = Build.frame(node, Layout.Road.height + heightAt(0), bankAt(0))
		samples[i] = { pos = pos, right = right }
	end

	steps[spec.id] = { id = spec.id, segments = #parts, folder = folder, samples = samples }
end

local function sampleAt(stepId: string, t: number): (Vector3, Vector3)
	local step = steps[stepId]
	if not step then
		error(`PlaygroundService: no step '{stepId}'`, 0)
	end
	local n = #step.samples
	local i = math.clamp(math.floor(t * (n - 1)) + 1, 1, n)
	local s = step.samples[i]
	return s.pos, s.right
end

local function buildMarkers(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Markers"
	folder.Parent = parent

	local size = Vector3.new(Layout.BrakeMarker.size.x, Layout.BrakeMarker.size.y, Layout.BrakeMarker.size.z)
	for _, step in Layout.Course do
		if not step.brakeMarkers then
			continue
		end
		local length = Path.length(step.kind, step)
		for _, before in step.brakeMarkers do
			local t = math.clamp((length - before) / length, 0, 1)
			local pos, right = sampleAt(step.id, t)
			for _, side in { -1, 1 } do
				local at = pos + right * (Layout.BrakeMarker.offset * side) + Vector3.new(0, size.Y * 0.5, 0)
				Build.part(`Brake_{before}_{side}`, size, CFrame.new(at), palette.BrakeMarker, folder)
				partCount += 1
			end
		end
	end
end

local function buildSpotMarkers(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SpotMarkers"
	folder.Parent = parent

	local size = Vector3.new(Layout.Spot.markerSize.x, Layout.Spot.markerSize.y, Layout.Spot.markerSize.z)
	for name, cf in PlaygroundService.Spots do
		local at = cf.Position + Vector3.new(0, size.Y * 0.5, 0)
		local part = Build.part(`Spot_{name}`, size, CFrame.new(at), palette.SpotMarker, folder)
		part.CanCollide = false -- a marker is to see, never to hit
		part.CanQuery = false
		part.Transparency = 0.35
		partCount += 1
	end
end

local function buildSpots()
	local spots: { [string]: CFrame } = {}
	local lift = Vector3.new(0, Layout.Spot.height, 0)

	local function poseAt(stepId: string, t: number): CFrame
		local step = steps[stepId]
		local n = #step.samples
		local i = math.clamp(math.floor(t * (n - 1)) + 1, 1, n - 1)
		local a = step.samples[i].pos
		local b = step.samples[i + 1].pos
		return CFrame.lookAt(a + lift, Vector3.new(b.X, a.Y + lift.Y, b.Z))
	end

	for _, step in Layout.Course do
		if step.spot then
			spots[step.spot] = poseAt(step.id, step.spotAt or 0)
		end
	end
	spots.Spawn = poseAt(Layout.Spawn.step, Layout.Spawn.at)

	local circle = Layout.Circle
	spots[circle.spot] = CFrame.new(circle.centre.x, Layout.Road.height + Layout.Spot.height, circle.centre.z)

	PlaygroundService.Spots = spots
end

local function buildSpawnLocation(parent: Instance)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlaygroundSpawn"
	spawn.Size = Vector3.new(Layout.Road.width * 0.5, 1, 12)
	spawn.CFrame = PlaygroundService.Spots.Spawn * CFrame.new(0, -Layout.Spot.height + 0.5, 0)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false -- a ground ray must find the road under it, not the pad
	spawn.Transparency = 0.6
	spawn.Color = palette.SpotMarker
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = parent
	partCount += 1
end

local function buildCones(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Cones"
	folder.Parent = parent

	local spec = Layout.Cones
	local rng = Random.new(spec.seed)
	local size = Vector3.new(spec.size.x, spec.size.y, spec.size.z)

	local placeable = {}
	for _, step in Layout.Course do
		if not spec.skipSteps[step.id] then
			table.insert(placeable, step.id)
		end
	end
	table.insert(placeable, Layout.Circle.id)

	for i = 1, spec.count do
		local stepId = placeable[rng:NextInteger(1, #placeable)]
		local pos, right = sampleAt(stepId, rng:NextNumber())
		local lateral = rng:NextNumber(spec.lateralMin, spec.lateralMax) * (rng:NextInteger(0, 1) == 0 and -1 or 1)
		local at = pos + right * lateral + Vector3.new(0, size.Y * 0.5 + 0.1, 0)

		local cone = Instance.new("Part")
		cone.Name = `Cone_{i}`
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

	table.clear(steps)
	table.clear(cones)
	partCount = 0

	local root = Instance.new("Folder")
	root.Name = "Playground"

	buildPlate(root)
	partCount += 1
	buildCourse(root)
	buildCircle(root)
	buildSpots()
	buildMarkers(root)
	buildSpotMarkers(root)
	buildSpawnLocation(root)
	buildCones(root)

	root.Parent = workspace
	PlaygroundService.Root = root

	if not RunService:IsStudio() then
		-- The fine samples are only there for the Studio tests.
		for _, step in steps do
			step.samples = nil
		end
	end
end

function PlaygroundService:Init()
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
	for id, step in steps do
		segments[id] = step.segments
	end
	return {
		built = PlaygroundService.Root ~= nil and PlaygroundService.Root.Parent ~= nil,
		partCount = partCount,
		coneCount = #cones,
		spots = spots,
		segments = segments,
		plate = { size = Layout.Plate.size, topY = 0 },
	}
end

-- Walks the ideal centre line of a feature, raycasting down at every sample, and
-- reports how the surface height moves between samples: the fidelity check that
-- matters most (features/drift-playground.md "Rules and numbers").
-- `lateral` offsets the walk sideways from the centre line, in studs.
function PlaygroundService:DebugWalk(stepId: string, lateral: number?, every: number?)
	local step = steps[stepId]
	if not step or not step.samples then
		error(`PlaygroundService: no walkable samples for '{tostring(stepId)}'`, 2)
	end
	local offset = lateral or 0
	local stride = math.max(1, math.floor(every or 1))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		PlaygroundService.Root.Cones,
		PlaygroundService.Root.Markers,
		PlaygroundService.Root.SpotMarkers,
	}

	local heights: { number } = {}
	local misses = 0
	local untagged = 0
	for i = 1, #step.samples, stride do
		local s = step.samples[i]
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
		step = stepId,
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

return PlaygroundService
