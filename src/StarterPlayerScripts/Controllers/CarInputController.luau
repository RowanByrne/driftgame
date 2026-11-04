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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
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
	self.handbrake = false
	self.DebugToggled = Signal.new()
	self._actions = {}
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

	self._drag = DragControl.new(function()
		self.DebugToggled:Fire()
	end)
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

	if self._actions and self._actions.Handbrake then
		handbrake = self._actions.Handbrake:GetState() == true
	end

	if self._drag then
		local dSteer, dHandbrake = self._drag:Get()
		if self._drag:Down() then
			steer = dSteer
		end
		handbrake = handbrake or dHandbrake
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
