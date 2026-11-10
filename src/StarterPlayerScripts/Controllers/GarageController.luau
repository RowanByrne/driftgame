--!nonstrict
-- GarageController: the garage visit on this client, and its menus
-- (docs/game/features/car-customization.md "How it plays" and "UI", T-103).
--
-- THE SERVER DECIDES WHEN THE CAR IS IN (`GarageVisit`, ServerScriptService/Services/
-- GarageVisitService): driving through the garage's door, or the Garage button here, which
-- asks. Its answer is what this acts on:
--   in   the car is held on the turntable. The simulation stops (`DriftController:Park`)
--        and the car is drawn on the deck this client can see, turning with it
--        (`SetHeldPose`); the finger lets go and Get out is off (`CarEntryController:
--        EnterGarage`); the garage camera takes over (`CarCameraController:SetView`); the
--        menus open.
--   out  the car is released at the door, facing out: the drift camera, the finger and the
--        simulation come back from there (`CarEntryController:LeaveGarage`).
--
-- THE MENUS are `Garage/GarageMenuView`, fed from `Garage/MenuModel`. Picking a part draws
-- it on the car here only (`Garage/Preview`); Fit asks the server (`CustomizeFit`), and
-- what is fitted is only ever what the server answered. Back, a new tab and Drive out all
-- put the fitted look back.
--
-- INPUT: touch and mouse on the buttons; gamepad selection on the rows and swatches, B for
-- Back, X for Fit, Y for Drive out, L1/R1 for the tabs; keyboard Backspace, Return, Q/E.
-- The Garage button is also G and the gamepad's DPad down.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Customization = require(ReplicatedStorage.Shared.Customization)
local Net = require(ReplicatedStorage.Shared.Net)

local GarageFolder = script.Parent.Parent:WaitForChild("Garage")
local GarageMenuView = require(GarageFolder.GarageMenuView)
local MenuModel = require(GarageFolder.MenuModel)
local Preview = require(GarageFolder.Preview)

local CarCameraController = require(script.Parent.CarCameraController)
local CarEntryController = require(script.Parent.CarEntryController)
local DriftController = require(script.Parent.DriftController)

local GarageController = {}
GarageController.Priority = 0 -- after the controllers it drives

local STEP_NAME = "GarageHud"
local FIT_ANSWER_WAIT = 3 -- seconds before a fit with no answer is given up on

function GarageController:Init()
	self.inGarage = false
	self.visit = nil -- the server's last state: { rel, home, how }
	self.fitted = nil -- the build the server says is on the car
	self.category = Customization.CategoryOrder[1]
	self.pick = nil
	self.pending = false
	self.pendingAt = 0
	self.status = { text = "", tone = "info" }
	self.askedAt = 0
	self.camCF = nil
	self.hidden = {} -- ScreenGui -> Enabled, the screens put away while the menus are open
	self.counts = {
		visitsAsked = 0,
		opened = 0,
		closed = 0,
		refusals = 0,
		fitsAsked = 0,
		fitsOk = 0,
		fitsRefused = 0,
		previews = 0,
		reverts = 0,
	}
	self.lastRefusal = nil
	self._visit = Net.event("GarageVisit")
	self._fit = Net.event("CustomizeFit")
end

function GarageController:Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self:_buildHud(playerGui)
	self.view = GarageMenuView.new(playerGui)
	self.view.ActionRequested:Connect(function(action, ...)
		self:_onAction(action, ...)
	end)
	self:_bindMenuKeys()

	self._visit.OnClientEvent:Connect(function(state)
		self:_onVisit(state)
	end)
	self._fit.OnClientEvent:Connect(function(answer)
		self:_onFitAnswer(answer)
	end)

	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 3, function()
		self:_frame()
	end)

	-- A client that joins (or reloads) while the server has it in the garage hears so.
	self._visit:FireServer(nil)
end

-- ---------------------------------------------------------------- the HUD button

