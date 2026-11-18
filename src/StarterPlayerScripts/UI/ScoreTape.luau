--!nonstrict
-- The passive rank widget shared by the live HUD and its Studio fixtures.
local GuiService = game:GetService("GuiService")
local Create = require(script.Parent.Create)
local Style = require(script.Parent.Theme).ScoreTape

local Tape = {}
local names = {
	"WARMUP", "GRIPPED", "LOOSE", "SIDEWAYS", "LINKED", "COMMITTED", "SMOKED", "BOOSTED",
	"LOCKED IN", "FULL SEND", "OVERDRIVE", "FLAT OUT", "REDLINE", "GHOST", "DEMON", "UNTOUGEABLE",
}
local tiers = {}
for i, name in names do
	local inks = Style.inks[math.min(i, #Style.inks)]
	tiers[i] = {
		name = name, accent = Color3.fromHex(inks[1]), base = Color3.fromHex(inks[2]),
		tail = Color3.fromHex(inks[3]), tip = Style.ink, force = math.min((i - 1) / 8, 1),
	}
end

function Tape.tier(rung)
	return tiers[math.clamp(math.floor(rung or 1), 1, #tiers)]
end

function Tape.format(n)
	local s = tostring(math.floor(math.max(n or 0, 0)))
	local grouped = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

function Tape.layout(size)
	local w, h = size.X, size.Y
	local compact = math.min(w, h) < 500
	local portrait = h > w
	local preference = ({Large = 1.12, Larger = 1.22, Largest = 1.32})[GuiService.PreferredTextSize.Name] or 1
	local width = math.round((if compact then 151 else math.clamp(w * .152, 166, 178)) * preference)
	local height = math.round((if compact then 36 else 43) * preference)
	local scoreWidth = math.round((if compact then 90 else 116) * preference)
	local gap = if compact then 7 else 11
	-- The concept anchors the rank, independently of the number of score digits.
	local x = math.max(scoreWidth + gap + 8, math.round(w * .3365 - width * .5))
	local y = math.round(h * .525 - height * .5)
	if portrait then
		-- Feed rows extend 20 px left of the tape. Keep them beside the map, with the
		-- score below it. That leaves the space above Garage for long completed rows.
		x = math.max(180, scoreWidth + gap + 8, math.floor((w + scoreWidth + gap - width) * .5))
		y = math.max(y, math.min(348 * preference, h * .60))
	elseif compact then
		-- Keep the upper live row clear of the 140 px road map on short phones.
		x = math.max(x, 180)
		y = math.max(y, math.min(195 * preference, h * .68))
	end
	x = math.max(0, math.min(x, w - width - 8))
	return {
		x = x, y = y, width = width, height = height, scoreWidth = scoreWidth, gap = gap, compact = compact,
		rankSize = math.round((if compact then 22 else 26) * preference),
		numberSize = math.round((if compact then 16 else 19) * preference), textScale = preference,
	}
end

function Tape.frame(name, parent, z)
	return Create("Frame", {
		Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = z or 1,
	}, parent)
end

function Tape.text(name, parent, font, color, size, z)
	return Create("TextLabel", {
		Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
		Text = "", FontFace = font, TextSize = size, TextColor3 = color, TextStrokeColor3 = Style.shadow,
		TextStrokeTransparency = 0.04, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = z or 2,
	}, parent)
end

local function rule(name, parent, color)
	local f = Tape.frame(name, parent)
	f.BackgroundTransparency = 0
	f.BackgroundColor3 = color
	return f
end

local segments = 14
local Rank = {}
Rank.__index = Rank

function Tape.newRank(parent)
	local self = setmetatable({}, Rank)
	self.root = Tape.frame("Rank", parent, 3)
	self.rule = rule("Hairline", self.root, Style.secondary)
	self.rule.BackgroundTransparency = 0.55
	self.echo = Tape.text("Echo", self.root, Style.rankFont, Style.ink, 26, 1)
	self.echo.Visible = false
	self.base = Tape.text("RankName", self.root, Style.rankFont, Style.secondary, 26)
	self.clip = Tape.frame("Charge", self.root, 3)
	self.clip.ClipsDescendants = true
	self.lit = Tape.text("ChargedLetters", self.clip, Style.rankFont, Style.ink, 26)
	self.mult = Tape.text("Multiplier", self.root, Style.feedFont, Style.ink, 20)
	self.mult.TextXAlignment = Enum.TextXAlignment.Right
	self.bar = Tape.frame("Bar", self.root)
	self.fill = Tape.frame("Fill", self.bar, 2)
	self.fill.ClipsDescendants = true
	self.paint = Tape.frame("Paint", self.fill)
	self.segments = {}
	for i = 1, segments do
		local back = rule("Track" .. i, self.bar, Style.track)
		local front = rule("Ink" .. i, self.paint, Style.ink)
		table.insert(self.segments, {back, front})
	end
	return self
end

function Rank:layout(layout)
	local w, h = layout.width, layout.height
	self.layoutData = layout
	self.root.Size = UDim2.fromOffset(w, h)
	self.rule.Size = UDim2.new(1, 0, 0, 1)
	self.bar.Position = UDim2.fromOffset(0, h - 4)
	self.bar.Size = UDim2.fromOffset(w, 4)
	self.paint.Size = UDim2.fromOffset(w, 4)
	for i, pair in self.segments do
		local x = math.floor((i - 1) * w / segments)
		local n = math.floor(i * w / segments) - x - 2
		for _, part in pair do
			part.Position = UDim2.fromOffset(x, 0)
			part.Size = UDim2.fromOffset(n, 4)
		end
	end
	local rankWidth = w - math.round(29 * layout.textScale)
	for _, part in {self.base, self.lit, self.echo} do
		part.TextSize = layout.rankSize
		part.Size = UDim2.fromOffset(rankWidth, h - 5)
	end
	self.base.Position = UDim2.fromOffset(0, 1)
	self.clip.Position = self.base.Position
	self.mult.Size = UDim2.fromOffset(w - rankWidth, h - 6)
	self.mult.Position = UDim2.fromOffset(rankWidth, 3)
	self.mult.TextSize = math.round((if layout.compact then 17 else 20) * layout.textScale)
	self.progress = nil
end

function Rank:draw(rung, progress)
	local style = Tape.tier(rung)
	if rung ~= self.rung then
		self.rung = rung
		for _, part in {self.base, self.lit, self.echo} do part.Text = style.name end
		self.base.TextColor3 = style.base
		self.lit.TextColor3 = style.accent
		self.echo.TextColor3 = style.tail
		self.mult.Text = "×" .. tostring(rung)
		self.mult.TextColor3 = style.accent
		self.rule.BackgroundColor3 = style.accent
		for i, pair in self.segments do
			local at = (i - 1) / (segments - 1)
			pair[2].BackgroundColor3 = if at < .78 then style.tail:Lerp(style.accent, at / .78)
				else style.accent:Lerp(style.tip, (at - .78) / .22)
		end
		self.root:SetAttribute("Rung", rung)
	end
	local p = math.clamp(progress, 0, 1)
	local width = math.ceil(self.base.TextBounds.X) + 2
	if p ~= self.progress or width ~= self.inkWidth then
		self.progress, self.inkWidth = p, width
		self.fill.Size = UDim2.fromScale(p, 1)
		self.clip.Size = UDim2.fromOffset(math.round(width * p), self.layoutData.height - 4)
	end
end

return Tape
