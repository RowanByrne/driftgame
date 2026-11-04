--@localscript
-- TunerUI: the car tuner (docs/game/features/car-tuner.md).
--
-- Eight sliders that move the car you are driving, live, and a garage of named cars you
-- can come back to. Programmer art, like everything until the UI phase
-- (docs/workflow/UI.md): plain frames, native text, no decoration and none of it is the
-- shop this game will one day have.
--
-- WHY A SLIDER LANDS INSTANTLY. It does not push anything into the simulation: it calls
-- `Cars.tune(key, value)`, and `Config.Drift` resolves every car number through the
-- active car on EVERY READ, so `Drift/Model` picks it up on the next simulation step --
-- one 120th of a second -- with nothing to refresh and no car to rebuild. A finger held
-- through a slider move feels the car change underneath it, which is the whole point of
-- the tool.
--
-- WHY IT DOES NOT STEER THE CAR. The whole screen is a drag pad: one finger, held, is the
-- entire control, and its horizontal distance IS the car's rate of turn (`Drift/DragControl`).
-- A thumb dragging a slider would therefore also be a thumb hauling the car round. It is
-- not, because this ScreenGui sits at a higher `DisplayOrder` than the pad's and every
-- part of the panel that can be touched -- the panel itself, every button, every slider
-- track -- is an Active GuiObject, so the touch is consumed here and `DragControl`'s pad
-- never sees it begin. Closed, the panel is `Visible = false` and `Active = false`, and
-- the pad has the whole screen back. Both halves are measured
-- (features/car-tuner.md "Testing").
--
-- WHY IT IS A LocalScript AND NOT A CONTROLLER. The client loader only loads
-- `Controllers/`, and this is a dev tool that nothing else talks to: it reads `Shared/Cars`
-- and three remotes and that is all its coupling. As a LocalScript it starts itself, and
-- `DriftController` does not grow a line to carry it. The day the tuner becomes a garage
-- screen a player sees, it becomes a controller.
--
-- IT IS NOT THE STAT PANEL. `Drift/DebugHud` draws the car: what it is, the four grip
-- numbers and the curve they make. This moves it. Both can be open at once, and the panel
-- follows the sliders because it reads the same resolved car.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local Garage = require(ReplicatedStorage.Shared.Cars.Garage)
local Net = require(ReplicatedStorage.Shared.Net)

if not Config.Drift.Tuner then
	return
end

local C = Config.Drift
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------- the look
-- Flat, dark, two greys and one accent, matched to the debug readout so the two panels
-- read as the same tool. Nothing here survives the UI phase.
--
-- Measured against the panel (WCAG relative-luminance contrast, text on BG, and on the
-- worst case the panel can reach where a white sky shows through its 8%): TEXT 15.5 /
-- 12.6, DIM 6.6 / 5.4, FILL 5.2 / 4.2, GOOD 10.9 / 8.9, BAD 7.7 / 6.2. All of them clear
-- 4.5:1, so the quiet grey is quiet and still readable rather than one shade off the
-- background. Keep any new colour above 4.5:1 on BG.
local BG = Color3.fromRGB(18, 20, 26)
local PANEL = Color3.fromRGB(28, 31, 39)
local TRACK = Color3.fromRGB(44, 48, 60)
local FILL = Color3.fromRGB(230, 90, 70)
local TEXT = Color3.fromRGB(235, 235, 240)
local DIM = Color3.fromRGB(150, 155, 170)
local GOOD = Color3.fromRGB(120, 220, 150)
local BAD = Color3.fromRGB(240, 140, 120)
local FONT = Font.fromEnum(Enum.Font.Code)
local FONT_UI = Font.fromEnum(Enum.Font.GothamMedium)

local PAD = 10
local NUDGE = 26 -- px, the - and + buttons either side of a track
local GAP = 4

