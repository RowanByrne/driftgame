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

-- Independent of the shadow fitter: read back the triangles Roblox actually draws and
-- vertically intersect them. A spatial bin keeps the face/corner sweep cheap.
local function envelope(model,excludedColours)
	local part = model.Road
	local em = part.MeshContent.Object
	local bins, triangles, step = {}, {}, 32
	local positions = {}
	local excluded=0
	for _, v in em:GetVertices() do positions[v] = part.CFrame:PointToWorldSpace(em:GetPosition(v)) end
	local function key(x, z)
		return `{math.floor(x / step)}:{math.floor(z / step)}`
	end
	local function add(a,b,c,face,colour)
		local det=(b.X-a.X)*(c.Z-a.Z)-(b.Z-a.Z)*(c.X-a.X)
		if (b-a):Cross(c-a).Magnitude<=1e-7 then return end
		local rock=Config.Spline.Terrain.RockColour
		local t={a=a,b=b,c=c,det=det,face=face,colour=colour,rock=math.abs(colour.R-rock.R)+math.abs(colour.G-rock.G)+math.abs(colour.B-rock.B)<.001}
		table.insert(triangles,t)
		for x=math.floor(math.min(a.X,b.X,c.X)/step),math.floor(math.max(a.X,b.X,c.X)/step) do
			for z=math.floor(math.min(a.Z,b.Z,c.Z)/step),math.floor(math.max(a.Z,b.Z,c.Z)/step) do
				local k=`{x}:{z}`;bins[k]=bins[k] or {};table.insert(bins[k],t)
			end
		end
	end
	for _, f in em:GetFaces() do
		local decorative=false
		if excludedColours then
			for _,id in em:GetFaceColors(f) do if excludedColours[id] then decorative=true;break end end
		end
		if decorative then excluded+=1;continue end
		local ids = em:GetFaceVertices(f)
		local a, b, c = positions[ids[1]], positions[ids[2]], positions[ids[3]]
		add(a,b,c,f,em:GetColor(em:GetFaceColors(f)[1]))
	end
	-- All eight faces of each actual wedge, including growth/thickness/clamping.
	-- A distant primitive must not hide an intrusion above the supported bank.
	local far=model:FindFirstChild("FarGround")
	if far then for _,p in far:GetChildren() do
		if not p:IsA("WedgePart") then continue end
		local h=p.Size*.5;local v={}
		for i,point in {Vector3.new(h.X,-h.Y,h.Z),Vector3.new(h.X,h.Y,h.Z),Vector3.new(h.X,-h.Y,-h.Z),
			Vector3.new(-h.X,-h.Y,h.Z),Vector3.new(-h.X,h.Y,h.Z),Vector3.new(-h.X,-h.Y,-h.Z)} do v[i]=p.CFrame:PointToWorldSpace(point) end
		for _,face in {{1,2,3},{4,6,5},{1,4,5},{1,5,2},{2,5,6},{2,6,3},{3,6,4},{3,4,1}} do
			add(v[face[1]],v[face[2]],v[face[3]],p.Name,p.Color)
		end
	end end
	local function height(p)
		local top = -math.huge
		local normal=nil
		local hit=nil
		for _, t in bins[key(p.X, p.Z)] or {} do
			if math.abs(t.det) <= 1e-7 then continue end
			local a, b, c = t.a, t.b, t.c
			local dx, dz = p.X - a.X, p.Z - a.Z
			local u = (dx * (c.Z - a.Z) - dz * (c.X - a.X)) / t.det
			local v = ((b.X - a.X) * dz - (b.Z - a.Z) * dx) / t.det
			if u >= -1e-5 and v >= -1e-5 and u + v <= 1 + 1e-5 then
				local y=a.Y + u * (b.Y - a.Y) + v * (c.Y - a.Y)
				if y>top then
					top=y;normal=(b-a):Cross(c-a).Unit;hit=t
					if normal.Y<0 then normal=-normal end
				end
			end
		end
		return top,normal,hit
	end
	local function nearby(part)
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, x in { -1, 1 } do for _, y in { -1, 1 } do for _, z in { -1, 1 } do
			local p = part.CFrame:PointToWorldSpace(part.Size * Vector3.new(x, y, z) / 2)
			lo, hi = lo:Min(p), hi:Max(p)
		end end end
		local found = {}
		for x = math.floor(lo.X / step), math.floor(hi.X / step) do
			for z = math.floor(lo.Z / step), math.floor(hi.Z / step) do
				for _, t in bins[`{x}:{z}`] or {} do found[t] = true end
			end
		end
		return found
	end
	return height, triangles, nearby, positions, excluded
end

