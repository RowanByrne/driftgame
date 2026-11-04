--!nonstrict
-- RoadService: the endless road, built by the server and owned by it
-- (docs/game/features/track-generation.md).
--
-- NOT `TrackService`. That one adopts the hand-placed kart circuit that lives only in
-- `DR-Main` and that git never sees; this builds the game's THIRD world, from numbers, at
-- `Config.Road.Offset`, far from both the others. Nothing here touches either of them.
--
-- OFF BY DEFAULT. This service builds nothing at `Init` and nothing at `Start`: a run
-- begins on an explicit `Generate(seed)`, which is what the start button becomes in step
-- 3. `Config.Drift.StartWorld` is untouched, so every place still spawns a car where it
-- always did.
--
-- What it actually owns:
--   * the parts -- one folder per piece under `Workspace.Road`, built by `Road/Builder`
--   * the window -- `AheadPieces` built in front of the car, `BehindPieces` kept behind it
--   * the closing barrier, `BarrierBehind` pieces back, moving up with the car
--   * progress -- which piece each car is on, how far along, and whether that is forward
--     on road it has not used. The server owns this for the same reason it owns the seed:
--     a client that reports its own progress reports its own score later.
--
-- The sequence itself is `Shared/Road/Generator`, which is pure and has no idea any of
-- this exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Builder = require(ReplicatedStorage.Shared.Road.Builder)
local Generator = require(ReplicatedStorage.Shared.Road.Generator)
local Pieces = require(ReplicatedStorage.Shared.Road.Pieces)

local RoadService = {}
-- Below PlaygroundService (100) and TrackService: this one builds nothing until asked,
-- so nothing depends on it having run first.
RoadService.Priority = 50

RoadService.Root = nil :: Folder?
RoadService.Running = false

local ROOT_NAME = "Road"

