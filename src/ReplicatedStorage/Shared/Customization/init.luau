--!nonstrict
-- Customization: the parts catalog and every rule about what a built car may be
-- (docs/game/features/car-customization.md, CONTRACTS.md "Customization").
--
-- SHARED ON PURPOSE, like `Shared/Cars/Garage`: the client draws its menus and previews
-- from this module and the server checks every fit against the same one, so the two ends
-- cannot disagree about what a part is or what it does.
--
-- PURE. Nothing here touches the car, the store or the wire, and nothing here APPLIES a
-- part's numbers to the car: `resolve` and `toTune` say what a build implies, and the step
-- that makes the car drive like it (T-106) is somebody else's.
--
-- A BUILD:
--   { base = <archetype key>, parts = { [categoryId] = partId }, paint = { body, second,
--     finish, wrap } }
-- with every one of the six part categories present (stock when nothing is fitted) and
-- every paint field present. `sanitize` makes one out of anything; `validate` says whether
-- a table already is one.

local Archetypes = require(script.Parent.Cars.Archetypes)
local Garage = require(script.Parent.Cars.Garage)
local Catalog = require(script.Catalog)

local Customization = {}

export type Build = {
	base: string,
	parts: { [string]: string },
	paint: { body: string, second: string, finish: string, wrap: string },
}

Customization.Catalog = Catalog
Customization.Version = Catalog.Version
Customization.MaxDelta = Catalog.MaxDelta
Customization.Limits = Catalog.Limits
Customization.Paint = Catalog.Paint
Customization.PAINT = Catalog.Paint.id -- "Paint": the seventh category, not a part slot

-- The car attributes a build is published as (CONTRACTS.md "Customization").
Customization.ATTR_PREFIX = "Fit_"
Customization.ATTR_COUNTER = "Fitted"

-- ---------------------------------------------------------------------- indexes

local categories = {} -- the six part categories, in menu order
local categoryById = {}
local partById = {}
local stockOf = {} -- categoryId -> the stock part's id
local keyOwner = {} -- car key -> the category that owns it
local catalogProblems = {} -- anything wrong with the data itself, found while indexing

local function problem(text: string)
	table.insert(catalogProblems, text)
end

for _, category in Catalog.Categories do
	table.insert(categories, category)
	if categoryById[category.id] then
		problem(`category {category.id} is listed twice`)
	end
	categoryById[category.id] = category
	for _, key in category.keys do
		if keyOwner[key] then
			problem(`car key {key} is owned by both {keyOwner[key]} and {category.id}`)
		end
		keyOwner[key] = category.id
	end
	for _, part in category.parts do
		-- Filled in here so a line of data never has to repeat them.
		part.category = category.id
		if part.price == nil then
			part.price = 0
		end
		if part.unlock == nil then
			part.unlock = "free"
		end
		if partById[part.id] then
			problem(`part id {part.id} is used twice`)
		end
		partById[part.id] = part
		if string.match(part.id, "_stock$") then
			if stockOf[category.id] then
				problem(`{category.id} has two stock parts`)
			end
			stockOf[category.id] = part.id
		end
	end
	if not stockOf[category.id] then
		problem(`{category.id} has no stock part (an id ending "_stock")`)
	end
end

-- Paint options, indexed by list ("colours", "finishes", "wraps") then id.
local paintById = {}
for _, list in { "colours", "finishes", "wraps" } do
	paintById[list] = {}
	for _, option in Catalog.Paint[list] do
		if paintById[list][option.id] then
			problem(`paint {list} id {option.id} is used twice`)
		end
		paintById[list][option.id] = option
	end
end

-- The catalog is frozen once indexed: a menu handed a part cannot change what the server
-- believes that part does, on its own machine or anywhere else.
local function deepFreeze(t)
	if type(t) ~= "table" or table.isfrozen(t) then
		return
	end
	for _, v in t do
		deepFreeze(v)
	end
	table.freeze(t)
end
deepFreeze(Catalog)

-- Every category id, the six part categories then Paint: the menu's tabs.
Customization.CategoryOrder = {}
for _, category in categories do
	table.insert(Customization.CategoryOrder, category.id)
end
table.insert(Customization.CategoryOrder, Catalog.Paint.id)

