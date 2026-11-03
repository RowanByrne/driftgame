--!nonstrict
-- CarInputController: steering, drift and brake, on keyboard, touch and gamepad.
--
-- Bound with the Input Action System (docs/workflow/CODING.md "Conventions"):
--   InputContext > InputAction > InputBinding, parented under the player's PlayerScripts.
-- Touch is not an InputBinding: a steering stick is an analogue drag, so Drift/TouchControls
-- draws its own programmer-art pad and buttons and this controller merges them in.
--
-- The whole controller exists to answer one question, once a frame: `Get()` -> what the
-- player is asking the car to do. Nothing here knows anything about the drift model.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

-- PlayerScripts.Controllers.CarInputController -> PlayerScripts.Drift
local TouchControls = require(script.Parent.Parent:WaitForChild("Drift").TouchControls)

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
	self.drift = false
	self.brake = false
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

	-- One input starts the drift: that is the whole hook.
	local drift = Instance.new("InputAction")
	drift.Name = "Drift"
	drift.Type = Enum.InputActionType.Bool
	drift.Parent = context
	binding("Space", drift, { KeyCode = Enum.KeyCode.Space })
	binding("Shift", drift, { KeyCode = Enum.KeyCode.LeftShift })
	binding("Trigger", drift, { KeyCode = Enum.KeyCode.ButtonR2, PressedThreshold = 0.2 })
	binding("Face", drift, { KeyCode = Enum.KeyCode.ButtonA })
	self._actions.Drift = drift

	-- Brake and reverse; the throttle drives itself in the prototype.
	local brake = Instance.new("InputAction")
	brake.Name = "Brake"
	brake.Type = Enum.InputActionType.Bool
	brake.Parent = context
	binding("S", brake, { KeyCode = Enum.KeyCode.S })
	binding("Down", brake, { KeyCode = Enum.KeyCode.Down })
	binding("Trigger", brake, { KeyCode = Enum.KeyCode.ButtonL2, PressedThreshold = 0.2 })
	binding("Face", brake, { KeyCode = Enum.KeyCode.ButtonB })
	self._actions.Brake = brake

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

	self._touch = TouchControls.new(function()
		self.DebugToggled:Fire()
	end)
end

-- What the player is asking for, this frame. Touch overrides the bound actions only while
-- a thumb is actually on the screen, so a phone with a gamepad plugged in still works.
function CarInputController:Get(): { steer: number, drift: boolean, brake: boolean }
	if self._override then
		self.steer, self.drift, self.brake = self._override.steer, self._override.drift, self._override.brake
		return self._override
	end

	local steer, drift, brake = 0, false, false

	local steerAction = self._actions and self._actions.Steer
	if steerAction then
		local value = steerAction:GetState()
		if typeof(value) == "Vector2" then
			steer = value.X
		elseif type(value) == "number" then
			steer = value
		end
	end
	if self._actions and self._actions.Drift then
		drift = self._actions.Drift:GetState() == true
		brake = self._actions.Brake:GetState() == true
	end

	if self._touch then
		local tSteer, tDrift, tBrake = self._touch:Get()
		if math.abs(tSteer) > math.abs(steer) then
			steer = tSteer
		end
		drift = drift or tDrift
		brake = brake or tBrake
	end

	self.steer = math.clamp(steer, -1, 1)
	self.drift = drift
	self.brake = brake
	return { steer = self.steer, drift = drift, brake = brake }
end

function CarInputController:Device(): string
	return UserInputService.PreferredInput.Name
end

function CarInputController:DebugState()
	return {
		steer = self.steer,
		drift = self.drift,
		brake = self.brake,
		device = self:Device(),
		touchScheme = Config.Drift.TouchScheme,
		touchVisible = (self._touch ~= nil and self._touch.gui.Enabled) or false,
		contextParent = (self._context and self._context.Parent and self._context.Parent:GetFullName()) or "none",
		actions = if self._context then #self._context:GetChildren() else 0,
		rawSteer = if self._actions and self._actions.Steer then tostring(self._actions.Steer:GetState()) else "none",
		overridden = self._override ~= nil,
	}
end

-- Studio only: pretend a key is held, so an agent playtest can drive a measured line
-- without touching the keyboard (docs/workflow/TESTING.md).
function CarInputController:DebugSetInput(steer: number?, drift: boolean?, brake: boolean?)
	self._override = {
		steer = steer or 0,
		drift = drift == true,
		brake = brake == true,
	}
	return self._override
end

function CarInputController:DebugClearInput()
	self._override = nil
	return true
end

function CarInputController:Override(): { steer: number, drift: boolean, brake: boolean }?
	return self._override
end

return CarInputController
