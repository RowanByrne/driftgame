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
--   Road        the surface, kerb to kerb: the mesh, because it curves, banks and twists
--   Barrier_*   an upright box per cross-section either side, standing on the kerb and
--               carried down `Thickness` so a crest never shows daylight under it
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

-- A mesh in the making: vertices relative to `centre`, with normals.
type Builder = {
	em: EditableMesh,
	centre: Vector3,
	vertices: number,
	triangles: number,
}


-- A quad strip between two rows of vertex ids, each with its normal id.
local function strip(b: Builder, rowA: { number }, normA: { number }, rowB: { number }, normB: { number }, flip: boolean)
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
		-- the surface: `across` strips, a row of vertices per cross-section
		local prevRow, prevNorm = nil, nil
		for _, s in cuts do
			local row, norm = {}, {}
			for j = 0, across do
				local d = -half + (2 * half) * j / across
				local x, y, z = spline:surfaceXYZ(s, d)
				row[j + 1] = road.em:AddVertex(Vector3.new(x - centre.X, y - centre.Y, z - centre.Z))
				norm[j + 1] = road.em:AddNormal(spline:normalAt(s, d))
				road.vertices += 1
			end
			if prevRow then
				strip(road, prevRow, prevNorm, row, norm, false)
			end
			prevRow, prevNorm = row, norm
		end

		local model = Instance.new("Model")
		model.Name = `Chunk_{math.floor(s0)}`
		model:SetAttribute("S0", s0)
		model:SetAttribute("S1", s1)
		local roadPart = toPart(road, "Road", R.Colours.Road, R.RoadMaterial)
		roadPart.Parent = model
		local parts = 0

		local function plain(name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material)
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
		end

		-- the barriers: a box per cut either side, on the same cuts as the surface, inner
		-- face at exactly half the width. UPRIGHT ACROSS THE ROAD but PITCHED ALONG IT, so its
		-- top follows the grade instead of stepping (a level box per cut drew a staircase on
		-- every slope, seen in the lane); carried down `Thickness` so a crest never shows
		-- daylight under it
		for _, side in { -1, 1 } do
			for k = 1, #cuts - 1 do
				local a, b = cuts[k], cuts[k + 1]
				local off = side * (half + R.BarrierThickness * 0.5)
				local ax, _, az = spline:surfaceXYZ(a, off)
				local bx, _, bz = spline:surfaceXYZ(b, off)
				local ea = spline:heightAt(a) + side * half * math.tan(spline:bankAt(a))
				local eb = spline:heightAt(b) + side * half * math.tan(spline:bankAt(b))
				local pa = Vector3.new(ax, ea, az)
				local pb = Vector3.new(bx, eb, bz)
				local chord = pb - pa
				local len = chord.Magnitude
				if len > 1e-3 then
					local height = R.BarrierHeight + R.Thickness
					local mid = (pa + pb) * 0.5 + Vector3.yAxis * ((R.BarrierHeight - R.Thickness) * 0.5)
					plain(
						`Barrier_{if side < 0 then "L" else "R"}_{k}`,
						Vector3.new(R.BarrierThickness, height, len + 0.2),
						CFrame.lookAt(mid, mid + chord, Vector3.yAxis),
						R.Colours.Barrier,
						R.BarrierMaterial
					)
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
		road.em:Destroy() -- never leak one of the eight
		return nil, tostring(built)
	end
	local result = built :: any
	result.stats.ms = (os.clock() - t0) * 1000
	meshesOf[result.model] = result.meshes
	result.model.Parent = parent
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

return SplineMesh
