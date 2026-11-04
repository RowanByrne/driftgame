--!nonstrict
-- Cars: which car is active, and what its numbers are
-- (docs/game/features/car-archetypes.md).
--
-- `Config.Drift` is the MODEL. This is THE CAR. Every number that is a property of one
-- car rather than of the simulation lives in `Cars/Archetypes`, and `Config.Drift`
-- resolves those keys through here -- so `local C = Config.Drift; C.MaxSteeringSpeed` in
-- `Drift/Model` reads the ACTIVE car's rate of turn, and not one line of the model had to
-- change to make that true.
--
-- There are three layers, nearest first:
--
--   tuned       a runtime override, for a test or a tuning session (`tune`/`untune`)
--   the car     the active archetype's sparse overrides
--   Base        the approved car, every field (`Archetypes.Base`)
--
-- `Config.Drift` holds NO car key raw, which is what makes this work and what keeps it
-- honest: a car number cannot be written into the model's table by accident, because the
-- model's table refuses it (`Config/Drift`, `__newindex`).
--
-- The body modules next to this one (`AE86`) are a DIFFERENT AXIS and nothing here reads
-- them: a car is how it drives, a body is what is drawn, and `Config.Drift.CarBody` picks
-- the body. Any body may wear any car's numbers, which is how an archetype is driven
-- before its art exists.
--
-- THE ACTIVE CAR IS GLOBAL TO ONE LUA VM, like `CarBody` already is, and on the CLIENT
-- that is exactly right: a client simulates one car, its own, so "the active car" and
-- "the car this player is in" are the same thing.
--
-- THE SERVER IS NOT LIKE THAT. It holds every player's car at once, so it cannot have one
-- active car and be telling the truth about any of them. It keeps a key per player
-- (`CarService`, T-033) and asks this module for that car's numbers through `resolve`,
-- which answers for ANY car without switching the active one; `withActive` is for the one
-- thing that genuinely reads the global -- building or dressing a car's SHAPE, which goes
-- through `CarModel` and `Config.Drift.CarBody`.

local Archetypes = require(script.Archetypes)

local Cars = {}

Cars.Archetypes = Archetypes
Cars.Order = Archetypes.Order
Cars.StatMax = Archetypes.StatMax
Cars.Default = Archetypes.Default

-- The three fields that are about SELLING a car rather than driving one. They never
-- resolve through `Config.Drift`: nothing in the simulation may read them, and the whole
-- point of the display bars is that nothing computes or consumes them.
local DISPLAY = { Name = true, Character = true, Bars = true }

-- Every key a car owns, built from `Base` so the two can never drift apart. `Config.Drift`
-- asks this what belongs to a car.
local FIELDS: { [string]: boolean } = {}
for key in Archetypes.Base do
	if not DISPLAY[key] then
		FIELDS[key] = true
	end
end

local activeKey: string = Archetypes.Default
local tuned: { [string]: any } = {}
local resolved: { [string]: any } = {}

-- One car's numbers, every field, the three layers applied in order. The ACTIVE car's
-- copy is cached (`resolved`) because the model reads it twenty times a step; any other
-- car's is built on the spot, which is what the server does per player and what the stat
-- panel does for a car nobody is driving.
local function layers(key: string): { [string]: any }
	local out = {}
	for field, value in Archetypes.Base do
		out[field] = value
	end
	for field, value in Archetypes.Cars[key] or {} do
		out[field] = value
	end
	for field, value in tuned do
		out[field] = value
	end
	return out
end

local function rebuild()
	resolved = layers(activeKey)
end

rebuild()

-- ---------------------------------------------------------------------- the active car

function Cars.activeKey(): string
	return activeKey
end

-- The active car, every field resolved: the display fields too, which is what the stat
-- panel reads. Do not keep the table -- a switch builds a new one.
function Cars.active(): { [string]: any }
	return resolved
end

