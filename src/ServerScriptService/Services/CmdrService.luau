--!nonstrict
-- CmdrService: the admin console's server half (docs/game/features/admin-console.md, T-159).
--
-- Cmdr is vendored at `ServerStorage.Cmdr` (ARCHITECTURE.md "Vendored libraries"). This
-- service requires it, registers the game's commands and types from
-- `ServerScriptService.AdminConsole`, and guards every command with a BeforeRun hook.
--
-- WHO MAY RUN A COMMAND IS DECIDED HERE, ON THE SERVER, EVERY TIME. Everyone in Studio; on a
-- live server only the game's owner (the user, or the owner of the owning group) and the
-- user ids in `Config.Admin.UserIds`. Nothing the client says is read as permission: the
-- `CmdrAdmin` attribute this sets on each player only tells their client whether to show the
-- window, and a client that flips it on for itself gets a window whose every command the
-- server refuses. Commands that act only on the client's own view (the sky, the score
-- panel) run there behind the same answer, which is all a client can ever be held to.
--
-- RATE-LIMITED PER USERID (`Config.Admin.PerSecond` / `PerMinute`), kept across rejoins.
--
-- Cmdr makes its own two remotes, `ReplicatedStorage.CmdrClient.CmdrEvent` and
-- `CmdrFunction`, when it is required; they are its, not `Net`'s (CONTRACTS.md "Remotes").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CmdrService = {}
CmdrService.Priority = 0 -- reads other services only when a command runs

-- The attribute a client reads to show the console or not. Grants nothing.
CmdrService.ADMIN_ATTRIBUTE = "CmdrAdmin"

-- Cmdr's built-in commands kept: help and its utilities, and its debug group. Its admin
-- group (kick, ban, kill, teleport, respawn...) acts on characters and the Roblox ban API,
-- and this game's car and avatar are not that; `fetch` makes the server call any URL, and
-- `blink` and `thru` move the character off its seat.
local BUILT_IN_GROUPS = { Help = true, DefaultUtil = true, DefaultDebug = true }
local BUILT_IN_SKIPPED = { fetch = true, blink = true, thru = true }

local LOG_KEEP = 50

--------------------------------------------------------------------------------
-- The two rules, pure, so the tests can ask them with any context
--------------------------------------------------------------------------------

export type AccessContext = {
	studio: boolean, -- RunService:IsStudio()
	creatorType: string, -- "User" or "Group" (game.CreatorType.Name)
	creatorId: number, -- game.CreatorId
	groupRank: number?, -- the player's rank in the owning group, when it is a group
	admins: { number }, -- Config.Admin.UserIds
}

-- May this user run commands? Returns the answer and why.
function CmdrService.allowed(userId: number, ctx: AccessContext): (boolean, string)
	if ctx.studio then
		return true, "studio"
	end
	if type(userId) ~= "number" or userId <= 0 then
		return false, "not a player"
	end
	if ctx.creatorType == "User" and ctx.creatorId == userId then
		return true, "owner"
	end
	if ctx.creatorType == "Group" and ctx.groupRank == 255 then
		return true, "group owner"
	end
	for _, id in ctx.admins or {} do
		if id == userId then
			return true, "admin list"
		end
	end
	return false, "not an admin"
end

-- One more command from a user whose limit is `entry` (made fresh when nil). Returns
-- whether it may run, and the entry to keep. Two windows: a second and a minute.
function CmdrService.rate(entry: any?, now: number, perSecond: number, perMinute: number): (boolean, any)
	entry = entry or { second = now, inSecond = 0, minute = now, inMinute = 0 }
	if now - entry.second >= 1 then
		entry.second = now
		entry.inSecond = 0
	end
	if now - entry.minute >= 60 then
		entry.minute = now
		entry.inMinute = 0
	end
	if entry.inSecond >= perSecond or entry.inMinute >= perMinute then
		return false, entry
	end
	entry.inSecond += 1
	entry.inMinute += 1
	return true, entry
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CmdrService:Init()
	self.ranks = {} -- userId -> rank in the owning group (live, group-owned games only)
	self.limits = {} -- userId -> rate entry, kept across rejoins
	self.counts = { ran = 0, refused = 0, limited = 0 }
	self.log = {} -- the last LOG_KEEP commands: { userId, text, at, ok, why }

	-- Requiring Cmdr makes its remotes and moves `CmdrClient` into ReplicatedStorage.
	local module = ServerStorage:FindFirstChild("Cmdr")
	if not module or not module:IsA("ModuleScript") then
		warn("[CmdrService] ServerStorage.Cmdr is missing: there is no admin console")
		return
	end
	local Cmdr = require(module)
	self.Cmdr = Cmdr

	local console = ServerScriptService:FindFirstChild("AdminConsole")
	if not console then
		warn("[CmdrService] ServerScriptService.AdminConsole is missing: only Cmdr's own commands are registered")
	end

	Cmdr.Registry:RegisterHook("BeforeRun", function(context)
		return self:_beforeRun(context)
	end)

	Cmdr.Registry:RegisterDefaultCommands(function(command)
		return BUILT_IN_GROUPS[command.Group] == true and not BUILT_IN_SKIPPED[command.Name]
	end)
	if console then
		local types = console:FindFirstChild("Types")
		if types then
			Cmdr.Registry:RegisterTypesIn(types)
		end
		local commands = console:FindFirstChild("Commands")
		if commands then
			Cmdr.Registry:RegisterCommandsIn(commands)
		end
	end
