--!nonstrict
-- GarageRoom/Build: turns GarageRoom/Layout into anchored parts -- the grey-box garage
-- interior to the picked concept, assets/garage-concept/garage-01.png (T-102).
--
-- Four kinds of part, and the difference matters to the drift model:
--   surface  the floor, the street, the turntable's deck and its bevel. Tagged
--            `DriftSurface`, because the car's ground rays include-filter to the tag.
--   solid    walls, props, the guardrail: collidable and untagged, so to the car a wall.
--   paint    bay lines, stripes, the deck's spokes: no collision, no query, no touch, so
--            the ground rays and the wall sweep are both blind to them (as the road's
--            centre-line dashes are, CONTRACTS.md `Mark_<n>_<k>`).
--   glow     the strip lights' lenses and the town's lit windows: Neon paint.
--
-- Nothing here has a constraint or an unanchored part. Everything is placed through the
-- room's frame (`at`), so the room can stand anywhere and face any way.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(script.Parent.Layout)

local Build = {}

local SURFACE_TAG = Config.Drift.SurfaceTag

type Kind = "surface" | "solid" | "paint" | "glow"

local function make(class: string, name: string, size: Vector3, cf: CFrame, colour: Color3, kind: Kind, parent: Instance): BasePart
	local part = Instance.new(class) :: BasePart
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.CastShadow = false
	part.Material = if kind == "glow" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Color = colour
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "paint" or kind == "glow" then
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	else
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
	end
	if kind == "surface" then
		CollectionService:AddTag(part, SURFACE_TAG)
	end
	part.Parent = parent
	return part
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Build the room under `parent`, with its frame at `at` (the turntable's centre on the
-- floor). Returns the room model and what the service keeps hold of.
function Build.room(at: CFrame, parent: Instance)
	local palette = Config.GarageRoom.Palette
	local room = Layout.Room
	local hx, hz, h, w = room.halfX, room.halfZ, room.height, room.wall

	local model = Instance.new("Model")
	model.Name = "GarageRoom"
	model:SetAttribute("GarageRoom", true)
	model.WorldPivot = at

	local function P(name, size, localCf, colour, kind, into, class)
		return make(class or "Part", name, size, at * localCf, colour, kind, into)
	end
	local function C(x, y, z)
		return CFrame.new(x, y, z)
	end
	-- A cylinder standing upright (its axis along Y): `height` tall, `diameter` across.
	local function upright(name, height, diameter, localPos: Vector3, colour, kind, into)
		local part = P(name, Vector3.new(height, diameter, diameter), CFrame.new(localPos) * CFrame.Angles(0, 0, math.rad(90)), colour, kind, into)
		part.Shape = Enum.PartType.Cylinder
		return part
	end
	-- A cylinder facing along Z (a wheel standing up, seen from the front of the room).
	local function facingZ(name, width, diameter, localPos: Vector3, colour, kind, into)
		local part = P(name, Vector3.new(width, diameter, diameter), CFrame.new(localPos) * CFrame.Angles(0, math.rad(90), 0), colour, kind, into)
		part.Shape = Enum.PartType.Cylinder
		return part
	end
	-- A thin bar from a to b.
	local function bar(name, a: Vector3, b: Vector3, thickness, colour, kind, into)
		local length = (b - a).Magnitude
		return P(name, Vector3.new(thickness, thickness, length), CFrame.lookAt((a + b) * 0.5, b), colour, kind, into)
	end

	------------------------------------------------------------------ floor and street
	local floorFolder = folder("Floor", model)
	P("Floor", Vector3.new(hx * 2 + w * 2, 2, hz * 2 + w * 2), C(0, -1, 0), palette.Floor, "surface", floorFolder)
	local street = Layout.Street
	P(
		"Street",
		Vector3.new(street.nearX - street.farX, 2, street.halfZ * 2),
		C((street.nearX + street.farX) * 0.5, -1, 0),
		palette.Street,
		"surface",
		floorFolder
	)

	-- The painted bay round the turntable.
	local bay = Layout.Bay
	local paintY = 0.02
	for _, sz in { -1, 1 } do
		P("BayLine", Vector3.new(bay.halfX * 2 + bay.line, 0.04, bay.line), C(0, paintY, sz * bay.halfZ), palette.Orange, "paint", floorFolder)
		P("BayLine", Vector3.new(bay.line, 0.04, bay.halfZ * 2), C(sz * bay.halfX, paintY, 0), palette.Orange, "paint", floorFolder)
	end
	-- Two lines leading in from the door.
	for _, sz in { -1, 1 } do
		P("LeadLine", Vector3.new(hx - bay.halfX, 0.04, bay.line * 0.6), C(-(hx + bay.halfX) * 0.5, paintY, sz * 6), palette.Orange, "paint", floorFolder)
	end

	---------------------------------------------------------------------- turntable
	local tt = Layout.Turntable
	local ttFolder = folder("TurntableBase", model)
	local band = { palette.Teal, palette.Deck, palette.Orange, palette.Deck }
	local bevelLength = tt.bevelOuter - tt.bevelInner
	local bevelMid = (tt.bevelOuter + tt.bevelInner) * 0.5
	local segWidth = 2 * tt.bevelOuter * math.tan(math.pi / tt.segments) + 0.05
	for i = 0, tt.segments - 1 do
		local a = (i + 0.5) / tt.segments * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local centre = out * bevelMid + Vector3.new(0, tt.deckTop * 0.5, 0)
		-- A WedgePart's tall end is its +Z face and its thin edge its -Z face, which is
		-- where `lookAt` points: so the thin edge points out and the bevel falls away
		-- from the deck to the floor.
		P(
			`Bevel_{i + 1}`,
			Vector3.new(segWidth, tt.deckTop, bevelLength),
			CFrame.lookAt(centre, centre + out),
			band[(i % #band) + 1],
			"surface",
			ttFolder,
			"WedgePart"
		)
	end

	local turntable = Instance.new("Model")
	turntable.Name = "Turntable"
	local deck = upright("Deck", tt.deckDepth, tt.radius * 2, Vector3.new(0, tt.deckTop - tt.deckDepth * 0.5, 0), palette.Deck, "surface", turntable)
	turntable.PrimaryPart = deck
	-- Four diameters drawn on the deck read as eight spokes, so a spin shows.
	for k = 0, 3 do
		P(
			"Spoke",
			Vector3.new(0.25, 0.04, tt.radius * 2 - 0.6),
			C(0, tt.deckTop + 0.02, 0) * CFrame.Angles(0, k * math.pi / 4, 0),
			palette.DeckLine,
			"paint",
			turntable
		)
	end
	upright("Hub", 0.05, 2.4, Vector3.new(0, tt.deckTop + 0.025, 0), palette.Orange, "paint", turntable)
	turntable.WorldPivot = at * CFrame.new(0, tt.deckTop, 0)
	turntable.Parent = model

	------------------------------------------------------------------------- shell
	local shell = folder("Shell", model)
	local wallY = h * 0.5
	P("WallBack", Vector3.new(hx * 2 + w * 2, h, w), C(0, wallY, -hz - w * 0.5), palette.Wall, "solid", shell)
	P("WallFront", Vector3.new(hx * 2 + w * 2, h, w), C(0, wallY, hz + w * 0.5), palette.Wall, "solid", shell)
	P("WallRight", Vector3.new(w, h, hz * 2), C(hx + w * 0.5, wallY, 0), palette.Wall, "solid", shell)
	local door = Layout.Door
	local dz = door.width * 0.5
	local sideLen = hz - dz
	for _, s in { -1, 1 } do
		P("WallLeft", Vector3.new(w, h, sideLen), C(-hx - w * 0.5, wallY, s * (dz + sideLen * 0.5)), palette.Wall, "solid", shell)
	end
	P("DoorLintel", Vector3.new(w, h - door.height, door.width), C(-hx - w * 0.5, (h + door.height) * 0.5, 0), palette.Wall, "solid", shell)
	P("Roof", Vector3.new(hx * 2 + w * 2, 1, hz * 2 + w * 2), C(0, h + 0.5, 0), palette.Roof, "solid", shell)

	-- The orange band round the walls, inside.
	local sy = room.stripeY
	local inset = 0.12
	P("Stripe", Vector3.new(hx * 2, 1, 0.2), C(0, sy, -hz + inset), palette.Orange, "paint", shell)
	P("Stripe", Vector3.new(hx * 2, 1, 0.2), C(0, sy, hz - inset), palette.Orange, "paint", shell)
	P("Stripe", Vector3.new(0.2, 1, hz * 2), C(hx - inset, sy, 0), palette.Orange, "paint", shell)
	for _, s in { -1, 1 } do
		P("Stripe", Vector3.new(0.2, 1, sideLen), C(-hx + inset, sy, s * (dz + sideLen * 0.5)), palette.Orange, "paint", shell)
	end

	-- Teal steel: columns at the corners, the door jambs and mid-walls, and the roof frame.
	local columns = {
		{ -hx + 0.8, -hz + 0.8 },
		{ hx - 0.8, -hz + 0.8 },
		{ -hx + 0.8, hz - 0.8 },
		{ hx - 0.8, hz - 0.8 },
		{ -hx + 0.8, -dz - 0.8 },
		{ -hx + 0.8, dz + 0.8 },
		{ -2, -hz + 0.8 },
		{ 20.5, -hz + 0.8 },
		{ hx - 0.8, -6 },
		{ -6, hz - 0.8 },
		{ 10, hz - 0.8 },
	}
	for _, c in columns do
		P("Column", Vector3.new(1.6, h, 1.6), C(c[1], wallY, c[2]), palette.Teal, "solid", shell)
	end
	local beamY = h - 0.8
	for _, x in { -13, 0, 13 } do
		P("Beam", Vector3.new(1.2, 1.2, hz * 2), C(x, beamY, 0), palette.Teal, "solid", shell)
	end
	for _, z in { -hz + 0.8, -7, 7, hz - 0.8 } do
		P("Girder", Vector3.new(hx * 2, 1, 1), C(0, beamY - 1.1, z), palette.Teal, "solid", shell)
	end
	-- Truss braces between the girders and the roof, a V per bay: the concept's lattice.
	for _, z in { -7, 7 } do
		for x = -hx + 4, hx - 4, 8 do
			bar("Brace", Vector3.new(x - 4, beamY - 1.1, z), Vector3.new(x, h - 0.2, z), 0.4, palette.TealDark, "solid", shell)
			bar("Brace", Vector3.new(x + 4, beamY - 1.1, z), Vector3.new(x, h - 0.2, z), 0.4, palette.TealDark, "solid", shell)
		end
	end

	-- The roller door, rolled up: a housing over the opening and the last slats showing.
	local doorFolder = folder("RollerDoor", model)
	P("Housing", Vector3.new(2.4, 2.4, door.width + 2), C(-hx + 1.4, door.height + 1.4, 0), palette.SteelDark, "solid", doorFolder)
	local slatH = (door.height - door.slatBottom) / door.slats
	for i = 0, door.slats - 1 do
		P(
			"Slat",
			Vector3.new(0.4, slatH - 0.08, door.width),
			C(-hx - 0.3, door.slatBottom + slatH * (i + 0.5), 0),
			if i % 2 == 0 then palette.Steel else palette.SteelDark,
			"solid",
			doorFolder
		)
	end
	for _, s in { -1, 1 } do
		P("Rail", Vector3.new(0.6, door.height, 0.5), C(-hx - 0.2, door.height * 0.5, s * (dz + 0.1)), palette.SteelDark, "solid", doorFolder)
	end
	-- A teal fascia over the door outside.
	P("Fascia", Vector3.new(0.4, 2.4, door.width + 6), C(-hx - w - 0.2, door.height + 2.4, 0), palette.Teal, "solid", doorFolder)

	-- The back wall's high window, dusk behind it.
	local wallZ = -hz + 0.15
	P("WindowFrame", Vector3.new(15, 3.6, 0.3), C(8, 13.2, wallZ), palette.SteelDark, "paint", shell)
	for i = 0, 2 do
		P("WindowPane", Vector3.new(4.4, 2.8, 0.2), C(3.2 + i * 4.8, 13.2, wallZ + 0.1), palette.GlassDusk, "paint", shell)
	end

	------------------------------------------------------------------------- props
	local props = folder("Props", model)

	-- Pegboard and its tools.
	local pegZ = -hz + 0.25
	P("Pegboard", Vector3.new(14, 6, 0.3), C(10, 8.4, pegZ), palette.Orange, "solid", props)
	local toolZ = pegZ + 0.25
	for i = 0, 4 do
		P("Wrench", Vector3.new(0.3, 1.6 + i * 0.25, 0.15), C(4.2 + i * 0.8, 9.2 - i * 0.12, toolZ), palette.Steel, "paint", props)
	end
	for i = 0, 3 do
		P("Driver", Vector3.new(0.35, 1, 0.2), C(8.6 + i * 0.7, 9.6, toolZ), palette.Teal, "paint", props)
		P("Shaft", Vector3.new(0.12, 0.9, 0.12), C(8.6 + i * 0.7, 8.7, toolZ), palette.Steel, "paint", props)
	end
	P("HammerHandle", Vector3.new(0.25, 1.8, 0.15), C(12.4, 8.8, toolZ), palette.Wood, "paint", props)
	P("HammerHead", Vector3.new(1.1, 0.4, 0.25), C(12.4, 9.8, toolZ), palette.SteelDark, "paint", props)
	P("Pliers", Vector3.new(0.5, 1.4, 0.15), C(13.8, 8.4, toolZ) * CFrame.Angles(0, 0, math.rad(12)), palette.SteelDark, "paint", props)
	for i = 0, 2 do
		P("HexKey", Vector3.new(0.12, 1 + i * 0.3, 0.12), C(15.2 + i * 0.5, 9.2, toolZ), palette.Steel, "paint", props)
	end

	-- Workbench under it, a teal drawer unit at its end.
	local benchZ = -hz + 1.8
	P("BenchTop", Vector3.new(16, 0.4, 3.4), C(10, 3.4, benchZ), palette.Wood, "solid", props)
	for _, x in { 2.4, 7 } do
		for _, dzLeg in { -1.3, 1.3 } do
			P("BenchLeg", Vector3.new(0.4, 3.2, 0.4), C(x, 1.6, benchZ + dzLeg), palette.SteelDark, "solid", props)
		end
	end
	P("Drawers", Vector3.new(6, 3.2, 3.2), C(14.6, 1.6, benchZ), palette.Teal, "solid", props)
	for i = 0, 2 do
		P("DrawerLine", Vector3.new(5.4, 0.12, 0.1), C(14.6, 0.8 + i * 1, benchZ + 1.65), palette.TealDark, "paint", props)
	end
	P("Vise", Vector3.new(1.4, 1, 1.2), C(16, 4.1, benchZ), palette.SteelDark, "solid", props)
	P("BenchBox", Vector3.new(1.6, 1.2, 1.4), C(4, 4.2, benchZ), palette.Steel, "solid", props)
	P("BenchBox", Vector3.new(1.4, 1.6, 1.2), C(6.2, 4.4, benchZ), palette.Teal, "solid", props)
	P("BenchBox", Vector3.new(1.6, 1, 1.4), C(10.5, 4.1, benchZ), palette.SteelDark, "solid", props)

	-- The tyre rack: a teal frame of two shelves, three wheels on each.
	local rackX0, rackX1 = -17, -5
	local rackZ0, rackZ1 = -hz + 0.6, -hz + 3.4
	for _, x in { rackX0, rackX1 } do
		for _, z in { rackZ0, rackZ1 } do
			P("RackPost", Vector3.new(0.5, 10.4, 0.5), C(x, 5.2, z), palette.Teal, "solid", props)
		end
	end
	for _, y in { 1.2, 5.8, 10.2 } do
		for _, z in { rackZ0, rackZ1 } do
			P("RackBar", Vector3.new(rackX1 - rackX0, 0.4, 0.4), C((rackX0 + rackX1) * 0.5, y, z), palette.Teal, "solid", props)
		end
	end
	local wheelZ = (rackZ0 + rackZ1) * 0.5
	for row, y in { 3.2, 7.8 } do
		for col, x in { -14.6, -11, -7.4 } do
			local at3 = Vector3.new(x, y, wheelZ)
			facingZ(`RackTyre_{row}_{col}`, 1.6, 3.6, at3, palette.Tyre, "solid", props)
			facingZ("RackRim", 1.7, 2.4, at3, palette.Rim, "paint", props)
			facingZ("RackHub", 1.8, 0.8, at3, palette.SteelDark, "paint", props)
		end
	end

	-- Stacked tyres: beside the rack, and in the front-right corner with one leaning.
	for i = 0, 3 do
		upright("StackTyre", 1.4, 3.8, Vector3.new(-21.5, 0.7 + i * 1.4, -hz + 3.2), palette.Tyre, "solid", props)
	end
	for i = 0, 2 do
		upright("StackTyre", 1.4, 3.8, Vector3.new(21, 0.7 + i * 1.4, hz - 3), palette.Tyre, "solid", props)
	end
	for i = 0, 1 do
		upright("StackTyre", 1.4, 3.8, Vector3.new(16.8, 0.7 + i * 1.4, hz - 2.6), palette.Tyre, "solid", props)
	end
	local lean = P("LeanTyre", Vector3.new(1.4, 3.8, 3.8), C(18.6, 2.1, hz - 6.2) * CFrame.Angles(0, math.rad(-30), math.rad(-20)), palette.Tyre, "solid", props)
	lean.Shape = Enum.PartType.Cylinder

	-- The engine hoist, back right, its boom reaching towards the turntable.
	local hoistZ = -11
	P("HoistFoot", Vector3.new(7.5, 0.5, 0.6), C(18, 0.6, hoistZ - 1.8), palette.Orange, "solid", props)
	P("HoistFoot", Vector3.new(7.5, 0.5, 0.6), C(18, 0.6, hoistZ + 1.8), palette.Orange, "solid", props)
	P("HoistCross", Vector3.new(0.6, 0.5, 4.2), C(21.5, 0.6, hoistZ), palette.Orange, "solid", props)
	for _, x in { 14.6, 21.4 } do
		for _, s in { -1, 1 } do
			upright("Caster", 0.35, 0.7, Vector3.new(x, 0.18, hoistZ + s * 1.8), palette.SteelDark, "solid", props)
		end
	end
	P("HoistPost", Vector3.new(0.8, 9.6, 0.8), C(21, 5.4, hoistZ), palette.Orange, "solid", props)
	bar("HoistBoom", Vector3.new(21.4, 9.6, hoistZ), Vector3.new(14.6, 11.6, hoistZ), 0.7, palette.Orange, "solid", props)
	bar("HoistRam", Vector3.new(21, 3, hoistZ), Vector3.new(18, 10.4, hoistZ), 0.35, palette.SteelDark, "solid", props)
	P("HoistChain", Vector3.new(0.2, 2.6, 0.2), C(14.8, 10.1, hoistZ), palette.Steel, "paint", props)
	P("HoistHook", Vector3.new(0.6, 0.6, 0.25), C(14.8, 8.6, hoistZ), palette.SteelDark, "paint", props)

	-- The parts shelves along the right wall, with boxes on them.
	local shelfX0, shelfX1 = hx - 3.4, hx - 0.3
	local shelfZ0, shelfZ1 = -3, 13
	for _, x in { shelfX0, shelfX1 } do
		for _, z in { shelfZ0, (shelfZ0 + shelfZ1) * 0.5, shelfZ1 } do
			P("ShelfPost", Vector3.new(0.4, 13, 0.4), C(x, 6.5, z), palette.Teal, "solid", props)
		end
	end
	local shelfLevels = { 0.5, 4, 7.5, 11 }
	for _, y in shelfLevels do
		P("Shelf", Vector3.new(shelfX1 - shelfX0, 0.25, shelfZ1 - shelfZ0), C((shelfX0 + shelfX1) * 0.5, y, (shelfZ0 + shelfZ1) * 0.5), palette.TealDark, "solid", props)
	end
	local rng = Random.new(Layout.Backdrop.seed)
	for level = 1, #shelfLevels do
		local z = shelfZ0 + 0.6
		while z < shelfZ1 - 2 do
			local len = rng:NextNumber(1.8, 3.4)
			local tall = rng:NextNumber(1.4, 2.8)
			local colour = if rng:NextNumber() < 0.75 then palette.Box else palette.SteelDark
			P(
				"Box",
				Vector3.new(2.4, tall, len),
				C((shelfX0 + shelfX1) * 0.5, shelfLevels[level] + 0.13 + tall * 0.5, z + len * 0.5),
				colour,
				"solid",
				props
			)
			z += len + rng:NextNumber(0.3, 1.4)
		end
	end

	-- The tool chest, front left, red as in the concept.
	local chestX, chestZ = -hx + 2.2, 15
	P("ToolChest", Vector3.new(3.2, 5.2, 6), C(chestX, 3.2, chestZ), palette.Red, "solid", props)
	P("ChestLid", Vector3.new(3.4, 0.3, 6.2), C(chestX, 5.95, chestZ), palette.SteelDark, "solid", props)
	for i = 0, 3 do
		P("ChestDrawer", Vector3.new(0.1, 0.12, 5.4), C(chestX + 1.65, 1.6 + i * 1.15, chestZ), palette.SteelDark, "paint", props)
		P("ChestHandle", Vector3.new(0.2, 0.2, 1.6), C(chestX + 1.7, 2.1 + i * 1.15, chestZ), palette.Steel, "paint", props)
	end
	for _, s in { -1, 1 } do
		for _, t in { -1, 1 } do
			upright("Caster", 0.6, 0.6, Vector3.new(chestX + s * 1.2, 0.3, chestZ + t * 2.6), palette.SteelDark, "solid", props)
		end
	end

	-------------------------------------------------------------------- strip lights
	local lights = folder("Lights", model)
	local lightY = h - 2.6
	for _, x in { -14, 0, 14 } do
		for _, z in { -10, 10 } do
			P("LightHousing", Vector3.new(10, 0.6, 1.6), C(x, lightY + 0.3, z), palette.SteelDark, "solid", lights)
			local lens = P("Light", Vector3.new(9.6, 0.15, 1.2), C(x, lightY - 0.05, z), palette.Light, "glow", lights)
			local glow = Instance.new("SurfaceLight")
			glow.Face = Enum.NormalId.Bottom
			glow.Angle = 120
			glow.Brightness = Config.GarageRoom.LightBrightness
			glow.Range = Config.GarageRoom.LightRange
			glow.Color = palette.Light
			glow.Shadows = false
			glow.Parent = lens
			for _, s in { -1, 1 } do
				P("LightRod", Vector3.new(0.12, h - lightY - 0.6, 0.12), C(x + s * 4, (h + lightY + 0.6) * 0.5, z), palette.SteelDark, "paint", lights)
			end
		end
	end

	--------------------------------------------------------------- outside: the street
	local outside = folder("Outside", model)
	-- The guardrail across the street from the door.
	for z = -street.railHalfZ, street.railHalfZ, street.railPost do
		P("RailPost", Vector3.new(0.5, 2.6, 0.5), C(street.railX, 1.3, z), palette.Rail, "solid", outside)
	end
	for _, y in { 1.4, 2.4 } do
		P("RailBar", Vector3.new(0.3, 0.3, street.railHalfZ * 2), C(street.railX, y, 0), palette.Rail, "solid", outside)
	end
	-- The street's two ends are closed, so a car can never drive off it.
	for _, s in { -1, 1 } do
		P("StreetEnd", Vector3.new(street.nearX - street.farX, 10, 2), C((street.nearX + street.farX) * 0.5, 5, s * (street.halfZ + 1)), palette.Silhouette, "solid", outside)
	end
	-- The far side is wall too, beyond the rail.
	-- and below it the ridge's retaining wall, down to the town.
	local backdrop = Layout.Backdrop
	local base = backdrop.townBase
	-- Its top is a kerb, no higher, so it does not hide the town from inside the door.
	P("StreetFar", Vector3.new(1, 0.6 - base, street.halfZ * 2), C(street.farX - 0.5, (0.6 + base) * 0.5, 0), palette.Silhouette, "solid", outside)

	-- The town's ground, below the ridge, out to the sky.
	P(
		"Lot",
		Vector3.new(street.farX - backdrop.lotFarX, 2, backdrop.skyHalfZ * 2),
		C((street.farX + backdrop.lotFarX) * 0.5, base - 1, 0),
		palette.Silhouette,
		"solid",
		outside
	)

	-- Power poles and their wires.
	local poleX = street.farX - 4
	for _, z in { -70, -10, 50 } do
		upright("Pole", 28 - base, 0.8, Vector3.new(poleX, (28 + base) * 0.5, z), palette.Silhouette, "solid", outside)
		P("PoleArm", Vector3.new(5, 0.4, 0.4), C(poleX, 25, z), palette.Silhouette, "solid", outside)
	end
	for _, dx in { -2, 2 } do
		P("Wire", Vector3.new(0.12, 0.12, 300), C(poleX + dx, 24.6, 0), palette.Silhouette, "paint", outside)
	end

	-- The silhouette town: blocks with a few lit windows, seeded so it is the same every build.
	local town = Random.new(backdrop.seed)
	local z = -backdrop.skyHalfZ + 20
	while z < backdrop.skyHalfZ - 20 do
		local width = town:NextNumber(18, 34)
		local depth = town:NextNumber(16, 26)
		local tall = town:NextNumber(backdrop.townLow, backdrop.townHigh)
		local x = town:NextNumber(-124, -96)
		P("Building", Vector3.new(depth, tall, width), C(x, base + tall * 0.5 - 0.5, z + width * 0.5), palette.Silhouette, "solid", outside)
		local face = x + depth * 0.5 + 0.06
		for _ = 1, town:NextInteger(1, 3) do
			local wy = base + town:NextNumber(3, math.max(4, tall - 3))
			local wz = z + town:NextNumber(3, width - 3)
			P("TownWindow", Vector3.new(0.1, 2.2, 2.6), C(face, wy, wz), palette.Window, "glow", outside)
		end
		-- A taller, paler block behind every other one, for depth.
		if town:NextNumber() < 0.5 then
			local backTall = tall + town:NextNumber(3, 10)
			P("BuildingFar", Vector3.new(20, backTall, width * 0.8), C(x - 30, base + backTall * 0.5 - 0.5, z + width * 0.5), palette.SilhouetteFar, "solid", outside)
		end
		z += width + town:NextNumber(2, 10)
	end

	-- Hills on the horizon: squares stood on their corners, half buried.
	for i, peak in { { -260, 40 }, { -170, 30 }, { -90, 44 }, { -20, 26 }, { 50, 38 }, { 130, 30 }, { 210, 42 }, { 290, 32 } } do
		P(
			`Hill_{i}`,
			Vector3.new(2, peak[2], peak[2]),
			C(backdrop.hillsX, base - peak[2] * 0.15, peak[1]) * CFrame.Angles(math.rad(45), 0, 0),
			palette.SilhouetteFar,
			"solid",
			outside
		)
	end

	-- The dusk sky, in bands from the horizon up. Seen through the door from inside, only
	-- the first few dozen studs of it show, so the bands are thin there and the last one
	-- carries on high enough to fill the view from the street.
	local skyBottom = base - 2
	for i, colour in palette.Sky do
		local bandHeight = backdrop.skyBands[i] or (backdrop.skyTop - skyBottom)
		P(
			`Sky_{i}`,
			Vector3.new(2, bandHeight, backdrop.skyHalfZ * 2),
			C(backdrop.skyX, skyBottom + bandHeight * 0.5, 0),
			colour,
			"paint",
			outside
		)
		skyBottom += bandHeight
	end

	------------------------------------------------------------------------- points
	local pointsFolder = folder("Points", model)
	local points = {}
	for _, name in Layout.PointOrder do
		local point = make("Part", name, Vector3.new(1, 1, 1), at * Layout.Points[name], palette.Orange, "paint", pointsFolder)
		point.Transparency = 1
		point:SetAttribute("GaragePoint", name)
		points[name] = point
	end

	model.Parent = parent
	return model, {
		turntable = turntable,
		deck = deck,
		points = points,
	}
end

return Build
