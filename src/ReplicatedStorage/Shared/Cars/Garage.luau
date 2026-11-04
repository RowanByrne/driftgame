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

-- ---------------------------------------------------------------------- the three
--
-- THREE SLIDERS, 0 TO 10, THAT REALLY DRIVE THE EIGHT. The user opened the tuner, said
-- there were too many numbers and that they did not know what each one did, and asked for
-- the three the reference game shows -- acceleration, handling, top speed.
--
-- IN THE REFERENCE THOSE THREE DRIVE NOTHING. They are a hand-written display field per
-- car; no code computes them from the physics and no code reads them back into it, which
-- is why ours are labelled "HAND-WRITTEN, display only" in the stat panel
-- (`Archetypes.Bars`, features/car-archetypes.md "Why the three bars are a lie, on
-- purpose"). THESE ARE NOT THOSE. These are a real control layer: moving one writes the
-- car fields underneath it, and the detailed sliders above visibly move with it. That is
-- the point -- the user learns what the eight do by watching them answer the three.
--
-- `Archetypes.Bars` is untouched and still a lie; nothing here reads it.
--
-- THE CURVE, AND WHY IT IS THIS ONE. Six numbers out of one slider is a choice, and a bad
-- choice makes every car feel the same. Each of the six is PIECEWISE LINEAR through three
-- anchors:
--
--   stat 0  -> the slider's own floor: the least of everything the tuner allows
--   stat 5  -> THE APPROVED CAR's value for that key (`Archetypes.Base`, 2026-11-03)
--   stat 10 -> a car-shaped ceiling: about twice the most extreme of the four archetypes,
--              capped at the reference's own design maxima where it states one
--
-- Three things follow from that, and all three are deliberate:
--
--   * **5 is the approved car, on every base.** The axis is ABSOLUTE, not relative to the
--     archetype being edited: "handling 7" is one car-feel whichever car you started from,
--     and the four archetypes land on four different numbers instead of all reading 5.
--   * **Every one of the six RISES with handling.** More handling means more grip at every
--     slip angle, a faster rate of turn and more downforce -- the car does what you ask,
--     sooner and harder. It is the obvious reading and it is the only honest one for a
--     single number: a car with a huge `SlipSqFriction` and a modest `ConstantFriction` is
--     a completely different animal from the reverse, and ONE NUMBER CANNOT SAY WHICH.
--     That spread is what the eight are for, and moving one of them by hand is what marks
--     the three custom (`statFit`).
--   * **The ceiling at 10 is a car, not the slider's end.** The design space runs far past
--     any real car (`SlipFriction` maxes at 228.6 where the grippiest archetype is 28.6),
--     so anchoring 10 there would spend the whole top half of the slider on cars nobody
--     would drive and squeeze the four archetypes into a sliver. The three cover the range
--     of real cars with headroom; the eight cover the whole space.
--
-- WHAT IT COSTS, stated plainly: handling 7 on the gripper overwrites the six numbers that
-- made the gripper the gripper. The base still gives the body, the geometry and everything
-- else; the cornering character becomes the curve's. That is what "one slider for six
-- numbers" means, and it is why the eight are still there underneath.

export type Stat = {
	id: string,
	label: string,
	feel: string,
	keys: { string }, -- slider ids, in panel order
}

-- 0..10, as the reference shows them. `step` is what a value is snapped to, `nudge` what
-- the - and + buttons move by: the step is fine enough that a car built from the three
-- reads back as the same three (checked over all 1001 values of each), and the nudge is
-- what a person actually wants from a button.
Garage.StatRange = { min = 0, max = 10, step = 0.01, nudge = 0.1 }

local STAT_MID = (Garage.StatRange.min + Garage.StatRange.max) / 2

-- The low and high anchors, per slider. The middle anchor is never written here: it is
-- always the approved car's own value for that key, so this table cannot drift away from
-- `Archetypes.Base`. `low = nil` means the slider's own floor.
Garage.StatAnchors = {
	-- handling
	eagerness = { top = 4 }, -- rad/s, the reference's own max for it
	grip = { top = 114.3 }, -- 2x the gripper's 57.2, and the reference's max
	catch = { top = 85.8 }, -- 2x the bruiser's 42.9 (the slider runs to 228.6)
	bite = { top = 114.3 }, -- 1.3x the gripper's 85.8, and the reference's max
	griplimit = { top = 215 }, -- 1.5x the gripper's 143: 6 g (the slider runs to 300)
	planted = { top = 0.7 }, -- 2x the bruiser's 0.35
	-- acceleration
	power = { top = 45 }, -- 2x the gripper's 21.5
	-- top speed
	topspeed = { top = 320 }, -- 1.5x the bruiser's 215 (the slider runs to 400)
}

Garage.Stats = {
	{
		id = "accel",
		label = "Acceleration",
		feel = "how hard it pulls away, and nothing else",
		keys = { "power" },
	},
	{
		id = "handling",
		label = "Handling",
		feel = "all six of the numbers that decide how it corners and slides, together",
		keys = { "eagerness", "grip", "catch", "bite", "griplimit", "planted" },
	},
	{
		id = "top",
		label = "Top speed",
		feel = "where it stops pulling, and nothing else",
		keys = { "topspeed" },
	},
}

-- NOT "topspeed": that is a SLIDER id, and one namespace with two meanings is a bug
-- waiting for a careless lookup.
Garage.StatOrder = {}
local statById: { [string]: Stat } = {}
for _, stat in Garage.Stats do
	table.insert(Garage.StatOrder, stat.id)
	statById[stat.id] = stat
end

function Garage.stat(id: string): Stat?
	return if type(id) == "string" then statById[id] else nil
end

function Garage.clampStat(value: any): number?
	if not finite(value) then
		return nil
	end
	local r = Garage.StatRange
	local v = math.clamp(value, r.min, r.max)
	return math.round(v / r.step) * r.step
end

-- The three anchors for one slider: its floor, the approved car's value, its ceiling.
local function anchors(sliderId: string): (number?, number?, number?)
	local slider = byId[sliderId]
	if not slider then
		return nil, nil, nil
	end
	local a = Garage.StatAnchors[sliderId]
	local low = if a and a.low then a.low else slider.min
	local top = if a and a.top then a.top else slider.max
	local mid = Archetypes.Base[slider.key]
	return low, mid, top
end

-- What one of the eight becomes at a given stat value. Clamped and snapped like any other
-- slider value, so a car built from the three is a car the store and the server already
-- understand: THE THREE SAVE NOTHING OF THEIR OWN.
function Garage.statValue(sliderId: string, stat: number): number?
	local low, mid, top = anchors(sliderId)
	if low == nil then
		return nil
	end
	local s = Garage.clampStat(stat)
	if s == nil then
		return nil
	end
	local v
	if s <= STAT_MID then
		v = low + (s / STAT_MID) * (mid - low)
	else
		v = mid + ((s - STAT_MID) / STAT_MID) * (top - mid)
	end
	return Garage.clamp(sliderId, v)
end

-- The other direction for ONE slider: where this value sits on the 0..10 axis. The honest
-- per-key answer, and what the fit below averages.
function Garage.statPosition(sliderId: string, value: number): number?
	local low, mid, top = anchors(sliderId)
	if low == nil or not finite(value) then
		return nil
	end
	local s
	if value <= mid then
		s = if mid > low then STAT_MID * (value - low) / (mid - low) else STAT_MID
	else
		s = if top > mid then STAT_MID + STAT_MID * (value - mid) / (top - mid) else STAT_MID
	end
	return math.clamp(s, Garage.StatRange.min, Garage.StatRange.max)
end

-- Every slider value one stat produces.
function Garage.statTune(statId: string, stat: number): { [string]: number }
	local out = {}
	local s = Garage.stat(statId)
	if not s then
		return out
	end
	for _, sliderId in s.keys do
		local v = Garage.statValue(sliderId, stat)
		if v ~= nil then
			out[sliderId] = v
		end
	end
	return out
end

-- THE OTHER DIRECTION, AND THE HONEST PART. A car whose six handling numbers were moved by
-- hand is NOT a point on the curve, and reading one number back out of it would be a lie
-- that looks like a fact -- the same lie the reference's bars tell.
--
-- So this returns two things: WHERE the car sits (the mean of the six per-key positions,
-- which is the least-squares answer in stat units and is where the knob is drawn) and
-- WHETHER that is the whole truth -- `exact` is true only when putting that stat value
-- back through `statValue` reproduces every one of the car's numbers to the digit. An
-- archetype, or any car with a detailed slider moved by hand, comes back `exact = false`
-- and the panel says `custom`.
--
-- The window around the mean is searched because each of the six is snapped to its own
-- step on the way out, and down at the bottom of the axis those steps are coarse in stat
-- units -- one step of `MaxSteeringSpeed` (0.05 of a 1.8 span over five stat units) is
-- 0.14 of a stat, fourteen times the stat's own resolution. The mean of six such roundings
-- can therefore sit a tenth of a stat away from the value that produced them. SEARCH_STEPS
-- covers that, which is what makes a car built from the three read back AS those three
-- (checked across all 1001 values of each, `GarageTests`).
local SEARCH_STEPS = 15
function Garage.statFit(statId: string, values: { [string]: number }): (number?, boolean)
	local stat = Garage.stat(statId)
	if not stat or type(values) ~= "table" then
		return nil, false
	end

	local function errorAt(s: number): (number, boolean)
		local err, exact = 0, true
		for _, sliderId in stat.keys do
			local actual = Garage.clamp(sliderId, values[sliderId])
			local produced = Garage.statValue(sliderId, s)
			if actual == nil or produced == nil then
				continue
			end
			if produced ~= actual then
				exact = false
			end
			local d = (Garage.statPosition(sliderId, produced) or 0) - (Garage.statPosition(sliderId, actual) or 0)
			err += d * d
		end
		return err, exact
	end

	local sum, n = 0, 0
	for _, sliderId in stat.keys do
		local p = Garage.statPosition(sliderId, Garage.clamp(sliderId, values[sliderId]) or 0)
		if p ~= nil then
			sum += p
			n += 1
		end
	end
	if n == 0 then
		return nil, false
	end

	-- The mean is the least-squares answer in stat units, and the SEARCH ORIGIN. Note the
	-- window is measured from `mean` and never from `best`: walking the window out from a
	-- moving best shifts it as it goes and can step straight over the one value that is
	-- exact, which is a bug this had and a check caught (handling 0.87 came back as 0.86,
	-- `custom`, on a car built from the three).
	local mean = Garage.clampStat(sum / n) :: number
	local best = mean
	local bestErr, bestExact = errorAt(best)
	for d = -SEARCH_STEPS, SEARCH_STEPS do
		if d ~= 0 then
			local s = Garage.clampStat(mean + d * Garage.StatRange.step)
			if s ~= nil then
				local err, exact = errorAt(s)
				if (exact and not bestExact) or (exact == bestExact and err < bestErr - 1e-12) then
					best, bestErr, bestExact = s, err, exact
				end
			end
		end
	end
	return best, bestExact
end

-- All three for a car, as the panel draws them: where each knob sits, and whether that
-- number IS the car or only the nearest point on the curve to it.
function Garage.statsFor(base: string?, tune: { [string]: number }?): { [string]: { value: number, exact: boolean } }
	local values = Garage.values(base, tune)
	local out = {}
	for _, stat in Garage.Stats do
		local value, exact = Garage.statFit(stat.id, values)
		if value ~= nil then
			out[stat.id] = { value = value, exact = exact }
		end
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
