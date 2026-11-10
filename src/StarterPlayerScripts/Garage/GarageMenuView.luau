--!nonstrict
-- GarageMenuView: the garage's menus, in programmer art (docs/game/features/car-customization.md
-- "UI", docs/workflow/UI.md "Programmer art"; T-103).
--
-- A VIEW: it builds the screen and draws it from a plain table (`setData`), and its buttons
-- only fire `ActionRequested`. It never touches a remote, a service or the car; the
-- controller (`Controllers/GarageController`) feeds it and acts on what it fires. Sample
-- data for every state is in `GarageMenuView.fixtures`.
--
-- WHAT IT DRAWS (the spec's "UI"): a row of category tabs across the top; the part list on
-- the left, each row a part's name, a FITTED mark, and for a performance part its
-- before/after bars; Paint has colour grids and finish and wrap pickers in place of the list;
-- the Back and Fit buttons under the list, and Drive out on its own. Plain frames and text,
-- to be restyled in the UI phase.
--
-- LAYOUTS (UI.md "Layouts per device"), chosen from the measured safe area, live on resize:
--   desktop   tabs across the top, the list down the left with Back and Fit under it,
--             Drive out bottom right
--   compact   a phone in landscape (height <= `CompactHeight`): the list takes the whole
--             height, and Back, Fit and Drive out stack in the bottom-right corner
--   portrait  tabs on top, the car in the top half, the list and a row of the three
--             buttons in the bottom half
-- The steering pad and Roblox's touch controls are both off while the menus are open
-- (`CarInputController:SetDriving(false)`, the avatar seated), so nothing here sits over a
-- live touch control.
--
-- ACTIONS fired: ("tab", categoryId), ("select", partId), ("paint", field, optionId),
-- ("fit"), ("back"), ("driveOut").
--
-- SNAPSHOT (see the fixtures):
--   { category, title, kind = "parts" | "paint", tabs = { { id, label } },
--     rows = { { id, name, fitted, selected, bars = { { label, before, after, text, up } } } },
--     paint = { { field, label, grid, options = { { id, name, colour?, fitted, selected } } } },
--     status = { text, tone = "info" | "error" | "pending" | "ok" },
--     canFit, canBack, pending }

local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)

local GarageMenuView = {}
GarageMenuView.__index = GarageMenuView

local FONT = Font.fromEnum(Enum.Font.Gotham)
local FONT_BOLD = Font.fromEnum(Enum.Font.GothamBold)

-- Plain colours, contrast checked against the panel (UI.md "Text and contrast").
local C = {
	panel = Color3.fromRGB(22, 22, 26),
	row = Color3.fromRGB(44, 44, 50),
	rowSelected = Color3.fromRGB(70, 70, 80),
	text = Color3.fromRGB(240, 240, 240),
	textDim = Color3.fromRGB(190, 190, 196),
	textDark = Color3.fromRGB(20, 20, 24),
	tab = Color3.fromRGB(50, 50, 56),
	tabSelected = Color3.fromRGB(240, 240, 240),
	fit = Color3.fromRGB(30, 115, 55),
	back = Color3.fromRGB(70, 70, 78),
	drive = Color3.fromRGB(30, 80, 150),
	disabled = Color3.fromRGB(60, 60, 64),
	disabledText = Color3.fromRGB(160, 160, 166),
	tag = Color3.fromRGB(240, 240, 240),
	barTrack = Color3.fromRGB(70, 70, 76),
	barBefore = Color3.fromRGB(170, 170, 176),
	barUp = Color3.fromRGB(90, 210, 120),
	barDown = Color3.fromRGB(240, 110, 100),
	error = Color3.fromRGB(255, 130, 120),
	ok = Color3.fromRGB(130, 230, 150),
	selectStroke = Color3.fromRGB(255, 255, 255),
}

local function cfg()
	return Config.GarageMenu
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

local function corner(parent: Instance, px: number?)
	new("UICorner", { CornerRadius = UDim.new(0, px or 6) }, parent)
end

