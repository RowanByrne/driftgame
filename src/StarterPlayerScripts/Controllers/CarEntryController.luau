--!nonstrict
-- CarEntryController: getting out of the car and back in (docs/game/features/car-v2.md,
-- T-096).
--
-- The player starts in the driver's seat, their avatar sitting behind the wheel. Below
-- `Config.CarEntry.ExitSpeed` a Get out button shows (bottom right, stacked above STOP, so
-- the steering finger keeps the rest of the screen), and `F` or the gamepad's Y does the
-- same. Out, the avatar walks with Roblox's own controls and camera; a Get in prompt at
-- the driver's door puts it back.
--
-- THE SERVER DECIDES, this asks (`CarExit`, `CarEnter`; ServerScriptService/Services/
-- CarService). Pressing Get out holds the car where it is and sends that pose; the answer
-- parks it, and the avatar is out the moment the server clears the car's `Driver`
-- attribute. Getting in is the prompt asking; the avatar sits when the server puts it in
-- the seat, and the drift camera and the finger come back when the server says the door
-- has shut. Nothing here moves the avatar: the seated one is placed each frame by
-- `DriftController` (and by `RemoteCars` on everyone else's screen), and the walking one
-- is the player's.
--
-- This module is the one place the three modes meet -- the drift camera or Roblox's, the
-- drag pad or Roblox's controls, the simulation running or held -- so they can only ever
-- change together.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local Driver = require(DriftFolder.Driver)
local DriftModel = require(DriftFolder.Model)

local CarCameraController = require(script.Parent.CarCameraController)
local CarInputController = require(script.Parent.CarInputController)
local DriftController = require(script.Parent.DriftController)

local CarEntryController = {}

CarEntryController.Priority = 1 -- after the camera (5): everything it switches exists

local STEP_NAME = "CarEntry"

-- driving: in the seat, the simulation running.
-- leaving: Get out pressed; the car is held, waiting for the server and then the door.
-- walking: out; Roblox's controls and camera.
-- entering: Get in pressed; waiting for the door, the seat and the door again.
local MODES = { driving = true, leaving = true, walking = true, entering = true }

local function flatSpeed(state): number
	if not state then
		return 0
	end
	local v = state.velocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

function CarEntryController:Init()
	self.mode = "driving"
	self.sitter = Driver.newSitter()
	self.seated = false -- the server has our avatar in our car's seat
	self.exitAccepted = false
	self.askedAt = 0
	self.parkCF = nil
	self.counts = {
		exitsAsked = 0,
		exitsAccepted = 0,
		exitsRefused = 0,
		entersAsked = 0,
		entersAccepted = 0,
		entersRefused = 0,
		timeouts = 0,
		sits = 0,
		stands = 0,
	}
	self.lastRefusal = nil
	self._carExit = Net.event("CarExit")
	self._carEnter = Net.event("CarEnter")
end

function CarEntryController:Start()
	local player = Players.LocalPlayer
	self:_buildButton()
	self:_bindKeys()
	self:_buildPrompt()

	-- Roblox's own movement, switched off while the avatar sits: no walking out of a moving
	-- car, and no thumbstick or jump button over the steering finger on a phone.
	task.spawn(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 20)
		if module then
			local ok, pm = pcall(require, module)
			if ok and pm and pm.GetControls then
				self._controls = pm:GetControls()
				self:_applyControls()
			end
		end
	end)

	self._carExit.OnClientEvent:Connect(function(ok, cf, reason)
		self:_onExitAnswer(ok, cf, reason)
	end)
	self._carEnter.OnClientEvent:Connect(function(ok, cf, reason)
		self:_onEnterAnswer(ok, cf, reason)
	end)
	-- A car handed out is a car with its driver in it.
	Net.event("CarSpawn").OnClientEvent:Connect(function()
		self:_becomeDriving(nil)
	end)

	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_frame(dt)
	end)
end

-- ---------------------------------------------------------------- the pieces

function CarEntryController:_buildButton()
	local E = Config.CarEntry
	local gui = Instance.new("ScreenGui")
	gui.Name = "CarEntry"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the same space as the drag pad and its STOP button
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = E.DisplayOrder -- above the drag pad's 5: a thumb here is a press
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local button = Instance.new("TextButton")
	button.Name = "GetOut"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Size = UDim2.fromOffset(E.ButtonSize.X, E.ButtonSize.Y)
	button.Position = UDim2.new(1, -E.ButtonMargin, 1, -E.ButtonAbove)
	button.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	button.BackgroundTransparency = 0.35
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Active = true
	button.Text = E.ButtonText
	button.TextColor3 = Color3.fromRGB(240, 240, 240)
	button.TextSize = 16
	button.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	button.Visible = false
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	button.Activated:Connect(function()
		self:RequestExit()
	end)
	self.button = button
