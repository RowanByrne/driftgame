--!nonstrict
-- DebugHud: the programmer-art readout, top left
-- (docs/game/features/drift-model.md "UI"). Nothing else is on screen in the prototype;
-- the real HUD waits for scoring.
--
-- It shows what the tuning conversation asks about: speed, slip angle, yaw rate, which of
-- the four grip phases the car is in, whether it is airborne, and the simulation step the
-- frame actually spent. Toggled by F3, gamepad DPad up, or the DBG button on touch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)

local DebugHud = {}
DebugHud.__index = DebugHud

local ROWS = {
	"speed",
	"slip",
	"yaw",
	"grip",
	"ground",
	"step",
	"input",
	"where",
}

function DebugHud.new()
	local self = setmetatable({}, DebugHud)

	local gui = Instance.new("ScreenGui")
	gui.Name = "DriftDebug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 10
	gui.Enabled = Config.Drift.DebugReadoutOpen == true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
	panel.BackgroundTransparency = 0.25 -- text over moving gameplay needs a real backing
	panel.BorderSizePixel = 0
	panel.Position = UDim2.fromOffset(12, 12)
	-- Wide enough for the longest row, which is the slip one: a panel its text runs out of
	-- is a readout nobody trusts.
	panel.Size = UDim2.fromOffset(560, 8 + #ROWS * 22 + 8)
	panel.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	self.labels = {}
	for i, key in ROWS do
		local label = Instance.new("TextLabel")
		label.Name = key
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 20)
		label.LayoutOrder = i
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(235, 238, 245)
		label.TextSize = 17
		label.FontFace = Font.fromEnum(Enum.Font.Code)
		label.Text = ""
		label.Parent = panel
		self.labels[key] = label
	end

	self.gui = gui
	return self
end

function DebugHud:Toggle(): boolean
	self.gui.Enabled = not self.gui.Enabled
	return self.gui.Enabled
end

function DebugHud:SetVisible(visible: boolean)
	self.gui.Enabled = visible
end

function DebugHud:IsVisible(): boolean
	return self.gui.Enabled
end

local PHASE_COLOUR = {
	gripping = Color3.fromRGB(150, 220, 150),
	breaking = Color3.fromRGB(255, 210, 110),
	drifting = Color3.fromRGB(255, 120, 90),
	catching = Color3.fromRGB(130, 195, 255),
	airborne = Color3.fromRGB(210, 160, 255),
}

-- `extra` carries what the model does not know about: the frame, the input and the world.
function DebugHud:Update(state: DriftModel.State?, extra)
	if not self.gui.Enabled then
		return
	end
	local L = self.labels
	if not state then
		L.speed.Text = "no car"
		for _, key in ROWS do
			if key ~= "speed" then
				L[key].Text = ""
			end
		end
		return
	end

	local C = Config.Drift
	local speed = DriftModel.speed(state)
	L.speed.Text = ("speed  %6.1f studs/s  (%3.0f%% of top)"):format(speed, 100 * speed / C.TopSpeed)
	L.slip.Text = ("slip   %6.1f deg  asked %5.1f   f %5.1f  r %5.1f"):format(
		math.deg(state.slip),
		math.deg(state.wantedSlip),
		math.deg(state.slipFront),
		math.deg(state.slipRear)
	)
	L.yaw.Text = ("yaw    %6.2f rad/s  heading %6.1f deg"):format(state.r, math.deg(state.yaw) % 360)
	L.grip.Text = ("grip   %-9s blend %4.2f  rear mu %4.2f"):format(state.phase, state.gripBlend, state.muRear)
	L.grip.TextColor3 = PHASE_COLOUR[state.phase] or Color3.fromRGB(235, 238, 245)

	local broke = if state.breakLoose then ("loose in %4.2fs"):format(state.breakLoose) else "gripping"
	L.ground.Text = ("ground %-9s %s  %s"):format(
		if state.airborne then "AIRBORNE" else "on",
		if extra and extra.surfaceTag then "tag" else "fallback",
		broke
	)
	L.step.Text = ("step   %5.2f ms x%d/frame   frame %5.1f ms"):format(
		C.FixedStep * 1000,
		(extra and extra.steps) or 0,
		((extra and extra.frameSeconds) or 0) * 1000
	)
	L.input.Text = ("input  steer %+5.2f  wheels %+5.1f deg  %s %s  [%s]"):format(
		(extra and extra.steerInput) or 0,
		math.deg(state.wheelAngle),
		if extra and extra.drift then "DRIFT" else "-----",
		if extra and extra.brake then "BRAKE" else "-----",
		(extra and extra.device) or "?"
	)
	L.where.Text = ("where  %7.1f %7.1f %7.1f   vy %6.1f"):format(
		state.position.X,
		state.position.Y,
		state.position.Z,
		state.vy
	)
end

function DebugHud:Destroy()
	self.gui:Destroy()
end

return DebugHud
