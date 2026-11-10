--!nonstrict
-- PartsFeelTests: fitted performance parts change how the car drives, T-106
-- (docs/game/features/car-customization.md "Rules and numbers").
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugPartsFeelTests", "run")
--
-- The model is driven on this VM exactly as the driving client drives it: a build goes on
-- through `Cars.setBuild` (what `Shared/Cars/BuildFeel` does on the client) and the model
-- reads it through `Config.Drift`. The server's bounds are asked about a stand-in userId
-- (negative) through `CarService:SetBuild`, never a real player's. Everything is put back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "PartsFeelTests only runs in Studio")

local Archetypes = require(ReplicatedStorage.Shared.Cars.Archetypes)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local Customization = require(ReplicatedStorage.Shared.Customization)
local Garage = require(ReplicatedStorage.Shared.Cars.Garage)

local CarService = require(ServerScriptService.Services.CarService)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Sim = require(DriftFolder.Sim)
local World = require(DriftFolder.World)

local PartsFeelTests = {}

local STAND_IN = -1060 -- negative: no real player can collide with it
local TEST_YAW = math.rad(15) -- off the world axes, as DriftTests drives
-- DriftTests' scripted corner, copied: the trajectory a stock build must not move.
local CORNER = { { t = 0, steer = 0 }, { t = 1, steer = 0.6 }, { t = 2.6, steer = 0 } }
local CORNER_SECONDS = 5
local CORNER_ENTRY = 120
local STRAIGHT_SECONDS = 60

local function check(checks, name, ok, detail)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
	return ok == true
end

local function startCF(): CFrame
	return CFrame.new(0, Config.Drift.RideHeight, 0) * CFrame.Angles(0, TEST_YAW, 0)
end

local function ahead(speed: number): Vector3
	return Model.axes(TEST_YAW) * speed
end

local function own(base: string, key: string): number
	local v = Archetypes.Cars[base][key]
	if v == nil then
		v = Archetypes.Base[key]
	end
	return v
end

local function withParts(parts: { [string]: string }, base: string?)
	local build = Customization.stock(base)
	for category, part in parts do
		build.parts[category] = part
	end
	return build
end

local function corner()
	return Sim.drive(CORNER, CORNER_SECONDS, { fps = 60, start = startCF(), velocity = ahead(CORNER_ENTRY) })
end

-- Flat out on a straight from just under the car's top speed: what it settles at.
local function straight(from: number): number
	local _, summary =
		Sim.drive({ { t = 0, steer = 0 } }, STRAIGHT_SECONDS, { fps = 60, start = startCF(), velocity = ahead(from) })
	return summary.maxSpeed
end

local function fmt(n: number, places: number?): string
	return string.format(`%.{places or 2}f`, n)
end