end

function CmdrService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_mark(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.ranks[player.UserId] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._mark, self, player)
	end
end

--------------------------------------------------------------------------------
-- The check
--------------------------------------------------------------------------------

-- The context for a real player on this server. Asks Roblox for their group rank once, when
-- the game is group-owned and live; a failed ask is "no rank", never "owner".
function CmdrService:_context(player: Player): AccessContext
	local studio = RunService:IsStudio()
	local creatorType = game.CreatorType.Name
	local rank = nil
	if not studio and creatorType == "Group" then
		rank = self.ranks[player.UserId]
		if rank == nil then
			local ok, got = pcall(player.GetRankInGroup, player, game.CreatorId)
			rank = if ok and type(got) == "number" then got else 0
			self.ranks[player.UserId] = rank
		end
	end
	return {
		studio = studio,
		creatorType = creatorType,
		creatorId = game.CreatorId,
		groupRank = rank,
		admins = Config.Admin.UserIds,
	}
end

-- May this player use the console? The answer and why.
function CmdrService:Allowed(player: Player): (boolean, string)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "not a player"
	end
	return CmdrService.allowed(player.UserId, self:_context(player))
end

function CmdrService:_mark(player: Player)
	local ok = self:Allowed(player)
	if player.Parent then
		player:SetAttribute(CmdrService.ADMIN_ATTRIBUTE, ok)
	end
end

function CmdrService:_remember(player: Player?, text: string, ok: boolean, why: string)
	table.insert(self.log, {
		userId = player and player.UserId or 0,
		text = string.sub(tostring(text), 1, 200),
		at = os.clock(),
		ok = ok,
		why = why,
	})
	while #self.log > LOG_KEEP do
		table.remove(self.log, 1)
	end
end

-- Cmdr's BeforeRun hook: nil lets the command run, a string refuses it with that reply.
function CmdrService:_beforeRun(context): string?
	local player = context.Executor
	local ok, why = self:Allowed(player)
	if not ok then
		self.counts.refused += 1
		self:_remember(player, context.RawText, false, why)
		return "You can't use the admin console here."
	end
	local fine, entry = CmdrService.rate(
		self.limits[player.UserId],
		os.clock(),
		Config.Admin.PerSecond,
		Config.Admin.PerMinute
	)
	self.limits[player.UserId] = entry
	if not fine then
		self.counts.limited += 1
		self:_remember(player, context.RawText, false, "rate")
		return "Slow down: too many commands. Try again in a moment."
	end
	self.counts.ran += 1
	self:_remember(player, context.RawText, true, why)
	return nil
end

--------------------------------------------------------------------------------
-- Studio and tests
--------------------------------------------------------------------------------

function CmdrService:DebugState()
	local names = {}
	if self.Cmdr then
		names = self.Cmdr.Registry:GetCommandNames()
		table.sort(names)
	end
	return {
		commands = #names,
		names = names,
		counts = table.clone(self.counts),
		log = self.log,
		admins = table.clone(Config.Admin.UserIds),
	}
end

-- Studio only: run a command as a player on the server, through the hook, as the remote
-- does. Server commands only: one that runs on the client answers "No implementation."
function CmdrService:DebugRun(text: string, userId: number?): string
	assert(RunService:IsStudio(), "DebugRun is Studio only")
	assert(self.Cmdr, "Cmdr did not load")
	for _, player in Players:GetPlayers() do
		if userId == nil or player.UserId == userId then
			return self.Cmdr.Dispatcher:EvaluateAndRun(text, player)
		end
	end
	return "no player"
end

-- Studio only: forget the rate limits, so a test that runs fifty commands isn't measuring
-- the limit.
function CmdrService:DebugClearLimits()
	assert(RunService:IsStudio(), "DebugClearLimits is Studio only")
	table.clear(self.limits)
	return true
end

return CmdrService
