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
--
-- THE DRIVER IS DRAWN HERE TOO (T-096, features/car-v2.md). The avatar in the seat is held
-- by nothing -- no Seat, no weld -- so its anchored root is written straight after the car,
-- from the body that was just drawn (`Drift/Driver`), and can never lag it. While the
-- player is out of the car the simulation is HELD: nothing steps, nothing is sent, and the
-- car is drawn where the server parked it, which is what lets its door swing for everyone
-- to see. `CarEntryController` decides when; this module only holds, parks and drives.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local DebugHud = require(DriftFolder.DebugHud)
local Driver = require(DriftFolder.Driver)
local DriftModel = require(DriftFolder.Model)
local EngineSound = require(DriftFolder.EngineSound)
local RemoteCars = require(DriftFolder.RemoteCars)
local Render = require(DriftFolder.Render)
local Sim = require(DriftFolder.Sim)
local SkidSound = require(DriftFolder.SkidSound)
local Trajectory = require(DriftFolder.Trajectory)
local Wheels = require(DriftFolder.Wheels)
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
--
-- THE SHELL IS CHECKED TOO, a group at a time by its first part, exactly as
-- `Drift/RemoteCars` has always checked another player's car. Since T-033 the SERVER
-- re-dresses a car when its driver switches archetype, which destroys the old `Shell` and
-- replicates a new one: without this the rig goes on writing to parts that no longer
-- exist and the new body is never placed at all. Measured in DR-Lane1 before the check
-- was here: the new shell's parts sat 282.68 studs from the car, where the server's own
-- copy of it is.
local function shellStands(shell, car: Model): boolean
	if not shell then
		return true -- no shell group is not a missing one: a block car has none
	end
	local first = shell.parts[1]
	return first ~= nil and first.part:IsDescendantOf(car)
end

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
		if not shellStands(wheel.shell, car) then
			return false
		end
	end
	if not shellStands(rig.bodyShell, car) then
		return false
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
	-- Held: the player is getting out, out, or getting back in. Nothing steps and nothing
	-- is sent; the car is drawn where it stands (T-096).
	self.held = false
	self.worldRebuilds = 0
	-- The tyre marks and the smoke (T-062, features/car-fx.md). The object is free until a
	-- rig exists: it holds no instance and does no work without one, and its sixteen are
	-- built once, when the rig is caught, and never again. The car's SOUNDS sit beside it
	-- (T-064) and take the same two calls, `Attach` on the rig and `Update` on the frame.
	self.wheels = Wheels.new()
	-- The engine note and the tyre squeal (T-064, features/car-fx.md). Free until a rig
	-- exists, exactly as the wheels are: no `Sound` is made until the car's parts have
	-- arrived, and then one each, once. BOTH ARE THE CLIENT'S AND THE LOCAL CAR'S -- no
	-- remote, no packet field, no server instance, and another player's car is silent
	-- this round. In an agent's playtest they are muted at the instance and go on
	-- computing, so a silent test still measures the whole state machine
	-- (ReplicatedFirst/QuietPlay, docs/workflow/TESTING.md).
	self.engineSound = EngineSound.new()
	self.skidSound = SkidSound.new()
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
	self.carsFolder = carsFolder
	self.remoteCars = RemoteCars.new(carsFolder, nil)

	-- The projected line (T-032). A dev tool: the object is free -- it creates no instance
	-- and does no work until it is switched on -- so it is always here, and
	-- `Config.Drift.TrajectoryLine` only decides whether it starts on. F6 toggles it.
	self.trajectory = Trajectory.new()
	self:_rebuildWorld()
	self:_watchCharacters()
	self.trajectory:BindToggle()
	self.trajectory:SetEnabled(Config.Drift.TrajectoryLine)

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

