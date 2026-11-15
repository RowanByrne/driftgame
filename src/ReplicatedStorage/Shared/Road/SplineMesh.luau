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
--               `Road/SplineGrove`), faceted the same way. The grass alone is textured
--               (T-187): a painted tile, `Road/GrassTexture`, mapped in world studs; every
--               other face samples the tile's plain corner
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
local GrassTexture = require(script.Parent.GrassTexture)
local Spline = require(script.Parent.Spline)
local SplineGrove = require(script.Parent.SplineGrove)
local SplineHill = require(script.Parent.SplineHill)

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
	sliceMs: number?, -- ms of building a frame (`Mesh.SliceMs`); math.huge builds it in one go
	hill: boolean?, -- false: no hillside past the faces, and no caps on them (the road as before T-190)
	-- a ground-first run (T-218): the road, its runoff, rails and groves only -- no rock
	-- faces, drops or hillside, which the ground drawn apart stands in for -- and a skirt
	-- down from each runoff's outer edge to the ground
	ground: boolean?,
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
SplineMesh.profile = require(script.Parent.SplineProfile).profile

-- A mesh in the making: vertices relative to `centre`, with normals.
type Builder = {
	em: EditableMesh,
	centre: Vector3,
	fixed: boolean?, -- copied into a fixed-size mesh when done (a ground run, T-218)
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
}


-- A quad strip between two rows of vertex ids, each with its normal id. `colours`, when
-- given, is a colour id per strip (between vertex i and i + 1), painted on both triangles.
-- `farA` / `farB`, when given, are the normals a vertex has as the FAR side of a strip
-- (vertex i + 1 of strip i), so one vertex can be smooth on one strip and flat on the next:
-- the road's step (T-184).
-- `uvA` / `uvB`, when given, are UV ids for the grass's vertices (T-187): a strip painted
-- `grass` is mapped with them; one that shares a grass vertex but is not grass gets `plainUV`.
local function strip(b: Builder, rowA: { number }, normA: { number }, rowB: { number }, normB: { number }, flip: boolean, colours: { number }?, farA: { number }?, farB: { number }?, uvA: { [number]: number }?, uvB: { [number]: number }?, grass: number?)
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
			if uvA and uvB and c == grass then
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
					b.grassTriangles += 2
				end
			elseif b.plainUV and uvA and uvB and (uvA[i] or uvA[i + 1] or uvB[i] or uvB[i + 1]) then
				-- a strip that is not grass but shares a vertex with the grass: the bevel, or
				-- a gravelled runoff
				local u = b.plainUV
				em:SetFaceUVs(f1, { u, u, u })
				em:SetFaceUVs(f2, { u, u, u })
			end
		end
		b.triangles += 2
	end
end

local function newBuilder(centre: Vector3): Builder
	local em = AssetService:CreateEditableMesh({ FixedSize = false })
	-- nil is the device saying no: out of its EditableMesh budget
	assert(em, "this device would not make an EditableMesh (out of its budget)")
	return { em = em :: EditableMesh, centre = centre, vertices = 0, triangles = 0, grassTriangles = 0, plainUV = nil, grassShade = nil }
end