local function label(props, parent: Instance)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextColor3 = C.text,
		TextSize = cfg().TextSize,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Active = false,
	}, parent)
	for k, v in props do
		l[k] = v
	end
	return l
end

local function button(name: string, text: string, colour: Color3, parent: Instance): TextButton
	local b = new("TextButton", {
		Name = name,
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Active = true,
		Selectable = true,
		Text = text,
		TextColor3 = C.text,
		TextSize = cfg().TextSize,
		FontFace = FONT_BOLD,
		TextWrapped = true,
	}, parent)
	corner(b)
	return b
end

-- ---------------------------------------------------------------------- building

function GarageMenuView.new(parent: Instance)
	local self = setmetatable({}, GarageMenuView)
	self.ActionRequested = Signal.new()
	self.connections = {}
	self.offsets = {}
	self.data = nil
	self.layout = "desktop"
	self.rowButtons = {} -- id -> button, the current list's
	self.tabButtons = {} -- id -> button

	local t = cfg()
	local gui = new("ScreenGui", {
		Name = "GarageMenu",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = t.MenuDisplayOrder,
		-- Out of Roblox's top bar and any notch: the tabs are at the top.
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Enabled = false,
	})
	self.gui = gui

	-- The whole usable area, so its AbsoluteSize is what the layout is measured from.
	local root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = false }, gui)
	self.root = root

	-- Tabs, scrolling sideways when seven do not fit (a phone).
	local tabs = new("ScrollingFrame", {
		Name = "Tabs",
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Selectable = false,
	}, root)
	tabs:SetAttribute("LayoutItem", "Tabs")
	corner(tabs)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, tabs)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, tabs)
	self.tabs = tabs

	-- The list panel: a header (the category and the status line), the scrolling list, and
	-- the Back and Fit buttons under it.
	local panel = new("Frame", {
		Name = "ListPanel",
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Active = true, -- a thumb on the panel's gaps is not a thumb on the world behind it
	}, root)
	panel:SetAttribute("LayoutItem", "ListPanel")
	corner(panel, 8)
	self.panel = panel

	self.title = label({
		Name = "Title",
		FontFace = FONT_BOLD,
		TextSize = 20,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 24),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, panel)
	self.status = label({
		Name = "Status",
		TextSize = t.SmallTextSize,
		TextColor3 = C.textDim,
		Position = UDim2.fromOffset(12, 34),
		Size = UDim2.new(1, -24, 0, 40),
		TextYAlignment = Enum.TextYAlignment.Top,
	}, panel)

	local list = new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Selectable = false,
	}, panel)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}, list)
	self.list = list

	self.backButton = button("Back", "Back", C.back, root)
	self.fitButton = button("Fit", "Fit", C.fit, root)
	self.driveButton = button("DriveOut", "Drive out", C.drive, root)
	self.backButton:SetAttribute("LayoutItem", "Back")
	self.fitButton:SetAttribute("LayoutItem", "Fit")
	self.driveButton:SetAttribute("LayoutItem", "DriveOut")
	table.insert(self.connections, self.backButton.Activated:Connect(function()
		if self.data and self.data.canBack then
			self.ActionRequested:Fire("back")
		end
	end))
	table.insert(self.connections, self.fitButton.Activated:Connect(function()
		if self.data and self.data.canFit and not self.data.pending then
			self.ActionRequested:Fire("fit")
		end
	end))
	table.insert(self.connections, self.driveButton.Activated:Connect(function()
		self.ActionRequested:Fire("driveOut")
	end))

	table.insert(self.connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout()
	end))

	gui.Parent = parent
	self:_layout()
	return self
end

-- ---------------------------------------------------------------------- layout

-- Which layout the measured safe area calls for.
function GarageMenuView.layoutFor(size: Vector2): string
	if size.X < size.Y then
		return "portrait"
	end
	if size.Y <= cfg().CompactHeight then
		return "compact"
	end
	return "desktop"
end

local function place(inst: GuiObject, x: number, y: number, w: number, h: number, offset: Vector2?)
	local o = offset or Vector2.zero
	inst.Position = UDim2.fromOffset(math.floor(x + o.X), math.floor(y + o.Y))
	inst.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
