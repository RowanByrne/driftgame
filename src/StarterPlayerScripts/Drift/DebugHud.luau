--!nonstrict
-- DebugHud: the programmer-art readout, top left
-- (docs/game/features/drift-model.md "UI", docs/game/features/car-archetypes.md).
-- Nothing else is on screen in the prototype; the real HUD waits for scoring.
--
-- It shows what the tuning conversation asks about, which since the port is a different
-- list: speed, the slip angle and whether the car counts as drifting, the yaw rate the
-- finger is setting, the lateral pull the grip is actually making against its ceiling,
-- the throttle easing itself in, which wheels are down and on what, and the simulation
-- step the frame really spent. Toggled by F3, gamepad DPad up, or the DBG button on touch.
--
-- Folded inside it is THE CAR'S STAT PANEL (T-027), in the same shape the reference uses
-- in its own shop:
--
--   * three bars -- acceleration, handling, top speed -- that are HAND-WRITTEN AND
--     DISPLAY ONLY. Nothing computes them from the physics and nothing reads them back
--     into it. They are marketing, deliberately, and they are marked as such on screen.
--   * the four numbers that are REAL, each as a fraction of the design space's maximum:
--     the rate of turn and the three grip terms. These are the car.
--   * the grip curve those four make, plotted from 0 to 90 degrees of slip, with the
--     ceiling drawn across it. It is the honest picture of how a car drifts, and it is
--     the same `f(b)` the model uses every step.
--
-- F4 switches car (or gamepad DPad right), F5 folds the panel, and clicking its header
-- does the same. The switch takes effect on the next simulation step, so a tester can
-- hold one finger through it and feel the car change underneath them.
--
-- F4 ASKS; IT DOES NOT DECIDE (T-033). Which car a player is in is the server's
-- (`CarService`, docs/game/CONTRACTS.md `CarSwitch`): the key switches this client's car
-- at once, because a client-side model is the only reason the feel can change under a
-- held finger, and it sends the same key to the server in the same breath. The server
-- validates it, re-dresses the car so the SHAPE follows too, and answers -- and the
-- answer is what settles it. A refused ask puts this client back in the car the server
-- believes, which is why the prediction is safe: it can be taken away.
--
-- The readout is off while anyone is driving: it is a measuring instrument, not part of
-- the game, and a wall of numbers over the car is the one thing a feel test cannot
-- afford. Whether it opens at spawn is `Config.Drift.DebugReadoutOpen`, which should be
-- false; this file only obeys it, and the toggle brings it back whole.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local DriftModel = require(script.Parent.Model)
local Net = require(ReplicatedStorage.Shared.Net)

local DebugHud = {}
DebugHud.__index = DebugHud

-- Art, not tuning. The rows are monospace, so the widest one sets the width: the grip row
-- measured 592 px at text size 17, inside a 540 px panel, so it was running out of its own
-- panel. 592 * 14 / 17 = 488, plus 20 px of padding.
local TEXT_SIZE = 14
local ROW_HEIGHT = 17
local PANEL_WIDTH = 508

local GRAPH_HEIGHT = 64
local GRAPH_POINTS = 31 -- 0 to 90 degrees, every 3

local ROWS = {
	"speed",
	"slip",
	"grip",
	"drive",
	"engine",
	"ground",
	"step",
	"input",
	"where",
	"score",
}

-- The stat panel's own rows, in order. `bars` is the hand-written three; `real1`..`real4`
-- are the four numbers that are actually the car.
local STAT_ROWS = {
	"character",
	"blurb",
	"bars",
	"realhead",
	"real1",
	"real2",
	"real3",
	"real4",
}

local INK = Color3.fromRGB(235, 238, 245)
local DIM = Color3.fromRGB(150, 156, 170)
local MARKETING = Color3.fromRGB(255, 205, 120)
local REAL = Color3.fromRGB(140, 220, 255)
local CURVE = Color3.fromRGB(120, 230, 150)
local CEILING = Color3.fromRGB(255, 120, 120)

local GRIPPING = Color3.fromRGB(150, 220, 150)
local DRIFTING = Color3.fromRGB(255, 150, 90)
local BRAKING = Color3.fromRGB(255, 110, 110)
local AIRBORNE = Color3.fromRGB(210, 160, 255)

-- Every car's curve is drawn to ONE scale, so switching car moves the curve rather than
-- rescaling the axis and showing the same shape every time. The scale is the hardest any
-- car in the game can pull, found once.
local function curveCeiling(): number
	local most = 1
	for _, key in Cars.Order do
		most = math.max(most, Cars.stats(key).samples[90])
	end
	return most * 1.1
end

