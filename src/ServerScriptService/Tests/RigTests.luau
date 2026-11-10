--!strict
-- RigTests: the car v2 rig architecture -- `Shared/Cars/Rig`, `Shared/CarParts` and the
-- v2 path through `Drift/Render` (docs/game/features/car-v2.md "The rig", T-094).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugRigTests", "run")
--
-- On a SYNTHETIC rig: a handful of boxes assembled through `Rig.assemble` -- a door with a
-- window riding on it, a hood and its prop rod, a strut, a lamp, and a hub, wheel and
-- caliper at a front and a rear corner -- dressed onto the block car exactly as an imported
-- model will be. No real car is built on the rig yet: the user is bringing a new model, and
-- this proves the architecture it will drop into. Nothing here needs a player or a
-- playtest; the times handed to `CarParts` are made up, so the timing checks are exact.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

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

local function box(name: string, at: Vector3, size: Vector3, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(at)
	if shape then
		p.Shape = shape
	end
	return p
end

-- The synthetic rig's hinges. Its numbers are the shape of a small car and nothing more:
-- what is under test is that whatever a model says, it is honoured.
local HINGES = {
	DoorR = { axis = Vector3.yAxis, open = 62 },
	DoorGlassR = { axis = Vector3.zAxis, open = 12 },
	Hood = { axis = Vector3.xAxis, open = 48 },
	HoodProp = { axis = Vector3.xAxis, open = 60 },
}

local function spec(): Rig.ShellSpec
	local y = Config.Drift.WheelDiameter * 0.5 - Config.Drift.RideHeight -- the hub plane
	local function hinge(name: string, pivot: Vector3, seconds: number, on: string?, parts: { BasePart }): Rig.GroupSpec
		return {
			name = name,
			kind = "hinge",
			pivot = pivot,
			axis = HINGES[name].axis,
			open = HINGES[name].open,
			seconds = seconds,
			on = on,
			parts = parts,
		}
	end
	local function corner(c: string, z: number, steer: number?): { Rig.GroupSpec }
		local hub = Vector3.new(-2.8, y, z)
		return {
			{ name = "Hub" .. c, kind = "hub", pivot = hub, steer = steer, wheel = "Wheel" .. c, parts = {} },
			{
				name = "Wheel" .. c,
				kind = "spin",
				pivot = hub,
				on = "Hub" .. c,
				parts = { box("Tire", hub, Vector3.new(1.2, 2.6, 2.6), Enum.PartType.Cylinder) },
			},
			{
				name = "Caliper" .. c,
				kind = "fixed",
				pivot = hub,
				on = "Hub" .. c,
				parts = { box("Caliper", hub + Vector3.new(-0.1, 0, 0.5), Vector3.new(0.3, 0.5, 0.3)) },
			},
		}
	end
	local groups: { Rig.GroupSpec } = {
		hinge("DoorR", Vector3.new(3.2, 0, -2.5), 0.8, nil, { box("Panel", Vector3.new(3.3, 0, 0), Vector3.new(0.2, 2, 5)) }),
		hinge("DoorGlassR", Vector3.new(3.3, 1, 0), 2, "DoorR", { box("Glass", Vector3.new(3.3, 1.5, 0), Vector3.new(0.1, 1, 3)) }),
		hinge("Hood", Vector3.new(0, 1, -3), 1, nil, { box("Panel", Vector3.new(0, 1, -5), Vector3.new(5, 0.1, 4)) }),
		hinge("HoodProp", Vector3.new(2, 0.5, -6), 0.5, nil, { box("Rod", Vector3.new(2, 0.5, -5), Vector3.new(0.05, 0.05, 2)) }),
		-- a gas strut between the hood and the body: each half aims at the other
		{
			name = "StrutTube",
			kind = "aim",
			pivot = Vector3.new(1.5, 0.95, -4.5),
			at = "StrutRod",
			on = "Hood",
			parts = { box("Tube", Vector3.new(1.5, 0.725, -4), Vector3.new(0.1, 0.1, 0.5)) },
		},
		{
			name = "StrutRod",
			kind = "aim",
			pivot = Vector3.new(1.5, 0.5, -3.5),
			at = "StrutTube",
			parts = { box("Rod", Vector3.new(1.5, 0.725, -4), Vector3.new(0.05, 0.05, 0.5)) },
		},
		{
			name = "HeadlightL",
			kind = "light",
			pivot = Vector3.new(-2, 0.3, -6.05),
			lamp = "headlight",
			parts = { box("Lens", Vector3.new(-2, 0.3, -6.05), Vector3.new(0.8, 0.4, 0.1)) },
		},
	}
	for _, g in corner("FL", -4.8, 30) do
		table.insert(groups, g)
	end
	for _, g in corner("RL", 4.8, nil) do
		table.insert(groups, g)
	end
	return {
		body = { box("Hull", Vector3.zero, Vector3.new(6, 2, 12)) },
		groups = groups,
		seat = CFrame.new(1.45, -0.5, 0.3),
		exit = CFrame.new(5, -Config.Drift.RideHeight, 0.6),
		floor = { FloorFL = Vector3.new(-3, -1.8, -6), FloorMC = Vector3.new(0, -1.8, 0), FloorRR = Vector3.new(3, -1.8, 6) },
	}
end

-- The block car wearing the synthetic rig, the way an imported model will be dressed on.
local function rigCar(): (Model, Rig.ShellSpec)
	CarModel.setBody("block")
	local car = CarModel.build()
	CarModel.setBody(nil)
	local s = spec()
	CarModel.dress(car, Rig.assemble(s))
	return car, s
end

local function snapshot(car: Model, cf: CFrame): { [string]: CFrame }
	local out = {}
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			out[d:GetFullName()] = cf:ToObjectSpace(d.CFrame)
		end
	end
	return out
end

-- The largest gap between two snapshots: in position (studs), and in the rotation
-- matrices' entries one by one -- not as an angle, which a near-identity turn reads with
-- half a milliradian of its own noise (acos near 1, in 32-bit numbers).
local function gap(a: { [string]: CFrame }, b: { [string]: CFrame }): (number, number)
	local worstP, worstR = 0, 0
	for name, cfA in a do
		local cfB = b[name]
		if not cfB then
			return math.huge, math.huge
		end
		worstP = math.max(worstP, (cfA.Position - cfB.Position).Magnitude)
		local ca, cb = { cfA:GetComponents() }, { cfB:GetComponents() }
		for i = 4, 12 do
			worstR = math.max(worstR, math.abs(ca[i] - cb[i]))
		end
	end
	return worstP, worstR
end

local function movedGroups(a: { [string]: CFrame }, b: { [string]: CFrame }): { string }
	local seen, out = {}, {}
	for name, cfA in a do
		if (cfA.Position - b[name].Position).Magnitude > 1e-4 then
			local group = string.match(name, "Shell%.([^%.]+)%.") or name
			if not seen[group] then
				seen[group] = true
				table.insert(out, group)
			end
		end
	end
	table.sort(out)
	return out
end

-- A car frame that is not the identity, so nothing passes by accident at the origin.
local AT = CFrame.new(37.5, 5.4, -12.25) * CFrame.Angles(0.05, 0.9, -0.03)

function RigTests.run()
	local checks = {}
	local car, s = rigCar()
	local rig = Render.rig(car)
	Render.place(rig, AT, 0, 0, 0)

	-- 1. Assembled, dressed and drawn: every group where its pivot says, read back off its
	-- own parts.
	do
		local worst, drawn, missing = 0, 0, {}
		for _, g in s.groups do
			if #g.parts > 0 then -- a hub may hold nothing: it is a frame for what rides on it
				local frame = Render.shellFrame(Render.group(rig, g.name))
				if frame then
					drawn += 1
					worst = math.max(worst, (AT:PointToObjectSpace(frame.Position) - g.pivot).Magnitude)
				else
					table.insert(missing, g.name)
				end
			end
		end
		local shell = car:FindFirstChild(CarModel.SHELL_NAME)
		check(
			checks,
			"an assembled rig is whole, and every group is drawn at its pivot",
			rig.complete and CarParts.isRig(car) and #missing == 0 and worst < 0.01,
			`{drawn} groups with parts drawn, worst {string.format("%.6f", worst)} studs off; G = {tostring(shell and shell:GetAttribute("G"))}, `
				.. `complete {rig.complete}{if #missing > 0 then "; missing " .. table.concat(missing, ", ") else ""}`
		)
	end

	-- 2. Every hinge to its full travel turns exactly its `Open` about its `Axis`, about its
	-- pivot; and back to shut is exactly shut, every part of the car.
	do
		local shut = snapshot(car, AT)
		local rows, ok, worstBack = {}, true, 0
		for name, h in HINGES do
			local group = Render.group(rig, name)
			local before = Render.shellFrame(group) :: CFrame
			CarParts.set(car, name, 1)
			Render.place(rig, AT, 0, 0, 0)
			local after = Render.shellFrame(group) :: CFrame
			local axis, angle = before:ToObjectSpace(after):ToAxisAngle()
			local signed = if axis:Dot(h.axis) < 0 then -angle else angle
			local err = math.abs(math.deg(signed) - h.open)
			ok = ok and err < 0.01 and (after.Position - before.Position).Magnitude < 1e-3
			CarParts.set(car, name, 0)
			Render.place(rig, AT, 0, 0, 0)
			local p, r = gap(shut, snapshot(car, AT))
			worstBack = math.max(worstBack, p, r)
			table.insert(rows, string.format("%s %.3f/%d", name, math.deg(signed), h.open))
		end
		check(
			checks,
			"every hinge opens to its angle, and back to shut is exactly shut",
			ok and worstBack == 0,
			`turned / asked: {table.concat(rows, ", ")}; worst back-to-shut gap {worstBack}`
		)
	end

	-- 3. Out and back over time through `open` and `close`: exactly shut at the end.
	do
		local shut = snapshot(car, AT)
		local t = 1000
		local out = math.max(CarParts.open(car, "DoorR", t), CarParts.open(car, "Hood", t))
		-- (a hair past the end: a move's seconds are held as 32-bit numbers on the car)
		local e = 1e-6
		local opened = CarParts.amount(car, "DoorR", t + out + e) == 1
			and CarParts.amount(car, "Hood", t + out + e) == 1
			and CarParts.amount(car, "HoodProp", t + out + e) == 1
		local t2 = t + out + 1
		local back = math.max(CarParts.close(car, "DoorR", t2), CarParts.close(car, "Hood", t2))
		local closed = CarParts.amount(car, "DoorR", t2 + back + e) == 0
			and CarParts.amount(car, "Hood", t2 + back + e) == 0
			and CarParts.amount(car, "HoodProp", t2 + back + e) == 0
		Render.place(rig, AT, 0, 0, 0) -- the real clock, long past both moves
		local p, r = gap(shut, snapshot(car, AT))
		check(
			checks,
			"opened and closed over time, every part ends exactly shut",
			opened and closed and p == 0 and r == 0 and not CarParts.busy(car, t2 + back + e),
			string.format(
				"open in %.2f s %s, shut in %.2f s %s, drawn gap %s / %s",
				out,
				tostring(opened),
				back,
				tostring(closed),
				tostring(p),
				tostring(r)
			)
		)
	end

	-- 4. The hood lifts before the prop rod swings, and the rod comes down first.
	do
		local t0 = 5000
		local total = CarParts.open(car, "Hood", t0)
		local order, hoodUp, rodStarts = true, -1, -1
		for i = 0, math.ceil(total / 0.01) + 5 do
			local t = t0 + i * 0.01
			local hood, prop = CarParts.amount(car, "Hood", t), CarParts.amount(car, "HoodProp", t)
			order = order and not (hood < 1 and prop > 0)
			if hood >= 1 and hoodUp < 0 then
				hoodUp = t - t0
			end
			if prop > 0 and rodStarts < 0 then
				rodStarts = t - t0
			end
		end
		local t1 = t0 + total + 1
		local back = CarParts.close(car, "Hood", t1)
		local shutOrder, rodDown, hoodStarts = true, -1, -1
		for i = 0, math.ceil(back / 0.01) + 5 do
			local t = t1 + i * 0.01
			local hood, prop = CarParts.amount(car, "Hood", t), CarParts.amount(car, "HoodProp", t)
			shutOrder = shutOrder and not (prop > 0 and hood < 1)
			if prop <= 0 and rodDown < 0 then
				rodDown = t - t1
			end
			if hood < 1 and hoodStarts < 0 then
				hoodStarts = t - t1
			end
		end
		CarParts.set(car, "Hood", 0)
		CarParts.set(car, "HoodProp", 0)
		check(
			checks,
			"the hood lifts before the prop rod swings, and the rod comes down first",
			order and shutOrder and rodStarts >= hoodUp and hoodStarts >= rodDown,
			string.format(
				"opening: hood up at %.2f s, rod starts %.2f s; shutting: rod down at %.2f s, hood starts %.2f s",
				hoodUp,
				rodStarts,
				rodDown,
				hoodStarts
			)
		)
	end

	-- 5. A strut's halves aim at each other wherever the hood carries one of them.
	do
		local desc = CarParts.describe(car) :: CarParts.Desc
		local worst = 0
		for _, amount in { 0, 0.5, 1 } do
			CarParts.set(car, "Hood", amount)
			local frames = CarParts.frames(car, desc, 0)
			for _, pair in { { "StrutTube", "StrutRod" }, { "StrutRod", "StrutTube" } } do
				local g = desc.byName[pair[1]]
				local here, there = frames[pair[1]], frames[pair[2]]
				local dir = here:VectorToWorldSpace(g.rest).Unit
				local u = (there.Position - here.Position).Unit
				-- off the cross product: acos of a dot near 1 reads 0.02 deg of its own noise
				worst = math.max(worst, math.deg(math.atan2(dir:Cross(u).Magnitude, dir:Dot(u))))
			end
		end
		CarParts.set(car, "Hood", 0)
		check(
			checks,
			"a strut's halves aim at each other as the hood lifts",
			worst < 0.01,
			string.format("worst aim %.5f deg", worst)
		)
	end

	-- 6. A wheel's lift moves its hub, wheel and caliper -- and the simulation's own wheel
	-- part -- by exactly that, and nothing else.
	do
		local base = snapshot(car, AT)
		Render.setWheelLift(rig, "WheelFL", 0.3)
		Render.place(rig, AT, 0, 0, 0)
		local lifted = snapshot(car, AT)
		local tire = (Render.group(rig, "WheelFL") :: any).parts[1].part:GetFullName()
		local rise = lifted[tire].Position.Y - base[tire].Position.Y
		local list = table.concat(movedGroups(base, lifted), ", ")
		Render.setWheelLift(rig, "WheelFL", 0)
		Render.place(rig, AT, 0, 0, 0)
		local p = gap(base, snapshot(car, AT))
		check(
			checks,
			"a wheel's lift moves its hub, wheel and caliper by exactly that, and nothing else",
			math.abs(rise - 0.3) < 1e-4 and list == "CaliperFL, Car.WheelFL, WheelFL" and p == 0,
			string.format("lift 0.3: up %.5f, moved [%s]; back to 0: gap %s", rise, list, tostring(p))
		)
	end

	-- 7. The front hub steers and the rear does not; the wheels spin and the calipers do not.
	do
		local rows, ok = {}, true
		Render.place(rig, AT, math.rad(25), math.rad(40), 0)
		for _, c in { "FL", "RL" } do
			local front = c == "FL"
			local w = Render.shellFrame(Render.group(rig, "Wheel" .. c)) :: CFrame
			local cal = Render.shellFrame(Render.group(rig, "Caliper" .. c)) :: CFrame
			local _, yaw = AT:ToObjectSpace(cal):ToOrientation()
			local steered = AT * CFrame.Angles(0, if front then math.rad(25) else 0, 0)
			local spin = select(1, steered:ToObjectSpace(w):ToOrientation())
			ok = ok
				and math.abs(math.deg(yaw) - (if front then 25 else 0)) < 0.01
				and math.abs(math.deg(spin) - 40) < 0.01
			table.insert(rows, string.format("%s caliper yaw %+.2f, wheel spin %+.2f", c, math.deg(yaw), math.deg(spin)))
		end
		Render.place(rig, AT, 0, 0, 0)
		check(
			checks,
			"the front hub steers, the rear does not; wheels spin, calipers do not",
			ok,
			table.concat(rows, "; ")
		)
	end

	-- 8. An open door, and the window riding on it, stay on the body wherever and however
	-- the car is put, leaning or not.
	do
		CarParts.set(car, "DoorR", 1)
		CarParts.set(car, "DoorGlassR", 0.5)
		local rng = Random.new(94)
		local first: { [string]: CFrame } = {}
		local worst = 0
		for _ = 1, 40 do
			local cf = CFrame.new(rng:NextNumber(-3000, 3000), rng:NextNumber(0, 200), rng:NextNumber(-3000, 3000))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-math.pi, math.pi), rng:NextNumber(-0.3, 0.3))
			Render.place(rig, cf, rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 50), rng:NextNumber(-0.17, 0.17))
			local body = Render.shellFrame(rig.bodyShell) :: CFrame
			for _, name in { "DoorR", "DoorGlassR" } do
				local rel = body:ToObjectSpace(Render.shellFrame(Render.group(rig, name)) :: CFrame)
				if first[name] then
					worst = math.max(worst, (rel.Position - first[name].Position).Magnitude)
				else
					first[name] = rel
				end
			end
		end
		CarParts.set(car, "DoorR", 0)
		CarParts.set(car, "DoorGlassR", 0)
		Render.place(rig, AT, 0, 0, 0)
		check(
			checks,
			"an open door and its window stay on the body wherever the car goes (to 0.001)",
			worst < 0.001,
			string.format("40 random poses up to 3000 studs out, leaning: offset from the body moved %.6f studs at most", worst)
		)
	end

	-- 9. The points come back off the shell as they went in.
	do
		local desc = CarParts.describe(car) :: CarParts.Desc
		local floors, floorOk = 0, true
		for name, p in s.floor or {} do
			floors += 1
			floorOk = floorOk and desc.floor[name] == p
		end
		check(
			checks,
			"the seat, the exit and the floor points read back off the shell",
			desc.seat == s.seat and desc.exit == s.exit and floorOk and floors == 3,
			`seat {tostring(desc.seat and desc.seat.Position)}, exit {tostring(desc.exit and desc.exit.Position)}, {floors} floor points`
		)
	end

	-- 10. Nothing in it is physics, and nothing came along that should not have.
	do
		local phys, stray = CarModel.physicsOffenders(car), CarModel.strayOffenders(car)
		check(
			checks,
			"an assembled rig holds no physics object and nothing stray",
			#phys == 0 and #stray == 0,
			`{#phys} physics offenders, {#stray} stray{if #phys > 0 then ": " .. table.concat(phys, "; ") else ""}`
		)
	end
	car:Destroy()

	-- 11. The bodies that were here are not rigs, and draw as before.
	do
		local rows, ok = {}, true
		for _, key in { "block", table.unpack(Bodies.Order) } do
			CarModel.setBody(key)
			local c = CarModel.build()
			local r = Render.rig(c)
			Render.place(r, CFrame.new(0, Config.Drift.RideHeight, 0), 0, 0, 0)
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

return RigTests
