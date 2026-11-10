--!nonstrict
-- CarEntryTests: getting in and out of the car (docs/game/features/car-v2.md, T-096).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugCarEntryTests", "run")
--
-- Two halves. The first needs nothing: the seat and exit points, off a rig and off the
-- fallbacks, and the driver's door on a synthetic rig. The second needs a playtest -- one
-- player, in their car -- and goes in at the REAL handlers (`CarService:_onExit`,
-- `_onEnter`): the checks the server makes, the refusals (too fast, too far, not the owner,
-- junk, too often, the wrong state), a parked car that does not move, and ten full cycles
-- of getting out and back in with the avatar measured at the seat and at the exit each
-- time. The player's own client follows along, exactly as it does when the button is
-- pressed: the answers go to it either way.
--
-- What only a client can measure -- the avatar's gap from the seat of the car AS DRAWN on
-- every frame, and the remote view -- is `CarEntryController:DebugCycles` and
-- `DebugRemoteDriver`, on the client bridge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "CarEntryTests only runs in Studio")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local CarParts = require(ReplicatedStorage.Shared.CarParts)
local Config = require(ReplicatedStorage.Shared.Config)
local Rig = require(ReplicatedStorage.Shared.Cars.Rig)

local Driver = require(StarterPlayer.StarterPlayerScripts:WaitForChild("Drift"):WaitForChild("Driver"))
local CarService = require(ServerScriptService.Services.CarService)

local CarEntryTests = {}

local TOL = 0.05 -- studs: "the avatar within 0.05 of the seat point"

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
end

local function near(a: CFrame, b: CFrame, tol: number?): boolean
	tol = tol or 1e-4
	if (a.Position - b.Position).Magnitude > tol then
		return false
	end
	local ca, cb = { a:GetComponents() }, { b:GetComponents() }
	for i = 4, 12 do
		if math.abs(ca[i] - cb[i]) > 1e-4 then
			return false
		end
	end
	return true
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

-- The block car wearing a rig that has a seat, an exit and a driver's door: the shape an
-- imported model will have.
local SEAT = CFrame.new(1.4, -0.9, 0.7)
local EXIT = CFrame.new(5.9, -2.4, 0.7)
local function rigCar(): Model
	CarModel.setBody("block")
	local car = CarModel.build()
	CarModel.setBody(nil)
	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Size = Vector3.new(0.2, 2, 5)
	panel.CFrame = CFrame.new(3.3, 0, 0)
	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Size = Vector3.new(6, 3, 14)
	CarModel.dress(
		car,
		Rig.assemble({
			body = { shell },
			groups = {
				{
					name = Config.CarEntry.DoorName,
					kind = "hinge",
					pivot = Vector3.new(3.2, 0, -2.5),
					axis = Vector3.yAxis,
					open = 62,
					seconds = 0.4,
					parts = { panel },
				},
			},
			seat = SEAT,
			exit = EXIT,
		})
	)
	return car
end

-- ---------------------------------------------------------------- without a player

