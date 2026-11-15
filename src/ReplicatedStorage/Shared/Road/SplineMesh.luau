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
local GrassTexture = require(script.Parent.GrassTexture)
local Spline = require(script.Parent.Spline)
local SplineGrove = require(script.Parent.SplineGrove)
local SplineHill = require(script.Parent.SplineHill)
local HillCuts = require(script.Parent.SplineHillCuts)
local SurfaceCuts = require(script.Parent.SplineSurfaceCuts)
local Boundary = require(script.Parent.SplineBoundary)
local Shadow = require(script.Parent.SplineShadow)
local Builder = require(script.Parent.Builder)
local Infield = require(script.Parent.SplineInfield)
local FieldCuts = require(script.Parent.SplineFieldCuts)
local SplineParts = require(script.Parent.SplineParts)

local SplineMesh = {}

local meshesOf: { [Model]: { EditableMesh } } = setmetatable({}, { __mode = "k" }) :: any
local liveMeshes:{[EditableMesh]:boolean}=setmetatable({}, {__mode="k"}) :: any
local consumersOf:{[EditableMesh]:{MeshPart}}=setmetatable({}, {__mode="k"}) :: any
local function releaseMesh(em:EditableMesh)
	local consumers=consumersOf[em];consumersOf[em]=nil
	-- Destroy every native consumer before its EditableMesh, including a
	-- partially configured part that never made it into its staging model.
	for _,part in consumers or {} do part:Destroy() end
	liveMeshes[em]=nil
	em:Destroy()
end

-- THE CLIFFS' HAZE follows the sky (features/day-night.md, T-144): the colour ids each live
-- mesh drew its haze with, so `setHaze` can recolour every drawn chunk in place, and the
-- colour new chunks are drawn with.
local hazeOf: { [EditableMesh]: { haze: number, mid: number, converted: {any}? } } = setmetatable({}, { __mode = "k" }) :: any
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
	tick: (() -> ())?, -- internal near-ground planning slice
	traceFaces: boolean?, -- test-only nominal source rows for terrain triangles
	fieldPlan: FieldCuts.Plan?, -- exact matching complete field coverage
	captureScenery: boolean?, -- retain uncut actual scenery for finite end joins
	cancelled: (() -> boolean)?,
}

export type Stats = {
	sections: number,
	vertices: number,
	triangles: number,
	ms: number,
	groveColourIds: {[number]:boolean}?, -- decorative faces, never terrain sample hits
}

-- The cross-sections of [s0, s1], placed where the surface needs them.
function SplineMesh.sections(spline: Spline.Spline, s0: number, s1: number, opts: Options?): { number }
	local o: Options = opts or {}
	local M = Config.Spline.Mesh
	local tol = o.tolerance or M.Tolerance
	local maxStep = o.maxStep or M.MaxStep
	local minStep = o.minStep or M.MinStep
	if spline:hasBiomeGround() then
		return SurfaceCuts.sections(spline,s0,s1,tol,maxStep,minStep,o.across or M.Across,M.GrassAcross,o.tick)
	end
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
SplineMesh.drawProfile = require(script.Parent.SplineProfile).draw