end

-- `F` and the gamepad's Y, in a context of their own that is only on while driving: the
-- same press as the button, through the same function.
function CarEntryController:_bindKeys()
	local context = Instance.new("InputContext")
	context.Name = "CarEntryControls"
	context.Priority = 1000
	context.Sink = false
	local action = Instance.new("InputAction")
	action.Name = "GetOut"
	action.Type = Enum.InputActionType.Bool
	action.Parent = context
	local key = Instance.new("InputBinding")
	key.Name = "Key"
	key.KeyCode = Enum.KeyCode.F
	key.Parent = action
	local pad = Instance.new("InputBinding")
	pad.Name = "Gamepad"
	pad.KeyCode = Enum.KeyCode.ButtonY
	pad.Parent = action
	context.Parent = Players.LocalPlayer:WaitForChild("PlayerScripts")
	action.Pressed:Connect(function()
		self:RequestExit()
	end)
	self._context = context
end

-- The Get in prompt hangs on an invisible part this client makes for itself, so only the
-- car's owner ever sees it, and nothing is added to the car (`CarModel.strayOffenders`
-- counts a ProximityPrompt as clutter). Not queryable, not collidable: the car's rays and
-- the walking avatar both go straight through it.
function CarEntryController:_buildPrompt()
	local E = Config.CarEntry
	local part = Instance.new("Part")
	part.Name = "CarEntryDoor"
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GetIn"
	prompt.ActionText = E.PromptText
	prompt.ObjectText = ""
	prompt.MaxActivationDistance = E.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Enabled = false
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		self:RequestEnter()
	end)
	part.Parent = workspace
	self.promptPart = part
	self.prompt = prompt
end

function CarEntryController:_applyControls()
	local controls = self._controls
	if controls then
		if self.seated then
			controls:Disable()
		else
			controls:Enable()
		end
	end
	local touch = Players.LocalPlayer.PlayerGui:FindFirstChild("TouchGui")
	if touch and touch:IsA("ScreenGui") then
		touch.Enabled = not self.seated
	end
end

-- ---------------------------------------------------------------- the frame

function CarEntryController:_frame(_dt: number)
	local player = Players.LocalPlayer
	local car = DriftController:Car()
	local character = player.Character
	local seatedNow = car ~= nil and character ~= nil and Driver.driverOf(car) == player.UserId

	-- The avatar sits and stands when the SERVER says so, by the car's `Driver` attribute.
	if seatedNow and (not self.seated or self.sitter.character ~= character) then
		self.seated = true
		self.counts.sits += 1
		self.sitter:Sit(character)
		self:_applyControls()
	elseif not seatedNow and self.seated then
		self.seated = false
		self.counts.stands += 1
		self.sitter:Stand()
		self:_applyControls()
	end

	local now = os.clock()
	if self.mode == "leaving" then
		if self.exitAccepted and not seatedNow then
			self:_becomeWalking()
		elseif not self.exitAccepted and now - self.askedAt > Config.CarEntry.AnswerWait then
			-- No answer at all: drive on rather than sit in a held car for ever.
			self.counts.timeouts += 1
			self.mode = "driving"
			DriftController:Resume()
		end
	elseif self.mode == "entering" then
		if not seatedNow and now - self.askedAt > Config.CarEntry.AnswerWait then
			self.counts.timeouts += 1
			self.mode = "walking"
		end
	end

	-- The button: driving, and slow enough to get out.
	local state = DriftController:CurrentState()
	self.button.Visible = self.mode == "driving"
		and DriftController:IsDriving()
		and flatSpeed(state) < Config.CarEntry.ExitSpeed
	self._context.Enabled = self.mode == "driving"

	-- The prompt: at the driver's door of the parked car, while walking.
	local walking = self.mode == "walking" and car ~= nil
	if walking then
		local carCF = self.parkCF or (state and DriftModel.cframe(state)) or car:GetPivot()
		self.promptPart.CFrame = CFrame.new(Driver.doorPoint(carCF, car))
	end
	self.prompt.Enabled = walking
end

-- ---------------------------------------------------------------- the modes

function CarEntryController:_becomeWalking()
	self.mode = "walking"
	CarInputController:SetDriving(false)
	CarCameraController:SetDriving(false)
end

function CarEntryController:_becomeDriving(cf: CFrame?)
	self.mode = "driving"
	self.exitAccepted = false
	self.parkCF = nil
	DriftController:Drive(cf)
	CarInputController:SetDriving(true)
	CarCameraController:SetDriving(true)
