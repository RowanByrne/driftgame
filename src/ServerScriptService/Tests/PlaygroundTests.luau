--!nonstrict
-- PlaygroundTests: asserts the rules that quietly break the drift model if they slip —
-- surfaces smooth enough for a ground ray, a plate that is actually flat, nothing
-- floating, nothing drivable running through a wall — plus the named spots, the open
-- yard round the spawn, and the part budget.
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
local MIN_CIRCLE_SEGMENTS = 48
local MIN_RAMP_SEGMENTS = 24
local MIN_ALLEY = 40 -- studs: narrower than this and no car gets through at all
local FEATURE_REACH = 1000 -- studs: nothing is further from the spawn than this
local PLATE_FLAT = 1e-3 -- studs the plate's top may vary by
-- How far a cone's base may be from the surface under it. Positive is floating, which is
-- the bug this catches; a little negative is the physics solver letting a settled cone
-- rest a hair inside what it stands on, which is normal and not a hole.
local CONE_REST_ABOVE = 0.5
local CONE_REST_BELOW = -0.25

local SPOT_NAMES = {
	"Spawn",
	"OpenGround",
	"DistrictGate",
	"Boulevard",
	"TightAlley",
	"PillarRun",
	"CircleCentre",
	"RampBase",
}

local Tests = {}

local function excludeParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		PlaygroundService.Root.Cones,
		PlaygroundService.Root.SpotMarkers,
	}
	return params
end

-- The world-space footprint of a part, however it is rotated.
local function footprint(part: BasePart): (number, number, number, number)
	local cf, size = part.CFrame, part.Size
	local rx, uy, bz = cf.RightVector, cf.UpVector, cf.LookVector
	local halfX = math.abs(rx.X) * size.X * 0.5 + math.abs(uy.X) * size.Y * 0.5 + math.abs(bz.X) * size.Z * 0.5
	local halfZ = math.abs(rx.Z) * size.X * 0.5 + math.abs(uy.Z) * size.Y * 0.5 + math.abs(bz.Z) * size.Z * 0.5
	return cf.Position.X, cf.Position.Z, halfX, halfZ
end

local function overlaps(ax, az, ahx, ahz, bx, bz, bhx, bhz, slack: number): boolean
	return math.abs(ax - bx) < ahx + bhx - slack and math.abs(az - bz) < ahz + bhz - slack
end

