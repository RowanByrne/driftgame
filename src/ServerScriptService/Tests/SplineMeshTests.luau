--!nonstrict
-- SplineMeshTests: the spline road's meshes (features/spline-road.md "The mesh, purely
-- visual", T-135). Builds real MeshParts from EditableMeshes in the place, measures them and
-- takes them away. Studio only; run it in a task:
--   game.ServerStorage.DebugBridge:Invoke("DebugSplineMeshTests", "run")
--
-- What it cannot check: whether the road LOOKS right. That is the user's, by driving it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "SplineMeshTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local SplineMesh = require(ReplicatedStorage.Shared.Road.SplineMesh)
local SplineGrove = require(ReplicatedStorage.Shared.Road.SplineGrove)

local Tests = {}

local SEED = 31337
local LENGTH = 8000

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 3) .. "f", x)
end

-- A chunk's surface as an EditableMesh to read back (T-274): a drawn chunk is opaque content,
-- so it is read through an editable copy of that content (what the GPU gets, the template's
-- unused faces folded to a point included); a chunk that kept its fixed-size mesh, through it.
-- The copies are let go by `forget`.
local AssetService = game:GetService("AssetService")
local readCopies: { [Instance]: EditableMesh } = {}
local function editable(part: MeshPart?): EditableMesh?
	if not part then
		return nil
	end
	local content = part.MeshContent
	local obj = content.Object
	if obj and obj:IsA("EditableMesh") then
		return obj
	end
	if readCopies[part] then
		return readCopies[part]
	end
	if content.SourceType ~= Enum.ContentSourceType.Opaque then
		return nil
	end
	local ok, em = pcall(function()
		return AssetService:CreateEditableMeshAsync(content, { FixedSize = true })
	end)
	if ok and em then
		readCopies[part] = em
		return em
	end
	return nil
end
local function forget()
	for part, em in readCopies do
		em:Destroy()
		readCopies[part] = nil
	end
end

