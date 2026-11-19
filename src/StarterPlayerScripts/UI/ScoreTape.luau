--!nonstrict
-- The passive rank widget shared by the live HUD and its Studio fixtures.
local GuiService = game:GetService("GuiService")
local Create = require(script.Parent.Create)
local Style = require(script.Parent.Theme).ScoreTape

local Tape = {}
local displayScale = 1.3
local tiers = require(script.Parent.ScoreRankRegistry)
local RankArt = require(script.Parent.ScoreRankArt)

function Tape.tier(rung)
	return tiers[math.clamp(math.floor(rung or 1), 1, #tiers)]
end

function Tape.format(n)
	local s = tostring(math.floor(math.max(n or 0, 0)))
	local grouped = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

function Tape.layout(size, preferredTextSize)
	local w, h = size.X, size.Y
	local compact = math.min(w, h) < 500
	local portrait = h > w
	local textSetting = preferredTextSize or GuiService.PreferredTextSize
	local preference = ({Large = 1.12, Larger = 1.22, Largest = 1.32})[textSetting.Name] or 1
	local scale = displayScale * preference
	local baseWidth = if compact then 151 else math.clamp(w * .152, 166, 178)
	local baseScore = if compact then 90 else 116
	local baseGap = if compact then 7 else 11
	-- Keep the total and rank side by side inside the safe width. Event
	-- lettering can use the full preference even when the two-column row cannot.
	local rowScale = math.min(scale, math.max(1, (w - 18) / (baseWidth + baseScore + baseGap)))
	local width = math.round(baseWidth * rowScale)
	local height = math.round((if compact then 36 else 43) * rowScale)
	local scoreWidth = math.round(baseScore * rowScale)
	local gap = math.round(baseGap * rowScale)
	local mapClearance = 160 + math.ceil(20 * scale)
	-- The concept anchors the rank, independently of the number of score digits.
	local x = math.max(scoreWidth + gap + 8, math.round(w * .3365 - width * .5))
	local y = math.round(h * .525 - height * .5)
	if portrait then
		-- Feed rows extend left of the tape. Keep them beside the map, with the
		-- score below it. That leaves the space above Garage for long completed rows.
		x = math.max(mapClearance, scoreWidth + gap + 8, math.floor((w + scoreWidth + gap - width) * .5))
		y = math.max(y, math.min(348 * preference, h * .60))
	elseif compact then
		-- Keep the upper live row clear of the 140 px road map on short phones.
		x = math.max(x, mapClearance)
		y = math.max(y, math.min(195 * preference, h * .68))
	end
	x = math.max(0, math.min(x, w - width - 8))
	return {
		x = x, y = y, width = width, height = height, scoreWidth = scoreWidth, gap = gap, compact = compact,
		rankSize = math.round((if compact then 22 else 26) * rowScale),
		numberSize = math.round((if compact then 16 else 19) * rowScale), textScale = rowScale, feedScale = scale,
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
	self.art = RankArt.new(self.root)
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
	self.sparks = {}
	for i, direction in {Vector2.new(-1,-.38), Vector2.new(1,-.32), Vector2.new(.8,.38), Vector2.new(-.75,.5), Vector2.new(.25,-.8)} do
		local spark = rule("GainSpark" .. i, self.root, Style.ink)
		spark.AnchorPoint = Vector2.new(.5,.5)
		spark.Rotation = math.deg(math.atan2(direction.Y,direction.X))
		spark.ZIndex = 5
		spark.Visible = false
		table.insert(self.sparks, {part = spark, direction = direction})
	end
	return self
end

function Rank:layout(layout)
	local w, h = layout.width, layout.height
	self.layoutData = layout
	self.root.Size = UDim2.fromOffset(w, h)
	self.rule.Size = UDim2.new(1, 0, 0, 1)
	local barHeight = math.round(4 * layout.textScale)
	local segmentGap = math.round(2 * layout.textScale)
	self.bar.Position = UDim2.fromOffset(0, h - barHeight)
	self.bar.Size = UDim2.fromOffset(w, barHeight)
	self.paint.Size = UDim2.new(0,w,1,0)
	for i, pair in self.segments do
		local x = math.floor((i - 1) * w / segments)
		local n = math.floor(i * w / segments) - x - segmentGap
		for _, part in pair do
			part.Position = UDim2.fromOffset(x, 0)
			part.Size = UDim2.new(0,n,1,0)
		end
	end
	self.doubleDigit = (self.rung or 1) >= 10
	local multiplierWidth = if self.doubleDigit then 37 else 29
	local rankWidth = w - math.round(multiplierWidth * layout.textScale)
	self.art:layout(rankWidth, h - barHeight - 2)
	self.mult.Size = UDim2.fromOffset(w - rankWidth, h - 6)
	self.mult.Position = UDim2.fromOffset(rankWidth, 3)
	self.mult.TextSize = math.round((if layout.compact then 17 else 20) * layout.textScale)
	self.progress = nil
end

function Rank:draw(rung, progress, entering, reduced)
	local style = Tape.tier(rung)
	if rung ~= self.rung then
		local widthChanged = self.doubleDigit ~= (rung >= 10)
		self.rung = rung
		if widthChanged then self:layout(self.layoutData) end
		self.art:setRank(rung, entering, reduced)
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
	if p ~= self.progress then
		self.progress = p
		self.fill.Size = UDim2.fromScale(p, 1)
		self.art:setCharge(p)
	end
end

-- The art clock starts on the first renderable word. The meter, multiplier
-- and particles follow that same beat, including when a cold fetch takes a frame.
function Rank:step(dt, reduced)
	local art = self.art
	art:step(dt, reduced)
	local active = art.promoted and art.waitForFace == nil and not reduced and art.age < math.max(art.duration, .324)
	if not active and not self.kicking then return Vector2.zero end
	self.kicking = active
	local l, s = self.layoutData, art.style
	local t = if active then math.min(1,art.age/art.duration) else 1
	local force = art.impactForce
	local envelope = (1-t)^2*force
	local recoil = if t < .37 then 1-t/.37*(1+.25) else -.25*(1-t)/.63
	local multWidth = math.round((if self.doubleDigit then 37 else 29)*l.textScale)
	local extra = math.round(12*math.max(0,recoil)*force)
	self.mult.Size = UDim2.fromOffset(multWidth+extra,l.height-6)
	self.mult.Position = UDim2.fromOffset(l.width-multWidth-extra,3+math.round(4*recoil*force))
	self.mult.TextSize = math.round((if l.compact then 17 else 20)*l.textScale*(1+.24*recoil*force))
	self.mult.TextColor3 = s.accent:Lerp(Style.ink,.85*envelope)
	local restHeight = math.round(4*l.textScale)
	local height = math.round(restHeight*(1+.65*envelope))
	self.bar.Position = UDim2.fromOffset(0,l.height-restHeight-(height-restHeight)/2)
	self.bar.Size = UDim2.fromOffset(l.width,height)
	-- Light the unfilled track, too: a promotion often leaves no ink in the bar.
	for _, pair in self.segments do
		pair[1].BackgroundColor3 = Style.track:Lerp(s.accent,.85*envelope)
	end
	local count = if self.rung >= 9 then 5 else 2
	for i, spark in self.sparks do
		local travel = math.min(1,art.age/(.26+.016*(i-1)))
		local visible = active and i <= count and travel < 1
		local part = spark.part
		part.Visible = visible
		if visible then
			local distance = 13+(1-(1-travel)^2)*25*force
			local at = Vector2.new(l.width*.43,l.height*.48)+spark.direction*distance
			part.Position = UDim2.fromOffset(at.X,at.Y)
			part.Size = UDim2.fromOffset((10-7*travel)*l.textScale,2)
			part.BackgroundColor3 = s.accent:Lerp(Style.ink,.7)
			part.BackgroundTransparency = travel
		end
	end
	return Vector2.new(math.sin(t*25)*5*envelope,math.cos(t*16)*5*envelope)
end

return Tape
