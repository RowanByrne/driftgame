--!nonstrict
-- RoadMapView: the road-ahead map, top left (docs/game/features/road-ahead-map.md, T-234,
-- docs/workflow/UI.md). Programmer art, in the settings style's colours.
--
-- A VIEW, and only that (UI.md "Each screen is a view"): it builds the panel and draws it
-- from a plain table. It reads no remote and no controller; `RoadMapController` hands it a
-- snapshot, and `RoadMapView.fixtures` hands it samples for measuring.
--
--   setData({ mode = "map", r = { ... }, a = { ... }, tight = { ... }, behind = n,
--             arrow = { r, a, deg } })
--   setData({ mode = "hidden" })
--
-- THE SNAPSHOT IS IN STUDS, not pixels, in the map's own frame: `r` studs to the right of
-- the road at the car, `a` studs ahead along it, the origin on the centre line at the car.
-- `tight[i]` marks the segment from point i to i + 1 as a tight bend, and the first
-- `behind` segments are road already driven. The arrow's `deg` is the car's nose against
-- the road, clockwise. The view alone knows its size, so the scale is its own.
--
-- WHERE IT SITS. The top left of the safe area, below Roblox's top bar (`IgnoreGuiInset`
-- false, `CoreUISafeInsets`), so it is never under Roblox's buttons on any device. Its size
-- comes from the measured screen: `Config.RoadMap.PhoneSize` when the short side is under
-- `PhoneBelow`, else `Size`. And when the screen is too narrow for it to sit beside the top
-- centre's column (the run button, its line, the score), it drops below that column.
--
-- IT NEVER TAKES A TOUCH. The whole screen is the steering pad (`Drift/DragControl`):
-- nothing here is `Active`, so a thumb on the map still steers.
--
-- THE LINE IS FRAMES: one rotated, pill-ended frame per segment, cut off at the panel's
-- inner edge by hand (a rotated frame is not clipped by its parent). No images.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layers = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Layers"))

local RoadMapView = {}
RoadMapView.__index = RoadMapView

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

-- Cut the segment (x0, y0)-(x1, y1) to the box [lo, hi] on both axes (Liang-Barsky).
-- Returns the cut ends, or nil when none of it is inside.
function RoadMapView.clip(x0: number, y0: number, x1: number, y1: number, lo: number, hi: number)
	local dx, dy = x1 - x0, y1 - y0
	local t0, t1 = 0, 1
	local p = { -dx, dx, -dy, dy }
	local q = { x0 - lo, hi - x0, y0 - lo, hi - y0 }
	for i = 1, 4 do
		if p[i] == 0 then
			if q[i] < 0 then
				return nil
			end
		else
			local t = q[i] / p[i]
			if p[i] < 0 then
				if t > t1 then
					return nil
				elseif t > t0 then
					t0 = t
				end
			else
				if t < t0 then
					return nil
				elseif t < t1 then
					t1 = t
				end
			end
		end
	end
	return x0 + dx * t0, y0 + dy * t0, x0 + dx * t1, y0 + dy * t1
end

function RoadMapView.new(parent: Instance)
	local C = Config.RoadMap
	local self = setmetatable({}, RoadMapView)
	self.offsets = {}
	self.mode = "hidden"
	self.segments = {}
	self.shownSegments = 0
	self.tightShown = 0
	self.layout = { size = C.Size, top = C.Margin, phone = false, below = false }

	local gui = new("ScreenGui", {
		Name = "RoadMap",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = Layers.RoadMap,
		Enabled = false,
	}, parent)
	self.gui = gui

	local panel = new("Frame", {
		Name = "Panel",
		BackgroundColor3 = C.PanelColor,
		BackgroundTransparency = C.PanelTransparency,
		BorderSizePixel = 0,
		Active = false,
	}, gui)
	panel:SetAttribute("LayoutItem", "RoadMap")
	new("UICorner", { CornerRadius = UDim.new(0, C.CornerRadius) }, panel)
	new("UIStroke", { Name = "Rim", Color = C.RimColor, Transparency = C.RimTransparency, Thickness = 1 }, panel)
	self.panel = panel

	-- the line sits in a layer of its own, under the arrow
	self.lineLayer = new("Frame", {
		Name = "Line",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 2,
	}, panel)

	local arrow = new("TextLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = "\u{25B2}", -- a filled triangle, pointing up
		TextColor3 = C.ArrowColor,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.2,
		FontFace = Font.fromEnum(Enum.Font.GothamBold),
		Active = false,
		AutoLocalize = false,
		ZIndex = 3,
	}, panel)
	self.arrow = arrow

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layout()
		self:_draw()
	end)
	self:_layout()
	return self
end