-- Only the six that hold a part.
Customization.PartCategories = {}
for _, category in categories do
	table.insert(Customization.PartCategories, category.id)
end

-- ---------------------------------------------------------------------- lookups

local function isId(v: any): boolean
	return type(v) == "string" and #v > 0 and #v <= Catalog.Limits.MaxIdLength
end

-- A category by id: one of the six part categories, or the Paint table. Nil otherwise.
function Customization.category(id: any)
	if not isId(id) then
		return nil
	end
	if id == Catalog.Paint.id then
		return Catalog.Paint
	end
	return categoryById[id]
end

function Customization.part(id: any)
	return if isId(id) then partById[id] else nil
end

function Customization.stockPart(categoryId: string): string?
	return stockOf[categoryId]
end

-- The parts in one category, in menu order, stock first. For Paint, every option of every
-- paint list, each tagged with the `field`s it can be chosen for.
function Customization.partsIn(categoryId: string): { any }
	if categoryId == Catalog.Paint.id then
		local out = {}
		for _, list in { "colours", "finishes", "wraps" } do
			for _, option in Catalog.Paint[list] do
				table.insert(out, table.freeze({
					id = option.id,
					name = option.name,
					list = list,
					colour = option.colour,
					material = option.material,
					reflectance = option.reflectance,
				}))
			end
		end
		return out
	end
	local category = categoryById[categoryId]
	if not category then
		return {}
	end
	return table.clone(category.parts)
end

-- One paint list ("colours", "finishes", "wraps"), or the list a paint field chooses from
-- ("body", "second", "finish", "wrap").
function Customization.paintOptions(listOrField: string): { any }
	local list = Catalog.Paint.fields[listOrField] or listOrField
	local options = Catalog.Paint[list]
	return if type(options) == "table" and paintById[list] then table.clone(options) else {}
end

function Customization.paintOption(field: string, id: any)
	local list = Catalog.Paint.fields[field]
	if not list or not isId(id) then
		return nil
	end
	return paintById[list][id]
end

-- A colour id's Color3, or nil for "stock" (the body's own colour) and unknown ids.
function Customization.paintColour(id: any): Color3?
	local option = isId(id) and paintById.colours[id] or nil
	return option and option.colour or nil
end

-- ---------------------------------------------------------------------- builds

local function knownBase(base: any): boolean
	return type(base) == "string" and Archetypes.Cars[base] ~= nil
end

-- The stock car: every category stock, the body's own paint. `base` nil or unknown is the
-- default archetype.
function Customization.stock(base: string?): Build
	local parts = {}
	for _, category in categories do
		parts[category.id] = stockOf[category.id]
	end
	return {
		base = if knownBase(base) then base :: string else Archetypes.Default,
		parts = parts,
		paint = table.clone(Catalog.Paint.stock),
	}
end

function Customization.copy(build: Build): Build
	return { base = build.base, parts = table.clone(build.parts), paint = table.clone(build.paint) }
end

function Customization.equal(a: Build?, b: Build?): boolean
	if a == nil or b == nil then
		return a == b
	end
	if a.base ~= b.base then
		return false
	end
	for _, category in categories do
		if a.parts[category.id] ~= b.parts[category.id] then
			return false
		end
	end
	for _, field in Catalog.Paint.fieldOrder do
		if a.paint[field] ~= b.paint[field] then
			return false
		end
	end
	return true
end

-- Is this table exactly a build: a known base, every part category present with a part of
-- THAT category, nothing extra, every paint field present with a known option. Returns
-- `false, reason` on the first thing wrong.
function Customization.validate(build: any): (boolean, string?)
	if type(build) ~= "table" then
		return false, "not a table"
	end
	if not knownBase(build.base) then
		return false, "unknown base"
	end
	if type(build.parts) ~= "table" or type(build.paint) ~= "table" then
		return false, "no parts or paint"
	end
	for categoryId, partId in build.parts do
		local category = if type(categoryId) == "string" then categoryById[categoryId] else nil
		if not category then
			return false, "unknown category"
		end
		local part = Customization.part(partId)
		if not part or part.category ~= categoryId then
			return false, `unknown part for {categoryId}`
		end
	end
	for _, category in categories do
		if build.parts[category.id] == nil then
			return false, `no part for {category.id}`
		end
	end
	for field, id in build.paint do
		if type(field) ~= "string" or not Catalog.Paint.fields[field] then
			return false, "unknown paint field"
		end
		if not Customization.paintOption(field, id) then
			return false, `unknown {field} paint`
		end
	end
	for _, field in Catalog.Paint.fieldOrder do
		if build.paint[field] == nil then
			return false, `no {field} paint`
		end
	end
	return true, nil
