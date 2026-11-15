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
local Boundary = require(ReplicatedStorage.Shared.Road.SplineBoundary)
local SplineParts = require(ReplicatedStorage.Shared.Road.SplineParts)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local Driver = require(DriftFolder:WaitForChild("Driver")) :: any
local SplineWorld = require(DriftFolder:WaitForChild("SplineWorld"))

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
local ownedSpline:any=nil
local walkingWorld:any=nil
local walkingActor:BasePart?=nil
local groundHit:any=nil
local fieldFloor:Model?=nil
local fieldEpoch=0
local fieldRequest:any=nil
local fieldBuilding=false
local fieldSliceMs:number?=nil
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
	fieldParts=0,
	fieldBuilds=0,
	fieldMs=0,
	fieldWorstMs=0,
	fieldFailure="",
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

local function resetWalking()
	if walkingWorld then walkingWorld.destroy() end
	walkingWorld=nil;walkingActor=nil;groundHit=nil
end

local function clear()
	fieldEpoch+=1;fieldRequest=nil
	if fieldFloor then fieldFloor:Destroy();fieldFloor=nil end
	stats.fieldParts=0
	lastKey=""
	if next(parts)==nil then return end
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

local function requestField(spline:any,pos:Vector3,actor:BasePart)
	if not spline.infields then return end
	local W=Config.Spline.Biomes.Infield.Walking
	local first=spline.firstSample*spline.step
	if fieldFloor and (not fieldFloor:IsDescendantOf(workspace) or fieldFloor:GetAttribute("InfieldFirst")~=first) then
		fieldFloor:Destroy();fieldFloor=nil;stats.fieldParts=0
	end
	-- The first exit into a field needs real ground before a sliced build can
	-- finish. This small exact neighbourhood is bounded and cannot yield.
	local covered=fieldFloor and math.abs(pos.X-(fieldFloor:GetAttribute("InfieldX") :: number))<=(fieldFloor:GetAttribute("InfieldRadius") :: number)-2
		and math.abs(pos.Z-(fieldFloor:GetAttribute("InfieldZ") :: number))<=(fieldFloor:GetAttribute("InfieldRadius") :: number)-2
	if not covered then
		local model,info=SplineParts.buildInfield(spline,pos.X,pos.Z,W.WarmRadius,folder :: Folder,
			{supportedOnly=true,collidable=true,queryable=true,first=first,noYield=true,maxTriangles=W.WarmTriangles})
		if model then local old=fieldFloor;fieldFloor=model;if old then old:Destroy() end;stats.fieldParts=info.parts
		elseif info~="empty" then stats.fieldFailure=tostring(info) end
	end
	fieldRequest={spline=spline,position=pos,actor=actor,epoch=fieldEpoch,
		first=spline.firstSample*spline.step,revision=spline.infieldRevision,parent=folder}
	if fieldBuilding then return end
	fieldBuilding=true
	task.spawn(function()
		while fieldRequest do
			local request=fieldRequest;fieldRequest=nil
			local staging=Instance.new("Folder")
			local function cancelled()
				local currentRoad=SplineRoadController:Road()
				return request.epoch~=fieldEpoch or request.spline~=ownedSpline or request.spline~=currentRoad or request.actor~=walkingActor
					or request.parent~=folder or not request.parent:IsDescendantOf(workspace)
					or walkingRoot()~=request.actor or request.first~=request.spline.firstSample*request.spline.step
					or request.revision~=request.spline.infieldRevision
			end
			local ok,model,info=pcall(SplineParts.buildInfield,request.spline,request.position.X,request.position.Z,
				W.Radius,staging,{supportedOnly=true,collidable=true,queryable=true,
					first=request.first,cancelled=cancelled,sliceMs=fieldSliceMs})
			if not cancelled() then
				if ok and model then
					local current=request.actor.Position
					if math.abs(current.X-request.position.X)<=W.Radius-2 and math.abs(current.Z-request.position.Z)<=W.Radius-2 then
						model.Parent=request.parent
						local old=fieldFloor;fieldFloor=model
						if old then old:Destroy() end
						stats.fieldParts=info.parts;stats.fieldBuilds+=1;stats.fieldMs=info.ms
						stats.fieldWorstMs=math.max(stats.fieldWorstMs,info.sliceMs);stats.fieldFailure=""
					end
				elseif ok and info=="empty" then
					if fieldFloor then fieldFloor:Destroy();fieldFloor=nil end
					stats.fieldParts=0;stats.fieldFailure=""
				else stats.fieldFailure=tostring(if ok then info else model) end
			end
			staging:Destroy()
		end
		fieldBuilding=false
	end)
end

