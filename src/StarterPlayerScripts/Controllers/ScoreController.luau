--!nonstrict
-- ScoreController: the endless run's score, on the client (docs/game/features/endless-score.md).
--
-- The arithmetic is `Drift/Score`; this is only its wiring. It holds one `Score`, hears
-- from the server when this player's run starts and ends (`RoadRun`, the same answer the
-- run button paints itself from), and while a run is on steps the score once per
-- simulation step of the player's own car (`DriftController:OnStep`).
--
-- ALL ON THE CLIENT, ON PURPOSE (the spec's "Server and client"). The car is driven here,
-- so the slip and the speed are here already, and nothing about the score is saved, shared
-- or rewarded, so there is nothing yet for the server to trust. The day a score is saved or
-- ranked, the server receives it at the run's end and bounds it; until then no remote
-- carries it, and nothing on the server reads it.
--
-- THE CLIENT IS TOLD WHEN A RUN IS ON, it never decides. A run starts when the server's
-- answer first says `inRun`, and that is when the score goes back to 0; it ends when an
-- answer first says it is not, and the score freezes there as the run's result. A press
-- the server refuses moves nothing.
--
-- THE PANEL IS `Drift/ScoreHudView`, fed from `View()` once a frame: the live run, then the
-- run's result for `Config.Score.SummarySeconds` after END RUN, then nothing.
--
-- THE FEED IS `Drift/ScoreFeedView` (features/score-events.md "UI"): each entry the score
-- events engine fires on `ScoreEvents.feed` goes straight to it. The engine is required only
-- if it is there, so the feed shows nothing in a build without it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local Score = require(DriftFolder.Score)
local ScoreHudView = require(DriftFolder.ScoreHudView)
local ScoreFeedView = require(DriftFolder.ScoreFeedView)

local DriftController = require(script.Parent.DriftController)

local ScoreController = {}

ScoreController.Priority = 0 -- after DriftController (10): its step list exists by Start

function ScoreController:Init()
	self.score = Score.new()
	self.inRun = false
	self.runs = 0 -- runs started this session
	self.steps = 0 -- steps scored this run, for tests
	self.runSeconds = 0 -- simulated seconds this run
	-- The run that just ended, as `Score:Get()` read it at the end, and when (os.clock).
	-- Nil until a run has ended. What the summary shows.
	self.lastRun = nil
	self.endedAt = nil
	self.answers = 0
end

function ScoreController:Start()
	DriftController:OnStep(function(dt, state)
		if self.inRun then
			self.score:Step(dt, state)
			self.steps += 1
			self.runSeconds += dt
		end
	end)

	DriftController:SetReadoutScore(function()
		local r = self.score:Get()
		r.inRun = self.inRun
		return r
	end)

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.playerGui = playerGui
	self.view = ScoreHudView.new(playerGui)
	self.feedView = ScoreFeedView.new(playerGui)
	self.feedEntries = 0 -- entries heard from the engine this session
	RunService.RenderStepped:Connect(function(dt)
		self.view:setData(self.fixture or self:Snapshot())
		self.feedView:step(dt)
	end)
	self:_listenToEvents()

	local roadRun = Net.event("RoadRun")
	roadRun.OnClientEvent:Connect(function(answer)
		if type(answer) ~= "table" then
			return
		end
		self.answers += 1
		self:_setInRun(answer.inRun == true)
	end)
end

-- The score events engine's feed, if the engine is in this build (a guarded require: the
-- feed is built before the engine and must stand without it).
function ScoreController:_listenToEvents()
	local module = DriftFolder:FindFirstChild("ScoreEvents")
	if not (module and module:IsA("ModuleScript")) then
		self.feedSource = "none"
		return
	end
	local ok, ScoreEvents = pcall(require, module)
	local feed = ok and type(ScoreEvents) == "table" and ScoreEvents.feed
	if not (feed and feed.Connect) then
		self.feedSource = if ok then "no feed" else `failed: {ScoreEvents}`
		warn(`ScoreController: the score feed is off ({self.feedSource})`)
		return
	end
	self.feedSource = "ScoreEvents"
	feed:Connect(function(entry)
		self.feedEntries += 1
		if not self.feedFixture then
			self.feedView:push(entry)
		end
	end)
end

function ScoreController:_setInRun(inRun: boolean)
	if inRun == self.inRun then
		return
	end
	if inRun then
		self.score:Reset()
		if not self.feedFixture then
			self.feedView:clear()
		end
		self.runs += 1
		self.steps = 0
		self.runSeconds = 0
		self.lastRun = nil
		self.endedAt = nil
	else
		-- Read before anything folds this run into the best: `score.best` is still the best
		-- of the runs BEFORE this one, which is what "a new best" is measured against.
		local previousBest = self.score.best
		self.lastRun = self.score:Get()
		self.lastRun.runSeconds = self.runSeconds
		self.lastRun.newBest = self.lastRun.score >= 1 and self.lastRun.score > previousBest
		self.endedAt = os.clock()
	end
	self.inRun = inRun