local function label(parent: Instance, name: string, text: string, size: number, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = colour
	l.TextSize = size
	l.FontFace = FONT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

-- Every clickable thing in this panel is one of these, and every one of them is what
-- keeps the steering out of the tuner: a TextButton is Active, so the touch that presses
-- it never reaches the drag pad underneath.
local function button(parent: Instance, name: string, text: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = TRACK
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = TEXT
	b.TextSize = 14
	b.FontFace = FONT_UI
	b.AutoButtonColor = true
	b.Active = true
	b.Selectable = true -- so a gamepad can reach it with Roblox's own GUI navigation
	b.Parent = parent
	return b
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local Tuner = {
	open = C.TunerOpen == true,
	base = Cars.activeKey(), -- the archetype under the tune
	tune = {}, -- slider id -> value, only what differs from the base
	loadedName = nil :: string?, -- the saved car being edited, if any
	dirtySince = false, -- edited since it was loaded or saved
	cars = {}, -- the garage the server believes
	persists = false,
	status = "",
	statusColour = DIM,
	dragging = nil, -- the slider id being dragged, or nil
	sent = 0, -- os.clock() of the last tune sent to the server
	pending = false, -- a tune the send rate has not let through yet
	rows = {}, -- slider id -> the row's instances
	garageRows = {},
}

local garageData = Net.event("GarageData")
local garageSave = Net.event("GarageSave")
local garageDelete = Net.event("GarageDelete")
local garageTune = Net.event("GarageTune")
local carSwitch = Net.event("CarSwitch")

local function setStatus(text: string, colour: Color3?)
	Tuner.status = text
	Tuner.statusColour = colour or DIM
end

-- The car as it is right now: every slider's value, base plus tune.
local function values(): { [string]: number }
	return Garage.values(Tuner.base, Tuner.tune)
end

-- Put the tune into the live car. ONE call, so the model never sees half a car
-- (`Cars.setTuning`), and only the sliders that actually differ from the base are in it
-- -- a tune that matches its base is not a tune, and leaving it out is what makes "reset"
-- and "this car is the plain gripper" the same state.
local function applyTune()
	local base = Garage.baseValues(Tuner.base)
	local trimmed = {}
	for id, value in Tuner.tune do
		if base[id] ~= value then
			trimmed[id] = value
		end
	end
	Tuner.tune = trimmed
	Cars.setTuning(Garage.toCarFields(trimmed))
end

-- Tell the server what we are driving, so its speed bound keeps up (`GarageService`,
-- "the ceiling"). Rate-limited, and always sent again when a drag ends, so the server
-- ends every drag holding the final number rather than whatever the last tick caught.
local function sendTune(force: boolean?)
	local now = os.clock()
	if not force and now - Tuner.sent < 1 / math.max(C.TunerSendRate, 1) then
		Tuner.pending = true
		return
	end
	Tuner.sent = now
	Tuner.pending = false
	garageTune:FireServer(Tuner.tune)
end

--------------------------------------------------------------------------------
-- Building the panel
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DriftTuner"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
-- WHY THE TEXT WAS UNREADABLE. `Instance.new("ScreenGui")` still defaults to the legacy
-- `Global` ZIndexBehavior, where a child does NOT automatically draw above its parent:
-- every ZIndex in the whole tree is compared against every other. The panel is ZIndex 2
-- and 8% transparent; every TextLabel here is the default ZIndex 1 -- so the panel's own
-- dark background was composited OVER all of it, and near-white text came out at 8%
-- strength: (235,235,240) drawn as (35,37,43) on a (18,20,26) panel, a contrast ratio of
-- 1.20:1. Invisible. Only the things given ZIndex 3+ by hand -- the buttons, the slider
-- fills, the notch -- were above the panel, which is why those alone read fine.
-- `Sibling` is what the rest of this file already assumes: a child is always above its
-- parent, and ZIndex only orders things against their own siblings. Every hand-set
-- ZIndex here is already consistent with that, so nothing moves; the text just stops
-- being painted over. The palette below is unchanged and was never the problem.
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- ABOVE THE DRAG PAD (`DriftControls`, DisplayOrder 5). This one number is what makes a
-- thumb on a slider a slider and not a steering input.
gui.DisplayOrder = 20
gui.Parent = playerGui

-- The button, for touch and for anyone who would rather not learn a function key. Lives
-- outside the panel so it is reachable while the panel is closed; sits under the
-- readout's own DBG button, which is at y = 64.
local openButton = button(gui, "TunerToggle", "TUNE")
openButton.Size = UDim2.fromOffset(64, 44)
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Position = UDim2.new(1, -16, 0, C.TunerTop - 52) -- just above the panel
openButton.BackgroundTransparency = 0.35
openButton.BackgroundColor3 = PANEL
openButton.ZIndex = 5

-- THE PANEL IS SIZED FROM THE SCREEN, NOT FROM ITS CONTENTS. Eight sliders, three
-- buttons and twelve saved cars is 870 px of panel, and a phone in landscape has 660 of
-- screen -- so a panel that grew to fit would run off the bottom and, worse, cover the
-- handbrake, which is the only way to stop a car once a run is over. It stops short of
-- both corners instead and the middle of it scrolls.
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -16, 0, C.TunerTop)
panel.Size = UDim2.new(0, C.TunerWidth, 1, -(C.TunerTop + C.TunerBottomGap))
panel.Active = true -- the panel's own background absorbs a touch too, so a thumb that
-- misses a slider does not fall through and steer the car
panel.Visible = false
panel.ZIndex = 2
panel.Parent = gui

local panelPad = Instance.new("UIPadding")
panelPad.PaddingTop = UDim.new(0, PAD)
panelPad.PaddingBottom = UDim.new(0, PAD)
panelPad.PaddingLeft = UDim.new(0, PAD)
panelPad.PaddingRight = UDim.new(0, PAD)
panelPad.Parent = panel

local INNER = C.TunerWidth - PAD * 2

-- The three fixed rows at the top and the status line at the bottom are placed by hand;
-- everything between them lives in the scrolling body below.
local function fixedRow(parent: Instance, y: number, height: number, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(0, y)
	f.Size = UDim2.new(1, 0, 0, height)
	f.ZIndex = 2
	f.Parent = parent
	return f
end

local TOP = 73 -- header + car + editing, and the gaps between them
local BOTTOM = 22 -- the status line and its gap

local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Position = UDim2.fromOffset(0, TOP)
body.Size = UDim2.new(1, 0, 1, -(TOP + BOTTOM))
body.CanvasSize = UDim2.new()
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.ScrollBarThickness = 4
body.ScrollBarImageColor3 = DIM
body.Active = true
body.ZIndex = 2
body.Parent = panel

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 4)
list.Parent = body

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function row(height: number, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, -6, 0, height) -- -6 leaves the scrollbar its lane
	f.LayoutOrder = nextOrder()
	f.ZIndex = 2
	f.Parent = body
	return f
end

-- ------------------------------------------------------------------ header
local header = fixedRow(panel, 0, 20, "Header")
local title = label(header, "Title", "CAR TUNER", 15, TEXT)
title.Size = UDim2.new(1, -60, 1, 0)
title.FontFace = FONT_UI
local closeButton = button(header, "Close", "CLOSE")
closeButton.Size = UDim2.fromOffset(56, 20)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.fromScale(1, 0)
closeButton.TextSize = 12
closeButton.ZIndex = 3

-- ------------------------------------------------------------------ which car
local carRow = fixedRow(panel, 24, 26, "Car")
local prevCar = button(carRow, "Prev", "<")
prevCar.Size = UDim2.fromOffset(26, 26)
prevCar.ZIndex = 3
local nextCar = button(carRow, "Next", ">")
nextCar.Size = UDim2.fromOffset(26, 26)
nextCar.AnchorPoint = Vector2.new(1, 0)
nextCar.Position = UDim2.fromScale(1, 0)
nextCar.ZIndex = 3
local carName = label(carRow, "Name", "", 14, TEXT)
carName.Size = UDim2.new(1, -60, 1, 0)
carName.Position = UDim2.fromOffset(30, 0)
carName.TextXAlignment = Enum.TextXAlignment.Center

local drivingRow = fixedRow(panel, 54, 15, "Driving")
local driving = label(drivingRow, "Text", "", 11, DIM)
driving.Size = UDim2.fromScale(1, 1)

-- The bottom line: what just happened, and -- while a slider is being touched -- what
-- that slider does. THE TOOLTIP, in other words, and the reason the rows above can be
-- two lines instead of three.
local statusRow = fixedRow(panel, 0, 16, "Status")
statusRow.AnchorPoint = Vector2.new(0, 1)
statusRow.Position = UDim2.new(0, 0, 1, 0)
local statusLabel = label(statusRow, "Text", "", 11, DIM)
statusLabel.Size = UDim2.fromScale(1, 1)

--------------------------------------------------------------------------------
-- The sliders
--------------------------------------------------------------------------------

-- The rows sit inside the scrolling body, which keeps 6 px for its scrollbar.
local ROW_W = INNER - 6
local TRACK_W = ROW_W - (NUDGE + GAP) * 2

local function format(slider, value: number): string
	return string.format(`%.{slider.decimals}f`, value)
end

local function setValue(id: string, value: number, fromDrag: boolean?)
	local clamped = Garage.clamp(id, value)
	if clamped == nil then
		return
	end
	Tuner.tune[id] = clamped
	Tuner.dirtySince = true
	applyTune()
	sendTune(not fromDrag)
	Tuner.refresh()
end

local DIM_HEX = DIM:ToHex()

local function buildSlider(slider)
	local f = row(C.TunerRowHeight, `Slider_{slider.id}`)

	-- THE HONEST HALF, and it is on the same line as the name rather than under it: the
	-- user asked for names that are not technical, so the name is "Eagerness" and the key
	-- it really moves is right beside it in grey. What the driver FEELS is the tooltip --
	-- touch the row and it is on the status line at the bottom.
	local name = label(f, "Label", "", 13, TEXT)
	name.RichText = true
	name.Text = `{slider.label}  <font color="#{DIM_HEX}" size="10">{slider.key}</font>`
	name.Size = UDim2.new(0.62, 0, 0, 15)
	name.FontFace = FONT_UI

	local value = label(f, "Value", "", 13, FILL)
	value.Size = UDim2.new(0.38, 0, 0, 15)
	value.Position = UDim2.new(0.62, 0, 0, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right

	local minus = button(f, "Minus", "-")
	minus.Size = UDim2.fromOffset(NUDGE, 16)
	minus.Position = UDim2.fromOffset(0, 16)
	minus.TextSize = 13
	minus.ZIndex = 3

	local plus = button(f, "Plus", "+")
	plus.Size = UDim2.fromOffset(NUDGE, 16)
	plus.Position = UDim2.fromOffset(NUDGE + GAP + TRACK_W + GAP, 16)
	plus.TextSize = 13
	plus.ZIndex = 3

	-- The track is a BUTTON, not a Frame: it has to absorb the press that starts a drag,
	-- or the drag pad under it takes that press and the car turns instead.
	local track = button(f, "Track", "")
	track.Size = UDim2.fromOffset(TRACK_W, 16)
	track.Position = UDim2.fromOffset(NUDGE + GAP, 16)
	track.BackgroundColor3 = TRACK
	track.AutoButtonColor = false
	track.ZIndex = 3

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = FILL
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 4
	fill.Parent = track

	-- The base car's own value, drawn as a notch, so "how far have I moved this from the
	-- car it came from" is readable without doing arithmetic.
	local notch = Instance.new("Frame")
	notch.Name = "Base"
	notch.BackgroundColor3 = TEXT
	notch.BorderSizePixel = 0
	notch.Size = UDim2.new(0, 1, 1, 0)
	notch.AnchorPoint = Vector2.new(0.5, 0)
	notch.ZIndex = 5
	notch.Parent = track

	local function tooltip()
		setStatus(`{slider.label}: {slider.feel}`, DIM)
		statusLabel.Text = Tuner.status
		statusLabel.TextColor3 = Tuner.statusColour
	end

	local function fromX(x: number)
		local width = math.max(track.AbsoluteSize.X, 1)
		local t = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		setValue(slider.id, slider.min + t * (slider.max - slider.min), true)
	end

	track.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			Tuner.dragging = slider.id
			tooltip()
			fromX(input.Position.X)
		end
	end)
	-- A mouse over the row says what the slider does, before anything has been moved.
	track.MouseEnter:Connect(tooltip)
	minus.Activated:Connect(function()
		tooltip()
		setValue(slider.id, (values()[slider.id] or slider.min) - slider.step)
	end)
	plus.Activated:Connect(function()
		tooltip()
		setValue(slider.id, (values()[slider.id] or slider.min) + slider.step)
	end)

	Tuner.rows[slider.id] = {
		slider = slider,
		value = value,
		fill = fill,
		notch = notch,
		track = track,
	}
end

for _, slider in Garage.Sliders do
	buildSlider(slider)
end

-- A drag follows the pointer anywhere on the screen once it has started on a track, and
-- ends wherever it is let go. Connected to UserInputService rather than to the track, so
-- a finger that slides off the end of the track still moves the slider instead of
-- silently stopping.
UserInputService.InputChanged:Connect(function(input)
	if not Tuner.dragging then
		return
	end
	if
		input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseMovement
	then
		local row_ = Tuner.rows[Tuner.dragging]
		if row_ then
			local width = math.max(row_.track.AbsoluteSize.X, 1)
			local t = math.clamp((input.Position.X - row_.track.AbsolutePosition.X) / width, 0, 1)
			setValue(Tuner.dragging, row_.slider.min + t * (row_.slider.max - row_.slider.min), true)
		end
	end
end)

local function endDrag()
	if Tuner.dragging then
		Tuner.dragging = nil
		sendTune(true) -- the server ends the drag holding the final number
	end
end

UserInputService.InputEnded:Connect(function(input)
	-- Only the pointer that could have started it: every key release comes through here
	-- too, and a drag that ends because somebody let go of a steering key is a slider
	-- that stops halfway for no reason the player can see.
	if
		input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
	then
		endDrag()
	end
end)
-- A finger that leaves the window mid-drag, the same way the steering drops its own.
UserInputService.WindowFocusReleased:Connect(endDrag)

--------------------------------------------------------------------------------
-- Save, reset, and the garage
--------------------------------------------------------------------------------

local actions = row(24, "Actions")
local saveButton = button(actions, "Save", "SAVE")
saveButton.Size = UDim2.fromOffset(math.floor((ROW_W - GAP * 2) / 3), 24)
saveButton.ZIndex = 3
local saveAsButton = button(actions, "SaveAs", "SAVE AS…")
saveAsButton.Size = saveButton.Size
saveAsButton.Position = UDim2.fromOffset(saveButton.Size.X.Offset + GAP, 0)
saveAsButton.ZIndex = 3
local resetButton = button(actions, "Reset", "RESET")
resetButton.Size = saveButton.Size
resetButton.Position = UDim2.fromOffset((saveButton.Size.X.Offset + GAP) * 2, 0)
resetButton.ZIndex = 3

local garageHeaderRow = row(16, "GarageHeader")
local garageHeader = label(garageHeaderRow, "Text", "SAVED CARS", 11, DIM)
garageHeader.Size = UDim2.fromScale(1, 1)

local garageList = Instance.new("Frame")
garageList.Name = "Garage"
garageList.BackgroundTransparency = 1
garageList.Size = UDim2.new(1, -6, 0, 0)
garageList.AutomaticSize = Enum.AutomaticSize.Y
garageList.LayoutOrder = nextOrder()
garageList.ZIndex = 2
garageList.Parent = body

local garageLayout = Instance.new("UIListLayout")
garageLayout.SortOrder = Enum.SortOrder.LayoutOrder
garageLayout.Padding = UDim.new(0, 2)
garageLayout.Parent = garageList

-- ------------------------------------------------------------------ the name dialog
local dialog = Instance.new("Frame")
dialog.Name = "NameDialog"
dialog.BackgroundColor3 = PANEL
dialog.BorderSizePixel = 0
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.Position = UDim2.fromScale(0.5, 0.4)
dialog.Size = UDim2.fromOffset(320, 108)
dialog.Active = true
dialog.Visible = false
dialog.ZIndex = 10
dialog.Parent = gui

local dialogTitle = label(dialog, "Title", "NAME THIS CAR", 13, TEXT)
dialogTitle.Position = UDim2.fromOffset(12, 10)
dialogTitle.Size = UDim2.new(1, -24, 0, 18)
dialogTitle.ZIndex = 11

local nameBox = Instance.new("TextBox")
-- NOT "Name": a child called that shadows `Instance.Name`, so `NameDialog.Name` is the
-- string "NameDialog" and every path to the box is a trap.
nameBox.Name = "Entry"
nameBox.BackgroundColor3 = TRACK
nameBox.BorderSizePixel = 0
nameBox.Position = UDim2.fromOffset(12, 34)
nameBox.Size = UDim2.new(1, -24, 0, 28)
nameBox.Text = ""
nameBox.PlaceholderText = "My car"
nameBox.TextColor3 = TEXT
nameBox.TextSize = 14
nameBox.FontFace = FONT
nameBox.ClearTextOnFocus = false
nameBox.Active = true
nameBox.ZIndex = 11
nameBox.Parent = dialog

local okButton = button(dialog, "Ok", "SAVE")
okButton.Size = UDim2.fromOffset(140, 26)
okButton.Position = UDim2.fromOffset(12, 70)
okButton.ZIndex = 11
local cancelButton = button(dialog, "Cancel", "CANCEL")
cancelButton.Size = UDim2.fromOffset(140, 26)
cancelButton.Position = UDim2.fromOffset(168, 70)
cancelButton.ZIndex = 11

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- The sliders and the two lines above them. Called on EVERY move of a slider, so it
-- touches nothing it does not have to: the garage list below is rebuilt separately,
-- because tearing twelve rows down and building them again sixty times a second while a
-- thumb is on a track is work nobody asked for.
local function refreshSliders()
	local vals = values()
	local base = Garage.baseValues(Tuner.base)
	local archetype = Cars.Archetypes.Cars[Tuner.base]
	local baseName = (archetype and archetype.Name) or Cars.Archetypes.Base.Name

	carName.Text = `{baseName}  ({Tuner.base})`
	if Tuner.loadedName then
		driving.Text = `editing "{Tuner.loadedName}"{if Tuner.dirtySince then " *" else ""}`
		driving.TextColor3 = if Tuner.dirtySince then FILL else GOOD
	else
		local n = 0
		for _ in Tuner.tune do
			n += 1
		end
		driving.Text = if n > 0 then `unsaved car, {n} slider(s) moved` else "the plain car, nothing moved"
		driving.TextColor3 = DIM
	end

	for id, r in Tuner.rows do
		local slider = r.slider
		local v = vals[id]
		local span = math.max(slider.max - slider.min, 1e-9)
		r.value.Text = `{format(slider, v)}{if slider.unit then " " .. slider.unit else ""}`
		r.value.TextColor3 = if Tuner.tune[id] ~= nil then FILL else TEXT
		r.fill.Size = UDim2.fromScale(math.clamp((v - slider.min) / span, 0, 1), 1)
		r.notch.Position = UDim2.fromScale(math.clamp((base[id] - slider.min) / span, 0, 1), 0)
	end

	statusLabel.Text = Tuner.status
	statusLabel.TextColor3 = Tuner.statusColour
end

-- The garage list. Rebuilt only when the server has told us something new, or when which
-- car is being edited changes.
local function refreshGarage()
	for _, child in Tuner.garageRows do
		child:Destroy()
	end
	Tuner.garageRows = {}
	local names = Garage.names(Tuner.cars)
	garageHeader.Text = `SAVED CARS  {#names}/{C.GarageMaxCars}{if Tuner.persists then "" else "   (this server only: no DataStore)"}`
	for i, name in names do
		local r = Instance.new("Frame")
		r.Name = `Car_{i}`
		r.BackgroundTransparency = 1
		r.Size = UDim2.new(1, 0, 0, 20)
		r.LayoutOrder = i
		r.ZIndex = 2
		r.Parent = garageList
		table.insert(Tuner.garageRows, r)

		local load = button(r, "Load", name)
		load.Size = UDim2.new(1, -24, 1, 0)
		load.TextXAlignment = Enum.TextXAlignment.Left
		load.TextSize = 13
		load.ZIndex = 3
		load.BackgroundColor3 = if name == Tuner.loadedName then FILL else TRACK
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 6)
		padding.Parent = load

		local del = button(r, "Delete", "×")
		del.Size = UDim2.fromOffset(20, 20)
		del.AnchorPoint = Vector2.new(1, 0)
		del.Position = UDim2.fromScale(1, 0)
		del.TextSize = 13
		del.ZIndex = 3

		load.Activated:Connect(function()
			Tuner.load(name)
		end)
		del.Activated:Connect(function()
			garageDelete:FireServer(name)
			if Tuner.loadedName == name then
				Tuner.loadedName = nil
			end
			setStatus(`deleted "{name}"`, DIM)
		end)
	end
