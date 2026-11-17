--!strict
-- RestyledCarTests: the restyled liftback, the default car since T-287 (`Shared/Cars/Restyled`,
-- `Shared/Cars/MeshRig`, CONTRACTS.md "The car rig", features/car-model.md "The restyled
-- model").
--
--   game.ServerStorage.DebugBridge:Invoke("DebugRestyledCarTests", "run")
--
-- Built from code alone: the imported model the data was read from (`Workspace.car-ae86-mid`,
-- in DR-Lane1 only) is moved out of the Workspace while the car is built and put back after.
-- Then: every piece and group where the data says, every hinge to its angle and back to
-- exactly shut, the pop-up lights raising the headlights, the wheels on the road at the
-- wheelbase and track, the tyre, disc and caliper maps, no physics, the same numbers as the
-- car it replaces, and that it is the car a player spawns in. Run in a playtest to cover the
-- spawned car too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "RestyledCarTests only runs in Studio")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local CarParts = require(ReplicatedStorage.Shared.CarParts)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local Restyled = require(ReplicatedStorage.Shared.Cars.Restyled) :: any
local MeshRig = require(ReplicatedStorage.Shared.Cars.MeshRig)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Render = require(DriftFolder.Render) :: any

local RestyledCarTests = {}

local IMPORTED = "car-ae86-mid" -- the imported model, in DR-Lane1 only
local TURN = CFrame.Angles(0, math.pi, 0)
local MAPS = { colour = "ColorMap", normal = "NormalMap", roughness = "RoughnessMap", metalness = "MetalnessMap" }

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

local function gap(a: { [string]: CFrame }, b: { [string]: CFrame }): number
	local worst = 0
	for name, cfA in a do
		local cfB = b[name]
		if not cfB then
			return math.huge
		end
		worst = math.max(worst, (cfA.Position - cfB.Position).Magnitude)
		local ca, cb = { cfA:GetComponents() }, { cfB:GetComponents() }
		for i = 4, 12 do
			worst = math.max(worst, math.abs(ca[i] - cb[i]))
		end
	end
	return worst
end

-- What a SurfaceAppearance's map holds, whichever property this engine has.
local function mapOf(sa: SurfaceAppearance, prop: string): string
	local ok, content = pcall(function()
		return (sa :: any)[prop .. "Content"]
	end)
	if ok and typeof(content) == "Content" and (content :: any).Uri then
		return (content :: any).Uri
	end
	local ok2, s = pcall(function()
		return (sa :: any)[prop]
	end)
	return if ok2 and type(s) == "string" then s else ""
end

local AT = CFrame.new(41.5, 6.2, -17.75) * CFrame.Angles(0.04, 1.1, -0.02)

