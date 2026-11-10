--!nonstrict
-- GarageVisitService: taking a player's car into the garage and out again
-- (docs/game/features/car-customization.md "How it plays", T-103).
--
-- IN: drive through the garage's door (the server watches where it has agreed each car is,
-- `Config.GarageMenu.Trigger`), or press Garage on the HUD (`GarageVisit` with `true`).
-- Either way the server parks the car on the turntable (`GarageRoomService:GetPoint
-- ("TurntableTop")`, raised by the ride height) and HOLDS it there (`CarService:Hold`): the
-- throttle is automatic, so a car left to its own simulation would roll straight off. The
-- client stops simulating and opens the menus.
--
-- WHILE IN: the turntable turns slowly, and every held car turns with it -- the turntable
-- carries nothing, so this moves both, each Heartbeat, from one angle.
--
-- OUT: Drive out (`GarageVisit` with `false`) releases the car at `CarExit`, facing out,
-- at rest (`CarService:Release`), and the client drives from there.
--
-- A respawn, a `Place` (a run starting, the test lift) or a new car calls a visit off
-- (`CarService.CarMoved`), and the client is told it is over.
--
-- ONE SHARED ROOM, for now (CONTRACTS.md `Workspace.GarageRoom`): two players in at once
-- are parked on the same turntable.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local CarService = require(script.Parent.CarService)
local GarageRoomService = require(script.Parent.GarageRoomService)

local GarageVisitService = {}
GarageVisitService.Priority = 0

local HOLD_TAG = "garage"

function GarageVisitService:Init()
	self.visits = {} -- userId -> { rel: CFrame, since: number, how: string }
	self.rate = {} -- userId -> { window, count }, kept across rejoins
	self.leftAt = {} -- userId -> os.clock() of the last visit's end
	self.angle = 0
	self.counts = {
		asks = 0,
		questions = 0,
		refused = 0,
		entered = 0,
		byDoor = 0,
		byButton = 0,
		left = 0,
		calledOff = 0,
	}
	self.reasons = {}
	self.remote = Net.event("GarageVisit")
end

function GarageVisitService:Start()
	self.remote.OnServerEvent:Connect(function(player, want)
		self:_onAsk(player, want)
	end)
	CarService.CarMoved:Connect(function(player, why)
		self:_calledOff(player, why)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.visits[player.UserId] = nil
	end)

	local sinceCheck, sinceOthers = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		sinceOthers += dt
		local tuning = Config.GarageMenu
		if sinceCheck >= tuning.TriggerPeriod then
			sinceCheck = 0
			self:_checkDoor()
		end
		local tell = sinceOthers >= tuning.OthersPeriod
		if tell then
			sinceOthers = 0
		end
		self:_spin(dt, tell)
	end)
end

-- ---------------------------------------------------------------- where

-- The room's own frame (ServerScriptService/GarageRoom/Layout): the turntable's centre on
-- the floor, +X the way a car comes in.
local function roomFrame(): CFrame
	local room = Config.GarageRoom
	return CFrame.new(room.Origin) * CFrame.Angles(0, math.rad(room.Yaw or 0), 0)
end

-- Is a world position inside the door's trigger?
function GarageVisitService.inTrigger(position: Vector3): boolean
	local box = Config.GarageMenu.Trigger
	local p = roomFrame():PointToObjectSpace(position)
	return p.X >= box.minX and p.X <= box.maxX and math.abs(p.Z) <= box.halfZ and p.Y >= box.minY and p.Y <= box.maxY
end

-- A named garage point with the car's ride height added: where a car's pivot goes.
local function carPoint(name: string): CFrame?
	local cf = GarageRoomService:GetPoint(name)
	if not cf then
		return nil
	end
	return cf + cf.UpVector * Config.Drift.RideHeight
end

-- The turntable's pivot with the turn taken out: where it stands at angle 0.
local function turntableHome(): CFrame?
	local turntable = GarageRoomService:Turntable()
	if not turntable or not turntable.Parent then
		return nil
	end
	return turntable:GetPivot() * CFrame.Angles(0, -GarageRoomService:TurntableAngle(), 0)
end

-- ---------------------------------------------------------------- in and out

