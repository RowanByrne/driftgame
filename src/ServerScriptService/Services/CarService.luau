--!nonstrict
-- CarService: spawning, respawning, despawning, and passing each car's state to the other
-- players.
--
-- The server does not simulate the car. Feel cannot survive a round trip, so the client
-- that drives a car moves it, and this service owns where a car may be put -- its spawn
-- and every respawn -- and who gets told about it (features/drift-model.md "Server and
-- client").
--
-- That split is what lets the checks below be strict. The server knows where it last put
-- the car and where it last agreed the car was, so a packet that follows from neither is
-- one nothing honest can have produced, and it is dropped -- and the next one is checked
-- against the same place, not against the jump. The client never moves itself: falling
-- off the world is a request (`CarRespawn`), and the answer is a position the server
-- chose.
--
-- The checks are still only the shape of server-authoritative movement, not the whole of
-- it: they bound speed and distance, they do not re-run the model. That waits for
-- something being scored or sold (features/drift-model.md "Open questions"). They drop
-- rather than kick (docs/game/CONTRACTS.md, `CarState`).
--
-- WHICH CAR EACH PLAYER IS IN IS THIS SERVICE'S TOO (T-033,
-- features/car-archetypes.md). It used to be nobody's: the archetype switched on the
-- client, the server bounded every packet against the top speed of the car IT happened to
-- have active, and the two were only ever reconciled by keeping every archetype slower
-- than the default car's tolerance. That is not a rule a game can keep.
--
-- So the client ASKS, over `CarSwitch`, and this service decides:
--
--   * it validates the key against the known archetypes and IGNORES anything else, rather
--     than trusting a string off the wire -- no key, a key that is not a car, a number, a
--     table, a flood: refused, counted, and ANSWERED with the car the server believes, so
--     a client that asked for something it may not have is put back where the server has
--     it rather than left simulating a car nobody agreed to;
--   * it re-dresses that player's car itself, so the shape follows the switch on a car
--     already spawned and every other player sees it (`CarModel.dress` and the `Body`
--     attribute replicate like anything else the server does);
--   * it bounds that player's `CarState` against THEIR car's numbers.
--
-- The client may still predict the switch locally -- that is the point of a client-side
-- model, and it is why the feel changes on the very next step -- but the server's answer
-- is what settles it.
--
-- WHO IS IN THE CAR IS THIS SERVICE'S TOO (T-096, features/car-v2.md). Characters are back:
-- each player has an avatar, and it starts in the driver's seat. Getting out and back in
-- are requests (`CarExit`, `CarEnter`), checked here against speed, distance and whose car
-- it is, and the answer is what moves the avatar. The seated avatar is held by NOTHING --
-- no Seat, no weld, no joint (DECISIONS.md, 2026-11-03) -- its root is anchored here and
-- every client writes it each frame into the car it has just drawn (`Drift/Driver`). The
-- car's `Driver` attribute says who is in it. A parked car is put where the server last
-- agreed it was, and stays there: no `CarState` moves it until its driver is back in.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local CarParts = require(ReplicatedStorage.Shared.CarParts)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local Customization = require(ReplicatedStorage.Shared.Customization)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)

-- The seat and exit points, from the same module every client places the driver with, so
-- the server and the clients cannot disagree about where the seat is. Pure: points and
-- offsets, nothing that needs a client.
local Driver = require(StarterPlayer.StarterPlayerScripts:WaitForChild("Drift"):WaitForChild("Driver"))

local CarService = {}

CarService.Priority = 50 -- remotes exist before any controller asks for them

-- Where the server believes a car is: the last position it agreed to, and when. A car has
-- one of these, and for `RespawnGrace` after a respawn it keeps the one it was on before
-- as well, so the packets already on the wire still have something true to check against.
export type Track = { position: Vector3, at: number }

function CarService.track(position: Vector3, at: number): Track
	return { position = position, at = at }
end

-- WHOSE TOP SPEED. Every bound below is a share of a top speed, and since T-033 that is
-- the top speed of the car THAT PLAYER is in -- a resolved car table from
-- `Cars.resolve(key)`, which answers for any car without touching which one is active.
-- `nil` falls back to `Config.Drift`, which is the active car, for a caller that has no
-- player in hand.
local function topSpeed(car: { [string]: any }?): number
	return if car then car.TopSpeed else Config.Drift.TopSpeed
end

-- Is this a speed the model could be going at? Horizontal and vertical are bounded by
-- different things -- top speed across the ground, terminal velocity down -- so they are
-- checked apart. Checking the magnitude of the two together rejects every honest packet
-- from a car that has driven off the world, which happens in normal play.
--
-- The fall is the MODEL's (`TerminalFall`) and not the car's: gravity is the same for
-- every archetype, and a car that has driven off the world is not driving.
function CarService.speedFits(velocity: Vector3, car: { [string]: any }?): boolean
	local C = Config.Drift
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude <= topSpeed(car) * C.StateSpeedTolerance
		and math.abs(velocity.Y) <= C.TerminalFall * C.StateSpeedTolerance
end

-- Whose numbers accept this velocity: the car the player is in, or -- inside
-- `CarSwitchGrace` -- the car they were in when the packet was sent. Returns the car that
-- accepts it and whether it took the old one to do it, or nil for a speed neither could
-- be going at. Pure, so the tests drive it with no player (Tests/DriftTests).
function CarService.allows(
	velocity: Vector3,
	car: { [string]: any }?,
	wasCar: { [string]: any }?
): ({ [string]: any }?, boolean)
	if CarService.speedFits(velocity, car) then
		return car, false
	end
	if wasCar and CarService.speedFits(velocity, wasCar) then
		return wasCar, true
	end
	return nil, false
end

-- Could a car on `track` be at `position` by `now`? The same split, applied to the
-- distance covered since the track was last agreed. Pure, so the tests drive it with no
-- player and no playtest (Tests/DriftTests).
function CarService.fits(track: Track, position: Vector3, now: number, car: { [string]: any }?): boolean
	local C = Config.Drift
	local budget = math.max(now - track.at, 1 / 1000) * C.StateMoveTolerance
	local moved = position - track.position
	return Vector3.new(moved.X, 0, moved.Z).Magnitude
			<= topSpeed(car) * C.StateSpeedTolerance * budget + C.StateMoveAllowance
		and math.abs(moved.Y) <= C.TerminalFall * C.StateSpeedTolerance * budget + C.StateMoveAllowance
end

