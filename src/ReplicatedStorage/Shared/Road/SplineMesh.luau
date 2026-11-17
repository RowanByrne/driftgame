--!strict
-- SplineMesh: one chunk of the spline road drawn as triangle meshes
-- (features/spline-road.md "The mesh, purely visual", T-135).
--
-- PURELY VISUAL. Nothing collides with it, nothing can query it, nothing touches it: the car
-- stands on the curve's maths (`Drift/SplineWorld`), and this is drawn from the very same
-- formula (`Spline.surfaceXYZ`), so what you see is where you are.
--
-- A chunk is ONE MeshPart and some plain parts, in the piece road's materials and colours:
--
--   Road        ONE MESH, coloured by vertex (T-140): the tarmac, the grass runoff either
--               side, a skirt down from each runoff's outer edge to the ground (T-218: the
--               ground itself is drawn apart, `Drift/GroundMeshView`), and a grove's trees
--               and bushes (T-183, `Road/SplineGrove`), flat-shaded, very low poly. The grass
--               alone is textured (T-187): a painted tile, `Road/GrassTexture`, mapped in
--               world studs; every other face samples the tile's plain corner. When the
--               ground draws the runoff (the default, T-251) there is no grass here, and the
--               TARMAC is textured instead (T-268): a texture painted in code,
--               `Road/RoadTexture`, mapped across the tarmac and along the road, with the
--               weathered edge lines, patches and cracks in it; and on the tight stretches
--               the DOUBLE YELLOW, two thin strips just over the tarmac mapped to the image's
--               line band (send-back 2). The GRAVEL is textured too (T-270): the bevels map
--               to the image's gravel band, and a strip over a tight cliff edge's gravel runoff
--   KRail*_*    a K-rail run drawn as a METAL CRASH BARRIER (T-149): a W-beam guardrail,
--               its beam two rounded ridges (`KRailTop_*`, `KRailLow_*`) and the groove
--               between (`KRailGroove_*`), a piece per stretch of the run, pitched along the
--               grade and cut finer round a bend; square posts (`KRailPost_*`) every
--               `KRailPostEvery` on spacer blocks (`KRailSpacer_*`), bolt heads at each
--               splice (`KRailBolt_*`), a striped hazard panel at each end (`KRailEnd_*`)
--   Mark        a flat box per dash of the centre line, `MarkLift` above the surface,
--               only when the tarmac is not textured (the texture paints its own lines)
--
-- Only the surface is a mesh: a client's mesh memory is small (`Config.Spline.Mesh.Budget`).
-- SINCE T-274 A DRAWN CHUNK HOLDS NONE OF IT: the surface is recorded in plain tables, written
-- into a fixed-size copy of a blank template, and made OPAQUE CONTENT, which costs none of it
-- (measured), the copy let go (`meshFor`). Nothing holds a growable mesh between chunks.
--
-- HOW FINELY IT IS CUT is decided by the surface itself, not by a fixed spacing: a cross-
-- section is placed as far on as it can be while the true surface halfway between it and
-- the last one stays within `Tolerance` of the straight line between them, at the centre and
-- at both kerbs. A straight is cut every `MaxStep`; a hairpin, a crest or a rolling bank as
-- often as they need. ACROSS, the road is `Across` strips, because where the bank rolls on a
-- grade through a bend the surface twists, and one triangle the whole width of the road
-- cannot follow it (measured: 6.5 degrees off the true normal at full width).
--
-- Every vertex carries the spline's own normal, so the shading is smooth across chunks and
-- across the cuts. Vertices are written relative to the chunk's own centre: a Vector3 20 000
-- studs out is good to ~0.002 studs, one a hundred studs from its part's centre is exact.
--
-- WHERE A DEVICE CANNOT MAKE A MESH -- out of its EditableMesh memory, or refusing one --
-- `build` returns nil and says why, and the caller draws the chunk with `Road/SplineParts`
-- instead.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local GrassTexture = require(script.Parent.GrassTexture)
local Ground = require(script.Parent.Ground)
local RoadTexture = require(script.Parent.RoadTexture)
local Spline = require(script.Parent.Spline)
local SplineGrove = require(script.Parent.SplineGrove)

local SplineMesh = {}

local meshesOf: { [Model]: { EditableMesh } } = setmetatable({}, { __mode = "k" }) :: any

-- THE HAZARD PANEL's diagonal stripes (T-149), as one gradient stepping sharply between its
-- two colours: no image to upload, and a gradient rotates without spilling past its frame.
local hazardStripes = (function(): ColorSequence
	local yellow, black = Config.Spline.Terrain.KRailHazardColours[1], Config.Spline.Terrain.KRailHazardColours[2]
	local bands = 9 -- a ColorSequence holds 20 keypoints at most: two a step, and the ends
	local keys = { ColorSequenceKeypoint.new(0, yellow) }
	for i = 1, bands - 1 do
		local t = i / bands
		table.insert(keys, ColorSequenceKeypoint.new(t - 0.002, if i % 2 == 1 then yellow else black))
		table.insert(keys, ColorSequenceKeypoint.new(t, if i % 2 == 1 then black else yellow))
	end
	table.insert(keys, ColorSequenceKeypoint.new(1, yellow))
	return ColorSequence.new(keys)
end)()

export type Options = {
	tolerance: number?,
	maxStep: number?,
	minStep: number?,
	across: number?,
	forceFail: boolean?, -- Studio tests: behave as a device that cannot make a mesh
	sliceMs: number?, -- ms of building a frame (`Mesh.SliceMs`); math.huge builds it in one go
	-- who draws the runoff (T-251): "ground" draws the road to its bevels' feet only, "road"
	-- the runoff too; nil, `Ground.runoffBy()`
	runoffBy: string?,
	-- out of mesh memory making the chunk's mesh (T-273, T-274): make room
	-- (`Drift/MeshBudget`) and say whether to try once more
	onShort: (() -> boolean)?,
	-- a far chunk's trees without trunks or flat undersides (T-273): the same outline from far
	-- off, about half the triangles
	leanTrees: boolean?,
}

export type Stats = {
	sections: number,
	vertices: number,
	triangles: number,
	ms: number,
}

-- The cross-sections of [s0, s1], placed where the surface needs them.
function SplineMesh.sections(spline: Spline.Spline, s0: number, s1: number, opts: Options?): { number }
	local o: Options = opts or {}
	local M = Config.Spline.Mesh
	local tol = o.tolerance or M.Tolerance
	local maxStep = o.maxStep or M.MaxStep
	local minStep = o.minStep or M.MinStep
	local half = Config.Road.Width * 0.5
	local out = { s0 }
	local s = s0
	local function off(a: number, b: number, d: number): number
		local ax, ay, az = spline:surfaceXYZ(a, d)
		local bx, by, bz = spline:surfaceXYZ(b, d)
		local mx, my, mz = spline:surfaceXYZ((a + b) * 0.5, d)
		local dx, dy, dz = mx - (ax + bx) * 0.5, my - (ay + by) * 0.5, mz - (az + bz) * 0.5
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	while s < s1 - 1e-6 do
		local step = math.min(maxStep, s1 - s)
		while step > minStep do
			local b = s + step
			if off(s, b, -half) <= tol and off(s, b, 0) <= tol and off(s, b, half) <= tol then
				break
			end
			step = math.max(minStep, step * 0.5)
		end
		s = math.min(s + step, s1)
		table.insert(out, s)
	end
	return out
end

-- THE RECORDING (T-274): a chunk is no longer built in a growable EditableMesh, which holds
-- 80 tiles of the client's mesh memory however little is in it (measured), but recorded here,
-- in plain tables, through the same calls (`AddVertex`, `AddTriangle`, `SetFaceNormals`...),
-- and written into a fixed-size mesh only once it is whole (`meshFor`). A face's attribute
-- left unset is 0: the plain normal, white, UV (0, 0), as a new EditableMesh's would be.
type RecData = {
	pos: { Vector3 },
	nrm: { Vector3 },
	col: { Color3 },
	alpha: { number },
	uv: { Vector2 },
	-- three a face: its vertices, and the normal, colour and UV each corner uses
	fv: { number },
	fn: { number },
	fc: { number },
	fu: { number },
	faces: number,
}
local Recorder = {}
Recorder.__index = Recorder
type Rec = typeof(setmetatable({} :: RecData, Recorder))

local function newRecorder(): Rec
	return setmetatable({ pos = {}, nrm = {}, col = {}, alpha = {}, uv = {}, fv = {}, fn = {}, fc = {}, fu = {}, faces = 0 } :: RecData, Recorder)
end
function Recorder.AddVertex(self: Rec, p: Vector3): number
	local n = #self.pos + 1
	self.pos[n] = p
	return n
end
function Recorder.AddNormal(self: Rec, v: Vector3): number
	local n = #self.nrm + 1
	self.nrm[n] = v
	return n
end
function Recorder.AddColor(self: Rec, c: Color3, a: number): number
	local n = #self.col + 1
	self.col[n] = c
	self.alpha[n] = a
	return n
end
function Recorder.AddUV(self: Rec, u: Vector2): number
	local n = #self.uv + 1
	self.uv[n] = u
	return n
