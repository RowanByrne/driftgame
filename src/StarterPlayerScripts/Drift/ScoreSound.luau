--!nonstrict
-- Local score presentation. All voices share the approved Redline Bonus sheet.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local SoundService = game:GetService("SoundService")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config).Fx.ScoreUI
local QuietPlay = require(ReplicatedFirst:WaitForChild("QuietPlay"))
local SoundLevels = require(script.Parent.SoundLevels)

local ScoreSound = {}
ScoreSound.__index = ScoreSound

function ScoreSound.new()
	local self = setmetatable({
		voices = {}, seen = {}, points = {}, banks = setmetatable({}, {__mode = "k"}),
		played = {}, nextTick = 0, nextCount = 0, countStep = 1, quiet = QuietPlay.isQuiet(),
	}, ScoreSound)
	for i = 1, Config.Voices do
		local sound = Instance.new("Sound")
		sound.Name = "ScoreUI_Redline" .. i
		sound.SoundId = Config.SoundId
		sound.PlaybackRegionsEnabled = true
		SoundLevels.apply(sound, "ScoreUI")
		sound.Parent = SoundService
		table.insert(self.voices, {sound = sound, started = 0})
	end
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({self.voices[1].sound}) end)
	end)
	return self
end

function ScoreSound:_stop(cue, owner)
	for _, voice in self.voices do
		if voice.cue == cue and (owner == nil or owner == voice.owner) then
			voice.sound:Stop()
			voice.cue, voice.owner = nil, nil
		end
	end
end

function ScoreSound:_play(name, owner, region)
	if SoundLevels.get("ScoreUI") == 0 then return false end
	local now = os.clock()
	if name == "event" and now < self.nextTick then return false end
	if name == "bankImpact" then
		self:_stop("event")
		self:_stop("accumulate")
		self.nextTick = now + Config.TickInterval
		self.nextCount = math.max(self.nextCount, now + Config.CountInterval)
	end
	local chosen
	local incidental = name == "event" or name == "accumulate"
	for _, voice in self.voices do
		if not voice.sound.IsLoaded then continue end
		if not voice.sound.IsPlaying then chosen = voice; break end
		if not incidental and voice.cue ~= "bankImpact" and (not chosen or voice.started < chosen.started) then
			chosen = voice
		end
	end
	if not chosen then return false end
	if name == "event" then self.nextTick = now + Config.TickInterval end
	local sound = chosen.sound
	region = region or Config.Cues[name]
	sound:Stop()
	chosen.started, chosen.cue, chosen.owner = now, name, owner
	sound.PlaybackRegion = region
	sound.Volume = if self.quiet then 0 else Config.Volume
	sound.TimePosition = region.Min
	sound:Play()
	self.played[name] = (self.played[name] or 0) + 1
	return true
end

-- All growing lines advance one musical phrase. A note is triggered only by a
-- new visible point total. Missed beats during a stall never queue a catch-up.
function ScoreSound:_count(id, now)
	if now < self.nextCount then return end
	if not self:_play("accumulate", id, Config.CountPhrase[self.countStep]) then return end
	self.countStep = self.countStep % #Config.CountPhrase + 1
	-- Feed updates arrive on simulation frames. Carry the beat through small
	-- delays; after a pause, start a fresh beat at the new increase.
	local beat = Config.CountInterval
	self.nextCount = if now - self.nextCount <= beat / 4 then self.nextCount + beat else now + beat
end

function ScoreSound:entry(entry, audible)
	local id = entry.id
	if id == nil or entry.notice then return end
	local previous = self.seen[id]
	if previous and previous ~= "live" then return end
	self.seen[id] = entry.state
	if entry.state == "live" then
		local points = math.round(entry.points or 0)
		local last = self.points[id]
		local now = os.clock()
		if last == nil and next(self.points) == nil then
			self.countStep = 1
			self.nextCount = math.max(self.nextCount, now + Config.CountInterval)
		end
		self.points[id] = points
		if audible then
			if not previous then self:_play("hold_open", id)
			elseif last ~= nil and points > last then self:_count(id, now) end
		end
	else
		self.points[id] = nil
		self:_stop("accumulate", id)
		self:_stop("hold_open", id)
		if audible and not previous and entry.state == "banked" and entry.points > 0 then
			self:_play("event")
		end
	end
end

function ScoreSound:rank(rung)
	local previous = self.rung
	self.rung = rung
	if not rung or not previous or previous == rung then return end
	if rung < previous then self:_play("rankDrop")
	elseif rung >= Config.HighRank then self:_play("rankHigh")
	else self:_play("rankLow") end
end

function ScoreSound:bankStart(line, reduced)
	local id = line.ids[1]
	if self.seen[id] ~= "live" then return end
	self:_stop("accumulate", id)
	self:_stop("hold_open", id)
	self.banks[line] = "winding"
	if not reduced then self:_play("windup", line) end
end

function ScoreSound:cancel(line)
	self.banks[line] = nil
	self:_stop("windup", line)
end

function ScoreSound:impact(line, reduced)
	if self.banks[line] ~= "winding" then return end
	self:cancel(line)
	if not reduced then self.banks[line] = "flying" end
	self:_play("bankImpact")
end

function ScoreSound:arrive(line)
	if self.banks[line] ~= "flying" then return end
	self.banks[line] = nil
	self:_play("score_receipt")
end

function ScoreSound:reset(newRun)
	self.rung, self.nextTick, self.nextCount, self.countStep = nil, 0, 0, 1
	table.clear(self.banks)
	table.clear(self.points)
	if newRun then table.clear(self.seen) end
	for _, voice in self.voices do
		voice.sound:Stop()
		voice.cue, voice.owner = nil, nil
	end
end

return ScoreSound