end

-- Every piece's place, for the layout the screen is in. Kept together on purpose, so the
-- three layouts cannot drift apart (UI.md "Same screen, different placement").
function GarageMenuView:_layout()
	local t = cfg()
	local size = self.root.AbsoluteSize
	local W, H = size.X, size.Y
	if W < 2 or H < 2 then
		return
	end
	local m, gap = t.Margin, t.Gap
	local layout = GarageMenuView.layoutFor(size)
	self.layout = layout
	local off = self.offsets

	place(self.tabs, m, m, W - 2 * m, t.TabHeight, off.Tabs)
	local top = m + t.TabHeight + gap
	local bh = t.ButtonHeight
	local headerH = 76

	if layout == "portrait" then
		-- The car in the top half; the list and one row of buttons in the bottom half.
		local listTop = math.max(top, math.floor(H * (1 - t.PortraitListShare)))
		local rowY = H - m - bh
		place(self.panel, m, listTop, W - 2 * m, rowY - gap - listTop, off.ListPanel)
		local each = (W - 2 * m - 2 * gap) / 3
		place(self.backButton, m, rowY, each, bh, off.Back)
		place(self.fitButton, m + each + gap, rowY, each, bh, off.Fit)
		place(self.driveButton, m + 2 * (each + gap), rowY, each, bh, off.DriveOut)
	elseif layout == "compact" then
		-- A phone on its side: every pixel of height is the list's. The three buttons stack
		-- in the bottom-right corner, Drive out lowest, and the car shows between them.
		local listW = math.min(t.ListWidthCompact, math.floor(W * 0.45))
		place(self.panel, m, top, listW, H - m - top, off.ListPanel)
		local colW = t.DriveOutWidth
		local x = W - m - colW
		place(self.driveButton, x, H - m - bh, colW, bh, off.DriveOut)
		place(self.fitButton, x, H - m - 2 * bh - gap, colW, bh, off.Fit)
		place(self.backButton, x, H - m - 3 * bh - 2 * gap, colW, bh, off.Back)
	else
		local listW = math.min(t.ListWidthDesktop, math.floor(W * 0.45))
		local rowY = H - m - bh
		place(self.panel, m, top, listW, rowY - gap - top, off.ListPanel)
		-- Back and Fit under the list, Fit the wider: it is the one that matters.
		local backW = math.min(t.BackWidth, math.floor((listW - gap) * 0.45))
		place(self.backButton, m, rowY, backW, bh, off.Back)
		place(self.fitButton, m + backW + gap, rowY, listW - backW - gap, bh, off.Fit)
		place(self.driveButton, W - m - t.DriveOutWidth, rowY, t.DriveOutWidth, bh, off.DriveOut)
	end

	if self.data then
		task.defer(function()
			self:_scrollToTab(self.data and self.data.category)
		end)
	end
	self.list.Position = UDim2.fromOffset(0, headerH)
	self.list.Size = UDim2.new(1, 0, 1, -headerH - 4)
	self.gui:SetAttribute("Layout", layout)
end

-- ---------------------------------------------------------------------- drawing

function GarageMenuView:_clearList()
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self.rowButtons)
end

local function tag(parent: Instance, text: string): TextLabel
	local t = cfg()
	local l = label({
		Name = "FittedTag",
		Text = text,
		FontFace = FONT_BOLD,
		TextSize = t.SmallTextSize,
		TextColor3 = C.textDark,
		BackgroundTransparency = 0,
		BackgroundColor3 = C.tag,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(72, 22),
	}, parent)
	corner(l, 4)
	return l
end

