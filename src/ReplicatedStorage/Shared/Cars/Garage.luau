--!nonstrict
-- Garage: the sliders a car is tuned with, and every rule about what a tuned car may be
-- (docs/game/features/car-tuner.md).
--
-- SHARED ON PURPOSE, and this is the point of the module: the client draws the sliders
-- from this table and the server validates against the same table, so there is one place
-- that says what a tuned car may be and no chance of the two ends disagreeing. A client
-- may ask for any numbers it likes; `sanitizeTune` is what the SERVER believes, and the
-- server never takes a number that did not come out of it.
--
-- A TUNED CAR IS NOT A NEW ARCHETYPE. It is `{ base = <archetype key>, tune = {...} }`:
-- one of the four cars, with some of its numbers moved. That shape is deliberate --
--   * the tune lands through `Cars.tune`, which `Config.Drift` resolves on every read, so
--     a slider moves the car on the NEXT SIMULATION STEP with nothing to refresh;
--   * the base is a real archetype, so the car keeps its own body, its geometry and
--     everything the tuner does not expose;
--   * the server already owns which archetype a player is in (`CarService`, T-033) and
--     nothing here has to argue with that.
--
-- THE NAMES ARE FOR THE DRIVER, NOT FOR THE PHYSICS. The user asked for "stuff that isn't
-- super technical", so every slider is named for what the car does and carries the real
-- key with it -- the UI prints that key under each row, so the tool stays honest about
-- what it is moving.
--
-- THE RANGES ARE A DESIGN SPACE, NOT A SAFETY RAIL, with one exception. A slider may make
-- a car undrivable, because "undrivable" is a thing a person tuning a car is allowed to
-- find; it may not make one that cannot be recovered or that breaks the simulation. Every
-- range below is recoverable by moving the slider back. The exception is `TopSpeed`,
-- whose MINIMUM IS NOT ZERO: the drivetrain divides by it (`u / TopSpeed`), so zero is a
-- NaN velocity and a car that is nowhere.

local Archetypes = require(script.Parent.Archetypes)
-- `Config` itself holds nothing and loads each feature's module on first use, so this is
-- not the cycle it looks like: `Config.Drift` requires `Shared/Cars`, and `Shared/Cars`
-- does not require this module.
local Config = require(script.Parent.Parent.Config)

local Garage = {}

-- The record a saved car is stored as. `savedAt` is `os.time()` on the server.
export type Car = {
	base: string,
	tune: { [string]: number },
	savedAt: number?,
}

export type Slider = {
	id: string, -- the stable id the wire and the store use
	label: string, -- what the driver reads
	key: string, -- the car field it really moves (`Cars/Archetypes`)
	feel: string, -- one line: what the driver feels
	min: number,
	max: number,
	step: number, -- the slider's resolution; every value is snapped to it
	unit: string?,
	decimals: number,
}

Garage.Version = 1

