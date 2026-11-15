--!strict
-- RoadGroundController: solid ground under our own avatar on the spline road, while it is
-- out of the car (T-154, features/mountain-road.md "Walking on the road").
--
-- The spline road has NOTHING SOLID ANYWHERE: the car drives on the curve's maths
-- (`Drift/SplineWorld`) and every drawn mesh and part has CanCollide off on purpose. So an
-- avatar that gets out of the car (features/car-v2.md) used to fall straight through it.
--
-- This keeps a small patch of invisible, anchored, colliding parts under and round our own
-- character while it walks, built from this client's copy of the curve (`Road/Spline`), to
-- the same cross-section the car drives on:
--
--   ground   the tarmac and the grass runoff, each tile on the surface's own slope (bank,
--            grade, and the grass easing flat), out to the edge on each side
--   walls    a rock face and a hedge at the runoff's outer edge, and a K-rail (the metal
--            crash barrier) on the tarmac's edge where one stands. The closing barrier
--            behind the run's window too
--   nothing  past a cliff's lip, or past the end of the laid road: walking off falls, and
--            whatever a fall does to an avatar today still happens
--
-- THE TILES SIT ON A FIXED LATTICE along the road (`ROW` studs a row, the cross-section cut
-- the same way every time), so the tile under the avatar never moves: walking only adds
-- rows ahead and drops rows behind. They are rebuilt only when the avatar crosses into
-- another row or band, the closing barrier moves, or more road arrives.
--
-- ONLY OUR OWN AVATAR. Each client simulates its own character, so ground made here is all
-- it needs; everyone else's avatar stands on the ground their own client makes, and we see
-- where it stands. Nothing here goes to the server.
--
-- THE CAR NEVER MEETS THESE PARTS. Its world (`Drift/World.live`, wrapped by
-- `Drift/SplineWorld`) sweeps and overlaps against anything solid, so the patch exists only
-- while the simulation is HELD (`DriftController:IsDriving()` false), which is exactly
-- while nothing steps and nothing asks the world. It goes the moment the server puts the
-- avatar back in the seat (its root anchored, the car's `Driver` ours), on `CarEnter` and
-- `CarSpawn`, when the run ends and when the road leaves; and this checks every frame at
-- `RenderPriority.First`, before the drift step, so a car that starts driving has already
-- lost them. None of them is tagged `DriftSurface`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local Driver = require(DriftFolder:WaitForChild("Driver")) :: any

local DriftController = require(script.Parent.DriftController) :: any
local SplineRoadController = require(script.Parent.SplineRoadController) :: any

local RoadGroundController = {}

local STEP_NAME = "RoadGround"

-- THE PATCH. Walking at 16 studs/s an avatar crosses a row in a quarter of a second, and
-- the patch reaches 6 rows each way, so it is never near the edge of its own ground.
local ROW = 4 -- studs along the road per row of tiles
local ROWS_EACH_WAY = 6 -- rows ahead of and behind the avatar's
local ACROSS = 24 -- studs either side of the avatar across the road
local PIECE = 6 -- the widest a tile is across: the grass eases flat, and stays within 0.1
local THICK = 2 -- studs: each tile's thickness, under the surface
local OVERLAP = 0.1 -- studs each tile is grown by, so no seam opens between two

-- A CLIFF'S LIP is where the grass ends, and the grass widens and narrows along the road
-- (up to about a third of a stud per stud). A row's outer tile on a cliff side is cut into
-- strips until no strip's lip steps in by more than this.
local LIP_STEP = 0.25

-- THE WALLS, in studs. The drawn rock face is 25 to 60 high and leans back; to the avatar
-- it is a wall at its foot it cannot climb. The hedge is drawn 6 high, which an avatar
-- can just jump on to, and behind it there is nothing drawn and nothing to stand on, so
-- its wall is taller than a jump. A K-rail is the car's wall exactly: jump it, and the
-- grass and then the cliff are behind it. The closing barrier is taller than a jump too.
local ROCK_WALL = 80
local ROCK_THICK = 6
local HEDGE_WALL = 12
local CLOSING_WALL = 24
local SINK = 3 -- how far a wall reaches down under the ground at its foot

type Spec = { size: Vector3, cf: CFrame, material: Enum.Material, kind: string }

local player = Players.LocalPlayer
local folder: Folder? = nil
local parts: { [string]: BasePart } = {}
local hint: number? = nil
local lastKey = ""
local stats = {
	rebuilds = 0,
	rebuildMs = 0, -- the last rebuild's cost
	worstMs = 0, -- and the worst so far
	clears = 0,
	created = 0,
	ground = 0,
	walls = 0,
	rails = 0,
	closing = 0,
	located = false,
	s = 0,
	d = 0,
	out = false,
}

local function newPart(): BasePart
	local p = Instance.new("Part")
	p.Name = "RoadGround"
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Locked = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	stats.created += 1
	return p
end

local function clear()
	if next(parts) == nil then
		return
	end
	for _, p in parts do
		p:Destroy()
	end
	table.clear(parts)
	lastKey = ""
	stats.clears += 1
	stats.ground, stats.walls, stats.rails, stats.closing = 0, 0, 0, 0
end

-- Our avatar's root while it is out of the car and free to walk, else nil. In the seat its
-- root is anchored and the car's `Driver` is us; while the car is driving nothing may be
-- solid round it.
local function walkingRoot(): BasePart?
	local character = player.Character
	local root = Driver.rootOf(character)
	if not root or root.Anchored then
		return nil
	end
	if DriftController:IsDriving() then
		return nil
	end
	local car = DriftController:Car()
	if car and Driver.driverOf(car) == player.UserId then
		return nil
	end
	return root
end

-- Where along and across the road a point is: from the last answer when there is one.
local function locate(spline: any, x: number, z: number, reach: number): (number?, number?)
	local s, d
	if hint then
		s, d = spline:projectFrom(x, z, hint)
	end
	if not s or not d or math.abs(d) > reach then
		s, d = spline:project(x, z, reach)
	end
	if not s or not d or math.abs(d) > reach then
		return nil, nil
	end
	hint = s
	return s, d
end

local function dist(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local x, y, z = bx - ax, by - ay, bz - az
	return math.sqrt(x * x + y * y + z * z)
end

-- Everything the patch should hold round (sc, dc), by key. A key names the same tile every
-- time it is asked for, and the same key always gives the same tile.
local function plan(spline: any, sc: number, dc: number, closingS: number?): { [string]: Spec }
	local R = Config.Road
	local T = Config.Spline.Terrain
	local half = R.Width * 0.5
	local want: { [string]: Spec } = {}
	local lo, hi = dc - ACROSS, dc + ACROSS

	-- a ground tile over [s0, s1] x [d0, d1], its top on the surface at its middle. A
	-- `slope` tile lies along the chord from its inner edge to its outer one instead of on
	-- the ground's normal: the road's step down to the grass (T-184), a ramp an avatar walks
	-- up rather than a ledge it has to jump
	local function tile(key: string, s0: number, s1: number, d0: number, d1: number, material: Enum.Material, slope: boolean?)
		if d1 - d0 < 0.05 or s1 - s0 < 0.05 or d1 < lo or d0 > hi then
			return
		end
		local sm, dm = (s0 + s1) * 0.5, (d0 + d1) * 0.5
		local x, y, z = spline:terrainXYZ(sm, dm)
		local n: Vector3 = spline:terrainNormal(sm, dm)
		local function along(d: number): number
			local ax, ay, az = spline:terrainXYZ(s0, d)
			local bx, by, bz = spline:terrainXYZ(s1, d)
			return dist(ax, ay, az, bx, by, bz)
		end
		local cx, cy, cz = spline:terrainXYZ(sm, d0)
		local ex, ey, ez = spline:terrainXYZ(sm, d1)
		local across = dist(cx, cy, cz, ex, ey, ez)
		if slope then
			local ax, ay, az = spline:terrainXYZ(s0, dm)
			local bx, by, bz = spline:terrainXYZ(s1, dm)
			local m = Vector3.new(bx - ax, by - ay, bz - az):Cross(Vector3.new(ex - cx, ey - cy, ez - cz))
			if m.Magnitude < 1e-6 then
				return
			end
			n = if m.Y < 0 then -m.Unit else m.Unit
			x, y, z = (cx + ex) * 0.5, (cy + ey) * 0.5, (cz + ez) * 0.5
		end
		local yaw = spline:yawAt(sm)
		local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
		local r = right - n * right:Dot(n)
		if r.Magnitude < 1e-4 then
			return
		end
		want[key] = {
			size = Vector3.new(across + OVERLAP, THICK, math.max(along(d0), along(d1)) + OVERLAP),
			cf = CFrame.fromMatrix(Vector3.new(x, y, z) - n * (THICK * 0.5), r.Unit, n),
			material = material,
			kind = "ground",
		}
	end

	-- an upright wall along the road on `side`, its inner face from `innerA` at `a` to
	-- `innerB` at `b` (studs out from the centre line), pitched along the grade as the drawn
	-- hedge is (`Road/SplineMesh`)
	local function wall(key: string, kind: string, a: number, b: number, side: number, innerA: number, innerB: number, thick: number, height: number, material: Enum.Material)
		if b - a < 0.05 then
			return
		end
		-- across the road the wall covers [near, far]; leave it out if that misses the window
		local near = side * math.min(innerA, innerB)
		local far = side * (math.max(innerA, innerB) + thick)
		if math.max(near, far) < lo - 1 or math.min(near, far) > hi + 1 then
			return
		end
		local ax, _, az = spline:terrainXYZ(a, side * (innerA + thick * 0.5))
		local bx, _, bz = spline:terrainXYZ(b, side * (innerB + thick * 0.5))
		local pa = Vector3.new(ax, spline:terrainY(a, side * innerA), az)
		local pb = Vector3.new(bx, spline:terrainY(b, side * innerB), bz)
		local chord = pb - pa
		local len = chord.Magnitude
		if len < 1e-3 then
			return
		end
		local mid = (pa + pb) * 0.5 + Vector3.yAxis * ((height - SINK) * 0.5)
		want[key] = {
			size = Vector3.new(thick, height + SINK, len + OVERLAP),
			cf = CFrame.lookAt(mid, mid + chord, Vector3.yAxis),
			material = material,
			kind = kind,
		}
	end

	-- the stretches of [s0, s1] with one edge kind each on `side`: an edge changes only at
	-- a section's end, found to a few hundredths of a stud
	local function edgeSpans(s0: number, s1: number, side: number): { { number } }
		local k0, k1 = spline:edgeAt(s0, side), spline:edgeAt(s1, side)
		if k0 == k1 then
			return { { s0, s1, k0 } }
		end
		local a, b = s0, s1
		for _ = 1, 8 do
			local m = (a + b) * 0.5
			if spline:edgeAt(m, side) == k0 then
				a = m
			else
				b = m
			end
		end
		return { { s0, b, k0 }, { b, s1, k1 } }
	end

	local nc = math.floor(sc / ROW)
	local tarmacPieces = math.ceil(R.Width / PIECE)
	local tarmacW = R.Width / tarmacPieces
	for n = nc - ROWS_EACH_WAY, nc + ROWS_EACH_WAY do
		local s0, s1 = n * ROW, (n + 1) * ROW
		if s0 < 0 or s1 > spline.length then
			continue -- off the start of the road, or past the end of what is laid
		end
		-- the tarmac
		for j = 1, tarmacPieces do
			local d0 = -half + (j - 1) * tarmacW
			tile(`t{n}:{j}`, s0, s1, d0, d0 + tarmacW, Enum.Material.Asphalt)
		end
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "L" else "R"
			-- the road's gravel bevel down to the grass (T-184), a sloping tile from the tarmac's
			-- edge to the bevel's foot
			local lipW = spline:lipWidthAt((s0 + s1) * 0.5, side)
			if side < 0 then
				tile(`s{tag}{n}`, s0, s1, -(half + lipW), -half, Enum.Material.Pebble, true)
			else
				tile(`s{tag}{n}`, s0, s1, half, half + lipW, Enum.Material.Pebble, true)
			end
			-- the grass, a band [half + w0, half + w1] out on this side over [a, b], from the
			-- bevel's foot out
			local function grass(key: string, a: number, b: number, w0: number, w1: number)
				w0 = math.max(w0, lipW)
				if w1 - w0 < 0.05 then
					return
				end
				-- gravel in a tight cliff stretch (T-181), for the footsteps
				local mat = if spline:gravelAt((a + b) * 0.5, side) then Enum.Material.Pebble else Enum.Material.Grass
				if side < 0 then
					tile(key, a, b, -(half + w1), -(half + w0), mat)
				else
					tile(key, a, b, half + w0, half + w1, mat)
				end
			end
			for g, span in edgeSpans(s0, s1, side) do
				local a, b, kind = span[1], span[2], span[3]
				local wa, wb = spline:runoffAt(a, side), spline:runoffAt(b, side)
				local key = `{tag}{n}:{g}`
				if kind == Spline.CLIFF then
					-- ground to the lip and not a hair past it: whole tiles as far as the
					-- narrowest the grass gets here, then the rest in strips
					local wMin = math.min(wa, wb, spline:runoffAt((a + b) * 0.5, side))
					local full = math.floor(wMin / PIECE)
					for j = 1, full do
						grass(`g{key}:{j}`, a, b, (j - 1) * PIECE, j * PIECE)
					end
					local strips = math.clamp(math.ceil(math.abs(wb - wa) / LIP_STEP), 1, 8)
					for i = 1, strips do
						local sa = a + (b - a) * (i - 1) / strips
						local sb = a + (b - a) * i / strips
						local w = math.min(spline:runoffAt(sa, side), spline:runoffAt(sb, side))
						grass(`l{key}:{i}`, sa, sb, full * PIECE, w)
					end
				else
					-- ground out under the wall, then the wall on the grass's outer edge
					local w = math.max(wa, wb) + 1
					local pieces = math.ceil(w / PIECE)
					for j = 1, pieces do
						grass(`g{key}:{j}`, a, b, (j - 1) * PIECE, math.min(j * PIECE, w))
					end
					if kind == Spline.ROCK then
						wall(`w{key}`, "wall", a, b, side, half + wa, half + wb, ROCK_THICK, ROCK_WALL, Enum.Material.Rock)
					else
						wall(`w{key}`, "wall", a, b, side, half + wa, half + wb, T.HedgeThickness, HEDGE_WALL, Enum.Material.LeafyGrass)
					end
				end
			end
			-- the K-rails standing on the tarmac's edge in this row
			local runs = spline:kRailsIn(s0, s1, side)
			for i = 1, #runs, 2 do
				local a, b = math.max(s0, runs[i]), math.min(s1, runs[i + 1])
				wall(`k{tag}{n}:{i}`, "rail", a, b, side, half, half, T.KRailThickness, T.KRailHeight, Enum.Material.Metal)
			end
		end
	end

	-- the closing barrier: the slab the car is stopped by (`Drift/SplineWorld`), 1 stud deep
	-- with its front face at `closingS`, across the tarmac, both runoffs and the edges
	if closingS and closingS >= 0 and closingS <= spline.length and math.abs(closingS - sc) <= ROW * (ROWS_EACH_WAY + 1) then
		local x, y, z = spline:surfaceXYZ(closingS, 0)
		local wider = math.max(spline:runoffAt(closingS, -1), spline:runoffAt(closingS, 1)) + T.EdgeDepth
		local wide = R.Width + 2 * wider
		local bankRise = wide * 0.5 * math.abs(math.tan(spline:bankAt(closingS)))
		local height = CLOSING_WALL + 2 * bankRise
		want.closing = {
			size = Vector3.new(wide, height + SINK, 1),
			cf = CFrame.new(x, y + (CLOSING_WALL - SINK) * 0.5, z) * CFrame.Angles(0, spline:yawAt(closingS), 0) * CFrame.new(0, 0, 0.5),
			material = Enum.Material.SmoothPlastic,
			kind = "closing",
		}
	end
	return want
end

-- Make the patch what `want` says: keep every tile already right, reuse the rest for the
-- new ones, and drop what is left over.
local function apply(want: { [string]: Spec })
	local spare: { BasePart } = {}
	for key, p in parts do
		if not want[key] then
			table.insert(spare, p)
			parts[key] = nil
		end
	end
	local f = folder
	if not f or not f.Parent then
		local made = Instance.new("Folder")
		made.Name = "RoadGround"
		made.Parent = workspace
		folder = made
		f = made
	end
	local counts: { [string]: number } = { ground = 0, wall = 0, rail = 0, closing = 0 }
	for key, spec in want do
		local p = parts[key]
		if not p then
			p = table.remove(spare) or newPart()
			parts[key] = p
		end
		local part = p :: BasePart
		if part.Size ~= spec.size then
			part.Size = spec.size
		end
		if part.CFrame ~= spec.cf then
			part.CFrame = spec.cf
		end
		if part.Material ~= spec.material then
			part.Material = spec.material
		end
		if part.Parent ~= f then
			part.Parent = f
		end
		counts[spec.kind] += 1
	end
	for _, p in spare do
		p:Destroy()
	end
	stats.ground, stats.walls, stats.rails, stats.closing = counts.ground, counts.wall, counts.rail, counts.closing
end

local function frame()
	local spline, closingS = SplineRoadController:Road()
	local root = if spline then walkingRoot() else nil
	stats.out = root ~= nil
	if not spline or not root then
		hint = nil
		stats.located = false
		clear()
		return
	end
	local R = Config.Road
	local reach = R.Width * 0.5 + Config.Spline.Terrain.RunoffMax + ACROSS
	local pos = root.Position
	local s, d = locate(spline, pos.X, pos.Z, reach)
	if not s or not d then
		stats.located = false
		clear()
		return
	end
	stats.located, stats.s, stats.d = true, s, d
	local n = math.floor(s / ROW)
	local band = math.floor(d / PIECE)
	-- more road only matters while the patch would reach past the end of it
	local laid = math.min(math.floor(spline.length / ROW), n + ROWS_EACH_WAY + 1)
	local closingKey = if closingS and math.abs(closingS - s) <= ROW * (ROWS_EACH_WAY + 1) then closingS else -1
	local key = `{n}/{band}/{laid}/{closingKey}`
	if key == lastKey then
		return
	end
	lastKey = key
	stats.rebuilds += 1
	local t0 = os.clock()
	apply(plan(spline, s, d, closingS))
	local ms = (os.clock() - t0) * 1000
	stats.rebuildMs = ms
	stats.worstMs = math.max(stats.worstMs, ms)
end

function RoadGroundController:Init() end

function RoadGroundController:Start()
	-- Back in the car, or handed a car: the ground goes at once, before anything drives.
	Net.event("CarEnter").OnClientEvent:Connect(function(ok)
		if ok == true then
			clear()
		end
	end)
	Net.event("CarSpawn").OnClientEvent:Connect(function()
		clear()
	end)
	-- Before the drift step (`Input + 1`), so a car that starts driving this frame has
	-- already lost the patch; and before physics, so ground under a newly freed avatar is
	-- there for its first fall.
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.First.Value, frame)
end

-- ---------------------------------------------------------------- debug

-- What the patch is now, and where our avatar stands on the road: `aboveSurface` is the
-- bottom of its feet (root minus `Driver.rootAboveFeet`) above the curve's own ground.
function RoadGroundController:DebugState()
	local spline = SplineRoadController:Road()
	local root = Driver.rootOf(player.Character)
	local surface, kind, aboveSurface = nil, nil, nil
	if spline and root and stats.located then
		surface = spline:terrainY(stats.s, stats.d)
		local k = spline:groundKind(stats.s, stats.d)
		kind = if k == Spline.TARMAC then "tarmac" elseif k == Spline.GRASS then "grass" elseif k == Spline.GRAVEL then "gravel" else "none"
		aboveSurface = root.Position.Y - Driver.rootAboveFeet(player.Character) - surface
	end
	local count = 0
	for _ in parts do
		count += 1
	end
	return {
		out = stats.out,
		located = stats.located,
		s = stats.s,
		d = stats.d,
		kind = kind,
		surface = surface,
		aboveSurface = aboveSurface,
		parts = count,
		ground = stats.ground,
		walls = stats.walls,
		rails = stats.rails,
		closing = stats.closing,
		rebuilds = stats.rebuilds,
		rebuildMs = stats.rebuildMs,
		worstMs = stats.worstMs,
		clears = stats.clears,
		created = stats.created,
		edgeL = spline and stats.located and spline:edgeAt(stats.s, -1) or nil,
		edgeR = spline and stats.located and spline:edgeAt(stats.s, 1) or nil,
		runoffL = spline and stats.located and spline:runoffAt(stats.s, -1) or nil,
		runoffR = spline and stats.located and spline:runoffAt(stats.s, 1) or nil,
	}
end

-- A point on the road's ground for a test to walk to, `d` studs right of the centre line at
-- `s`, with what is at that `s` either side: `{ point, edgeL, edgeR, runoffL, runoffR,
-- kRailL, kRailR }` (edges 1 rock, 2 hedge, 3 cliff). Nil with no road.
function RoadGroundController:DebugPoint(s: number, d: number)
	local spline = SplineRoadController:Road()
	if not spline then
		return nil
	end
	local x, y, z = spline:terrainXYZ(s, d)
	return {
		point = Vector3.new(x, y, z),
		length = spline.length,
		edgeL = spline:edgeAt(s, -1),
		edgeR = spline:edgeAt(s, 1),
		runoffL = spline:runoffAt(s, -1),
		runoffR = spline:runoffAt(s, 1),
		kRailL = spline:kRailAt(s, -1) ~= nil,
		kRailR = spline:kRailAt(s, 1) ~= nil,
	}
end

return RoadGroundController
