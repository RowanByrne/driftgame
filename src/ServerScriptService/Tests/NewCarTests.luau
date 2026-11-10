--!strict
-- NewCarTests: the game's own car, the liftback (T-111; `Shared/Cars/Liftback`,
-- `Shared/Cars/MeshRig`, CONTRACTS.md "The car rig").
--
--   game.ServerStorage.DebugBridge:Invoke("DebugNewCarTests", "run")
--
-- Built from code alone: the imported model the data was read from (`Workspace.car-ae86`,
-- in DR-Lane3 only) is moved out of the Workspace while the car is built and put back
-- after, so a pass proves every place can build it. Then: every piece and every group where
-- the data says, every hinge opening to its angle and shutting exactly, the wheels on the
-- road, the paint roles and stock colours, no physics, and that it is the car a player
-- spawns in, on the approved car's numbers. Run in a playtest to cover the spawned car too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "NewCarTests only runs in Studio")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local CarParts = require(ReplicatedStorage.Shared.CarParts)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local Liftback = require(ReplicatedStorage.Shared.Cars.Liftback) :: any
local MeshRig = require(ReplicatedStorage.Shared.Cars.MeshRig)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Render = require(DriftFolder.Render) :: any

local NewCarTests = {}

local IMPORTED = "car-ae86" -- the imported model, in DR-Lane3 only

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
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

-- A car frame that is not the identity, so nothing passes by accident at the origin.
local AT = CFrame.new(41.5, 6.2, -17.75) * CFrame.Angles(0.04, 1.1, -0.02)

