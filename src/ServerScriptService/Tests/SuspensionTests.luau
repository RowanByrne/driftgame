--!nonstrict
-- SuspensionTests: the wheels on their springs and the car resting on its floor
-- (docs/game/features/car-v2.md "Testing", T-095; Drift/Suspension).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugSuspensionTests", "run")
--
-- Pure model drives on made-up ground -- a kerb, a crest, a jump, a ledge -- plus one ledge
-- BUILT in the place and driven through `Drift/World.live`, with the real car model drawn
-- on it every step through `Drift/Render`, so "nothing of the car below the ledge's top" is
-- measured on the parts you would see. No player and no playtest client is needed; the
-- ledge is built far from everything and taken down again.
--
-- `run()` returns `{ passed, checks, log }`: `log` is the step-by-step record of the ledge
-- and the wheels, for the report and for anybody tuning the springs.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "SuspensionTests only runs in Studio")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Render = require(DriftFolder.Render)
local Sim = require(DriftFolder.Sim)
local Suspension = require(DriftFolder.Suspension)
local World = require(DriftFolder.World)

local SuspensionTests = {}

local NAMES = { "FL", "FR", "RL", "RR" }

-- The ledge in the place: far out in the empty quarter, clear of the playground, the track
-- and the other suites' own rigs (CollisionTests at 20 000, 500, 20 000).
local LEDGE_AT = Vector3.new(-30000, 800, 30000)
local LEDGE_SIZE = Vector3.new(60, 8, 60)

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
end

local function hit(y: number, normal: Vector3?): Model.Hit
	local C = Config.Drift
	return { y = y, normal = normal or Vector3.yAxis, grip = C.GripTarmac, score = C.ScoreTarmac }
end

-- Ground made of a height function: `height(x, z)` is the ground's Y there, or nil for
-- nothing at all. Its normal is read off the function itself, so a slope is a slope.
local function ground(height: (number, number) -> number?): Model.World
	return {
		probe = function(pos: Vector3): Model.Hit?
			local y = height(pos.X, pos.Z)
			if not y then
				return nil
			end
			local e = 0.05
			local yx = height(pos.X + e, pos.Z) or y
			local yz = height(pos.X, pos.Z + e) or y
			local n = Vector3.new(-(yx - y) / e, 1, -(yz - y) / e).Unit
			return hit(y, n)
		end,
		sweep = nil,
		penetration = nil,
	}
end

-- A car going straight down -Z (yaw 0) at `speed`, ride height over Y = 0.
local function carAt(z: number, speed: number): Model.State
	local C = Config.Drift
	local s = Model.new(CFrame.new(0, C.RideHeight, z))
	s.velocity = Vector3.new(0, 0, -speed)
	return s
end

-- The car with no engine and no grip, so a drive goes exactly where it is pushed: the
-- ledge is about the floor, not about how a car with its rear off a ledge would drive.
local COAST = { MaxAcceleration = 0, ConstantFriction = 0, SlipFriction = 0, SlipSqFriction = 0 }

local function fmt(n: number): string
	return string.format("%.3f", n)
end

--------------------------------------------------------------------------------

