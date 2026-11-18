--!nonstrict
-- Live score events sit above the rank. One-offs, losses and hairpin notices sit below it.
-- Feed entries carry cumulative points, including the multiplier. The two bank callbacks
-- coordinate presentation with the score HUD; neither one awards points.
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local UI = script.Parent.Parent:WaitForChild("UI")
local Create = require(UI:WaitForChild("Create"))
local Layers = require(UI:WaitForChild("Layers"))
local Tape = require(UI:WaitForChild("ScoreTape"))
local Style = require(UI:WaitForChild("Theme")).ScoreTape

local ScoreFeedView = {}
ScoreFeedView.__index = ScoreFeedView

local C = {
	Width = 220,
	LineHeight = 20,
	Gap = 2,
	RankGap = 5,
	TextSize = 16,
	Lines = 5,
	PhoneLines = 3,
	SlideTime = 0.16,
	OneOffHold = 2.5,
	NoticeHold = 2,
	FinishedHold = 2,
	Fade = 0.4,
	MergeWindow = 1.5,
	BankTime = 0.43,
	CountRate = 14,
}
ScoreFeedView.Config = C
function ScoreFeedView.format(n: number): string
	return Tape.format(math.round(n or 0))
end

local TEXT = {
	Merged = "{name} x{count}",
	Points = "+{points}",
	Lost = "LOST <s>+{points}</s>",
	LostPlain = "LOST +{points}", -- the same, measured without its tags
	-- notices: whole words, each its own string
	Notices = {
		hairpinAhead = "HAIRPIN AHEAD",
	},
	Left = "LEFT",
	Right = "RIGHT",
}

local function fill(template: string, values): string
	return (template:gsub("{(%w+)}", function(k)
		return tostring(values[k])
	end))
end

function ScoreFeedView.new(parent: Instance)
	local self = setmetatable({}, ScoreFeedView)
	self.offsets = {}
	self.lines = {}
	self.byId = {}
	self.t = 0
	self.hold = false
	self.serial = 0
	self:setRung(1)
	self.gui = Create("ScreenGui", {
		Name = "ScoreFeed", ResetOnSpawn = false, IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = Layers.ScoreFeed,
	}, parent)
	self.root = Tape.frame("Feed", self.gui)
	self.root:SetAttribute("LayoutItem", "ScoreFeed")
	self.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout()
	end)
	self.textPreference = GuiService:GetPropertyChangedSignal("PreferredTextSize"):Connect(function()
		self:_layout()
	end)
	self:_layout()
	return self
end

function ScoreFeedView:setRung(rung: number)
	self.tier = Tape.tier(rung)
end

function ScoreFeedView:_reduced(): boolean
	if self.reducedMotionOverride ~= nil then
		return self.reducedMotionOverride
	end
	return GuiService.ReducedMotionEnabled
end

function ScoreFeedView:_layout()
	local screen = self.gui.AbsoluteSize
	local meter = Tape.layout(screen)
	local offset = self.offsets.ScoreFeed or Vector2.zero
	local textSize = math.round(C.TextSize * meter.textScale)
	local width = math.min(C.Width * meter.textScale, meter.width + 40 * meter.textScale, math.max(1, screen.X - 8))
	self.phone = meter.compact
	self.maxLines = if meter.compact then C.PhoneLines else C.Lines
	self.placement = "split"
	self.anchorX = math.clamp(meter.x + (meter.width - width) / 2, 0, math.max(0, screen.X - width)) + offset.X
	self.top = meter.y + offset.Y
	self.rankHeight = meter.height
	self.rankWidth = meter.width
	self.rankCenter = meter.x + meter.width / 2 + offset.X - self.anchorX
	if width ~= self.width or textSize ~= self.textSize then
		self.width = width
		self.textSize = textSize
		self.lineHeight = math.round(C.LineHeight * meter.textScale)
		for _, line in self.lines do
			self:_fit(line)
		end
	end
	self:_trim()
	self:_place(true)
end

function ScoreFeedView:_nameText(line): string
	if line.count > 1 then
		return fill(TEXT.Merged, { name = line.label, count = line.count })
	end
	return line.label
