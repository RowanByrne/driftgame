--!strict
-- GroundMarks: the grass and mud marks as a mesh ribbon laid on the ground, one per wheel
-- (T-265, features/car-fx.md "Ruts cut into the ground"). `Drift/Wheels` decides WHEN a wheel
-- marks grass and which look; this module draws it.
--
-- ------------------------------------------------------------------ why a mesh, not a Trail
--
-- The user, of the trail-built ruts: *"this just looks kinda cheap ... research methods for
-- realism looking tire marks, not cheap roblox stuff."* A `Trail` lays a flat, unlit quad a
-- frame between two points: hard edges, a kink wherever a frame's points jump, a colour that
-- ignores the scene's light (black bands at night), and nothing across its width. Racing
-- games draw skid marks as a ribbon MESH on the ground, and so does this:
--
--   * A CROSS-SECTION every few studs (`Ribbon.Spacing`, sooner through a bend and while a
--     mark fades in), joined to the last by a segment of quads, square to the bisector of
--     the path either side (a mitred joint), so a curve is a curve. The newest segment
--     follows the tyre every frame, so a mark never lags or steps.
--   * A SHAPED PROFILE across it (`Grass.Profile`): an edge, a berm, a wall leaning in, a
--     floor. Its NORMALS lean with it and the parts are lit by the scene, so one wall catches
--     the sun, the moon or the headlights and the other falls into shade. The drawn ground
--     cannot be cut, but that light is what the eye reads as depth.
--   * IT BLENDS INTO THE GROUND ITSELF, not by see-through. In Roblox neither a vertex
--     colour's alpha nor a MeshPart texture's alpha is see-through -- both show the part's own
--     colour (measured, DR-Lane3: white streaks and white bands) -- and a SurfaceAppearance,
--     which is, cannot be set from a game script (measured: refused at runtime). So the
--     ribbon is opaque, and its OUTER strips are drawn exactly as the ground under them is:
--     the same `Grass` material on the same world UVs, the ground's own vertex colour and
--     normal at the edge (read off the drawn tile), blending into the mark's colour and shape
--     toward the berm. An edge that is the ground is an edge you cannot see.
--   * The INNER strips (berm, walls, floor) are `Ribbon.InnerMaterial` (wet mud) with a streak
--     texture made here in code (an `EditableImage`, nothing uploaded): tread lines along the
--     travel and clods toward the edges, tinted by the vertex colours.
--   * HOW MUCH OF THE MARK SHOWS is a per-vertex blend between the ground's colour and
--     normal and the mark's: it comes in over a mark's first studs, goes out over its last
--     segment, is fainter for the flattened-grass look than for a rut, and fades back into the
--     ground with age while the mud dries, rewritten in `AgeLevels` steps.
--   * ON THE DRAWN GROUND: each section's outer points and centre are put on the ground mesh
--     (`GroundMeshView._drawnAt`), the rest on the lines between.
--
-- ------------------------------------------------------------------ what it is made of
--
-- `Ribbon.Chunks` chunks, each two `EditableMesh` MeshParts (the outer strips and the inner
-- ones) of `PerChunk` SEGMENT SLOTS: 2 sections across the profile's points. Built ONCE (it
-- yields, so in its own thread) and only rewritten in place -- SetPosition / SetNormal /
-- SetColor / SetUV, about a tenth of a microsecond a call (measured). A dead slot is collapsed
-- to a point. Slots are handed out in a ring, oldest first; a chunk is started at the car and
-- takes segments within `ChunkReach` of there, so its local coordinates stay small.
--
-- The ids `Add...` returns are the ids of the fixed copy `CreateEditableMeshAsync` makes
-- (measured), so they are kept as returned. (Not by `GetColors` order: that also lists what
-- `AddTriangle` makes for itself -- measured, it left slots white.)
--
-- Nothing here reads the car. Every input is a plain value from `Drift/Wheels`.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GroundMarks = {}
GroundMarks.__index = GroundMarks

local HALF = 512 -- studs: a chunk's local box, either way of its origin
local MARKER = 0.01 -- studs: the two tiny triangles that hold the box open
local DEPTH_LEVELS = 8 -- the flat-to-rut blend, in steps, for the colour table

-- One of a chunk's two meshes: which profile points it carries, and the quads between them.
type Layer = {
	name: string,
	points: { number }, -- profile point indices, left to right
	strips: { { number } }, -- pairs of indices into `points`
	at: { number }, -- profile point j -> its index in `points`, 0 if not in this layer
	n: number, -- #points
	vids: { number }, -- by (slot - 1) * 2n + section * n + index
	cids: { number },
	nids: { number },
	uids: { number },
	textured: boolean, -- the inner layer: streak texture, UVs across and along the mark
}

type Chunk = {
	origin: Vector3,
	ems: { EditableMesh }, -- one per layer
	parts: { MeshPart },
}