end

local function refresh()
	refreshSliders()
	refreshGarage()
end

Tuner.refresh = refreshSliders -- what a slider move calls; the garage list is untouched

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

function Tuner.setOpen(open: boolean)
	Tuner.open = open
	panel.Visible = open
	panel.Active = open -- CLOSED MEANS CLOSED: an invisible Active frame would still
	-- swallow the touch that was meant to steer the car
	openButton.Text = if open then "HIDE" else "TUNE"
	if not open then
		dialog.Visible = false
		Tuner.dragging = nil
	else
		refresh()
	end
end

function Tuner.toggle()
	Tuner.setOpen(not Tuner.open)
end

-- Switch the archetype under the tune. The tune itself is kept: the sliders are absolute
-- numbers, so "the gripper with my steering rate" is a car somebody may want -- but
-- anything the tune does not cover (the body, the geometry, the multipliers) comes from
-- the new base.
--
-- THE SERVER DECIDES, exactly as the readout's F4 does (`CarService`, T-033): this asks
-- over `CarSwitch` and takes the car locally while the asking is in flight, so the feel
-- changes on the next step. The server's answer settles it below.
function Tuner.setBase(key: string)
	if not Cars.exists(key) then
		return
	end
	Tuner.base = key
	Tuner.dirtySince = true
	Cars.setActive(key)
	applyTune()
	carSwitch:FireServer(key)
	sendTune(true)
	refresh()
