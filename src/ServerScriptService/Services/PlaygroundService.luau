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
--
-- WHERE IT BUILDS IT is the one thing that is not in the layout (T-026). A place can have
-- a hand-placed track as well (TrackService), and a track is where its author put it,
-- which is the origin -- the same place this world's 2 000-stud plate would be. So this
-- world, the one that is built from a layout and can therefore be built anywhere, moves:
-- with a track in the place everything here is shifted by
-- `Config.Drift.PlaygroundOffsetFromTrack`, and with no track the offset is zero and not
-- one coordinate changes. The shift is applied ONCE, to the built parts, the named spots
-- and the test samples together, so the layout stays a layout and nothing downstream --
-- `DebugWalk`, `DebugBounds`, `DebugObstacles` -- has to know about it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Build = require(ServerScriptService.Playground.Build)
local Layout = require(ServerScriptService.Playground.Layout)
local Path = require(ServerScriptService.Playground.Path)
-- THE TEST HILL IS MADE OF REAL ROAD PIECES (T-065), which is the only reason this world
-- knows anything about the road at all. `Road/Pieces` is pure maths and `Road/Builder`
-- turns one placed piece into parts; neither knows about the generator, the window or a
-- run, so using them here costs nothing and borrows nothing from `RoadService`. A hill
-- built out of hand-made ramps would not test what the user asked to test.
local RoadBuilder = require(ReplicatedStorage.Shared.Road.Builder)
local RoadPieces = require(ReplicatedStorage.Shared.Road.Pieces)

local SAMPLE_SPACING = 1 -- studs between the centre-line samples tests walk

local PlaygroundService = {}
PlaygroundService.Priority = 100 -- the world is built before anything spawns into it

PlaygroundService.Root = nil :: Folder?
PlaygroundService.Spots = {} :: { [string]: CFrame }
-- Where this playground was built, in world space. Zero unless the place has a track.
PlaygroundService.Offset = Vector3.zero
-- Kept so the old name still answers: nothing is skipped for a track any more (T-026).
PlaygroundService.SkippedForTrack = false

local tuning = Config.Playground
local palette = tuning.Palette

local features: { [string]: any } = {} -- id -> { segments, folder, samples }
local cones: { { part: BasePart, home: CFrame } } = {}
local partCount = 0
local hillPartCount = 0
local offset = Vector3.zero -- where this world is built; see the header
local trackPresent = false

-- The test hill, in LAYOUT coordinates (everything here is built about the origin and
-- shifted once at the end; see the header). `pieces` are `Road/Pieces.Placed`, `built`
-- the `Road/Builder.Built` entries they became.
local hill = {
	pieces = {} :: { any },
	built = {} :: { any },
	entryY = 0, -- the road's top at its first socket, in world Y
	exitY = 0, -- and at its last: the plate's own kerb height, by construction
	topY = 0,
	approachRise = 0,
	approachLength = 0,
	pad = nil :: any,
	bounds = nil :: any,
}
-- Whether the guardrails are up, for the hill AND for the road: one switch, because the
-- user asked for one button (`Drift/TestHud`, T-067).
local railsOn = true

-- TrackService, if this place has one loaded. Looked up rather than required at the top,
-- because a lane place may have no track at all and the two services must not depend on
-- each other's load order (TrackService has the higher priority, so it has already run).
local function trackService(): any?
	local services = script.Parent
	local module = services and services:FindFirstChild("TrackService")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, track = pcall(require, module)
	if ok and type(track) == "table" then
		return track
	end
	return nil
end

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

-- One ring of the bowl: the banked band, or the apron that climbs to it.
local function buildRing(id: string, folder: Instance, centre: Vector3, radius: number, segments: number, width: number, thickness: number, colour: Color3, heightAt, bankAt)
	local nodes = Path.ring(centre, radius, segments)
	local parts = Build.ribbon(nodes, {
		name = id,
		width = width,
		thickness = thickness,
		colour = colour,
		baseY = Layout.Surface.height,
		heightAt = heightAt,
		bankAt = bankAt,
		closed = true,
		parent = folder,
	})
	partCount += #parts

	local circumference = 2 * math.pi * radius
	local dense = Path.ring(centre, radius, math.max(8, math.ceil(circumference / SAMPLE_SPACING)))
	local samples = {}
	for i, node in dense do
		local pos, right = Build.frame(node, Layout.Surface.height + heightAt(0), bankAt(0))
		samples[i] = { pos = pos, right = right }
	end

	features[id] = { id = id, segments = #parts, folder = folder, samples = samples }
end

-- The bowl: the banked band, and the apron outside it that the car drives up to reach it.
-- Without the apron the band's rim is an 8-stud wall all the way round (Layout.Circle).
local function buildCircle(parent: Instance)
	local spec = Layout.Circle
	local centre = Vector3.new(spec.centre.x, 0, spec.centre.z)
	local bankAt, heightAt, skirtBankAt, skirtHeightAt = Build.circleProfiles(spec)
	local folder = newFolder(spec.id, parent)

	buildRing(spec.id, folder, centre, spec.radius, spec.segments, spec.width, spec.thickness, palette[spec.colour], heightAt, bankAt)
	buildRing(
		`{spec.id}Skirt`,
		folder,
		centre,
		spec.skirt.radius,
		spec.skirt.segments,
		spec.skirt.width,
		spec.skirt.thickness,
		palette[spec.skirt.colour],
		skirtHeightAt,
		skirtBankAt
	)
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

	local climbAt, lipAt = Build.rampProfiles(spec)
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
		heightAt = lipAt,
		bankAt = flat,
		parent = folder,
	})
	partCount += #lipParts
	features[`{spec.id}Lip`] = {
		id = `{spec.id}Lip`,
		segments = #lipParts,
		folder = folder,
		samples = denseStraight(lipCursor, spec.lip.length, lipAt, Layout.Surface.height),
	}
