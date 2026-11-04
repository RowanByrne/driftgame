--!nonstrict
-- GarageService: the server half of the car tuner (docs/game/features/car-tuner.md).
--
-- ============================================================================
-- THIS IS A DEV TOOL AND IT IS NOT THE SAVE SYSTEM. DELETE IT WHEN THE REAL ONE ARRIVES.
-- ============================================================================
--
-- It is the first thing in this game that persists anything, and that is an accident of
-- ordering rather than a decision: the foundation kit's `DataService` and `PlayerData`
-- are deliberately not built yet (`ARCHITECTURE.md`), because nothing is meant to save
-- until the drift feel is proven. So this is a SMALL, DEDICATED STORE FOR TUNED CARS
-- ONLY -- not a player profile, not a schema anything else may hang off, and not the
-- start of the save system:
--
--   * one key per player in one store of its own, holding nothing but named tunes;
--   * no session lock, because there is nothing here two servers can fight over that
--     matters -- last write wins, and the thing that is lost is a slider position;
--   * no migration path promised beyond `Garage.Version`;
--   * nothing else in the game may read it.
--
-- WHAT REPLACING IT PROPERLY LOOKS LIKE, so the next agent does not have to work it out:
-- build `DataService` to the kit's API (CODING.md "The kit's fixed names"), give the
-- profile a `garage` key, and this file becomes `DataService:Get(player, "garage")` and
-- `DataService:Update(player, "garage", fn)` -- about forty lines go, the remotes and the
-- validation stay, and the old store is read once and dropped. The shape saved here is
-- already the shape a profile key would hold, so that migration is a copy.
--
-- ---------------------------------------------------------------- what it actually does
--
-- 1. Holds each player's garage in memory, loads it once when they join and writes it
--    back behind them. THE IN-MEMORY COPY IS THE LIVE ONE: a write that fails is retried
--    and then warned about, and never costs the user the car they are driving.
-- 2. Validates everything off the wire through `Shared/Cars/Garage`, which is the same
--    module the client draws its sliders from, so there is one definition of what a tuned
--    car may be.
-- 3. Keeps the server's speed bound ahead of a tuned car -- see "the ceiling".

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local Garage = require(ReplicatedStorage.Shared.Cars.Garage)
local Net = require(ReplicatedStorage.Shared.Net)

local GarageService = {}

GarageService.Priority = 40 -- after CarService (50): its remotes and its per-player car
-- key both exist before anything here asks about them

local STORE_NAME = "DriftGarageDev_v1" -- the "Dev" is load-bearing: this store is
-- throwaway and nothing but the tuner may read it
local KEY_PREFIX = "garage_"

-- ---------------------------------------------------------------------- the store
--
-- MEMORY MODE IS THE NORMAL CASE TODAY, and it is not an error. Drift has no published
-- place yet (`PROJECT.md`: the place id is still a placeholder), and Roblox refuses
-- DataStore calls from an unpublished place -- so in Studio this keeps the garage in a
-- table that lives as long as the server. Saving, loading, editing and the whole round
-- trip all work there; what does not survive is stopping the playtest
-- (docs/workflow/TESTING.md, "No DataStores in unpublished places").
--
-- The rule is the kit's: memory mode ONLY in Studio or with no place id. A live server
-- never silently falls back to it -- it retries and warns, because pretending to have
-- saved is the one failure worse than not saving.
local Store = {}
Store.__index = Store

function Store.memory(reason: string)
	return setmetatable({ kind = "memory", reason = reason, data = {}, reads = 0, writes = 0, failures = 0 }, Store)
end

function Store.live(store: DataStore)
	return setmetatable({ kind = "datastore", store = store, reads = 0, writes = 0, failures = 0 }, Store)
end

function Store:Get(key: string): (boolean, any)
	self.reads += 1
	if self.kind == "memory" then
		return true, self.data[key]
	end
	local ok, result = pcall(function()
		return self.store:GetAsync(key)
	end)
	if not ok then
		self.failures += 1
	end
	return ok, result
end

