--!nonstrict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme, Glass, Create = require(UI:WaitForChild("Theme")), require(UI:WaitForChild("Glass")), require(UI:WaitForChild("Create"))
local Layers = require(UI:WaitForChild("Layers"))
local View = {}
View.__index = View

local function rect(object, x, y, w, h)
	object.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	object.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
end

-- A slider: a clear button holding its track, the track's fill and a knob.
local function makeSlider(name, parent)
	local slider = Glass.button(name, parent, "")
	slider.BackgroundTransparency = 1
	slider.Rim.Transparency = 1
	local track = Create("Frame", { Name = "Track", BackgroundColor3 = Theme.Color.Track, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromScale(0, 0.5) }, slider)
	Create("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
	local fill = Create("Frame", { Name = "Fill", BackgroundColor3 = Theme.Color.Accent, BorderSizePixel = 0,
		Size = UDim2.fromScale(0.5, 1) }, track)
	Create("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	local knob = Create("Frame", { Name = "Knob", BackgroundColor3 = Theme.Color.Text, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20), Position = UDim2.fromScale(0.5, 0.5) }, slider)
	Create("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
	return slider, track, fill, knob
end

-- The Sound tab's rows, in order (T-256). `key` is the `Drift/SoundLevels` category.
local SOUND_ROWS = {
	{ key = "Music", label = "Music", note = "No music plays yet. This level is kept for when it does." },
	{ key = "TireSqueal", label = "Tire squeal" },
	{ key = "OffRoad", label = "Off-road drift", note = "Sliding on grass, dirt and gravel." },
	{ key = "Suspension", label = "Suspension", note = "Bumps, kerbs and landing from a jump." },
	{ key = "Engine", label = "Engine" },
}
local SOUND_STEP = 10

function View.new(parent)
	local self = setmetatable({ ActionRequested = Signal.new(), connections = {}, offsets = {}, data = {}, opened = false }, View)
	self.gui = Create("ScreenGui", { Name = "Settings", ResetOnSpawn = false, IgnoreGuiInset = true,
		ClipToDeviceSafeArea = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = Layers.Settings }, parent)
	-- IgnoreGuiInset also writes ScreenInsets; set the final policy after construction.
	self.gui.ScreenInsets = Enum.ScreenInsets.None
	self.entry = Glass.button("OpenSettings", self.gui, "Settings")
	self.entry:SetAttribute("LayoutItem", "SettingsEntry")
	self.entry.Activated:Connect(function() self.ActionRequested:Fire("open") end)
	self.modal = Create("Frame", { Name = "Modal", BackgroundColor3 = Theme.Color.Surface,
		BackgroundTransparency = 0.9, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Active = true,
		Visible = false }, self.gui)
	self.modal:SetAttribute("GlassTransparency", 0.9)
	self.root = self.modal
	self.pane = Glass.panel("Pane", self.modal)
	self.pane.Active = true
	self.pane:SetAttribute("LayoutGroup", "SettingsPane")
	self.title = Glass.label("Title", self.pane, "Settings", true)
	self.subtitle = Glass.label("Subtitle", self.pane, "Make the drive yours")
	self.subtitle.TextColor3 = Theme.Color.Secondary
	self.close = Glass.button("Close", self.pane, "X")
	self.close.Activated:Connect(function() self.ActionRequested:Fire("close") end)
	self.navSteer = Glass.button("SteeringTab", self.pane, "Steering")
	self.navUI = Glass.button("InterfaceTab", self.pane, "Interface")
	self.navGfx = Glass.button("GraphicsTab", self.pane, "Graphics")
	self.navSnd = Glass.button("SoundTab", self.pane, "Sound")
	for _, pair in { {self.navSteer, "steering"}, {self.navUI, "interface"}, {self.navGfx, "graphics"}, {self.navSnd, "sound"} } do
		pair[1].Activated:Connect(function() self.ActionRequested:Fire("category", pair[2]) end)
	end
	self.scroll = Create("ScrollingFrame", { Name = "Content", BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Color.Secondary,
		CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, Active = true,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable }, self.pane)
	self.steering = Glass.panel("DrivingControls", self.scroll, true)
	self.heading = Glass.label("Heading", self.steering, "Driving controls", true)
	self.modeLabel = Glass.label("ModeLabel", self.steering, "Steering mode")
	self.dynamic = Glass.button("Dynamic", self.steering, "Dynamic")
	self.centred = Glass.button("Centred", self.steering, "Centred")
	self.dynamic.Activated:Connect(function() self.ActionRequested:Fire("mode", "dynamic") end)
	self.centred.Activated:Connect(function() self.ActionRequested:Fire("mode", "centred") end)
	self.modeNote = Glass.label("ModeNote", self.steering, "")
	self.modeNote.TextColor3 = Theme.Color.Secondary
	self.sensitivityLabel = Glass.label("SensitivityLabel", self.steering, "Pointer sensitivity")
	self.value = Glass.label("Value", self.steering, "5", true)
	self.value.TextXAlignment = Enum.TextXAlignment.Right
	self.minus = Glass.button("Decrease", self.steering, "-")
	self.plus = Glass.button("Increase", self.steering, "+")
	self.slider, self.track, self.fill, self.knob = makeSlider("Sensitivity", self.steering)
	self.range = Glass.label("Range", self.steering, "1                                                  10")
	self.range.TextColor3 = Theme.Color.Secondary
	self.note = Glass.label("Note", self.steering, "Higher sensitivity means shorter finger travel.")
	self.note.TextColor3 = Theme.Color.Secondary
	self.minus.Activated:Connect(function() self:nudge(-1) end)
	self.plus.Activated:Connect(function() self:nudge(1) end)
	self.slider.InputBegan:Connect(function(input)
		if self.opened and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			self.drag, self.dragSlider = input, self.slider
			self:_fromX(input.Position.X)
		end
	end)
	self.interface = Glass.panel("InterfaceControls", self.scroll, true)
	self.uiHeading = Glass.label("Heading", self.interface, "Interface", true)
	self.uiLabel = Glass.label("ShortcutLabel", self.interface, "Hide / restore game UI")
	self.keycap = Glass.label("Keycap", self.interface, "P", true)
	self.keycap.TextXAlignment = Enum.TextXAlignment.Center
	self.keycap.BackgroundColor3 = Theme.Color.Tile
	self.keycap.BackgroundTransparency = 0
	Create("UICorner", { CornerRadius = UDim.new(0, 8) }, self.keycap)
	Create("UIStroke", { Color = Theme.Color.Rim }, self.keycap)
	self.uiNote = Glass.label("ShortcutNote", self.interface,
		"Press P on a keyboard to hide or restore the game UI. Driving stays available. The shortcut waits while you type or use the Roblox menu.")
	self.uiNote.TextColor3 = Theme.Color.Secondary
	-- Graphics: how far ahead and round the car the ground stays sharp (T-225)
	self.graphics = Glass.panel("GraphicsControls", self.scroll, true)
	self.gfxHeading = Glass.label("Heading", self.graphics, "Graphics", true)
	self.groundLabel = Glass.label("GroundLabel", self.graphics, "Ground detail")
	self.groundValue = Glass.label("GroundValue", self.graphics, "Medium", true)
	self.groundValue.TextXAlignment = Enum.TextXAlignment.Right
	self.groundMinus = Glass.button("GroundDecrease", self.graphics, "-")
	self.groundPlus = Glass.button("GroundIncrease", self.graphics, "+")
	self.groundSlider, self.groundTrack, self.groundFill, self.groundKnob = makeSlider("GroundDetail", self.graphics)
	self.groundRange = Glass.label("GroundRange", self.graphics, "Light - Ultra")
	self.groundRange.TextColor3 = Theme.Color.Secondary
	self.groundNote = Glass.label("GroundNote", self.graphics,
		"How far ahead along the road, and around you, the ground stays sharp. Higher looks further but costs more on slower devices.")
	self.groundNote.TextColor3 = Theme.Color.Secondary
	self.groundMinus.Activated:Connect(function() self:nudgeGround(-1) end)
	self.groundPlus.Activated:Connect(function() self:nudgeGround(1) end)
	self.groundSlider.InputBegan:Connect(function(input)
		if self.opened and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			self.drag, self.dragSlider = input, self.groundSlider
			self:_fromX(input.Position.X)
		end
	end)
	-- Graphics: how far ahead of the car the road is drawn (T-263)
	self.aheadLabel = Glass.label("AheadLabel", self.graphics, "Road ahead")
	self.aheadValue = Glass.label("AheadValue", self.graphics, "Medium", true)
	self.aheadValue.TextXAlignment = Enum.TextXAlignment.Right
	self.aheadMinus = Glass.button("AheadDecrease", self.graphics, "-")
	self.aheadPlus = Glass.button("AheadIncrease", self.graphics, "+")
	self.aheadSlider, self.aheadTrack, self.aheadFill, self.aheadKnob = makeSlider("RoadAhead", self.graphics)
	self.aheadRange = Glass.label("AheadRange", self.graphics, "Short - Longest")
	self.aheadRange.TextColor3 = Theme.Color.Secondary
	self.aheadNote = Glass.label("AheadNote", self.graphics,
		"How far ahead the road and its ground are drawn. Longer shows more of what's coming but costs more on slower devices.")
	self.aheadNote.TextColor3 = Theme.Color.Secondary
	self.aheadMinus.Activated:Connect(function() self:nudgeAhead(-1) end)
	self.aheadPlus.Activated:Connect(function() self:nudgeAhead(1) end)
	self.aheadSlider.InputBegan:Connect(function(input)
		if self.opened and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			self.drag, self.dragSlider = input, self.aheadSlider
			self:_fromX(input.Position.X)
		end
	end)
	-- Graphics: how far back the road stays drawn behind the car (T-230)
	self.behindLabel = Glass.label("BehindLabel", self.graphics, "Road behind")
	self.behindValue = Glass.label("BehindValue", self.graphics, "Short", true)
	self.behindValue.TextXAlignment = Enum.TextXAlignment.Right
	self.behindMinus = Glass.button("BehindDecrease", self.graphics, "-")
	self.behindPlus = Glass.button("BehindIncrease", self.graphics, "+")
	self.behindSlider, self.behindTrack, self.behindFill, self.behindKnob = makeSlider("RoadBehind", self.graphics)
	self.behindRange = Glass.label("BehindRange", self.graphics, "Short - Longest")
	self.behindRange.TextColor3 = Theme.Color.Secondary
	self.behindNote = Glass.label("BehindNote", self.graphics,
		"How far back the road and its ground stay drawn when you look or turn around. Longer uses more memory on slower devices.")
	self.behindNote.TextColor3 = Theme.Color.Secondary
	self.behindMinus.Activated:Connect(function() self:nudgeBehind(-1) end)
	self.behindPlus.Activated:Connect(function() self:nudgeBehind(1) end)
	self.behindSlider.InputBegan:Connect(function(input)
		if self.opened and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			self.drag, self.dragSlider = input, self.behindSlider
			self:_fromX(input.Position.X)
		end
	end)
	-- Sound: one volume slider per category, 0-100% (T-256)
	self.sound = Glass.panel("SoundControls", self.scroll, true)
	self.sndHeading = Glass.label("Heading", self.sound, "Sound", true)
	self.soundRows = {}
	for _, row in SOUND_ROWS do
		local key = row.key
		local r = { key = key }
		r.label = Glass.label(key .. "Label", self.sound, row.label)
		r.value = Glass.label(key .. "Value", self.sound, "30%", true)
		r.value.TextXAlignment = Enum.TextXAlignment.Right
		r.minus = Glass.button(key .. "Decrease", self.sound, "-")
		r.plus = Glass.button(key .. "Increase", self.sound, "+")
		r.slider, r.track, r.fill, r.knob = makeSlider(key .. "Volume", self.sound)
		r.slider:SetAttribute("SoundKey", key)
		if row.note then
			r.note = Glass.label(key .. "Note", self.sound, row.note)
			r.note.TextColor3 = Theme.Color.Secondary
		end
		r.minus.Activated:Connect(function() self:nudgeSound(key, -1) end)
		r.plus.Activated:Connect(function() self:nudgeSound(key, 1) end)
		r.slider.InputBegan:Connect(function(input)
			if self.opened and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				self.drag, self.dragSlider = input, r.slider
				self:_fromX(input.Position.X)
			end
		end)
		table.insert(self.soundRows, r)
	end
	self.back = Glass.button("Back", self.pane, "Back to drive")
	self.back.Activated:Connect(function() self.ActionRequested:Fire("close") end)
	self.session = Glass.label("Session", self.pane, "Session only")
	self.session.TextColor3 = Theme.Color.Secondary
	self.session.TextXAlignment = Enum.TextXAlignment.Right
	for _, object in {self.navSteer, self.navUI, self.navGfx, self.navSnd, self.close, self.back, self.steering, self.interface, self.graphics, self.sound} do object:SetAttribute("LayoutItem", object.Name) end
	self:_connect(UserInputService.InputChanged, function(input)
		if self.drag and self.opened and self.modal.AbsoluteSize.X > 1 then
			if input == self.drag or (self.drag.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then self:_fromX(input.Position.X) end
		end
	end)
	self:_connect(UserInputService.InputEnded, function(input)
		if input == self.drag or input.UserInputType == Enum.UserInputType.MouseButton1 then self:cancelDrag() end
	end)
	self:_connect(UserInputService.WindowFocusReleased, function() self:cancelDrag() end)
	self:_connect(self.gui:GetPropertyChangedSignal("AbsoluteSize"), function() self:cancelDrag(); self:_layout() end)
	for _, property in {"PreferredTextSize", "PreferredTransparency"} do
		self:_connect(GuiService:GetPropertyChangedSignal(property), function() self:cancelDrag(); self:_layout() end)
	end
	self:setData({category = "steering", mode = "dynamic", sensitivity = 5})
	return self
end

function View:_connect(signal, fn) table.insert(self.connections, signal:Connect(fn)) end
function View:_groundCount() return #(self.data.groundNames or {}) > 0 and #self.data.groundNames or 5 end
function View:_behindCount() return #(self.data.behindNames or {}) > 0 and #self.data.behindNames or 4 end
function View:_aheadCount() return #(self.data.aheadNames or {}) > 0 and #self.data.aheadNames or 4 end
function View:_fromX(x)
	local slider = self.dragSlider or self.slider
	local width = slider.AbsoluteSize.X
	if width <= 1 then return end
	local t = math.clamp((x - slider.AbsolutePosition.X) / width, 0, 1)
	local soundKey = slider:GetAttribute("SoundKey")
	if soundKey then
		self.ActionRequested:Fire("soundLevel", soundKey, math.floor(t * 100 + 0.5))
	elseif slider == self.groundSlider then
		local count = self:_groundCount()
		self.ActionRequested:Fire("groundDetail", math.floor(1 + t * (count - 1) + 0.5))
	elseif slider == self.behindSlider then
		local count = self:_behindCount()
		self.ActionRequested:Fire("roadBehind", math.floor(1 + t * (count - 1) + 0.5))
	elseif slider == self.aheadSlider then
		local count = self:_aheadCount()
		self.ActionRequested:Fire("roadAhead", math.floor(1 + t * (count - 1) + 0.5))
	else
		self.ActionRequested:Fire("sensitivity", math.floor(1 + t * 9 + 0.5))
	end
end
function View:nudge(delta)
	if self.opened then self.ActionRequested:Fire("sensitivity", math.clamp((self.data.sensitivity or 5) + delta, 1, 10)) end
end
function View:nudgeGround(delta)
	if self.opened then self.ActionRequested:Fire("groundDetail", math.clamp((self.data.groundDetail or 3) + delta, 1, self:_groundCount())) end
end
function View:nudgeBehind(delta)
	if self.opened then self.ActionRequested:Fire("roadBehind", math.clamp((self.data.roadBehind or 1) + delta, 1, self:_behindCount())) end
end
function View:nudgeAhead(delta)
	if self.opened then self.ActionRequested:Fire("roadAhead", math.clamp((self.data.roadAhead or 2) + delta, 1, self:_aheadCount())) end
end
function View:_soundLevel(key) return (self.data.soundLevels or {})[key] or 30 end
-- +/- moves a sound level to the next whole step of 10%.
function View:nudgeSound(key, delta)
	if not self.opened then return end
	local level = self:_soundLevel(key)
	local target = if delta > 0 then math.floor(level / SOUND_STEP + 1e-6) * SOUND_STEP + SOUND_STEP
		else math.ceil(level / SOUND_STEP - 1e-6) * SOUND_STEP - SOUND_STEP
	self.ActionRequested:Fire("soundLevel", key, math.clamp(target, 0, 100))
end
-- Left/right on a focused slider: true if one was focused.
function View:nudgeSelected(delta)
	local selected = GuiService.SelectedObject
	local soundKey = selected and selected:GetAttribute("SoundKey")
	if soundKey then self:nudgeSound(soundKey, delta); return true end
	if selected == self.slider then self:nudge(delta); return true end
	if selected == self.groundSlider then self:nudgeGround(delta); return true end
	if selected == self.aheadSlider then self:nudgeAhead(delta); return true end
	if selected == self.behindSlider then self:nudgeBehind(delta); return true end
	return false
end
function View:cancelDrag() self.drag = nil; self.dragSlider = nil end

function View:setData(data)
	local changedCategory = self.data.category ~= data.category
	self.data = table.clone(data)
	self.data.category = self.data.category or "steering"
	self.dynamic:SetAttribute("Selected", data.mode ~= "centred")
	self.centred:SetAttribute("Selected", data.mode == "centred")
	self.navSteer:SetAttribute("Selected", self.data.category == "steering")
	self.navUI:SetAttribute("Selected", self.data.category == "interface")
	self.value.Text = tostring(data.sensitivity or 5)
	local t = ((data.sensitivity or 5) - 1) / 9
	self.fill.Size = UDim2.fromScale(t, 1)
	self.knob.Position = UDim2.fromScale(t, 0.5)
	self.modeLabel.Text = data.modeLabel or "Steering mode"
	self.sensitivityLabel.Text = data.sensitivityLabel or "Pointer sensitivity"
	self.modeNote.Text = if data.mode == "centred" then "Steer from the middle of your screen." else "Steer from where you first touch."
	self.note.Text = data.note or "Higher sensitivity means shorter finger travel. Keyboard and gamepad steering keep their current response."
	self.navGfx:SetAttribute("Selected", self.data.category == "graphics")
	local count = self:_groundCount()
	local ground = math.clamp(data.groundDetail or 3, 1, count)
	self.groundValue.Text = if data.groundNames then data.groundNames[ground] else tostring(ground)
	local g = (ground - 1) / math.max(count - 1, 1)
	self.groundFill.Size = UDim2.fromScale(g, 1)
	self.groundKnob.Position = UDim2.fromScale(g, 0.5)
	self.groundRange.Text = if data.groundNames then data.groundNames[1] .. " - " .. data.groundNames[count] else "1 - " .. count
	local aheadCount = self:_aheadCount()
	local ahead = math.clamp(data.roadAhead or 2, 1, aheadCount)
	self.aheadValue.Text = if data.aheadNames then data.aheadNames[ahead] else tostring(ahead)
	local a = (ahead - 1) / math.max(aheadCount - 1, 1)
	self.aheadFill.Size = UDim2.fromScale(a, 1)
	self.aheadKnob.Position = UDim2.fromScale(a, 0.5)
	self.aheadRange.Text = if data.aheadNames then data.aheadNames[1] .. " - " .. data.aheadNames[aheadCount] else "1 - " .. aheadCount
	local behindCount = self:_behindCount()
	local behind = math.clamp(data.roadBehind or 1, 1, behindCount)
	self.behindValue.Text = if data.behindNames then data.behindNames[behind] else tostring(behind)
	local b = (behind - 1) / math.max(behindCount - 1, 1)
	self.behindFill.Size = UDim2.fromScale(b, 1)
	self.behindKnob.Position = UDim2.fromScale(b, 0.5)
	self.behindRange.Text = if data.behindNames then data.behindNames[1] .. " - " .. data.behindNames[behindCount] else "1 - " .. behindCount
	self.navSnd:SetAttribute("Selected", self.data.category == "sound")
	for _, r in self.soundRows do
		local level = math.clamp(self:_soundLevel(r.key), 0, 100)
		r.value.Text = level .. "%"
		r.fill.Size = UDim2.fromScale(level / 100, 1)
		r.knob.Position = UDim2.fromScale(level / 100, 0.5)
	end
	self.steering.Visible = self.data.category == "steering"
	self.interface.Visible = self.data.category == "interface"
	self.graphics.Visible = self.data.category == "graphics"
	self.sound.Visible = self.data.category == "sound"
	if changedCategory then
		self:cancelDrag()
		self.scroll.CanvasPosition = Vector2.zero
		-- Focus left on a page that just hid goes to the tab of the page now showing.
		local selected = GuiService.SelectedObject
		local tabs = {steering = self.navSteer, interface = self.navUI, graphics = self.navGfx, sound = self.navSnd}
		if selected and selected:IsDescendantOf(self.scroll) then
			for _, panel in {self.steering, self.interface, self.graphics, self.sound} do
				if not panel.Visible and selected:IsDescendantOf(panel) then GuiService.SelectedObject = tabs[self.data.category] or self.navSteer end
			end
		end
	end
	self:_layout()
end

function View:_layout()
	local size = self.gui.AbsoluteSize
	if size.X < 2 then return end
	local preferred = GuiService.PreferredTextSize.Name
	local scale = self.data.textScale or ({Medium = 1, Large = 1.15, Larger = 1.3, Largest = 1.5})[preferred] or 1
	self.textScale = scale
	local fontSize, secondary = math.floor(18 * scale), math.floor(16 * scale)
	for _, item in self.gui:GetDescendants() do
		if item:IsA("TextLabel") or item:IsA("TextButton") then item.TextSize = fontSize end
	end
	for _, label in {self.subtitle, self.session, self.modeNote, self.note, self.uiNote, self.range, self.groundRange, self.groundNote, self.aheadRange, self.aheadNote, self.behindRange, self.behindNote} do label.TextSize = secondary end
	for _, r in self.soundRows do if r.note then r.note.TextSize = secondary end end
	self.title.TextSize = math.floor(30 * math.min(scale, 1.2))
	self.heading.TextSize, self.uiHeading.TextSize, self.gfxHeading.TextSize = math.floor(22 * scale), math.floor(22 * scale), math.floor(22 * scale)
	self.sndHeading.TextSize = math.floor(22 * scale)
	-- GetInsetArea rectangles share the core-UI origin. Translate into this full-screen GUI.
	local full = GuiService:GetInsetArea(Enum.ScreenInsets.None)
	local safe = GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
	local low, high = safe.Min - full.Min, safe.Max - full.Min
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		local tv = Vector2.new(size.X * 0.05, size.Y * 0.05)
		low = Vector2.new(math.max(low.X, tv.X), math.max(low.Y, tv.Y))
		high = Vector2.new(math.min(high.X, size.X - tv.X), math.min(high.Y, size.Y - tv.Y))
	end
	self.safe = {x = low.X + self.gui.AbsolutePosition.X, y = low.Y + self.gui.AbsolutePosition.Y, w = high.X - low.X, h = high.Y - low.Y}
	local available = high - low
	local w, h = math.min(available.X - 24, 1000), math.min(available.Y - 24, 632)
	local wide = size.X >= 1000 and size.Y >= 500
	local short = h < 430
	self.layout = if wide then "wide" elseif size.X > size.Y then "landscape" else "portrait"
	local px, py = low.X + (available.X - w) / 2, low.Y + (available.Y - h) / 2
	rect(self.entry, high.X - 160, low.Y + 176, 144, 48)
	rect(self.pane, px, py, w, h)
	rect(self.title, 24, 16, w - 108, 42)
	self.subtitle.Visible = not short
	rect(self.subtitle, 24, 58, w - 108, 30 * scale)
	rect(self.close, w - 72, 16, 48, 48)
	local navY = if short then 72 else math.max(104, 70 + 30 * scale)
	local contentX, contentY, contentW
	if wide then
		rect(self.navSteer, 24, navY, 184, 56)
		rect(self.navUI, 24, navY + 68, 184, 56)
		rect(self.navGfx, 24, navY + 136, 184, 56)
		rect(self.navSnd, 24, navY + 204, 184, 56)
		contentX, contentY, contentW = 232, navY, w - 256
	else
		-- four tabs in a row while each keeps room for its word; else two rows of two
		local navW4 = (w - 84) / 4
		if navW4 >= 120 * scale then
			rect(self.navSteer, 24, navY, navW4, 48)
			rect(self.navUI, 36 + navW4, navY, navW4, 48)
			rect(self.navGfx, 48 + 2 * navW4, navY, navW4, 48)
			rect(self.navSnd, 60 + 3 * navW4, navY, navW4, 48)
			contentX, contentY, contentW = 20, navY + 60, w - 40
		else
			local navW = (w - 60) / 2
			rect(self.navSteer, 24, navY, navW, 48)
			rect(self.navUI, 36 + navW, navY, navW, 48)
			rect(self.navGfx, 24, navY + 60, navW, 48)
			rect(self.navSnd, 36 + navW, navY + 60, navW, 48)
			contentX, contentY, contentW = 20, navY + 120, w - 40
		end
	end
	rect(self.scroll, contentX, contentY, contentW, math.max(48, h - contentY - 84))
	local inner = contentW - 28
	local y = 18
	local function label(item, height, width)
		local tw = width or inner
		local measured = TextService:GetTextSize(item.Text, item.TextSize, Enum.Font.GothamMedium, Vector2.new(tw, 10000))
		local th = math.max(height, measured.Y + 8)
		rect(item, 14, y, tw, th)
		y += th + 10
	end
	label(self.heading, 32 * scale)
	label(self.modeLabel, 28 * scale)
	local buttonH = math.max(48, 36 * scale)
	rect(self.dynamic, 14, y, (inner - 12) / 2, buttonH)
	rect(self.centred, 26 + (inner - 12) / 2, y, (inner - 12) / 2, buttonH)
	y += buttonH + 10
	label(self.modeNote, 24 * scale)
	y += 12
	local labelY = y
	label(self.sensitivityLabel, 28 * scale, inner - 44)
	rect(self.value, inner - 24, labelY, 38, math.max(28 * scale, 36))
	rect(self.minus, 14, y, 48, 48)
	rect(self.slider, 74, y, inner - 120, 48)
	rect(self.plus, inner - 34, y, 48, 48)
	y += 60
	-- Endpoints are explicit text, so the range is readable without tiny graduations.
	self.range.Text = "1 - 10"
	label(self.range, 24 * scale)
	label(self.note, 48 * scale)
	rect(self.steering, 0, 0, contentW, y + 8)
	local steeringH = y + 8
	self.columns = 1
	if not wide and size.X > size.Y and inner >= 520 and scale <= 1.15 then
		self.columns = 2
		local column = (inner - 24) / 2
		local right = 14 + column + 24
		local function height(item, width, minimum)
			return math.max(minimum, TextService:GetTextSize(item.Text, item.TextSize, Enum.Font.GothamMedium, Vector2.new(width, 10000)).Y + 8)
		end
		local rowY = 30 + 32 * scale
		local labelsH = math.max(height(self.modeLabel, column, 28 * scale), height(self.sensitivityLabel, column - 42, 28 * scale))
		rect(self.modeLabel, 14, rowY, column, labelsH)
		rect(self.sensitivityLabel, right, rowY, column - 42, labelsH)
		rect(self.value, right + column - 38, rowY, 38, labelsH)
		rowY += labelsH + 10
		rect(self.dynamic, 14, rowY, (column - 10) / 2, 48)
		rect(self.centred, 24 + (column - 10) / 2, rowY, (column - 10) / 2, 48)
		rect(self.minus, right, rowY, 48, 48)
		rect(self.slider, right + 60, rowY, column - 120, 48)
		rect(self.plus, right + column - 48, rowY, 48, 48)
		local modeH = height(self.modeNote, column, 24 * scale)
		rect(self.modeNote, 14, rowY + 60, column, modeH)
		rect(self.range, right, rowY + 60, column, 24 * scale)
		local noteH = height(self.note, column, 48 * scale)
		rect(self.note, right, rowY + 96, column, noteH)
		steeringH = math.max(rowY + 68 + modeH, rowY + 108 + noteH)
		rect(self.steering, 0, 0, contentW, steeringH)
	end
	y = 18
	label(self.uiHeading, 32 * scale)
	label(self.uiLabel, 32 * scale, inner - 62)
	rect(self.keycap, inner - 34, 68 * scale, 48, 48)
	y = math.max(y + 18, 132 * scale)
	label(self.uiNote, 72 * scale)
	rect(self.interface, 0, 0, contentW, y + 10)
	local interfaceH = y + 14
	y = 18
	label(self.gfxHeading, 32 * scale)
	local groundY = y
	label(self.groundLabel, 28 * scale, inner - 124)
	rect(self.groundValue, inner - 96, groundY, 110, math.max(28 * scale, 36))
	rect(self.groundMinus, 14, y, 48, 48)
	rect(self.groundSlider, 74, y, inner - 120, 48)
	rect(self.groundPlus, inner - 34, y, 48, 48)
	y += 60
	label(self.groundRange, 24 * scale)
	label(self.groundNote, 48 * scale)
	y += 12
	local aheadY = y
	label(self.aheadLabel, 28 * scale, inner - 124)
	rect(self.aheadValue, inner - 96, aheadY, 110, math.max(28 * scale, 36))
	rect(self.aheadMinus, 14, y, 48, 48)
	rect(self.aheadSlider, 74, y, inner - 120, 48)
	rect(self.aheadPlus, inner - 34, y, 48, 48)
	y += 60
	label(self.aheadRange, 24 * scale)
	label(self.aheadNote, 48 * scale)
	y += 12
	local behindY = y
	label(self.behindLabel, 28 * scale, inner - 124)
	rect(self.behindValue, inner - 96, behindY, 110, math.max(28 * scale, 36))
	rect(self.behindMinus, 14, y, 48, 48)
	rect(self.behindSlider, 74, y, inner - 120, 48)
	rect(self.behindPlus, inner - 34, y, 48, 48)
	y += 60
	label(self.behindRange, 24 * scale)
	label(self.behindNote, 48 * scale)
	rect(self.graphics, 0, 0, contentW, y + 8)
	local graphicsH = y + 12
	y = 18
	label(self.sndHeading, 32 * scale)
	for i, r in self.soundRows do
		if i > 1 then y += 8 end
		local rowY = y
		label(r.label, 28 * scale, inner - 124)
		rect(r.value, inner - 96, rowY, 110, math.max(28 * scale, 36))
		rect(r.minus, 14, y, 48, 48)
		rect(r.slider, 74, y, inner - 120, 48)
		rect(r.plus, inner - 34, y, 48, 48)
		y += 58
		if r.note then label(r.note, 24 * scale) end
	end
	rect(self.sound, 0, 0, contentW, y + 8)
	local soundH = y + 12
	self.scroll.CanvasSize = UDim2.fromOffset(0, if self.data.category == "interface" then interfaceH
		elseif self.data.category == "graphics" then graphicsH
		elseif self.data.category == "sound" then soundH else steeringH + 4)
	rect(self.back, 24, h - 64, math.min(200, w - 48), 48)
	self.session.Visible = w >= 500
	rect(self.session, w - 224, h - 60, 200, 40)
	Glass.preferences(self.gui, self.data.transparency)
	for name, offset in self.offsets do
		local item = if name == "SettingsPane" then self.pane elseif name == "SettingsEntry" then self.entry else self.pane:FindFirstChild(name, true)
		if item and item:IsA("GuiObject") then item.Position += UDim2.fromOffset(offset.X, offset.Y) end
	end
	self:_focusOrder()
end

function View:_focusOrder()
	local list = {self.navSteer, self.navUI, self.navGfx, self.navSnd}
	if self.data.category == "steering" then
		for _, item in {self.dynamic, self.centred, self.minus, self.slider, self.plus} do table.insert(list, item) end
	elseif self.data.category == "graphics" then
		for _, item in {self.groundMinus, self.groundSlider, self.groundPlus, self.aheadMinus, self.aheadSlider, self.aheadPlus, self.behindMinus, self.behindSlider, self.behindPlus} do table.insert(list, item) end
	elseif self.data.category == "sound" then
		for _, r in self.soundRows do
			for _, item in {r.minus, r.slider, r.plus} do table.insert(list, item) end
		end
	end
	table.insert(list, self.back)
	table.insert(list, self.close)
	self.focusables = list
	for i, item in list do
		item.NextSelectionUp = list[(i - 2) % #list + 1]
		item.NextSelectionDown = list[i % #list + 1]
		item.NextSelectionLeft = list[(i - 2) % #list + 1]
		item.NextSelectionRight = list[i % #list + 1]
	end
end
function View:focus(step)
	local index = table.find(self.focusables, GuiService.SelectedObject) or 0
	GuiService.SelectedObject = self.focusables[(index + (step or 1) - 1) % #self.focusables + 1]
end
function View:activateSelected()
	local selected = GuiService.SelectedObject
	if selected == self.navSteer then self.ActionRequested:Fire("category", "steering")
	elseif selected == self.navUI then self.ActionRequested:Fire("category", "interface")
	elseif selected == self.navGfx then self.ActionRequested:Fire("category", "graphics")
	elseif selected == self.navSnd then self.ActionRequested:Fire("category", "sound")
	elseif selected == self.groundMinus then self:nudgeGround(-1)
	elseif selected == self.groundPlus then self:nudgeGround(1)
	elseif selected == self.aheadMinus then self:nudgeAhead(-1)
	elseif selected == self.aheadPlus then self:nudgeAhead(1)
	elseif selected == self.behindMinus then self:nudgeBehind(-1)
	elseif selected == self.behindPlus then self:nudgeBehind(1)
	elseif selected == self.dynamic then self.ActionRequested:Fire("mode", "dynamic")
	elseif selected == self.centred then self.ActionRequested:Fire("mode", "centred")
	elseif selected == self.minus then self:nudge(-1)
	elseif selected == self.plus then self:nudge(1)
	elseif selected == self.close or selected == self.back then self.ActionRequested:Fire("close")
	else
		for _, r in self.soundRows do
			if selected == r.minus then self:nudgeSound(r.key, -1)
			elseif selected == r.plus then self:nudgeSound(r.key, 1) end
		end
	end
end
function View:show()
	self.opened, self.modal.Visible, self.entry.Visible = true, true, false
end
function View:hide()
	self.opened, self.modal.Visible = false, false
	self:cancelDrag()
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.modal) then GuiService.SelectedObject = nil end
end
function View:setLayoutOffset(name, offset) self.offsets[name] = offset; self:_layout() end
function View:describe()
	local out = {layout = self.layout, columns = self.columns, open = self.opened, dragging = self.drag ~= nil,
		viewport = {self.gui.AbsoluteSize.X, self.gui.AbsoluteSize.Y}, safe = self.safe, textScale = self.textScale, category = self.data.category,
		pieces = {}, controls = {}, textFailures = {}}
	for _, item in self.gui:GetDescendants() do
		if item:IsA("GuiObject") then
			local visible, ancestor = item.Visible, item.Parent
			while visible and ancestor and ancestor ~= self.gui do
				if ancestor:IsA("GuiObject") then visible = ancestor.Visible end
				ancestor = ancestor.Parent
			end
			if visible then
				local pos, size = item.AbsolutePosition, item.AbsoluteSize
				if item:IsA("GuiButton") then table.insert(out.controls, {name = item.Name, x = pos.X, y = pos.Y, w = size.X, h = size.Y, state = item:GetAttribute("State")}) end
				if item:GetAttribute("LayoutItem") then out.pieces[item.Name] = {x = pos.X, y = pos.Y, w = size.X, h = size.Y} end
				if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" and (not item.TextFits or item.TextSize < 16) then
					table.insert(out.textFailures, {name = item.Name, text = item.Text, fits = item.TextFits, size = item.TextSize})
				end
			end
		end
	end
	return out
end
function View:destroy()
	for _, connection in self.connections do connection:Disconnect() end
	self.ActionRequested:DisconnectAll()
	self.gui:Destroy()
end
return View