function CarService:Init()
	self.cars = {} -- userId -> Model
	self.seen = {} -- userId -> { expect: Track, was: Track?, graceUntil, window, count, dropped, ... }
	self.carKeys = {} -- userId -> the archetype key the SERVER says that player is in
	self.builds = {} -- userId -> their fitted build (CustomizationService), for the bounds (T-106)
	self.buildSets = 0
	self.dropped = 0
	self.respawns = 0
	self.respawnsRefused = 0
	self.inFlightKept = 0
	self.switches = 0
	self.switchesRefused = 0
	self.switchInFlightKept = 0
	self.dressing = false -- one car dressed at a time: dressing flips the active car
	-- Getting in and out (T-096). `entry` is per car and goes with it; `entryRate` is keyed
	-- by UserId and kept, so rejoining does not reset the limit.
	self.entry = {} -- userId -> { driving, busy, gen, parked: CFrame? }
	self.entryRate = {} -- userId -> { window, count }
	self.exits = 0
	self.enters = 0
	self.exitsRefused = 0
	self.entersRefused = 0
	self.refusals = {} -- reason -> count
	self.parkedDropped = 0 -- CarState packets for a car whose driver is out
	-- Fired with `(player, why)` whenever this service puts a player's car somewhere of its
	-- own accord -- a respawn, a `Place`, a new car, the car going -- so anything holding the
	-- car (the garage visit, T-103) lets go rather than fight it.
	self.CarMoved = Signal.new()
	self.holds = 0
	self.releases = 0

	-- IT HAS TO BE A FOLDER, and asking by name alone is not enough. A place file can
	-- carry anything called `Cars` -- `DR-Lane2` had a stray ModuleScript of that name,
	-- left over from some earlier session -- and `FindFirstChild` would hand it back. The
	-- cars then hang off a ModuleScript, which happens to render, so nothing looks wrong
	-- until something walks `Workspace.Cars` expecting the folder `CONTRACTS.md` promises.
	-- Anything else of that name is pushed aside rather than destroyed: it is not ours.
	local folder = workspace:FindFirstChild("Cars")
	if folder and not folder:IsA("Folder") then
		warn(`[CarService] Workspace.Cars is a {folder.ClassName}, not a Folder. Renaming it to Cars_NotOurs and making the folder.`)
		folder.Name = "Cars_NotOurs"
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Cars"
		folder.Parent = workspace
	end
	self.folder = folder

	self.carSpawn = Net.event("CarSpawn")
	self.carRespawn = Net.event("CarRespawn")
	self.carSwitch = Net.event("CarSwitch")
	self.carState = Net.unreliable("CarState")
	self.carStateOther = Net.unreliable("CarStateOther")
	self.carEnter = Net.event("CarEnter")
	self.carExit = Net.event("CarExit")
end