type Ribbon = {
	on: boolean,
	head: number?, -- the slot being drawn to the tyre, nil between sections
	lastSlot: number?, -- the last segment committed, which a mark ending just after fades
	lastPos: Vector3, -- the last committed section's centre, world
	lastPts: { Vector3 }, -- its points, normals, and the ground's colour and normal under them
	lastNrm: { Vector3 },
	lastGC: { Color3 },
	lastGN: { Vector3 },
	lastD: number, -- its blend (0 flat .. 1 rut), strength (0..1) and texture v
	lastS: number,
	lastV: number,
	prevDir: Vector3?, -- the direction of the last committed segment
	dist: number, -- studs along this mark to the last section
	depth: number, -- the blend now, walking toward `rut`
	ratio: number, -- the smoothed width share (T-207)
	rut: boolean,
	snapped: number, -- points of the newest section on the drawn ground, 0..3
}

export type GroundMarks = typeof(setmetatable(
	{} :: {
		ready: boolean,
		failed: string?,
		folder: Folder?,
		image: EditableImage?,
		layers: { Layer },
		chunks: { Chunk },
		P: number, -- points across a section
		perChunk: number,
		total: number,
		-- per slot, 1..total
		live: { boolean },
		born: { number },
		level: { number },
		isHead: { boolean },
		d0: { number },
		d1: { number },
		s0: { number },
		s1: { number },
		ground: { Color3 }, -- per slot and point: the ground's colour, (g-1)*2P + sec*P + j
		cursor: number,
		current: number,
		clock: number,
		life: number,
		wheels: { Ribbon },
		scratchPts: { Vector3 },
		scratchNrm: { Vector3 },
		scratchGC: { Color3 },
		scratchGN: { Vector3 },
		lutC: { Color3 }, -- [(h-1)*(DL+1)*AL + dl*AL + al + 1]: the mark's own colour
		fadeAt: { number }, -- per age step: how much of the mark is left
		offsets: { number }, -- per point, signed share of the half-width, -1..1
		heights: { { number } }, -- per point: flat, rut
		tilts: { { number } },
		weights: { number }, -- per point: how much it is the mark rather than the ground
		us: { number },
		segments: number,
		recycled: number, -- live segments thrown away early to make room
		lookups: number,
	},
	GroundMarks
))

--------------------------------------------------------------------------------
-- The texture, pure
--------------------------------------------------------------------------------

-- The inner strips' streak texture: `Width x Height` RGBA bytes, columns across the mark (u)
-- and rows along it (v), grey (the vertex colours tint it), opaque. Repeats seamlessly along
-- v. Deterministic from `Seed`.
function GroundMarks.texturePixels(T: any): buffer
	local W, H = T.Width, T.Height
	local rng = Random.new(T.Seed)
	local buf = buffer.create(W * H * 4)
	-- Tread streaks: a value per column, smoothed across so a streak is a few pixels wide,
	-- and a slow wobble along each one (whole sine periods, so the tile repeats).
	local raw = table.create(W, 0)
	for x = 1, W do
		raw[x] = rng:NextNumber()
	end
	local streak = table.create(W, 0)
	for x = 1, W do
		local a, b, c = raw[math.max(x - 1, 1)], raw[x], raw[math.min(x + 1, W)]
		streak[x] = (a + 2 * b + c) / 4
	end
	local phase, freq = table.create(W, 0), table.create(W, 1)
	for x = 1, W do
		phase[x] = rng:NextNumber() * math.pi * 2
		freq[x] = rng:NextInteger(1, 3)
	end
	for y = 1, H do
		local t = (y - 1) / H * math.pi * 2
		for x = 1, W do
			local wobble = 1 - T.StreakWobble * (0.5 + 0.5 * math.sin(t * freq[x] + phase[x]))
			local value = T.Base - T.StreakDepth * streak[x] * wobble
			local o = ((y - 1) * W + (x - 1)) * 4
			local g = math.clamp(math.floor(value * 255 + 0.5), 0, 255)
			buffer.writeu8(buf, o, g)
			buffer.writeu8(buf, o + 1, g)
			buffer.writeu8(buf, o + 2, g)
			buffer.writeu8(buf, o + 3, 255)
		end
	end
	-- Flecks and clods: 1 to 3 pixel blots, mostly in the bands near the edges, light (a dry
	-- clod in the sun) or dark (a wet one).
	for _ = 1, T.Flecks do
		local band = rng:NextNumber() * T.FleckBand
		local u = if rng:NextNumber() < 0.5 then band else 1 - band
		if rng:NextNumber() < 0.25 then
			u = rng:NextNumber()
		end
		local cx = math.clamp(math.floor(u * W), 0, W - 1)
		local cy = rng:NextInteger(0, H - 1)
		local size = rng:NextInteger(1, 3)
		local g = math.floor((if rng:NextNumber() < 0.6 then T.FleckLight else T.FleckDark) * 255 + 0.5)
		for dy = 0, size - 1 do
			for dx = 0, size - 1 do
				local px = cx + dx
				if px < W then
					local o = (((cy + dy) % H) * W + px) * 4
					buffer.writeu8(buf, o, g)
					buffer.writeu8(buf, o + 1, g)
					buffer.writeu8(buf, o + 2, g)
				end
			end
		end
	end
	return buf