function Store:Set(key: string, value: any): (boolean, any)
	self.writes += 1
	if self.kind == "memory" then
		self.data[key] = value
		return true, nil
	end
	local ok, err = pcall(function()
		self.store:SetAsync(key, value)
	end)
	if not ok then
		self.failures += 1
	end
	return ok, err
end

local function openStore()
	if RunService:IsStudio() then
		return Store.memory("Studio")
	end
	if game.PlaceId == 0 then
		return Store.memory("no place id")
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not ok or not store then
		warn(`[GarageService] no DataStore ({tostring(store)}); tuned cars will not be saved this server`)
		return Store.memory("GetDataStore failed")
	end
	return Store.live(store)
end

--------------------------------------------------------------------------------

function GarageService:Init()
	self.store = openStore()
	self.garages = {} -- userId -> { [name] = Garage.Car }
	self.tunes = {} -- userId -> the live tune they are driving, sanitized
	self.dirty = {} -- userId -> true, a garage the store has not caught up with
	self.loaded = {} -- userId -> true once the store has answered
	self.limits = {} -- userId -> rate-limit windows
	self.ceiling = nil -- the top speed the server is currently allowing, or nil
	self.saves = 0
	self.savesRefused = 0
	self.deletes = 0
	self.tuneUpdates = 0
	self.tunesRefused = 0

	self.garageData = Net.event("GarageData") -- both ways: the client asks, the server tells
	self.garageSave = Net.event("GarageSave")
	self.garageDelete = Net.event("GarageDelete")
	self.garageTune = Net.event("GarageTune")
end