local function selectedLook(b: GuiObject, selected: boolean)
	local stroke = b:FindFirstChild("SelectedStroke")
	if selected and not stroke then
		stroke = new("UIStroke", {
			Name = "SelectedStroke",
			Color = C.selectStroke,
			Thickness = 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, b)
	elseif not selected and stroke then
		stroke:Destroy()
	end
end

function GarageMenuView:_drawRow(row, order: number)
	local t = cfg()
	local bars = row.bars or {}
	local h = t.RowHeight + #bars * t.BarRowHeight
	local b = new("TextButton", {
		Name = "Row_" .. row.id,
		LayoutOrder = order,
		BackgroundColor3 = if row.selected then C.rowSelected else C.row,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Active = true,
		Selectable = true,
		Text = "",
		Size = UDim2.new(1, 0, 0, h),
	}, self.list)
	corner(b)
	b:SetAttribute("PartId", row.id)
	b:SetAttribute("State", if row.selected then "Selected" else "Normal")
	b:SetAttribute("Fitted", row.fitted == true)
	selectedLook(b, row.selected == true)
	label({
		Name = "Name",
		Text = row.name,
		FontFace = if row.selected then FONT_BOLD else FONT,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -(12 + 84), 0, t.RowHeight),
		TextYAlignment = Enum.TextYAlignment.Center,
	}, b)
	if row.fitted then
		local tg = tag(b, "FITTED")
		tg.Position = UDim2.new(1, -8, 0, math.floor((t.RowHeight - 22) / 2))
	end
	for i, bar in bars do
		local y = t.RowHeight + (i - 1) * t.BarRowHeight - 6
		label({
			Name = "BarLabel" .. i,
			Text = bar.label,
			TextSize = t.SmallTextSize,
			TextColor3 = C.textDim,
			TextWrapped = false,
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.fromOffset(92, t.BarRowHeight),
		}, b)
		local track = new("Frame", {
			Name = "Bar" .. i,
			BackgroundColor3 = C.barTrack,
			BorderSizePixel = 0,
			Active = false,
			Position = UDim2.new(0, 108, 0, y + 5),
			Size = UDim2.new(1, -(108 + 70), 0, t.BarRowHeight - 10),
		}, b)
		new("Frame", {
			Name = "Before",
			BackgroundColor3 = C.barBefore,
			BorderSizePixel = 0,
			Active = false,
			Size = UDim2.fromScale(math.clamp(bar.before, 0, 1), 0.5),
		}, track)
		new("Frame", {
			Name = "After",
			BackgroundColor3 = if bar.up then C.barUp else C.barDown,
			BorderSizePixel = 0,
			Active = false,
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(math.clamp(bar.after, 0, 1), 0.5),
		}, track)
		label({
			Name = "BarText" .. i,
			Text = bar.text,
			FontFace = FONT_BOLD,
			TextSize = t.SmallTextSize,
			TextColor3 = if bar.up then C.ok else C.error,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, y),
			Size = UDim2.fromOffset(60, t.BarRowHeight),
		}, b)
	end
	-- Not kept in `connections`: the row is rebuilt on every redraw, and destroying it
	-- disconnects this.
	b.Activated:Connect(function()
		self.ActionRequested:Fire("select", row.id)
	end)
	self.rowButtons[row.id] = b
	return b
end