end

function Tuner.reset()
	Tuner.tune = {}
	Tuner.loadedName = nil
	Tuner.dirtySince = false
	applyTune()
	sendTune(true)
	setStatus("back to the plain car", DIM)
	refresh()
end

function Tuner.load(name: string)
	local car = Tuner.cars[name]
	if not car then
		setStatus(`no car called "{name}"`, BAD)
		refresh()
		return
	end
	Tuner.loadedName = name
	Tuner.dirtySince = false
	Tuner.tune = Garage.sanitizeTune(car.tune)
	if car.base ~= Tuner.base then
		Tuner.base = car.base
		Cars.setActive(car.base)
		carSwitch:FireServer(car.base)
	end
	applyTune()
	sendTune(true)
	setStatus(`driving "{name}"`, GOOD)
	refresh()
end

function Tuner.save(name: string?)
	local clean = Garage.cleanName(name or Tuner.loadedName)
	if not clean then
		Tuner.askName()
		return
	end
	garageSave:FireServer(clean, Tuner.base, Tuner.tune)
	Tuner.loadedName = clean
	Tuner.dirtySince = false
	setStatus(`saving "{clean}"…`, DIM)
	refresh()
end

function Tuner.askName()
	nameBox.Text = Tuner.loadedName or ""
	dialog.Visible = true
	nameBox:CaptureFocus()