-- Size and place the panel from the measured screen.
function RoadMapView:_layout()
	local C = Config.RoadMap
	local screen = self.gui.AbsoluteSize
	local phone = screen.X > 0 and math.min(screen.X, screen.Y) < C.PhoneBelow
	local size = if phone then C.PhoneSize else C.Size
	-- beside the top centre's column, or below it when the screen is too narrow
	local roomBeside = (screen.X - C.CentreColumn) * 0.5 - C.CentreGap
	local below = screen.X > 0 and C.Margin + size > roomBeside
	local top = if below then C.ScoreBottom else C.Margin
	local offset = self.offsets.RoadMap or Vector2.zero
	self.layout = { size = size, top = top, phone = phone, below = below, screen = screen }
	self.panel.Size = UDim2.fromOffset(size, size)
	self.panel.Position = UDim2.fromOffset(C.Margin + offset.X, top + offset.Y)
	self.lineWidth = if phone then C.PhoneLineWidth else C.LineWidth
	local arrowSize = if phone then C.PhoneArrowSize else C.ArrowSize
	self.arrow.Size = UDim2.fromOffset(arrowSize, arrowSize)
	self.arrow.TextSize = arrowSize
	-- the scale: `StudsToTop` studs from the arrow to the top inset
	self.anchor = Vector2.new(size * 0.5, size * (1 - C.ArrowFromBottom))
	self.scale = (self.anchor.Y - C.Inset) / C.StudsToTop
end

function RoadMapView:_segment(i: number)
	local seg = self.segments[i]
	if not seg then
		seg = new("Frame", {
			Name = `Seg{i}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 2,
		}, self.lineLayer)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, seg)
		self.segments[i] = seg
	end
	return seg
end

-- Map frame (studs) to panel pixels.
function RoadMapView:toPixels(r: number, a: number): (number, number)
	return self.anchor.X + r * self.scale, self.anchor.Y - a * self.scale
end

function RoadMapView:_draw()
	local C = Config.RoadMap
	local data = self.data
	local used, tightUsed = 0, 0
	if data and data.mode == "map" and data.r then
		local lo, hi = C.Inset, self.layout.size - C.Inset
		local r, a, tight = data.r, data.a, data.tight or {}
		local behind = data.behind or 0
		local w = self.lineWidth
		local px, py = self:toPixels(r[1], a[1])
		for i = 1, #r - 1 do
			local qx, qy = self:toPixels(r[i + 1], a[i + 1])
			local x0, y0, x1, y1 = RoadMapView.clip(px, py, qx, qy, lo, hi)
			if x0 then
				local dx, dy = x1 - x0, y1 - y0
				local len = math.sqrt(dx * dx + dy * dy)
				used += 1
				local seg = self:_segment(used)
				local isTight = tight[i] == true
				local width = if isTight then w + C.TightExtraWidth else w
				if isTight then
					tightUsed += 1
				end
				seg.BackgroundColor3 = if isTight then C.TightColor else C.LineColor
				seg.BackgroundTransparency = if i <= behind then C.BehindTransparency else C.LineTransparency
				-- the pill's round ends overlap the next segment's, so the joints close
				seg.Size = UDim2.fromOffset(len + width, width)
				seg.Position = UDim2.fromOffset((x0 + x1) * 0.5, (y0 + y1) * 0.5)
				seg.Rotation = math.deg(math.atan2(dy, dx))
				seg.Visible = true
			end
			px, py = qx, qy
		end
	end
	for i = used + 1, #self.segments do
		self.segments[i].Visible = false
	end
	self.shownSegments = used
	self.tightShown = tightUsed

	local arrow = data and data.arrow
	if arrow then
		local x, y = self:toPixels(arrow.r, arrow.a)
		local m = C.ArrowMaxOffset
		x = math.clamp(x, self.anchor.X - m, self.anchor.X + m)
		self.arrow.Position = UDim2.fromOffset(x, y)
		self.arrow.Rotation = arrow.deg
		self.arrow.Visible = true
	else
		self.arrow.Visible = false
	end
end

function RoadMapView:setData(snapshot)
	self.data = snapshot
	self.mode = if snapshot and snapshot.mode == "map" then "map" else "hidden"
	self.gui.Enabled = self.mode == "map"
	if self.mode == "map" then
		self:_draw()
	end
end

function RoadMapView:show()
	self.gui.Enabled = true
end

function RoadMapView:hide()
	self.gui.Enabled = false
end

function RoadMapView:setLayoutOffset(name: string, offset: Vector2?)
	self.offsets[name] = offset
	self:_layout()
	self:_draw()
end

-- Its pieces' rects and state, for the UI checks.
function RoadMapView:describe()
	local function rect(g: GuiObject)
		return { position = g.AbsolutePosition, size = g.AbsoluteSize, visible = g.Visible }
	end
	return {
		mode = self.mode,
		enabled = self.gui.Enabled,
		screen = self.gui.AbsoluteSize,
		layout = table.clone(self.layout),
		scale = self.scale,
		panel = rect(self.panel),
		arrow = {
			position = self.arrow.AbsolutePosition + self.arrow.AbsoluteSize * 0.5,
			rotation = self.arrow.Rotation,
			visible = self.arrow.Visible,
		},
		segments = self.shownSegments,
		tightSegments = self.tightShown,
		pool = #self.segments,
	}
end

function RoadMapView:destroy()
	self.gui:Destroy()
end

return RoadMapView
