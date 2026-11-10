--!nonstrict
-- CustomizationTests: the parts catalog and fitting parts to a car, T-101
-- (docs/game/features/car-customization.md "Testing", docs/workflow/TESTING.md).
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugCustomizationTests", "run")
--
-- THIS SAVES, so it gets the treatment saving gets: the store is a fake one swapped in for
-- the length of each check, the players are stand-ins with negative UserIds, and no real
-- player's garage or car is touched. The one check that reads a real player's car only
-- reads it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

assert(RunService:IsStudio(), "CustomizationTests only runs in Studio")

local Archetypes = require(ReplicatedStorage.Shared.Cars.Archetypes)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Customization = require(ReplicatedStorage.Shared.Customization)
local Garage = require(ReplicatedStorage.Shared.Cars.Garage)

local CustomizationService = require(ServerScriptService.Services.CustomizationService)
local GarageService = require(ServerScriptService.Services.GarageService)

local CustomizationTests = {}

local TEST_USER = -1010 -- negative: no real player can collide with it
local TEST_USER_B = -1011

local function check(checks, name, ok, detail)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
	return ok == true
end

-- A stand-in for a Player: the services only read `UserId` off one, and never fire a
-- remote at anything that is not a real Player.
local function standIn(userId: number)
	return { UserId = userId, Name = `stand-in {userId}` }
end

-- A stand-in in the garage, its store answered, with a fresh fake store. Returns the store
-- that was there, for `leave`.
local function arrive(userId: number, store)
	local was = GarageService:DebugSwapStore(store or GarageService.MemoryStore("test"))
	GarageService.garages[userId] = {}
	GarageService.loaded[userId] = true
	GarageService.builds[userId] = nil
	GarageService.dirty[userId] = nil
	CustomizationService.limits[userId] = nil
	return was
end

local function leave(userId: number, was)
	GarageService:DebugSwapStore(was)
	GarageService.garages[userId] = nil
	GarageService.builds[userId] = nil
	GarageService.loaded[userId] = nil
	GarageService.dirty[userId] = nil
	GarageService.limits[userId] = nil
	CustomizationService.limits[userId] = nil
end

-- The archetype's own number, read straight off `Archetypes`: what "today's car" means.
local function own(base: string, key: string): number
	local v = Archetypes.Cars[base][key]
	if v == nil then
		v = Archetypes.Base[key]
	end
	return v
end

local function describe(build): string
	local bits = { build.base }
	for _, id in Customization.PartCategories do
		table.insert(bits, build.parts[id])
	end
	for _, field in Customization.Paint.fieldOrder do
		table.insert(bits, `{field}={build.paint[field]}`)
	end
	return table.concat(bits, " ")
end

-- Every ask a client could make that must be refused, as (category, choice). Each is
-- something a broken or hostile client could send down `CustomizeFit`.
local BAD_ASKS = {
	{ 123, "engine_race" }, -- a number for a category
	{ {}, {} }, -- tables for both
	{ 0 / 0, nil }, -- NaN
	{ nil, "engine_race" }, -- a part with no category (not a question: choice is set)
	{ "Turbo", "engine_race" }, -- no such category
	{ "engine", "engine_race" }, -- the wrong case
	{ "Fit_Engine", "engine_race" }, -- an attribute name, not a category
	{ string.rep("E", 1000), "engine_race" }, -- a long string
	{ "Engine", nil }, -- a category with no part
	{ "Engine", "" }, -- an empty part
	{ "Engine", "engine_nitro" }, -- no such part
	{ "Engine", "engine_race " }, -- a near miss
	{ "Engine", "wheels_mesh" }, -- a real part, from another category
	{ "Engine", 5 }, -- a number for a part
	{ "Engine", { "engine_race" } }, -- a table for a part
	{ "Engine", string.rep("x", 5000) }, -- a long part id
	{ "Paint", "red" }, -- paint must be a table
	{ "Paint", {} }, -- paint that sets nothing
	{ "Paint", { body = "gold" } }, -- no such colour
	{ "Paint", { colour = "red" } }, -- no such paint field
	{ "Paint", { body = Color3.new(1, 0, 0) } }, -- a Color3, not an id
	{ "Paint", { finish = "red" } }, -- a colour id where a finish goes
	{ "Paint", { [1] = "red" } }, -- a number for a field
	{ "Paint", { body = 0 / 0 } }, -- NaN
	{ "Paint", { body = "red", wrap = "flames" } }, -- half good: refused whole
	{ "Paint", { body = "red", second = "red", finish = "gloss", wrap = "none", extra = "x" } }, -- five fields
}