-- A mesh in the making: vertices relative to `centre`, with normals.
type Builder = {
	em: EditableMesh,
	centre: Vector3,
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
			local painted=false
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
						painted=true
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
			if not painted then
				em:SetFaceColors(f1, { c, c, c })
				em:SetFaceColors(f2, { c, c, c })
			end
		end
		b.triangles += 2
	end
end

local function newBuilder(centre: Vector3): Builder
	local em = AssetService:CreateEditableMesh({ FixedSize = false })
	-- nil is the device saying no: out of its EditableMesh budget
	assert(em, "this device would not make an EditableMesh (out of its budget)")
	liveMeshes[em :: EditableMesh]=true
	consumersOf[em :: EditableMesh]={}
	return { em = em :: EditableMesh, centre = centre, vertices = 0, triangles = 0, grassTriangles = 0, plainUV = nil, grassShade = nil }
end

-- A MeshPart made from an EditableMesh keeps the vertices exactly where they were written,
-- relative to the part (measured: not re-centred), while its Size -- and so what Roblox culls
-- it by -- is the bounding box. So the vertices are moved to be centred on their own box
-- first, and the part is put where that box is.
local function toPart(b: Builder, name: string, colour: Color3, material: Enum.Material, texture: EditableImage?, tick:(()->())?): MeshPart
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	local ids=b.em:GetVertices()
	local positions={}
	for index, v in ids do
		local p = b.em:GetPosition(v)
		positions[index]=p
		lo, hi = lo:Min(p), hi:Max(p)
		if tick and index%128==0 then tick() end
	end
	local mid = (lo + hi) * 0.5
	for index, v in ids do
		b.em:SetPosition(v, positions[index] - mid)
		if tick and index%128==0 then tick() end
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
	table.insert(consumersOf[b.em],mp)
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
	if texture then
		-- the grass's texture (T-187, `Road/GrassTexture`); it replaces the material's colour
		-- map on every face, so the faces that are not grass sample its plain corner
		mp.TextureContent = Content.fromObject(texture)
	end

	return mp
end

-- Draw [s0, s1] of the road under a new Model in `parent`. Returns the model and what it
-- cost, or nil and the reason when this device cannot make a mesh.
function SplineMesh.build(spline: Spline.Spline, s0: number, s1: number, parent: Instance, opts: Options?): (Model?, any, {omitHills:boolean}?)
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
		if o.cancelled and o.cancelled() then error("terrain mesh build cancelled") end
	end
	local function slice()
		if o.cancelled and o.cancelled() then error("terrain mesh build cancelled") end
		if os.clock() - sliceStart >= budget then
			yieldNow()
		end
	end
	if o.fieldPlan and o.fieldPlan.identity~=spline.infields then return nil,"field coverage belongs to another road" end
	local fieldContext=if o.fieldPlan then FieldCuts.forBuild(o.fieldPlan,slice) else nil
	local scenery:any=if o.captureScenery or fieldContext then {} else nil
	local fieldCutTriangles,fieldRejectedCasters=0,0
	local function hitsField(cf:CFrame?,size:Vector3?):boolean
		return fieldContext~=nil and cf~=nil and size~=nil and FieldCuts.intersectsBox(fieldContext,cf,size)
	end
	local half = R.Width * 0.5
	local across = o.across or M.Across
	local cutOptions=table.clone(o)
	cutOptions.tick=slice
	local surfaceStarted=os.clock()-paused
	local cuts = SplineMesh.sections(spline, s0, s1, cutOptions)
	local surfacePlanMs=(os.clock()-paused-surfaceStarted)*1000
	local cx, cy, cz = spline:surfaceXYZ((s0 + s1) * 0.5, 0)
	local centre = Vector3.new(cx, cy, cz)

	if o.forceFail then
		return nil, "forced (a test standing in for a device that cannot make meshes)"
	end
	local made, road = pcall(newBuilder, centre)
	if not made then
		return nil, tostring(road)
	end
	local pendingModel:Model?=nil
	local uncertifiedHill=false
	local ok, built = pcall(function()
		local farTriangles:any={}
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
		local RUNOFF_STRIPS = if spline:hasBiomeGround() then M.GrassAcross else 2
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
		local sourceScale=GrassTexture.plainScale(grassImage)
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
		local surfaceRows: { { Vector3 } } = {}
		local prevRow, prevNear, prevFar, prevS, prevUV = nil, nil, nil, 0, nil
		for k, s in cuts do
			local row, norm, pts = {}, {}, {}
			local wL, wR = spline:runoffAt(s, -1), spline:runoffAt(s, 1)
			local ds = {}
			if spline:hasBiomeGround() then
				ds=SurfaceCuts.offsets(spline,s,across,RUNOFF_STRIPS)
			else
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
			end
			local uv: { [number]: number }? = if grassImage then {} else nil
			local sampled,normalVectors,relative=spline:terrainRow(s,ds,true,centre)
			for j, d in ds do
				local x,z=sampled[j].X,sampled[j].Z
				pts[j] = sampled[j]
				row[j] = road.em:AddVertex(relative[j])
				norm[j] = road.em:AddNormal(normalVectors[j])
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
			surfaceRows[k] = pts
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
		local hillStarted=os.clock()-paused
		local hill = if o.hill ~= false then SplineHill.context(spline, s0, s1, SplineMesh.drawProfile, slice, true) else nil
		local rays: { [number]: { SplineHill.Ray } } = { [-1] = {}, [1] = {} }
		local caps: { [number]: { number } } = { [-1] = {}, [1] = {} }
		local hillTriangles = 0
		local hillTrimmedTriangles=0
		local hillTrimmer:any=nil
		-- the cuts a ray is worked out at: `CutStep` apart at least (a hairpin's cuts are a stud
		-- or two apart, far too many), the chunk's two ends (so the next chunk's first ray is
		-- this one's last), and wherever an edge changes kind (its faces come down to nothing
		-- there). The cuts between take their caps from the rays either side
		local rayCuts: { number } = {}
		local hillPlan={added=0,tests=0,exact=0,terminal=0}
		if hill then
			local need = { [1] = true, [#cuts] = true }
			local last = 1
			for k = 2, #cuts - 1 do
				local changes = false
				for _, side in { -1, 1 } do
					if spline:edgeAt((cuts[k - 1] + cuts[k]) * 0.5, side) ~= spline:edgeAt((cuts[k] + cuts[k + 1]) * 0.5, side) then
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
			if spline:hasBiomeGround() then
				rayCuts,hillPlan,hillTrimmer=HillCuts.refine(spline,hill,cuts,surfaceRows,rayCuts,rays,caps,SplineMesh.drawProfile,slice)
				uncertifiedHill=hillPlan.terminal~=0
				if hillPlan.terminal~=0 and not hillTrimmer then
					uncertifiedHill=true
					error(`unsafe terminal hillside span ({hillPlan.terminal}, folded {hillPlan.terminalFolds or 0})`)
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
		local hillPlanMs=(os.clock()-paused-hillStarted)*1000

		-- THE FACES OF THE MOUNTAINSIDE, in the same mesh: a client may hold only eight
		-- EditableMeshes and the road's window uses six, so the faces cannot have meshes of
		-- their own. Between each pair of cuts, on each side whose edge is a rock face or a
		-- cliff, a few quads of the profile `SplineMesh.profile` gives, flat-shaded.
		local em = road.em
		local vertexOrigins:any=if o.traceFaces then {} else nil
		local faceOrigins:any=if o.traceFaces then {} else nil
		local traceKind="face"
		local sourceMaterials={}
		local function material(colour:number):any
			local value=sourceMaterials[colour]
			if not value then value=table.freeze({colour=em:GetColor(colour),textureScale=sourceScale});sourceMaterials[colour]=value end
			return value
		end
		local function source(pa:Vector3,pb:Vector3,pc:Vector3,paint:any):any
			local points={{pa.X,pa.Y,pa.Z},{pb.X,pb.Y,pb.Z},{pc.X,pc.Y,pc.Z}}
			if scenery then
				if #scenery>=24576 then error("field scenery source limit") end
				for _,p in points do table.freeze(p) end
				table.insert(scenery,table.freeze({points=table.freeze(points),material=paint,kind=traceKind}))
			end
			return points
		end
		-- FLAT-SHADED BUT SHARED: a face's normal and colour are set per face, so the
		-- vertices of a row are shared by every face that touches them (a third of the
		-- vertices, and a third of the cost, of a vertex per corner)
		local function tri(a: number, b: number, c: number, pa: Vector3, pb: Vector3, pc: Vector3, colour: number, facing: Vector3, protected:boolean?)
			local sourceId:number?=nil
			local n = (pb - pa):Cross(pc - pa)
			if n.Magnitude < 1e-9 then
				return
			end
			if n:Dot(facing) < 0 then
				b, c = c, b
				pb,pc=pc,pb
				n = -n
			end
			if not protected and traceKind~="grove" and (scenery or fieldContext) then
				local points=source(pa,pb,pc,material(colour))
				sourceId=if scenery then #scenery else nil
				if fieldContext then
					local pieces,changed,why=FieldCuts.triangle(fieldContext,points[1],points[2],points[3])
					if not pieces then error(`field scenery cut failed: {why}`) end
					if changed then
						fieldCutTriangles+=1;local normal=em:AddNormal(n.Unit)
						for _,piece in pieces do
							if road.triangles>=19000 then error("field mesh triangle limit") end
							local ids={}
							for _,p in piece do table.insert(ids,em:AddVertex(Vector3.new(p[1]-centre.X,p[2]-centre.Y,p[3]-centre.Z)));road.vertices+=1 end
							local face=em:AddTriangle(ids[1],ids[2],ids[3])
							em:SetFaceNormals(face,{normal,normal,normal});em:SetFaceColors(face,{colour,colour,colour})
							if road.plainUV then em:SetFaceUVs(face,{road.plainUV,road.plainUV,road.plainUV}) end
							if faceOrigins then faceOrigins[face]={kind=traceKind,fieldCut=true,fieldSource=sourceId} end
							road.triangles+=1
						end
						slice()
						return
					end
				end
			end
			local f = em:AddTriangle(a, b, c)
			if faceOrigins then faceOrigins[f]={kind=traceKind,a=vertexOrigins[a],b=vertexOrigins[b],c=vertexOrigins[c],protected=protected,fieldSource=sourceId} end
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
		sourceMaterials[faceColours.haze]=table.freeze({colour=haze,haze="haze",textureScale=sourceScale})
		sourceMaterials[cliffMid]=table.freeze({colour=T.CliffColour:Lerp(haze,.5),haze="mid",textureScale=sourceScale})
		hazeOf[em] = { haze = faceColours.haze, mid = cliffMid }
		local faceRows: { [number]: { [number]: { [number]: { Vector3 } } } } = { [-1] = {}, [1] = {} }
		for _, side in { -1, 1 } do
			-- one row of vertices per cut and kind, made the first time a face needs it
			local rows: { [number]: { pts: { Vector3 }, ids: { number }, kind: number } } = {}
			local function rowAt(k: number, kind: number)
				local row = rows[k]
				if row and row.kind == kind then
					return row
				end
				local pts = SplineMesh.drawProfile(spline, cuts[k], side, kind, if hill then caps[side][k] else nil)
				faceRows[side][kind] = faceRows[side][kind] or {}
				faceRows[side][kind][k] = pts
				local ids = table.create(#pts)
				for i, p in pts do
					ids[i] = em:AddVertex(p - centre)
					if vertexOrigins then vertexOrigins[ids[i]]={kind="face",side=side,s=cuts[k],point=i} end
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
					if spline:hasBiomeGround() and kind==Spline.ROCK
						and (spline:infieldOpening(a,side)<1-1e-8 or spline:infieldOpening(b,side)<1-1e-8) then
						local ta,tb=Boundary.toeRow(spline,a,side),Boundary.toeRow(spline,b,side)
						local ai,bi={},{}
						for j=1,3 do ai[j]=em:AddVertex(ta[j]-centre);bi[j]=em:AddVertex(tb[j]-centre) end
						road.vertices+=6
						for j=1,2 do
							tri(ai[j],ai[j+1],bi[j],ta[j],ta[j+1],tb[j],faceColours.rock,-outward,true)
							tri(ai[j+1],bi[j+1],bi[j],ta[j+1],tb[j+1],tb[j],faceColours.rock,-outward,true)
						end
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
				local hillColour = em:AddColor(H.Colour, 1)
				local farMaterial=table.freeze({colour=H.Colour,textureScale=if grassImage then Config.Spline.Grass.Shade else 1})
				local function farGround(pa:Vector3,pb:Vector3,pc:Vector3)
					if (pb-pa):Cross(pc-pa).Y<0 then pb,pc=pc,pb end
					if scenery or fieldContext then
						local points=source(pa,pb,pc,farMaterial)
						if fieldContext then
							local pieces,changed,why=FieldCuts.triangle(fieldContext,points[1],points[2],points[3])
							if not pieces then error(`field far scenery cut failed: {why}`) end
							if changed then fieldCutTriangles+=1 end
							for _,piece in pieces do table.insert(farTriangles,{points=piece,exact=true}) end
							slice()
							return
						end
						table.insert(farTriangles,{points=points,exact=true})
						return
					end
					table.insert(farTriangles,{pa,pb,pc})
				end
				local function ground(a: number?, b: number?, c: number?, pa: Vector3, pb: Vector3, pc: Vector3)
					if HillCuts.collapsed(pa,pb,pc) then return end
					if hillTrimmer then
						local triangles,changed,failure=hillTrimmer(pa,pb,pc)
						if not triangles then uncertifiedHill=true;error(`unsafe terminal hillside repair: {failure or "fragmentation budget"}`) end
						if changed then
							if road.triangles+#triangles>19000 then error("unsafe terminal hillside repair budget") end
							hillTrimmedTriangles+=1
							for _,points in triangles do
								if a and b and c then
									local ids={}
									for j,p in points do
										ids[j]=em:AddVertex(p-centre);road.vertices+=1
										if vertexOrigins then vertexOrigins[ids[j]]={kind="hill bank join",side=side} end
									end
									tri(ids[1],ids[2],ids[3],points[1],points[2],points[3],hillColour,Vector3.yAxis)
								else farGround(points[1],points[2],points[3]) end
								hillTriangles+=1
							end
							return
						end
					end
					local n = (pb - pa):Cross(pc - pa)
					if n.Magnitude < 1e-9 then
						return
					end
					if a and b and c then
						tri(a, b, c, pa, pb, pc, hillColour, Vector3.yAxis)
					else
						farGround(pa,pb,pc)
					end
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
					local pts, coreCount = SplineHill.drawRings(spline,ray)
					local ids = {}
					local near=ray.clip<=ray.st.w[if side<0 then 1 else 2]+H.CoreReach+1e-6
					for j, p in pts do
						if j>coreCount and not near then continue end
						ids[j] = em:AddVertex(p - centre)
						if vertexOrigins then vertexOrigins[ids[j]]={kind="hill",side=side,s=cuts[k],ring=j} end
						road.vertices += 1
					end
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
						traceKind="hill fan"
						for i = ka, kb - 1 do
							local fa, fb = rowAt(i, kind), rowAt(i + 1, kind)
							local far = if i < m then A else B
							ground(fa.ids[5], fb.ids[5], far.ids[1], fa.pts[5], fb.pts[5], far.pts[1])
						end
						local fm = rowAt(m, kind)
						ground(fm.ids[5], A.ids[1], B.ids[1], fm.pts[5], A.pts[1], B.pts[1])
						traceKind="hill ring"
						for j = 1, #A.pts - 1 do
							if j==#A.pts-1 and sideRays[ka].free and sideRays[kb].free then continue end
							ground(A.ids[j], A.ids[j + 1], B.ids[j], A.pts[j], A.pts[j + 1], B.pts[j])
							ground(A.ids[j + 1], B.ids[j + 1], B.ids[j], A.pts[j + 1], B.pts[j + 1], B.pts[j])
						end
					end
					slice()
				end
			end
			traceKind="face"
		end

		-- THE GROVES (T-183): trees and bushes on a widened runoff, in this same mesh, so a
		-- grove costs triangles and no parts (`Road/SplineGrove`)
		-- (measured: 13 ms a grove chunk in one go, 20 at worst). Its trees are drawn a few ms a
		-- frame like the rest (T-193): `slice()` between the triangles
		slice()
		local groveColours: { [Color3]: number } = {}
		traceKind="grove"
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
		pendingModel=model
		model.Name = `Chunk_{math.floor(s0)}`
		model:SetAttribute("Trees", trees)
		model:SetAttribute("S0", s0)
		model:SetAttribute("S1", s1)
		-- white, so the vertex colours are what show
		slice()
		local partStarted=os.clock()-paused
		local roadPart = toPart(road, "Road", Color3.new(1, 1, 1), R.RoadMaterial, grassImage,slice)
		local meshPartMs=(os.clock()-paused-partStarted)*1000
		roadPart.Parent = model
		slice()
		local parts = 0
		local farFolder=Instance.new("Folder");farFolder.Name="FarGround";farFolder.Parent=model
		-- The tile's plain corner also shades the core hillside. Match it with
		-- uniform-colour, flat-lit wedges; no EditableMesh slots are spent here.
		local shade=if grassImage then Config.Spline.Grass.Shade else 1
		local farColour=Color3.new(H.Colour.R*shade,H.Colour.G*shade,H.Colour.B*shade)
		for index,points in farTriangles do
			local made={}
			if points.exact then made=SplineParts.exactTriangle(points.points,.15,farFolder,`Far_{index}`,farColour,Enum.Material.SmoothPlastic)
			else Builder.triangleSlab(`Far_{index}`,points[1],points[2],points[3],.15,farColour,Enum.Material.SmoothPlastic,farFolder,made :: any) end
			for _,part in made do part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false;parts+=1 end
			slice()
		end

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
		-- T-206: certify against the same rows and triangle diagonals as the mesh above.
		-- Intersecting their inward halfspaces gives a conservative convex part of the
		-- terrain, even on a twisted bend. Span/footprint bounds keep boxes behind caps.
		local function endPlanes(planes: { Shadow.Plane }, ka: number, kb: number)
			for _, pair in { { ka, -1 }, { kb, 1 } } do
				local yaw = spline:yawAt(cuts[pair[1]])
				local n = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)) * pair[2]
				table.insert(planes, { n = n, d = n:Dot(surfaceRows[pair[1]][lipL + 1]), span = true })
			end
		end
		local function roof(planes: { Shadow.Plane }, a: { Vector3 }, b: { Vector3 }, first: number, last: number)
			for j = first, last - 1 do
				Shadow.plane(planes, a[j], a[j + 1], b[j], Vector3.yAxis)
				Shadow.plane(planes, a[j + 1], b[j + 1], b[j], Vector3.yAxis)
			end
		end
		local planeCache: { [string]: { Shadow.Plane } } = {}
		local function shadeSpan(ka:number,kb:number,side:number,kind:number):(number,number)
			local rows=faceRows[side][kind]
			-- Internal caster ends need overlap. Certify that overlap against the
			-- actual neighbouring cell rather than imposing two inward margins at
			-- every fine row. Real profile ends retain their closed span boundary.
			if ka>1 and rows[ka-1] and spline:edgeAt((cuts[ka-1]+cuts[ka])*.5,side)==kind then ka-=1 end
			if kb<#cuts and rows[kb+1] and spline:edgeAt((cuts[kb]+cuts[kb+1])*.5,side)==kind then kb+=1 end
			return ka,kb
		end
		local function facePlanes(ka: number, kb: number, side: number, kind: number): { Shadow.Plane }
			local key = `{side}:{kind}:{ka}:{kb}`
			if planeCache[key] then return planeCache[key] end
			ka,kb=shadeSpan(ka,kb,side,kind)
			local planes = {}
			endPlanes(planes, ka, kb)
			local rows = faceRows[side][kind]
			for k = ka, kb - 1 do
				local a, b = rows[k], rows[k + 1]
				local yaw = spline:yawAt((cuts[k] + cuts[k + 1]) / 2)
				local outward = Vector3.new(side * math.cos(yaw), 0, -side * math.sin(yaw))
				local last = if kind == Spline.ROCK and hill then #a - 2 else #a - 1
				for j = 1, last do
					local e = a[j + 1] - a[j]
					local facing = outward * -e.Y + Vector3.yAxis * e:Dot(outward)
					Shadow.plane(planes, a[j], a[j + 1], b[j], facing)
					Shadow.plane(planes, a[j + 1], b[j + 1], b[j], facing)
				end
				if kind == Spline.ROCK then
					-- The hillside starts at the crest; keep the whole caster on this side
					-- of it, without extrapolating an unrelated hillside triangle over it.
					if hill then Shadow.edge(planes, a[5], b[5], (a[1] + b[1]) / 2) end
				else
					-- A cliff caster is inside the drop, under this side's actual runoff.
					local sa, sb = surfaceRows[k], surfaceRows[k + 1]
					local first, lastGrass = if side < 0 then 1 else lipR + 1, if side < 0 then lipL else #sa
					roof(planes, sa, sb, first, lastGrass)
					local inner = if side < 0 then lipL else lipR + 1
					Shadow.edge(planes, sa[inner], sb[inner], (a[1] + b[1]) / 2)
					-- Keep the caster under the actual runoff footprint, including the
					-- lip at a narrow cap. A lower face can fan outside that footprint.
					Shadow.edge(planes, a[1], b[1], (sa[inner] + sb[inner]) / 2)
				end
				slice()
			end
			planeCache[key] = planes
			return planes
		end
		local function footPlanes(ka: number, kb: number, side: number): { Shadow.Plane }?
			local key = `foot:{side}:{ka}:{kb}`
			if planeCache[key] then return planeCache[key] end
			ka,kb=shadeSpan(ka,kb,side,Spline.ROCK)
			local planes = {}
			endPlanes(planes, ka, kb)
			local rows = faceRows[side][Spline.ROCK]
			for k = ka, kb - 1 do
				local a, b = rows[k], rows[k + 1]
				-- A separate safe solid BELOW the actual first face strip. Its vertical
				-- footprint is closed on both sides, so higher jags' infinite planes need
				-- not clip this low caster. This is only valid for an upward facing strip.
				local before = #planes
				local yaw = spline:yawAt((cuts[k] + cuts[k + 1]) / 2)
				local outward = Vector3.new(side * math.cos(yaw), 0, -side * math.sin(yaw))
				local e = a[2] - a[1]
				local facing = outward * -e.Y + Vector3.yAxis * e:Dot(outward)
				Shadow.plane(planes, a[1], a[2], b[1], facing)
				Shadow.plane(planes, a[2], b[2], b[1], facing)
				if #planes ~= before + 2 or planes[before + 1].n.Y <= 1e-5 or planes[before + 2].n.Y <= 1e-5 then return nil end
				Shadow.edge(planes, a[1], b[1], (a[2] + b[2]) / 2)
				Shadow.edge(planes, a[2], b[2], (a[1] + b[1]) / 2)
			end
			planeCache[key] = planes
			return planes
		end
		local function crossesToe(cf:CFrame,size:Vector3,a:Vector3,b:Vector3,c:Vector3):boolean
			local pa,pb,pc=cf:PointToObjectSpace(a),cf:PointToObjectSpace(b),cf:PointToObjectSpace(c)
			local h=size*.5+Vector3.one*.02 -- mesh recentering/packing uncertainty
			local function separated(axis:Vector3):boolean
				if axis.Magnitude<1e-8 then return false end
				local x,y,z=pa:Dot(axis),pb:Dot(axis),pc:Dot(axis)
				local reach=h.X*math.abs(axis.X)+h.Y*math.abs(axis.Y)+h.Z*math.abs(axis.Z)
				return math.min(x,y,z)>reach or math.max(x,y,z)<-reach
			end
			for _,axis in {Vector3.xAxis,Vector3.yAxis,Vector3.zAxis} do if separated(axis) then return false end end
			if separated((pb-pa):Cross(pc-pa)) then return false end
			for _,edge in {pb-pa,pc-pb,pa-pc} do for _,axis in {Vector3.xAxis,Vector3.yAxis,Vector3.zAxis} do
				if separated(edge:Cross(axis)) then return false end
			end end
			return true
		end
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "L" else "R"
			local function footShade(ka: number, kb: number)
				local a, b = faceRows[side][Spline.ROCK][ka], faceRows[side][Spline.ROCK][kb]
				local along = (b[1] - a[1]) * Vector3.new(1, 0, 1)
				if along.Magnitude < 1e-3 then return end
				local x = along.Unit
				local up = (a[2] + b[2] - a[1] - b[1]) / 2 -- proposal matches the certified first strip
				local y = (up - x * up:Dot(x)).Unit
				local outward = Vector3.new(side * math.cos(spline:yawAt((cuts[ka] + cuts[kb]) / 2)), 0, -side * math.sin(spline:yawAt((cuts[ka] + cuts[kb]) / 2)))
				if x:Cross(y):Dot(outward) > 0 then x = -x end
				local toRoad = x:Cross(y)
				local h = math.min(up.Magnitude, T.RockShadeStep)
				if up.Y <= 0.25 or h < 1 then return end
				local size = Vector3.new(along.Magnitude, h + shadeBack, T.RockShadeThickness)
				local centre = (a[1] + b[1]) / 2 + y * ((h - shadeBack) / 2) - toRoad * (shadeBack + size.Z / 2)
				local planes = footPlanes(ka, kb, side)
				if not planes then return end
				local cf, fit = Shadow.fit(CFrame.fromMatrix(centre, x, y, toRoad), size, planes, -toRoad)
				local toeHit=false
				if cf and fit and spline:hasBiomeGround() then
					local toeA,toeB=shadeSpan(ka,kb,side,Spline.ROCK)
					for k=toeA,toeB-1 do
						local a,b=Boundary.toeRow(spline,cuts[k],side),Boundary.toeRow(spline,cuts[k+1],side)
						for j=1,2 do
							if crossesToe(cf,fit,a[j],a[j+1],b[j]) or crossesToe(cf,fit,a[j+1],b[j+1],b[j]) then toeHit=true;break end
						end
						if toeHit then break end
					end
				end
				local fieldHit=hitsField(cf,fit)
				if kb - ka > 1 and (fieldHit or toeHit or not fit or fit.X < size.X * 0.85 or fit.Y < size.Y * 0.8) then
					local mid = (ka + kb) // 2
					footShade(ka, mid)
					footShade(mid, kb)
				elseif not fieldHit and not toeHit and cf and fit and fit.X > 0.15 and fit.Y > 0.25 and fit.Z > 0.15 then
					plain(`RockShade_{tag}_{ka}_Foot`, fit, cf, T.RockColour, Enum.Material.Slate)
				elseif fieldHit then fieldRejectedCasters+=1
				end
			end
			-- A ROCK BODY'S TOP (T-185): a second box under its scrub top, from the face's top
			-- edge to the crest, `shadeBack` down inside the body and short of both ends, so a
			-- grand body's whole height casts and the box is never seen
			-- Both ends' profiles for a box over cuts ka..kb. A rock body's height changes
			-- along the road, and a box drawn between its two ends would show at the lower one,
			-- so the taller end is brought down to the lower's height above its foot (T-185)
			local function ends(ka: number, kb: number, kind: number): ({ Vector3 }, { Vector3 })
				local rows = faceRows[side][kind]
				local pa, pb = table.clone(rows[ka]), table.clone(rows[kb])
				if kind == Spline.ROCK then
					local low = math.huge
					for k = ka, kb do low = math.min(low, rows[k][4].Y - rows[k][1].Y) end
					for _, p in { pa, pb } do
						local h = p[4].Y - p[1].Y
						if h > low and h > 1e-3 then
							for i = 2, #p do p[i] = p[1] + (p[i] - p[1]) * math.max(0, low) / h end
						end
					end
				end
				return pa, pb
			end

			-- A BODY'S END (T-189): a box reaches half a stud past each end of its span, to
			-- overlap its neighbour inside the body; where the body itself ends there (its end
			-- closed by a cap, `cap` above) the box stops half a stud short instead, so it never
			-- shows through the cap, as where the rock meets the drop in a hairpin. Returns the
			-- box's length and how far its centre moves along a -> b.
			local function fitEnds(ka: number, kb: number, kind: number, base: number): (number, number)
				local a, b = cuts[ka], cuts[kb]
				local endA = a > 0.01 and spline:edgeAt(a - 0.01, side) ~= kind
				local endB = b < spline.length - 0.01 and spline:edgeAt(b + 0.01, side) ~= kind
				local extA, extB = if endA then -0.5 else 0.5, if endB then -0.5 else 0.5
				return math.max(0.5, base + extA + extB), (extB - extA) * 0.5
			end
			local function shadeTop(ka: number, kb: number, pa: { Vector3 }, pb: { Vector3 })
				local edge, crest = (pa[4] + pb[4]) * 0.5, (pa[5] + pb[5]) * 0.5
				local along = ((pb[4] + pb[5]) - (pa[4] + pa[5])) * 0.5
				local over = crest - edge
				local len, width = along.Magnitude, over.Magnitude
				local thick = T.RockShadeThickness
				-- a stud short of the face's edge (the face leans back below it, so under the top
				-- there is body) and `trimCrest` short of the crest: the box sinks along the
				-- top's normal, which leans out toward the steep back slope
				local g = spline:grandAt((cuts[ka] + cuts[kb]) * 0.5)
				-- (further from a grand body's edge: its jagged face wanders more from one cut to the next)
				local trim, trimCrest = 1 + 8 * g, 2 + (shadeBack + thick) * 0.6 + 8 * g
				if len < 1e-3 or width < trim + trimCrest + 1 then
					return
				end
				local planAlong = Vector3.new(along.X, 0, along.Z)
				if planAlong.Magnitude < 1e-3 then return end
				local x = planAlong.Unit
				local y = (over - x * over:Dot(x)).Unit
				local z = x:Cross(y)
				if z.Y > 0 then
					x = -x
					z = -z
				end
				-- z now points down, into the body
				local centre = (edge + crest) * 0.5 + y * ((trim - trimCrest) * 0.5) + z * (shadeBack + thick * 0.5)
				-- as long as the crest's own stretch (T-193): on the outside of a bend that is the
				-- longer edge, so neighbours overlap; on the inside, where the profiles fan in, the
				-- shorter, so the box never reaches into a neighbour's differently shaped top; and
				-- short of the body's ends (T-189)
				local short, shift = fitEnds(ka, kb, Spline.ROCK, ((pb[5] - pa[5]) * Vector3.new(1, 0, 1)).Magnitude)
				centre += planAlong.Unit * shift
				local desired = Vector3.new(short, width - trim - trimCrest, thick)
				local cf, size = Shadow.fit(CFrame.fromMatrix(centre, x, y, z), desired, facePlanes(ka, kb, side, Spline.ROCK), z)
				local fieldHit=hitsField(cf,size)
				if kb - ka > 1 and (fieldHit or not size or size.X < desired.X * 0.65 or size.Y < desired.Y * 0.7) then
					local mid = (ka + kb) // 2
					local aa, ab = ends(ka, mid, Spline.ROCK)
					local ba, bb = ends(mid, kb, Spline.ROCK)
					shadeTop(ka, mid, aa, ab)
					shadeTop(mid, kb, ba, bb)
				elseif not fieldHit and cf and size and size.X > 0.15 and size.Y > 0.25 and size.Z > 0.15 then
					plain(`RockShadeTop_{tag}_{ka}`, size, cf, T.RockColour, Enum.Material.Slate)
				elseif fieldHit then fieldRejectedCasters+=1
				end
			end
			local function shade(ka: number, kb: number, kind: number)
				local rock = kind == Spline.ROCK
				local shadeThick = if rock then T.RockShadeThickness else T.CliffShadeThickness
				local pa, pb = ends(ka, kb, kind)
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
					fa = Vector3.new(pa[1].X, footY, pa[1].Z)
					fb = Vector3.new(pb[1].X, footY, pb[1].Z)
				end
				local foot = (fa + fb) * 0.5
				local top = (ta + tb) * 0.5
				local along = ((fb + tb) - (fa + ta)) * 0.5
				local up = top - foot
				local len, height = along.Magnitude, up.Magnitude
				if len < 1e-3 or height < 1e-3 or up.Y <= 0.25 then
					if kb - ka > 1 then
						local mid = (ka + kb) // 2
						shade(ka, mid, kind)
						shade(mid, kb, kind)
					end
					return
				end
				-- Profiles stand upright across the plan curve. Pitching a tall caster
				-- along the grade tipped its upper end into another cross-section and
				-- forced a safe fit to throw away most of its foot/length on steep roads.
				local planAlong = Vector3.new(along.X, 0, along.Z)
				if planAlong.Magnitude < 1e-3 then return end
				local x = planAlong.Unit
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
					-- up to a stud under the face's top edge where the top is deep enough to hold the
					-- box behind the face (T-185: so the shadow reaches the body's top); where a bend
					-- squeezes the top narrow, `RockShadeTopGap` short as before
					local topDeep = math.min(((pa[5] - pa[4]) * Vector3.new(1, 0, 1)).Magnitude, ((pb[5] - pb[4]) * Vector3.new(1, 0, 1)).Magnitude)
					local gap = if topDeep > shadeBack + 5 + shadeThick + 2 then 2 + 4 * spline:grandAt((cuts[ka] + cuts[kb]) * 0.5) else T.RockShadeTopGap
					-- and behind the deepest the jagged face can dent in (T-185: half its jag)
					local back = shadeBack + (2.5 + 7 * spline:grandAt((cuts[ka] + cuts[kb]) * 0.5)) * 0.5
					-- as long as its top's own stretch (T-193): on the outside of a bend the longer
					-- edge, so neighbours overlap up a tall face; on the inside the shorter, so it stays
					-- out of a neighbour where the profiles fan in; and short of the body's ends (T-189)
					local short, shift = fitEnds(ka, kb, kind, ((tb - ta) * Vector3.new(1, 0, 1)).Magnitude)
					local centre = (foot + top) * 0.5 - y * ((shadeBack + gap) * 0.5) - toRoad * (back + shadeThick * 0.5) + planAlong.Unit * shift
					local cf = CFrame.fromMatrix(centre, x, y, toRoad)
					local desired = Vector3.new(short, math.max(0, height + shadeBack - gap), shadeThick)
					local fitted, size = Shadow.fit(cf, desired, facePlanes(ka, kb, side, kind), -toRoad)
					local fieldHit=hitsField(fitted,size)
					if kb - ka > 1 and (fieldHit or not size or size.X < desired.X * 0.65 or size.Y < desired.Y * 0.7) then
						local mid = (ka + kb) // 2
						shade(ka, mid, kind)
						shade(mid, kb, kind)
						return
					elseif not fieldHit and fitted and size and size.X > 0.15 and size.Y > 0.25 and size.Z > 0.15 then
						plain(`RockShade_{tag}_{ka}`, size, fitted, T.RockColour, Enum.Material.Slate)
					elseif fieldHit then fieldRejectedCasters+=1
					end
					if up.Y > shadeBack * 2 + T.RoadShadeSink then
						footShade(ka, kb)
					end
					shadeTop(ka, kb, pa, pb)
				else
					-- behind the face is the road's side: inside the drop, under the grass
					local short, shift = fitEnds(ka, kb, kind, math.max(((fb - fa) * Vector3.new(1, 0, 1)).Magnitude, ((tb - ta) * Vector3.new(1, 0, 1)).Magnitude))
					local centre = (foot + top) * 0.5 + toRoad * (shadeBack + shadeThick * 0.5) + planAlong.Unit * shift
					local cf = CFrame.fromMatrix(centre, x, y, toRoad)
					local desired = Vector3.new(short, height, shadeThick)
					local fitted, size = Shadow.fit(cf, desired, facePlanes(ka, kb, side, kind), toRoad)
					local fieldHit=hitsField(fitted,size)
					if kb - ka > 1 and (fieldHit or not size or size.X < desired.X * 0.65 or size.Y < desired.Y * 0.7) then
						local mid = (ka + kb) // 2
						shade(ka, mid, kind)
						shade(mid, kb, kind)
					elseif not fieldHit and fitted and size and size.X > 0.15 and size.Y > 0.25 and size.Z > 0.15 then
						plain(`CliffShade_{tag}_{ka}`, size, fitted, T.CliffColour, Enum.Material.Slate)
					elseif fieldHit then fieldRejectedCasters+=1
					end
				end
			end
			local k0, kind0 = nil, nil
			for k = 1, #cuts do
				local kind = if k < #cuts then spline:edgeAt((cuts[k] + cuts[k + 1]) * 0.5, side) else nil
				local face = kind == Spline.ROCK or kind == Spline.CLIFF
				-- (and a new box where the grandeur has moved on, so a box follows a body that
				-- grows or shrinks fast, T-185)
				-- On the inside of a tight bend the profiles fan round the bend's centre, so a
				-- flat box there covers less road: about 0.06 radians of the turn
				local span = shadeStep
				if k0 then
					-- the tighter of the bend where the box began and where it has reached (T-193: a
					-- box running from a bend's easing into its tight part would be as long as the easing allows)
					for _, at in { cuts[k0], cuts[k] } do
						local kk = spline:curvatureAt(at)
						if kk ~= 0 and (kk > 0) == (side < 0) then
							span = math.min(span, math.clamp(0.06 / math.abs(kk), 4, shadeStep))
						end
					end
				end
				if k0 and (kind ~= kind0 or cuts[k] - cuts[k0] >= span or math.abs(spline:grandAt(cuts[k]) - spline:grandAt(cuts[k0])) > 0.05) then
					shade(k0, k, kind0 :: number)
					k0 = nil
				end
				if face and not k0 then
					k0, kind0 = k, kind
				end
			end
		end

		-- The roof is below EVERY actual road vertex in this frame, including the
		-- bevel. Every point of a rendered triangle is a convex combination of those
		-- vertices, so this one bound certifies its whole surface without extending a
		-- steep bevel's plane across unrelated tarmac/grass. Footprint planes still
		-- follow every intermediate cut where bank/runoff can narrow.
		do
			local function under(ka: number, kb: number, first: number, last: number, tag: string)
				local sa, sb = cuts[ka], cuts[kb]
				local c = Vector3.new(spline:terrainXYZ((sa + sb) / 2, 0))
				local chord = Vector3.new(spline:terrainXYZ(sb, 0)) - Vector3.new(spline:terrainXYZ(sa, 0))
				if chord.Magnitude < 1e-3 then return end
				local x = chord.Unit
				local n = spline:terrainNormal((sa + sb) / 2, 0)
				local y = (n - x * n:Dot(x)).Unit
				local z = x:Cross(y)
				local x0, x1, z0, z1, top = math.huge, -math.huge, -math.huge, math.huge, math.huge
				local planes = {}
				endPlanes(planes, ka, kb)
				for k = ka, kb do
					local row = surfaceRows[k]
					local za, zb = (row[first] - c):Dot(z), (row[last] - c):Dot(z)
					z0, z1 = math.max(z0, math.min(za, zb)), math.min(z1, math.max(za, zb))
					for j = first, last do
						local p = row[j] - c
						x0, x1, top = math.min(x0, p:Dot(x)), math.max(x1, p:Dot(x)), math.min(top, p:Dot(y))
					end
					if k < kb then
						local nextRow = surfaceRows[k + 1]
						Shadow.edge(planes, row[first], nextRow[first], (row[last] + nextRow[last]) / 2)
						Shadow.edge(planes, row[last], nextRow[last], (row[first] + nextRow[first]) / 2)
					end
				end
				if z1 - z0 < 0.25 then return end
				table.insert(planes, { n = y, d = y:Dot(c) + top })
				local thick = T.RoadShadeThickness
				local centre = c + x * ((x0 + x1) / 2) + y * (top - T.RoadShadeSink - thick / 2) + z * ((z0 + z1) / 2)
				local desired = Vector3.new(x1 - x0, thick, z1 - z0)
				local cf, size = Shadow.fit(CFrame.fromMatrix(centre, x, y, z), desired, planes)
				local fieldHit=hitsField(cf,size)
				if kb - ka > 1 and (fieldHit or not size or size.X < desired.X * 0.65 or size.Z < desired.Z * 0.7) then
					local mid = (ka + kb) // 2
					under(ka, mid, first, last, tag)
					under(mid, kb, first, last, tag)
				elseif not fieldHit and cf and size and size.X > 0.15 and size.Y > 0.15 and size.Z > 0.25 then
					plain(`RoadShade_{tag}_{ka}`, size, cf, T.CliffColour, Enum.Material.Slate)
				elseif fieldHit then fieldRejectedCasters+=1
				end
			end
			local k0 = 1
			for k = 2, #cuts do
				if k == #cuts or cuts[k] - cuts[k0] >= T.RoadShadeStep then
					under(k0, k, 1, #surfaceRows[k0], "Road")
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

		local groveColourIds:{[number]:boolean}={}
		for _,id in groveColours do groveColourIds[id]=true end
		local stats = {
			scenery=if scenery then table.freeze(scenery) else nil,
			fieldCutTriangles=fieldCutTriangles,fieldRejectedCasters=fieldRejectedCasters,
			sections = #cuts,
			vertices = road.vertices,
			triangles = road.triangles,
			grassTriangles = road.grassTriangles, -- textured (T-187)
			textured = grassImage ~= nil,
			parts = parts,
			trees = trees,
			treeTriangles = road.triangles - trianglesBefore,
			groveColourIds = groveColourIds, -- exact provenance for ground measurements
			faceOrigins = faceOrigins,
			treeMs = treeMs,
			hillTriangles = hillTriangles,
			farTriangles=#farTriangles,
			farParts=#farFolder:GetChildren(),
			hillRefinedRays=hillPlan.added,
			hillPlanTests=hillPlan.tests,
			hillPlanExact=hillPlan.exact,
			hillUnsafe=0, -- every emitted repair is recertified against the bank triangles
			hillTerminalOriginal=hillPlan.terminal,
			hillTrimmedTriangles=hillTrimmedTriangles,
			hillTerminalFolds=hillPlan.terminalFolds or 0,
			stations = if hill then #hill.stations else 0,
			surfacePlanMs=surfacePlanMs,
			hillPlanMs=hillPlanMs,
			meshPartMs=meshPartMs,
			ms = 0,
		}
		return { model = model, stats = stats, meshes = { road.em } }
	end)
	if not ok then
		hazeOf[road.em] = nil
		if pendingModel then pendingModel:Destroy() end
		releaseMesh(road.em) -- consumers are destroyed before freeing this slot
		return nil, tostring(built),if uncertifiedHill then {omitHills=true} else nil
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

-- The complete nearby field, including the half owned by an off-window peer.
function SplineMesh.buildInfield(spline:Spline.Spline,x:number,z:number,radius:number,parent:Instance,opts:any?):(Model?,any)
	local o=opts or {}
	if o.forceFail then return nil,"forced infield mesh failure" end
	local began=os.clock()
	if not spline.infields then return nil,"empty" end
	local first=o.first or spline.firstSample*spline.step
	if o.plan and (o.plan.identity~=spline.infields or o.plan.first~=first) then return nil,"field coverage belongs to another road or retained first" end
	local selected=if o.plan then o.plan.triangles else Infield.near(spline.infields,x,z,radius,nil,first)
	local seams=o.seams or {}
	if #selected==0 then return nil,"empty" end
	local paused,slices,worst=0,1,0
	local sliceStart=began
	local budget=(o.sliceMs or Config.Spline.Mesh.SliceMs)/1000
	local function tick()
		if o.cancelled and o.cancelled() then error("infield build cancelled") end
		local now=os.clock()
		if now-sliceStart>=budget then
			worst=math.max(worst,now-sliceStart)
			local before=os.clock();task.wait();local after=os.clock()
			paused+=after-before;slices+=1;sliceStart=after
			if o.cancelled and o.cancelled() then error("infield build cancelled") end
		end
	end
	local lo,hi={math.huge,math.huge,math.huge},{-math.huge,-math.huge,-math.huge}
	for i,t in selected do
		for _,v in {t.a,t.b,t.c} do for j=1,3 do lo[j]=math.min(lo[j],v.p[j]);hi[j]=math.max(hi[j],v.p[j]) end end
		if i%128==0 then local bounded,why=pcall(tick);if not bounded then return nil,tostring(why) end end
	end
	for i,seam in seams do
		if #seam.points~=3 then return nil,"invalid field seam triangle" end
		for _,p in seam.points do for j=1,3 do
			if #p~=3 or p[j]~=p[j] or math.abs(p[j])==math.huge then return nil,"invalid field seam point" end
			lo[j]=math.min(lo[j],p[j]);hi[j]=math.max(hi[j],p[j])
		end end
		if i%128==0 then local bounded,why=pcall(tick);if not bounded then return nil,tostring(why) end end
	end
	for j=1,3 do if hi[j]-lo[j]>2048 then return nil,"infield view exceeds the mesh bounds" end end
	local centre=Vector3.new((lo[1]+hi[1])*.5,(lo[2]+hi[2])*.5,(lo[3]+hi[3])*.5)
	local b:Builder?=nil
	local model:Model?=nil
	local mp:MeshPart?=nil
	local ok,result=xpcall(function()
		tick();b=newBuilder(centre)
		local build=b :: Builder
		local image=GrassTexture.get()
		local targetScale=GrassTexture.plainScale(image)
		tick()
		local T=Config.Spline.Terrain
		local baseU,baseV=GrassTexture.base(centre)
		local plain=build.em:AddUV(Vector2.zero)
		local rock=build.em:AddColor(T.RockColour,1)
		local fieldHaze=hazeColour or T.HazeColour
		local hazeId=build.em:AddColor(fieldHaze,1);local midId=build.em:AddColor(T.CliffColour:Lerp(fieldHaze,.5),1)
		local converted={}
		hazeOf[build.em]={haze=hazeId,mid=midId,converted=converted}
		for _,t in selected do
			local vertices,uvs,colours={},{},{}
			local normal=build.em:AddNormal(t.normal)
			local ordered={t.a,t.b,t.c}
			local a,c,d=t.a.p,t.b.p,t.c.p
			if (c[1]-a[1])*(d[3]-a[3])-(c[3]-a[3])*(d[1]-a[1])>0 then ordered={t.a,t.c,t.b} end
			for _,v in ordered do
				local p=v.p
				table.insert(vertices,build.em:AddVertex(Vector3.new(p[1]-centre.X,p[2]-centre.Y,p[3]-centre.Z)))
				if t.supported then
					local shade=GrassTexture.blotch(p[1],p[3]);local grass=T.GrassColour
					table.insert(colours,build.em:AddColor(Color3.new(math.min(1,grass.R*shade),math.min(1,grass.G*shade),math.min(1,grass.B*shade)),1))
					table.insert(uvs,if image then build.em:AddUV(GrassTexture.uv(p[1],p[3],baseU,baseV)) else plain)
				else table.insert(colours,rock);table.insert(uvs,plain) end
			end
			local f=build.em:AddTriangle(vertices[1],vertices[2],vertices[3])
			build.em:SetFaceNormals(f,{normal,normal,normal});build.em:SetFaceColors(f,colours);build.em:SetFaceUVs(f,uvs)
			build.vertices+=3;build.triangles+=1
			if t.supported then build.grassTriangles+=1 end
			tick()
		end
		for _,seam in seams do
			local a,c,d=seam.points[1],seam.points[2],seam.points[3]
			local normal=Vector3.new(c[1]-a[1],c[2]-a[2],c[3]-a[3]):Cross(Vector3.new(d[1]-a[1],d[2]-a[2],d[3]-a[3]))
			if normal.Magnitude<1e-9 then continue end
			local n=build.em:AddNormal(normal.Unit);local vertices={}
			local material=seam.material
			local colour=SplineParts.seamColour(material,targetScale,hazeColour or T.HazeColour)
			local paint=build.em:AddColor(colour,1)
			if type(material)=="table" and material.haze then
				table.insert(converted,{id=paint,material=material,scale=targetScale})
			end
			for _,p in seam.points do table.insert(vertices,build.em:AddVertex(Vector3.new(p[1]-centre.X,p[2]-centre.Y,p[3]-centre.Z))) end
			local face=build.em:AddTriangle(vertices[1],vertices[2],vertices[3])
			build.em:SetFaceNormals(face,{n,n,n});build.em:SetFaceColors(face,{paint,paint,paint});build.em:SetFaceUVs(face,{plain,plain,plain})
			build.vertices+=3;build.triangles+=1;tick()
		end
		mp=toPart(build,"Infield",Color3.new(1,1,1),Enum.Material.SmoothPlastic,image,tick)
		local fieldPart=mp :: MeshPart
		fieldPart.DoubleSided=true -- unioned legacy closure copies retain both visible sides
		tick()
		model=Instance.new("Model");model.Name="Infield"
		(mp :: MeshPart).Parent=model
		model:SetAttribute("Infield",true);model:SetAttribute("InfieldRevision",if o.plan then o.plan.revision else spline.infieldRevision or 0)
		model:SetAttribute("InfieldCoverage",if o.plan then o.plan.key else "near")
		model.Parent=parent
		meshesOf[model]={build.em}
		worst=math.max(worst,os.clock()-sliceStart)
		return {triangles=build.triangles,vertices=build.vertices,grassTriangles=build.grassTriangles,seamTriangles=#seams,
			ms=(os.clock()-began-paused)*1000,sliceMs=worst*1000,slices=slices}
	end,debug.traceback)
	if not ok then
		if model then meshesOf[model]=nil;model:Destroy() elseif mp then mp:Destroy() end
		if b then hazeOf[b.em]=nil;releaseMesh(b.em) end
		return nil,tostring(result)
	end
	return model,result
end

-- Colour cliff feet in existing chunks and chunks drawn from now on.
function SplineMesh.setHaze(colour: Color3): number
	hazeColour = colour
	local cliff = Config.Spline.Terrain.CliffColour
	local count = 0
	for em, ids in hazeOf do
		local ok = pcall(function()
			em:SetColor(ids.haze, colour)
			em:SetColor(ids.mid, cliff:Lerp(colour, 0.5))
			for _,entry in ids.converted or {} do em:SetColor(entry.id,SplineParts.seamColour(entry.material,entry.scale,colour)) end
		end)
		if ok then
			count += 1
		else
			hazeOf[em] = nil -- destroyed
		end
	end
	SplineParts.setHaze(colour)
	return count
end

-- The haze colour new chunks are drawn with.
function SplineMesh.haze(): Color3
	return hazeColour or Config.Spline.Terrain.HazeColour
end

-- Release mesh slots synchronously; a view can retire the hidden ordinary
-- Parts separately without keeping an EditableMesh alive through that drain.
function SplineMesh.release(model:Model)
	local meshes = meshesOf[model]
	meshesOf[model] = nil
	if meshes then
		for _, em in meshes do
			hazeOf[em] = nil
			releaseMesh(em)
		end
	end
end

-- Take a chunk down, with the mesh data its parts are drawn from.
function SplineMesh.destroy(model: Model)
	model:Destroy()
	SplineMesh.release(model)
end

function SplineMesh.owns(model:Instance):boolean
	return meshesOf[model :: any]~=nil
end

function SplineMesh.liveMeshCount():number
	local count=0;for _ in liveMeshes do count+=1 end;return count
end

return SplineMesh