function GarageController:_buildHud(playerGui: Instance)
	local t = Config.GarageMenu
	local gui = Instance.new("ScreenGui")
	gui.Name = "GarageHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the same space as the drag pad and the GET OUT button
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = t.HudDisplayOrder -- above the drag pad's 5: a thumb here is a press
	gui.Parent = playerGui
	self.hud = gui

	local button = Instance.new("TextButton")
	button.Name = "Garage"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Size = UDim2.fromOffset(t.HudButtonSize.X, t.HudButtonSize.Y)
	button.Position = UDim2.new(1, -t.HudButtonMargin, 1, -t.HudButtonAbove)
	button.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	button.BackgroundTransparency = 0.35
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Active = true
	button.Text = t.HudText
	button.TextColor3 = Color3.fromRGB(240, 240, 240)
	button.TextSize = 16
	button.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	button.Visible = false
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	button.Activated:Connect(function()
		self:RequestGarage()
	end)
	self.hudButton = button

	local context = Instance.new("InputContext")
	context.Name = "GarageHudControls"
	context.Priority = 1000
	context.Sink = false
	local action = Instance.new("InputAction")
	action.Name = "Garage"
	action.Type = Enum.InputActionType.Bool
	action.Parent = context
	for name, key in { Key = Enum.KeyCode.G, Gamepad = Enum.KeyCode.DPadDown } do
		local binding = Instance.new("InputBinding")
		binding.Name = name
		binding.KeyCode = key
		binding.Parent = action
	end
	context.Parent = Players.LocalPlayer:WaitForChild("PlayerScripts")
	action.Pressed:Connect(function()
		self:RequestGarage()
	end)
	self._hudContext = context
end

function GarageController:_canAskIn(): boolean
	return not self.inGarage and CarEntryController.mode == "driving" and DriftController:IsDriving()
end

-- The Garage button, G and DPad down. The server decides; this only asks.
function GarageController:RequestGarage(): (boolean, string?)
	if not self:_canAskIn() then
		return false, "not driving"
	end
	local now = os.clock()
	if now - self.askedAt < 0.5 then
		return false, "asked"
	end
	self.askedAt = now
	self.counts.visitsAsked += 1
	self._visit:FireServer(true)
	return true, nil
end

-- ---------------------------------------------------------------- menu keys

function GarageController:_bindMenuKeys()
	local context = Instance.new("InputContext")
	context.Name = "GarageMenuControls"
	context.Priority = 2000
	context.Sink = false
	context.Enabled = false
	local function bind(name: string, keys: { Enum.KeyCode }, fn: () -> ())
		local action = Instance.new("InputAction")
		action.Name = name
		action.Type = Enum.InputActionType.Bool
		action.Parent = context
		for i, key in keys do
			local binding = Instance.new("InputBinding")
			binding.Name = "Key" .. i
			binding.KeyCode = key
			binding.Parent = action
		end
		action.Pressed:Connect(fn)
	end
	bind("Back", { Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace }, function()
		self:_onAction("back")
	end)
	bind("Fit", { Enum.KeyCode.ButtonX, Enum.KeyCode.Return }, function()
		self:_onAction("fit")
	end)
	bind("DriveOut", { Enum.KeyCode.ButtonY }, function()
		self:_onAction("driveOut")
	end)
	bind("PrevTab", { Enum.KeyCode.ButtonL1, Enum.KeyCode.Q }, function()
		self:_stepTab(-1)
	end)
	bind("NextTab", { Enum.KeyCode.ButtonR1, Enum.KeyCode.E }, function()
		self:_stepTab(1)
	end)
	context.Parent = Players.LocalPlayer:WaitForChild("PlayerScripts")
	self._menuContext = context
end