local function pure(checks)
	local E = Config.CarEntry

	-- 1. Today's cars: the fallbacks.
	do
		CarModel.setBody("block")
		local car = CarModel.build()
		CarModel.setBody(nil)
		local seat, exit, fromRig = Driver.points(car)
		check(
			checks,
			"a car with no rig uses the fallback seat and exit",
			near(seat, E.SeatFallback) and near(exit, E.ExitFallback) and not fromRig,
			`seat {seat.Position}, exit {exit.Position}, fromRig {fromRig}`
		)
		car:Destroy()
	end

	-- 2. A rig's own points win, and the seat follows the body wherever it is drawn.
	local car = rigCar()
	do
		local seat, exit, fromRig = Driver.points(car)
		check(
			checks,
			"a rig's Seat and Exit are used when it has them",
			near(seat, SEAT) and near(exit, EXIT) and fromRig,
			`seat {seat.Position}, exit {exit.Position}, fromRig {fromRig}`
		)
		local body = CFrame.new(40, 6, -12) * CFrame.Angles(0.04, 1.1, -0.06)
		local want = body * SEAT * CFrame.new(0, E.RootAboveSeat, 0)
		check(
			checks,
			"the seated root is the drawn body's seat, lifted by RootAboveSeat",
			near(Driver.seatRoot(body, car), want),
			`gap {(Driver.seatRoot(body, car).Position - want.Position).Magnitude}`
		)
	end

	-- 3. The driver's door: opened and shut by the server through CarParts, over its own
	-- time, so every client sees it.
	do
		local opening = CarService:_door(car, true)
		local now = CarParts.now()
		local midway = CarParts.amount(car, E.DoorName, now + opening * 0.5)
		local open = CarParts.amount(car, E.DoorName, now + opening + 0.01)
		CarParts.set(car, E.DoorName, 1) -- all the way open, now: the shut has its full travel
		local shutting = CarService:_door(car, false)
		local shut = CarParts.amount(car, E.DoorName, CarParts.now() + shutting + 0.01)
		check(
			checks,
			"the rig's DoorR opens and shuts over its Seconds",
			math.abs(opening - 0.4) < 1e-3
				and midway > 0.3
				and midway < 0.7
				and open > 0.999
				and math.abs(shutting - 0.4) < 1e-3
				and shut < 1e-3,
			`opening {opening}s, halfway {midway}, open {open}, shut {shut} after {shutting}s`
		)
		local plain = CarModel.build()
		local none = CarService:_door(plain, true)
		check(checks, "a car with no rig has no door to wait for", none == E.NoDoorSeconds, `{none}s`)
		plain:Destroy()
	end
	car:Destroy()
end

-- ---------------------------------------------------------------- with a player

local function serverSeatGap(player: Player, car: Model): number
	local root = Driver.rootOf(player.Character)
	local body = car:FindFirstChild(CarModel.BODY_NAME)
	if not root or not body then
		return math.huge
	end
	return (root.Position - Driver.seatRoot(body.CFrame, car).Position).Magnitude
end