end

-- Anything (out of the store, off an instance) made into a build. Never refuses: whatever
-- is unknown or missing becomes stock, so a store written before a part was renamed still
-- gives back everything else the player built.
function Customization.sanitize(raw: any, base: string?): Build
	local build = Customization.stock(if type(raw) == "table" and knownBase(raw.base) then raw.base else base)
	if type(raw) ~= "table" then
		return build
	end
	if type(raw.parts) == "table" then
		for _, category in categories do
			local part = Customization.part(raw.parts[category.id])
			if part and part.category == category.id then
				build.parts[category.id] = part.id
			end
		end
	end
	if type(raw.paint) == "table" then
		for _, field in Catalog.Paint.fieldOrder do
			if Customization.paintOption(field, raw.paint[field]) then
				build.paint[field] = raw.paint[field]
			end
		end
	end
	return build
end

-- ONE CHANGE, AS ASKED OFF THE WIRE, applied to a copy of a build. The server's only way to
-- change a build, so every rule about what may be asked for is here:
--   * `categoryId` a string naming one of the seven categories;
--   * a part category takes `choice` = a part id string, OF THAT CATEGORY;
--   * Paint takes `choice` = a table of 1-4 paint fields to set, each a known option for
--     that field, and nothing else in it.
-- Returns the new build, or `nil, reason`. The build passed in is never touched.
function Customization.fit(build: Build, categoryId: any, choice: any): (Build?, string?)
	if not isId(categoryId) then
		return nil, "bad category"
	end
	if categoryId == Catalog.Paint.id then
		if type(choice) ~= "table" then
			return nil, "bad paint"
		end
		local out = Customization.copy(build)
		local n = 0
		for field, id in choice do
			n += 1
			if n > #Catalog.Paint.fieldOrder then
				return nil, "bad paint" -- more fields than paint has: refused before more work
			end
			if type(field) ~= "string" or not Catalog.Paint.fields[field] then
				return nil, "unknown paint field"
			end
			if not Customization.paintOption(field, id) then
				return nil, "unknown paint"
			end
			out.paint[field] = id
		end
		if n == 0 then
			return nil, "bad paint"
		end
		return out, nil
	end
	local category = categoryById[categoryId]
	if not category then
		return nil, "unknown category"
	end
	if not isId(choice) then
		return nil, "bad part"
	end
	local part = partById[choice]
	if not part then
		return nil, "unknown part"
	end
	if part.category ~= categoryId then
		return nil, "wrong category"
	end
	local out = Customization.copy(build)
	out.parts[categoryId] = part.id
	return out, nil
end

-- ---------------------------------------------------------------------- what it implies

-- The archetype's own number for a car key: its override, else the approved car's. The
-- raw value, never clamped or snapped, so a stock build is today's car to the bit.
local function rawValue(base: string, key: string): number?
	local car = Archetypes.Cars[base] or Archetypes.Cars[Archetypes.Default]
	local v = car and car[key]
	if v == nil then
		v = Archetypes.Base[key]
	end
	return v
end

-- Every fraction a build moves the car by, `{ [car key] = fraction }`. Only keys that move;
-- each summed over the build's parts and held inside `MaxDelta` whatever the data says.
function Customization.deltas(build: Build): { [string]: number }
	local out = {}
	for _, category in categories do
		local part = partById[build.parts[category.id] or ""]
		if part and part.perf then
			for key, fraction in part.perf do
				if keyOwner[key] == category.id and Garage.finite(fraction) then
					out[key] = (out[key] or 0) + fraction
				end
			end
		end
	end
	for key, fraction in out do
		if fraction == 0 then
			out[key] = nil
		else
			out[key] = math.clamp(fraction, -Catalog.MaxDelta, Catalog.MaxDelta)
		end
	end
	return out
end

