--!nonstrict
-- DragControl: the whole control scheme, in one gesture
-- (docs/game/DECISIONS.md, 2026-11-03; features/drift-model.md "How it plays").
--
-- A finger goes down, or the mouse button does. From then until it comes up, the only
-- thing that matters is how far across the screen it has moved from where it went down.
-- That horizontal offset is the entire control:
--
--   a little offset steers;
--   past `DriftOffset`, or flicked across faster than `DriftFlickRate`, the rear lets go;
--   holding the offset holds the slide, and how far out it is sets how wide the slide runs;
--   easing back toward the middle is the counter-steer, not a second mode;
--   lifting the finger hooks the rear back up over `GripBlendOut`.
--
-- Touch and mouse run the same code, because they are the same gesture and there is no
-- sense in tuning two of them. Keyboard and gamepad keep their own bindings in
-- CarInputController, so every device works (docs/workflow/CODING.md "Conventions").
--
-- Programmer art: a track, a knob, and a word that lights up (docs/workflow/UI.md). The
-- UI kit does not exist yet and this is here to be felt, not looked at.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local DragControl = {}
DragControl.__index = DragControl

local PAD = Color3.fromRGB(30, 32, 38)
local KNOB = Color3.fromRGB(150, 155, 165)
local LIVE = Color3.fromRGB(230, 90, 70)
local TEXT = Color3.fromRGB(235, 235, 240)

local function clamp(x, lo, hi)
	return math.max(lo, math.min(hi, x))
end

