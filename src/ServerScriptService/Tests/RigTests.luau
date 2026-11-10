--!strict
-- RigTests: the car v2 rig, the stand-in built on it, and the module that moves it
-- (docs/game/features/car-v2.md "The rig", T-094).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugRigTests", "run")
--
-- Nothing here needs a player or a playtest: the stand-in is built at the origin, placed
-- by `Drift/Render` exactly as the game places a car, and read back off its own parts. The
-- times handed to `CarParts` are made up, so the timing checks are exact and instant.
--
-- Studio only, and no part of `run()`: put every live car in the stand-in, or take it out
-- again, to drive it in a playtest.
--
--   game.ServerStorage.DebugBridge:Invoke("DebugRigTests", "useStandIn", true)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")

assert(RunService:IsStudio(), "RigTests only runs in Studio")

local Bodies = require(ReplicatedStorage.Shared.Cars.Bodies)
local CarModel = require(ReplicatedStorage.Shared.CarModel)
local CarParts = require(ReplicatedStorage.Shared.CarParts)
local Config = require(ReplicatedStorage.Shared.Config)
local Rig = require(ReplicatedStorage.Shared.Cars.Rig)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Render = require(DriftFolder.Render)

local RigTests = {}

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
end

local function fmt(x: number): string
	return string.format("%.4f", x)
end

-- A stand-in car, built the way the game builds one.
local function standInCar(): Model
	local was = CarModel.bodyName()
	CarModel.setBody(CarModel.STANDIN)
	local car = CarModel.build()
	CarModel.setBody(if was == CarModel.STANDIN then CarModel.STANDIN else nil)
	return car
end

-- Every part of a car, by its full name inside the car.
local function partsOf(car: Model): { [string]: BasePart }
	local out = {}
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			out[d:GetFullName()] = d
		end
	end
	return out
end

-- Every part's CFrame, relative to the car's frame `cf`.
local function snapshot(car: Model, cf: CFrame): { [string]: CFrame }
	local out = {}
	for name, part in partsOf(car) do
		out[name] = cf:ToObjectSpace(part.CFrame)
	end
	return out
end

-- The largest gap between two snapshots: in position (studs), and in the rotation
-- matrices' entries compared one by one -- not as an angle, which a near-identity turn
-- reads with half a milliradian of noise of its own (acos near 1, in 32-bit numbers).
local function gap(a: { [string]: CFrame }, b: { [string]: CFrame }): (number, number, string)
	local worstP, worstR, where = 0, 0, ""
	for name, cfA in a do
		local cfB = b[name]
		if cfB then
			local d = (cfA.Position - cfB.Position).Magnitude
			local ca, cb = { cfA:GetComponents() }, { cfB:GetComponents() }
			for i = 4, 12 do
				worstR = math.max(worstR, math.abs(ca[i] - cb[i]))
			end
			if d > worstP then
				worstP, where = d, name
			end
		else
			worstP, where = math.huge, name .. " (missing)"
		end
	end
	return worstP, worstR, where
end

-- The parts of one group that moved more than `eps` between two snapshots.
local function movedGroups(a: { [string]: CFrame }, b: { [string]: CFrame }, eps: number): { [string]: boolean }
	local out = {}
	for name, cfA in a do
		local cfB = b[name]
		if cfB and (cfA.Position - cfB.Position).Magnitude > eps then
			local group = string.match(name, "Shell%.([^%.]+)%.") or name
			out[group] = true
		end
	end
	return out
end

local function sortedKeys(t: { [string]: any }): { string }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- A car frame that is not the identity, so nothing passes by accident at the origin.
local function somewhere(): CFrame
	return CFrame.new(37.5, Config.Drift.RideHeight + 3, -12.25) * CFrame.Angles(0.05, 0.9, -0.03)
end

