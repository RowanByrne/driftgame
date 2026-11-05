--[[
MeasureUI.luau: the per-viewport measurement checks (docs/workflow/TESTING.md "Checking UI").

Run with execute_luau in the CLIENT datamodel during a playtest, once per viewport (SimulatorSweep.luau
sets the device between runs). Edit CONFIG, then send the whole file as the execute_luau code.

Checks every visible GuiObject (Visible through all ancestors, in an enabled ScreenGui) for:
  textFits    TextFits on non-empty text
  textSize    effective TextSize (x every ancestor UIScale x CONFIG.scale) >= essentialMin, or auxMin
              for labels with the attribute TextAux = true; TextScaled labels are listed, not judged
  targets     GuiButtons and TextBoxes >= targetMin on both sides (attribute TargetExempt = "<reason>" skips)
  images      on-screen images IsLoaded and ContentProvider fetch status Success
  artwork     every frame with an ArtworkWithinLimit attribute has it true (UI.md "4. Assets")
  layering    text not covered by a higher-ZIndex image sibling, or by an image child of its own
  overlaps    no two CONFIG.pieces intersect; with touch, no piece holding a button sits in the
              thumbstick or jump zones (UI.md "Layouts per device")
  safeArea    buttons and text inside the device safe area
  fullBleed   CONFIG.fullBleed pieces reach every screen edge
  coverage    drawn area % on a 2 px grid (CONFIG.coverage = true; text-only labels count as TextBounds)
All rects are in screen px (origin = the screen's top-left, under the Roblox top bar).
Returns string-keyed tables only (execute_luau drops the hash part of mixed tables).
]]

local CONFIG = {
	guis = nil, -- { "MainHud", "HudPanels" }; nil = every enabled ScreenGui in PlayerGui
	excludeGuis = { "Freecam", "TouchGui", "BubbleChat", "Chat", "RobloxGui" },
	essentialMin = 16,
	auxMin = 14,
	targetMin = 44,
	touchPreferred = 48,
	scale = 1, -- extra factor when a project emulator shrinks the UI; 1 in the device simulator
	pieces = nil, -- overlap check: { "MainHud.TopBar", "Hotbar.Bar" } (paths under PlayerGui)
	thumbZones = "auto", -- "auto": add touch zones when TouchEnabled; true / false to force
	coverage = false,
	safeArea = true,
	fullBleed = nil, -- { "Cinematic.Letterbox" }
	artworkAttribute = "ArtworkWithinLimit",
	maxListed = 20,
}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- A stalled renderer (Studio's 1x1 client viewport) makes every rect meaningless: check first.
local pulses = 0
local pulseConn = RunService.RenderStepped:Connect(function()
	pulses += 1
end)
local started = os.clock()
while os.clock() - started < 0.5 do
	task.wait()
end
pulseConn:Disconnect()
if pulses == 0 then
	return { pass = false, rendererStalled = true, note = "No RenderStepped pulses in 0.5 s: restart Play before measuring (11, Studio traps)." }
end

type Rect = { x: number, y: number, w: number, h: number }

local function round(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end
local function intersect(a: Rect, b: Rect): Rect?
	local x0, y0 = math.max(a.x, b.x), math.max(a.y, b.y)
	local x1, y1 = math.min(a.x + a.w, b.x + b.w), math.min(a.y + a.h, b.y + b.h)
	if x1 - x0 <= 0 or y1 - y0 <= 0 then
		return nil
	end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end
local function rectString(r: Rect): string
	return string.format("%g,%g %gx%g", round(r.x), round(r.y), round(r.w), round(r.h))
end

-- Screen and safe-area rects from two empty probe guis, in the same space as AbsolutePosition.
local function probe(insets: Enum.ScreenInsets): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = "__MeasureUIProbe"
	g.ScreenInsets = insets
	g.ResetOnSpawn = false
	g.Parent = playerGui
	return g
end
local fullProbe, safeProbe = probe(Enum.ScreenInsets.None), probe(Enum.ScreenInsets.DeviceSafeInsets)
for _ = 1, 30 do
	if fullProbe.AbsoluteSize.X > 0 and safeProbe.AbsoluteSize.X > 0 then
		break
	end
	task.wait()
end
local origin = fullProbe.AbsolutePosition
local screen: Rect = { x = 0, y = 0, w = fullProbe.AbsoluteSize.X, h = fullProbe.AbsoluteSize.Y }
local safe: Rect = {
	x = safeProbe.AbsolutePosition.X - origin.X,
	y = safeProbe.AbsolutePosition.Y - origin.Y,
	w = safeProbe.AbsoluteSize.X,
	h = safeProbe.AbsoluteSize.Y,
}
fullProbe:Destroy()
safeProbe:Destroy()

local function rectOf(o: GuiBase2d): Rect
	local p, s = o.AbsolutePosition, o.AbsoluteSize
	return { x = p.X - origin.X, y = p.Y - origin.Y, w = s.X, h = s.Y }
end
local function pathOf(o: Instance): string
	return (string.gsub(o:GetFullName(), "^.-PlayerGui%.", ""))
end

local touch = UserInputService.TouchEnabled
local result: { [string]: any } = {
	viewport = string.format("%dx%d", screen.w, screen.h),
	safeInsets = { left = safe.x, top = safe.y, right = screen.w - safe.x - safe.w, bottom = screen.h - safe.y - safe.h },
	touch = touch,
	scale = CONFIG.scale,
}
local fails = {
	textFits = {}, textSize = {}, targets = {}, images = {}, artwork = {}, layering = {},
	overlaps = {}, safeArea = {}, fullBleed = {},
}
local notes = { textScaled = {}, underTouchPreferred = {}, layeringTies = {}, offscreenImages = 0, hiddenPieces = {} }
local counts = { objects = 0, text = 0, targets = 0, images = 0 }
local minText, minTarget, maxDistortion = math.huge, math.huge, 0
local failCounts: { [string]: number } = {}

local function add(list: { any }, key: string, entry: any)
	failCounts[key] = (failCounts[key] or 0) + 1
	if #list < CONFIG.maxListed then
		table.insert(list, entry)
	end
end
local function note(list: { any }, entry: any)
	if #list < CONFIG.maxListed then
		table.insert(list, entry)
	end
end

local excluded = {}
for _, n in CONFIG.excludeGuis do
	excluded[n] = true
end
local filterGuis = CONFIG.guis ~= nil
local wanted: { [string]: boolean } = {}
for _, n in CONFIG.guis or {} do
	wanted[n] = true
end

-- Coverage grid (2 px cells), one byte per cell.
local gw, gh = math.ceil(screen.w / 2), math.ceil(screen.h / 2)
local grid = if CONFIG.coverage then buffer.create(gw * gh) else nil
local guiCover: { [string]: number } = {}
local function mark(r: Rect, guiName: string)
	if not grid then
		return
	end
	local c = intersect(r, screen)
	if not c then
		return
	end
	local own = 0
	for cy = math.floor(c.y / 2), math.min(gh - 1, math.ceil((c.y + c.h) / 2) - 1) do
		local row = cy * gw
		for cx = math.floor(c.x / 2), math.min(gw - 1, math.ceil((c.x + c.w) / 2) - 1) do
			if buffer.readu8(grid, row + cx) == 0 then
				buffer.writeu8(grid, row + cx, 1)
				own += 1
			end
		end
	end
	guiCover[guiName] = (guiCover[guiName] or 0) + own
end

local function hasText(o: Instance): boolean
	return (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox"))
		and (o :: any).ContentText ~= "" and (o :: any).TextTransparency < 1
end
local function hasImage(o: Instance): boolean
	return (o:IsA("ImageLabel") or o:IsA("ImageButton")) and (o :: any).Image ~= "" and (o :: any).ImageTransparency < 1
end

local function textBox(o: any, r: Rect): Rect
	local tb = o.TextBounds
	local x = r.x
	if o.TextXAlignment == Enum.TextXAlignment.Center then
		x += (r.w - tb.X) / 2
	elseif o.TextXAlignment == Enum.TextXAlignment.Right then
		x += r.w - tb.X
	end
	local y = r.y
	if o.TextYAlignment == Enum.TextYAlignment.Center then
		y += (r.h - tb.Y) / 2
	elseif o.TextYAlignment == Enum.TextYAlignment.Bottom then
		y += r.h - tb.Y
	end
	return { x = x, y = y, w = tb.X, h = tb.Y }
end

local function inspect(o: GuiObject, scale: number, clip: Rect, guiName: string)
	counts.objects += 1
	local r = rectOf(o)
	local onScreen = intersect(r, clip)
	local path = pathOf(o)

	if hasText(o) then
		counts.text += 1
		local t = o :: any
		if not t.TextFits then
			add(fails.textFits, "textFits", { path = path, text = string.sub(t.ContentText, 1, 40), rect = rectString(r) })
		end
		if t.TextScaled then
			note(notes.textScaled, path)
		else
			local eff = t.TextSize * scale * CONFIG.scale
			local aux = o:GetAttribute("TextAux") == true
			if not aux then
				minText = math.min(minText, eff)
			end
			if eff < (if aux then CONFIG.auxMin else CONFIG.essentialMin) - 0.01 then
				add(fails.textSize, "textSize", { path = path, effective = round(eff), aux = aux, text = string.sub(t.ContentText, 1, 40) })
			end
		end
		if CONFIG.safeArea and onScreen then
			local tb = textBox(t, r) -- the drawn text, not a full-screen label's box
			if tb.x < safe.x - 0.5 or tb.y < safe.y - 0.5 or tb.x + tb.w > safe.x + safe.w + 0.5 or tb.y + tb.h > safe.y + safe.h + 0.5 then
				add(fails.safeArea, "safeArea", { path = path, rect = rectString(tb), kind = "text" })
			end
		end
		-- Covered by an image child of its own (children always draw above their parent).
		for _, ch in o:GetChildren() do
			if ch:IsA("GuiObject") and ch.Visible and hasImage(ch) and (ch :: any).ImageTransparency < 0.5 and intersect(rectOf(ch), r) then
				add(fails.layering, "layering", { path = path, coveredBy = ch.Name, why = "image child draws above its parent's text" })
			end
		end
		-- Covered by an image sibling with a higher ZIndex (ties are noted: order decides).
		if o.Parent then
			for _, sib in o.Parent:GetChildren() do
				if sib ~= o and sib:IsA("GuiObject") and sib.Visible and hasImage(sib) and (sib :: any).ImageTransparency < 0.5
					and intersect(rectOf(sib), r) then
					if sib.ZIndex > o.ZIndex then
						add(fails.layering, "layering", { path = path, coveredBy = sib.Name, why = string.format("sibling ZIndex %d > %d", sib.ZIndex, o.ZIndex) })
					elseif sib.ZIndex == o.ZIndex then
						note(notes.layeringTies, path .. " ~ " .. sib.Name)
					end
				end
			end
		end
	end

	if o:IsA("GuiButton") or o:IsA("TextBox") then
		local okI, interactable = pcall(function()
			return (o :: any).Interactable
		end)
		if not (okI and interactable == false) and not o:GetAttribute("TargetExempt") then
			counts.targets += 1
			local w, h = r.w * CONFIG.scale, r.h * CONFIG.scale
			local side = math.min(w, h)
			minTarget = math.min(minTarget, side)
			if side < CONFIG.targetMin - 0.01 then
				add(fails.targets, "targets", { path = path, size = string.format("%gx%g", round(w), round(h)) })
			elseif touch and side < CONFIG.touchPreferred - 0.01 then
				note(notes.underTouchPreferred, path .. " " .. string.format("%gx%g", round(w), round(h)))
			end
			if CONFIG.safeArea and onScreen and (r.x < safe.x - 0.5 or r.y < safe.y - 0.5 or r.x + r.w > safe.x + safe.w + 0.5 or r.y + r.h > safe.y + safe.h + 0.5) then
				-- Full-screen input catchers legitimately span the screen; skip anything at least screen-sized.
				if not (r.w >= screen.w - 1 and r.h >= screen.h - 1) then
					add(fails.safeArea, "safeArea", { path = path, rect = rectString(r), kind = "button" })
				end
			end
		end
	end

	if hasImage(o) then
		counts.images += 1
		local img = o :: any
		if not onScreen then
			notes.offscreenImages += 1
		else
			local okStatus, status = pcall(function()
				return ContentProvider:GetAssetFetchStatus(img.Image)
			end)
			local statusName = if okStatus then status.Name else "unknown"
			if not img.IsLoaded or (okStatus and status ~= Enum.AssetFetchStatus.Success) then
				add(fails.images, "images", { path = path, image = img.Image, isLoaded = img.IsLoaded, fetch = statusName })
			end
		end
	end

	local within = o:GetAttribute(CONFIG.artworkAttribute)
	if within ~= nil then
		local d = o:GetAttribute("ArtworkDistortion")
		if type(d) == "number" then
			maxDistortion = math.max(maxDistortion, d)
		end
		if within ~= true then
			add(fails.artwork, "artwork", { path = path, variant = tostring(o:GetAttribute("ArtworkVariant")), distortion = d })
		end
	end

	if grid and onScreen then
		local drawn = o.BackgroundTransparency < 0.97 or hasImage(o) or o:IsA("ViewportFrame")
		if drawn then
			mark(onScreen, guiName)
		elseif hasText(o) then
			local box = intersect(textBox(o, r), clip)
			if box then
				mark(box, guiName)
			end
		end
	end
end

local sinceYield = 0
local function walk(node: Instance, parentScale: number, clip: Rect, guiName: string)
	sinceYield += 1
	if sinceYield >= 400 then
		sinceYield = 0
		task.wait() -- keep Studio responsive on big UIs
	end
	local scale = parentScale
	for _, ch in node:GetChildren() do
		if ch:IsA("UIScale") then
			scale *= ch.Scale
		end
	end
	if node:IsA("GuiObject") then
		inspect(node, scale, clip, guiName)
		if node.ClipsDescendants then
			clip = intersect(clip, rectOf(node)) or { x = 0, y = 0, w = 0, h = 0 }
		end
	end
	for _, ch in node:GetChildren() do
		if ch:IsA("LayerCollector") then
			continue -- nested guis (Billboard/Surface) are not screen UI
		elseif ch:IsA("GuiObject") then
			if ch.Visible then
				walk(ch, scale, clip, guiName)
			end
		elseif ch:IsA("Folder") then
			walk(ch, scale, clip, guiName)
		end
	end
end

local checked = {}
for _, gui in playerGui:GetChildren() do
	if gui:IsA("ScreenGui") and gui.Enabled and gui.Name ~= "__MeasureUIProbe" and not excluded[gui.Name]
		and (not filterGuis or wanted[gui.Name]) then
		table.insert(checked, gui.Name)
		walk(gui, 1, screen, gui.Name)
	end
end
result.guis = checked

-- Overlaps between named pieces, plus touch zones for pieces that hold a button.
local function find(path: string): Instance?
	local node: Instance? = playerGui
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end
local function shown(o: Instance): boolean
	local n: Instance? = o
	while n and n ~= playerGui do
		if n:IsA("GuiObject") and not n.Visible then
			return false
		end
		if n:IsA("ScreenGui") and not n.Enabled then
			return false
		end
		n = n.Parent
	end
	return true
end
local function holdsButton(o: Instance): boolean
	if o:IsA("GuiButton") then
		return true
	end
	for _, d in o:GetDescendants() do
		if d:IsA("GuiButton") and shown(d) then
			return true
		end
	end
	return false
end
if CONFIG.pieces then
	local pieces = {}
	for _, p in CONFIG.pieces do
		local o = find(p)
		if o and o:IsA("GuiObject") and shown(o) then
			table.insert(pieces, { name = p, rect = rectOf(o), button = holdsButton(o) })
		else
			note(notes.hiddenPieces, p)
		end
	end
	local zones = {}
	if CONFIG.thumbZones == true or (CONFIG.thumbZones == "auto" and touch) then
		if screen.w >= screen.h then
			table.insert(zones, { name = "thumbstick zone", rect = { x = 0, y = screen.h / 3, w = screen.w * 0.4, h = screen.h * 2 / 3 } })
		else
			table.insert(zones, { name = "thumbstick zone", rect = { x = 0, y = screen.h * 0.6, w = screen.w, h = screen.h * 0.4 } })
		end
		table.insert(zones, { name = "jump button", rect = { x = screen.w - 95, y = screen.h - 90, w = 70, h = 70 } })
	end
	for i = 1, #pieces do
		for j = i + 1, #pieces do
			local hit = intersect(pieces[i].rect, pieces[j].rect)
			if hit and hit.w * hit.h > 1 then
				add(fails.overlaps, "overlaps", { a = pieces[i].name, b = pieces[j].name, rect = rectString(hit) })
			end
		end
		for _, z in zones do
			local hit = pieces[i].button and intersect(pieces[i].rect, z.rect)
			if hit and hit.w * hit.h > 1 then
				add(fails.overlaps, "overlaps", { a = pieces[i].name, b = z.name, rect = rectString(hit) })
			end
		end
	end
end

if CONFIG.fullBleed then
	for _, p in CONFIG.fullBleed do
		local o = find(p)
		if not (o and o:IsA("GuiObject") and shown(o)) then
			note(notes.hiddenPieces, p)
		else
			local r = rectOf(o)
			if r.x > 0.5 or r.y > 0.5 or r.x + r.w < screen.w - 0.5 or r.y + r.h < screen.h - 0.5 then
				add(fails.fullBleed, "fullBleed", { path = p, rect = rectString(r), screen = result.viewport })
			end
		end
	end
end

if grid then
	local total = 0
	for i = 0, gw * gh - 1 do
		total += buffer.readu8(grid, i)
	end
	local byGui = {}
	for name, cells in guiCover do
		byGui[name] = round(cells / (gw * gh) * 100)
	end
	result.coverage = { percent = round(total / (gw * gh) * 100), byGui = byGui, note = "byGui counts cells a gui added first; guis are walked in PlayerGui order" }
end

local pass = true
for _, list in fails do
	if #list > 0 then
		pass = false
	end
end
result.pass = pass
result.fails = fails
result.failCounts = failCounts
result.notes = notes
result.counts = counts
result.minEssentialText = if minText == math.huge then nil else round(minText)
result.minTarget = if minTarget == math.huge then nil else round(minTarget)
result.maxDistortion = math.floor(maxDistortion * 1000 + 0.5) / 1000
return result