end
function Recorder.AddTriangle(self: Rec, a: number, b: number, c: number): number
	local f = self.faces + 1
	self.faces = f
	local k = 3 * f
	self.fv[k - 2], self.fv[k - 1], self.fv[k] = a, b, c
	self.fn[k - 2], self.fn[k - 1], self.fn[k] = 0, 0, 0
	self.fc[k - 2], self.fc[k - 1], self.fc[k] = 0, 0, 0
	self.fu[k - 2], self.fu[k - 1], self.fu[k] = 0, 0, 0
	return f
end
function Recorder.SetFaceNormals(self: Rec, f: number, ids: { number })
	local k = 3 * f
	self.fn[k - 2], self.fn[k - 1], self.fn[k] = ids[1], ids[2], ids[3]
end
function Recorder.SetFaceColors(self: Rec, f: number, ids: { number })
	local k = 3 * f
	self.fc[k - 2], self.fc[k - 1], self.fc[k] = ids[1], ids[2], ids[3]
end
function Recorder.SetFaceUVs(self: Rec, f: number, ids: { number })
	local k = 3 * f
	self.fu[k - 2], self.fu[k - 1], self.fu[k] = ids[1], ids[2], ids[3]
end
-- (nothing to do: only the faces' vertices are written, `meshFor`)
function Recorder.RemoveUnused(_self: Rec) end

-- How a build hands the frame back, and waits on the engine (`AssetService`'s Async calls run
-- off the frame: measured, the worst frame was the same with them as without), so that wait
-- is neither counted as the build's work nor as its frame's slice.
type Pace = { slice: () -> (), wait: (() -> ...any) -> ...any }

-- A mesh in the making: vertices relative to `centre`, with normals.
type Builder = {
	em: Rec,
	centre: Vector3,
	onShort: (() -> boolean)?,
	pace: Pace, -- hands the frame back when this frame's share of the build is spent
	held: EditableMesh?, -- the fixed-size mesh, kept only where it could not be made opaque
	vertices: number,
	triangles: number,
	grassTriangles: number,
	-- with the grass's texture: the tile's plain corner, (0, 0), for the faces that are not
	-- grass but share a vertex with it. Every other face's default UV is (0, 0) already, but
	-- one sharing a grass vertex picks up the grass's UV there (measured: the bevel did).
	-- Set only where needed: on every face it cost ~2 ms a chunk (measured)
	plainUV: number?,
	-- with the texture: each grass vertex's colour id, `GrassColour` lightened or darkened by
	-- `GrassTexture.blotch` at its place
	grassShade: { [number]: number }?,
	-- with the tarmac's texture (T-268): faces painted the tarmac's colour id are the ones
	-- mapped, and `grassShade` holds each tarmac vertex's tone
	tarmacTriangles: number,
}


-- A quad strip between two rows of vertex ids, each with its normal id. `colours`, when
-- given, is a colour id per strip (between vertex i and i + 1), painted on both triangles.
-- `farA` / `farB`, when given, are the normals a vertex has as the FAR side of a strip
-- (vertex i + 1 of strip i), so one vertex can be smooth on one strip and flat on the next:
-- the road's step (T-184).
-- `uvA` / `uvB`, when given, are UV ids for the textured vertices: the grass's (T-187), or
-- the tarmac's (T-268). A strip painted `mapped` is mapped with them; one that shares a mapped
-- vertex but is not painted `mapped` gets `plainUV`. `tarmac`: the mapped faces are tarmac.
-- `onFace(i, f1, f2)`, when given, is told each strip's two faces once they are made (T-270:
-- the gravel bevels are mapped there).
local function strip(b: Builder, rowA: { number }, normA: { number }, rowB: { number }, normB: { number }, flip: boolean, colours: { number }?, farA: { number }?, farB: { number }?, uvA: { [number]: number }?, uvB: { [number]: number }?, mapped: number?, tarmac: boolean?, onFace: ((number, number, number) -> ())?)
	local em = b.em
	local fa, fb = farA or normA, farB or normB
	for i = 1, #rowA - 1 do
		local a0, a1, b0, b1 = rowA[i], rowA[i + 1], rowB[i], rowB[i + 1]
		local na0, na1, nb0, nb1 = normA[i], fa[i + 1], normB[i], fb[i + 1]
		local f1, f2
		if flip then
			f1 = em:AddTriangle(a0, b0, a1)
			f2 = em:AddTriangle(a1, b0, b1)
			em:SetFaceNormals(f1, { na0, nb0, na1 })
			em:SetFaceNormals(f2, { na1, nb0, nb1 })
		else
			f1 = em:AddTriangle(a0, a1, b0)
			f2 = em:AddTriangle(a1, b1, b0)
			em:SetFaceNormals(f1, { na0, na1, nb0 })
			em:SetFaceNormals(f2, { na1, nb1, nb0 })
		end
		if colours then
			local c = colours[i]
			em:SetFaceColors(f1, { c, c, c })
			em:SetFaceColors(f2, { c, c, c })
			if uvA and uvB and c == mapped then
				local ua0, ua1, ub0, ub1 = uvA[i], uvA[i + 1], uvB[i], uvB[i + 1]
				if ua0 and ua1 and ub0 and ub1 then
					if flip then
						em:SetFaceUVs(f1, { ua0, ub0, ua1 })
						em:SetFaceUVs(f2, { ua1, ub0, ub1 })
					else
						em:SetFaceUVs(f1, { ua0, ua1, ub0 })
						em:SetFaceUVs(f2, { ua1, ub1, ub0 })
					end
					-- the blotches (T-187): each corner its own vertex's shade of the grass
					-- (or of the tarmac, its tone, T-268)
					local shadeOf = b.grassShade
					if shadeOf then
						local ca0, ca1, cb0, cb1 = shadeOf[a0] or c, shadeOf[a1] or c, shadeOf[b0] or c, shadeOf[b1] or c
						if flip then
							em:SetFaceColors(f1, { ca0, cb0, ca1 })
							em:SetFaceColors(f2, { ca1, cb0, cb1 })
						else
							em:SetFaceColors(f1, { ca0, ca1, cb0 })
							em:SetFaceColors(f2, { ca1, cb1, cb0 })
						end
					end
					if tarmac then
						b.tarmacTriangles += 2
					else
						b.grassTriangles += 2
					end
				end
			elseif b.plainUV and uvA and uvB and (uvA[i] or uvA[i + 1] or uvB[i] or uvB[i + 1]) then
				-- a strip that is not mapped but shares a mapped vertex: the bevel, or a
				-- gravelled runoff
				local u = b.plainUV
				em:SetFaceUVs(f1, { u, u, u })
				em:SetFaceUVs(f2, { u, u, u })
			end
		end
		if onFace then
			onFace(i, f1, f2)
		end
		b.triangles += 2
	end
end

local function newBuilder(centre: Vector3, pace: Pace): Builder
	return { em = newRecorder(), centre = centre, pace = pace, held = nil, vertices = 0, triangles = 0, grassTriangles = 0, tarmacTriangles = 0, plainUV = nil, grassShade = nil }
end

-- THE TEMPLATES (T-274). A fixed-size mesh can only be had as a copy of another mesh, and a
-- growable one holds 80 tiles however little is in it (measured: empty, 128 or 6 144
-- triangles alike). So a chunk is written into a fixed-size COPY OF A BLANK TEMPLATE: the
-- smallest of a ladder of sizes that holds it, each face its own three vertices (any face can
-- then be anything), the faces it does not use folded to a point. The templates are made
-- once, as a client loads (`prepare`, up to `Mesh.PrepareFaces`) or the first time a chunk
-- needs a larger size, in one growable mesh let go at once, and kept as OPAQUE CONTENT, which
-- costs none of the client's mesh memory (measured). The ids a copy of a template gets are
-- the same every time (measured), so where each face's corners are is worked out once a size
-- (`map`). Where opaque content is refused, the road builds as T-273 did (`viaGrowable`).
local SIZES: { number } = {}
do
	local s = 64
	while s < 20000 do
		table.insert(SIZES, s)
		s = math.ceil(s * 1.25 / 32) * 32
	end
	table.insert(SIZES, 20000) -- the most triangles an EditableMesh may hold
end
type Template = {
	content: Content,
	faces: number,
	-- per corner (3 a face), the copy's vertex, normal, colour and UV ids; and its first and
	-- last face's ids, to tell a copy whose ids are not the same after all
	map: { tv: { number }, tn: { number }, tc: { number }, tu: { number }, f1: number, fN: number }?,
}
local templates: { [number]: Template } = {}
local WHITE = Color3.new(1, 1, 1)
local buildStats = {
	templates = 0, -- sizes made
	templateFails = 0, -- times one could not be made (no room for its growable mesh)
	copies = 0, -- chunks written into a copy
	copyFails = 0,
	growable = 0, -- chunks built in a growable mesh instead (opaque content refused, the fallback)
	opaque = 0, -- chunks made opaque
	opaqueFails = 0, -- chunks that kept their fixed-size mesh instead
	faces = 0, -- the chunks' own faces
	templateFaces = 0, -- and the sizes they were written into
	writeMs = 0,
	worstWriteMs = 0,
	worstClassTiles = 0, -- the largest fixed-size mesh a build held for a moment, in tiles
}