local function frame(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = PAD
	f.BackgroundTransparency = 0.55
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function button(name: string, text: string, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = PAD
	b.BackgroundTransparency = 0.35
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = TEXT
	b.TextSize = 20
	b.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	b.AutoButtonColor = false
	b.Parent = parent
	return b
end

function DragControl.new(onDebugToggle: () -> ())
	local self = setmetatable({}, DragControl)
	self.steer = 0
	self.drift = false
	self.brake = false
	self._pointer = nil -- the InputObject being dragged, or "mouse"
	self._originX = 0
	self._lastX = 0
	self._flick = 0 -- px/s, smoothed
	self._latched = false -- the rear has let go and stays gone while the finger is down
	self._onDebugToggle = onDebugToggle
	self._connections = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "DriftControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	self:_build()
	return self
end

function DragControl:_build()
	local C = Config.Drift
	local gui = self.gui

	-- The whole screen takes the drag. It sits under the buttons, so a thumb on BRAKE is a
	-- brake and not a steering input.
	local pad = frame("DragArea", gui)
	pad.BackgroundTransparency = 0.99 -- not quite invisible, so touches actually arrive
	pad.Active = true
	pad.Size = UDim2.fromScale(1, 1)
	pad.ZIndex = 1
	self.pad = pad

	-- The readout of the gesture: a track with the middle marked, and a knob on it. It
	-- only appears while a finger or the mouse is actually down.
	local track = frame("Track", gui)
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -60)
	track.Size = UDim2.fromOffset(C.DragFullLock * 2 + 60, 14)
	track.ZIndex = 2
	track.Visible = false
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	self.track = track

	local centre = frame("Centre", track)
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.Position = UDim2.fromScale(0.5, 0.5)
	centre.Size = UDim2.fromOffset(3, 22)
	centre.BackgroundColor3 = TEXT
	centre.BackgroundTransparency = 0.4
	centre.ZIndex = 3

	local knob = frame("Knob", track)
	knob.BackgroundColor3 = KNOB
	knob.BackgroundTransparency = 0.1
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(56, 56)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.ZIndex = 4
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob
	self.knob = knob

	local label = Instance.new("TextLabel")
	label.Name = "State"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0, -8)
	label.Size = UDim2.fromOffset(200, 22)
	label.TextColor3 = TEXT
	label.TextSize = 18
	label.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	label.Text = ""
	label.ZIndex = 4
	label.Parent = track
	self.label = label

	-- Brake and reverse keep their own input: the decision is that *one* input does the
	-- steering and the drift, not that there is only one input (DECISIONS.md, 2026-11-03).
	local brakeButton = button("Brake", "BRAKE", gui)
	brakeButton.AnchorPoint = Vector2.new(1, 1)
	brakeButton.Size = UDim2.fromOffset(120, 120)
	brakeButton.Position = UDim2.new(1, -28, 1, -28)
	brakeButton.ZIndex = 5
	local brakeCorner = Instance.new("UICorner")
	brakeCorner.CornerRadius = UDim.new(1, 0)
	brakeCorner.Parent = brakeButton
	self.brakeButton = brakeButton

	local debugButton = button("DebugToggle", "DBG", gui)
	debugButton.Size = UDim2.fromOffset(64, 48)
	debugButton.AnchorPoint = Vector2.new(1, 0)
	debugButton.Position = UDim2.new(1, -16, 0, 64)
	debugButton.TextSize = 16
	debugButton.ZIndex = 5
	self.debugButton = debugButton

	local function connect(signal, fn)
		table.insert(self._connections, signal:Connect(fn))
	end

	local function pointerType(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
	end

	connect(brakeButton.InputBegan, function(input)
		if pointerType(input) then
			self.brake = true
			brakeButton.BackgroundColor3 = LIVE
		end
	end)
	connect(brakeButton.InputEnded, function(input)
		if pointerType(input) then
			self.brake = false
			brakeButton.BackgroundColor3 = PAD
		end
	end)
	connect(debugButton.Activated, function()
		self._onDebugToggle()
	end)

	connect(pad.InputBegan, function(input)
		if not pointerType(input) or self._pointer then
			return
		end
		self._pointer = input
		self._originX = input.Position.X
		self._lastX = input.Position.X
		self._flick = 0
		self._latched = false
		self.steer = 0
		track.Visible = true
		self:_draw()
	end)

	-- Touch reports its moves on the same InputObject; the mouse reports MouseMovement,
	-- which is a different object, so the mouse is matched by "a button is still down".
	connect(UserInputService.InputChanged, function(input)
		if not self._pointer then
			return
		end
		local isOurs = input == self._pointer
			or (
				self._pointer.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if isOurs then
			self:_move(input.Position.X)
		end
	end)

	local function release(input)
		if not self._pointer then
			return
		end
		local isOurs = input == self._pointer or input.UserInputType == self._pointer.UserInputType
		if not isOurs then
			return
		end
		self._pointer = nil
		self._latched = false
		self.steer = 0
		self._flick = 0
		track.Visible = false
	end

	connect(pad.InputEnded, release)
	connect(UserInputService.InputEnded, release)
	-- A finger that leaves the window, or focus lost mid-drag, must not leave the car
	-- locked over: the slide would hold with nobody holding it.
	connect(UserInputService.WindowFocusReleased, function()
		self._pointer = nil
		self._latched = false
		self.steer = 0
		track.Visible = false
	end)
end

-- One move of the pointer. `dt` is not available here, so the flick rate is measured
-- against the clock: this fires far more often than a frame does.
function DragControl:_move(x: number)
	local C = Config.Drift
	local now = os.clock()
	local dt = math.max(now - (self._lastMove or now - 1 / 60), 1 / 1000)
	self._lastMove = now

	local rate = math.abs(x - self._lastX) / dt
	local alpha = 1 - math.exp(-dt / math.max(C.DriftFlickSmoothing, 1e-3))
	self._flick += (rate - self._flick) * alpha
	self._lastX = x

	local offset = x - self._originX
	local steer = clamp(offset / math.max(C.DragFullLock, 1), -1, 1)
	if math.abs(steer) < C.DragDeadzone then
		steer = 0
	end
	self.steer = steer

	-- Two ways in, both tunable, so which one dominates is a number and not a decision
	-- buried in here: hold it far enough out, or snap it across fast enough.
	if not self._latched then
		if math.abs(steer) >= C.DriftOffset or self._flick >= C.DriftFlickRate then
			self._latched = true
		end
	end

	self:_draw()
end

function DragControl:_draw()
	local C = Config.Drift
	self.knob.Position = UDim2.new(0.5, self.steer * C.DragFullLock, 0.5, 0)
	local live = self._latched
	self.knob.BackgroundColor3 = live and LIVE or KNOB
	self.label.Text = if live
		then ("DRIFT  %+.0f%%"):format(self.steer * 100)
		else ("steer  %+.0f%%"):format(self.steer * 100)
	self.label.TextColor3 = live and LIVE or TEXT
end

-- What the gesture is asking for. The drift stays latched while the pointer is down, which
-- is what makes easing back toward the middle a counter-steer instead of an exit.
function DragControl:Get(): (number, boolean, boolean)
	if not self._pointer then
		return 0, false, self.brake
	end
	return self.steer, self._latched, self.brake
end

function DragControl:DebugState()
	return {
		dragging = self._pointer ~= nil,
		pointer = if self._pointer then self._pointer.UserInputType.Name else "none",
		steer = self.steer,
		latched = self._latched,
		flickRate = self._flick,
		brake = self.brake,
		offsetPx = self.steer * Config.Drift.DragFullLock,
	}
end

-- Studio only: act out a drag, so an agent playtest can drive the real control path
-- rather than the override behind it (docs/workflow/TESTING.md).
function DragControl:DebugDrag(offsetPx: number?, flickRate: number?)
	if offsetPx == nil then
		self._pointer = nil
		self._latched = false
		self.steer = 0
		self.track.Visible = false
		return self:DebugState()
	end
	self._pointer = self._pointer or { UserInputType = Enum.UserInputType.Touch }
	self._flick = flickRate or 0
	self._lastX = offsetPx
	self._originX = 0
	local C = Config.Drift
	local steer = clamp(offsetPx / math.max(C.DragFullLock, 1), -1, 1)
	self.steer = if math.abs(steer) < C.DragDeadzone then 0 else steer
	if math.abs(self.steer) >= C.DriftOffset or self._flick >= C.DriftFlickRate then
		self._latched = true
	end
	self.track.Visible = true
	self:_draw()
	return self:DebugState()
end

function DragControl:Destroy()
	for _, c in self._connections do
		c:Disconnect()
	end
	self.gui:Destroy()
end

return DragControl
