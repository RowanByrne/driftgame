--!nonstrict
-- RoadService: the endless road, built by the server and owned by it
-- (docs/game/features/track-generation.md).
--
-- NOT `TrackService`. That one adopts the hand-placed kart circuit that lives only in
-- `DR-Main` and that git never sees; this builds the game's THIRD world, from numbers, at
-- `Config.Road.Offset`, far from both the others. Nothing here touches either of them.
--
-- OFF BY DEFAULT. This service builds nothing at `Init` and nothing at `Start`: a run
-- begins on an explicit `Generate(seed)`, and `Config.Drift.StartWorld` is untouched, so
-- every place still spawns a car where it always did. The ONLY thing in the game that
-- starts a road is a player pressing the start button (`Drift/RoadHud`, the `RoadRun`
-- remote, features/endless-run.md).
--
-- What it actually owns:
--   * the parts -- one folder per piece under `Workspace.Road`, built by `Road/Builder`
--   * the window -- `AheadPieces` built in front of the car, `BehindPieces` kept behind it
--   * the closing barrier, `BarrierBehind` pieces back, moving up with the car
--   * progress -- which piece each car is on, how far along, and whether that is forward
--     on road it has not used. The server owns this for the same reason it owns the seed:
--     a client that reports its own progress reports its own score later.
--   * THE RUN (T-044 step 3): who is on the road, which world each of them came from, and
--     what a fall puts them back on.
--
-- WHAT THE CLIENT MAY SAY, which is the whole of the trust boundary here: one of three
-- things -- "start", "end", or "which is it?". It may not name a seed, a spawn, a piece
-- or a progress, and nothing on the wire is read as any of those. The seed is picked
-- here, the spawn is computed here from the generator, and progress is measured here from
-- the position `CarService` has already agreed to. A client that reported its own progress
-- would be reporting its own score the day there is one.
--
-- NOTHING HERE MOVES A CAR. `CarService:Respawn(player, cf)` is still the only thing that
-- does, as it has been since T-026: this service decides WHERE and asks.
--
-- The sequence itself is `Shared/Road/Generator`, which is pure and has no idea any of
-- this exists.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Builder = require(ReplicatedStorage.Shared.Road.Builder)
local Generator = require(ReplicatedStorage.Shared.Road.Generator)
local Net = require(ReplicatedStorage.Shared.Net)
local Pieces = require(ReplicatedStorage.Shared.Road.Pieces)

local RoadService = {}
-- Below PlaygroundService (100) and TrackService: this one builds nothing until asked,
-- so nothing depends on it having run first.
RoadService.Priority = 50

RoadService.Root = nil :: Folder?
RoadService.Running = false

local ROOT_NAME = "Road"

-- The world's name, the one `CarService` knows it by. A third name beside "track" and
-- "playground" (`WORLD.md` "The three worlds"), and the only one of the three that is not
-- always there.
local WORLD_ROAD = "road"

-- THE TWO LIMITS ON THE START BUTTON, and neither is a new number. Nothing in
-- `Config.Road` may be touched by this task (lane 2 owns that file), so the run reuses the
-- two numbers that already bound the two other things a client may ask the server to do
-- to its car: how many asks a second it will take, and how long it must wait between two
-- that land. A press is a car being put somewhere, so a respawn's cooldown is the right
-- shape for it. They want their own `Config.Road.RunRateLimit` / `RunCooldown` the day
-- that file is free (features/endless-run.md "Open questions").
local RUN_RATE_LIMIT = "CarSwitchRateLimit" -- asks a second per UserId
local RUN_COOLDOWN = "RespawnCooldown" -- seconds between two presses that land

local generator = nil :: any
local built: { [number]: any } = {} -- n -> Builder.Built
local closing: Part? = nil
local leader = Vector3.zero -- where the window is centred: the furthest car down the road
local leaderN = 1
local windowCentre = 1 -- the furthest the window has been asked to reach; it never goes back
local ticking = false
local lastProgress = nil :: any

-- Who is on the road: userId -> { from, since, n, t, position, told }. `from` is the world
-- they pressed start in, so ending a run puts them back where they came from rather than
-- wherever `StartWorld` happens to say.
local runners: { [number]: any } = {}
local runnerCount = 0

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

