--!nonstrict
-- ScoreHudView: the endless run's score panel (docs/game/features/endless-score.md "UI",
-- docs/workflow/UI.md). Programmer art.
--
-- A VIEW, and only that (UI.md "Each screen is a view"): it builds the panel and draws it
-- from a plain table. It reads no remote and no controller; `ScoreController` hands it a
-- snapshot every frame, and `ScoreHudView.fixtures` hands it samples for measuring.
--
--   setData({ mode = "run", score, multiplier, progress, maxMultiplier })
--   setData({ mode = "summary", score, best, newBest })
--   setData({ mode = "hidden" })
--
-- WHERE IT SITS. Top centre, straight under the run button and its state line
-- (`Drift/RoadHud`: a 220 x 44 button 8 px below the inset, its line under that to 74 px),
-- so the eye goes button, line, score. The same place in every layout: it is 220 px wide,
-- which fits the narrowest supported screen (390 px, phone portrait) with 85 px either side,
-- and it is the button's own column, so it covers nothing the button does not already.
--
-- IT NEVER TAKES A TOUCH. The whole screen is the steering pad (`Drift/DragControl`), and a
-- panel that ate a thumb would be a dead patch in it. Nothing here is `Active`, and its
-- `DisplayOrder` (14) is under the run button's 15, so it can never cover the button either.
--
-- NOT `IgnoreGuiInset`, unlike UI.md's default and like `Drift/RoadHud`: it hangs off the
-- run button, which starts below the inset, and two screens measured from two different
-- tops would drift apart on every device whose inset differs.

local ScoreHudView = {}
ScoreHudView.__index = ScoreHudView

local INK = Color3.fromRGB(240, 242, 248)
local DIM = Color3.fromRGB(190, 196, 210)
local PLATE = Color3.fromRGB(20, 22, 30)
local BAR_BACK = Color3.fromRGB(60, 64, 78)
local BAR_FILL = Color3.fromRGB(255, 196, 64)
local NEW_BEST = Color3.fromRGB(255, 214, 96)

local WIDTH = 220
local TOP = 80 -- px below the inset: under the run button (8 + 44) and its line (to 74)
local HEIGHT = 58
local PAD = 8
local SCORE_SIZE = 28
local MULT_SIZE = 22
local LINE_SIZE = 16
local BAR_HEIGHT = 6

local function new(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function text(name: string, size: number, font: Enum.Font, parent: Instance): TextLabel
	local label = new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		TextSize = size,
		FontFace = Font.fromEnum(font),
		-- Over the sky as often as not: the stroke is what makes it read on anything
		-- (T-040, the "i can't see the text" bug, as `Drift/RoadHud` says).
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.4,
		Active = false,
		ZIndex = 2,
		-- A big score shrinks to fit rather than spilling out of the plate: down to 16 px,
		-- which is UI.md's floor for text a player must read.
		TextScaled = true,
	}, parent)
	new("UITextSizeConstraint", { MaxTextSize = size, MinTextSize = 16 }, label)
	return label
end

