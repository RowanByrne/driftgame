--!nonstrict
-- GarageRoomTests: the garage interior's checks (T-102; docs/game/WORLD.md "Garage").
--
-- Run it from the server debug bridge, in a playtest:
--   game.ServerStorage.DebugBridge:Invoke("DebugGarageRoomTests", "run")
--
-- It rebuilds the room twice on purpose (the "no duplicates" check) and leaves it built,
-- with the turntable back at angle 0. It needs no player.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

assert(RunService:IsStudio(), "GarageRoomTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ServerScriptService.GarageRoom.Layout)
local GarageRoomService = require(ServerScriptService.Services.GarageRoomService)

local SAMPLE = 0.5 -- studs between the samples of the walk from the street to the deck
-- Studs of empty space round the room, at the least. The room stands in the playground's
-- yard now (Config.GarageRoom), so the ground it stands on -- any part whose top is at or
-- below the garage floor -- is not counted; anything else must keep this far off.
local MIN_CLEARANCE = 4
-- The car, as a box to sweep through the door: wider and taller than the AE86's shell
-- (6.8 wide, about 4.5 tall at ride height), lifted off the floor by its ground clearance.
local CAR_BOX = Vector3.new(7.4, 4.2, 1)
local CAR_BOX_LIFT = 0.6

local GarageRoomTests = {}

local function round(x: number, places: number?): number
	local m = 10 ^ (places or 2)
	return math.round(x * m) / m
end

local function roomParts(root: Instance): { BasePart }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function rooms(): number
	local n = 0
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("GarageRoom") == true then
			n += 1
		end
	end
	return n
end

-- A part's world axis-aligned box.
local function aabb(part: BasePart): (Vector3, Vector3)
	local cf, s = part.CFrame, part.Size * 0.5
	local function abs(v: Vector3)
		return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
	end
	local half = abs(cf.XVector) * s.X + abs(cf.YVector) * s.Y + abs(cf.ZVector) * s.Z
	return cf.Position - half, cf.Position + half
end

local function gap(aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3): number
	local dx = math.max(0, aMin.X - bMax.X, bMin.X - aMax.X)
	local dy = math.max(0, aMin.Y - bMax.Y, bMin.Y - aMax.Y)
	local dz = math.max(0, aMin.Z - bMax.Z, bMin.Z - aMax.Z)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function surfaceParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged(Config.Drift.SurfaceTag)
	return params
end

-- What the car's own sweep would hit: everything solid that is not ground.
local function wallParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged(Config.Drift.SurfaceTag)
	return params
end

local function groundAt(position: Vector3, params: RaycastParams): RaycastResult?
	return Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -12, 0), params)
end

