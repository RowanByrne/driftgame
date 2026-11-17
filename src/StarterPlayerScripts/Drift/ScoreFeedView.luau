--!nonstrict
-- ScoreFeedView: the score feed, a killfeed of score events as they trigger and accumulate
-- (docs/game/features/score-events.md "UI", docs/workflow/UI.md). Programmer art, in the
-- settings style's colours (`UI/Theme`: smoked glass, off-white text, the orange accent).
--
-- A VIEW, and only that (UI.md "Each screen is a view"). It reads no remote and no engine:
-- `ScoreController` hands it each feed entry (`push`), and steps it once a frame (`step`);
-- `ScoreFeedView.fixtures` hands it samples for measuring.
--
--   push({ id, kind, label, points, state = "live" | "banked" | "void", rung })
--   setData({ entries = { entry, ... }, hold = true? })  -- a still picture, for fixtures
--   step(dt)  ;  clear()  ;  describe()
--
-- AN ENTRY'S `points` IS ITS TOTAL SO FAR, not a step's share, with the rung already in it
-- (the line never shows the rung). The same `id` again is the same event growing or ending.
--
-- NEWEST ON TOP. A new line slides in at the top of the stack and pushes the older ones down,
-- so the line the eye meets first is the latest.
--
-- WHAT A LINE DOES:
--   * A ONE-OFF (its first entry already `banked`): pops in, stays `OneOffHold`, fades. The
--     same kind again within `MergeWindow` merges into it: `NEAR MISS x3`, points added,
--     its clock restarted.
--   * A SUSTAINED or CONDITIONAL one (first entry `live`): its points count up in place and
--     an orange underline pulses while it holds. `banked`: the plate flashes white once and
--     a copy of the points glides up toward the score. `void`: red, `LOST`, points struck
--     through. Either stays `FinishedHold`, then fades. A live line is never pushed out.
--   * At most `Lines` lines (`PhoneLines` on a phone): past that the oldest finished line
--     fades out at once.
--   * Reduced Motion (`GuiService.ReducedMotionEnabled`): no slide, no flash, no glide, no
--     pulse; lines appear and fade.
--
-- WHERE IT SITS (`_layout`). Not under the score panel, the spec's first choice: measured
-- there (T-296) it covered the road ahead on phones on their side and at HD 720. So on every
-- screen wider than tall: the top right corner, as a killfeed, 16 px in, as wide as fits up to
-- 220 px beside the run button's column, and above the Settings button. A phone upright (the
-- road map has dropped below the centre column on the left): right of the map, under the
-- Settings button that shares that edge. The map's rule is read from `Config.RoadMap`, the
-- same numbers `Drift/RoadMapView` places itself by.
--
-- IT NEVER TAKES A TOUCH: the whole screen is the steering pad. Nothing here is `Active`, and
-- its `DisplayOrder` (13) is under the score panel's 14, over the drag pad's 5.
--
-- NOT `IgnoreGuiInset`, like `Drift/ScoreHudView`: it hangs off the score panel, so both are
-- measured from the same top.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local ScoreFeedView = {}
ScoreFeedView.__index = ScoreFeedView

