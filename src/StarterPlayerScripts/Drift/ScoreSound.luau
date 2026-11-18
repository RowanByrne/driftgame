--!nonstrict
-- Local score presentation only. Each source stays resident, so a late load can never
-- play an old event during the next bank or run.
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
		voices = {}, seen = {}, banks = setmetatable({}, {__mode = "k"}),
		played = {}, nextTick = 0, quiet = QuietPlay.isQuiet(),
	}, ScoreSound)
	local preload = {}
	for name, source in Config.Sources do
		local pool = {}
		for i = 1, source.Voices do
			local sound = Instance.new("Sound")
			sound.Name = "ScoreUI_" .. name .. i
			sound.SoundId = source.Id
			sound.PlaybackRegionsEnabled = true
			SoundLevels.apply(sound, "ScoreUI")
			sound.Parent = SoundService
			table.insert(pool, {sound = sound, started = 0})
		end
		self.voices[name] = pool
		table.insert(preload, pool[1].sound)
	end
	task.spawn(function() pcall(function() ContentProvider:PreloadAsync(preload) end) end)
	return self
end

-- If all voices are busy, replace the oldest non-impact in this source's pool.
function ScoreSound:_play(name, bank)
	local cue = Config.Cues[name]
	local pool = self.voices[cue.Source]
	local chosen = nil
	for _, voice in pool do
		if not voice.sound.IsLoaded then continue end
		if not voice.sound.IsPlaying then chosen = voice; break end
		if voice.cue ~= "bankImpact" and (not chosen or voice.started < chosen.started) then
			chosen = voice
		end
	end
	if not chosen or SoundLevels.get("ScoreUI") == 0 then return end
	local now = os.clock()
	if name == "event" then
		if now < self.nextTick then return end
		self.nextTick = now + Config.TickInterval
	elseif name == "bankImpact" then
		self.voices.Hover[1].sound:Stop()
		self.nextTick = now + Config.TickInterval
	end
	local sound = chosen.sound
	sound:Stop()
	chosen.started, chosen.cue, chosen.bank = now, name, bank
	sound.PlaybackRegion = cue.Region
	sound.PlaybackSpeed = cue.Speed
	sound.Volume = if self.quiet then 0 else Config.Volume * Config.Sources[cue.Source].Gain * cue.Gain
	sound.TimePosition = cue.Region.Min
	sound:Play()
	self.played[name] = (self.played[name] or 0) + 1
end

-- Called after the live engine's entry has reached the feed. Keep its identity after
-- the visible row fades, so a repeated terminal snapshot cannot turn into a new tick.
function ScoreSound:entry(entry, audible)
	local id = entry.id
	if id == nil or entry.notice then return end
	local previous = self.seen[id]
	if previous and previous ~= "live" then return end
	self.seen[id] = entry.state
	if previous or not audible then return end
	if entry.state == "live" then
		self:_play("hold_open")
	elseif entry.state == "banked" and entry.points > 0 then
		self:_play("event")
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
	if self.seen[line.ids[1]] ~= "live" then return end
	self.banks[line] = "winding"
	if not reduced then self:_play("windup", line) end
end

function ScoreSound:cancel(line)
	self.banks[line] = nil
	for _, voice in self.voices.Tape do
		if voice.bank == line and voice.cue == "windup" then
			voice.sound:Stop()
			voice.bank = nil
		end
	end
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
	self.rung, self.nextTick = nil, 0
	table.clear(self.banks)
	if newRun then table.clear(self.seen) end
	for _, pool in self.voices do
		for _, voice in pool do
			voice.sound:Stop()
			voice.bank = nil
		end
	end
end

return ScoreSound
