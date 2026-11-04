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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

	local folder = workspace:FindFirstChild("Cars")
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

-- Where a car starts, and where every respawn puts it back. The playground owns its own
-- named spots; with no playground (a lane place with only a baseplate) the car starts
-- above the origin instead (docs/game/WORLD.md "Named spots").
function CarService:SpawnCFrame(): CFrame
	local services = ServerScriptService:FindFirstChild("Services")
	-- A hand-placed track owns the spawn when the place has one: the playground was never
	-- built, so its spots do not exist (TrackService, T-031).
	local trackModule = services and services:FindFirstChild("TrackService")
	if trackModule and trackModule:IsA("ModuleScript") then
		local ok, track = pcall(require, trackModule)
		if ok and type(track) == "table" and type(track.SpawnCFrame) == "function" then
			local gotSpawn, cf = pcall(track.SpawnCFrame, track)
			if gotSpawn and typeof(cf) == "CFrame" then
				return cf
			end
		end
	end
	local module = services and services:FindFirstChild("PlaygroundService")
	if module and module:IsA("ModuleScript") then
		local ok, playground = pcall(require, module)
		if ok and type(playground) == "table" and type(playground.GetSpot) == "function" then
			local gotSpot, spot = pcall(playground.GetSpot, playground, "Spawn")
			if gotSpot and typeof(spot) == "CFrame" then
				return spot
			end
		end
	end
	return CFrame.new(0, Config.Drift.RideHeight, 0)
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
function CarService:Respawn(player: Player): CFrame?
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

	local cf = self:SpawnCFrame()
	car:PivotTo(cf)
	seen = self:_expect(player.UserId, cf.Position)
	seen.respawnedAt = os.clock()
	self.respawns += 1
	self.carRespawn:FireClient(player, cf)
	return cf
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
	for userId, car in self.cars do
		local seen = self.seen[userId]
		local key = self.carKeys[userId] or Cars.Default
		local numbers = Cars.resolve(key)
		table.insert(cars, {
			userId = userId,
			name = car.Name,
			position = car:GetPivot().Position,
			expected = seen and seen.expect and seen.expect.position or nil,
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
	return {
		cars = cars,
		carCount = #cars,
		spawn = self:SpawnCFrame().Position,
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