-- Every number the feed is drawn with.
local C = {
	DisplayOrder = 13, -- under the score panel (14), over the drag pad (5)
	Width = 220, -- px, the score panel's width
	Top = 146, -- px below the inset, beside the map: the score panel's bottom (80 + 58) and a gap
	Margin = 16, -- px from the screen's top and right edges
	MapGap = 8, -- px kept clear between the map and the feed
	-- The Settings button on the right edge (`Settings/SettingsView`: 144 x 48, its top 176 px
	-- below the safe area's top): beside the map the feed starts under it, top right it stops
	-- above it (and above the Garage button, `Config.GarageMenu`).
	SettingsTop = 176, -- px below the safe area's top
	SettingsHeight = 48,
	-- The testing buttons in the top right corner, the readout's DBG and the tuner's TUNE
	-- (`Drift/DragControl`, `Drift/TunerUI`: 64 px wide, 16 px in): the feed keeps left of
	-- them where the screen is wide enough, so on desktop and tablet.
	TestButtons = 64 + 8,
	LineHeight = 30, -- px, one row
	TwoRowHeight = 50, -- px, a name too long to share its row with the points
	Gap = 4, -- px between lines
	Pad = 8, -- px inside the plate
	TextSize = 18, -- px, Gotham Bold, name and points
	MinTextSize = 16, -- px, UI.md's floor for text a player must read
	Lines = 5, -- most lines on a big screen
	PhoneLines = 3, -- and on a phone (short side under `Config.RoadMap.PhoneBelow`)

	SlideTime = 0.16, -- s, a new line sliding in, the others moving down
	SlideIn = 24, -- px a new line slides in from the right
	OneOffHold = 2.5, -- s a one-off line stays before fading
	FinishedHold = 2.0, -- s a banked or lost sustained line stays
	Fade = 0.4, -- s
	MergeWindow = 1.5, -- s: the same one-off kind within this merges into its line
	Flash = 0.3, -- s, the white flash when a sustained line banks
	Glide = 0.45, -- s, the banked points gliding up toward the score
	GlideRise = 30, -- px they rise
	CountRate = 10, -- 1/s: how fast live points catch up with the engine's total
	PulseHz = 2, -- the live underline's pulse
	UnderlineHeight = 2, -- px

	Plate = Theme.Color.Surface,
	PlateTransparency = 0.3, -- solid enough to read over moving gameplay (UI.md)
	Ink = Theme.Color.Text,
	Accent = Theme.Color.Accent,
	Void = Color3.fromRGB(235, 92, 92),
	FlashColor = Color3.fromRGB(255, 255, 255),
	StrokeTransparency = 0.4,
	CornerRadius = 6, -- px, as the score panel
}
ScoreFeedView.Config = C

-- Whole strings with placeholders, never glued in code (UI.md "Localization").
local TEXT = {
	Merged = "{name} x{count}",
	Points = "+{points}",
	Lost = "LOST <s>+{points}</s>",
	LostPlain = "LOST +{points}", -- the same, measured without its tags
}

local FONT = Enum.Font.GothamBold

local function fill(template: string, values): string
	return (template:gsub("{(%w+)}", function(k)
		return tostring(values[k])
	end))
end

-- 48210.7 -> "48,210". Points are shown whole.
function ScoreFeedView.format(n: number): string
	local s = tostring(math.floor(math.max(n or 0, 0) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

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

local function textWidth(s: string, size: number): number
	return TextService:GetTextSize(s, size, FONT, Vector2.new(10000, 100)).X
end

local function label(name: string, parent: Instance): TextLabel
	local l = new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = C.Ink,
		TextSize = C.TextSize,
		FontFace = Font.fromEnum(FONT),
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = C.StrokeTransparency,
		TextYAlignment = Enum.TextYAlignment.Center,
		Active = false,
		ZIndex = 2,
	}, parent)
	return l
end

function ScoreFeedView.new(parent: Instance)
	local self = setmetatable({}, ScoreFeedView)
	self.offsets = {}
	self.lines = {} -- newest first
	self.byId = {} -- entry id -> line (merged ids point at the line they merged into)
	self.t = 0 -- the view's own clock, advanced by `step`
	self.hold = false -- a still fixture: nothing ages
	self.reducedMotionOverride = nil
	self.serial = 0

	local gui = new("ScreenGui", {
		Name = "ScoreFeed",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = C.DisplayOrder,
		Enabled = true,
	}, parent)
	self.gui = gui

	local root = new("Frame", {
		Name = "Feed",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(C.Width, C.LineHeight),
		Active = false,
	}, gui)
	root:SetAttribute("LayoutItem", "ScoreFeed")
	self.root = root

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout()
	end)
	self:_layout()
	return self
end

function ScoreFeedView:_reduced(): boolean
	if self.reducedMotionOverride ~= nil then
		return self.reducedMotionOverride
	end
	return GuiService.ReducedMotionEnabled
end