-- THE GUARDRAIL SWITCH (T-067). The user asked to be able to drive off the side of the
-- road on purpose, so the walls can be stood down and put back.
--
-- IT TOUCHES THE WALLS AND NOTHING ELSE, and that distinction is the whole of the care
-- needed here. `Builder.build` hands back the slabs and the barriers in two separate
-- lists; the slabs are what the car's ground rays find (they are tagged `DriftSurface`)
-- and the barriers are deliberately untagged, which is what makes a barrier a wall rather
-- than a kerb (`Shared/Road/Builder`). Touching a slab's `CanQuery` would take the ROAD
-- out from under the car, not the fence.
--
-- `CanQuery` IS THE ONE THAT MATTERS, not `CanCollide`. The car is kinematic -- Roblox
-- physics never moves it -- and what stops it at a wall is a `Blockcast` through
-- `RaycastParams` (`Drift/World`), which obeys `CanQuery` and knows nothing about
-- `CanCollide`. Both are set anyway, so the player's character cannot walk through a wall
-- that is still there either.
local railsOn = true

local function applyRails(entry: any)
	for _, wall in entry.barriers do
		wall.CanCollide = railsOn
		wall.CanQuery = railsOn
		-- Not destroyed and not hidden: left visible enough to see where they were, so
		-- the user can tell "the rails are off" from "this piece has no rails".
		wall.Transparency = if railsOn then 0 else 0.85
	end
end

--------------------------------------------------------------------------------
-- The profile (T-085), off unless `Config.Road.Profile` says otherwise
--------------------------------------------------------------------------------
-- WHY IT IS HERE AT ALL. "The road hitches when a piece appears" names a symptom and
-- three suspects -- the generator's search, the few hundred `Instance.new`s a piece is,
-- and the single `.Parent` write that puts them in the Workspace -- and the only way to
-- tell them apart is to time them separately on the frame they happen. So each stage is
-- timed into a ring, with the clock reading it was taken at, and `DebugProfile()` hands
-- the ring back for a test or a bridge call to total up.
--
-- IT COSTS NOTHING WHEN IT IS OFF: one `== true` per piece built and per piece destroyed.
-- Nothing in here prints, ever.
local profile = {
	pieces = {} :: { any }, -- one per piece built
	destroys = {} :: { any }, -- one per piece destroyed
	windows = {} :: { any }, -- one per `window()` call that did any work
	builtEver = 0, -- pieces this VM has built, so a window call can say how many were its
}

local function profiling(): boolean
	return Config.Road.Profile == true
end

local function keep(list: { any }, entry: any)
	table.insert(list, entry)
	local limit = Config.Road.ProfileKeep or 400
	while #list > limit do
		table.remove(list, 1)
	end
end

local function buildPiece(piece: any)
	if built[piece.n] then
		return
	end
	local entry = Builder.build(piece, root())
	built[piece.n] = entry
	-- A piece built while the rails are down comes up with them down: the window builds
	-- new road under a driver who already asked for them off.
	if not railsOn then
		applyRails(entry)
	end
	profile.builtEver += 1
	if profiling() then
		keep(profile.pieces, {
			n = piece.n,
			kind = piece.kind,
			id = piece.id,
			parts = entry.parts,
			road = #entry.road,
			barriers = #entry.barriers,
			marks = #entry.marks,
			segments = #piece.quads,
			makeMs = entry.makeMs or 0,
			tagMs = entry.tagMs or 0,
			parentMs = entry.parentMs or 0,
			at = os.clock(),
		})
	end
end

local function destroyPiece(n: number)
	local entry = built[n]
	if not entry then
		return
	end
	local at = if profiling() then os.clock() else 0
	entry.folder:Destroy()
	built[n] = nil
	if profiling() then
		keep(profile.destroys, {
			n = n,
			parts = entry.parts,
			destroyMs = (os.clock() - at) * 1000,
			at = at,
		})
	end
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
	local on = profiling()
	local startedAt = if on then os.clock() else 0
	windowCentre = math.max(windowCentre, centre)
	centre = windowCentre
	local genAt = if on then os.clock() else 0
	local added = generator:extendTo(centre + C.AheadPieces)
	local genMs = if on then (os.clock() - genAt) * 1000 else 0
	local before = profile.builtEver
	for _, piece in added do
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
	if on then
		local wholeMs = (os.clock() - startedAt) * 1000
		if wholeMs > 0.05 or #added > 0 then
			keep(profile.windows, {
				centre = centre,
				genMs = genMs,
				wholeMs = wholeMs,
				addedPieces = #added,
				builtPieces = profile.builtEver - before,
				at = startedAt,
			})
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