-- WHAT THE CAR'S RAYS MUST NEVER SEE: the cars, and since T-096 every avatar. The sweep
-- and the overlap hit anything solid that is not in this list, and a seated driver sits
-- INSIDE the car's box -- left in, the car is pushed out of its own driver on the first
-- step. A player walking about is not a wall either: running people over is out of scope
-- (features/car-v2.md "Left out"), and nothing in a car is physics to bump them with.
--
-- `World.live` copies the list into its filters once, so a character arriving or leaving
-- means a new world. Coalesced: one rebuild per frame's worth of changes.
function DriftController:_worldIgnore(): { Instance }
	local list: { Instance } = { self.carsFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, stand in Driver.debugCharacters do
		table.insert(list, stand)
	end
	return list
end

function DriftController:_rebuildWorld()
	self.worldDirty = false
	local old = self.world
	self.world = World.live(self:_worldIgnore())
	self.worldRebuilds += 1
	if self.trajectory then
		self.trajectory:SetWorld(self.world)
	end
	if old and old.destroy then
		old.destroy()
	end
end

function DriftController:_worldChanged()
	if self.worldDirty then
		return
	end
	self.worldDirty = true
	task.defer(function()
		if self.worldDirty then
			self:_rebuildWorld()
		end
	end)
end

function DriftController:_watchCharacters()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			self:_worldChanged()
		end)
		player.CharacterRemoving:Connect(function()
			self:_worldChanged()
		end)
		if player.Character then
			self:_worldChanged()
		end
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function()
		self:_worldChanged()
	end)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
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
	self.held = false -- a car the server has just handed out has its driver in it
	self.rig = nil
	self.rigAttempts = 0
	self.rigFirstParts = -1
	self.rigLiveAfter = -1
	self.rigAskedAt = os.clock()
	self.rigWarned = false
	self.runner = Sim.newRunner(spawnCFrame)
	self.remoteCars:SetOwnCar(car)
	self.wheels:Cut()
	self.engineSound:Cut()
	self.skidSound:Cut()
	if self:_ensureRig() then
		Render.apply(self.rig, self.runner.state)
		self.wheels:Attach(self.rig)
		self.engineSound:Attach(self.rig)
		self.skidSound:Attach(self.rig)
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
	-- Everything off BEFORE the car is put down. A trail that is still enabled across a
	-- jump draws one straight black line from where the car was to where it now is,
	-- across the whole world (T-062). The sounds are cut with them: a squeal that was
	-- fading up must not carry across the jump, and the gearbox goes back to first rather
	-- than walking down five gears half a second each (T-064).
	self.wheels:Cut()
	self.engineSound:Cut()
	self.skidSound:Cut()
	if self:_ensureRig() then
		Render.apply(self.rig, self.runner.state)
	end
end

function DriftController:_frame(dt: number)
	self.frameSeconds = dt
	if not self.runner then
		if self.wheels then
			self.wheels:Update(nil, nil, dt)
		end
		-- Still updated with no car: both fade to their floor rather than holding
		-- whatever they were at when the car went away.
		if self.engineSound then
			self.engineSound:Update(nil, nil, dt)
		end
		if self.skidSound then
			self.skidSound:Update(nil, nil, dt)
		end
		if self.hud then
			self.hud:Update(nil, nil)
		end
		if self.trajectory then
			self.trajectory:Update(nil, nil, dt)
		end
		return
	end

	if self.held then
		self:_frameHeld(dt)
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

	-- Drawn at THIS FRAME'S moment, not at the last completed step: the accumulator's
	-- leftover is handed to Render, which carries the pose across it (T-025, Drift/Render
	-- header). Without it the car is drawn a varying fraction of a step behind itself --
	-- up to 1.49 studs at top speed -- and a varying lag is a judder.
	if self:_ensureRig() then
		Render.apply(self.rig, state, self.runner.accumulator)
		-- The driver, from the body just drawn: the same frame, the same pose (T-096).
		self:_placeDriver()
		-- The wheel effects hang off the rig's own body, so they are attached here and
		-- nowhere else: the rig is the one thing that knows the car's parts have arrived,
		-- and `Attach` does nothing at all once it has built for a body (T-062).
		self.wheels:Attach(self.rig)
		-- The sounds hang off the same body and are attached in the same place, for the
		-- same reason (T-064).
		self.engineSound:Attach(self.rig)
		self.skidSound:Attach(self.rig)
	end
	-- Marks and smoke, from this frame's state and this frame's input: the handbrake is an
	-- input and not model state, so both go in (Drift/Wheels).
	self.wheels:Update(state, input, dt)
	-- The engine note, from the road speed alone, and the squeal, from the slip angle.
	self.engineSound:Update(state, input, dt)
	self.skidSound:Update(state, input, dt)
	self.remoteCars:Update(dt)

	-- Where the car would go if the finger stayed exactly where it is: the real model run
	-- forward from a COPY of this state, so the line is the car and not a guess at it
	-- (Drift/Trajectory). Off by default and free when it is off.
	if self.trajectory then
		self.trajectory:Update(state, input, dt)
	end

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

