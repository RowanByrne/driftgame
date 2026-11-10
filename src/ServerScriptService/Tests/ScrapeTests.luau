--!nonstrict
-- ScrapeTests: sparks and the scrape off the car's floor (docs/game/features/car-v2.md
-- "Floor scraping", T-097; Drift/Scrape).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugScrapeTests", "run")
--
-- Pure model drives on made-up ground, as `SuspensionTests` does: a car rolled backwards
-- off a ledge, so its floor lands on the edge and grinds, and a car driven on the flat.
-- `Drift/Scrape` is updated every step from the model's own state, with its spark parts in
-- a folder of the test's own and its sound on a stand-in body, both taken down after.
--
-- `run()` returns `{ passed, checks, log }`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "ScrapeTests only runs in Studio")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Scrape = require(DriftFolder.Scrape)
local World = require(DriftFolder.World)

local ScrapeTests = {}

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
end

-- Ground made of a height function (SuspensionTests' own).
local function ground(height: (number, number) -> number?): Model.World
	local C = Config.Drift
	return {
		probe = function(pos: Vector3): Model.Hit?
			local y = height(pos.X, pos.Z)
			if not y then
				return nil
			end
			return { y = y, normal = Vector3.yAxis, grip = C.GripTarmac, score = C.ScoreTarmac }
		end,
		sweep = nil,
		penetration = nil,
	}
end

-- No engine and no grip: the ledge is about the floor.
local COAST = { MaxAcceleration = 0, ConstantFriction = 0, SlipFriction = 0, SlipSqFriction = 0 }

-- A ledge whose top is Y = 0 for z <= 0, 8 below beyond. The car faces -Z and is rolled
-- backwards off it at `speed`, rear first. `onStep(s)` after every model step.
local function ledgeDrive(speed: number, onStep)
	local C = Config.Drift
	local world = ground(function(_x, z)
		return if z <= 0 then 0 else -8
	end)
	local s = Model.new(CFrame.new(0, C.RideHeight, -9))
	Cars.withTuning(COAST, function()
		for _ = 1, math.floor(9 / C.FixedStep) do
			s.velocity = Vector3.new(0, s.velocity.Y, speed)
			Model.step(s, { steer = 0 }, C.FixedStep, world)
			if onStep then
				onStep(s)
			end
			if s.position.Y < -6 then
				break
			end
		end
	end)
	return s
end

-- The distinct sliding points in a list of contacts, as Scrape is meant to see them.
local function distinctFast(contacts): number
	local P = Config.Fx.Scrape
	local pts = {}
	for _, c in contacts do
		local merged = false
		for _, q in pts do
			if (q.p - c.position).Magnitude <= P.MergeDistance then
				q.s = math.max(q.s, c.speed)
				merged = true
				break
			end
		end
		if not merged then
			table.insert(pts, { p = c.position, s = c.speed })
		end
	end
	local n = 0
	for _, q in pts do
		if q.s >= P.MinSpeed then
			n += 1
		end
	end
	return math.min(n, P.MaxPoints)
end

local function lit(scrape): number
	local n = 0
	for _, slot in scrape.slots do
		if slot.on and slot.emitter.Enabled then
			n += 1
		end
	end
	return n
end

local function runAll()
	local C = Config.Drift
	local P = Config.Fx.Scrape
	local dt = C.FixedStep
	local checks = {}
	local log = {}

	local folder = Instance.new("Folder")
	folder.Name = "ScrapeTestsFx"
	folder.Parent = workspace
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.Transparency = 1
	body.Position = Vector3.new(-31000, 900, 31000)
	body.Parent = folder

	local ok, err = pcall(function()
		local scrape = Scrape.new(folder)
		scrape:Attach({ body = body })
		local instancesBefore = scrape:CountInstances()

		------------------------------------------------ the ledge: on only while touching
		local steps, touchSteps, litSteps, mismatch, afterOff = 0, 0, 0, 0, 0
		local maxRaw, maxPoints = 0, 0
		local worstH, worstV = 0, 0
		local touchedOnce = false
		local samples = {}
		ledgeDrive(3, function(s)
			scrape:Update(s, dt)
			steps += 1
			local want = distinctFast(s.floorContacts)
			local got = lit(scrape)
			maxRaw = math.max(maxRaw, #s.floorContacts)
			maxPoints = math.max(maxPoints, scrape.n)
			if want > 0 then
				touchSteps += 1
				touchedOnce = true
			end
			if got > 0 then
				litSteps += 1
				if #s.floorContacts == 0 then
					afterOff += 1
				end
			end
			if want ~= got then
				mismatch += 1
			end
			-- Each lit spark sits on a contact the model listed: the nearest one's offset.
			for i, slot in scrape.slots do
				if slot.on then
					local at = slot.part.Position - Vector3.new(0, P.Lift, 0)
					local best, bh, bv = math.huge, 0, 0
					for _, c in s.floorContacts do
						local d = at - c.position
						if d.Magnitude < best then
							best = d.Magnitude
							bh = Vector3.new(d.X, 0, d.Z).Magnitude
							bv = math.abs(d.Y)
						end
					end
					worstH = math.max(worstH, bh)
					worstV = math.max(worstV, bv)
					if #samples < 6 and steps % 10 == 0 then
						table.insert(
							samples,
							string.format(
								"step %d slot %d spark (%.2f, %.2f, %.2f) speed %.2f rate %.0f, car z %.2f",
								steps, i, slot.part.Position.X, slot.part.Position.Y, slot.part.Position.Z,
								scrape.ps[i], slot.emitter.Rate, s.position.Z
							)
						)
					end
				end
			end
		end)
		table.insert(log, "LEDGE 3 studs/s backwards, sparks:\n  " .. table.concat(samples, "\n  "))
		check(
			checks,
			"off a ledge, sparks are lit exactly while a floor point touches and slides, one per distinct point",
			touchedOnce and mismatch == 0 and afterOff == 0,
			string.format(
				"%d steps: %d with a sliding floor contact, %d with sparks lit, %d where the lit count differed from the distinct sliding points, %d lit with no contact; most contacts the model listed in a step %d, merged to %d points",
				steps, touchSteps, litSteps, mismatch, afterOff, maxRaw, maxPoints
			)
		)
		check(
			checks,
			"each spark sits on its contact",
			touchedOnce and worstH < 1e-3 and worstV < 1e-3,
			string.format("worst offset from the nearest contact (less Lift %.2f): %.5f studs across, %.5f up", P.Lift, worstH, worstV)
		)

		------------------------------------------------ louder the faster it slides
		local function peak(speed: number)
			scrape:Cut()
			local top, fastest = 0, 0
			ledgeDrive(speed, function(s)
				scrape:Update(s, dt)
				top = math.max(top, scrape.target)
				fastest = math.max(fastest, scrape.fastest)
			end)
			return top, fastest
		end
		local v1, f1 = peak(2)
		local v2, f2 = peak(5)
		local v3, f3 = peak(10)
		local stepsUp = {}
		local prev, rising = -1, true
		for _, sp in { 0.2, 1, 5, 10, 20, 40, 80 } do
			local v = Scrape.volumeFor(sp)
			table.insert(stepsUp, string.format("%g->%.3f", sp, v))
			if v < prev then
				rising = false
			end
			prev = v
		end
		check(
			checks,
			"the scrape is louder the faster the floor slides",
			rising and v1 > 0 and v2 > v1 and v3 > v2,
			string.format(
				"ledge at 2 / 5 / 10 studs/s: fastest point %.2f / %.2f / %.2f studs/s, peak volume %.3f / %.3f / %.3f; the curve (speed->volume): %s",
				f1, f2, f3, v1, v2, v3, table.concat(stepsUp, " ")
			)
		)
		-- And it fades out once the floor is clear.
		scrape:Cut()
		local endVol = 0
		ledgeDrive(3, function(s)
			scrape:Update(s, dt)
		end)
		for _ = 1, 60 do
			scrape:Update(nil, dt)
		end
		endVol = scrape.volume
		check(checks, "silent again once the floor is clear", endVol == 0 and lit(scrape) == 0, string.format("volume %.4f and %d sparks half a second after", endVol, lit(scrape)))

		------------------------------------------------ duplicates merge
		scrape:Cut()
		local p0 = Vector3.new(0, 0, 0)
		scrape:Update({
			velocity = Vector3.new(0, 0, 10),
			floorContacts = {
				{ name = "FloorRL", position = p0, speed = 10, edge = false },
				{ name = "FloorRL", position = p0, speed = 10, edge = false },
				{ name = "FloorRC", position = p0 + Vector3.new(0.2, 0, 0), speed = 12, edge = true },
				{ name = "FloorRR", position = p0 + Vector3.new(3, 0, 0), speed = 9, edge = false },
			},
		}, dt)
		local dup = scrape:DebugState()
		check(
			checks,
			"a point listed once per segment is one spark",
			dup.rawContacts == 4 and dup.points == 2 and #dup.sparks == 2 and math.abs(dup.fastest - 12) < 1e-9,
			string.format("%d contacts listed -> %d points, %d sparks lit, fastest %.1f", dup.rawContacts, dup.points, #dup.sparks, dup.fastest)
		)
		scrape:Cut()

		------------------------------------------------ flat driving: nothing
		do
			local s = Model.new(CFrame.new(0, C.RideHeight, 0))
			local flat = World.flat(0)
			local everLit, worstTarget = 0, 0
			for i = 1, 1200 do
				Model.step(s, { steer = if i > 300 then 0.6 else 0 }, dt, flat)
				scrape:Update(s, dt)
				everLit = math.max(everLit, lit(scrape))
				worstTarget = math.max(worstTarget, scrape.target)
			end
			check(
				checks,
				"on flat driving there are no sparks and no scrape",
				everLit == 0 and worstTarget == 0,
				string.format("10 s straight then sliding: most sparks lit %d, loudest target %.3f, speed at the end %.1f", everLit, worstTarget, s.velocity.Magnitude)
			)
		end

		------------------------------------------------ looks only
		local a = ledgeDrive(3, function(s)
			scrape:Update(s, dt)
		end)
		local b = ledgeDrive(3, nil)
		check(
			checks,
			"the car's motion is the same with the sparks running or not",
			(a.position - b.position).Magnitude < 1e-9 and (a.velocity - b.velocity).Magnitude < 1e-9,
			string.format("%.3e studs and %.3e studs/s apart at the end", (a.position - b.position).Magnitude, (a.velocity - b.velocity).Magnitude)
		)

		local instancesAfter = scrape:CountInstances()
		check(
			checks,
			"nothing is created or destroyed while driving",
			instancesBefore == instancesAfter and instancesBefore == P.MaxPoints * 2 + 2,
			string.format("%d instances before every drive, %d after (%d slots x part+emitter, the folder, the sound)", instancesBefore, instancesAfter, P.MaxPoints)
		)
		scrape:Destroy()
	end)
	folder:Destroy()
	if not ok then
		check(checks, "ScrapeTests ran", false, tostring(err))
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = table.concat(log, "\n") }
end

function ScrapeTests.run()
	return Cars.withActive("balanced", runAll)
end

return ScrapeTests