end

--------------------------------------------------------------------------------
-- The ground under a point
--------------------------------------------------------------------------------

-- The drawn ground's colour at (x, z), from the tile `_drawnAt` handed back with its height:
-- its vertex colours, bilinear across the grid cell. nil without a tile.
function GroundMarks.tileColour(tile: any, x: number, z: number): Color3?
	if type(tile) ~= "table" or type(tile.leaf) ~= "table" or type(tile.colours) ~= "table" then
		return nil
	end
	local C = Config.Spline.Ground.TileCells
	local n = C + 1
	local leaf = tile.leaf
	local fx, fz = (x - leaf.x0) / leaf.s, (z - leaf.z0) / leaf.s
	local i, j = math.clamp(math.floor(fx), 0, C - 1), math.clamp(math.floor(fz), 0, C - 1)
	local tx, tz = math.clamp(fx - i, 0, 1), math.clamp(fz - j, 0, 1)
	local cs = tile.colours
	local c00, c10, c01, c11 = cs[i * n + j + 1], cs[(i + 1) * n + j + 1], cs[i * n + j + 2], cs[(i + 1) * n + j + 2]
	if not (c00 and c10 and c01 and c11) then
		return nil
	end
	return c00:Lerp(c10, tx):Lerp(c01:Lerp(c11, tx), tz)
end