end

-- ---------------------------------------------------------------- asking

-- Get out: the button, `F` and Y all land here. Refused on the spot while not driving or
-- too fast; otherwise the car is held where it is and the server is asked.
function CarEntryController:RequestExit(): (boolean, string?)
	if self.mode ~= "driving" or not DriftController:IsDriving() then
		return false, "not driving"
	end
	if flatSpeed(DriftController:CurrentState()) >= Config.CarEntry.ExitSpeed then
		return false, "too fast"
	end
	local state = DriftController:CurrentState()
	local cf = DriftController:Hold()
	if not cf then
		return false, "no car"
	end
	self.mode = "leaving"
	self.exitAccepted = false
	self.askedAt = os.clock()
	self.counts.exitsAsked += 1
	-- The server judges the speed by the last pose it agreed to, which can be up to a
	-- packet old -- and a car that has just stopped dead against a wall was doing 40 in
	-- it. So the held pose goes first, as an ordinary `CarState`, and the request a packet
	-- later: what the server checks is the car as it is when the button went down.
	DriftController:_send(state)
	local wanted = self.counts.exitsAsked
	task.delay(1 / math.max(Config.Drift.StateSendRate, 1), function()
		if self.mode == "leaving" and self.counts.exitsAsked == wanted then
			self._carExit:FireServer(cf)
		end
	end)
	return true, nil
end

function CarEntryController:_onExitAnswer(ok: any, cf: any, reason: any)
	if ok == true and typeof(cf) == "CFrame" then
		self.counts.exitsAccepted += 1
		self.exitAccepted = true
		self.parkCF = cf
		self.mode = "leaving"
		DriftController:Park(cf)
		return
	end
	self.counts.exitsRefused += 1
	self.lastRefusal = tostring(reason)
	if self.mode == "leaving" and not self.exitAccepted then
		self.mode = "driving"
		DriftController:Resume()
	end
end

-- Get in: the prompt lands here.
function CarEntryController:RequestEnter(): (boolean, string?)
	if self.mode ~= "walking" then
		return false, "not walking"
	end
	self.mode = "entering"
	self.askedAt = os.clock()
	self.counts.entersAsked += 1
	self._carEnter:FireServer(DriftController:Car())
	return true, nil
end

-- `ok` is the server saying the player is in and the door is shut -- in answer to the
-- prompt, or because the server sat them down itself (a respawn, a run, a new avatar).
function CarEntryController:_onEnterAnswer(ok: any, cf: any, reason: any)
	if ok == true then
		self.counts.entersAccepted += 1
		self:_becomeDriving(if typeof(cf) == "CFrame" then cf else nil)
		return
	end
	self.counts.entersRefused += 1
	self.lastRefusal = tostring(reason)
	if self.mode == "entering" then
		self.mode = "walking"
	end
end

-- ---------------------------------------------------------------- debug

function CarEntryController:DebugState()
	local player = Players.LocalPlayer
	local car = DriftController:Car()
	local root = Driver.rootOf(player.Character)
	local body = car and car:FindFirstChild("Body")
	local seatTarget = if body then Driver.seatRoot(body.CFrame, car) else nil
	local seat, exit, fromRig = Driver.points(car)
	return {
		mode = self.mode,
		modes = MODES[self.mode] == true,
		seated = self.seated,
		sitting = self.sitter:IsSitting(),
		driver = Driver.driverOf(car),
		simDriving = DriftController:IsDriving(),
		buttonVisible = self.button.Visible,
		buttonPosition = self.button.AbsolutePosition,
		buttonSize = self.button.AbsoluteSize,
		promptEnabled = self.prompt.Enabled,
		promptAt = self.promptPart.Position,
		keysEnabled = self._context.Enabled,
		controls = self._controls ~= nil,
		rootAnchored = root and root.Anchored or nil,
		rootAt = root and root.Position or nil,
		seatGap = if root and seatTarget then (root.Position - seatTarget.Position).Magnitude else nil,
		bodyAt = body and body.Position or nil,
		seatPoint = seat.Position,
		exitPoint = exit.Position,
		pointsFromRig = fromRig,
		cameraType = workspace.CurrentCamera and workspace.CurrentCamera.CameraType.Name or nil,
		counts = table.clone(self.counts),
		lastRefusal = self.lastRefusal,
		device = UserInputService.PreferredInput.Name,
	}
end

-- Studio only: Get in exactly as the prompt's `Triggered` does.
function CarEntryController:DebugTriggerPrompt()
	return { RequestEnter = table.pack(self:RequestEnter()) }
