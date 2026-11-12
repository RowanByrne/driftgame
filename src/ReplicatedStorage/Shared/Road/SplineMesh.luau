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
--               very low poly, programmer colours
--   Edge_*      a hedge: a green box per cross-section, at the grass's outer edge
--   KRail*_*    a K-rail run drawn as a METAL CRASH BARRIER (T-149): a W-beam guardrail,
--               its beam two ridges (`KRailTop_*`, `KRailLow_*`) and the groove between
--               (`KRailGroove_*`), a piece per stretch of the run, pitched along the grade
--               and cut finer round a bend; round posts (`KRailPost_*`) every `KRailPostEvery`
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

local SplineMesh = {}

local meshesOf: { [Model]: { EditableMesh } } = setmetatable({}, { __mode = "k" }) :: any

-- THE CLIFFS' HAZE follows the sky (features/day-night.md, T-144): the colour ids each live
-- mesh drew its haze with, so `setHaze` can recolour every drawn chunk in place, and the
-- colour new chunks are drawn with.
local hazeOf: { [EditableMesh]: { haze: number, mid: number } } = setmetatable({}, { __mode = "k" }) :: any
local hazeColour: Color3? = nil -- nil: `Config.Spline.Terrain.HazeColour`

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
--   ROCK   the foot on the grass, a jagged middle, the top at `RockHeight` leaning back at
--          `RockSlope`, then a ledge of scrub. Height, lean and jag wander along the road on
--          slow sines, so the face is never a wall of one height. On the inside of a bend the
--          face is drawn steeper rather than reach past the bend's centre
--   CLIFF  the lip, then a face dropping `CliffDrop` and stepping out a little as it goes
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
	local pts: { { number } } -- {out, up}
	if kind == Spline.ROCK then
		local h = T.RockHeight[1] + (T.RockHeight[2] - T.RockHeight[1]) * wave(s + side * 311, 61, 23)
		local lean = math.rad(T.RockSlope[1] + (T.RockSlope[2] - T.RockSlope[1]) * wave(s - side * 173, 43, 17))
		local run = h / math.tan(lean)
		local jag = 2.5 * (wave(s * 3.1, 7, 3) - 0.5)
		pts = { { 0, 0 }, { run * 0.4 + jag, h * 0.45 }, { run, h }, { run + 14, h + 4 } }
		-- the inside of a bend: never past 90% of the way to its centre
		local k = spline:curvatureAt(s)
		if k ~= 0 and (k > 0) == (side < 0) then
			local room = 0.9 / math.abs(k) - w
			local reach = pts[4][1]
			if room < reach then
				local scale = math.max(room, 0.5) / reach
				for _, p in pts do
					p[1] *= scale
				end
			end
		end
	else
		local drop = T.CliffDrop
		pts = { { 0, 0 }, { 1.5, -drop * 0.08 }, { 4, -drop * 0.45 }, { 7, -drop } }
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
local function strip(b: Builder, rowA: { number }, normA: { number }, rowB: { number }, normB: { number }, flip: boolean, colours: { number }?)
	local em = b.em
	for i = 1, #rowA - 1 do
		local a0, a1, b0, b1 = rowA[i], rowA[i + 1], rowB[i], rowB[i + 1]
		local na0, na1, nb0, nb1 = normA[i], normA[i + 1], normB[i], normB[i + 1]
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
	mp.CastShadow = false
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
		local RUNOFF_STRIPS = 2
		local tarmacColour = road.em:AddColor(R.Colours.Road, 1)
		local grassColour = road.em:AddColor(Config.Spline.Terrain.GrassColour, 1)
		local colours = {}
		for j = 1, RUNOFF_STRIPS * 2 + across do
			colours[j] = if j <= RUNOFF_STRIPS or j > RUNOFF_STRIPS + across then grassColour else tarmacColour
		end
		local prevRow, prevNorm = nil, nil
		for _, s in cuts do
			local row, norm = {}, {}
			local wL, wR = spline:runoffAt(s, -1), spline:runoffAt(s, 1)
			local ds = {}
			for j = 0, RUNOFF_STRIPS - 1 do
				table.insert(ds, -half - wL * (1 - j / RUNOFF_STRIPS))
			end
			for j = 0, across do
				table.insert(ds, -half + (2 * half) * j / across)
			end
			for j = 1, RUNOFF_STRIPS do
				table.insert(ds, half + wR * j / RUNOFF_STRIPS)
			end
			for j, d in ds do
				local x, y, z = spline:terrainXYZ(s, d)
				row[j] = road.em:AddVertex(Vector3.new(x - centre.X, y - centre.Y, z - centre.Z))
				norm[j] = road.em:AddNormal(spline:terrainNormal(s, d))
				road.vertices += 1
			end
			if prevRow then
				strip(road, prevRow, prevNorm, row, norm, false, colours)
			end
			prevRow, prevNorm = row, norm
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
			for k = 1, #cuts - 1 do
				local a, b = cuts[k], cuts[k + 1]
				local kind = spline:edgeAt((a + b) * 0.5, side)
				if kind == Spline.ROCK or kind == Spline.CLIFF then
					local ra, rb = rowAt(k, kind), rowAt(k + 1, kind)
					-- a rock face faces the road; a cliff face faces out, over the drop
					local yaw = spline:yawAt((a + b) * 0.5)
					local outward = Vector3.new(side * math.cos(yaw), 0, -side * math.sin(yaw))
					local facing = if kind == Spline.ROCK then -outward + Vector3.yAxis * 0.3 else outward
					local pa, pb, ia, ib = ra.pts, rb.pts, ra.ids, rb.ids
					for i = 1, #pa - 1 do
						local colour
						if kind == Spline.ROCK then
							colour = if i == #pa - 1 then faceColours.scrub else faceColours.rock
						else
							colour = if i == 1 then faceColours.cliff elseif i == #pa - 1 then faceColours.haze else cliffMid
						end
						tri(ia[i], ia[i + 1], ib[i], pa[i], pa[i + 1], pb[i], colour, facing)
						tri(ia[i + 1], ib[i + 1], ib[i], pa[i + 1], pb[i + 1], pb[i], colour, facing)
					end
				end
			end
		end

		local model = Instance.new("Model")
		model.Name = `Chunk_{math.floor(s0)}`
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
			part.CastShadow = false
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
		-- THE GUARDRAIL's pieces (T-149), placed from the tarmac's edge on `side`: a piece of
		-- beam `u .. u + thick` out from the edge and `y0 .. y1` above it, pitched along the
		-- road between `a` and `b`; and an upright round post at `s`
		local railMaterial = Enum.Material.Metal
		local function beam(name: string, a: number, b: number, side: number, u: number, thick: number, y0: number, y1: number)
			local off = side * (half + u + thick * 0.5)
			local ax, _, az = spline:terrainXYZ(a, off)
			local bx, _, bz = spline:terrainXYZ(b, off)
			local lift = (y0 + y1) * 0.5
			local pa = Vector3.new(ax, spline:terrainY(a, side * half) + lift, az)
			local pb = Vector3.new(bx, spline:terrainY(b, side * half) + lift, bz)
			local chord = pb - pa
			local len = chord.Magnitude
			if len > 1e-3 then
				local mid = (pa + pb) * 0.5
				plain(name, Vector3.new(thick, y1 - y0, len + 0.1), CFrame.lookAt(mid, mid + chord, Vector3.yAxis), T.KRailColour, railMaterial)
			end
		end
		local function post(name: string, s: number, side: number)
			local d = T.KRailPostSize
			local x, _, z = spline:terrainXYZ(s, side * (half + T.KRailRidge + 0.1 + d * 0.5))
			local sink, top = 1, T.KRailHeight - 0.15
			local y = spline:terrainY(s, side * half) + (top - sink) * 0.5
			-- a cylinder's axis is its X: stood upright
			local part = plain(name, Vector3.new(top + sink, d, d), CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi * 0.5), T.KRailColour, railMaterial)
			part.Shape = Enum.PartType.Cylinder
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
			-- `KRailHeight`; the posts behind it, inside that wall
			local runs = spline:kRailsIn(s0, s1, side)
			for r = 1, #runs, 2 do
				local ra, rb = runs[r], runs[r + 1]
				local id = `{tag}_{math.floor(ra)}`
				-- the beam: a piece per stretch, as long as `KRailStep` on a straight and
				-- short enough round a bend that its chord keeps to the curve
				local a = math.max(ra, s0)
				local stop = math.min(rb, s1)
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
					beam(`KRailTop_{id}_{n}`, a, b, side, 0, T.KRailRidge, T.KRailHeight - T.KRailBeam / 3, T.KRailHeight)
					beam(`KRailGroove_{id}_{n}`, a, b, side, T.KRailRidge - 0.05, 0.15, T.KRailHeight - T.KRailBeam * 2 / 3, T.KRailHeight - T.KRailBeam / 3)
					beam(`KRailLow_{id}_{n}`, a, b, side, 0, T.KRailRidge, T.KRailHeight - T.KRailBeam, T.KRailHeight - T.KRailBeam * 2 / 3)
					a = b
				end
				-- the posts: on a pattern from the run's own start, so a run drawn across two
				-- chunks has the same posts in both, and one at its very end
				local every, inset = T.KRailPostEvery, T.KRailPostSize
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
						post(`KRailPost_{id}_{j}`, p, side)
					end
					if last then
						break
					end
					j += 1
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
					plain("Mark", Vector3.new(R.MarkWidth, R.MarkThickness, len), CFrame.fromMatrix(centreOf, right, up), R.Colours.Marking, Enum.Material.SmoothPlastic)
				end
			end
			start += interval
		end

		local stats = {
			sections = #cuts,
			vertices = road.vertices,
			triangles = road.triangles,
			parts = parts,
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
	result.stats.ms = (os.clock() - t0) * 1000
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