-- One point put on the drawn ground: back `lift` over it, with the ground's colour and the
-- normal it is drawn with there -- or as it was (false) when there is no ground drawn there
-- or reaching it would move it more than `maxSnap`.
function GroundMarks.probe(ground: any, p: Vector3, lift: number, maxSnap: number): (Vector3, boolean, Color3?, Vector3?)
	local y, tile, _, sn = ground:_drawnAt(p.X, p.Z)
	if type(y) == "number" and math.abs(y + lift - p.Y) <= maxSnap then
		local normal = if typeof(sn) == "Vector3" and sn.Magnitude > 1e-4 then sn.Unit else nil
		return Vector3.new(p.X, y + lift, p.Z), true, GroundMarks.tileColour(tile, p.X, p.Z), normal
	end
	return p, false, nil, nil
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function makeLayer(name: string, points: { number }, P: number, textured: boolean): Layer
	local at = table.create(P, 0)
	for i, j in points do
		at[j] = i
	end
	local strips = {}
	for i = 1, #points - 1 do
		-- only between neighbours in the profile (the outer layer has a gap in the middle)
		if points[i + 1] == points[i] + 1 then
			table.insert(strips, { i, i + 1 })
		end
	end
	return { name = name, points = points, strips = strips, at = at, n = #points, vids = {}, cids = {}, nids = {}, uids = {}, textured = textured }
end

-- A ribbon with nothing built yet. `Build` makes the meshes (it yields).
function GroundMarks.new(): GroundMarks
	local G = Config.Fx.Ground
	local R = G.Ribbon
	local profile = G.Grass.Profile
	local half = #profile
	local P = half * 2
	local inner = {}
	for j = 2, P - 1 do
		table.insert(inner, j)
	end
	local self = setmetatable({
		ready = false,
		failed = nil,
		folder = nil,
		image = nil,
		layers = {
			-- the outer strips, edge to berm either side: drawn as the ground is
			makeLayer("Outer", { 1, 2, P - 1, P }, P, false),
			-- the berm, walls and floor between: the mark itself
			makeLayer("Inner", inner, P, true),
		},
		chunks = {},
		P = P,
		perChunk = R.PerChunk,
		total = R.Chunks * R.PerChunk,
		live = {},
		born = {},
		level = {},
		isHead = {},
		d0 = {},
		d1 = {},
		s0 = {},
		s1 = {},
		ground = {},
		cursor = 1,
		current = 1,
		clock = 0,
		life = G.MarkSeconds,
		wheels = {},
		scratchPts = table.create(P, Vector3.zero),
		scratchNrm = table.create(P, Vector3.yAxis),
		scratchGC = table.create(P, Color3.new()),
		scratchGN = table.create(P, Vector3.yAxis),
		lutC = {},
		fadeAt = {},
		offsets = table.create(P, 0),
		heights = {},
		tilts = {},
		weights = table.create(P, 0),
		us = table.create(P, 0),
		segments = 0,
		recycled = 0,
		lookups = 0,
	}, GroundMarks) :: any
	-- The profile, mirrored: point 1 is the left edge, P the right edge.
	local flat, rut = G.Grass.FlatMark, G.Grass.TrenchMark
	for j = 1, P do
		local h = if j <= half then j else P + 1 - j
		local side = if j <= half then -1 else 1
		local p = profile[h]
		self.offsets[j] = side * p.Offset
		self.us[j] = (side * p.Offset + 1) * 0.5
		self.heights[j] = { p.Height * flat.HeightScale, p.Height * rut.HeightScale }
		self.tilts[j] = { math.rad(p.Tilt * flat.TiltScale), math.rad(p.Tilt * rut.TiltScale) }
		self.weights[j] = p.Weight
	end
	GroundMarks._buildTables(self)
	for i = 1, 4 do
		self.wheels[i] = {
			on = false,
			head = nil,
			lastSlot = nil,
			lastPos = Vector3.zero,
			lastPts = table.create(P, Vector3.zero),
			lastNrm = table.create(P, Vector3.yAxis),
			lastGC = table.create(P, Color3.new()),
			lastGN = table.create(P, Vector3.yAxis),
			lastD = 0,
			lastS = 0,
			lastV = 0,
			prevDir = nil,
			dist = 0,
			depth = 0,
			ratio = 1,
			rut = false,
			snapped = 0,
		}
	end
	return self
end

-- The mark's own colour at every profile point, blend step and age step, and how much of the
-- mark is left at every age step, so painting a slot is lookups.
function GroundMarks._buildTables(self: GroundMarks)
	local G = Config.Fx.Ground
	local R = G.Ribbon
	local flat, rut = G.Grass.FlatMark.Points, G.Grass.TrenchMark.Points
	local AL = R.AgeLevels
	local fadeAt = Config.Fx.Marks.FadeAt
	table.clear(self.lutC)
	table.clear(self.fadeAt)
	for al = 0, AL - 1 do
		local age = (al + 0.5) / AL
		self.fadeAt[al + 1] = if age <= fadeAt then 1 else math.clamp(1 - (age - fadeAt) / math.max(1 - fadeAt, 1e-4), 0, 1)
	end
	for h = 1, #flat do
		for dl = 0, DEPTH_LEVELS do
			local d = dl / DEPTH_LEVELS
			local wet = flat[h].Colour:Lerp(rut[h].Colour, d)
			local dry = flat[h].DryColour:Lerp(rut[h].DryColour, d)
			for al = 0, AL - 1 do
				self.lutC[(h - 1) * (DEPTH_LEVELS + 1) * AL + dl * AL + al + 1] = wet:Lerp(dry, (al + 0.5) / AL)
			end
		end
	end
end

-- One layer's template mesh: `slots` segments, the layer's points at each of 2 sections,
-- its strips' quads, and two specks at opposite corners that hold the box open at +-HALF so
-- the MeshPart is made at scale 1. Ids are written into the layer from `base`.
local function makeTemplate(layer: Layer, slots: number, base: number): EditableMesh
	local em = AssetService:CreateEditableMesh({ FixedSize = false })
	assert(em, "no EditableMesh")
	local n = layer.n
	for slot = 1, slots do
		local v, c, nn, u = table.create(2 * n, 0), table.create(2 * n, 0), table.create(2 * n, 0), table.create(2 * n, 0)
		for k = 1, 2 * n do
			v[k] = em:AddVertex(Vector3.zero)
			c[k] = em:AddColor(Color3.new(1, 1, 1), 1)
			nn[k] = em:AddNormal(Vector3.yAxis)
			u[k] = em:AddUV(Vector2.zero)
			local at = base + (slot - 1) * 2 * n + k
			layer.vids[at], layer.cids[at], layer.nids[at], layer.uids[at] = v[k], c[k], nn[k], u[k]
		end
		-- Section 0 (k = 1..n) is the start, behind; section 1 (n+1..2n) the end, ahead.
		-- Wound so `(c - a) x (b - a)` points up: a ahead-left, c behind-left, b ahead-right.
		for _, strip in layer.strips do
			local i, i2 = strip[1], strip[2]
			local a, b, cc, d = n + i, n + i2, i, i2
			for _, t in { { a, cc, b }, { b, cc, d } } do
				local f = em:AddTriangle(v[t[1]], v[t[2]], v[t[3]])
				em:SetFaceColors(f, { c[t[1]], c[t[2]], c[t[3]] })
				em:SetFaceNormals(f, { nn[t[1]], nn[t[2]], nn[t[3]] })
				em:SetFaceUVs(f, { u[t[1]], u[t[2]], u[t[3]] })
			end
		end
	end
	for _, corner in { -HALF, HALF } do
		local p = Vector3.new(corner, corner, corner)
		local ids = {}
		for q = 0, 2 do
			ids[q + 1] = em:AddVertex(p + Vector3.new(if q == 1 then MARKER else 0, 0, if q == 2 then MARKER else 0))
		end
		em:AddTriangle(ids[1], ids[2], ids[3])
	end
	return em
end

-- Make the meshes, the texture and the folder. YIELDS: call it in its own thread. Returns
-- whether it worked; `failed` says why not. `parent` is where the folder goes (Workspace in
-- play; the tests use ServerStorage).
function GroundMarks.Build(self: GroundMarks, parent: Instance?): boolean
	local ok, err = pcall(function()
		local R = Config.Fx.Ground.Ribbon
		local folder = Instance.new("Folder")
		folder.Name = Config.Fx.Names.MarksFolder
		local T = R.Texture
		local size = Vector2.new(T.Width, T.Height)
		local image = AssetService:CreateEditableImage({ Size = size })
		assert(image, "no EditableImage")
		image:WritePixelsBuffer(Vector2.zero, size, GroundMarks.texturePixels(T))
		self.image = image
		for ci = 1, R.Chunks do
			local chunk: Chunk = { origin = Vector3.zero, ems = {}, parts = {} }
			for li, layer in self.layers do
				local template = makeTemplate(layer, self.perChunk, (ci - 1) * self.perChunk * 2 * layer.n)
				local em = AssetService:CreateEditableMeshAsync(Content.fromObject(template), { FixedSize = true })
				template:Destroy()
				assert(em, "no fixed copy")
				local part = AssetService:CreateMeshPartAsync(Content.fromObject(em), {
					CollisionFidelity = Enum.CollisionFidelity.Box,
					RenderFidelity = Enum.RenderFidelity.Precise,
				})
				assert(part, "no MeshPart")
				part.Name = string.format(Config.Fx.Names.MarksChunk, ci) .. layer.name
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Color = Color3.new(1, 1, 1)
				if layer.textured then
					part.Material = R.InnerMaterial
					part.TextureContent = Content.fromObject(image)
				else
					part.Material = R.OuterMaterial -- the ground's own
				end
				part.CFrame = CFrame.new(0, 0, 0)
				part.Parent = folder
				chunk.ems[li] = em
				chunk.parts[li] = part
			end
			table.insert(self.chunks, chunk)
		end
		for g = 1, self.total do
			self.live[g] = false
			self.born[g] = 0
			self.level[g] = -1
			self.isHead[g] = false
			self.d0[g], self.d1[g], self.s0[g], self.s1[g] = 0, 0, 0, 0
		end
		local grass = Config.Spline.Terrain.GrassColour
		for k = 1, self.total * 2 * self.P do
			self.ground[k] = grass
		end
		folder.Parent = parent or workspace
		self.folder = folder
	end)
	if not ok then
		self.failed = tostring(err)
		GroundMarks.Destroy(self)
		return false
	end
	self.ready = true
	return true
end

function GroundMarks.Destroy(self: GroundMarks)
	self.ready = false
	for _, ch in self.chunks do
		for li = 1, #ch.parts do
			ch.parts[li]:Destroy()
			ch.ems[li]:Destroy()
		end
	end
	table.clear(self.chunks)
	if self.image then
		self.image:Destroy()
		self.image = nil
	end
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
end

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------

local function chunkOf(self: GroundMarks, g: number): Chunk
	return self.chunks[(g - 1) // self.perChunk + 1]
end

local function kill(self: GroundMarks, g: number)
	if not self.live[g] then
		return
	end
	self.live[g] = false
	self.isHead[g] = false
	local ch = chunkOf(self, g)
	for li, layer in self.layers do
		local em = ch.ems[li]
		local base = (g - 1) * 2 * layer.n
		for k = 1, 2 * layer.n do
			em:SetPosition(layer.vids[base + k], Vector3.zero)
		end
	end
end

-- The next free slot, for a segment starting at `at`. Moves to the next chunk -- clearing
-- what is left in it, oldest first -- when this one is full or `at` is out of its reach.
local function alloc(self: GroundMarks, at: Vector3): number
	local R = Config.Fx.Ground.Ribbon
	local ch = self.chunks[self.current]
	local off = at - ch.origin
	if self.cursor > self.perChunk or math.max(math.abs(off.X), math.abs(off.Y), math.abs(off.Z)) > R.ChunkReach then
		self.current = self.current % #self.chunks + 1
		self.cursor = 1
		ch = self.chunks[self.current]
		local first = (self.current - 1) * self.perChunk
		for g = first + 1, first + self.perChunk do
			if self.live[g] then
				if self.isHead[g] then
					-- A wheel is still drawing into it: let it go, its mark just restarts.
					for _, r in self.wheels do
						if r.head == g then
							r.head = nil
						end
					end
				end
				self.recycled += 1
				kill(self, g)
			end
		end
		ch.origin = at
		for _, part in ch.parts do
			part.CFrame = CFrame.new(at)
		end
	end
	local g = (self.current - 1) * self.perChunk + self.cursor
	self.cursor += 1
	if self.live[g] then
		self.recycled += 1
		kill(self, g)
	end
	self.live[g] = true
	self.born[g] = self.clock
	self.level[g] = -1
	self.segments += 1
	return g
end

local function lut(self: GroundMarks, j: number, d: number, al: number): Color3
	local P = self.P
	local half = P // 2
	local h = if j <= half then j else P + 1 - j
	local AL = Config.Fx.Ground.Ribbon.AgeLevels
	local dl = math.clamp(math.floor(d * DEPTH_LEVELS + 0.5), 0, DEPTH_LEVELS)
	return self.lutC[(h - 1) * (DEPTH_LEVELS + 1) * AL + dl * AL + math.clamp(al, 0, AL - 1) + 1]
end

-- How much of the mark shows at a section, 0..1: its strength (soft ends), its look (a
-- flattened line is fainter than a rut) and what age has left of it.
function GroundMarks.showing(self: GroundMarks, d: number, s: number, al: number): number
	local G = Config.Fx.Ground
	local look = G.Grass.FlatMark.Opacity + (G.Grass.TrenchMark.Opacity - G.Grass.FlatMark.Opacity) * d
	return s * look * self.fadeAt[math.clamp(al, 0, G.Ribbon.AgeLevels - 1) + 1]
end

-- Write one section of slot `g` (0 the start, 1 the end): its points, normals and UVs, and
-- the ground's colour under it (kept for painting as it ages).
local function writeSection(self: GroundMarks, g: number, sec: number, pts: { Vector3 }, nrm: { Vector3 }, gc: { Color3 }, v: number)
	local ch = chunkOf(self, g)
	local origin = ch.origin
	local P = self.P
	local uvStuds = Config.Spline.Ground.UVStuds
	for j = 1, P do
		self.ground[(g - 1) * 2 * P + sec * P + j] = gc[j]
	end
	for li, layer in self.layers do
		local em = ch.ems[li]
		local n = layer.n
		local base = (g - 1) * 2 * n + sec * n
		for i, j in layer.points do
			local k = base + i
			local p = pts[j]
			em:SetPosition(layer.vids[k], p - origin)
			em:SetNormal(layer.nids[k], nrm[j])
			-- The inner strips: across and along the mark, for the streaks. The outer ones:
			-- the ground's own world mapping, so its material lines up with the ground's.
			em:SetUV(layer.uids[k], if layer.textured then Vector2.new(self.us[j], v) else Vector2.new(p.X / uvStuds, p.Z / uvStuds))
		end
	end
end

-- Paint slot `g` for age step `al`: each point the ground's colour, blended toward the mark's
-- by how much of the mark shows there and how much that point is the mark (`Weight`).
local function paint(self: GroundMarks, g: number, al: number)
	local ch = chunkOf(self, g)
	local P = self.P
	for sec = 0, 1 do
		local d = if sec == 0 then self.d0[g] else self.d1[g]
		local s = if sec == 0 then self.s0[g] else self.s1[g]
		local show = GroundMarks.showing(self, d, s, al)
		for li, layer in self.layers do
			local em = ch.ems[li]
			local base = (g - 1) * 2 * layer.n + sec * layer.n
			for i, j in layer.points do
				local gc = self.ground[(g - 1) * 2 * P + sec * P + j]
				em:SetColor(layer.cids[base + i], gc:Lerp(lut(self, j, d, al), self.weights[j] * show))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------

-- One cross-section at `centre` (the tyre's contact, world), square to `tangent`, with the
-- ground's up `up`, half-width `hw`, blend `d` and strength `s`, into the scratch arrays.
-- Its two outer points and its centre are put on `ground` when given; the others go on the
-- lines between. Returns how many of the three found the ground.
local function section(self: GroundMarks, centre: Vector3, tangent: Vector3, up: Vector3, hw: number, d: number, s: number, ground: any?): number
	local G = Config.Fx.Ground
	local right = tangent:Cross(up)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local base = centre + up * G.Lift
	local L, M, Rr = base - right * hw, base, base + right * hw
	local grass = Config.Spline.Terrain.GrassColour
	local cL, cM, cR, nL, nM, nR = grass, grass, grass, up, up, up
	local found = 0
	if ground then
		local okL, okM, okR, c1, c2, c3, n1, n2, n3
		L, okL, c1, n1 = GroundMarks.probe(ground, L, G.Lift, G.MaxSnap)
		M, okM, c2, n2 = GroundMarks.probe(ground, M, G.Lift, G.MaxSnap)
		Rr, okR, c3, n3 = GroundMarks.probe(ground, Rr, G.Lift, G.MaxSnap)
		found = (if okL then 1 else 0) + (if okM then 1 else 0) + (if okR then 1 else 0)
		cL, cM, cR = c1 or grass, c2 or grass, c3 or grass
		nL, nM, nR = n1 or up, n2 or up, n3 or up
		self.lookups += 3
	end
	-- The section's own up, from its two edges and the path: the ground across the mark.
	local across = Rr - L
	local n = if across.Magnitude > 1e-4 then across:Cross(tangent) else up
	if n.Magnitude < 1e-4 or n:Dot(up) <= 0 then
		n = up
	end
	n = n.Unit
	local acrossUnit = if across.Magnitude > 1e-4 then across.Unit else right
	for j = 1, self.P do
		local f = self.offsets[j]
		local t = math.abs(f)
		local at = if f < 0 then M:Lerp(L, t) else M:Lerp(Rr, t)
		local gc = if f < 0 then cM:Lerp(cL, t) else cM:Lerp(cR, t)
		local gn = (if f < 0 then nM:Lerp(nL, t) else nM:Lerp(nR, t)).Unit
		local hs, ts = self.heights[j], self.tilts[j]
		-- How much of the mark's shape shows here: none at the edge, all of it inside.
		local shape = self.weights[j] * s
		local height = (hs[1] + (hs[2] - hs[1]) * d) * shape
		local tilt = (ts[1] + (ts[2] - ts[1]) * d) * shape
		self.scratchPts[j] = at + n * height
		-- Lean toward the centre: +across on the left side, -across on the right; and at the
		-- edge, exactly the ground's own normal, so the light falls on both alike.
		local inward = if f < 0 then acrossUnit else -acrossUnit
		local shaped = (n * math.cos(tilt) + inward * math.sin(tilt)).Unit
		self.scratchNrm[j] = gn:Lerp(shaped, self.weights[j]).Unit
		self.scratchGC[j] = gc
		self.scratchGN[j] = gn
	end
	return found
end

local function keep(self: GroundMarks, r: Ribbon)
	for j = 1, self.P do
		r.lastPts[j] = self.scratchPts[j]
		r.lastNrm[j] = self.scratchNrm[j]
		r.lastGC[j] = self.scratchGC[j]
		r.lastGN[j] = self.scratchGN[j]
	end
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

-- Finish wheel `r`'s mark where it is: its last segment fades out into the ground.
local function finish(self: GroundMarks, r: Ribbon)
	local g = r.head or r.lastSlot
	if g and self.live[g] then
		self.s1[g] = 0
		self.isHead[g] = false
		local al = math.max(self.level[g], 0)
		self.level[g] = al
		paint(self, g, al)
	end
	r.head = nil
	r.lastSlot = nil
	r.on = false
end

-- One wheel, one frame. `on`: it is marking grass. `contact`: its contact centre on the
-- ground, world. `up`: the ground's up. `across`: its path's cross axis (T-207's span), used
-- until the mark has a direction of its own. `ratio`: T-207's width share. `rut`: the trench
-- look (Wheels' hysteresis). `ground`: the drawn ground (anything with `_drawnAt`), or nil.
function GroundMarks.Wheel(
	self: GroundMarks,
	i: number,
	on: boolean,
	contact: Vector3,
	up: Vector3,
	across: Vector3,
	ratio: number,
	rut: boolean,
	ground: any?,
	dt: number
)
	local r = self.wheels[i]
	if not self.ready or not r then
		return
	end
	if not on then
		if r.on then
			finish(self, r)
		end
		r.snapped = 0
		return
	end
	local G = Config.Fx.Ground
	local R = G.Ribbon
	r.rut = rut
	local hw = G.Grass.Width * 0.5
	if not r.on then
		-- A new mark: its first section, at nothing, where the tyre is.
		r.on = true
		r.head = nil
		r.lastSlot = nil
		r.prevDir = nil
		r.dist = 0
		r.depth = if rut then 1 else 0
		r.ratio = math.max(ratio, G.Grass.MinWidthRatio)
		local tangent = up:Cross(across)
		r.snapped = section(self, contact, if tangent.Magnitude > 1e-4 then tangent.Unit else Vector3.zAxis, up, hw * r.ratio, r.depth, 0, ground)
		keep(self, r)
		r.lastPos, r.lastD, r.lastS, r.lastV = contact, r.depth, 0, (i - 1) * 0.37
		return
	end
	-- Ease the blend and the width, so neither ever steps.
	local target = if rut then 1 else 0
	local blend = dt / math.max(R.BlendSeconds, 1e-4)
	r.depth = if r.depth < target then math.min(r.depth + blend, target) else math.max(r.depth - blend, target)
	r.ratio += (math.max(ratio, G.Grass.MinWidthRatio) - r.ratio) * (1 - math.exp(-dt / math.max(R.WidthSeconds, 1e-4)))

	local chord = contact - r.lastPos
	chord -= up * chord:Dot(up)
	local len = chord.Magnitude
	if len < 0.05 then
		return
	end
	local dir = chord / len
	if not r.prevDir and not r.head then
		-- The mark's first segment: square its first section to where it actually went,
		-- not to the guess it started with, so the ribbon cannot twist.
		section(self, r.lastPos, dir, up, hw * r.ratio, r.lastD, r.lastS, ground)
		keep(self, r)
	end
	-- Square to the bisector of this segment and the last: a mitred joint, no kink.
	local tangent = dir
	if r.prevDir then
		local bis = dir + (r.prevDir :: Vector3)
		if bis.Magnitude > 1e-3 then
			tangent = bis.Unit
		end
	end
	local strength = math.clamp((r.dist + len) / math.max(R.FadeInStuds, 1e-4), 0, 1)
	r.snapped = section(self, contact, tangent, up, hw * r.ratio, r.depth, strength, ground)
	local v = r.lastV + len / math.max(R.TileLength, 1e-4)

	local g = r.head
	if not g then
		g = alloc(self, r.lastPos)
		r.head = g
		self.isHead[g] = true
		self.d0[g], self.s0[g] = r.lastD, r.lastS
		writeSection(self, g, 0, r.lastPts, r.lastNrm, r.lastGC, r.lastV)
	end
	self.d1[g], self.s1[g] = r.depth, strength
	writeSection(self, g, 1, self.scratchPts, self.scratchNrm, self.scratchGC, v)
	paint(self, g, 0)

	-- Commit: this section is fixed, and the next segment starts from it. Short segments
	-- while the mark comes in, so it comes in smoothly.
	local turned = if r.prevDir then math.deg(math.acos(math.clamp(dir:Dot(r.prevDir :: Vector3), -1, 1))) else 0
	local spacing = if r.dist < R.FadeInStuds then R.MinSpacing else R.Spacing
	if len >= spacing or (len >= R.MinSpacing and turned >= R.TurnDegrees) then
		self.isHead[g] = false
		self.born[g] = self.clock
		self.level[g] = 0
		r.head = nil
		r.lastSlot = g
		keep(self, r)
		r.lastPos, r.lastD, r.lastS, r.lastV = contact, r.depth, strength, v
		r.dist += len
		r.prevDir = dir
	end
end

-- Once a frame, after the wheels: the clock moves on, and every laid segment dries and
-- fades into the ground a step whenever its age crosses one, and goes when its life is up.
function GroundMarks.Age(self: GroundMarks, dt: number)
	if not self.ready then
		return
	end
	self.clock += dt
	local AL = Config.Fx.Ground.Ribbon.AgeLevels
	local life = math.max(self.life, 1e-3)
	for g = 1, self.total do
		if self.live[g] and not self.isHead[g] then
			local age = self.clock - self.born[g]
			if age >= life then
				kill(self, g)
			else
				local al = math.floor(age / life * AL)
				if al ~= self.level[g] then
					self.level[g] = al
					paint(self, g, al)
				end
			end
		end
	end
end

-- Every wheel's mark ends where it is, with no fade: the car has jumped (spawn, respawn,
-- teleport), and the next mark must not join across the jump.
function GroundMarks.Cut(self: GroundMarks)
	for _, r in self.wheels do
		if r.head then
			self.isHead[r.head] = false
		end
		r.head = nil
		r.lastSlot = nil
		r.on = false
		r.snapped = 0
	end
end

-- Every mark gone, at once.
function GroundMarks.Clear(self: GroundMarks)
	GroundMarks.Cut(self)
	for g = 1, self.total do
		kill(self, g)
	end
	self.cursor = self.perChunk + 1 -- start a fresh chunk next
end

-- How long a mark lasts from now on.
function GroundMarks.SetLife(self: GroundMarks, seconds: number)
	self.life = seconds
end

-- What wheel `i` is laying: "rut", "flat" or nil.
function GroundMarks.Kind(self: GroundMarks, i: number): string?
	local r = self.wheels[i]
	if not r or not r.on then
		return nil
	end
	return if r.rut then "rut" else "flat"
end

-- Live segments now.
function GroundMarks.LiveCount(self: GroundMarks): number
	local n = 0
	for g = 1, self.total do
		if self.live[g] then
			n += 1
		end
	end
	return n
end

-- A slot as drawn, for the tests: per section and profile point (index sec * P + j), its
-- world point, normal and colour; and how much of the mark shows at each end.
function GroundMarks.DebugSlot(self: GroundMarks, g: number)
	local ch = chunkOf(self, g)
	local P = self.P
	local pts, nrm, col = {}, {}, {}
	for sec = 0, 1 do
		for j = 1, P do
			-- every point is in the inner layer but the edges, which are in the outer one
			local li = if j == 1 or j == P then 1 else 2
			local layer = self.layers[li]
			local k = (g - 1) * 2 * layer.n + sec * layer.n + layer.at[j]
			local em = ch.ems[li]
			pts[sec * P + j] = em:GetPosition(layer.vids[k]) + ch.origin
			nrm[sec * P + j] = em:GetNormal(layer.nids[k])
			col[sec * P + j] = em:GetColor(layer.cids[k])
		end
	end
	local al = math.max(self.level[g], 0)
	return {
		live = self.live[g],
		head = self.isHead[g],
		born = self.born[g],
		points = pts,
		normals = nrm,
		colours = col,
		showing = { GroundMarks.showing(self, self.d0[g], self.s0[g], al), GroundMarks.showing(self, self.d1[g], self.s1[g], al) },
	}
end

function GroundMarks.DebugState(self: GroundMarks)
	local kinds = {}
	for i, r in self.wheels do
		kinds[i] = { kind = GroundMarks.Kind(self, i), depth = r.depth, ratio = r.ratio, snapped = r.snapped, head = r.head }
	end
	return {
		ready = self.ready,
		failed = self.failed,
		chunks = #self.chunks,
		slots = self.total,
		live = if self.ready then GroundMarks.LiveCount(self) else 0,
		segments = self.segments,
		recycled = self.recycled,
		lookups = self.lookups,
		life = self.life,
		wheels = kinds,
	}
end

return GroundMarks