-- ---------------------------------------------------------------------- the sliders
--
-- Eight, and the four archetypes' own values are inside every one of them -- so any of
-- the four can be dialled up from any other, and a saved car can be any of them.
--
-- WHERE THE RANGES COME FROM. The four with an entry in `Archetypes.StatMax` use the
-- reference's own design space, which is what the stat panel already draws them as a
-- fraction of. The other four have no stated maximum, so they are drawn from the spread
-- the four cars use, opened up far enough either side to be worth a slider.
--
-- WHY EIGHT AND NOT THE SEVEN THAT WERE ASKED FOR: `SlipFriction` is the LINEAR grip
-- term and the one that decides how a car behaves between "straight" and "properly
-- sideways". Without it the bruiser cannot be built in this tool at all -- its 42.9 is
-- three times everything else's and is most of its character -- so it is here as
-- "Catch". What is deliberately NOT here: the four multipliers (`AccelMultiplier` and
-- friends, all 1 on every car, and redundant with the absolute numbers next to them),
-- `SteeringSensitivity` (the same dial as Eagerness), the throttle ramp and the
-- handbrake (not felt in a corner), and all of the geometry -- which is read when a car
-- MODEL is built, so moving it live would change nothing until a rejoin and would be a
-- slider that lies.
Garage.Sliders = {
	{
		id = "eagerness",
		label = "Eagerness",
		key = "MaxSteeringSpeed",
		feel = "how fast the car rotates when you move your finger",
		min = 0.2,
		max = 4, -- StatMax
		step = 0.05,
		unit = "rad/s",
		decimals = 2,
	},
	{
		id = "grip",
		label = "Grip",
		key = "ConstantFriction",
		feel = "how hard it resists sliding at all",
		min = 0,
		max = 114.3, -- StatMax
		step = 0.1,
		unit = "studs/s²",
		decimals = 1,
	},
	{
		id = "catch",
		label = "Catch",
		key = "SlipFriction",
		feel = "how quickly it starts fighting back as the tail steps out",
		min = 0,
		max = 228.6, -- StatMax
		step = 0.1,
		unit = "studs/s² per rad",
		decimals = 1,
	},
	{
		id = "bite",
		label = "Bite",
		key = "SlipSqFriction",
		feel = "how hard it hauls itself straight once it IS sliding",
		min = 0,
		max = 114.3, -- StatMax
		step = 0.1,
		unit = "studs/s² per rad²",
		decimals = 1,
	},
	{
		id = "griplimit",
		label = "Grip limit",
		key = "MaxFriction",
		feel = "the tightest circle it can hold before it just slides",
		min = 0,
		max = 300, -- twice the grippiest car's 143, and well past where the curve binds
		step = 1,
		unit = "studs/s²",
		decimals = 0,
	},
	{
		id = "power",
		label = "Power",
		key = "MaxAcceleration",
		feel = "how hard it pulls away",
		min = 0, -- a car that cannot move. Recoverable: move the slider back
		max = 60, -- nearly three times the quickest car's 21.5
		step = 0.1,
		unit = "studs/s²",
		decimals = 1,
	},
	{
		id = "topspeed",
		label = "Top speed",
		key = "TopSpeed",
		feel = "where it stops pulling",
		min = 20, -- NOT ZERO, and this is the one hard floor in the table: the drivetrain
		-- divides by this number, so zero is a NaN velocity and a car that is
		-- nowhere -- the one setting here that could wedge the game
		max = 400, -- nearly twice the fastest car's 215
		step = 1,
		unit = "studs/s",
		decimals = 0,
	},
	{
		id = "planted",
		label = "Planted",
		key = "DownforcePerSpeed",
		feel = "how much it is pressed into the road with speed",
		min = 0, -- never negative: downforce that lifts is a car that flies
		max = 1,
		step = 0.01,
		unit = "per second",
		decimals = 2,
	},
}

Garage.Order = {}
local byId: { [string]: Slider } = {}
local byKey: { [string]: Slider } = {}
for _, slider in Garage.Sliders do
	table.insert(Garage.Order, slider.id)
	byId[slider.id] = slider
	byKey[slider.key] = slider
end

function Garage.slider(id: string): Slider?
	return if type(id) == "string" then byId[id] else nil
end

function Garage.sliderForKey(key: string): Slider?
	return if type(key) == "string" then byKey[key] else nil
end

-- ---------------------------------------------------------------------- numbers

-- Is this a number the simulation could survive? NaN and the infinities are not: the
-- client is the one that sends these, and `0/0` off the wire would poison the car's
-- velocity for the rest of the session with nothing to blame.
local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

Garage.finite = finite

-- One slider's value, clamped into its range and snapped to its step. The snap is what
-- makes a saved car reproduce EXACTLY: the client draws a knob from a pixel position, and
-- a value that has been through here is the same number on both ends and after a save.
function Garage.clamp(id: string, value: any): number?
	local slider = Garage.slider(id)
	if not slider or not finite(value) then
		return nil
	end
	local v = math.clamp(value, slider.min, slider.max)
	local snapped = slider.min + math.round((v - slider.min) / slider.step) * slider.step
	-- The snap can land a hair outside after the floating-point round trip.
	snapped = math.clamp(snapped, slider.min, slider.max)
	-- And it can leave 14.299999999999999 where 14.3 was meant, which would make a saved
	-- car differ from the car that was saved in the ninth decimal. Rounded to the step's
	-- own resolution, which is the finest thing a slider can express.
	local places = math.max(0, math.ceil(-math.log(slider.step, 10) + 1e-9))
	local scale = 10 ^ places
	return math.round(snapped * scale) / scale
end

-- A tune table off the wire, or out of the store, made safe: only known sliders, only
-- finite numbers, every one clamped and snapped. Anything else is dropped silently --
-- there is nothing useful to say to a client that sent a table of strings.
--
-- Keyed by SLIDER ID, not by car field: the ids are this tool's own and a stored car
-- keeps working if a slider is ever renamed or pointed at a different number.
function Garage.sanitizeTune(tune: any): { [string]: number }
	local out = {}
	if type(tune) ~= "table" then
		return out
	end
	for id, value in tune do
		local clamped = Garage.clamp(id, value)
		if clamped ~= nil then
			out[id] = clamped
		end
	end
	return out
end

-- The same table as the car fields `Cars.tune` wants. This is the only place the two
-- vocabularies meet.
function Garage.toCarFields(tune: { [string]: number }): { [string]: number }
	local out = {}
	for id, value in tune do
		local slider = Garage.slider(id)
		if slider then
			out[slider.key] = value
		end
	end
	return out
end