function PartsFeelTests.run()
	local checks = {}
	local passed = true
	local function pass(ok)
		passed = passed and ok
	end
	local C = Config.Drift
	local wasActive = Cars.activeKey()
	local wasBuild = Cars.build()
	local wasTune = Cars.tuning()
	Cars.setBuild(nil)
	Cars.setTuning(nil)

	local ok, err = pcall(function()
		-- 1. Stock is today's car exactly: no fields, every number `==`, the server agrees.
		do
			local bad, n = {}, 0
			for _, key in Archetypes.Order do
				local stock = Customization.stock(key)
				if next(Customization.carFields(stock, key)) ~= nil then
					table.insert(bad, `{key}: stock moves something`)
				end
				local server = (function()
					CarService.builds[STAND_IN] = Customization.copy(stock)
					local numbers = CarService:_numbersFor(STAND_IN, key)
					CarService.builds[STAND_IN] = nil
					return numbers
				end)()
				local plain = Cars.resolve(key)
				Cars.withBuild(Customization.layer(stock), function()
					Cars.withActive(key, function()
						for _, slider in Garage.Sliders do
							n += 1
							local want = own(key, slider.key)
							if Cars.active()[slider.key] ~= want or C[slider.key] ~= want then
								table.insert(bad, `{key}.{slider.key} client`)
							end
							if server[slider.key] ~= plain[slider.key] then
								table.insert(bad, `{key}.{slider.key} server`)
							end
						end
					end)
				end)
			end
			pass(
				check(
					checks,
					"a stock build is today's car exactly",
					#bad == 0,
					if #bad == 0
						then `{n} numbers on {#Archetypes.Order} cars, every one == the archetype on the client and the server`
						else table.concat(bad, ", ")
				)
			)
		end

		-- 2. And drives the identical line: DriftTests' corner, point for point.
		do
			local pathA, a = corner()
			local pathB, b = Cars.withBuild(Customization.layer(Customization.stock(Cars.activeKey())), corner)
			local worst = if #pathA == #pathB then 0 else math.huge
			for i = 1, math.min(#pathA, #pathB) do
				worst = math.max(worst, (pathA[i] - pathB[i]).Magnitude)
			end
			pass(
				check(
					checks,
					"a stock build drives DriftTests' corner identically",
					worst == 0 and a.endPosition == b.endPosition,
					`{#pathA} points, worst gap {worst} studs; turned {fmt(a.headingChangeDeg, 1)} deg both`
				)
			)
		end

		-- 3. A race engine and long gears raise top speed by their fraction, on a straight.
		local measuredRace, raceTop
		do
			local key = Cars.activeKey()
			local stockTop = own(key, "TopSpeed")
			local stockMeasured = straight(stockTop * 0.95)
			local lines, good = {}, true
			for _, partId in { "engine_race", "engine_longgears" } do
				local build = withParts({ Engine = partId }, key)
				local fields = Customization.carFields(build, key)
				local part = Customization.part(partId)
				local measured = Cars.withBuild(Customization.layer(build), function()
					return straight(stockTop * 0.95)
				end)
				local gotFraction = measured / stockMeasured - 1
				local wantFraction = fields.TopSpeed / stockTop - 1
				-- Within half a percentage point of the snapped number, and of the part's own.
				local fine = math.abs(gotFraction - wantFraction) < 0.005
					and math.abs(gotFraction - part.perf.TopSpeed) < 0.005
				good = good and fine
				if partId == "engine_race" then
					measuredRace, raceTop = measured, fields.TopSpeed
				end
				table.insert(
					lines,
					`{partId}: {fmt(stockMeasured)} -> {fmt(measured)} studs/s (+{fmt(gotFraction * 100)}%; part +{fmt(
						part.perf.TopSpeed * 100
					)}%, number {stockTop} -> {fields.TopSpeed})`
				)
			end
			pass(check(checks, "an Engine part raises top speed by its fraction", good, table.concat(lines, "; ")))
		end

		-- 4. The server takes the faster packets: the bound moves with the build.
		do
			local tol = C.StateSpeedTolerance
			local stockBound = Cars.resolve(Cars.Default).TopSpeed * tol
			local built = withParts({ Engine = "engine_race" }, Cars.Default)
			CarService:SetBuild(STAND_IN, built)
			local numbers = CarService:_numbersFor(STAND_IN, Cars.Default)
			local builtBound = numbers.TopSpeed * tol
			local justUnder = ahead(builtBound * 0.995)
			local honest = ahead(measuredRace)
			local takesHonest = CarService.speedFits(honest, numbers)
			local takesFast = CarService.speedFits(justUnder, numbers)
			local stockRefuses = not CarService.speedFits(justUnder, Cars.resolve(Cars.Default))
			local track = CarService.track(Vector3.zero, 0)
			local reach = numbers.TopSpeed * tol * C.StateMoveTolerance * 0.99
			local fitsFar = CarService.fits(track, Vector3.new(reach, 0, 0), 1, numbers)
			-- Back to stock lowers the bound, behind the switch grace like a car switch.
			CarService.seen[STAND_IN] = { expect = track }
			CarService:SetBuild(STAND_IN, nil)
			local graced = CarService.seen[STAND_IN].carWas ~= nil
				and CarService.seen[STAND_IN].carWas.TopSpeed == numbers.TopSpeed
			local back = CarService:_numbersFor(STAND_IN, Cars.Default).TopSpeed
			CarService.seen[STAND_IN] = nil
			pass(
				check(
					checks,
					"the server takes the faster packets",
					takesHonest
						and takesFast
						and stockRefuses
						and fitsFar
						and graced
						and back == Cars.resolve(Cars.Default).TopSpeed
						and raceTop == numbers.TopSpeed,
					`bound {fmt(stockBound)} -> {fmt(builtBound)} studs/s; the measured {fmt(measuredRace)} taken {takesHonest}, {fmt(
						builtBound * 0.995
					)} taken {takesFast} (stock refuses {stockRefuses}); a move of {fmt(reach)} studs in 1 s fits {fitsFar}; back to stock {back}, grace {graced}`
				)
			)
		end

		-- 5. The dev tuner's ceiling never pulls a built car below its build.
		do
			local built = withParts({ Engine = "engine_longgears" }, "bruiser")
			CarService:SetBuild(STAND_IN, built)
			local ceiling = Garage.fastestArchetype()
			local under = Cars.withTuning({ TopSpeed = ceiling }, function()
				return CarService:_numbersFor(STAND_IN, "bruiser").TopSpeed
			end)
			local over = Cars.withTuning({ TopSpeed = 400 }, function()
				return CarService:_numbersFor(STAND_IN, "bruiser").TopSpeed
			end)
			local want = Customization.carFields(built, "bruiser").TopSpeed
			CarService:SetBuild(STAND_IN, nil)
			pass(
				check(
					checks,
					"the tuner's server ceiling never lowers a build",
					under == want and over == 400 and want > ceiling,
					`bruiser + long gears {want}; under a {ceiling} ceiling the bound uses {under}, under 400 it uses {over}`
				)
			)
		end

		-- 6. Every build on every car stays inside the tuner's ranges, and the parts follow
		-- the player into another car: that car's own numbers, by the same fractions.
		do
			local function partsOf(category)
				local out = {}
				for _, part in Customization.partsIn(category) do
					table.insert(out, part.id)
				end
				return out
			end
			local engines, susps, wheels = partsOf("Engine"), partsOf("Suspension"), partsOf("Wheels")
			local n, bad, follow = 0, {}, 0
			for _, base in Archetypes.Order do
				for _, e in engines do
					for _, s in susps do
						for _, w in wheels do
							local build = withParts({ Engine = e, Suspension = s, Wheels = w }, base)
							local layer = Customization.layer(build)
							for _, key in Archetypes.Order do
								local fields = Customization.carFields(build, key)
								local rebased = Customization.resolve(withParts({ Engine = e, Suspension = s, Wheels = w }, key))
								for field, value in fields do
									n += 1
									local slider = Garage.sliderForKey(field)
									if not slider or value < slider.min or value > slider.max then
										table.insert(bad, `{key} {e}/{s}/{w} {field} {value}`)
									end
									if value ~= rebased[field] or (layer[key] or {})[field] ~= value then
										table.insert(bad, `{key} {field} not the rebased number`)
									end
									follow += 1
								end
							end
						end
					end
				end
			end
			pass(
				check(
					checks,
					"every build on every car stays in the tuner's ranges",
					#bad == 0 and n > 0,
					if #bad == 0
						then `{n} moved numbers ({#Archetypes.Order} saved bases x {#Archetypes.Order} cars driven x 125 builds), all inside; each the driven car's own number x the part`
						else `{#bad} bad: {table.concat(bad, "; ", 1, math.min(#bad, 5))}`
				)
			)
		end

		-- 7. On the next simulation step: one step's push, before and after a fit.
		do
			local key = Cars.activeKey()
			local build = withParts({ Engine = "engine_race", Wheels = "wheels_semislick" }, key)
			local fields = Customization.carFields(build, key)
			local function oneStep(): number
				local world = World.flat(0)
				local runner = Sim.newRunner(startCF())
				runner.state.velocity = ahead(5)
				-- One step for the ground rays to find the floor (a fresh state has cast none),
				-- then the step that is read.
				Sim.advance(runner, C.FixedStep, { steer = 0 }, world)
				local before = Model.speed(runner.state)
				Sim.advance(runner, C.FixedStep, { steer = 0 }, world)
				return Model.speed(runner.state) - before
			end
			local stockPush = oneStep()
			local reads, builtPush = Cars.withBuild(Customization.layer(build), function()
				local seen = {}
				for field, value in fields do
					if C[field] ~= value then
						table.insert(seen, field)
					end
				end
				return seen, oneStep()
			end)
			local ratio = builtPush / stockPush
			local want = fields.MaxAcceleration / own(key, "MaxAcceleration")
			pass(
				check(
					checks,
					"a fit lands on the next simulation step",
					#reads == 0 and math.abs(ratio - want) < 0.01,
					`Config.Drift reads all {#Garage.Sliders} build numbers ({if #reads == 0 then "none off" else table.concat(reads, ",")}); one step's push x{fmt(
						ratio,
						3
					)}, power x{fmt(want, 3)}`
				)
			)
		end

		-- 8. The tuner still works on top: a slider wins its number, letting go gives the
		-- build back, and the tuner never clears the build.
		do
			local key = Cars.activeKey()
			local build = withParts({ Engine = "engine_race" }, key)
			local builtTop = Customization.carFields(build, key).TopSpeed
			local log = {}
			local good = Cars.withBuild(Customization.layer(build), function()
				local a = C.TopSpeed == builtTop
				Cars.tune("TopSpeed", 250)
				local b = C.TopSpeed == 250
				Cars.untune("TopSpeed")
				local c = C.TopSpeed == builtTop
				Cars.setTuning({ ConstantFriction = 50 })
				local d = C.ConstantFriction == 50 and C.TopSpeed == builtTop
				Cars.untuneAll()
				local e = C.ConstantFriction == own(key, "ConstantFriction") and C.TopSpeed == builtTop
				log = { `built {builtTop}`, `tuned 250 {b}`, `untuned {C.TopSpeed}`, `grip tuned {d}`, `untuneAll keeps build {e}` }
				return a and b and c and d and e
			end)
			pass(check(checks, "the tuner works on top of the build", good, table.concat(log, ", ")))
		end
	end)

	Cars.setActive(wasActive)
	Cars.setBuild(wasBuild)
	Cars.setTuning(wasTune)
	CarService.builds[STAND_IN] = nil
	CarService.seen[STAND_IN] = nil
	if not ok then
		pass(check(checks, "the suite ran to the end", false, tostring(err)))
	end

	-- 9. Nothing left behind.
	do
		local left = {}
		if next(Cars.build()) ~= nil and next(wasBuild) == nil then
			table.insert(left, "a build layer")
		end
		if next(Cars.tuning()) ~= nil and next(wasTune) == nil then
			table.insert(left, "tuning")
		end
		if CarService.builds[STAND_IN] then
			table.insert(left, "the stand-in's build")
		end
		pass(
			check(
				checks,
				"the tests left nothing behind",
				#left == 0,
				if #left == 0 then "no build, no tuning, no stand-in" else table.concat(left, ", ")
			)
		)
	end

	return { passed = passed, checks = checks }
end

return PartsFeelTests