function CarService:Start()
	if Config.CarEntry.Characters then
		-- Characters are back (T-096): the avatar sits in the car, anchored and placed by
		-- code, and walks with Roblox's own controls when it gets out. `Config.Drift.
		-- HideCharacter` no longer decides this.
		Players.CharacterAutoLoads = true
	else
		-- The old way: the player is the car. No character means no Humanoid to fight the
		-- simulation, no default touch thumbstick over our own, nothing physical.
		Players.CharacterAutoLoads = false
		for _, player in Players:GetPlayers() do
			if player.Character then
				player.Character:Destroy()
			end
		end
	end

	local function join(player: Player)
		player.CharacterAdded:Connect(function(character)
			self:_onCharacter(player, character)
		end)
		self:Spawn(player)
		if player.Character then
			self:_onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(join)
	Players.PlayerRemoving:Connect(function(player)
		self:Despawn(player)
		self.builds[player.UserId] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(join, player)
	end

	self.carState.OnServerEvent:Connect(function(player, cf, velocity, drifting, lift)
		self:_onState(player, cf, velocity, drifting, lift)
	end)
	self.carRespawn.OnServerEvent:Connect(function(player)
		-- No payload: there is nothing for the client to say. It asks, the server picks.
		self:Respawn(player)
	end)
	self.carSwitch.OnServerEvent:Connect(function(player, key)
		self:_onSwitch(player, key)
	end)
	-- Getting out and in (T-096). One value each, and nothing else on the wire is read.
	self.carExit.OnServerEvent:Connect(function(player, cf)
		self:_onExit(player, cf)
	end)
	self.carEnter.OnServerEvent:Connect(function(player, car)
		self:_onEnter(player, car)
	end)
end

--------------------------------------------------------------------------------
-- Which world, and where in it
--------------------------------------------------------------------------------
-- A place has TWO worlds since T-026: the hand-placed track where its author left it,
-- and the playground built from its layout thousands of studs away
-- (`Config.Drift.PlaygroundOffsetFromTrack`). So "where a car goes" is a choice, and this
-- service makes it, because it is the service that owns where a car may be put.
--
--   * a car SPAWNS in `Config.Drift.StartWorld`, and in whichever world exists if that
--     one does not;
--   * a car RESPAWNS in the world it was last believed to be in, so falling out of one
--     world never drops you into the other;
--   * `DebugCross` hops between them, which is the only way across: they are islands
--     over the void and far too far apart to drive.
--
-- SINCE T-044 THERE IS A THIRD, AND IT COMES AND GOES: the endless road, at
-- `Config.Road.Offset`, which exists only while somebody is driving a run
-- (`RoadService`, features/endless-run.md). It is a world for exactly the reason the
-- other two are -- so that falling out of it puts a car back INTO it -- and it is not in
-- the fall-through order below, because nothing may ever SPAWN there: a run is entered by
-- pressing the button and no other way. `Config.Drift.StartWorld` stays "track".
--
-- Two things about it are not like the other two, and both are handled here:
--
--   * it MOVES. The other two are fixed boxes round a fixed spawn, so "which world is
--     this position in" is the nearest spawn. The road grows away from its start for as
--     long as the run lasts, so the road is asked DIRECTLY whether a position is on it,
--     and only the two fixed worlds are decided by distance;
--   * its respawn is not its spawn. A car that falls off at piece 30 belongs back on
--     piece 30, not on piece 1 -- which was destroyed twenty-six pieces ago, and would
--     be the run starting again. `RoadService:SafeStart` is that place, and a fall
--     never ends a run.

local WORLD_TRACK = "track"
local WORLD_PLAYGROUND = "playground"
local WORLD_ROAD = "road"

local function service(name: string): any?
	local services = ServerScriptService:FindFirstChild("Services")
	local module = services and services:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, loaded = pcall(require, module)
	if ok and type(loaded) == "table" then
		return loaded
	end
	return nil
end

-- The road, if this place has one loaded AND a run is going. `nil` the rest of the time,
-- which is most of the time: the road is off by default.
local function liveRoad(): any?
	local road = service("RoadService")
	if not road or type(road.HasRoad) ~= "function" then
		return nil
	end
	local ok, has = pcall(road.HasRoad, road)
	if ok and has then
		return road
	end
	return nil
end

-- Each world's spawn, or nil for a world this place has not got. The road is in here only
-- while a run is going, and it is the only one of the three that can disappear.
local function worldSpawns(): { [string]: CFrame }
	local out = {}
	local track = service("TrackService")
	if track and type(track.SpawnCFrame) == "function" then
		local ok, cf = pcall(track.SpawnCFrame, track)
		if ok and typeof(cf) == "CFrame" then
			out[WORLD_TRACK] = cf
		end
	end
	local playground = service("PlaygroundService")
	if playground and type(playground.GetSpot) == "function" then
		local ok, cf = pcall(playground.GetSpot, playground, "Spawn")
		if ok and typeof(cf) == "CFrame" then
			out[WORLD_PLAYGROUND] = cf
		end
	end
	local road = liveRoad()
	if road and type(road.SpawnCFrame) == "function" then
		local ok, cf = pcall(road.SpawnCFrame, road)
		if ok and typeof(cf) == "CFrame" then
			out[WORLD_ROAD] = cf
		end
	end
	return out
end

-- The worlds this place has, named. Studio and the tests read it; so does `DebugState`.
function CarService:Worlds(): { [string]: CFrame }
	return worldSpawns()
end

-- Where a car starts in a named world. An unknown or missing world falls through to
-- whichever one the place has, and a place with neither (a bare baseplate lane) puts the
-- car above the origin, exactly as before.
--
-- THE ROAD IS DELIBERATELY NOT IN THE FALL-THROUGH. It can be asked for by name, which is
-- how a run starts, but nothing is ever sent there by default: a place with a road up and
-- no track would otherwise start spawning cars into somebody else's run.
function CarService:SpawnCFrameIn(world: string?): CFrame
	local spawns = worldSpawns()
	local wanted = spawns[world or ""]
	if wanted then
		return wanted
	end
	return spawns[WORLD_TRACK] or spawns[WORLD_PLAYGROUND] or CFrame.new(0, Config.Drift.RideHeight, 0)
end

-- Which world a position is in.
--
-- THE ROAD IS ASKED, THE OTHER TWO ARE MEASURED. The track and the playground are fixed
-- boxes round a fixed spawn 12 000 studs apart, each 2 000 across at the most, so "nearer"
-- is never a close call and there is no need to box-test either of them. The road is not
-- like that: it grows away from its own start for as long as the run lasts, so after an
-- hour of driving "nearest to piece 1" would stop being true of a car that is plainly on
-- it. It knows where it is, so it is asked -- `PieceAt` is nil for a position that is not
-- on the road at all.
function CarService:WorldAt(position: Vector3): string?
	local road = liveRoad()
	if road and type(road.PieceAt) == "function" then
		local ok, piece = pcall(road.PieceAt, road, position)
		if ok and piece then
			return WORLD_ROAD
		end
	end
	local nearest, nearestName = math.huge, nil
	for name, cf in worldSpawns() do
		if name == WORLD_ROAD then
			continue -- answered above, by the road itself
		end
		local flat = Vector3.new(position.X - cf.Position.X, 0, position.Z - cf.Position.Z).Magnitude
		if flat < nearest then
			nearest, nearestName = flat, name
		end
	end
	return nearestName
end

-- Where a car that was last at `position` belongs: the spawn of the world it was in.
-- PlaygroundService's fall catcher asks this too, so a car it scoops up off the void
-- comes back in the world it fell out of.
--
-- The road answers with `SafeStart` and not with its spawn, because its spawn is piece 1
-- and piece 1 stopped existing a long way back. A fall costs the piece you were in the
-- middle of, and nothing else (`RoadService:SafeStart`).
function CarService:SpawnCFrameNear(position: Vector3): CFrame
	local world = self:WorldAt(position)
	if world == WORLD_ROAD then
		local road = liveRoad()
		if road and type(road.SafeStart) == "function" then
			local ok, cf = pcall(road.SafeStart, road, position)
			if ok and typeof(cf) == "CFrame" then
				return cf
			end
		end
	end
	return self:SpawnCFrameIn(world)
end

-- Where a car starts: the configured world.
function CarService:SpawnCFrame(): CFrame
	return self:SpawnCFrameIn(Config.Drift.StartWorld)
end

-- Where the server last believed this player's car to be. NOT the model's pivot: the
-- server does not simulate the car and never moves the model between the places it puts
-- it, so the pivot is the last spawn and the believed position is the last `CarState` it
-- accepted. That is what says which world a respawn belongs in.
function CarService:BelievedPosition(userId: number): Vector3?
	local seen = self.seen and self.seen[userId]
	local track = seen and (seen.expect or seen.was)
	return track and track.position or nil
end

-- Everything that puts a car somewhere goes through here, because the movement check is
-- only as good as the position it compares against. A respawn keeps the track the car was
-- on for `RespawnGrace`: a CarState sent a moment before the respawn can land after it --
-- an unreliable packet and a reliable request race each other -- and that packet is
-- honest, from a place the server knows the car was.
function CarService:_expect(userId: number, position: Vector3)
	local now = os.clock()
	local seen = self.seen[userId]
	if not seen then
		seen = { window = now, count = 0, dropped = 0, respawnWindow = now, respawnCount = 0 }
		self.seen[userId] = seen
	elseif seen.expect then
		seen.was = seen.expect
		seen.graceUntil = now + Config.Drift.RespawnGrace
	end
	seen.expect = CarService.track(position, now)
	return seen
end

-- ---------------------------------------------------------------- which car, per player

-- The car the SERVER says this player is in. A player it has never heard of is in the
-- default car, which is also what it would build one for.
function CarService:CarKey(player: Player): string
	return self.carKeys[player.UserId] or Cars.Default
end

-- That car's numbers, resolved: what every bound on their `CarState` is a share of. A
-- fresh table per packet on purpose -- `Cars.tune` during a tuning session moves the
-- server's bounds with the client's feel, and a cached copy would not.
--
-- WITH THEIR FITTED PARTS (T-106). The player's build is laid over the car they are in NOW
-- (`Customization.carFields(build, key)`: the parts go with the player into whichever car
-- they switch to), exactly as the driving client lays it (`Shared/Cars/BuildFeel`), so an
-- Engine part's extra top speed is extra speed the server takes. The tuning layer still
-- sits on top, as it does on the client; and the dev tuner's server-wide `TopSpeed`
-- ceiling (`GarageService`) can only ever RAISE a bound, never pull a built car below its
-- own build's top speed.
function CarService:_numbersFor(userId: number, key: string): { [string]: any }?
	local build = self.builds[userId]
	if not build then
		return Cars.resolve(key)
	end
	local fields = Customization.carFields(build, key)
	local numbers = Cars.resolve(key, fields)
	if numbers and fields.TopSpeed and fields.TopSpeed > numbers.TopSpeed then
		numbers.TopSpeed = fields.TopSpeed
	end
	return numbers
end

function CarService:_numbers(userId: number): { [string]: any }?
	return self:_numbersFor(userId, self.carKeys[userId] or Cars.Default)
end

-- THE PLAYER'S FITTED BUILD, for their bounds (T-106). `CustomizationService` calls this
-- whenever a build is loaded, fitted or published on a car; nil is the stock car. A build
-- that lowers their top speed opens `CarSwitchGrace`, as a car switch does: a packet
-- already on the wire was honest under the build they had.
function CarService:SetBuild(userId: number, build: Customization.Build?)
	local before = self:_numbers(userId)
	self.builds[userId] = if build then Customization.copy(build) else nil
	self.buildSets += 1
	local seen = self.seen[userId]
	local after = self:_numbers(userId)
	if seen and before and after and after.TopSpeed < before.TopSpeed then
		seen.carWas = before
		seen.carGraceUntil = os.clock() + Config.Drift.CarSwitchGrace
	end
end

function CarService:BuildOf(userId: number): Customization.Build?
	local build = self.builds[userId]
	return if build then Customization.copy(build) else nil
end

-- Build or dress a car as `key`, with `key` active for the length of the call.
--
-- `CarModel` reads the ACTIVE car for both the body it draws (`CarBody = "auto"`) and the
-- geometry it draws it around, so this is the one place the server touches the global
-- active car -- and it puts it back. Serialised, because `CarModel.shell()` can yield on
-- a mesh body and two overlapping dresses would each restore the other's car.
function CarService:_withCar(key: string, fn: () -> ...any): ...any
	while self.dressing do
		task.wait()
	end
	self.dressing = true
	local results = table.pack(pcall(Cars.withActive, key, fn))
	self.dressing = false
	if not results[1] then
		warn(`[CarService] dressing a car as '{key}' failed: {tostring(results[2])}`)
		return nil
	end
	return table.unpack(results, 2, results.n)
end

-- Put a live car in the shape of `key`, where the server's own copy is.
--
-- A fresh shell is built about the origin, so it is placed once, here, as an absolute
-- pivot on a model that has never been pivoted -- not the per-frame delta that walked a
-- shell 2 500 studs off its car (Drift/Render, T-020). Every client draws the shell
-- itself; this is so the SERVER's copy is a whole car, and so a client that catches the
-- new shell before it has drawn it does not see it at the world origin.
function CarService:_dress(car: Model, key: string)
	self:_withCar(key, function()
		CarModel.dress(car, CarModel.shell())
		local shell = car:FindFirstChild(CarModel.SHELL_NAME)
		if shell and shell:IsA("Model") then
			shell:PivotTo(car:GetPivot())
		end
	end)
end

-- THE SERVER'S DECISION, and the only thing that moves a player between cars. The remote
-- below is one caller; `DebugSetCar` and the tests are others, and none of them may skip
-- this.
--
-- Refused for an unknown key, for anything that is not a string, and for a player with no
-- car. Accepted, it re-dresses the car -- so the shape changes on a car already spawned,
-- for everyone, with no rejoin -- and opens `CarSwitchGrace`, in which a `CarState` that
-- is too fast for the new car is still checked against the old one.
function CarService:SetCar(player: Player, key: string): boolean
	if not Cars.exists(key) then
		return false
	end
	local car = self.cars[player.UserId]
	if not car or not car.Parent then
		return false
	end

	local was = self:CarKey(player)
	if was == key then
		return true -- already in it: accepted, and nothing to rebuild
	end

	local seen = self.seen[player.UserId]
	if seen then
		-- The car they were in, kept the way a respawn keeps the place they were: a packet
		-- already on the wire was honest under it.
		seen.carWas = self:_numbersFor(player.UserId, was)
		seen.carGraceUntil = os.clock() + Config.Drift.CarSwitchGrace
	end
	self.carKeys[player.UserId] = key
	self.switches += 1
	self:_dress(car, key)
	return true
end

-- The wire. A client may ask; it may not insist, and it may not ask quickly.
--
-- `key` nil is a QUESTION -- "which car does the server have me in?" -- which the client
-- asks when it starts up, so a client that missed the answer sent with its spawn is never
-- left out of step. Anything else that is not a known archetype is refused and counted.
--
-- Every path answers, including every refusal: the answer is what puts a client that
-- predicted a switch it may not have back into the car the server believes.
function CarService:_onSwitch(player: Player, key: any)
	local seen = self.seen[player.UserId]
	local now = os.clock()

	-- Rate limit first, and the question counts against it too: a flood is a flood.
	if seen then
		if now - (seen.switchWindow or 0) >= 1 then
			seen.switchWindow = now
			seen.switchCount = 0
		end
		seen.switchCount = (seen.switchCount or 0) + 1
		if seen.switchCount > Config.Drift.CarSwitchRateLimit then
			self.switchesRefused += 1
			self:_tellCar(player, false)
			return
		end
	end

	if key == nil then
		self:_tellCar(player, true) -- a question, answered, changing nothing
		return
	end

	if not self:SetCar(player, key) then
		self.switchesRefused += 1
		self:_tellCar(player, false)
		return
	end
	self:_tellCar(player, true)
end

-- What the server believes, said out loud. `accepted` is false when the ask was refused,
-- which is the client's cue to put itself back rather than go on simulating a car nobody
-- agreed to.
function CarService:_tellCar(player: Player, accepted: boolean)
	self.carSwitch:FireClient(player, self:CarKey(player), accepted)
end

-- Studio only: move a player between cars with no client involved, exactly as the remote
-- does. `userId` nil takes the first player.
function CarService:DebugSetCar(key: string, userId: number?): string?
	for _, player in Players:GetPlayers() do
		if userId == nil or player.UserId == userId then
			local ok = self:SetCar(player, key)
			self:_tellCar(player, ok)
			return if ok then self:CarKey(player) else nil
		end
	end
	return nil
end

function CarService:Spawn(player: Player): Model?
	-- Read before the despawn, which forgets it: a car rebuilt for a player already in one
	-- is rebuilt in that car, shape and geometry both.
	local key = self:CarKey(player)
	self:Despawn(player)
	self.carKeys[player.UserId] = key
	self.CarMoved:Fire(player, "spawn")

	local spawnCFrame = self:SpawnCFrame()
	local car = self:_withCar(key, CarModel.build)
	if not car then
		return nil
	end
	car.Name = `Car_{player.UserId}`
	car:SetAttribute("UserId", player.UserId)
	car:PivotTo(spawnCFrame)
	car.Parent = self.folder

	local offenders = CarModel.physicsOffenders(car)
	if #offenders > 0 then
		-- The one rule the whole model rests on (docs/game/DECISIONS.md, 2026-11-03).
		warn(`[CarService] {car.Name} is not purely kinematic: {table.concat(offenders, "; ")}`)
	end

	self.cars[player.UserId] = car
	self:_expect(player.UserId, spawnCFrame.Position)
	-- A new car has its driver in it: the avatar, if it has arrived, goes in the seat now,
	-- and one that arrives later is put there by `_onCharacter`.
	self.entry[player.UserId] = { driving = true, busy = false, gen = 0, parked = nil }
	self:_seatCharacter(player)
	self.carSpawn:FireClient(player, car, spawnCFrame)
	-- And which car it is. A client that is not listening yet asks the same question back
	-- when it starts (`_onSwitch` with no key), so neither end has to win that race.
	self:_tellCar(player, true)
	return car
end

-- A client whose car has fallen off the world asks for this; the server picks the place,
-- moves the car, records it as where the car is expected, and tells the client. Refused
-- if the player has no car, if it asks again inside `RespawnCooldown`, or past
-- `RespawnRateLimit` requests in a second (docs/game/CONTRACTS.md, `CarRespawn`).
--
-- `to` is for the server's own callers only -- the debug crossing between worlds -- and
-- is never taken off the wire: `_onSwitch`'s neighbour here, the `CarRespawn` handler,
-- passes nothing, because where a car goes is not the client's to say.
function CarService:Respawn(player: Player, to: CFrame?): CFrame?
	local car = self.cars[player.UserId]
	if not car or not car.Parent then
		self.respawnsRefused += 1
		return nil
	end

	local now = os.clock()
	local seen = self.seen[player.UserId]
	if seen then
		if now - (seen.respawnWindow or 0) >= 1 then
			seen.respawnWindow = now
			seen.respawnCount = 0
		end
		seen.respawnCount = (seen.respawnCount or 0) + 1
		if seen.respawnCount > Config.Drift.RespawnRateLimit then
			self.respawnsRefused += 1
			return nil
		end
		if seen.respawnedAt and now - seen.respawnedAt < Config.Drift.RespawnCooldown then
			self.respawnsRefused += 1
			return nil
		end
	end

	-- WHICH WORLD it comes back in: the one the server last believed the car was in, so
	-- a car that drove off the playground is not put down on the track 12 000 studs away
	-- (T-026). Nothing believed yet -- a respawn before the first accepted packet -- is
	-- the configured start world.
	--
	-- A PLAYER IN A RUN IS ASKED ABOUT FIRST, and the question is the roster, not the
	-- position. Falling off the road usually leaves a believed position the road can still
	-- place -- it locates in X and Z and a fall is in Y -- but a car that has not sent a
	-- packet yet, or that went off the side and kept going, would fall through to
	-- `SpawnCFrame` and be yanked back to the track, silently ending a run a fall is not
	-- allowed to end (features/endless-run.md "What a fall does").
	local believed = self:BelievedPosition(player.UserId)
	local cf = to
	if not cf then
		local road = liveRoad()
		if road and type(road.InRun) == "function" and type(road.SafeStart) == "function" then
			local ok, inRun = pcall(road.InRun, road, player)
			if ok and inRun then
				local got, onRoad = pcall(road.SafeStart, road, believed)
				if got and typeof(onRoad) == "CFrame" then
					cf = onRoad
				end
			end
		end
	end
	if not cf then
		cf = if believed then self:SpawnCFrameNear(believed) else self:SpawnCFrame()
	end
	car:PivotTo(cf)
	seen = self:_expect(player.UserId, cf.Position)
	seen.respawnedAt = os.clock()
	self.respawns += 1
	-- Whatever was holding the car (the garage) lets go first: this move is the last word.
	self.CarMoved:Fire(player, "respawn")
	-- A car put somewhere is a car with its driver in it (T-096). A player who was out --
	-- a run started or ended, a Studio hop -- is sat back in first and told so, BEFORE the
	-- respawn's answer, so their client is driving again when it hears where the car is. A
	-- player already in has the server's copy of their avatar moved with the car.
	self:_seatNow(player, true)
	self.carRespawn:FireClient(player, cf)
	return cf
end

-- THE SERVER PUTTING A CAR SOMEWHERE BECAUSE IT DECIDED TO, rather than because a client
-- asked. The only difference from `Respawn(player, cf)` is that the respawn cooldown and
-- counter do not apply: they exist to stop a client hammering `CarRespawn` and teleporting
-- itself about, and a move the server chose is not that.
--
-- It is still a narrow door. `cf` is never a value off the wire -- the two callers are
-- `RoadService` starting and ending a run, which computes it from the generator, and
-- `DebugCross`, which is Studio only. The caller's own rate limit is what bounds how often
-- this can happen: a start button that could be pressed freely would be a teleport with a
-- label on it (features/endless-run.md "What the client may say").
function CarService:Place(player: Player, cf: CFrame): CFrame?
	if typeof(cf) ~= "CFrame" then
		return nil
	end
	local seen = self.seen[player.UserId]
	if seen then
		seen.respawnedAt = nil
		seen.respawnCount = 0
	end
	return self:Respawn(player, cf)
end

function CarService:Despawn(player: Player)
	local car = self.cars[player.UserId]
	if car then
		car:Destroy()
	end
	self.cars[player.UserId] = nil
	self.seen[player.UserId] = nil
	self.carKeys[player.UserId] = nil
	self.entry[player.UserId] = nil
end

function CarService:_drop(seen)
	self.dropped += 1
	if seen then
		seen.dropped = (seen.dropped or 0) + 1
	end
end

-- The four wheels' suspension lift, packed one byte each (`Drift/Suspension.pack`, T-095):
-- looks only, so nothing is checked against it but its shape. Nil is an older client.
function CarService.liftOk(lift: any): boolean
	return lift == nil
		or (type(lift) == "number" and lift == lift and lift >= 0 and lift < 4294967296 and lift % 1 == 0)
end

function CarService:_onState(player: Player, cf, velocity, drifting, lift)
	local seen = self.seen[player.UserId]
	if
		typeof(cf) ~= "CFrame"
		or typeof(velocity) ~= "Vector3"
		or type(drifting) ~= "boolean"
		or not CarService.liftOk(lift)
	then
		self:_drop(seen)
		return
	end
	if not seen or not seen.expect then
		-- The server has not put a car anywhere for this player, so there is nothing to
		-- check the packet against.
		self:_drop(seen)
		return
	end
	local entry = self.entry[player.UserId]
	if entry and (not entry.driving or entry.busy) then
		-- Parked, or on the way in or out (T-096). Nobody is driving this car, so nothing
		-- may move it: a packet now is either in flight from before the press or a lie.
		self.parkedDropped += 1
		self:_drop(seen)
		return
	end

	local now = os.clock()

	-- Rate limit, keyed by UserId so rejoining does not reset it.
	if now - seen.window >= 1 then
		seen.window = now
		seen.count = 0
	end
	seen.count += 1
	if seen.count > Config.Drift.StateRateLimit then
		self:_drop(seen)
		return
	end

	-- WHICH CAR THIS PACKET IS BOUNDED AGAINST. Theirs -- and, for `CarSwitchGrace` after
	-- a switch, the car they were in a moment ago as well.
	--
	-- A car's top speed changes the instant a switch lands, and `CarState` is unreliable
	-- and 50 ms apart: a packet sent by the bruiser at 215 studs/s can arrive after the
	-- switch to a gripper bounded at 150 x 1.25 = 187.5, and it is honest. This is exactly
	-- what `RespawnGrace` does for a position the car has just been moved from, and it is
	-- answered the same way: try the car it is now, then the car it was, and count the
	-- ones only the old car explains. Past the grace, only the new car counts -- which is
	-- the whole point, because a switch to a slower car has to actually tighten the bound.
	local car = self:_numbers(player.UserId)
	local wasCar = nil
	if seen.carWas then
		if now < (seen.carGraceUntil or 0) then
			wasCar = seen.carWas
		else
			seen.carWas = nil
			seen.carGraceUntil = nil
		end
	end

	local allowed, keptByOldCar = CarService.allows(velocity, car, wasCar)
	if not allowed then
		self:_drop(seen)
		return
	end

	if seen.was and now >= (seen.graceUntil or 0) then
		seen.was = nil -- the grace is over: only where the server put the car counts now
		seen.graceUntil = nil
	end

	-- Could their car have covered this since the track was agreed -- or, inside the
	-- grace, could the car they were in?
	local function reaches(track): boolean
		if CarService.fits(track, cf.Position, now, car) then
			return true
		end
		if wasCar and CarService.fits(track, cf.Position, now, wasCar) then
			keptByOldCar = true
			return true
		end
		return false
	end

	if reaches(seen.expect) then
		seen.expect = CarService.track(cf.Position, now)
		-- The whole pose and the speed, for getting out: where a car is parked when the
		-- press itself cannot be believed, and whether it was slow enough (T-096).
		seen.lastCF = cf
		seen.lastVelocity = velocity
	elseif seen.was and reaches(seen.was) then
		-- Sent before the respawn, arrived after it. Honest, so it is passed on, but it
		-- does not move where the server expects the car: that stays the respawn position
		-- until a packet arrives that follows from it.
		seen.was = CarService.track(cf.Position, now)
		self.inFlightKept += 1
	else
		-- A jump nobody asked for. Dropped, and the one after it is checked against the
		-- same place: the server never takes the client's word for where the car is.
		self:_drop(seen)
		return
	end

	if keptByOldCar then
		-- Honest only under the car they were just in: in flight across the switch.
		self.switchInFlightKept += 1
	end

	for _, other in Players:GetPlayers() do
		if other ~= player then
			self.carStateOther:FireClient(other, player.UserId, cf, velocity, drifting, lift)
		end
	end
end

--------------------------------------------------------------------------------
-- Getting in and out (T-096, features/car-v2.md)
--------------------------------------------------------------------------------
-- The avatar is the server's to move between the seat and the road, and these are the
-- only places that do it. In the seat, its root is anchored and the server's copy is put
-- in the server's copy of the car; every client then writes it each frame into the car IT
-- draws (`Drift/Driver`). Out, the root is unanchored and the avatar is the player's to
-- walk.
--
-- The door, where a car has one (a v2 rig's `DoorR`), is opened and shut through
-- `Shared/CarParts` here on the server, so its attributes reach every client and everyone
-- sees it swing. Today's cars have no rig and no door: the steps happen in the same order
-- with `NoDoorSeconds` between them.
--
-- A sequence is numbered (`gen`). Anything that sits the player down outright -- a respawn,
-- a new avatar, a new car -- bumps it, and a sequence that wakes to find its number gone
-- stops where it is rather than finishing a move nobody wants any more.

local DRIVER = Config.CarEntry.DriverAttribute

-- Requests a second, getting in and out together, keyed by UserId.
function CarService:_entryRateOk(player: Player): boolean
	local now = os.clock()
	local rate = self.entryRate[player.UserId]
	if not rate then
		rate = { window = now, count = 0 }
		self.entryRate[player.UserId] = rate
	end
	if now - rate.window >= 1 then
		rate.window = now
		rate.count = 0
	end
	rate.count += 1
	return rate.count <= Config.CarEntry.RateLimit
end

function CarService:_refuse(player: Player, remote: RemoteEvent, reason: string): (boolean, string)
	self.refusals[reason] = (self.refusals[reason] or 0) + 1
	if remote == self.carExit then
		self.exitsRefused += 1
	else
		self.entersRefused += 1
	end
	remote:FireClient(player, false, nil, reason)
	return false, reason
end

-- A CFrame a car can be parked at: finite, with a rotation that is a rotation.
local function sane(cf: any): boolean
	if typeof(cf) ~= "CFrame" then
		return false
	end
	local p = cf.Position
	if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z or p.Magnitude > 1e7 then
		return false
	end
	local x, y = cf.XVector.Magnitude, cf.YVector.Magnitude
	return math.abs(x - 1) < 1e-3 and math.abs(y - 1) < 1e-3
end

-- Open or shut the driver's door, and how long that takes. No rig, no door.
function CarService:_door(car: Model, open: boolean): number
	local name = Config.CarEntry.DoorName
	if CarParts.isRig(car) then
		local desc = CarParts.describe(car)
		if desc and desc.byName[name] then
			local ok, seconds = pcall(if open then CarParts.open else CarParts.close, car, name)
			if ok and type(seconds) == "number" then
				return seconds
			end
		end
	end
	return Config.CarEntry.NoDoorSeconds
end

-- The server's copy of the avatar into the server's copy of the car, and the car told who
-- is in it. False with no car or no avatar yet.
function CarService:_seatCharacter(player: Player): boolean
	if not Config.CarEntry.Characters then
		return false
	end
	local car = self.cars[player.UserId]
	local root = Driver.rootOf(player.Character)
	if not car or not car.Parent or not root then
		return false
	end
	root.Anchored = true
	local body = car:FindFirstChild(CarModel.BODY_NAME)
	local bodyCF = if body and body:IsA("BasePart") then body.CFrame else car:GetPivot()
	root.CFrame = Driver.seatRoot(bodyCF, car)
	car:SetAttribute(DRIVER, player.UserId)
	return true
end

-- The avatar out on the road beside a car parked at `parkCF`, and the seat empty.
function CarService:_standCharacter(player: Player, parkCF: CFrame)
	local car = self.cars[player.UserId]
	if car then
		car:SetAttribute(DRIVER, nil)
	end
	local character = player.Character
	local root = Driver.rootOf(character)
	if root then
		root.CFrame = Driver.exitRoot(parkCF, car, character)
		root.Anchored = false
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
end

-- Sit the player in their car NOW, whatever they were doing: a respawn, a run starting, a
-- new avatar. A player who was out is told over `CarEnter`, so their client drives again;
-- one already in is only re-seated, which moves the server's copy of the avatar with the
-- car. Any getting-in or getting-out still going is called off.
function CarService:_seatNow(player: Player, tell: boolean)
	local entry = self.entry[player.UserId]
	local car = self.cars[player.UserId]
	if not entry or not car then
		return
	end
	local wasOut = not entry.driving or entry.busy
	if wasOut then
		entry.gen += 1
		entry.busy = false
		entry.driving = true
		entry.parked = nil
		entry.hold = nil
		if CarParts.isRig(car) and CarParts.describe(car) then
			pcall(CarParts.set, car, Config.CarEntry.DoorName, 0)
		end
		-- The car has not moved since it was parked, but the clock has: the check on the
		-- first packet starts from now, not from when the player got out.
		local seen = self.seen[player.UserId]
		if seen then
			seen.expect = CarService.track(car:GetPivot().Position, os.clock())
			seen.lastVelocity = Vector3.zero
		end
	end
	self:_seatCharacter(player)
	if wasOut and tell then
		self.carEnter:FireClient(player, true, car:GetPivot())
	end
end

-- A new avatar: into the seat. Always -- the player spawns in the car (features/car-v2.md
-- "How it plays"), and an avatar that died walking comes back driving.
function CarService:_onCharacter(player: Player, character: Model)
	task.spawn(function()
		character:WaitForChild("HumanoidRootPart", 10)
		local deadline = os.clock() + 10
		while character.Parent == nil and os.clock() < deadline do
			task.wait()
		end
		-- After the engine has put it at a spawn point, so this is the last word.
		task.wait()
		if player.Character ~= character or not self.cars[player.UserId] then
			return -- replaced already, or no car yet: `Spawn` seats it when the car is made
		end
		self:_seatNow(player, true)
	end)
end

-- GET OUT. `cf` is where the client stopped its car when the button went down. It is
-- believed only if it follows from where the server last agreed the car was -- the same
-- check every `CarState` passes -- and otherwise the car is parked at that agreed place.
-- Refused: no car, not driving (out already, or mid-move), faster than `ExitSpeed`, or
-- asking too often. Accepted: the car is parked and the client told at once; then the
-- door opens, the avatar stands beside it, and the door shuts.
function CarService:_onExit(player: Player, cf: any): (boolean, string?)
	if not self:_entryRateOk(player) then
		return self:_refuse(player, self.carExit, "rate")
	end
	local userId = player.UserId
	local car = self.cars[userId]
	local seen = self.seen[userId]
	local entry = self.entry[userId]
	if not car or not car.Parent or not seen or not seen.expect or not entry then
		return self:_refuse(player, self.carExit, "no car")
	end
	if not entry.driving or entry.busy then
		return self:_refuse(player, self.carExit, "not driving")
	end
	local E = Config.CarEntry
	local v = seen.lastVelocity or Vector3.zero
	if Vector3.new(v.X, 0, v.Z).Magnitude > E.ExitSpeed * E.ExitSpeedTolerance then
		return self:_refuse(player, self.carExit, "too fast")
	end

	local now = os.clock()
	local park: CFrame
	if sane(cf) and CarService.fits(seen.expect, cf.Position, now, self:_numbers(userId)) then
		park = cf
	else
		park = seen.lastCF or car:GetPivot()
	end

	entry.driving = false
	entry.busy = true
	entry.gen += 1
	entry.parked = park
	car:PivotTo(park)
	seen.expect = CarService.track(park.Position, now)
	seen.was, seen.graceUntil = nil, nil
	seen.lastCF, seen.lastVelocity = park, Vector3.zero
	self.exits += 1
	self.carExit:FireClient(player, true, park)

	local gen = entry.gen
	task.spawn(function()
		local opening = self:_door(car, true)
		if opening > 0 then
			task.wait(opening)
		end
		if self.entry[userId] ~= entry or entry.gen ~= gen then
			return
		end
		self:_standCharacter(player, park)
		local shutting = self:_door(car, false)
		if shutting > 0 then
			task.wait(shutting)
		end
		if self.entry[userId] == entry and entry.gen == gen then
			entry.busy = false
		end
	end)
	return true, nil
end

-- GET IN. `car` is the car the player asks to get into, and it has to be THEIRS: another
-- player's car, a car that is not in `Workspace.Cars`, or anything that is not a car is
-- refused. So is a request from further than `PromptDistance` (plus `EnterDistanceSlack`)
-- from the driver's door, one while still driving or mid-move, and one too soon after the
-- last. Accepted: the door opens, the avatar sits, the door shuts, and only then is the
-- client told to drive, from where the car is parked.
function CarService:_onEnter(player: Player, car: any): (boolean, string?)
	if not self:_entryRateOk(player) then
		return self:_refuse(player, self.carEnter, "rate")
	end
	local userId = player.UserId
	local own = self.cars[userId]
	local entry = self.entry[userId]
	if typeof(car) ~= "Instance" or not car:IsA("Model") or car.Parent ~= self.folder then
		return self:_refuse(player, self.carEnter, "no car")
	end
	if car ~= own or car:GetAttribute("UserId") ~= userId then
		return self:_refuse(player, self.carEnter, "not owner")
	end
	if not entry or entry.driving or entry.busy then
		return self:_refuse(player, self.carEnter, "not out")
	end
	local root = Driver.rootOf(player.Character)
	if not root then
		return self:_refuse(player, self.carEnter, "no character")
	end
	local E = Config.CarEntry
	local park = entry.parked or car:GetPivot()
	local door = Driver.doorPoint(park, car)
	if (root.Position - door).Magnitude > E.PromptDistance + E.EnterDistanceSlack then
		return self:_refuse(player, self.carEnter, "too far")
	end

	entry.busy = true
	entry.gen += 1
	self.enters += 1
	local gen = entry.gen
	task.spawn(function()
		local opening = self:_door(car, true)
		if opening > 0 then
			task.wait(opening)
		end
		if self.entry[userId] ~= entry or entry.gen ~= gen then
			return
		end
		self:_seatCharacter(player)
		local shutting = self:_door(car, false)
		if shutting > 0 then
			task.wait(shutting)
		end
		if self.entry[userId] ~= entry or entry.gen ~= gen then
			return
		end
		entry.driving = true
		entry.busy = false
		entry.parked = nil
		local seen = self.seen[userId]
		if seen then
			seen.expect = CarService.track(park.Position, os.clock())
			seen.was, seen.graceUntil = nil, nil
			seen.lastCF, seen.lastVelocity = park, Vector3.zero
		end
		self.carEnter:FireClient(player, true, park)
	end)
	return true, nil
end

-- Studio only: the two requests, through the real handlers, with no client. `userId` nil
-- takes the first player.
local function playerFor(userId: number?): Player?
	for _, player in Players:GetPlayers() do
		if userId == nil or player.UserId == userId then
			return player
		end
	end
	return nil
end

function CarService:DebugExit(cf: CFrame?, userId: number?)
	local player = playerFor(userId)
	if not player then
		return { ok = false, reason = "no player" }
	end
	local ok, reason = self:_onExit(player, cf)
	return { ok = ok, reason = reason }
end

function CarService:DebugEnter(car: Instance?, userId: number?)
	local player = playerFor(userId)
	if not player then
		return { ok = false, reason = "no player" }
	end
	local ok, reason = self:_onEnter(player, car or self.cars[player.UserId])
	return { ok = ok, reason = reason }
end

function CarService:DebugClearEntryLimits()
	table.clear(self.entryRate)
	return true
end

-- Who is where, for one player: the server's side of getting in and out.
function CarService:EntryState(userId: number)
	local entry = self.entry[userId]
	local car = self.cars[userId]
	local player = Players:GetPlayerByUserId(userId)
	local root = player and Driver.rootOf(player.Character)
	return {
		hasCar = car ~= nil,
		driving = entry ~= nil and entry.driving or false,
		busy = entry ~= nil and entry.busy or false,
		driver = car and car:GetAttribute(DRIVER) or nil,
		parked = entry and entry.parked and entry.parked.Position or nil,
		carAt = car and car:GetPivot().Position or nil,
		rootAnchored = root and root.Anchored or nil,
		rootAt = root and root.Position or nil,
		door = car and Driver.doorPoint(entry and entry.parked or car:GetPivot(), car) or nil,
	}
end

--------------------------------------------------------------------------------
-- Held by the server (T-103, the garage visit)
--------------------------------------------------------------------------------
-- The server parking a car where IT chose, with the driver still in the seat: the garage's
-- turntable. Nothing the client sends moves a held car -- every `CarState` is dropped, as
-- for a parked one -- and neither getting out nor getting in is open (`_onExit` refuses
-- "not driving", `_onEnter` "not out"). `MoveHeld` is how the holder turns it, and
-- `Release` hands it back to its driver at a pose the holder chose. A respawn, a `Place`
-- or a new car calls the hold off (`CarMoved`): the holder hears it and lets go.

-- Hold `player`'s car at `cf`, a pose the server chose (never one off the wire). `tag` says
-- who holds it. False with a reason: no car, not driving (out, mid-move, or held already).
function CarService:Hold(player: Player, cf: CFrame, tag: string): (boolean, string?)
	if not sane(cf) then
		return false, "bad pose"
	end
	local userId = player.UserId
	local car = self.cars[userId]
	local seen = self.seen[userId]
	local entry = self.entry[userId]
	if not car or not car.Parent or not seen or not entry then
		return false, "no car"
	end
	if not entry.driving or entry.busy then
		return false, "not driving"
	end
	entry.driving = false
	entry.busy = true
	entry.gen += 1
	entry.hold = tag
	entry.parked = cf
	car:PivotTo(cf)
	seen.expect = CarService.track(cf.Position, os.clock())
	seen.was, seen.graceUntil = nil, nil
	seen.lastCF, seen.lastVelocity = cf, Vector3.zero
	self:_seatCharacter(player)
	self.holds += 1
	return true, nil
end

-- Who holds this player's car, or nil.
function CarService:HeldBy(player: Player): string?
	local entry = self.entry[player.UserId]
	return entry and entry.hold or nil
end

-- Move a held car (the turntable turning it). The avatar goes with it. `tellOthers` passes
-- the pose on to the other players as a `CarStateOther`, at rest, so they see it turn.
function CarService:MoveHeld(player: Player, cf: CFrame, tellOthers: boolean?): boolean
	local userId = player.UserId
	local entry = self.entry[userId]
	local car = self.cars[userId]
	if not entry or not entry.hold or not car or not sane(cf) then
		return false
	end
	entry.parked = cf
	car:PivotTo(cf)
	local seen = self.seen[userId]
	if seen then
		seen.expect = CarService.track(cf.Position, os.clock())
		seen.lastCF = cf
	end
	self:_seatCharacter(player)
	if tellOthers then
		for _, other in Players:GetPlayers() do
			if other ~= player then
				self.carStateOther:FireClient(other, userId, cf, Vector3.zero, false)
			end
		end
	end
	return true
end

-- Hand a held car back to its driver at `cf`, at rest: the server agrees the car is there,
-- and the next `CarState` is checked from it. Returns the pose, or nil if it was not held.
function CarService:Release(player: Player, cf: CFrame): CFrame?
	local userId = player.UserId
	local entry = self.entry[userId]
	local car = self.cars[userId]
	if not entry or not entry.hold or not car or not sane(cf) then
		return nil
	end
	entry.hold = nil
	entry.parked = nil
	entry.gen += 1
	entry.busy = false
	entry.driving = true
	car:PivotTo(cf)
	local seen = self.seen[userId]
	if seen then
		seen.expect = CarService.track(cf.Position, os.clock())
		seen.was, seen.graceUntil = nil, nil
		seen.lastCF, seen.lastVelocity = cf, Vector3.zero
	end
	self:_seatCharacter(player)
	self.releases += 1
	return cf
end

function CarService:DebugState()
	local cars = {}
	local offenders = {}
	local road = liveRoad()
	for userId, car in self.cars do
		local seen = self.seen[userId]
		local key = self.carKeys[userId] or Cars.Default
		local numbers = self:_numbersFor(userId, key)
		table.insert(cars, {
			userId = userId,
			name = car.Name,
			position = car:GetPivot().Position,
			expected = seen and seen.expect and seen.expect.position or nil,
			-- Which world the server believes this car is in, which is what a respawn
			-- reads (T-026).
			world = self:WorldAt(self:BelievedPosition(userId) or car:GetPivot().Position),
			-- Whether the ROSTER has them in a run, which is not the same question as
			-- which world they are standing in: a car that has fallen off the road is
			-- still in the run (T-044).
			inRun = road ~= nil and road:InRun(Players:GetPlayerByUserId(userId)) or false,
			dropped = seen and seen.dropped or 0,
			-- The whole of T-033 in three fields: the car the SERVER says this player is
			-- in, the speed it will take from them, and the shape it has dressed them in.
			car = key,
			topSpeed = numbers and numbers.TopSpeed or nil,
			maxReportedSpeed = (numbers and numbers.TopSpeed or 0) * Config.Drift.StateSpeedTolerance,
			body = car:GetAttribute("Body"),
			switchGrace = seen and seen.carWas ~= nil and math.max((seen.carGraceUntil or 0) - os.clock(), 0) or 0,
			-- Who is in it (T-096): the `Driver` attribute, whether the server has them
			-- driving, and mid-way in or out.
			driver = car:GetAttribute(DRIVER),
			driving = self.entry[userId] ~= nil and self.entry[userId].driving or false,
			entryBusy = self.entry[userId] ~= nil and self.entry[userId].busy or false,
			-- Who holds the car, if the server does (T-103): "garage" on the turntable.
			heldBy = self.entry[userId] ~= nil and self.entry[userId].hold or nil,
		})
		for _, problem in CarModel.physicsOffenders(car) do
			table.insert(offenders, problem)
		end
	end
	local worlds = {}
	for name, cf in worldSpawns() do
		worlds[name] = cf.Position
	end
	return {
		cars = cars,
		carCount = #cars,
		spawn = self:SpawnCFrame().Position,
		-- Every world this place has right now, and which one a car starts in (T-026).
		-- `road` is in `worlds` only while a run is going, and is never `startWorld`.
		worlds = worlds,
		startWorld = Config.Drift.StartWorld,
		roadUp = liveRoad() ~= nil,
		droppedStates = self.dropped,
		respawns = self.respawns,
		respawnsRefused = self.respawnsRefused,
		inFlightKept = self.inFlightKept,
		switches = self.switches,
		switchesRefused = self.switchesRefused,
		switchInFlightKept = self.switchInFlightKept,
		buildSets = self.buildSets, -- fitted builds handed over for the bounds (T-106)
		charactersOff = not Players.CharacterAutoLoads,
		physicsOffenders = offenders,
		exits = self.exits,
		enters = self.enters,
		exitsRefused = self.exitsRefused,
		entersRefused = self.entersRefused,
		refusals = table.clone(self.refusals),
		parkedDropped = self.parkedDropped,
	}
end

-- Studio only: the way across. A place has two worlds and they are 12 000 studs apart,
-- which is not drivable and is not meant to be, so this puts the car down in the OTHER
-- one -- or in `world` by name -- through the same path a respawn takes: the server
-- chooses the place, moves its own copy, records it as where it expects the car, and
-- tells the client, which is what moves the car the player is actually driving.
--
-- Deliberately a bridge method and not a button: this is a dev convenience, not a
-- feature, and nothing in the game offers it.
function CarService:DebugCross(world: string?, userId: number?)
	for _, player in Players:GetPlayers() do
		if userId == nil or player.UserId == userId then
			local believed = self:BelievedPosition(player.UserId)
			local from = believed and self:WorldAt(believed) or Config.Drift.StartWorld
			local to = world
			if not to then
				to = if from == WORLD_TRACK then WORLD_PLAYGROUND else WORLD_TRACK
			end
			local spawns = worldSpawns()
			if not spawns[to] then
				return { crossed = false, from = from, to = to, reason = `this place has no '{to}'` }
			end
			-- The cooldown is there to stop a client asking twice; a Studio hop is not a
			-- client, and waiting half a second for it only hides what is being measured.
			local cf = self:Place(player, spawns[to])
			return {
				crossed = cf ~= nil,
				from = from,
				to = to,
				at = cf and cf.Position or nil,
				ground = cf and self:DebugGroundUnder(cf.Position) or nil,
			}
		end
	end
	return { crossed = false, reason = "no player" }
end

-- Studio only: is there drivable ground under this point, and how far down? The crossing
-- quotes it, because a hop that puts the car over the void is not a hop that worked.
--
-- Filtered the way the CAR's ground rays are (`Drift/World.live`): an INCLUDE list of
-- everything tagged, not "whatever is solid". The difference matters -- the Studio
-- default SpawnLocation sits untagged on the track at the origin, and an exclude ray
-- lands on it and reports ground the car cannot see.
function CarService:DebugGroundUnder(position: Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged(Config.Drift.SurfaceTag)
	local up = Config.Drift.GroundRayUp
	local hit = workspace:Raycast(position + Vector3.new(0, up, 0), Vector3.new(0, -Config.Drift.GroundRayLength, 0), params)
	if not hit then
		return { hit = false, surfaces = #params.FilterDescendantsInstances }
	end
	return {
		hit = true,
		part = hit.Instance.Name,
		drop = math.round((position.Y - hit.Position.Y) * 1000) / 1000,
		surface = hit.Instance:GetAttribute(Config.Drift.SurfaceAttribute),
	}
end

-- Studio only: tell the server it has agreed this car is here.
--
-- WHY A TEST NEEDS THIS. Where the server believes a car is, is the last `CarState` it
-- accepted -- and a test with no client cannot send one, because the movement check would
-- quite rightly refuse a car that covered three hundred studs between two calls in the
-- same frame. Every question about which world a car is in, and about where a fall puts
-- it, hangs off that one position, so a test that cannot set it cannot ask any of them.
-- This sets it the same way a spawn and a respawn do -- through `_expect`, so the grace
-- and the counters behave exactly as they do in play -- and it is the SERVER writing its
-- own belief, not a client proposing one. Nothing in the game calls it.
function CarService:DebugBelieve(userId: number, position: Vector3)
	assert(RunService:IsStudio(), "DebugBelieve is Studio only")
	self:_expect(userId, position)
	return self:BelievedPosition(userId)
end

-- Studio only: respawn a player's car exactly as a request does, with no client involved.
function CarService:DebugRespawn(userId: number?): Vector3?
	for _, player in Players:GetPlayers() do
		if userId == nil or player.UserId == userId then
			local cf = self:Respawn(player)
			return cf and cf.Position or nil
		end
	end
	return nil
end

return CarService