end

local function waitFor(predicate: () -> boolean, seconds: number): boolean
	local deadline = os.clock() + seconds
	while not predicate() do
		if os.clock() > deadline then
			return false
		end
		RunService.RenderStepped:Wait()
	end
	return true
end

-- Studio only: `n` full cycles of getting out and back in, through the real paths -- the
-- button's function, the prompt's function -- with the avatar measured EVERY FRAME after the
-- car and the driver have both been drawn: its root's gap from the seat of the body as
-- drawn while seated, and how far the drawn car moves while it is parked. `drive` seconds
-- of driving with `steer` between cycles, so the seat is measured on a moving, leaning car
-- and the car is parked somewhere new each time. Walks the avatar to the door to get in.
function CarEntryController:DebugCycles(n: number?, drive: number?, steer: number?)
	n = n or 10
	drive = drive or 1.5
	local player = Players.LocalPlayer
	local out = {
		cycles = 0,
		failures = {},
		seatedFrames = 0,
		maxSeatGap = 0,
		movingSeatedFrames = 0,
		maxSpeedSeated = 0,
		parkedFrames = 0,
		maxParkedMove = 0,
		walkingFrames = 0,
		maxExitGap = 0, -- avatar's feet from the exit point the moment it is out
		cameraOk = true,
		inputOk = true,
	}

	-- The measurement: after DriftController, RemoteCars and this controller have run.
	local parkedAt: Vector3? = nil
	local conn = RunService.RenderStepped:Connect(function()
		local car = DriftController:Car()
		local body = car and car:FindFirstChild("Body")
		local root = Driver.rootOf(player.Character)
		if not body or not root then
			return
		end
		if Driver.driverOf(car) == player.UserId and root.Anchored then
			out.seatedFrames += 1
			local gap = (root.Position - Driver.seatRoot(body.CFrame, car).Position).Magnitude
			out.maxSeatGap = math.max(out.maxSeatGap, gap)
			local speed = flatSpeed(DriftController:CurrentState())
			if speed > 1 then
				out.movingSeatedFrames += 1
			end
			out.maxSpeedSeated = math.max(out.maxSpeedSeated, speed)
		end
		if self.mode == "walking" then
			out.walkingFrames += 1
			parkedAt = parkedAt or body.Position
			out.parkedFrames += 1
			out.maxParkedMove = math.max(out.maxParkedMove, (body.Position - parkedAt).Magnitude)
		else
			parkedAt = nil
		end
	end)

	local function fail(i, what)
		table.insert(out.failures, `cycle {i}: {what}`)
	end

	for i = 1, n do
		-- Drive a bit, then stop with the handbrake.
		CarInputController:DebugSetInput(steer or 0.35, false)
		task.wait(drive)
		CarInputController:DebugSetInput(0, true)
		if not waitFor(function()
			return flatSpeed(DriftController:CurrentState()) < Config.CarEntry.ExitSpeed * 0.5
		end, 8) then
			fail(i, "never slowed")
			break
		end
		CarInputController:DebugClearInput()
		CarInputController:DebugSetBrake(false)

		-- Get out.
		local ok, why = self:RequestExit()
		if not ok then
			fail(i, "exit refused locally: " .. tostring(why))
			break
		end
		if not waitFor(function()
			return self.mode == "walking"
		end, 5) then
			fail(i, "never got out (mode " .. self.mode .. ")")
			break
		end
		task.wait() -- the server's placement lands
		local root = Driver.rootOf(player.Character)
		local car = DriftController:Car()
		if root and car and self.parkCF then
			local feet = (self.parkCF * select(2, Driver.points(car))).Position
			local rootFeet = root.Position - Vector3.new(0, Driver.rootAboveFeet(player.Character), 0)
			out.maxExitGap = math.max(out.maxExitGap, (rootFeet - feet).Magnitude)
		end
		local cam = workspace.CurrentCamera
		if not cam or cam.CameraType ~= Enum.CameraType.Custom then
			out.cameraOk = false
		end
		if CarInputController:IsDriving() then
			out.inputOk = false
		end

		-- Stand about a moment with the car parked, then walk to the door.
		task.wait(0.5)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:MoveTo(self.promptPart.Position)
		end
		waitFor(function()
			local r = Driver.rootOf(player.Character)
			return r ~= nil and (r.Position - self.promptPart.Position).Magnitude < Config.CarEntry.PromptDistance - 2
		end, 4)

		-- Get in, as the prompt does.
		local entered = self:RequestEnter()
		if not entered then
			fail(i, "enter refused locally")
			break
		end
		if not waitFor(function()
			return self.mode == "driving"
		end, 6) then
			fail(i, "never got in (mode " .. self.mode .. ", " .. tostring(self.lastRefusal) .. ")")
			break
		end
		local cam2 = workspace.CurrentCamera
		if not cam2 or cam2.CameraType ~= Enum.CameraType.Scriptable then
			out.cameraOk = false
		end
		if not CarInputController:IsDriving() then
			out.inputOk = false
		end
		out.cycles = i
	end
	CarInputController:DebugClearInput()
	-- A last stretch of driving, measured, so the final cycle's getting in is followed by a
	-- moving car with its driver in it.
	CarInputController:DebugSetInput(steer or 0.35, false)
	task.wait(drive)
	CarInputController:DebugClearInput()
	conn:Disconnect()
	out.counts = table.clone(self.counts)
	return out