function RigTests.run()
	local checks = {}
	local ride = Config.Drift.RideHeight
	local pivots = Rig.Pivots.parts

	local car = standInCar()
	local rig = Render.rig(car)
	local at = somewhere()
	Render.place(rig, at, 0, 0, 0)

	-- 1. It is a whole v2 rig, and the simulation's five parts are still there.
	do
		local shell = car:FindFirstChild(CarModel.SHELL_NAME)
		local groups, parts = 0, 0
		if shell then
			for _, g in shell:GetChildren() do
				if g:IsA("Model") then
					groups += 1
				end
			end
			for _, d in shell:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
		end
		local sim = 0
		for _, d in car:GetChildren() do
			if d:IsA("BasePart") then
				sim += 1
			end
		end
		check(
			checks,
			"the stand-in is a whole v2 rig on the five simulation parts",
			rig.complete and rig.groups ~= nil and CarParts.isRig(car) and sim == 5 and groups == shell:GetAttribute("G"),
			`body '{car:GetAttribute("Body")}', {groups} groups (G = {tostring(shell and shell:GetAttribute("G"))}), {parts} parts on {sim} simulation parts, rig complete {rig.complete}`
		)
	end

	-- 2. Every pivot in the pivot list is a group, drawn at its place: the group's frame,
	-- read back off its own parts, turned back into the list's axes.
	do
		local worst, worstName, missing, seen = 0, "", {}, 0
		for _, name in sortedKeys(pivots) do
			local shell = Render.group(rig, name)
			local frame = Render.shellFrame(shell)
			if not frame then
				table.insert(missing, name)
			else
				seen += 1
				local p = at:PointToObjectSpace(frame.Position)
				local back = { -p.X, p.Z, p.Y + ride }
				local o = pivots[name].origin
				local d = math.sqrt((back[1] - o[1]) ^ 2 + (back[2] - o[2]) ^ 2 + (back[3] - o[3]) ^ 2)
				if d > worst then
					worst, worstName = d, name
				end
			end
		end
		local lamps, lampMissing = 0, {}
		for name in Rig.Pivots.lights do
			if Render.group(rig, name) then
				lamps += 1
			else
				table.insert(lampMissing, name)
			end
		end
		check(
			checks,
			"every pivot in the pivot list is a group at its place (within 0.01)",
			#missing == 0 and worst < 0.01 and #lampMissing == 0,
			`{seen} of {seen + #missing} parts drawn, worst {string.format("%.6f", worst)} studs ({worstName}); `
				.. `{lamps} lamps as groups{if #missing > 0 then "; missing " .. table.concat(missing, ", ") else ""}`
				.. `{if #lampMissing > 0 then "; lamps missing " .. table.concat(lampMissing, ", ") else ""}`
		)
	end

	-- 3. Every hinge to its full travel turns its group exactly the list's angle about the
	-- list's axis, and back to shut puts every part of the car back where it was.
	do
		local shut = snapshot(car, at)
		local rows, ok = {}, true
		local worstBack = 0
		for _, name in sortedKeys(pivots) do
			local d = pivots[name]
			if d.kind == "hinge" then
				local shell = Render.group(rig, name)
				local before = Render.shellFrame(shell) :: CFrame
				CarParts.set(car, name, 1)
				Render.place(rig, at, 0, 0, 0)
				local after = Render.shellFrame(shell) :: CFrame
				local turn = before:ToObjectSpace(after)
				local axis, angle = turn:ToAxisAngle()
				local want = Rig.dirToCar(d.axis).Unit
				-- the same turn may read as the opposite axis and angle
				local signed = if axis:Dot(want) < 0 then -angle else angle
				-- and a needle's -240 reads as +120: compare round the circle
				local err = math.abs((math.deg(signed) - d.angle + 180) % 360 - 180)
				local axisErr = math.min((axis - want).Magnitude, (axis + want).Magnitude)
				local still = (after.Position - before.Position).Magnitude
				ok = ok and err < 0.01 and axisErr < 1e-3 and still < 1e-3
				CarParts.set(car, name, 0)
				Render.place(rig, at, 0, 0, 0)
				local back = snapshot(car, at)
				local p, r = gap(shut, back)
				worstBack = math.max(worstBack, p, r)
				table.insert(rows, string.format("%s %.2f/%.1f", name, math.deg(signed), d.angle))
			end
		end
		check(
			checks,
			"every hinge opens to its recorded angle, and back to shut is exactly shut",
			ok and worstBack == 0,
			`worst back-to-shut gap {worstBack} (studs, or a rotation entry); turned / recorded: {table.concat(rows, ", ")}`
		)
	end

	-- 4. The same out and back over time, through `open` and `close`: at the end every part
	-- is exactly where it started, and nothing is still moving.
	do
		local t = 1000
		local shut = snapshot(car, at)
		local longest = 0
		local names = {}
		for _, name in sortedKeys(pivots) do
			if pivots[name].kind == "hinge" and name ~= "HoodProp" then
				table.insert(names, name)
			end
		end
		for _, name in names do
			longest = math.max(longest, CarParts.open(car, name, t))
		end
		-- (a hair past the end: a move's seconds are kept as 32-bit numbers on the car)
		local openAmounts = {}
		for _, name in names do
			openAmounts[name] = CarParts.amount(car, name, t + longest + 1e-6)
		end
		local t2 = t + longest + 1
		local back = 0
		for _, name in names do
			back = math.max(back, CarParts.close(car, name, t2))
		end
		local allOpen, allShut = true, true
		for _, name in names do
			allOpen = allOpen and openAmounts[name] == 1
			allShut = allShut and CarParts.amount(car, name, t2 + back + 1e-6) == 0
		end
		allOpen = allOpen and CarParts.amount(car, "HoodProp", t + longest + 1e-6) == 1
		allShut = allShut and CarParts.amount(car, "HoodProp", t2 + back + 1e-6) == 0
		-- draw it shut through the real clock, which is long past both moves
		Render.place(rig, at, 0, 0, 0)
		local p, r = gap(shut, snapshot(car, at))
		check(
			checks,
			"every part opened and closed over time ends exactly shut",
			allOpen and allShut and p == 0 and r == 0 and not CarParts.busy(car, t2 + back + 1e-6),
			`{#names} parts and the prop rod: open after {fmt(longest)} s {allOpen}, shut after {fmt(back)} s {allShut}, `
				.. `drawn gap {p} studs, {r} in a rotation entry`
		)
	end

	-- 5. The hood lifts before the prop rod swings, and the rod comes down before the hood.
	do
		local t0 = 5000
		local total = CarParts.open(car, "Hood", t0)
		local order, firstProp, hoodDone = true, -1, -1
		for i = 0, math.ceil(total / 0.01) + 10 do
			local t = t0 + i * 0.01
			local hood, prop = CarParts.amount(car, "Hood", t), CarParts.amount(car, "HoodProp", t)
			if hood < 1 and prop > 0 then
				order = false
			end
			if prop > 0 and firstProp < 0 then
				firstProp = t - t0
			end
			if hood >= 1 and hoodDone < 0 then
				hoodDone = t - t0
			end
		end
		local t1 = t0 + total + 1
		local back = CarParts.close(car, "Hood", t1)
		local shutOrder, propDown, hoodMoves = true, -1, -1
		for i = 0, math.ceil(back / 0.01) + 10 do
			local t = t1 + i * 0.01
			local hood, prop = CarParts.amount(car, "Hood", t), CarParts.amount(car, "HoodProp", t)
			if prop > 0 and hood < 1 then
				shutOrder = false
			end
			if prop <= 0 and propDown < 0 then
				propDown = t - t1
			end
			if hood < 1 and hoodMoves < 0 then
				hoodMoves = t - t1
			end
		end
		check(
			checks,
			"the hood lifts before the prop rod swings, and the rod comes down first",
			order and shutOrder and firstProp >= hoodDone and hoodMoves >= propDown and total > 0,
			string.format(
				"opening: hood up at %.2f s, rod starts at %.2f s, all up at %.2f s; shutting: rod down at %.2f s, hood starts at %.2f s",
				hoodDone,
				firstProp,
				total,
				propDown,
				hoodMoves
			)
		)
		CarParts.set(car, "Hood", 0)
		CarParts.set(car, "HoodProp", 0)
	end

	-- 6. The struts point at each other as the hatch lifts, and the rod never leaves the tube.
	do
		local desc = CarParts.describe(car) :: CarParts.Desc
		local worst, shortest = 0, math.huge
		local rows = {}
		for _, amount in { 0, 0.25, 0.5, 0.75, 1 } do
			CarParts.set(car, "Hatch", amount)
			local frames = CarParts.frames(car, desc, 0)
			for _, side in { "L", "R" } do
				local tube, rod = desc.byName["StrutTube" .. side], desc.byName["StrutRod" .. side]
				local ft, fr = frames[tube.name], frames[rod.name]
				local between = fr.Position - ft.Position
				-- where each points now: its shut direction, turned with it
				local tubeDir = ft:VectorToWorldSpace(tube.rest).Unit
				local rodDir = fr:VectorToWorldSpace(rod.rest).Unit
				-- the angle off its cross product, which stays exact where acos of a dot near 1
				-- would read 0.02 degrees of its own noise
				local u = between.Unit
				local e1 = math.deg(math.atan2(tubeDir:Cross(u).Magnitude, tubeDir:Dot(u)))
				local e2 = math.deg(math.atan2(rodDir:Cross(-u).Magnitude, rodDir:Dot(-u)))
				worst = math.max(worst, e1, e2)
				local tubePart = tube.model:FindFirstChild("Tube") :: BasePart
				local rodPart = rod.model:FindFirstChild("Rod") :: BasePart
				local overlap = tubePart.Size.Z + rodPart.Size.Z - between.Magnitude
				shortest = math.min(shortest, overlap)
				if side == "L" then
					table.insert(rows, string.format("%.2f: pins %.3f apart", amount, between.Magnitude))
				end
			end
		end
		CarParts.set(car, "Hatch", 0)
		check(
			checks,
			"the hatch struts aim at each other all the way up, and stay in each other",
			worst < 0.01 and shortest > 0.05,
			string.format("worst aim %.5f deg, least overlap %.3f studs; %s", worst, shortest, table.concat(rows, ", "))
		)
	end

	-- 7. A wheel's lift moves its hub, its wheel and its caliper, by exactly that, and
	-- nothing else; and back to 0 is back where it was.
	do
		local base = snapshot(car, at)
		Render.setWheelLift(rig, "WheelFL", 0.3)
		Render.place(rig, at, 0, 0, 0)
		local lifted = snapshot(car, at)
		local moved = movedGroups(base, lifted, 1e-4)
		Render.setWheelLift(rig, "WheelFL", 0)
		Render.place(rig, at, 0, 0, 0)
		local p = gap(base, snapshot(car, at))
		local wheelPart = (Render.group(rig, "WheelFL") :: any).parts[1].part
		local deltaY = lifted[wheelPart:GetFullName()].Position.Y - base[wheelPart:GetFullName()].Position.Y
		local names = sortedKeys(moved)
		local want = { CaliperFL = true, WheelFL = true }
		local onlyThose = true
		for _, n in names do
			-- the simulation's own wheel part is a direct child, not in the shell
			if not (want[n] or string.find(n, "Car%.WheelFL$")) then
				onlyThose = false
			end
		end
		check(
			checks,
			"a wheel's lift moves its hub, wheel and caliper by exactly that, and nothing else",
			math.abs(deltaY - 0.3) < 1e-4 and onlyThose and moved.WheelFL == true and moved.CaliperFL == true and p == 0,
			string.format("lift 0.3: wheel up %.5f, moved [%s]; back to 0: gap %s", deltaY, table.concat(names, ", "), tostring(p))
		)
	end

	-- 8. The front hubs steer and the rear ones do not; the wheels spin, the calipers do not.
	do
		local rows, ok = {}, true
		Render.place(rig, at, math.rad(25), math.rad(40), 0)
		for _, wheel in Rig.WHEELS do
			local suffix = string.sub(wheel, 6)
			local w = Render.shellFrame(Render.group(rig, wheel)) :: CFrame
			local c = Render.shellFrame(Render.group(rig, "Caliper" .. suffix)) :: CFrame
			local front = suffix == "FL" or suffix == "FR"
			local _, cy = at:ToObjectSpace(c):ToOrientation()
			local wp = select(1, (at * CFrame.Angles(0, if front then math.rad(25) else 0, 0)):ToObjectSpace(w):ToOrientation())
			local wantYaw = if front then 25 else 0
			ok = ok and math.abs(math.deg(cy) - wantYaw) < 0.01 and math.abs(math.deg(wp) - 40) < 0.01
			table.insert(rows, string.format("%s caliper yaw %+.2f, wheel spin %+.2f", suffix, math.deg(cy), math.deg(wp)))
		end
		Render.place(rig, at, 0, 0, 0)
		check(checks, "the front hubs steer, the rear do not; wheels spin, calipers do not", ok, table.concat(rows, "; "))
	end

	-- 9. An open door rides with the car: wherever and however the car is put, leaning or
	-- not, the door's place relative to the body does not move.
	do
		CarParts.set(car, "DoorR", 1)
		CarParts.set(car, "DoorL", 0.5)
		local function rel(name: string): CFrame
			local body = Render.shellFrame(rig.bodyShell) :: CFrame
			return body:ToObjectSpace(Render.shellFrame(Render.group(rig, name)) :: CFrame)
		end
		local rng = Random.new(94)
		local first: { [string]: CFrame } = {}
		local worst = 0
		for i = 1, 40 do
			local cf = CFrame.new(rng:NextNumber(-3000, 3000), rng:NextNumber(0, 200), rng:NextNumber(-3000, 3000))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-math.pi, math.pi), rng:NextNumber(-0.3, 0.3))
			Render.place(rig, cf, rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 50), rng:NextNumber(-0.17, 0.17))
			for _, name in { "DoorR", "DoorL", "DoorGlassR" } do
				local r = rel(name)
				if not first[name] then
					first[name] = r
				else
					worst = math.max(worst, (r.Position - first[name].Position).Magnitude)
				end
			end
		end
		CarParts.set(car, "DoorR", 0)
		CarParts.set(car, "DoorL", 0)
		Render.place(rig, at, 0, 0, 0)
		check(
			checks,
			"an open door stays on the body wherever the car goes (to 0.001)",
			worst < 0.001,
			string.format("40 random poses up to 3000 studs out, leaning: door offset from the body moved %.6f studs at most", worst)
		)
	end

	-- 10. The points: the driver's seat on the right, the exit on the ground outside the
	-- driver's door, and the nine floor points under the car.
	do
		local desc = CarParts.describe(car) :: CarParts.Desc
		local seat, exit = desc.seat, desc.exit
		local floorCount, floorY = 0, 0
		for _, p in desc.floor do
			floorCount += 1
			floorY = math.max(floorY, math.abs(p.Y - (Rig.FLOOR.FloorMC[3] - ride)))
		end
		local doorX = -pivots.DoorR.origin[1] -- the driver's door, in the car's frame (right)
		local ok = seat ~= nil
			and exit ~= nil
			and seat.Position.X > 0
			and exit.Position.X > doorX
			and math.abs(exit.Position.Y + ride) < 1e-4
			and floorCount == 9
			and floorY < 1e-4
		check(
			checks,
			"the seat, the exit and the floor points are on the shell",
			ok,
			string.format(
				"seat %s, exit %s (door hinge at x %.2f), %d floor points %.2f above the road",
				tostring(seat and seat.Position),
				tostring(exit and exit.Position),
				doorX,
				floorCount,
				Rig.FLOOR.FloorMC[3]
			)
		)
	end

	-- 11. Nothing in it is physics, and nothing came along that should not have.
	do
		local phys = CarModel.physicsOffenders(car)
		local stray = CarModel.strayOffenders(car)
		local anchored, parts = 0, 0
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch then
					anchored += 1
				end
			end
		end
		check(
			checks,
			"the stand-in builds with no physics object and nothing stray",
			#phys == 0 and #stray == 0 and anchored == parts,
			`{parts} parts, {anchored} anchored with no collision, query or touch; {#phys} physics offenders, {#stray} stray`
		)
	end
	car:Destroy()

	-- 12. The bodies that were here are not rigs, and draw exactly as before.
	do
		local rows, ok = {}, true
		for _, key in { "block", table.unpack(Bodies.Order) } do
			CarModel.setBody(key)
			local c = CarModel.build()
			local r = Render.rig(c)
			Render.place(r, CFrame.new(0, ride, 0), 0, 0, 0)
			local isRig = CarParts.isRig(c)
			ok = ok and not isRig and r.complete and r.groups == nil
			table.insert(rows, `{key} rig {isRig}, complete {r.complete}`)
			c:Destroy()
		end
		CarModel.setBody(nil)
		check(checks, "the other bodies are not rigs and still draw", ok, table.concat(rows, ", "))
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

-- Studio only: every live car into the stand-in (`on` true) or back to its own body
-- (`on` false), through the server's own dressing, so every client sees it.
function RigTests:useStandIn(on: boolean?): string
	CarModel.setBody(if on == false then nil else CarModel.STANDIN)
	local CarService = require(ServerScriptService.Services.CarService) :: any
	local done = {}
	for _, player in Players:GetPlayers() do
		local car = CarService.cars[player.UserId]
		if car and car.Parent then
			CarService:_dress(car, CarService:CarKey(player))
			table.insert(done, `{player.Name}: {tostring(car:GetAttribute("Body"))}`)
		end
	end
	return `body '{CarModel.bodyName()}'; {table.concat(done, ", ")}`
end

return RigTests