end

-- What the score panel draws (T-119 step 2): the live run, or the summary of the one that
-- just ended while it is still showing, or nothing.
--   { mode = "run", reading } | { mode = "summary", reading } | { mode = "hidden" }
function ScoreController:View()
	if self.inRun then
		return { mode = "run", reading = self.score:Get() }
	end
	if self.lastRun and self.endedAt and os.clock() - self.endedAt < Config.Score.SummarySeconds then
		return { mode = "summary", reading = self.lastRun }
	end
	return { mode = "hidden" }
end

-- `View()` as the panel's snapshot (`ScoreHudView:setData`).
function ScoreController:Snapshot()
	local v = self:View()
	local r = v.reading
	if v.mode == "run" then
		return {
			mode = "run",
			score = r.score,
			multiplier = r.multiplier,
			progress = r.progress,
			maxMultiplier = Config.Score.MaxMultiplier,
		}
	elseif v.mode == "summary" then
		return { mode = "summary", score = r.score, best = r.best, newBest = r.newBest == true }
	end
	return { mode = "hidden" }
end

-- The panel's pieces as drawn: rects, texts, whether anything in it could take a touch.
function ScoreController:DebugView()
	return self.view and self.view:describe() or nil
end

-- Studio only: draw the panel from a fixture (`Drift/ScoreHudView.fixtures`) for measuring,
-- or `nil` to hand it back to the live score.
function ScoreController:DebugFixture(name: string?)
	if not RunService:IsStudio() then
		return nil
	end
	if name == nil then
		self.fixture = nil
		return self:DebugView()
	end
	local fixtures = require(DriftFolder:WaitForChild("ScoreHudView.fixtures"))
	self.fixture = fixtures[name]
	assert(self.fixture, `no fixture '{name}'`)
	self.view:setData(self.fixture)
	return self:DebugView()
end

-- The feed's lines as drawn: rects, texts, states (`ScoreFeedView:describe`).
function ScoreController:DebugFeed()
	local d = self.feedView and self.feedView:describe() or nil
	if d then
		d.source = self.feedSource
		d.entriesHeard = self.feedEntries
		d.fixture = self.feedFixture
	end
	return d
end

-- Studio only: play a feed fixture (`Drift/ScoreFeedView.fixtures`): a still picture at
-- once, or a timed script as the engine would fire it. While one plays the engine's entries
-- are ignored; `nil` clears the feed and hands it back.
function ScoreController:DebugFeedFixture(name: string?)
	if not RunService:IsStudio() then
		return nil
	end
	self.feedToken = (self.feedToken or 0) + 1
	local token = self.feedToken
	self.feedView:clear()
	if name == nil then
		self.feedFixture = nil
		return self:DebugFeed()
	end
	local fixtures = require(DriftFolder:WaitForChild("ScoreFeedView.fixtures"))
	local fixture = fixtures[name]
	assert(fixture, `no feed fixture '{name}'`)
	self.feedFixture = name
	if fixture.script then
		for _, entry in fixture.script do
			task.delay(entry.at or 0, function()
				if self.feedToken == token then
					self.feedView:push(entry)
				end
			end)
		end
	else
		self.feedView:setData(fixture)
	end
	return self:DebugFeed()
end

-- Studio only: Reduced Motion forced on or off for the feed, `nil` to follow the setting.
function ScoreController:DebugFeedMotion(reduced: boolean?)
	if not RunService:IsStudio() then
		return nil
	end
	self.feedView:setReducedMotion(reduced)
	return self:DebugFeed()
end

-- Studio only: drag mode for the feed (UI.md "Move things now"), to try it elsewhere.
-- Returns the export: each moved piece's distance from its nearest corner.
function ScoreController:DebugFeedDrag(on: boolean)
	if not RunService:IsStudio() then
		return nil
	end
	if not self.feedDrag then
		local UI = script.Parent.Parent:WaitForChild("UI")
		local LayoutDrag = require(UI:WaitForChild("Dev"):WaitForChild("LayoutDrag"))
		self.feedDrag = LayoutDrag.new({ view = self.feedView, parent = self.playerGui })
	end
	self.feedDrag:setEnabled(on == true)
	return self.feedDrag:export()
end

-- The live score, for tests and agent playtests:
--   game.Players.LocalPlayer.PlayerScripts.DebugBridge:Invoke("ScoreController", "DebugState")
function ScoreController:DebugState()
	local r = self.score:Get()
	r.inRun = self.inRun
	r.runs = self.runs
	r.steps = self.steps
	r.runSeconds = self.runSeconds
	r.answers = self.answers
	r.lastRun = self.lastRun
	r.view = self:View().mode
	return r
end

return ScoreController
