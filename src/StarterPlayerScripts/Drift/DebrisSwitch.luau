--@localscript
-- DebrisSwitch: a button that cycles how grass and mud are thrown while you drive -- 3D
-- chunks, a fine spray, or the painted sprites (T-283, features/tyre-particles.md "Grass
-- and mud: three ways, compared"). A dev tool for the user's comparison, in the tuner's
-- programmer-art look; it goes when the user has picked (`Config.Fx.Ground.Debris.Switch`).
--
-- It sits beside the TUNE button, in a ScreenGui above the drag pad, and is Active, so a
-- touch on it never steers the car (the same rule as `Drift/TunerUI`).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

if not Config.Fx.Ground.Debris.Switch then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local DriftController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("DriftController"))

local NAMES = {
	chunks = "GRASS: 3D CHUNKS",
	specks = "GRASS: FINE SPRAY",
	sprites = "GRASS: SPRITES",
}

local gui = Instance.new("ScreenGui")
gui.Name = "DebrisSwitch"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 20 -- above the drag pad (`DriftControls`, 5)
gui.Parent = playerGui

local b = Instance.new("TextButton")
b.Name = "Cycle"
b.Size = UDim2.fromOffset(170, 44)
b.AnchorPoint = Vector2.new(1, 0)
b.Position = UDim2.new(1, -88, 0, Config.Drift.TunerTop - 52) -- left of TUNE
b.BackgroundColor3 = Color3.fromRGB(28, 31, 39)
b.BackgroundTransparency = 0.35
b.BorderSizePixel = 0
b.TextColor3 = Color3.fromRGB(235, 235, 240)
b.TextSize = 14
b.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
b.AutoButtonColor = true
b.Active = true
b.Text = NAMES[Config.Fx.Ground.Debris.Mode] or "GRASS"
b.Parent = gui

b.Activated:Connect(function()
	local mode = DriftController:SetDebrisMode(nil)
	if mode then
		b.Text = NAMES[mode] or mode
	end
end)
