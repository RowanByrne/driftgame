--!nonstrict
-- CustomizationService: fitting parts and paint to a player's car, on the server
-- (docs/game/features/car-customization.md, CONTRACTS.md "Customization", T-101).
--
-- THE SERVER DECIDES WHAT A CAR IS. A client asks to fit one part, or to set some paint,
-- over `CustomizeFit`; this checks the ask against the catalog (`Shared/Customization`,
-- the same module the client's menu is drawn from), records the new build with
-- `GarageService` (which owns the dev store and writes it behind the player), publishes it
-- on the player's car as attributes so every client can draw it, and answers.
--
-- WHAT IT DOES NOT DO, deliberately: draw anything (T-104, T-105), open a menu (T-103), or
-- move the car's numbers (T-106). `Customization.resolve` says what a build implies; the
-- step that applies it is somebody else's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Customization = require(ReplicatedStorage.Shared.Customization)
local Net = require(ReplicatedStorage.Shared.Net)

local GarageService = require(ServerScriptService.Services.GarageService)

local CustomizationService = {}

CustomizationService.Priority = 35 -- after GarageService (40), whose signal this listens to

local CARS_FOLDER = "Cars" -- `Workspace.Cars`, made by CarService (CONTRACTS.md "Paths")

function CustomizationService:Init()
	self.fitRemote = Net.event("CustomizeFit") -- both ways: the client asks, the server answers
	self.limits = {} -- userId -> { at, count }, keyed by UserId so a rejoin does not reset it
	self.asks = 0 -- every ask that reached the checks, questions included
	self.questions = 0
	self.fits = 0
	self.refused = 0
	self.flooded = 0 -- dropped by the rate limit, unanswered
	self.reasons = {} -- reason -> how many refusals gave it
	self.published = 0 -- attribute writes onto a car
end

function CustomizationService:Start()
	GarageService.BuildLoaded:Connect(function(userId, player)
		self:_publishFor(userId)
		self:_answer(player, true, nil, nil)
	end)

	self.fitRemote.OnServerEvent:Connect(function(player, category, choice)
		-- Two values are read and nothing else: extra arguments never reach anything.
		self:_onFit(player, category, choice)
	end)

	-- Every car that appears gets its player's build, so a spawn, a respawn rebuild or a
	-- car switch is drawn right from its first frame. CarService names and attributes the
	-- car before parenting it, so `UserId` is already there when it lands.
	local folder = Workspace:FindFirstChild(CARS_FOLDER) or Workspace:WaitForChild(CARS_FOLDER, 30)
	if folder then
		folder.ChildAdded:Connect(function(car)
			self:_carAdded(car)
		end)
		for _, car in folder:GetChildren() do
			self:_carAdded(car)
		end
	else
		warn("[CustomizationService] Workspace.Cars never appeared; builds will not be drawn on cars")
	end
end

-- ---------------------------------------------------------------- builds

-- The archetype the server says this player is in (CarService's, via GarageService).
function CustomizationService:_carKeyOf(userId: number): string
	return GarageService:_carKeyOf(userId)
end

-- What the server believes this player's car is built as: their saved build, or the
-- stock car on the archetype they are in.
function CustomizationService:Build(userId: number)
	return GarageService:GetBuild(userId) or Customization.stock(self:_carKeyOf(userId))
end

-- ---------------------------------------------------------------- on the car

function CustomizationService:_carOf(userId: number): Model?
	local folder = Workspace:FindFirstChild(CARS_FOLDER)
	if not folder then
		return nil
	end
	for _, car in folder:GetChildren() do
		if car:GetAttribute("UserId") == userId then
			return car
		end
	end
	return nil
end

-- Write a build onto a car: every `Fit_*` attribute, then `Fitted` up by one, last, so a
-- client watching `Fitted` reads a whole build.
function CustomizationService:Publish(car: Instance, build)
	for name, value in Customization.attributes(build) do
		car:SetAttribute(name, value)
	end
	local was = car:GetAttribute(Customization.ATTR_COUNTER)
	car:SetAttribute(Customization.ATTR_COUNTER, (if type(was) == "number" then was else 0) + 1)
	self.published += 1
end

function CustomizationService:_publishFor(userId: number): boolean
	local car = self:_carOf(userId)
	if not car then
		return false
	end
	self:Publish(car, self:Build(userId))
	return true
end

function CustomizationService:_carAdded(car: Instance)
	local userId = car:GetAttribute("UserId")
	if type(userId) ~= "number" then
		return
	end
	-- Before the store has answered this is the stock car; `BuildLoaded` publishes again.
	self:Publish(car, self:Build(userId))
end

-- ---------------------------------------------------------------- the wire

function CustomizationService:_allowed(userId: number): boolean
	local now = os.clock()
	local window = self.limits[userId]
	if not window or now - window.at >= 1 then
		window = { at = now, count = 0 }
		self.limits[userId] = window
	end
	window.count += 1
	return window.count <= Customization.Limits.FitsPerSecond
end

-- `{ ok, reason?, category?, build }`: the answer, always with the whole build the server
-- believes, so a client that previewed something refused goes straight back to it.
function CustomizationService:_answer(player, ok: boolean, reason: string?, category: string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return -- a stand-in from the tests, or somebody already gone
	end
	self.fitRemote:FireClient(player, {
		ok = ok,
		reason = reason,
		category = category,
		build = self:Build(player.UserId),
	})
end

function CustomizationService:_refuse(player, reason: string, category: string?)
	self.refused += 1
	self.reasons[reason] = (self.reasons[reason] or 0) + 1
	self:_answer(player, false, reason, category)
	return false, reason
end

-- One ask off the wire. `category` nil and `choice` nil is a QUESTION ("what is my car
-- built as?"), answered with the build. Otherwise, in order: the rate limit (a flood is
-- dropped unanswered), the store has answered for this player, and the ask itself against
-- the catalog (`Customization.fit`). Returns `ok, reason` for the tests and Studio.
function CustomizationService:_onFit(player, category: any, choice: any): (boolean, string?)
	local userId = player.UserId
	if not self:_allowed(userId) then
		self.flooded += 1
		return false, "flood"
	end
	self.asks += 1
	if category == nil and choice == nil then
		self.questions += 1
		self:_answer(player, true, nil, nil)
		return true, nil
	end
	-- Only a known category is echoed back, never a value off the wire.
	local echo = if Customization.category(category) then category else nil
	if not GarageService:BuildReady(userId) then
		return self:_refuse(player, "loading", echo)
	end
	local current = self:Build(userId)
	local nextBuild, reason = Customization.fit(current, category, choice)
	if not nextBuild then
		return self:_refuse(player, reason or "refused", echo)
	end
	-- The base is the server's own idea of the car the parts went on, never the client's.
	nextBuild.base = self:_carKeyOf(userId)
	if not GarageService:SetBuild(userId, nextBuild) then
		return self:_refuse(player, "no garage", echo)
	end
	self.fits += 1
	self:_publishFor(userId)
	self:_answer(player, true, nil, echo)
	return true, nil
end

-- ---------------------------------------------------------------- Studio and the tests

function CustomizationService:DebugState()
	local players = {}
	for _, player in Players:GetPlayers() do
		local car = self:_carOf(player.UserId)
		table.insert(players, {
			userId = player.UserId,
			ready = GarageService:BuildReady(player.UserId),
			build = self:Build(player.UserId),
			car = car and car.Name or nil,
			fitted = car and car:GetAttribute(Customization.ATTR_COUNTER) or nil,
		})
	end
	return {
		asks = self.asks,
		questions = self.questions,
		fits = self.fits,
		refused = self.refused,
		flooded = self.flooded,
		reasons = table.clone(self.reasons),
		published = self.published,
		players = players,
	}
end

-- Studio only: an ask as if it came off the wire, for a player in the server.
function CustomizationService:DebugFit(userId: number, category, choice)
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return self:_onFit(player, category, choice)
		end
	end
	return false, "no player"
end

function CustomizationService:DebugClearLimits(userId: number?)
	if userId then
		self.limits[userId] = nil
	else
		self.limits = {}
	end
end

return CustomizationService
