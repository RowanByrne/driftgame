--!nonstrict
-- HorizonTests: the shapes of the mountains round the run (features/horizon.md "Testing",
-- T-150). Pure: nothing in the place is touched. Run it in Studio:
--   game.ServerStorage.DebugBridge:Invoke("DebugHorizonTests", "run")
--
-- What it cannot check: whether they LOOK right. That is the user's, in the lane.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsStudio(), "HorizonTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Horizon = require(ReplicatedStorage.Shared.Horizon)

local Tests = {}

local function flatDistance(p: Vector3): number
	return Vector3.new(p.X, 0, p.Z).Magnitude
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

	local H = Config.Horizon
	local layout = Horizon.layout(H)

	-- the same on every client
	local again = Horizon.layout(H)
	local same = again.triangles == layout.triangles
	for i, layer in layout.layers do
		for t, tri in layer.triangles do
			local o = again.layers[i].triangles[t]
			if not o or o.a ~= tri.a or o.b ~= tri.b or o.c ~= tri.c or o.colour ~= tri.colour then
				same = false
			end
		end
	end
	check("the same seed gives the same mountains", same)

	check("three ridge layers and the peak", #layout.layers == #H.Layers + 1, `{#layout.layers} layers`)

	-- every part fits: no side over MaxEdge, so no wedge over 2 048
	local longest = 0
	for _, layer in layout.layers do
		for _, tri in layer.triangles do
			longest = math.max(longest, (tri.a - tri.b).Magnitude, (tri.b - tri.c).Magnitude, (tri.c - tri.a).Magnitude)
		end
	end
	check("no triangle side over MaxEdge", longest <= H.MaxEdge + 1e-6, string.format("longest %.0f", longest))
	-- each triangle is two wedges: "a few hundred parts"
	check("at most 600 parts", layout.triangles * 2 <= 600, `{layout.triangles * 2} parts`)

	-- each ridge layer: heights in range, ridge at its radius, and beyond the drawn road
	-- the road drawn ahead of the car, and the camera a little behind the car on top
	local roadReach = Config.Spline.Mesh.Ahead + 40
	-- and the lowest the road can stand in the horizon's own frame: at its lowest while the
	-- camera is at the road's highest, so the horizon has risen with it (`FollowHeight`)
	local roadLow = Config.Spline.MinHeight - H.FollowHeight * Config.Spline.MaxHeight
	for i, L in H.Layers do
		local layer = layout.layers[i]
		local lo, hi, near, far = math.huge, -math.huge, math.huge, 0
		for _, tri in layer.triangles do
			for _, p in { tri.a, tri.b, tri.c } do
				lo, hi = math.min(lo, p.Y), math.max(hi, p.Y)
				near, far = math.min(near, flatDistance(p)), math.max(far, flatDistance(p))
			end
		end
		check(`{L.Name}: foot and top in range`, math.abs(lo - L.Base) < 1e-6 and hi <= L.Height[2] + 1e-6 and hi >= L.Height[1], string.format("%.0f..%.0f", lo, hi))
		check(
			`{L.Name}: within its ring`,
			far <= L.Radius * (1 + L.RadiusJitter) + 1e-6 and near >= L.Radius * (1 - L.Depth) * (1 - L.RadiusJitter) - 1e-6,
			string.format("%.0f..%.0f studs out", near, far)
		)
		-- where a face stands as high as the road can go low, it is past the drawn road
		local nearAtRoad = math.huge
		for _, tri in layer.triangles do
			local pts = { tri.a, tri.b, tri.c }
			for k = 1, 3 do
				local p, q = pts[k], pts[k % 3 + 1]
				if p.Y >= roadLow then
					nearAtRoad = math.min(nearAtRoad, flatDistance(p))
				end
				if (p.Y - roadLow) * (q.Y - roadLow) < 0 then
					nearAtRoad = math.min(nearAtRoad, flatDistance(p:Lerp(q, (roadLow - p.Y) / (q.Y - p.Y))))
				end
			end
		end
		check(
			`{L.Name}: never as near as the drawn road`,
			nearAtRoad - L.MaxLag > roadReach,
			string.format("nearest %.0f with the lag, road drawn to %d", nearAtRoad - L.MaxLag, roadReach)
		)
	end

	-- the snow peak: its bearing, its height, snow on top
	local peak = layout.layers[#layout.layers]
	local P = H.Peak
	local top, topP = -math.huge, Vector3.zero
	local snowLow = math.huge
	for _, tri in peak.triangles do
		for _, p in { tri.a, tri.b, tri.c } do
			if p.Y > top then
				top, topP = p.Y, p
			end
		end
		if tri.colour.R > P.Rock.R * 1.3 then -- a snow face
			snowLow = math.min(snowLow, tri.a.Y, tri.b.Y, tri.c.Y)
		end
	end
	local bearing = math.deg(math.atan2(topP.X, -topP.Z)) % 360
	check("peak: summit at its height", math.abs(top - P.Height) < 1e-6, string.format("%.0f", top))
	check("peak: at its bearing", math.abs(bearing - P.Bearing) < 3, string.format("%.1f degrees", bearing))
	check(
		"peak: snow on its top third",
		snowLow >= P.Height * (P.SnowLine - P.SnowJag) - 1 and snowLow <= P.Height * 0.75,
		string.format("snow from %.0f of %d", snowLow, P.Height)
	)
	local tallestFar = 0
	for _, tri in layout.layers[#H.Layers].triangles do
		tallestFar = math.max(tallestFar, tri.a.Y, tri.b.Y, tri.c.Y)
	end
	-- seen from the road's start, the summit stands above the far ridges
	local summitAngle = math.atan2(P.Height, P.Radius)
	local farAngle = math.atan2(tallestFar, H.Layers[#H.Layers].Radius * (1 - H.Layers[#H.Layers].RadiusJitter))
	check("peak: stands above the far ridges", summitAngle > farAngle, string.format("%.1f vs %.1f degrees", math.deg(summitAngle), math.deg(farAngle)))

	-- the valley floor: parts that fit, below every cliff, under the near ridges' feet, and
	-- reaching past where those ridges rise out of it on every side
	local F = H.Floor
	local plates = Horizon.floor(H)
	local biggest = 0
	for _, plate in plates do
		biggest = math.max(biggest, plate.size.X, plate.size.Y, plate.size.Z)
	end
	check("floor: plates fit a part", #plates == F.Tiles * F.Tiles and biggest <= 2048, string.format("%d plates, %.0f studs", #plates, biggest))
	-- the highest the floor stands against the lowest a cliff's face goes: the road at its
	-- lowest, the horizon risen with a camera at the road's highest
	local floorHigh = -F.Depth + H.FollowHeight * Config.Spline.MaxHeight
	local cliffLow = Config.Spline.MinHeight - Config.Spline.Terrain.CliffDrop
	check("floor: below every cliff's face", floorHigh < cliffLow, string.format("floor at most %.0f, cliffs down to %.0f", floorHigh, cliffLow))
	local feetSink = true
	for _, L in H.Layers do
		local layerFeetBelow = L.Base < -F.Depth
		-- the far layer stands beyond the floor, behind the nearer ones
		if L.Radius * (1 - L.Depth) < F.Size / 2 * math.sqrt(2) and not layerFeetBelow then
			feetSink = false
		end
	end
	check("floor: the ridges over it have their feet below it", feetSink)
	local nearL = H.Layers[1]
	local rise = 0
	for _, tri in layout.layers[1].triangles do
		local pts = { tri.a, tri.b, tri.c }
		for k = 1, 3 do
			local p, q = pts[k], pts[k % 3 + 1]
			if (p.Y + F.Depth) * (q.Y + F.Depth) < 0 then
				rise = math.max(rise, flatDistance(p:Lerp(q, (-F.Depth - p.Y) / (q.Y - p.Y))))
			end
		end
	end
	check(
		"floor: reaches past where the near ridges rise out of it",
		F.Size / 2 > rise + nearL.MaxLag,
		string.format("half %.0f, ridges rise by %.0f (+%d lag)", F.Size / 2, rise, nearL.MaxLag)
	)

	-- following the camera: eased, capped, and the peak exact
	local cam = Vector3.new(0, 0, -100)
	local c = Vector3.zero
	for _ = 1, 1800 do -- 30 s at 60 fps, the camera driving 100 studs/s
		cam += Vector3.new(0, 0, -100 / 60)
		c = Horizon.follow(c, cam, 1 / 60, 3, 400)
	end
	check("a layer trails a moving camera by about speed x lag", math.abs((cam - c).Magnitude - 300) < 5, string.format("%.1f behind", (cam - c).Magnitude))
	c = Horizon.follow(Vector3.zero, Vector3.new(5000, 0, 0), 1 / 60, 3, 400)
	check("a layer is never further behind than MaxLag", (Vector3.new(5000, 0, 0) - c).Magnitude <= 400 + 1e-6)
	check("the peak follows exactly", Horizon.follow(Vector3.zero, Vector3.new(7, 0, 9), 1 / 60, 0, 0) == Vector3.new(7, 0, 9))
	local still = Vector3.new(100, 0, 0)
	for _ = 1, 600 do
		still = Horizon.follow(still, Vector3.zero, 1 / 60, 3, 400)
	end
	check("a layer settles on a still camera", still.Magnitude < 5, string.format("%.2f off", still.Magnitude))

	return { passed = passed, checks = checks }
end

return Tests