function NewCarTests.run()
	local checks = {}

	-- 1. Built from the code alone, with the imported model out of the place.
	local imported = workspace:FindFirstChild(IMPORTED)
	if imported then
		imported.Parent = ServerStorage
	end
	local t0 = os.clock()
	local okBuild, shell, built, failed = pcall(MeshRig.build, Liftback)
	local seconds = os.clock() - t0
	local stillOut = workspace:FindFirstChild(IMPORTED) == nil
	if imported then
		imported.Parent = workspace
	end
	local groupsWanted = 1 -- the Body
	for _, g in Liftback.groups do
		if g.kind then
			groupsWanted += if g.kind == "spin" then 2 else 1 -- a wheel brings its hub
		end
	end
	local groupCount = 0
	if okBuild and shell then
		for _, child in shell:GetChildren() do
			if child:IsA("Model") then
				groupCount += 1
			end
		end
	end
	check(
		checks,
		"the car builds from code, with the imported model out of the place",
		okBuild and shell ~= nil and stillOut and built == #Liftback.pieces and failed == 0 and groupCount == groupsWanted,
		if okBuild
			then string.format(
				"%d of %d pieces in %d groups (want %d) in %.2f s, %d failed; imported model %s during the build, %s after",
				built or 0,
				#Liftback.pieces,
				groupCount,
				groupsWanted,
				seconds,
				failed or 0,
				if imported then "out" else "absent",
				if workspace:FindFirstChild(IMPORTED) then "back" else "absent"
			)
			else `MeshRig.build failed: {shell}`
	)
	if not (okBuild and shell) then
		return { passed = false, checks = checks }
	end

	-- Dressed onto a car exactly as `CarModel` dresses it, and drawn by `Render`.
	CarModel.setBody("block")
	local car = CarModel.build()
	CarModel.setBody(nil)
	CarModel.dress(car, shell)
	local rig = Render.rig(car)
	Render.place(rig, AT, 0, 0, 0)

	-- 2. Every piece where the data puts it, and every group drawn at its pivot.
	do
		local worstPiece, pieces = 0, 0
		local TURN = CFrame.Angles(0, math.pi, 0)
		local byName = {}
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") then
				byName[d.Name] = d
			end
		end
		for _, d in Liftback.pieces do
			local part = byName[d[1]]
			if part then
				pieces += 1
				local want = CFrame.new(MeshRig.point(Liftback, { d[6], d[7], d[8] })) * TURN
				local got = AT:ToObjectSpace(part.CFrame)
				worstPiece = math.max(worstPiece, (got.Position - want.Position).Magnitude, (got.LookVector - want.LookVector).Magnitude)
			end
		end
		local worstGroup, drawn = 0, 0
		for name, g in Liftback.groups do
			if g.kind then
				local frame = Render.shellFrame(Render.group(rig, name))
				if frame then
					drawn += 1
					worstGroup = math.max(worstGroup, (AT:PointToObjectSpace(frame.Position) - MeshRig.point(Liftback, g.pivot)).Magnitude)
				end
			end
		end
		check(
			checks,
			"every piece and every group is where the model has it",
			rig.complete and CarParts.isRig(car) and pieces == #Liftback.pieces and worstPiece < 0.001 and worstGroup < 0.001,
			string.format(
				"%d pieces, worst %.6f studs off; %d groups drawn at their pivots, worst %.6f; rig complete %s",
				pieces,
				worstPiece,
				drawn,
				worstGroup,
				tostring(rig.complete)
			)
		)
	end

	-- 3. Every hinge to its full travel turns exactly its `Open`, and back to shut is
	-- exactly shut, every part of the car.
	do
		local shut = snapshot(car, AT)
		local rows, ok, worstBack, count = {}, true, 0, 0
		local names = {}
		for name, g in Liftback.groups do
			if g.kind == "hinge" then
				table.insert(names, name)
			end
		end
		table.sort(names)
		for _, name in names do
			local g = Liftback.groups[name]
			local group = Render.group(rig, name)
			local before = Render.shellFrame(group) :: CFrame
			CarParts.set(car, name, 1)
			Render.place(rig, AT, 0, 0, 0)
			local after = Render.shellFrame(group) :: CFrame
			local rel = before:ToObjectSpace(after)
			-- the turn about the data's axis, read off the parts: a full turn reads as none
			local want = (g.open + 180) % 360 - 180
			local turned = CFrame.fromAxisAngle(Vector3.new(table.unpack(g.axis)).Unit, math.rad(want))
			local err = 0
			local ca, cb = { rel:GetComponents() }, { turned:GetComponents() }
			for i = 4, 12 do
				err = math.max(err, math.abs(ca[i] - cb[i]))
			end
			local stayed = (after.Position - before.Position).Magnitude
			ok = ok and err < 1e-4 and stayed < 1e-3
			CarParts.set(car, name, 0)
			Render.place(rig, AT, 0, 0, 0)
			local p, r = gap(shut, snapshot(car, AT))
			worstBack = math.max(worstBack, p, r)
			count += 1
			if err >= 1e-4 or stayed >= 1e-3 then
				table.insert(rows, string.format("%s off by %.5f, pivot moved %.4f", name, err, stayed))
			end
		end
		check(
			checks,
			"every hinge opens to its angle about its pivot, and back to shut is exactly shut",
			ok and worstBack == 0 and count >= 20,
			string.format("%d hinges; worst back-to-shut gap %s%s", count, tostring(worstBack), if #rows > 0 then "; " .. table.concat(rows, "; ") else "")
		)
	end

	-- 4. The doors, the hood (and its rod), the hatch and the pop-up lights out and back
	-- over time through `CarParts`: open at the end of the move, and exactly shut after.
	do
		local shut = snapshot(car, AT)
		local t = 1000
		local moving = { "DoorR", "DoorL", "Hood", "Hatch", "PodL", "PodR" }
		local out = 0
		for _, name in moving do
			out = math.max(out, CarParts.open(car, name, t))
		end
		local e = 1e-6
		local opened = true
		for _, name in { "DoorR", "DoorL", "Hood", "HoodProp", "Hatch", "PodL", "PodR" } do
			opened = opened and CarParts.amount(car, name, t + out + e) == 1
		end
		-- open, drawn: the driver's door's rear edge is out from the body, the hood is up
		CarParts.set(car, "DoorR", 1)
		CarParts.set(car, "Hood", 1)
		Render.place(rig, AT, 0, 0, 0)
		local doorPaint = (car:FindFirstChild("DoorR_Paint", true) :: BasePart)
		local hoodPaint = (car:FindFirstChild("Hood_Paint", true) :: BasePart)
		local doorOut = AT:PointToObjectSpace(doorPaint.Position).X - MeshRig.point(Liftback, { 2.8184, 3.83, -0.05 }).X
		local hoodUp = AT:PointToObjectSpace(hoodPaint.Position).Y - MeshRig.point(Liftback, { 0, 3.3229, -5.4949 }).Y
		local t2 = t + out + 1
		local back = 0
		for _, name in moving do
			back = math.max(back, CarParts.close(car, name, t2))
		end
		local closed = true
		for _, name in { "DoorR", "DoorL", "Hood", "HoodProp", "Hatch", "PodL", "PodR" } do
			closed = closed and CarParts.amount(car, name, t2 + back + e) == 0
		end
		Render.place(rig, AT, 0, 0, 0) -- the real clock, long past every move
		local p, r = gap(shut, snapshot(car, AT))
		check(
			checks,
			"the doors, hood, hatch and pop-up lights open through CarParts and shut exactly",
			opened and closed and p == 0 and r == 0 and doorOut > 1 and hoodUp > 0.5,
			string.format(
				"open in %.2f s %s, shut in %.2f s %s; driver's door panel %.2f studs out, hood panel %.2f up when open; drawn gap shut %s / %s",
				out,
				tostring(opened),
				back,
				tostring(closed),
				doorOut,
				hoodUp,
				tostring(p),
				tostring(r)
			)
		)
	end

	-- 5. The wheels on the road, placed as the game places a car on a road at y = 0; the
	-- front pair steer, every wheel spins, the calipers do not.
	do
		local onRoad = CFrame.new(0, Config.Drift.RideHeight, 0)
		Render.place(rig, onRoad, 0, 0, 0)
		local gaps, worst = {}, 0
		for _, name in CarModel.WHEEL_NAMES do
			local tyre = car:FindFirstChild(name .. "_Tyre", true) :: BasePart
			local g = tyre.Position.Y - tyre.Size.Y * 0.5
			worst = math.max(worst, math.abs(g))
			table.insert(gaps, string.format("%s %+.4f", string.sub(name, 6), g))
		end
		local steerOk = true
		Render.place(rig, onRoad, math.rad(20), math.rad(35), 0)
		for _, c in { "FL", "FR", "RL", "RR" } do
			local front = c == "FL" or c == "FR"
			local cal = Render.shellFrame(Render.group(rig, "Caliper" .. c)) :: CFrame
			local _, yaw = onRoad:ToObjectSpace(cal):ToOrientation()
			steerOk = steerOk and math.abs(math.deg(yaw) - (if front then 20 else 0)) < 0.01
		end
		Render.place(rig, AT, 0, 0, 0)
		check(
			checks,
			"every wheel sits on the road, and the front pair steer",
			worst < 0.01 and steerOk,
			string.format(
				"tyre %.4f across (the config's WheelDiameter is %.1f); gap to the road at each corner: %s; calipers steer %s",
				(car:FindFirstChild("WheelFL_Tyre", true) :: BasePart).Size.Y,
				Config.Drift.WheelDiameter,
				table.concat(gaps, ", "),
				tostring(steerOk)
			)
		)
	end

	-- 6. Paint roles on every piece, and the stock look the user drew: white over black,
	-- black wheels and trim, dark glass, amber indicators, red tail lamps.
	do
		local roles = { body = 0, second = 0, rim = 0, tyre = 0, none = 0 }
		local untagged = 0
		for _, d in car:GetDescendants() do
			if d:IsA("MeshPart") then
				local role = d:GetAttribute("Paint")
				if type(role) == "string" and roles[role] then
					roles[role] += 1
				else
					untagged += 1
				end
			end
		end
		local function colour(name: string): Color3
			return (car:FindFirstChild(name, true) :: BasePart).Color
		end
		local function luma(c: Color3): number
			return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
		end
		local white = luma(colour("Body_Paint")) > 0.9
		local black = luma(colour("Body_Second")) < 0.1
			and luma(colour("WheelFL_Rim")) < 0.15
			and luma(colour("Body_Trim")) < 0.1
		local glass = car:FindFirstChild("GlassWindscreen_Glass", true) :: BasePart
		local amber = colour("IndicatorFrontL_LensAmber")
		local red = colour("TailLampL_LensRed")
		local look = white
			and black
			and glass.Transparency > 0.2
			and luma(glass.Color) < 0.25
			and amber.R > 0.8
			and amber.G > 0.3
			and amber.B < 0.2
			and red.R > 0.6
			and red.G < 0.2
		check(
			checks,
			"every piece carries its paint role, and the stock look is the user's",
			untagged == 0 and roles.body == 11 and roles.second == 5 and roles.rim == 4 and roles.tyre == 4 and look,
			string.format(
				"body %d, second %d, rim %d, tyre %d, none %d, untagged %d; body luma %.2f, second %.2f, rim %.2f, glass %.2f at %.2f see-through",
				roles.body,
				roles.second,
				roles.rim,
				roles.tyre,
				roles.none,
				untagged,
				luma(colour("Body_Paint")),
				luma(colour("Body_Second")),
				luma(colour("WheelFL_Rim")),
				luma(glass.Color),
				glass.Transparency
			)
		)
	end

	-- 7. Nothing in it is physics, and nothing came along that should not have.
	do
		local phys, stray = CarModel.physicsOffenders(car), CarModel.strayOffenders(car)
		local loose = 0
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") and (d.CanCollide or d.CanQuery or d.CanTouch) then
				loose += 1
			end
		end
		check(
			checks,
			"the car holds no physics object, nothing stray, and nothing the rays can hit",
			#phys == 0 and #stray == 0 and loose == 0,
			`{#phys} physics offenders, {#stray} stray, {loose} parts collidable, queryable or touchable{if #phys > 0 then ": " .. table.concat(phys, "; ") else ""}`
		)
	end
	car:Destroy()

	-- 8. The car a player spawns in, on exactly the approved car's numbers.
	do
		local key = Cars.Default
		local mine = Cars.resolve(key) :: any
		local approved = Cars.resolve("balanced") :: any
		local same, fields, differ = true, 0, {}
		for field, value in Cars.Archetypes.Base do
			if field ~= "Name" and field ~= "Character" and field ~= "Bars" then
				fields += 1
				if mine[field] ~= value or approved[field] ~= value then
					same = false
					table.insert(differ, field)
				end
			end
		end
		local drawn = Cars.withActive(key, function()
			return CarModel.bodyName()
		end)
		local spawned, spawnedRows = 0, {}
		local folder = workspace:FindFirstChild("Cars")
		for _, c in (if folder then folder:GetChildren() else {}) do
			spawned += 1
			table.insert(spawnedRows, `{c.Name} wears '{tostring(c:GetAttribute("Body"))}', rig {CarParts.isRig(c)}`)
		end
		local spawnedOk = true
		for _, c in (if folder then folder:GetChildren() else {}) do
			spawnedOk = spawnedOk and c:GetAttribute("Body") == "liftback" and CarParts.isRig(c)
		end
		local cycle = {}
		local at = key
		for _ = 1, #Cars.Order do
			table.insert(cycle, at)
			at = Cars.nextKey(at)
		end
		check(
			checks,
			"it is the car a player spawns in, on the approved car's numbers",
			key == "liftback" and drawn == "liftback" and same and fields > 30 and spawnedOk and at == key,
			string.format(
				"default '%s' draws '%s'; %d car numbers equal to the approved car's%s; F4 cycles %s; %s",
				key,
				tostring(drawn),
				fields,
				if #differ > 0 then " EXCEPT " .. table.concat(differ, ", ") else "",
				table.concat(cycle, " > "),
				if spawned > 0 then table.concat(spawnedRows, " | ") else "no car spawned (run in a playtest to cover it)"
			)
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return NewCarTests