-- A player in a run stays on the road: the garage is the playground's.
local function inRun(player: Player): boolean
	local module = script.Parent:FindFirstChild("RoadService")
	if not module then
		return false
	end
	local ok, road = pcall(require, module)
	if not ok or type(road) ~= "table" or type(road.InRun) ~= "function" then
		return false
	end
	local asked, yes = pcall(road.InRun, road, player)
	return asked and yes == true
end

function GarageVisitService:_rateOk(player: Player): boolean
	local now = os.clock()
	local rate = self.rate[player.UserId]
	if not rate then
		rate = { window = now, count = 0 }
		self.rate[player.UserId] = rate
	end
	if now - rate.window >= 1 then
		rate.window = now
		rate.count = 0
	end
	rate.count += 1
	return rate.count <= Config.GarageMenu.RateLimit
end

function GarageVisitService:_send(player: Player, state)
	self.remote:FireClient(player, state)
end

function GarageVisitService:_refuse(player: Player, reason: string, inGarage: boolean): (boolean, string)
	self.counts.refused += 1
	self.reasons[reason] = (self.reasons[reason] or 0) + 1
	self:_send(player, { inGarage = inGarage, ok = false, reason = reason })
	return false, reason
end

-- The whole state of one player's visit, as it goes down the wire.
function GarageVisitService:_stateFor(player: Player, extra)
	local visit = self.visits[player.UserId]
	local out = { inGarage = visit ~= nil, ok = true }
	if visit then
		out.rel = visit.rel
		out.home = turntableHome()
		out.how = visit.how
	end
	for k, v in extra or {} do
		out[k] = v
	end
	return out
end

-- `want`: true = take me in, false = drive me out, nil = a question. Nothing else is read.
function GarageVisitService:_onAsk(player: Player, want: any): (boolean, string?)
	self.counts.asks += 1
	if not self:_rateOk(player) then
		return self:_refuse(player, "rate", self.visits[player.UserId] ~= nil)
	end
	if want == nil then
		self.counts.questions += 1
		self:_send(player, self:_stateFor(player))
		return true, nil
	end
	if type(want) ~= "boolean" then
		return self:_refuse(player, "bad ask", self.visits[player.UserId] ~= nil)
	end
	if want then
		return self:Enter(player, "button")
	end
	return self:Leave(player)
end

-- Into the garage. `how` is "door" or "button".
function GarageVisitService:Enter(player: Player, how: string): (boolean, string?)
	local userId = player.UserId
	if self.visits[userId] then
		return self:_refuse(player, "already in", true)
	end
	local leftAt = self.leftAt[userId]
	if leftAt and os.clock() - leftAt < Config.GarageMenu.Cooldown then
		return self:_refuse(player, "too soon", false)
	end
	if inRun(player) then
		return self:_refuse(player, "in a run", false)
	end
	local park = carPoint("TurntableTop")
	local home = turntableHome()
	if not park or not home then
		return self:_refuse(player, "no garage", false)
	end
	-- The car goes on at the turntable's CURRENT angle, so a second car arriving while one
	-- is already turning lands where the deck is, not where it was at angle 0.
	local rel = home:ToObjectSpace(park)
	local turntable = GarageRoomService:Turntable()
	local at = turntable:GetPivot() * rel
	local ok, reason = CarService:Hold(player, at, HOLD_TAG)
	if not ok then
		return self:_refuse(player, reason or "not driving", false)
	end
	self.visits[userId] = { rel = rel, since = os.clock(), how = how }
	self.counts.entered += 1
	if how == "door" then
		self.counts.byDoor += 1
	else
		self.counts.byButton += 1
	end
	self:_send(player, self:_stateFor(player, { cf = at }))
	return true, nil
end

-- Out of the garage: the car at `CarExit`, facing out, at rest.
function GarageVisitService:Leave(player: Player): (boolean, string?)
	local userId = player.UserId
	if not self.visits[userId] then
		return self:_refuse(player, "not in garage", false)
	end
	local exit = carPoint("CarExit")
	if not exit then
		return self:_refuse(player, "no garage", true)
	end
	local cf = CarService:Release(player, exit)
	self.visits[userId] = nil
	self.leftAt[userId] = os.clock()
	if not cf then
		-- The hold was already gone (a respawn got there first): nothing to release.
		self:_send(player, { inGarage = false, ok = true })
		return true, nil
	end
	self.counts.left += 1
	self:_send(player, { inGarage = false, ok = true, cf = cf })
	return true, nil
