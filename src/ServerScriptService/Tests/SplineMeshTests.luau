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
		for i = 0, chunks - 1 do
			local s0, s1 = i * L, math.min((i + 1) * L, spline.length)
			local model, info = SplineMesh.build(spline, s0, s1, folder)
			if not model then
				failed += 1
				check("chunk " .. i .. " built", false, tostring(info))
			else
				models[i] = model
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
		-- (40: the hillside, T-190, is about 6 ms of a chunk, measured: 22 against 16; it is
		-- built a few ms a frame, the next check, so what a frame pays is unchanged)
		check("a chunk is quick to build", worstMs < 40, `mean {fmt(sumMs / math.max(1, built), 2)} ms of work, worst {fmt(worstMs, 2)} ms (one chunk is built at a time)`)
		check(
			"no frame pays much of a chunk",
			worstSlice < Config.Spline.Mesh.SliceMs * 3,
			`spread over {fmt(slices / math.max(1, built), 1)} frames a chunk; the most any one frame paid {fmt(worstSlice, 2)} ms (aim {Config.Spline.Mesh.SliceMs})`
		)
		local window = math.ceil((M.Ahead + M.Behind) / L) + 1
		check(
			"the window fits the client's eight EditableMeshes",
			window + 1 <= 8,
			`the window round the car is {window} chunks, so {window} meshes alive and one being built (a client may hold 8): about {math.floor(tris / math.max(1, built) * window)} triangles and {math.floor(plainParts / math.max(1, built) * window)} plain parts`
		)

		-- 2. Every vertex of the road surface is on the curve's surface.
		local worstV, n = 0, 0
		for _, model in models do
			local road = model:FindFirstChild("Road")
			if road then
				-- read the mesh back through the part: the vertices the GPU gets

				local content = road.MeshContent
				local obj = content and content.Object
				if obj and obj:IsA("EditableMesh") then
					for _, v in obj:GetVertices() do
						local p = road.CFrame:PointToWorldSpace(obj:GetPosition(v))
						local s, d = spline:project(p.X, p.Z, reach)
						-- the ground only: the tarmac and the grass, not the rock and cliff faces
						-- that share the mesh
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
		-- (0.03, where it was 0.01: with the hillside in it, T-190, a chunk's mesh is far bigger,
		-- and the error read back grew with its size -- 0.015 at 973 studs across, 0.022 now --
		-- as if a mesh kept its vertices to a 65 536th of its size)
		check("every surface vertex, tarmac and grass, is on the ground the car stands on", n > 0 and worstV < 0.03, `{n} vertices read back through their parts: worst {fmt(worstV, 4)} studs off (it grows with the mesh's size: the hillside is in it)`)

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
				local obj = road and road.MeshContent.Object
				if obj and obj:IsA("EditableMesh") then
					if road.TextureContent.Object then
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
				local ar, br = a.Road.MeshContent.Object, b.Road.MeshContent.Object
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

		-- 4b. The hedge and K-rail tops run on without a step from one box to the next (a
		-- level box per cut drew a staircase on every slope, seen in the lane). Only
		-- neighbours of the same height, and only the low walls whose tops a driver sees: the
		-- rock face's boxes are a stand-in, redrawn as faces in the feature's next step.
		local worstStep, pairs, steps = 0, 0, 0
		for _, model in models do
			local byName = {}
			for _, p in model:GetChildren() do
				byName[p.Name] = p
			end
			for _, prefix in { "Edge_L_", "Edge_R_" } do
				for k = 1, 4000 do
					local a, b = byName[prefix .. k], byName[prefix .. (k + 1)]
					if a and b and math.abs(a.Size.Y - b.Size.Y) < 1e-3 and a.Size.Y < 20 then
						-- the top edge's end of one box, and the start of the next
						local aEnd = a.CFrame * Vector3.new(0, a.Size.Y / 2, -a.Size.Z / 2 + 0.1)
						local bStart = b.CFrame * Vector3.new(0, b.Size.Y / 2, b.Size.Z / 2 - 0.1)
						local step = math.abs(aEnd.Y - bStart.Y)
						worstStep = math.max(worstStep, step)
						steps += if step > 0.1 then 1 else 0
						pairs += 1
					end
				end
			end
		end
		-- WHERE THE GROUND ITSELF TURNS SHARPLY a short box pitches far more than its
		-- neighbour (the inside of a hairpin, where the grass's width is cut back fast on a
		-- bank): a step of a few tenths there is the ground's shape, not a staircase
		-- NO HEDGES ON THE ROAD since T-189: the generator never chooses one, so no hedge box
		-- is drawn. Should one be (hedges come back as decoration), its tops must still run on
		-- without steps
		local hedges = 0
		for _, model in models do
			for _, p in model:GetChildren() do
				if string.sub(p.Name, 1, 5) == "Edge_" then
					hedges += 1
				end
			end
		end
		check("no hedge drawn on the road, and any hedge tops run on without steps", hedges == 0 and steps <= pairs * 0.01 and worstStep < 0.5, `{hedges} hedge boxes; {pairs} joints: {steps} step more than 0.1 studs, worst {fmt(worstStep, 3)}`)

		-- 4c. The faces of the mountainside: in the one mesh, and never reaching past a
		-- bend's centre on its inside (where the faces of a hairpin would fold through
		-- each other)
		local Spline = require(ReplicatedStorage.Shared.Road.Spline)
		local worstReach, faces = 0, 0
		for u = 0, spline.length, 5 do
			for _, side in { -1, 1 } do
				local kind = spline:edgeAt(u, side)
				if kind == Spline.ROCK or kind == Spline.CLIFF then
					faces += 1
					local k = spline:curvatureAt(u)
					if k ~= 0 and (k > 0) == (side < 0) then
						local pts = SplineMesh.profile(spline, u, side, kind)
						local cx, cz = spline:planAt(u)
						for _, p in pts do
							local reachOut = math.sqrt((p.X - cx) ^ 2 + (p.Z - cz) ^ 2) * math.abs(k)
							worstReach = math.max(worstReach, reachOut)
						end
					end
				end
			end
		end
		check("rock and cliff faces never fold past a bend's centre", faces > 0 and worstReach <= 0.9 + 1e-3, `{faces} face profiles every 5 studs; on the inside of bends the furthest point is {fmt(worstReach * 100, 1)}% of the way to the centre (limit 90%)`)

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
