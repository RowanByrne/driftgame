--!nonstrict
-- Endless-run presentation. The score snapshot stays authoritative while a bank is in flight.
local GuiService = game:GetService("GuiService")
local UI = script.Parent.Parent.UI
local Create = require(UI.Create)
local Layers = require(UI.Layers)
local Tape = require(UI.ScoreTape)
local Style = require(UI.Theme).ScoreTape

local ScoreHudView = {}
ScoreHudView.__index = ScoreHudView
ScoreHudView.format = Tape.format

local impactDuration, flightDuration, countDuration = 0.29, 0.30, 0.28
local streaks = {Vector2.new(-28,-10), Vector2.new(31,-9), Vector2.new(23,10), Vector2.new(-20,13), Vector2.new(8,-18)}

local function rect(item)
	return {position = item.AbsolutePosition, size = item.AbsoluteSize, visible = item.Visible}
end

function ScoreHudView.new(parent)
	local self = setmetatable({}, ScoreHudView)
	self.offsets = {}
	self.mode = "hidden"
	self.waiting = 0
	self.debits = {}
	self.transfers = {}
	self.bankStarts, self.absorbs = 0, 0
	self.gui = Create("ScreenGui", {
		Name = "ScoreHud", ResetOnSpawn = false, IgnoreGuiInset = false, Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = Layers.ScoreHud,
	}, parent)
	self.panel = Tape.frame("Panel", self.gui)
	self.panel:SetAttribute("LayoutItem", "ScorePanel")
	self.rank = Tape.newRank(self.panel)
	self.score = Tape.text("Score", self.panel, Style.numberFont, Style.ink, 19)
	self.score.TextXAlignment = Enum.TextXAlignment.Right
	self.caption = Tape.text("ScoreCaption", self.panel, Style.feedFont, Style.secondary, 14)
	self.caption.TextXAlignment = Enum.TextXAlignment.Right
	self.caption.Text = "RUN SCORE"
	self.caption:SetAttribute("TextAux", true)
	self.divider = Tape.frame("Divider", self.panel)
	self.divider.BackgroundTransparency = .3
	self.divider.BackgroundColor3 = Style.secondary

	self.sparks = {}
	for i, vector in streaks do
		local spark = Tape.frame("Spark" .. i, self.panel, 5)
		spark.AnchorPoint = Vector2.new(.5,.5)
		spark.Visible = false
		spark.Rotation = math.deg(math.atan2(vector.Y, vector.X))
		table.insert(self.sparks, spark)
	end
	self.runLine = Tape.text("RunScore", self.panel, Style.feedFont, Style.ink, 20)
	self.bestLine = Tape.text("Best", self.panel, Style.feedFont, Style.secondary, 17)
	self.runLine.TextXAlignment = Enum.TextXAlignment.Center
	self.bestLine.TextXAlignment = Enum.TextXAlignment.Center
	self.prefConn = GuiService:GetPropertyChangedSignal("PreferredTextSize"):Connect(function() self:_layout() end)
	self.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:_layout() end)
	self:_layout()
	self:setData({mode = "hidden"})
	return self
end

function ScoreHudView:_layout()
	local l = Tape.layout(self.gui.AbsoluteSize)
	self.layout = l
	local o = self.offsets.ScorePanel or Vector2.zero
	local lead = l.scoreWidth + l.gap
	local width = lead + l.width
	self.panel.Position = UDim2.fromOffset(l.x - lead + o.X, l.y + o.Y + (self.feedShift or 0))
	self.panel.Size = UDim2.fromOffset(width, l.height)
	self.rank.root.Position = UDim2.fromOffset(lead, 0)
	self.rank:layout(l)
	self.caption.TextSize = math.round(14 * l.textScale)
	self.caption.Size = UDim2.fromOffset(l.scoreWidth - 5, math.ceil(l.height * .41))
	self.score.Position = UDim2.fromOffset(0, math.floor(l.height * .39))
	self.score.Size = UDim2.fromOffset(l.scoreWidth - 5, math.ceil(l.height * .61))
	self.score.TextSize = l.numberSize
	self.divider.Position = UDim2.fromOffset(l.scoreWidth, 3)
	self.divider.Size = UDim2.fromOffset(1, l.height - 6)
	self.runLine.TextSize = math.round(20 * l.textScale)
	self.bestLine.TextSize = math.round(17 * l.textScale)
	self.runLine.Size = UDim2.fromOffset(width, math.ceil(l.height * .55))
	self.bestLine.Position = UDim2.fromOffset(0, math.ceil(l.height * .55))
	self.bestLine.Size = UDim2.fromOffset(width, math.ceil(l.height * .5))
	if self.rung then self.rank:draw(self.rung, self.progress or 0) end