function GarageController:_stepTab(step: number)
	local order = Customization.CategoryOrder
	local i = table.find(order, self.category) or 1
	local nextId = order[((i - 1 + step) % #order) + 1]
	self:_onAction("tab", nextId)
end

-- ---------------------------------------------------------------- the visit

local function car(): Model?
	return DriftController:Car()
end

local function room(): Instance?
	return workspace:FindFirstChild("GarageRoom")
end

local function turntable(): Model?
	local r = room()
	local t = r and r:FindFirstChild("Turntable")
	return if t and t:IsA("Model") then t else nil
end

local function point(name: string): CFrame?
	local r = room()
	local points = r and r:FindFirstChild("Points")
	local p = points and points:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p.CFrame else nil
end

function GarageController:_onVisit(state: any)
	if type(state) ~= "table" then
		return
	end
	if state.ok == false then
		self.counts.refusals += 1
		self.lastRefusal = tostring(state.reason)
		if self.inGarage then
			self:_setStatus(`Not done: {self.lastRefusal}.`, "error")
		end
	end
	if state.inGarage == true then
		self.visit = {
			rel = if typeof(state.rel) == "CFrame" then state.rel else (self.visit and self.visit.rel),
			home = if typeof(state.home) == "CFrame" then state.home else (self.visit and self.visit.home),
			how = state.how,
		}
		if not self.inGarage then
			self:_open(if typeof(state.cf) == "CFrame" then state.cf else nil)
		end
	elseif state.inGarage == false and self.inGarage then
		self:_close(if typeof(state.cf) == "CFrame" then state.cf else nil)
	end
end

-- Where this client draws its car while it is on the turntable: on the deck it can see.
function GarageController:_carPose(): CFrame?
	local t = turntable()
	local visit = self.visit
	if not t or not visit or not visit.rel then
		return nil
	end
	return t:GetPivot() * visit.rel
end

-- The garage camera: the category's named point, eased to. Close-ups turn with the
-- turntable so they stay on the part; the wide one stands still and watches the car turn.
function GarageController:_cameraTarget(): CFrame?
	local name = Config.GarageMenu.CameraFor[self.category] or "CamWide"
	local cf = point(name) or point("CamWide")
	if not cf then
		return nil
	end
	local t = turntable()
	local home = self.visit and self.visit.home
	if name ~= "CamWide" and t and home then
		cf = (t:GetPivot() * home:Inverse()) * cf
	end
	return cf
end

function GarageController:_camera(dt: number): (CFrame?, number?)
	local target = self:_cameraTarget()
	if not target then
		return self.camCF, Config.GarageMenu.CamFieldOfView
	end
	if not self.camCF or GuiService.ReducedMotionEnabled then
		self.camCF = target
	else
		local alpha = 1 - math.exp(-Config.GarageMenu.CamEase * dt)
		self.camCF = self.camCF:Lerp(target, alpha)
	end
	return self.camCF, Config.GarageMenu.CamFieldOfView
end

function GarageController:_open(cf: CFrame?)
	local own = car()
	self.inGarage = true
	self.counts.opened += 1
	self.fitted = if own then Customization.read(own) else Customization.stock()
	self.category = Customization.CategoryOrder[1]
	self.pick = nil
	self.pending = false
	self:_setStatus("Pick a part to see it on the car.", "info", true)

	if cf then
		DriftController:Park(cf)
	end
	DriftController:SetHeldPose(function()
		return self:_carPose()
	end)
	CarEntryController:EnterGarage()
	self.camCF = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or nil
	CarCameraController:SetView(function(dt)
		return self:_camera(dt)
	end, "garage")

	-- Every other screen away while the menus are up, and back as it was after.
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	table.clear(self.hidden)
	for _, name in Config.GarageMenu.HideGuis do
		local gui = playerGui and playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") then
			self.hidden[gui] = gui.Enabled
			gui.Enabled = false
		end
	end

	-- Roblox's thumbstick and jump button off: their zones are where the list and the
	-- buttons are, and a tap there would be theirs (UI.md "Keep the touch controls clear").
	self.touchControlsWere = GuiService.TouchControlsEnabled
	GuiService.TouchControlsEnabled = false

	self.view:show()
	self._menuContext.Enabled = true
	self:_redraw()
	self:_focus()
end

function GarageController:_close(cf: CFrame?)
	if not self.inGarage then
		return
	end
	self:_revert()
	self.inGarage = false
	self.counts.closed += 1
	self.pick = nil
	self.pending = false
	self.view:hide()
	self._menuContext.Enabled = false
	for gui, enabled in self.hidden do
		if gui.Parent then
			gui.Enabled = enabled
		end
	end
	table.clear(self.hidden)
	if self.touchControlsWere ~= nil then
		GuiService.TouchControlsEnabled = self.touchControlsWere
		self.touchControlsWere = nil
	end
	CarCameraController:SetView(nil)
	DriftController:SetHeldPose(nil)
	CarEntryController:LeaveGarage(cf)
	self.visit = nil
	self.camCF = nil
end

-- ---------------------------------------------------------------- the menus

function GarageController:_setStatus(text: string, tone: string, quiet: boolean?)
	self.status = { text = text, tone = tone }
	if not quiet and self.inGarage then
		self:_redraw()
	end
end

function GarageController:_snapshot()
	return MenuModel.snapshot({
		fitted = self.fitted or Customization.stock(),
		category = self.category,
		pick = self.pick,
		status = self.status,
		pending = self.pending,
	})
end

-- Redraw, keeping the gamepad's selection on the same button across the rebuild.
function GarageController:_redraw()
	if not self.view then
		return
	end
	local selected = GuiService.SelectedObject
	local selectedName = selected and selected:IsDescendantOf(self.view.gui) and selected.Name or nil
	self.view:setData(self:_snapshot())
	if selectedName then
		local again = self.view.gui:FindFirstChild(selectedName, true)
		if again and again:IsA("GuiObject") then
			GuiService.SelectedObject = again
		end
	end
end

local function usingGamepad(): boolean
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if ok and preferred ~= nil then
		return preferred == Enum.PreferredInput.Gamepad
	end
	return UserInputService.GamepadEnabled and not UserInputService.TouchEnabled
end

-- With a gamepad, selection lands on the list: the picked row, else the first.
function GarageController:_focus()
	if not usingGamepad() then
		return
	end
	task.defer(function()
		local first = self.view and self.view:firstSelectable()
		if first then
			GuiService.SelectedObject = first
		end
	end)
end

function GarageController:_previewBuild()
	return MenuModel.preview(self.fitted, self.category, self.pick)
end

function GarageController:_drawPreview()
	local own = car()
	if not own then
		return
	end
	if MenuModel.hasPick(self.category, self.pick) then
		self.counts.previews += 1
		Preview.draw(own, self:_previewBuild())
	else
		self:_revert()
	end
end

function GarageController:_revert()
	local own = car()
	if own then
		self.counts.reverts += 1
		Preview.revert(own)
	end
end

function GarageController:_onAction(action: string, a: any, b: any)
	if not self.inGarage then
		return
	end
	if action == "tab" then
		if type(a) ~= "string" or not Customization.category(a) or a == self.category then
			return
		end
		-- Leaving a list backs out of it: the fitted look goes back on.
		if MenuModel.hasPick(self.category, self.pick) then
			self:_revert()
		end
		self.category = a
		self.pick = nil
		self:_setStatus("Pick a part to see it on the car.", "info", true)
		self:_redraw()
		self:_focus()
	elseif action == "select" then
		if self.pending or type(a) ~= "string" then
			return
		end
		self.pick = MenuModel.pickPart(self.fitted, self.category, a)
		self:_afterPick()
	elseif action == "paint" then
		if self.pending or type(a) ~= "string" or type(b) ~= "string" then
			return
		end
		self.pick = MenuModel.pickPaint(self.fitted, self.pick, a, b)
		if next(self.pick) == nil then
			self.pick = nil
		end
		self:_afterPick()
	elseif action == "back" then
		if not MenuModel.hasPick(self.category, self.pick) then
			return
		end
		self.pick = nil
		self:_revert()
		self:_setStatus("Back on the fitted part.", "info")
	elseif action == "fit" then
		self:RequestFit()
	elseif action == "driveOut" then
		self:RequestDriveOut()
	end
end

function GarageController:_afterPick()
	self:_drawPreview()
	if MenuModel.hasPick(self.category, self.pick) then
		self:_setStatus(`Previewing {MenuModel.pickName(self.category, self.pick)}. Fit keeps it; Back puts the fitted part back.`, "info")
	else
		self:_setStatus("That is what is fitted.", "info")
	end
end

-- Fit what is picked: ask the server. What is fitted changes only when it answers.
function GarageController:RequestFit(category: string?, choice: any): (boolean, string?)
	if not self.inGarage then
		return false, "not in garage"
	end
	if self.pending then
		return false, "pending"
	end
	category = category or self.category
	if choice == nil then
		if not MenuModel.hasPick(self.category, self.pick) then
			return false, "nothing picked"
		end
		choice = self.pick
	end
	self.pending = true
	self.pendingAt = os.clock()
	self.pendingCategory = category
	self.counts.fitsAsked += 1
	self:_setStatus("Asking the server...", "pending")
	self._fit:FireServer(category, choice)
	return true, nil
end

function GarageController:_onFitAnswer(answer: any)
	if type(answer) ~= "table" then
		return
	end
	local build = if type(answer.build) == "table" then Customization.sanitize(answer.build) else nil
	if not self.pending then
		-- Not ours to answer (the store answering on join): keep what is fitted current.
		if build then
			self.fitted = build
			if self.inGarage then
				self:_redraw()
			end
		end
		return
	end
	self.pending = false
	if build then
		self.fitted = build
	end
	if answer.ok == true then
		self.counts.fitsOk += 1
		local name = MenuModel.pickName(self.category, self.pick)
		self.pick = nil
		-- The car is redrawn from the attributes the server has just set; drawing it here
		-- too is the same look and removes any doubt about the order they arrive in.
		self:_revert()
		self:_setStatus(`Fitted: {name}.`, "ok")
	else
		self.counts.fitsRefused += 1
		self.lastRefusal = tostring(answer.reason)
		-- Refused: back to what the server says is on the car, and say why.
		self.pick = nil
		self:_revert()
		self:_setStatus(`Not fitted: {self.lastRefusal}. Back on the fitted part.`, "error")
	end
end

function GarageController:RequestDriveOut(): (boolean, string?)
	if not self.inGarage then
		return false, "not in garage"
	end
	self.counts.visitsAsked += 1
	self._visit:FireServer(false)
	return true, nil
end

-- ---------------------------------------------------------------- the frame

function GarageController:_frame()
	local show = self:_canAskIn()
	self.hudButton.Visible = show
	self._hudContext.Enabled = show
	if self.pending and os.clock() - self.pendingAt > FIT_ANSWER_WAIT then
		self.pending = false
		self.pick = nil
		self:_revert()
		self:_setStatus("No answer from the server. Nothing was fitted.", "error")
	end
end

-- ---------------------------------------------------------------- Studio only

function GarageController:DebugState()
	local own = car()
	local pose = self:_carPose()
	local drawn = nil
	if own then
		local body = own:FindFirstChild("Body")
		drawn = body and body:IsA("BasePart") and body.Position or nil
	end
	return {
		inGarage = self.inGarage,
		how = self.visit and self.visit.how or nil,
		category = self.category,
		pick = self.pick,
		pending = self.pending,
		status = self.status.text,
		statusTone = self.status.tone,
		fitted = self.fitted,
		fittedCounter = own and own:GetAttribute(Customization.ATTR_COUNTER) or nil,
		carPose = pose and pose.Position or nil,
		simAt = DriftController:CurrentState() and DriftController:CurrentState().position or nil,
		bodyAt = drawn,
		entryMode = CarEntryController.mode,
		getOutVisible = CarEntryController.button and CarEntryController.button.Visible or nil,
		hudVisible = self.hudButton.Visible,
		hudRect = { self.hudButton.AbsolutePosition, self.hudButton.AbsoluteSize },
		cameraType = workspace.CurrentCamera and workspace.CurrentCamera.CameraType.Name or nil,
		cameraAt = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or nil,
		cameraTarget = (function()
			local t = self:_cameraTarget()
			return t and t.Position or nil
		end)(),
		menuKeys = self._menuContext.Enabled,
		touchControls = GuiService.TouchControlsEnabled,
		counts = table.clone(self.counts),
		lastRefusal = self.lastRefusal,
		view = self.view and self.view:describe() or nil,
	}
end

-- The car's looks as drawn now (`CarLooks.describe`).
function GarageController:DebugLooks()
	local own = car()
	return own and Preview.describe(own) or nil
end

-- Press a menu action as the view would fire it: ("tab", id), ("select", id),
-- ("paint", field, id), ("fit"), ("back"), ("driveOut").
function GarageController:DebugAction(action: string, a: any, b: any)
	self:_onAction(action, a, b)
	return self:DebugState()
end

-- Fit something the menu would never offer, to see a refusal reach the list.
function GarageController:DebugFitRaw(category: any, choice: any)
	return { self:RequestFit(category, choice) }
end

return GarageController