-- A held frame: the player is getting out, is out, or is getting back in. The car is drawn
-- where it stands every frame all the same -- its door is moving (`Shared/CarParts`
-- attributes, set by the server) and only drawing shows it -- and the driver is placed in
-- it while the server still has them in the seat. No step, no fall test, no packet: the
-- car is parked, and the server drops a `CarState` for a parked car anyway.
function DriftController:_frameHeld(dt: number)
	local state = self.runner.state
	if self:_ensureRig() then
		Render.apply(self.rig, state, 0)
		self:_placeDriver()
	end
	-- The engine and the squeal fade to nothing; the marks and the smoke stop.
	self.wheels:Update(nil, nil, dt)
	self.engineSound:Update(nil, nil, dt)
	self.skidSound:Update(nil, nil, dt)
	self.remoteCars:Update(dt)
	if self.trajectory then
		self.trajectory:Update(nil, nil, dt)
	end
	if self.hud then
		self.hud:Update(state, { steps = 0, frameSeconds = dt, steerInput = 0, handbrake = false,
			device = CarInputController:Device(), surfaceTag = self.world.usingTag })
	end
end

function DriftController:_placeDriver()
	local body = self.rig and self.rig.body
	if body and self.car then
		Driver.placeIn(self.car, body.CFrame)
	end
end

-- ---------------------------------------------------------------- getting in and out
--
-- `CarEntryController` calls these; the server's answers are what it calls them on.

-- Is the simulation running (the player is driving), rather than held?
function DriftController:IsDriving(): boolean
	return self.runner ~= nil and not self.held
end

-- Stop the car where it is, now, and say where that is: the press of Get out. Nothing
-- steps until `Resume` (refused) or `Park` (accepted).
function DriftController:Hold(): CFrame?
	if not self.runner then
		return nil
	end
	self.held = true
	return DriftModel.cframe(self.runner.state)
end

-- Refused: drive on from exactly where it was held, at the speed it had.
function DriftController:Resume()
	if not self.runner then
		return
	end
	self.held = false
	self.runner.accumulator = 0
	self.sendClock = 0
end

-- Accepted: the car is parked where the server says, at rest, and stays held.
function DriftController:Park(cf: CFrame)
	if typeof(cf) ~= "CFrame" or not self.runner then
		return
	end
	self.held = true
	self.runner = Sim.newRunner(cf)
	self.wheels:Cut()
	self.engineSound:Cut()
	self.skidSound:Cut()
	if self:_ensureRig() then
		Render.apply(self.rig, self.runner.state, 0)
	end
end

-- Back in: drive off from where the server parked the car, from rest.
function DriftController:Drive(cf: CFrame?)
	if not self.runner then
		return
	end
	if typeof(cf) == "CFrame" then
		self.runner = Sim.newRunner(cf)
		self.spawnCFrame = cf
	end
	self.held = false
	self.awaitingRespawn = false
	self.runner.accumulator = 0
	self.sendClock = 0
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

-- How far into the current step this frame is, in seconds (0 .. FixedStep): what Sim's
-- accumulator has left over after the whole steps it spent. The car is DRAWN this far past
-- the last step (Drift/Render) and the camera follows the same carried-forward pose, so
-- the two agree about where the car is (T-025).
function DriftController:SubStep(): number
	return self.runner and self.runner.accumulator or 0
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
		-- Out of the car, or on the way in or out: nothing steps, nothing is sent (T-096).
		held = self.held,
		worldRebuilds = self.worldRebuilds,
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
--
-- Measured against where the car is AT THIS MOMENT, which is the last completed step
-- carried across the accumulator's leftover -- not against the step itself (T-025). The
-- two differ by up to 1.49 studs at top speed, and the carried-forward one is the honest
-- answer: `state.position` is where the car was up to 1/120 s ago. The alarm this number
-- exists to raise is unchanged, because a car that has stopped being drawn is hundreds of
-- studs out, not one (T-016).
function DriftController:DrawnGap(): number
	local state = self:CurrentState()
	local rig = self.rig
	local body = rig and rig.body
	if not state or not body or not self.car or not body:IsDescendantOf(self.car) then
		return -1
	end
	local drawnAt = Render.subStep(state, self:SubStep())
	return (body.Position - drawnAt).Magnitude
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
	self.wheels:Cut()
	self.engineSound:Cut()
	self.skidSound:Cut()
	if self:_ensureRig() then
		Render.apply(self.rig, self.runner.state)
	end
	return self:DebugState()
