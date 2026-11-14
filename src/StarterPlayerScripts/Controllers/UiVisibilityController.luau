--!nonstrict
-- P hides the game's screen UI for this session. Owners keep their Enabled/Visible
-- state, so closing a menu or changing worlds while hidden cannot reopen old UI.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local UiVisibilityController = {}

-- These belong to Roblox, even when Roblox puts them in PlayerGui.
local SYSTEM_SCREENS = { TouchGui = true, Chat = true, BubbleChat = true }
-- UIScale clamps zero to a tiny positive value; allow for its float rounding.
local HIDDEN_SCALE = 1e-7

local function visualRoot(object, playerGui)
	if not object:IsA("GuiObject") then
		return false
	end
	local ancestor = object.Parent
	while ancestor and ancestor ~= playerGui do
		if ancestor:IsA("GuiObject") then
			return false -- one suppressor covers the whole visual subtree
		elseif ancestor:IsA("ScreenGui") then
			return not SYSTEM_SCREENS[ancestor.Name]
				and not (ancestor.Name == "DriftControls" and object.Name == "DragArea")
		end
		ancestor = ancestor.Parent
	end
	return false
end

function UiVisibilityController:Init()
	self.hidden = false
	self.toggles = 0
	self.suppressed = {}
end

function UiVisibilityController:_suppress(object)
	if self.suppressed[object] or not visualRoot(object, self.playerGui) then
		return
	end
	-- A separate scale leaves the owner's visibility flags and hierarchy alone. At
	-- its minimum the subtree is smaller than a pixel, including its hit area. Never
	-- scale DragArea: it is the driving input, not HUD artwork.
	local scale = object:FindFirstChildOfClass("UIScale")
	local entry = { owned = scale == nil }
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "UiVisibilityScale"
	end
	entry.scale = scale
	entry.restore = scale.Scale
	self.suppressed[object] = entry
	scale.Scale = HIDDEN_SCALE
	scale.Parent = object
	entry.changed = scale:GetPropertyChangedSignal("Scale"):Connect(function()
		if scale.Scale > HIDDEN_SCALE * 2 then
			entry.restore = scale.Scale
			scale.Scale = HIDDEN_SCALE
		end
	end)
	entry.ancestry = object.AncestryChanged:Connect(function()
		if not object:IsDescendantOf(self.playerGui) or not visualRoot(object, self.playerGui) then
			self:_restore(object)
		end
	end)
end

function UiVisibilityController:_restore(object)
	local entry = self.suppressed[object]
	if not entry then
		return
	end
	self.suppressed[object] = nil
	entry.changed:Disconnect()
	entry.ancestry:Disconnect()
	if entry.owned then
		entry.scale:Destroy()
	else
		entry.scale.Scale = entry.restore
	end
end

function UiVisibilityController:Toggle()
	if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then
		return self.hidden
	end
	self.hidden = not self.hidden
	self.toggles += 1
	if self.hidden then
		for _, object in self.playerGui:GetDescendants() do
			self:_suppress(object)
		end
	else
		for object in self.suppressed do
			self:_restore(object)
		end
	end
	return self.hidden
end

function UiVisibilityController:Start()
	if self.context then
		return -- one binding, including if Start is called again in Studio
	end
	self.playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.playerGui.DescendantAdded:Connect(function(object)
		if self.hidden then
			self:_suppress(object)
		end
	end)
	local context = Instance.new("InputContext")
	context.Name = "UiVisibilityControls"
	context.Priority = 1000
	context.Sink = false
	local action = Instance.new("InputAction")
	action.Name = "ToggleUi"
	action.Type = Enum.InputActionType.Bool
	action.Parent = context
	local key = Instance.new("InputBinding")
	key.Name = "Key"
	key.KeyCode = Enum.KeyCode.P
	key.Parent = action
	action.Pressed:Connect(function()
		self:Toggle()
	end)
	self.context = context
	context.Parent = Players.LocalPlayer:WaitForChild("PlayerScripts")
end

function UiVisibilityController:DebugState()
	local count = 0
	for _ in self.suppressed do
		count += 1
	end
	return { hidden = self.hidden, toggles = self.toggles, suppressed = count, bound = self.context ~= nil }
end

return UiVisibilityController