function GarageRoomTests:run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok == true, detail = detail or "" })
	end

	-- 1. Builds once, and a rebuild replaces it rather than adding a second.
	GarageRoomService:Build()
	local first = #roomParts(GarageRoomService.Root)
	GarageRoomService:Build()
	local root = GarageRoomService.Root
	local parts = roomParts(root)
	check(
		"one room after building twice",
		rooms() == 1 and #parts == first,
		`{rooms()} room(s) in the Workspace; {first} parts after the first build, {#parts} after the second`
	)
	check(
		"the part count is inside the budget",
		#parts <= Config.GarageRoom.PartBudget,
		`{#parts} parts (budget {Config.GarageRoom.PartBudget})`
	)

	-- 2. Everything anchored, and only ground tagged.
	local unanchored, tagged, taggedNotGround = 0, 0, {}
	local groundNames = { Floor = true, Street = true, Deck = true }
	for _, part in parts do
		if not part.Anchored then
			unanchored += 1
		end
		if CollectionService:HasTag(part, Config.Drift.SurfaceTag) then
			tagged += 1
			if not groundNames[part.Name] and not string.match(part.Name, "^Bevel_") then
				table.insert(taggedNotGround, part:GetFullName())
			end
		end
	end
	check("every part is anchored", unanchored == 0, `{unanchored} unanchored`)
	check(
		"only the floor, the street and the turntable are DriftSurface",
		#taggedNotGround == 0 and tagged == 3 + Layout.Turntable.segments,
		`{tagged} tagged; not ground: {table.concat(taggedNotGround, ", ")}`
	)

	-- 3. Every named point exists, in the room, and the service hands it out.
	local missing = {}
	for _, name in Layout.PointOrder do
		local cf = GarageRoomService:GetPoint(name)
		local part = root:FindFirstChild("Points") and root.Points:FindFirstChild(name)
		if not cf or not part or (cf.Position - part.Position).Magnitude > 1e-3 then
			table.insert(missing, name)
		end
	end
	check(
		`all {#Layout.PointOrder} named points exist`,
		#missing == 0 and GarageRoomService:GetPoint("NoSuchPoint") == nil,
		if #missing == 0 then table.concat(Layout.PointOrder, ", ") else `missing: {table.concat(missing, ", ")}`
	)

	-- Every car point stands on ground.
	local surfaces = surfaceParams()
	for _, name in { "TurntableTop", "CarEntry", "CarExit" } do
		local cf = GarageRoomService:GetPoint(name)
		local hit = cf and groundAt(cf.Position, surfaces)
		check(
			`{name} stands on a DriftSurface`,
			hit ~= nil and math.abs(hit.Position.Y - cf.Position.Y) < 0.02,
			if hit then `on {hit.Instance.Name}, {round(hit.Position.Y - cf.Position.Y, 3)} studs from the point` else "no ground under it"
		)
	end

	-- 4. The turntable top against the floor round it.
	local top = GarageRoomService:GetPoint("TurntableTop")
	local deckHit = top and groundAt(top.Position, surfaces)
	local floorHit = top and groundAt(top.Position + Vector3.new(0, 0, Layout.Bay.halfZ - 0.8), surfaces)
	local step = if deckHit and floorHit then deckHit.Position.Y - floorHit.Position.Y else math.huge
	check(
		"the turntable's top is within a kerb of the floor",
		deckHit ~= nil and deckHit.Instance.Name == "Deck" and floorHit ~= nil and floorHit.Instance.Name == "Floor" and step >= 0 and step <= Config.GarageRoom.MaxStep,
		`deck top {deckHit and round(deckHit.Position.Y, 3)}, floor {floorHit and round(floorHit.Position.Y, 3)}: {round(step, 3)} studs (limit {Config.GarageRoom.MaxStep}), over a {round(Layout.Turntable.bevelOuter - Layout.Turntable.bevelInner, 2)}-stud bevel`
	)

	-- 5. The drive in: from the street through the door onto the deck, ground all the way
	--    and nothing solid in the car's way.
	local entry = GarageRoomService:GetPoint("CarEntry")
	if entry and top then
		local from, to = entry.Position, top.Position
		local length = (to - from).Magnitude
		local n = math.floor(length / SAMPLE)
		local misses, maxStep, lastY, overhead = 0, 0, nil, 0
		local open = RaycastParams.new()
		for i = 0, n do
			local p = from:Lerp(to, i / n)
			local hit = groundAt(p, surfaces)
			if not hit then
				misses += 1
				continue
			end
			if lastY then
				maxStep = math.max(maxStep, math.abs(hit.Position.Y - lastY))
			end
			lastY = hit.Position.Y
			-- Unfiltered, the first thing below the car's roof must be the ground itself.
			local any = Workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -12, 0), open)
			if not any or not CollectionService:HasTag(any.Instance, Config.Drift.SurfaceTag) then
				overhead += 1
			end
		end
		check(
			"the drive in has ground all the way, with no step over a kerb",
			misses == 0 and overhead == 0 and maxStep <= Config.GarageRoom.MaxStep,
			`{n + 1} samples over {round(length, 1)} studs: {misses} missed, {overhead} under something solid, largest step {round(maxStep, 3)} studs`
		)
		local lift = Vector3.new(0, CAR_BOX_LIFT + CAR_BOX.Y * 0.5, 0)
		local start = CFrame.lookAt(from + lift, to + lift)
		local blocked = Workspace:Blockcast(start, CAR_BOX, (to + lift) - (from + lift), wallParams())
		check(
			"a car-sized box sweeps from the street to the deck without touching anything",
			blocked == nil,
			if blocked
				then `hit {blocked.Instance:GetFullName()} at {round(blocked.Distance, 1)} studs`
				else `{round(CAR_BOX.X, 1)} wide, {round(CAR_BOX.Y, 1)} tall, {round(length, 1)} studs, through the {Layout.Door.width}-stud door`
		)
	end

	-- 6. The turntable spins about its own centre, and takes its spokes with it.
	local turntable = GarageRoomService:Turntable()
	if turntable and turntable.PrimaryPart then
		local deck = turntable.PrimaryPart
		local spoke = turntable:FindFirstChild("Spoke")
		local deckBefore, spokeBefore = deck.Position, spoke and spoke.CFrame.LookVector
		GarageRoomService:SetTurntableAngle(math.pi / 2)
		local moved = (deck.Position - deckBefore).Magnitude
		local turned = spoke and math.deg(math.acos(math.clamp(spoke.CFrame.LookVector:Dot(spokeBefore), -1, 1))) or 0
		local topStill = GarageRoomService:GetPoint("TurntableTop")
		GarageRoomService:SetTurntableAngle(0)
		check(
			"the turntable spins in place",
			moved < 1e-3 and math.abs(turned - 90) < 0.1 and topStill ~= nil and (topStill.Position - top.Position).Magnitude < 1e-3,
			`deck moved {round(moved, 4)} studs, spokes turned {round(turned, 2)} degrees`
		)
		check(
			"the deck is DriftSurface, so the car stands on it",
			CollectionService:HasTag(deck, Config.Drift.SurfaceTag) and deck.CanQuery and deck.CanCollide,
			deck:GetFullName()
		)
	else
		check("the turntable is a model with a deck", false, "no Turntable or no PrimaryPart")
	end

	-- 7. Clearance: the nearest thing in the Workspace that is not the room, a player or a car.
	local roomMin, roomMax = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in parts do
		local a, b = aabb(part)
		roomMin, roomMax = roomMin:Min(a), roomMax:Max(b)
	end
	local skip = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			skip[player.Character] = true
		end
	end
	local carService = ServerScriptService.Services:FindFirstChild("CarService")
	local cars = carService and require(carService).cars
	if type(cars) == "table" then
		for _, car in cars do
			skip[car] = true
		end
	end
	local nearest, nearestName, others = math.huge, "nothing", 0
	for _, d in Workspace:GetDescendants() do
		if not d:IsA("BasePart") or d:IsA("Terrain") or d:IsDescendantOf(root) then
			continue
		end
		local owner = d:FindFirstAncestorOfClass("Model")
		local skipped = false
		while owner do
			if skip[owner] then
				skipped = true
				break
			end
			owner = owner:FindFirstAncestorOfClass("Model")
		end
		if skipped then
			continue
		end
		local a, b = aabb(d)
		if b.Y <= Config.GarageRoom.Origin.Y + 0.01 then
			continue -- the ground the room stands on
		end
		others += 1
		local g = gap(roomMin, roomMax, a, b)
		if g < nearest then
			nearest, nearestName = g, d:GetFullName()
		end
	end
	local size = roomMax - roomMin
	check(
		`at least {MIN_CLEARANCE} studs clear of everything else`,
		nearest >= MIN_CLEARANCE,
		`room spans x {round(roomMin.X, 0)}..{round(roomMax.X, 0)}, z {round(roomMin.Z, 0)}..{round(roomMax.Z, 0)}`
			.. ` ({round(size.X, 0)} by {round(size.Z, 0)}, {round(size.Y, 0)} tall); nearest of {others} other parts is`
			.. ` {nearestName}, {round(nearest, 0)} studs away`
	)

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return GarageRoomTests