-- The furthest car down the road. ONE WORLD, ONE WINDOW: with two players the road is
-- kept around whoever is ahead, and the closing barrier follows the same car. A second
-- player who presses start while a run is going JOINS THIS ROAD rather than getting one
-- of their own (features/endless-run.md "More than one player") -- which is the honest
-- answer for a test build, and is also the only one a single server-owned window can give.
--
-- WHERE A CAR IS, ON THE SERVER, IS NOT ITS PIVOT. The client simulates its own car and
-- writes the CFrames locally; those writes never replicate, so the server's copy of the
-- model sits where the server last PUT it -- its spawn -- for the whole run. The honest
-- answer is `CarService:BelievedPosition`, the last `CarState` packet the server accepted
-- (`CONTRACTS.md`). The pivot is the fallback, and it is the right one in a test with no
-- player in it.
--
-- ONLY RUNNERS MOVE THE WINDOW once anyone is in a run: a player sitting on the track is
-- 20 000 studs away and would locate nowhere anyway, but saying so is cheaper than relying
-- on it. With nobody in a run at all (a test driving the road with no player) every car is
-- read, exactly as before.
local function readCars(): (Vector3?, number?)
	local folder = workspace:FindFirstChild("Cars")
	if not folder then
		return nil, nil
	end
	local cars = carService()
	local onlyRunners = runnerCount > 0
	local bestPos, bestN = nil, nil
	for _, car in folder:GetChildren() do
		if not car:IsA("Model") then
			continue
		end
		local userId = tonumber(car:GetAttribute("UserId"))
		if onlyRunners and (not userId or not runners[userId]) then
			continue
		end
		local at: Vector3? = nil
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
		local n, t = generator:locate(at)
		local entry = userId and runners[userId]
		if entry then
			-- Each runner's own place in the run, measured here from the position the
			-- server has already agreed to. This is the number the HUD is told, and it is
			-- never one the client sent.
			entry.position = at
			if n then
				entry.n, entry.t = n, t
			end
		end
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
	-- Tell each runner where the SERVER says they are, and only when it has changed piece.
	-- A HUD that is pushed ten times a second to say the same number is ten packets a
	-- second saying nothing.
	for userId, entry in runners do
		if entry.n ~= entry.told then
			entry.told = entry.n
			local player = Players:GetPlayerByUserId(userId)
			if player then
				RoadService:_tell(player)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RoadService:Init()
	-- No road is built here, and none ever is until a player presses start. The ONE thing
	-- that has to exist before any controller asks for it is the remote.
	self.roadRun = Net.event("RoadRun")
	self.asks = 0
	self.asksRefused = 0
	self.started = 0
	self.ended = 0
	self.limits = {} -- userId -> { window, count, lastAt }
end

function RoadService:Start()
	self.roadRun.OnServerEvent:Connect(function(player, want)
		self:_onRun(player, want)
	end)

	-- A player who leaves mid-run leaves the run. Without this the road stays up for ever
	-- around a car that is not there, because the roster is what decides when it comes
	-- down.
	Players.PlayerRemoving:Connect(function(player)
		self:_leave(player.UserId)
	end)

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
-- The run
--------------------------------------------------------------------------------

-- The roster, with nothing instanced: who is on the road and where each of them came
-- from. A seed is not in here -- the generator holds it -- and nothing a client said is.
function RoadService:InRun(player: Player?): boolean
	return player ~= nil and runners[player.UserId] ~= nil
end

function RoadService:RunnerCount(): number
	return runnerCount
end