end

-- CarService moved the car itself: the visit is over, and the client is told so. The car
-- is wherever that move put it, so nothing is released here.
function GarageVisitService:_calledOff(player: Player, why: string?)
	local userId = player.UserId
	if not self.visits[userId] then
		return
	end
	self.visits[userId] = nil
	self.leftAt[userId] = os.clock()
	self.counts.calledOff += 1
	self:_send(player, { inGarage = false, ok = true, calledOff = why or "moved" })
end

-- ---------------------------------------------------------------- every frame

-- A car the server believes is inside the door goes in.
function GarageVisitService:_checkDoor()
	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		if not self.visits[userId] then
			local position = CarService:BelievedPosition(userId)
			local entry = CarService.entry and CarService.entry[userId]
			if position and entry and entry.driving and not entry.busy and GarageVisitService.inTrigger(position) then
				local leftAt = self.leftAt[userId]
				if not leftAt or os.clock() - leftAt >= Config.GarageMenu.Cooldown then
					self:Enter(player, "door")
				end
			end
		end
	end
end

-- Turn the turntable, and every car held on it with it.
function GarageVisitService:_spin(dt: number, tellOthers: boolean)
	if next(self.visits) == nil then
		return
	end
	local turntable = GarageRoomService:Turntable()
	if not turntable or not turntable.Parent then
		return
	end
	local home = turntableHome()
	self.angle = GarageRoomService:TurntableAngle() + Config.GarageMenu.SpinRate * dt
	GarageRoomService:SetTurntableAngle(self.angle)
	local pivot = home * CFrame.Angles(0, GarageRoomService:TurntableAngle(), 0)
	for userId, visit in self.visits do
		local player = Players:GetPlayerByUserId(userId)
		if player and CarService:HeldBy(player) == HOLD_TAG then
			CarService:MoveHeld(player, pivot * visit.rel, tellOthers)
		end
	end
end

-- ---------------------------------------------------------------- Studio only

local function playerFor(userId: number?): Player?
	for _, player in Players:GetPlayers() do
		if userId == nil or player.UserId == userId then
			return player
		end
	end
	return nil
end

function GarageVisitService:InGarage(player: Player): boolean
	return self.visits[player.UserId] ~= nil
end

-- One player's visit as the server sees it: where the car is against where the turntable
-- says it should be, and the angle.
function GarageVisitService:VisitState(userId: number?)
	local player = playerFor(userId)
	if not player then
		return { player = false }
	end
	local visit = self.visits[player.UserId]
	local car = CarService.cars and CarService.cars[player.UserId]
	local out = {
		inGarage = visit ~= nil,
		how = visit and visit.how or nil,
		heldBy = CarService:HeldBy(player),
		angle = GarageRoomService:TurntableAngle(),
		carAt = car and car:GetPivot().Position or nil,
	}
	local turntable = GarageRoomService:Turntable()
	if visit and car and turntable then
		local want = turntable:GetPivot() * visit.rel
		out.offTurntable = (car:GetPivot().Position - want.Position).Magnitude
		local top = GarageRoomService:GetPoint("TurntableTop")
		if top then
			-- The car's pivot over the deck's centre, flat: 0 is dead centre.
			local p = car:GetPivot().Position - top.Position
			out.offCentre = Vector3.new(p.X, 0, p.Z).Magnitude
			out.aboveDeck = p.Y
		end
	end
	return out
end

function GarageVisitService:DebugState()
	local visits = {}
	for userId, visit in self.visits do
		visits[tostring(userId)] = { how = visit.how, seconds = os.clock() - visit.since }
	end
	return {
		visits = visits,
		angle = GarageRoomService:TurntableAngle(),
		counts = table.clone(self.counts),
		reasons = table.clone(self.reasons),
	}
end

-- In at the real handler, guards and all: `want` as the client would send it.
function GarageVisitService:DebugAsk(want: any, userId: number?)
	local player = playerFor(userId)
	if not player then
		return { ok = false, reason = "no player" }
	end
	local ok, reason = self:_onAsk(player, want)
	return { ok = ok, reason = reason }
end

function GarageVisitService:DebugClearLimits()
	table.clear(self.rate)
	table.clear(self.leftAt)
	return true
end

return GarageVisitService
