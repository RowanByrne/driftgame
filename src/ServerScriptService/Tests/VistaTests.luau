--!nonstrict
-- VistaTests: the painted vista's sums and rules (features/painted-vista.md "Testing", T-266).
-- Pure: nothing in the place is touched. Run it in Studio:
--   game.ServerStorage.DebugBridge:Invoke("VistaTests", "run")
--
-- What it cannot check: whether it LOOKS right. That is the user's, in the lane.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "VistaTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Vista = require(ReplicatedStorage.Shared.Vista)

local Tests = {}

-- The drawn ground's widest reach round the car (`Spline.Ground.Detail`), plus the tiles
-- drawn past it near the road (`RoadPad`).
local function groundReach(): number
	local G = Config.Spline.Ground
	local reach = 0
	for _, d in G.Detail do
		reach = math.max(reach, d.Reach)
	end
	return reach + (G.RoadPad or 0)
end

function Tests.run()
	local checks = {}
	local passed = true
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
		if not ok then
			passed = false
		end
	end

	local V = Config.Vista
	local reach = groundReach()
	local total = 0

	for _, layer in V.Layers do
		local panels = Vista.panels(layer)
		check(`{layer.Name}: a panel for every share of the ring`, #panels == layer.Panels, `{#panels}`)
		local widest = 0
		for _, p in panels do
			widest = math.max(widest, p.size.X, p.size.Y, if p.skirt then p.skirt.size.Y else 0)
		end
		check(`{layer.Name}: every part under 2 048 studs`, widest < 2048, string.format("largest side %.0f", widest))
		-- curved panels carry their own skirt; flat ones (the fallback) have a part for it
		total += #panels * (if V.Mesh.Build or not panels[1].skirt then 1 else 2) + 1

		-- beyond the drawn ground even at its full trail
		local nearest = layer.Radius * math.cos(math.pi / layer.Panels) - layer.MaxLag
		check(`{layer.Name}: beyond the drawn ground at its full trail`, nearest > reach, string.format("nearest %.0f, ground %.0f", nearest, reach))

		-- the panels close the ring: each one's ends meet its neighbours'
		local gap = 0
		for i, p in panels do
			local q = panels[i % #panels + 1]
			local pr = (p.cframe * CFrame.new(p.size.X / 2, 0, 0)).Position
			local ql = (q.cframe * CFrame.new(-q.size.X / 2, 0, 0)).Position
			gap = math.max(gap, Vector3.new(pr.X - ql.X, 0, pr.Z - ql.Z).Magnitude)
		end
		check(`{layer.Name}: no gap between neighbouring panels`, gap < 0.5, string.format("widest gap %.2f", gap))

		-- each panel looks in at the anchor
		local facing = true
		for _, p in panels do
			local toCentre = -Vector3.new(p.cframe.Position.X, 0, p.cframe.Position.Z).Unit
			if p.cframe.LookVector:Dot(toCentre) < 0.999 then
				facing = false
			end
		end
		check(`{layer.Name}: every panel faces the camera`, facing)

		-- a few degrees tall, with its bottom below the horizon
		local peak, top, bottom = Vista.angles(layer)
		check(`{layer.Name}: summit 2-10 degrees up`, peak >= 2 and peak <= 10, string.format("summit %.1f, top %.1f, bottom %.1f", peak, top, bottom))
		local skirtBottom = 0
		if panels[1].skirt then
			local s = panels[1].skirt
			skirtBottom = s.cframe.Position.Y - s.size.Y / 2
		end
		local mid = layer.Radius * math.cos(math.pi / layer.Panels)
		-- the cloud sea's far edge, seen from the camera at the road's start
		check(
			`{layer.Name}: the skirt reaches down below the cloud sea`,
			skirtBottom < -V.CloudSea.Below,
			string.format("skirt to %.0f, cloud at %.0f", skirtBottom, -V.CloudSea.Below)
		)
		check(
			`{layer.Name}: the cloud sea reaches past it, so its edge is never seen`,
			Vista.cloudReach(V.CloudSea) > layer.Radius + layer.MaxLag,
			string.format("cloud reaches %.0f", Vista.cloudReach(V.CloudSea))
		)

		-- the curved panels (`Config.Vista.Mesh`)
		local mesh = V.Mesh
		check(`{layer.Name}: as many panels as arcs round the ring`, math.abs(layer.Panels * mesh.ArcDeg - 360) < 1e-6, `{layer.Panels} x {mesh.ArcDeg}`)
		local arcs = Vista.arcs(layer, mesh)
		local arcGap, arcWidest = 0, 0
		for i, p in arcs do
			local q = arcs[i % #arcs + 1]
			local pr = (p.cframe * CFrame.new(p.size.X / 2, 0, -p.size.Z / 2)).Position
			local ql = (q.cframe * CFrame.new(-q.size.X / 2, 0, -q.size.Z / 2)).Position
			arcGap = math.max(arcGap, Vector3.new(pr.X - ql.X, 0, pr.Z - ql.Z).Magnitude)
			arcWidest = math.max(arcWidest, p.size.X, p.size.Y, p.size.Z)
		end
		check(`{layer.Name}: curved panels meet end to end`, arcGap < 0.5, string.format("widest gap %.2f", arcGap))
		check(`{layer.Name}: curved panels under 2 048 studs`, arcWidest < 2048, string.format("largest side %.0f", arcWidest))
		local a1 = arcs[1]
		local arcBottom = a1.cframe.Position.Y - a1.size.Y / 2
		check(
			`{layer.Name}: a curved panel's skirt reaches below the cloud sea`,
			arcBottom < -V.CloudSea.Below,
			string.format("to %.0f, cloud at %.0f", arcBottom, -V.CloudSea.Below)
		)
		local surfaces = game:GetService("ReplicatedStorage"):FindFirstChild("VistaSurfaces")
		local missing = {}
		for _, id in layer.Images do
			local sa = surfaces and surfaces:FindFirstChild(string.match(id, "%d+$") or "")
			if not (sa and sa:IsA("SurfaceAppearance") and sa.AlphaMode == Enum.AlphaMode.Transparency) then
				table.insert(missing, id)
			end
		end
		check(`{layer.Name}: a see-through surface made for every picture`, #missing == 0, table.concat(missing, ", "))
		check(`{layer.Name}: a saddle height for every picture`, layer.Edges ~= nil and #layer.Edges == #layer.Images, `{layer.Edges and #layer.Edges or 0} for {#layer.Images}`)
		-- neighbouring curved panels' saddles meet: each lift cancels its picture's own edge
		local artH = Vista.panelWidth(layer.Radius, layer.Panels) / layer.Aspect
		local worst = 0
		for i, p in arcs do
			local q = arcs[i % #arcs + 1]
			local k1, k2 = (p.index - 1) % #layer.Images + 1, (q.index - 1) % #layer.Images + 1
			local s1 = p.cframe.Position.Y + p.size.Y / 2 + (mesh.TopV - layer.Edges[k1]) * artH
			local s2 = q.cframe.Position.Y + q.size.Y / 2 + (mesh.TopV - layer.Edges[k2]) * artH
			worst = math.max(worst, math.abs(s1 - s2))
		end
		check(`{layer.Name}: neighbouring saddles meet`, worst < 0.5, string.format("worst step %.2f studs", worst))
		local art = #layer.Images > 0
		for _, id in layer.Images do
			art = art and string.match(id, "^rbxassetid://%d+$") ~= nil
		end
		check(`{layer.Name}: every picture has its asset id`, art)
	end

	-- the rings never cross, even at their full trails, and nearer ones slide less
	local byRadius = table.clone(V.Layers)
	table.sort(byRadius, function(a, b)
		return a.Radius < b.Radius
	end)
	for i = 1, #byRadius - 1 do
		local inner, outer = byRadius[i], byRadius[i + 1]
		local _, innerFar = Vista.ringSpan(inner)
		local outerNear = Vista.ringSpan(outer)
		check(
			`{inner.Name} never crosses {outer.Name}`,
			innerFar < outerNear,
			string.format("%s reaches %.0f, %s comes to %.0f", inner.Name, innerFar, outer.Name, outerNear)
		)
		check(`{inner.Name} slides less than {outer.Name}`, inner.Slide < outer.Slide, string.format("%.2f, %.2f", inner.Slide, outer.Slide))
	end
	-- climbing 1 000 studs sinks the nearest ring furthest below the camera
	local sunk = {}
	for _, layer in byRadius do
		table.insert(sunk, string.format("%s %.0f", layer.Name, 1000 - Vista.lift(V, 0, 1000, layer.Slide)))
	end
	check("climbing 1 000 studs, each ring sinks", true, table.concat(sunk, ", "))

	-- the arc mesh: every face looks in at the ring's centre, its box is centred and as sized
	local g = Vista.arcGeometry(V.Mesh)
	local half = math.rad(V.Mesh.ArcDeg / 2)
	local centre = Vector3.new(0, 0, -1000 * (1 + math.cos(half)) / 2)
	local away = 0
	for _, t in g.triangles do
		local a, b, c = g.positions[t[1]], g.positions[t[2]], g.positions[t[3]]
		local n = (b - a):Cross(c - a)
		local to = centre - a
		if n:Dot(Vector3.new(to.X, 0, to.Z)) <= 0 then
			away += 1
		end
	end
	check("arc: every face looks in at the centre", away == 0, `{away} of {#g.triangles} face away`)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in g.positions do
		lo, hi = lo:Min(p), hi:Max(p)
	end
	check("arc: its box is centred", ((lo + hi) / 2).Magnitude < 0.01, tostring((lo + hi) / 2))
	check("arc: its box is the size it says", ((hi - lo) - g.size).Magnitude < 0.01, tostring(hi - lo))
	local uvOk = true
	for _, uv in g.uvs do
		uvOk = uvOk and uv.X >= 0 and uv.X <= 1 and uv.Y > 0 and uv.Y < 1
	end
	check("arc: the picture's v stays inside its edges", uvOk)

	-- the cloud sea
	local sea = V.CloudSea
	check("cloud: the top layer is the widest", sea.Layers[1].Grid >= (sea.Layers[2] and sea.Layers[2].Grid or 0))
	check("cloud: has its asset id", string.match(sea.Image, "^rbxassetid://%d+$") ~= nil)
	check("cloud: the tile divides a part, so parts join",sea.PartSize % sea.Tile == 0, `{sea.PartSize} / {sea.Tile}`)
	check("cloud: parts under 2 048 studs", sea.PartSize <= 2048)
	if sea.Enabled ~= false then
		for _, l in sea.Layers do
			total += l.Grid * l.Grid + 1
		end
	end
	check("fewer than 100 parts in all", total < 100, `{total}`)

	local snapped = Vista.snap(Vector3.new(1530, 0, -2600), sea.Tile)
	check("cloud: snaps to whole tiles", snapped.X % sea.Tile == 0 and snapped.Z % sea.Tile == 0, tostring(snapped))
	local origin = 1000
	check("cloud: under the road's start", Vista.cloudTop(V, origin, origin) == origin - sea.Below)
	check("cloud: rises with the road", Vista.cloudTop(V, origin, origin + 400) > origin - sea.Below)
	local down = origin - 3000
	check(
		"cloud: never nearer than MinBelow under the camera on a long descent",
		down - Vista.cloudTop(V, origin, down) >= sea.MinBelow - 1e-6,
		string.format("%.0f under", down - Vista.cloudTop(V, origin, down))
	)
	local u, v = Vista.drift(1e6, 2.6, 35, sea.Tile)
	check("cloud: drift wraps within a tile", u >= 0 and u < sea.Tile and v >= 0 and v < sea.Tile)

	-- following the camera
	local cam = Vector3.zero
	local c = Vector3.zero
	for _ = 1, 1800 do
		cam += Vector3.new(0, 0, -100 / 60)
		c = Vista.follow(c, cam, 1 / 60, 3, 400)
	end
	check("a layer trails a moving camera by about speed x lag", math.abs((cam - c).Magnitude - 300) < 5, string.format("%.1f behind", (cam - c).Magnitude))
	c = Vista.follow(Vector3.zero, Vector3.new(5000, 0, 0), 1 / 60, 3, 400)
	check("a layer is never further behind than MaxLag", (Vector3.new(5000, 0, 0) - c).Magnitude <= 400 + 1e-6)

	-- every keyframe names the new values
	local missing = {}
	for _, kf in Config.DayNight.Keyframes do
		if typeof(kf.VistaTint) ~= "Color3" or typeof(kf.CloudSeaColour) ~= "Color3" then
			table.insert(missing, kf.Name)
		end
	end
	check("every keyframe names VistaTint and CloudSeaColour", #missing == 0, table.concat(missing, ", "))

	return { passed = passed, checks = checks }
end

return Tests
