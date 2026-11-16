--!strict
-- GroundMarks: the grass and mud marks as a mesh ribbon laid on the ground, one per wheel
-- (T-265, features/car-fx.md "Ruts cut into the ground"). `Drift/Wheels` decides WHEN a wheel
-- marks grass and which look; this module draws it.
--
-- ------------------------------------------------------------------ why a mesh, not a Trail
--
-- The user, of the trail-built ruts: *"this just looks kinda cheap ... research methods for
-- realism looking tire marks, not cheap roblox stuff."* A `Trail` lays a flat, unlit quad a
-- frame, between two points: hard edges, a kink wherever a frame's points jump, a colour that
-- ignores the scene's light (black bands at night), and nothing across its width. Racing
-- games draw skid marks as a ribbon MESH on the ground instead, and so does this:
--
--   * A CROSS-SECTION every few studs (`Ribbon.Spacing`, sooner through a bend), joined to the
--     last by a segment of quads. Each section is square to the path's bisector, so a curve
--     is a curve, and the newest segment follows the tyre every frame, so a mark never lags.
--   * A SHAPED PROFILE across it (`Grass.Profile`): an edge that fades to nothing, a berm,
--     a wall leaning in, a floor. Its NORMALS lean with it, and the MeshPart is lit by the
--     scene, so one wall catches the sun (or the moon, or the headlights) and the other is in
--     shade. That is the depth: the drawn ground cannot be cut, but the eye reads the light.
--   * A STREAK TEXTURE made here in code (`EditableImage`, nothing uploaded): tread lines
--     along the travel, flecks and clods toward the edges, a ragged soft alpha edge. Grey,
--     multiplied by the vertex colours, so the same texture serves grass and mud.
--   * VERTEX COLOUR per section: the flattened-grass look blends into the rut look, and the
--     colour dries with age. OPACITY comes from the TEXTURE, not the vertices: Roblox draws a
--     vertex colour's alpha as a blend toward white, not as see-through (measured: the first
--     build's fade-ins came out as white streaks). So the texture is an ATLAS of
--     `Texture.Levels` copies of the streak tile side by side, each fainter than the last, and
--     a segment picks its opacity by which copy its UVs point at: it fades in over a mark's
--     first studs, out over its last segment, and out with age, in `AgeLevels` steps.
--   * ON THE DRAWN GROUND: each section's outer points and centre are put on the ground mesh
--     (`GroundMeshView._drawnAt`, `Wheels.onGround`), the rest on the lines between.
--
-- ------------------------------------------------------------------ what it is made of
--
-- `Ribbon.Chunks` MeshParts, each an `EditableMesh` of `PerChunk` SEGMENT SLOTS: 2 sections
-- x 8 profile points, 14 triangles. Built ONCE (it yields, so in its own thread) and only
-- ever rewritten in place: SetPosition / SetNormal / SetColor / SetUV, about a tenth of a
-- microsecond a call (measured). A dead slot is collapsed to a point. Slots are handed out in
-- a ring, so the oldest is reused first; a chunk is started at the car and takes segments
-- within `ChunkReach` of there, so its local coordinates stay small.
--
-- The vertex, face and attribute ids of the copy `CreateEditableMeshAsync` makes are the
-- template's own (measured, DR-Lane2), so the template's ids are kept and used directly.
--
-- Nothing here reads the car. Every input is a plain value from `Drift/Wheels`.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GroundMarks = {}
GroundMarks.__index = GroundMarks

local HALF = 512 -- studs: a chunk's local box, either way of its origin
local MARKER = 0.01 -- studs: the two tiny invisible triangles that hold the box open
local DEPTH_LEVELS = 8 -- the flat-to-rut blend, in steps, for the colour tables

type Chunk = {
	em: EditableMesh,
	part: MeshPart,
	origin: Vector3,
}

