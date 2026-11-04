--!nonstrict
-- DriftController: the drift model's lifecycle on the client that drives the car.
--
-- The model itself is Drift/Model; the fixed step is Drift/Sim; the Workspace queries are
-- Drift/World; drawing is Drift/Render. This module is only the wiring: take the car the
-- server spawned, read the input once a frame, spend the frame in whole simulation steps,
-- put the car where the model says, and tell the server at 20 Hz.
--
-- One thing this module does not do is decide where the car goes. A car that has fallen
-- off the world asks the server for a respawn and waits for the position it sends back
-- (`CarRespawn`); moving itself would be indistinguishable from a cheat, and the server
-- rejects it as one (ServerScriptService/Services/CarService).
--
-- Roblox physics never touches the car (docs/game/DECISIONS.md, 2026-11-03). Every part is
-- anchored and its CFrame is written from the simulation; there is no BodyMover, no force
-- and no constraint anywhere in the car.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local DebugHud = require(DriftFolder.DebugHud)
local DriftModel = require(DriftFolder.Model)
local RemoteCars = require(DriftFolder.RemoteCars)
local Render = require(DriftFolder.Render)
local Sim = require(DriftFolder.Sim)
local World = require(DriftFolder.World)

local CarInputController = require(script.Parent.CarInputController)

local DriftController = {}

DriftController.Priority = 10 -- after CarInputController (20), before the camera (5)

local STEP_NAME = "DriftSim"

function DriftController:Init()
	self.runner = nil
	self.rig = nil
	self.car = nil
	self.spawnCFrame = CFrame.new(0, Config.Drift.RideHeight, 0)
	self.frameSeconds = 0
	self.sendClock = 0
	self.respawns = 0
	self.respawnsAsked = 0
	self.awaitingRespawn = false
	self.askedAt = 0
	self._carSpawn = Net.event("CarSpawn")
	self._carRespawn = Net.event("CarRespawn")
	self._carState = Net.unreliable("CarState")
	self._carStateOther = Net.unreliable("CarStateOther")
end

function DriftController:Start()
	local carsFolder = workspace:WaitForChild("Cars", 30)
	if not carsFolder then
		warn("[DriftController] Workspace.Cars never appeared; is CarService running?")
		carsFolder = Instance.new("Folder")
		carsFolder.Name = "Cars"
		carsFolder.Parent = workspace
	end
	self.world = World.live({ carsFolder })
	self.remoteCars = RemoteCars.new(carsFolder, nil)

	if Config.Drift.DebugReadout then
		self.hud = DebugHud.new()
		CarInputController.DebugToggled:Connect(function()
			self.hud:Toggle()
		end)
	end

	self._carSpawn.OnClientEvent:Connect(function(car, spawnCFrame)
		self:_attach(car, spawnCFrame)
	end)

	self._carRespawn.OnClientEvent:Connect(function(cf)
		self:_placeAt(cf)
	end)

	self._carStateOther.OnClientEvent:Connect(function(userId, cf, velocity, drifting)
		if type(userId) == "number" and typeof(cf) == "CFrame" then
			self.remoteCars:OnState(userId, cf, velocity, drifting)
		end
	end)

	-- CarSpawn can fire before this controller is listening, and the car model can
	-- replicate after it. Either way the car is picked up: the folder is the backstop.
	local function claim(child: Instance)
		if self.car then
			return
		end
		if child:IsA("Model") and child:GetAttribute("UserId") == Players.LocalPlayer.UserId then
			self:_attach(child, child:GetPivot())
		end
	end
	carsFolder.ChildAdded:Connect(claim)
	for _, child in carsFolder:GetChildren() do
		claim(child)
	end

	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Input.Value + 1, function(dt)
		self:_frame(dt)
	end)
end