end

function ScoreHudView:_reduced()
	if self.motionOverride ~= nil then return self.motionOverride end
	return GuiService.ReducedMotionEnabled
end

function ScoreHudView:_resetEffects()
	for _, entry in self.transfers do entry.label:Destroy() end
	table.clear(self.transfers)
	table.clear(self.debits)
	self.waiting = 0
	self.pulse = nil
	self.reservedThisSnapshot = 0
	self.score.Position = UDim2.fromOffset(0, math.floor(self.layout.height * .39))
	for _, spark in self.sparks do spark.Visible = false end
	self.rank.root.Position = UDim2.fromOffset(self.layout.scoreWidth + self.layout.gap, 0)
end

function ScoreHudView:setReducedMotion(on)
	self.motionOverride = on
	if self:_reduced() then self:_resetEffects() end
end

function ScoreHudView:setData(data)
	data = data or {mode = "hidden"}
	local mode = data.mode or "hidden"
	local changed = self.mode ~= mode or not self.data
	if changed then
		self:_resetEffects()
		self.panel:SetAttribute("State", mode)
		self.gui.Enabled = mode ~= "hidden"
		local live = mode == "run"
		for _, item in {self.rank.root, self.score, self.caption, self.divider} do item.Visible = live end
		self.runLine.Visible = mode == "summary"
		self.bestLine.Visible = mode == "summary"
		self.rank.rung = nil
		self.rung = nil
		self.shown = nil
	end
	self.mode, self.data = mode, data
	self.reservedThisSnapshot = 0
	if mode == "run" then
		local rung = data.multiplier or 1
		local style = Tape.tier(rung)
		local entering = self.rung ~= nil and rung > self.rung
		if self.rung ~= rung then
			if self.rung and rung < self.rung and not self:_reduced() then
				self.pulse = {age = 0, strength = .20 + style.force * .8, drop = rung < self.rung}
			end
			self.rung = rung
			self.score.TextColor3 = style.accent:Lerp(Style.ink, .3)
			self.divider.BackgroundColor3 = style.accent
		end
		self.progress = math.clamp(data.progress or 0, 0, 1)
		self.rank:draw(rung, self.progress, entering)
		self:_drawTotal()
	elseif mode == "summary" then
		self.runLine.Text = "RUN SCORE " .. Tape.format(data.score)
		self.bestLine.Text = (if data.newBest then "NEW BEST " else "BEST ") .. Tape.format(data.best)
		self.bestLine.TextColor3 = if data.newBest then Tape.tier(4).accent else Style.secondary
	end
end

-- The engine banks once, before the view hears it. Delay only the *newly visible* points.
-- A grouped bend can include points already credited earlier; those stay on the readout.
function ScoreHudView:bankStart(points, id, latestScore)
	if self.mode ~= "run" then return end
	self.bankStarts += 1
	if self:_reduced() then return end
	local room = math.max(0, (latestScore or 0) - (self.data.score or 0) - self.reservedThisSnapshot)
	local debit = math.min(points, room)
	self.debits[id] = debit
	self.waiting += debit
	self.reservedThisSnapshot += debit
end

function ScoreHudView:bankCancel(id)
	local debit = self.debits[id] or 0
	self.waiting = math.max(0, self.waiting - debit)
	self.debits[id] = nil
	return debit
end

function ScoreHudView:absorb(points, id)
	if self.mode ~= "run" then return end
	self.absorbs += 1
	local deferred = self:bankCancel(id)
	if self:_reduced() then return end
	self.pulse = {age = 0, strength = .52 + Tape.tier(self.rung).force * .48, bank = true}
	local label = Tape.text("BankTransfer", self.panel, Style.numberFont, Tape.tier(self.rung).accent, math.round(16 * self.layout.textScale), 6)
	label.AnchorPoint = Vector2.new(.5,.5)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Size = UDim2.fromOffset(self.layout.scoreWidth + math.round(16 * self.layout.textScale), math.round(22 * self.layout.textScale))
	label.Text = "+" .. Tape.format(points)
	table.insert(self.transfers, {id = id, age = 0, deferred = deferred, remaining = deferred, label = label})
end