-- A row of text in a list-laid-out frame.
local function textRow(parent: Instance, name: string, order: number, colour: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	label.LayoutOrder = order
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = colour or INK
	label.TextSize = TEXT_SIZE
	label.FontFace = Font.fromEnum(Enum.Font.Code)
	label.Text = ""
	label.Parent = parent
	return label
end

-- Ten blocks, as many filled as the number says. The bars are 0..10 and hand-written.
local function barText(value: number): string
	local filled = math.clamp(math.round(value), 0, 10)
	return string.rep("#", filled) .. string.rep(".", 10 - filled)
end

function DebugHud.new()
	local self = setmetatable({}, DebugHud)

	local gui = Instance.new("ScreenGui")
	gui.Name = "DriftDebug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 10
	gui.Enabled = Config.Drift.DebugReadoutOpen == true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- One column, so the stat panel sits under the readout and neither has to know how
	-- tall the other is.
	local column = Instance.new("Frame")
	column.Name = "Column"
	column.BackgroundTransparency = 1
	column.Position = UDim2.fromOffset(12, 12)
	column.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.Parent = gui

	local columnLayout = Instance.new("UIListLayout")
	columnLayout.Padding = UDim.new(0, 6)
	columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnLayout.Parent = column

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
	panel.BackgroundTransparency = 0.25 -- text over moving gameplay needs a real backing
	panel.BorderSizePixel = 0
	panel.LayoutOrder = 1
	-- Wide enough for the longest row: a readout whose text is clipped is one nobody
	-- trusts, and small, because when it is open it is sitting over the car.
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 8 + #ROWS * (ROW_HEIGHT + 2) + 8)
	panel.Parent = column

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
		self.labels[key] = textRow(panel, key, i)
	end

	----------------------------------------------------------------- the stat panel
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
	stats.BackgroundTransparency = 0.25
	stats.BorderSizePixel = 0
	stats.LayoutOrder = 2
	stats.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
	stats.AutomaticSize = Enum.AutomaticSize.Y
	stats.Parent = column

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.Padding = UDim.new(0, 2)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = stats

	local statsPadding = Instance.new("UIPadding")
	statsPadding.PaddingTop = UDim.new(0, 6)
	statsPadding.PaddingBottom = UDim.new(0, 6)
	statsPadding.PaddingLeft = UDim.new(0, 10)
	statsPadding.PaddingRight = UDim.new(0, 10)
	statsPadding.Parent = stats

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	header.LayoutOrder = 0
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = INK
	header.TextSize = TEXT_SIZE
	header.FontFace = Font.fromEnum(Enum.Font.Code)
	header.Text = ""
	header.AutoButtonColor = false
	header.Parent = stats

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.LayoutOrder = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Visible = Config.Drift.DebugStatsOpen == true
	body.Parent = stats

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 2)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	self.stat = {}
	for i, key in STAT_ROWS do
		local colour = INK
		if key == "bars" then
			colour = MARKETING
		elseif key == "blurb" then
			colour = DIM
		elseif key:match("^real") then
			colour = REAL
		end
		self.stat[key] = textRow(body, key, i, colour)
	end

	----------------------------------------------------------------- the grip curve
	local graph = Instance.new("Frame")
	graph.Name = "Graph"
	graph.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	graph.BorderSizePixel = 0
	graph.LayoutOrder = #STAT_ROWS + 1
	graph.Size = UDim2.new(1, 0, 0, GRAPH_HEIGHT)
	graph.Parent = body

	local ceilingLine = Instance.new("Frame")
	ceilingLine.Name = "Ceiling"
	ceilingLine.BackgroundColor3 = CEILING
	ceilingLine.BackgroundTransparency = 0.4
	ceilingLine.BorderSizePixel = 0
	ceilingLine.AnchorPoint = Vector2.new(0, 1)
	ceilingLine.Size = UDim2.new(1, 0, 0, 1)
	ceilingLine.Parent = graph

	self.curveBars = {}
	for i = 1, GRAPH_POINTS do
		local bar = Instance.new("Frame")
		bar.Name = ("p%d"):format(i)
		bar.BackgroundColor3 = CURVE
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new((i - 1) / (GRAPH_POINTS - 1), 0, 1, 0)
		bar.Size = UDim2.new(1 / GRAPH_POINTS, -2, 0, 1)
		bar.Parent = graph
		self.curveBars[i] = bar
	end

	self.graph = graph
	self.ceilingLine = ceilingLine
	self.samples = textRow(body, "samples", #STAT_ROWS + 2, DIM)
	self.axis = textRow(body, "axis", #STAT_ROWS + 3, DIM)

	self.gui = gui
	self.statsBody = body
	self.header = header
	self.curveCeiling = curveCeiling()
	self.shownCar = nil -- so the first Update draws the car whatever it is

	header.Activated:Connect(function()
		self:ToggleStats()
	end)

	-- Which car this client is in is the SERVER's answer, and this is where the client
	-- hears it. The listener lives here because F4 lives here: while switching car is a
	-- tester's key rather than a player's choice, the debug readout is the whole of the
	-- feature on this side (docs/game/CONTRACTS.md, `CarSwitch`).
	self.asked = 0
	self.refused = 0
	self.pending = nil -- a car asked for and not yet answered
	self.serverCar = Cars.activeKey()
	self.carSwitch = Net.event("CarSwitch")
	self.carSwitch.OnClientEvent:Connect(function(key, accepted)
		self:_answered(key, accepted)
	end)
	-- "Which car does the server have me in?" The server sends this with the spawn too,
	-- and a client built after that would have missed it.
	self.carSwitch:FireServer()

	-- F4 switches car, F5 folds the panel. Bound here rather than in CarInputController
	-- because both are about this panel and nothing else; the driving controls are that
	-- file's and stay there.
	self.actionNext = "DriftDebugNextCar"
	self.actionFold = "DriftDebugFoldStats"
	ContextActionService:BindAction(self.actionNext, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:AskForNextCar()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F4, Enum.KeyCode.DPadRight)
	ContextActionService:BindAction(self.actionFold, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:ToggleStats()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F5)

	return self
end

-- Ask for the next car round the list, and take it locally while the asking is in flight.
--
-- PREDICTING IS THE POINT, not a shortcut: the model runs on this client, so taking the
-- car now is what makes the feel change under a finger already held, on the very next
-- step. It is safe because it is not a decision -- the server's answer overwrites it, and
-- a refusal puts this client back in whatever car the server believes.
function DebugHud:AskForNextCar(): string
	local want = Cars.nextKey()
	self.pending = want
	self.asked += 1
	Cars.setActive(want) -- predicted; the answer below settles it
	self.shownCar = nil
	self.carSwitch:FireServer(want)
	return want
end

-- The server's answer: the car it says this client is in, and whether the last ask was
-- taken. Either way this client ends up in the server's car, because the server is the
-- one that knows.
function DebugHud:_answered(key: string, accepted: boolean?)
	if type(key) ~= "string" or not Cars.exists(key) then
		return
	end
	if accepted == false then
		self.refused += 1
	end
	self.pending = nil
	self.serverCar = key
	if Cars.activeKey() ~= key then
		Cars.setActive(key)
	end
	self.shownCar = nil -- the header says which car and whether it was refused
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

function DebugHud:ToggleStats(): boolean
	self.statsBody.Visible = not self.statsBody.Visible
	self.shownCar = nil -- the header says which way the fold goes, so redraw it
	self:drawCar()
	return self.statsBody.Visible
end

-- Redraw the stat panel. Only when the car has actually changed: a curve of 31 frames
-- rewritten every frame is a lot of nothing.
function DebugHud:drawCar()
	local s = Cars.stats()
	if self.shownCar == s.key then
		return
	end
	self.shownCar = s.key

	-- The server's word on which car this is, on screen beside the car: `asking` while an
	-- ask is in flight, `refused` when one came back no, `server` when the two agree.
	local answer = if self.pending
		then ("asking %s"):format(self.pending)
		elseif self.refused > 0 then ("server %s, %d refused"):format(self.serverCar, self.refused)
		else ("server %s"):format(self.serverCar)
	self.header.Text = ("car    %-10s [%s]  %-22s F4 next   F5 %s"):format(
		s.name,
		s.key,
		answer,
		if self.statsBody.Visible then "fold" else "unfold"
	)
	self.stat.character.Text = ("       %s"):format(s.character)

	-- The line that has to be on screen: these three are not the physics.
	self.stat.blurb.Text = "bars   HAND-WRITTEN, display only -- nothing computes them and nothing reads them"
	self.stat.bars.Text = ("       accel %s  handling %s  top %s"):format(
		barText(s.bars.Acceleration),
		barText(s.bars.Handling),
		barText(s.bars.TopSpeed)
	)

	self.stat.realhead.Text = "real   the car, as fractions of the design space"
	local LABELS = {
		MaxSteeringSpeed = "rate of turn  ",
		ConstantFriction = "grip, straight",
		SlipFriction = "grip, linear  ",
		SlipSqFriction = "grip, squared ",
	}
	local UNITS = {
		MaxSteeringSpeed = "rad/s",
		ConstantFriction = "st/s^2",
		SlipFriction = "st/s^2/rad",
		SlipSqFriction = "st/s^2/rad^2",
	}
	for i, real in s.reals do
		self.stat[("real%d"):format(i)].Text = ("       %s %7.1f of %7.1f %-12s %s %3.0f%%"):format(
			LABELS[real.field],
			real.value,
			real.max,
			UNITS[real.field],
			barText(real.fraction * 10),
			real.fraction * 100
		)
	end

	-- The curve, to a scale shared by every car, with the car's own ceiling across it.
	local top = self.curveCeiling
	for i, bar in self.curveBars do
		local point = s.curve[i]
		bar.Size = UDim2.new(1 / GRAPH_POINTS, -2, math.clamp(point.f / top, 0, 1), 0)
	end
	self.ceilingLine.Position = UDim2.new(0, 0, 1 - math.clamp(s.maxFriction / top, 0, 1), 0)

	self.samples.Text = ("curve  0deg %5.1f  15 %5.1f  30 %5.1f  45 %5.1f  60 %5.1f  90 %5.1f studs/s^2"):format(
		s.samples[0],
		s.samples[15],
		s.samples[30],
		s.samples[45],
		s.samples[60],
		s.samples[90]
	)
	self.axis.Text = ("       slip 0 to 90 deg across, 0 to %.0f studs/s^2 up; red is this car's ceiling (%.0f)"):format(
		top,
		s.maxFriction
	)
end

-- `extra` carries what the model does not know about: the frame, the input and the world.
function DebugHud:Update(state: DriftModel.State?, extra)
	if not self.gui.Enabled then
		return
	end
	self:drawCar()
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

	-- Rotating IS drifting: the slip angle and the yaw rate the finger is setting, side by
	-- side, because the whole model is the gap between them.
	L.slip.Text = ("slip   %+6.1f deg  %-8s yaw %+5.2f rad/s  heading %5.1f deg"):format(
		math.deg(state.slip),
		if state.braking then "BACKWARDS" elseif state.drifting then "DRIFTING" else "straight",
		state.r,
		math.deg(state.yaw) % 360
	)
	L.slip.TextColor3 = if state.braking then BRAKING elseif state.drifting then DRIFTING else GRIPPING

	L.grip.Text = ("grip   %6.1f of %.0f studs/s^2  surface %4.2f  %s"):format(
		state.gripAccel,
		C.MaxFriction,
		state.surfaceGrip,
		if state.braking then "pulling AGAINST the travel" else "pulling toward the nose"
	)

	L.drive.Text = ("drive  throttle %4.2f  along the nose %6.1f  across %+6.1f studs/s"):format(
		state.throttle,
		state.u,
		state.v
	)

	-- The fake engine the sound follows (T-125). Sound only: the drive above never reads it.
	local eng = extra and extra.engine
	if eng then
		L.engine.Text = ("engine %5.0f rpm  gear %d  throttle %4.2f  %s  %s"):format(
			eng.rpm,
			eng.gear,
			eng.load,
			if eng.inDrift then "DRIFT" else "-----",
			if eng.cut then "LIMITER" else ""
		)
		L.engine.TextColor3 = if eng.cut then BRAKING elseif eng.inDrift then DRIFTING else INK
	else
		L.engine.Text = ""
	end

	local wheels = ""
	for i, down in state.wheelsDown do
		wheels ..= if down then ("%d"):format(i) else "-"
	end
	L.ground.Text = ("ground %-9s wheels %s  %s  %s"):format(
		if state.airborne then "AIRBORNE" else "on",
		wheels,
		if state.rearDown then "driven" else "coasting",
		if extra and extra.surfaceTag then "tagged" else "fallback"
	)
	L.ground.TextColor3 = if state.airborne then AIRBORNE else INK

	L.step.Text = ("step   %5.2f ms x%d/frame   frame %5.1f ms"):format(
		C.FixedStep * 1000,
		(extra and extra.steps) or 0,
		((extra and extra.frameSeconds) or 0) * 1000
	)
	-- The finger and what it buys: a rate of turn, nothing else.
	L.input.Text = ("input  finger %+5.2f = %+5.2f rad/s  %s  [%s]"):format(
		(extra and extra.steerInput) or 0,
		state.r,
		if extra and extra.handbrake then "HANDBRAKE" else "---------",
		(extra and extra.device) or "?"
	)
	L.where.Text = ("where  %7.1f %7.1f %7.1f   vy %6.1f"):format(
		state.position.X,
		state.position.Y,
		state.position.Z,
		state.vy
	)
	-- The endless run's score (T-119): what it is, the rung and its bar, in numbers. The
	-- score panel shows the same to a player; this is for tuning the ladder.
	local sc = extra and extra.score
	if sc and sc.inRun then
		L.score.Text = ("score  %9.0f  x%d  bar %+5.2f  %s"):format(
			sc.score,
			sc.multiplier,
			sc.progress,
			if sc.scoring then "SCORING" else "-------"
		)
	else
		L.score.Text = "score  not in a run"
	end
end

function DebugHud:Destroy()
	ContextActionService:UnbindAction(self.actionNext)
	ContextActionService:UnbindAction(self.actionFold)
	self.gui:Destroy()
end

return DebugHud