function DriftController:_attach(car: Model, spawnCFrame: CFrame)
	if typeof(spawnCFrame) ~= "CFrame" or not car or not car:IsA("Model") then
		warn("[DriftController] CarSpawn arrived without a car and a CFrame")
		return
	end
	self.spawnCFrame = spawnCFrame
	if self.car == car and self.runner then
		return -- already driving it; the folder and the remote both found the same car
	end
	self.car = car
	self.rig = Render.rig(car)
	self.runner = Sim.newRunner(spawnCFrame)
	self.remoteCars:SetOwnCar(car)
	Render.apply(self.rig, self.runner.state)
end

-- Ask the server to put the car back. The car keeps falling until the answer comes: it is
-- the server that decides where a respawned car goes, and a client that helps itself is a
-- client the server cannot tell from a cheat. Asking again is held off for
-- `RespawnAnswerWait`, so one long fall is one request and not one a frame, and a lost
-- answer still gets the car back.
function DriftController:_askForRespawn()
	if not self.runner then
		return
	end
	local now = os.clock()
	if self.awaitingRespawn and now - self.askedAt < Config.Drift.RespawnAnswerWait then
		return
	end
	self.awaitingRespawn = true
	self.askedAt = now
	self.respawnsAsked += 1
	self._carRespawn:FireServer()
end

-- The answer: the server has moved the car, and this is where it is.
function DriftController:_placeAt(cf: CFrame)
	if typeof(cf) ~= "CFrame" then
		warn("[DriftController] CarRespawn arrived without a CFrame")
		return
	end
	self.awaitingRespawn = false
	self.spawnCFrame = cf
	if not self.runner then
		return
	end
	self.runner = Sim.newRunner(cf)
	self.respawns += 1
	if self.rig then
		Render.apply(self.rig, self.runner.state)
	end
end

function DriftController:_frame(dt: number)
	self.frameSeconds = dt
	if not self.runner then
		if self.hud then
			self.hud:Update(nil, nil)
		end
		return
	end

	-- The model wants one number and a handbrake, and that is exactly what the input
	-- controller answers now (T-013): `steer` is the car's rate of turn as a share of
	-- `MaxSteeringSpeed`, and the handbrake only stops the car once a run is over. There
	-- is no drift input left -- rotating is drifting.
	local input = CarInputController:Get()
	local steps = Sim.advance(self.runner, dt, input, self.world)
	local state = self.runner.state

	if state.fell then
		self:_askForRespawn()
	end

	if self.rig then
		Render.apply(self.rig, state)
	end
	self.remoteCars:Update(dt)

	-- One packet a frame at most, and never a backlog: a frame that took a second (the
	-- first few, while the place is still loading) must not be paid back as a burst of
	-- sends at frame rate, which is a burst the server's rate limit drops.
	local period = 1 / math.max(Config.Drift.StateSendRate, 1)
	self.sendClock = math.min(self.sendClock + dt, period)
	if self.sendClock >= period then
		self.sendClock -= period
		if not self.awaitingRespawn then
			-- Nothing is sent between asking and being put back. Where the car is while
			-- it waits is of no interest to anyone, and the fewer packets in flight over
			-- a respawn, the less the server has to forgive on the other side of it.
			self:_send(state)
		end
	end

	if self.hud then
		self.hud:Update(state, {
			steps = steps,
			frameSeconds = dt,
			steerInput = input.steer,
			handbrake = input.handbrake,
			device = CarInputController:Device(),
			surfaceTag = self.world.usingTag,
		})
	end
end

function DriftController:_send(state)
	-- `drifting` is read off the car, not off the input: rotating is drifting, and there
	-- is no drift input left to report (Config.Drift.MinSlipAngleForDrift).
	self._carState:FireServer(DriftModel.cframe(state), state.velocity, state.drifting)
end

-- The camera asks for this every frame (docs/game/ARCHITECTURE.md "Studio tools").
function DriftController:CurrentState()
	return self.runner and self.runner.state or nil
end

function DriftController:Car(): Model?
	return self.car
end

