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
--               side, and the faces of the mountainside -- a rock face rising from the
--               grass, faceted, its height and lean changing along the road; a cliff face
--               dropping from the grass's lip into haze. Faces are flat-shaded on purpose:
--               very low poly, programmer colours. And a grove's trees and bushes (T-183,
--               `Road/SplineGrove`), faceted the same way
--   RockShade_* plain boxes standing unseen behind each rock face, casting its shadow,
--               since a mesh drawn from an EditableMesh casts none (T-178)
--   Edge_*      a hedge: a green box per cross-section, at the grass's outer edge
--   KRail*_*    a K-rail run drawn as a METAL CRASH BARRIER (T-149): a W-beam guardrail,
--               its beam two rounded ridges (`KRailTop_*`, `KRailLow_*`) and the groove
--               between (`KRailGroove_*`), a piece per stretch of the run, pitched along the
--               grade and cut finer round a bend; square posts (`KRailPost_*`) every
--               `KRailPostEvery` on spacer blocks (`KRailSpacer_*`), bolt heads at each
--               splice (`KRailBolt_*`), a striped hazard panel at each end (`KRailEnd_*`)
--   Mark        a flat box per dash of the centre line, `MarkLift` above the surface
--
-- Only the surface is a mesh because a client may hold only eight EditableMeshes at once and
-- a MeshPart is drawn from its EditableMesh for as long as it exists (see `build`).
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

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)
local SplineGrove = require(script.Parent.SplineGrove)

local SplineMesh = {}

local meshesOf: { [Model]: { EditableMesh } } = setmetatable({}, { __mode = "k" }) :: any

-- THE CLIFFS' HAZE follows the sky (features/day-night.md, T-144): the colour ids each live
-- mesh drew its haze with, so `setHaze` can recolour every drawn chunk in place, and the
-- colour new chunks are drawn with.
local hazeOf: { [EditableMesh]: { haze: number, mid: number } } = setmetatable({}, { __mode = "k" }) :: any
local hazeColour: Color3? = nil -- nil: `Config.Spline.Terrain.HazeColour`

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

-- THE PROFILE OF AN EDGE'S FACE at `s` on `side`: the points of its cross-section, world
-- space, from the grass's outer edge outward. The same on every device, from `s` alone.
--
--   ROCK   A SOLID BODY (T-185): the foot on the grass, a jagged face up to its top at
--          `RockHeight` leaning back at `RockSlope`, a top of scrub `RockTop` deep, and a
--          back slope down to the ground again, `RockBack` of its height behind. Height, lean
--          and jag wander along the road on slow sines, so the face is never a wall of one
--          height; and all of it grows with the road's grandeur (`Spline.grandAt`) toward the
--          `Grand` numbers, huge mid-leg. On the inside of a bend the body is drawn squeezed
--          rather than reach past the bend's centre
--   CLIFF  the lip, then a jagged face dropping `CliffDrop` (to `GrandCliffDrop`, grand) and
--          stepping out a little as it goes
-- Traversed so the body is always on the right of the profile's way (out, then up and
-- over, or out and down): each quad faces (-dUp, dOut), away from the mountain.
local function wave(s: number, a: number, b: number): number
	-- two slow sines with no common period: 0..1, smooth, the same everywhere
	return 0.5 + 0.3 * math.sin(s / a) + 0.2 * math.sin(s / b + 1.7)
end

