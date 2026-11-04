--!nonstrict
-- DragControl: one finger, held, is the whole control
-- (docs/game/features/drift-model.md "The control", "How it plays" 2-4).
--
-- A finger goes down anywhere, or the mouse button does. From then until it comes up the
-- only thing that matters is its HORIZONTAL distance -- measured either from the middle of
-- the screen or from where it went down, which is `Config.Drift.InputMode` -- as a share
-- of a full travel. That share IS the car's rate of turn: the model multiplies it by
-- `MaxSteeringSpeed` and sets the yaw, so centring the finger stops the turn on the next
-- step and holding it out keeps the car rotating. Nothing here is a steering angle, a
-- weight to throw, a drift or a brake; the throttle is not an input at all and drives
-- itself inside the model.
--
-- Full travel is `SliderWidthMin`..`SliderWidthMax` of HALF the screen width, lerped by
-- `Sensitivity` (1..10) BACKWARDS: a higher sensitivity is a SHORTER travel, so the same
-- finger movement turns the car more. That inversion is the reference's and it is
-- deliberate.
--
-- `InvertSteering` is NOT applied here. The model owns it (Drift/Model.luau, at the one
-- line that sets the yaw rate), so what this returns is the raw signed share of the
-- travel -- positive is a finger to the right -- and the slider's knob can simply sit
-- where the finger is.
--
-- Touch and mouse are the same gesture and the same code. Keyboard and gamepad feed the
-- same single axis from CarInputController, scaled by `KeySensitivity`, because the model
-- only ever wanted one number.
--
-- Programmer art: the slider is Drift/SliderHud and exists only while the finger is down
-- (docs/workflow/UI.md). The two buttons are the handbrake, which is only there to stop
-- the car once a run is over, and the debug readout's toggle.
--
-- THE HANDBRAKE BUTTON IS A TOGGLE (T-041): one click or tap and the car brakes until it
-- stops and stays stopped, another and it drives off. This file does NOT hold that state.
-- It reports a PRESS to CarInputController and is told what to light up with `SetBrake`,
-- because the same toggle is also on a key and a gamepad button, and two latches would be
-- two answers. One owner, one state, one light.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.Config)
local SliderHud = require(script.Parent.SliderHud)

local DragControl = {}
DragControl.__index = DragControl

