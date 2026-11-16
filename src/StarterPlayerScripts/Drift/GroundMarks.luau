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
--     mark fades in), square to the bisector of the path either side (a mitred joint), so a
--     curve is a curve. The newest section follows the tyre every frame: nothing lags or steps.
--   * A SHAPED PROFILE across it (`Grass.Profile`): an edge, a raised berm, a floor, with the
--     wall between leaning in. Its NORMALS lean with it and the parts are lit by the scene, so
--     one wall catches the sun, the moon or the headlights and the other falls into shade. The
--     drawn ground cannot be cut, but that light is what the eye reads as depth.
--   * IT BLENDS INTO THE GROUND ITSELF, not by see-through. In Roblox neither a vertex
--     colour's alpha nor a MeshPart texture's alpha is see-through -- both show the part's own
--     colour (measured, DR-Lane3: white streaks and white bands) -- and a SurfaceAppearance,
--     which is, cannot be set from a game script (measured). So the ribbon is opaque, and its
--     OUTER strips are drawn exactly as the ground under them is: the same `Grass` material on
--     the same world UVs, the ground's own vertex colour and normal at the edge (read off the
--     drawn tile), blending into the mark toward the berm. An edge that is the ground is an
--     edge you cannot see.
--   * The INNER strips (berm, walls, floor) are `Ribbon.InnerMaterial` (soil) with a streak
--     texture made here in code (an `EditableImage`, nothing uploaded), tinted by the vertex
--     colours.
--   * HOW MUCH OF THE MARK SHOWS is a per-vertex blend of the ground's colour and normal and
--     the mark's: it comes in over a mark's first studs, goes out at its end, is fainter for the
--     flattened-grass look than for a rut, and fades back into the ground with age while the
--     mud dries, rewritten in `AgeLevels` steps.
--   * ON THE DRAWN GROUND: each section's outer points and centre are put on the ground mesh
--     (`GroundMeshView._drawnAt`), the rest on the lines between.
--
-- ------------------------------------------------------------------ the mesh budget
--
-- A client holds only so many EditableMesh vertices -- about 35 000 to 40 000, the ground and
-- the road's chunks already most of them (features/ground-trial.md "The mesh budget"). A first
-- build of this ribbon held 31 000 and pushed the road out of budget (measured: "out of mesh
-- budget" from SplineRoadView). So each wheel is ONE STRIP: a ring of `Ribbon.Sections`
-- cross-sections whose vertices are shared by the segment either side, in two MeshParts (the
-- outer strips and the inner ones). About 4 000 vertices for all four wheels.
--
-- A strip joins EVERY section to the next, so what must not show is made of POINTS: a section
-- collapsed to one point draws nothing to a point beside it, and only a sliver to a section
-- whose centre it sits on. So the ring always keeps, ahead of the tyre, a point on the tyre's
-- section and a point on the oldest section's centre; a mark's end and the next mark's start
-- are each capped with a point the same way; and a section that ages out becomes a point on
-- the next one's centre. Nothing is ever stretched from one mark to another.
--
-- Built ONCE (making a mesh yields, so in its own thread) and only rewritten in place:
-- SetPosition / SetNormal / SetColor / SetUV, about a tenth of a microsecond a call (measured).
-- The ids `Add...` returns are the fixed copy's own (measured), so they are kept as returned
-- (not by `GetColors` order, which also lists what `AddTriangle` makes for itself).
--
-- Nothing here reads the car. Every input is a plain value from `Drift/Wheels`.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GroundMarks = {}
GroundMarks.__index = GroundMarks

local HALF = 2048 -- studs: a strip's local box either way of its origin; float32 is 0.0002 here
local MARKER = 0.01 -- studs: the two tiny triangles that hold the box open
local DEPTH_LEVELS = 8 -- the flat-to-rut blend, in steps, for the colour table

-- One of a strip's two meshes: which profile points it carries, and the quads between them.
type Layer = {
	name: string,
	points: { number }, -- profile point indices, left to right
	strips: { { number } }, -- pairs of indices into `points`
	n: number, -- #points
	textured: boolean, -- the inner layer: streak texture, UVs across and along the mark
}

-- A section of a wheel's ring.
type Section = {
	real: boolean, -- a cross-section of a mark (false: a point, drawing nothing)
	born: number,
	level: number, -- the age step it was last painted at
	d: number, -- blend, 0 flat .. 1 rut
	s: number, -- strength, 0..1 (the soft ends)
	v: number, -- texture v
	centre: Vector3,
	pts: { Vector3 }, -- world, per profile point
	gc: { Color3 }, -- the ground's colour under each point
}

type Strip = {
	origin: Vector3,
	ems: { EditableMesh }, -- per layer
	parts: { MeshPart },
	-- ids, per layer: [(k - 1) * n + index], k the section
	vids: { { number } },
	cids: { { number } },
	nids: { { number } },
	uids: { { number } },
	sections: { Section },
	tip: number, -- the section following the tyre (or where the last mark ended)
	-- the mark being laid
	on: boolean,
	first: boolean, -- no segment yet: the first section still faces where it was guessed
	lastPos: Vector3, -- the last fixed section's centre
	prevDir: Vector3?,
	dist: number, -- studs along this mark to the last fixed section
	depth: number,
	ratio: number,
	rut: boolean,
	snapped: number,
	lastV: number,
}

export type GroundMarks = typeof(setmetatable(
	{} :: {
		ready: boolean,
		failed: string?,
		folder: Folder?,
		image: EditableImage?,
		layers: { Layer },
		strips: { Strip },
		P: number, -- points across a section
		N: number, -- sections a wheel
		clock: number,
		life: number,
		scratchPts: { Vector3 },
		scratchNrm: { Vector3 },
		scratchGC: { Color3 },
		lutC: { Color3 }, -- [(h-1)*(DL+1)*AL + dl*AL + al + 1]: the mark's own colour
		fadeAt: { number }, -- per age step: how much of the mark is left
		offsets: { number }, -- per point, signed share of the half-width, -1..1
		heights: { { number } }, -- per point: flat, rut
		tilts: { { number } },
		weights: { number }, -- per point: how much it is the mark rather than the ground
		us: { number },
		sectionsLaid: number,
		recycled: number, -- live sections thrown away early to make room
		lookups: number,
		reorigins: number,
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

local function makeLayer(name: string, points: { number }, textured: boolean): Layer
	local strips = {}
	for i = 1, #points - 1 do
		-- only between neighbours in the profile (the outer layer has a gap in the middle)
		if points[i + 1] == points[i] + 1 then
			table.insert(strips, { i, i + 1 })
		end
	end
	return { name = name, points = points, strips = strips, n = #points, textured = textured }
end

local function newSection(P: number, grass: Color3): Section
	return {
		real = false,
		born = 0,
		level = -1,
		d = 0,
		s = 0,
		v = 0,
		centre = Vector3.zero,
		pts = table.create(P, Vector3.zero),
		gc = table.create(P, grass),
	}
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
			makeLayer("Outer", { 1, 2, P - 1, P }, false),
			-- the berm, walls and floor between: the mark itself
			makeLayer("Inner", inner, true),
		},
		strips = {},
		P = P,
		N = R.Sections,
		clock = 0,
		life = G.MarkSeconds,
		scratchPts = table.create(P, Vector3.zero),
		scratchNrm = table.create(P, Vector3.yAxis),
		scratchGC = table.create(P, Color3.new()),
		lutC = {},
		fadeAt = {},
		offsets = table.create(P, 0),
		heights = {},
		tilts = {},
		weights = table.create(P, 0),
		us = table.create(P, 0),
		sectionsLaid = 0,
		recycled = 0,
		lookups = 0,
		reorigins = 0,
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
	return self
end

-- The mark's own colour at every profile point, blend step and age step, and how much of the
-- mark is left at every age step, so painting a section is lookups.
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

-- One layer's ring: N sections of the layer's points, each joined to the next (the last to
-- the first), and two specks at opposite corners that hold the box open at +-HALF so the
-- MeshPart is made at scale 1.
local function makeTemplate(layer: Layer, N: number, vids: { number }, cids: { number }, nids: { number }, uids: { number }): EditableMesh
	local em = AssetService:CreateEditableMesh({ FixedSize = false })
	assert(em, "no EditableMesh")
	local n = layer.n
	for k = 1, N * n do
		vids[k] = em:AddVertex(Vector3.zero)
		cids[k] = em:AddColor(Color3.new(1, 1, 1), 1)
		nids[k] = em:AddNormal(Vector3.yAxis)
		uids[k] = em:AddUV(Vector2.zero)
	end
	-- Section k is behind section k + 1. Wound so `(c - a) x (b - a)` points up: a ahead-left,
	-- c behind-left, b ahead-right.
	for k = 1, N do
		local behind, ahead = (k - 1) * n, (k % N) * n
		for _, strip in layer.strips do
			local a, b, c, d = ahead + strip[1], ahead + strip[2], behind + strip[1], behind + strip[2]
			for _, t in { { a, c, b }, { b, c, d } } do
				local f = em:AddTriangle(vids[t[1]], vids[t[2]], vids[t[3]])
				em:SetFaceColors(f, { cids[t[1]], cids[t[2]], cids[t[3]] })
				em:SetFaceNormals(f, { nids[t[1]], nids[t[2]], nids[t[3]] })
				em:SetFaceUVs(f, { uids[t[1]], uids[t[2]], uids[t[3]] })
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

local function resetStrip(self: GroundMarks, st: Strip)
	st.tip = 1
	st.on = false
	st.first = false
	st.prevDir = nil
	st.dist = 0
	st.depth = 0
	st.ratio = 1
	st.rut = false
	st.snapped = 0
	st.lastV = 0
	st.lastPos = Vector3.zero
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
		local grass = Config.Spline.Terrain.GrassColour
		for wi = 1, R.Wheels do
			local st: Strip = {
				origin = Vector3.zero,
				ems = {},
				parts = {},
				vids = {},
				cids = {},
				nids = {},
				uids = {},
				sections = {},
				tip = 1,
				on = false,
				first = false,
				lastPos = Vector3.zero,
				prevDir = nil,
				dist = 0,
				depth = 0,
				ratio = 1,
				rut = false,
				snapped = 0,
				lastV = 0,
			}
			for li, layer in self.layers do
				local v, c, n, u = {}, {}, {}, {}
				local template = makeTemplate(layer, self.N, v, c, n, u)
				local em = AssetService:CreateEditableMeshAsync(Content.fromObject(template), { FixedSize = true })
				template:Destroy()
				assert(em, "no fixed copy")
				local part = AssetService:CreateMeshPartAsync(Content.fromObject(em), {
					CollisionFidelity = Enum.CollisionFidelity.Box,
					RenderFidelity = Enum.RenderFidelity.Precise,
				})
				assert(part, "no MeshPart")
				part.Name = string.format(Config.Fx.Names.MarksChunk, wi) .. layer.name
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
				st.ems[li], st.parts[li] = em, part
				st.vids[li], st.cids[li], st.nids[li], st.uids[li] = v, c, n, u
			end
			for k = 1, self.N do
				st.sections[k] = newSection(self.P, grass)
			end
			table.insert(self.strips, st)
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
	for _, st in self.strips do
		for li = 1, #st.parts do
			st.parts[li]:Destroy()
			st.ems[li]:Destroy()
		end
	end
	table.clear(self.strips)
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
-- Sections
--------------------------------------------------------------------------------

local function wrap(self: GroundMarks, k: number): number
	return (k - 1) % self.N + 1
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

-- Write section `k` of strip `st` from its `Section`: every layer's points, and, unless
-- `colourOnly`... always its colours too. Normals and UVs come from `nrm` when given.
local function writeSection(self: GroundMarks, st: Strip, k: number, nrm: { Vector3 }?)
	local sec = st.sections[k]
	local origin = st.origin
	local uvStuds = Config.Spline.Ground.UVStuds
	local al = math.max(sec.level, 0)
	local show = if sec.real then GroundMarks.showing(self, sec.d, sec.s, al) else 0
	for li, layer in self.layers do
		local em = st.ems[li]
		local n = layer.n
		local base = (k - 1) * n
		local vids, cids, nids, uids = st.vids[li], st.cids[li], st.nids[li], st.uids[li]
		for i, j in layer.points do
			local id = base + i
			local p = sec.pts[j]
			em:SetPosition(vids[id], p - origin)
			if nrm then
				em:SetNormal(nids[id], nrm[j])
				-- The inner strips: across and along the mark, for the streaks. The outer ones:
				-- the ground's own world mapping, so its material lines up with the ground's.
				em:SetUV(uids[id], if layer.textured then Vector2.new(self.us[j], sec.v) else Vector2.new(p.X / uvStuds, p.Z / uvStuds))
			end
			if sec.real then
				em:SetColor(cids[id], sec.gc[j]:Lerp(lut(self, j, sec.d, al), self.weights[j] * show))
			end
		end
	end
end

-- Recolour section `k` for its age step (its points and normals stay).
local function paint(self: GroundMarks, st: Strip, k: number)
	local sec = st.sections[k]
	if not sec.real then
		return
	end
	local al = math.max(sec.level, 0)
	local show = GroundMarks.showing(self, sec.d, sec.s, al)
	for li, layer in self.layers do
		local em = st.ems[li]
		local base = (k - 1) * layer.n
		local cids = st.cids[li]
		for i, j in layer.points do
			em:SetColor(cids[base + i], sec.gc[j]:Lerp(lut(self, j, sec.d, al), self.weights[j] * show))
		end
	end
end

-- Collapse section `k` to one point at `at`: it draws nothing next to another point, and only
-- a sliver next to a section whose centre `at` is.
local function point(self: GroundMarks, st: Strip, k: number, at: Vector3)
	local sec = st.sections[k]
	if sec.real then
		sec.real = false
	end
	sec.centre = at
	for j = 1, self.P do
		sec.pts[j] = at
	end
	writeSection(self, st, k, nil)
end

-- Put the strip's origin at `at` when a section would be too far from it, rewriting every
-- section where it was (they are kept in world space).
local function reach(self: GroundMarks, st: Strip, at: Vector3)
	local off = at - st.origin
	if math.max(math.abs(off.X), math.abs(off.Y), math.abs(off.Z)) <= Config.Fx.Ground.Ribbon.ReOrigin then
		return
	end
	st.origin = at
	for _, part in st.parts do
		part.CFrame = CFrame.new(at)
	end
	self.reorigins += 1
	for k = 1, self.N do
		local sec = st.sections[k]
		for li, layer in self.layers do
			local em = st.ems[li]
			local base = (k - 1) * layer.n
			for i, j in layer.points do
				em:SetPosition(st.vids[li][base + i], sec.pts[j] - at)
			end
		end
	end
end

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
	end
	return found
end

-- Section `k` becomes a real cross-section from the scratch arrays.
-- `evict`: it may be an old mark's, thrown away early to make room (counted).
local function place(self: GroundMarks, st: Strip, k: number, d: number, s: number, v: number, evict: boolean?)
	local sec = st.sections[k]
	if evict and sec.real then
		self.recycled += 1
	end
	sec.real = true
	sec.born = self.clock
	sec.level = 0
	-- Its centre is the middle of its own edge points, on the ground: where a point beside it
	-- must sit to draw only a sliver (not the tyre's contact, which rides higher).
	sec.d, sec.s, sec.v, sec.centre = d, s, v, (self.scratchPts[1] + self.scratchPts[self.P]) * 0.5
	for j = 1, self.P do
		sec.pts[j] = self.scratchPts[j]
		sec.gc[j] = self.scratchGC[j]
	end
	writeSection(self, st, k, self.scratchNrm)
end

-- Keep the two points ahead of the tip: one on the tip's centre, one on the centre of the
-- section after them (the oldest), so the tip is never joined to an old mark.
local function guard(self: GroundMarks, st: Strip)
	local a, b, c = wrap(self, st.tip + 1), wrap(self, st.tip + 2), wrap(self, st.tip + 3)
	point(self, st, a, st.sections[st.tip].centre)
	if st.sections[b].real then
		self.recycled += 1
	end
	point(self, st, b, st.sections[c].centre)
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

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
	local st = self.strips[i]
	if not self.ready or not st then
		return
	end
	if not on then
		if st.on then
			-- The mark ends where the tyre is, fading out into the ground there.
			st.on = false
			local tip = st.sections[st.tip]
			if tip.real then
				tip.s = 0
				tip.born = self.clock
				paint(self, st, st.tip)
			end
		end
		st.snapped = 0
		return
	end
	local G = Config.Fx.Ground
	local R = G.Ribbon
	st.rut = rut
	local hw = G.Grass.Width * 0.5
	if not st.on then
		-- A new mark. Past the old tip and its point: a point on this mark's start, then its
		-- first section (fixed, at nothing), then the tip that follows the tyre.
		st.on = true
		st.first = true
		st.prevDir = nil
		st.dist = 0
		st.depth = if rut then 1 else 0
		st.ratio = math.max(ratio, G.Grass.MinWidthRatio)
		reach(self, st, contact)
		local tangent = up:Cross(across)
		tangent = if tangent.Magnitude > 1e-4 then tangent.Unit else Vector3.zAxis
		st.snapped = section(self, contact, tangent, up, hw * st.ratio, st.depth, 0, ground)
		local start = wrap(self, st.tip + 2)
		local first = wrap(self, st.tip + 3)
		st.lastV = (i - 1) * 0.37
		place(self, st, first, st.depth, 0, st.lastV, true)
		point(self, st, start, st.sections[first].centre)
		st.tip = wrap(self, first + 1)
		place(self, st, st.tip, st.depth, 0, st.lastV, true)
		guard(self, st)
		st.lastPos = contact
		self.sectionsLaid += 2
		return
	end
	-- Ease the blend and the width, so neither ever steps.
	local target = if rut then 1 else 0
	local blend = dt / math.max(R.BlendSeconds, 1e-4)
	st.depth = if st.depth < target then math.min(st.depth + blend, target) else math.max(st.depth - blend, target)
	st.ratio += (math.max(ratio, G.Grass.MinWidthRatio) - st.ratio) * (1 - math.exp(-dt / math.max(R.WidthSeconds, 1e-4)))

	local chord = contact - st.lastPos
	chord -= up * chord:Dot(up)
	local len = chord.Magnitude
	if len < 0.05 then
		return
	end
	local dir = chord / len
	reach(self, st, contact)
	if st.first then
		-- The mark's first segment: square its first section to where it actually went,
		-- not to the guess it started with, so the ribbon cannot twist.
		local firstK = wrap(self, st.tip - 1)
		local fs = st.sections[firstK]
		section(self, st.lastPos, dir, up, hw * st.ratio, fs.d, 0, ground)
		place(self, st, firstK, fs.d, 0, fs.v)
	end
	-- Square to the bisector of this segment and the last: a mitred joint, no kink.
	local tangent = dir
	if st.prevDir then
		local bis = dir + (st.prevDir :: Vector3)
		if bis.Magnitude > 1e-3 then
			tangent = bis.Unit
		end
	end
	local strength = math.clamp((st.dist + len) / math.max(R.FadeInStuds, 1e-4), 0, 1)
	st.snapped = section(self, contact, tangent, up, hw * st.ratio, st.depth, strength, ground)
	local v = st.lastV + len / math.max(R.TileLength, 1e-4)
	place(self, st, st.tip, st.depth, strength, v)
	point(self, st, wrap(self, st.tip + 1), st.sections[st.tip].centre)

	-- Commit: the tip is fixed, and a new tip follows the tyre from it. Short segments while
	-- the mark comes in, so it comes in smoothly.
	local turned = if st.prevDir then math.deg(math.acos(math.clamp(dir:Dot(st.prevDir :: Vector3), -1, 1))) else 0
	local spacing = if st.dist < R.FadeInStuds then R.MinSpacing else R.Spacing
	if len >= spacing or (len >= R.MinSpacing and turned >= R.TurnDegrees) then
		st.first = false
		st.tip = wrap(self, st.tip + 1)
		place(self, st, st.tip, st.depth, strength, v)
		guard(self, st)
		st.lastPos, st.lastV = contact, v
		st.dist += len
		st.prevDir = dir
		self.sectionsLaid += 1
	end
end

-- Once a frame, after the wheels: the clock moves on, and every laid section dries and fades
-- into the ground a step whenever its age crosses one, and goes when its life is up (a point
-- on the next section's centre).
function GroundMarks.Age(self: GroundMarks, dt: number)
	if not self.ready then
		return
	end
	self.clock += dt
	local AL = Config.Fx.Ground.Ribbon.AgeLevels
	local life = math.max(self.life, 1e-3)
	for _, st in self.strips do
		for k = 1, self.N do
			local sec = st.sections[k]
			if sec.real and not (st.on and (k == st.tip or k == wrap(self, st.tip - 1) and st.first)) then
				local age = self.clock - sec.born
				if age >= life then
					point(self, st, k, st.sections[wrap(self, k + 1)].centre)
				else
					local al = math.floor(age / life * AL)
					if al ~= sec.level then
						sec.level = al
						paint(self, st, k)
					end
				end
			end
		end
	end
end

-- Every wheel's mark ends where it is, with no fade: the car has jumped (spawn, respawn,
-- teleport), and the next mark must not join across the jump.
function GroundMarks.Cut(self: GroundMarks)
	for _, st in self.strips do
		st.on = false
		st.first = false
		st.snapped = 0
	end
end

-- Every mark gone, at once.
function GroundMarks.Clear(self: GroundMarks)
	for _, st in self.strips do
		for k = 1, self.N do
			point(self, st, k, st.origin)
		end
		resetStrip(self, st)
		st.lastPos = st.origin
	end
end

-- How long a mark lasts from now on.
function GroundMarks.SetLife(self: GroundMarks, seconds: number)
	self.life = seconds
end

-- What wheel `i` is laying: "rut", "flat" or nil.
function GroundMarks.Kind(self: GroundMarks, i: number): string?
	local st = self.strips[i]
	if not st or not st.on then
		return nil
	end
	return if st.rut then "rut" else "flat"
end

-- Real (drawn) sections now, all wheels.
function GroundMarks.LiveCount(self: GroundMarks): number
	local n = 0
	for _, st in self.strips do
		for _, sec in st.sections do
			if sec.real then
				n += 1
			end
		end
	end
	return n
end

-- Wheel `i`'s strip as drawn, for the tests: every section in ring order from the oldest
-- (just past the tip's guard points), each with its world points, normals and colours read
-- back off the mesh, whether it is real, and how much of the mark it shows.
function GroundMarks.DebugStrip(self: GroundMarks, i: number)
	local st = self.strips[i]
	local out = {}
	local P = self.P
	for step = 1, self.N do
		local k = wrap(self, st.tip + step)
		local sec = st.sections[k]
		local pts, nrm, col = {}, {}, {}
		for j = 1, P do
			-- every point is in the inner layer but the edges, which are in the outer one
			local li = if j == 1 or j == P then 1 else 2
			local layer = self.layers[li]
			local idx = table.find(layer.points, j) :: number
			local id = (k - 1) * layer.n + idx
			local em = st.ems[li]
			pts[j] = em:GetPosition(st.vids[li][id]) + st.origin
			nrm[j] = em:GetNormal(st.nids[li][id])
			col[j] = em:GetColor(st.cids[li][id])
		end
		table.insert(out, {
			k = k,
			real = sec.real,
			tip = k == st.tip,
			points = pts,
			normals = nrm,
			colours = col,
			showing = if sec.real then GroundMarks.showing(self, sec.d, sec.s, math.max(sec.level, 0)) else 0,
		})
	end
	return out
end

function GroundMarks.DebugState(self: GroundMarks)
	local kinds = {}
	for i, st in self.strips do
		kinds[i] = { kind = GroundMarks.Kind(self, i), depth = st.depth, ratio = st.ratio, snapped = st.snapped, tip = st.tip }
	end
	local vertices = 0
	for _, layer in self.layers do
		vertices += layer.n * self.N + 6
	end
	return {
		ready = self.ready,
		failed = self.failed,
		strips = #self.strips,
		sections = self.N,
		vertices = vertices * #self.strips, -- mesh vertices held, against the client's budget
		live = if self.ready then GroundMarks.LiveCount(self) else 0,
		laid = self.sectionsLaid,
		recycled = self.recycled,
		lookups = self.lookups,
		reorigins = self.reorigins,
		life = self.life,
		wheels = kinds,
	}
end

return GroundMarks