end

closeButton.Activated:Connect(function()
	Tuner.setOpen(false)
end)
openButton.Activated:Connect(Tuner.toggle)
prevCar.Activated:Connect(function()
	-- `nextKey` only walks forwards, so backwards is the key whose next is this one.
	local key = Tuner.base
	for _ = 1, #Cars.Order - 1 do
		key = Cars.nextKey(key)
	end
	Tuner.setBase(key)
end)
nextCar.Activated:Connect(function()
	Tuner.setBase(Cars.nextKey(Tuner.base))
end)
saveButton.Activated:Connect(function()
	Tuner.save(nil)
end)
saveAsButton.Activated:Connect(function()
	Tuner.askName()
end)
resetButton.Activated:Connect(Tuner.reset)
okButton.Activated:Connect(function()
	local clean = Garage.cleanName(nameBox.Text)
	if not clean then
		setStatus("a car needs a name", BAD)
		refresh()
		return
	end
	dialog.Visible = false
	Tuner.save(clean)
end)
cancelButton.Activated:Connect(function()
	dialog.Visible = false
end)
nameBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		local clean = Garage.cleanName(nameBox.Text)
		if clean then
			dialog.Visible = false
			Tuner.save(clean)
		end
	end
end)

--------------------------------------------------------------------------------
-- The wire
--------------------------------------------------------------------------------