type Ribbon = {
	on: boolean,
	head: number?, -- the slot being drawn to the tyre, nil between sections
	lastSlot: number?, -- the last segment committed, which a mark ending just after fades
	lastPos: Vector3, -- the last committed section's centre, world
	lastPts: { Vector3 }, -- its points and normals, world
	lastNrm: { Vector3 },
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
		surface: string, -- how the texture is put on: "SurfaceAppearance" (see-through) or
		-- "TextureContent" (a fallback: Roblox shows the part's colour where a MeshPart
		-- texture is clear, so its soft edges and fades would show white)
		folder: Folder?,
		image: EditableImage?,
		chunks: { Chunk },
		P: number, -- points across a section
		perChunk: number,
		total: number,
		-- per slot, 1..total
		vids: { number }, -- (slot-1)*2P + k: vertex, colour, normal, uv ids
		cids: { number },
		nids: { number },
		uids: { number },
		live: { boolean },
		born: { number },
		level: { number },
		isHead: { boolean },
		d0: { number },
		d1: { number },
		s0: { number },
		s1: { number },
		cursor: number, -- the next slot in the current chunk
		current: number, -- the current chunk
		clock: number,
		life: number,
		wheels: { Ribbon },
		scratchPts: { Vector3 },
		scratchNrm: { Vector3 },
		lutC: { Color3 }, -- [(h-1)*(DL+1)*AL + dl*AL + al + 1]
		fadeAt: { number }, -- per age step, 0..1: how much of a segment's opacity is left
		v0: { number }, -- per slot: texture v at its two sections
		v1: { number },
		offsets: { number }, -- per point, signed share of the half-width, -1..1
		heights: { { number } }, -- per point: flat, rut
		tilts: { { number } },
		us: { number },
		-- what it has done, for `DebugState`
		segments: number,
		recycled: number, -- live segments thrown away early to make room
		lookups: number,
	},
	GroundMarks
))

