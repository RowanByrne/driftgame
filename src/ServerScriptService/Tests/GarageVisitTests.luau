--!nonstrict
-- GarageVisitTests: getting into the garage and out again, and what the menus show (T-103;
-- docs/game/features/car-customization.md "How it plays").
--
--   game.ServerStorage.DebugBridge:Invoke("DebugGarageVisitTests", "run")
--
-- Two halves. The first needs nothing: the door's trigger box against the room's named
-- points, and the menus' model (`StarterPlayerScripts/Garage/MenuModel`) on the real
-- catalog -- tabs, rows, bars, picks and previews. The second needs a playtest with one
-- player in their car, and goes in at the REAL handler (`GarageVisitService:_onAsk`) and
-- the real door check: in by the button and by the door, the car on the turntable and held
-- there while it turns, packets and Get out refused while in, every refusal, a respawn
-- calling the visit off, and out at `CarExit` facing out. The player's own client follows
-- along: the answers go to it either way. It leaves the player driving, out of the garage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "GarageVisitTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local Customization = require(ReplicatedStorage.Shared.Customization)

local MenuModel = require(StarterPlayer.StarterPlayerScripts:WaitForChild("Garage"):WaitForChild("MenuModel"))
local CarService = require(ServerScriptService.Services.CarService)
local GarageRoomService = require(ServerScriptService.Services.GarageRoomService)
local GarageVisitService = require(ServerScriptService.Services.GarageVisitService)

local GarageVisitTests = {}

local TOL = 0.05 -- studs: "the car on the turntable within 0.05"

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
end

local function r(x: number?): number
	return if x then math.round(x * 1000) / 1000 else -1
end

local function waitFor(predicate: () -> boolean, seconds: number): boolean
	local deadline = os.clock() + seconds
	while not predicate() do
		if os.clock() > deadline then
			return false
		end
		task.wait()
	end
	return true
end

local function carPoint(name: string): CFrame?
	local cf = GarageRoomService:GetPoint(name)
	return cf and (cf + cf.UpVector * Config.Drift.RideHeight)
end

-- ---------------------------------------------------------------- no player needed