function ScoreHudView:_drawTotal()
	local concealed = self.waiting
	for _, entry in self.transfers do concealed += entry.remaining end
	local value = math.floor(math.max(0, (self.data.score or 0) - concealed))
	if self.shown ~= value then self.score.Text = Tape.format(value); self.shown = value end
end

function ScoreHudView:step(dt)
	if self.mode ~= "run" then return end
	if self.gui.Enabled then self.rank.art:step(dt, self:_reduced()) end
	if self:_reduced() then
		if self.pulse or #self.transfers > 0 or self.waiting > 0 then self:_resetEffects(); self:_drawTotal() end
		return
	end
	local l = self.layout
	local lead = l.scoreWidth + l.gap
	local center = Vector2.new(lead + l.width * .43, l.height * .5)
	local pulse = self.pulse
	if pulse then
		pulse.age += dt
		local t = math.min(1, pulse.age / impactDuration)
		local amplitude = (1 - t)^2 * pulse.strength
		local x = math.sin(t * 34) * amplitude * 4
		local y = math.sin(t * 17) * amplitude * (if pulse.drop then -5 else 6)
		self.rank.root.Position = UDim2.fromOffset(lead + x, y)
		for i, spark in self.sparks do
			spark.Visible = self.rung >= 3 and not pulse.drop and i <= math.min(5, self.rung - 1) and t < 1
			if spark.Visible then
				local at = center + streaks[i] * (.35 + .9 * t)
				spark.Position = UDim2.fromOffset(at.X, at.Y)
				spark.Size = UDim2.fromOffset(8 * (1 - t) + 2, 1)
				spark.BackgroundColor3 = Tape.tier(self.rung).accent
				spark.BackgroundTransparency = t
			end
		end
		if t == 1 then self.pulse = nil end
	end
	for i = #self.transfers, 1, -1 do
		local e = self.transfers[i]
		local previousAge = e.age
		e.age += dt
		if previousAge < flightDuration and e.age >= flightDuration and self.onBankArrival then
			self.onBankArrival(e.id)
		end
		local t = math.min(1, e.age / flightDuration)
		local arrival = math.clamp((e.age - flightDuration) / countDuration, 0, 1)
		local pos = center:Lerp(Vector2.new(l.scoreWidth * .67, l.height * .72), t)
		e.label.Position = UDim2.fromOffset(pos.X, pos.Y - math.sin(t * math.pi) * 12)
		e.label.TextTransparency = t^3
		e.label.TextStrokeTransparency = t^3
		e.remaining = e.deferred * (1 - arrival)^3
		if arrival > 0 then
			self.score.Position = UDim2.fromOffset(0, math.floor(l.height * .39) - 3 * math.sin(arrival * math.pi))
		end
		if arrival == 1 then e.label:Destroy(); table.remove(self.transfers, i) end
	end
	self:_drawTotal()
end

function ScoreHudView:show() self.gui.Enabled = self.mode ~= "hidden" end
function ScoreHudView:hide() self.gui.Enabled = false end

function ScoreHudView:setLayoutOffset(name, offset)
	self.offsets[name] = offset
	self:_layout()
end

function ScoreHudView:setFeedShift(shift)
	if self.feedShift == shift then return end
	self.feedShift = shift
	local l = self.layout
	local o = self.offsets.ScorePanel or Vector2.zero
	self.panel.Position = UDim2.fromOffset(l.x - l.scoreWidth - l.gap + o.X, l.y + o.Y + shift)
end

function ScoreHudView:describe()
	local active = false
	for _, d in self.gui:GetDescendants() do if d:IsA("GuiObject") and d.Active then active = true; break end end
	return {
		mode = self.mode, enabled = self.gui.Enabled, displayOrder = self.gui.DisplayOrder, panel = rect(self.panel),
		score = rect(self.score), scoreText = self.score.Text, multiplier = rect(self.rank.mult), multiplierText = self.rank.mult.Text,
		rank = rect(self.rank.root), rankText = Tape.tier(self.rung).name, progress = self.progress or 0, accent = Tape.tier(self.rung).accent,
		bar = rect(self.rank.bar), fill = rect(self.rank.fill), runLine = rect(self.runLine), runText = self.runLine.Text,
		bestLine = rect(self.bestLine), bestText = self.bestLine.Text, anyActive = active,
		bankStarts = self.bankStarts, absorbs = self.absorbs, pendingPoints = self.waiting, transferCount = #self.transfers,
		reducedMotion = self:_reduced(),
	}
end

function ScoreHudView:destroy()
	self.prefConn:Disconnect()
	self.gui:Destroy()
end

return ScoreHudView
