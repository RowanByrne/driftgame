--!nonstrict
-- CarInputController: one number, from whatever the player is holding
-- (docs/game/features/drift-model.md "The control").
--
-- The model takes exactly one input: `steer`, -1 .. 1, which IS the car's rate of turn.
-- There is no drift input, no throttle input and no brake in normal play -- the throttle
-- eases itself in inside the model, and the handbrake is only there to stop the car once
-- a run is over. So this controller answers one question once a frame: how far across is
-- the finger, as a share of full travel.
--
-- The game's own scheme is that finger: held down and slid left and right, measured from
-- the middle of the screen or from where it went down (`Config.Drift.InputMode`). That is
-- an analogue drag rather than an InputBinding, so Drift/DragControl owns it and this
-- merges it in.
--
-- Keyboard and gamepad feed the SAME single axis through the Input Action System
-- (docs/workflow/CODING.md "Conventions"): InputContext > InputAction > InputBinding under
-- the player's PlayerScripts. A key is always at the end of its travel, so it is worth
-- `KeySensitivity` of a full finger; a stick is analogue and is scaled the same way.
--
-- `InvertSteering` is applied by the model, at the single line that sets the yaw rate, and
-- NOT here: what leaves this file is the raw signed share of the travel.
--
-- THE PAN is the one other thing a pointer does here (T-036): the RIGHT mouse button held
-- and dragged looks around, the way every Roblox game does. It is deliberately a different
-- button from the steering, which is a LEFT-button drag in Drift/DragControl, so the two
-- never meet -- both can be held at once and the car keeps steering while the view moves.
-- All this file does is collect the pixels; the feel, the limits and the return all live
-- in CarCameraController, which pulls them once a frame with `PanInput()`.
--
-- The mouse is NOT locked while panning, and that is on purpose: the steering is measured
-- from where the cursor IS, so locking it would freeze the car's rate of turn the moment
-- the right button went down.
--
-- THE HANDBRAKE IS A TOGGLE AND THIS FILE OWNS IT (T-041). Press the on-screen button,
-- the key or the gamepad button once and the car brakes until it stops and stays stopped;
-- press any of them again and it drives off. It is still the one handbrake the model
-- already has -- while the toggle is on, this hands the model `handbrake = true` every
-- frame, exactly as a held button used to -- and there is no second braking mechanism.
-- Steering is untouched by it, so a stopped car still rotates under the finger, which is
-- how a player lines a shot up.
--
-- Every path is the SAME latch: the button reports a press (DragControl has no state of
-- its own) and the InputAction's `Pressed` reports one, both land in `_toggleBrake`, so
-- key-then-button and button-then-key cannot disagree.
--
-- IT CLEARS ON A RESPAWN AND ON A CAR SWITCH (`CarRespawn`, `CarSwitch`). Both are the
-- server handing the player a fresh car, and a latch left on would hold that new car still
-- with nothing but a button colour to say why -- a respawn in particular is how a player
-- gets going again after stopping. Listening here, rather than being told by
-- DriftController, keeps the toggle's whole life in one file.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)

-- PlayerScripts.Controllers.CarInputController -> PlayerScripts.Drift
local DragControl = require(script.Parent.Parent:WaitForChild("Drift").DragControl)

local CarInputController = {}

-- Ahead of DriftController, so an input is there on the drift model's first frame.
CarInputController.Priority = 20

local function binding(name: string, parent: Instance, props: { [string]: any }): Instance
	local b = Instance.new("InputBinding")
	b.Name = name
	for key, value in props do
		b[key] = value
	end
	b.Parent = parent
	return b
end

function CarInputController:Init()
	self.steer = 0
	-- The toggle. `brakeOn` IS the latch; `handbrake` is only what the last `Get()` handed
	-- the model, which is the latch except under a Studio override.
	self.brakeOn = false
	self.handbrake = false
	self.brakeToggles = 0 -- how many times it has flipped, for a test to count
	self.brakeCleared = 0 -- and how many times a respawn or a switch dropped it
	self.DebugToggled = Signal.new()
	self._actions = {}
	-- The pan, in PIXELS of mouse travel since the camera last took them. `dx`/`dy` are
	-- drained by `PanInput()`; `totalX`/`totalY` are never drained and exist only so
	-- `DebugState` can be read without stealing the camera's input.
	self._pan = { held = false, dx = 0, dy = 0, totalX = 0, totalY = 0 }
	self._panLastPos = nil
	self._panConnections = {}