function Cars.exists(key: string): boolean
	return type(key) == "string" and Archetypes.Cars[key] ~= nil
end

-- ANY car's numbers, without touching which one is active, and nil for a car that does
-- not exist. This is how the SERVER reads a player's car: it holds every player at once,
-- so it can never use the active one (`CarService`, T-033).
--
-- A fresh table every call, on purpose: the caller is free to keep it, and a car switch
-- cannot reach back into a copy somebody is holding. Tuning DOES apply -- `tune` is a
-- layer over whichever car is being asked about, not over one of them -- so a tuning
-- session moves the server's bounds with the client's feel.
function Cars.resolve(key: string): { [string]: any }?
	if not Cars.exists(key) then
		return nil
	end
	return layers(key) -- a copy, never the cached table the model reads
end

-- Switch car. Takes effect on the very next simulation step: the model reads
-- `Config.Drift` every step and holds nothing from the last one.
--
-- GEOMETRY IS THE ONE EXCEPTION. `Wheelbase`, `WheelDiameter` and the rest are read when
-- a car MODEL is built, so a switch between cars with different geometry leaves the shell
-- as it was until the next respawn. Every archetype shares the approved car's geometry
-- today, so today there is nothing to notice.
function Cars.setActive(key: string)
	if not Archetypes.Cars[key] then
		local names = {}
		for _, k in Archetypes.Order do
			table.insert(names, k)
		end
		error(`Cars: no '{key}'. There is: {table.concat(names, ", ")}`, 2)
	end
	activeKey = key
	rebuild()
end

