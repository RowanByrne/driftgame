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
		return { loaded = false, admin = admin() }
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
		gui = cmdr.Gui and cmdr.Gui:GetFullName() or nil,
	}
end

return CmdrController
