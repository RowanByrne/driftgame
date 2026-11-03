--!nonstrict
-- CarService: spawning, despawning, and passing each car's state to the other players.
--
-- The server does not simulate the car. Feel cannot survive a round trip, so the client
-- that drives a car moves it, and this service only owns where a car comes from and who
-- gets told about it (docs/game/features/drift-model.md "Server and client").
--
-- That is the whole contract while nothing is scored, sold or saved. Before any of those
-- exist, the server has to check each reported state against what the model allows; the
-- checks below are the shape of it, not the whole of it, and they drop rather than kick
-- (docs/game/CONTRACTS.md, `CarState`).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local CarService = {}

CarService.Priority = 50 -- remotes exist before any controller asks for them

local RATE_LIMIT_PER_SECOND = 30

function CarService:Init()
	self.cars = {} -- userId -> Model
	self.seen = {} -- userId -> { last, count, window, dropped }
	self.dropped = 0

	local folder = workspace:FindFirstChild("Cars")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Cars"
		folder.Parent = workspace
	end
	self.folder = folder

	self.carSpawn = Net.event("CarSpawn")
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
end

-- Where a car starts. The playground owns its own named spots; with no playground (a lane
-- place with only a baseplate) the car starts above the origin instead
-- (docs/game/WORLD.md "Named spots").
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
	self.carSpawn:FireClient(player, car, spawnCFrame)
	return car
end

function CarService:Despawn(player: Player)
	local car = self.cars[player.UserId]
	if car then
		car:Destroy()
	end
	self.cars[player.UserId] = nil
	self.seen[player.UserId] = nil
end

function CarService:_onState(player: Player, cf, velocity, drifting)
	if typeof(cf) ~= "CFrame" or typeof(velocity) ~= "Vector3" or type(drifting) ~= "boolean" then
		self.dropped += 1
		return
	end

	local C = Config.Drift
	local now = os.clock()
	local seen = self.seen[player.UserId]
	if not seen then
		seen = { last = now, window = now, count = 0, position = cf.Position }
		self.seen[player.UserId] = seen
	end

	-- Rate limit, keyed by UserId so rejoining does not reset it.
	if now - seen.window >= 1 then
		seen.window = now
		seen.count = 0
	end
	seen.count += 1
	if seen.count > RATE_LIMIT_PER_SECOND then
		self.dropped += 1
		return
	end

	local elapsed = math.max(now - seen.last, 1 / 1000)
	local maxSpeed = C.TopSpeed * 1.25
	if velocity.Magnitude > maxSpeed then
		self.dropped += 1
		return
	end
	if (cf.Position - seen.position).Magnitude > maxSpeed * elapsed * 1.5 + C.TopSpeed * 0.1 then
		self.dropped += 1
		return
	end

	seen.last = now
	seen.position = cf.Position

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
		table.insert(cars, { userId = userId, name = car.Name, position = car:GetPivot().Position })
		for _, problem in CarModel.physicsOffenders(car) do
			table.insert(offenders, problem)
		end
	end
	return {
		cars = cars,
		carCount = #cars,
		spawn = self:SpawnCFrame().Position,
		droppedStates = self.dropped,
		charactersOff = not Players.CharacterAutoLoads,
		physicsOffenders = offenders,
	}
end

return CarService