local generator = nil :: any
local built: { [number]: any } = {} -- n -> Builder.Built
local closing: Part? = nil
local leader = Vector3.zero -- where the window is centred: the furthest car down the road
local leaderN = 1
local windowCentre = 1 -- the furthest the window has been asked to reach; it never goes back
local ticking = false
local lastProgress = nil :: any

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function root(): Folder
	local existing = RoadService.Root
	if existing and existing.Parent then
		return existing
	end
	local old = workspace:FindFirstChild(ROOT_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = ROOT_NAME
	folder.Parent = workspace
	RoadService.Root = folder
	return folder
end

local function buildPiece(piece: any)
	if built[piece.n] then
		return
	end
	built[piece.n] = Builder.build(piece, root())
end

local function destroyPiece(n: number)
	local entry = built[n]
	if not entry then
		return
	end
	entry.folder:Destroy()
	built[n] = nil
end

-- Build ahead, destroy behind. Everything the window does is here, in one place, so there
-- is exactly one answer to "how many pieces exist".
--
-- THE WINDOW ONLY EVER MOVES FORWARD, and that is not a convenience: a piece behind the
-- car has been DESTROYED, and nothing can un-destroy it. A player driving back down the
-- road would otherwise drag the window backwards and ask for pieces that no longer exist.
-- So the window follows the furthest the run has reached, which is also why the closing
-- barrier behind it cannot be pushed back by turning round.
local function window(centre: number)
	local C = Config.Road
	windowCentre = math.max(windowCentre, centre)
	centre = windowCentre
	for _, piece in generator:extendTo(centre + C.AheadPieces) do
		buildPiece(piece)
	end
	-- A piece the generator already had but that has no parts (a Generate that was
	-- interrupted, or a rebuild) is caught here rather than left as a hole.
	for n = math.max(generator.first, centre - C.BehindPieces), generator.last do
		local piece = generator:piece(n)
		if piece then
			buildPiece(piece)
		end
	end
	for _, n in generator:trimBefore(centre - C.BehindPieces) do
		destroyPiece(n)
	end
	-- Anything parented that the generator has forgotten goes too: the folder is the
	-- window, and nothing is allowed to leak into it.
	for n in built do
		if n < generator.first then
			destroyPiece(n)
		end
	end
end

-- It sits behind the WINDOW's centre, not behind the car, for the same reason the window
-- only moves forward: turning round must not open the way back up.
local function moveClosingBarrier()
	local C = Config.Road
	if not closing or not closing.Parent then
		return
	end
	local n = windowCentre - C.BarrierBehind
	local piece = generator:piece(n)
	if not piece then
		-- Early in a run there is nothing that far back; park it at the very start, which
		-- is still behind the car and still closes the way out.
		piece = generator:piece(generator.first)
	end
	if piece then
		Builder.moveClosingBarrier(closing, piece, 0)
	end
end

--------------------------------------------------------------------------------
-- Who the window follows
--------------------------------------------------------------------------------

-- CarService, if this place has one loaded. Looked up rather than required at the top, as
-- PlaygroundService does, so the two services need no load order between them.
local function carService(): any?
	local services = script.Parent
	local module = services and services:FindFirstChild("CarService")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, cars = pcall(require, module)
	if ok and type(cars) == "table" then
		return cars
	end
	return nil
end

-- The furthest car down the road. One world, one window: with two players the road is
-- kept around whoever is ahead, and the closing barrier follows the same car. What a run
-- with more than one player in it actually means is not decided yet (`PITCH.md`).
--
-- WHERE A CAR IS, ON THE SERVER, IS NOT ITS PIVOT. The client simulates its own car and
-- writes the CFrames locally; those writes never replicate, so the server's copy of the
-- model sits where the server last PUT it -- its spawn -- for the whole run. The honest
-- answer is `CarService:BelievedPosition`, the last `CarState` packet the server accepted
-- (`CONTRACTS.md`). The pivot is the fallback, and it is the right one in a test with no
-- player in it.
local function readCars(): (Vector3?, number?)
	local folder = workspace:FindFirstChild("Cars")
	if not folder then
		return nil, nil
	end
	local cars = carService()
	local bestPos, bestN = nil, nil
	for _, car in folder:GetChildren() do
		if not car:IsA("Model") then
			continue
		end
		local at: Vector3? = nil
		local userId = tonumber(car:GetAttribute("UserId"))
		if cars and userId and type(cars.BelievedPosition) == "function" then
			local ok, believed = pcall(cars.BelievedPosition, cars, userId)
			if ok and typeof(believed) == "Vector3" then
				at = believed
			end
		end
		if not at then
			local ok, pivot = pcall(function()
				return car:GetPivot().Position
			end)
			at = if ok then pivot else nil
		end
		if not at then
			continue
		end
		local n = generator:locate(at)
		if n and (bestN == nil or n > bestN) then
			bestPos, bestN = at, n
		end
	end
	return bestPos, bestN
end

local function tick()
	if not RoadService.Running or not generator then
		return
	end
	local pos, n = readCars()
	if pos and n then
		leader, leaderN = pos, n
		lastProgress = generator:progress(pos)
	end
	window(leaderN)
	moveClosingBarrier()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RoadService:Init()
	-- Deliberately nothing. The road is off until something asks for it.
end

function RoadService:Start()
	task.spawn(function()
		ticking = true
		while ticking do
			task.wait(Config.Road.TickSeconds)
			local ok, err = pcall(tick)
			if not ok then
				warn(`[Road] tick failed: {err}`)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Contract (docs/game/CONTRACTS.md)
--------------------------------------------------------------------------------

-- Start a run. The seed is the server's: the same seed is the same road, which is what
-- makes a run reproducible, a ghost possible and a score checkable later.
function RoadService:Generate(seed: number?): CFrame
	self:Stop()
	generator = Generator.new(seed or (DateTime.now().UnixTimestampMillis % 2 ^ 31))
	RoadService.Running = true
	leaderN = 1
	windowCentre = 1
	lastProgress = nil

	local folder = root()
	closing = Builder.closingBarrier(folder)
	window(1)
	moveClosingBarrier()
	local spawn = self:SpawnCFrame()
	leader = spawn.Position
	return spawn
end

-- Tear the road down. Leaves no folder and no parts behind.
function RoadService:Stop()
	RoadService.Running = false
	for n in built do
		destroyPiece(n)
	end
	table.clear(built)
	if closing then
		closing:Destroy()
		closing = nil
	end
	local folder = RoadService.Root
	if folder then
		folder:Destroy()
	end
	RoadService.Root = nil
	generator = nil
	lastProgress = nil
	leaderN = 1
	windowCentre = 1
end

function RoadService:HasRoad(): boolean
	return RoadService.Running and generator ~= nil
end

-- Where a car starts: on the centre line of piece 1, a little way in, facing the way the
-- road goes. Who calls this, and when, is step 3's: nothing does yet.
function RoadService:SpawnCFrame(): CFrame
	if not generator then
		error("RoadService: no road. Call Generate(seed) first.", 2)
	end
	local piece = generator:piece(1)
	if not piece then
		error("RoadService: the road has no first piece", 2)
	end
	local t = math.clamp(20 / math.max(piece.length, 1), 0, 0.5)
	return Pieces.poseAt(piece, t, Config.Road.SurfaceY + Config.Drift.RideHeight)
end

-- Which piece a world position is on, and how far along it. `nil` off the road entirely.
function RoadService:PieceAt(position: Vector3)
	if not generator then
		return nil
	end
	local n, t, lateral = generator:locate(position)
	if not n then
		return nil
	end
	local piece = generator:piece(n)
	return {
		n = n,
		t = t,
		lateral = lateral,
		kind = piece.kind,
		variant = piece.id,
		onRoad = lateral <= Config.Road.Width * 0.5,
	}
end

-- Where a position is in the RUN: the two flags only the road can answer.
function RoadService:Progress(position: Vector3)
	if not generator then
		return nil
	end
	return generator:progress(position)
end

function RoadService:Bounds(): { min: Vector3, max: Vector3 }?
	if not generator then
		return nil
	end
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for n = generator.first, generator.last do
		local piece = generator:piece(n)
		if piece then
			minX = math.min(minX, piece.minX)
			maxX = math.max(maxX, piece.maxX)
			minZ = math.min(minZ, piece.minZ)
			maxZ = math.max(maxZ, piece.maxZ)
		end
	end
	if minX == math.huge then
		return nil
	end
	local C = Config.Road
	return {
		min = Vector3.new(minX, C.SurfaceY - C.Thickness, minZ),
		max = Vector3.new(maxX, C.SurfaceY + C.BarrierHeight, maxZ),
	}
end

function RoadService:DebugState()
	if not generator then
		return { running = false, built = 0, pieces = 0 }
	end
	local report = generator:report()
	local parts = 0
	local pieces = 0
	for _, entry in built do
		parts += entry.parts
		pieces += 1
	end
	report.running = RoadService.Running
	report.builtPieces = pieces
	report.parts = parts
	report.leaderN = leaderN
	report.leader = leader
	report.progress = lastProgress
	report.closingAt = if closing then closing.Position else nil
	report.offset = Config.Road.Offset
	report.width = Config.Road.Width
	return report
end

-- Studio only: step the window on as if a car were at `position`, with no car and no
-- playtest. This is how the tests drive five hundred pieces of road in a few seconds.
function RoadService:DebugAdvance(position: Vector3)
	assert(RunService:IsStudio(), "DebugAdvance is Studio only")
	if not generator then
		return nil
	end
	local progress = generator:progress(position)
	if progress then
		leader, leaderN = position, progress.n
		lastProgress = progress
	end
	window(leaderN)
	moveClosingBarrier()
	return progress
end

-- Studio only: jump the window straight to piece `n`, without a position. Used by the
-- long-run tests, which care about the sequence rather than about driving it.
function RoadService:DebugAdvanceTo(n: number)
	assert(RunService:IsStudio(), "DebugAdvanceTo is Studio only")
	if not generator then
		return nil
	end
	leaderN = math.max(1, n)
	window(leaderN)
	moveClosingBarrier()
	return generator:report()
end

-- Studio only: the live generator itself, so the tests can drive the pure half directly
-- rather than through a keyhole. Nothing in the game reads this.
function RoadService:DebugGenerator()
	assert(RunService:IsStudio(), "DebugGenerator is Studio only")
	return generator
end

-- Studio only: every piece currently in the window, as plain numbers.
function RoadService:DebugPieces()
	assert(RunService:IsStudio(), "DebugPieces is Studio only")
	if not generator then
		return {}
	end
	local out = {}
	for n = generator.first, generator.last do
		local piece = generator:piece(n)
		if piece then
			table.insert(out, {
				n = n,
				id = piece.id,
				kind = piece.kind,
				dir = piece.dir,
				length = piece.length,
				segments = #piece.quads,
				start = piece.start,
				finish = piece.finish,
				parts = if built[n] then built[n].parts else 0,
			})
		end
	end
	return out
end

return RoadService