function SuspensionTests.run()
	local C = Config.Drift
	local P = C.Suspension
	local dt = C.FixedStep
	local checks = {}
	local log = {}

	------------------------------------------------------------ flat: nothing moves
	do
		local runner = Sim.newRunner(CFrame.new(0, C.RideHeight, 0))
		local flat = World.flat(0)
		local hangs, worstLift, worstTravel = 0, 0, 0
		for i = 1, 1200 do
			Model.step(runner.state, { steer = if i > 300 then 0.6 else 0 }, dt, flat)
			local s = runner.state
			if s.hanging then
				hangs += 1
			end
			for k = 1, 4 do
				worstLift = math.max(worstLift, math.abs(s.wheelLift[k]))
				worstTravel = math.max(worstTravel, math.abs(s.travel[k] - P.Rest))
			end
		end
		check(
			checks,
			"on flat ground the floor solve never runs and every wheel sits at Rest",
			hangs == 0 and worstTravel < 1e-9 and worstLift < 0.02,
			string.format(
				"10 s straight then sliding on a flat plane: the floor solve ran on %d steps; worst travel off Rest %.2e studs; worst drawn lift %.4f studs (the model's own ground follow sits that far under ride height at speed, and the wheels are drawn on the road)",
				hangs,
				worstTravel,
				worstLift
			)
		)
	end

	------------------------------------------------------------ a kerb, a crest, a jump
	-- Each wheel's travel, sampled, at 40 studs/s.
	local function drive(world: Model.World, z0: number, speed: number, seconds: number, onStep)
		local s = carAt(z0, speed)
		for i = 1, math.floor(seconds / dt) do
			Model.step(s, { steer = 0 }, dt, world)
			if onStep then
				onStep(s, i)
			end
		end
		return s
	end

	do
		-- A kerb 0.3 high and 3 long across the left half of the road only, at z = -40.
		local kerb = ground(function(x, z)
			if x < 0 and z < -40 and z > -43 then
				return 0.3
			end
			return 0
		end)
		local peak = { 0, 0, 0, 0 }
		local low = { P.Travel, P.Travel, P.Travel, P.Travel }
		local roll = 0
		local hangs = 0
		local samples = {}
		drive(kerb, 0, 40, 2.5, function(s, i)
			for k = 1, 4 do
				peak[k] = math.max(peak[k], s.travel[k])
				low[k] = math.min(low[k], s.travel[k])
			end
			roll = math.max(roll, math.abs(s.body.q))
			if s.hanging then
				hangs += 1
			end
			if i % 6 == 0 and s.position.Z < -30 and s.position.Z > -60 then
				table.insert(
					samples,
					string.format("z %.1f: %s %s %s %s", s.position.Z, fmt(s.travel[1]), fmt(s.travel[2]), fmt(s.travel[3]), fmt(s.travel[4]))
				)
			end
		end)
		table.insert(log, "KERB 0.3 under the left wheels at 40 studs/s, travel FL FR RL RR:\n  " .. table.concat(samples, "\n  "))
		check(
			checks,
			"over a kerb the left wheels ride up on their own and the right ones barely move",
			peak[1] > P.Rest + 0.15 and peak[3] > P.Rest + 0.15 and peak[2] < P.Rest + 0.15 and hangs == 0,
			string.format(
				"0.3-stud kerb under the left side at 40 studs/s: peak travel FL %.3f FR %.3f RL %.3f RR %.3f (Rest %.2f, Travel %.2f); lowest FL %.3f FR %.3f; the body rolled %.2f deg on its springs; floor solve ran %d steps",
				peak[1],
				peak[2],
				peak[3],
				peak[4],
				P.Rest,
				P.Travel,
				low[1],
				low[2],
				math.deg(roll),
				hangs
			)
		)
	end

	do
		-- A crest: 10 degrees up for 40 studs, 10 down for 40.
		local t = math.tan(math.rad(10))
		local crest = ground(function(_x, z)
			local d = -z - 30
			if d < 0 then
				return 0
			elseif d < 40 then
				return d * t
			elseif d < 80 then
				return (80 - d) * t
			end
			return 0
		end)
		local low = { P.Travel, P.Travel, P.Travel, P.Travel }
		local high = { 0, 0, 0, 0 }
		local samples = {}
		local air = 0
		drive(crest, 0, 40, 3.5, function(s, i)
			if s.airborne then
				air += 1
			end
			if -s.position.Z > 45 and -s.position.Z < 105 then
				for k = 1, 4 do
					low[k] = math.min(low[k], s.travel[k])
					high[k] = math.max(high[k], s.travel[k])
				end
			end
			if i % 6 == 0 and -s.position.Z > 50 and -s.position.Z < 120 then
				table.insert(
					samples,
					string.format("z %.1f: %s %s %s %s", s.position.Z, fmt(s.travel[1]), fmt(s.travel[2]), fmt(s.travel[3]), fmt(s.travel[4]))
				)
			end
		end)
		table.insert(log, "CREST 10 deg up, 10 down, at 40 studs/s, travel FL FR RL RR:\n  " .. table.concat(samples, "\n  "))
		check(
			checks,
			"over a crest the wheels drop and over the sag after it they take the load",
			low[1] < P.Rest - 0.05 and high[1] > P.Rest + 0.05 and air == 0,
			string.format(
				"10-degree crest at 40 studs/s: front travel from %.3f to %.3f, rear from %.3f to %.3f (Rest %.2f); airborne %d steps",
				low[1],
				high[1],
				low[3],
				high[3],
				P.Rest,
				air
			)
		)
	end

	do
		-- A jump: a 15-degree ramp 5 high, then flat ground 0 beyond a gap.
		local t = math.tan(math.rad(15))
		local jump = ground(function(_x, z)
			local d = -z - 20
			if d < 0 then
				return 0
			elseif d < 5 / t then
				return d * t
			end
			return 0
		end)
		local left, landed, flatAgain = nil, nil, nil
		local airWorst = 0
		local fullDrop = nil
		local samples = {}
		drive(jump, 0, 70, 4, function(s, i)
			if s.airborne and not left then
				left = s.time
			end
			if left and not landed and s.airborne then
				local since = s.time - left
				local worst = 0
				for k = 1, 4 do
					worst = math.max(worst, s.travel[k])
				end
				if since > P.DropTime + 2 * dt then
					airWorst = math.max(airWorst, worst)
				end
				if worst <= 1e-9 and not fullDrop then
					fullDrop = since
				end
			end
			if left and not landed and not s.airborne then
				landed = s.time
			end
			if landed and not flatAgain then
				local off = 0
				for k = 1, 4 do
					off = math.max(off, math.abs(s.travel[k] - P.Rest))
				end
				-- Settled: every wheel within a hundredth of Rest and the body still.
				if off < 0.01 and math.abs(s.body.vz) < 0.05 and s.time - landed > dt then
					flatAgain = s.time
				end
			end
			if left and i % 4 == 0 and (not flatAgain or s.time - flatAgain < 0.1) then
				table.insert(
					samples,
					string.format(
						"t %.2f %s: %s %s %s %s body %+.3f",
						s.time,
						if s.airborne then "air " else "road",
						fmt(s.travel[1]),
						fmt(s.travel[2]),
						fmt(s.travel[3]),
						fmt(s.travel[4]),
						s.body.z
					)
				)
			end
		end)
		table.insert(log, "JUMP 15-degree ramp 5 high at 70 studs/s, travel FL FR RL RR:\n  " .. table.concat(samples, "\n  "))
		local settle = if landed and flatAgain then flatAgain - landed else math.huge
		check(
			checks,
			"off a jump every wheel hangs at the bottom of its travel, and is back at Rest within half a second of landing",
			left ~= nil and landed ~= nil and airWorst <= 1e-9 and fullDrop ~= nil and fullDrop <= P.DropTime + 2 * dt and settle <= 0.5,
			string.format(
				"left the ramp at %.2f s; all four at full drop %.3f s later (DropTime %.2f) and held there (worst travel in the air after that %.3f); landed at %.2f s; back within 0.01 of Rest %.3f s after landing",
				left or -1,
				fullDrop or -1,
				P.DropTime,
				airWorst,
				landed or -1,
				settle
			)
		)
	end

	------------------------------------------------------------ the ledge, made up
	-- The ledge top is Y = 0 for z <= 0 and the ground is 8 below beyond it. The car faces
	-- -Z (into the ledge) and is rolled BACKWARDS off it at 3 studs/s, rear first.
	local function ledgeDrive(world: Model.World, start: Vector3, speed: number, floor, onStep)
		local s = Model.new(CFrame.new(start))
		s.floor = floor
		Cars.withTuning(COAST, function()
			for i = 1, math.floor(9 / dt) do
				s.velocity = Vector3.new(0, s.velocity.Y, speed)
				Model.step(s, { steer = 0 }, dt, world)
				if onStep(s, i) then
					break
				end
			end
		end)
		return s
	end

	-- The floor's lowest point over the ledge: the outline walked every tenth of a stud, and
	-- the points themselves.
	local function floorLow(s: Model.State, floor, edgeZ: number): number
		local fwd, right, up = Suspension.basis(s.yaw, s.up)
		local pts = floor or Suspension.defaultFloor()
		local low = math.huge
		local function at(p: Vector3)
			local w = s.position + right * p.X + up * p.Y - fwd * p.Z
			if w.Z <= edgeZ then
				low = math.min(low, w.Y)
			end
		end
		for _, a in pts do
			at(a.at)
			for _, b in pts do
				local n = math.ceil((b.at - a.at).Magnitude / 0.1)
				for k = 1, n - 1 do
					at(a.at:Lerp(b.at, k / n))
				end
			end
		end
		return low
	end

	do
		local edge = 0
		local world = ground(function(_x, z)
			return if z <= edge then 0 else -8
		end)
		local worst = math.huge
		local maxPitch, firstTouch = 0, nil
		local fellAt = nil
		local hangSteps = 0
		ledgeDrive(world, Vector3.new(0, C.RideHeight, -9), 3, nil, function(s)
			local low = floorLow(s, nil, edge)
			if s.position.Y > -1 then
				worst = math.min(worst, low)
			end
			local a = Suspension.tiltOf(s.yaw, s.up)
			maxPitch = math.max(maxPitch, math.deg(a))
			if s.floorTouching > 0 and not firstTouch then
				firstTouch = s.position.Z
			end
			if s.hanging then
				hangSteps += 1
			end
			if s.airborne and s.position.Y < 0 and not fellAt then
				fellAt = s.position.Z
			end
			return s.position.Y < -6
		end)
		check(
			checks,
			"rolled off a ledge rear first, the rear drops on to the floor, grinds, and nothing goes below the ledge",
			firstTouch ~= nil and maxPitch > 3 and worst >= -1e-3 and fellAt ~= nil,
			string.format(
				"made-up ledge, 3 studs/s backwards: the floor first touched the edge with the car's middle %.2f studs from it; the car pitched up to %.1f deg; it fell with its middle %.2f studs past the edge; the lowest the floor ever got over the ledge was %+.4f studs off its top; the floor solve ran %d steps",
				firstTouch or 0,
				maxPitch,
				fellAt or 0,
				worst,
				hangSteps
			)
		)
	end

	------------------------------------------------------------ the ledge, built
	-- A real part in the place, tagged as road, driven through `World.live` with the car
	-- model drawn on it every step: the parts you would see, measured.
	local folder = Instance.new("Folder")
	folder.Name = "SuspensionTestsLedge"
	local ledge = Instance.new("Part")
	ledge.Name = "Ledge"
	ledge.Anchored = true
	ledge.Size = LEDGE_SIZE
	-- The ledge's far edge (+Z) is the drop; the floor beyond is a plate 8 below its top.
	ledge.CFrame = CFrame.new(LEDGE_AT - Vector3.new(0, LEDGE_SIZE.Y * 0.5, 0))
	ledge.Parent = folder
	local below = Instance.new("Part")
	below.Name = "Below"
	below.Anchored = true
	below.Size = Vector3.new(200, 2, 200)
	below.CFrame = CFrame.new(LEDGE_AT - Vector3.new(0, LEDGE_SIZE.Y + 1, 0))
	below.Parent = folder
	CollectionService:AddTag(ledge, C.SurfaceTag)
	CollectionService:AddTag(below, C.SurfaceTag)

	local car = CarModel.build()
	car.Name = "SuspensionTestsCar"
	car.Parent = folder
	folder.Parent = workspace

	local ok, err = pcall(function()
		local world = World.live({ car })
		local rig = Render.rig(car)
		local edgeZ = LEDGE_AT.Z + LEDGE_SIZE.Z * 0.5
		local top = LEDGE_AT.Y
		local floor = rig.floor
		local worstBody, worstWheel, worstFloor = math.huge, math.huge, math.huge
		local worstBodyAt, worstWheelAt = "", ""
		local maxPitch, firstTouch, fellAt = 0, nil, nil
		local touchedNames = {}
		local rows = {}
		local hangSteps = 0
		local sparks = 0
		local radius = C.WheelDiameter * 0.5

		local function measure(s: Model.State)
			-- Every drawn body part: its box's corners, over the ledge.
			for _, d in car:GetDescendants() do
				if not d:IsA("BasePart") or d.Transparency >= 1 then
					continue
				end
				if d.Name:sub(1, 5) == "Wheel" or (d.Parent and d.Parent.Name:sub(1, 5) == "Wheel") then
					continue -- wheels: measured on their own circle below
				end
				local h = d.Size * 0.5
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local w = d.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
							if w.Z <= edgeZ and math.abs(w.X - LEDGE_AT.X) < LEDGE_SIZE.X * 0.5 then
								local gap = w.Y - top
								if gap < worstBody then
									worstBody, worstBodyAt = gap, d:GetFullName():gsub("^.-SuspensionTestsCar%.", "")
								end
							end
						end
					end
				end
			end
			-- Every wheel: its tread, all the way round, over the ledge.
			for _, name in CarModel.WHEEL_NAMES do
				local w = car:FindFirstChild(name)
				if w then
					for k = 0, 23 do
						local a = k / 24 * math.pi * 2
						local p = w.CFrame * Vector3.new(0, math.sin(a) * radius, math.cos(a) * radius)
						if p.Z <= edgeZ then
							local gap = p.Y - top
							if gap < worstWheel then
								worstWheel, worstWheelAt = gap, name
							end
						end
					end
				end
			end
		end

		local start = Vector3.new(LEDGE_AT.X, top + C.RideHeight, edgeZ - 9)
		ledgeDrive(world, start, 2.5, floor, function(s, i)
			Render.apply(rig, s)
			measure(s)
			if s.position.Y > top - 1 then
				worstFloor = math.min(worstFloor, floorLow(s, floor, edgeZ) - top)
			end
			local a = Suspension.tiltOf(s.yaw, s.up)
			maxPitch = math.max(maxPitch, math.deg(a))
			if s.hanging then
				hangSteps += 1
			end
			for _, c in s.floorContacts do
				touchedNames[c.name] = true
				sparks += 1
			end
			if s.floorTouching > 0 and not firstTouch then
				firstTouch = s.position.Z - edgeZ
			end
			if s.airborne and s.position.Y < top and not fellAt then
				fellAt = s.position.Z - edgeZ
			end
			if i % 12 == 0 and s.position.Y > top - 6 then
				local names = {}
				for _, c in s.floorContacts do
					table.insert(names, string.format("%s%s@%.1f", c.name, if c.edge then "(edge)" else "", c.speed))
				end
				table.insert(
					rows,
					string.format(
						"middle %+.2f from edge, height %+.3f over the ledge, pitch %+.1f deg, %s, touching [%s], rear travel %s %s",
						s.position.Z - edgeZ,
						s.position.Y - top - C.RideHeight,
						math.deg(a),
						if s.airborne then "air" else "resting",
						table.concat(names, " "),
						fmt(s.travel[3]),
						fmt(s.travel[4])
					)
				)
			end
			return s.position.Y < top - 7
		end)
		local names = {}
		for n in touchedNames do
			table.insert(names, n)
		end
		table.sort(names)
		table.insert(log, "LEDGE built in the place, the car rolled off it rear first at 2.5 studs/s:\n  " .. table.concat(rows, "\n  "))
		check(
			checks,
			"the built ledge: the rear drops, the floor rests on the edge and grinds, and no drawn part of the car goes below the ledge's top",
			firstTouch ~= nil and maxPitch > 3 and worstBody >= -1e-3 and worstFloor >= -1e-3 and fellAt ~= nil,
			string.format(
				"%s body, floor of %d points read off it: first touch with the middle %.2f studs short of the edge; pitch up to %.1f deg; fell %.2f studs past it; floor points that touched: %s (%d contact-steps for sparks). Lowest over the ledge's top: the floor %+.4f, the drawn body %+.4f (%s), the wheels' tread %+.4f (%s)",
				car:GetAttribute("Body") or "?",
				if floor then #floor else 0,
				firstTouch or 0,
				maxPitch,
				fellAt or 0,
				table.concat(names, ", "),
				sparks,
				worstFloor,
				worstBody,
				worstBodyAt,
				worstWheel,
				worstWheelAt
			)
		)
		world.destroy()
	end)
	folder:Destroy()
	if not ok then
		check(checks, "the built ledge ran", false, tostring(err))
	end

	------------------------------------------------------------ the same drive twice
	do
		local edge = 0
		local world = ground(function(_x, z)
			return if z <= edge then 0 else -8
		end)
		local function once(): Vector3
			local last
			ledgeDrive(world, Vector3.new(0, C.RideHeight, -9), 3, nil, function(s)
				last = s.position
				return s.position.Y < -6
			end)
			return last
		end
		local a, b = once(), once()
		check(checks, "off a ledge, twice, is the same line", (a - b).Magnitude < 1e-9, string.format("%.9f studs apart", (a - b).Magnitude))
	end

	------------------------------------------------------------ over the wire
	do
		local lifts = { 0.31, -0.25, 0, 0.004 }
		local back = Suspension.unpack(Suspension.pack(lifts))
		local worst = 0
		for k = 1, 4 do
			worst = math.max(worst, math.abs(back[k] - lifts[k]))
		end
		local junk = Suspension.unpack("nope")
		local junk2 = Suspension.unpack(-5)
		local junk3 = Suspension.unpack(1.5)
		check(
			checks,
			"four lifts go over CarState in one number and come back",
			worst <= P.LiftRange / 127 * 0.5 + 1e-9
				and junk[1] == 0
				and junk2[2] == 0
				and junk3[3] == 0
				and Suspension.unpack(Suspension.pack({ 0, 0, 0, 0 }))[1] == 0,
			string.format(
				"packed %d; worst error %.4f studs (a step is %.4f); a string, a negative and a fraction all unpack to zeros",
				Suspension.pack(lifts),
				worst,
				P.LiftRange / 127
			)
		)
	end

	------------------------------------------------------------ what it costs
	do
		local edge = 0
		local world = ground(function(_x, z)
			return if z <= edge then 0 else -8
		end)
		local s = Model.new(CFrame.new(0, C.RideHeight, 1))
		local t0 = os.clock()
		local n = 0
		Cars.withTuning(COAST, function()
			for _ = 1, 240 do
				s.velocity = Vector3.new(0, s.velocity.Y, 0.5)
				Model.step(s, { steer = 0 }, dt, world)
				n += 1
			end
		end)
		local hang = (os.clock() - t0) / n * 1e6
		local flatS = Model.new(CFrame.new(0, C.RideHeight, 0))
		local flat = World.flat(0)
		t0 = os.clock()
		for _ = 1, 2400 do
			Model.step(flatS, { steer = 0.3 }, dt, flat)
		end
		local plain = (os.clock() - t0) / 2400 * 1e6
		check(
			checks,
			"the floor solve is affordable, and only paid on a ledge",
			hang < 400,
			string.format("%.1f us a step resting on a ledge's edge, %.2f us on the flat (a step is 8333 us)", hang, plain)
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = table.concat(log, "\n") }
end

return SuspensionTests