-- What the server will tell a client about the run. Every field is the server's own:
-- `n` and `furthestN` are measured from positions `CarService` agreed to, `players` is
-- the roster's size. The seed is deliberately NOT in it -- nothing on the client needs it
-- and a seed on the wire is a seed a client can be seen to have.
function RoadService:RunState(player: Player?)
	local entry = player and runners[player.UserId]
	return {
		running = self:HasRoad(),
		inRun = entry ~= nil,
		players = runnerCount,
		n = entry and entry.n or 0,
		furthestN = if generator then generator.furthestN else 0,
	}
end

-- Start a run for one player.
--
-- The seed is picked HERE, from the clock, and never comes off the wire. The world they
-- came from is read BEFORE they are moved, because once they are on the road
-- `CarService:WorldAt` will quite correctly say they are on the road.
function RoadService:StartRun(player: Player): CFrame?
	if runners[player.UserId] then
		return nil -- already in it; a second press is the END press, not a restart
	end

	local cars = carService()
	if not cars or type(cars.Place) ~= "function" then
		warn("[Road] a run was asked for with no CarService to move a car")
		return nil
	end

	-- Where they are now, so ending the run can put them back there. Measured, not
	-- remembered from a config: a player who drove from the track to the playground ends
	-- their run on the playground.
	local from = Config.Drift.StartWorld
	if type(cars.WorldAt) == "function" and type(cars.BelievedPosition) == "function" then
		local ok, believed = pcall(cars.BelievedPosition, cars, player.UserId)
		if ok and typeof(believed) == "Vector3" then
			local got, world = pcall(cars.WorldAt, cars, believed)
			if got and type(world) == "string" and world ~= WORLD_ROAD then
				from = world
			end
		end
	end

	local fresh = not self:HasRoad()
	if fresh then
		self:Generate()
	end

	local cf = self:JoinCFrame()
	if not cf then
		if fresh then
			self:Stop()
		end
		return nil
	end

	-- On the roster BEFORE the car moves: `CarService:Respawn` asks this service where a
	-- runner belongs, and a player who is not on the roster yet would be sent to the world
	-- they are standing in instead of onto the road.
	runners[player.UserId] = { from = from, since = os.clock(), n = 1, t = 0, told = nil }
	runnerCount += 1

	local ok, placed = pcall(cars.Place, cars, player, cf)
	if not ok or not placed then
		runners[player.UserId] = nil
		runnerCount -= 1
		if fresh then
			self:Stop()
		end
		return nil
	end
	self.started += 1
	return placed
end

-- End one player's run and put them back in the world they started it from.
--
-- ONE PLAYER ENDING A RUN CANNOT STRAND ANOTHER: the road comes down only when the roster
-- empties. While anyone is still on it the window, the barrier and every piece stay
-- exactly where they are, and the player who pressed end simply leaves.
function RoadService:EndRun(player: Player): CFrame?
	local entry = runners[player.UserId]
	if not entry then
		return nil
	end

	local cars = carService()
	local cf = nil
	if cars and type(cars.SpawnCFrameIn) == "function" then
		local ok, got = pcall(cars.SpawnCFrameIn, cars, entry.from)
		if ok and typeof(got) == "CFrame" then
			cf = got
		end
	end

	-- Off the roster first, for the same reason they went on it first: the respawn below
	-- asks this service where this player belongs, and the answer has to be "not here".
	runners[player.UserId] = nil
	runnerCount -= 1
	self.ended += 1

	if cf and cars and type(cars.Place) == "function" then
		pcall(cars.Place, cars, player, cf)
	end

	if runnerCount <= 0 then
		self:Stop()
	end
	return cf
end

-- A player who left the place, or whose car went away. No car to move, just the roster.
function RoadService:_leave(userId: number)
	if not runners[userId] then
		return
	end
	runners[userId] = nil
	runnerCount -= 1
	if runnerCount <= 0 then
		self:Stop()
	end
end