-- A MeshPart made from an EditableMesh keeps the vertices exactly where they were written,
-- relative to the part (measured: not re-centred), while its Size -- and so what Roblox culls
-- it by -- is the bounding box. So the vertices are moved to be centred on their own box
-- first, and the part is put where that box is.
local function toPart(b: Builder, name: string, colour: Color3, material: Enum.Material, texture: EditableImage?): MeshPart
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, v in b.em:GetVertices() do
		local p = b.em:GetPosition(v)
		lo, hi = lo:Min(p), hi:Max(p)
	end
	local mid = (lo + hi) * 0.5
	for _, v in b.em:GetVertices() do
		b.em:SetPosition(v, b.em:GetPosition(v) - mid)
	end
	-- A GROUND RUN'S ROAD (T-218) is copied into a fixed-size mesh, which costs a device's
	-- mesh budget by its size, not by what a growable one holds back (measured: the ground's
	-- grids pushed growable road chunks out of the budget). The growable one goes
	if b.fixed then
		local okCopy, copy = pcall(function()
			return AssetService:CreateEditableMeshAsync(Content.fromObject(b.em), { FixedSize = true })
		end)
		if okCopy and copy then
			hazeOf[b.em] = nil
			b.em:Destroy()
			b.em = copy
		end
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
	-- EditableMesh casts no shadow at all, either side of its faces. The hidden boxes that
	-- once cast it were removed (T-229); a different approach to shadows is to come.
	mp.CastShadow = true
	mp.Color = colour
	mp.Material = material
	mp.CFrame = CFrame.new(b.centre + mid)
	if texture then
		-- the grass's texture (T-187, `Road/GrassTexture`); it replaces the material's colour
		-- map on every face, so the faces that are not grass sample its plain corner
		mp.TextureContent = Content.fromObject(texture)
	end

	return mp
end