function GarageMenuView:_drawPaint(sections)
	local t = cfg()
	for i, section in sections do
		label({
			Name = "Head_" .. section.field,
			LayoutOrder = i * 2 - 1,
			Text = section.label,
			FontFace = FONT_BOLD,
			TextSize = t.SmallTextSize,
			TextColor3 = C.textDim,
			Size = UDim2.new(1, 0, 0, 22),
		}, self.list)
		local holder = new("Frame", {
			Name = "Options_" .. section.field,
			LayoutOrder = i * 2,
			BackgroundTransparency = 1,
			Active = false,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, self.list)
		local cell = if section.grid then UDim2.fromOffset(t.SwatchSize, t.SwatchSize) else UDim2.fromOffset(150, 48)
		new("UIGridLayout", {
			CellSize = cell,
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, holder)
		for j, option in section.options do
			local swatch = section.grid and option.colour ~= nil
			local b = new("TextButton", {
				Name = section.field .. "_" .. option.id,
				LayoutOrder = j,
				BackgroundColor3 = if swatch then option.colour elseif option.selected then C.rowSelected else C.row,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Active = true,
				Selectable = true,
				-- A colour swatch carries no text: its name is on the status line when picked.
				Text = if swatch then "" else option.name,
				TextColor3 = C.text,
				TextSize = t.SmallTextSize,
				FontFace = if option.selected then FONT_BOLD else FONT,
				TextWrapped = true,
			}, holder)
			corner(b)
			b:SetAttribute("PaintField", section.field)
			b:SetAttribute("OptionId", option.id)
			b:SetAttribute("State", if option.selected then "Selected" else "Normal")
			b:SetAttribute("Fitted", option.fitted == true)
			selectedLook(b, option.selected == true)
			if option.fitted then
				-- On a swatch, a small mark in its corner; on a word, a bar under it.
				local mark = label({
					Name = "FittedTag",
					Text = if swatch then "FIT" else "",
					FontFace = FONT_BOLD,
					TextSize = 14,
					TextColor3 = C.textDark,
					BackgroundTransparency = 0,
					BackgroundColor3 = C.tag,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextWrapped = false,
				}, b)
				mark:SetAttribute("TextAux", true)
				if swatch then
					mark.AnchorPoint = Vector2.new(1, 1)
					mark.Position = UDim2.new(1, -2, 1, -2)
					mark.Size = UDim2.fromOffset(30, 16)
				else
					mark.AnchorPoint = Vector2.new(0.5, 1)
					mark.Position = UDim2.new(0.5, 0, 1, -3)
					mark.Size = UDim2.new(0.6, 0, 0, 4)
				end
			end
			b.Activated:Connect(function()
				self.ActionRequested:Fire("paint", section.field, option.id)
			end)
			self.rowButtons[section.field .. ":" .. option.id] = b
		end
	end
end

function GarageMenuView:_drawTabs(tabs, current: string)
	local t = cfg()
	local same = self._tabIds ~= nil and #self._tabIds == #tabs
	if same then
		for i, tabData in tabs do
			if self._tabIds[i] ~= tabData.id then
				same = false
			end
		end
	end
	if not same then
		for _, b in self.tabButtons do
			b:Destroy()
		end
		table.clear(self.tabButtons)
		self._tabIds = {}
		for i, tabData in tabs do
			local b = button("Tab_" .. tabData.id, tabData.label, C.tab, self.tabs)
			b.LayoutOrder = i
			b.TextWrapped = false
			b:SetAttribute("TabId", tabData.id)
			-- Wide enough for its own text, never shrunk to fit (UI.md "Never shrink text").
			local bounds = TextService:GetTextSize(tabData.label, t.TextSize, Enum.Font.GothamBold, Vector2.new(1000, 100))
			local width = math.max(t.TabMinWidth, math.ceil(bounds.X) + t.TabPadding)
			b.Size = UDim2.fromOffset(width, t.TabHeight - 8)
			table.insert(self.connections, b.Activated:Connect(function()
				self.ActionRequested:Fire("tab", tabData.id)
			end))
			self.tabButtons[tabData.id] = b
			self._tabIds[i] = tabData.id
		end
	end
	for id, b in self.tabButtons do
		local on = id == current
		b.BackgroundColor3 = if on then C.tabSelected else C.tab
		b.TextColor3 = if on then C.textDark else C.text
		b:SetAttribute("State", if on then "Selected" else "Normal")
		selectedLook(b, false)
	end
	self:_scrollToTab(current)
end

-- On a phone the seven tabs scroll sideways: keep the open one in view.
function GarageMenuView:_scrollToTab(id: string?)
	local b = id and self.tabButtons[id]
	if not b then
		return
	end
	local view = self.tabs.AbsoluteSize.X
	local left = b.AbsolutePosition.X - self.tabs.AbsolutePosition.X + self.tabs.CanvasPosition.X
	local right = left + b.AbsoluteSize.X
	local at = self.tabs.CanvasPosition.X
	if left < at then
		at = left - 4
	elseif right > at + view then
		at = right - view + 4
	end
	self.tabs.CanvasPosition = Vector2.new(math.max(at, 0), 0)
end

local function setEnabled(b: TextButton, on: boolean, colour: Color3, pending: boolean?)
	b.BackgroundColor3 = if on then colour else C.disabled
	b.TextColor3 = if on then C.text else C.disabledText
	b.AutoButtonColor = on
	b:SetAttribute("State", if pending then "Pending" elseif on then "Normal" else "Disabled")
end

-- Redraw from a snapshot. The list is rebuilt; the tabs only when the set of tabs changes.
function GarageMenuView:setData(data)
	self.data = data
	self:_drawTabs(data.tabs or {}, data.category)
	self.title.Text = data.title or ""
	local status = data.status or {}
	self.status.Text = status.text or ""
	self.status.TextColor3 = if status.tone == "error"
		then C.error
		elseif status.tone == "ok" then C.ok
		else C.textDim
	self.status:SetAttribute("Tone", status.tone or "info")
	self:_clearList()
	if data.kind == "paint" then
		self:_drawPaint(data.paint or {})
	else
		for i, row in data.rows or {} do
			self:_drawRow(row, i)
		end
	end
	setEnabled(self.fitButton, data.canFit == true and not data.pending, C.fit, data.pending)
	self.fitButton.Text = if data.pending then "Fitting..." else "Fit"
	setEnabled(self.backButton, data.canBack == true, C.back)
	setEnabled(self.driveButton, true, C.drive)
end

-- The first thing gamepad selection should land on: the selected row, else the first.
function GarageMenuView:firstSelectable(): GuiObject?
	local first, chosen = nil, nil
	local best = math.huge
	for _, b in self.rowButtons do
		if b:GetAttribute("State") == "Selected" then
			chosen = b
		end
		local y = b.AbsolutePosition.Y * 10000 + b.AbsolutePosition.X
		if y < best then
			best, first = y, b
		end
	end
	return chosen or first
end

function GarageMenuView:show()
	self.gui.Enabled = true
	self:_layout()
end

function GarageMenuView:hide()
	self.gui.Enabled = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.gui) then
		GuiService.SelectedObject = nil
	end
end

function GarageMenuView:isOpen(): boolean
	return self.gui.Enabled
end

function GarageMenuView:setLayoutOffset(name: string, offset: Vector2?)
	self.offsets[name] = offset
	self:_layout()
end

local function rect(g: GuiObject)
	return {
		x = g.AbsolutePosition.X,
		y = g.AbsolutePosition.Y,
		w = g.AbsoluteSize.X,
		h = g.AbsoluteSize.Y,
		visible = g.Visible,
	}
end

-- Every piece's rect and state, for the UI checks (TESTING.md "Checking UI").
function GarageMenuView:describe()
	local rows = {}
	for id, b in self.rowButtons do
		rows[id] = {
			rect = rect(b),
			state = b:GetAttribute("State"),
			fitted = b:GetAttribute("Fitted"),
		}
	end
	local tabs = {}
	for id, b in self.tabButtons do
		tabs[id] = { rect = rect(b), state = b:GetAttribute("State"), textFits = b.TextFits }
	end
	return {
		open = self.gui.Enabled,
		layout = self.layout,
		area = { w = self.root.AbsoluteSize.X, h = self.root.AbsoluteSize.Y, x = self.root.AbsolutePosition.X, y = self.root.AbsolutePosition.Y },
		tabs = rect(self.tabs),
		tabButtons = tabs,
		panel = rect(self.panel),
		list = rect(self.list),
		title = self.title.Text,
		status = self.status.Text,
		statusTone = self.status:GetAttribute("Tone"),
		back = { rect = rect(self.backButton), state = self.backButton:GetAttribute("State") },
		fit = { rect = rect(self.fitButton), state = self.fitButton:GetAttribute("State"), text = self.fitButton.Text },
		driveOut = { rect = rect(self.driveButton), state = self.driveButton:GetAttribute("State") },
		rows = rows,
	}
end

function GarageMenuView:destroy()
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
	self.gui:Destroy()
end

return GarageMenuView