local function smooth01(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

--------------------------------------------------------------------------------
-- The texture, pure
--------------------------------------------------------------------------------

-- The streak texture's pixels: a buffer of `Width x Height` RGBA bytes, rows along the mark
-- (v) and columns across it (u). Repeats seamlessly along v. Deterministic from `Seed`.
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
	-- The ragged edge: how far in each side's fade starts, wandering along v.
	local edgeL, edgeR = table.create(H, 0), table.create(H, 0)
	local pL1, pL2, pR1, pR2 = rng:NextNumber() * 6.3, rng:NextNumber() * 6.3, rng:NextNumber() * 6.3, rng:NextNumber() * 6.3
	for y = 1, H do
		local t = (y - 1) / H * math.pi * 2
		edgeL[y] = T.EdgeRagged * (0.5 + 0.3 * math.sin(t * 3 + pL1) + 0.2 * math.sin(t * 7 + pL2))
		edgeR[y] = T.EdgeRagged * (0.5 + 0.3 * math.sin(t * 2 + pR1) + 0.2 * math.sin(t * 9 + pR2))
	end
	for y = 1, H do
		local t = (y - 1) / H * math.pi * 2
		for x = 1, W do
			local u = (x - 0.5) / W
			local wobble = 1 - T.StreakWobble * (0.5 + 0.5 * math.sin(t * freq[x] + phase[x]))
			local value = T.Base - T.StreakDepth * streak[x] * wobble
			local fromL = (u - edgeL[y]) / T.EdgeSoft
			local fromR = ((1 - u) - edgeR[y]) / T.EdgeSoft
			local alpha = smooth01(math.min(fromL, fromR))
			local o = ((y - 1) * W + (x - 1)) * 4
			local g = math.clamp(math.floor(value * 255 + 0.5), 0, 255)
			buffer.writeu8(buf, o, g)
			buffer.writeu8(buf, o + 1, g)
			buffer.writeu8(buf, o + 2, g)
			buffer.writeu8(buf, o + 3, math.clamp(math.floor(alpha * 255 + 0.5), 0, 255))
		end
	end
	-- Flecks and clods: 1 to 3 pixel blots, mostly in the bands near the edges, light (a dry
	-- clod in the sun) or dark (a wet one). Solid where they land inside the mark.
	for _ = 1, T.Flecks do
		local band = rng:NextNumber() * T.FleckBand
		local u = if rng:NextNumber() < 0.5 then band else 1 - band
		if rng:NextNumber() < 0.25 then
			u = rng:NextNumber() -- some anywhere
		end
		local cx = math.clamp(math.floor(u * W), 0, W - 1)
		local cy = rng:NextInteger(0, H - 1)
		local size = rng:NextInteger(1, 3)
		local g = math.floor((if rng:NextNumber() < 0.6 then T.FleckLight else T.FleckDark) * 255 + 0.5)
		for dy = 0, size - 1 do
			for dx = 0, size - 1 do
				local px = cx + dx
				if px < W then
					local py = (cy + dy) % H
					local o = (py * W + px) * 4
					if buffer.readu8(buf, o + 3) > 40 then
						buffer.writeu8(buf, o, g)
						buffer.writeu8(buf, o + 1, g)
						buffer.writeu8(buf, o + 2, g)
						buffer.writeu8(buf, o + 3, 255)
					end
				end
			end
		end
	end
	return buf
end

-- The atlas the ribbon is drawn with: `Levels` copies of the tile side by side, copy `c`
-- (0-based) at `c / (Levels - 1)` of the tile's opacity, so the first is clear and the last
-- solid. `(Width * Levels) x Height` RGBA bytes.
function GroundMarks.atlasPixels(T: any): buffer
	local W, H, K = T.Width, T.Height, T.Levels
	local tile = GroundMarks.texturePixels(T)
	local out = buffer.create(W * K * H * 4)
	for c = 0, K - 1 do
		local opacity = c / math.max(K - 1, 1)
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				local i = (y * W + x) * 4
				local o = (y * W * K + c * W + x) * 4
				buffer.writeu8(out, o, buffer.readu8(tile, i))
				buffer.writeu8(out, o + 1, buffer.readu8(tile, i + 1))
				buffer.writeu8(out, o + 2, buffer.readu8(tile, i + 2))
				buffer.writeu8(out, o + 3, math.floor(buffer.readu8(tile, i + 3) * opacity + 0.5))
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- A ribbon with nothing built yet. `Build` makes the meshes (it yields).
function GroundMarks.new(): GroundMarks
	local G = Config.Fx.Ground
	local R = G.Ribbon
	local profile = G.Grass.Profile
	local half = #profile
	local P = half * 2
	local self = setmetatable({
		ready = false,
		failed = nil,
		surface = "none",
		folder = nil,
		image = nil,
		chunks = {},
		P = P,
		perChunk = R.PerChunk,
		total = R.Chunks * R.PerChunk,
		vids = {},
		cids = {},
		nids = {},
		uids = {},
		live = {},
		born = {},
		level = {},
		isHead = {},
		d0 = {},
		d1 = {},
		s0 = {},
		s1 = {},
		cursor = 1,
		current = 1,
		clock = 0,
		life = G.MarkSeconds,
		wheels = {},
		scratchPts = table.create(P, Vector3.zero),
		scratchNrm = table.create(P, Vector3.yAxis),
		lutC = {},
		fadeAt = {},
		v0 = {},
		v1 = {},
		offsets = table.create(P, 0),
		heights = {},
		tilts = {},
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

-- The colour of every profile point at every blend step and every age step, and how much
-- opacity is left at every age step, so rewriting a slot as it ages is table lookups and no
-- `Color3` made.
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
				local k = (h - 1) * (DEPTH_LEVELS + 1) * AL + dl * AL + al + 1
				self.lutC[k] = wet:Lerp(dry, (al + 0.5) / AL)
			end
		end
	end
end

-- The ids each `Add` returns are written into `self`'s id lists from `base`: kept as they
-- come back, because `GetColors` and the like also list attributes `AddTriangle` makes for
-- itself, so their order is not ours (measured: painting by that order left slots white).
local function makeTemplate(self: GroundMarks, slots: number, P: number, base: number): EditableMesh
	local em = AssetService:CreateEditableMesh({ FixedSize = false })
	assert(em, "no EditableMesh")
	for slot = 1, slots do
		local v, c, n, u = table.create(2 * P, 0), table.create(2 * P, 0), table.create(2 * P, 0), table.create(2 * P, 0)
		for k = 1, 2 * P do
			v[k] = em:AddVertex(Vector3.zero)
			c[k] = em:AddColor(Color3.new(1, 1, 1), 1)
			n[k] = em:AddNormal(Vector3.yAxis)
			u[k] = em:AddUV(Vector2.zero)
			local at = base + (slot - 1) * 2 * P + k
			self.vids[at], self.cids[at], self.nids[at], self.uids[at] = v[k], c[k], n[k], u[k]
		end
		-- Section 0 (k = 1..P) is the start, behind; section 1 (P+1..2P) the end, ahead.
		-- Wound so `(c - a) x (b - a)` points up: a ahead-left, c behind-left, b ahead-right.
		for j = 1, P - 1 do
			local a, b, cc, d = P + j, P + j + 1, j, j + 1
			for _, t in { { a, cc, b }, { b, cc, d } } do
				local f = em:AddTriangle(v[t[1]], v[t[2]], v[t[3]])
				em:SetFaceColors(f, { c[t[1]], c[t[2]], c[t[3]] })
				em:SetFaceNormals(f, { n[t[1]], n[t[2]], n[t[3]] })
				em:SetFaceUVs(f, { u[t[1]], u[t[2]], u[t[3]] })
			end
		end
	end
	-- Two specks at opposite corners hold the mesh's box open at +-HALF, so the MeshPart is
	-- made at scale 1 and a vertex anywhere within HALF of the origin draws where it is put.
	for _, corner in { -HALF, HALF } do
		local p = Vector3.new(corner, corner, corner)
		local ids = {}
		for q = 0, 2 do
			ids[q + 1] = em:AddVertex(p + Vector3.new(if q == 1 then MARKER else 0, 0, if q == 2 then MARKER else 0))
		end
		local f = em:AddTriangle(ids[1], ids[2], ids[3])
		local clear = em:AddColor(Color3.new(1, 1, 1), 0)
		em:SetFaceColors(f, { clear, clear, clear })
	end
	return em
end

-- Make the meshes, the texture and the folder. YIELDS: call it in its own thread. Returns
-- whether it worked; `failed` says why not. `parent` is where the folder goes (Workspace in
-- play; the tests use ServerStorage).
function GroundMarks.Build(self: GroundMarks, parent: Instance?): boolean
	local ok, err = pcall(function()
		local R = Config.Fx.Ground.Ribbon
		local P = self.P
		local folder = Instance.new("Folder")
		folder.Name = Config.Fx.Names.MarksFolder
		local T = R.Texture
		local size = Vector2.new(T.Width * T.Levels, T.Height)
		local image = AssetService:CreateEditableImage({ Size = size })
		assert(image, "no EditableImage")
		image:WritePixelsBuffer(Vector2.zero, size, GroundMarks.atlasPixels(T))
		self.image = image
		for ci = 1, R.Chunks do
			-- The template's ids are the copy's too (measured), so they are kept as made.
			local template = makeTemplate(self, self.perChunk, P, (ci - 1) * self.perChunk * 2 * P)
			local em = AssetService:CreateEditableMeshAsync(Content.fromObject(template), { FixedSize = true })
			template:Destroy()
			assert(em, "no fixed copy")
			local part = AssetService:CreateMeshPartAsync(Content.fromObject(em), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Precise,
			})
			assert(part, "no MeshPart")
			part.Name = string.format(Config.Fx.Names.MarksChunk, ci)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = R.Material
			part.Color = Color3.new(1, 1, 1)
			part.Transparency = R.Transparency
			-- SEE-THROUGH NEEDS A SURFACEAPPEARANCE. Neither a vertex colour's alpha nor a
			-- MeshPart texture's alpha is drawn as see-through -- both show the part's own
			-- colour (measured: white streaks and bands, DR-Lane3) -- but a SurfaceAppearance
			-- in `AlphaMode.Transparency` is. Its colour map is the atlas.
			local okSA = pcall(function()
				local sa = Instance.new("SurfaceAppearance")
				sa.AlphaMode = Enum.AlphaMode.Transparency
				sa.ColorMapContent = Content.fromObject(image)
				sa.Parent = part
			end)
			if okSA then
				self.surface = "SurfaceAppearance"
			else
				for _, child in part:GetChildren() do
					child:Destroy()
				end
				part.TextureContent = Content.fromObject(image)
				self.surface = "TextureContent"
			end
			part.CFrame = CFrame.new(0, 0, 0)
			part.Parent = folder
			table.insert(self.chunks, { em = em, part = part, origin = Vector3.zero })
		end
		for g = 1, self.total do
			self.live[g] = false
			self.born[g] = 0
			self.level[g] = -1
			self.isHead[g] = false
			self.d0[g], self.d1[g], self.s0[g], self.s1[g] = 0, 0, 0, 0
			self.v0[g], self.v1[g] = 0, 0
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
		ch.part:Destroy()
		ch.em:Destroy()
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
	local em = chunkOf(self, g).em
	local base = (g - 1) * 2 * self.P
	for k = 1, 2 * self.P do
		em:SetPosition(self.vids[base + k], Vector3.zero)
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
		ch.part.CFrame = CFrame.new(at)
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

-- Which copy of the atlas slot `g` is drawn with at age step `al`: its strength (soft ends),
-- its look's opacity (a flattened line is fainter than a rut) and what age has left of it.
function GroundMarks.opacityLevel(self: GroundMarks, g: number, al: number): number
	local G = Config.Fx.Ground
	local K = G.Ribbon.Texture.Levels
	local d = (self.d0[g] + self.d1[g]) * 0.5
	local look = G.Grass.FlatMark.Opacity + (G.Grass.TrenchMark.Opacity - G.Grass.FlatMark.Opacity) * d
	local s = (self.s0[g] + self.s1[g]) * 0.5
	local fade = self.fadeAt[math.clamp(al, 0, G.Ribbon.AgeLevels - 1) + 1]
	return math.clamp(math.floor(s * look * fade * (K - 1) + 0.5), 0, K - 1)
end

-- Write one section of slot `g` (0 the start, 1 the end): its points and normals.
local function writeSection(self: GroundMarks, g: number, sec: number, pts: { Vector3 }, nrm: { Vector3 })
	local ch = chunkOf(self, g)
	local em, origin = ch.em, ch.origin
	local P = self.P
	local base = (g - 1) * 2 * P + sec * P
	for j = 1, P do
		local k = base + j
		em:SetPosition(self.vids[k], pts[j] - origin)
		em:SetNormal(self.nids[k], nrm[j])
	end
end

-- Paint slot `g` for age step `al`: every vertex's colour (blend and drying) and its UV in
-- the atlas copy for its opacity.
local function paint(self: GroundMarks, g: number, al: number)
	local em = chunkOf(self, g).em
	local P = self.P
	local T = Config.Fx.Ground.Ribbon.Texture
	local K = T.Levels
	local copy = GroundMarks.opacityLevel(self, g, al)
	local pad = 1 / T.Width
	local base = (g - 1) * 2 * P
	for sec = 0, 1 do
		local d = if sec == 0 then self.d0[g] else self.d1[g]
		local v = if sec == 0 then self.v0[g] else self.v1[g]
		for j = 1, P do
			local k = base + sec * P + j
			em:SetColor(self.cids[k], lut(self, j, d, al))
			em:SetUV(self.uids[k], Vector2.new((copy + pad + self.us[j] * (1 - 2 * pad)) / K, v))
		end
	end
end

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------

-- One cross-section at `centre` (the tyre's contact, world), square to `tangent`, with the
-- ground's up `up`, half-width `hw` and blend `d`, into the scratch arrays. Its two outer
-- points and its centre are put on `ground` (anything with `_drawnAt`), when given; the
-- others go on the lines between. Returns how many of the three found the ground.
local function section(self: GroundMarks, centre: Vector3, tangent: Vector3, up: Vector3, hw: number, d: number, ground: any?, onGround: any): number
	local G = Config.Fx.Ground
	local right = tangent:Cross(up)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local base = centre + up * G.Lift
	local L, M, Rr = base - right * hw, base, base + right * hw
	local found = 0
	if ground then
		local okL, okM, okR
		L, okL = onGround(ground, L, G.Lift, G.MaxSnap)
		M, okM = onGround(ground, M, G.Lift, G.MaxSnap)
		Rr, okR = onGround(ground, Rr, G.Lift, G.MaxSnap)
		found = (if okL then 1 else 0) + (if okM then 1 else 0) + (if okR then 1 else 0)
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
	local P = self.P
	for j = 1, P do
		local f = self.offsets[j]
		local at = if f < 0 then M:Lerp(L, -f) else M:Lerp(Rr, f)
		local hs, ts = self.heights[j], self.tilts[j]
		local height = hs[1] + (hs[2] - hs[1]) * d
		local tilt = ts[1] + (ts[2] - ts[1]) * d
		self.scratchPts[j] = at + n * height
		-- Lean toward the centre: +across on the left side, -across on the right.
		local inward = if f < 0 then acrossUnit else -acrossUnit
		self.scratchNrm[j] = (n * math.cos(tilt) + inward * math.sin(tilt)).Unit
	end
	return found
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

-- Finish wheel `r`'s mark where it is: its last segment fades out to nothing.
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
-- look (Wheels' hysteresis). `ground`: the drawn ground, or nil. `onGround`: `Wheels.onGround`.
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
	onGround: any,
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
		r.snapped = section(self, contact, if tangent.Magnitude > 1e-4 then tangent.Unit else Vector3.zAxis, up, hw * r.ratio, r.depth, ground, onGround)
		for j = 1, self.P do
			r.lastPts[j] = self.scratchPts[j]
			r.lastNrm[j] = self.scratchNrm[j]
		end
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
		section(self, r.lastPos, dir, up, hw * r.ratio, r.lastD, ground, onGround)
		for j = 1, self.P do
			r.lastPts[j] = self.scratchPts[j]
			r.lastNrm[j] = self.scratchNrm[j]
		end
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
	r.snapped = section(self, contact, tangent, up, hw * r.ratio, r.depth, ground, onGround)
	local v = r.lastV + len / math.max(R.TileLength, 1e-4)

	local g = r.head
	if not g then
		g = alloc(self, r.lastPos)
		r.head = g
		self.isHead[g] = true
		self.d0[g], self.s0[g], self.v0[g] = r.lastD, r.lastS, r.lastV
		writeSection(self, g, 0, r.lastPts, r.lastNrm)
	end
	self.d1[g], self.s1[g], self.v1[g] = r.depth, strength, v
	writeSection(self, g, 1, self.scratchPts, self.scratchNrm)
	paint(self, g, 0)

	-- Commit: this section is fixed, and the next segment starts from it.
	local turned = if r.prevDir then math.deg(math.acos(math.clamp(dir:Dot(r.prevDir :: Vector3), -1, 1))) else 0
	-- Short segments while the mark fades in, so its opacity climbs in small steps.
	local spacing = if r.dist < R.FadeInStuds then R.MinSpacing else R.Spacing
	if len >= spacing or (len >= R.MinSpacing and turned >= R.TurnDegrees) then
		self.isHead[g] = false
		self.born[g] = self.clock
		self.level[g] = 0
		r.head = nil
		r.lastSlot = g
		for j = 1, self.P do
			r.lastPts[j] = self.scratchPts[j]
			r.lastNrm[j] = self.scratchNrm[j]
		end
		r.lastPos, r.lastD, r.lastS, r.lastV = contact, r.depth, strength, v
		r.dist += len
		r.prevDir = dir
	end
end

-- Once a frame, after the wheels: the clock moves on, and every laid segment dries and
-- fades a step whenever its age crosses one, and goes when its life is up.
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

-- A slot's points in the world, for the tests: its start section, then its end.
function GroundMarks.DebugSlot(self: GroundMarks, g: number)
	local ch = chunkOf(self, g)
	local P = self.P
	local base = (g - 1) * 2 * P
	local pts, nrm, uv = {}, {}, {}
	for k = 1, 2 * P do
		pts[k] = ch.em:GetPosition(self.vids[base + k]) + ch.origin
		nrm[k] = ch.em:GetNormal(self.nids[base + k])
		uv[k] = ch.em:GetUV(self.uids[base + k])
	end
	-- `opacity`: 0..1, the atlas copy its UVs point at.
	local K = Config.Fx.Ground.Ribbon.Texture.Levels
	local copy = math.floor(uv[1].X * K)
	return {
		live = self.live[g],
		head = self.isHead[g],
		born = self.born[g],
		points = pts,
		normals = nrm,
		uvs = uv,
		opacity = copy / math.max(K - 1, 1),
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
		surface = self.surface,
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
