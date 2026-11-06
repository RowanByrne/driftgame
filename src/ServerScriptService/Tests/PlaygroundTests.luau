--!nonstrict
-- PlaygroundTests: asserts the rules that quietly break the drift model if they slip —
-- surfaces smooth enough for a ground ray, a plate that is actually flat, nothing
-- floating, nothing drivable running through a wall — plus the named spots, the open
-- yard round the spawn, and the part budget.
--
-- Run it through the server debug bridge (docs/workflow/TESTING.md):
--   game.ServerStorage.DebugBridge:Invoke("DebugPlaygroundTests", "run")

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

assert(RunService:IsStudio(), "PlaygroundTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local RoadPieces = require(ReplicatedStorage.Shared.Road.Pieces)
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
	"HillBase",
	"HillTop",
}

-- The hill climbs at 7 degrees and its steepest piece touches about 8.8, so a stud of
-- travel moves the surface about 0.155 studs. MAX_STEP (0.25) covers that with room; this
-- is the same rule, written out for the hill so a change that made it a staircase shows up
-- as "the hill" and not as a number nobody can place.
local HILL_FLAT = 1e-3 -- studs the hill's exit may miss the plate's kerb height by
-- THE KERB IS HELD TO THE SAME LIMIT AS THE CENTRE LINE, and that is a result rather than
-- an assumption. Where a piece has grade and turn at once, two neighbouring boxes' top
-- faces cross and each stands proud of the other at the kerb; before the seams were
-- triangulated (`Config.Road.TriangulateSegments`, T-066) this hill's worst kerb step was
-- 0.336 studs per stud and needed a looser limit of its own. With the triangles in it is
-- 0.169, under the 0.25 everything else in this world is held to.
local HILL_KERB_STEP = MAX_STEP

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

	-- A place with a track used to build no playground at all, and this test reported a
	-- skip. Since T-026 it builds both and moves this one out of the track's way, so
	-- there is always a world here and every check below runs. `offset` is where it was
	-- moved to: zero with no track. Every coordinate this test takes from the LAYOUT --
	-- which is written about the origin -- is shifted by it, and everything it reads off
	-- a built part or a named spot is already in world space.
	if not root then
		check("world built", false, "no Workspace.Playground, and nothing stands it down any more")
		return { passed = false, checks = checks }
	end
	local offset = state.offset or Vector3.zero
	local function world(x: number, z: number): (number, number)
		return x + offset.X, z + offset.Z
	end

	check("world built", state.built == true, `Workspace.Playground present: {state.built}`)
	check(
		"built where this place keeps it",
		(offset.Magnitude < 1e-6) == (state.withTrack ~= true) and offset.Y == 0,
		`offset {offset}, track in this place: {tostring(state.withTrack)}`
	)

	-- The two worlds do not overlap. Only worth asking where there is a second one.
	local TrackService = require(ServerScriptService.Services.TrackService)
	local trackBounds = TrackService:Bounds()
	if trackBounds then
		local mine = PlaygroundService:Bounds()
		local apart = mine.min.X > trackBounds.max.X
			or mine.max.X < trackBounds.min.X
			or mine.min.Z > trackBounds.max.Z
			or mine.max.Z < trackBounds.min.Z
		local gapX = math.max(mine.min.X - trackBounds.max.X, trackBounds.min.X - mine.max.X)
		local gapZ = math.max(mine.min.Z - trackBounds.max.Z, trackBounds.min.Z - mine.max.Z)
		check(
			"the playground and the track do not overlap",
			apart,
			`gap {math.round(math.max(gapX, gapZ))} studs; playground x {math.round(mine.min.X)}..{math.round(mine.max.X)} z {math.round(mine.min.Z)}..{math.round(mine.max.Z)}, track x {math.round(trackBounds.min.X)}..{math.round(trackBounds.max.X)} z {math.round(trackBounds.min.Z)}..{math.round(trackBounds.max.Z)}`
		)
	end

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

	-- 4. Part budget. The hill is counted separately against its own: it is bigger than
	--    everything else in this world put together, and lumping the two would hide a
	--    change in either (Config.Playground, `HillPartBudget`).
	local hillFolder = root:FindFirstChild(Layout.Hill.id)
	local live, liveHill = 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			if hillFolder and d:IsDescendantOf(hillFolder) then
				liveHill += 1
			else
				live += 1
			end
		end
	end
	check(
		`part count under {tuning.PartBudget}`,
		live < tuning.PartBudget,
		`{live} parts under Workspace.Playground outside the hill (DebugState says {state.partCount})`
	)
	check(
		`the hill's part count under {tuning.HillPartBudget}`,
		liveHill < tuning.HillPartBudget,
		`{liveHill} parts under Workspace.Playground.{Layout.Hill.id} (DebugState says {state.hillPartCount})`
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
	local minX, minZ = world(-edge, -edge)
	local maxX, maxZ = world(edge, edge)
	check(
		"everything fits on the plate",
		bounds.min.X > minX and bounds.max.X < maxX and bounds.min.Z > minZ and bounds.max.Z < maxZ,
		`x {math.round(bounds.min.X)}..{math.round(bounds.max.X)}, z {math.round(bounds.min.Z)}..{math.round(bounds.max.Z)}, plate x {math.round(minX)}..{math.round(maxX)} z {math.round(minZ)}..{math.round(maxZ)}`
	)

	-- 8. The Studio default plate is gone -- unless the track has adopted it as its floor
	--    of last resort, in which case destroying it would take the ground out from under
	--    the other world (TrackService, T-026) -- and ours is at Y = 0.
	local plateGone = workspace:FindFirstChild(Config.Drift.TrackFloorName) == nil
	check(
		"Studio's default Baseplate is gone, or is the track's floor",
		plateGone or trackBounds ~= nil,
		if plateGone then "" else `kept as the track's floor of last resort`
	)
	local plate = root:FindFirstChild("Plate")
	local topY = plate and (plate.Position.Y + plate.Size.Y * 0.5)
	check("our plate's top is Y = 0", plate ~= nil and math.abs(topY) < PLATE_FLAT, `top at {tostring(topY)}`)

	-- 9. The plate is flat: a grid of rays over the open yard either finds the plate at
	--    exactly Y = 0, or finds an obstacle standing on it. Nothing in between.
	local params = excludeParams()
	local gridMisses, plateHits, offPlate, worstY = 0, 0, 0, 0
	local obstacleHits = 0
	for lx = Layout.Open.minX, Layout.Open.maxX, 25 do
		for lz = Layout.Open.minZ, Layout.Open.maxZ, 25 do
			local x, z = world(lx, lz)
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
	local circleX, circleZ = world(Layout.Circle.centre.x, Layout.Circle.centre.z)
	local circleAway = math.sqrt((circleX - spawn.X) ^ 2 + (circleZ - spawn.Z) ^ 2) + Layout.Circle.radius
	if circleAway > furthest then
		furthest, furthestId = circleAway, "Circle (far rim)"
	end
	local rampX, rampZ = world(Layout.Ramp.x, Layout.Ramp.z + Layout.Ramp.length + Layout.Ramp.lip.length)
	reach(rampX, rampZ, "Ramp (lip)")
	check(
		`nothing is more than {FEATURE_REACH} studs from the spawn`,
		furthest <= FEATURE_REACH,
		`furthest is {furthestId} at {math.round(furthest)} studs`
	)

	----------------------------------------------------------------------------
	-- 14. The test hill (features/test-hill.md, T-065 and T-067)
	----------------------------------------------------------------------------
	local hill = state.hill
	check(
		"the hill is built, every piece of it",
		hill ~= nil and hill.count == #Layout.Hill.pieces and hillFolder ~= nil,
		`{tostring(hill and hill.count)} pieces placed of {#Layout.Hill.pieces} in the layout, folder {tostring(hillFolder ~= nil)}`
	)

	if hill and hill.count == #Layout.Hill.pieces then
		-- THE PROFILE. Ten pieces that only ever go up, then ten that only ever come down,
		-- and the last of them level with the plate. This is the whole feature in four
		-- checks, and the heights are the server's own, read off the placed pieces.
		local climbing, descending, topAt, topY = 0, 0, 0, -math.huge
		local steepest, steepestOn = 0, "?"
		for _, p in hill.pieces do
			if p.n <= hill.climbPieces then
				climbing += if p.dy > 0 then 1 else 0
			else
				descending += if p.dy < 0 then 1 else 0
			end
			if p.endY > topY then
				topY, topAt = p.endY, p.n
			end
			if p.maxGrade > steepest then
				steepest, steepestOn = p.maxGrade, `{p.n} {p.id}`
			end
		end
		check(
			`all {hill.climbPieces} climbing pieces climb`,
			climbing == hill.climbPieces,
			`{climbing} of {hill.climbPieces} gained height`
		)
		check(
			`all {hill.count - hill.climbPieces} descending pieces descend`,
			descending == hill.count - hill.climbPieces,
			`{descending} of {hill.count - hill.climbPieces} lost height`
		)
		check(
			"the top of the hill is the end of the climb",
			topAt == hill.climbPieces and math.abs(topY - hill.topY) < HILL_FLAT,
			`highest at piece {topAt} ({topY} studs); the climb is {hill.climbPieces} pieces long`
		)
		check(
			"the hill comes back to the plate",
			math.abs(hill.exitY - hill.plateY) < HILL_FLAT,
			`the last piece ends at Y {hill.exitY}, the plate's kerb is at {hill.plateY}`
		)
		check(
			"the hill's entry is a ramp off the plate, not a step",
			hill.approachRise > 0 and hill.approachLength >= Layout.Hill.approach.minLength
				and math.abs((hill.plateY + hill.approachRise) - hill.entryY) < HILL_FLAT,
			`entry at Y {hill.entryY}, approach rises {hill.approachRise} studs over {hill.approachLength}`
				.. ` ({math.round(math.deg(math.atan(hill.approachRise / math.max(hill.approachLength, 1e-6))) * 100) / 100} deg mean)`
		)
		check(
			`nothing on the hill is steeper than Config.Road.MaxGrade ({Config.Road.MaxGrade} deg)`,
			steepest <= Config.Road.MaxGrade + 1e-6,
			`steepest is {steepest} deg, on piece {steepestOn}`
		)

		-- It does not cross itself. The generator asks this of every piece it lays; a
		-- hand-written list gets no such check unless it is made here.
		local placed = {}
		local socket = {
			x = Layout.Hill.x,
			z = Layout.Hill.z,
			yaw = math.rad(Layout.Hill.heading),
			y = 0,
			pitch = 0,
			roll = 0,
		}
		for i, id in Layout.Hill.pieces do
			local variant = RoadPieces.get(id)
			if not variant then
				break
			end
			placed[i] = RoadPieces.place(variant, socket, i)
			socket = placed[i].finish
		end
		local crossings = {}
		for i = 1, #placed do
			for j = i + 2, #placed do
				if RoadPieces.overlap(placed[i], placed[j]) then
					table.insert(crossings, `{i}:{placed[i].id} / {j}:{placed[j].id}`)
				end
			end
		end
		check(
			"no two pieces of the hill overlap",
			#placed == #Layout.Hill.pieces and #crossings == 0,
			`{#placed} placed, {#crossings} overlapping{if #crossings > 0 then ": " .. table.concat(crossings, ", ") else ""}`
		)

		-- THE SLABS ARE TAGGED AND THE WALLS ARE NOT, which is what makes a barrier a wall
		-- and the road a road (`Shared/Road/Builder`). If this ever flips, a car drives
		-- through the fence or falls through the floor.
		local rails = PlaygroundService:DebugBarrierReport()
		check(
			"the hill's road is tagged and its barriers are not",
			rails.slabs > 0 and rails.slabsTagged == rails.slabs and rails.walls > 0,
			`{rails.slabsTagged} of {rails.slabs} slabs tagged, {rails.walls} walls`
		)
		local untaggedWalls = 0
		for _, part in hillFolder:GetDescendants() do
			if part:IsA("BasePart") and part.Name:match("^Barrier_") and CollectionService:HasTag(part, SURFACE_TAG) then
				untaggedWalls += 1
			end
		end
		check("no hill barrier is tagged DriftSurface", untaggedWalls == 0, `{untaggedWalls} tagged walls`)

		-- THE SWITCH. Off, then on, with the slabs counted both times: the one way this
		-- could go wrong is by taking the ROAD away instead of the fence.
		local before = PlaygroundService:DebugBarrierReport()
		PlaygroundService:SetBarriers(false)
		local off = PlaygroundService:DebugBarrierReport()
		PlaygroundService:SetBarriers(true)
		local on = PlaygroundService:DebugBarrierReport()
		check(
			"the guardrail switch stands the walls down",
			off.wallsQueryable == 0 and off.wallsSolid == 0 and off.walls == before.walls,
			`{off.walls} walls, {off.wallsQueryable} still queryable, {off.wallsSolid} still solid`
		)
		check(
			"and does not touch the road under them",
			off.slabs == before.slabs
				and off.slabsQueryable == before.slabs
				and off.slabsSolid == before.slabs
				and off.slabsTagged == before.slabs,
			`{off.slabs} slabs: {off.slabsQueryable} queryable, {off.slabsSolid} solid, {off.slabsTagged} tagged`
		)
		check(
			"and puts them back",
			on.wallsQueryable == on.walls and on.wallsSolid == on.walls and PlaygroundService:BarriersOn(),
			`{on.wallsQueryable} of {on.walls} queryable again`
		)

		-- The ground under it. The hill stands on a plate of its own, and that plate has
		-- to cover it and meet the playground's.
		local bounds = PlaygroundService:DebugHillBounds()
		if bounds and bounds.pad then
			-- EVERY PIECE OF ROAD IS OVER THE PAD. The approach ramp is not asked the
			-- same question: crossing on to the playground's own plate is its whole job.
			local road = bounds.road
			check(
				"every piece of the hill's road stands on the hill's own plate",
				road.min.X >= bounds.pad.min.X
					and road.max.X <= bounds.pad.max.X
					and road.min.Z >= bounds.pad.min.Z
					and road.max.Z <= bounds.pad.max.Z,
				`road x {math.round(road.min.X)}..{math.round(road.max.X)} z {math.round(road.min.Z)}..{math.round(road.max.Z)},`
					.. ` pad x {math.round(bounds.pad.min.X)}..{math.round(bounds.pad.max.X)} z {math.round(bounds.pad.min.Z)}..{math.round(bounds.pad.max.Z)}`
			)
			check(
				"the approach is the only part of it that reaches the playground's plate",
				bounds.max.Z > bounds.pad.max.Z and road.max.Z <= bounds.pad.max.Z,
				`the hill reaches Z {math.round(bounds.max.Z)}, its road only {math.round(road.max.Z)}, the pad ends at {math.round(bounds.pad.max.Z)}`
			)
			local plateSouth = offset.Z - Layout.Plate.size * 0.5
			check(
				"the hill's plate meets the playground's",
				bounds.pad.max.Z >= plateSouth,
				`the pad reaches Z {math.round(bounds.pad.max.Z)}, the plate's south edge is {math.round(plateSouth)}`
			)
			-- AND IT STAYS ON THE PLAYGROUND'S SIDE OF THE WORLD. `CarService:WorldAt`
			-- answers by whichever world's spawn is nearer, so a hill that reached past
			-- the halfway line would have a car falling off it respawn on the kart track.
			local worlds = require(ServerScriptService.Services.CarService):Worlds()
			local spawn = worlds.playground
			local other = worlds.track
			if spawn and other then
				local worst, worstAt = -math.huge, Vector3.zero
				for _, x in { bounds.pad.min.X, bounds.pad.max.X } do
					for _, z in { bounds.pad.min.Z, bounds.pad.max.Z } do
						local here = Vector3.new(x, 0, z)
						local d = (here - Vector3.new(spawn.Position.X, 0, spawn.Position.Z)).Magnitude
							- (here - Vector3.new(other.Position.X, 0, other.Position.Z)).Magnitude
						if d > worst then
							worst, worstAt = d, here
						end
					end
				end
				check(
					"every corner of the hill's plate is nearer the playground than the track",
					worst < 0,
					`worst corner {worstAt} is {math.round(-worst)} studs nearer the playground`
				)
			end
		else
			check("the hill stands on its own plate", false, "no HillPad part")
		end

		-- 15. The surface, walked. Down the centre line and along both kerbs, where a
		--     graded curve's boxes twist worst (`Shared/Road/Builder`, "the same thing
		--     happens in the vertical").
		--     BOTH KERBS AS WELL AS THE CENTRE LINE, because the kerb is where a graded
		--     curve's seams go wrong and the middle of it is where they do not
		--     (`Shared/Road/Builder`, "the same thing happens in the vertical").
		local lateral = Config.Road.Width * 0.5 - 4
		local walks = {
			{ id = "Hill", lateral = 0, limit = MAX_STEP },
			{ id = "Hill", lateral = lateral, limit = HILL_KERB_STEP },
			{ id = "Hill", lateral = -lateral, limit = HILL_KERB_STEP },
			{ id = "HillApproach", lateral = 0, limit = MAX_STEP },
			{ id = "HillApproach", lateral = lateral, limit = MAX_STEP },
		}
		for _, walk in walks do
			local w = PlaygroundService:DebugWalk(walk.id, walk.lateral)
			check(
				`{walk.id} ray walk at {walk.lateral} studs out: no holes`,
				w.misses == 0 and w.untagged == 0,
				`{w.samples} samples, {w.misses} missed, {w.untagged} hit something untagged`
			)
			check(
				`{walk.id} ray walk at {walk.lateral} studs out: reads as a road`,
				w.maxStepStuds <= walk.limit,
				`largest height change between samples {w.maxStepStuds} studs per {w.spacingStuds} stud (limit {walk.limit}),`
					.. ` mean {w.meanStepStuds}, height {w.minY} to {w.maxY}`
			)
		end

		-- 16. The lift, and what a client may ask for. Every one of these goes through the
		--     real remote handler (`DebugTool`), not past it.
		-- IT AIMS AT THE CREST, which is where the climb ends and the first descending
		-- piece begins. The road there still points UP at the grade it climbed at -- that
		-- is what a crest is -- and the piece the car is put on is the one that takes it
		-- down. So the two things to assert are the height and the piece, not the pitch.
		local top = PlaygroundService:HillTopCFrame()
		local climbEnd = hill.pieces[hill.climbPieces]
		local firstDown = hill.pieces[hill.climbPieces + 1]
		check(
			"the lift aims at the top of the hill, on the piece that goes down it",
			top ~= nil
				and climbEnd ~= nil
				and firstDown ~= nil
				and math.abs((top.Position.Y - Config.Drift.RideHeight) - climbEnd.endY) < 2.0
				and firstDown.dy < 0,
			if top
				then `lift to {math.round(top.Position.X)}, {math.round(top.Position.Y * 100) / 100}, {math.round(top.Position.Z)};`
					.. ` the climb ends at Y {climbEnd and climbEnd.endY}, and piece {hill.climbPieces + 1}`
					.. ` ({firstDown and firstDown.id}) loses {firstDown and -firstDown.dy} studs`
				else "no HillTop"
		)

		local player = Players:GetPlayers()[1]
		if not player then
			check("a forged lift request does nothing", false, "there is nobody in the place: this check needs a player")
		else
			PlaygroundService:DebugClearToolLimits()
			local refusedBefore = state.toolsRefused or 0
			local liftsBefore = state.lifts or 0
			local forgeries = {
				CFrame.new(0, 5000, 0),
				Vector3.new(0, 5000, 0),
				true,
				7,
				"liftme",
				{ world = "track", x = 0, y = 5000, z = 0 },
				{ "lift" },
				workspace,
				Enum.Material.Asphalt,
				0 / 0,
			}
			for _, forged in forgeries do
				PlaygroundService:DebugTool(forged)
				PlaygroundService:DebugClearToolLimits()
			end
			local after = PlaygroundService:DebugState()
			check(
				`{#forgeries} forged tool requests do nothing and are counted`,
				(after.lifts or 0) == liftsBefore and (after.toolsRefused or 0) >= refusedBefore + #forgeries,
				`{(after.toolsRefused or 0) - refusedBefore} refused, {(after.lifts or 0) - liftsBefore} lifts happened`
			)
		end
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