function SplineMesh.profile(spline: Spline.Spline, s: number, side: number, kind: number): { Vector3 }
	local T = Config.Spline.Terrain
	local w = Config.Road.Width * 0.5 + spline:runoffAt(s, side)
	local x, z = spline:planAt(s)
	local yaw = spline:yawAt(s)
	local rx, rz = math.cos(yaw), -math.sin(yaw)
	local y0 = spline:terrainY(s, side * w)
	local g = spline:grandAt(s)
	local function grand(near: number, far: number): number
		return near + (far - near) * g
	end
	local pts: { { number } } -- {out, up}
	if kind == Spline.ROCK then
		local hLo, hHi = grand(T.RockHeight[1], T.GrandRockHeight[1]), grand(T.RockHeight[2], T.GrandRockHeight[2])
		local h = hLo + (hHi - hLo) * wave(s + side * 311, 61, 23)
		local lLo, lHi = grand(T.RockSlope[1], T.GrandRockSlope[1]), grand(T.RockSlope[2], T.GrandRockSlope[2])
		local lean = math.rad(lLo + (lHi - lLo) * wave(s - side * 173, 43, 17))
		local run = h / math.tan(lean)
		local jagSize = 2.5 + 7 * g
		local jag = jagSize * (wave(s * 3.1, 7, 3) - 0.5)
		local jag2 = jagSize * (wave(s * 2.3 + 50, 5, 11) - 0.5)
		local top = grand(T.RockTop[1], T.RockTop[2])
		local crest = h + 4 + 6 * g
		pts = {
			{ 0, 0 },
			{ run * 0.3 + jag, h * 0.3 },
			{ run * 0.62 + jag2, h * 0.64 },
			{ run, h },
			{ run + top, crest },
			{ run + top + T.RockBack * h, 0 },
		}
		-- the inside of a bend: never past 90% of the way to its centre
		local k = spline:curvatureAt(s)
		if k ~= 0 and (k > 0) == (side < 0) then
			local room = 0.9 / math.abs(k) - w
			local reach = pts[#pts][1]
			if room < reach then
				local scale = math.max(room, 0.5) / reach
				for _, p in pts do
					p[1] *= scale
				end
			end
		end
	else
		-- never deeper than `GrandCliffDrop`: the valley floor is below that
		local drop = grand(T.CliffDrop, T.GrandCliffDrop) * (0.8 + 0.2 * wave(s - side * 97, 53, 19))
		local jagSize = 1.5 + 4 * g
		local reach = 7 + 9 * g
		pts = {
			{ 0, 0 },
			{ 1.5, -drop * 0.06 },
			{ reach * 0.45 + jagSize * (wave(s * 2.7 + 9, 6, 13) - 0.5), -drop * 0.3 },
			{ reach * 0.7 + jagSize * (wave(s * 1.9 + 31, 8, 5) - 0.5), -drop * 0.62 },
			{ reach, -drop },
		}
	end
	local out = {}
	for i, p in pts do
		local d = side * (w + p[1])
		out[i] = Vector3.new(x + d * rx, y0 + p[2], z + d * rz)
	end
	return out
end

-- A mesh in the making: vertices relative to `centre`, with normals.
type Builder = {
	em: EditableMesh,
	centre: Vector3,
	vertices: number,
	triangles: number,
}


-- A quad strip between two rows of vertex ids, each with its normal id. `colours`, when
-- given, is a colour id per strip (between vertex i and i + 1), painted on both triangles.
-- `farA` / `farB`, when given, are the normals a vertex has as the FAR side of a strip
-- (vertex i + 1 of strip i), so one vertex can be smooth on one strip and flat on the next:
-- the road's step (T-184).
local function strip(b: Builder, rowA: { number }, normA: { number }, rowB: { number }, normB: { number }, flip: boolean, colours: { number }?, farA: { number }?, farB: { number }?)
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
		end
		b.triangles += 2
	end
end

local function newBuilder(centre: Vector3): Builder
	local em = AssetService:CreateEditableMesh({ FixedSize = false })
	-- nil is the device saying no: out of its EditableMesh budget
	assert(em, "this device would not make an EditableMesh (out of its budget)")
	return { em = em :: EditableMesh, centre = centre, vertices = 0, triangles = 0 }
end

-- A MeshPart made from an EditableMesh keeps the vertices exactly where they were written,
-- relative to the part (measured: not re-centred), while its Size -- and so what Roblox culls
-- it by -- is the bounding box. So the vertices are moved to be centred on their own box
-- first, and the part is put where that box is.
local function toPart(b: Builder, name: string, colour: Color3, material: Enum.Material): MeshPart
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, v in b.em:GetVertices() do
		local p = b.em:GetPosition(v)
		lo, hi = lo:Min(p), hi:Max(p)
	end
	local mid = (lo + hi) * 0.5
	for _, v in b.em:GetVertices() do
		b.em:SetPosition(v, b.em:GetPosition(v) - mid)
	end
	local ok, part = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(b.em), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)
	if not ok then
		part = AssetService:CreateMeshPartAsync(Content.fromObject(b.em))
	end
	local mp = part :: MeshPart
	mp.Name = name
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	-- Set, but it does nothing (T-178, measured in the lane): a MeshPart drawn from an
	-- EditableMesh casts no shadow at all, either side of its faces. The rock faces' shadow
	-- comes from the plain `RockShade_*` parts behind them (`build`).
	mp.CastShadow = true
	mp.Color = colour
	mp.Material = material
	mp.CFrame = CFrame.new(b.centre + mid)

	return mp
