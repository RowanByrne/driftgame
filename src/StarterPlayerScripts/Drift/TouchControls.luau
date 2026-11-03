--!nonstrict
-- TouchControls: programmer-art touch controls for the prototype
-- (docs/game/features/drift-model.md "UI", docs/workflow/UI.md "Programmer art").
--
-- Plain frames and plain text. No art, no theme: the UI kit does not exist yet, and this
-- is here to be felt, not looked at.
--
-- Two schemes, switched by `Config.Drift.TouchScheme`, because the user picks between them
-- by feel ("Open questions"):
--   TwoThumb   the left half of the screen is a steering stick, the right half is drift
--   OneFinger  one finger anywhere: slide it sideways to steer, hold it down to drift
--
-- Both appear only while the player is actually using touch (`PreferredInput`), so a
-- desktop player never sees them, and a phone player who plugs in a gamepad loses them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local TouchControls = {}
TouchControls.__index = TouchControls

local PAD = Color3.fromRGB(30, 32, 38)
local KNOB = Color3.fromRGB(150, 155, 165)
local LIVE = Color3.fromRGB(230, 90, 70)
local TEXT = Color3.fromRGB(235, 235, 240)

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

function TouchControls.new(onDebugToggle: () -> ())
	local self = setmetatable({}, TouchControls)
	self.steer = 0
	self.drift = false
	self.brake = false
	self.scheme = Config.Drift.TouchScheme
	self._steerTouch = nil :: InputObject?
	self._steerOrigin = Vector2.zero
	self._onDebugToggle = onDebugToggle
	self._connections = {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "DriftTouchControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	self:_build()
	self:_watchInput()
	return self
end

function TouchControls:_build()
	local C = Config.Drift
	local gui = self.gui

	-- Steering: the left half in TwoThumb, the whole screen in OneFinger.
	local pad = frame("SteerPad", gui)
	-- Not quite invisible, and Active, so touches on it actually arrive.
	pad.BackgroundTransparency = 0.99
	pad.Active = true
	if self.scheme == "OneFinger" then
		pad.Size = UDim2.fromScale(1, 1)
		pad.Position = UDim2.fromScale(0, 0)
	else
		pad.Size = UDim2.fromScale(0.45, 1)
		pad.Position = UDim2.fromScale(0, 0)
	end
	self.pad = pad

	local ring = frame("Ring", pad)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(C.TouchStickRadius * 2, C.TouchStickRadius * 2)
	ring.Position = UDim2.fromScale(0.5, 0.72)
	ring.Visible = self.scheme ~= "OneFinger"
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	self.ring = ring

	local knob = frame("Knob", ring)
	knob.BackgroundColor3 = KNOB
	knob.BackgroundTransparency = 0.2
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(70, 70)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob
	self.knob = knob

	-- Drift: the right half in TwoThumb. In OneFinger the whole screen is the drift hold,
	-- so the button is only a reminder of what the finger is doing.
	local driftButton = button("Drift", "DRIFT", gui)
	driftButton.AnchorPoint = Vector2.new(1, 1)
	driftButton.Size = UDim2.fromOffset(190, 190)
	driftButton.Position = UDim2.new(1, -28, 1, -28)
	local driftCorner = Instance.new("UICorner")
	driftCorner.CornerRadius = UDim.new(1, 0)
	driftCorner.Parent = driftButton
	driftButton.Active = self.scheme ~= "OneFinger"
	self.driftButton = driftButton

	local brakeButton = button("Brake", "BRAKE", gui)
	brakeButton.AnchorPoint = Vector2.new(1, 1)
	brakeButton.Size = UDim2.fromOffset(110, 110)
	brakeButton.Position = UDim2.new(1, -236, 1, -28)
	local brakeCorner = Instance.new("UICorner")
	brakeCorner.CornerRadius = UDim.new(1, 0)
	brakeCorner.Parent = brakeButton
	self.brakeButton = brakeButton

	local debugButton = button("DebugToggle", "DBG", gui)
	debugButton.Size = UDim2.fromOffset(64, 48)
	debugButton.AnchorPoint = Vector2.new(1, 0)
	debugButton.Position = UDim2.new(1, -16, 0, 64)
	debugButton.TextSize = 16
	self.debugButton = debugButton

	local function hold(b: TextButton, set: (boolean) -> ())
		table.insert(
			self._connections,
			b.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					set(true)
					b.BackgroundColor3 = LIVE
				end
			end)
		)
		table.insert(
			self._connections,
			b.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					set(false)
					b.BackgroundColor3 = PAD
				end
			end)
		)
	end

	hold(driftButton, function(down)
		if self.scheme ~= "OneFinger" then
			self.drift = down
		end
	end)
	hold(brakeButton, function(down)
		self.brake = down
	end)

	table.insert(
		self._connections,
		debugButton.Activated:Connect(function()
			self._onDebugToggle()
		end)
	)

	table.insert(
		self._connections,
		pad.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			self._steerTouch = input
			self._steerOrigin = Vector2.new(input.Position.X, input.Position.Y)
			if self.scheme == "OneFinger" then
				self.drift = true
				driftButton.BackgroundColor3 = LIVE
			else
				ring.Position = UDim2.fromOffset(
					self._steerOrigin.X - pad.AbsolutePosition.X,
					self._steerOrigin.Y - pad.AbsolutePosition.Y
				)
			end
		end)
	)

	local function endSteer(input)
		if self._steerTouch ~= input then
			return
		end
		self._steerTouch = nil
		self.steer = 0
		self.knob.Position = UDim2.fromScale(0.5, 0.5)
		if self.scheme == "OneFinger" then
			self.drift = false
			driftButton.BackgroundColor3 = PAD
		end
	end

	table.insert(self._connections, pad.InputEnded:Connect(endSteer))
	table.insert(
		self._connections,
		UserInputService.TouchEnded:Connect(function(input)
			endSteer(input)
		end)
	)

	table.insert(
		self._connections,
		UserInputService.TouchMoved:Connect(function(input)
			if self._steerTouch ~= input then
				return
			end
			local dx = input.Position.X - self._steerOrigin.X
			local axis = math.clamp(dx / C.TouchStickRadius, -1, 1)
			if math.abs(axis) < C.TouchDeadzone then
				axis = 0
			end
			self.steer = axis
			self.knob.Position = UDim2.new(0.5, axis * C.TouchStickRadius, 0.5, 0)
		end)
	)
end

function TouchControls:_watchInput()
	local function update()
		self.gui.Enabled = UserInputService.PreferredInput == Enum.PreferredInput.Touch
		if not self.gui.Enabled then
			self.steer, self.drift, self.brake = 0, false, false
		end
	end
	table.insert(self._connections, UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(update))
	update()
end

function TouchControls:Get(): (number, boolean, boolean)
	if not self.gui.Enabled then
		return 0, false, false
	end
	return self.steer, self.drift, self.brake
end

function TouchControls:Destroy()
	for _, c in self._connections do
		c:Disconnect()
	end
	self.gui:Destroy()
end

return TouchControls
