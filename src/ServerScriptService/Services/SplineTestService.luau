--!nonstrict
-- SplineTestService: a spline road to drive in Studio before the run uses it
-- (features/spline-road.md "Testing", T-134). STUDIO ONLY: outside Studio it does nothing
-- and makes no remote.
--
-- Steps 2 and 3 of the spline road can only be judged by driving them, and the run does not
-- lay a spline road until step 4. So this lays one on its own, far from everything else
-- (`Config.Spline.TestOrigin`), and puts the player's car on it:
--
--   * THE SERVER CHOOSES IT AND THE CLIENT REPLAYS IT, exactly as the real thing will: the
--     client is sent the generator's sections and builds its own copy of the curve, which
--     its car then drives on through `Drift/SplineWorld`. The car never touches a part.
--   * WHAT YOU SEE IS A STAND-IN until step 3's mesh: the same road laid as parts that
--     nothing can collide with or query (`Road/SplineParts`).
--   * A FALL PUTS YOU BACK ON IT (`SafeStart`), as a fall on the piece road does, through
--     the one question `CarService:Respawn` asks first.
--
-- The client may send exactly two things on `SplineTest`: nil ("what is the state?") and
-- "toggle". It never sends a seed, a place or a section.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local SplineParts = require(ReplicatedStorage.Shared.Road.SplineParts)

local SplineTestService = {}
SplineTestService.Priority = 0

local COOLDOWN = 1 -- seconds between two toggles that land

local function service(name: string): any?
	local module = script.Parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, svc = pcall(require, module)
	return if ok then svc else nil
end

function SplineTestService:Init()
	self.enabled = RunService:IsStudio()
	self.drivers = {} -- [userId] = true
	self.lastToggle = {} -- [userId] = os.clock()
	self.gen = nil
	self.folder = nil
	self.builds = 0
	self.refused = 0
	if not self.enabled then
		return
	end
	self.remote = Net.event("SplineTest")
end

function SplineTestService:Start()
	if not self.enabled then
		return
	end
	self.remote.OnServerEvent:Connect(function(player, what)
		self:_onAsk(player, what)
	end)
	Players.PlayerRemoving:Connect(function(player)
		if self.drivers[player.UserId] then
			self.drivers[player.UserId] = nil
			self:_tearDownIfEmpty()
		end
	end)
end

function SplineTestService:InTest(player: Player): boolean
	return self.drivers ~= nil and self.drivers[player.UserId] == true and self.gen ~= nil
end

-- Where a car on the test road goes back to: the nearest point of the road to where it was,
-- on the centre line, facing along it. Never the first or last 30 studs.
function SplineTestService:SafeStart(position: Vector3?): CFrame?
	local gen = self.gen
	if not gen then
		return nil
	end
	local spline = gen.spline
	local s = 20
	if position then
		local found = spline:project(position.X, position.Z, Config.Road.Width * 0.5 + 400)
		if found then
			s = found
		end
	end
	s = math.clamp(s, 20, spline.length - 30)
	local x, y, z = spline:surfaceXYZ(s, 0)
	return CFrame.new(x, y + Config.Drift.RideHeight, z) * CFrame.Angles(0, spline:yawAt(s), 0)
end

function SplineTestService:_build()
	local C = Config.Spline
	local seed = (os.time() * 7919 + self.builds * 104729) % 1000000
	self.builds += 1
	local o = C.TestOrigin
	local gen = SplineGen.new(seed, { x = o.X, y = o.Y, z = o.Z, yaw = math.rad(Config.Road.StartHeading) })
	gen:extendTo(C.TestLength)
	local folder = Instance.new("Folder")
	folder.Name = "SplineTestRoad"
	folder:SetAttribute("Seed", seed)
	folder.Parent = Workspace
	SplineParts.build(gen.spline, 0, gen.spline.length, folder, { step = C.TestStandInStep, queryable = false, yieldEvery = 60 })
	self.gen = gen
	self.folder = folder
end

function SplineTestService:_tearDownIfEmpty()
	if next(self.drivers) ~= nil then
		return
	end
	if self.folder then
		self.folder:Destroy()
	end
	self.folder = nil
	self.gen = nil
end

function SplineTestService:_state(player: Player)
	local gen = self.gen
	local on = self:InTest(player)
	local o = gen and gen.spline.origin
	return {
		on = on,
		seed = gen and gen.seed or nil,
		origin = if on and o then { x = o.x, y = o.y, z = o.z, yaw = o.yaw } else nil,
		sections = if on and gen then gen.sections else nil,
	}
end

function SplineTestService:_tell(player: Player)
	self.remote:FireClient(player, self:_state(player))
end

function SplineTestService:_onAsk(player: Player, what: any)
	if what == nil then
		self:_tell(player)
		return
	end
	if what ~= "toggle" then
		self.refused += 1
		self:_tell(player)
		return
	end
	local now = os.clock()
	if now - (self.lastToggle[player.UserId] or -math.huge) < COOLDOWN then
		self.refused += 1
		self:_tell(player)
		return
	end
	self.lastToggle[player.UserId] = now
	if self.drivers[player.UserId] then
		self:Leave(player)
	else
		self:Join(player)
	end
end

function SplineTestService:Join(player: Player): boolean
	local cars = service("CarService")
	local road = service("RoadService")
	if not cars then
		return false
	end
	-- not from inside a run: the run's roster would still have them
	if road and type(road.InRun) == "function" and road:InRun(player) then
		self.refused += 1
		self:_tell(player)
		return false
	end
	if not self.gen then
		self:_build()
	end
	self.drivers[player.UserId] = true
	-- the road first, then the car: the client must have its world before it lands on it
	self:_tell(player)
	cars:Place(player, self:SafeStart(nil))
	return true
end

function SplineTestService:Leave(player: Player)
	local cars = service("CarService")
	self.drivers[player.UserId] = nil
	if cars then
		cars:Place(player, cars:SpawnCFrameIn(Config.Drift.StartWorld))
	end
	self:_tell(player)
	self:_tearDownIfEmpty()
end

function SplineTestService:DebugState()
	local n = 0
	for _ in self.drivers do
		n += 1
	end
	return {
		enabled = self.enabled,
		up = self.gen ~= nil,
		seed = self.gen and self.gen.seed or nil,
		length = self.gen and self.gen.spline.length or 0,
		sections = self.gen and #self.gen.sections or 0,
		parts = self.folder and #self.folder:GetDescendants() or 0,
		drivers = n,
		refused = self.refused,
	}
end

-- Join or leave for a player with no client button to press (tests, the debug bridge).
function SplineTestService:DebugToggle(userId: number?)
	local player = if userId then Players:GetPlayerByUserId(userId) else Players:GetPlayers()[1]
	if not player then
		return "no player"
	end
	self.lastToggle[player.UserId] = nil
	self:_onAsk(player, "toggle")
	return self:DebugState()
end

return SplineTestService