-- THE CAR NUMBERS A BUILD IMPLIES: every one of the tuner's eight car keys, `{ [car key] =
-- number }`. A key no part moves is the archetype's own number exactly; a moved one is
-- `own × (1 + fraction)`, clamped into the tuner's range and snapped to its step
-- (`Garage.clamp`), so it is a number the tuner, the store and the server all understand.
-- SAYS, NEVER APPLIES: putting these on the car is T-106's.
function Customization.resolve(build: Build): { [string]: number }
	local base = if knownBase(build.base) then build.base else Archetypes.Default
	local deltas = Customization.deltas(build)
	local out = {}
	for _, slider in Garage.Sliders do
		local own = rawValue(base, slider.key)
		local fraction = deltas[slider.key]
		if fraction == nil or own == nil then
			out[slider.key] = own
		else
			out[slider.key] = Garage.clamp(slider.id, own * (1 + fraction)) or own
		end
	end
	return out
end

-- The same, as a tuner tune (`{ [slider id] = value }`, only the keys a part moved): the
-- shape `Garage.toCarFields` and `Cars.setTuning` already take, for the step that applies it.
function Customization.toTune(build: Build): { [string]: number }
	local base = if knownBase(build.base) then build.base else Archetypes.Default
	local numbers = Customization.resolve(build)
	local out = {}
	for _, slider in Garage.Sliders do
		if numbers[slider.key] ~= rawValue(base, slider.key) then
			out[slider.id] = numbers[slider.key]
		end
	end
	return out
end

-- What a build draws, `{ [categoryId] = look }` for every part category with one fitted,
-- plus `Paint` = the paint table. Stock parts carry no look.
function Customization.looks(build: Build): { [string]: any }
	local out = {}
	for _, category in categories do
		local part = partById[build.parts[category.id] or ""]
		if part and part.look then
			out[category.id] = part.look
		end
	end
	out[Catalog.Paint.id] = table.clone(build.paint)
	return out
end

-- ---------------------------------------------------------------------- on the car
--
-- A build is published on the player's car as plain string attributes, so every client
-- draws it from the car alone (CONTRACTS.md "Customization"):
--   Fit_<categoryId>   the part id, for each of the six part categories
--   Fit_Paint<Field>   Fit_PaintBody, Fit_PaintSecond, Fit_PaintFinish, Fit_PaintWrap
--   Fit_Base           the archetype the parts were fitted on
--   Fitted             a number that goes up every time the server rewrites them: watch
--                      this one, then read the rest

local function paintAttr(field: string): string
	return Customization.ATTR_PREFIX .. "Paint" .. string.upper(string.sub(field, 1, 1)) .. string.sub(field, 2)
end

function Customization.attributeNames(): { string }
	local out = { Customization.ATTR_PREFIX .. "Base" }
	for _, category in categories do
		table.insert(out, Customization.ATTR_PREFIX .. category.id)
	end
	for _, field in Catalog.Paint.fieldOrder do
		table.insert(out, paintAttr(field))
	end
	return out
end

function Customization.attributes(build: Build): { [string]: string }
	local out = { [Customization.ATTR_PREFIX .. "Base"] = build.base }
	for _, category in categories do
		out[Customization.ATTR_PREFIX .. category.id] = build.parts[category.id]
	end
	for _, field in Catalog.Paint.fieldOrder do
		out[paintAttr(field)] = build.paint[field]
	end
	return out
end

-- The build on an instance, as a client reads it. Through `sanitize`, so an attribute
-- that has not arrived yet, or one this copy of the catalog does not know, reads as stock.
function Customization.read(instance: Instance): Build
	local raw = { base = instance:GetAttribute(Customization.ATTR_PREFIX .. "Base"), parts = {}, paint = {} }
	for _, category in categories do
		raw.parts[category.id] = instance:GetAttribute(Customization.ATTR_PREFIX .. category.id)
	end
	for _, field in Catalog.Paint.fieldOrder do
		raw.paint[field] = instance:GetAttribute(paintAttr(field))
	end
	return Customization.sanitize(raw)
end

-- ---------------------------------------------------------------------- the data itself

-- Everything wrong with the catalog, as sentences. Empty is the rule; `CustomizationTests`
-- asserts it. Checks every part's shape, every performance number against `MaxDelta` and
-- the keys its category owns, and every look against `LookFields`, `Slots` and
-- `LookBounds`.
function Customization.problems(): { string }
	local out = table.clone(catalogProblems)
	local function bad(text: string)
		table.insert(out, text)
	end

	for _, category in categories do
		local n = #category.parts
		if n < 4 or n > 6 then
			bad(`{category.id} has {n} parts; stock plus 3 to 5 is the rule`)
		end
		if category.parts[1] == nil or category.parts[1].id ~= stockOf[category.id] then
			bad(`{category.id}: stock is not listed first`)
		end
		local owns = {}
		for _, key in category.keys do
			if not Garage.sliderForKey(key) then
				bad(`{category.id} owns {key}, which is not one of the tuner's car keys`)
			end
			owns[key] = true
		end
		for _, part in category.parts do
			local where = `{category.id}/{tostring(part.id)}`
			if not isId(part.id) or string.match(part.id, "^[%w_]+$") == nil then
				bad(`{where}: id is not a short [a-z0-9_] string`)
			end
			if type(part.name) ~= "string" or part.name == "" then
				bad(`{where}: no name`)
			end
			if type(part.price) ~= "number" or part.price < 0 then
				bad(`{where}: price is not a number >= 0`)
			end
			if type(part.unlock) ~= "string" then
				bad(`{where}: unlock is not a string`)
			end
			local stock = part.id == stockOf[category.id]
			if stock and (part.perf ~= nil or part.look ~= nil) then
				bad(`{where}: stock must change nothing`)
			end
			if not stock and part.perf == nil and part.look == nil then
				bad(`{where}: changes nothing`)
			end
			if part.perf ~= nil then
				if category.kind == "looks" then
					bad(`{where}: a looks-only category carries perf`)
				end
				for key, fraction in part.perf do
					if not owns[key] then
						bad(`{where}: moves {tostring(key)}, which {category.id} does not own`)
					elseif not Garage.finite(fraction) or fraction == 0 then
						bad(`{where}: {key} is not a non-zero number`)
					elseif math.abs(fraction) > Catalog.MaxDelta + 1e-9 then
						bad(`{where}: {key} moves {fraction}, past ±{Catalog.MaxDelta}`)
					end
				end
			end
			if part.look ~= nil then
				if category.kind == "performance" then
					bad(`{where}: a performance-only category carries a look`)
				end
				local fields = Catalog.LookFields[category.id] or {}
				for field, value in part.look do
					local want = fields[field]
					if want == nil then
						bad(`{where}: look field {tostring(field)} is not one {category.id} has`)
					elseif typeof(value) ~= want then
						bad(`{where}: look {field} is a {typeof(value)}, not a {want}`)
					end
				end
				local bounds = Catalog.LookBounds
				for field, range in bounds do
					local v = part.look[field]
					if type(v) == "number" and (v < range.min or v > range.max) then
						bad(`{where}: look {field} {v} is outside {range.min}..{range.max}`)
					end
				end
				if part.look.mode ~= nil and not table.find(Catalog.UnderglowModes, part.look.mode) then
					bad(`{where}: underglow mode {tostring(part.look.mode)} is unknown`)
				end
				if type(part.look.slots) == "table" then
					local allowed = Catalog.Slots[category.id] or {}
					for slot, piece in part.look.slots do
						if not table.find(allowed, slot) then
							bad(`{where}: slot {tostring(slot)} is not one of {category.id}'s`)
						elseif type(piece) ~= "string" or piece == "" then
							bad(`{where}: slot {slot} names no piece`)
						end
					end
				end
			end
		end
	end

	local paint = Catalog.Paint
	for field, list in paint.fields do
		if not paintById[list] then
			bad(`paint field {field} chooses from a list that does not exist`)
		elseif not paintById[list][paint.stock[field]] then
			bad(`paint field {field}'s stock is not in its list`)
		end
	end
	for _, list in { "colours", "finishes", "wraps" } do
		local n = #paint[list]
		if n < 4 then
			bad(`paint {list} has {n} options; stock plus 3 at least`)
		end
		for _, option in paint[list] do
			if not isId(option.id) or type(option.name) ~= "string" then
				bad(`paint {list}/{tostring(option.id)}: no id or name`)
			end
			if list == "colours" and option.id ~= "stock" and typeof(option.colour) ~= "Color3" then
				bad(`paint colour {option.id} has no Color3`)
			end
		end
	end
	return out
end

return Customization
