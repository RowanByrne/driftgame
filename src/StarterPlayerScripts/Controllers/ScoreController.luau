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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local Score = require(DriftFolder.Score)

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

	local roadRun = Net.event("RoadRun")
	roadRun.OnClientEvent:Connect(function(answer)
		if type(answer) ~= "table" then
			return
		end
		self.answers += 1
		self:_setInRun(answer.inRun == true)
	end)
end

function ScoreController:_setInRun(inRun: boolean)
	if inRun == self.inRun then
		return
	end
	if inRun then
		self.score:Reset()
		self.runs += 1
		self.steps = 0
		self.runSeconds = 0
		self.lastRun = nil
		self.endedAt = nil
	else
		self.lastRun = self.score:Get()
		self.lastRun.runSeconds = self.runSeconds
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
