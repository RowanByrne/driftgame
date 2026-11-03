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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
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

-- Is this a speed the model could be going at? Horizontal and vertical are bounded by
-- different things -- top speed across the ground, terminal velocity down -- so they are
-- checked apart. Checking the magnitude of the two together rejects every honest packet
-- from a car that has driven off the world, which happens in normal play.
function CarService.speedFits(velocity: Vector3): boolean
	local C = Config.Drift
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude <= C.TopSpeed * C.StateSpeedTolerance
		and math.abs(velocity.Y) <= C.TerminalFall * C.StateSpeedTolerance
end

-- Could a car on `track` be at `position` by `now`? The same split, applied to the
-- distance covered since the track was last agreed. Pure, so the tests drive it with no
-- player and no playtest (Tests/DriftTests).
function CarService.fits(track: Track, position: Vector3, now: number): boolean
	local C = Config.Drift
	local budget = math.max(now - track.at, 1 / 1000) * C.StateMoveTolerance
	local moved = position - track.position
	return Vector3.new(moved.X, 0, moved.Z).Magnitude
			<= C.TopSpeed * C.StateSpeedTolerance * budget + C.StateMoveAllowance
		and math.abs(moved.Y) <= C.TerminalFall * C.StateSpeedTolerance * budget + C.StateMoveAllowance
end

function CarService:Init()
	self.cars = {} -- userId -> Model
	self.seen = {} -- userId -> { expect: Track, was: Track?, graceUntil, window, count, dropped, ... }
	self.dropped = 0
	self.respawns = 0
	self.respawnsRefused = 0
	self.inFlightKept = 0

	local folder = workspace:FindFirstChild("Cars")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Cars"
		folder.Parent = workspace
	end
	self.folder = folder

	self.carSpawn = Net.event("CarSpawn")
	self.carRespawn = Net.event("CarRespawn")
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
end

-- Where a car starts, and where every respawn puts it back. The playground owns its own
-- named spots; with no playground (a lane place with only a baseplate) the car starts
-- above the origin instead (docs/game/WORLD.md "Named spots").
function CarService:SpawnCFrame(): CFrame
	local services = ServerScriptService:FindFirstChild("Services")
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

function CarService:Spawn(player: Player): Model?
	self:Despawn(player)

	local spawnCFrame = self:SpawnCFrame()
	local car = CarModel.build()
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

	if not CarService.speedFits(velocity) then
		self:_drop(seen)
		return
	end

	if seen.was and now >= (seen.graceUntil or 0) then
		seen.was = nil -- the grace is over: only where the server put the car counts now
		seen.graceUntil = nil
	end

	if CarService.fits(seen.expect, cf.Position, now) then
		seen.expect = CarService.track(cf.Position, now)
	elseif seen.was and CarService.fits(seen.was, cf.Position, now) then
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
		table.insert(cars, {
			userId = userId,
			name = car.Name,
			position = car:GetPivot().Position,
			expected = seen and seen.expect and seen.expect.position or nil,
			dropped = seen and seen.dropped or 0,
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
