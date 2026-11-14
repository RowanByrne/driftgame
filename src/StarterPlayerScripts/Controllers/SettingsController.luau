--!nonstrict
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)
local UI = script.Parent.Parent:WaitForChild("UI")
local MenuInput, Theme = require(UI:WaitForChild("MenuInput")), require(UI:WaitForChild("Theme"))
local Folder = script.Parent.Parent:WaitForChild("Settings")
local SettingsView = require(Folder:WaitForChild("SettingsView"))
local Fixtures = require(Folder:WaitForChild("SettingsView.fixtures"))
local CarInput = require(script.Parent.CarInputController)
local Visibility = require(script.Parent.UiVisibilityController)
local Garage = require(script.Parent.GarageController)
local Cmdr = require(script.Parent.CmdrController)
local Settings = { Priority = -10 }

function Settings:Init()
	self.open = false
	self.category = "steering"
	self.releaseVersion = 0
	self.opens, self.closes, self.changes = 0, 0, 0
	self.handlers = {}
end

function Settings:_closingKeyHeld()
	if UserInputService:IsKeyDown(Enum.KeyCode.Backspace) then return true end
	for _, pad in UserInputService:GetConnectedGamepads() do
		if UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonB) then return true end
	end
	return false
end

function Settings:_releaseInput()
	self.releaseVersion += 1
	local version = self.releaseVersion
	-- B is also the handbrake. Rearm driving after the closing press has ended.
	task.spawn(function()
		RunService.Heartbeat:Wait()
		while self.releaseVersion == version and self:_closingKeyHeld() do RunService.Heartbeat:Wait() end
		if self.releaseVersion == version and not self.effective then MenuInput.SetBlocked("Settings", false) end
	end)
end

function Settings:_draw()
	if not self.view then return end
	local data = if self.fixture then table.clone(self.fixture) else CarInput:GetSettings()
	data.category = self.category
	self.view:setData(data)
end

function Settings:_refresh()
	if not self.view then return end
	if (Garage.inGarage or not CarInput:IsDriving()) and self.open then self:Close() end
	local effective = self.open and not Visibility.hidden and not GuiService.MenuIsOpen and not Garage.inGarage
	local tuner = self.playerGui:FindFirstChild("DriftTuner")
	local tunerPanel = tuner and tuner:FindFirstChild("Panel")
	local tunerOpen = tuner and tuner.Enabled and tunerPanel and tunerPanel.Visible
	self.view.entry.Visible = not self.open and not Visibility.hidden and not Garage.inGarage and CarInput:IsDriving() and not tunerOpen
	if effective == self.effective then return end
	self.effective = effective
	Visibility:SetOverlayHidden("Settings", effective, {Settings = true, LayoutDrag = true})
	self.menuContext.Enabled = effective
	self.blur.Enabled = effective and GuiService.PreferredTransparency > 0
	self.blur.Size = Theme.Blur * GuiService.PreferredTransparency
	if effective then
		self.releaseVersion += 1
		MenuInput.SetBlocked("Settings", true)
		self.view:show()
		if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then self.view:focus(1) end
	else
		self.view:hide()
		if self.layoutDrag then self.layoutDrag:setEnabled(false) end
		self:_releaseInput()
	end
end

function Settings:Open()
	if self.open or Visibility.hidden or GuiService.MenuIsOpen or Garage.inGarage or not CarInput:IsDriving() or UserInputService:GetFocusedTextBox() then return false end
	if Cmdr.Cmdr and Cmdr.Cmdr._interface.Window:IsVisible() then return false end
	self.previousFocus = GuiService.SelectedObject
	self.open = true
	self.opens += 1
	self:_draw()
	self:_refresh()
	return true
end

function Settings:Close()
	if not self.open then return false end
	self.open = false
	self.closes += 1
	self:_refresh()
	local previous = self.previousFocus
	if previous and previous.Parent and previous.Visible then
		local ancestor, visible = previous.Parent, true
		while ancestor and ancestor ~= self.playerGui do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then visible = false end
			if ancestor:IsA("ScreenGui") and not ancestor.Enabled then visible = false end
			ancestor = ancestor.Parent
		end
		if visible and not Visibility.hidden and not Garage.inGarage then GuiService.SelectedObject = previous end
	end
	return true
end

function Settings:_action(action, value)
	if action == "open" then self:Open(); return end
	if not self.effective then return end
	if action == "close" then self:Close()
	elseif action == "category" then
		if value == "steering" or value == "interface" then self.category = value; self:_draw() end
	elseif action == "mode" or action == "sensitivity" then
		if self.fixture then
			self.fixture[if action == "mode" then "mode" else "sensitivity"] = value
		else
			local ok = CarInput:SetSettings(if action == "mode" then value else nil, if action == "sensitivity" then value else nil)
			if ok then self.changes += 1 end
		end
		self:_draw()
	end
end

function Settings:_bind(context, name, keys, fn)
	self.handlers[name] = fn
	local action = Instance.new("InputAction")
	action.Name, action.Type, action.Parent = name, Enum.InputActionType.Bool, context
	for i, key in keys do
		local binding = Instance.new("InputBinding")
		binding.Name, binding.KeyCode, binding.Parent = "Key" .. i, key, action
	end
	action.Pressed:Connect(fn)