end

function ScoreFeedView:_pointsText(line, value: number, plain: boolean?): string
	if line.notice then
		return if line.dir == nil then "" elseif line.dir > 0 then TEXT.Left else TEXT.Right
	end
	local p = ScoreFeedView.format(value)
	if line.state == "void" then
		return fill(if plain then TEXT.LostPlain else TEXT.Lost, { points = p })
	end
	return fill(TEXT.Points, { points = p })
end

-- Reserve width for the target total. A changing last digit never moves the event name.
-- The readback is Enum.Font.Unknown for a custom weight or style; use the equivalent
-- condensed or monospaced family for measuring. Leave a little room for the italic edge.
local function textBounds(text, size, font, fallback, width)
	local metric = if font == Enum.Font.Unknown then fallback else font
	return TextService:GetTextSize(text, size, metric, Vector2.new(width or 10000, 10000))
end

function ScoreFeedView:_fit(line)
	local name = self:_nameText(line)
	local points = self:_pointsText(line, line.points, true)
	local held = line.state == "live" or line.bankPoints ~= nil
	line.name.FontFace = if held then Style.rankFont else Style.feedFont
	line.name.TextSize = self.textSize
	line.pts.TextSize = self.textSize
	line.name.Text = name
	local nameWidth = math.ceil(textBounds(name, self.textSize, line.name.Font, Enum.Font.RobotoCondensed).X) + 5
	local pointsWidth = math.ceil(textBounds(points, self.textSize, line.pts.Font, Enum.Font.RobotoMono).X) + 3
	local mark = if held then 9 else 0
	local gap = 6
	local width = self.width
	local single = mark + nameWidth + gap + pointsWidth <= width
	local rowH = self.lineHeight
	local nameRows = 1
	if not single and nameWidth > width - mark then
		local wrapped = textBounds(name, self.textSize, line.name.Font, Enum.Font.RobotoCondensed, math.max(1, width - mark - 5))
		nameRows = math.max(2, math.ceil(wrapped.Y / rowH))
	end
	line.rows = if single then 1 else nameRows + 1
	line.height = line.rows * rowH
	line.frame.Size = UDim2.fromOffset(width, line.height)
	local rowWidth = if single then math.max(mark + nameWidth + gap + pointsWidth, self.rankWidth - 8) else width
	local left = if held and single then math.floor((width - mark - nameWidth - gap - pointsWidth) / 2)
		else math.floor((width - rowWidth) / 2)
	local nameLeft = left + mark
	line.name.TextWrapped = not single
	line.name.Position = UDim2.fromOffset(nameLeft, 0)
	local pointsLeft = if single then (if held then nameLeft + nameWidth + gap else left + rowWidth - pointsWidth) else 0
	line.name.Size = UDim2.fromOffset(if single then pointsLeft - nameLeft - gap else width - nameLeft, nameRows * rowH)
	line.pts.Position = UDim2.fromOffset(pointsLeft, if single then 0 else nameRows * rowH)
	line.pts.Size = UDim2.fromOffset(if single then pointsWidth else width, rowH)
	line.marker.Position = UDim2.fromOffset(left, math.floor((rowH - 4) / 2))
	line.frame:SetAttribute("State", if line.notice then "Notice" else line.state)
end