-- Draw [s0, s1] of the road under a new Model in `parent`. Returns the model and what it
-- cost, or nil and the reason when this device cannot make a mesh.
function SplineMesh.build(spline: Spline.Spline, s0: number, s1: number, parent: Instance, opts: Options?): (Model?, any)
	-- every edge, as this build sees it: none in a ground run (T-218)
	local function edgeOf(s: number, side: number): number
		return if opts and opts.ground then 0 else spline:edgeAt(s, side)
	end
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
	road.fixed = o.ground
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
		-- THE GRASS'S TEXTURE (T-187): its vertices get UVs in world studs, in the shared
		-- tile; a strip painted grass is mapped with them (`strip`)
		-- (loaded once, the first time a chunk asks: not that chunk's cost)
		local g0 = os.clock()
		local grassImage = GrassTexture.get()
		local g1 = os.clock()
		if g1 - g0 > 0.001 then
			-- it waited on the asset: not work, and the frame's slice starts afresh (T-193)
			paused += g1 - g0
			sliceStart = g1
		end
		local baseU, baseV = GrassTexture.base(centre)
		if grassImage then
			road.plainUV = road.em:AddUV(Vector2.zero)
			road.grassShade = {}
		end
		local prevRow, prevNear, prevFar, prevS, prevUV = nil, nil, nil, 0, nil
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
			local uv: { [number]: number }? = if grassImage then {} else nil
			for j, d in ds do
				local x, y, z = spline:terrainXYZ(s, d)
				pts[j] = Vector3.new(x, y, z)
				row[j] = road.em:AddVertex(Vector3.new(x - centre.X, y - centre.Y, z - centre.Z))
				norm[j] = road.em:AddNormal(spline:terrainNormal(s, d))
				road.vertices += 1
				-- the grass's vertices: the runoff either side, out from each bevel's foot
				if uv and (j <= lipL or j > lipR) then
					uv[j] = road.em:AddUV(GrassTexture.uv(x, z, baseU, baseV))
					local shade = road.grassShade
					if shade then
						local k = GrassTexture.blotch(x, z)
						local g = TT.GrassColour
						shade[row[j]] = road.em:AddColor(Color3.new(math.min(1, g.R * k), math.min(1, g.G * k), math.min(1, g.B * k)), 1)
					end
				end
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
				strip(road, prevRow, prevNear, row, near, false, use, prevFar, far, prevUV, uv, grassColour)
			end
			prevRow, prevNear, prevFar, prevS, prevUV = row, near, far, s, uv
			slice()
		end

		-- THE HILLSIDE (T-190, `Road/SplineHill`): the stations of every stretch of road round
		-- this chunk, then a ray per cut and side: how tall its face may stand (`caps`), and
		-- where its ground ends. The faces below are drawn to their caps, and past them the
		-- ground carries on to the next leg
		local H = Config.Spline.Hill
		local hill = if o.hill ~= false and not o.ground then SplineHill.context(spline, s0, s1, SplineMesh.profile, slice) else nil
		local rays: { [number]: { SplineHill.Ray } } = { [-1] = {}, [1] = {} }
		local caps: { [number]: { number } } = { [-1] = {}, [1] = {} }
		local hillTriangles = 0
		-- the cuts a ray is worked out at: `CutStep` apart at least (a hairpin's cuts are a stud
		-- or two apart, far too many), the chunk's two ends (so the next chunk's first ray is
		-- this one's last), and wherever an edge changes kind (its faces come down to nothing
		-- there). The cuts between take their caps from the rays either side
		local rayCuts: { number } = {}
		if hill then
			local need = { [1] = true, [#cuts] = true }
			local last = 1
			for k = 2, #cuts - 1 do
				local changes = false
				for _, side in { -1, 1 } do
					if edgeOf((cuts[k - 1] + cuts[k]) * 0.5, side) ~= edgeOf((cuts[k] + cuts[k + 1]) * 0.5, side) then
						changes = true
					end
				end
				if changes or cuts[k] - cuts[last] >= H.CutStep then
					need[k] = true
					if not changes then
						last = k
					end
				end
			end
			for k = 1, #cuts do
				if need[k] then
					table.insert(rayCuts, k)
					for _, side in { -1, 1 } do
						local ray = SplineHill.ray(hill, cuts[k], side)
						rays[side][k] = ray
						caps[side][k] = SplineHill.cap(ray)
					end
					slice()
				end
			end
			for n = 1, #rayCuts - 1 do
				local a, b = rayCuts[n], rayCuts[n + 1]
				for k = a + 1, b - 1 do
					local u = (cuts[k] - cuts[a]) / math.max(cuts[b] - cuts[a], 1e-9)
					for _, side in { -1, 1 } do
						local ca, cb = caps[side][a], caps[side][b]
						caps[side][k] = if ca == math.huge or cb == math.huge then (if u < 0.5 then ca else cb) else ca + (cb - ca) * u
					end
				end
			end
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
		for name, c in { rock = T.RockColour, scrub = T.ScrubColour, cliff = T.CliffColour, haze = haze, skirt = Config.Spline.Ground.SkirtColour } do
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
				local pts = SplineMesh.profile(spline, cuts[k], side, kind, if hill then caps[side][k] else nil)
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
				kinds[k] = edgeOf((cuts[k] + cuts[k + 1]) * 0.5, side)
			end
			kinds[0] = if cuts[1] > 0 then edgeOf(cuts[1] - 0.01, side) else kinds[1]
			local sEnd = cuts[#cuts]
			kinds[#cuts] = if sEnd < spline.length - 0.01 then edgeOf(sEnd + 0.01, side) else kinds[#cuts - 1]
			-- A GROUND RUN'S SKIRT (T-218): from the runoff's outer edge straight down
			-- `Ground.Skirt`, leaning out a little, so where the ground drawn apart dips below
			-- the edge (a ditch beside a cutting, a fill falling away) no gap shows
			if o.ground then
				local G = Config.Spline.Ground
				local skirtColour = faceColours.skirt
				local tops, bottoms = table.create(#cuts), table.create(#cuts)
				local topP, bottomP = table.create(#cuts), table.create(#cuts)
				for k = 1, #cuts do
					local w = half + spline:runoffAt(cuts[k], side)
					topP[k] = Vector3.new(spline:terrainXYZ(cuts[k], side * w))
					bottomP[k] = Vector3.new(spline:terrainXYZ(cuts[k], side * (w + G.SkirtLean))) - Vector3.yAxis * G.Skirt
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
			-- WHERE THE ROCK MEETS THE DROP on one side (T-189: the mountain changes sides at one
			-- point in a hairpin, so the outside's rock ends where its cliff starts, and the
			-- inside's the other way round). The two ends' caps close each body, but under the
			-- rock body, past the cliff's face, there is nothing: from the drop side you would
			-- see through under the rock's end. So a wall closes it, in the plane of the join:
			-- from the cliff's face out to the rock body's back foot, down from the ground to
			-- the cliff's foot. Drawn both ways, since it is seen from either side of the join
			-- (it shares no plane with the cliff's own cap, which is on the road's side of the face)
			local function join(rockRow: { pts: { Vector3 }, ids: { number }, kind: number }, kc: number)
				local cliff = rowAt(kc, Spline.CLIFF)
				local cp, ci = cliff.pts, cliff.ids
				-- the rock's foot, its back foot, then up the cliff's face from its foot
				local pts = { rockRow.pts[1], rockRow.pts[#rockRow.pts] }
				local ids = { rockRow.ids[1], rockRow.ids[#rockRow.ids] }
				for i = #cp, 2, -1 do
					table.insert(pts, cp[i])
					table.insert(ids, ci[i])
				end
				local mid = Vector3.zero
				for _, p in pts do
					mid += p
				end
				mid /= #pts
				local midId = em:AddVertex(mid - centre)
				road.vertices += 1
				local yaw = spline:yawAt(cuts[kc])
				local along = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
				for i = 1, #pts do
					local j = i % #pts + 1
					tri(midId, ids[i], ids[j], mid, pts[i], pts[j], cliffMid, along)
					tri(midId, ids[i], ids[j], mid, pts[i], pts[j], cliffMid, -along)
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
					-- with the hillside (T-190) a rock body has no back slope: the ground carries on
					-- up from its crest; and a cliff's foot stands on ground, not in haze
					local last = if hill and kind == Spline.ROCK then #pa - 2 else #pa - 1
					for i = 1, last do
						local colour
						if kind == Spline.ROCK then
							colour = if i == #pa - 2 then faceColours.scrub else faceColours.rock
						else
							colour = if i == 1 then faceColours.cliff elseif i == #pa - 1 and not hill then faceColours.haze else cliffMid
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
					-- (with the hillside both faces come down to nothing where they meet: no wall)
					if kind == Spline.ROCK and not hill then
						if kinds[k - 1] == Spline.CLIFF then
							join(ra, k)
						end
						if kinds[k + 1] == Spline.CLIFF then
							join(rb, k + 1)
						end
					end
				end
				slice()
			end

			-- THE HILLSIDE (T-190): past each face's end -- a rock body's crest, a cliff's foot --
			-- the ground carries on along the cut's ray to where it meets the next stretch's,
			-- a row of vertices per ray at `Hill.Rings` of its length. Rays are `CutStep` apart
			-- at least (a hairpin's cuts are a stud or two apart: far too many), and the faces'
			-- own rows, on every cut, are stitched to the first ring with a fan.
			if hill then
				local sideRays = rays[side]
				local hk = rayCuts
				local shades: { [number]: number } = {}
				local function ground(a: number, b: number, c: number, pa: Vector3, pb: Vector3, pc: Vector3)
					local n = (pb - pa):Cross(pc - pa)
					if n.Magnitude < 1e-9 then
						return
					end
					local colour
					if math.abs(n.Unit.Y) < H.SteepRock then
						colour = faceColours.rock
					else
						-- a few greens, by the blotch at the face's middle
						local mid = (pa + pb + pc) / 3
						local level = math.floor((GrassTexture.blotch(mid.X, mid.Z) - 1) * 12 + 0.5)
						colour = shades[level]
						if not colour then
							local g, kk = H.Colour, 1 + level / 12
							colour = em:AddColor(Color3.new(math.min(1, g.R * kk), math.min(1, g.G * kk), math.min(1, g.B * kk)), 1)
							shades[level] = colour
						end
					end
					tri(a, b, c, pa, pb, pc, colour, Vector3.yAxis)
					hillTriangles += 1
				end
				local hillRows: { [number]: { pts: { Vector3 }, ids: { number } } } = {}
				local function hillRow(k: number)
					local row = hillRows[k]
					if row then
						return row
					end
					local ray = sideRays[k]
					SplineHill.finish(hill, ray)
					local t0f = SplineHill.faceEnd(ray)
					local span = math.max(ray.clip - t0f, 0)
					local pts, ids = {}, {}
					for j, share in H.Rings do
						pts[j] = SplineHill.at(ray, t0f + span * share)
					end
					table.insert(pts, SplineHill.at(ray, t0f + span + H.Skirt))
					for j, p in pts do
						ids[j] = em:AddVertex(p - centre)
					end
					road.vertices += #pts
					row = { pts = pts, ids = ids }
					hillRows[k] = row
					return row
				end
				for n = 1, #hk - 1 do
					local ka, kb = hk[n], hk[n + 1]
					local kind = kinds[ka]
					if kind == Spline.ROCK or kind == Spline.CLIFF then
						local A, B = hillRow(ka), hillRow(kb)
						-- the fan from the faces' ends (their fifth point, on every cut) to the
						-- first ring's two vertices
						local m = (ka + kb + 1) // 2
						for i = ka, kb - 1 do
							local fa, fb = rowAt(i, kind), rowAt(i + 1, kind)
							local far = if i < m then A else B
							ground(fa.ids[5], fb.ids[5], far.ids[1], fa.pts[5], fb.pts[5], far.pts[1])
						end
						local fm = rowAt(m, kind)
						ground(fm.ids[5], A.ids[1], B.ids[1], fm.pts[5], A.pts[1], B.pts[1])
						for j = 1, #A.pts - 1 do
							ground(A.ids[j], A.ids[j + 1], B.ids[j], A.pts[j], A.pts[j + 1], B.pts[j])
							ground(A.ids[j + 1], B.ids[j + 1], B.ids[j], A.pts[j + 1], B.pts[j + 1], B.pts[j])
						end
					end
					slice()
				end
			end
		end

		-- THE GROVES (T-183): trees and bushes on a widened runoff, in this same mesh, so a
		-- grove costs triangles and no parts (`Road/SplineGrove`)
		-- (measured: 13 ms a grove chunk in one go, 20 at worst). Its trees are drawn a few ms a
		-- frame like the rest (T-193): `slice()` between the triangles
		slice()
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
				slice()
			end,
		})
		local treeMs = (os.clock() - treeT0) * 1000

		local model = Instance.new("Model")
		model.Name = `Chunk_{math.floor(s0)}`
		model:SetAttribute("Trees", trees)
		model:SetAttribute("S0", s0)
		model:SetAttribute("S1", s1)
		-- white, so the vertex colours are what show
		slice()
		local roadPart = toPart(road, "Road", Color3.new(1, 1, 1), R.RoadMaterial, grassImage)
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
			slice()
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

		-- HEDGES: a green box per cut at the grass's outer edge (rock and cliff are faces in
		-- the mesh, above)
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "L" else "R"
			for k = 1, #cuts - 1 do
				local a, b = cuts[k], cuts[k + 1]
				if edgeOf((a + b) * 0.5, side) == Spline.HEDGE then
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
			grassTriangles = road.grassTriangles, -- textured (T-187)
			textured = grassImage ~= nil,
			parts = parts,
			trees = trees,
			treeTriangles = road.triangles - trianglesBefore,
			treeMs = treeMs,
			hillTriangles = hillTriangles,
			stations = if hill then #hill.stations else 0,
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
	meshesOf[result.model] = result.meshes
	-- the parent may have gone while the chunk was built over several frames (T-193)
	local placed = pcall(function()
		result.model.Parent = parent
	end)
	worstSlice = math.max(worstSlice, os.clock() - sliceStart)
	result.stats.ms = (os.clock() - t0 - paused) * 1000
	result.stats.slices = slices -- frames the build was spread over
	result.stats.sliceMs = worstSlice * 1000 -- the most of it any one frame paid
	if not placed then
		SplineMesh.destroy(result.model)
		return nil, "the chunk's parent went while it was built"
	end
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