-- Place the feed from the measured screen. Two placements, both in this one function
-- (UI.md "Keep each screen's per-layout placement together"):
--   topRight   desktop, tablet, a phone on its side: the top right corner, beside the run
--              button's column, above the Settings button
--   besideMap  a phone upright: right of the road map, under the Settings button
function ScoreFeedView:_layout()
	local RM = Config.RoadMap
	local G = Config.GarageMenu
	local screen = self.gui.AbsoluteSize
	local phone = screen.X > 0 and math.min(screen.X, screen.Y) < RM.PhoneBelow
	local mapSize = if phone then RM.PhoneSize else RM.Size
	local roomBeside = (screen.X - RM.CentreColumn) * 0.5 - RM.CentreGap
	local besideMap = screen.X > 0 and RM.Margin + mapSize > roomBeside
	local o = self.offsets.ScoreFeed or Vector2.zero

	-- The right edge's buttons, in this screen's px: Settings (`Settings/SettingsView`, its
	-- top 176 px below the safe area's top) and Garage (`Config.GarageMenu`, bottom right).
	local safe = GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
	local full = GuiService:GetInsetArea(Enum.ScreenInsets.None)
	local myTop = self.gui.AbsolutePosition.Y
	local settingsTop = safe.Min.Y + C.SettingsTop - myTop
	local garageTop = full.Max.Y - (G.HudButtonAbove + G.HudButtonSize.Y) - myTop

	local placement, width, top, maxBottom
	if besideMap then
		placement = "besideMap"
		local left = RM.Margin + mapSize + C.MapGap
		width = math.min(C.Width, screen.X - C.Margin - left)
		top = math.max(C.Top, settingsTop + C.SettingsHeight + C.MapGap)
		self.root.AnchorPoint = Vector2.new(1, 0)
		self.root.Position = UDim2.new(1, -C.Margin + o.X, 0, top + o.Y)
	else
		-- Measured (T-296): under the score panel, the spec's first choice, the feed covered
		-- the road ahead: on a phone on its side the road fills the centre column from the car
		-- up to the horizon, and at HD 720 the horizon is 203 px down, above the feed's lower
		-- lines. The top right is sky and scenery on every screen measured, and it is where
		-- a killfeed sits. It stops above the Settings and Garage buttons.
		placement = "topRight"
		-- left of the testing buttons where there is room for it; on a phone there is not
		local right = C.Margin + (if phone then 0 else C.TestButtons)
		local left = (screen.X + RM.CentreColumn) * 0.5 + C.MapGap
		width = math.min(C.Width, screen.X - right - left)
		top = C.Margin
		maxBottom = math.min(settingsTop, garageTop) - C.MapGap
		self.root.AnchorPoint = Vector2.new(1, 0)
		self.root.Position = UDim2.new(1, -right + o.X, 0, top + o.Y)
	end
	local changed = self.width ~= width
	self.width = width
	self.phone = phone
	self.placement = placement
	self.top = top
	self.maxHeight = if maxBottom then math.max(maxBottom - top, C.LineHeight) else nil
	self.maxLines = if phone then C.PhoneLines else C.Lines
	if changed then
		for _, line in self.lines do
			self:_fit(line)
		end
	end
	self:_trim()
	self:_place(true)
end

-- ---------------------------------------------------------------------------- lines

function ScoreFeedView:_nameText(line): string
	if line.count > 1 then
		return fill(TEXT.Merged, { name = line.label, count = line.count })
	end
	return line.label
end

function ScoreFeedView:_pointsText(line, value: number, plain: boolean?): string
	local p = ScoreFeedView.format(value)
	if line.state == "void" then
		return fill(if plain then TEXT.LostPlain else TEXT.Lost, { points = p })
	end
	return fill(TEXT.Points, { points = p })
end

-- Size the line to its text: one row at 18 px, else one row at 16, else two rows (the name
-- above, the points under it on the right). Reflow, never cut off (UI.md).
function ScoreFeedView:_fit(line)
	local nameText = self:_nameText(line)
	-- measured at the engine's total, which the live count never passes, so the row never
	-- reflows while it counts
	local ptsText = self:_pointsText(line, line.points, true)
	local avail = self.width - C.Pad * 2
	local size, rows = C.TextSize, 1
	local function fits(s)
		return textWidth(nameText, s) + textWidth(ptsText, s) + C.Pad <= avail
	end
	if not fits(C.TextSize) then
		if fits(C.MinTextSize) then
			size = C.MinTextSize
		else
			rows = 2
			if textWidth(nameText, C.TextSize) > avail or textWidth(ptsText, C.TextSize) > avail then
				size = C.MinTextSize
			end
		end
	end
	line.rows, line.size = rows, size
	line.height = if rows == 2 then C.TwoRowHeight else C.LineHeight
	local f = line.frame
	f.Size = UDim2.fromOffset(self.width, line.height)
	line.name.TextSize = size
	line.pts.TextSize = size
	line.name.Text = nameText
	local rowH = if rows == 2 then (line.height - 4) / 2 else line.height
	if rows == 2 then
		line.name.Position = UDim2.fromOffset(C.Pad, 2)
		line.name.Size = UDim2.fromOffset(avail, rowH)
		line.pts.Position = UDim2.fromOffset(C.Pad, 2 + rowH)
		line.pts.Size = UDim2.fromOffset(avail, rowH)
	else
		local ptsW = textWidth(ptsText, size) + 2
		line.name.Position = UDim2.fromOffset(C.Pad, 0)
		line.name.Size = UDim2.fromOffset(avail - ptsW - C.Pad, rowH)
		line.pts.Position = UDim2.fromOffset(C.Pad + avail - ptsW, 0)
		line.pts.Size = UDim2.fromOffset(ptsW, rowH)
	end
	line.underline.Size = UDim2.new(1, -C.Pad * 2, 0, C.UnderlineHeight)
	line.underline.Position = UDim2.new(0, C.Pad, 1, -C.UnderlineHeight - 2)
	line.ghost.Size = line.pts.Size
end

function ScoreFeedView:_newLine(entry)
	self.serial += 1
	local frame = new("Frame", {
		Name = `Line{self.serial}`,
		BackgroundColor3 = C.Plate,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
	}, self.root)
	new("UICorner", { CornerRadius = UDim.new(0, C.CornerRadius) }, frame)
	local name = label("Name", frame)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.None
	local pts = label("Points", frame)
	pts.TextXAlignment = Enum.TextXAlignment.Right
	pts.TextColor3 = C.Accent
	pts.RichText = true
	pts.AutoLocalize = false -- a number that changes every frame
	local underline = new("Frame", {
		Name = "Underline",
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 2,
		Visible = false,
	}, frame)
	local ghost = label("Glide", frame)
	ghost.TextXAlignment = Enum.TextXAlignment.Right
	ghost.TextColor3 = C.Accent
	ghost.AutoLocalize = false
	ghost.ZIndex = 3
	ghost.Visible = false

	local sustained = entry.state == "live"
	local line = {
		serial = self.serial,
		kind = entry.kind,
		label = tostring(entry.label or entry.kind or "?"),
		count = 1,
		points = entry.points or 0,
		shown = if sustained then 0 else (entry.points or 0),
		state = entry.state or "banked",
		rung = entry.rung,
		ids = { entry.id },
		sustained = sustained,
		born = self.t,
		touched = self.t,
		endedAt = if sustained then nil else self.t,
		flashAt = nil,
		fadeFrom = nil, -- set when pushed out: fades from then
		x = if self:_reduced() then 0 else C.SlideIn,
		y = 0,
		appear = if self:_reduced() then 1 else 0,
		alpha = 0,
		frame = frame,
		name = name,
		pts = pts,
		underline = underline,
		ghost = ghost,
	}
	self:_fit(line)
	pts.Text = self:_pointsText(line, line.shown)
	return line
end

function ScoreFeedView:_finishedHold(line): number
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
		if not line.fadeFrom and line.state ~= "live" then
			line.fadeFrom = self.t
			kept -= 1
		end
	end
	-- and past the room it has (top right on a phone: above the Settings and Garage buttons)
	if self.maxHeight then
		local function height()
			local h = 0
			for _, line in self.lines do
				if not line.fadeFrom then
					h += line.height + C.Gap
				end
			end
			return h - C.Gap
		end
		for i = #self.lines, 1, -1 do
			if height() <= self.maxHeight then
				break
			end
			local line = self.lines[i]
			if not line.fadeFrom and line.state ~= "live" then
				line.fadeFrom = self.t
			end
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
	if line then
		local was = line.state
		line.points = entry.points or line.points
		line.rung = entry.rung or line.rung
		line.state = entry.state or line.state
		line.touched = self.t
		if was == "live" and line.state ~= "live" then
			line.endedAt = self.t
			if line.state == "banked" then
				line.shown = line.points
				line.flashAt = self.t
			end
		end
		self:_fit(line)
		self:_trim()
		return
	end

	-- A one-off of a kind already on screen as a one-off, recently: merge into its line.
	if entry.state ~= "live" then
		for _, other in self.lines do
			if
				not other.sustained
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

-- Each line's place in the stack, newest on top. `snap` puts them there at once.
function ScoreFeedView:_place(snap: boolean)
	local y = 0
	for _, line in self.lines do
		line.targetY = y
		if snap or line.appear == 0 then
			line.y = y
		end
		y += line.height + C.Gap
	end
	self.contentHeight = math.max(y - C.Gap, 0)
	self.root.Size = UDim2.fromOffset(self.width or C.Width, math.max(self.contentHeight, C.LineHeight))
end

function ScoreFeedView:_destroyLine(line)
	for _, id in line.ids do
		if id ~= nil and self.byId[id] == line then
			self.byId[id] = nil
		end
	end
	line.frame:Destroy()
end

-- Advance the feed by `dt` seconds: counting, sliding, flashing, fading.
function ScoreFeedView:step(dt: number)
	dt = math.max(dt or 0, 0)
	self.t += dt
	local t = self.t
	local reduced = self:_reduced()
	local ease = if reduced then 1 else 1 - math.exp(-dt * 3 / C.SlideTime)
	local count = 1 - math.exp(-dt * C.CountRate)

	local removed = false
	for i = #self.lines, 1, -1 do
		local line = self.lines[i]
		-- how visible: in, then out
		if reduced then
			line.appear = 1
			line.x = 0
		else
			line.appear = math.min(1, line.appear + dt / C.SlideTime)
			line.x += (0 - line.x) * ease
		end
		local fade = 1
		-- pushed out fades even in a still fixture; only the natural aging is held
		local from = line.fadeFrom
		if not self.hold and line.endedAt and line.state ~= "live" then
			local natural = line.endedAt + self:_finishedHold(line)
			from = if from then math.min(from, natural) else natural
		end
		if from then
			fade = if self.hold then 0 else 1 - math.clamp((t - from) / C.Fade, 0, 1)
		end
		if fade <= 0 then
			self:_destroyLine(line)
			table.remove(self.lines, i)
			removed = true
			continue
		end
		line.alpha = line.appear * fade
		line.fade = fade
	end
	if removed then
		self:_place(false)
	end

	for _, line in self.lines do
		line.y += ((line.targetY or line.y) - line.y) * ease
		local a = line.alpha
		local f = line.frame
		f.Position = UDim2.fromOffset(line.x, line.y)

		-- the plate: smoked glass, flashing white once on a bank
		local plate = C.Plate
		if line.flashAt and not reduced then
			local k = math.clamp((t - line.flashAt) / C.Flash, 0, 1)
			plate = C.FlashColor:Lerp(C.Plate, k)
		end
		f.BackgroundColor3 = plate
		f.BackgroundTransparency = 1 - (1 - C.PlateTransparency) * a

		-- the points: counting up while live
		if line.state == "live" then
			line.shown += (line.points - line.shown) * count
			if math.abs(line.points - line.shown) < 1 then
				line.shown = line.points
			end
		else
			line.shown = line.points
		end
		local void = line.state == "void"
		line.pts.Text = self:_pointsText(line, line.shown)
		line.pts.TextColor3 = if void then C.Void else C.Accent
		line.name.TextColor3 = if void then C.Void else C.Ink
		for _, l in { line.name, line.pts } do
			l.TextTransparency = 1 - a
			l.TextStrokeTransparency = 1 - (1 - C.StrokeTransparency) * a
		end

		-- the underline: pulsing while it holds
		local live = line.state == "live"
		line.underline.Visible = live
		if live then
			local pulse = if reduced then 1 else 0.5 + 0.5 * math.cos((t - line.born) * math.pi * 2 * C.PulseHz)
			line.underline.BackgroundTransparency = 1 - a * (0.35 + 0.65 * pulse)
		end

		-- the banked points gliding up toward the score
		local g = line.ghost
		if line.flashAt and line.state == "banked" and not reduced and t - line.flashAt < C.Glide then
			local k = (t - line.flashAt) / C.Glide
			g.Visible = true
			g.TextSize = line.pts.TextSize
			g.Text = ScoreFeedView.format(line.points)
			g.Text = fill(TEXT.Points, { points = g.Text })
			local p = line.pts.Position
			g.Position = UDim2.fromOffset(p.X.Offset, p.Y.Offset - C.GlideRise * k)
			g.TextTransparency = k
			g.TextStrokeTransparency = C.StrokeTransparency + (1 - C.StrokeTransparency) * k
		else
			g.Visible = false
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
		line.x = 0
		line.flashAt = nil
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
			state = line.state,
			count = line.count,
			sustained = line.sustained,
			name = line.name.Text,
			points = line.pts.Text,
			total = line.points,
			shown = line.shown,
			rows = line.rows,
			textSize = line.size,
			alpha = line.alpha,
			fading = line.fadeFrom ~= nil or (line.fade or 1) < 1,
			rect = rect(line.frame),
			nameRect = rect(line.name),
			nameFits = line.name.TextFits,
			nameBounds = line.name.TextBounds,
			pointsRect = rect(line.pts),
			pointsFits = line.pts.TextFits,
			pointsBounds = line.pts.TextBounds,
			underline = line.underline.Visible,
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
	self.gui:Destroy()
end

return ScoreFeedView