function ScoreFeedView:_newLine(entry)
	self.serial += 1
	local frame = Create("Frame", {
		Name = `Line{self.serial}`, BackgroundTransparency = 1, Active = false,
	}, self.root)
	local name = Tape.text("Name", frame, Style.feedFont, Style.ink, self.textSize)
	local pts = Tape.text("Points", frame, Style.numberFont, Style.ink, self.textSize)
	pts.TextXAlignment = Enum.TextXAlignment.Right
	pts.RichText = true
	pts.AutoLocalize = entry.notice ~= nil
	-- The directional notice has its own small outline around LEFT/RIGHT. Its row
	-- stays transparent, like every other event.
	local stroke = Create("UIStroke", {
		Name = "Notice", ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = Style.shadow, Thickness = 2, Enabled = entry.notice ~= nil,
	}, pts)
	local marker = Create("Frame", {
		Name = "LiveMark", Size = UDim2.fromOffset(4, 4), BackgroundColor3 = self.tier.accent,
		BorderSizePixel = 0, Active = false, Visible = false,
	}, frame)
	Create("UICorner", { CornerRadius = UDim.new(1, 0) }, marker)
	local sustained = entry.state == "live" and not entry.notice
	local line = {
		kind = entry.kind, notice = entry.notice, dir = entry.dir,
		label = if entry.notice then (TEXT.Notices[entry.notice] or tostring(entry.notice)) else tostring(entry.label or entry.kind or "?"),
		points = entry.points or 0, shown = if sustained then 0 else (entry.points or 0),
		count = 1, state = if entry.notice then "banked" else (entry.state or "banked"),
		ids = { entry.id }, rung = entry.rung, sustained = sustained, touched = self.t,
		endedAt = if sustained then nil else self.t,
		appear = if self:_reduced() then 1 else 0, alpha = 0,
		frame = frame, name = name, pts = pts, marker = marker, stroke = stroke,
	}
	self:_fit(line)
	pts.Text = self:_pointsText(line, line.shown)
	return line
end

function ScoreFeedView:_finishedHold(line): number
	if line.notice then
		return C.NoticeHold
	end
	return if line.sustained then C.FinishedHold else C.OneOffHold
end

-- Past the most lines, the oldest finished lines fade out at once. Live lines stay.
function ScoreFeedView:_trim()
	local kept = 0
	for _, line in self.lines do
		if not line.fadeFrom then
			kept += 1
		end
	end
	for i = #self.lines, 1, -1 do
		if kept <= (self.maxLines or C.Lines) then
			break
		end
		local line = self.lines[i]
		if not line.fadeFrom and line.state ~= "live" and line.bankAt == nil then
			line.fadeFrom = self.t
			kept -= 1
		end
	end
end

-- A feed entry: a new event, or one already on screen growing or ending.
function ScoreFeedView:push(entry)
	if type(entry) ~= "table" then
		return
	end
	local id = entry.id
	local line = id ~= nil and self.byId[id] or nil
	if line and line.notice then
		return -- a notice is shown once, as it came
	end
	if line then
		local was = line.state
		-- Events are terminal once banked or void. Ignore repeat settlement, including
		-- updates for an id that has already been merged into a one-off.
		if was ~= "live" then
			return
		end
		-- its words may change: a jump's "BIG AIR", a bend line upgraded as it banks (T-299)
		if line.count == 1 and entry.label ~= nil then
			line.label = tostring(entry.label)
			line.kind = entry.kind or line.kind
		end
		line.points = entry.points or line.points
		line.rung = entry.rung or line.rung
		line.state = entry.state or line.state
		line.touched = self.t
		if line.state ~= "live" then
			line.endedAt = self.t
			if line.state == "banked" and not self.hold then
				line.bankPoints = line.points
				line.bankAt = self.t
				line.shown = line.points
				if self.onBankStart then self.onBankStart(line.bankPoints, line) end
				if self:_reduced() then self:_impact(line) end
			end
		end
		self:_fit(line)
		self:_trim()
		self:_place(false)
		return
	end

	-- A one-off of a kind already on screen as a one-off, recently: merge into its line.
	-- A notice never merges.
	if entry.state ~= "live" and not entry.notice then
		for _, other in self.lines do
			if
				not other.sustained
				and not other.notice
				and not other.fadeFrom
				and other.kind == entry.kind
				and other.state == entry.state
				and self.t - other.touched <= C.MergeWindow
			then
				other.count += 1
				other.points += entry.points or 0
				other.shown = other.points
				other.touched = self.t
				other.endedAt = self.t -- its clock restarts
				table.insert(other.ids, id)
				if id ~= nil then
					self.byId[id] = other
				end
				self:_fit(other)
				return
			end
		end
	end

	line = self:_newLine(entry)
	if id ~= nil then
		self.byId[id] = line
	end
	table.insert(self.lines, 1, line)
	self:_trim()
	self:_place(false)
