--!nonstrict
-- GarageTests: the car tuner's automated checks
-- (docs/game/features/car-tuner.md "Testing", docs/workflow/TESTING.md).
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugGarageTests", "run")
--
-- THIS IS THE FIRST THING IN THIS GAME THAT SAVES ANYTHING, so it gets the treatment
-- saving gets (TESTING.md "What gets one"): the store is a fake one swapped in for the
-- length of the run, no real player's garage is touched, and the checks cover the things
-- that lose data -- a write that fails, a garage over its cap, a name that is not a name,
-- and a number off the wire that the simulation could not survive.
--
-- Most of it is pure. Three checks run the real drift model from `Drift/Sim`, exactly as
-- `DriftTests` does, because "a slider lands on the next step" is a claim about the model
-- and not about this file.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "GarageTests only runs in Studio")

local Archetypes = require(ReplicatedStorage.Shared.Cars.Archetypes)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local Garage = require(ReplicatedStorage.Shared.Cars.Garage)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Sim = require(DriftFolder.Sim)
local World = require(DriftFolder.World)

local CarService = require(ServerScriptService.Services.CarService)
local GarageService = require(ServerScriptService.Services.GarageService)

local GarageTests = {}

local TEST_USER = -4040 -- negative: no real player can collide with it
local TEST_USER_B = -4041

local function check(checks, name, ok, detail)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
	return ok == true
end

local function round(x: number, places: number?): number
	local scale = 10 ^ (places or 6)
	return math.round(x * scale) / scale
end

-- A stand-in for a Player: the service only ever reads `UserId` off one, and `_tell`
-- checks it has a real Instance before it fires a remote at it.
local function standIn(userId: number)
	return { UserId = userId, Name = `stand-in {userId}` }
end

-- A store that refuses every write, for the check that a failed write never costs the
-- player the car they are driving.
local function brokenStore()
	return {
		kind = "memory",
		reason = "broken, on purpose",
		reads = 0,
		writes = 0,
		failures = 0,
		Get = function(self, _key)
			self.reads += 1
			return false, "GetAsync refused (test)"
		end,
		Set = function(self, _key, _value)
			self.writes += 1
			self.failures += 1
			return false, "SetAsync refused (test)"
		end,
	}
end

-- ---------------------------------------------------------------------- the model

local TEST_YAW = math.rad(15) -- off the world axes, for the reason DriftTests states

local function startCF(): CFrame
	return CFrame.new(0, Config.Drift.RideHeight, 0) * CFrame.Angles(0, TEST_YAW, 0)
end

-- One step of the real model from a known state, and what it did. `tune` is applied the
-- way the tuner applies it -- through `Cars.setTuning` -- and taken off again however the
-- run ends.
--
--   yawRate   how fast the car rotated this step, rad/s      (Eagerness)
--   gripPull  the sideways pull along the car's right, studs/s^2  (Grip / Bite)
--   accel     the push along the nose, studs/s^2             (Power)
local function oneStep(tune: { [string]: number }?, slipDeg: number, speed: number, steer: number)
	local C = Config.Drift
	local was = Cars.tuning()
	Cars.setTuning(Garage.toCarFields(Garage.sanitizeTune(tune or {})))

	local runner = Sim.newRunner(startCF())
	local travel = Model.axes(TEST_YAW + math.rad(slipDeg))
	local world = World.flat(0)

	-- One step so the ground rays have found the surface, then the state is put exactly
	-- where the measurement wants it and the NEXT step is the one that is read.
	runner.state.velocity = travel * speed
	Sim.advance(runner, C.FixedStep, { steer = 0 }, world)
	runner.state.velocity = travel * speed
	runner.state.yaw = TEST_YAW

	local fwd, right = Model.axes(TEST_YAW)
	local before = runner.state.velocity
	local yawBefore = runner.state.yaw
	Sim.advance(runner, C.FixedStep, { steer = steer }, world)
	local after = runner.state.velocity

	Cars.setTuning(was)
	return {
		yawRate = (runner.state.yaw - yawBefore) / C.FixedStep,
		gripPull = math.abs((after - before):Dot(right)) / C.FixedStep,
		accel = (after - before):Dot(fwd) / C.FixedStep,
	}
end

--------------------------------------------------------------------------------

