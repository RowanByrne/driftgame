--!nonstrict
-- CmdrController: the admin console's client half (docs/game/features/admin-console.md, T-159).
--
-- Requires Cmdr's client (`ReplicatedStorage.CmdrClient`, put there by `CmdrService`), sets
-- its key (`Config.Admin.ActivationKeys`, F2) and title, and shows it only to a player the
-- server has marked `CmdrAdmin`. That mark decides nothing on the server, which checks
-- every command itself (`CmdrService`); here it only keeps the window away from players who
-- could not use it.
--
-- Keyboard only: F2 opens and closes it. There is no gamepad or touch way in yet.
--
-- IT ALSO DOES WHAT ONLY THIS CLIENT CAN, for commands aimed at this player (`Act`): getting
-- out and in, the car's speed, the run's score. The caller's own client does it directly when
-- they target only themselves; when an admin targets someone else, the server sends the
-- target's client a `DriftAction` event, after the server's own check.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CmdrController = {}
CmdrController.Priority = 0

local ADMIN_ATTRIBUTE = "CmdrAdmin" -- set by CmdrService
local WAIT_SECONDS = 30

local function admin(): boolean
	return Players.LocalPlayer:GetAttribute(ADMIN_ATTRIBUTE) == true
end

function CmdrController:Init()
	self.Cmdr = nil
	self.actions = 0 -- actions done for a command that targeted this player
	self.lastAction = nil
end

local function controller(name: string)
	return require(script.Parent:WaitForChild(name))
end

local SPEED_LIMIT = 1000 -- studs/s either way

-- THE THINGS ONLY THIS CLIENT CAN DO TO ITS OWN CAR AND SCORE, for the console: run here when
-- the caller targets themselves, and on a target's client when an admin targets them. Each
-- returns its reply. Writes only the state the controllers hand out (`CurrentState`,
-- `ScoreController.score`) and asks through their own requests (`RequestExit`/`RequestEnter`).
local ACTIONS = {}

function ACTIONS.getOut(): string
	local ok, why = controller("CarEntryController"):RequestExit()
	return if ok then "Getting out." else `Not out: {tostring(why)}.`
end

function ACTIONS.getIn(): string
	local ok, why = controller("CarEntryController"):RequestEnter()
	return if ok then "Getting in." else `Not in: {tostring(why)}.`
end

function ACTIONS.speed(speed: any): string
	local drift = controller("DriftController")
	local state = drift:CurrentState()
	if not state then
		return "No car."
	end
	local Model = require(script.Parent.Parent:WaitForChild("Drift"):WaitForChild("Model"))
	if speed == nil then
		return `Speed {string.format("%.1f", Model.speed(state))} studs/s.`
	end
	if type(speed) ~= "number" or speed ~= speed or math.abs(speed) > SPEED_LIMIT then
		return `Speed is -{SPEED_LIMIT} to {SPEED_LIMIT} studs/s.`
	end
	if not drift:IsDriving() then
		return "Not driving: get in first."
	end
	-- The state CurrentState() hands out is the simulation's own: velocity is the one thing
	-- the model moves, and every other speed is read off it each step.
	local forward = Model.axes(state.yaw)
	state.velocity = forward * speed + Vector3.yAxis * state.velocity.Y
	return `Speed set to {speed} studs/s.`
end

function ACTIONS.scoreSet(points: any, multiplier: any): string
	if type(points) ~= "number" or points ~= points or points < 0 or points > 1e12 then
		return "The score is 0 or more."
	end
	local score = controller("ScoreController").score
	score.score = points
	if type(multiplier) == "number" and multiplier == multiplier then
		score.multiplier = math.clamp(math.floor(multiplier), 1, Config.Score.MaxMultiplier)
		score.peakMultiplier = math.max(score.peakMultiplier, score.multiplier)
		score.progress = 0
	end
	return `Score {math.floor(score.score)}, x{score.multiplier}.`
end

function ACTIONS.scoreReset(): string
	local score = controller("ScoreController").score
	score:Reset()
	return `Score 0, x1. Best {math.floor(score.best)}.`
end

-- Do one of the actions above on this client; returns its reply.
function CmdrController:Act(action: string, ...): string
	local fn = ACTIONS[action]
	if not fn then
		return `No action '{tostring(action)}'.`
	end
	return fn(...)
end

-- Whether a command's target list is just this player (or left out): then it runs here.
function CmdrController.onlyMe(players: { Player }?): boolean
	return players == nil or #players == 0 or (#players == 1 and players[1] == Players.LocalPlayer)
end

function CmdrController:Start()
	local root = ReplicatedStorage:WaitForChild("CmdrClient", WAIT_SECONDS)
	if not root then
		warn("[CmdrController] ReplicatedStorage.CmdrClient never appeared: is CmdrService running?")
		return
	end
	local CmdrClient = require(root)
	self.Cmdr = CmdrClient

	CmdrClient:SetActivationKeys(Config.Admin.ActivationKeys)
	CmdrClient:SetPlaceName(Config.Admin.PlaceName)
	CmdrClient:SetActivationUnlocksMouse(true)

	-- Commands that run on this client (the sky, the score panel, the readout) are held to
	-- the same answer the server gives; commands that run on the server are checked there
	-- again, and that check is the one that counts.
	CmdrClient.Registry:RegisterHook("BeforeRun", function()
		if not admin() then
			return "You can't use the admin console here."
		end
		return nil
	end)

	-- A command an admin ran with this player as its target, for something only this client
	-- can do (`Ops.sendAction` on the server). It comes from the server, after the server's
	-- check, so it is done whether or not this player is an admin themselves.
	CmdrClient:HandleEvent("DriftAction", function(action: any, ...)
		if type(action) ~= "string" then
			return
		end
		local ok, reply = pcall(self.Act, self, action, ...)
		self.lastAction = { action = action, reply = if ok then reply else "failed: " .. tostring(reply), at = os.clock() }
		self.actions += 1
	end)

	local function sync()
		CmdrClient:SetEnabled(admin())
	end
	Players.LocalPlayer:GetAttributeChangedSignal(ADMIN_ATTRIBUTE):Connect(sync)
	sync()
end

-- Run a command as this player, exactly as typing it does, and return Cmdr's reply. Lines a
-- command prints with `context:Reply` go to the window, not into the reply.
function CmdrController:Run(text: string): string
	assert(self.Cmdr, "Cmdr is not loaded")
	return self.Cmdr.Dispatcher:EvaluateAndRun(text)
end

function CmdrController:Show()
	if self.Cmdr then
		self.Cmdr:Show()
	end
end

function CmdrController:Hide()
	if self.Cmdr then
		self.Cmdr:Hide()
	end
end

function CmdrController:DebugState()
	local cmdr = self.Cmdr
	if not cmdr then
		return { loaded = false, admin = admin(), actions = self.actions, lastAction = self.lastAction }
	end
	local names = cmdr.Registry:GetCommandNames()
	table.sort(names)
	return {
		loaded = true,
		admin = admin(),
		enabled = cmdr._enabled,
		visible = cmdr._interface.Window:IsVisible(),
		keys = cmdr._activationKeys,
		commands = #names,
		names = names,
		actions = self.actions,
		lastAction = self.lastAction,
		gui = cmdr.Gui and cmdr.Gui:GetFullName() or nil,
	}
end

return CmdrController
