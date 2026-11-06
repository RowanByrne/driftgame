--!strict
--[[
LayoutDrag: Studio-only layout drag mode for programmer-art screens (docs/workflow/UI.md "Programmer art").

The user drags whole widgets (a card, an action button, a counter) to try placements, or at
the cluster level whole clusters (a strip of cards, the action buttons). Never single sub-elements.
Generic: it works with any view that
	- tags each widget's top-level frame with LayoutItem = "<name>" and each cluster's pieces with
	  LayoutGroup = "<name>" (pieces sharing a name move together),
	- may tag fixed areas with LayoutReserve = "<name>" (shown, never moved: e.g. Roblox chat),
	- has a `gui` (its ScreenGui) and a `root` frame whose UIScale defines the base px,
	- implements view:setLayoutOffset(name, Vector2) and adds that offset (base px) in its layout.
Dragging never edits layout code: offsets ride on top of the view's own layout, reset puts everything
back, and export prints each piece's distance from its nearest screen corner, to copy into the layout
constants and the screen's entry in docs/game/UI-INVENTORY.md.

A game copies this file unchanged to src/StarterPlayerScripts/UI/Dev/LayoutDrag.luau (docs/workflow/CODING.md
"The kit's fixed names"); the template's tools/ui/LayoutDrag.luau is the master.

Snapping (on by default; hold Alt while dragging to bypass it once): an edge or centre lines up with
another piece's edge or centre, or with the 8 / 16 / 24 px screen margins, within 6 px, and a guide line
shows what it snapped to; otherwise the distance from the nearest corner snaps to an 8 px grid.

	local drag = LayoutDrag.new({ view = hud, parent = playerGui })
	drag:setEnabled(true)        -- handles on; offsets stay applied when it's turned off
	drag:setLevel("items")       -- "items" (widgets, default) or "groups" (clusters)
	drag:setSnap(true)
	drag:setView(otherHud)       -- re-bind to another view; current offsets are re-applied to it
	drag:export() -> string ; drag:reset() ; drag:destroy()
	drag.Changed (BindableEvent) fires after a move, reset, level or snap change
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local OK_COLOR = Color3.fromHex("#A98AFF")
local BAD_COLOR = Color3.fromHex("#E0484F")
local RESERVE_COLOR = Color3.fromHex("#999AB4")
local GUIDE_COLOR = Color3.fromHex("#5ED5EE")
local LABEL_BG = Color3.fromHex("#080912")
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local GRID = 8
local MARGINS = { 8, 16, 24 }
local SNAP_RANGE = 6

type Rect = { x: number, y: number, w: number, h: number }
type Piece = { rect: Rect, reserve: boolean, members: { Rect } }

local LayoutDrag = {}
LayoutDrag.__index = LayoutDrag

local function intersects(a: Rect, b: Rect): boolean
	return math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x) > 1 and math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y) > 1
end

local function shown(o: Instance, stop: Instance): boolean
	local n: Instance? = o
	while n and n ~= stop do
		if n:IsA("GuiObject") and not n.Visible then
			return false
		end
		n = n.Parent
	end
	return true
end

local function scaled(r: Rect, k: number): Rect
	return { x = r.x / k, y = r.y / k, w = r.w / k, h = r.h / k }
end

-- One axis: the smallest move that lines one of `values` up with one of `targets` within SNAP_RANGE.
local function align(values: { number }, targets: { number }): (number?, number?)
	local best, at = nil, nil
	for _, v in values do
		for _, t in targets do
			local d = t - v
			if math.abs(d) <= SNAP_RANGE and (best == nil or math.abs(d) < math.abs(best)) then
				best, at = d, t
			end
		end
	end
	return best, at
end

-- One axis on the grid: the distance from the nearer screen edge snaps to a multiple of GRID.
local function gridSnap(lo: number, hi: number, span: number): number
	if lo <= span - hi then
		return math.floor(lo / GRID + 0.5) * GRID - lo
	end
	local fromFar = span - hi
	return (span - math.floor(fromFar / GRID + 0.5) * GRID) - hi