function GarageTests:run()
	local checks = {}
	local passed = 0
	local function pass(ok)
		if ok then
			passed += 1
		end
	end

	-- 1. Every archetype is inside every slider, so any of the four can be dialled up
	-- from any other and a saved car can be any of them.
	do
		local outside = {}
		for key, car in Archetypes.Cars do
			for _, slider in Garage.Sliders do
				local v = car[slider.key] or Archetypes.Base[slider.key]
				if v < slider.min or v > slider.max then
					table.insert(outside, `{key}.{slider.key} = {v} outside [{slider.min}, {slider.max}]`)
				end
			end
		end
		pass(
			check(
				checks,
				"every car is inside every slider",
				#outside == 0,
				if #outside == 0
					then `{#Garage.Sliders} sliders x {#Archetypes.Order} cars, all inside`
					else table.concat(outside, "; ")
			)
		)
	end

	-- 2. The one range that is not a matter of taste: Top speed can never be zero. The
	-- drivetrain divides by it, and zero is a NaN velocity and a car that is nowhere.
	do
		local slider = Garage.slider("topspeed")
		local low = Garage.clamp("topspeed", 0)
		local negative = Garage.clamp("topspeed", -500)
		pass(
			check(
				checks,
				"Top speed can never reach zero",
				slider.min > 0 and low == slider.min and negative == slider.min,
				`min {slider.min}; clamp(0) = {low}, clamp(-500) = {negative}`
			)
		)
	end

	-- 3. Nothing the simulation could not survive gets through, whatever the client sends.
	do
		local junk = Garage.sanitizeTune({
			topspeed = 0 / 0, -- NaN
			power = math.huge,
			grip = -math.huge,
			eagerness = "fast", -- a string
			bite = {}, -- a table
			nonsense = 5, -- a slider that does not exist
			planted = 99, -- real, but far out of range
		})
		local n = 0
		for _ in junk do
			n += 1
		end
		pass(
			check(
				checks,
				"NaN, infinity, junk and unknown sliders never reach the car",
				n == 1 and junk.planted == 1,
				`{n} value(s) survived: planted = {tostring(junk.planted)} (clamped from 99)`
			)
		)
	end

	-- 4. A value that has been through `clamp` is the same number twice, which is what
	-- makes a saved car reproduce to the value rather than to a few decimals.
	do
		local same = true
		local sample = {}
		for _, slider in Garage.Sliders do
			local raw = slider.min + (slider.max - slider.min) * 0.37
			local once = Garage.clamp(slider.id, raw)
			local twice = Garage.clamp(slider.id, once)
			if once ~= twice then
				same = false
			end
			table.insert(sample, `{slider.id}={once}`)
		end
		pass(check(checks, "a clamped value is stable", same, table.concat(sample, " ")))
	end

	-- 5. Names.
	do
		local cases = {
			{ "  Night Runner  ", "Night Runner" },
			{ "line\nbreak", "line break" },
			{ "", nil },
			{ "    ", nil },
			{ 42, nil },
			{ string.rep("x", Config.Drift.GarageNameMax + 20), string.rep("x", Config.Drift.GarageNameMax) },
		}
		local bad = {}
		for _, case in cases do
			local got = Garage.cleanName(case[1])
			if got ~= case[2] then
				table.insert(bad, `{tostring(case[1])} -> {tostring(got)}, wanted {tostring(case[2])}`)
			end
		end
		pass(
			check(
				checks,
				"a name is trimmed, bounded, and never empty",
				#bad == 0,
				if #bad == 0 then `{#cases} cases` else table.concat(bad, "; ")
			)
		)
	end

	-- 6. THE WHOLE POINT: a slider lands on the next simulation step. Three of them,
	-- measured out of the real model rather than out of the tuner.
	do
		local plain = oneStep(nil, 20, 120, 1)
		local eager = oneStep({ eagerness = 4 }, 20, 120, 1)
		local gripped = oneStep({ grip = 100 }, 20, 120, 0)
		local powered = oneStep({ power = 50 }, 0, 20, 0)
		local base = Garage.baseValues(Cars.activeKey())

		local yawOk = round(eager.yawRate, 4) ~= round(plain.yawRate, 4)
			and math.abs(math.abs(eager.yawRate) - 4) < 1e-6
		local gripOk = gripped.gripPull > plain.gripPull * 2
		local powerOk = powered.accel > plain.accel

		pass(
			check(
				checks,
				"Eagerness changes the car's yaw rate on the next step",
				yawOk,
				`{base.eagerness} rad/s -> {round(plain.yawRate, 6)} measured; 4 rad/s -> {round(eager.yawRate, 6)}`
			)
		)
		pass(
			check(
				checks,
				"Grip changes the sideways pull on the next step",
				gripOk,
				`grip {base.grip} -> {round(plain.gripPull, 4)} studs/s^2 at 20 deg of slip; `
					.. `grip 100 -> {round(gripped.gripPull, 4)}`
			)
		)
		pass(
			check(
				checks,
				"Power changes the acceleration on the next step",
				powerOk,
				`power {base.power} -> {round(plain.accel, 4)} studs/s^2 from 20 studs/s; `
					.. `power 50 -> {round(powered.accel, 4)}`
			)
		)
	end

	-- 7. The tuning layer is put back exactly, so a tuning session leaves no trace.
	do
		local before = Config.Drift.MaxSteeringSpeed
		local was = Cars.tuning()
		Cars.setTuning({ MaxSteeringSpeed = 3.5 })
		local during = Config.Drift.MaxSteeringSpeed
		Cars.setTuning(was)
		local after = Config.Drift.MaxSteeringSpeed
		pass(
			check(
				checks,
				"the tuning layer goes on and comes off exactly",
				during == 3.5 and after == before,
				`{before} -> {during} -> {after}`
			)
		)
	end

	-- 8. Save, forget everything, read it back: the same numbers, to the value.
	do
		local store = GarageService.MemoryStore("test")
		local was = GarageService:DebugSwapStore(store)
		local player = standIn(TEST_USER)
		GarageService.garages[TEST_USER] = {}

		local tune = { eagerness = 2.65, grip = 41.3, topspeed = 233, planted = 0.44 }
		GarageService:_onSave(player, "  Night Runner ", "gripper", tune)
		GarageService:_write(TEST_USER, GarageService.garages[TEST_USER])

		-- Everything in memory is dropped, exactly as leaving drops it.
		GarageService.garages[TEST_USER] = nil
		GarageService.loaded[TEST_USER] = nil

		local ok, raw = store:Get("garage_" .. TEST_USER)
		local back = Garage.sanitizeGarage(if type(raw) == "table" then raw.cars else nil)
		local car = back["Night Runner"]
		local wanted = Garage.sanitizeTune(tune)
		local same = car ~= nil and car.base == "gripper"
		local diffs = {}
		if car then
			for id, v in wanted do
				if car.tune[id] ~= v then
					table.insert(diffs, `{id}: {tostring(car.tune[id])} ~= {v}`)
				end
			end
			for id in car.tune do
				if wanted[id] == nil then
					table.insert(diffs, `{id} should not be there`)
				end
			end
		end
		pass(
			check(
				checks,
				"a saved car survives being forgotten, to the value",
				ok and same and #diffs == 0,
				if car
					then `"Night Runner" on {car.base}: eagerness {car.tune.eagerness}, grip {car.tune.grip}, `
						.. `topspeed {car.tune.topspeed}, planted {car.tune.planted}{if #diffs > 0 then "; " .. table.concat(diffs, ", ") else ""}`
					else "the car did not come back"
			)
		)
		GarageService:DebugSwapStore(was)
		GarageService.garages[TEST_USER] = nil
		GarageService.dirty[TEST_USER] = nil
		GarageService.limits[TEST_USER] = nil
	end

	-- 9. Two cars, edited one at a time, and neither moves the other.
	do
		local store = GarageService.MemoryStore("test")
		local was = GarageService:DebugSwapStore(store)
		local player = standIn(TEST_USER)
		GarageService.garages[TEST_USER] = {}
		GarageService.limits[TEST_USER] = nil

		GarageService:_onSave(player, "Alpha", "balanced", { eagerness = 1.5, grip = 10 })
		GarageService:_onSave(player, "Beta", "slider", { eagerness = 3.2, topspeed = 300 })
		-- Alpha is loaded, edited and saved again under its own name.
		GarageService:_onSave(player, "Alpha", "balanced", { eagerness = 1.5, grip = 95.5 })

		local garage = GarageService.garages[TEST_USER]
		local a, b = garage.Alpha, garage.Beta
		local ok = a ~= nil
			and b ~= nil
			and a.tune.grip == 95.5
			and a.tune.eagerness == 1.5
			and a.base == "balanced"
			and b.tune.eagerness == 3.2
			and b.tune.topspeed == 300
			and b.tune.grip == nil
			and b.base == "slider"
		pass(
			check(
				checks,
				"two saved cars are edited independently",
				ok,
				`Alpha ({a and a.base}): eagerness {a and a.tune.eagerness}, grip {a and a.tune.grip}; `
					.. `Beta ({b and b.base}): eagerness {b and b.tune.eagerness}, topspeed {b and b.tune.topspeed}, `
					.. `grip {tostring(b and b.tune.grip)}`
			)
		)
		GarageService:DebugSwapStore(was)
		GarageService.garages[TEST_USER] = nil
		GarageService.dirty[TEST_USER] = nil
		GarageService.limits[TEST_USER] = nil
	end

	-- 10. A full garage refuses a new name and still takes an overwrite, so a tuning
	-- session is never stuck with nowhere to put the car it is driving.
	do
		local store = GarageService.MemoryStore("test")
		local was = GarageService:DebugSwapStore(store)
		local player = standIn(TEST_USER_B)
		GarageService.garages[TEST_USER_B] = {}
		local max = Config.Drift.GarageMaxCars
		-- Past the rate limit on purpose would hide the cap, so the window is cleared
		-- between saves: this check is about the cap, and check 11 is about the limit.
		for i = 1, max + 3 do
			GarageService.limits[TEST_USER_B] = nil
			GarageService:_onSave(player, `car {i}`, "balanced", { grip = i })
		end
		local full = Garage.count(GarageService.garages[TEST_USER_B])
		GarageService.limits[TEST_USER_B] = nil
		GarageService:_onSave(player, "car 1", "balanced", { grip = 77 })
		local overwritten = GarageService.garages[TEST_USER_B]["car 1"]
		pass(
			check(
				checks,
				"a full garage refuses a new name and still takes an overwrite",
				full == max and overwritten and overwritten.tune.grip == 77,
				`{full}/{max} saved from {max + 3} asked; "car 1" overwritten to grip {overwritten and overwritten.tune.grip}`
			)
		)
		GarageService:DebugSwapStore(was)
		GarageService.garages[TEST_USER_B] = nil
		GarageService.dirty[TEST_USER_B] = nil
		GarageService.limits[TEST_USER_B] = nil
	end

	-- 11. A flood is ignored, counted by UserId so a rejoin does not reset it.
	do
		local store = GarageService.MemoryStore("test")
		local was = GarageService:DebugSwapStore(store)
		local player = standIn(TEST_USER)
		GarageService.garages[TEST_USER] = {}
		GarageService.limits[TEST_USER] = nil
		local before = GarageService.saves
		for i = 1, 40 do
			GarageService:_onSave(player, `flood {i}`, "balanced", { grip = i })
		end
		local took = GarageService.saves - before
		pass(
			check(
				checks,
				"a flood of saves is rate-limited",
				took <= Config.Drift.GarageSaveRateLimit,
				`{took} of 40 taken, limit {Config.Drift.GarageSaveRateLimit}/s`
			)
		)
		GarageService:DebugSwapStore(was)
		GarageService.garages[TEST_USER] = nil
		GarageService.dirty[TEST_USER] = nil
		GarageService.limits[TEST_USER] = nil
	end

	-- 12. A write that fails never costs the player the car they are driving.
	do
		local was = GarageService:DebugSwapStore(brokenStore())
		local player = standIn(TEST_USER)
		GarageService.garages[TEST_USER] = {}
		GarageService.limits[TEST_USER] = nil
		GarageService:_onSave(player, "Doomed", "bruiser", { topspeed = 390 })
		-- The real retry path, with the backoff cut to nothing so the test does not sit
		-- for six seconds.
		local backoff = Config.Drift.GarageRetryBackoff
		Config.Drift.GarageRetryBackoff = 0
		GarageService.silent = true -- the failure is the point; the warning is not
		local wrote = GarageService:_write(TEST_USER, GarageService.garages[TEST_USER])
		GarageService.silent = nil
		Config.Drift.GarageRetryBackoff = backoff

		local kept = GarageService.garages[TEST_USER].Doomed
		pass(
			check(
				checks,
				"a failed write keeps the in-memory car and stays dirty",
				wrote == false and kept ~= nil and kept.tune.topspeed == 390 and GarageService.dirty[TEST_USER] == true,
				`write returned {tostring(wrote)}; "Doomed" still here at topspeed {kept and kept.tune.topspeed}; `
					.. `dirty = {tostring(GarageService.dirty[TEST_USER])}`
			)
		)
		GarageService:DebugSwapStore(was)
		GarageService.garages[TEST_USER] = nil
		GarageService.dirty[TEST_USER] = nil
		GarageService.limits[TEST_USER] = nil
	end

	-- 13. THE ONE THING A TUNED CAR BREAKS. A car tuned past its archetype's top speed
	-- is dropped by the server's own check -- and is not, once the ceiling is in place.
	do
		local car = Cars.resolve("gripper")
		local tunedTop = 300 -- the slider's own range; the gripper's own is 150
		local velocity = Vector3.new(0, 0, -(tunedTop - 1))

		local droppedBefore = not CarService.speedFits(velocity, car)

		-- Exactly what `GarageService:_applyCeiling` does.
		local wasTune = Cars.tuning()
		Cars.setTuning({ TopSpeed = math.max(Garage.fastestArchetype(), tunedTop) })
		local withCeiling = Cars.resolve("gripper")
		local acceptedAfter = CarService.speedFits(velocity, withCeiling)

		-- And the floor: a plain bruiser must still be accepted at its own top speed
		-- whatever anybody else is tuning. Here with a SLOW tune in play.
		Cars.setTuning({ TopSpeed = math.max(Garage.fastestArchetype(), 60) })
		local bruiser = Cars.resolve("bruiser")
		local bruiserOk = CarService.speedFits(Vector3.new(0, 0, -215), bruiser)
		Cars.setTuning(wasTune)

		pass(
			check(
				checks,
				"a tuned car faster than its archetype is not dropped",
				droppedBefore and acceptedAfter and bruiserOk,
				`gripper at {tunedTop - 1} studs/s: dropped against its own {car.TopSpeed} `
					.. `(bound {round(car.TopSpeed * Config.Drift.StateSpeedTolerance, 2)}), `
					.. `accepted against the ceiling {withCeiling.TopSpeed} `
					.. `(bound {round(withCeiling.TopSpeed * Config.Drift.StateSpeedTolerance, 2)}); `
					.. `a plain bruiser at 215 still accepted while somebody tunes down to 60: {tostring(bruiserOk)}`
			)
		)
	end

	-- 14. The ceiling only ever loosens, and it goes away when nobody is tuning.
	do
		local wasTune = Cars.tuning()
		Cars.untuneAll()
		local plain = Cars.resolve("gripper").TopSpeed
		local floor = Garage.fastestArchetype()
		local fastest = 0
		for _, key in Archetypes.Order do
			fastest = math.max(fastest, Cars.resolve(key).TopSpeed)
		end
		Cars.setTuning(wasTune)
		pass(
			check(
				checks,
				"the ceiling's floor is the fastest archetype",
				floor == fastest and plain == 150,
				`floor {floor} studs/s = the fastest of {table.concat(Archetypes.Order, ", ")}; `
					.. `an untuned gripper is still {plain}`
			)
		)
	end

	-- ----------------------------------------------------------------- the three
	--
	-- Three sliders, 0..10, that really drive the eight above them -- unlike the reference
	-- game's three bars, and unlike our own `Archetypes.Bars`, which are hand-written
	-- display fields that reach nothing (`DriftTests` proves that separately).

	-- 15. The curve is anchored where it says it is: 5 is the approved car on every one of
	-- the eight keys the three touch, 0 is the slider's floor and 10 is the stated
	-- ceiling. If this fails, "handling 5" has stopped meaning the car the user approved.
	do
		local bad = {}
		for _, stat in Garage.Stats do
			for _, id in stat.keys do
				local slider = Garage.slider(id)
				local low, mid, top = Garage.statValue(id, 0), Garage.statValue(id, 5), Garage.statValue(id, 10)
				local wantedMid = Garage.clamp(id, Archetypes.Base[slider.key])
				local anchor = Garage.StatAnchors[id]
				local wantedTop = Garage.clamp(id, (anchor and anchor.top) or slider.max)
				local wantedLow = Garage.clamp(id, (anchor and anchor.low) or slider.min)
				if mid ~= wantedMid or low ~= wantedLow or top ~= wantedTop then
					table.insert(bad, `{id}: {low}/{mid}/{top} wanted {wantedLow}/{wantedMid}/{wantedTop}`)
				end
			end
		end
		pass(
			check(
				checks,
				"the three are anchored on the approved car at 5",
				#bad == 0,
				if #bad == 0
					then `8 keys across {#Garage.Stats} stats: 5 is Archetypes.Base to the value`
					else table.concat(bad, "; ")
			)
		)
	end

	-- 16. Every number a stat drives RISES with it, all the way across. This is the whole
	-- claim the one slider makes -- "more handling" is more grip, a faster rate of turn and
	-- more downforce, together -- and a curve with a dip in it would be a slider that
	-- sometimes makes the car worse as you pull it up.
	do
		local bad = {}
		for _, stat in Garage.Stats do
			for _, id in stat.keys do
				local last = Garage.statValue(id, 0)
				for i = 1, 1000 do
					local v = Garage.statValue(id, i / 100)
					if v < last then
						table.insert(bad, `{id} fell at {i / 100}: {last} -> {v}`)
						break
					end
					last = v
				end
				if last <= Garage.statValue(id, 0) then
					table.insert(bad, `{id} never rose`)
				end
			end
		end
		pass(
			check(
				checks,
				"every number the three drive rises with them",
				#bad == 0,
				if #bad == 0
					then "8 keys x 1001 steps, never once falling"
					else table.concat(bad, "; ")
			)
		)
	end

	-- 17. The four archetypes land on four different numbers rather than all on 5, which
	-- is what makes the axis absolute rather than relative to whatever car is under it.
	do
		local shown, values = {}, {}
		for _, key in Archetypes.Order do
			local stats = Garage.statsFor(key, nil)
			values[key] = stats
			table.insert(
				shown,
				`{key} {string.format("%.1f/%.1f/%.1f", stats.accel.value, stats.handling.value, stats.top.value)}`
			)
		end
		-- The grippiest car is the highest and the loosest is the lowest, and that matches
		-- the model's own measured ordering of how much speed each keeps through a corner
		-- (features/car-archetypes.md).
		local ok = values.gripper.handling.value > values.balanced.handling.value
			and values.slider.handling.value < values.balanced.handling.value
			and values.bruiser.top.value > values.gripper.top.value
			and values.bruiser.accel.value < values.gripper.accel.value
			and math.abs(values.balanced.handling.value - 5) < 1e-9
		pass(
			check(
				checks,
				"the four cars land on four different places on the three",
				ok,
				`accel/handling/top: {table.concat(shown, ", ")}`
			)
		)
	end

	-- 18. A car built from one of the three reads back AS that number. The eight are each
	-- snapped to their own step on the way out, so this is not free -- it is what lets the
	-- panel show a number rather than `custom` after a save and a load.
	do
		local bad = {}
		for _, stat in Garage.Stats do
			for i = 0, 1000 do
				local s = i / 100
				local tune = Garage.statTune(stat.id, s)
				local _, exact = Garage.statFit(stat.id, Garage.values("balanced", tune))
				if not exact then
					table.insert(bad, `{stat.id} at {s}`)
					break
				end
			end
		end
		pass(
			check(
				checks,
				"a car built from the three reads back as the three",
				#bad == 0,
				if #bad == 0
					then `{#Garage.Stats} stats x 1001 values, every one exact`
					else table.concat(bad, "; ")
			)
		)
	end

	-- 19. AND THE HONEST HALF. Move one of the eight by hand afterwards and the stat above
	-- it cannot be read back as one number any more, so it says so. The other two, which
	-- share none of its keys, are untouched.
	do
		local tune = Garage.statTune("handling", 7)
		for id, v in Garage.statTune("accel", 6) do
			tune[id] = v
		end
		local clean = Garage.statsFor("balanced", tune)
		tune.bite = Garage.clamp("bite", 90) -- one of handling's six, moved by hand
		local dirty = Garage.statsFor("balanced", tune)
		local ok = clean.handling.exact
			and clean.accel.exact
			and not dirty.handling.exact
			and dirty.accel.exact
			and dirty.accel.value == clean.accel.value
		pass(
			check(
				checks,
				"a detailed slider moved by hand makes its stat custom, and only its own",
				ok,
				`handling {string.format("%.2f", clean.handling.value)} exact -> bite 90 -> `
					.. `{string.format("%.2f", dirty.handling.value)} custom; `
					.. `accel {string.format("%.2f", dirty.accel.value)} still exact`
			)
		)
	end

	-- 20. THE POINT OF THE WHOLE FEATURE, measured out of the real model: pulling Handling
	-- up changes how the car rotates AND how hard it is held sideways, on the next step.
	do
		local low = oneStep(Garage.statTune("handling", 3), 20, 120, 1)
		local high = oneStep(Garage.statTune("handling", 7), 20, 120, 1)
		-- The rate of turn IS one of handling's six, so the yaw rate the model produces is
		-- the number the curve asked for, to the digit.
		local ok = math.abs(math.abs(low.yawRate) - Garage.statValue("eagerness", 3)) < 1e-6
			and math.abs(math.abs(high.yawRate) - Garage.statValue("eagerness", 7)) < 1e-6
			and high.gripPull > low.gripPull * 2
		pass(
			check(
				checks,
				"Handling changes how the car rotates and how hard it grips",
				ok,
				`handling 3: {round(math.abs(low.yawRate), 3)} rad/s, {round(low.gripPull, 2)} studs/s^2 sideways; `
					.. `handling 7: {round(math.abs(high.yawRate), 3)} rad/s, {round(high.gripPull, 2)}`
			)
		)
	end

	-- 21. A car tuned ONLY with the three saves and loads like any other, because it IS
	-- any other: the three write ordinary slider values and nothing new is stored.
	do
		local store = GarageService.MemoryStore("test")
		local was = GarageService:DebugSwapStore(store)
		local player = standIn(TEST_USER)
		GarageService.garages[TEST_USER] = {}
		GarageService.limits[TEST_USER] = nil

		local tune = Garage.statTune("handling", 7.5)
		for id, v in Garage.statTune("accel", 8) do
			tune[id] = v
		end
		for id, v in Garage.statTune("top", 6.5) do
			tune[id] = v
		end
		GarageService:_onSave(player, "Simple", "bruiser", tune)
		GarageService:_write(TEST_USER, GarageService.garages[TEST_USER])
		GarageService.garages[TEST_USER] = nil
		GarageService.loaded[TEST_USER] = nil

		local ok, raw = store:Get("garage_" .. TEST_USER)
		local back = Garage.sanitizeGarage(if type(raw) == "table" then raw.cars else nil)
		local car = back.Simple
		local stats = if car then Garage.statsFor(car.base, car.tune) else nil
		local same = car ~= nil
			and car.base == "bruiser"
			and stats.handling.exact
			and stats.accel.exact
			and stats.top.exact
			and math.abs(stats.handling.value - 7.5) < 0.05
			and math.abs(stats.accel.value - 8) < 0.05
			and math.abs(stats.top.value - 6.5) < 0.05
		pass(
			check(
				checks,
				"a car tuned only with the three comes back as those three",
				ok and same,
				if stats
					then `"Simple" on {car.base}: {string.format("%.2f / %.2f / %.2f", stats.accel.value, stats.handling.value, stats.top.value)} `
						.. `(asked 8 / 7.5 / 6.5), all exact`
					else "the car did not come back"
			)
		)
		GarageService:DebugSwapStore(was)
		GarageService.garages[TEST_USER] = nil
		GarageService.dirty[TEST_USER] = nil
		GarageService.limits[TEST_USER] = nil
	end

	-- 22. Nothing above left a tune on the car, which would poison every check after it
	-- and every playtest in this server.
	do
		local left = {}
		for key, value in Cars.tuning() do
			table.insert(left, `{key} = {tostring(value)}`)
		end
		pass(
			check(
				checks,
				"the tests left no tuning behind",
				#left == 0,
				if #left == 0 then "the car is the car" else table.concat(left, ", ")
			)
		)
	end

	return { passed = passed, checks = checks }
end

-- Studio only, and no part of `run()`: what a real player's garage holds right now.
function GarageTests:garage(userId: number?)
	local id = userId
	if not id then
		local player = Players:GetPlayers()[1]
		id = player and player.UserId
	end
	if not id then
		return "no player"
	end
	return GarageService:DebugState()
end

return GarageTests