end

-- Studio only: the REMOTE view of a driver, with no second client. A stand-in car (a clone
-- of ours, owned by a made-up UserId) and a stand-in avatar (a clone of ours, anchored, as
-- the server anchors a seated one) are handed to `RemoteCars` as another player's, with
-- that car's `Driver` set to the stand-in; then `CarStateOther`-shaped poses are fed in at
-- 20 Hz along a curve and the avatar's gap from the seat of the car AS DRAWN is measured
-- every frame. Everything it made is destroyed after.
function CarEntryController:DebugRemoteDriver(seconds: number?)
	seconds = seconds or 3
	local player = Players.LocalPlayer
	local car = DriftController:Car()
	local character = player.Character
	local remote = DriftController.remoteCars
	if not car or not character or not remote then
		return { ok = false, reason = "no car, avatar or remote cars" }
	end
	local fakeId = -4242
	local folder = car.Parent
	local carCopy = car:Clone()
	carCopy.Name = "Car_" .. fakeId
	carCopy:SetAttribute("UserId", fakeId)
	carCopy:SetAttribute(Config.CarEntry.DriverAttribute, fakeId)
	character.Archivable = true
	local stand = character:Clone()
	character.Archivable = false
	for _, d in stand:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	stand.Name = "RemoteDriverStandIn"
	local standRoot = Driver.rootOf(stand)
	if not standRoot then
		carCopy:Destroy()
		stand:Destroy()
		return { ok = false, reason = "no root on the stand-in" }
	end
	standRoot.Anchored = true
	stand.Parent = workspace
	Driver.debugCharacters[fakeId] = stand
	DriftController:_worldChanged() -- the stand-in is an avatar: out of the car's rays
	carCopy.Parent = folder

	local start = (self.parkCF or car:GetPivot()) * CFrame.new(30, 0, 0)
	local out = { frames = 0, maxGap = 0, maxReportedGap = 0, packets = 0, drawnFrames = 0 }
	local t0 = os.clock()
	local lastSend = -1
	local conn = RunService.RenderStepped:Connect(function()
		local entry = remote.cars[fakeId]
		local body = entry and entry.rig and entry.rig.body
		if not body or not entry.drawn then
			return
		end
		out.drawnFrames += 1
		local gap = (standRoot.Position - Driver.seatRoot(body.CFrame, carCopy).Position).Magnitude
		out.maxGap = math.max(out.maxGap, gap)
	end)
	while os.clock() - t0 < seconds do
		local t = os.clock() - t0
		if t - lastSend >= 1 / Config.Drift.StateSendRate then
			lastSend = t
			-- Round a 40-stud circle at 32 studs/s, so the drawn car eases and turns
			-- between poses the way a real remote car does.
			local yaw = t * 0.8
			local cf = CFrame.new(start.Position + Vector3.new(math.sin(yaw) * 40, 0, (1 - math.cos(yaw)) * 40))
				* CFrame.Angles(0, -yaw, 0)
			remote:OnState(fakeId, cf, Vector3.new(32 * math.cos(yaw), 0, 32 * math.sin(yaw)), true)
			out.packets += 1
		end
		RunService.RenderStepped:Wait()
	end
	conn:Disconnect()
	out.frames = out.drawnFrames
	local listed = nil
	for _, e in remote:DebugState() do
		if e.userId == fakeId then
			listed = e
		end
	end
	out.listedDriver = listed and listed.driver or nil
	out.listedDriverGap = listed and listed.driverGap or nil
	Driver.debugCharacters[fakeId] = nil
	carCopy:Destroy()
	stand:Destroy()
	DriftController:_worldChanged()
	out.ok = out.drawnFrames > 0 and out.maxGap <= 0.05
	return out
end

return CarEntryController