garageData.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	Tuner.cars = {}
	for name, car in Garage.sanitizeGarage(payload.cars) do
		Tuner.cars[name] = car
	end
	Tuner.persists = payload.persists == true
	if Tuner.loadedName and Tuner.cars[Tuner.loadedName] and not Tuner.dirtySince then
		setStatus(`saved "{Tuner.loadedName}"`, GOOD)
	end
	refresh()
end)
garageData:FireServer() -- "what is in my garage?"

-- Which archetype the server says we are in. The tuner follows it whoever moved it --
-- its own arrows, the readout's F4, or the server putting a client back.
carSwitch.OnClientEvent:Connect(function(key, accepted)
	if type(key) ~= "string" or not Cars.exists(key) then
		return
	end
	if key ~= Tuner.base then
		Tuner.base = key
		if Cars.activeKey() ~= key then
			Cars.setActive(key)
		end
		applyTune()
		sendTune(true)
	end
	if accepted == false then
		setStatus("the server refused that car", BAD)
	end
	refresh()
end)

-- The tune the send rate held back. One check a frame costs nothing and means a slider
-- let go of between ticks is still reported.
RunService.RenderStepped:Connect(function()
	if Tuner.pending and os.clock() - Tuner.sent >= 1 / math.max(C.TunerSendRate, 1) then
		sendTune(true)
	end
end)

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