end

function CarInputController:Start()
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")

	local context = Instance.new("InputContext")
	context.Name = "DriftControls"
	context.Priority = 1000
	context.Sink = false
	self._context = context

	-- Steering is an axis. Direction2D so one binding covers a thumbstick; only X is read.
	local steer = Instance.new("InputAction")
	steer.Name = "Steer"
	steer.Type = Enum.InputActionType.Direction2D
	steer.Parent = context
	binding("Keyboard", steer, { Left = Enum.KeyCode.A, Right = Enum.KeyCode.D })
	binding("Arrows", steer, { Left = Enum.KeyCode.Left, Right = Enum.KeyCode.Right })
	binding("Stick", steer, { KeyCode = Enum.KeyCode.Thumbstick1, Deadzone = NumberRange.new(0.14, 1) })
	self._actions.Steer = steer

	-- Not part of the control: the handbrake exists only to stop the car once a run is
	-- over (features/drift-model.md "How it plays" 2). There is no drift button and no
	-- throttle, because rotating is drifting and the car drives itself.
	local handbrake = Instance.new("InputAction")
	handbrake.Name = "Handbrake"
	handbrake.Type = Enum.InputActionType.Bool
	handbrake.Parent = context
	binding("Space", handbrake, { KeyCode = Enum.KeyCode.Space })
	binding("S", handbrake, { KeyCode = Enum.KeyCode.S })
	binding("Down", handbrake, { KeyCode = Enum.KeyCode.Down })
	binding("Trigger", handbrake, { KeyCode = Enum.KeyCode.ButtonL2, PressedThreshold = 0.2 })
	binding("Face", handbrake, { KeyCode = Enum.KeyCode.ButtonB })
	self._actions.Handbrake = handbrake

	local debugToggle = Instance.new("InputAction")
	debugToggle.Name = "DebugReadout"
	debugToggle.Type = Enum.InputActionType.Bool
	debugToggle.Parent = context
	binding("F3", debugToggle, { KeyCode = Enum.KeyCode.F3 })
	binding("DPad", debugToggle, { KeyCode = Enum.KeyCode.DPadUp })
	self._actions.DebugReadout = debugToggle

	context.Parent = playerScripts

	debugToggle.Pressed:Connect(function()
		self.DebugToggled:Fire()
	end)

	-- One press, one flip, whichever of the two things was pressed.
	handbrake.Pressed:Connect(function()
		self:_toggleBrake()
	end)

	self._drag = DragControl.new(function()
		self.DebugToggled:Fire()
	end, function()
		self:_toggleBrake()
	end)
	self._drag:SetBrake(self.brakeOn)

	self:_bindPan()
	self:_bindCarEvents()
end

-- ---------------------------------------------------------------- the brake toggle

function CarInputController:_setBrake(on: boolean): boolean
	on = on == true
	if self.brakeOn ~= on then
		self.brakeOn = on
		self.brakeToggles += 1
	end
	-- Pushed every time, even when nothing changed: it is the button's light, and a light
	-- out of step with the latch is the bug this one-owner design exists to rule out.
	if self._drag then
		self._drag:SetBrake(self.brakeOn)
	end
	return self.brakeOn
end

function CarInputController:_toggleBrake(): boolean
	return self:_setBrake(not self.brakeOn)
end

-- A respawn or a car switch drops it (see the header). Bound in the background because
-- both remotes may not exist yet when this starts, and a latch cleared a moment late is a
-- latch nobody has had time to set.
function CarInputController:_bindCarEvents()
	task.spawn(function()
		local function clear()
			if self.brakeOn then
				self.brakeCleared += 1
				self:_setBrake(false)
			end
		end
		local ok, err = pcall(function()
			Net.event("CarRespawn").OnClientEvent:Connect(clear)
			-- `CarSwitch` is also the answer to the question this client asks at startup,
			-- and to a switch the server REFUSED. Neither changes the car under the
			-- player, so neither may let the brake off: only a key that is actually
			-- different from the one we were last told does.
			Net.event("CarSwitch").OnClientEvent:Connect(function(key: any, accepted: any)
				local was = self._carKey
				if type(key) == "string" then
					self._carKey = key
				end
				if accepted == true and was ~= nil and type(key) == "string" and key ~= was then
					clear()
				end
			end)
		end)
		self._carEventsBound = ok
		if not ok then
			warn("[CarInputController] the brake toggle cannot watch CarRespawn/CarSwitch: " .. tostring(err))
		end
	end)