-- 48210.7 -> "48,210". The score is a float in the engine; it is always shown whole.
function ScoreHudView.format(n: number): string
	local s = tostring(math.floor(math.max(n or 0, 0)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function ScoreHudView.new(parent: Instance)
	local self = setmetatable({}, ScoreHudView)
	self.offsets = {}
	self.mode = "hidden"

	local gui = new("ScreenGui", {
		Name = "ScoreHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 14, -- under the run button (15), over the drag pad (5)
		Enabled = false,
	}, parent)
	self.gui = gui

	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		BackgroundColor3 = PLATE,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Active = false,
	}, gui)
	panel:SetAttribute("LayoutItem", "ScorePanel")
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, panel)
	self.panel = panel

	-- The live run: the score left, the rung right, the bar under both.
	local score = text("Score", SCORE_SIZE, Enum.Font.GothamBlack, panel)
	score.TextXAlignment = Enum.TextXAlignment.Left
	score.Position = UDim2.fromOffset(PAD, 6)
	score.Size = UDim2.fromOffset(WIDTH - PAD * 2 - 56, 34)
	self.score = score

	local mult = text("Multiplier", MULT_SIZE, Enum.Font.GothamBold, panel)
	mult.TextXAlignment = Enum.TextXAlignment.Right
	mult.Position = UDim2.fromOffset(WIDTH - PAD - 56, 6)
	mult.Size = UDim2.fromOffset(56, 34)
	mult.TextColor3 = BAR_FILL
	self.mult = mult

	local bar = new("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(PAD, HEIGHT - PAD - BAR_HEIGHT),
		Size = UDim2.fromOffset(WIDTH - PAD * 2, BAR_HEIGHT),
		BackgroundColor3 = BAR_BACK,
		BorderSizePixel = 0,
		ClipsDescendants = true, -- the fill is clipped, never stretched past the casing
		Active = false,
		ZIndex = 2,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, bar)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = BAR_FILL,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 3,
	}, bar)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, fill)
	self.bar, self.fill = bar, fill

	-- The summary: two lines in place of the live score.
	local runLine = text("RunScore", LINE_SIZE + 4, Enum.Font.GothamBlack, panel)
	runLine.Position = UDim2.fromOffset(PAD, 6)
	runLine.Size = UDim2.fromOffset(WIDTH - PAD * 2, 24)
	self.runLine = runLine

	local bestLine = text("Best", LINE_SIZE, Enum.Font.GothamBold, panel)
	bestLine.Position = UDim2.fromOffset(PAD, 32)
	bestLine.Size = UDim2.fromOffset(WIDTH - PAD * 2, 20)
	bestLine.TextColor3 = DIM
	self.bestLine = bestLine

	self:_layout()
	self:setData({ mode = "hidden" })
	return self
end

function ScoreHudView:_layout()
	local o = self.offsets.ScorePanel or Vector2.zero
	self.panel.Position = UDim2.new(0.5, o.X, 0, TOP + o.Y)
end

function ScoreHudView:setData(data)
	data = data or { mode = "hidden" }
	local mode = data.mode or "hidden"
	self.mode = mode
	self.data = data
	if mode == "hidden" then
		self.gui.Enabled = false
		return
	end
	self.gui.Enabled = true
	local live = mode == "run"
	self.score.Visible = live
	self.mult.Visible = live
	self.bar.Visible = live
	self.runLine.Visible = not live
	self.bestLine.Visible = not live

	if live then
		self.score.Text = ScoreHudView.format(data.score)
		self.mult.Text = `x{data.multiplier or 1}`
		-- Below 0 is the grace before a rung is lost (`Drift/Score`): drawn as empty. At
		-- the top rung the bar is full and stays full.
		self.fill.Size = UDim2.fromScale(math.clamp(data.progress or 0, 0, 1), 1)
	else
		self.runLine.Text = `RUN SCORE {ScoreHudView.format(data.score)}`
		if data.newBest then
			self.bestLine.Text = `NEW BEST {ScoreHudView.format(data.best)}`
			self.bestLine.TextColor3 = NEW_BEST
		else
			self.bestLine.Text = `BEST {ScoreHudView.format(data.best)}`
			self.bestLine.TextColor3 = DIM
		end
	end
end

function ScoreHudView:show()
	if self.mode ~= "hidden" then
		self.gui.Enabled = true
	end
end

function ScoreHudView:hide()
	self.gui.Enabled = false
end

function ScoreHudView:setLayoutOffset(name: string, offset: Vector2?)
	self.offsets[name] = offset
	self:_layout()
end

local function rect(g: GuiObject)
	return {
		position = g.AbsolutePosition,
		size = g.AbsoluteSize,
		visible = g.Visible,
	}
end

-- Its pieces' rects and states, for the UI checks (TESTING.md "Checking UI").
function ScoreHudView:describe()
	return {
		mode = self.mode,
		enabled = self.gui.Enabled,
		displayOrder = self.gui.DisplayOrder,
		panel = rect(self.panel),
		score = rect(self.score),
		scoreText = self.score.Text,
		multiplier = rect(self.mult),
		multiplierText = self.mult.Text,
		bar = rect(self.bar),
		fill = rect(self.fill),
		runLine = rect(self.runLine),
		runText = self.runLine.Text,
		bestLine = rect(self.bestLine),
		bestText = self.bestLine.Text,
		anyActive = (function()
			for _, d in self.gui:GetDescendants() do
				if d:IsA("GuiObject") and d.Active then
					return true
				end
			end
			return false
		end)(),
	}
end

function ScoreHudView:destroy()
	self.gui:Destroy()
end

return ScoreHudView