-- Exact triangle/box intersection, including side faces: a higher, unrelated road
-- cannot mask a caster crossing its local rock/cliff in this check. The 3 box axes,
-- triangle normal and 9 edge/box-axis crosses are the separating axes.
local function crossesFace(part, triangle)
	local a, b, c = part.CFrame:PointToObjectSpace(triangle.a), part.CFrame:PointToObjectSpace(triangle.b), part.CFrame:PointToObjectSpace(triangle.c)
	local h = part.Size / 2
	local function separate(axis)
		if axis.Magnitude < 1e-8 then return false end
		local x, y, z = a:Dot(axis), b:Dot(axis), c:Dot(axis)
		local r = h.X * math.abs(axis.X) + h.Y * math.abs(axis.Y) + h.Z * math.abs(axis.Z)
		return math.min(x, y, z) > r or math.max(x, y, z) < -r
	end
	for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do if separate(axis) then return false end end
	if separate((b - a):Cross(c - a)) then return false end
	for _, edge in { b - a, c - b, a - c } do
		for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do if separate(edge:Cross(axis)) then return false end end
	end
	return true
end

local function rayBox(origin, direction, part)
	local o, d = part.CFrame:PointToObjectSpace(origin), part.CFrame:VectorToObjectSpace(direction)
	local lo, hi = 0, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local h = part.Size[axis] / 2
		if math.abs(d[axis]) < 1e-8 then
			if math.abs(o[axis]) > h then return false end
		else
			local a, b = (-h - o[axis]) / d[axis], (h - o[axis]) / d[axis]
			lo, hi = math.max(lo, math.min(a, b)), math.min(hi, math.max(a, b))
			if hi < lo then return false end
		end
	end
	return hi >= lo
end

local function rayTerrain(origin, direction, triangles, reach)
	for _, t in triangles do
		if not t.rock then continue end
		local e1, e2 = t.b - t.a, t.c - t.a
		local h = direction:Cross(e2)
		local det = e1:Dot(h)
		if math.abs(det) < 1e-7 then continue end
		local s = origin - t.a
		local u = s:Dot(h) / det
		if u < 0 or u > 1 then continue end
		local q = s:Cross(e1)
		local v = direction:Dot(q) / det
		local distance = e2:Dot(q) / det
		if v >= 0 and u + v <= 1 and distance > 0.05 and distance < reach then return true end
	end
	return false
end

