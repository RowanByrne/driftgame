--!nonstrict
-- Showroom: builds the playground and one of every road piece into the OPEN PLACE, in
-- EDIT MODE, so the user can fly around them and look at them while we go on editing the
-- code that makes them. Nothing in the game requires this module; it is a Studio tool and
-- it is never reached at runtime.
--
-- RUN IT, from Studio's command bar (one line, paste it as it is):
--
--   require(game.ServerScriptService.Tools.Showroom).build()
--
-- and to take it away again:
--
--   require(game.ServerScriptService.Tools.Showroom).clear()
--
-- Both print what they did. `build()` is `clear()` followed by a fresh build, so running
-- it twice leaves exactly one `Workspace.Showroom` and never two.
--
-- IT ONLY EVER TOUCHES WHAT IT MADE. Everything goes under one folder,
-- `Workspace.Showroom`, marked with the attribute `Showroom`; `clear()` destroys that
-- folder and nothing else, and refuses outright if a folder of that name is there without
-- the mark. The one exception is the place's default `Baseplate`, and it is handled
-- rather than ignored -- see "The baseplate" below.
--
-- THE PLACE MUST BE SAVED for the showroom to still be there next time Studio opens it
-- (Ctrl+S). It is ordinary instances in the Workspace, not something a script rebuilds.
--
-- A PLAYTEST TAKES IT DOWN BY ITSELF, AND LEAVES IT ALONE. `PlaygroundService:Build()`
-- destroys `Workspace.Showroom` before laying its own playground, because the two sit at
-- the same world coordinates and two playgrounds in one space is doubled geometry,
-- doubled cones and a second spawn pad. Play runs on a COPY of the datamodel, so nothing
-- saved is touched: stop the playtest and the showroom is still there. Nothing to clear
-- by hand, and nothing to rebuild afterwards.
--
--------------------------------------------------------------------------------
-- How it gets the playground in edit mode
--------------------------------------------------------------------------------
--
-- It calls `PlaygroundService:Init()`, which is the real thing and not a copy of it.
-- `Init` is callable with nothing else running: it looks `TrackService` up through
-- `script.Parent` inside a `pcall` and tolerates its absence, works out this place's
-- offset, and calls `Build()`, which is pure instance-making plus one downward raycast a
-- cone -- all of which edit mode does exactly as a server does. `Start()` is NOT called,
-- and that is the point: `Start` is the two forever-loops that reset cones and catch
-- fallers, and neither belongs in an edit session.
--
-- `Build()` parents its folder straight to `Workspace` as `Playground`, so the showroom
-- takes it from there and reparents it under its own folder. Folders carry no transform,
-- so not one coordinate changes on the way.
--
-- THE BASEPLATE. `Build()` destroys the place's default `Baseplate`, by design: the
-- playground's own 2 000-stud plate is the floor, the two are exactly coplanar at y = 0,
-- and leaving both would z-fight over 2 048 studs. So the showroom lets it happen, but
-- first writes the baseplate's name, size, CFrame, colour and material onto its own root
-- as attributes, and `clear()` puts an identical part back. Anything that was parented to
-- the baseplate (the template's vestigial `Snap`) does not come back with it.
--
--------------------------------------------------------------------------------
-- What it builds
--------------------------------------------------------------------------------
--
--   Workspace.Showroom
--     Playground        exactly what `PlaygroundService:Build()` makes, where it makes it
--     Gallery           one of every variant in `Pieces.order()`, in a grid
--       Floor           a plain pad under the grid, so the pieces are not in the void
--       <VariantId>     one per piece: its parts, a flat sign and a billboard label
--
-- Each piece is placed from its own start socket, then MOVED BODILY so its real measured
-- bounding box is centred on its cell. The cell is the widest piece's longest side plus
-- `GALLERY_GAP`, so the clear distance between any two neighbours is at least that gap,
-- and the whole grid is pushed clear of the playground's plate by `GALLERY_MARGIN`. Both
-- are measured from the parts, never assumed, so a change to the piece set re-lays the
-- grid by itself.
--
-- Every label reads the variant's own id, twice: a `SurfaceGui` lying flat on the ground
-- at the front of each cell, which is what reads when flying over, and a `BillboardGui`
-- above the piece, which reads from any angle at road level.
--
-- EVERYTHING IT MAKES IS ANCHORED, including the playground's cones, which the game
-- deliberately leaves to physics. An edit-mode session must not have loose parts in it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Pieces = require(ReplicatedStorage.Shared.Road.Pieces)
local Builder = require(ReplicatedStorage.Shared.Road.Builder)

local Showroom = {}

local ROOT_NAME = "Showroom"
local MARK = "Showroom" -- the attribute that says "this folder is mine"

local GALLERY_GAP = 200 -- studs of clear ground between one piece's box and the next
local GALLERY_MARGIN = 400 -- studs between the playground's plate and the grid
local GALLERY_COLUMNS = 3
local SIGN_DEPTH = 90 -- studs; the flat name sign at the front of each cell
local SIGN_RISE = 0.25 -- studs the sign's top sits above the road surface
-- The close-up billboard. Studs, all of it, including its own size: see `makeBillboard`.
local LABEL_HEIGHT = 26 -- studs it floats above the road surface
local LABEL_SIZE = 10 -- studs tall
local LABEL_WIDTH = 40 -- studs wide
local LABEL_RANGE = 420 -- studs past which it stops drawing, so a pulled-back view has none

--------------------------------------------------------------------------------
-- Little helpers
--------------------------------------------------------------------------------

local function folderIn(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- The world-space box of every BasePart under `root`. Returns nil if there are none.
local function boxOf(root: Instance): ({ min: Vector3, max: Vector3, centre: Vector3, size: Vector3 }?)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			found = true
			-- Every part here is a box or a cylinder lying on an axis, and all the
			-- gallery's are axis-aligned only after they are rotated, so take the
			-- rotated extent properly rather than `Position +/- Size * 0.5`.
			local cf, size = d.CFrame, d.Size
			local rx = math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z
			local ry = math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z
			local rz = math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z
			local half = Vector3.new(rx, ry, rz) * 0.5
			minV = minV:Min(cf.Position - half)
			maxV = maxV:Max(cf.Position + half)
		end
	end
	if not found then
		return nil
	end
	return { min = minV, max = maxV, centre = (minV + maxV) * 0.5, size = maxV - minV }
end

local function moveBy(root: Instance, by: Vector3)
	if by.Magnitude < 1e-6 then
		return
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = d.CFrame + by
		end
	end
end

local function anchorAll(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
			n += 1
		end
	end
	return n
end

local function countParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- Edit mode caches every `require` for as long as the session lives, and `Config` caches
-- each of its children on the table itself. So a `Config/Road.luau` that Lync has just
-- re-synced is a NEW ModuleScript that nothing has re-required. Dropping the cached keys
-- makes `Config.__index` require the child instances again, and `Pieces.rebuild()` then
-- rebuilds the variant set from them. That is as far as a module can reach: if Studio's
-- own require cache is still holding the old result for the SAME instance, only reopening
-- the place clears it.
--
-- SO IF THE PIECES COME OUT LOOKING OLD, OR `build()` ERRORS ON A PROPERTY THAT IS NIL,
-- CLOSE THE PLACE AND OPEN IT AGAIN. Both are the same cause: an edit session that has a
-- half-refreshed set of modules in its cache, where (say) a new `Builder` is reading a
-- `Config.Road` that has not been re-required and has none of its new fields. Nothing a
-- module can do about it from the inside; a reopened place is always right.
local function refreshConfig()
	for _, key in { "Road", "Playground", "Drift" } do
		rawset(Config, key, nil)
	end
	Pieces.rebuild()
end

--------------------------------------------------------------------------------
-- The baseplate the playground replaces
--------------------------------------------------------------------------------

local function rememberBaseplate(root: Folder)
	local name = Config.Drift.TrackFloorName
	local plate = workspace:FindFirstChild(name)
	if not plate or not plate:IsA("BasePart") then
		return
	end
	root:SetAttribute("BaseplateName", plate.Name)
	root:SetAttribute("BaseplateSize", plate.Size)
	root:SetAttribute("BaseplateCFrame", plate.CFrame)
	root:SetAttribute("BaseplateColour", plate.Color)
	root:SetAttribute("BaseplateMaterial", plate.Material.Name)
end

local function restoreBaseplate(root: Folder)
	local name = root:GetAttribute("BaseplateName")
	if type(name) ~= "string" then
		return false
	end
	if workspace:FindFirstChild(name) then
		return false -- it survived, or something else has taken the name
	end
	local plate = Instance.new("Part")
	plate.Name = name
	plate.Size = root:GetAttribute("BaseplateSize") or Vector3.new(2048, 16, 2048)
	plate.CFrame = root:GetAttribute("BaseplateCFrame") or CFrame.new(0, -8, 0)
	plate.Color = root:GetAttribute("BaseplateColour") or Color3.fromRGB(91, 91, 91)
	local material = root:GetAttribute("BaseplateMaterial")
	if type(material) == "string" and (Enum.Material :: any)[material] then
		plate.Material = (Enum.Material :: any)[material]
	end
	plate.Anchored = true
	plate.Locked = true
	plate.Parent = workspace
	return true
end

--------------------------------------------------------------------------------
-- Labels
--------------------------------------------------------------------------------

-- The flat sign at the front of a cell: a thin slab with its name printed on its top
-- face, which is what the user reads flying over the grid. A `SurfaceGui` shows in a
-- screen capture where a `BillboardGui` does not, so this is also the one that can be
-- proved by looking.
local function makeSign(id: string, centre: Vector3, width: number, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = `Sign_{id}`
	-- THE SIGN IS BUILT SIDEWAYS ON PURPOSE. A `SurfaceGui` on the TOP face lays its
	-- canvas across the part's Z (canvas X) and along the part's X (canvas Y) -- measured,
	-- not assumed: a 420 x 90 slab gives a 720 x 3 360 canvas, which is the text turned a
	-- quarter turn and squeezed. So the slab is made long in its own Z and then turned a
	-- quarter turn, which puts the canvas's long axis along world X. The quarter turn goes
	-- the NEGATIVE way (checked by looking): that is the one that reads the right way up
	-- from a camera above and behind the grid, facing -Z, which is where Studio's camera
	-- starts and which is the side the playground is on.
	part.Size = Vector3.new(SIGN_DEPTH, 1, width)
	part.CFrame = CFrame.new(centre) * CFrame.Angles(0, -math.pi * 0.5, 0)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(18, 18, 22)
	part.Parent = parent

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	-- TEXT CANNOT BE BIGGER THAN 100 PIXELS. `TextScaled` stops there whatever the canvas
	-- is and a `UITextSizeConstraint` cannot raise it (measured: a 3 360 x 720 canvas drew
	-- 100-pixel text either way, which on a 90-stud slab is a whisper). So the canvas is
	-- scaled to the ceiling instead: at 100/SIGN_DEPTH pixels a stud, 100 pixels of text
	-- IS the full depth of the sign, and the letters come out SIGN_DEPTH studs tall.
	gui.PixelsPerStud = 100 / SIGN_DEPTH
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	-- A `SurfaceGui` stops drawing past `MaxDistance`, which defaults to 1 000 studs: the
	-- whole point of these is to be read from a camera a long way up, so the limit goes.
	gui.MaxDistance = 100000
	gui.Parent = part

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 236, 140)
	text.Text = id
	text.Parent = gui

	return part
end

-- The billboard above a piece: the CLOSE-UP label, for when the camera is down among the
-- pieces and the sign lying on the ground is edge-on and unreadable. It will not appear in
-- a screen capture; that is Studio, not this module.
--
-- IT IS SIZED IN STUDS AND IT SWITCHES OFF AT RANGE, and both of those are the fix for
-- what the first version got wrong (T-059, sent back). A `BillboardGui` sized in OFFSET is
-- sized in PIXELS: 110 pixels tall is 110 pixels tall from ten studs away and from two
-- thousand, so pulling the camera back to see the gallery grew the labels relative to the
-- pieces until nine of them overlapped into a wall of text with no road visible behind it.
-- A label must do the opposite of that. So:
--
--   SCALE in `Size` is STUDS, not a fraction, so the label shrinks with distance exactly
--   as the piece it names does and can never cover it;
--   `MaxDistance` stops it drawing at all past `LABEL_RANGE`, so the pull-back view --
--   the one the user actually flies -- has no billboards in it and reads off the ground
--   signs, which are what works from the air.
local function makeBillboard(id: string, at: Vector3, parent: Instance): Part
	local anchor = Instance.new("Part")
	anchor.Name = `Label_{id}`
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(at)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(LABEL_WIDTH, LABEL_SIZE) -- studs, not a fraction of anything
	gui.StudsOffsetWorldSpace = Vector3.new(0, LABEL_HEIGHT, 0)
	gui.AlwaysOnTop = true -- small enough to hide nothing, and a barrier must not hide it
	gui.LightInfluence = 0
	gui.MaxDistance = LABEL_RANGE
	gui.Parent = anchor

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	text.BackgroundTransparency = 0.25
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 236, 140)
	text.Text = id
	text.Parent = gui

	return anchor
end

--------------------------------------------------------------------------------
-- The gallery
--------------------------------------------------------------------------------

-- One of every variant, each built from a socket at the origin, measured, and then moved
-- bodily onto its cell. Returns the per-variant report the proof is read from.
local function buildGallery(parent: Instance, groundCentre: Vector3)
	local gallery = folderIn("Gallery", parent)
	local order = Pieces.order()
	local all = Pieces.all()

	-- Pass one: build each piece where its own maths puts it, and measure what came out.
	local entries = {}
	local widest = 0
	for i, id in order do
		local variant = all[id]
		if not variant then
			continue
		end
		local folder = folderIn(id, gallery)
		local placed = Pieces.place(variant, { x = 0, z = 0, yaw = 0 }, i)
		local built = Builder.build(placed, folder)
		built.folder.Name = "Parts"
		local box = boxOf(folder)
		table.insert(entries, { id = id, folder = folder, box = box, parts = built.parts })
		widest = math.max(widest, box.size.X, box.size.Z)
	end

	-- Pass two: a square grid of cells, each big enough for the widest piece plus the gap,
	-- laid out just past the playground's plate so neither is ever in the other's way.
	local cell = widest + GALLERY_GAP + SIGN_DEPTH
	local columns = math.min(GALLERY_COLUMNS, #entries)
	local rows = math.ceil(#entries / columns)
	local gridX = columns * cell
	local gridZ = rows * cell
	local plateHalf = 0.5 * require(ServerScriptService.Playground.Layout).Plate.size
	local centre = Vector3.new(
		groundCentre.X,
		0,
		groundCentre.Z + plateHalf + GALLERY_MARGIN + gridZ * 0.5
	)

	local surfaceY = Config.Road.SurfaceY
	for i, entry in entries do
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local cellCentre = Vector3.new(
			centre.X + (col + 0.5 - columns * 0.5) * cell,
			0,
			centre.Z + (row + 0.5 - rows * 0.5) * cell
		)
		-- The piece is centred on its cell's PIECE AREA -- the cell less the strip the
		-- sign lives in -- so the sign can never be under a barrier.
		local pieceCentre = cellCentre - Vector3.new(0, 0, SIGN_DEPTH * 0.5)
		moveBy(entry.folder, Vector3.new(pieceCentre.X - entry.box.centre.X, 0, pieceCentre.Z - entry.box.centre.Z))
		entry.box = boxOf(entry.folder)
		entry.cell = cellCentre

		makeSign(
			entry.id,
			Vector3.new(cellCentre.X, surfaceY + SIGN_RISE - 0.5, cellCentre.Z + cell * 0.5 - SIGN_DEPTH * 0.5 - 10),
			math.min(cell - 40, 420),
			entry.folder
		)
		makeBillboard(entry.id, Vector3.new(entry.box.centre.X, surfaceY, entry.box.centre.Z), entry.folder)
	end

	-- A plain pad under the whole grid, so the pieces are standing on something rather
	-- than floating in the void. Untagged on purpose: it is scenery, never drift surface.
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = Vector3.new(gridX, 4, gridZ)
	floor.CFrame = CFrame.new(centre.X, surfaceY - Config.Road.Thickness - 2, centre.Z)
	floor.Anchored = true
	floor.CanCollide = true
	floor.CastShadow = false
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.fromRGB(46, 48, 54)
	floor.Parent = gallery

	return gallery, entries, { cell = cell, columns = columns, rows = rows, centre = centre, size = Vector3.new(gridX, 0, gridZ) }
end

--------------------------------------------------------------------------------
-- Build and clear
--------------------------------------------------------------------------------

local function existingRoot(): Folder?
	local found = workspace:FindFirstChild(ROOT_NAME)
	if not found then
		return nil
	end
	if found:GetAttribute(MARK) ~= true then
		error(
			`Showroom: Workspace.{ROOT_NAME} exists but is not mine (no '{MARK}' attribute). `
				.. `Rename or remove it by hand; this tool will not touch anything it did not make.`,
			0
		)
	end
	return found
end

function Showroom.clear(): boolean
	local root = existingRoot()
	if not root then
		print("Showroom: nothing to clear.")
		return false
	end
	local restored = restoreBaseplate(root)
	root:Destroy()
	print(`Showroom: cleared.{if restored then " The place's baseplate is back." else ""}`)
	return true
end

function Showroom.build()
	refreshConfig()
	Showroom.clear()

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root:SetAttribute(MARK, true)
	root:SetAttribute("BuiltAt", DateTime.now():ToIsoDate())
	rememberBaseplate(root)
	root.Parent = workspace

	-- The playground, built by the service itself (see the header). `Init` leaves it at
	-- `Workspace.Playground`; it is moved under the showroom's root, which changes no
	-- coordinate because a folder has no transform.
	local PlaygroundService = require(ServerScriptService.Services.PlaygroundService)
	PlaygroundService:Init()
	local playground = PlaygroundService.Root
	if not playground or not playground.Parent then
		root:Destroy()
		error("Showroom: PlaygroundService:Init() did not leave a playground behind.", 0)
	end
	playground.Parent = root

	local gallery, entries, grid = buildGallery(root, PlaygroundService.Offset)

	local anchored = anchorAll(root)

	-- The proof: what is in each folder, and how far apart the pieces ended up.
	local report = {
		root = root:GetFullName(),
		playgroundParts = countParts(playground),
		galleryParts = countParts(gallery),
		anchoredParts = anchored,
		cell = grid.cell,
		columns = grid.columns,
		rows = grid.rows,
		pieces = {},
	}
	for _, entry in entries do
		table.insert(report.pieces, {
			id = entry.id,
			parts = entry.parts,
			sizeX = math.round(entry.box.size.X * 100) / 100,
			sizeZ = math.round(entry.box.size.Z * 100) / 100,
			minX = math.round(entry.box.min.X * 100) / 100,
			maxX = math.round(entry.box.max.X * 100) / 100,
			minZ = math.round(entry.box.min.Z * 100) / 100,
			maxZ = math.round(entry.box.max.Z * 100) / 100,
		})
	end

	print(
		`Showroom: built {report.playgroundParts} playground parts and {#report.pieces} road pieces `
			.. `({report.galleryParts} parts) in a {grid.columns}x{grid.rows} grid of {math.round(grid.cell)}-stud cells. `
			.. `Save the place (Ctrl+S) to keep it. A playtest takes it down by itself and leaves the saved one alone.`
	)
	for _, p in report.pieces do
		print(`  {p.id}: {p.parts} parts, {p.sizeX} x {p.sizeZ} studs`)
	end

	return report
end

-- What is there now, without changing anything: for a check after the fact.
function Showroom.state()
	local root = workspace:FindFirstChild(ROOT_NAME)
	if not root then
		return { built = false }
	end
	local out = { built = true, mine = root:GetAttribute(MARK) == true, folders = {} }
	for _, child in root:GetChildren() do
		out.folders[child.Name] = countParts(child)
	end
	local gallery = root:FindFirstChild("Gallery")
	if gallery then
		out.pieces = {}
		for _, folder in gallery:GetChildren() do
			if folder:IsA("Folder") then
				local box = boxOf(folder)
				out.pieces[folder.Name] = {
					parts = countParts(folder),
					min = box and box.min,
					max = box and box.max,
				}
			end
		end
	end
	out.tagged = #CollectionService:GetTagged(Config.Drift.SurfaceTag)
	return out
end

return Showroom