function Tests.run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local M = Config.Spline.Mesh
	local half = Config.Road.Width * 0.5
	-- the surface reaches past the tarmac now, across the grass (T-140)
	local reach = half + Config.Spline.Terrain.RunoffMax + 5
	local gen = SplineGen.new(SEED)
	gen:extendTo(LENGTH)
	local spline = gen.spline
	local folder = Instance.new("Folder")
	folder.Name = "__SplineMeshTest"
	folder.Parent = workspace

	local ok, err = pcall(function()
		-- 1. The whole road, chunk by chunk, as the client draws it.
		local L = M.ChunkLength
		local chunks = math.ceil(spline.length / L)
		local tris, verts, worstMs, sumMs, failed, sections, plainParts = 0, 0, 0, 0, 0, 0, 0
		local worstSlice, slices = 0, 0 -- a chunk is built a few ms a frame (T-193)
		local models = {}
		local modelTris = {}
		for i = 0, chunks - 1 do
			local s0, s1 = i * L, math.min((i + 1) * L, spline.length)
			-- (with the road drawing its own runoff, which these checks read: when the ground draws
			-- it, T-251, `GroundMeshView.DebugRunoffGap` measures it)
			local model, info = SplineMesh.build(spline, s0, s1, folder, { runoffBy = "road" })
			if not model then
				failed += 1
				check("chunk " .. i .. " built", false, tostring(info))
			else
				models[i] = model
				modelTris[i] = info.triangles
				tris += info.triangles
				verts += info.vertices
				sections += info.sections
				plainParts += info.parts
				worstMs = math.max(worstMs, info.ms)
				worstSlice = math.max(worstSlice, info.sliceMs or info.ms)
				slices += info.slices or 1
				sumMs += info.ms
			end
			if i % 4 == 3 then
				task.wait()
			end
		end
		local built = chunks - failed
		check(
			"the whole road draws as meshes",
			failed == 0,
			`{built} chunks of {L} studs for {math.floor(spline.length)} studs of road: {tris} triangles, {verts} vertices, {sections} cross-sections ({fmt(spline.length / math.max(1, sections - built), 1)} studs apart on average), {plainParts} barrier and dash parts`
		)
		-- (built a few ms a frame, the next check, so what a frame pays is less than this)
		check("a chunk is quick to build", worstMs < 40, `mean {fmt(sumMs / math.max(1, built), 2)} ms of work, worst {fmt(worstMs, 2)} ms (one chunk is built at a time)`)
		check(
			"no frame pays much of a chunk",
			worstSlice < Config.Spline.Mesh.SliceMs * 3,
			`spread over {fmt(slices / math.max(1, built), 1)} frames a chunk; the most any one frame paid {fmt(worstSlice, 2)} ms (aim {Config.Spline.Mesh.SliceMs})`
		)
		-- THE WINDOW AND THE BUDGET (T-230, T-263, T-273, T-274). Chunks within `Near` of the car
		-- are whole, the rest drawn at `Far`'s detail (T-263). EVERY MESH USER shares the
		-- client's mesh memory (`Mesh.Budget`, in tiles of 128 triangles), EditableImages too:
		-- the ground's tiles and its master, the road, the drift marks, the vista's arc, the
		-- road's texture. T-273: the vista's arc was kept growable (80 tiles) and nothing here
		-- counted it, the marks or the texture, so at the defaults the road ran out and let every
		-- chunk behind the car go. T-274: a drawn chunk is opaque content and holds none of it;
		-- building one holds its template's size for a moment.
		local MB = M.Budget
		local G = Config.Spline.Ground
		local tileTris = G.TileCells * G.TileCells * 2
		-- (as the game draws them, whoever draws the runoff: the chunks above draw it
		-- themselves for the checks that read it, which costs more than the game pays). The
		-- first chunks of this road, and every chunk with a grove, whole and far
		local F = M.Far
		local wholeTris, farTris, sampled, heaviest, heaviestFar = 0, 0, 0, 0, 0
		local groveWhole, groveFar, groves = 0, 0, 0
		for i = 0, chunks - 1 do
			local s0, s1 = i * L, math.min((i + 1) * L, spline.length)
			local hasGrove = models[i] ~= nil and (models[i]:GetAttribute("Trees") or 0) > 0
			if i < 8 or hasGrove then
				local whole, wi = SplineMesh.build(spline, s0, s1, folder, {})
				local far, fi = SplineMesh.build(spline, s0, s1, folder, { tolerance = F.Tolerance, maxStep = F.MaxStep, across = F.Across, leanTrees = F.LeanTrees })
				if whole and far then
					if i < 8 then
						wholeTris += wi.triangles
						farTris += fi.triangles
						sampled += 1
					end
					if hasGrove then
						groveWhole += wi.triangles
						groveFar += fi.triangles
						groves += 1
					end
					heaviest = math.max(heaviest, wi.triangles)
					heaviestFar = math.max(heaviestFar, fi.triangles)
				end
				if whole then
					SplineMesh.destroy(whole)
				end
				if far then
					SplineMesh.destroy(far)
				end
				task.wait()
			end
		end
		local mean = wholeTris / math.max(1, sampled)
		local farMean = farTris / math.max(1, sampled)
		check("a far chunk costs much less than a whole one", sampled > 0 and farMean < mean * 0.6, `far {math.floor(farMean)} triangles, whole {math.floor(mean)}, over {sampled} chunks`)
		check(
			"a far chunk's trees are lean: a grove chunk far costs well under half of it whole",
			groves == 0 or groveFar < groveWhole * 0.5,
			`{groves} grove chunks: whole {math.floor(groveWhole / math.max(1, groves))} triangles, far {math.floor(groveFar / math.max(1, groves))} on average`
		)
		-- THE ESTIMATES THE BUDGET IS WORKED OUT FROM hold what is built: a chunk whole and far
		-- (on average, and the grove chunks with them) as it is built; the heaviest one's
		-- template, what a build holds for a moment (`Building`); the marks' ribbons (their
		-- textures are opaque, T-274). (`Growable` and `Image1024` are measured in a client: a
		-- server has no mesh budget to fill)
		local StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
		local GroundMarks = require(StarterPlayerScripts.Drift.GroundMarks)
		local marks = 0
		for _, spec in { GroundMarks.grassSpec(), GroundMarks.rubberSpec() } do
			local gm = GroundMarks.new(spec)
			marks += GroundMarks.meshTriangles(gm) / tileTris
		end
		-- (a road of this seed's mix: a grove one chunk in every few)
		local allWhole = (wholeTris + groveWhole) / math.max(1, sampled + groves)
		local allFar = (farTris + groveFar) / math.max(1, sampled + groves)
		-- (a copy of a template needs about twice its size while it is made: measured)
		local building = 2 * (SplineMesh.templateFaces(heaviest) or math.huge) / tileTris
		check(
			"the mesh budget's estimates hold what is built",
			allWhole / tileTris <= MB.WholeChunk and allFar / tileTris <= MB.FarChunk and building <= MB.Building and marks <= MB.Marks,
			`a whole chunk {fmt(allWhole / tileTris, 1)} tiles (allowed {MB.WholeChunk}), far {fmt(allFar / tileTris, 1)} ({MB.FarChunk}), with groves weighted in; building the heaviest ({heaviest} triangles) holds twice its template's size for a moment, {fmt(building, 1)} ({MB.Building}); the marks {fmt(marks, 1)} ({MB.Marks})`
		)
		check("a heavy chunk is a small share of the spare room", heaviest / tileTris <= MB.Spare, `heaviest whole chunk {heaviest} triangles ({fmt(heaviest / tileTris, 1)} tiles), far {heaviestFar}; spare {MB.Spare}`)
		-- (T-274) A DRAWN CHUNK HOLDS NO EDITABLEMESH: it is opaque content, read back here
		-- through an editable copy of it, the template's unused faces folded to a point
		local opaque, fixedHeld, folded, foldedOk = 0, 0, 0, true
		for _, model in models do
			local road = model:FindFirstChild("Road") :: MeshPart?
			if road and road.MeshContent.SourceType == Enum.ContentSourceType.Opaque then
				opaque += 1
			elseif road then
				fixedHeld += 1
			end
		end
		for i, model in models do
			local em = editable(model:FindFirstChild("Road") :: MeshPart?)
			if em then
				local here = 0
				for _, f in em:GetFaces() do
					local vs = em:GetFaceVertices(f)
					local a, b, c = em:GetPosition(vs[1]), em:GetPosition(vs[2]), em:GetPosition(vs[3])
					if a == b and b == c then
						here += 1
					end
				end
				folded += here
				-- its own faces, and the rest of its template's folded
				foldedOk = foldedOk and #em:GetFaces() == SplineMesh.templateFaces(modelTris[i]) and here == #em:GetFaces() - modelTris[i]
			else
				foldedOk = false
			end
		end
		check(
			"a drawn chunk is opaque content, written into a template's copy",
			opaque == built and fixedHeld == 0 and foldedOk,
			`{opaque} of {built} chunks opaque, {fixedHeld} holding a fixed-size mesh; read back, each is its template's size with {folded} unused faces in all folded to a point; build state {game:GetService("HttpService"):JSONEncode(SplineMesh.BuildState())}`
		)
		-- (a) THE DEFAULTS: every mesh user fits with `Budget.Spare` over, and the ground keeps
		-- at least its own Ground detail's tiles (what it gives up is corridor far along the road)
		local others = SplineMesh.otherTiles()
		local ultraTiles = G.Detail[#G.Detail].Tiles
		local function groundTiles(detail: any, a: any, b: any): number
			local wanted = math.max(detail.Tiles, math.min(detail.Tiles + a.GroundTiles + b.GroundTiles, ultraTiles + G.CorridorMost))
			return math.max(G.YieldFloor, math.min(wanted, SplineMesh.groundRoom(a.Studs, b.Studs) - G.Spare)), wanted
		end
		local defaults = {
			{ "PC", G.Detail[G.DetailDefault], M.Ahead[M.AheadDefault], M.Behind[M.BehindDefault] },
			{ "touch", G.Detail[G.DetailTouchDefault], M.Ahead[M.AheadTouchDefault], M.Behind[M.BehindTouchDefault] },
		}
		local defOk, defLines = true, {}
		for _, d in defaults do
			local tiles, wanted = groundTiles(d[2], d[3], d[4])
			local road, window, near = SplineMesh.roadTiles(d[3].Studs, d[4].Studs)
			local total = tiles + G.Spare + road + others
			defOk = defOk and total <= MB.Tiles - MB.Spare + 1e-6 and tiles >= d[2].Tiles
			table.insert(defLines, `{d[1]} ({d[2].Name}, {d[3].Name} ahead, {d[4].Name} behind): {math.floor(total)} of {MB.Tiles} tiles = ground {tiles} shown (of {wanted} asked; its own {d[2].Tiles}) + {G.Spare} hidden + road {math.floor(road)} ({window} chunks, {near} whole) + the rest {math.floor(others)}; {math.floor(SplineMesh.freeTiles(d[3].Studs, d[4].Studs))} free`)
		end
		check("every mesh user fits the client's mesh memory at the default settings, the ground keeping its own detail", defOk, `{table.concat(defLines, "; ")}; spare kept {MB.Spare}`)
		-- (T-274) THE GROUND DRAWS WHAT IT DREW: its share is still T-273's (`Budget.GroundShare`),
		-- whose caps T-273 measured (323 tiles at the old defaults, 254 at Longest both ways; 344 at T-278's smaller defaults), and what
		-- the savings freed stays free until the user spends it
		local capDefault = SplineMesh.groundRoom(M.Ahead[M.AheadDefault].Studs, M.Behind[M.BehindDefault].Studs)
		local capLongest = SplineMesh.groundRoom(M.Ahead[#M.Ahead].Studs, M.Behind[#M.Behind].Studs)
		local freeDefault = SplineMesh.freeTiles(M.Ahead[M.AheadDefault].Studs, M.Behind[M.BehindDefault].Studs)
		local freeLongest = SplineMesh.freeTiles(M.Ahead[#M.Ahead].Studs, M.Behind[#M.Behind].Studs)
		check(
			"the ground draws what it drew before T-274, and the savings stay free",
			capDefault == 344 and capLongest == 254 and freeDefault > 0 and freeLongest > 0,
			`the ground's cap {capDefault} at the defaults (T-278: 344; T-273's 323 was at 4 800 ahead, 3 000 behind), {capLongest} at Longest both ways (254); free by these figures {math.floor(freeDefault)} and {math.floor(freeLongest)} tiles`
		)
		-- (b) ANY SETTINGS: the road's whole window fits beside the least ground there can be
		-- (`YieldFloor`, `Drift/MeshBudget`), so no road near the car need ever go; and how many
		-- tiles the ground keeps at each pair, on Ultra
		local worst, worstName, lines = 0, "", {}
		for _, a in M.Ahead do
			for _, b in M.Behind do
				local floored = G.YieldFloor + G.Spare + (SplineMesh.roadTiles(a.Studs, b.Studs)) + others
				if floored > worst then
					worst, worstName = floored, `{a.Name} ahead, {b.Name} behind`
				end
				if a == M.Ahead[#M.Ahead] or b == M.Behind[#M.Behind] then
					local tiles, wanted = groundTiles(G.Detail[#G.Detail], a, b)
					table.insert(lines, `{a.Name}/{b.Name} {tiles} of {wanted}`)
				end
			end
		end
		check(
			"at any Road ahead and behind, the road's whole window fits beside the least ground",
			worst <= MB.Tiles,
			`worst {worstName}: {math.floor(worst)} of {MB.Tiles} tiles with the ground at {G.YieldFloor + G.Spare}; the ground on Ultra: {table.concat(lines, "; ")}`
		)
		-- each way its own steps, growing, to the same Longest (T-278, the user 2026-11-17:
		-- short behind about 1 000, short ahead about 2 000, Longest 9 600 both ways)
		local function grows(list: any): boolean
			local previous = 0
			for _, step in list do
				if step.Studs <= previous or step.GroundTiles < 0 then
					return false
				end
				previous = step.Studs
			end
			return #list >= 2
		end
		check(
			"Road ahead and Road behind each grow to the same Longest",
			grows(M.Ahead) and grows(M.Behind) and M.Ahead[#M.Ahead].Studs == M.Behind[#M.Behind].Studs and M.Ahead[1].Studs > M.Behind[1].Studs,
			`ahead {#M.Ahead} steps, behind {#M.Behind}; Longest {M.Ahead[#M.Ahead].Studs} and {M.Behind[#M.Behind].Studs}`
		)
		local aPc, aTouch = M.Ahead[M.AheadDefault], M.Ahead[M.AheadTouchDefault]
		local bPc, bTouch = M.Behind[M.BehindDefault], M.Behind[M.BehindTouchDefault]
		check(
			"the defaults are Medium ahead (3 600) and Short behind (1 000)",
			aPc ~= nil and aTouch ~= nil and bPc ~= nil and bTouch ~= nil and aPc.Studs == 3600 and aTouch.Studs <= aPc.Studs
				and bPc.Studs == 1000 and bTouch.Studs <= bPc.Studs,
			`ahead PC {aPc and aPc.Studs}, touch {aTouch and aTouch.Studs}; behind PC {bPc and bPc.Studs}, touch {bTouch and bTouch.Studs}`
		)

		-- 2. Every vertex of the road surface is on the curve's surface.
		local worstV, n = 0, 0
		for _, model in models do
			local road = model:FindFirstChild("Road")
			if road then
				-- read the mesh back through the part: the vertices the GPU gets

				local obj = editable(road)
				if obj then
					for _, v in obj:GetVertices() do
						local p = road.CFrame:PointToWorldSpace(obj:GetPosition(v))
						local s, d = spline:project(p.X, p.Z, reach)
						-- the ground only: the tarmac and the grass, not the skirt below their edge
						local side = if d and d < 0 then -1 else 1
						-- nor a grove's trees and bushes standing on the grass (T-183)
						local onTree = false
						if s and d then
							for _, it in SplineGrove.items(spline, s - 20, s + 20, side) do
								local dx, dz = p.X - it.x, p.Z - it.z
								if dx * dx + dz * dz <= (it.r + 0.1) ^ 2 then
									onTree = true
									break
								end
							end
						end
						if s and d and not onTree and math.abs(d) <= half + spline:runoffAt(s, side) + 0.01 then
							local y = spline:terrainY(s, d)
							worstV = math.max(worstV, math.abs(p.Y - y))
							n += 1
						end
					end
				end
			end
		end
		-- (the error read back grows with a mesh's size, as if it kept its vertices to a
		-- 65 536th of it: 0.015 at 973 studs across, 0.022 with the old hillside in it, T-190)
		check("every surface vertex, tarmac and grass, is on the ground the car stands on", n > 0 and worstV < 0.03, `{n} vertices read back through their parts: worst {fmt(worstV, 4)} studs off`)

		-- 2b. The grass's texture (T-187): every grass face mapped in world studs, every other
		-- face on UV (0, 0), where the tile is plain `Shade` grey.
		local GrassTexture = require(ReplicatedStorage.Shared.Road.GrassTexture)
		if Config.Spline.Grass.Enabled then
			local tile = Config.Spline.Grass.TileStuds
			local G = Config.Spline.Grass
			-- a grass face: GrassColour, lightened or darkened by a blotch (the same factor on each
			-- channel, within `Blotch`)
			local gc = Config.Spline.Terrain.GrassColour
			local shadeLo, shadeHi = math.huge, -math.huge
			local function isGrass(c: Color3): boolean
				local k = c.G / gc.G
				local ok = math.abs(c.R - gc.R * k) < 0.01 and math.abs(c.B - gc.B * k) < 0.01 and math.abs(k - 1) <= G.Blotch + 0.01
				if ok then
					shadeLo, shadeHi = math.min(shadeLo, k), math.max(shadeHi, k)
				end
				return ok
			end
			local grassFaces, mappedOk, plainFaces, plainOk, worstStuds, textured = 0, 0, 0, 0, 0, 0
			for _, model in models do
				local road = model:FindFirstChild("Road")
				local obj = editable(road)
				if obj then
					if road.TextureContent.SourceType ~= Enum.ContentSourceType.None then
						textured += 1
					end
					for _, f in obj:GetFaces() do
						local uvs = obj:GetFaceUVs(f)
						if isGrass(obj:GetColor(obj:GetFaceColors(f)[1])) then
							grassFaces += 1
							-- each corner's UV, times the tile, is its world X and Z less whole tiles
							local ok = true
							for k, v in obj:GetFaceVertices(f) do
								local p = road.CFrame:PointToWorldSpace(obj:GetPosition(v))
								local uv = obj:GetUV(uvs[k]) * tile
								local du = (p.X - uv.X) / tile
								local dv = (p.Z - uv.Y) / tile
								local off = math.max(math.abs(du - math.round(du)), math.abs(dv - math.round(dv))) * tile
								worstStuds = math.max(worstStuds, off)
								ok = ok and off < 0.01
							end
							if ok then
								mappedOk += 1
							end
						else
							plainFaces += 1
							local ok = true
							for _, u in uvs do
								ok = ok and obj:GetUV(u).Magnitude < 1e-6
							end
							if ok then
								plainOk += 1
							end
						end
					end
				end
			end
			check(
				"the grass is textured in world studs, and nothing else is",
				textured == built and grassFaces > 0 and mappedOk == grassFaces and plainOk == plainFaces,
				`{textured} of {built} chunks textured; {mappedOk} of {grassFaces} grass faces mapped (worst {fmt(worstStuds, 4)} studs off), {plainOk} of {plainFaces} other faces on the plain corner; blotches {fmt(shadeLo, 3)} to {fmt(shadeHi, 3)} of the grass colour`
			)
			-- the shared image itself, as the chunks draw it: the painted tile, its corners set
			local ts = GrassTexture.DebugState()
			local img = GrassTexture.get()
			local cornerOk, mean, size = false, 0, 0
			local want = math.floor(G.Shade * 255 + 0.5)
			if img then
				size = img.Size.X
				local px = img:ReadPixelsBuffer(Vector2.zero, img.Size)
				cornerOk = true
				for _, xy in { { 0, 0 }, { 1, 1 }, { size - 1, 0 }, { 0, size - 1 }, { size - 1, size - 1 }, { size - 2, 1 } } do
					local o = (xy[2] * size + xy[1]) * 4
					for c = 0, 2 do
						cornerOk = cornerOk and buffer.readu8(px, o + c) == want
					end
				end
				local sum = 0
				for i = 0, size * size - 1 do
					sum += buffer.readu8(px, i * 4 + 1)
				end
				mean = sum / (size * size) / 255
			end
			check("the painted tile loads, its corners plain Shade, and it averages Shade", img ~= nil and cornerOk and math.abs(mean - G.Shade) < 0.03, `{G.Image}: {size} px, loaded in {fmt(ts.buildMs, 1)} ms; corners {want}/255; mean {fmt(mean, 3)} against Shade {G.Shade}`)
		end

		-- 2c. THE TARMAC'S UPLOADED IMAGE IS THE PAINTED ONE (T-274): what the painting makes
		-- today sums to `Tarmac.ImageHash`, and so does the image Roblox decodes from the upload.
		-- Change anything the painting reads and this fails: export it and upload it again
		-- (`assets/road/MANIFEST.md`).
		do
			local RoadTexture = require(ReplicatedStorage.Shared.Road.RoadTexture)
			local T = Config.Spline.Tarmac
			local painted = RoadTexture.pixelHash((RoadTexture.paint()))
			local decoded, why = nil, "no image"
			if T.Image ~= "" then
				local okImg, img = pcall(function()
					return AssetService:CreateEditableImageAsync(Content.fromUri(T.Image))
				end)
				if okImg and img then
					decoded = RoadTexture.pixelHash(img:ReadPixelsBuffer(Vector2.zero, img.Size))
					why = `decoded {img.Size.X} x {img.Size.Y}`
					img:Destroy()
				else
					why = `could not decode it here: {img}`
				end
			end
			check(
				"the tarmac's uploaded image is exactly what is painted",
				T.Image ~= "" and painted == T.ImageHash and (decoded == nil or decoded == T.ImageHash),
				`{T.Image}: painted sum {painted}, decoded {decoded} ({why}), recorded {T.ImageHash}`
			)
		end

		-- 3. Between the cuts, the drawn surface stays within the tolerance of the true one.
		local worstSag = 0
		for i = 0, 5 do
			local cuts = SplineMesh.sections(spline, i * L, (i + 1) * L)
			for k = 1, #cuts - 1 do
				local a, b = cuts[k], cuts[k + 1]
				for _, d in { -half, -half / 2, 0, half / 2, half } do
					local ax, ay, az = spline:surfaceXYZ(a, d)
					local bx, by, bz = spline:surfaceXYZ(b, d)
					local mx, my, mz = spline:surfaceXYZ((a + b) / 2, d)
					local dx, dy, dz = mx - (ax + bx) / 2, my - (ay + by) / 2, mz - (az + bz) / 2
					worstSag = math.max(worstSag, math.sqrt(dx * dx + dy * dy + dz * dz))
				end
			end
		end
		check("the drawn surface stays within tolerance of the true one", worstSag <= M.Tolerance * 1.5, `worst {fmt(worstSag, 4)} studs between cross-sections, at five points across (tolerance {M.Tolerance}, checked at three while cutting)`)

		-- 4. Chunks meet without a seam: the last cut of one is the first of the next.
		local worstSeam = 0
		for i = 0, chunks - 2 do
			local a, b = models[i], models[i + 1]
			if a and b then
				local ar, br = editable(a.Road), editable(b.Road)
				-- the vertices of each at the boundary s, read back through their parts
				local sB = (i + 1) * L
				local function atBoundary(part, em)
					local pts = {}
					for _, v in em:GetVertices() do
						local p = part.CFrame:PointToWorldSpace(em:GetPosition(v))
						local s = spline:project(p.X, p.Z, reach)
						if s and math.abs(s - sB) < 0.01 then
							table.insert(pts, p)
						end
					end
					return pts
				end
				local pa, pb = atBoundary(a.Road, ar), atBoundary(b.Road, br)
				for _, p in pa do
					local best = math.huge
					for _, q in pb do
						best = math.min(best, (p - q).Magnitude)
					end
					worstSeam = math.max(worstSeam, best)
				end
			end
		end
		check("chunks meet with no seam", worstSeam < 0.01, `worst gap between neighbouring chunks' shared edge: {fmt(worstSeam, 4)} studs`)

		-- 4d. The K-rails, drawn as metal crash barriers (T-149), stand where the car's wall
		-- is (`Drift/SplineWorld`): the beam's face on the tarmac's edge, its top at
		-- `KRailHeight`, its posts and spacers inside the wall, its pieces running on without
		-- a step, and a striped hazard panel at both ends of every run.
		local T = Config.Spline.Terrain
		local beams, worstFace, worstTop, posts, postsOut, railSteps, railJoints = 0, 0, 0, 0, 0, 0, 0
		local spacers, bolts, ends, striped = 0, 0, 0, 0
		local function insideWall(p: BasePart, depth: number): boolean
			local s, d = spline:project(p.Position.X, p.Position.Z)
			return s ~= nil and math.abs(d) - depth / 2 >= half - 1e-3 and math.abs(d) + depth / 2 <= half + T.KRailThickness + 1e-3
		end
		for _, model in models do
			local byName = {}
			for _, p in model:GetChildren() do
				byName[p.Name] = p
			end
			for name, p in byName do
				local id, n = string.match(name, "^KRailTop_(.+)_(%d+)$")
				if id then
					-- a rounded ridge: a cylinder along the road (its X), Y up, Z across
					beams += 1
					local best, bestS, bestD = math.huge, nil, nil
					for _, sz in { -1, 1 } do
						local q = p.CFrame * Vector3.new(0, 0, sz * p.Size.Z / 2)
						local s, d = spline:project(q.X, q.Z)
						if s and math.abs(d) < best then
							best, bestS, bestD = math.abs(d), s, d
						end
					end
					if bestS then
						worstFace = math.max(worstFace, math.abs(best - half))
						local top = p.CFrame * Vector3.new(0, p.Size.Y / 2, 0)
						local edgeY = spline:terrainY(bestS, (if bestD < 0 then -1 else 1) * half)
						worstTop = math.max(worstTop, math.abs(top.Y - edgeY - T.KRailHeight))
					end
					local nextP = byName[`KRailTop_{id}_{tonumber(n) + 1}`]
					if nextP then
						local aEnd = p.CFrame * Vector3.new(p.Size.X / 2 - 0.05, p.Size.Y / 2, 0)
						local bStart = nextP.CFrame * Vector3.new(-nextP.Size.X / 2 + 0.05, nextP.Size.Y / 2, 0)
						railJoints += 1
						railSteps += if (aEnd - bStart).Magnitude > 0.1 then 1 else 0
					end
				elseif string.match(name, "^KRailPost_") then
					posts += 1
					postsOut += if insideWall(p, p.Size.X) then 0 else 1
				elseif string.match(name, "^KRailSpacer_") then
					spacers += 1
					postsOut += if insideWall(p, p.Size.X) then 0 else 1
				elseif string.match(name, "^KRailBolt_") then
					bolts += 1
				elseif string.match(name, "^KRailEnd_") then
					ends += 1
					local gui = p:FindFirstChildOfClass("SurfaceGui")
					local frame = gui and gui:FindFirstChildOfClass("Frame")
					striped += if frame and frame:FindFirstChildOfClass("UIGradient") then 1 else 0
				end
			end
		end
		local railLen, railRuns = 0, 0
		for _, side in { -1, 1 } do
			local runs = spline:kRailsIn(0, spline.length, side)
			for r = 1, #runs, 2 do
				railLen += runs[r + 1] - runs[r]
				railRuns += 1
			end
		end
		check("the crash barriers stand where the car's wall is", beams > 0 and worstFace < 0.1 and worstTop < 0.1 and postsOut == 0,
			`{beams} beam pieces on {math.floor(railLen)} studs of rail: face worst {fmt(worstFace, 3)} studs off the tarmac's edge, top worst {fmt(worstTop, 3)} off {T.KRailHeight}; {posts} posts and {spacers} spacers, {postsOut} outside the wall`)
		check("the crash barriers' beams run on without a step", railJoints > 0 and railSteps == 0, `{railJoints} joints, {railSteps} with a gap over 0.1 studs`)
		check("a post on a spacer every ~" .. T.KRailPostEvery .. " studs", posts >= railLen / T.KRailPostEvery and posts <= railLen / T.KRailPostEvery + 2 * railRuns and spacers == posts, `{posts} posts, {spacers} spacers, {bolts} bolt heads on {math.floor(railLen)} studs in {railRuns} runs`)
		check("a striped hazard panel at both ends of every run", ends == 2 * railRuns and striped == ends, `{ends} panels ({striped} striped) for {railRuns} runs`)

		-- 5. Nothing drawn can be touched, collided with or queried.
		local solid = 0
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") and (d.CanCollide or d.CanQuery or d.CanTouch) then
				solid += 1
			end
		end
		check("nothing drawn is solid", solid == 0, `{solid} parts with CanCollide, CanQuery or CanTouch on`)

		-- 6. A device that cannot make a mesh says so, and the caller draws parts.
		local m, why = SplineMesh.build(spline, 0, L, folder, { forceFail = true })
		check("a device that cannot make a mesh says so", m == nil and type(why) == "string", `answered nil: "{tostring(why)}"`)

		for _, model in models do
			SplineMesh.destroy(model)
		end
	end)
	if not ok then
		check("the suite ran", false, tostring(err))
	end
	forget()
	folder:Destroy()

	local passed = 0
	for _, c in checks do
		if c.ok then
			passed += 1
		end
	end
	return { passed = passed, total = #checks, checks = checks }
end

return Tests