local PAD = Color3.fromRGB(30, 32, 38)
local LIVE = Color3.fromRGB(230, 90, 70)
local TEXT = Color3.fromRGB(235, 235, 240)

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function button(name: string, text: string, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = PAD
	b.BackgroundTransparency = 0.35
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = TEXT
	b.TextSize = 18
	b.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	b.AutoButtonColor = false
	b.Parent = parent
	return b
end

function DragControl.new(onDebugToggle: () -> (), onBrakePressed: (() -> ())?)
	local self = setmetatable({}, DragControl)
	self.steer = 0 -- the raw share of full travel, -1 .. 1, sign as the finger moved
	self.handbrake = false -- MIRRORED from CarInputController for the light; never read back
	self._onBrakePressed = onBrakePressed or function() end
	self._pointer = nil -- the InputObject being dragged, or nil
	self._originX = 0 -- where the finger went down, px (dynamic mode)
	self._x = 0 -- where it is now, px
	self._y = 0 -- and its height, for where the track is drawn
	self._mode = nil -- Studio-only overrides of the two settings (DebugSettings)
	self._sensitivity = nil
	self._onDebugToggle = onDebugToggle
	self._connections = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "DriftControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	self.hud = SliderHud.new(gui)
	self:_build()
	return self
end

-- The screen, in pixels. The ScreenGui ignores the inset, so its own size is the window's;
-- input positions do not, so the inset goes back on the Y to put the track under the
-- finger. Only the X matters to the steering.
function DragControl:_screen(): (number, number)
	local size = self.gui.AbsoluteSize
	if size.X < 1 then
		local camera = workspace.CurrentCamera
		size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	end
	return size.X, size.Y
end

-- A full finger, in pixels. `Sensitivity` 1..10 lerps the share of half the screen width
-- between `SliderWidthMax` and `SliderWidthMin` BACKWARDS, so 10 is the shortest travel.
-- `sensitivity` is a Studio-only override, for measuring the curve without editing Config.
function DragControl:TravelPx(sensitivity: number?): number
	local C = Config.Drift
	local width = self:_screen()
	local s = sensitivity or self._sensitivity or C.Sensitivity
	local t = clamp((s - 1) / 9, 0, 1)
	local share = C.SliderWidthMax + (C.SliderWidthMin - C.SliderWidthMax) * t
	return math.max(share * width * 0.5, 1)
end

function DragControl:Mode(): string
	return self._mode or Config.Drift.InputMode
end

-- Where the middle of the travel sits on screen this frame, in gui pixels.
function DragControl:CentreX(): number
	local width = self:_screen()
	if self:Mode() == "centred" then
		return width * 0.5
	end
	return self._originX
end

function DragControl:_build()
	local gui = self.gui

	-- The whole screen takes the drag. It sits under the buttons, so a thumb on the
	-- handbrake is a handbrake and not a steering input.
	local pad = Instance.new("Frame")
	pad.Name = "DragArea"
	pad.BackgroundTransparency = 0.99 -- not quite invisible, so touches actually arrive
	pad.BorderSizePixel = 0
	pad.Active = true
	pad.Size = UDim2.fromScale(1, 1)
	pad.ZIndex = 1
	pad.Parent = gui
	self.pad = pad

	-- Not part of the control: the handbrake only stops the car once a run is over
	-- (features/drift-model.md "How it plays" 2), and the readout's toggle is for us.
	local handbrake = button("Handbrake", "STOP", gui)
	handbrake.AnchorPoint = Vector2.new(1, 1)
	handbrake.Size = UDim2.fromOffset(96, 96)
	handbrake.Position = UDim2.new(1, -28, 1, -28)
	handbrake.ZIndex = 5
	local hbCorner = Instance.new("UICorner")
	hbCorner.CornerRadius = UDim.new(1, 0)
	hbCorner.Parent = handbrake
	self.handbrakeButton = handbrake

	local debugButton = button("DebugToggle", "DBG", gui)
	debugButton.Size = UDim2.fromOffset(64, 44)
	debugButton.AnchorPoint = Vector2.new(1, 0)
	debugButton.Position = UDim2.new(1, -16, 0, 64)
	debugButton.TextSize = 15
	debugButton.ZIndex = 5
	self.debugButton = debugButton

	local function connect(signal, fn)
		table.insert(self._connections, signal:Connect(fn))
	end

	local function isPointer(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
	end

	-- A PRESS, not a hold (T-041). Letting go does nothing: the state is the toggle's, and
	-- it comes back through `SetBrake`.
	connect(handbrake.InputBegan, function(input)
		if isPointer(input) then
			self._onBrakePressed()
		end
	end)
	connect(debugButton.Activated, function()
		self._onDebugToggle()
	end)

	connect(pad.InputBegan, function(input)
		if not isPointer(input) or self._pointer then
			return
		end
		self._pointer = input
		self._originX = input.Position.X
		self._y = input.Position.Y + GuiService:GetGuiInset().Y
		self:_move(input.Position.X)
	end)

	-- Touch reports its moves on the same InputObject; the mouse reports MouseMovement,
	-- which is a different object, so the mouse is matched by "a button is still down".
	connect(UserInputService.InputChanged, function(input)
		if not self._pointer then
			return
		end
		local ours = input == self._pointer
			or (
				self._pointer.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if ours then
			self._y = input.Position.Y + GuiService:GetGuiInset().Y
			self:_move(input.Position.X)
		end
	end)

	local function release(input)
		if not self._pointer then
			return
		end
		if input ~= self._pointer and input.UserInputType ~= self._pointer.UserInputType then
			return
		end
		self:_lift()
	end

	connect(pad.InputEnded, release)
	connect(UserInputService.InputEnded, release)
	-- A finger that leaves the window, or focus lost mid-drag, must not leave the car
	-- turning: the yaw rate IS the finger, so a stuck finger is a car that never stops
	-- rotating.
	connect(UserInputService.WindowFocusReleased, function()
		self:_lift()
	end)

	-- The slider is drawn here rather than by whoever reads the input, so it is right even
	-- on a frame the car is not being simulated at all.
	connect(RunService.RenderStepped, function(dt)
		self.hud:Update(dt, self._pointer ~= nil, self:CentreX(), self._y, self:TravelPx(), self.steer)
	end)
end

function DragControl:_lift()
	self._pointer = nil
	self.steer = 0
end

-- One move of the pointer: the whole control, in three lines.
function DragControl:_move(x: number)
	self._x = x
	local offset = x - self:CentreX()
	self.steer = clamp(offset / self:TravelPx(), -1, 1)
end

-- What the gesture is asking for: the car's rate of turn as a share of `MaxSteeringSpeed`,
-- before `InvertSteering`, which the model applies. The brake is NOT here -- it is a
-- toggle CarInputController owns, and handing a copy of it back would be a second answer.
function DragControl:Get(): number
	if not self._pointer then
		return 0
	end
	return self.steer
end

-- The toggle's state, pushed in by its owner: the button's light, and nothing else.
function DragControl:SetBrake(on: boolean)
	self.handbrake = on == true
	if self.handbrakeButton then
		self.handbrakeButton.BackgroundColor3 = if self.handbrake then LIVE else PAD
		self.handbrakeButton.Text = if self.handbrake then "GO" else "STOP"
	end
end

function DragControl:Down(): boolean
	return self._pointer ~= nil
end

function DragControl:DebugState()
	local width = self:_screen()
	return {
		down = self._pointer ~= nil,
		pointer = if self._pointer and self._pointer.UserInputType then self._pointer.UserInputType.Name else "none",
		mode = self:Mode(),
		sensitivity = self._sensitivity or Config.Drift.Sensitivity,
		steer = self.steer,
		travelPx = self:TravelPx(),
		centreX = self:CentreX(),
		originX = self._originX,
		x = self._x,
		offsetPx = self._x - self:CentreX(),
		screenWidth = width,
		handbrake = self.handbrake,
		slider = self.hud:DebugState(),
	}
end

-- Studio only: stand in for the settings screen that does not exist yet, so both input
-- modes and the whole sensitivity range can be measured without editing Config, which the
-- model and the camera read too. Either argument nil goes back to Config.
function DragControl:DebugSettings(mode: string?, sensitivity: number?)
	self._mode = mode
	self._sensitivity = sensitivity
	if self._pointer then
		self:_move(self._x)
	end
	return self:DebugState()
end

-- Studio only: act out the real gesture, so a test exercises the control the player uses
-- rather than the override that bypasses it (docs/workflow/TESTING.md). The finger goes
-- down at `originPx` across the screen, the middle of it by default, and moves `offsetPx`
-- from there -- which is what tells the two input modes apart, because only `dynamic`
-- measures from where the finger landed. `nil` lifts it.
function DragControl:DebugDrag(offsetPx: number?, originPx: number?)
	if offsetPx == nil then
		self:_lift()
		return self:DebugState()
	end
	local width, height = self:_screen()
	if not self._pointer then
		self._pointer = { UserInputType = Enum.UserInputType.Touch }
		self._originX = originPx or width * 0.5
		self._y = height * 0.8
	elseif originPx then
		self._originX = originPx
	end
	self:_move(self._originX + offsetPx)
	return self:DebugState()
end

-- Studio only: press the on-screen button, through the exact path a real tap takes, so a
-- test proves the BUTTON toggles rather than poking the toggle it reports to.
function DragControl:DebugPressBrake()
	self._onBrakePressed()
	return { brake = self.handbrake, buttonText = self.handbrakeButton and self.handbrakeButton.Text }
end

function DragControl:Destroy()
	for _, c in self._connections do
		c:Disconnect()
	end
	self.hud:Destroy()
	self.gui:Destroy()
end

return DragControl
