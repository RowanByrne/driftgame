--!nonstrict
-- DriftController: the drift model's lifecycle on the client that drives the car.
--
-- The model itself is Drift/Model; the fixed step is Drift/Sim; the Workspace queries are
-- Drift/World; drawing is Drift/Render. This module is only the wiring: take the car the
-- server spawned, read the input once a frame, spend the frame in whole simulation steps,
-- put the car where the model says, and tell the server at 20 Hz.
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
	self._carSpawn = Net.event("CarSpawn")
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

function DriftController:_respawn()
	if not self.runner then
		return
	end
	self.runner = Sim.newRunner(self.spawnCFrame)
	self.respawns += 1
end

function DriftController:_frame(dt: number)
	self.frameSeconds = dt
	if not self.runner then
		if self.hud then
			self.hud:Update(nil, nil)
		end
		return
	end

	local input = CarInputController:Get()
	local steps = Sim.advance(self.runner, dt, input, self.world)
	local state = self.runner.state

	if state.fell then
		self:_respawn()
		state = self.runner.state
	end

	if self.rig then
		Render.apply(self.rig, state)
	end
	self.remoteCars:Update(dt)

	self.sendClock += dt
	local period = 1 / math.max(Config.Drift.StateSendRate, 1)
	if self.sendClock >= period then
		self.sendClock -= period
		self:_send(state)
	end

	if self.hud then
		self.hud:Update(state, {
			steps = steps,
			frameSeconds = dt,
			steerInput = input.steer,
			drift = input.drift,
			brake = input.brake,
			device = CarInputController:Device(),
			surfaceTag = self.world.usingTag,
		})
	end
end

function DriftController:_send(state)
	local fwd, right = DriftModel.axes(state.yaw)
	local velocity = fwd * state.u + right * state.v + Vector3.yAxis * state.vy
	self._carState:FireServer(DriftModel.cframe(state), velocity, state.gripBlend > 0.5)
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
		return { hasCar = false, spawn = self.spawnCFrame.Position }
	end
	return {
		hasCar = true,
		position = s.position,
		headingDeg = math.deg(s.yaw) % 360,
		speed = DriftModel.speed(s),
		forwardSpeed = s.u,
		lateralSpeed = s.v,
		yawRate = s.r,
		verticalSpeed = s.vy,
		slipDeg = math.deg(s.slip),
		slipFrontDeg = math.deg(s.slipFront),
		slipRearDeg = math.deg(s.slipRear),
		wantedSlipDeg = math.deg(s.wantedSlip),
		wheelAngleDeg = math.deg(s.wheelAngle),
		steer = s.steer,
		gripBlend = s.gripBlend,
		rearGrip = s.muRear,
		phase = s.phase,
		airborne = s.airborne,
		groundY = s.groundY,
		wallHit = s.wallHit,
		breakLooseSeconds = s.breakLoose,
		simSeconds = s.time,
		stepSeconds = Config.Drift.FixedStep,
		stepsLastFrame = self.runner.steps,
		totalSteps = self.runner.totalSteps,
		frameSeconds = self.frameSeconds,
		respawns = self.respawns,
		usingSurfaceTag = self.world and self.world.usingTag or false,
		surfaceParts = self.world and self.world.surfaceCount or 0,
		remoteCars = self.remoteCars and #self.remoteCars:DebugState() or 0,
	}
end

-- Run the model with no player and return the path it took. Deterministic: the same
-- inputs from the same start give the same line (features/drift-model.md "Determinism").
-- `opts`: { fps, sample, start, world }. `live = true` uses the real Workspace instead of
-- a flat plane, so a recorded drive can be measured on the playground itself.
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
		world = world,
	})
end

-- Studio only: put the car back at its spawn, so a measured run always starts the same.
function DriftController:DebugReset(cf: CFrame?)
	if cf then
		self.spawnCFrame = cf
	end
	self:_respawn()
	return self:DebugState()
end

function DriftController:DebugToggleReadout(): boolean
	if not self.hud then
		return false
	end
	return self.hud:Toggle()
end

return DriftController