end

-- ---------------------------------------------------------------- the pan
--
-- The right mouse button, held and dragged. Nothing else in the game uses that button:
-- DragControl takes MouseButton1 and Touch only, so there is nothing here to fight.
--
-- `gameProcessedEvent` is DELIBERATELY IGNORED. DragControl's drag area is a full-screen
-- Active frame, so every mouse event in the window comes through marked processed; filter
-- on it and the pan never fires at all.
function CarInputController:_bindPan()
	local function connect(signal, fn)
		table.insert(self._panConnections, signal:Connect(fn))
	end

	connect(UserInputService.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._pan.held = true
			self._panLastPos = nil -- the first move of a drag is measured from itself
		end
	end)

	local function release(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self._pan.held = false
		end
	end
	connect(UserInputService.InputEnded, release)
	-- A button released outside the window never ends: a stuck pan would be a view that
	-- never comes back, so focus lost drops it the same way the steering drops its finger.
	connect(UserInputService.WindowFocusReleased, function()
		self._pan.held = false
	end)

	connect(UserInputService.InputChanged, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local last = self._panLastPos
		self._panLastPos = pos
		if not self._pan.held then
			return
		end
		-- How far the mouse moved. Position first, because `Delta` is only filled in
		-- reliably for a LOCKED mouse and this one is deliberately free (see the header);
		-- `Delta` is the fallback for the frames where the cursor has hit a screen edge
		-- and stopped moving but the mouse itself has not.
		local d = if last then pos - last else Vector2.zero
		if d.Magnitude < 1e-6 then
			d = Vector2.new(input.Delta.X, input.Delta.Y)
		end
		self:_addPan(d.X, d.Y)
	end)
end

function CarInputController:_addPan(dx: number, dy: number)
	self._pan.dx += dx
	self._pan.dy += dy
	self._pan.totalX += dx
	self._pan.totalY += dy
end

-- What the pan has been handed since this was last called, in pixels, and whether the
-- button is still down. The camera pulls this once a frame and DRAINS it: nothing else may
-- call it, or the pixels go to whoever asked first.
function CarInputController:PanInput(): { held: boolean, dx: number, dy: number }
	local pan = self._pan
	local out = { held = pan.held, dx = pan.dx, dy = pan.dy }
	pan.dx, pan.dy = 0, 0
	return out
end

-- The one number the model wants, this frame, plus the handbrake that is not part of the
-- control. The finger wins while it is down -- it is the scheme the game is designed
-- around -- and the keys steer between drags, so a player with a gamepad plugged in can
-- still use it.
function CarInputController:Get(): { steer: number, handbrake: boolean }
	if self._override then
		self.steer, self.handbrake = self._override.steer, self._override.handbrake
		return self._override
	end

	local steer, handbrake = 0, false

	local steerAction = self._actions and self._actions.Steer
	if steerAction then
		local value = steerAction:GetState()
		if typeof(value) == "Vector2" then
			steer = value.X
		elseif type(value) == "number" then
			steer = value
		end
	end
	-- A key held is the end of its travel, which on a rate-of-turn control would be a car
	-- that only ever spins. It is worth `KeySensitivity` of a full finger.
	steer *= Config.Drift.KeySensitivity

	-- The brake is the latch, not a button read this frame: every press, from every input
	-- path, has already been folded into it by `_toggleBrake`.
	handbrake = self.brakeOn

	if self._drag then
		if self._drag:Down() then
			steer = self._drag:Get()
		end
	end

	self.steer = math.clamp(steer, -1, 1)
	self.handbrake = handbrake
	return { steer = self.steer, handbrake = handbrake }
end

function CarInputController:Device(): string
	return UserInputService.PreferredInput.Name
end

function CarInputController:DebugState()
	return {
		steer = self.steer,
		handbrake = self.handbrake,
		brakeOn = self.brakeOn, -- the toggle's own state (T-041)
		brakeToggles = self.brakeToggles,
		brakeCleared = self.brakeCleared,
		brakeWatching = self._carEventsBound == true,
		device = self:Device(),
		mode = if self._drag then self._drag:Mode() else Config.Drift.InputMode,
		sensitivity = Config.Drift.Sensitivity,
		keySensitivity = Config.Drift.KeySensitivity,
		travelPx = if self._drag then self._drag:TravelPx() else 0,
		drag = if self._drag then self._drag:DebugState() else nil,
		contextParent = (self._context and self._context.Parent and self._context.Parent:GetFullName()) or "none",
		actions = if self._context then #self._context:GetChildren() else 0,
		rawSteer = if self._actions and self._actions.Steer then tostring(self._actions.Steer:GetState()) else "none",
		overridden = self._override ~= nil,
		pan = {
			held = self._pan.held,
			pendingX = self._pan.dx, -- not yet taken by the camera
			pendingY = self._pan.dy,
			totalX = self._pan.totalX, -- every pixel since the controller started
			totalY = self._pan.totalY,
		},
	}
end

-- Studio only: act out the right-button drag, so a test exercises the real path into the
-- camera rather than poking the camera's own state. `held` nil leaves the button as it is.
function CarInputController:DebugPan(dxPx: number?, dyPx: number?, held: boolean?)
	if held ~= nil then
		self._pan.held = held
		if held then
			self._panLastPos = nil
		end
	end
	self:_addPan(dxPx or 0, dyPx or 0)
	return {
		held = self._pan.held,
		pendingX = self._pan.dx,
		pendingY = self._pan.dy,
	}
end

-- Studio only: pretend an input is held, so an agent playtest can drive a measured line
-- without touching the keyboard (docs/workflow/TESTING.md). There is no throttle argument:
-- the throttle is not an input and the model eases it in itself.
function CarInputController:DebugSetInput(steer: number?, handbrake: boolean?)
	self._override = {
		steer = math.clamp(steer or 0, -1, 1),
		handbrake = handbrake == true,
	}
	return self._override
end

-- Studio only: the brake toggle's two press paths, each through exactly the code the real
-- thing runs (T-041). `DebugPressBrakeButton` goes in at DragControl's button handler;
-- `DebugPressBrakeKey` goes in where the Handbrake InputAction's `Pressed` lands, which is
-- the one thing a test cannot make the engine fire for it. Neither sets the state
-- directly, so the two cannot be proven to agree by cheating.
function CarInputController:DebugPressBrakeButton()
	if self._drag then
		self._drag:DebugPressBrake()
	end
	return self:DebugBrakeState()
end

function CarInputController:DebugPressBrakeKey()
	self:_toggleBrake()
	return self:DebugBrakeState()
end

function CarInputController:DebugBrakeState()
	local drag = if self._drag then self._drag:DebugState() else nil
	return {
		brakeOn = self.brakeOn,
		handbrake = self.handbrake,
		toggles = self.brakeToggles,
		cleared = self.brakeCleared,
		watching = self._carEventsBound == true,
		-- What the button is showing. It must always equal `brakeOn`.
		buttonLit = if drag then drag.handbrake else nil,
	}
end

-- Studio only: put the toggle somewhere known, the same way a press does, so a test can
-- set up a case without pressing its way there.
function CarInputController:DebugSetBrake(on: boolean?)
	self:_setBrake(on == true)
	return self:DebugBrakeState()
end

function CarInputController:DebugClearInput()
	self._override = nil
	return true
end

function CarInputController:Override(): { steer: number, handbrake: boolean }?
	return self._override
end

-- Studio only: a full finger in pixels, optionally at a sensitivity other than the one in
-- Config, so the travel curve can be measured end to end (Drift/DragControl).
function CarInputController:DebugTravelPx(sensitivity: number?): number
	return if self._drag then self._drag:TravelPx(sensitivity) else 0
end

-- Studio only: stand in for the settings screen that does not exist yet, so both input
-- modes and the sensitivity range can be driven in a test. Either argument nil goes back
-- to Config.
function CarInputController:DebugSettings(mode: string?, sensitivity: number?)
	return if self._drag then self._drag:DebugSettings(mode, sensitivity) else nil
end

-- Studio only: act out the real gesture, so a test exercises the control the player uses
-- rather than the override that bypasses it. The finger goes down at `originPx`, the
-- middle of the screen by default; `offsetPx` nil lifts it.
function CarInputController:DebugDrag(offsetPx: number?, originPx: number?)
	if not self._drag then
		return nil
	end
	return self._drag:DebugDrag(offsetPx, originPx)
end

return CarInputController