local function dist(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	local x, y, z = bx - ax, by - ay, bz - az
	return math.sqrt(x * x + y * y + z * z)
end

-- Everything the patch should hold round (sc, dc), by key. A key names the same tile every
-- time it is asked for, and the same key always gives the same tile.
local function plan(spline: any, sc: number, dc: number, closingS: number?, worldPosition:Vector3?): { [string]: Spec }
	local R = Config.Road
	local T = Config.Spline.Terrain
	local half = R.Width * 0.5
	local want: { [string]: Spec } = {}
	local lo, hi = dc - ACROSS, dc + ACROSS

	-- a ground tile over [s0, s1] x [d0, d1], its top on the surface at its middle. A
	-- `slope` tile lies along the chord from its inner edge to its outer one instead of on
	-- the ground's normal: the road's step down to the grass (T-184), a ramp an avatar walks
	-- up rather than a ledge it has to jump
	local function tile(key: string, s0: number, s1: number, d0: number, d1: number, material: Enum.Material, slope: boolean?, depth: number?)
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
		-- Refine a fixed tile only where a bank/turn needs it. The avatar never
		-- changes the lattice, and no broad tangent box bridges a curved bank.
		if spline:hasBiomeGround() and not slope and (depth or 0)<5 then
			local alongError,acrossError=0,0
			for _,sa in {s0,s1} do
				for _,da in {d0,d1} do
					local px,py,pz=spline:terrainXYZ(sa,da)
					local error=math.abs(py-(y-(n.X*(px-x)+n.Z*(pz-z))/n.Y))
					if error>0.08 then
						alongError=math.max(alongError,math.abs(s1-s0))
						acrossError=math.max(acrossError,math.abs(d1-d0))
					end
				end
			end
			if math.max(alongError,acrossError)>0 then
				if acrossError>alongError then
					tile(key.."a",s0,s1,d0,dm,material,slope,(depth or 0)+1)
					tile(key.."b",s0,s1,dm,d1,material,slope,(depth or 0)+1)
				else
					tile(key.."a",s0,sm,d0,d1,material,slope,(depth or 0)+1)
					tile(key.."b",sm,s1,d0,d1,material,slope,(depth or 0)+1)
				end
				return
			end
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
		local ax, _, az = spline:terrainXYZ(a, side * innerA)
		local bx, _, bz = spline:terrainXYZ(b, side * innerB)
		local pa = Vector3.new(ax, spline:terrainY(a, side * innerA), az)
		local pb = Vector3.new(bx, spline:terrainY(b, side * innerB), bz)
		if spline:hasBiomeGround() and b-a>.125 then
			local sm=(a+b)*.5
			local innerM=if kind=="wall" then half+spline:runoffAt(sm,side) else (innerA+innerB)*.5
			local pm=Vector3.new(spline:terrainXYZ(sm,side*innerM))
			if (pm-(pa+pb)*.5).Magnitude>.05 then
				wall(key.."a",kind,a,sm,side,innerA,innerM,thick,height,material)
				wall(key.."b",kind,sm,b,side,innerM,innerB,thick,height,material)
				return
			end
		end
		local chord = pb - pa
		local len = chord.Magnitude
		if len < 1e-3 then
			return
		end
		local outward=Vector3.new(-chord.Z,0,chord.X).Unit
		local yaw=spline:yawAt((a+b)*.5)
		if outward:Dot(Vector3.new(side*math.cos(yaw),0,-side*math.sin(yaw)))<0 then outward=-outward end
		-- Thickness is normal to the taper's chord, not to the asphalt. Offset
		-- along that same normal so the inner face cannot protrude onto grass.
		local mid = (pa + pb) * 0.5 + outward*(thick*.5) + Vector3.yAxis * ((height - SINK) * 0.5)
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
		if spline:hasBiomeGround() then
			local out={}
			local points=Boundary.points(spline,s0,s1)
			for i=1,#points-1 do table.insert(out,{points[i],points[i+1],spline:edgeAt((points[i]+points[i+1])*.5,side)}) end
			return out
		end
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
		if s0 < spline.firstSample*spline.step or s1 > spline.length then
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
				if kind == Spline.CLIFF or spline:hasBiomeGround() then
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
					if kind~=Spline.CLIFF then
						local height=spline:boundaryHeight((a+b)*.5,side)
						if height>0 then wall(`w{key}`,"wall",a,b,side,half+wa,half+wb,
							if spline:infieldOpening((a+b)*.5,side)>0 then 3 else ROCK_THICK,height,Enum.Material.Rock) end
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
	if closingS and spline.infields then
		local position=worldPosition or Vector3.new(spline:terrainXYZ(sc,dc))
		local reach=ACROSS+ROW*(ROWS_EACH_WAY+1)
		for i,panel in spline:closingPanels(closingS) do
			local a,b=panel.a,panel.b
			if math.max(a[1],b[1])<position.X-reach or math.min(a[1],b[1])>position.X+reach
				or math.max(a[3],b[3])<position.Z-reach or math.min(a[3],b[3])>position.Z+reach then continue end
			local cf,size=Boundary.closingSpec(panel)
			want[`closing:{i}`]={cf=cf,size=size,material=Enum.Material.SmoothPlastic,kind="closing"}
		end
	elseif closingS and closingS >= 0 and closingS <= spline.length and math.abs(closingS - sc) <= ROW * (ROWS_EACH_WAY + 1) then
		local x, y, z = spline:surfaceXYZ(closingS, 0)
		local wider = math.max(spline:runoffAt(closingS, -1), spline:runoffAt(closingS, 1)) + T.EdgeDepth
		local wide = R.Width + 2 * wider
		local bankRise = wide * 0.5 * math.abs(math.tan(spline:bankAt(closingS)))
		local bottom=y-SINK-bankRise
		local top=y+CLOSING_WALL+bankRise
		if spline:hasBiomeGround() then
			for _,side in {-1,1} do
				local edge=half+spline:runoffAt(closingS,side)
				for t=0,1,.25 do
					local ground=spline:terrainY(closingS,side*edge*t)
					bottom,top=math.min(bottom,ground-SINK),math.max(top,ground+CLOSING_WALL)
				end
			end
		end
		want.closing = {
			size = Vector3.new(wide, top-bottom, 1),
			cf = CFrame.new(x, (bottom+top)*.5, z) * CFrame.Angles(0, spline:yawAt(closingS), 0) * CFrame.new(0, 0, 0.5),
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
		part:SetAttribute("GroundKind",spec.kind)
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
	if spline~=ownedSpline then ownedSpline=spline;resetWalking();clear() end
	local root = if spline then walkingRoot() else nil
	stats.out = root ~= nil
	if not spline or not root then
		resetWalking()
		stats.located = false
		clear()
		return
	end
	local pos = root.Position
	if walkingActor~=root then
		resetWalking();clear();walkingActor=root;walkingWorld=SplineWorld.new(spline)
		local carSpline,carHint,contact=DriftController:SplineHint()
		if carSpline==spline then walkingWorld.hint=carHint;walkingWorld.restoreContact(contact) end
	end
	walkingWorld.setClosing(closingS)
	local owner,_,physical,lateral=walkingWorld.locate(pos)
	local s,d=physical or owner,lateral or 0
	if not s then
		stats.located = false
		clear()
		return
	end
	groundHit=walkingWorld.probe(pos)
	DriftController:DrawWalkingSpline(spline,s)
	stats.located, stats.s, stats.d = true, s, d
	local n = math.floor(s / ROW)
	local band = math.floor(d / PIECE)
	-- more road only matters while the patch would reach past the end of it
	local laid = math.min(math.floor(spline.length / ROW), n + ROWS_EACH_WAY + 1)
	local closingKey = if closingS and (spline.infields or math.abs(closingS-s)<=ROW*(ROWS_EACH_WAY+1)) then closingS else -1
	local fieldKey=if spline.infields then `/{spline.infieldRevision}/{spline.firstSample}/{math.floor(pos.X/PIECE)}/{math.floor(pos.Z/PIECE)}` else ""
	local key = `{n}/{band}/{laid}/{closingKey}{fieldKey}`
	if key == lastKey then
		return
	end
	lastKey = key
	stats.rebuilds += 1
	local t0 = os.clock()
	apply(plan(spline, s, d, closingS,pos))
	requestField(spline,pos,root)
	local ms = (os.clock() - t0) * 1000
	stats.rebuildMs = ms
	stats.worstMs = math.max(stats.worstMs, ms)
end

function RoadGroundController:Init() end

function RoadGroundController:Start()
	-- Back in the car, or handed a car: the ground goes at once, before anything drives.
	Net.event("CarEnter").OnClientEvent:Connect(function(ok)
		if ok == true then
			resetWalking()
			clear()
		end
	end)
	Net.event("CarSpawn").OnClientEvent:Connect(function()
		resetWalking()
		clear()
	end)
	Net.event("CarRespawn").OnClientEvent:Connect(function()
		resetWalking()
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
		surface = if groundHit then groundHit.y else spline:terrainY(stats.s,stats.d)
		local k = if walkingWorld and walkingWorld.contactState then walkingWorld.contactState.kind else spline:groundKind(stats.s,stats.d)
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
		fieldParts=stats.fieldParts,
		fieldBuilds=stats.fieldBuilds,
		fieldMs=stats.fieldMs,
		fieldWorstMs=stats.fieldWorstMs,
		fieldFailure=stats.fieldFailure,
		fieldBuilding=fieldBuilding,
		ownerS=walkingWorld and walkingWorld.hint,
		anchorS=walkingWorld and walkingWorld.contactState and walkingWorld.contactState.anchorS,
		travel=walkingWorld and walkingWorld.contactState and walkingWorld.contactState.travel,
		edgeL = spline and stats.located and spline:edgeAt(stats.s, -1) or nil,
		edgeR = spline and stats.located and spline:edgeAt(stats.s, 1) or nil,
		runoffL = spline and stats.located and spline:runoffAt(stats.s, -1) or nil,
		runoffR = spline and stats.located and spline:runoffAt(stats.s, 1) or nil,
	}
end

function RoadGroundController:DebugFieldBudget(sliceMs:number?)
	assert(RunService:IsStudio(),"DebugFieldBudget is Studio only")
	fieldSliceMs=if sliceMs then math.clamp(sliceMs,.001,Config.Spline.Mesh.SliceMs) else nil
	lastKey=""
	return fieldSliceMs
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