end

-- Draw [s0, s1] of the road under a new Model in `parent`. Returns the model and what it
-- cost, or nil and the reason when this device cannot make a mesh.
function SplineMesh.build(spline: Spline.Spline, s0: number, s1: number, parent: Instance, opts: Options?): (Model?, any)
	local o: Options = opts or {}
	local t0 = os.clock()
	local paused = 0 -- seconds spent waiting a frame between the road and its trees
	local R = Config.Road
	local M = Config.Spline.Mesh
	local half = R.Width * 0.5
	local across = o.across or M.Across
	local cuts = SplineMesh.sections(spline, s0, s1, o)
	local cx, cy, cz = spline:surfaceXYZ((s0 + s1) * 0.5, 0)
	local centre = Vector3.new(cx, cy, cz)

	if o.forceFail then
		return nil, "forced (a test standing in for a device that cannot make meshes)"
	end
	local made, road = pcall(newBuilder, centre)
	if not made then
		return nil, tostring(road)
	end
	local ok, built = pcall(function()
		-- ONE EDITABLEMESH A CHUNK, AND IT STAYS ALIVE WITH IT. A MeshPart made from one is
		-- drawn from it: let it go and the part draws nothing (measured -- the road vanished).
		-- And a client may hold only EIGHT at once, whatever their size (measured in a Studio
		-- client: 8 empty, 8 of 2 000 vertices, 8 of 20 000). So the mesh is spent on what only
		-- a mesh can draw -- the surface, which curves, banks and twists -- and the barriers and
		-- the centre line are plain parts, as the piece road's are: upright boxes and flat
		-- dashes, which a box draws exactly.
		-- the surface: the left runoff in `RUNOFF_STRIPS` strips, the tarmac in `across`,
		-- the right runoff in `RUNOFF_STRIPS`; a row of vertices per cross-section. The
		-- runoff's width changes along the road, so each row places its own grass vertices
		-- THE ROAD'S GRAVEL BEVEL (T-184): one more strip each side between the tarmac and
		-- the grass, `Spline:lipWidthAt` across (`RoadLipWidth`), sloping down `RoadLip` to the
		-- grass, in the gravel's colour. It is shaded FLAT across (its own normal), so it reads
		-- as an angled shoulder; the tarmac and the grass either side keep their smooth normals.
		local RUNOFF_STRIPS = 2
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
		local prevRow, prevNear, prevFar, prevS = nil, nil, nil, 0
		for _, s in cuts do
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
			for j, d in ds do
				local x, y, z = spline:terrainXYZ(s, d)
				pts[j] = Vector3.new(x, y, z)
				row[j] = road.em:AddVertex(Vector3.new(x - centre.X, y - centre.Y, z - centre.Z))
				norm[j] = road.em:AddNormal(spline:terrainNormal(s, d))
				road.vertices += 1
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
			-- as the near side of a strip the left foot and the right top are on a bevel; as
			-- the far side, the left top and the right foot are
			local near, far = table.clone(norm), table.clone(norm)
			near[lipL], near[lipR] = nL, nR
			far[lipL + 1], far[lipR + 1] = nL, nR
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
				strip(road, prevRow, prevNear, row, near, false, use, prevFar, far)
			end
			prevRow, prevNear, prevFar, prevS = row, near, far, s
		end

		-- THE FACES OF THE MOUNTAINSIDE, in the same mesh: a client may hold only eight
		-- EditableMeshes and the road's window uses six, so the faces cannot have meshes of
		-- their own. Between each pair of cuts, on each side whose edge is a rock face or a
		-- cliff, a few quads of the profile `SplineMesh.profile` gives, flat-shaded.
		local em = road.em
		-- FLAT-SHADED BUT SHARED: a face's normal and colour are set per face, so the
		-- vertices of a row are shared by every face that touches them (a third of the
		-- vertices, and a third of the cost, of a vertex per corner)
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
		local T = Config.Spline.Terrain
		local faceColours = {}
		local haze = hazeColour or T.HazeColour
		for name, c in { rock = T.RockColour, scrub = T.ScrubColour, cliff = T.CliffColour, haze = haze } do
			faceColours[name] = em:AddColor(c, 1)
		end
		local cliffMid = em:AddColor(T.CliffColour:Lerp(haze, 0.5), 1)
		hazeOf[em] = { haze = faceColours.haze, mid = cliffMid }
		for _, side in { -1, 1 } do
			-- one row of vertices per cut and kind, made the first time a face needs it
			local rows: { [number]: { pts: { Vector3 }, ids: { number }, kind: number } } = {}
			local function rowAt(k: number, kind: number)
				local row = rows[k]
				if row and row.kind == kind then
					return row
				end
				local pts = SplineMesh.profile(spline, cuts[k], side, kind)
				local ids = table.create(#pts)
				for i, p in pts do
					ids[i] = em:AddVertex(p - centre)
				end
				road.vertices += #pts
				row = { pts = pts, ids = ids, kind = kind }
				rows[k] = row
				return row
			end
			-- the edge between each pair of cuts, and the one just before the chunk (so a body
			-- running on from the last chunk gets no end drawn across it)
			local kinds = table.create(#cuts - 1)
			for k = 1, #cuts - 1 do
				kinds[k] = spline:edgeAt((cuts[k] + cuts[k + 1]) * 0.5, side)
			end
			kinds[0] = if cuts[1] > 0 then spline:edgeAt(cuts[1] - 0.01, side) else kinds[1]
			local sEnd = cuts[#cuts]
			kinds[#cuts] = if sEnd < spline.length - 0.01 then spline:edgeAt(sEnd + 0.01, side) else kinds[#cuts - 1]
			-- AN END: where a body starts or stops, its profile is closed with a fan of
			-- triangles round its middle, facing along the road out of the body (T-185). A
			-- cliff's is closed straight down from just past its lip (past it, so no point of
			-- the body stands where the grass is)
			local function cap(row: { pts: { Vector3 }, ids: { number }, kind: number }, s: number, facingSign: number)
				local pts, ids = table.clone(row.pts), table.clone(row.ids)
				if row.kind == Spline.CLIFF then
					local lip = pts[1]:Lerp(pts[2], 0.3)
					local under = Vector3.new(lip.X, pts[#pts].Y, lip.Z)
					table.insert(pts, under)
					table.insert(ids, em:AddVertex(under - centre))
					road.vertices += 1
				end
				local mid = Vector3.zero
				for _, p in pts do
					mid += p
				end
				mid /= #pts
				local midId = em:AddVertex(mid - centre)
				road.vertices += 1
				local yaw = spline:yawAt(s)
				local facing = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)) * facingSign
				local colour = if row.kind == Spline.ROCK then faceColours.rock else cliffMid
				for i = 1, #pts do
					local j = i % #pts + 1
					tri(midId, ids[i], ids[j], mid, pts[i], pts[j], colour, facing)
				end
			end
			for k = 1, #cuts - 1 do
				local a, b = cuts[k], cuts[k + 1]
				local kind = kinds[k]
				if kind == Spline.ROCK or kind == Spline.CLIFF then
					local ra, rb = rowAt(k, kind), rowAt(k + 1, kind)
					local yaw = spline:yawAt((a + b) * 0.5)
					local outward = Vector3.new(side * math.cos(yaw), 0, -side * math.sin(yaw))
					local pa, pb, ia, ib = ra.pts, rb.pts, ra.ids, rb.ids
					for i = 1, #pa - 1 do
						local colour
						if kind == Spline.ROCK then
							colour = if i == #pa - 2 then faceColours.scrub else faceColours.rock
						else
							colour = if i == 1 then faceColours.cliff elseif i == #pa - 1 then faceColours.haze else cliffMid
						end
						-- each quad faces away from the body: the profile's way turned (-up, out)
						local e = pa[i + 1] - pa[i]
						local facing = outward * -e.Y + Vector3.yAxis * e:Dot(outward)
						tri(ia[i], ia[i + 1], ib[i], pa[i], pa[i + 1], pb[i], colour, facing)
						tri(ia[i + 1], ib[i + 1], ib[i], pa[i + 1], pb[i + 1], pb[i], colour, facing)
					end
					if kinds[k - 1] ~= kind then
						cap(ra, a, -1)
					end
					if kinds[k + 1] ~= kind then
						cap(rb, b, 1)
					end
				end
			end
		end

		-- THE GROVES (T-183): trees and bushes on a widened runoff, in this same mesh, so a
		-- grove costs triangles and no parts (`Road/SplineGrove`)
		-- A chunk with a grove is built over two frames, the road then its trees, so neither
		-- frame pays for both (measured: 13 ms a grove chunk in one go, 20 at worst)
		if #SplineGrove.items(spline, s0, s1, -1) + #SplineGrove.items(spline, s0, s1, 1) > 0 then
			local w0 = os.clock()
			task.wait()
			paused += os.clock() - w0
		end
		local groveColours: { [Color3]: number } = {}
		local trianglesBefore, treeT0 = road.triangles, os.clock()
		local trees = SplineGrove.draw(spline, s0, s1, {
			vertex = function(p: Vector3): number
				road.vertices += 1
				return em:AddVertex(p - centre)
			end,
			tri = function(a: number, b: number, c: number, pa: Vector3, pb: Vector3, pc: Vector3, colour: Color3, facing: Vector3)
				local id = groveColours[colour]
				if not id then
					id = em:AddColor(colour, 1)
					groveColours[colour] = id
				end
				tri(a, b, c, pa, pb, pc, id, facing)
			end,
		})
		local treeMs = (os.clock() - treeT0) * 1000

		local model = Instance.new("Model")
		model.Name = `Chunk_{math.floor(s0)}`
		model:SetAttribute("Trees", trees)
		model:SetAttribute("S0", s0)
		model:SetAttribute("S1", s1)
		-- white, so the vertex colours are what show
		local roadPart = toPart(road, "Road", Color3.new(1, 1, 1), R.RoadMaterial)
		roadPart.Parent = model
		local parts = 0

		local function plain(name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material): Part
			local part = Instance.new("Part")
			part.Name = name
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			-- hedges, walls and guardrails cast (T-178); bolts and dashes, too small or too
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
			return part
		end

		-- an upright box along the road between two cuts, its foot on the ground at lateral
		-- `inner .. inner + thick` (signed by side) as the old barriers were: UPRIGHT ACROSS
		-- THE ROAD but PITCHED ALONG IT, so its top follows the grade instead of stepping;
		-- carried down `sink` so a crest never shows daylight under it
		local function wall(name: string, a: number, b: number, side: number, innerA: number, innerB: number, thick: number, height: number, sink: number, colour: Color3, material: Enum.Material)
			local offA, offB = side * (innerA + thick * 0.5), side * (innerB + thick * 0.5)
			local ax, _, az = spline:terrainXYZ(a, offA)
			local bx, _, bz = spline:terrainXYZ(b, offB)
			local pa = Vector3.new(ax, spline:terrainY(a, side * innerA), az)
			local pb = Vector3.new(bx, spline:terrainY(b, side * innerB), bz)
			local chord = pb - pa
			local len = chord.Magnitude
			if len > 1e-3 then
				local mid = (pa + pb) * 0.5 + Vector3.yAxis * ((height - sink) * 0.5)
				plain(name, Vector3.new(thick, height + sink, len + 0.2), CFrame.lookAt(mid, mid + chord, Vector3.yAxis), colour, material)
			end
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
		-- THE ROCK FACES' SHADOW (T-178). The mesh casts none -- a MeshPart drawn from an
		-- EditableMesh casts no shadow, measured: a low sun shone straight through a 40-stud
		-- rock face onto the car, and a plain part put where the face is shaded it. So each
		-- rock face has plain boxes standing just behind it, inside the mountain, foot to top,
		-- a box per `RockShadeStep` of road at most: they cast the face's shadow and are never
		-- seen, the face is in front of them and its ledge above them.
		-- A CLIFF FACE the same way, and the road's surface (below): a cliff's boxes stand
		-- behind its face, on the road's side, from a few studs under the lip to its foot,
		-- `CliffShadeThickness` thick, so light cannot come up through the drop.
		local shadeStep = T.RockShadeStep
		local shadeBack = T.RockShadeBack
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "L" else "R"
			-- A ROCK BODY'S TOP (T-185): a second box under its scrub top, from the face's top
			-- edge to the crest, `shadeBack` down inside the body and short of both ends, so a
			-- grand body's whole height casts and the box is never seen
			local function shadeTop(ka: number, kb: number)
				local pa = SplineMesh.profile(spline, cuts[ka], side, Spline.ROCK)
				local pb = SplineMesh.profile(spline, cuts[kb], side, Spline.ROCK)
				local edge, crest = (pa[4] + pb[4]) * 0.5, (pa[5] + pb[5]) * 0.5
				local along = ((pb[4] + pb[5]) - (pa[4] + pa[5])) * 0.5
				local over = crest - edge
				local len, width = along.Magnitude, over.Magnitude
				local thick = T.RockShadeThickness
				local trim = shadeBack + T.RockShadeTopGap
				if len < 1e-3 or width < 2 * trim + 1 then
					return
				end
				local x = along / len
				local y = (over - x * over:Dot(x)).Unit
				local z = x:Cross(y)
				if z.Y > 0 then
					x = -x
					z = -z
				end
				-- z now points down, into the body
				local centre = (edge + crest) * 0.5 + z * (shadeBack + thick * 0.5)
				plain(`RockShadeTop_{tag}_{ka}`, Vector3.new(len + 1, width - 2 * trim, thick), CFrame.fromMatrix(centre, x, y, z), T.RockColour, Enum.Material.Slate)
			end
			local function shade(ka: number, kb: number, kind: number)
				local rock = kind == Spline.ROCK
				local shadeThick = if rock then T.RockShadeThickness else T.CliffShadeThickness
				local pa = SplineMesh.profile(spline, cuts[ka], side, kind)
				local pb = SplineMesh.profile(spline, cuts[kb], side, kind)
				-- rock, foot to top: the profile's first point and its face's top edge (the
				-- fourth, T-185); cliff, foot to top: the last, and the lip lowered by
				-- `RoadShadeSink` (under the grass, as the road's boxes are, so a ray in just
				-- under the lip meets one or the other)
				local sinkV = Vector3.yAxis * T.RoadShadeSink
				local fa, fb = if rock then pa[1] else pa[#pa], if rock then pb[1] else pb[#pb]
				local ta, tb = if rock then pa[4] else pa[1] - sinkV, if rock then pb[4] else pb[1] - sinkV
				if not rock then
					-- a cliff's depth wanders along the road (T-185): the box's foot stands at the
					-- shallower end's, and a little above it, so it never shows below the face
					local footY = math.max(fa.Y, fb.Y) + 2 + 0.02 * (pa[1].Y - fa.Y)
					fa = Vector3.new(fa.X, footY, fa.Z)
					fb = Vector3.new(fb.X, footY, fb.Z)
				end
				local foot = (fa + fb) * 0.5
				local top = (ta + tb) * 0.5
				local along = ((fb + tb) - (fa + ta)) * 0.5
				local up = top - foot
				local len, height = along.Magnitude, up.Magnitude
				if len < 1e-3 or height < 1e-3 then
					return
				end
				local x = along / len
				local y = (up - x * up:Dot(x)).Unit
				-- the face's normal, pointing at the road: the road's side of the foot (x turned
				-- round with it, so the frame stays right-handed)
				local roadward = Vector3.new(spline:surfaceXYZ((cuts[ka] + cuts[kb]) * 0.5, 0)) - foot
				if x:Cross(y):Dot(roadward) < 0 then
					x = -x
				end
				local toRoad = x:Cross(y)
				if rock then
					-- behind the face, away from the road, and down past the foot by
					-- `shadeBack`, so no low light slips under it; its top `RockShadeTopGap` short
					-- of the face's, so it stays under the ledge where a bend narrows the ledge
					local gap = T.RockShadeTopGap
					-- and behind the deepest the jagged face can dent in (T-185: half its jag)
					local back = shadeBack + (2.5 + 7 * spline:grandAt((cuts[ka] + cuts[kb]) * 0.5)) * 0.5
					local centre = (foot + top) * 0.5 - y * ((shadeBack + gap) * 0.5) - toRoad * (back + shadeThick * 0.5)
					local cf = CFrame.fromMatrix(centre, x, y, toRoad)
					plain(`RockShade_{tag}_{ka}`, Vector3.new(len + 1, math.max(1, height + shadeBack - gap), shadeThick), cf, T.RockColour, Enum.Material.Slate)
					shadeTop(ka, kb)
				else
					-- behind the face is the road's side: inside the drop, under the grass
					local centre = (foot + top) * 0.5 + toRoad * (shadeBack + shadeThick * 0.5)
					local cf = CFrame.fromMatrix(centre, x, y, toRoad)
					plain(`CliffShade_{tag}_{ka}`, Vector3.new(len + 1, height, shadeThick), cf, T.CliffColour, Enum.Material.Slate)
				end
			end
			local k0, kind0 = nil, nil
			for k = 1, #cuts do
				local kind = if k < #cuts then spline:edgeAt((cuts[k] + cuts[k + 1]) * 0.5, side) else nil
				local face = kind == Spline.ROCK or kind == Spline.CLIFF
				if k0 and (kind ~= kind0 or cuts[k] - cuts[k0] >= shadeStep) then
					shade(k0, k, kind0 :: number)
					k0 = nil
				end
				if face and not k0 then
					k0, kind0 = k, kind
				end
			end
		end

		-- THE ROAD'S SURFACE, tarmac and runoff, casts through a flat box under each
		-- `RoadShadeStep` of it: `RoadShadeSink` below the lowest point of the surface it
		-- covers, so nothing at the road's edge (a gravel strip, a raised lip) is pierced,
		-- and 1 stud in from the runoff's outer edge. A leg of road above another now
		-- shades it, and no light comes up through the road.
		do
			local roadStep, sink, thick = T.RoadShadeStep, T.RoadShadeSink, T.RoadShadeThickness
			local function under(ka: number, kb: number)
				local sa, sb = cuts[ka], cuts[kb]
				local c = Vector3.new(spline:terrainXYZ((sa + sb) * 0.5, 0))
				local chord = Vector3.new(spline:terrainXYZ(sb, 0)) - Vector3.new(spline:terrainXYZ(sa, 0))
				if chord.Magnitude < 1e-3 then
					return
				end
				local x = chord.Unit
				local n = spline:terrainNormal((sa + sb) * 0.5, 0)
				local y = (n - x * n:Dot(x)).Unit
				local z = x:Cross(y)
				-- across: only as wide as the surface is at both ends AND the middle, so on a
				-- bend (where the arc bows out of its chord) the box stays under the surface;
				-- along: from end to end of the centre line, a stud over each end
				local x0, x1, z0, z1, top = math.huge, -math.huge, -math.huge, math.huge, math.huge
				for _, s in { sa, (sa + sb) * 0.5, sb } do
					local wL = half + spline:runoffAt(s, -1) - 1
					local wR = half + spline:runoffAt(s, 1) - 1
					local zs = {}
					for _, d in { -wL, -half, 0, half, wR } do
						local p = Vector3.new(spline:terrainXYZ(s, d)) - c
						table.insert(zs, p:Dot(z))
						top = math.min(top, p:Dot(y))
						if d == 0 then
							x0, x1 = math.min(x0, p:Dot(x)), math.max(x1, p:Dot(x))
						end
					end
					z0 = math.max(z0, math.min(zs[1], zs[5]))
					z1 = math.min(z1, math.max(zs[1], zs[5]))
				end
				if z1 - z0 < 1 then
					return
				end
				top -= sink
				local centre = c + x * ((x0 + x1) * 0.5) + y * (top - thick * 0.5) + z * ((z0 + z1) * 0.5)
				plain(`RoadShade_{ka}`, Vector3.new(x1 - x0 + 2, thick, z1 - z0), CFrame.fromMatrix(centre, x, y, z), T.CliffColour, Enum.Material.Slate)
			end
			local k0 = 1
			for k = 2, #cuts do
				if k == #cuts or cuts[k] - cuts[k0] >= roadStep then
					under(k0, k)
					k0 = k
				end
			end
		end

		-- HEDGES: a green box per cut at the grass's outer edge (rock and cliff are faces in
		-- the mesh, above)
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "L" else "R"
			for k = 1, #cuts - 1 do
				local a, b = cuts[k], cuts[k + 1]
				if spline:edgeAt((a + b) * 0.5, side) == Spline.HEDGE then
					local wa, wb = half + spline:runoffAt(a, side), half + spline:runoffAt(b, side)
					wall(`Edge_{tag}_{k}`, a, b, side, wa, wb, T.HedgeThickness, T.HedgeHeight, R.Thickness, T.HedgeColour, Enum.Material.Grass)
				end
			end
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
					local step = if kEdge > 1e-6 then math.clamp(math.sqrt(8 * 0.06 / kEdge), 2, T.KRailStep) else T.KRailStep
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
		-- across chunks, its painted face `MarkLift` above the surface along its normal
		local interval, dash = R.MarkInterval, R.MarkDashLength
		local start = math.floor(s0 / interval) * interval
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
			parts = parts,
			trees = trees,
			treeTriangles = road.triangles - trianglesBefore,
			treeMs = treeMs,
			ms = 0,
		}
		return { model = model, stats = stats, meshes = { road.em } }
	end)
	if not ok then
		hazeOf[road.em] = nil
		road.em:Destroy() -- never leak one of the eight
		return nil, tostring(built)
	end
	local result = built :: any
	result.stats.ms = (os.clock() - t0 - paused) * 1000
	meshesOf[result.model] = result.meshes
	result.model.Parent = parent
	return result.model, result.stats
end

-- Colour the foot of every cliff, in every chunk drawn and every chunk drawn from now on
-- (`Controllers/SkyController`). Each mesh is rewritten, so call it when the colour has
-- moved, not every frame. Returns how many meshes it recoloured.
function SplineMesh.setHaze(colour: Color3): number
	hazeColour = colour
	local cliff = Config.Spline.Terrain.CliffColour
	local count = 0
	for em, ids in hazeOf do
		local ok = pcall(function()
			em:SetColor(ids.haze, colour)
			em:SetColor(ids.mid, cliff:Lerp(colour, 0.5))
		end)
		if ok then
			count += 1
		else
			hazeOf[em] = nil -- destroyed
		end
	end
	return count
end

-- The haze colour new chunks are drawn with.
function SplineMesh.haze(): Color3
	return hazeColour or Config.Spline.Terrain.HazeColour
end

-- Take a chunk down, with the mesh data its parts are drawn from.
function SplineMesh.destroy(model: Model)
	local meshes = meshesOf[model]
	meshesOf[model] = nil
	model:Destroy()
	if meshes then
		for _, em in meshes do
			hazeOf[em] = nil
			em:Destroy()
		end
	end
end

return SplineMesh