-- The model's full state, for tests and agent playtests.
function DriftController:DebugState()
	local s = self:CurrentState()
	if not s then
		return { hasCar = false, spawn = self.spawnCFrame.Position, awaitingRespawn = self.awaitingRespawn }
	end
	return {
		hasCar = true,
		position = s.position,
		headingDeg = math.deg(s.yaw) % 360,
		speed = DriftModel.speed(s),
		velocity = s.velocity,
		forwardSpeed = s.u,
		lateralSpeed = s.v,
		yawRate = s.r, -- rad/s, and it IS the finger times MaxSteeringSpeed
		verticalSpeed = s.vy,
		slipDeg = math.deg(s.slip), -- + means the car is travelling out to its LEFT
		steer = s.steer, -- the finger: a share of the car's maximum rate of turn
		throttle = s.throttle, -- eased in over FullThrottleSeconds; never an input
		gripAccel = s.gripAccel, -- studs/s^2 of lateral pull this step
		braking = s.braking, -- past 90 deg of slip: the pull is against the travel
		drifting = s.drifting,
		surfaceGrip = s.surfaceGrip,
		surfaceScore = s.surfaceScore,
		wheelsDown = s.wheelsDown, -- FL, FR, RL, RR
		rearDown = s.rearDown,
		grounded = s.grounded,
		airborne = s.airborne,
		groundY = s.groundY,
		wallHit = s.wallHit,
		simSeconds = s.time,
		stepSeconds = Config.Drift.FixedStep,
		stepsLastFrame = self.runner.steps,
		totalSteps = self.runner.totalSteps,
		frameSeconds = self.frameSeconds,
		respawns = self.respawns,
		respawnsAsked = self.respawnsAsked,
		awaitingRespawn = self.awaitingRespawn,
		usingSurfaceTag = self.world and self.world.usingTag or false,
		surfaceParts = self.world and self.world.surfaceCount or 0,
		remoteCars = self.remoteCars and #self.remoteCars:DebugState() or 0,
	}
end

-- Run the model with no player and return the path it took. Deterministic: the same
-- inputs from the same start give the same line (features/drift-model.md "Determinism").
-- `opts`: { fps, sample, start, velocity, world }. `live = true` uses the real Workspace
-- instead of a flat plane, so a recorded drive can be measured on the playground itself,
-- and `velocity` starts the car already moving, which is how a slide is measured without
-- waiting out the run-up.
function DriftController:DebugDrive(inputs, seconds: number, opts)
	opts = opts or {}
	local start = opts.start or self.spawnCFrame
	local world = opts.world
	if world == nil and opts.live then
		world = self.world
	end
	return Sim.drive(inputs, seconds, {
		fps = opts.fps,
		sample = opts.sample,
		start = start,
		velocity = opts.velocity,
		world = world,
	})
end

-- Studio only: put the car back, so a measured run always starts the same. It asks the
-- server, like everything else does, and waits for the answer -- which is why it takes no
-- CFrame any more: where a car goes is not the client's to say.
function DriftController:DebugReset()
	self:_askForRespawn()
	local deadline = os.clock() + Config.Drift.RespawnAnswerWait
	while self.awaitingRespawn and os.clock() < deadline do
		task.wait()
	end
	return self:DebugState()
end

-- Studio only, and a cheat on purpose: move the car without asking the server. Every
-- CarState that follows is a jump from where the server put the car, and the server drops
-- it -- that is the whole point of the server owning respawns, and it is what the proof in
-- features/drift-model.md "Testing" measures.
function DriftController:DebugTeleport(cf: CFrame)
	if typeof(cf) ~= "CFrame" or not self.runner then
		return nil
	end
	self.runner = Sim.newRunner(cf)
	if self.rig then
		Render.apply(self.rig, self.runner.state)
	end
	return self:DebugState()
end

function DriftController:DebugToggleReadout(): boolean
	if not self.hud then
		return false
	end
	return self.hud:Toggle()
end

return DriftController