function Tests.runShadows(_self, options)
	local opts = options or {}
	local counts, samples, bad, missing, worst, examples, outside = {}, {}, {}, {}, {}, {}, {}
	local built, failed, parts, work, sliceMs = 0, 0, 0, 0, 0
	local sunRays, shaded, opaque = 0, 0, true
	local allRays, allShaded = 0, 0
	local cases = { tight = 0, capped = 0, transition = 0, bankedNarrow = 0 }
	local intersections, pairs, firstIntersection = 0, 0, "none"
	local misses={}
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "__ShadowContainmentTest", workspace
	local ok, err = pcall(function()
		for _, seed in opts.seeds or { 31337, 101, 2024 } do
			local gen = SplineGen.new(seed)
			gen:extendTo(opts.length or 12000)
			local L = Config.Spline.Mesh.ChunkLength
			for chunk = 0, math.ceil(gen.spline.length / L) - 1 do
				if opts.chunks and not table.find(opts.chunks, chunk) then
					continue
				end
				local model, info = SplineMesh.build(gen.spline, chunk * L, math.min((chunk + 1) * L, gen.spline.length), folder)
				if not model then
					failed += 1
					continue
				end
				built += 1
				parts += info.parts
				work = math.max(work, info.ms)
				sliceMs = math.max(sliceMs, info.sliceMs)
				local height, triangles, nearby, positions = envelope(model,info.groveColourIds)
				local cuts = SplineMesh.sections(gen.spline, chunk * L, math.min((chunk + 1) * L, gen.spline.length))
				local actualHeights = { [-1] = {}, [1] = {} }
				for _, side in { -1, 1 } do
					for k, s in cuts do
						local p = SplineMesh.drawProfile(gen.spline, s, side, 1)
						local delta = p[4] - p[1]
						local share = 0
						for _, point in positions do
							local u = (point - p[1]):Dot(delta) / delta:Dot(delta)
							if u > share and u <= 1.001 and (point - p[1] - delta * u).Magnitude < 0.04 then share = u end
						end
						actualHeights[side][k] = share * delta.Y
					end
				end
				for k = 1, #cuts - 1 do
					local s = (cuts[k] + cuts[k + 1]) / 2
					for _, side in { -1, 1 } do
						local kind = gen.spline:edgeAt(s, side)
						local curvature = gen.spline:curvatureAt(s)
						if kind == 1 and math.abs(curvature) > 1 / Config.Spline.Terrain.TightRockRadius and (curvature > 0) == (side < 0) then cases.tight += 1 end
						if kind == 1 then
							local natural = SplineMesh.drawProfile(gen.spline, cuts[k], side, 1)
							if actualHeights[side][k] < (natural[4].Y - natural[1].Y) * 0.9 then cases.capped += 1 end
						end
						if k > 1 and kind ~= gen.spline:edgeAt((cuts[k - 1] + cuts[k]) / 2, side) then cases.transition += 1 end
						if gen.spline:runoffAt(s, side) < 8 and math.abs(gen.spline:bankAt(s)) > 0.02 then cases.bankedNarrow += 1 end
					end
				end
				local casters = {}
				for _, p in model:GetChildren() do
					local kind = string.match(p.Name, "^(%a+Shade%a*)_")
					if not kind then continue end
					table.insert(casters, p)
					opaque = opaque and p.Transparency == 0 and p.CastShadow and not p.CanCollide and not p.CanTouch and not p.CanQuery
					for triangle in nearby(p) do
						pairs += 1
						if crossesFace(p, triangle) then
							intersections += 1
							if firstIntersection=="none" then firstIntersection = `{seed} chunk {chunk} {p.Name}; face {triangle.face}, colour {triangle.colour}` end
						end
					end
					counts[kind] = (counts[kind] or 0) + 1
					for x = -1, 1 do for y = -1, 1 do for z = -1, 1 do
						if x == 0 and y == 0 and z == 0 then continue end
						local q = p.CFrame:PointToWorldSpace(p.Size * Vector3.new(x, y, z) * 0.5)
						local top = height(q)
						local exposed = q.Y - top
						samples[kind] = (samples[kind] or 0) + 1
						if exposed > 0.04 then
							bad[kind] = (bad[kind] or 0) + 1
							if top == -math.huge then
								missing[kind] = (missing[kind] or 0) + 1
								outside[kind] = outside[kind] or `{seed} chunk {chunk} {p.Name} at {q}; size {p.Size}`
							end
							if top ~= -math.huge and exposed > (worst[kind] or -math.huge) then
								worst[kind] = exposed
								examples[kind] = `{seed} chunk {chunk} {p.Name} at {q}`
							end
						end
					end end end
				end
				-- A ten-degree sun behind an actual rock face should still meet an opaque
				-- caster. Qualify rays by intersection with the rendered terrain, not the
				-- uncapped profile, so zero-room transitions are not imaginary coverage.
				for s = chunk * L + 5.3, math.min((chunk + 1) * L, gen.spline.length) - 5, 11 do
					for _, side in { -1, 1 } do
						if gen.spline:edgeAt(s, side) ~= 1 then continue end
						local k = 1
						while k < #cuts - 1 and cuts[k + 1] < s do k += 1 end
						local tall = math.min(actualHeights[side][k], actualHeights[side][k + 1]) >= 25
						local p = SplineMesh.drawProfile(gen.spline, s, side, 1)
						local origin = p[1] + Vector3.yAxis * 2
						local yaw = gen.spline:yawAt(s)
						local direction = Vector3.new(side * math.cos(yaw), math.tan(math.rad(10)), -side * math.sin(yaw))
						if not rayTerrain(origin, direction, triangles, (p[5] - p[1]).Magnitude + 20) then continue end
						allRays += 1
						if tall then sunRays += 1 end
						local blocked=false
						for _, caster in casters do
							if rayBox(origin, direction, caster) then
								blocked=true
								allShaded += 1
								if tall then shaded += 1 end
								break
							end
						end
						if tall and not blocked then
							misses[tostring(seed)]=misses[tostring(seed)] or {}
							if #misses[tostring(seed)]<8 then table.insert(misses[tostring(seed)],{chunk=chunk,s=s,side=side,from=tostring(origin),direction=tostring(direction),rowA=cuts[k],rowB=cuts[k+1]}) end
						end
					end
				end
				SplineMesh.destroy(model)
				task.wait()
			end
		end
	end)
	folder:Destroy()
	local checks = {}
	for _, kind in { "RoadShade", "RockShade", "RockShadeTop", "CliffShade" } do
		table.insert(checks, { name = `{kind} stays inside the rendered terrain`, ok = (counts[kind] or 0) > 0 and (bad[kind] or 0) == 0,
			detail = `{counts[kind] or 0} casters, {samples[kind] or 0} corner/face samples; {bad[kind] or 0} exposed ({missing[kind] or 0} outside footprint), worst finite {worst[kind] or 0}; {examples[kind] or outside[kind] or "none"}` })
	end
	table.insert(checks, { name = "shadow sweep built every requested chunk", ok = ok and failed == 0, detail = `{built} built, {failed} failed, {parts} parts; worst work {fmt(work)} ms, slice {fmt(sliceMs)} ms; {err or ""}` })
	table.insert(checks, { name = "contained casters remain opaque and block a low sun", ok = opaque and sunRays > 0 and shaded / sunRays > 0.8, detail = `{shaded}/{sunRays} ten-degree rays through rendered rock >=25 studs tall blocked; all rock-colour hits including low caps/hillside: {allShaded}/{allRays}; all casters opaque, casting, non-solid: {opaque}` })
	table.insert(checks, { name = "no caster crosses a rendered terrain face, including its sides", ok = intersections == 0, detail = `{pairs} triangle/box pairs; {intersections} intersections; {firstIntersection}` })
	table.insert(checks, { name = "shadow sweep keeps the frame slice budget", ok = sliceMs < Config.Spline.Mesh.SliceMs * 3, detail = `worst {fmt(sliceMs)} ms; bound {Config.Spline.Mesh.SliceMs * 3}` })
	table.insert(checks, { name = "shadow sweep includes bends, caps, transitions and banked narrow runoff", ok = cases.tight > 0 and cases.capped > 0 and cases.transition > 0 and cases.bankedNarrow > 0, detail = game.HttpService:JSONEncode(cases) })
	local passed = 0
	for _, c in checks do if c.ok then passed += 1 end end
	return { passed = passed, total = #checks, checks = checks,misses=misses }
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

function Tests.farGround()
	local Spline=require(ReplicatedStorage.Shared.Road.Spline)
	local H=Config.Spline.Hill
	local saved={reach=H.DrawReach,gather=H.DrawGather,ground=Config.Spline.Biomes.GroundEnabled}
	local folder=Instance.new("Folder");folder.Name="__FarGroundTest";folder.Parent=workspace
	local active=nil
	local ok,result=xpcall(function()
		Config.Spline.Biomes.GroundEnabled=true
		local sp=Spline.new({x=0,y=80,z=-20000,yaw=0});sp.fall=math.pi*.5
		sp:append({len=2000,k={2000,0},g={2000,0},b={2000,0},rl={2000,80},rr={2000,80},el={2000,Spline.ROCK},er={2000,Spline.CLIFF},bm={0,1,0}})
		local info;active,info=SplineMesh.build(sp,700,1180,folder,{traceFaces=true});assert(active,tostring(info))
		local em=active.Road.MeshContent.Object
		local colours,faces={},0
		for face,origin in info.faceOrigins do
			if not string.find(origin.kind,"hill",1,true) then continue end
			for _,id in em:GetFaceColors(face) do colours[tostring(em:GetColor(id))]=true end
			faces+=1
		end
		local count=0;for _ in colours do count+=1 end
		local far=active.FarGround
		local clean=true
		for _,p in far:GetChildren() do clean=clean and not p.CastShadow and not p.CanCollide and not p.CanQuery and not p.CanTouch end
		local measure=envelope(active,info.groveColourIds)
		local covered=0
		for _,side in {-1,1} do
			local p=Vector3.new(sp:terrainXYZ(940,side*(Config.Road.Width*.5+80+H.DrawReach-25)))
			if measure(p)>-math.huge then covered+=1 end
		end
		local meshes=0;for _,p in active:GetDescendants() do if p:IsA("MeshPart") then meshes+=1 end end
		local size=active.Road.MeshSize
		local checks={
			{name="far ground reaches twice the original distance on both open sides",ok=H.DrawReach==2*H.Reach and covered==2 and info.farParts>0,
				detail=`{covered}/2 samples at {H.DrawReach-25} studs past the supported edge; {info.farParts} coarse parts`},
			{name="one legal-size EditableMesh holds the core",ok=meshes==1 and math.max(size.X,size.Y,size.Z)<=2048,
				detail=`{meshes} mesh; core extents {size}; distant ground uses no extra EditableMesh slots`},
			{name="far ground uses one colour and preserves the existing lighting/collision behavior",ok=faces>0 and count==1 and clean,
				detail=`{faces} core hill faces, {count} colour; far parts are non-solid and do not add shadow casters: {clean}`},
		}
		SplineMesh.destroy(active);active=nil
		local function same(a,b)
			if type(a)~=type(b) then return false end
			if type(a)~="table" then return a==b end
			for k,v in a do if not same(v,b[k]) then return false end end
			for k in b do if a[k]==nil then return false end end
			return true
		end
		H.DrawReach,H.DrawGather=H.Reach,H.Gather
		local before=SplineGen.new(203);before:extendTo(6000)
		H.DrawReach,H.DrawGather=saved.reach,saved.gather
		local after=SplineGen.new(203);after:extendTo(6000)
		table.insert(checks,{name="visible reach does not reroute or redecorate the approved road",ok=same(before.sections,after.sections),
			detail=`seed203, {#after.sections} sections; all section geometry, ground, biomes and scenery data compared exactly`})
		local passed=0;for _,item in checks do if item.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	if active then SplineMesh.destroy(active) end
	folder:Destroy();H.DrawReach,H.DrawGather=saved.reach,saved.gather;Config.Spline.Biomes.GroundEnabled=saved.ground
	return if ok then result else {passed=0,total=1,checks={{name="far ground fixture completes",ok=false,detail=result}}}
end

function Tests.hillRobustness()
	local Hill=require(ReplicatedStorage.Shared.Road.SplineHill)
	local Cuts=require(ReplicatedStorage.Shared.Road.SplineHillCuts)
	local Spline=require(ReplicatedStorage.Shared.Road.Spline)
	local saved=Config.Spline.Biomes.GroundEnabled
	Config.Spline.Biomes.GroundEnabled=true
	local folder=Instance.new("Folder");folder.Name="__HillRobustness";folder.Parent=workspace
	local active=nil
	local ok,result=xpcall(function()
		local checks={}
		local function check(name,pass,detail)table.insert(checks,{name=name,ok=pass,detail=detail})end
		for _,side in {-1,1} do
			local a,b,c=Vector3.zero,Vector3.new(side*20,0,0),Vector3.new(0,0,-10)
			check(`side {side}: proper ground and real fold stay distinct`,not Cuts.collapsed(a,b,c) and not Cuts.folded(a,b,c,side)
				and Cuts.folded(a,c,b,side),"reversed finite footprint is still rejected")
			local smallA,smallB,smallC=Vector3.zero,Vector3.new(side*.006,0,0),Vector3.new(0,0,-.006)
			check(`side {side}: small resolvable folds are rejected`,not Cuts.collapsed(smallA,smallB,smallC)
				and not Cuts.folded(smallA,smallB,smallC,side) and Cuts.folded(smallA,smallC,smallB,side),
				"finite footprint below the former fixed area cutoff")
			local sp=Spline.new({x=0,y=0,z=0,yaw=0})
			sp:append({len=1000,k={1,-side/75,1000,-side/75},g={1000,0},b={1000,0}})
			local centre={st={s=200},side=side,clip=75}
			local facing={st={s=200},side=side,clip=60}
			local outside={st={s=200},side=-side,clip=75}
			check(`side {side}: inside skirts stop at the bend centre`,Hill.skirtEnd(sp,centre)<=75+1e-8
				and Hill.skirtEnd(sp,facing)==60+Config.Spline.Hill.Skirt and Hill.skirtEnd(sp,outside)==75+Config.Spline.Hill.Skirt,
				"only the centre-crossing overlap is shortened")
		end
		local a,b,c=Vector3.new(4515.73828125,-115.117668,-20236.787109375),
			Vector3.new(4517.07763671875,-117.05075,-20250.3828125),Vector3.new(4518.47900390625,-124.28023,-20264.603515625)
		check("rounded bend-centre fins have no resolvable ground footprint",Cuts.collapsed(a,b,c),
			"observed seed203 span9437.5..9440.5; paper triangle is omitted, not turned into an upright wall")
		local invalid=Spline.new({x=0,y=0,z=0,yaw=0})
		invalid.fall=math.pi*.5
		invalid:append({len=1,k={1,4},g={1,0},b={1,0},rl={1,12},rr={1,12},el={1,Spline.ROCK},er={1,Spline.CLIFF},bm={0,1,0}})
		local reason,hint
		active,reason,hint=SplineMesh.build(invalid,0,1,folder)
		check("an uncertifiable terminal hillside fails closed",active==nil and hint and hint.omitHills==true and string.find(tostring(reason),"unsafe terminal hillside span",1,true)~=nil,
			`deliberately impossible bend; build returned {reason}`)
		if active then SplineMesh.destroy(active);active=nil end
		local valid=Spline.new({x=0,y=0,z=0,yaw=0})
		valid.fall=math.pi*.5
		valid:append({len=200,k={200,0},g={200,0},b={200,0},rl={200,12},rr={200,12},el={200,Spline.ROCK},er={200,Spline.CLIFF},bm={0,1,0}})
		local hill=Hill.context(valid,0,1,SplineMesh.drawProfile,nil,true)
		local empty=Hill.ray(hill,0,-1)
		local endAt=Hill.faceEnd(empty)
		empty.clip=endAt-.5;empty.meet=1000
		local emptyPoints=Hill.drawRings(valid,empty)
		local endpoint=SplineMesh.drawProfile(valid,0,-1,Spline.ROCK,Hill.cap(empty))[5]
		local emptyGap=0;for _,point in emptyPoints do emptyGap=math.max(emptyGap,(point-endpoint).Magnitude) end
		check("an occupied radial domain collapses to the profile endpoint",emptyGap<.002,
			`no outer ground exists behind the bank; largest endpoint gap {emptyGap}`)
		local rays,caps={[-1]={},[1]={}},{[-1]={},[1]={}}
		for _,side in {-1,1} do for k,s in {0,1} do
			rays[side][k]=Hill.ray(hill,s,side);caps[side][k]=Hill.cap(rays[side][k])
		end end
		local rows={{Vector3.new(-2000,-1000,0),Vector3.new(2000,-1000,0)},
			{Vector3.new(-2000,-1000,-1),Vector3.new(2000,-1000,-1)}}
		local _,occlusion,trim=Cuts.refine(valid,hill,{0,1},rows,{1,2},rays,caps,SplineMesh.drawProfile)
		check("terminal bank occlusion is detected without a fold",occlusion.terminal==1 and occlusion.terminalFolds==0,
			`{occlusion.terminal} unsafe, {occlusion.terminalFolds} folded; correctly wound hills above a synthetic supported plane`)
		local clipped,changed=trim(Vector3.new(1999,0,-.2),Vector3.new(2001,0,-.2),Vector3.new(2001,0,-.8))
		local anchored,peak,insideSafe=false,false,clipped~=nil
		for _,triangle in clipped or {} do for _,p in triangle do
			if math.abs(p.X-2000)<.021 then anchored=anchored or p.Y<-1000.1 end
			peak=peak or p.X>2000.9 and math.abs(p.Y)<.001
			insideSafe=insideSafe and (p.X>=1999.999 or p.Y<-1000.1)
		end end
		check("terminal repairs join the bank while retaining the outer hill",changed and anchored and peak and insideSafe,
			"new boundary vertices sit behind the bank; untouched outside summit remains")
		local touching,touchChanged=trim(Vector3.new(2000,0,-.2),Vector3.new(2001,0,-.2),Vector3.new(2000,0,-.8))
		local joined=touching~=nil
		for _,triangle in touching or {} do for _,p in triangle do
			if math.abs(p.X-2000)<.002 then joined=joined and p.Y<-1000.1 end
		end end
		check("an adjoining hill triangle shares the lowered bank edge",touchChanged and joined,
			"a triangle touching the bank receives the same boundary heights as its clipped neighbour")
		local long,longChanged=trim(Vector3.new(2000,0,1),Vector3.new(2001,0,-.5),Vector3.new(2000,0,-2))
		local ends={[0]=false,[-1]=false}
		for _,triangle in long or {} do for _,p in triangle do
			if math.abs(p.X-2000)<.002 then for z in ends do if math.abs(p.Z-z)<.002 and p.Y<-1000.1 then ends[z]=true end end end
		end end
		check("long touching edges split at both bank limits",longChanged and ends[0] and ends[-1],
			"neither original endpoint lies on the finite bank; new shared boundary vertices close the join")
		local oldRay=rays[1][2]
		local foldedRay=table.clone(oldRay);foldedRay.st=table.clone(oldRay.st);foldedRay.st.rx=-foldedRay.st.rx
		rays[1][2]=foldedRay
		local _,hiddenFold,hiddenRepair=Cuts.refine(valid,hill,{0,1},rows,{1,2},rays,caps,SplineMesh.drawProfile)
		rays[1][2]=oldRay
		check("an early bank occlusion cannot hide a later finite fold",hiddenFold.terminalFolds==1 and hiddenRepair==nil,
			"both sides are checked for winding before a terminal bank repair is allowed")
		local fallback,stats=require(ReplicatedStorage.Shared.Road.SplineParts).build(valid,0,24,folder,{terrain=true,omitHills=hint and hint.omitHills})
		local ground,faces,hills=0,0,0
		for _,part in fallback do
			if string.find(part.Name,"Ground_",1,true)==1 then ground+=1 end
			if string.find(part.Name,"Face_",1,true)==1 then faces+=1 end
			if string.find(part.Name,"Hill_",1,true)==1 then hills+=1 end
		end
		check("unsafe-hill fallback retains supported ground and capped faces",stats.hillsOmitted and ground>0 and faces>0 and hills==0,
			`{ground} ground, {faces} capped face, {hills} hill parts; typed mesh failure hint propagated`)
		for _,part in fallback do part:Destroy() end
		active,reason=SplineMesh.build(valid,0,96,folder)
		check("a valid mesh can build immediately after terminal rejection",active~=nil,tostring(reason))
		if active then SplineMesh.destroy(active);active=nil end
		local passed=0;for _,item in checks do if item.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	if active then SplineMesh.destroy(active) end
	folder:Destroy();Config.Spline.Biomes.GroundEnabled=saved
	return if ok then result else {passed=0,total=1,checks={{name="hill robustness fixture completes",ok=false,detail=result}}}
end

function Tests.surfaceRows()
	local C=Config.Spline.Biomes
	local saved=C.GroundEnabled
	local ok,result=xpcall(function()
		C.GroundEnabled=true
		local g=SplineGen.new(203);g:extendTo(12000)
		local sp=g.spline
		local at={0,219.95,220,220.05,509.1,511.95,512,512.05,sp.length}
		for s=100,sp.length-1,317 do table.insert(at,s) end
		for i=4,#sp.biomes,3 do
			for _,s in {sp.biomes[i]-sp.biomes[i+2]*.5,sp.biomes[i],sp.biomes[i]+sp.biomes[i+2]*.5} do
				for _,d in {-.05,0,.05} do if s+d>=0 and s+d<=sp.length then table.insert(at,s+d) end end
			end
		end
		local checks={}
		for _,enabled in {true,false} do
			C.GroundEnabled=enabled
			local gap,normal,samples=0,0,0
			local optional=true
			for _,direction in {1,-1} do for index=1,#at do
				local s=at[if direction>0 then index else #at-index+1]
				local ds=require(ReplicatedStorage.Shared.Road.SplineSurfaceCuts).offsets(sp,s,4,16)
				local half=Config.Road.Width*.5
				for _,side in {-1,1} do for _,d in {0,.001,sp:lipWidthAt(s,side),sp:runoffAt(s,side)} do
					for _,shift in {-.001,.001} do table.insert(ds,side*(half+d+shift)) end
				end end
				local origin=Vector3.new(41,7,-20200)
				local points,norms,relative=sp:terrainRow(s,ds,true,origin)
				local plain,none,localNone=sp:terrainRow(s,ds,false)
				optional=optional and #none==0 and #localNone==0
				for j,d in ds do
					local x,y,z=sp:terrainXYZ(s,d)
					gap=math.max(gap,(points[j]-Vector3.new(x,y,z)).Magnitude,(relative[j]-Vector3.new(x-origin.X,y-origin.Y,z-origin.Z)).Magnitude,(plain[j]-points[j]).Magnitude)
					normal=math.max(normal,(norms[j]-sp:terrainNormal(s,d)).Magnitude);samples+=1
				end
				if index%16==0 then task.wait() end
			end end
			table.insert(checks,{name=`bulk ground rows equal scalar queries, biome ground {tostring(enabled)}`,ok=gap<1e-7 and normal<1e-7 and optional,
				detail=`{samples} forward/reverse samples at knots, road edges, bevels, banks and transitions; point/relative gap {gap}, normal gap {normal}, optional outputs empty {optional}`})
		end
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	C.GroundEnabled=saved
	return if ok then result else {passed=0,total=1,checks={{name="bulk row fixture completes",ok=false,detail=result}}}
end

function Tests.biomes(_self,options)
	options=options or {}
	local old=Config.Spline.Biomes.GroundEnabled
	Config.Spline.Biomes.GroundEnabled=true
	local folder=Instance.new("Folder");folder.Name="__BiomeMeshTest";folder.Parent=workspace
	local active=nil
	local ok,result=xpcall(function()
		local seed=options.seed or 203
		local gen=SplineGen.new(seed);gen:extendTo(options.length or 12000)
		local spline=gen.spline
		local records=spline.biomes
		local pairs,chunks={},{}
		for i=4,#records,3 do
			local pair=`{records[i-2]}>{records[i+1]}`
			if not pairs[pair] then pairs[pair]=true;chunks[math.floor(records[i]/480)]=true end
		end
		local pairCount=0;for _ in pairs do pairCount+=1 end
		if options.chunk then chunks={[options.chunk]=true} end
		local built,missing,samples,maxError,maxNormal,maxTriangles,maxSlice,work=0,0,0,0,0,0,0,0
		local normalAt="none"
		local errorAt="none"
		local excluded,expectedExcluded=0,0
		local refined,unsafe=0,0
		local activeOrigins=nil
		local function describe(s,d,w,p,y,triangle)
			local detail=`s={s}, d={d}, width={w}, expected={p.Y}, found={y}`
			if triangle then
				detail..=`; face={triangle.face}, colour={triangle.colour}, rock={triangle.rock}`
				if activeOrigins and activeOrigins[triangle.face] then detail..=`; origin={game:GetService("HttpService"):JSONEncode(activeOrigins[triangle.face])}` end
				for _,name in {"a","b","c"} do
					local v=triangle[name]
					local along,across=spline:project(v.X,v.Z,1500)
					detail..=`; {name}={v} (s={along}, d={across})`
				end
			end
			return detail
		end
		for chunk in chunks do
			local s0,s1=chunk*480,math.min((chunk+1)*480,spline.length)
			local info
			active,info=SplineMesh.build(spline,s0,s1,folder,{traceFaces=options.trace==true})
			assert(active,tostring(info))
			activeOrigins=info.faceOrigins
			built+=1;maxTriangles=math.max(maxTriangles,info.triangles);maxSlice=math.max(maxSlice,info.sliceMs);work=math.max(work,info.ms)
			local height,_,_,_,skipped=envelope(active,info.groveColourIds)
			excluded+=skipped;expectedExcluded+=info.treeTriangles
			refined+=info.hillRefinedRays or 0;unsafe+=info.hillUnsafe or 0
			local neighbourHeights={}
			for near=chunk-(options.windowRadius or 1),chunk+(options.windowRadius or 1) do
				if near==chunk then continue end
				if near<0 or near*480>=spline.length then continue end
				local other,stats=SplineMesh.build(spline,near*480,math.min((near+1)*480,spline.length),folder)
				assert(other,tostring(stats))
				local measure=envelope(other,stats.groveColourIds)
				table.insert(neighbourHeights,measure)
				SplineMesh.destroy(other)
			end
			for s=s0+1.17,s1-1,9.31 do
				for _,side in {-1,1} do
					local w=spline:runoffAt(s,side)
					for _,u in {.06,.24,.47,.73,.94,.98,.999,.9999} do
						local d=side*(Config.Road.Width*.5+w*u)
						local p=Vector3.new(spline:terrainXYZ(s,d))
						local y,n,triangle=height(p)
						for _,measure in neighbourHeights do
							local ny,nn,nt=measure(p)
							if ny>y then y,n,triangle=ny,nn,nt end
						end
						if y==-math.huge then missing+=1 else
							local error=math.abs(y-p.Y)
							if error>maxError then maxError=error;errorAt=describe(s,d,w,p,y,triangle) end
							if u<=.94 and w*u>spline:lipWidthAt(s,side)+.5 and n then
								local delta=math.deg(math.acos(math.clamp(n:Dot(spline:terrainNormal(s,d)),-1,1)))
								if delta>maxNormal then maxNormal=delta;normalAt=describe(s,d,w,p,y,triangle) end
							end
						end
						samples+=1
					end
				end
				task.wait()
			end
			SplineMesh.destroy(active);active=nil
		end
		local checks={
			{name="coarse hillside chords stay below supported ground",ok=unsafe==0,detail=`{refined} added hill rays, {unsafe} terminal unsafe spans`},
			{name="terrain measurements exclude only known decorative grove faces",ok=(options.requireDecorations==false or excluded>0) and excluded==expectedExcluded,detail=`{excluded} excluded, exactly {expectedExcluded} generated tree/bush triangles; all terrain faces remain measured`},
			{name="actual mesh interiors match supported terrain through all transitions",ok=(options.chunk~=nil or pairCount==6) and built>0 and missing==0 and maxError<.15,detail=`seed {seed}, {pairCount} directed transitions in {built} chunks; window radius {options.windowRadius or 1}; {samples} samples, missing {missing}, largest height error {maxError}; {errorAt}`},
			{name="bank triangle normals follow the shared surface",ok=maxNormal<5,detail=`largest normal difference {maxNormal} degrees at {normalAt}`},
			{name="near-ground detail keeps one mesh and bounded chunks",ok=maxTriangles<20000 and maxSlice<20,detail=`largest chunk {maxTriangles} triangles, slice {maxSlice} ms, aggregate work {work} ms`},
		}
		local passed=0;for _,c in checks do if c.ok then passed+=1 end end
		return {passed=passed,total=#checks,checks=checks}
	end,debug.traceback)
	if active then SplineMesh.destroy(active) end
	folder:Destroy();Config.Spline.Biomes.GroundEnabled=old
	if not ok then return {passed=0,total=1,checks={{name="biome mesh fixture completes",ok=false,detail=result}}} end
	return result
end

return Tests