function GarageService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_join(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_leave(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_join(player)
		end)
	end

	self.garageData.OnServerEvent:Connect(function(player)
		-- No payload: "send me my garage". The client asks when it starts up, because it
		-- may have been built after the server pushed it on join.
		self:_tell(player)
	end)
	self.garageSave.OnServerEvent:Connect(function(player, name, base, tune)
		self:_onSave(player, name, base, tune)
	end)
	self.garageDelete.OnServerEvent:Connect(function(player, name)
		self:_onDelete(player, name)
	end)
	self.garageTune.OnServerEvent:Connect(function(player, tune)
		self:_onTune(player, tune)
	end)

	-- The writer. One loop, not a write per change: a slider being dragged is twenty
	-- changes a second and the store must never see them (CODING.md "Data store limits").
	task.spawn(function()
		while true do
			task.wait(Config.Drift.GarageWriteInterval)
			self:Flush()
		end
	end)

	game:BindToClose(function()
		self:Flush(true)
	end)
end

-- ---------------------------------------------------------------- joining and leaving

function GarageService:_join(player: Player)
	local userId = player.UserId
	if self.garages[userId] then
		return
	end
	self.garages[userId] = {} -- something to answer with before the store has
	task.spawn(function()
		local ok, raw = self.store:Get(KEY_PREFIX .. userId)
		if not ok then
			warn(`[GarageService] could not read {player.Name}'s garage: {tostring(raw)}`)
		end
		-- A player who has tuned or saved something in the second the read took keeps it:
		-- the store's answer only fills in names this session has not touched.
		local loaded = Garage.sanitizeGarage(if type(raw) == "table" then raw.cars else nil)
		local live = self.garages[userId]
		if not live then
			return -- left while the store was answering
		end
		for name, car in loaded do
			if live[name] == nil then
				live[name] = car
			end
		end
		self.loaded[userId] = true
		if player.Parent then
			self:_tell(player)
		end
	end)
end

function GarageService:_leave(player: Player)
	local userId = player.UserId
	local garage = self.garages[userId]
	if garage and self.dirty[userId] then
		task.spawn(function()
			self:_write(userId, garage)
		end)
	end
	self.garages[userId] = nil
	self.tunes[userId] = nil
	self.loaded[userId] = nil
	self.limits[userId] = nil
	self:_applyCeiling()
end

-- ---------------------------------------------------------------- writing

-- Write one garage, with retries and a backoff. Returns whether it landed. THE CALLER
-- KEEPS ITS COPY EITHER WAY -- nothing here ever clears `self.garages`.
function GarageService:_write(userId: number, garage): boolean
	local payload = { version = Garage.Version, cars = garage, at = os.time() }
	local wait = Config.Drift.GarageRetryBackoff
	for attempt = 1, Config.Drift.GarageWriteRetries do
		local ok, err = self.store:Set(KEY_PREFIX .. userId, payload)
		if ok then
			self.dirty[userId] = nil
			return true
		end
		if attempt < Config.Drift.GarageWriteRetries then
			task.wait(wait)
			wait *= 2
		elseif not self.silent then
			-- `silent` is `GarageTests` driving a store that refuses every write ON
			-- PURPOSE. A test that leaves a warning in the console is a test that makes
			-- the next agent's console check lie.
			warn(`[GarageService] gave up writing {userId}'s garage after {attempt} tries: {tostring(err)}`)
		end
	end
	-- Left dirty on purpose: the next flush tries again, and the in-memory garage is
	-- still the one the player is using.
	return false
end

-- Write every garage the store has not caught up with. `now` runs them in line, for
-- `BindToClose`, which is the one caller that cannot return before the writes are done.
function GarageService:Flush(now: boolean?): number
	local wrote = 0
	for userId in self.dirty do
		local garage = self.garages[userId]
		if garage then
			if now then
				if self:_write(userId, garage) then
					wrote += 1
				end
			else
				task.spawn(function()
					self:_write(userId, garage)
				end)
				wrote += 1
			end
		else
			self.dirty[userId] = nil
		end
	end
	return wrote
end

-- ---------------------------------------------------------------- the wire

-- Ignore anything asked for faster than a person could ask for it. Keyed by UserId, so a
-- rejoin does not reset it (CODING.md "Server rules").
function GarageService:_allowed(userId: number, bucket: string, perSecond: number): boolean
	local limits = self.limits[userId]
	if not limits then
		limits = {}
		self.limits[userId] = limits
	end
	local window = limits[bucket]
	local now = os.clock()
	if not window or now - window.at >= 1 then
		window = { at = now, count = 0 }
		limits[bucket] = window
	end
	window.count += 1
	return window.count <= perSecond
end

-- What the server believes this player's garage is. The whole thing every time: a garage
-- is at most `GarageMaxCars` rows of eight numbers, which is smaller than the packet
-- header, and a client that is told everything can never be half out of step.
function GarageService:_tell(player: Player)
	local garage = self.garages[player.UserId]
	if not garage then
		return
	end
	if typeof(player) ~= "Instance" then
		return -- a stand-in, from `GarageTests`: there is nobody to tell
	end
	self.garageData:FireClient(player, {
		version = Garage.Version,
		cars = garage,
		loaded = self.loaded[player.UserId] == true,
		persists = self.store.kind == "datastore",
	})
end

function GarageService:_onSave(player: Player, name: any, base: any, tune: any)
	local userId = player.UserId
	if not self:_allowed(userId, "save", Config.Drift.GarageSaveRateLimit) then
		self.savesRefused += 1
		return
	end
	local garage = self.garages[userId]
	if not garage then
		self.savesRefused += 1
		return
	end
	local clean = Garage.cleanName(name)
	local car = Garage.sanitizeCar({ base = base, tune = tune })
	if not clean or not car then
		self.savesRefused += 1
		self:_tell(player) -- the client is put back on what the server believes
		return
	end
	-- A full garage still takes an OVERWRITE: somebody tuning should never be told the
	-- car they are driving cannot be saved over the one it came from.
	if garage[clean] == nil and Garage.count(garage) >= Config.Drift.GarageMaxCars then
		self.savesRefused += 1
		self:_tell(player)
		return
	end
	car.savedAt = os.time()
	garage[clean] = car
	self.dirty[userId] = true
	self.saves += 1
	self:_tell(player)
end

function GarageService:_onDelete(player: Player, name: any)
	local userId = player.UserId
	if not self:_allowed(userId, "save", Config.Drift.GarageSaveRateLimit) then
		return
	end
	local garage = self.garages[userId]
	local clean = Garage.cleanName(name)
	if not garage or not clean or garage[clean] == nil then
		return
	end
	garage[clean] = nil
	self.dirty[userId] = true
	self.deletes += 1
	self:_tell(player)
end

-- ---------------------------------------------------------------- the ceiling
--
-- THE ONE THING A TUNED CAR BREAKS, AND HOW IT IS ANSWERED.
--
-- The server bounds every `CarState` against the top speed of the car it believes that
-- player is in (`CarService`, T-033): a packet reporting more than `TopSpeed x
-- StateSpeedTolerance` is dropped. A player who drags the Top speed slider past their
-- archetype's own top speed is therefore driving a car the server does not believe in,
-- and every packet from it is thrown away -- the car stops moving for everyone else and
-- the drop counter climbs.
--
-- `Cars.resolve`, which is what `CarService` asks, applies the tuning layer. So the
-- answer is to tune the SERVER's `TopSpeed` to a CEILING:
--
--     ceiling = max(the fastest archetype, every player's effective top speed)
--
-- and to apply it only while somebody is actually tuned above their own car. Three
-- things make that safe rather than a hole:
--
--   * IT ONLY EVER LOOSENS. The floor is the fastest archetype (215 studs/s today), so
--     no player in a plain car is ever bounded below their own top speed, whatever
--     anybody else is tuning. A tighter ceiling would drop honest packets, which is the
--     failure this is here to prevent.
--   * IT IS BOUNDED BY THE SLIDER. `TopSpeed` maxes at 400 (`Shared/Cars/Garage`), so
--     the loosest the server can ever get is 400 x 1.25 = 500 studs/s, and the distance
--     check moves with it -- a teleport is still a teleport.
--   * IT GOES AWAY. The moment nobody is tuned above their car, the tune is removed and
--     the bound is exactly what T-033 made it, to the stud.
--
-- WHAT IT IS NOT: per player. `Cars.tune` is one layer over one Lua VM and `CarService`
-- asks `Cars.resolve(key)` with no player in hand, so a per-player bound is not
-- expressible from here. It would be three lines in `CarService:_numbers` -- resolve,
-- then lay that player's tune over it -- in a file this task does not own, and that is
-- the proper fix the day a tuned car is anything but a dev tool. Until then: while
-- somebody is tuning, every player on this server shares the loosest bound, which is the
-- same slack the game lived with before T-033 and is a dev tool's price.
function GarageService:_carService()
	local services = ServerScriptService:FindFirstChild("Services")
	local module = services and services:FindFirstChild("CarService")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, loaded = pcall(require, module)
	return if ok then loaded else nil
end

-- The archetype the SERVER says this player is in. Never this service's own idea of it:
-- `CarService` owns that (T-033) and a second opinion here would be the first thing to
-- make it a lie.
function GarageService:_carKeyOf(userId: number): string
	local CarService = self:_carService()
	if CarService then
		for _, player in Players:GetPlayers() do
			if player.UserId == userId then
				return CarService:CarKey(player)
			end
		end
	end
	return Cars.Default
end

-- That car's top speed with this player's live tune over it: the speed they could really
-- be doing, and what the ceiling has to clear.
function GarageService:_effectiveTopSpeed(userId: number): number
	return Garage.topSpeed(self:_carKeyOf(userId), self.tunes[userId])
end

-- Work out the ceiling and put it in place, or take it away. Cheap and called on every
-- tune, join and leave.
function GarageService:_applyCeiling(): number?
	local floor = Garage.fastestArchetype()
	local wanted = floor
	local anyTuned = false
	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		local tune = self.tunes[userId]
		if tune and tune.topspeed ~= nil then
			local effective = self:_effectiveTopSpeed(userId)
			wanted = math.max(wanted, effective)
			-- Only a tune ABOVE the player's own car needs the ceiling at all; one below
			-- it is already inside the bound.
			if effective > Garage.topSpeed(self:_carKeyOf(userId), nil) then
				anyTuned = true
			end
		end
	end

	if not anyTuned then
		if self.ceiling ~= nil then
			Cars.untune("TopSpeed")
			self.ceiling = nil
		end
		return nil
	end

	if self.ceiling ~= wanted then
		Cars.tune("TopSpeed", wanted)
		self.ceiling = wanted
	end
	return self.ceiling
end

function GarageService:_onTune(player: Player, tune: any)
	local userId = player.UserId
	if not self:_allowed(userId, "tune", Config.Drift.GarageTuneRateLimit) then
		self.tunesRefused += 1
		return
	end
	self.tunes[userId] = Garage.sanitizeTune(tune)
	self.tuneUpdates += 1
	self:_applyCeiling()
end

-- ---------------------------------------------------------------- Studio and the tests

-- Everything the service knows, for Studio and for `GarageTests`.
function GarageService:DebugState()
	local players = {}
	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		local garage = self.garages[userId] or {}
		table.insert(players, {
			userId = userId,
			name = player.Name,
			cars = Garage.names(garage),
			carCount = Garage.count(garage),
			loaded = self.loaded[userId] == true,
			dirty = self.dirty[userId] == true,
			tune = self.tunes[userId],
			carKey = self:_carKeyOf(userId),
			effectiveTopSpeed = self:_effectiveTopSpeed(userId),
		})
	end
	return {
		store = self.store.kind,
		storeReason = self.store.reason,
		reads = self.store.reads,
		writes = self.store.writes,
		writeFailures = self.store.failures,
		ceiling = self.ceiling,
		archetypeFloor = Garage.fastestArchetype(),
		boundNow = Cars.resolve(Cars.Default).TopSpeed,
		saves = self.saves,
		savesRefused = self.savesRefused,
		deletes = self.deletes,
		tuneUpdates = self.tuneUpdates,
		tunesRefused = self.tunesRefused,
		players = players,
	}
end

-- Studio and the tests only: the three client asks, with no client.
function GarageService:DebugSave(userId: number, name: string, base: string, tune): boolean
	local before = self.saves
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			self:_onSave(player, name, base, tune)
			return self.saves > before
		end
	end
	return false
end

function GarageService:DebugTune(userId: number, tune): number?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			self:_onTune(player, tune)
			return self.ceiling
		end
	end
	return nil
end

-- Studio and the tests only: forget everything about a player in memory, exactly as
-- leaving does, WITHOUT dropping their garage from the store. The other half of a rejoin,
-- so the round trip through the store can be proved without restarting a playtest.
function GarageService:DebugForget(userId: number): boolean
	if self.dirty[userId] and self.garages[userId] then
		self:_write(userId, self.garages[userId])
	end
	local had = self.garages[userId] ~= nil
	self.garages[userId] = nil
	self.tunes[userId] = nil
	self.loaded[userId] = nil
	self:_applyCeiling()
	return had
end

-- And the first half: load a player back out of the store as joining does, in line, so
-- the caller can read the answer straight after.
function GarageService:DebugRejoin(userId: number)
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			self:_join(player)
			local waited = 0
			while not self.loaded[userId] and waited < 5 do
				task.wait(0.05)
				waited += 0.05
			end
			return { loaded = self.loaded[userId] == true, cars = Garage.names(self.garages[userId] or {}) }
		end
	end
	return { loaded = false, cars = {} }
end

-- One saved car's numbers, by name, as they are on the server. What a "to the value"
-- check reads.
function GarageService:DebugCar(userId: number, name: string)
	local garage = self.garages[userId]
	local car = garage and garage[Garage.cleanName(name) or ""]
	if not car then
		return nil
	end
	return { base = car.base, tune = car.tune, values = Garage.values(car.base, car.tune), savedAt = car.savedAt }
end

-- The tests drive the store directly rather than through a player, and must never touch
-- a real one. Swaps in a fresh memory store and gives back the old one to put back.
function GarageService:DebugSwapStore(store)
	local was = self.store
	self.store = store or Store.memory("test")
	return was
end

GarageService.MemoryStore = Store.memory

return GarageService