function RestyledCarTests.run()
	local checks = {}

	-- 1. Built from the code alone, with the imported model out of the place.
	local imported = workspace:FindFirstChild(IMPORTED)
	if imported then
		imported.Parent = ServerStorage
	end
	local t0 = os.clock()
	local okBuild, shell, built, failed = pcall(MeshRig.build, Restyled)
	local seconds = os.clock() - t0
	local stillOut = workspace:FindFirstChild(IMPORTED) == nil
	if imported then
		imported.Parent = workspace
	end
	local groupsWanted, moving, lamps = 1, 0, 0
	for _, g in Restyled.groups do
		groupsWanted += if g.kind == "spin" then 2 else 1
		if g.kind == "light" then
			lamps += 1
		else
			moving += 1
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
		okBuild and shell ~= nil and stillOut and built == 142 and #Restyled.pieces == 142 and failed == 0
			and groupCount == groupsWanted and moving == 36 and lamps == 18,
		if okBuild
			then string.format(
				"%d of %d pieces (142 in the export) in %d groups (want %d: %d moving parts, %d lamps, 4 hubs, the body) in %.2f s, %d failed",
				built or 0,
				#Restyled.pieces,
				groupCount,
				groupsWanted,
				moving,
				lamps,
				seconds,
				failed or 0
			)
			else `MeshRig.build failed: {shell}`
	)
	if not (okBuild and shell) then
		return { passed = false, checks = checks }
	end

	CarModel.setBody("block")
	local car = CarModel.build()
	CarModel.setBody(nil)
	CarModel.dress(car, shell)
	local rig = Render.rig(car)
	Render.place(rig, AT, 0, 0, 0)

	local byName: { [string]: BasePart } = {}
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			byName[d.Name] = d
		end
	end

	-- 2. Every piece where the data puts it, and every group drawn at its pivot.
	do
		local worstPiece, pieces = 0, 0
		for _, d in Restyled.pieces do
			local part = byName[d[1]]
			if part then
				pieces += 1
				local want = CFrame.new(MeshRig.point(Restyled, { d[6], d[7], d[8] })) * TURN
				local got = AT:ToObjectSpace(part.CFrame)
				worstPiece = math.max(worstPiece, (got.Position - want.Position).Magnitude, (got.LookVector - want.LookVector).Magnitude)
			end
		end
		local worstGroup, drawn = 0, 0
		for name, g in Restyled.groups do
			local frame = Render.shellFrame(Render.group(rig, name))
			if frame then
				drawn += 1
				worstGroup = math.max(worstGroup, (AT:PointToObjectSpace(frame.Position) - MeshRig.point(Restyled, g.pivot)).Magnitude)
			end
		end
		check(
			checks,
			"every piece and every group is where the model has it",
			rig.complete and pieces == 142 and worstPiece < 0.001 and worstGroup < 0.001,
			string.format("%d pieces, worst %.6f studs off; %d groups at their pivots, worst %.6f", pieces, worstPiece, drawn, worstGroup)
		)
	end

	-- 3. Every hinge to its full travel turns exactly its `Open`, and back is exactly shut.
	do
		local shut = snapshot(car, AT)
		local rows, ok, worstBack, count = {}, true, 0, 0
		local names = {}
		for name, g in Restyled.groups do
			if g.kind == "hinge" then
				table.insert(names, name)
			end
		end
		table.sort(names)
		for _, name in names do
			local g = Restyled.groups[name]
			local group = Render.group(rig, name)
			local before = Render.shellFrame(group) :: CFrame
			CarParts.set(car, name, 1)
			Render.place(rig, AT, 0, 0, 0)
			local after = Render.shellFrame(group) :: CFrame
			local rel = before:ToObjectSpace(after)
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
			worstBack = math.max(worstBack, gap(shut, snapshot(car, AT)))
			count += 1
			if err >= 1e-4 or stayed >= 1e-3 then
				table.insert(rows, string.format("%s off by %.5f, pivot moved %.4f", name, err, stayed))
			end
		end
		check(
			checks,
			"every hinge opens to its angle about its pivot, and back to shut is exactly shut",
			ok and worstBack == 0 and count == 24,
			string.format("%d hinges (24 in the export); worst back-to-shut gap %s%s", count, tostring(worstBack), if #rows > 0 then "; " .. table.concat(rows, "; ") else "")
		)
	end

	-- 4. The pop-up lights: written down, their travel raises them, carrying the headlight
	-- lenses up and forward; the doors, hood and hatch open and shut the same way.
	do
		local shut = snapshot(car, AT)
		local lensDown = AT:PointToObjectSpace(byName.HeadlightL_LensHead.Position)
		local t = 1000
		local out = 0
		for _, name in { "PodL", "PodR", "DoorR", "DoorL", "Hood", "Hatch" } do
			out = math.max(out, CarParts.open(car, name, t))
		end
		local opened = true
		for _, name in { "PodL", "PodR", "DoorR", "DoorL", "Hood", "HoodProp", "Hatch" } do
			opened = opened and CarParts.amount(car, name, t + out + 1e-6) == 1
		end
		for _, name in { "PodL", "PodR", "DoorR", "Hood" } do
			CarParts.set(car, name, 1)
		end
		Render.place(rig, AT, 0, 0, 0)
		local lensUp = AT:PointToObjectSpace(byName.HeadlightL_LensHead.Position)
		local lensUpR = AT:PointToObjectSpace(byName.HeadlightR_LensHead.Position)
		local doorOut = AT:PointToObjectSpace(byName.DoorR_Paint.Position).X - MeshRig.point(Restyled, { 2.6955, 3.4162, 0.0383 }).X
		local hoodUp = AT:PointToObjectSpace(byName.Hood_Paint.Position).Y - MeshRig.point(Restyled, { 0, 3.0344, -5.2986 }).Y
		for _, name in { "PodL", "PodR", "DoorR", "DoorL", "Hood", "HoodProp", "Hatch" } do
			CarParts.set(car, name, 0)
		end
		Render.place(rig, AT, 0, 0, 0)
		local back = gap(shut, snapshot(car, AT))
		local rise = lensUp.Y - lensDown.Y
		check(
			checks,
			"the pop-up lights raise the headlights; doors, hood and hatch open, and all shut exactly",
			opened and rise > 0.3 and math.abs(lensUp.Y - lensUpR.Y) < 1e-4 and doorOut > 1 and hoodUp > 0.5 and back == 0,
			string.format(
				"pods open in %.2f s; the left headlight lens %.3f up and %.3f forward when raised (the right level with it: %s); driver's door panel %.2f out, hood panel %.2f up; shut gap %s",
				out,
				rise,
				lensDown.Z - lensUp.Z,
				tostring(math.abs(lensUp.Y - lensUpR.Y) < 1e-4),
				doorOut,
				hoodUp,
				tostring(back)
			)
		)
	end

	-- 5. The wheels on the road at the wheelbase and the track; the front pair steer.
	do
		local onRoad = CFrame.new(0, Config.Drift.RideHeight, 0)
		Render.place(rig, onRoad, 0, 0, 0)
		local worst, rows = 0, {}
		local at: { [string]: Vector3 } = {}
		for _, name in CarModel.WHEEL_NAMES do
			local tyre = byName[name .. "_Tyre"]
			local g = tyre.Position.Y - tyre.Size.Y * 0.5
			worst = math.max(worst, math.abs(g))
			at[name] = tyre.Position
			table.insert(rows, string.format("%s (%.3f, %.3f, %.3f)", string.sub(name, 6), tyre.Position.X, tyre.Position.Y, tyre.Position.Z))
		end
		local base = (at.WheelRL.Z - at.WheelFL.Z + at.WheelRR.Z - at.WheelFR.Z) * 0.5
		local track = (at.WheelFR.X - at.WheelFL.X + at.WheelRR.X - at.WheelRL.X) * 0.5
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
			"every wheel sits on the road at the model's wheelbase and track, and the front pair steer",
			worst < 0.01 and math.abs(base - Config.Drift.Wheelbase) < 0.01 and math.abs(track - Restyled.measured.track) < 0.01 and steerOk,
			string.format(
				"wheelbase %.3f (config %.1f), track %.3f (model %.3f; config %.1f), tyre %.4f across (config WheelDiameter %.1f); worst gap to the road %.4f; tyres at %s; calipers steer %s",
				base,
				Config.Drift.Wheelbase,
				track,
				Restyled.measured.track,
				Config.Drift.TrackWidth,
				byName.WheelFL_Tyre.Size.Y,
				Config.Drift.WheelDiameter,
				worst,
				table.concat(rows, ", "),
				tostring(steerOk)
			)
		)
	end

	-- 6. The textured surfaces carry their maps: every tyre, disc and caliper.
	do
		local want, have, rows = 0, 0, {}
		for _, d in Restyled.pieces do
			local _, surfaceName = string.match(d[1], "^(%w+)_(%w+)$")
			local maps = Restyled.surfaces[surfaceName or ""].maps
			if maps then
				local part = byName[d[1]]
				local sa = part and part:FindFirstChildOfClass("SurfaceAppearance")
				for key, id in maps do
					want += 1
					local got = if sa then mapOf(sa, MAPS[key]) else ""
					if got == id then
						have += 1
					elseif #rows < 4 then
						table.insert(rows, `{d[1]} {key} '{got}'`)
					end
				end
			end
		end
		check(
			checks,
			"the tyres, discs and calipers carry their maps",
			want == 28 and have == want,
			string.format("%d of %d maps on (4 tyres x 2, 4 discs x 3, 4 calipers x 2)%s", have, want, if #rows > 0 then "; missing: " .. table.concat(rows, ", ") else "")
		)
	end

	-- 7. No physics, nothing the rays can hit.
	do
		local loose = 0
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") and (not d.Anchored or d.CanCollide or d.CanQuery or d.CanTouch) then
				loose += 1
			end
			if d:IsA("Constraint") or d:IsA("JointInstance") or d:IsA("BodyMover") or d:IsA("Seat") or d:IsA("VehicleSeat") then
				loose += 1
			end
		end
		check(checks, "nothing in the car is physics, or can be hit", loose == 0, `{loose} offenders`)
	end
	car:Destroy()

	-- 8. The car a player spawns in, on exactly the numbers of the car it replaces.
	do
		local key = Cars.Default
		local mine = Cars.resolve(key) :: any
		local old = Cars.resolve("liftback") :: any
		local differ, fields = {}, 0
		for field in Cars.Archetypes.Base do
			if field ~= "Name" and field ~= "Character" and field ~= "Bars" then
				fields += 1
				if mine[field] ~= old[field] then
					table.insert(differ, field)
				end
			end
		end
		local drawn = Cars.withActive(key, function()
			return CarModel.bodyName()
		end)
		local spawnedOk, spawned = true, {}
		local folder = workspace:FindFirstChild("Cars")
		for _, c in (if folder then folder:GetChildren() else {}) do
			table.insert(spawned, `{c.Name} wears '{tostring(c:GetAttribute("Body"))}'`)
		end
		check(
			checks,
			"it is the default, drawn as itself, on the old default's numbers to the bit",
			key == "restyled" and drawn == "restyled" and #differ == 0 and fields > 30 and Cars.exists("liftback") and spawnedOk,
			string.format(
				"default '%s' draws '%s'; %d car numbers, %d differ from the liftback's%s; the liftback still there: %s; %s",
				key,
				tostring(drawn),
				fields,
				#differ,
				if #differ > 0 then " (" .. table.concat(differ, ", ") .. ")" else "",
				tostring(Cars.exists("liftback")),
				if #spawned > 0 then table.concat(spawned, " | ") else "no car spawned"
			)
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return RestyledCarTests