local function live(checks, player: Player)
	local E = Config.CarEntry
	local id = player.UserId
	local car = CarService.cars[id]
	local seen = CarService.seen[id]
	if not car or not seen then
		check(checks, "the player has a car", false, "no car for " .. id)
		return
	end
	CarService:DebugClearEntryLimits()

	-- The car drives itself (the throttle eases in), so getting out needs it stopped: put
	-- the handbrake on from the client first (`CarInputController:DebugSetBrake(true)`).
	local stopped = waitFor(function()
		local v = seen.lastVelocity or Vector3.zero
		return Vector3.new(v.X, 0, v.Z).Magnitude < E.ExitSpeed * 0.5
	end, 8)
	if not stopped then
		check(checks, "the car is stopped (handbrake on from the client)", false, `speed {seen.lastVelocity}`)
		return
	end

	-- 4. In the seat from the start: anchored, the server's copy where the seat is, and the
	-- car still has nothing in it that is physics.
	do
		local state = CarService:EntryState(id)
		local gap = serverSeatGap(player, car)
		check(
			checks,
			"the player starts in the driver's seat",
			state.driving and state.driver == id and state.rootAnchored == true and gap <= TOL,
			`driving {state.driving}, driver {state.driver}, anchored {state.rootAnchored}, gap {gap}`
		)
		local phys, stray = CarModel.physicsOffenders(car), CarModel.strayOffenders(car)
		local inside = player.Character and player.Character:IsDescendantOf(car)
		check(
			checks,
			"no Seat, weld, joint or prompt in the car, and the avatar is not inside it",
			#phys == 0 and #stray == 0 and not inside,
			`{#phys} physics, {#stray} stray, avatar inside {inside}`
		)
	end

	-- 5. Refusals while driving.
	do
		local was = seen.lastVelocity
		seen.lastVelocity = Vector3.new(E.ExitSpeed * E.ExitSpeedTolerance + 1, 0, 0)
		local r = CarService:DebugExit(nil, id)
		seen.lastVelocity = was
		local state = CarService:EntryState(id)
		check(
			checks,
			"getting out is refused too fast, and nothing changes",
			not r.ok and r.reason == "too fast" and state.driving and state.driver == id,
			`{r.ok} {r.reason}, still driving {state.driving}`
		)

		local other = Instance.new("Model")
		other.Name = "Car_NotYours"
		other:SetAttribute("UserId", id + 1)
		other.Parent = CarService.folder
		CarService:DebugClearEntryLimits()
		local r2 = CarService:DebugEnter(other, id)
		other:Destroy()
		check(checks, "getting into another player's car is refused", not r2.ok and r2.reason == "not owner", `{r2.reason}`)

		local junk = {}
		for _, value in { "Car", 42, true, Instance.new("Part"), workspace, {} } do
			CarService:DebugClearEntryLimits()
			local rj = CarService:DebugEnter(value, id)
			if rj.ok or rj.reason ~= "no car" then
				table.insert(junk, typeof(value) .. " -> " .. tostring(rj.reason))
			end
		end
		check(checks, "junk instead of a car is refused", #junk == 0, if #junk == 0 then "6 refused" else table.concat(junk, ", "))

		CarService:DebugClearEntryLimits()
		local r3 = CarService:DebugEnter(nil, id)
		check(checks, "getting in while driving is refused", not r3.ok and r3.reason == "not out", `{r3.reason}`)

		CarService:DebugClearEntryLimits()
		local burst = {}
		for _ = 1, E.RateLimit + 2 do
			table.insert(burst, CarService:DebugEnter(nil, id).reason)
		end
		check(
			checks,
			"asking more than RateLimit times a second is refused",
			burst[#burst] == "rate" and burst[E.RateLimit] ~= "rate",
			table.concat(burst, ", ")
		)
		CarService:DebugClearEntryLimits()
	end

	-- 6. A pose from the client that does not follow from the agreed one is not believed:
	-- the car parks where the server agreed it was. Then, parked, nothing moves it.
	local parkedCF
	do
		local agreed = seen.lastCF or car:GetPivot()
		local liar = agreed * CFrame.new(900, 0, 0)
		local r = CarService:DebugExit(liar, id)
		parkedCF = car:GetPivot()
		check(
			checks,
			"a far-off pose on Get out is not believed: the car parks where the server agreed",
			r.ok and (parkedCF.Position - agreed.Position).Magnitude < 1 and (parkedCF.Position - liar.Position).Magnitude > 800,
			`{r.reason}, parked {(parkedCF.Position - agreed.Position).Magnitude} from agreed`
		)
		local out = waitFor(function()
			return CarService:EntryState(id).driver == nil and not CarService:EntryState(id).busy
		end, 5)
		local root = Driver.rootOf(player.Character)
		local feet = (parkedCF * select(2, Driver.points(car))).Position
		local standing = root and (root.Position - Vector3.new(0, Driver.rootAboveFeet(player.Character), 0) - feet).Magnitude
		check(
			checks,
			"out: the seat is empty and the avatar stands at the exit point, free",
			out and root ~= nil and not root.Anchored and standing ~= nil and standing <= 0.5,
			`out {out}, anchored {root and root.Anchored}, feet {standing} from the exit point`
		)

		-- Parked: CarState packets are dropped and the car stays put, server and all.
		local before = CarService.parkedDropped
		for i = 1, 5 do
			CarService:_onState(player, parkedCF * CFrame.new(0, 0, -i), Vector3.new(0, 0, -20), false)
		end
		task.wait(0.5)
		local moved = (car:GetPivot().Position - parkedCF.Position).Magnitude
		check(
			checks,
			"a parked car takes no CarState and does not move",
			CarService.parkedDropped - before >= 5 and moved < 1e-4,
			`{CarService.parkedDropped - before} dropped, moved {moved}`
		)

		CarService:DebugClearEntryLimits()
		local r4 = CarService:DebugExit(nil, id)
		check(checks, "getting out while out is refused", not r4.ok and r4.reason == "not driving", `{r4.reason}`)
	end

	-- 7. Too far from the door, then near it.
	do
		local root = Driver.rootOf(player.Character)
		local door = Driver.doorPoint(parkedCF, car)
		local reach = E.PromptDistance + E.EnterDistanceSlack
		if root then
			root.CFrame = CFrame.new(door + Vector3.new(reach + 6, 0, 0))
		end
		CarService:DebugClearEntryLimits()
		local far = CarService:DebugEnter(nil, id)
		check(checks, "getting in from too far is refused", not far.ok and far.reason == "too far", `{far.reason} at {reach + 6} studs`)
		if root then
			root.CFrame = CFrame.new(door + Vector3.new(2, 0, 0))
		end
		CarService:DebugClearEntryLimits()
		local nearby = CarService:DebugEnter(nil, id)
		local back = waitFor(function()
			local s = CarService:EntryState(id)
			return s.driving and not s.busy
		end, 5)
		local gap = serverSeatGap(player, car)
		check(
			checks,
			"getting in from beside the door: seated, anchored, driving",
			nearby.ok and back and CarService:EntryState(id).driver == id and gap <= TOL,
			`{nearby.ok} {nearby.reason}, back {back}, seat gap {gap}`
		)
	end

	-- 8. Ten cycles. Each: out (the car parks, the avatar at the exit, free), then in from
	-- beside the door (seated, anchored, the seat empty in between).
	do
		local rows, worstSeat, worstExit, done = {}, 0, 0, 0
		for i = 1, 10 do
			task.wait(0.25) -- the client drives a moment and reports where it is
			CarService:DebugClearEntryLimits()
			local exitR = CarService:DebugExit(nil, id)
			if not exitR.ok then
				table.insert(rows, `{i}: out refused {exitR.reason}`)
				break
			end
			local park = car:GetPivot()
			if not waitFor(function()
				local s = CarService:EntryState(id)
				return s.driver == nil and not s.busy
			end, 5) then
				table.insert(rows, `{i}: never out`)
				break
			end
			local root = Driver.rootOf(player.Character)
			if not root or root.Anchored then
				table.insert(rows, `{i}: avatar still anchored`)
				break
			end
			local feet = (park * select(2, Driver.points(car))).Position
			worstExit = math.max(
				worstExit,
				(root.Position - Vector3.new(0, Driver.rootAboveFeet(player.Character), 0) - feet).Magnitude
			)
			root.CFrame = CFrame.new(Driver.doorPoint(park, car) + Vector3.new(1.5, 0, 0))
			CarService:DebugClearEntryLimits()
			local enterR = CarService:DebugEnter(nil, id)
			if not enterR.ok then
				table.insert(rows, `{i}: in refused {enterR.reason}`)
				break
			end
			if not waitFor(function()
				local s = CarService:EntryState(id)
				return s.driving and not s.busy
			end, 5) then
				table.insert(rows, `{i}: never in`)
				break
			end
			worstSeat = math.max(worstSeat, serverSeatGap(player, car))
			if (car:GetPivot().Position - park.Position).Magnitude > 1e-4 then
				table.insert(rows, `{i}: the car moved while parked`)
				break
			end
			done = i
		end
		check(
			checks,
			"ten cycles of getting out and back in",
			done == 10 and worstSeat <= TOL and worstExit <= 0.5,
			`{done}/10, worst seat gap {worstSeat}, worst exit gap {worstExit}{if #rows > 0 then "; " .. table.concat(rows, "; ") else ""}`
		)
	end

	-- 9. A respawn while out puts the driver back in: the car is put somewhere, and a car
	-- put somewhere has its driver in it.
	do
		CarService:DebugClearEntryLimits()
		local r = CarService:DebugExit(nil, id)
		waitFor(function()
			return CarService:EntryState(id).driver == nil and not CarService:EntryState(id).busy
		end, 5)
		local respawned = CarService:Place(player, CarService:SpawnCFrame())
		local s = CarService:EntryState(id)
		check(
			checks,
			"a respawn while out sits the driver back in",
			r.ok and respawned ~= nil and s.driving and s.driver == id and serverSeatGap(player, car) <= TOL,
			`exit {r.ok}, respawned {respawned ~= nil}, driving {s.driving}, driver {s.driver}`
		)
	end
end

function CarEntryTests.run()
	local checks = {}
	pure(checks)
	local player = Players:GetPlayers()[1]
	if player then
		live(checks, player)
	else
		check(checks, "a player is in the game (the live checks need a playtest)", false, "no player")
	end
	CarService:DebugClearEntryLimits()
	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return CarEntryTests