-- THE WIRE. One of three things, and nothing else is read off it:
--
--   nil   a QUESTION -- "am I in a run?" -- which the HUD asks when it starts up, so a
--         client that missed the answer sent with its last press is never out of step;
--   true  start;
--   false end.
--
-- There is no seed here, no position, no piece and no progress, and there is nowhere for
-- one to hide: anything that is not a boolean or nil is refused and counted. Rate-limited
-- by UserId so rejoining does not reset it, and held to one press every `RunCooldown`, the
-- same two guards `CarRespawn` and `CarSwitch` already have.
--
-- Every path answers, refusals included: the answer is what puts a HUD that guessed wrong
-- back in step with the server.
function RoadService:_onRun(player: Player, want: any)
	self.asks += 1
	local now = os.clock()
	local limit = self.limits[player.UserId]
	if not limit then
		limit = { window = now, count = 0, lastAt = -math.huge }
		self.limits[player.UserId] = limit
	end
	if now - limit.window >= 1 then
		limit.window = now
		limit.count = 0
	end
	limit.count += 1
	if limit.count > Config.Drift[RUN_RATE_LIMIT] then
		self.asksRefused += 1
		self:_tell(player)
		return
	end

	if want == nil then
		self:_tell(player) -- a question, answered, changing nothing
		return
	end
	if type(want) ~= "boolean" then
		self.asksRefused += 1
		self:_tell(player)
		return
	end
	if now - limit.lastAt < Config.Drift[RUN_COOLDOWN] then
		self.asksRefused += 1
		self:_tell(player)
		return
	end

	local acted
	if want then
		acted = self:StartRun(player) ~= nil
	else
		acted = self:EndRun(player) ~= nil
	end
	if acted then
		limit.lastAt = now
	else
		self.asksRefused += 1
	end
	self:_tell(player)
end

function RoadService:_tell(player: Player)
	if self.roadRun then
		self.roadRun:FireClient(player, self:RunState(player))
	end
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
--
-- IT EMPTIES THE ROSTER TOO, because a road that does not exist has nobody on it. A car
-- left over the void where the road was falls, asks for a respawn, is no longer a runner,
-- and so comes back in the nearest world that does exist -- which is a graceful landing
-- rather than a hole. In normal play this never happens: `EndRun` only reaches here once
-- the last runner has already left.
function RoadService:Stop()
	RoadService.Running = false
	table.clear(runners)
	runnerCount = 0
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

-- The guardrail switch, for the testing HUD (`Drift/TestHud`, T-067). The road's own
-- walls; the test hill's are `PlaygroundService`'s, and the one button asks both.
--
-- THE CLOSING BARRIER IS NOT A GUARDRAIL and is deliberately left alone: it is the wall
-- that stops a driver reversing into road that is about to be destroyed
-- (features/track-generation.md), not a fence along the edge, and standing it down would
-- be a way to fall out of a run rather than a way to leave the road sideways.
function RoadService:SetBarriers(on: boolean): boolean
	railsOn = on == true
	for _, entry in built do
		applyRails(entry)
	end
	return railsOn
end

function RoadService:BarriersOn(): boolean
	return railsOn
end

-- Studio only: what the switch actually did, part by part, so a test can say the SLABS
-- were not touched rather than only that the walls were.
function RoadService:DebugBarrierReport()
	assert(RunService:IsStudio(), "DebugBarrierReport is Studio only")
	local walls, wallsQueryable, wallsSolid = 0, 0, 0
	local slabs, slabsQueryable, slabsSolid, slabsTagged = 0, 0, 0, 0
	for _, entry in built do
		for _, wall in entry.barriers do
			walls += 1
			wallsQueryable += if wall.CanQuery then 1 else 0
			wallsSolid += if wall.CanCollide then 1 else 0
		end
		for _, slab in entry.road do
			slabs += 1
			slabsQueryable += if slab.CanQuery then 1 else 0
			slabsSolid += if slab.CanCollide then 1 else 0
			slabsTagged += if CollectionService:HasTag(slab, Config.Drift.SurfaceTag) then 1 else 0
		end
	end
	return {
		on = railsOn,
		walls = walls,
		wallsQueryable = wallsQueryable,
		wallsSolid = wallsSolid,
		slabs = slabs,
		slabsQueryable = slabsQueryable,
		slabsSolid = slabsSolid,
		slabsTagged = slabsTagged,
	}
end