-- Every part category fitted with something that is not stock, and every paint field set.
local FULL_ASKS = {
	{ "Engine", "engine_race" },
	{ "Suspension", "susp_drift" },
	{ "Wheels", "wheels_semislick" },
	{ "BodyKit", "kit_wide" },
	{ "Underglow", "glow_magenta" },
	{ "Interior", "int_full" },
	{ "Paint", { body = "red", second = "black", finish = "metallic", wrap = "stripes" } },
}

--------------------------------------------------------------------------------

function CustomizationTests:run()
	local checks = {}
	local passed = 0
	local function pass(ok)
		if ok then
			passed += 1
		end
	end

	-- 1. The seven categories, in menu order, each with stock and 3 to 5 parts.
	do
		local want = { "Engine", "Suspension", "Wheels", "BodyKit", "Underglow", "Interior", "Paint" }
		local ok = #Customization.CategoryOrder == #want
		local counts = {}
		for i, id in want do
			if Customization.CategoryOrder[i] ~= id then
				ok = false
			end
			if id == "Paint" then
				local nc = #Customization.paintOptions("colours")
				local nf = #Customization.paintOptions("finishes")
				local nw = #Customization.paintOptions("wraps")
				ok = ok and nc >= 4 and nf >= 4 and nw >= 4
				table.insert(counts, `Paint {nc} colours / {nf} finishes / {nw} wraps`)
			else
				local parts = Customization.partsIn(id)
				ok = ok and #parts >= 4 and #parts <= 6 and parts[1].id == Customization.stockPart(id)
				table.insert(counts, `{id} {#parts}`)
			end
		end
		pass(check(checks, "the seven categories, each with stock and 3-5 parts", ok, table.concat(counts, ", ")))
	end

	-- 2. The catalog's own check finds nothing wrong.
	do
		local problems = Customization.problems()
		pass(
			check(
				checks,
				"every part is valid (the catalog's own check)",
				#problems == 0,
				if #problems == 0 then "0 problems" else table.concat(problems, "; ")
			)
		)
	end

	-- 3. Every part has the fields the spec asks for, the unused ones included.
	do
		local n, missing = 0, {}
		for _, id in Customization.PartCategories do
			for _, part in Customization.partsIn(id) do
				n += 1
				if
					type(part.id) ~= "string"
					or type(part.name) ~= "string"
					or part.category ~= id
					or type(part.price) ~= "number"
					or type(part.unlock) ~= "string"
				then
					table.insert(missing, tostring(part.id))
				end
				if Customization.part(part.id) ~= part then
					table.insert(missing, `{part.id} (not found by id)`)
				end
			end
		end
		pass(
			check(
				checks,
				"every part has id, name, category, price and unlock",
				#missing == 0 and n > 0,
				if #missing == 0 then `{n} parts, all price 0 and unlock "free" today` else table.concat(missing, ", ")
			)
		)
	end

	-- 4. Every performance number inside the bound, on a key its category owns, and no key
	-- owned twice -- which is what keeps a whole BUILD inside the bound too.
	do
		local n, worst, outside = 0, 0, {}
		local owner = {}
		for _, id in Customization.PartCategories do
			local category = Customization.category(id)
			for _, key in category.keys do
				if owner[key] then
					table.insert(outside, `{key} owned by {owner[key]} and {id}`)
				end
				owner[key] = id
			end
		end
		local keys = 0
		for _ in owner do
			keys += 1
		end
		for _, id in Customization.PartCategories do
			for _, part in Customization.partsIn(id) do
				for key, fraction in part.perf or {} do
					n += 1
					worst = math.max(worst, math.abs(fraction))
					if math.abs(fraction) > Customization.MaxDelta + 1e-12 or owner[key] ~= id then
						table.insert(outside, `{part.id}.{key} = {fraction}`)
					end
				end
			end
		end
		pass(
			check(
				checks,
				"every performance number is inside ±15%, on a key only its category owns",
				#outside == 0 and n > 0,
				if #outside == 0
					then `{n} numbers, the largest {math.round(worst * 100)}%; {keys} keys, one owner each`
					else table.concat(outside, "; ")
			)
		)
	end

	-- 5. No build leaves the tuner's ranges on any car: every combination of the three
	-- performance categories, on all four archetypes, BEFORE any clamping.
	do
		local engines = Customization.partsIn("Engine")
		local susps = Customization.partsIn("Suspension")
		local wheels = Customization.partsIn("Wheels")
		local combos, numbers, outside = 0, 0, {}
		local tightest, tightestAt = math.huge, ""
		for _, base in Archetypes.Order do
			for _, e in engines do
				for _, s in susps do
					for _, w in wheels do
						combos += 1
						local build = Customization.stock(base)
						build.parts.Engine = e.id
						build.parts.Suspension = s.id
						build.parts.Wheels = w.id
						local deltas = Customization.deltas(build)
						local resolved = Customization.resolve(build)
						for _, slider in Garage.Sliders do
							numbers += 1
							local raw = own(base, slider.key) * (1 + (deltas[slider.key] or 0))
							local margin = math.min(raw - slider.min, slider.max - raw) / (slider.max - slider.min)
							if margin < tightest then
								tightest, tightestAt = margin, `{base} {slider.key} {raw}`
							end
							local v = resolved[slider.key]
							if raw < slider.min or raw > slider.max or v < slider.min or v > slider.max then
								table.insert(outside, `{base} {e.id}+{s.id}+{w.id}: {slider.key} {raw}`)
							end
						end
					end
				end
			end
		end
		pass(
			check(
				checks,
				"no build leaves the tuner's ranges, on any of the four cars",
				#outside == 0,
				if #outside == 0
					then `{combos} builds × 8 keys = {numbers} numbers, all inside; tightest {string.format("%.1f", tightest * 100)}% `
						.. `of the range from an edge ({tightestAt})`
					else `{#outside} outside: {table.concat(outside, "; ", 1, math.min(#outside, 5))}`
			)
		)
	end

	-- 6. The stock car IS today's car, to the bit, on all four archetypes.
	do
		local diffs, n = {}, 0
		for _, base in Archetypes.Order do
			local stock = Customization.stock(base)
			local resolved = Customization.resolve(stock)
			for _, slider in Garage.Sliders do
				n += 1
				if resolved[slider.key] ~= own(base, slider.key) then
					table.insert(diffs, `{base}.{slider.key}: {resolved[slider.key]} ~= {own(base, slider.key)}`)
				end
			end
			if next(Customization.toTune(stock)) ~= nil or next(Customization.deltas(stock)) ~= nil then
				table.insert(diffs, `{base}: stock has a tune or a delta`)
			end
			local looks = Customization.looks(stock)
			for id in looks do
				if id ~= "Paint" then
					table.insert(diffs, `{base}: stock draws {id}`)
				end
			end
		end
		pass(
			check(
				checks,
				"stock resolves to today's numbers exactly",
				#diffs == 0,
				if #diffs == 0
					then `{n} numbers on 4 cars, every one == Archetypes; no tune, no delta, no look`
					else table.concat(diffs, "; ")
			)
		)
	end

	-- 7. A part moves only its own numbers, by its own fraction.
	do
		local wrong, n = {}, 0
		local sample = ""
		for _, id in Customization.PartCategories do
			for _, part in Customization.partsIn(id) do
				if part.perf then
					local build = Customization.stock("balanced")
					build.parts[id] = part.id
					local resolved = Customization.resolve(build)
					for _, slider in Garage.Sliders do
						n += 1
						local fraction = part.perf[slider.key]
						local want = if fraction
							then Garage.clamp(slider.id, own("balanced", slider.key) * (1 + fraction))
							else own("balanced", slider.key)
						if resolved[slider.key] ~= want then
							table.insert(wrong, `{part.id}.{slider.key}: {resolved[slider.key]} ~= {want}`)
						end
					end
					if part.id == "engine_race" then
						sample = `engine_race on balanced: power {own("balanced", "MaxAcceleration")} -> {resolved.MaxAcceleration}, `
							.. `top speed {own("balanced", "TopSpeed")} -> {resolved.TopSpeed}`
					end
				end
			end
		end
		pass(
			check(
				checks,
				"a part moves only its own numbers, by its own fraction",
				#wrong == 0 and n > 0,
				if #wrong == 0 then `{n} numbers; {sample}` else table.concat(wrong, "; ")
			)
		)
	end

	-- 8. validate and sanitize: a stock and a full build are builds; junk sanitizes to stock;
	-- a half-damaged one keeps what is good.
	do
		local full = Customization.stock("gripper")
		for _, ask in FULL_ASKS do
			full = Customization.fit(full, ask[1], ask[2]) or full
		end
		local okStock = Customization.validate(Customization.stock())
		local okFull = Customization.validate(full)
		local badBuild = Customization.validate({ base = "gripper", parts = { Engine = "wheels_mesh" }, paint = {} })
		local junk = Customization.sanitize("junk")
		local mixed = Customization.sanitize({
			base = "slider",
			parts = { Engine = "engine_street", Wheels = "engine_race", Turbo = "x", Interior = 7 },
			paint = { body = "blue", second = "gold", finish = 3 },
		})
		local ok = okStock
			and okFull
			and not badBuild
			and Customization.equal(junk, Customization.stock())
			and mixed.base == "slider"
			and mixed.parts.Engine == "engine_street"
			and mixed.parts.Wheels == "wheels_stock"
			and mixed.parts.Interior == "int_stock"
			and mixed.parts.Turbo == nil
			and mixed.paint.body == "blue"
			and mixed.paint.second == "stock"
			and mixed.paint.finish == "stock"
			and Customization.validate(mixed)
		pass(
			check(
				checks,
				"validate and sanitize: builds pass, junk becomes stock, damage keeps the good",
				ok,
				`stock {okStock}, full {okFull}, wrong-category {badBuild}; damaged -> {describe(mixed)}`
			)
		)
	end

	-- 9. Every bad ask is refused by the catalog, and the build handed in is untouched.
	do
		local build = Customization.stock()
		local before = describe(build)
		local refused, taken = 0, {}
		local reasons = {}
		for i, ask in BAD_ASKS do
			local out, reason = Customization.fit(build, ask[1], ask[2])
			if out == nil and type(reason) == "string" then
				refused += 1
				reasons[reason] = (reasons[reason] or 0) + 1
			else
				table.insert(taken, `#{i}`)
			end
		end
		local list = {}
		for reason, count in reasons do
			table.insert(list, `{reason} {count}`)
		end
		table.sort(list)
		pass(
			check(
				checks,
				"every bad ask is refused by the catalog",
				refused == #BAD_ASKS and describe(build) == before,
				`{refused} of {#BAD_ASKS} refused ({table.concat(list, ", ")})`
					.. (if #taken > 0 then `; TAKEN: {table.concat(taken, ", ")}` else "")
			)
		)
	end

	-- 10. The same asks off the wire, through the real handler: each refused, the build and
	-- the store untouched.
	do
		local was = arrive(TEST_USER)
		local player = standIn(TEST_USER)
		local refusedBefore = CustomizationService.refused
		local fitsBefore = CustomizationService.fits
		local before = describe(CustomizationService:Build(TEST_USER))
		local answeredFalse = 0
		for _, ask in BAD_ASKS do
			CustomizationService.limits[TEST_USER] = nil -- each one on its own, not a flood
			local ok = CustomizationService:_onFit(player, ask[1], ask[2])
			if ok == false then
				answeredFalse += 1
			end
		end
		local refused = CustomizationService.refused - refusedBefore
		local ok = refused == #BAD_ASKS
			and answeredFalse == #BAD_ASKS
			and CustomizationService.fits == fitsBefore
			and describe(CustomizationService:Build(TEST_USER)) == before
			and GarageService.builds[TEST_USER] == nil
			and not GarageService.dirty[TEST_USER]
		pass(
			check(
				checks,
				"bad asks off the wire are refused and change nothing",
				ok,
				`{refused} of {#BAD_ASKS} refused by the service, {CustomizationService.fits - fitsBefore} fitted, `
					.. `build unchanged {describe(CustomizationService:Build(TEST_USER)) == before}, store dirty {GarageService.dirty[TEST_USER] == true}`
			)
		)
		leave(TEST_USER, was)
	end

	-- 11. A flood is dropped past the limit, and not answered.
	do
		local was = arrive(TEST_USER)
		local player = standIn(TEST_USER)
		local fitsBefore = CustomizationService.fits
		local floodedBefore = CustomizationService.flooded
		local parts = Customization.partsIn("Engine")
		for i = 1, 40 do
			CustomizationService:_onFit(player, "Engine", parts[(i % #parts) + 1].id)
		end
		local fitted = CustomizationService.fits - fitsBefore
		local flooded = CustomizationService.flooded - floodedBefore
		pass(
			check(
				checks,
				"a flood of fits is rate-limited",
				fitted == Customization.Limits.FitsPerSecond and flooded == 40 - fitted,
				`{fitted} of 40 taken, {flooded} dropped (limit {Customization.Limits.FitsPerSecond}/s)`
			)
		)
		leave(TEST_USER, was)
	end

	-- 12. A fit before the store has answered is refused, never applied over a build that
	-- has not loaded yet.
	do
		local was = arrive(TEST_USER)
		GarageService.loaded[TEST_USER] = nil
		local ok, reason = CustomizationService:_onFit(standIn(TEST_USER), "Engine", "engine_race")
		pass(
			check(
				checks,
				"a fit before the store has answered is refused, not lost",
				ok == false and reason == "loading" and GarageService.builds[TEST_USER] == nil,
				`answered {tostring(ok)} ({tostring(reason)}), build {if GarageService.builds[TEST_USER] then "set" else "untouched"}`
			)
		)
		leave(TEST_USER, was)
	end

	-- 13. Fit everything, save, forget the player, join again: the same build comes back,
	-- and the tuned cars next to it are kept.
	do
		local store = GarageService.MemoryStore("test")
		local was = arrive(TEST_USER, store)
		local player = standIn(TEST_USER)
		GarageService:_onSave(player, "Night Runner", "gripper", { grip = 41.3 })
		local accepted = 0
		for _, ask in FULL_ASKS do
			CustomizationService.limits[TEST_USER] = nil
			if CustomizationService:_onFit(player, ask[1], ask[2]) then
				accepted += 1
			end
		end
		local built = CustomizationService:Build(TEST_USER)
		local dirty = GarageService.dirty[TEST_USER] == true
		local wrote = GarageService:_write(TEST_USER, GarageService.garages[TEST_USER])

		-- Everything in memory dropped, exactly as leaving drops it...
		GarageService.garages[TEST_USER] = nil
		GarageService.builds[TEST_USER] = nil
		GarageService.loaded[TEST_USER] = nil
		local gone = CustomizationService:Build(TEST_USER)

		-- ...then read back out of the store exactly as joining reads it.
		local fired = false
		local conn = GarageService.BuildLoaded:Connect(function(userId)
			if userId == TEST_USER then
				fired = true
			end
		end)
		GarageService:_join(player)
		local waited = 0
		while not GarageService.loaded[TEST_USER] and waited < 2 do
			task.wait(0.05)
			waited += 0.05
		end
		conn:Disconnect()
		local back = CustomizationService:Build(TEST_USER)
		local car = GarageService.garages[TEST_USER] and GarageService.garages[TEST_USER]["Night Runner"]
		local _, raw = store:Get("garage_" .. TEST_USER)
		local ok = accepted == #FULL_ASKS
			and dirty
			and wrote
			and not Customization.equal(gone, built)
			and Customization.equal(back, built)
			and fired
			and car ~= nil
			and car.tune.grip == 41.3
			and type(raw) == "table"
			and type(raw.build) == "table"
		pass(
			check(
				checks,
				"fit, save, rejoin: the build comes back, and the tuned cars with it",
				ok,
				`{accepted}/{#FULL_ASKS} fitted; saved {tostring(wrote)}; forgotten -> {describe(gone)}; `
					.. `back -> {describe(back)}; BuildLoaded {fired}; "Night Runner" grip {car and car.tune.grip}`
			)
		)
		leave(TEST_USER, was)
	end

	-- 14. A garage saved before builds existed loads as the stock car, and keeps its cars.
	do
		local store = GarageService.MemoryStore("test")
		local was = arrive(TEST_USER_B, store)
		GarageService.garages[TEST_USER_B] = nil
		GarageService.loaded[TEST_USER_B] = nil
		store:Set("garage_" .. TEST_USER_B, {
			version = 1,
			at = 0,
			cars = { Old = { base = "slider", tune = { power = 30 } } },
		})
		GarageService:_join(standIn(TEST_USER_B))
		local build = CustomizationService:Build(TEST_USER_B)
		local old = GarageService.garages[TEST_USER_B] and GarageService.garages[TEST_USER_B].Old
		local ok = GarageService:BuildReady(TEST_USER_B)
			and GarageService:GetBuild(TEST_USER_B) == nil
			and Customization.equal(build, Customization.stock(build.base))
			and old ~= nil
			and old.tune.power == 30
		pass(
			check(
				checks,
				"a garage saved before builds loads as stock and keeps its cars",
				ok,
				`build {describe(build)}; "Old" power {old and old.tune.power}`
			)
		)
		leave(TEST_USER_B, was)
	end

	-- 15. A damaged build in the store keeps everything it can.
	do
		local store = GarageService.MemoryStore("test")
		local was = arrive(TEST_USER_B, store)
		GarageService.garages[TEST_USER_B] = nil
		GarageService.loaded[TEST_USER_B] = nil
		store:Set("garage_" .. TEST_USER_B, {
			version = 1,
			at = 0,
			cars = {},
			build = {
				base = "bruiser",
				parts = { Engine = "engine_warp", Wheels = "wheels_dish", Underglow = { "x" } },
				paint = { body = "purple", wrap = "logo" },
			},
		})
		GarageService:_join(standIn(TEST_USER_B))
		local build = CustomizationService:Build(TEST_USER_B)
		local ok = build.base == "bruiser"
			and build.parts.Engine == "engine_stock"
			and build.parts.Wheels == "wheels_dish"
			and build.parts.Underglow == "glow_stock"
			and build.paint.body == "purple"
			and build.paint.wrap == "none"
			and Customization.validate(build)
		pass(
			check(checks, "a damaged build in the store keeps what is good", ok, describe(build))
		)
		leave(TEST_USER_B, was)
	end

	-- 16. The car carries the build: a car appearing for the player gets every attribute,
	-- a client reading it back gets the same build, and a refit moves `Fitted` on.
	do
		local was = arrive(TEST_USER)
		local player = standIn(TEST_USER)
		for _, ask in FULL_ASKS do
			CustomizationService.limits[TEST_USER] = nil
			CustomizationService:_onFit(player, ask[1], ask[2])
		end
		local build = CustomizationService:Build(TEST_USER)

		-- A car as CarService makes one, never parented: nothing else in the game sees it.
		local car = Instance.new("Model")
		car.Name = `Car_{TEST_USER}`
		car:SetAttribute("UserId", TEST_USER)
		CustomizationService:_carAdded(car)

		local wrong = {}
		for name, value in Customization.attributes(build) do
			if car:GetAttribute(name) ~= value then
				table.insert(wrong, `{name} = {tostring(car:GetAttribute(name))}, want {value}`)
			end
		end
		local readBack = Customization.read(car)
		local first = car:GetAttribute(Customization.ATTR_COUNTER)

		CustomizationService.limits[TEST_USER] = nil
		CustomizationService:_onFit(player, "Engine", "engine_stock")
		CustomizationService:Publish(car, CustomizationService:Build(TEST_USER))
		local second = car:GetAttribute(Customization.ATTR_COUNTER)
		local engineNow = car:GetAttribute("Fit_Engine")
		local names = #Customization.attributeNames()
		car:Destroy()

		local ok = #wrong == 0
			and Customization.equal(readBack, build)
			and first == 1
			and second == 2
			and engineNow == "engine_stock"
		pass(
			check(
				checks,
				"the car carries the build, and a client reads the same build back",
				ok,
				if #wrong == 0
					then `{names} attributes + Fitted; read back equal {Customization.equal(readBack, build)}; `
						.. `Fitted {first} -> {second}, Fit_Engine -> {engineNow}`
					else table.concat(wrong, "; ")
			)
		)
		leave(TEST_USER, was)
	end

	-- 17. Read only: every real player's car in this server carries that player's build.
	do
		local folder = Workspace:FindFirstChild("Cars")
		local n, wrong = 0, {}
		for _, player in Players:GetPlayers() do
			local car = CustomizationService:_carOf(player.UserId)
			if car then
				n += 1
				local onCar = Customization.read(car)
				local believed = CustomizationService:Build(player.UserId)
				if not Customization.equal(onCar, believed) then
					table.insert(wrong, `{player.Name}: car {describe(onCar)} / server {describe(believed)}`)
				end
				if type(car:GetAttribute(Customization.ATTR_COUNTER)) ~= "number" then
					table.insert(wrong, `{player.Name}: no Fitted`)
				end
			end
		end
		pass(
			check(
				checks,
				"every real player's car carries their build",
				#wrong == 0,
				if #wrong > 0
					then table.concat(wrong, "; ")
					elseif n == 0 then `no car in this server to read (Workspace.Cars {if folder then "empty" else "missing"}): not checked`
					else `{n} car(s), each equal`
			)
		)
	end

	-- 18. Nothing left behind: no stand-in in the garage, no tuning on the car.
	do
		local left = {}
		for _, userId in { TEST_USER, TEST_USER_B } do
			if
				GarageService.garages[userId]
				or GarageService.builds[userId]
				or GarageService.loaded[userId]
				or GarageService.dirty[userId]
			then
				table.insert(left, `stand-in {userId}`)
			end
		end
		for key in Cars.tuning() do
			table.insert(left, `tuned {key}`)
		end
		pass(
			check(
				checks,
				"the tests left nothing behind",
				#left == 0,
				if #left == 0 then "no stand-in, no tuning" else table.concat(left, ", ")
			)
		)
	end

	return { passed = passed, checks = checks }
end

return CustomizationTests
