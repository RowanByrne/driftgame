--!nonstrict
-- PlaygroundTests: asserts the two rules that quietly break the drift model if they
-- slip — surfaces smooth enough for a ground ray, and nothing of Roblox's physics
-- touching the car — plus the named spots and the part budget.
--
-- Run it through the server debug bridge (docs/workflow/TESTING.md):
--   game.ServerStorage.DebugBridge:Invoke("DebugPlaygroundTests", "run")

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

assert(RunService:IsStudio(), "PlaygroundTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ServerScriptService.Playground.Layout)
local PlaygroundService = require(ServerScriptService.Services.PlaygroundService)

local SURFACE_TAG = "DriftSurface"
local SPOT_RAY = 5 -- studs: a spot must sit this close above a drivable surface
local MAX_STEP = 0.25 -- studs of surface height per stud travelled, along a feature
local MIN_CORNER_SEGMENTS = 24
local MIN_CIRCLE_SEGMENTS = 48

local SPOT_NAMES = {
	"Spawn",
	"StraightStart",
	"CornerEntry",
	"HairpinEntry",
	"SBendEntry",
	"CircleCentre",
	"RampBase",
}

-- The curved features and the smallest number of segments each may be built from.
local CURVES = {
	Corner = MIN_CORNER_SEGMENTS,
	Hairpin = MIN_CORNER_SEGMENTS,
	SBendA = MIN_CORNER_SEGMENTS,
	SBendB = MIN_CORNER_SEGMENTS,
	Berm = MIN_CORNER_SEGMENTS,
	Circle = MIN_CIRCLE_SEGMENTS,
}

local Tests = {}

local function spotRay(cf: CFrame)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		PlaygroundService.Root.Cones,
		PlaygroundService.Root.Markers,
		PlaygroundService.Root.SpotMarkers,
	}
	return workspace:Raycast(cf.Position, Vector3.new(0, -SPOT_RAY - 1, 0), params)
end