end

function LayoutDrag.new(opts: { view: any, parent: Instance, displayOrder: number?, clearance: number? })
	assert(RunService:IsStudio(), "LayoutDrag is Studio-only")
	local gui = Instance.new("ScreenGui")
	gui.Name = "LayoutDrag"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = opts.displayOrder or 1001
	gui.Enabled = false
	gui.Parent = opts.parent
	local function guide(name: string, vertical: boolean): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.BackgroundColor3 = GUIDE_COLOR
		f.Size = if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1)
		f.Visible = false
		f.ZIndex = 5
		f.Parent = gui
		return f
	end
	local self = setmetatable({
		gui = gui,
		view = opts.view,
		clearance = opts.clearance or 8,
		offsets = {} :: { [string]: Vector2 },
		handles = {} :: { [string]: any },
		dragging = nil :: any,
		enabled = false,
		level = "items",
		snap = true,
		guideX = guide("GuideX", true),
		guideY = guide("GuideY", false),
		lastPieces = {} :: { [string]: Piece },
		connections = {} :: { RBXScriptConnection },
		Changed = Instance.new("BindableEvent"),
	}, LayoutDrag)

	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		local d = self.dragging
		if d and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			self:_dragTo(Vector2.new(input.Position.X, input.Position.Y))
		end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if self.dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			self.dragging = nil
			self.guideX.Visible = false
			self.guideY.Visible = false
			self.Changed:Fire()
		end
	end))
	table.insert(self.connections, RunService.RenderStepped:Connect(function()
		if self.enabled then
			self:_refresh()
		end
	end))
	return self
end

function LayoutDrag._scale(self: any): number
	local root = self.view and self.view.root
	local s = root and root:FindFirstChildOfClass("UIScale")
	return if s then s.Scale else 1
end