end

-- Coordinates are relative to the top of the rank, so a second event arriving
-- never changes the destination of a flying bank. Keep the root around both
-- groups for Studio's whole-widget layout drag.
function ScoreFeedView:_place(snap: boolean)
	local above = C.RankGap
	local below = self.rankHeight + C.RankGap
	for _, line in self.lines do
		if line.state == "live" or line.bankAt then
			above += line.height
			line.targetY = -above
			above += C.Gap
			line.zone = "above"
		else
			line.targetY = below
			below += line.height + C.Gap
			line.zone = "below"
		end
		if snap or line.y == nil then line.y = line.targetY end
	end
	self.origin = above - C.Gap
	self.contentHeight = below + self.origin
	self.root.Position = UDim2.fromOffset(self.anchorX, self.top - self.origin)
	self.root.Size = UDim2.fromOffset(self.width, self.contentHeight)
end

function ScoreFeedView:_impact(line)
	local points = line.bankPoints
	if points == nil then return end
	line.bankPoints = nil
	if self.onAbsorb then self.onAbsorb(points, line) end
end

function ScoreFeedView:_destroyLine(line)
	if line.bankPoints ~= nil and self.onBankCancel then self.onBankCancel(line.bankPoints, line) end
	for _, id in line.ids do
		if self.byId[id] == line then self.byId[id] = nil end
	end
	line.frame:Destroy()
end

function ScoreFeedView:step(dt: number)
	dt = math.max(dt or 0, 0)
	self.t += dt
	local t = self.t
	local reduced = self:_reduced()
	local ease = if reduced then 1 else 1 - math.exp(-dt * 3 / C.SlideTime)
	local count = if reduced then 1 else 1 - math.exp(-dt * C.CountRate)

	local removed = false
	for i = #self.lines, 1, -1 do
		local line = self.lines[i]
		local age = if line.bankAt then t - line.bankAt else nil
		local finished = age ~= nil and (reduced or age >= C.BankTime)
		if finished then self:_impact(line) end
		local from = line.fadeFrom
		if not self.hold and line.endedAt and age == nil then
			local natural = line.endedAt + self:_finishedHold(line)
			from = if from then math.min(from, natural) else natural
		end
		local fade = if from then (if self.hold then 0 else 1 - math.clamp((t - from) / C.Fade, 0, 1)) else 1
		if finished or (fade <= 0 and age == nil) then
			self:_destroyLine(line)
			table.remove(self.lines, i)
			removed = true
			continue
		end
		line.appear = if reduced then 1 else math.min(1, line.appear + dt / C.SlideTime)
		line.fade = fade
		line.alpha = line.appear * fade
	end
	if removed then self:_place(false) end

	for _, line in self.lines do
		line.y += (line.targetY - line.y) * ease
		local x = (1 - line.appear) * 7
		local y = line.y
		local alpha = line.alpha
		if line.bankAt then
			local k = math.clamp((t - line.bankAt) / C.BankTime, 0, 1)
			local fall = math.clamp((k - 0.43) / 0.57, 0, 1) ^ 2
			local pull = -6 * math.sin(math.min(k / 0.43, 1) * math.pi / 2)
			x += (self.rankCenter - self.width / 2) * fall
			y += pull + (self.rankHeight / 2 - line.height / 2 - y - pull) * fall
			alpha *= 1 - 0.8 * fall
		end
		line.frame.Position = UDim2.fromOffset(math.round(x), math.round(self.origin + y))
		local live = line.state == "live"
		if live then
			line.shown += (line.points - line.shown) * count
			if math.abs(line.points - line.shown) < 1 then line.shown = line.points end
		else
			line.shown = line.points
		end
		local value = math.round(line.shown)
		if line.lastShown ~= value or line.lastState ~= line.state then
			line.lastShown = value
			line.lastState = line.state
			line.pts.Text = self:_pointsText(line, value)
		end
		local accent = self.tier.accent
		line.name.TextColor3 = if line.state == "void" then Style.lost elseif live or line.bankAt then Style.ink else Style.secondary
		line.pts.TextColor3 = if line.state == "void" then Style.lost elseif live or line.bankAt or line.notice then accent else Style.secondary
		line.name.TextTransparency = 1 - alpha
		line.pts.TextTransparency = 1 - alpha
		line.name.TextStrokeTransparency = 1 - 0.94 * alpha
		line.pts.TextStrokeTransparency = 1 - 0.94 * alpha
		if line.notice then line.stroke.Transparency = 1 - alpha end
		line.marker.Visible = live
		if live then
			line.marker.BackgroundColor3 = accent
			local pulse = if reduced then 1 else 0.8 + 0.2 * math.cos(t * math.pi * 3)
			line.marker.BackgroundTransparency = 1 - pulse * alpha
		end
	end