function Tests.run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end

	local tuning = Config.Playground
	local state = PlaygroundService:DebugState()
	local root = PlaygroundService.Root

	-- A place with a hand-placed track never builds the playground -- both sit at the
	-- origin, so a place gets one or the other (TrackService, T-031). There is nothing
	-- here to test, and saying so is not a failure: every check below would otherwise
	-- index a world that was deliberately not made.
	if PlaygroundService.SkippedForTrack or not root then
		check(
			"skipped: this place has a track, not a playground",
			PlaygroundService.SkippedForTrack == true,
			if PlaygroundService.SkippedForTrack
				then "TrackService adopted a track, so PlaygroundService stood down"
				else "no Playground and no track either, which should not happen"
		)
		return { passed = PlaygroundService.SkippedForTrack == true, checks = checks, skipped = true }
	end

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
		local hit = workspace:Raycast(cf.Position, Vector3.new(0, -SPOT_RAY - 1, 0), excludeParams())
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

	-- 2. Segment counts: the fidelity rule, on the only two curved or sloped features.
	for id, minimum in { Circle = MIN_CIRCLE_SEGMENTS, Ramp = MIN_RAMP_SEGMENTS } do
		local built = state.segments[id]
		check(
			`{id} segments >= {minimum}`,
			built ~= nil and built >= minimum,
			`built from {tostring(built)} segments`
		)
	end

	-- 3. Everything anchored, nothing constrained, except the cones.
	local unanchored, constraints = {}, 0
	local taggedCones = 0
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
		end
	end
	check("every part anchored except the cones", #unanchored == 0, `{#unanchored} unanchored: {table.concat(unanchored, ", ")}`)
	check("no constraints anywhere", constraints == 0, `{constraints} constraints`)
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

	-- 5. Smoothness: walk the ideal line of each elevated feature and read the surface
	--    under it, at its centre and at both edges, where a banked box twists worst.
	local walks = {
		{ id = "Circle", lateral = 0 },
		{ id = "Circle", lateral = 24 },
		{ id = "Circle", lateral = -24 },
		{ id = "Ramp", lateral = 0 },
		{ id = "Ramp", lateral = 24 },
		{ id = "Ramp", lateral = -24 },
		{ id = "RampLip", lateral = 0 },
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

	-- 6. The circle banks the right way: its outer edge is higher than its inner.
	local half = Layout.Circle.width * 0.5 - 6
	local outer = PlaygroundService:DebugWalk("Circle", -half)
	local inner = PlaygroundService:DebugWalk("Circle", half)
	check(
		"the circle's outer edge is above its inner",
		outer.maxY > inner.maxY + 1,
		`outer at {outer.maxY}, inner at {inner.maxY}`
	)

	-- 7. Everything is on the plate.
	local bounds = PlaygroundService:DebugBounds()
	local edge = Layout.Plate.size * 0.5
	check(
		"everything fits on the plate",
		bounds.min.X > -edge and bounds.max.X < edge and bounds.min.Z > -edge and bounds.max.Z < edge,
		`x {math.round(bounds.min.X)}..{math.round(bounds.max.X)}, z {math.round(bounds.min.Z)}..{math.round(bounds.max.Z)}, plate +-{edge}`
	)

	-- 8. The Studio default plate is gone, and ours is at Y = 0.
	check("Studio's default Baseplate is gone", workspace:FindFirstChild("Baseplate") == nil, "")
	local plate = root:FindFirstChild("Plate")
	local topY = plate and (plate.Position.Y + plate.Size.Y * 0.5)
	check("our plate's top is Y = 0", plate ~= nil and math.abs(topY) < PLATE_FLAT, `top at {tostring(topY)}`)

	-- 9. The plate is flat: a grid of rays over the open yard either finds the plate at
	--    exactly Y = 0, or finds an obstacle standing on it. Nothing in between.
	local params = excludeParams()
	local gridMisses, plateHits, offPlate, worstY = 0, 0, 0, 0
	local obstacleHits = 0
	for x = Layout.Open.minX, Layout.Open.maxX, 25 do
		for z = Layout.Open.minZ, Layout.Open.maxZ, 25 do
			local hit = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -300, 0), params)
			if not hit then
				gridMisses += 1
			elseif hit.Instance == plate then
				plateHits += 1
				worstY = math.max(worstY, math.abs(hit.Position.Y))
				if math.abs(hit.Position.Y) > PLATE_FLAT then
					offPlate += 1
				end
			else
				obstacleHits += 1
			end
		end
	end
	check("no hole in the open yard", gridMisses == 0, `{gridMisses} of {plateHits + obstacleHits + gridMisses} rays hit nothing`)
	check(
		"the plate is flat at Y = 0",
		offPlate == 0,
		`{plateHits} plate hits, worst |Y| {math.round(worstY * 10000) / 10000}; {obstacleHits} rays landed on something standing on it`
	)

	-- 10. Nothing floats: every building and pillar is sunk into the plate, and every
	--     cone rests on whatever is under it.
	local obstacles = PlaygroundService:DebugObstacles()
	local floating = {}
	for _, o in obstacles do
		if o.bottom > 0 then
			table.insert(floating, `{o.id} at {math.round(o.bottom * 100) / 100}`)
		end
	end
	check(
		"no building or pillar floats",
		#floating == 0,
		`{#obstacles} obstacles, {#floating} with a base above the plate: {table.concat(floating, ", ")}`
	)

	local coneParams = excludeParams()
	local coneFloat, coneMiss, highest, lowest = 0, 0, -math.huge, math.huge
	for _, cone in root.Cones:GetChildren() do
		if not cone:IsA("BasePart") then
			continue
		end
		local base = cone.Position.Y - cone.Size.X * 0.5 -- a cylinder on its side: X is its height
		local hit = workspace:Raycast(cone.Position, Vector3.new(0, -60, 0), coneParams)
		if not hit then
			coneMiss += 1
		else
			local gap = base - hit.Position.Y
			highest = math.max(highest, gap)
			lowest = math.min(lowest, gap)
			if gap > CONE_REST_ABOVE or gap < CONE_REST_BELOW then
				coneFloat += 1
			end
			if not CollectionService:HasTag(hit.Instance, SURFACE_TAG) then
				coneFloat += 1 -- a cone on a roof, not on something drivable
			end
		end
	end
	check(
		"every cone rests on a drivable surface",
		coneMiss == 0 and coneFloat == 0,
		`{state.coneCount} cones, {coneMiss} over nothing, {coneFloat} not resting on one, gap {math.round(lowest * 1000) / 1000} to {math.round(highest * 1000) / 1000} studs`
	)

	-- 11. Nothing drivable runs through a wall: no tagged surface but the plate shares a
	--     footprint with a building or a pillar, so a car never climbs one or clips a
	--     corner that is also a floor. Buildings do not overlap each other either.
	local clash = {}
	for _, part in root:GetDescendants() do
		if not part:IsA("BasePart") or part == plate or not CollectionService:HasTag(part, SURFACE_TAG) then
			continue
		end
		local px, pz, phx, phz = footprint(part)
		for _, o in obstacles do
			if overlaps(px, pz, phx, phz, o.x, o.z, o.halfX, o.halfZ, 0) then
				table.insert(clash, `{part.Name} / {o.id}`)
			end
		end
	end
	check(
		"no drivable surface runs through a building or pillar",
		#clash == 0,
		`{#clash} clashes{if #clash > 0 then ": " .. table.concat(clash, ", ", 1, math.min(5, #clash)) else ""}`
	)

	local building = {}
	for _, o in obstacles do
		if o.kind == "Buildings" then
			table.insert(building, o)
		end
	end
	local merged = {}
	for i = 1, #building do
		for j = i + 1, #building do
			local a, b = building[i], building[j]
			if overlaps(a.x, a.z, a.halfX, a.halfZ, b.x, b.z, b.halfX, b.halfZ, 0) then
				table.insert(merged, `{a.id} / {b.id}`)
			end
		end
	end
	check("no two buildings overlap", #merged == 0, `{#building} buildings, {#merged} overlapping`)

	-- 12. The streets. Measured from the layout's strips, which are what the builder uses.
	local gaps = {}
	for _, axis in { Layout.District.columns, Layout.District.rows } do
		for i = 1, #axis - 1 do
			table.insert(gaps, axis[i + 1].from - axis[i].to)
		end
	end
	table.sort(gaps)
	check(
		`every street is at least {MIN_ALLEY} studs wide`,
		gaps[1] >= MIN_ALLEY,
		`{#gaps} streets, narrowest {gaps[1]}, widest {gaps[#gaps]} studs`
	)

	-- 13. The yard round the spawn is clear, and nothing is a long drive away.
	local spawn = PlaygroundService:GetSpot("Spawn").Position
	local nearest, nearestId = math.huge, "?"
	for _, o in obstacles do
		local dx = math.max(0, math.abs(o.x - spawn.X) - o.halfX)
		local dz = math.max(0, math.abs(o.z - spawn.Z) - o.halfZ)
		local d = math.sqrt(dx * dx + dz * dz)
		if d < nearest then
			nearest, nearestId = d, o.id
		end
	end
	check(
		`nothing stands within {Layout.Open.clearRadius} studs of the spawn`,
		nearest >= Layout.Open.clearRadius,
		`nearest is {nearestId} at {math.round(nearest)} studs`
	)

	local furthest, furthestId = 0, "?"
	local function reach(x: number, z: number, id: string)
		local d = math.sqrt((x - spawn.X) ^ 2 + (z - spawn.Z) ^ 2)
		if d > furthest then
			furthest, furthestId = d, id
		end
	end
	for _, o in obstacles do
		reach(o.x + o.halfX * (if o.x >= spawn.X then 1 else -1), o.z + o.halfZ * (if o.z >= spawn.Z then 1 else -1), o.id)
	end
	local circleAway = math.sqrt((Layout.Circle.centre.x - spawn.X) ^ 2 + (Layout.Circle.centre.z - spawn.Z) ^ 2)
		+ Layout.Circle.radius
	if circleAway > furthest then
		furthest, furthestId = circleAway, "Circle (far rim)"
	end
	reach(Layout.Ramp.x, Layout.Ramp.z + Layout.Ramp.length + Layout.Ramp.lip.length, "Ramp (lip)")
	check(
		`nothing is more than {FEATURE_REACH} studs from the spawn`,
		furthest <= FEATURE_REACH,
		`furthest is {furthestId} at {math.round(furthest)} studs`
	)

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