-- The pieces at the current level, plus reserves: visible member rects and their union (screen px).
function LayoutDrag._pieces(self: any): { [string]: Piece }
	local out: { [string]: Piece } = {}
	local vgui = self.view and self.view.gui
	if not vgui then
		return out
	end
	local origin = vgui.AbsolutePosition
	local attr = if self.level == "groups" then "LayoutGroup" else "LayoutItem"
	for _, o in vgui:GetDescendants() do
		if o:IsA("GuiObject") then
			local name = o:GetAttribute(attr)
			local reserve = o:GetAttribute("LayoutReserve")
			local key = if type(name) == "string" then name elseif type(reserve) == "string" then reserve else nil
			if key and shown(o, vgui) and o.AbsoluteSize.X > 0 then
				local p, s = o.AbsolutePosition - origin, o.AbsoluteSize
				local member = { x = p.X, y = p.Y, w = s.X, h = s.Y }
				local g = out[key]
				if not g then
					out[key] = { rect = member, reserve = type(name) ~= "string", members = { member } }
				else
					table.insert(g.members, member)
					local r = g.rect
					local x0, y0 = math.min(r.x, p.X), math.min(r.y, p.Y)
					local x1, y1 = math.max(r.x + r.w, p.X + s.X), math.max(r.y + r.h, p.Y + s.Y)
					g.rect = { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
				end
			end
		end
	end
	return out
end

-- Distance from the nearest screen corner, in base px.
function LayoutDrag._corner(self: any, r: Rect): (string, number, number)
	local k = self:_scale()
	local W, H = self.gui.AbsoluteSize.X / k, self.gui.AbsoluteSize.Y / k
	local b = scaled(r, k)
	local left, right, top, bottom = b.x, W - b.x - b.w, b.y, H - b.y - b.h
	local horiz = if left <= right then "left" else "right"
	local vert = if top <= bottom then "top" else "bottom"
	return vert .. "-" .. horiz, math.floor((if horiz == "left" then left else right) + 0.5), math.floor((if vert == "top" then top else bottom) + 0.5)
end

function LayoutDrag._dragTo(self: any, mouse: Vector2)
	local d = self.dragging
	local k = self:_scale()
	local raw = d.startOffset + (mouse - d.startMouse) / k
	local final = raw
	self.guideX.Visible = false
	self.guideY.Visible = false
	local bypass = UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
	if self.snap and not bypass then
		local W, H = self.gui.AbsoluteSize.X / k, self.gui.AbsoluteSize.Y / k
		local s = d.startRect
		local r = { x = s.x + raw.X - d.startOffset.X, y = s.y + raw.Y - d.startOffset.Y, w = s.w, h = s.h }
		local tx, ty = {}, {}
		for _, m in MARGINS do
			table.insert(tx, m); table.insert(tx, W - m)
			table.insert(ty, m); table.insert(ty, H - m)
		end
		for _, o in d.others do
			table.insert(tx, o.x); table.insert(tx, o.x + o.w); table.insert(tx, o.x + o.w / 2)
			table.insert(ty, o.y); table.insert(ty, o.y + o.h); table.insert(ty, o.y + o.h / 2)
		end
		local dx, atX = align({ r.x, r.x + r.w / 2, r.x + r.w }, tx)
		local dy, atY = align({ r.y, r.y + r.h / 2, r.y + r.h }, ty)
		if dx then
			self.guideX.Position = UDim2.fromOffset(math.floor((atX :: number) * k + 0.5), 0)
			self.guideX.Visible = true
		else
			dx = gridSnap(r.x, r.x + r.w, W)
		end
		if dy then
			self.guideY.Position = UDim2.fromOffset(0, math.floor((atY :: number) * k + 0.5))
			self.guideY.Visible = true
		else
			dy = gridSnap(r.y, r.y + r.h, H)
		end
		final = raw + Vector2.new(dx :: number, dy :: number)
	end
	final = Vector2.new(math.floor(final.X + 0.5), math.floor(final.Y + 0.5))
	self.offsets[d.name] = if final.Magnitude > 0 then final else nil
	self.view:setLayoutOffset(d.name, final)
end

function LayoutDrag._handle(self: any, name: string, reserve: boolean)
	local h = self.handles[name]
	if h then
		return h
	end
	local box = Instance.new("TextButton")
	box.Name = "Handle_" .. name
	box.Text = ""
	box.AutoButtonColor = false
	box.BackgroundColor3 = if reserve then RESERVE_COLOR else OK_COLOR
	box.BackgroundTransparency = if reserve then 0.92 else 0.85
	box.Active = not reserve
	box.Interactable = not reserve
	box.ZIndex = 1
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = if reserve then RESERVE_COLOR else OK_COLOR
	stroke.Transparency = if reserve then 0.5 else 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	local tag = Instance.new("TextLabel")
	tag.Name = "Readout"
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.Size = UDim2.fromOffset(0, 22)
	tag.BackgroundColor3 = LABEL_BG
	tag.BackgroundTransparency = 0.15
	tag.TextColor3 = Color3.new(1, 1, 1)
	tag.FontFace = FONT
	tag.TextSize = 16
	tag.ZIndex = 2
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = tag
	tag.Parent = box
	if not reserve then
		box.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local pieces = self:_pieces()
				local mine = pieces[name]
				if not mine then
					return
				end
				local k = self:_scale()
				local others = {}
				for other, p in pieces do
					if other ~= name then
						for _, m in p.members do
							table.insert(others, scaled(m, k))
						end
					end
				end
				self.dragging = { name = name, startMouse = Vector2.new(input.Position.X, input.Position.Y), startOffset = self.offsets[name] or Vector2.zero, startRect = scaled(mine.rect, k), others = others }
			end
		end)
	end
	box.Parent = self.gui
	h = { box = box, stroke = stroke, tag = tag, reserve = reserve }
	self.handles[name] = h
	return h
end