end

function Settings:Start()
	self.playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.view = SettingsView.new(self.playerGui)
	self.view.ActionRequested:Connect(function(...) self:_action(...) end)
	self.blur = Instance.new("BlurEffect")
	self.blur.Name, self.blur.Size, self.blur.Enabled, self.blur.Parent = "SettingsFog", Theme.Blur, false, Lighting
	local menu = Instance.new("InputContext")
	menu.Name, menu.Priority, menu.Sink, menu.Enabled = "SettingsNavigation", 3000, true, false
	self.menuContext = menu
	self:_bind(menu, "Close", {Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB}, function() self:Close() end)
	self:_bind(menu, "Next", {Enum.KeyCode.Tab, Enum.KeyCode.Down, Enum.KeyCode.DPadDown}, function()
		self.view:focus(if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then -1 else 1)
	end)
	self:_bind(menu, "Previous", {Enum.KeyCode.Up, Enum.KeyCode.DPadUp}, function() self.view:focus(-1) end)
	for name, direction in {Left = -1, Right = 1} do
		self:_bind(menu, name, {Enum.KeyCode[name], Enum.KeyCode["DPad" .. name]}, function()
			if GuiService.SelectedObject == self.view.slider then self.view:nudge(direction) else self.view:focus(direction) end
		end)
	end
	self:_bind(menu, "Activate", {Enum.KeyCode.Return}, function() self.view:activateSelected() end)
	menu.Parent = Players.LocalPlayer.PlayerScripts
	local toggle = Instance.new("InputContext")
	toggle.Name, toggle.Priority, toggle.Sink = "SettingsShortcut", 3000, true
	self:_bind(toggle, "Toggle", {Enum.KeyCode.M, Enum.KeyCode.ButtonR3}, function()
		if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then return end
		if self.open then self:Close() else self:Open() end
	end)
	toggle.Parent = Players.LocalPlayer.PlayerScripts
	self.toggleContext = toggle
	Visibility.Changed:Connect(function() self:_refresh() end)
	GuiService.MenuOpened:Connect(function() self:_refresh() end)
	GuiService.MenuClosed:Connect(function() self:_refresh() end)
	GuiService:GetPropertyChangedSignal("PreferredTransparency"):Connect(function()
		self.blur.Enabled = self.effective and GuiService.PreferredTransparency > 0
		self.blur.Size = Theme.Blur * GuiService.PreferredTransparency
	end)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		self.view:cancelDrag()
		self.view:_layout()
		if self.effective and UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then self.view:focus(1) end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function() self:Close() end)
	Net.event("CarRespawn").OnClientEvent:Connect(function() self:Close() end)
	RunService.Heartbeat:Connect(function()
		if not self.consoleHooked and Cmdr.Cmdr then
			self.consoleHooked = true
			Cmdr.Cmdr.Toggled:Connect(function(visible)
				if visible then self:Close() end
				MenuInput.SetBlocked("Console", visible)
			end)
			MenuInput.SetBlocked("Console", Cmdr.Cmdr._interface.Window:IsVisible())
		end
		self:_refresh()
	end)
	self:_draw()
	self:_refresh()
end

function Settings:DebugState()
	return {open = self.open, effective = self.effective, blocked = MenuInput.IsBlocked(), opens = self.opens,
		closes = self.closes, changes = self.changes, blur = self.blur and self.blur.Enabled,
		blurSize = self.blur and self.blur.Size, category = self.category, fixture = self.fixture ~= nil,
		values = CarInput:GetSettings(), view = self.view and self.view:describe()}
end
function Settings:DebugAction(action, value) self:_action(action, value); return self:DebugState() end
function Settings:DebugFixture(name)
	assert(RunService:IsStudio(), "Studio only")
	assert(name == nil or Fixtures[name], "Unknown settings fixture")
	self.fixture = name and table.clone(Fixtures[name]) or nil
	if self.fixture then self.category = self.fixture.category or "steering" end
	self:_draw()
	self:Open()
	return self:DebugState()
end
function Settings:DebugNavigate(name)
	assert(RunService:IsStudio() and self.handlers[name], "Unknown navigation handler")
	self.handlers[name]()
	return self:DebugState()
end
function Settings:DebugDrag(on, level)
	assert(RunService:IsStudio(), "Studio only")
	if not self.layoutDrag then
		local LayoutDrag = require(UI:WaitForChild("Dev"):WaitForChild("LayoutDrag"))
		self.layoutDrag = LayoutDrag.new({view = self.view, parent = self.playerGui})
	end
	self.layoutDrag:setLevel(level or "items")
	self.layoutDrag:setEnabled(on == true)
	return self.layoutDrag:export()
end
function Settings:DebugSnap(on) if self.layoutDrag then self.layoutDrag:setSnap(on == true) end end
function Settings:DebugExportLayout() return self.layoutDrag and self.layoutDrag:export() or "" end
function Settings:DebugResetLayout() if self.layoutDrag then self.layoutDrag:reset() end end
return Settings