-- The next car round the list after `key` (the active one by default), switching nothing.
-- The client's F4 needs this rather than `cycle`: it has to name the car it is ASKING the
-- server for, and the server is the one that decides (`CarService`, T-033).
function Cars.nextKey(key: string?): string
	local order = Archetypes.Order
	local from = key or activeKey
	local at = 1
	for i, k in order do
		if k == from then
			at = i
			break
		end
	end
	return order[(at % #order) + 1]
end

-- The next car round the list, for a test that wants to walk all of them. Returns the key
-- it switched to.
--
-- NOT what the F4 key does any more: a player's car is the SERVER's to decide, so the
-- panel asks over `CarSwitch` and this would be the client deciding for itself.
function Cars.cycle(): string
	local nextKey = Cars.nextKey()
	Cars.setActive(nextKey)
	return nextKey
end

-- Run `fn` with another car active, and put the active one back however it ends.
--
-- For the one thing that really does read the global active car: the SHAPE. `CarModel`
-- builds and dresses a car around `Cars.activeKey()` (`CarBody = "auto"`) and around the
-- active car's geometry, so dressing one player's car in their own archetype means making
-- it active for the length of that call. Nothing in the simulation runs on the server, so
-- nothing there can see the flip -- but it is not re-entrant across a yield, and the
-- server serialises its dressing for that reason (`CarService:_withCar`).
function Cars.withActive(key: string, fn: () -> ...any): ...any
	local was = activeKey
	Cars.setActive(key)
	local results = table.pack(pcall(fn))
	Cars.setActive(was)
	if not results[1] then
		error(results[2], 2)
	end
	return table.unpack(results, 2, results.n)
end

-- ---------------------------------------------------------------------- what Config asks

function Cars.isField(key: string): boolean
	return FIELDS[key] == true
end

-- The active car's value for a model-facing key, or nil if it is not a car key at all.
-- This is the hot path: `Config.Drift.<car key>` is one call and one table index, and the
-- model makes about twenty of them a step.
function Cars.value(key: string): any
	if FIELDS[key] then
		return resolved[key]
	end
	return nil
end

-- ---------------------------------------------------------------------- tuning

-- A runtime override on top of whatever car is active, for a test or a tuning session.
-- `Config.Drift.MaxSteeringSpeed = x` deliberately ERRORS instead of doing this quietly:
-- a car number written into the model's table would survive a car switch and silently
-- make every car the same, which is the one failure this whole split exists to prevent.
function Cars.tune(key: string, value: any)
	if not FIELDS[key] then
		error(`Cars.tune: '{key}' is not a car number. Model numbers live in Config.Drift`, 2)
	end
	tuned[key] = value
	rebuild()
end

function Cars.untune(key: string)
	tuned[key] = nil
	rebuild()
end

function Cars.untuneAll()
	tuned = {}
	rebuild()
end

-- Run `fn` with some numbers moved, and put them back however it ends. The shape a test
-- should use: a restore that an error can skip is a test suite that poisons the ones
-- after it.
function Cars.withTuning(overrides: { [string]: any }, fn: () -> ...any): ...any
	for key, value in overrides do
		Cars.tune(key, value)
	end
	local results = table.pack(pcall(fn))
	for key in overrides do
		Cars.untune(key)
	end
	if not results[1] then
		error(results[2], 2)
	end
	return table.unpack(results, 2, results.n)
end

-- ---------------------------------------------------------------------- the grip curve

-- What a car's tyres can pull at a given slip angle, in studs/s^2, before the surface and
-- `FrictionMultiplier`: the honest picture of how a car drifts, and the same four numbers
-- `Drift/Model` uses. `car` is a resolved car table; nil means the active one.
--
--   f(b) = min(ConstantFriction + SlipFriction*b + SlipSqFriction*b^2, MaxFriction)
--
-- with `b` capped at 90 degrees, exactly as the model caps it.
function Cars.gripAt(slipDeg: number, car: { [string]: any }?): number
	local c = car or resolved
	local b = math.min(math.abs(math.rad(slipDeg)), math.pi * 0.5)
	return math.min(c.ConstantFriction + c.SlipFriction * b + c.SlipSqFriction * b * b, c.MaxFriction)
end

-- The curve as `count` points from 0 to 90 degrees, for drawing.
function Cars.gripCurve(count: number, car: { [string]: any }?): { { deg: number, f: number } }
	local out = {}
	local n = math.max(count, 2)
	for i = 1, n do
		local deg = 90 * (i - 1) / (n - 1)
		table.insert(out, { deg = deg, f = Cars.gripAt(deg, car) })
	end
	return out
end

-- ---------------------------------------------------------------------- the stat panel

-- Everything the stat panel draws, for one car. Three hand-written bars that NOTHING
-- computes, then the four real numbers as fractions of the design space's maxima, then
-- the curve those four make.
function Cars.stats(key: string?): { [string]: any }
	local carKey = key or activeKey
	local car = if carKey == activeKey then resolved else (Cars.resolve(carKey) or resolved)

	local reals = {}
	for _, field in { "MaxSteeringSpeed", "ConstantFriction", "SlipFriction", "SlipSqFriction" } do
		local max = Archetypes.StatMax[field]
		table.insert(reals, {
			field = field,
			value = car[field],
			max = max,
			fraction = car[field] / max,
		})
	end

	return {
		key = carKey,
		name = car.Name,
		character = car.Character,
		bars = car.Bars, -- DISPLAY ONLY: hand-written, derived from nothing
		reals = reals,
		maxFriction = car.MaxFriction,
		topSpeed = car.TopSpeed,
		curve = Cars.gripCurve(31, car),
		samples = {
			[0] = Cars.gripAt(0, car),
			[15] = Cars.gripAt(15, car),
			[30] = Cars.gripAt(30, car),
			[45] = Cars.gripAt(45, car),
			[60] = Cars.gripAt(60, car),
			[90] = Cars.gripAt(90, car),
		},
	}
end

-- The whole state of the car system in one call, for Studio and for the tests, which
-- `require` this module directly (it is a Shared module, not a loaded service, so it is
-- not on the debug bridge).
function Cars.DebugState(): { [string]: any }
	return Cars.stats()
end

return Cars