function LayoutDrag._refresh(self: any)
	local pieces = self:_pieces()
	self.lastPieces = pieces
	local k = self:_scale()
	local screen = self.gui.AbsoluteSize
	local seen = {}
	for name, g in pieces do
		seen[name] = true
		local h = self:_handle(name, g.reserve)
		local r = g.rect
		h.box.Position = UDim2.fromOffset(r.x, r.y)
		h.box.Size = UDim2.fromOffset(r.w, r.h)
		h.box.Visible = true
		-- Labels sit above their box unless that leaves the screen; reserves label inside.
		h.tag.Position = if not g.reserve and r.y >= 26 then UDim2.fromOffset(0, -24) else UDim2.fromOffset(4, 4)
		if g.reserve then
			h.tag.Text = name .. " (fixed)"
		else
			local corner, cx, cy = self:_corner(r)
			local o = self.offsets[name]
			local moved = if o then string.format("  moved %+d, %+d", o.X, o.Y) else ""
			local problems = {}
			-- Overlaps compare the actual pieces, not bounding boxes (which can hold empty space).
			for other, og in pieces do
				if other ~= name then
					local hit = false
					for _, m in g.members do
						for _, om in og.members do
							if intersects(m, om) then
								hit = true
								break
							end
						end
						if hit then
							break
						end
					end
					if hit then
						table.insert(problems, "overlaps " .. other)
					end
				end
			end
			local edge = self.clearance * k
			if r.x < edge - 0.5 or r.y < -0.5 or screen.X - (r.x + r.w) < edge - 0.5 or screen.Y - (r.y + r.h) < edge - 0.5 then
				table.insert(problems, "under " .. self.clearance .. " px from an edge")
			end
			local bad = #problems > 0
			h.stroke.Color = if bad then BAD_COLOR else OK_COLOR
			h.box.BackgroundColor3 = if bad then BAD_COLOR else OK_COLOR
			h.tag.Text = string.format("%s · %s %d, %d%s%s", name, corner, cx, cy, moved, if bad then "  · " .. table.concat(problems, ", ") else "")
		end
	end
	for name, h in self.handles do
		if not seen[name] then
			h.box.Visible = false
		end
	end
end

function LayoutDrag.setEnabled(self: any, on: boolean)
	self.enabled = on
	self.gui.Enabled = on
	self.dragging = nil
	if on then
		self:_refresh()
	end
end

function LayoutDrag.setLevel(self: any, level: string)
	if level ~= "items" and level ~= "groups" then
		return
	end
	self.level = level
	self.dragging = nil
	for _, h in self.handles do
		h.box.Visible = false
	end
	self.Changed:Fire()
end

function LayoutDrag.setSnap(self: any, on: boolean)
	self.snap = on
	self.Changed:Fire()
end

-- Re-bind to another view (a rebuilt or swapped surface); the current offsets carry over.
function LayoutDrag.setView(self: any, view: any)
	self.view = view
	self.dragging = nil
	for name, o in self.offsets do
		view:setLayoutOffset(name, o)
	end
end

function LayoutDrag.reset(self: any)
	for name in self.offsets do
		self.view:setLayoutOffset(name, Vector2.zero)
	end
	table.clear(self.offsets)
	self.Changed:Fire()
end

-- Every piece's distance from its nearest corner in base px, ready to copy into the layout and the spec.
function LayoutDrag.export(self: any): string
	local pieces = self:_pieces()
	local names = {}
	for name, g in pieces do
		if not g.reserve then
			table.insert(names, name)
		end
	end
	table.sort(names)
	local lines = { string.format("-- LayoutDrag · %s · %s · screen %dx%d (scale %.3g) · base px from each piece's nearest corner", self.view.gui.Name, if self.level == "groups" then "clusters" else "widgets", self.gui.AbsoluteSize.X, self.gui.AbsoluteSize.Y, self:_scale()) }
	for _, name in names do
		local corner, cx, cy = self:_corner(pieces[name].rect)
		local o = self.offsets[name] or Vector2.zero
		table.insert(lines, string.format("%-9s %-13s x=%-4d y=%-4d (moved %+d, %+d)", name, corner, cx, cy, o.X, o.Y))
	end
	local text = table.concat(lines, "\n")
	print(text)
	return text
end

function LayoutDrag.destroy(self: any)
	for _, c in self.connections do
		c:Disconnect()
	end
	self.gui:Destroy()
	self.Changed:Destroy()
end

return LayoutDrag