end

-- The body pad (Layout.BodyPad, T-196): each piece a box standing on the plate, or a slab
-- tilted so its top runs from one height to the other, tagged as road.
--
-- A SLOPE IS A TILTED BOX, NOT A WedgePart, and that is not taste: the car is kept out of
-- things by `Drift/World.penetration`, which knows a part by its box. To it a wedge is the
-- whole block the wedge was cut from, so the car met the thin end of one as a wall and
-- stopped dead (measured: 78 studs/s to nothing at the foot of the first slope). A tilted
-- box is what the ramp and the bowl are made of, and its buried underside is never seen.
local function buildBodyPad(parent: Instance)
	local spec = Layout.BodyPad
	local folder = newFolder(spec.id, parent)
	local sink = 1 -- studs a box goes into the plate
	local slab = 2 -- studs thick a slope is
	for _, p in spec.pieces do
		local x, z = spec.x + p.dx, spec.z + p.dz + p.length * 0.5
		if p.from == p.to then
			Build.surface(
				p.name,
				Vector3.new(p.width, p.from + sink, p.length),
				CFrame.new(x, (p.from - sink) * 0.5, z),
				palette[spec.colour],
				folder
			)
		else
			local run = Vector3.new(0, p.to - p.from, p.length)
			local up = Vector3.new(0, p.length, p.from - p.to).Unit
			local top = Vector3.new(x, (p.from + p.to) * 0.5, z)
			Build.surface(
				p.name,
				Vector3.new(p.width, slab, run.Magnitude),
				CFrame.fromMatrix(top - up * (slab * 0.5), Vector3.xAxis, up),
				palette[spec.colour],
				folder
			)
		end
		partCount += 1
	end
end

-- THE GUARDRAIL SWITCH, the hill's half (T-067). `RoadService` has the identical thing
-- for the endless road and the one button asks both.
--
-- IT TOUCHES THE WALLS AND NOTHING ELSE. `Road/Builder` hands back the slabs and the
-- barriers in two separate lists; the slabs are what the car's ground rays find (they are
-- tagged `DriftSurface`) and the barriers are deliberately untagged, which is what makes
-- a barrier a wall and not a kerb. Touching a slab here would take the ROAD out from
-- under the car rather than the fence beside it.
--
-- `CanQuery` IS THE ONE THAT MATTERS, not `CanCollide`: the car is kinematic, and what
-- stops it at a wall is a `Blockcast` through `RaycastParams` (`Drift/World`), which obeys
-- `CanQuery` and knows nothing about `CanCollide`. Both are set, so a player's character
-- cannot walk through a wall that is still standing either.
local function applyHillRails()
	for _, entry in hill.built do
		for _, wall in entry.barriers do
			wall.CanCollide = railsOn
			wall.CanQuery = railsOn
			wall.Transparency = if railsOn then 0 else 0.85
		end
	end
end