-- The Input Action System, as everything new is (CODING.md "Conventions"). `Sink = false`
-- so the drive controls under it are untouched.
local context = Instance.new("InputContext")
context.Name = "DriftTuner"
context.Priority = 900
context.Sink = false

local toggleAction = Instance.new("InputAction")
toggleAction.Name = "TunerToggle"
toggleAction.Type = Enum.InputActionType.Bool
toggleAction.Parent = context

local keyBinding = Instance.new("InputBinding")
keyBinding.Name = "Key"
keyBinding.KeyCode = C.TunerKey
keyBinding.Parent = toggleAction

local padBinding = Instance.new("InputBinding")
padBinding.Name = "Pad"
padBinding.KeyCode = C.TunerGamepadKey
padBinding.Parent = toggleAction

context.Parent = player:WaitForChild("PlayerScripts")
toggleAction.Pressed:Connect(Tuner.toggle)

--------------------------------------------------------------------------------
-- Studio
--------------------------------------------------------------------------------

-- The client debug bridge only reaches loaded CONTROLLERS, and this is a LocalScript, so
-- it puts up its own -- the same shape, next to the other one
-- (docs/workflow/TESTING.md "Reaching live game state"):
--
--   game.Players.LocalPlayer.PlayerScripts.TunerBridge:Invoke("DebugState")
local function debugState()
	local vals = values()
	local shown = {}
	for id, r in Tuner.rows do
		shown[id] = {
			value = vals[id],
			fill = r.fill.Size.X.Scale,
			trackX = r.track.AbsolutePosition.X,
			trackW = r.track.AbsoluteSize.X,
			trackY = r.track.AbsolutePosition.Y + GuiService:GetGuiInset().Y,
			tuned = Tuner.tune[id] ~= nil,
		}
	end
	return {
		open = Tuner.open,
		visible = panel.Visible,
		active = panel.Active,
		base = Tuner.base,
		activeCar = Cars.activeKey(),
		loadedName = Tuner.loadedName,
		dirty = Tuner.dirtySince,
		dragging = Tuner.dragging,
		tune = Tuner.tune,
		values = vals,
		carFields = Garage.toCarFields(Tuner.tune),
		-- What the MODEL will read on its next step. The proof that a slider landed is
		-- this agreeing with `values` above, and it comes out of `Config.Drift` rather
		-- than out of anything this file holds.
		live = {
			MaxSteeringSpeed = C.MaxSteeringSpeed,
			ConstantFriction = C.ConstantFriction,
			SlipFriction = C.SlipFriction,
			SlipSqFriction = C.SlipSqFriction,
			MaxFriction = C.MaxFriction,
			MaxAcceleration = C.MaxAcceleration,
			TopSpeed = C.TopSpeed,
			DownforcePerSpeed = C.DownforcePerSpeed,
		},
		cars = Garage.names(Tuner.cars),
		persists = Tuner.persists,
		status = Tuner.status,
		panel = { x = panel.AbsolutePosition.X, y = panel.AbsolutePosition.Y, w = panel.AbsoluteSize.X, h = panel.AbsoluteSize.Y },
		sliders = shown,
	}
end

if RunService:IsStudio() then
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "TunerBridge"
	bridge.OnInvoke = function(member: string, ...)
		if member == "DebugState" then
			return debugState()
		elseif member == "Toggle" then
			Tuner.toggle()
			return debugState()
		elseif member == "SetOpen" then
			Tuner.setOpen((...) == true)
			return debugState()
		elseif member == "Set" then
			local id, value = ...
			setValue(id, value)
			return debugState()
		elseif member == "SetBase" then
			Tuner.setBase((...))
			return debugState()
		elseif member == "Save" then
			Tuner.save((...))
			return debugState()
		elseif member == "Load" then
			Tuner.load((...))
			return debugState()
		elseif member == "Delete" then
			garageDelete:FireServer((...))
			return debugState()
		elseif member == "Reset" then
			Tuner.reset()
			return debugState()
		end
		error(`TunerBridge: no '{tostring(member)}'. There is: DebugState, Toggle, SetOpen, Set, SetBase, Save, Load, Delete, Reset`, 0)
	end
	bridge.Parent = player:WaitForChild("PlayerScripts")
end

Tuner.setOpen(Tuner.open)
refresh()