local function pure(checks)
	-- The trigger: the door and the bay in, the street, the exit and the yard out.
	local function at(name: string): Vector3
		local cf = GarageRoomService:GetPoint(name)
		return cf and (cf.Position + Vector3.new(0, Config.Drift.RideHeight, 0)) or Vector3.zero
	end
	local roomCF = CFrame.new(Config.GarageRoom.Origin) * CFrame.Angles(0, math.rad(Config.GarageRoom.Yaw), 0)
	local cases = {
		{ "turntable", at("TurntableTop"), true },
		{ "just inside the door", roomCF:PointToWorldSpace(Vector3.new(-25, 2.4, 0)), true },
		{ "door's edge", roomCF:PointToWorldSpace(Vector3.new(-25, 2.4, 8.5)), true },
		{ "CarExit", at("CarExit"), false },
		{ "CarEntry", at("CarEntry"), false },
		{ "beside the door, outside", roomCF:PointToWorldSpace(Vector3.new(-30, 2.4, 0)), false },
		{ "on the roof", roomCF:PointToWorldSpace(Vector3.new(0, 20, 0)), false },
		{ "the playground's spawn", Vector3.new(0, 2.65, 0), false },
	}
	local wrong = {}
	for _, case in cases do
		if GarageVisitService.inTrigger(case[2]) ~= case[3] then
			table.insert(wrong, case[1])
		end
	end
	check(checks, "Door trigger: the bay in, the street and the exit out", #wrong == 0,
		if #wrong == 0 then `{#cases} positions, all as expected` else "wrong: " .. table.concat(wrong, ", "))

	-- The menus' model.
	local stock = Customization.stock()
	local tabs = MenuModel.tabs()
	local labels = {}
	for _, tab in tabs do
		table.insert(labels, tab.label)
	end
	check(checks, "Seven tabs in menu order", #tabs == 7 and tabs[1].id == "Engine" and tabs[7].id == "Paint",
		table.concat(labels, " | "))

	local rowsOk, rowDetail = true, {}
	for _, id in Customization.PartCategories do
		local snap = MenuModel.snapshot({ fitted = stock, category = id })
		local fitted = 0
		for _, row in snap.rows do
			if row.fitted then
				fitted += 1
			end
		end
		if snap.kind ~= "parts" or #snap.rows ~= #Customization.partsIn(id) or fitted ~= 1 or not snap.rows[1].fitted then
			rowsOk = false
		end
		table.insert(rowDetail, `{id} {#snap.rows}`)
	end
	local paint = MenuModel.snapshot({ fitted = stock, category = "Paint" })
	local sectionCounts = {}
	for _, section in paint.paint or {} do
		table.insert(sectionCounts, `{section.field} {#section.options}{if section.grid then " grid" else ""}`)
	end
	check(checks, "Every tab has its list, the stock part marked fitted; Paint has grids and pickers",
		rowsOk and paint.kind == "paint" and #(paint.paint or {}) == 4 and paint.paint[1].grid and not paint.paint[3].grid,
		table.concat(rowDetail, ", ") .. "; paint: " .. table.concat(sectionCounts, ", "))

	-- Bars: the race build over stock goes up on both numbers; long gears over street goes
	-- down on power and up on top speed; a looks-only part has none.
	local race = MenuModel.bars(stock, "Engine", "engine_race")
	local street = Customization.fit(stock, "Engine", "engine_street")
	local gears = MenuModel.bars(street, "Engine", "engine_longgears")
	local mesh = MenuModel.bars(stock, "Wheels", "wheels_mesh")
	local resolvedStock = Customization.resolve(stock)
	local resolvedRace = Customization.resolve(Customization.fit(stock, "Engine", "engine_race"))
	local barText = {}
	for _, bar in race do
		table.insert(barText, `{bar.label} {r(bar.beforeValue)}->{r(bar.afterValue)} {bar.text}`)
	end
	for _, bar in gears do
		table.insert(barText, `gears {bar.label} {bar.text}`)
	end
	local raceOk = #race == 2 and race[1].up and race[2].up and race[1].afterValue == resolvedRace[race[1].key]
		and race[1].beforeValue == resolvedStock[race[1].key] and math.abs(race[1].before - 0.5) < 1e-9
	local gearsOk = #gears == 2 and (gears[1].up ~= gears[2].up)
	check(checks, "Performance bars come from Customization.resolve, before and after", raceOk and gearsOk and #mesh == 0,
		table.concat(barText, "; ") .. `; mesh rims {#mesh} bars`)

	-- Picks and previews.
	local pickFitted = MenuModel.pickPart(stock, "Engine", "engine_stock")
	local pickRace = MenuModel.pickPart(stock, "Engine", "engine_race")
	local preview = MenuModel.preview(stock, "Engine", pickRace)
	local p1 = MenuModel.pickPaint(stock, nil, "body", "red")
	local p2 = MenuModel.pickPaint(stock, p1, "body", "stock")
	local paintPreview = MenuModel.preview(stock, "Paint", p1)
	local snap = MenuModel.snapshot({ fitted = stock, category = "Engine", pick = pickRace })
	local selected = 0
	for _, row in snap.rows do
		if row.selected then
			selected += 1
		end
	end
	check(checks, "A pick previews through Customization.fit; picking what is fitted is no pick",
		pickFitted == nil and pickRace == "engine_race" and preview.parts.Engine == "engine_race"
			and stock.parts.Engine == "engine_stock" and p2.body == nil and paintPreview.paint.body == "red"
			and snap.canFit and snap.canBack and selected == 1 and Customization.equal(MenuModel.preview(stock, "Engine", nil), stock),
		`race pick {tostring(pickRace)}, preview engine {preview.parts.Engine}, fitted untouched {stock.parts.Engine}; paint pick red then stock -> {tostring(p2.body)}`)
end

-- ---------------------------------------------------------------- with a player

local function live(checks, player: Player)
	local userId = player.UserId
	local car = CarService.cars[userId]
	if not car then
		check(checks, "A player with a car", false, "no car")
		return
	end
	GarageVisitService:DebugClearLimits()
	CarService:DebugClearEntryLimits()
	-- Make sure we start out, driving.
	if GarageVisitService:InGarage(player) then
		GarageVisitService:_onAsk(player, false)
		GarageVisitService:DebugClearLimits()
	end
	waitFor(function()
		local e = CarService.entry[userId]
		return e ~= nil and e.driving and not e.busy
	end, 5)

	-- Junk on the wire.
	local junk = { "yes", 1, {}, Vector3.zero, workspace }
	local refusedJunk = 0
	for _, value in junk do
		GarageVisitService:DebugClearLimits()
		local ok, reason = GarageVisitService:_onAsk(player, value)
		if not ok and reason == "bad ask" then
			refusedJunk += 1
		end
	end
	GarageVisitService:DebugClearLimits()
	local outOk, outReason = GarageVisitService:_onAsk(player, false)
	check(checks, "Junk asks and leaving when not in are refused", refusedJunk == #junk and not outOk and outReason == "not in garage",
		`{refusedJunk}/{#junk} junk refused "bad ask"; out while out: {tostring(outReason)}`)

	-- IN BY THE BUTTON.
	GarageVisitService:DebugClearLimits()
	local ok, reason = GarageVisitService:_onAsk(player, true)
	local state = GarageVisitService:VisitState(userId)
	local top = carPoint("TurntableTop")
	local offTop = top and (car:GetPivot().Position - (GarageRoomService:Turntable():GetPivot() * GarageVisitService.visits[userId].rel).Position).Magnitude or 99
	check(checks, "In by the button: the car is held on the turntable", ok and state.inGarage and state.heldBy == "garage"
		and (state.offTurntable or 99) <= TOL and (state.offCentre or 99) <= TOL and offTop <= TOL,
		`ok {tostring(ok)} {tostring(reason)}; off the deck {r(state.offTurntable)}, off centre {r(state.offCentre)}, pivot {r(state.aboveDeck)} above the deck top`)

	local again, againReason = GarageVisitService:_onAsk(player, true)
	local exitOk, exitReason = CarService:_onExit(player, car:GetPivot())
	local enterOk, enterReason = CarService:_onEnter(player, car)
	CarService:DebugClearEntryLimits()
	local droppedBefore = CarService.parkedDropped
	CarService:_onState(player, car:GetPivot() + Vector3.new(0, 0, 5), Vector3.new(0, 0, 10), false)
	local droppedPacket = CarService.parkedDropped == droppedBefore + 1
	check(checks, "While in: a second in, Get out, Get in and every packet are refused",
		not again and againReason == "already in" and not exitOk and exitReason == "not driving" and not enterOk and enterReason == "not out" and droppedPacket,
		`again {tostring(againReason)}, get out {tostring(exitReason)}, get in {tostring(enterReason)}, packet dropped {tostring(droppedPacket)}`)

	-- HELD WHILE IT TURNS, for 10 seconds, sampled every frame.
	local angle0 = GarageRoomService:TurntableAngle()
	local worst, worstCentre, worstHeight, worstTilt, samples = 0, 0, 0, 0, 0
	local height0 = car:GetPivot().Position.Y
	local deadline = os.clock() + 10
	while os.clock() < deadline do
		RunService.Heartbeat:Wait()
		local s = GarageVisitService:VisitState(userId)
		worst = math.max(worst, s.offTurntable or 99)
		worstCentre = math.max(worstCentre, s.offCentre or 99)
		worstHeight = math.max(worstHeight, math.abs(car:GetPivot().Position.Y - height0))
		-- The deck and the car stay level: the turn is about the world's up, nothing else.
		local deckUp = GarageRoomService:Turntable():GetPivot().UpVector
		worstTilt = math.max(worstTilt, 1 - math.min(deckUp.Y, car:GetPivot().UpVector.Y))
		samples += 1
	end
	local turned = (GarageRoomService:TurntableAngle() - angle0) % (2 * math.pi)
	check(checks, "Held on the turntable for 10 s while it turns, level",
		worst <= TOL and worstCentre <= TOL and worstHeight <= TOL and worstTilt < 1e-4 and turned > 0.5,
		`{samples} frames, worst {r(worst)} off the deck, {r(worstCentre)} off its centre, {r(worstHeight)} up or down, tilt {r(worstTilt)}; the turntable turned {r(math.deg(turned))} deg`)

	-- OUT.
	GarageVisitService:DebugClearLimits()
	local leftOk, leftReason = GarageVisitService:_onAsk(player, false)
	local exit = carPoint("CarExit")
	local pivot = car:GetPivot()
	local gap = exit and (pivot.Position - exit.Position).Magnitude or 99
	local facing = exit and pivot.LookVector:Dot(exit.LookVector) or -1
	local entry = CarService.entry[userId]
	check(checks, "Drive out: at CarExit, facing out, driving, believed there",
		leftOk and gap <= TOL and facing > 0.999 and entry.driving and not entry.busy and CarService:HeldBy(player) == nil
			and not GarageVisitService.inTrigger(pivot.Position)
			and (CarService:BelievedPosition(userId) - exit.Position).Magnitude <= TOL,
		`ok {tostring(leftOk)} {tostring(leftReason)}; {r(gap)} from CarExit, facing dot {r(facing)}`)

	-- Too soon back in; then a flood.
	local soonOk, soonReason = GarageVisitService:_onAsk(player, true)
	GarageVisitService:DebugClearLimits()
	local flooded = 0
	for _ = 1, 10 do
		local _, why = GarageVisitService:_onAsk(player, nil)
		if why == "rate" then
			flooded += 1
		end
	end
	check(checks, "Back in too soon, and a flood, are refused", not soonOk and soonReason == "too soon"
		and flooded == 10 - Config.GarageMenu.RateLimit,
		`too soon: {tostring(soonReason)}; {flooded} of 10 questions refused "rate"`)

	-- IN BY THE DOOR: the server agrees the car is just inside it.
	GarageVisitService:DebugClearLimits()
	task.wait(0.3) -- the client's first packets from the exit
	local roomCF = CFrame.new(Config.GarageRoom.Origin) * CFrame.Angles(0, math.rad(Config.GarageRoom.Yaw), 0)
	local doorBefore = GarageVisitService.counts.byDoor
	-- Believed and checked in one go: the client is still sending packets from the street,
	-- and one of them, close enough, would move the belief before the next 0.1 s check.
	CarService:DebugBelieve(userId, roomCF:PointToWorldSpace(Vector3.new(-24, Config.Drift.RideHeight, 0)))
	GarageVisitService:_checkDoor()
	local byDoor = waitFor(function()
		return GarageVisitService.counts.byDoor > doorBefore
	end, 2)
	local doorState = GarageVisitService:VisitState(userId)
	check(checks, "In by the door: a car the server believes inside it goes in", byDoor and doorState.inGarage
		and doorState.how == "door" and (doorState.offTurntable or 99) <= TOL,
		`went in {tostring(byDoor)} by {tostring(doorState.how)}, {r(doorState.offTurntable)} off the deck`)

	-- A respawn calls the visit off; the car is the respawn's.
	local offBefore = GarageVisitService.counts.calledOff
	local placed = CarService:Place(player, CarService:SpawnCFrame())
	local entryAfter = CarService.entry[userId]
	check(checks, "A respawn calls the visit off and the car drives from where it was put",
		placed ~= nil and not GarageVisitService:InGarage(player) and GarageVisitService.counts.calledOff == offBefore + 1
			and entryAfter.driving and not entryAfter.busy and CarService:HeldBy(player) == nil,
		`placed {tostring(placed and placed.Position)}; visit {tostring(GarageVisitService:InGarage(player))}, called off {GarageVisitService.counts.calledOff - offBefore}`)

	GarageVisitService:DebugClearLimits()
	CarService:DebugClearEntryLimits()
end

function GarageVisitTests.run()
	local checks = {}
	pure(checks)
	local player = Players:GetPlayers()[1]
	if player then
		live(checks, player)
	else
		check(checks, "A player to test with", false, "none: run this in a playtest")
	end
	local passed, count = true, 0
	for _, c in checks do
		passed = passed and c.ok
		if c.ok then
			count += 1
		end
	end
	return { passed = passed, count = `{count}/{#checks}`, checks = checks }
end

return GarageVisitTests