-- Where a car starts: on the centre line of piece 1, a little way in, facing the way the
-- road goes. This is where the FIRST player of a run lands; a player joining a run already
-- under way lands on `JoinCFrame` instead, because piece 1 has long been destroyed.
function RoadService:SpawnCFrame(): CFrame
	if not generator then
		error("RoadService: no road. Call Generate(seed) first.", 2)
	end
	local piece = generator:piece(1)
	if not piece then
		error("RoadService: the road has no first piece", 2)
	end
	return RoadService:_poseOn(piece)
end

-- A pose on a piece's centre line, a little way in from its start socket, at ride height.
-- The same pose for piece 1 (a spawn), for the piece a joiner lands on, and for the piece
-- a fall puts a car back on -- the spec's `safeStart`.
function RoadService:_poseOn(piece: any): CFrame
	local t = math.clamp(20 / math.max(piece.length, 1), 0, 0.5)
	return Pieces.poseAt(piece, t, Config.Road.SurfaceY + Config.Drift.RideHeight)
end

-- WHERE A CAR THAT CAME OFF THE ROAD GOES BACK ON, and the one rule it obeys: forward, or
-- where it was -- never backward past the closing barrier.
--
--   * it is put on the piece it was last on, so a fall costs the piece it was in the
--     middle of and not the run. `N` cannot go backwards, because `furthestN` is the
--     generator's own high-water mark and nothing here writes it;
--   * never before `BarrierBehind - 1` pieces back from the window's centre, because the
--     closing barrier is a WALL at `BarrierBehind` and a car put down behind it would be
--     facing it;
--   * never before the first piece that still exists, because the rest have been
--     destroyed;
--   * `nil` position -- a joiner, who has no place on the road yet -- lands at the
--     window's centre, which is where whoever is furthest is driving.
--
-- A fall does NOT end a run, and nothing in this function can end one: it returns a place
-- on the road, and that is all it does.
function RoadService:SafeStart(position: Vector3?): CFrame?
	if not generator then
		return nil
	end
	local C = Config.Road
	local want = nil
	if position then
		want = generator:locate(position)
	end
	want = want or windowCentre

	local lo = math.max(generator.first, windowCentre - C.BarrierBehind + 1)
	local hi = generator.last
	if hi < lo then
		return nil
	end
	local n = math.clamp(want, lo, hi)
	local piece = generator:piece(n)
	if not piece then
		return nil
	end
	return RoadService:_poseOn(piece)
end

-- Where a player pressing start lands. On a fresh road that is piece 1; on a road someone
-- is already driving it is the window's centre, so a joiner arrives beside the leader
-- rather than behind a barrier on road that is about to be destroyed.
function RoadService:JoinCFrame(): CFrame?
	if not generator then
		return nil
	end
	return self:SafeStart(nil)
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

-- The roster as plain numbers, for the HUD's tests and for a playtest. Not Studio-only:
-- it says nothing a player could not see on their own screen.
function RoadService:RunReport()
	local out = {}
	for userId, entry in runners do
		table.insert(out, {
			userId = userId,
			from = entry.from,
			n = entry.n,
			t = entry.t,
			seconds = os.clock() - entry.since,
			position = entry.position,
		})
	end
	table.sort(out, function(a, b)
		return a.userId < b.userId
	end)
	return out
end

function RoadService:DebugState()
	if not generator then
		return {
			running = false,
			built = 0,
			pieces = 0,
			runners = 0,
			run = {},
			asks = self.asks or 0,
			asksRefused = self.asksRefused or 0,
			started = self.started or 0,
			ended = self.ended or 0,
			barriersOn = railsOn,
		}
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
	report.runners = runnerCount
	report.run = self:RunReport()
	report.asks = self.asks or 0
	report.asksRefused = self.asksRefused or 0
	report.started = self.started or 0
	report.ended = self.ended or 0
	report.barriersOn = railsOn
	report.safeStart = self:SafeStart(nil)
	return report
end

-- Studio only: press the start button for a player with no client involved, through the
-- exact path the remote takes -- rate limit, cooldown, type check and all -- so a test
-- exercises what a tap really does rather than the method behind it. `want` nil is the
-- question.
function RoadService:DebugPress(want: boolean?, userId: number?)
	assert(RunService:IsStudio(), "DebugPress is Studio only")
	for _, player in Players:GetPlayers() do
		if userId == nil or player.UserId == userId then
			self:_onRun(player, want)
			return self:RunState(player)
		end
	end
	return nil