end

-- The projected line, on or off (T-032). No argument toggles it. Returns whether it is on
-- after the call; switching it off destroys its folder and every part in it.
function DriftController:DebugTrajectory(on: boolean?): boolean
	if not self.trajectory then
		return false
	end
	if on == nil then
		return self.trajectory:Toggle()
	end
	return self.trajectory:SetEnabled(on == true)
end

-- What the line is costing, what it drew and how far ahead it reaches.
function DriftController:DebugTrajectoryState()
	if not self.trajectory then
		return { enabled = false }
	end
	return self.trajectory:DebugState()
end

-- The predicted path itself, as points: for measuring the line against where the car
-- really goes. Predicted from the LIVE state with the finger held exactly where it is now,
-- which is the same call the drawn line makes.
function DriftController:DebugTrajectoryPoints(opts)
	local state = self:CurrentState()
	if not state then
		return nil
	end
	local input = CarInputController:Get()
	local prediction = Trajectory.predict(state, input, opts)
	return {
		points = prediction.points,
		length = prediction.length,
		steps = prediction.steps,
		seconds = prediction.seconds,
		endSpeed = prediction.endSpeed,
		stoppedEarly = prediction.stopped,
	}
end

-- What each wheel's marks and smoke are doing, and WHICH GATE decided it (T-062,
-- features/car-fx.md "Testing"). Read against the live state and the live input, so a
-- playtest can say "the fronts are not emitting because the slip is 22 degrees and their
-- threshold is 30" rather than "no smoke".
function DriftController:DebugWheels()
	if not self.wheels then
		return { enabled = false, attached = false }
	end
	local input = CarInputController:Get()
	local out = self.wheels:DebugState(self:CurrentState(), input)
	out.liveInstances = self.wheels:CountInstances()
	return out
end

-- The wheel effects on or off wholesale. Where a `show effects` setting would land, and
-- how the frame cost is measured: the same drive with it true and with it false. It
-- creates and destroys nothing either way.
function DriftController:DebugWheelFx(on: boolean?): boolean
	if not self.wheels then
		return false
	end
	if on == nil then
		return self.wheels:SetEnabled(not self.wheels.enabled)
	end
	return self.wheels:SetEnabled(on == true)
end

-- What the car's two sounds are doing, and WHY (T-064, features/car-fx.md "Testing").
-- Read against the live state, so a playtest can say "the squeal is silent because the
-- slip is 3 degrees" and "the pitch is 1.44 because the box just shifted into second at
-- 23.6 studs/s" rather than "no sound".
--
-- `quiet` being true means an agent's playtest has MUTED the instances and nothing else:
-- every number below is computed and reported exactly as it would be with sound on.
function DriftController:DebugSound()
	local state = self:CurrentState()
	return {
		engine = self.engineSound and self.engineSound:DebugState(state) or { attached = false },
		skid = self.skidSound and self.skidSound:DebugState(state) or { attached = false },
	}
end

-- The largest single-frame change in each sound's lerped value since this was last
-- called, and the counters reset. The "pitch is continuous" check: `engine` must stay
-- under `(MaxPitch - MinPitch) * PitchLerpSpeed * dt` and a jump means the lerp is not
-- doing its job.
function DriftController:DebugSoundMeasure()
	return {
		engine = self.engineSound and self.engineSound:ResetMeasure() or 0,
		skid = self.skidSound and self.skidSound:ResetMeasure() or 0,
	}
end

-- The car's sounds on or off wholesale, the same switch `DebugWheelFx` is. It creates and
-- destroys nothing either way. No argument toggles.
function DriftController:DebugSoundFx(on: boolean?): boolean
	if not self.engineSound or not self.skidSound then
		return false
	end
	local want = if on == nil then not self.engineSound.enabled else on == true
	self.skidSound:SetEnabled(want)
	return self.engineSound:SetEnabled(want)
end

function DriftController:DebugToggleReadout(): boolean
	if not self.hud then
		return false
	end
	return self.hud:Toggle()
end

return DriftController