-- The smallest size that holds `faces`, or nil past the largest.
local function sizeFor(faces: number): number?
	for k, s in SIZES do
		if s >= faces then
			return k
		end
	end
	return nil
end

-- The faces of the template a chunk of `faces` triangles is written into (the tests).
function SplineMesh.templateFaces(faces: number): number?
	local k = sizeFor(faces)
	return if k then SIZES[k] else nil
end

local making = false -- templates being made (one growable mesh at a time)

-- `em` as opaque content: (true, content), or false where it is refused. In Studio,
-- `workspace.__no_opaque = true` refuses it, to try the fallback (T-274).
local function toOpaque(em: EditableMesh): (boolean, Content?)
	if RunService:IsStudio() and workspace:GetAttribute("__no_opaque") == true then
		return false, nil
	end
	local ok, result, content = pcall(function()
		return AssetService:CreateDataModelContentAsync(Content.fromObject(em))
	end)
	return ok and result == Enum.CreateContentResult.Success, if ok then content else nil
end

-- Make every size up to `k` not made yet, in ONE growable mesh: blank faces are added, and
-- the mesh is made opaque each time it reaches a size, then let go. Returns "ok", "memory"
-- (no room for the growable mesh) or "refused" (opaque content was refused).
local function makeTemplates(k: number, pace: Pace): string
	while making do
		task.wait()
	end
	if templates[k] then
		return "ok"
	end
	making = true
	local ok, g = pcall(function()
		return AssetService:CreateEditableMesh()
	end)
	if not ok or not g then
		making = false
		buildStats.templateFails += 1
		return "memory"
	end
	local em = g :: EditableMesh
	local outcome = "ok"
	local done = pcall(function()
		local f = 0
		for size = 1, k do
			local faces = SIZES[size]
			while f < faces do
				-- (well inside the 2 048 studs a mesh may span, so any size fits)
				local x, z = (f % 64) * 2, (f // 64) * 2
				local a = em:AddVertex(Vector3.new(x, 0, z))
				local b = em:AddVertex(Vector3.new(x, 0, z + 1))
				local c = em:AddVertex(Vector3.new(x + 1, 0, z))
				local face = em:AddTriangle(a, b, c)
				em:SetFaceNormals(face, { em:AddNormal(Vector3.yAxis), em:AddNormal(Vector3.yAxis), em:AddNormal(Vector3.yAxis) })
				em:SetFaceColors(face, { em:AddColor(WHITE, 1), em:AddColor(WHITE, 1), em:AddColor(WHITE, 1) })
				em:SetFaceUVs(face, { em:AddUV(Vector2.zero), em:AddUV(Vector2.zero), em:AddUV(Vector2.zero) })
				f += 1
				if f % 128 == 0 then
					pace.slice()
				end
			end
			if not templates[size] then
				local made, content = pace.wait(function()
					return toOpaque(em)
				end)
				if not made or not content then
					outcome = "refused"
					break
				end
				templates[size] = { content = content, faces = faces, map = nil }
				buildStats.templates += 1
			end
		end
	end)
	em:Destroy()
	making = false
	if not done or outcome ~= "ok" then
		buildStats.templateFails += 1
		return if done then outcome else "memory"
	end
	return "ok"
end

-- A fixed-size copy of template `k`, and where each of its faces' corners are; nil when the
-- device has no room for it.
local function copyOf(k: number, pace: Pace): (EditableMesh?, any)
	local t = templates[k]
	local ok, copy = pace.wait(function()
		return pcall(function()
			return AssetService:CreateEditableMeshAsync(t.content, { FixedSize = true })
		end)
	end)
	if not ok or not copy then
		buildStats.copyFails += 1
		return nil, nil
	end
	local em = copy :: EditableMesh
	local faces = em:GetFaces()
	local map = t.map
	if map and (#faces ~= t.faces or faces[1] ~= map.f1 or faces[#faces] ~= map.fN) then
		map = nil
	end
	if not map then
		local tv, tn, tc, tu = table.create(3 * #faces), table.create(3 * #faces), table.create(3 * #faces), table.create(3 * #faces)
		for i, f in faces do
			local vs, ns, cs, us = em:GetFaceVertices(f), em:GetFaceNormals(f), em:GetFaceColors(f), em:GetFaceUVs(f)
			local k3 = 3 * i
			for q = 1, 3 do
				tv[k3 - 3 + q], tn[k3 - 3 + q], tc[k3 - 3 + q], tu[k3 - 3 + q] = vs[q], ns[q], cs[q], us[q]
			end
			if i % 256 == 0 then
				pace.slice()
			end
		end
		map = { tv = tv, tn = tn, tc = tc, tu = tu, f1 = faces[1], fN = faces[#faces] }
		t.map = map
	end
	buildStats.copies += 1
	return em, map
end

-- THE FALLBACK (T-274): where opaque content is refused (`CreateContentResult`, seen once in a
-- Studio client), no template can be made, and the road builds as T-273 did: in one growable
-- mesh kept while it must be (80 tiles, `Budget.Growable`), each chunk copied into a
-- fixed-size mesh of its own size. Let go again as soon as a template serves.
local kept: EditableMesh? = nil
local keptBusy = false
local refusedUntil = 0 -- no template is tried again before this (os.clock)
local REFUSED_WAIT = 30 -- seconds

-- The recording replayed into a growable mesh, its vertices `mid` nearer the part's centre.
local function replay(em: EditableMesh, rec: Rec, mid: Vector3, pace: Pace)
	local vid, nid, cid, uid = {}, {}, {}, {}
	local plainN, plainC, plainU = nil, nil, nil
	local pos, nrm, col, alpha, uv = rec.pos, rec.nrm, rec.col, rec.alpha, rec.uv
	local fv, fn, fc, fu = rec.fv, rec.fn, rec.fc, rec.fu
	for f = 1, rec.faces do
		local k = 3 * f
		local vs, ns, cs, us = {}, {}, {}, {}
		for q = 1, 3 do
			local i = k - 3 + q
			local v = fv[i]
			vid[v] = vid[v] or em:AddVertex(pos[v] - mid)
			vs[q] = vid[v]
			local n = fn[i]
			if n > 0 then
				nid[n] = nid[n] or em:AddNormal(nrm[n])
				ns[q] = nid[n]
			else
				plainN = plainN or em:AddNormal(Vector3.yAxis)
				ns[q] = plainN
			end
			local c = fc[i]
			if c > 0 then
				cid[c] = cid[c] or em:AddColor(col[c], alpha[c])
				cs[q] = cid[c]
			else
				plainC = plainC or em:AddColor(WHITE, 1)
				cs[q] = plainC
			end
			local u = fu[i]
			if u > 0 then
				uid[u] = uid[u] or em:AddUV(uv[u])
				us[q] = uid[u]
			else
				plainU = plainU or em:AddUV(Vector2.zero)
				us[q] = plainU
			end
		end
		local face = em:AddTriangle(vs[1], vs[2], vs[3])
		em:SetFaceNormals(face, ns)
		em:SetFaceColors(face, cs)
		em:SetFaceUVs(face, us)
		if f % 128 == 0 then
			pace.slice()
		end
	end
end

local function viaGrowable(b: Builder, mid: Vector3, pace: Pace): (Content, EditableMesh?)
	buildStats.growable += 1
	local own = keptBusy -- the kept one is in use (a view being replaced): one of its own
	local em: EditableMesh? = if own then nil else kept
	if not em then
		local function make(): EditableMesh?
			local ok, g = pcall(function()
				return AssetService:CreateEditableMesh()
			end)
			return if ok then g else nil
		end
		em = make()
		if not em and b.onShort and b.onShort() then
			em = make()
		end
		assert(em, "this device would not make an EditableMesh (out of its budget)")
		if not own then
			kept = em
		end
	end
	local mesh = em :: EditableMesh
	if not own then
		keptBusy = true
	end
	local function done()
		if own then
			mesh:Destroy()
		else
			mesh:Clear()
			keptBusy = false
		end
	end
	local ok, err = pcall(function(): any
		replay(mesh, b.em, mid, pace)
		return nil
	end)
	if not ok then
		done()
		error(err)
	end
	local made, content = pace.wait(function()
		return toOpaque(mesh)
	end)
	if made and content then
		done()
		buildStats.opaque += 1
		return content, nil
	end
	local function copyIt(): EditableMesh?
		local okCopy, copy = pace.wait(function()
			return pcall(function()
				return AssetService:CreateEditableMeshAsync(Content.fromObject(mesh), { FixedSize = true })
			end)
		end)
		return if okCopy then copy else nil
	end
	local copy = copyIt()
	if not copy and b.onShort and b.onShort() then
		copy = copyIt()
	end
	done()
	assert(copy, "this device would not copy the chunk into a fixed-size mesh (out of its budget)")
	buildStats.opaqueFails += 1
	return Content.fromObject(copy), copy
end

-- The recorded chunk as a mesh (T-274): written into a fixed-size copy of the smallest
-- template that holds it, its vertices `mid` nearer the part's centre, then MADE OPAQUE and
-- the copy let go, so a chunk once drawn holds none of the client's mesh memory (measured).
-- Returns the mesh's content, and the fixed-size mesh where it could not be made opaque (it is
-- then the chunk's mesh, held at its size, as every chunk was before). Errors when out of
-- memory.
local function meshFor(b: Builder, mid: Vector3, pace: Pace): (Content, EditableMesh?)
	local rec = b.em
	local F = rec.faces
	local k = sizeFor(F)
	assert(k, `a chunk of {F} triangles is more than an EditableMesh may hold`)
	if not templates[k] then
		-- (refused a moment ago: not asked again for `REFUSED_WAIT`, each try costs a growable mesh)
		if os.clock() < refusedUntil then
			return viaGrowable(b, mid, pace)
		end
		local made = makeTemplates(k, pace)
		if made == "memory" and b.onShort and b.onShort() then
			made = makeTemplates(k, pace)
		end
		if made == "refused" then
			refusedUntil = os.clock() + REFUSED_WAIT
			return viaGrowable(b, mid, pace)
		end
		assert(made == "ok", "this device would not make an EditableMesh (out of its budget)")
	end
	local em, map = copyOf(k, pace)
	if not em and b.onShort and b.onShort() then
		em, map = copyOf(k, pace)
	end
	assert(em and map, "this device would not make the chunk's fixed-size mesh (out of its budget)")
	local mesh = em :: EditableMesh
	buildStats.worstClassTiles = math.max(buildStats.worstClassTiles, SIZES[k] / Config.Spline.Mesh.Budget.TileTriangles)
	local t0 = os.clock()
	local paused = 0
	local ok, err = pcall(function()
		local pos, nrm, col, alpha, uv = rec.pos, rec.nrm, rec.col, rec.alpha, rec.uv
		local fv, fn, fc, fu = rec.fv, rec.fn, rec.fc, rec.fu
		local tv, tn, tc, tu = map.tv, map.tn, map.tc, map.tu
		for i = 1, 3 * F do
			mesh:SetPosition(tv[i], pos[fv[i]] - mid)
			local n = fn[i]
			mesh:SetNormal(tn[i], if n > 0 then nrm[n] else Vector3.yAxis)
			local c = fc[i]
			if c > 0 then
				mesh:SetColor(tc[i], col[c])
				if alpha[c] ~= 1 then
					mesh:SetColorAlpha(tc[i], alpha[c])
				end
			else
				mesh:SetColor(tc[i], WHITE)
			end
			local u = fu[i]
			mesh:SetUV(tu[i], if u > 0 then uv[u] else Vector2.zero)
			if i % 384 == 0 then
				local w = os.clock()
				pace.slice()
				paused += os.clock() - w
			end
		end
		-- the faces past the chunk's own: each folded to one point of the chunk, drawing nothing
		local p0 = pos[fv[1]] - mid
		for i = 3 * F + 1, #tv do
			mesh:SetPosition(tv[i], p0)
		end
	end)
	local ms = (os.clock() - t0 - paused) * 1000
	buildStats.writeMs += ms
	buildStats.worstWriteMs = math.max(buildStats.worstWriteMs, ms)
	buildStats.faces += F
	buildStats.templateFaces += SIZES[k]
	if not ok then
		mesh:Destroy()
		error(err)
	end
	-- a template serves: the fallback's growable mesh is let go
	if kept and not keptBusy then
		kept:Destroy()
		kept = nil
	end
	local made, content = pace.wait(function()
		return toOpaque(mesh)
	end)
	if made and content then
		mesh:Destroy()
		buildStats.opaque += 1
		return content, nil
	end
	buildStats.opaqueFails += 1
	return Content.fromObject(mesh), mesh
end

-- Make the templates most chunks need now, a few ms a frame in the background (a client, as
-- soon as the road's code loads, while its mesh memory is still free), so building a chunk in
-- a run seldom makes one.
function SplineMesh.prepare()
	local budget = Config.Spline.Mesh.SliceMs / 1000
	local sliceStart = os.clock()
	local pace: Pace = {
		slice = function()
			if os.clock() - sliceStart >= budget then
				task.wait()
				sliceStart = os.clock()
			end
		end,
		wait = function(fn: () -> ...any): ...any
			local out = table.pack(fn())
			sliceStart = os.clock()
			return table.unpack(out, 1, out.n)
		end,
	}
	local k = sizeFor(Config.Spline.Mesh.PrepareFaces) or #SIZES
	task.spawn(makeTemplates, k, pace)
end

-- THE CLIENT'S MESH MEMORY (T-273, T-274, `Config.Spline.Mesh.Budget`), in tiles.
-- The road's window for a Road ahead and Road behind: chunk-aligned (up to a chunk more each
-- way), whole within `Near` of the car and far past it. Returns its chunks, and how many whole.
function SplineMesh.roadWindow(aheadStuds: number, behindStuds: number): (number, number)
	local M = Config.Spline.Mesh
	local L = M.ChunkLength
	local window = math.ceil((aheadStuds + behindStuds) / L) + 1
	return window, math.min(window, math.ceil((M.Near.Ahead + M.Near.Behind) / L) + 1)
end

-- What the road holds (T-274): its chunks none once drawn (opaque content), and while one is
-- built, the fixed-size mesh it is written into, at most `Building`. Returns the tiles, the
-- chunks and how many of them whole.
function SplineMesh.roadTiles(aheadStuds: number, behindStuds: number): (number, number, number)
	local B = Config.Spline.Mesh.Budget
	local window, near = SplineMesh.roadWindow(aheadStuds, behindStuds)
	return window * B.DrawnChunk + B.Building, window, near
end

-- What every mesh user but the road and the ground's tiles holds, in tiles: the drift marks,
-- the vista's arc, the road's texture (none uploaded, T-274), and the ground's master tile.
function SplineMesh.otherTiles(): number
	local B = Config.Spline.Mesh.Budget
	local T = Config.Spline.Tarmac
	local painted = T.Enabled and T.Image == "" and Config.Spline.Ground.RunoffBy == "ground"
	local texture = if painted then T.Width * T.Length / (1024 * 1024) * B.Image1024 else 0
	return B.Marks + B.Vista + texture + 1
end

-- The tiles the ground may take (its `Spare` included) beside a road ahead and behind this
-- long. STILL WORKED OUT AS BEFORE T-274 (`Budget.GroundShare`): the road's window at T-273's
-- figures, and the others' T-273 total, so the ground draws what it drew; the tiles T-274
-- freed stay free (`freeTiles`) until the user picks what they buy.
function SplineMesh.groundRoom(aheadStuds: number, behindStuds: number): number
	local B = Config.Spline.Mesh.Budget
	local S = B.GroundShare
	local window, near = SplineMesh.roadWindow(aheadStuds, behindStuds)
	local road = near * S.WholeChunk + (window - near) * S.FarChunk + S.WholeChunk
	return math.floor(B.Tiles - B.Spare - S.Others - road)
end

-- The tiles nobody holds at these settings, past `Budget.Spare` (T-274): what the savings
-- freed, for the user to spend.
function SplineMesh.freeTiles(aheadStuds: number, behindStuds: number): number
	local B = Config.Spline.Mesh.Budget
	return B.Tiles - B.Spare - SplineMesh.groundRoom(aheadStuds, behindStuds) - (SplineMesh.roadTiles(aheadStuds, behindStuds)) - SplineMesh.otherTiles()
end

-- How the road's chunks were made, for the debug readouts (T-274).
function SplineMesh.BuildState()
	local s = table.clone(buildStats)
	local sizes = {}
	for k in templates do
		table.insert(sizes, SIZES[k])
	end
	table.sort(sizes)
	s.sizes = sizes
	s.meanWriteMs = if buildStats.copies > 0 then buildStats.writeMs / buildStats.copies else 0
	-- the share of the copies' faces that were the chunks' own
	s.used = if buildStats.templateFaces > 0 then buildStats.faces / buildStats.templateFaces else 0
	return s
end

-- A MeshPart made from a mesh keeps the vertices exactly where they were written, relative to
-- the part (measured: not re-centred), while its Size -- and so what Roblox culls it by -- is
-- the bounding box. So the vertices are written centred on their own box (`meshFor`), and the
-- part is put where that box is.
local function toPart(b: Builder, name: string, colour: Color3, material: Enum.Material, texture: Content?): MeshPart
	local rec = b.em
	assert(rec.faces > 0, "an empty chunk")
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	local pos, fv = rec.pos, rec.fv
	for i = 1, 3 * rec.faces do
		local p = pos[fv[i]]
		lo, hi = lo:Min(p), hi:Max(p)
	end
	local mid = (lo + hi) * 0.5
	-- THE CHUNK'S MESH (T-274): a fixed-size copy of a template, made opaque (`meshFor`). Out
	-- of room for it, the builder may make room (`onShort`) and try once more
	local content, held = meshFor(b, mid, b.pace)
	b.held = held
	local ok, part = b.pace.wait(function()
		return pcall(function()
			return AssetService:CreateMeshPartAsync(content, {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Precise,
			})
		end)
	end)
	if not ok then
		part = b.pace.wait(function()
			return AssetService:CreateMeshPartAsync(content)
		end)
	end
	local mp = part :: MeshPart
	mp.Name = name
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	-- Set, but it does nothing (T-178, measured in the lane): a MeshPart drawn from an
	-- EditableMesh casts no shadow at all, either side of its faces. The hidden boxes that
	-- once cast it were removed (T-229); a different approach to shadows is to come.
	mp.CastShadow = true
	mp.Color = colour
	mp.Material = material
	mp.CFrame = CFrame.new(b.centre + mid)
	if texture then
		-- the grass's texture (T-187, `Road/GrassTexture`) or the tarmac's (T-268,
		-- `Road/RoadTexture`, uploaded since T-274); it replaces the material's colour map on
		-- every face, so the faces it is not for sample its plain corner or band
		mp.TextureContent = texture
	end

	return mp
end

-- Draw [s0, s1] of the road under a new Model in `parent`. Returns the model and what it
-- cost, or nil and the reason when this device cannot make a mesh.
function SplineMesh.build(spline: Spline.Spline, s0: number, s1: number, parent: Instance, opts: Options?): (Model?, any)
	local o: Options = opts or {}
	local t0 = os.clock()
	local paused = 0 -- seconds spent waiting for the next frame
	local R = Config.Road
	local M = Config.Spline.Mesh
	-- BUILT A FEW MS A FRAME (T-193): `slice()` between steps hands the frame back once
	-- `SliceMs` of it has gone, and the build carries on next frame. The chunk's model is
	-- parented only when all of it is done, so it appears whole: no face or box arrives late
	local budget = (o.sliceMs or M.SliceMs) / 1000
	local sliceStart, worstSlice, slices = t0, 0, 1
	local function yieldNow()
		local now = os.clock()
		worstSlice = math.max(worstSlice, now - sliceStart)
		task.wait()
		sliceStart = os.clock()
		paused += sliceStart - now
		slices += 1
	end
	local function slice()
		if os.clock() - sliceStart >= budget then
			yieldNow()
		end
	end
	-- waiting on the engine (T-274): not work, and the frame's slice starts afresh after it
	local asyncWait = 0
	local function wait(fn: () -> ...any): ...any
		local w0 = os.clock()
		local out = table.pack(fn())
		local w1 = os.clock()
		paused += w1 - w0
		asyncWait += w1 - w0
		sliceStart = w1
		return table.unpack(out, 1, out.n)
	end
	local half = R.Width * 0.5
	local across = o.across or M.Across
	local cuts = SplineMesh.sections(spline, s0, s1, o)
	local cx, cy, cz = spline:surfaceXYZ((s0 + s1) * 0.5, 0)
	local centre = Vector3.new(cx, cy, cz)

	if o.forceFail then
		return nil, "forced (a test standing in for a device that cannot make meshes)"
	end
	-- recorded, then written into a fixed-size mesh and made opaque once whole (T-274, `meshFor`)
	local road = newBuilder(centre, { slice = slice, wait = wait })
	road.onShort = o.onShort
	local ok, built = pcall(function()
		-- ONE MESH A CHUNK, AND IT STAYS ALIVE WITH IT. A MeshPart made from an EditableMesh is
		-- drawn from it: let it go and the part draws nothing (measured -- the road vanished).
		-- Made opaque (T-274), the content is what the part is drawn from, and it lives as long
		-- as the part does. The mesh is spent on what only a mesh can draw -- the surface,
		-- which curves, banks and twists -- and the barriers and the centre line are plain
		-- parts, as the piece road's are: upright boxes and flat dashes, which a box draws
		-- exactly.
		-- the surface: the left runoff in `RUNOFF_STRIPS` strips, the tarmac in `across`,
		-- the right runoff in `RUNOFF_STRIPS`; a row of vertices per cross-section. The
		-- runoff's width changes along the road, so each row places its own grass vertices
		-- THE ROAD'S GRAVEL BEVEL (T-184): one more strip each side between the tarmac and
		-- the grass, `Spline:lipWidthAt` across (`RoadLipWidth`), sloping down `RoadLip` to the
		-- grass, in the gravel's colour. It is shaded FLAT across (its own normal), so it reads
		-- as an angled shoulder; the tarmac and the grass either side keep their smooth normals.
		-- (T-251: when the ground mesh draws the runoff, `Ground.RunoffBy = "ground"`, none: the
		-- road stops at its bevels' feet)
		local groundRunoff = (o.runoffBy or Ground.runoffBy()) == "ground"
		local RUNOFF_STRIPS = if groundRunoff then 0 else 2
		local TT = Config.Spline.Terrain
		local tarmacColour = road.em:AddColor(R.Colours.Road, 1)
		local grassColour = road.em:AddColor(TT.GrassColour, 1)
		local gravelColour = road.em:AddColor(TT.GravelColour, 1)
		local lipL = RUNOFF_STRIPS + 1 -- the left bevel's strip, from its foot's vertex
		local lipR = lipL + across + 1 -- the right bevel's strip, from its top's vertex
		local colours = {}
		for j = 1, RUNOFF_STRIPS * 2 + across + 2 do
			colours[j] = if j == lipL or j == lipR then gravelColour elseif j < lipL or j > lipR then grassColour else tarmacColour
		end
		-- a tight cliff edge's runoff is gravel (T-181): its strips take the gravel colour
		-- between two cuts whose middle is in a gravel run
		local gravelled = table.clone(colours)
		-- THE GRASS'S TEXTURE (T-187): its vertices get UVs in world studs, in the shared
		-- tile; a strip painted grass is mapped with them (`strip`)
		-- (loaded once, the first time a chunk asks: not that chunk's cost)
		-- THE TARMAC'S TEXTURE (T-268): when the ground draws the runoff the road's mesh has no
		-- grass, so its one texture is the tarmac's (painted in code, `Road/RoadTexture`)
		local g0 = os.clock()
		local tarmacImage = if groundRunoff then RoadTexture.get() else nil
		local grassImage = if tarmacImage then nil else GrassTexture.get()
		local g1 = os.clock()
		if g1 - g0 > 0.001 then
			-- it waited on the asset: not work, and the frame's slice starts afresh (T-193)
			paused += g1 - g0
			sliceStart = g1
		end
		local baseU, baseV = GrassTexture.base(centre)
		local baseS = RoadTexture.base(s0)
		if grassImage or tarmacImage then
			road.plainUV = road.em:AddUV(Vector2.zero)
			road.grassShade = {}
		end
		-- THE DOUBLE YELLOW (T-268 send-back 2): on the tight stretches only
		-- (`RoadTexture.centreRuns`), with a cut at each end of a run, so the line starts and
		-- stops square, on the same grid point in every chunk, near or far
		local runs = if tarmacImage then RoadTexture.centreRuns(spline, s0, s1) else {}
		if #runs > 0 then
			for _, b in runs do
				local dup = false
				for _, c in cuts do
					if math.abs(c - b) < 0.05 then
						dup = true
						break
					end
				end
				if not dup then
					table.insert(cuts, b)
				end
			end
			table.sort(cuts)
		end
		local tarmacRows: { { Vector3 } } = {} -- per cut, with a run: the drawn tarmac's points
		local lineTris = 0
		-- THE GRAVEL (T-270): with the tarmac's texture, the bevels are mapped to the image's
		-- gravel band, from the tarmac's edge (0) to their foot (`BandStuds`, or `RunFoot` in a
		-- gravel run, where gravel goes on past the foot), each row shaded by its tone
		local GV = Config.Spline.Gravel
		local baseG = RoadTexture.gravelBase(s0)
		local gravelRows: { any } = {} -- per cut: { [side] = { top, foot, run } UV ids, c = tone }
		local bevelTris = 0
		local prevG: any = nil
		local gravelOn = tarmacImage ~= nil and RoadTexture.gravelEnabled()
		local prevRow, prevNear, prevFar, prevS, prevUV = nil, nil, nil, 0, nil
		for k, s in cuts do
			local row, norm, pts = {}, {}, {}
			local wL, wR = spline:runoffAt(s, -1), spline:runoffAt(s, 1)
			local ds = {}
			for j = 0, RUNOFF_STRIPS - 1 do
				table.insert(ds, -half - wL * (1 - j / RUNOFF_STRIPS))
			end
			table.insert(ds, -half - spline:lipWidthAt(s, -1))
			for j = 0, across do
				table.insert(ds, -half + (2 * half) * j / across)
			end
			table.insert(ds, half + spline:lipWidthAt(s, 1))
			for j = 1, RUNOFF_STRIPS do
				table.insert(ds, half + wR * j / RUNOFF_STRIPS)
			end
			local uv: { [number]: number }? = if grassImage or tarmacImage then {} else nil
			for j, d in ds do
				local x, y, z = spline:terrainXYZ(s, d)
				pts[j] = Vector3.new(x, y, z)
				row[j] = road.em:AddVertex(Vector3.new(x - centre.X, y - centre.Y, z - centre.Z))
				norm[j] = road.em:AddNormal(spline:terrainNormal(s, d))
				road.vertices += 1
				-- the grass's vertices: the runoff either side, out from each bevel's foot
				if uv and tarmacImage then
					-- the tarmac's vertices, from the left edge to the right: mapped across and
					-- along, each shaded by its tone
					if j > lipL and j <= lipR then
						uv[j] = road.em:AddUV(RoadTexture.uv(s, d, baseS))
						local shade = road.grassShade
						if shade then
							shade[row[j]] = road.em:AddColor(RoadTexture.tone(s, d), 1)
						end
					end
				elseif uv and (j <= lipL or j > lipR) then
					uv[j] = road.em:AddUV(GrassTexture.uv(x, z, baseU, baseV))
					local shade = road.grassShade
					if shade then
						local k = GrassTexture.blotch(x, z)
						local g = TT.GrassColour
						shade[row[j]] = road.em:AddColor(Color3.new(math.min(1, g.R * k), math.min(1, g.G * k), math.min(1, g.B * k)), 1)
					end
				end
			end
			if #runs > 0 then
				local tp = {}
				for j = lipL + 1, lipR do
					table.insert(tp, pts[j])
				end
				tarmacRows[k] = tp
			end
			local gRow: any = nil
			if gravelOn then
				local em = road.em
				gRow = { c = (road.grassShade :: any)[row[lipL + 1]] }
				for _, side in { -1, 1 } do
					gRow[side] = {
						em:AddUV(RoadTexture.gravelUV(s, 0, baseG, side)),
						em:AddUV(RoadTexture.gravelUV(s, GV.BandStuds, baseG, side)),
						em:AddUV(RoadTexture.gravelUV(s, GV.RunFoot, baseG, side)),
					}
				end
				gravelRows[k] = gRow
			end
			-- each bevel's own normal: square to the road's way and to its slope, outward
			local yaw = spline:yawAt(s)
			local along = Vector3.new(-math.sin(yaw), spline:gradeAt(s), -math.cos(yaw))
			local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
			local function stepNormal(foot: Vector3, top: Vector3, side: number): number
				local n = along:Cross(top - foot)
				if n.Magnitude < 1e-6 then
					n = right * side
				elseif n:Dot(Vector3.yAxis) < 0 then
					n = -n
				end
				return road.em:AddNormal(n.Unit)
			end
			local nL = stepNormal(pts[lipL], pts[lipL + 1], -1)
			local nR = stepNormal(pts[lipR + 1], pts[lipR], 1)
			-- as the near side of a strip the left foot is on a bevel, as the far side the right
			-- foot is. A bevel's TOP keeps the tarmac's own normal (T-270 send-back 3, the user:
			-- "edit both gravel and road textures so that they mesh evenly"): lit the same as the
			-- tarmac at their seam, shading on down to its own slope at its foot, so no crease of
			-- light runs along the road's edge (it was flat at its slope, 19 degrees off: at noon
			-- 22% less sun than the tarmac beside it)
			local near, far = table.clone(norm), table.clone(norm)
			near[lipL] = nL
			far[lipR + 1] = nR
			if prevRow then
				local mid = (prevS + s) * 0.5
				local gL, gR = spline:gravelAt(mid, -1), spline:gravelAt(mid, 1)
				local use = colours
				if gL or gR then
					for j = 1, RUNOFF_STRIPS do
						gravelled[j] = if gL then gravelColour else grassColour
						gravelled[lipR + j] = if gR then gravelColour else grassColour
					end
					use = gravelled
				end
				-- the bevels' faces onto the gravel band: the left bevel's strip runs foot to top,
				-- the right one's top to foot
				local onFace: ((number, number, number) -> ())? = nil
				if gRow and prevG then
					local A, Bn = prevG, gRow
					onFace = function(i: number, f1: number, f2: number)
						if i ~= lipL and i ~= lipR then
							return
						end
						local side = if i == lipL then -1 else 1
						local inRun = if side < 0 then gL else gR
						local fi = if inRun then 3 else 2
						local ta, fa, tb, fb = A[side][1], A[side][fi], Bn[side][1], Bn[side][fi]
						local em = road.em
						if side < 0 then
							em:SetFaceUVs(f1, { fa, ta, fb })
							em:SetFaceUVs(f2, { ta, tb, fb })
						else
							em:SetFaceUVs(f1, { ta, fa, tb })
							em:SetFaceUVs(f2, { fa, fb, tb })
						end
						local ca, cb = A.c, Bn.c
						if ca and cb then
							em:SetFaceColors(f1, { ca, ca, cb })
							em:SetFaceColors(f2, { ca, cb, cb })
						end
						bevelTris += 2
					end
				end
				strip(road, prevRow, prevNear, row, near, false, use, prevFar, far, prevUV, uv, if tarmacImage then tarmacColour else grassColour, tarmacImage ~= nil, onFace)
			end
			prevG = gRow
			prevRow, prevNear, prevFar, prevS, prevUV = row, near, far, s, uv
			slice()
		end

		-- THE DOUBLE YELLOW's strips: two a run, each `CentreLineWidth` wide, `CentreLineGap`
		-- apart about the middle, mapped to the image's line band. Laid on the DRAWN tarmac
		-- (between its own vertices, so on a coarse far chunk they sit on its coarse surface)
		-- and lifted `CentreLineLift` along the normal, more on a coarser chunk
		if #runs > 0 then
			local em = road.em
			local lw, gap = R.CentreLineWidth, R.CentreLineGap
			local lineLift = R.CentreLineLift + (o.tolerance or M.Tolerance) * 0.25
			local edgesD = { { -gap * 0.5 - lw, -gap * 0.5 }, { gap * 0.5, gap * 0.5 + lw } }
			local function onTarmac(k: number, d: number): Vector3
				local tp = tarmacRows[k]
				local f = (d + half) / (2 * half) * across
				local i = math.clamp(math.floor(f), 0, across - 1)
				return tp[i + 1]:Lerp(tp[i + 2], f - i)
			end
			local made: { [number]: { [number]: any } } = {}
			local function rowOf(k: number, which: number): any
				made[k] = made[k] or {}
				local m = made[k][which]
				if m then
					return m
				end
				local s = cuts[k]
				local e = edgesD[which]
				local n = spline:terrainNormal(s, (e[1] + e[2]) * 0.5)
				local pL = onTarmac(k, e[1]) + n * lineLift
				local pR = onTarmac(k, e[2]) + n * lineLift
				m = {
					l = em:AddVertex(pL - centre),
					r = em:AddVertex(pR - centre),
					ul = em:AddUV(RoadTexture.lineUV(s, 0, baseS, which)),
					ur = em:AddUV(RoadTexture.lineUV(s, 1, baseS, which)),
					n = em:AddNormal(n),
					c = em:AddColor(RoadTexture.tone(s, 0), 1),
				}
				road.vertices += 2
				made[k][which] = m
				return m
			end
			for k = 1, #cuts - 1 do
				local mid = (cuts[k] + cuts[k + 1]) * 0.5
				local inRun = false
				for r = 1, #runs, 2 do
					if mid > runs[r] and mid < runs[r + 1] then
						inRun = true
						break
					end
				end
				if inRun then
					for which = 1, 2 do
						local a, b = rowOf(k, which), rowOf(k + 1, which)
						-- as the tarmac's strips: left to right, cut k to cut k + 1
						local f1 = em:AddTriangle(a.l, a.r, b.l)
						local f2 = em:AddTriangle(a.r, b.r, b.l)
						em:SetFaceNormals(f1, { a.n, a.n, b.n })
						em:SetFaceNormals(f2, { a.n, b.n, b.n })
						em:SetFaceColors(f1, { a.c, a.c, b.c })
						em:SetFaceColors(f2, { a.c, b.c, b.c })
						em:SetFaceUVs(f1, { a.ul, a.ur, b.ul })
						em:SetFaceUVs(f2, { a.ur, b.ur, b.ul })
						road.triangles += 2
						lineTris += 2
					end
				end
			end
			slice()
		end

		-- THE GRAVEL RUNOFF (T-270): a tight cliff edge's runoff is a narrow strip of gravel
		-- past the bevel's foot, drawn by the ground mesh (T-251) in plain gravel colour. A strip
		-- of this mesh is laid over it, from the bevel's foot to the runoff's lip, on the surface
		-- the car stands on there (`terrainXYZ`), lifted `RunoffLift` (more on a coarse chunk),
		-- and mapped to the gravel band's pure gravel (`RunFrom` to `RunFoot`)
		local gravelTris = 0
		if gravelOn and groundRunoff then
			local em = road.em
			local gLift = GV.RunoffLift + (o.tolerance or M.Tolerance) * 0.25
			local made: { [number]: { [number]: any } } = {}
			local function rowOf(k: number, side: number): any
				made[k] = made[k] or {}
				local m = made[k][side]
				if m then
					return m
				end
				local s = cuts[k]
				local dFoot = side * (half + spline:lipWidthAt(s, side))
				local dLip = side * (half + math.max(spline:runoffAt(s, side), spline:lipWidthAt(s, side)))
				local n = spline:terrainNormal(s, (dFoot + dLip) * 0.5)
				local pF = Vector3.new(spline:terrainXYZ(s, dFoot)) + n * gLift
				local pL = Vector3.new(spline:terrainXYZ(s, dLip)) + n * gLift
				local g = gravelRows[k]
				m = {
					foot = em:AddVertex(pF - centre),
					lip = em:AddVertex(pL - centre),
					uf = em:AddUV(RoadTexture.gravelUV(s, GV.RunFrom, baseG, side)),
					ul = em:AddUV(RoadTexture.gravelUV(s, GV.RunFoot, baseG, side)),
					n = em:AddNormal(n),
					c = g and g.c or em:AddColor(RoadTexture.tone(s, 0), 1),
				}
				road.vertices += 2
				made[k][side] = m
				return m
			end
			for k = 1, #cuts - 1 do
				local mid = (cuts[k] + cuts[k + 1]) * 0.5
				for _, side in { -1, 1 } do
					if spline:gravelAt(mid, side) then
						local a, b = rowOf(k, side), rowOf(k + 1, side)
						-- left to right across the road: on the left the lip is outermost
						local l0, r0, l1, r1 = a.lip, a.foot, b.lip, b.foot
						local ul0, ur0, ul1, ur1 = a.ul, a.uf, b.ul, b.uf
						if side > 0 then
							l0, r0, l1, r1 = a.foot, a.lip, b.foot, b.lip
							ul0, ur0, ul1, ur1 = a.uf, a.ul, b.uf, b.ul
						end
						local f1 = em:AddTriangle(l0, r0, l1)
						local f2 = em:AddTriangle(r0, r1, l1)
						em:SetFaceNormals(f1, { a.n, a.n, b.n })
						em:SetFaceNormals(f2, { a.n, b.n, b.n })
						em:SetFaceColors(f1, { a.c, a.c, b.c })
						em:SetFaceColors(f2, { a.c, b.c, b.c })
						em:SetFaceUVs(f1, { ul0, ur0, ul1 })
						em:SetFaceUVs(f2, { ur0, ur1, ul1 })
						road.triangles += 2
						gravelTris += 2
					end
				end
			end
			slice()
		end

		-- THE SKIRT (T-218) and the groves share one way of adding a face: flat-shaded, its
		-- normal and colour set per face, so a row's vertices are shared by every face that
		-- touches them
		local em = road.em
		local function tri(a: number, b: number, c: number, pa: Vector3, pb: Vector3, pc: Vector3, colour: number, facing: Vector3)
			local n = (pb - pa):Cross(pc - pa)
			if n.Magnitude < 1e-9 then
				return
			end
			if n:Dot(facing) < 0 then
				b, c = c, b
				n = -n
			end
			local f = em:AddTriangle(a, b, c)
			local nid = em:AddNormal(n.Unit)
			em:SetFaceNormals(f, { nid, nid, nid })
			em:SetFaceColors(f, { colour, colour, colour })
			road.triangles += 1
		end
		-- from each runoff's outer edge straight down `Ground.Skirt`, leaning out a little, so
		-- where the ground drawn apart dips below the edge (a ditch beside a cutting, a fill
		-- falling away) no gap shows. When the ground draws the runoff (T-251) there is no
		-- edge of the road's own out there: a short one, `BevelSkirt`, from each bevel's foot,
		-- under the ground wherever it is drawn finely, in the gravel's colour
		local T = Config.Spline.Terrain
		local G = Config.Spline.Ground
		local skirtColour = em:AddColor(if groundRunoff then T.GravelColour else G.SkirtColour, 1)
		local skirtDepth = if groundRunoff then G.BevelSkirt else G.Skirt
		local skirtLean = if groundRunoff then G.BevelSkirtLean else G.SkirtLean
		for _, side in { -1, 1 } do
			local tops, bottoms = table.create(#cuts), table.create(#cuts)
			local topP, bottomP = table.create(#cuts), table.create(#cuts)
			for k = 1, #cuts do
				local w = half + (if groundRunoff then spline:lipWidthAt(cuts[k], side) else spline:runoffAt(cuts[k], side))
				topP[k] = Vector3.new(spline:terrainXYZ(cuts[k], side * w))
				bottomP[k] = Vector3.new(spline:terrainXYZ(cuts[k], side * (w + skirtLean))) - Vector3.yAxis * skirtDepth
				tops[k] = em:AddVertex(topP[k] - centre)
				bottoms[k] = em:AddVertex(bottomP[k] - centre)
				road.vertices += 2
			end
			for k = 1, #cuts - 1 do
				local yaw = spline:yawAt((cuts[k] + cuts[k + 1]) * 0.5)
				local outward = Vector3.new(side * math.cos(yaw), 0, -side * math.sin(yaw))
				tri(tops[k], bottoms[k], tops[k + 1], topP[k], bottomP[k], topP[k + 1], skirtColour, outward)
				tri(bottoms[k], bottoms[k + 1], tops[k + 1], bottomP[k], bottomP[k + 1], topP[k + 1], skirtColour, outward)
			end
			slice()
		end

		-- THE GROVES (T-183): trees and bushes on a widened runoff, in this same mesh, so a
		-- grove costs triangles and no parts (`Road/SplineGrove`)
		-- (measured: 13 ms a grove chunk in one go, 20 at worst). Its trees are drawn a few ms a
		-- frame like the rest (T-193): `slice()` between the triangles
		slice()
		local groveColours: { [Color3]: number } = {}
		local trianglesBefore, treeT0 = road.triangles, os.clock()
		-- A FAR CHUNK'S TREES ARE LEAN (T-273): no trunk and no flat underside, a few pixels
		-- out there, so the same outline costs about half the mesh memory
		local lean = o.leanTrees == true
		local skipped = 0
		local trunkColour = T.TrunkColour
		local trees = SplineGrove.draw(spline, s0, s1, {
			vertex = function(p: Vector3): number
				road.vertices += 1
				return em:AddVertex(p - centre)
			end,
			tri = function(a: number, b: number, c: number, pa: Vector3, pb: Vector3, pc: Vector3, colour: Color3, facing: Vector3)
				if lean then
					local n = (pb - pa):Cross(pc - pa)
					if n:Dot(facing) < 0 then
						n = -n
					end
					if colour == trunkColour or (n.Magnitude > 1e-9 and n.Unit.Y < -0.9) then
						skipped += 1
						return
					end
				end
				local id = groveColours[colour]
				if not id then
					id = em:AddColor(colour, 1)
					groveColours[colour] = id
				end
				tri(a, b, c, pa, pb, pc, id, facing)
				slice()
			end,
		})
		local treeMs = (os.clock() - treeT0) * 1000
		if skipped > 0 then
			-- (the trunks' and undersides' vertices too: a fixed-size copy keeps every vertex)
			em:RemoveUnused()
		end

		local model = Instance.new("Model")
		model.Name = `Chunk_{math.floor(s0)}`
		model:SetAttribute("Trees", trees)
		model:SetAttribute("S0", s0)
		model:SetAttribute("S1", s1)
		-- white, so the vertex colours are what show
		slice()
		local roadPart = toPart(road, "Road", Color3.new(1, 1, 1), R.RoadMaterial, tarmacImage or (if grassImage then Content.fromObject(grassImage) else nil))
		roadPart.Parent = model
		slice()
		local parts = 0

		local function plain(name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material): Part
			local part = Instance.new("Part")
			part.Name = name
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			-- guardrails cast (T-178); bolts and dashes, too small or too
			-- flat to show one, are switched off where they are made
			part.CastShadow = true
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Material = material
			part.Color = colour
			part.Size = size
			part.CFrame = cf
			part.Parent = model
			parts += 1
			slice()
			return part
		end

		-- THE GUARDRAIL's pieces (T-149), placed from the tarmac's edge on `side`, `u` out from
		-- it and `y` above the ground there. The W-beam's profile, from the road: two rounded
		-- ridges (flattened cylinders) `KRailRidge` deep, the groove between them set back; a
		-- spacer block behind the groove, and a square post behind that
		local railMaterial = Enum.Material.Metal
		local ridgeH = T.KRailBeam * 0.45 -- each ridge's height; the groove shows between them
		local grooveU = T.KRailRidge * 0.45 -- the groove's face, set back from the ridges'
		local backU = T.KRailRidge -- the beam's back
		-- a piece of beam between `a` and `b`, pitched along the road: a cylinder runs along
		-- the chord (its axis is its X), a box stands upright across the road
		local function beam(name: string, a: number, b: number, side: number, u: number, y: number, h: number, depth: number, round: boolean)
			local off = side * (half + u)
			local ax, _, az = spline:terrainXYZ(a, off)
			local bx, _, bz = spline:terrainXYZ(b, off)
			local pa = Vector3.new(ax, spline:terrainY(a, side * half) + y, az)
			local pb = Vector3.new(bx, spline:terrainY(b, side * half) + y, bz)
			local chord = pb - pa
			local len = chord.Magnitude
			if len > 1e-3 then
				local mid = (pa + pb) * 0.5
				local cf = CFrame.lookAt(mid, mid + chord, Vector3.yAxis)
				if round then
					local part = plain(name, Vector3.new(len + 0.1, h, depth), cf * CFrame.Angles(0, math.pi * 0.5, 0), T.KRailColour, railMaterial)
					part.Shape = Enum.PartType.Cylinder
				else
					plain(name, Vector3.new(depth, h, len + 0.1), cf, T.KRailColour, railMaterial)
				end
			end
		end
		-- upright at `s`, looking along the road (level), `u` out and `y` up
		local function uprightAt(s: number, side: number, u: number, y: number): CFrame
			local x, _, z = spline:terrainXYZ(s, side * (half + u))
			local x0, _, z0 = spline:terrainXYZ(s - 0.5, 0)
			local x1, _, z1 = spline:terrainXYZ(s + 0.5, 0)
			local pos = Vector3.new(x, spline:terrainY(s, side * half) + y, z)
			return CFrame.lookAt(pos, pos + Vector3.new(x1 - x0, 0, z1 - z0), Vector3.yAxis)
		end
		-- a square post and its spacer block, and at a splice the bolt heads in the groove
		local function post(id: string, s: number, side: number, splice: boolean)
			local d, sp = T.KRailPostSize, T.KRailSpacer
			-- a post stands past the road's step, so it reaches down to the grass (T-184)
			local sink, top = 1 + T.RoadLip, T.KRailHeight - 0.15
			plain(`KRailPost_{id}`, Vector3.new(d, top + sink, d), uprightAt(s, side, backU + sp + d * 0.5, (top - sink) * 0.5), T.KRailColour, railMaterial)
			plain(`KRailSpacer_{id}`, Vector3.new(backU + sp - grooveU, T.KRailBeam * 0.6, d * 0.8), uprightAt(s, side, (grooveU + backU + sp) * 0.5, T.KRailHeight - T.KRailBeam * 0.5), T.KRailColour, railMaterial)
			if splice then
				local n = T.KRailSpliceBolts
				for i = 1, n do
					local along = (i - (n + 1) * 0.5) * 0.5
					local cf = uprightAt(s, side, grooveU - 0.03, T.KRailHeight - T.KRailBeam * 0.5) * CFrame.new(0, 0, -along)
					-- a cylinder's axis is its X: across the road, a round head facing it
					local bolt = plain(`KRailBolt_{id}_{i}`, Vector3.new(0.08, 0.16, 0.16), cf, T.KRailBoltColour, Enum.Material.Metal)
					bolt.Shape = Enum.PartType.Cylinder
					bolt.CastShadow = false
				end
			end
		end
		-- the hazard panel at an end of a run: upright across the road over the beam's end,
		-- its striped face looking away from the run (`outward` 1: on along the road, -1: back)
		local function hazardPanel(name: string, s: number, side: number, outward: number)
			local w, y0, y1 = 1.5, 0.5, T.KRailHeight + 0.1
			local cf = uprightAt(s, side, w * 0.5 - 0.05, (y0 + y1) * 0.5)
			if outward < 0 then
				cf *= CFrame.Angles(0, math.pi, 0)
			end
			local part = plain(name, Vector3.new(w, y1 - y0, 0.12), cf, T.KRailColour, railMaterial)
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.LightInfluence = 1
			local frame = Instance.new("Frame")
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.Size = UDim2.new(1, -10, 1, -10) -- a galvanized rim round the stripes
			frame.BorderSizePixel = 0
			frame.BackgroundColor3 = Color3.new(1, 1, 1)
			local gradient = Instance.new("UIGradient")
			gradient.Color = hazardStripes
			gradient.Rotation = 55
			gradient.Parent = frame
			frame.Parent = gui
			gui.Parent = part
		end

		for _, side in { -1, 1 } do
			local tag = if side < 0 then "L" else "R"
			-- K-RAILS, drawn as a metal crash barrier (T-149): the beam's face on the tarmac's
			-- edge, where the car's wall begins (`Drift/SplineWorld`), its top at
			-- `KRailHeight`; spacers and posts behind it, inside that wall; a hazard panel at
			-- each end of the run
			local H, B = T.KRailHeight, T.KRailBeam
			local runs = spline:kRailsIn(s0, s1, side)
			for r = 1, #runs, 2 do
				local ra, rb = runs[r], runs[r + 1]
				local id = `{tag}_{math.floor(ra)}`
				-- the beam: a piece per stretch, as long as `KRailStep` on a straight and
				-- short enough round a bend that its chord keeps to the curve
				-- (its ends stop short of the hazard panels' faces, so no piece pokes through)
				local a = math.max(ra + 0.15, s0)
				local stop = math.min(rb - 0.15, s1)
				local n = 0
				while stop - a > 0.05 do
					local k = math.abs(spline:curvatureAt(a))
					local kEdge = k / math.max(0.2, 1 - k * half) -- the tighter, inside edge
					local step = if kEdge > 1e-6 then math.clamp(math.sqrt(8 * T.KRailChordTolerance / kEdge), 2, T.KRailStep) else T.KRailStep
					local b = math.min(a + step, stop)
					if stop - b < 1 then
						b = stop -- no sliver at the end
					end
					n += 1
					beam(`KRailTop_{id}_{n}`, a, b, side, backU * 0.5, H - ridgeH * 0.5, ridgeH, backU, true)
					beam(`KRailGroove_{id}_{n}`, a, b, side, (grooveU + backU) * 0.5, H - B * 0.5, B - ridgeH, backU - grooveU, false)
					beam(`KRailLow_{id}_{n}`, a, b, side, backU * 0.5, H - B + ridgeH * 0.5, ridgeH, backU, true)
					a = b
				end
				-- the posts: on a pattern from the run's own start, so a run drawn across two
				-- chunks has the same posts in both, and one near its very end
				local every, inset = T.KRailPostEvery, 1
				local j = math.max(0, math.ceil((s0 - ra - inset) / every))
				while true do
					local p = ra + inset + j * every
					local last = false
					if p > rb - inset - every * 0.3 then
						p, last = rb - inset, true
					end
					if p >= s1 then
						break
					end
					if p >= s0 then
						post(`{id}_{j}`, p, side, j > 0 and not last and j % T.KRailSpliceEvery == 0)
					end
					if last then
						break
					end
					j += 1
				end
				-- the hazard panels, each drawn by the chunk it stands in
				if ra >= s0 and ra < s1 then
					hazardPanel(`KRailEnd_{id}_A`, ra, side, -1)
				end
				if rb >= s0 and rb < s1 then
					hazardPanel(`KRailEnd_{id}_B`, rb, side, 1)
				end
			end
		end

		-- the centre line: a flat box per dash on the global pattern, so the dashes run on
		-- across chunks, its painted face `MarkLift` above the surface along its normal.
		-- None on a textured tarmac: the texture paints the lines (T-268)
		local interval, dash = R.MarkInterval, R.MarkDashLength
		local start = math.floor(s0 / interval) * interval
		if tarmacImage then
			start = s1
		end
		while start < s1 do
			local a, b = math.max(start, s0), math.min(start + dash, s1)
			if b - a >= R.MarkMinLength then
				local pa = Vector3.new(spline:surfaceXYZ(a, 0))
				local pb = Vector3.new(spline:surfaceXYZ(b, 0))
				local n = spline:normalAt((a + b) * 0.5, 0)
				local along = pb - pa
				local len = along.Magnitude
				if len > 1e-3 then
					local fwd = along / len
					local right = fwd:Cross(n).Unit
					local up = right:Cross(fwd)
					local centreOf = (pa + pb) * 0.5 + up * (R.MarkLift - R.MarkThickness * 0.5)
					local mark = plain("Mark", Vector3.new(R.MarkWidth, R.MarkThickness, len), CFrame.fromMatrix(centreOf, right, up), R.Colours.Marking, Enum.Material.SmoothPlastic)
					mark.CastShadow = false
				end
			end
			start += interval
		end

		local stats = {
			sections = #cuts,
			vertices = road.vertices,
			triangles = road.triangles,
			grassTriangles = road.grassTriangles, -- textured (T-187)
			tarmacTriangles = road.tarmacTriangles, -- textured (T-268)
			centreLineTriangles = lineTris, -- the double yellow's strips (T-268)
			centreRuns = #runs // 2,
			bevelTriangles = bevelTris, -- the bevels mapped to the gravel band (T-270)
			gravelTriangles = gravelTris, -- the strips over gravel runoff (T-270)
			textured = grassImage ~= nil or tarmacImage ~= nil,
			grassTextured = grassImage ~= nil,
			tarmacTextured = tarmacImage ~= nil,
			parts = parts,
			trees = trees,
			treeTriangles = road.triangles - trianglesBefore,
			treeMs = treeMs,
			ms = 0,
		}
		-- (an opaque chunk holds no EditableMesh: its content goes with its part)
		stats.opaque = road.held == nil
		return { model = model, stats = stats, meshes = if road.held then { road.held } else {} }
	end)
	if not ok then
		-- never leak one: a fixed-size mesh it kept is let go
		if road.held then
			road.held:Destroy()
		end
		return nil, tostring(built)
	end
	local result = built :: any
	meshesOf[result.model] = result.meshes
	-- the parent may have gone while the chunk was built over several frames (T-193)
	local placed = pcall(function()
		result.model.Parent = parent
	end)
	worstSlice = math.max(worstSlice, os.clock() - sliceStart)
	result.stats.ms = (os.clock() - t0 - paused) * 1000
	result.stats.slices = slices -- frames the build was spread over
	result.stats.sliceMs = worstSlice * 1000 -- the most of it any one frame paid
	result.stats.asyncMs = asyncWait * 1000 -- waiting on the engine (T-274), not in `ms`
	if not placed then
		SplineMesh.destroy(result.model)
		return nil, "the chunk's parent went while it was built"
	end
	return result.model, result.stats
end

-- Take a chunk down, with the mesh data its parts are drawn from.
function SplineMesh.destroy(model: Model)
	local meshes = meshesOf[model]
	meshesOf[model] = nil
	model:Destroy()
	if meshes then
		for _, em in meshes do
			em:Destroy()
		end
	end
end

if RunService:IsClient() then
	task.defer(SplineMesh.prepare)
end

return SplineMesh
