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

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

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
	self.dropped = 0
	self.respawns = 0
	self.respawnsRefused = 0
	self.inFlightKept = 0
	self.switches = 0
	self.switchesRefused = 0
	self.switchInFlightKept = 0
	self.dressing = false -- one car dressed at a time: dressing flips the active car

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
end

function CarService:Start()
	if Config.Drift.HideCharacter then
		-- The player is the car. No character means no Humanoid to fight the simulation,
		-- no default touch thumbstick over our own, and nothing physical in the world.
		Players.CharacterAutoLoads = false
		for _, player in Players:GetPlayers() do
			if player.Character then
				player.Character:Destroy()
			end
		end
	end

	Players.PlayerAdded:Connect(function(player)
		self:Spawn(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:Despawn(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:Spawn(player)
		end)
	end

	self.carState.OnServerEvent:Connect(function(player, cf, velocity, drifting)
		self:_onState(player, cf, velocity, drifting)
	end)
	self.carRespawn.OnServerEvent:Connect(function(player)
		-- No payload: there is nothing for the client to say. It asks, the server picks.
		self:Respawn(player)
	end)
	self.carSwitch.OnServerEvent:Connect(function(player, key)
		self:_onSwitch(player, key)
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
function CarService:_numbers(userId: number): { [string]: any }?
	return Cars.resolve(self.carKeys[userId] or Cars.Default)
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
		seen.carWas = Cars.resolve(was)
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
end

function CarService:_drop(seen)
	self.dropped += 1
	if seen then
		seen.dropped = (seen.dropped or 0) + 1
	end
end

function CarService:_onState(player: Player, cf, velocity, drifting)
	local seen = self.seen[player.UserId]
	if typeof(cf) ~= "CFrame" or typeof(velocity) ~= "Vector3" or type(drifting) ~= "boolean" then
		self:_drop(seen)
		return
	end
	if not seen or not seen.expect then
		-- The server has not put a car anywhere for this player, so there is nothing to
		-- check the packet against.
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
			self.carStateOther:FireClient(other, player.UserId, cf, velocity, drifting)
		end
	end
end

function CarService:DebugState()
	local cars = {}
	local offenders = {}
	local road = liveRoad()
	for userId, car in self.cars do
		local seen = self.seen[userId]
		local key = self.carKeys[userId] or Cars.Default
		local numbers = Cars.resolve(key)
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
		charactersOff = not Players.CharacterAutoLoads,
		physicsOffenders = offenders,
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
