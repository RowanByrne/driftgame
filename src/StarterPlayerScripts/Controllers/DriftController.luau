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
--
-- Which is why the one thing this module must never stop doing is WRITING. The car is
-- drawn only by `Render.apply`; the moment it has nothing to write through, the car stops
-- dead while everything else -- the simulation, the camera, the packets -- carries on
-- without it, and the player is left looking at empty world (`_ensureRig`, T-016).

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

-- Is this rig still holding parts that are in the world?
--
-- A rig is a handful of direct references to the car's parts, taken once. Two things make
-- one useless, and both leave `Render.apply` silently writing nothing -- which looks
-- exactly like a car that has stopped following the simulation (T-016):
--
--   * it was built from a model whose parts had not replicated yet, so it caught nothing;
--   * its parts have since left the car (a part replaced, a model streamed out).
--
-- `IsDescendantOf` rather than `.Parent ==` on purpose: a car model is free to put its
-- parts inside a folder or a sub-model (Shared/CarModel), and a rig built from one is
-- still a rig this controller can write through.
local function rigIsLive(rig, car: Model?): boolean
	if not rig or not car or rig.car ~= car then
		return false
	end
	if not rig.body or not rig.body:IsDescendantOf(car) then
		return false
	end
	local wheels = rig.wheels
	if not wheels or #wheels == 0 then
		return false
	end
	for _, wheel in wheels do
		if not wheel.part or not wheel.part:IsDescendantOf(car) then
			return false
		end
	end
	return true
end

local function rigParts(rig): number
	if not rig then
		return 0
	end
	return (if rig.body then 1 else 0) + #(rig.wheels or {})
end

function DriftController:Init()
	self.runner = nil
	self.rig = nil
	self.car = nil
	self.spawnCFrame = CFrame.new(0, Config.Drift.RideHeight, 0)
	self.frameSeconds = 0
	self.sendClock = 0
	self.respawns = 0
	self.respawnsAsked = 0
	self.rigAttempts = 0 -- how many times the rig has been taken for the car we hold
	self.rigFirstParts = -1 -- parts the first attempt found: 0 is the race in "the rig"
	self.rigLiveAfter = -1 -- seconds from the first attempt until it caught the parts
	self.rigAskedAt = 0
	self.rigWarned = false
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
	-- Bail only on the car we are ALREADY driving, never on "we hold some car". The server
	-- may replace a player's car -- a run ending and handing out a fresh one is the case
	-- that is coming -- and the old test, `if self.car then return`, ignored the new model
	-- for ever (T-016). `_attach` already re-rigs when the model differs; it was never
	-- reached.
	--
	-- This fires on a model that usually has NO CHILDREN YET -- the parts are still on the
	-- wire -- and that is fine here and handled in `_ensureRig`. Nothing in this function
	-- may assume the car has parts.
	local function claim(child: Instance)
		if child == self.car then
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
	self.rig = nil
	self.rigAttempts = 0
	self.rigFirstParts = -1
	self.rigLiveAfter = -1
	self.rigAskedAt = os.clock()
	self.rigWarned = false
	self.runner = Sim.newRunner(spawnCFrame)
	self.remoteCars:SetOwnCar(car)
	if self:_ensureRig() then
		Render.apply(self.rig, self.runner.state)
	end
end

-- Hold a rig that can actually draw the car, and take it again until it can.
--
-- THIS IS THE WHOLE OF T-016. A Model replicates BEFORE its parts do: when the server
-- hands this client a car mid-session -- `CarService:Spawn` again, which is the path a run
-- ending will take -- `Workspace.Cars.ChildAdded` fires on a model with ZERO children, and
-- a rig taken at that instant catches no body and no wheels. `Render.apply` then writes
-- nothing, for ever: the simulation drives on, the camera follows the simulation, and the
-- car the player sees stays at the spawn with the right model held and its parts parented
-- in the world. Measured in DR-Lane3: 0 children at the event, 5 of them 0.5 s later, and
-- the car 380 studs behind the simulation by the time it was asked.
--
-- So the rig is not something taken once at attach. It is taken until it holds parts that
-- are in the world, and taken again if it ever stops holding them.
function DriftController:_ensureRig(): boolean
	local car = self.car
	if not car then
		return false
	end
	if rigIsLive(self.rig, car) then
		return true
	end
	self.rig = Render.rig(car)
	self.rigAttempts += 1
	if self.rigFirstParts < 0 then
		self.rigFirstParts = rigParts(self.rig)
	end
	if rigIsLive(self.rig, car) then
		if self.rigLiveAfter < 0 then
			self.rigLiveAfter = os.clock() - self.rigAskedAt
		end
		return true
	end
	-- A car whose parts never arrive is a car the player will never see, and silence is
	-- what made this bug cost a day. Said once per car.
	if not self.rigWarned and os.clock() - self.rigAskedAt > Config.Drift.RespawnAnswerWait then
		self.rigWarned = true
		warn(
			`[DriftController] {car.Name} still has no parts to draw after {self.rigAttempts} tries; `
				.. `the car will not move`
		)
	end
	return false
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
	if self:_ensureRig() then
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

	if self:_ensureRig() then
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
		-- The one number T-016 is about: how far the car the player SEES is from the car
		-- the simulation says is there. It is a frame of lag at most -- under a stud at
		-- any speed -- and anything more means the drawing has stopped.
		drawnGap = self:DrawnGap(),
		rigParts = rigParts(self.rig),
		usingSurfaceTag = self.world and self.world.usingTag or false,
		surfaceParts = self.world and self.world.surfaceCount or 0,
		remoteCars = self.remoteCars and #self.remoteCars:DebugState() or 0,
	}
end

-- How far the drawn car is from where the simulation says it is, in studs, or -1 when
-- there is nothing drawn to measure. Read off a part in the world, not off the rig, so a
-- rig holding parts that left the car still reads as the long gap it is.
function DriftController:DrawnGap(): number
	local state = self:CurrentState()
	local rig = self.rig
	local body = rig and rig.body
	if not state or not body or not self.car or not body:IsDescendantOf(self.car) then
		return -1
	end
	return (body.Position - state.position).Magnitude
end

-- What the car is being drawn through, and what it cost to get hold of it. `firstParts`
-- is the T-016 race, in one number: 0 means the model arrived before its parts did, and
-- `attempts` and `liveAfter` are how long it took to catch them.
function DriftController:DebugRig()
	return {
		car = self.car and self.car.Name or nil,
		carInWorld = self.car ~= nil and self.car.Parent ~= nil,
		live = rigIsLive(self.rig, self.car),
		parts = rigParts(self.rig),
		wheels = self.rig and #(self.rig.wheels or {}) or 0,
		hasBody = self.rig ~= nil and self.rig.body ~= nil,
		attempts = self.rigAttempts,
		firstParts = self.rigFirstParts,
		liveAfter = self.rigLiveAfter,
		drawnGap = self:DrawnGap(),
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
	if self:_ensureRig() then
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