--------------------------------------------------------------------------------
-- The test hill (features/test-hill.md, T-065)
--------------------------------------------------------------------------------
-- A permanent stretch of the REAL endless road, built here so the user can feel a climb
-- and a descent without starting a run: ten pieces up, ten back down, and a ground of its
-- own under all of it.
--
-- WHY IT IS NOT A RAMP. The thing being judged is how the car behaves on graded road, and
-- the graded road is `Road/Pieces` and `Road/Builder`. A hand-built slope would have a
-- different profile, a different segment length and different seams, and would therefore
-- answer a different question.
--
-- THE ROAD CLIMBS AT 7 DEGREES AND DESCENDS AT 5, AND THAT ASYMMETRY IS THE PIECE SET'S,
-- not a choice made here. `Link` is the only piece in the set that climbs and it hands on
-- +7 degrees; `Corkscrew` is the only one that sets a descent and it hands on -5. Every
-- other piece CARRIES the grade it arrived at (`Config.Road.Pieces`, "the road's height is
-- a state machine"). So ten pieces up gain more than ten pieces down lose, and the two
-- halves are balanced by choosing the pieces' LENGTHS rather than their grades.
--
-- WHICH END IS PINNED. The exit is, exactly: the last piece's surface lands on
-- `Layout.Surface.height`, the quarter-stud kerb every drivable thing in this world sits
-- at, so the car drives off the end of the hill on to the ground at the same height as
-- the plate. The entry is then however much higher the twenty pieces come down -- a few
-- studs -- and a short ramp carries the plate up to it. It is that way round because a
-- ramp at the entry is taken at 20 studs/s and a ramp at the exit would be taken at 150.

-- Place the whole hill from one starting height. Pure: no instances, no Workspace.
local function placeHill(y0: number): { any }
	local spec = Layout.Hill
	local socket = { x = spec.x, z = spec.z, yaw = math.rad(spec.heading), y = y0, pitch = 0, roll = 0 }
	local placed = {}
	for i, id in spec.pieces do
		local variant = RoadPieces.get(id)
		if not variant then
			error(`PlaygroundService: the hill asks for road piece '{id}', which Config.Road.Pieces has not got`)
		end
		placed[i] = RoadPieces.place(variant, socket, i)
		socket = placed[i].finish
	end
	return placed
end

-- Fine samples down the whole hill, for `DebugWalk`: a point on the surface and the
-- surface's own right at every stud, so the tests can walk its kerbs as well as its line.
local function hillSamples(placed: { any }): { any }
	local out = {}
	for _, piece in placed do
		local n = math.max(2, math.ceil(piece.length / SAMPLE_SPACING))
		-- `i` starts at 1, not 0: t = 0 of this piece is t = 1 of the last one, and a
		-- repeated sample is a free zero in the step measurement.
		local from = if #out == 0 then 0 else 1
		for i = from, n do
			local cf = RoadPieces.poseAt(piece, i / n, Config.Road.SurfaceY)
			table.insert(out, { pos = cf.Position, right = cf.RightVector })
		end
	end
	return out
end

local function buildHill(parent: Instance)
	local spec = Layout.Hill
	table.clear(hill.pieces)
	table.clear(hill.built)
	hillPartCount = 0

	-- TWO PASSES, AND THE FIRST ONE BUILDS NOTHING. A piece's height change depends on the
	-- grade it arrived at and not at all on the absolute height, so the whole hill can be
	-- placed once at zero simply to read what it comes to, and then placed again at the
	-- height that lands its exit on the plate. Doing it this way means the balance is a
	-- fact about the pieces rather than a number somebody has to keep up to date.
	local trial = placeHill(0)
	local net = trial[#trial].finish.y
	local y0 = Layout.Surface.height - Config.Road.SurfaceY - net
	if net >= 0 then
		-- The descent does not get back down. Build it anyway, entry on the plate, so the
		-- world still exists and `PlaygroundTests` can say exactly what is wrong.
		warn(
			`[Playground] the test hill ends {string.format("%.1f", net)} studs ABOVE where it starts: `
				.. `its descent has to lose at least as much as its climb gains (Layout.Hill)`
		)
		y0 = Layout.Surface.height - Config.Road.SurfaceY
	end

	local placed = placeHill(y0)
	hill.pieces = placed
	hill.entryY = Config.Road.SurfaceY + y0
	hill.exitY = Config.Road.SurfaceY + placed[#placed].finish.y
	hill.topY = -math.huge
	for _, piece in placed do
		hill.topY = math.max(hill.topY, Config.Road.SurfaceY + piece.finish.y)
	end

	local folder = newFolder(spec.id, parent)

	-- The ground under the hill, FIRST, so everything else is built over it. The hill is
	-- 5 000 studs of road and the playground's plate is 2 000 across with a world already
	-- on it, so the hill cannot stand on it: it gets a plate of its own, sized to its own
	-- footprint and meeting the playground's at its southern edge. That is also what
	-- catches a car that drives off the side -- which is the whole point of the guardrail
	-- switch -- instead of dropping it into the void.
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, piece in placed do
		minX = math.min(minX, piece.minX)
		maxX = math.max(maxX, piece.maxX)
		minZ = math.min(minZ, piece.minZ)
		maxZ = math.max(maxZ, piece.maxZ)
	end
	hill.bounds = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
	local m = spec.pad.margin
	local plateEdge = -Layout.Plate.size * 0.5
	local padMinX, padMaxX = minX - m, maxX + m
	local padMinZ = minZ - m
	-- It never reaches further north than the playground's own plate, which it overlaps by
	-- `spec.pad.meet` studs so no ground ray can find the seam between them. Both tops are
	-- at Y = 0, so an overlap is two coplanar faces and not a step.
	local padMaxZ = math.min(maxZ + m, plateEdge + spec.pad.meet)
	local padThickness = Layout.Plate.thickness
	Build.surface(
		"HillPad",
		Vector3.new(padMaxX - padMinX, padThickness, padMaxZ - padMinZ),
		CFrame.new((padMinX + padMaxX) * 0.5, -padThickness * 0.5, (padMinZ + padMaxZ) * 0.5),
		palette[spec.pad.colour],
		folder
	)
	hillPartCount += 1
	hill.pad = { minX = padMinX, maxX = padMaxX, minZ = padMinZ, maxZ = padMaxZ }

	-- The approach: the plate climbing to wherever the road's first socket ended up. Its
	-- length comes out of the rise, so it is the same grade whatever the pieces come to.
	local rise = hill.entryY - Layout.Surface.height
	local length = math.max(spec.approach.minLength, rise / math.tan(math.rad(spec.approach.grade)))
	local f = RoadPieces.forward(math.rad(spec.heading))
	local foot = Vector3.new(spec.x, 0, spec.z) - f * length
	local cursor = Path.cursor(foot.X, foot.Z, spec.heading)
	local startCursor = Path.clone(cursor)
	local heightAt = Build.heightProfile({ shape = "ramp", to = rise }, 0)
	local flat = Build.bankProfile(nil, 1)
	local approach = Build.ribbon(Path.straight(cursor, length, spec.approach.segments), {
		name = "HillApproach",
		width = Config.Road.Width,
		-- Thick enough that its high end is still buried in the plate it rises out of.
		thickness = math.max(spec.approach.minThickness, rise + 6),
		colour = Config.Road.Colours.Road,
		baseY = Layout.Surface.height,
		heightAt = heightAt,
		bankAt = flat,
		parent = folder,
	})
	hillPartCount += #approach
	hill.approachRise = rise
	hill.approachLength = length
	features.HillApproach = {
		id = "HillApproach",
		segments = #approach,
		folder = folder,
		samples = denseStraight(startCursor, length, heightAt, Layout.Surface.height),
	}
	hill.foot = foot

	-- And the road itself, piece by piece, exactly as a run builds it.
	for _, piece in placed do
		local entry = RoadBuilder.build(piece, folder)
		table.insert(hill.built, entry)
		hillPartCount += entry.parts
	end
	applyHillRails()

	features.Hill = {
		id = "Hill",
		segments = #placed,
		folder = folder,
		samples = hillSamples(placed),
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

	-- The hill's two: where you line up for it, and the top of it.
	if #hill.pieces > 0 then
		local spec = Layout.Hill
		-- `HillBase` is on the flat, a little short of the approach ramp, so the marker
		-- disc that shows it lies on the plate and not on the slope.
		local back = RoadPieces.forward(math.rad(spec.heading)) * 16
		spots.HillBase = CFrame.new(hill.foot.X - back.X, Layout.Spot.height, hill.foot.Z - back.Z)
			* CFrame.Angles(0, math.rad(spec.heading), 0)
		-- `HillTop` is the first inch of the FIRST DESCENDING PIECE, which is the same
		-- point as the end of the climb and already faces down the hill. Read off the
		-- piece, so it follows the road's own grade and bank rather than a guess.
		local top = hill.pieces[spec.climbPieces + 1] or hill.pieces[#hill.pieces]
		spots.HillTop = RoadPieces.poseAt(top, 0.01, Config.Road.SurfaceY + Layout.Spot.height)
	end

	PlaygroundService.Spots = spots
end

-- A spot is shown by a flat disc lying on the ground, never a pillar: a marker standing
-- in the driving line blocks the view, which is what made the old course unreadable.
local function buildSpotMarkers(parent: Instance)
	local folder = newFolder("SpotMarkers", parent)
	-- THE HILL'S TWO MARKERS GO UNDER THE HILL, because the hill is a world of its own
	-- off the plate's southern edge and `DebugBounds` -- which is how `PlaygroundTests`
	-- asks "is everything on the plate?" -- skips whatever is under it. A disc 259 studs
	-- up at the top of the hill is not a thing that belongs on the plate.
	local hillFolder = parent:FindFirstChild(Layout.Hill.id)
	local hillSpots = { HillBase = true, HillTop = true }
	local d = Layout.Spot.markerDiameter
	for name, cf in PlaygroundService.Spots do
		-- IN THE SPOT'S OWN FRAME, not the world's. A spot on a slope -- `RampBase`, and
		-- now `HillTop` on a 7-degree climb -- has a tilted up, and a disc laid flat
		-- across 26 studs of 7-degree road is buried at one end and in the air at the
		-- other. Dropping down the spot's own up and turning the cylinder in the spot's
		-- own frame lays it ON the surface wherever the surface is pointing.
		local part = Build.part(
			`Spot_{name}`,
			Vector3.new(Layout.Spot.markerThickness, d, d),
			cf * CFrame.new(0, -Layout.Spot.height + 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
			palette.SpotMarker,
			if hillSpots[name] and hillFolder then hillFolder else folder
		)
		part.Shape = Enum.PartType.Cylinder
		part.CanCollide = false -- a marker is to see, never to hit
		part.CanQuery = false
		part.Transparency = 0.4
		if hillSpots[name] and hillFolder then
			hillPartCount += 1
		else
			partCount += 1
		end
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
			-- The cones are the one thing built AFTER the world has been shifted into
			-- place, because each is rested on the ground by a ray and a ray needs the
			-- ground to be where it is going to stay. So the offset is applied here, to
			-- the cluster's own coordinates, rather than afterwards.
			local at = Vector3.new(
				cluster.x + math.cos(angle) * radius,
				size.Y * 0.5 + 0.1,
				cluster.z + math.sin(angle) * radius
			) + offset
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

-- Move the whole world, once, to where it is being built.
--
-- Everything above builds from the layout, which is written about the origin, and this is
-- the only place that knows otherwise: the parts, the named spots and the fine samples
-- the tests walk all move together, so nothing downstream can be left behind. Horizontal
-- only in practice (`PlaygroundOffsetFromTrack` has no Y), which is why both worlds still
-- share one `FallY`.
local function shift(root: Instance, by: Vector3)
	if by.Magnitude < 1e-6 then
		return
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = d.CFrame + by
		end
	end
	for name, cf in PlaygroundService.Spots do
		PlaygroundService.Spots[name] = cf + by
	end
	for _, feature in features do
		if feature.samples then
			for _, sample in feature.samples do
				sample.pos = sample.pos + by
			end
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

-- Where something that has fallen out of the world belongs: the spawn of the world it
-- fell out of, which with two worlds is no longer a constant. CarService owns that
-- choice -- it is the service that owns where a car may be put -- so this asks it, and
-- falls back to this world's own spawn if it cannot (a place with no CarService loaded).
local function catchSpawn(position: Vector3): CFrame?
	local services = script.Parent
	local module = services and services:FindFirstChild("CarService")
	if module and module:IsA("ModuleScript") then
		local ok, cars = pcall(require, module)
		if ok and type(cars) == "table" and type(cars.SpawnCFrameNear) == "function" then
			local got, cf = pcall(cars.SpawnCFrameNear, cars, position)
			if got and typeof(cf) == "CFrame" then
				return cf
			end
		end
	end
	return PlaygroundService.Spots.Spawn
end

-- THIS WORLD CATCHES ITS OWN FALLERS AND NOBODY ELSE'S, and `FallY` is why (T-067).
-- It is an absolute world height, -40, which was right while every world's ground was at
-- Y = 0. The road descends now (features/road-elevation.md), so a car eleven pieces down
-- an ordinary descent is below -40 while sitting perfectly on the road, and this would
-- pivot it back to a spawn on every tick, for ever. The client's own fall test is the one
-- that matters there and it is measured from the ground the car last touched, not from
-- zero.
--
-- So ask CarService which world the position is in and leave anything that is not ours
-- alone. A place with no CarService answers nil, and then this behaves exactly as it did:
-- a lane with only a playground in it must not stop catching fallers because a lookup
-- failed.
local function notOurWorld(position: Vector3): boolean
	local services = script.Parent
	local module = services and services:FindFirstChild("CarService")
	if module and module:IsA("ModuleScript") then
		local ok, cars = pcall(require, module)
		if ok and type(cars) == "table" and type(cars.WorldAt) == "function" then
			local got, world = pcall(cars.WorldAt, cars, position)
			if got and type(world) == "string" then
				return world ~= "playground"
			end
		end
	end
	return false
end

local function catchFallers()
	local carFolder = workspace:FindFirstChild("Cars")
	if carFolder then
		for _, car in carFolder:GetChildren() do
			if car:IsA("Model") then
				local ok, pivot = pcall(function()
					return car:GetPivot()
				end)
				if ok and pivot.Position.Y < tuning.FallY and not notOurWorld(pivot.Position) then
					local back = catchSpawn(pivot.Position)
					if back then
						car:PivotTo(back)
					end
				end
			end
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Y < tuning.FallY and not notOurWorld(root.Position) then
			local back = catchSpawn(root.Position)
			if back then
				character:PivotTo(back * CFrame.new(0, 2, 0))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function PlaygroundService:Build()
	-- Studio's default plate goes, so every lane and the Main place look the same --
	-- UNLESS a track has adopted it. The plate is then the floor the two worlds SHARE: the
	-- track sits on it, this world's own plate meets its edge exactly, and the bare strip
	-- between them is what a car drives across to get from one world to the other.
	-- Destroying it would put the void back and make the crossing a teleport again.
	if not trackPresent then
		local default = workspace:FindFirstChild(Config.Drift.TrackFloorName)
		if default and default:IsA("BasePart") then
			default:Destroy()
		end
	end
	local existing = workspace:FindFirstChild("Playground")
	if existing then
		existing:Destroy()
	end

	-- A place that has the showroom saved in it (Tools/Showroom, T-059) carries a second
	-- copy of this world, at these same coordinates, built in edit mode so the user can
	-- fly around it. It is scenery, it is not tagged the way a live world is, and two
	-- playgrounds in one space is a place nobody can drive in -- so a playtest takes it
	-- down. Play runs on a COPY of the datamodel, so this never touches what is saved:
	-- stop the playtest and the showroom is still there to look at.
	--
	-- ONLY WHILE THE GAME IS RUNNING, and that guard is not a nicety -- without it this
	-- destroys the showroom AS THE SHOWROOM IS BEING BUILT (T-068). `Showroom.build()`
	-- parents its own `Workspace.Showroom` folder and only then calls `Init()` to get a
	-- playground to put inside it, so an unguarded destroy here eats the folder the tool
	-- is halfway through filling, and `build()` returns with nothing to show and no error.
	-- In edit mode there is no playtest to protect, so there is nothing to do.
	if RunService:IsRunning() then
		local showroom = workspace:FindFirstChild("Showroom")
		if showroom then
			showroom:Destroy()
		end
	end

	table.clear(features)
	table.clear(cones)
	partCount = 0
	hillPartCount = 0

	local root = Instance.new("Folder")
	root.Name = "Playground"

	buildPlate(root)
	partCount += 1
	buildBuildings(root)
	buildPillars(root)
	buildCircle(root)
	buildRamp(root)
	buildBodyPad(root)
	-- The test hill before the spots, because two of them are read off its pieces.
	buildHill(root)
	buildSpots()
	buildSpotMarkers(root)
	buildSpawnLocation(root)

	-- Built about the origin, moved to where this place keeps it, and only then put in
	-- the Workspace: one shift, before anything can read a position off it.
	shift(root, offset)
	PlaygroundService.Offset = offset

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
	-- A place with a hand-placed track gets BOTH worlds (T-026). The track is where its
	-- author put it and does not move; this one is built from a layout, so it is the one
	-- that moves out of the way. With no track the offset is zero and this world is built
	-- exactly where it always was.
	local track = trackService()
	trackPresent = track ~= nil and type(track.HasTrack) == "function" and track:HasTrack() == true
	offset = if trackPresent then Config.Drift.PlaygroundOffsetFromTrack else Vector3.zero
	PlaygroundService.SkippedForTrack = false

	-- The testing HUD's remote, made before anything can ask for it (T-065, T-067).
	-- ONLY WHILE THE GAME IS RUNNING. This service's `Init` is also called in EDIT mode,
	-- by the showroom tool (`Tools/Showroom`, T-059), and a remote made there would be a
	-- real instance in the saved place rather than a thing the server put up at startup.
	if RunService:IsRunning() then
		self.tools = Net.event("TestTools")
	end
	self.toolAsks = 0
	self.toolsRefused = 0
	self.lifts = 0
	self.railSwitches = 0
	self.toolLimits = {} -- userId -> { window, count, lastAt }

	self:Build()
end

function PlaygroundService:Start()
	if self.tools then
		self.tools.OnServerEvent:Connect(function(player, what)
			self:_onTool(player, what)
		end)
	end

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
-- The testing tools (features/test-hill.md, T-065 and T-067)
--------------------------------------------------------------------------------
-- Two buttons in `Drift/TestHud`, one remote, and a trust boundary drawn in exactly the
-- place `features/endless-run.md` "Server and client" draws it:
--
--   THE CLIENT SENDS ONE OF THREE THINGS and nothing on the wire is read as anything
--   else -- `"lift"`, `"rails"`, or nil for "what is the state?". It may NOT send a
--   position, a piece, a height or a boolean. Where the top of the hill is, is the
--   server's own number, read off the pieces it placed; a client that could name where
--   to put its car would be a client with a teleport.
--
-- The two guards are the same two numbers the start button borrows, for the same reason:
-- a press is a car being put somewhere, so a respawn's cooldown is the right shape for
-- it, and neither wants a number of its own until something asks for one.
local TOOL_RATE_LIMIT = "CarSwitchRateLimit" -- asks a second per UserId
local TOOL_COOLDOWN = "RespawnCooldown" -- seconds between two presses that land

local function roadService(): any?
	local services = script.Parent
	local module = services and services:FindFirstChild("RoadService")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, road = pcall(require, module)
	if ok and type(road) == "table" then
		return road
	end
	return nil
end

local function carService(): any?
	local services = script.Parent
	local module = services and services:FindFirstChild("CarService")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, cars = pcall(require, module)
	if ok and type(cars) == "table" then
		return cars
	end
	return nil
end

-- Where the lift puts a car: the top of the hill, facing down it, `RideHeight` above the
-- road's own surface and lying with the road's own grade. `HillTop` is a spot three studs
-- up, so this is that spot moved down ITS OWN up -- not the world's, which on a 7-degree
-- climb would be a stud out sideways.
function PlaygroundService:HillTopCFrame(): CFrame?
	local cf = PlaygroundService.Spots.HillTop
	if not cf then
		return nil
	end
	return cf * CFrame.new(0, Config.Drift.RideHeight - Layout.Spot.height, 0)
end

function PlaygroundService:HasHill(): boolean
	return #hill.pieces > 0 and PlaygroundService.Root ~= nil
end

function PlaygroundService:BarriersOn(): boolean
	return railsOn
end

-- The one switch, for the hill AND for the endless road: the user asked for one button
-- and "the barriers" means all of them. The road may not be up, which is not an error.
function PlaygroundService:SetBarriers(on: boolean): boolean
	railsOn = on == true
	applyHillRails()
	local road = roadService()
	if road and type(road.SetBarriers) == "function" then
		pcall(road.SetBarriers, road, railsOn)
	end
	return railsOn
end

function PlaygroundService:ToolState()
	return { hill = self:HasHill(), rails = railsOn }
end

function PlaygroundService:_tellTools(player: Player)
	if self.tools then
		self.tools:FireClient(player, self:ToolState())
	end
end

function PlaygroundService:_onTool(player: Player, what: any)
	self.toolAsks += 1
	local now = os.clock()
	local limit = self.toolLimits[player.UserId]
	if not limit then
		limit = { window = now, count = 0, lastAt = -math.huge }
		self.toolLimits[player.UserId] = limit
	end
	if now - limit.window >= 1 then
		limit.window = now
		limit.count = 0
	end
	limit.count += 1
	if limit.count > Config.Drift[TOOL_RATE_LIMIT] then
		self.toolsRefused += 1
		self:_tellTools(player)
		return
	end

	if what == nil then
		self:_tellTools(player) -- a question, answered, changing nothing
		return
	end
	-- ANYTHING THAT IS NOT ONE OF THE TWO WORDS IS REFUSED, counted, and answered with
	-- the state the server really has. A CFrame, a Vector3, a table naming a place, a
	-- number: all of them land here.
	if what ~= "lift" and what ~= "rails" then
		self.toolsRefused += 1
		self:_tellTools(player)
		return
	end
	if now - limit.lastAt < Config.Drift[TOOL_COOLDOWN] then
		self.toolsRefused += 1
		self:_tellTools(player)
		return
	end

	local acted = false
	if what == "rails" then
		self:SetBarriers(not railsOn)
		self.railSwitches += 1
		acted = true
	else
		-- THE SERVER MOVES THE CAR, and it moves it to a CFrame it worked out itself.
		local to = self:HillTopCFrame()
		local cars = carService()
		local road = roadService()
		-- Not while they are on the endless road: the roster would still have them on it
		-- and the window would follow a car that had left.
		local inRun = road ~= nil and type(road.InRun) == "function" and road:InRun(player) == true
		if to and cars and type(cars.Place) == "function" and not inRun then
			acted = cars:Place(player, to) ~= nil
			if acted then
				self.lifts += 1
			end
		end
	end
	if acted then
		limit.lastAt = now
	else
		self.toolsRefused += 1
	end
	self:_tellTools(player)
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
		hillPartCount = hillPartCount,
		hill = PlaygroundService:DebugHill(),
		rails = railsOn,
		toolAsks = self.toolAsks or 0,
		toolsRefused = self.toolsRefused or 0,
		lifts = self.lifts or 0,
		railSwitches = self.railSwitches or 0,
		coneCount = #cones,
		buildingCount = #Layout.Buildings + #Layout.Blocks,
		pillarCount = #Layout.Pillars,
		spots = spots,
		segments = segments,
		plate = { size = Layout.Plate.size, topY = 0 },
		open = Layout.Open,
		-- Where this world is, and why: zero unless the place also has a track (T-026).
		offset = offset,
		withTrack = trackPresent,
		centre = Vector3.zero + offset,
	}
end

-- This world's footprint, plate and all, so a caller can ask which world a position is
-- in without knowing anything about the layout. The plate is the widest thing here, so
-- it is the whole of it -- EXCEPT for the test hill, which stands on a plate of its own
-- off the southern edge and reaches 259 studs into the air (T-065). Both are in here, so
-- a car on the hill is a car in this world.
function PlaygroundService:Bounds(): { min: Vector3, max: Vector3 }
	local half = Layout.Plate.size * 0.5
	local minX, maxX = -half, half
	local minZ, maxZ = -half, half
	local maxY = 200
	if hill.pad then
		minX = math.min(minX, hill.pad.minX)
		maxX = math.max(maxX, hill.pad.maxX)
		minZ = math.min(minZ, hill.pad.minZ)
		maxZ = math.max(maxZ, hill.pad.maxZ)
		maxY = math.max(maxY, hill.topY + 100)
	end
	return {
		min = offset + Vector3.new(minX, -Layout.Plate.thickness, minZ),
		max = offset + Vector3.new(maxX, maxY, maxZ),
	}
end

-- The hill: its profile piece by piece, where it starts and ends, how high it gets, and
-- the ground it stands on. Heights are world Y and need no offset; X and Z are layout
-- coordinates and `offset` is what makes them world ones.
function PlaygroundService:DebugHill()
	local pieces = {}
	for i, piece in hill.pieces do
		local dy = piece.finish.y - piece.start.y
		local maxPitch, maxBank = 0, 0
		for _, node in piece.nodes do
			maxPitch = math.max(maxPitch, math.abs(node.pitch))
			maxBank = math.max(maxBank, math.abs(node.bank))
		end
		pieces[i] = {
			n = i,
			id = piece.id,
			kind = piece.kind,
			length = math.round(piece.length * 10) / 10,
			startY = math.round((Config.Road.SurfaceY + piece.start.y) * 1000) / 1000,
			endY = math.round((Config.Road.SurfaceY + piece.finish.y) * 1000) / 1000,
			dy = math.round(dy * 1000) / 1000,
			meanGrade = math.round(math.deg(math.atan(dy / piece.length)) * 100) / 100,
			maxGrade = math.round(math.deg(maxPitch) * 100) / 100,
			maxBank = math.round(math.deg(maxBank) * 100) / 100,
			segments = #piece.nodes - 1,
			parts = if hill.built[i] then hill.built[i].parts else 0,
		}
	end
	local length = 0
	for _, piece in hill.pieces do
		length += piece.length
	end
	return {
		pieces = pieces,
		count = #hill.pieces,
		climbPieces = Layout.Hill.climbPieces,
		entryY = math.round(hill.entryY * 1000) / 1000,
		exitY = math.round(hill.exitY * 1000) / 1000,
		topY = math.round(hill.topY * 1000) / 1000,
		plateY = Layout.Surface.height,
		lengthStuds = math.round(length),
		parts = hillPartCount,
		approachRise = math.round(hill.approachRise * 1000) / 1000,
		approachLength = math.round(hill.approachLength * 10) / 10,
		bounds = hill.bounds,
		pad = hill.pad,
		offset = offset,
		rails = railsOn,
	}
end

-- Studio only: the hill's centre line as a list of world points, so a test autopilot has
-- something to aim at. `Road/Generator` gives the endless road's drives an `ahead`; the
-- hill has no generator, so this is the line and the caller walks it.
--
-- Each point carries the piece it is on, which is what turns "the car was doing 92" into
-- "the car was doing 92 on piece 7, which climbs".
function PlaygroundService:DebugHillLine(spacing: number?)
	assert(RunService:IsStudio(), "DebugHillLine is Studio only")
	local step = math.max(spacing or 8, 1)
	local out = {}
	for _, piece in hill.pieces do
		local n = math.max(2, math.ceil(piece.length / step))
		local from = if #out == 0 then 0 else 1
		for i = from, n do
			local cf = RoadPieces.poseAt(piece, i / n, Config.Road.SurfaceY)
			table.insert(out, { pos = cf.Position + offset, n = piece.n, id = piece.id })
		end
	end
	return out
end

-- Studio only: whether the switch touched the walls and nothing else. The slab columns
-- are the ones that matter -- a slab that stopped being queryable would be a car falling
-- through the road.
function PlaygroundService:DebugBarrierReport()
	assert(RunService:IsStudio(), "DebugBarrierReport is Studio only")
	local walls, wallsQueryable, wallsSolid = 0, 0, 0
	local slabs, slabsQueryable, slabsSolid, slabsTagged = 0, 0, 0, 0
	for _, entry in hill.built do
		for _, wall in entry.barriers do
			walls += 1
			wallsQueryable += if wall.CanQuery then 1 else 0
			wallsSolid += if wall.CanCollide then 1 else 0
		end
		for _, slab in entry.road do
			slabs += 1
			slabsQueryable += if slab.CanQuery then 1 else 0
			slabsSolid += if slab.CanCollide then 1 else 0
			slabsTagged += if CollectionService:HasTag(slab, Config.Drift.SurfaceTag) then 1 else 0
		end
	end
	return {
		on = railsOn,
		walls = walls,
		wallsQueryable = wallsQueryable,
		wallsSolid = wallsSolid,
		slabs = slabs,
		slabsQueryable = slabsQueryable,
		slabsSolid = slabsSolid,
		slabsTagged = slabsTagged,
	}
end

-- Studio only: press a testing button for a player with no client involved, through the
-- exact path the remote takes -- rate limit, cooldown, type check and all -- so a test
-- exercises what a tap really does rather than the method behind it. `what` nil is the
-- question, and anything that is not "lift" or "rails" is a forgery.
function PlaygroundService:DebugTool(what: any, userId: number?)
	assert(RunService:IsStudio(), "DebugTool is Studio only")
	for _, player in Players:GetPlayers() do
		if userId == nil or player.UserId == userId then
			self:_onTool(player, what)
			return self:ToolState()
		end
	end
	return nil
end

-- Studio only: the two guards exist to stop a client hammering the buttons, and a test
-- that waits half a second between presses is only measuring the wait.
function PlaygroundService:DebugClearToolLimits()
	assert(RunService:IsStudio(), "DebugClearToolLimits is Studio only")
	self.toolLimits = {}
end

-- The hill's own footprint and the pad under it, in world space, for the tests.
function PlaygroundService:DebugHillBounds()
	local folder = PlaygroundService.Root and PlaygroundService.Root:FindFirstChild(Layout.Hill.id)
	if not folder then
		return nil
	end
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	-- THE ROAD'S OWN BOX, SEPARATELY FROM THE APPROACH'S, because the two stand on
	-- different ground on purpose: every piece of road is over the hill's pad, and the
	-- approach ramp is the thing that crosses on to the playground's own plate.
	local roadMin = Vector3.new(math.huge, math.huge, math.huge)
	local roadMax = Vector3.new(-math.huge, -math.huge, -math.huge)
	local pad = folder:FindFirstChild("HillPad")
	for _, part in folder:GetDescendants() do
		if part:IsA("BasePart") and part ~= pad then
			local lo, hi = part.Position - part.Size * 0.5, part.Position + part.Size * 0.5
			minV, maxV = minV:Min(lo), maxV:Max(hi)
			if part.Parent and part.Parent.Name:match("^Piece_") then
				roadMin, roadMax = roadMin:Min(lo), roadMax:Max(hi)
			end
		end
	end
	return {
		min = minV,
		max = maxV,
		road = { min = roadMin, max = roadMax },
		pad = if pad then { min = pad.Position - pad.Size * 0.5, max = pad.Position + pad.Size * 0.5 } else nil,
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
-- THE TEST HILL IS NOT IN IT, and that is the point of the exclusion rather than a
-- loophole: the hill stands off the southern edge on a plate of its own and is measured
-- by `DebugHillBounds` against THAT (T-065). Everything this one answers for still has to
-- be on the 2 000-stud square.
function PlaygroundService:DebugBounds()
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local hillFolder = PlaygroundService.Root:FindFirstChild(Layout.Hill.id)
	for _, part in PlaygroundService.Root:GetDescendants() do
		if hillFolder and part:IsDescendantOf(hillFolder) then
			continue
		end
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