-- A car's own value for every slider: where the knobs sit for an untuned car, and what
-- "reset" puts back. `base` nil is the default car.
function Garage.baseValues(base: string?): { [string]: number }
	local car = if type(base) == "string" and Archetypes.Cars[base] then base else Archetypes.Default
	local out = {}
	for _, slider in Garage.Sliders do
		local value = Archetypes.Cars[car][slider.key]
		if value == nil then
			value = Archetypes.Base[slider.key]
		end
		out[slider.id] = Garage.clamp(slider.id, value) or slider.min
	end
	return out
end

-- Every slider's value for a tuned car: the base car's, with the tune over it. What the
-- UI draws and what the whole car really is.
function Garage.values(base: string?, tune: { [string]: number }?): { [string]: number }
	local out = Garage.baseValues(base)
	for id, value in Garage.sanitizeTune(tune) do
		out[id] = value
	end
	return out
end

-- ---------------------------------------------------------------------- a saved car

-- A name, trimmed and bounded. Returns nil for anything that is not a name: the client
-- cannot be trusted to have checked, and an empty or whitespace name would be a car
-- nobody can pick out of a list.
--
-- Control characters are stripped rather than refused, so a paste with a newline in it
-- still saves. NOTHING HERE IS MODERATION: a name a player could see would have to go
-- through `TextService:FilterStringAsync` (PLATFORM-RISKS.md), and this tool is a dev
-- tool whose names only ever reach the person who typed them.
function Garage.cleanName(name: any): string?
	if type(name) ~= "string" then
		return nil
	end
	local clean = string.gsub(name, "%c", " ")
	clean = string.match(clean, "^%s*(.-)%s*$") or ""
	if clean == "" then
		return nil
	end
	if utf8.len(clean) == nil then
		return nil -- not valid UTF-8: a string the client made up
	end
	local max = Config.Drift.GarageNameMax
	if utf8.len(clean) > max then
		local cut = utf8.offset(clean, max + 1)
		clean = string.sub(clean, 1, (cut or (max + 1)) - 1)
		clean = string.match(clean, "^%s*(.-)%s*$") or ""
	end
	return if clean ~= "" then clean else nil
end

-- A saved car off the wire or out of the store. An unknown base falls back to the default
-- car rather than being refused: a store written before an archetype was renamed should
-- still give back the numbers somebody tuned.
function Garage.sanitizeCar(car: any): Car?
	if type(car) ~= "table" then
		return nil
	end
	local base = car.base
	if type(base) ~= "string" or not Archetypes.Cars[base] then
		base = Archetypes.Default
	end
	return {
		base = base,
		tune = Garage.sanitizeTune(car.tune),
		savedAt = if finite(car.savedAt) then car.savedAt else nil,
	}
end

-- A whole garage out of the store: `{ [name] = Car }`, everything checked, and never more
-- than the cap even if the store somehow holds more.
function Garage.count(garage: { [string]: Car }): number
	local n = 0
	for _ in garage do
		n += 1
	end
	return n
end

function Garage.sanitizeGarage(raw: any): { [string]: Car }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	local max = Config.Drift.GarageMaxCars
	local names = {}
	for name in raw do
		if type(name) == "string" then
			table.insert(names, name)
		end
	end
	table.sort(names) -- deterministic, so a store over the cap loses the same cars twice
	local kept = 0
	for _, name in names do
		if kept >= max then
			break
		end
		local clean = Garage.cleanName(name)
		local car = Garage.sanitizeCar(raw[name])
		if clean and car and out[clean] == nil then
			out[clean] = car
			kept += 1
		end
	end
	return out
end

-- The names in a garage, sorted, so both ends draw the same list in the same order.
function Garage.names(garage: { [string]: Car }): { string }
	local out = {}
	for name in garage do
		table.insert(out, name)
	end
	table.sort(out, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	return out
end

-- ---------------------------------------------------------------------- the speed bound

-- What a tuned car's top speed really is: the tune's, or the base car's if it is not
-- tuned. THE ONE NUMBER THE SERVER HAS TO KNOW about a tuned car, because every bound it
-- puts on a `CarState` is a share of it (`CarService`, `GarageService`).
function Garage.topSpeed(base: string?, tune: { [string]: number }?): number
	local values = Garage.values(base, tune)
	return values.topspeed
end

-- The fastest any UNTUNED car can be. The floor under the server's ceiling: whatever a
-- tuning session does, no player in a plain archetype may ever be bounded below their own
-- car's top speed (`GarageService`, "the ceiling").
function Garage.fastestArchetype(): number
	local fastest = Archetypes.Base.TopSpeed
	for _, car in Archetypes.Cars do
		fastest = math.max(fastest, car.TopSpeed or Archetypes.Base.TopSpeed)
	end
	return fastest
end

return Garage
