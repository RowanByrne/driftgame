--!nonstrict
-- CarInputController: steering, drift and brake, on touch, mouse, keyboard and gamepad.
--
-- The game's own scheme is one gesture: a finger or the mouse held down and slid left and
-- right, where the same offset steers and puts the car into the drift (DECISIONS.md,
-- 2026-11-03). That is not an InputBinding -- it is an analogue drag with a latch -- so
-- Drift/DragControl owns it and this controller merges it in.
--
-- Keyboard and gamepad are the fallback, and keep discrete bindings through the Input
-- Action System (docs/workflow/CODING.md "Conventions"): InputContext > InputAction >
-- InputBinding, under the player's PlayerScripts. Every device works from the first
-- version, but only one of them is the scheme the game is designed around.
--
-- The whole controller exists to answer one question, once a frame: `Get()` -> what the
-- player is asking the car to do. Nothing here knows anything about the drift model.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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

	-- Keyboard and gamepad cannot slide a thumb, so they get a discrete drift button. The
	-- model takes the same two values either way: a steering axis and a drift flag.
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

	self._drag = DragControl.new(function()
		self.DebugToggled:Fire()
	end)
end

-- What the player is asking for, this frame. The gesture wins over the bound actions, but
-- only while a finger or the mouse is actually down, so a player with a gamepad plugged in
-- can still use it and a keyboard still steers between drags.
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

	if self._drag then
		local dSteer, dDrift, dBrake = self._drag:Get()
		if math.abs(dSteer) > math.abs(steer) then
			steer = dSteer
		end
		drift = drift or dDrift
		brake = brake or dBrake
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
		drag = if self._drag then self._drag:DebugState() else nil,
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

-- Studio only: act out the real gesture, so a test exercises the control the player uses
-- rather than the override that bypasses it. `offsetPx` nil lifts the finger.
function CarInputController:DebugDrag(offsetPx: number?, flickRate: number?)
	if not self._drag then
		return nil
	end
	return self._drag:DebugDrag(offsetPx, flickRate)
end

return CarInputController