end

-- Every line away, at once.
function ScoreFeedView:clear()
	for _, line in self.lines do
		self:_destroyLine(line)
	end
	self.lines = {}
	self.byId = {}
	self.hold = false
	self:_place(true)
end

-- A still picture, for fixtures: the entries pushed in order, settled, and (with `hold`)
-- never aging, so they can be measured.
function ScoreFeedView:setData(data)
	data = data or {}
	self:clear()
	self.hold = data.hold == true
	for _, entry in data.entries or {} do
		self:push(entry)
	end
	for _, line in self.lines do
		line.appear = 1
		line.shown = line.points
	end
	self:step(0) -- drops the lines pushed out past the most
	self:_place(true)
	self:step(0)
end

function ScoreFeedView:show()
	self.gui.Enabled = true
end

function ScoreFeedView:hide()
	self.gui.Enabled = false
end

-- Reduced Motion forced on or off for testing; `nil` follows the player's setting.
function ScoreFeedView:setReducedMotion(on: boolean?)
	self.reducedMotionOverride = on
end

function ScoreFeedView:setLayoutOffset(name: string, offset: Vector2?)
	self.offsets[name] = offset
	self:_layout()
end

local function rect(g: GuiObject)
	return { position = g.AbsolutePosition, size = g.AbsoluteSize }
end

-- Its pieces' rects and states, for the UI checks (TESTING.md "Checking UI").
function ScoreFeedView:describe()
	local lines = {}
	for i, line in self.lines do
		lines[i] = {
			kind = line.kind,
			notice = line.notice,
			dir = line.dir,
			outline = line.stroke.Enabled,
			state = line.state,
			count = line.count,
			sustained = line.sustained,
			name = line.name.Text,
			points = line.pts.Text,
			total = line.points,
			shown = line.shown,
			rows = line.rows,
			textSize = self.textSize,
			alpha = line.alpha,
			fading = line.fadeFrom ~= nil or (line.fade or 1) < 1,
			rect = rect(line.frame),
			nameRect = rect(line.name),
			nameFits = line.name.TextFits,
			nameBounds = line.name.TextBounds,
			pointsRect = rect(line.pts),
			pointsFits = line.pts.TextFits,
			pointsBounds = line.pts.TextBounds,
			underline = false,
			liveMark = line.marker.Visible,
			zone = line.zone,
			banking = line.bankPoints ~= nil,
			backdrop = line.frame.BackgroundTransparency,
		}
	end
	local anyActive = false
	for _, d in self.gui:GetDescendants() do
		if d:IsA("GuiObject") and d.Active then
			anyActive = true
		end
	end
	return {
		enabled = self.gui.Enabled,
		displayOrder = self.gui.DisplayOrder,
		screen = self.gui.AbsoluteSize,
		placement = self.placement,
		top = self.top,
		maxHeight = self.maxHeight,
		phone = self.phone,
		maxLines = self.maxLines,
		width = self.width,
		root = rect(self.root),
		contentHeight = self.contentHeight,
		reducedMotion = self:_reduced(),
		hold = self.hold,
		lines = lines,
		anyActive = anyActive,
	}
end

function ScoreFeedView:destroy()
	self.textPreference:Disconnect()
	self:clear()
	self.gui:Destroy()
end

return ScoreFeedView