end

-- Studio only: the cooldown and the rate limit exist to stop a client hammering the
-- button, and a test that waits half a second between presses is only measuring the wait.
function RoadService:DebugClearLimits()
	assert(RunService:IsStudio(), "DebugClearLimits is Studio only")
	self.limits = {}
end

-- Studio only: a SECOND DRIVER, with no second client to be one.
--
-- Studio gives a test exactly one player, and "what happens when somebody else presses
-- start while a run is going" is a question about the roster, the window and the road
-- staying up -- none of which need a car. So this puts a bare userId on the roster, the
-- way `StartRun` does, and hands back where that player's car WOULD have been put. The
-- half this cannot prove is the car moving, which the real player beside it proves
-- (Tests/RunTests). Nothing in the game calls either of these.
function RoadService:DebugJoin(userId: number)
	assert(RunService:IsStudio(), "DebugJoin is Studio only")
	if runners[userId] or not generator then
		return nil
	end
	local cf = self:JoinCFrame()
	if not cf then
		return nil
	end
	runners[userId] = { from = Config.Drift.StartWorld, since = os.clock(), n = 1, t = 0, told = nil }
	runnerCount += 1
	return cf
end

-- Studio only: run the service's own tick now, rather than waiting up to `TickSeconds` for
-- the thread to come round. A drive that moved the car and then slept a tenth of a second
-- for the window to notice would spend almost all of its time asleep; this runs the REAL
-- path -- read the runners' believed positions, move the window, move the barrier -- so
-- what is measured is the thing that runs in play, only sooner.
function RoadService:DebugTick()
	assert(RunService:IsStudio(), "DebugTick is Studio only")
	tick()
	return self:DebugState()
end

-- Studio only: the stage timings (T-085). `on` nil reads the switch, true or false sets
-- it; setting it either way empties the ring, so a measurement never contains the frames
-- before it was asked for. `Config.Road.Profile` is the one switch, so `Road/Builder`
-- sees the same answer.
function RoadService:DebugProfile(on: boolean?)
	assert(RunService:IsStudio(), "DebugProfile is Studio only")
	if on ~= nil then
		Config.Road.Profile = on == true
		table.clear(profile.pieces)
		table.clear(profile.destroys)
		table.clear(profile.windows)
	end
	-- Totalled here rather than in the caller so that every report of this is the same
	-- report. `worst` is the single longest piece, stages and all.
	local sum = { makeMs = 0, tagMs = 0, parentMs = 0, parts = 0 }
	local worst, worstMs = nil, -1
	for _, p in profile.pieces do
		local whole = p.makeMs + p.tagMs + p.parentMs
		sum.makeMs += p.makeMs
		sum.tagMs += p.tagMs
		sum.parentMs += p.parentMs
		sum.parts += p.parts
		if whole > worstMs then
			worst, worstMs = p, whole
		end
	end
	local genMs, worstGen = 0, 0
	for _, w in profile.windows do
		genMs += w.genMs
		worstGen = math.max(worstGen, w.genMs)
	end
	local destroyMs, worstDestroy = 0, 0
	for _, d in profile.destroys do
		destroyMs += d.destroyMs
		worstDestroy = math.max(worstDestroy, d.destroyMs)
	end
	return {
		on = Config.Road.Profile == true,
		pieces = profile.pieces,
		destroys = profile.destroys,
		windows = profile.windows,
		totals = {
			built = #profile.pieces,
			destroyed = #profile.destroys,
			parts = sum.parts,
			makeMs = sum.makeMs,
			tagMs = sum.tagMs,
			parentMs = sum.parentMs,
			genMs = genMs,
			destroyMs = destroyMs,
			worstPieceMs = if worstMs >= 0 then worstMs else 0,
			worstPieceN = worst and worst.n,
			worstGenMs = worstGen,
			worstDestroyMs = worstDestroy,
		},
	}
end

function RoadService:DebugLeave(userId: number)
	assert(RunService:IsStudio(), "DebugLeave is Studio only")
	self:_leave(userId)
	return runnerCount
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