function Tests.run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end

	local tuning = Config.Playground
	local state = PlaygroundService:DebugState()
	local root = PlaygroundService.Root

	check("world built", state.built == true, `Workspace.Playground present: {state.built}`)

	-- 1. Named spots, each sitting on a drivable surface.
	for _, name in SPOT_NAMES do
		local ok, cf = pcall(function()
			return PlaygroundService:GetSpot(name)
		end)
		if not ok then
			check(`spot {name}`, false, tostring(cf))
			continue
		end
		local hit = spotRay(cf)
		if not hit then
			check(`spot {name}`, false, `nothing within {SPOT_RAY} studs below {cf.Position}`)
		else
			local drop = cf.Position.Y - hit.Position.Y
			local tagged = CollectionService:HasTag(hit.Instance, SURFACE_TAG)
			check(
				`spot {name}`,
				tagged and drop <= SPOT_RAY,
				`{math.round(drop * 100) / 100} studs above {hit.Instance.Name}, tagged {SURFACE_TAG}: {tagged}`
			)
		end
	end

	-- An unknown spot must error rather than return nil.
	local unknownOk = pcall(function()
		return PlaygroundService:GetSpot("NoSuchSpot")
	end)
	check("GetSpot errors on an unknown name", unknownOk == false, `pcall returned {tostring(unknownOk)}`)

	-- 2. Segment counts: the fidelity rule.
	for id, minimum in CURVES do
		local built = state.segments[id]
		check(
			`{id} segments >= {minimum}`,
			built ~= nil and built >= minimum,
			`built from {tostring(built)} segments`
		)
	end

	-- 3. Everything anchored, nothing constrained, except the cones.
	local unanchored, constraints, taggedCones, welds = {}, 0, 0, 0
	for _, d in root:GetDescendants() do
		local inCones = d:IsDescendantOf(root.Cones)
		if d:IsA("BasePart") then
			if inCones then
				if CollectionService:HasTag(d, SURFACE_TAG) then
					taggedCones += 1
				end
			elseif not d.Anchored then
				table.insert(unanchored, d:GetFullName())
			end
		elseif
			d:IsA("Constraint")
			or d:IsA("JointInstance")
			or d:IsA("WeldConstraint")
			or d:IsA("NoCollisionConstraint")
		then
			constraints += 1
			if d:IsA("WeldConstraint") or d:IsA("Weld") then
				welds += 1
			end
		end
	end
	check("every part anchored except the cones", #unanchored == 0, `{#unanchored} unanchored: {table.concat(unanchored, ", ")}`)
	check("no constraints anywhere", constraints == 0, `{constraints} constraints ({welds} welds)`)
	check("no cone is tagged DriftSurface", taggedCones == 0, `{taggedCones} of {state.coneCount} cones tagged`)
	check("cones are unanchored", (function()
		local loose = 0
		for _, c in root.Cones:GetChildren() do
			if c:IsA("BasePart") and not c.Anchored then
				loose += 1
			end
		end
		return loose == state.coneCount and loose > 0
	end)(), `{state.coneCount} cones`)

	-- 4. Part budget.
	local live = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			live += 1
		end
	end
	check(
		`part count under {tuning.PartBudget}`,
		live < tuning.PartBudget,
		`{live} parts under Workspace.Playground (DebugState says {state.partCount})`
	)

	-- 5. Smoothness: walk the ideal curve and read the surface under it.
	local walks = {
		{ id = "Circle", lateral = 0 },
		{ id = "Circle", lateral = 20 },
		{ id = "Corner", lateral = 0 },
		{ id = "Corner", lateral = 20 },
		{ id = "Berm", lateral = 0 },
		{ id = "Berm", lateral = 24 }, -- the road's edges, where a changing bank twists worst
		{ id = "Berm", lateral = -24 },
		{ id = "Hairpin", lateral = 0 },
		{ id = "Ramp", lateral = 0 },
	}
	for _, walk in walks do
		local w = PlaygroundService:DebugWalk(walk.id, walk.lateral)
		check(
			`{walk.id} ray walk at {walk.lateral} studs out: no holes`,
			w.misses == 0 and w.untagged == 0,
			`{w.samples} samples, {w.misses} missed, {w.untagged} hit something untagged`
		)
		check(
			`{walk.id} ray walk at {walk.lateral} studs out: reads as a curve`,
			w.maxStepStuds <= MAX_STEP,
			`largest height change between samples {w.maxStepStuds} studs per {w.spacingStuds} stud, mean {w.meanStepStuds}, height {w.minY} to {w.maxY}`
		)
	end

	-- 6. The berm banks the right way: its outer edge is higher than its inner.
	local half = Layout.Road.width * 0.5 - 6
	local outer = PlaygroundService:DebugWalk("Berm", -half)
	local inner = PlaygroundService:DebugWalk("Berm", half)
	check(
		"the berm's outer edge is above its inner",
		outer.maxY > inner.maxY,
		`outer peaks at {outer.maxY}, inner at {inner.maxY}`
	)

	-- 7. Everything is on the plate.
	local bounds = PlaygroundService:DebugBounds()
	local edge = Layout.Plate.size * 0.5
	check(
		"the course fits on the plate",
		bounds.min.X > -edge and bounds.max.X < edge and bounds.min.Z > -edge and bounds.max.Z < edge,
		`x {math.round(bounds.min.X)}..{math.round(bounds.max.X)}, z {math.round(bounds.min.Z)}..{math.round(bounds.max.Z)}, plate +-{edge}`
	)

	-- 8. The Studio default plate is gone, and ours is at Y = 0.
	check("Studio's default Baseplate is gone", workspace:FindFirstChild("Baseplate") == nil, "")
	local plate = root:FindFirstChild("Plate")
	local topY = plate and (plate.Position.Y + plate.Size.Y * 0.5)
	check("our plate's top is Y = 0", plate ~= nil and math.abs(topY) < 1e-3, `top at {tostring(topY)}`)

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
