--!strict
-- T-203: seeded, bounded semi-random categories of the existing mountain terrain.
-- Records are absolute {boundaryS, destinationKind, blendLength} triples. A transition
-- keeps its original endpoints even when it crosses several generator sections.
local Config = require(game.ReplicatedStorage.Shared.Config)
local Biome = {}
Biome.FIELD, Biome.SMALL, Biome.STEEP = 1, 2, 3
Biome.Names = { "Fields", "Small cliffs", "Steep cliffs" }

local Schedule = {}
Schedule.__index = Schedule
export type Schedule = typeof(setmetatable({} :: {
	list: { number },
	lengthRng: Random,
	choiceRng: Random,
	distance: { number },
	total: number,
}, Schedule))

local function finite(n: any): boolean
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

-- Cubic smoothstep's largest derivative is 1.5. Reserve distance against the
-- maximum actual profile envelopes, not just a fade between category names.
function Biome.blendLength(a: number, b: number): number
	local C = Config.Spline.Biomes
	local length = math.max(C.MinBlend,
		1.5 * math.abs(C.Rise[b] - C.Rise[a]) / C.RiseRate,
		1.5 * math.abs(C.Drop[b] - C.Drop[a]) / C.DropRate,
		1.5 * math.abs(C.Width[b] - C.Width[a]) / C.WidthRate)
	assert(length <= C.MaxBlend, "SplineBiome: profile change exceeds the transition budget")
	return length
end

function Biome.new(seed: number): Schedule
	return setmetatable({
		list = { 0, Biome.FIELD, 0 },
		lengthRng = Random.new((seed * 29 + 4013) % 2 ^ 31),
		choiceRng = Random.new((seed * 31 + 5051) % 2 ^ 31),
		distance = { 0, 0, 0 },
		total = 0,
	}, Schedule)
end

function Schedule.clone(self: Schedule): Schedule
	return setmetatable({
		list = table.clone(self.list),
		lengthRng = self.lengthRng:Clone(),
		choiceRng = self.choiceRng:Clone(),
		distance = table.clone(self.distance),
		total = self.total,
	}, Schedule)
end

local function nextBoundary(self: Schedule)
	local C = Config.Spline.Biomes
	local list = self.list
	local n = #list
	local current, incoming = list[n - 1], list[n]
	local mean = (C.Length[1] + C.Length[2]) * 0.5
	local weights, total = {}, 0
	for kind = 1, 3 do
		local used = self.distance[kind] + (if kind == current then mean else 0)
		local deficit = C.Weights[kind] * (self.total + 2 * mean) - used
		local weight = if kind == current then 0 else math.max(0, deficit) + C.Weights[kind] * mean * C.ChoiceJitter
		weights[kind] = weight
		total += weight
	end
	local roll = self.choiceRng:NextNumber() * total
	local chosen = 3
	for kind = 1, 3 do
		roll -= weights[kind]
		if roll < 0 then chosen = kind; break end
	end
	local outgoing = Biome.blendLength(current, chosen)
	local minimum = math.max(C.Length[1], C.PlateauMin + (incoming + outgoing) * 0.5)
	assert(minimum <= C.Length[2], "SplineBiome: no room for gradual transitions within length bounds")
	local length = minimum + (C.Length[2] - minimum) * self.lengthRng:NextNumber()
	self.distance[current] += length
	self.total += length
	table.insert(list, list[n - 2] + length)
	table.insert(list, chosen)
	table.insert(list, outgoing)
end

-- Resolve the next transition before any of its ground can be emitted. The extra
-- future record is private to the server until the first section touching its blend.
function Schedule.extend(self: Schedule, s: number)
	local list = self.list
	while list[#list - 2] - list[#list] * 0.5 <= s do
		nextBoundary(self)
	end
end

function Schedule.records(self: Schedule, s0: number, s1: number): { number }
	self:extend(s1)
	local list = self.list
	local lo, hi = 1, #list // 3
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if list[3 * mid - 2] <= s0 then lo = mid else hi = mid - 1 end
	end
	local anchor = 3 * lo - 2
	local out = {}
	for i = math.max(1, anchor - 3), #list, 3 do
		if list[i] - list[i + 2] * 0.5 > s1 then break end
		table.insert(out, list[i])
		table.insert(out, list[i + 1])
		table.insert(out, list[i + 2])
	end
	return out
end

-- Validate against an old prefix and a tiny pending suffix without copying an hour
-- of records. No input changes until the owning Spline commits the whole section.
function Biome.validate(known: { number }?, additions: { number }?, s0: number): { number }?
	if additions == nil then return nil end
	assert(#additions >= 3 and #additions % 3 == 0, "SplineBiome: records come in triples")
	local C = Config.Spline.Biomes
	local old = known or {}
	local count = #old
	local pending = {}
	local function get(i: number): number
		return if i <= count then old[i] else pending[i - count]
	end
	local previous = -math.huge
	for i = 1, #additions, 3 do
		local boundary, kind, blend = additions[i], additions[i + 1], additions[i + 2]
		assert(finite(boundary) and finite(kind) and finite(blend), "SplineBiome: finite records required")
		assert(boundary > previous and kind % 1 == 0 and kind >= 1 and kind <= 3, "SplineBiome: increasing boundaries and known categories required")
		previous = boundary
		local n = count + #pending
		if n == 0 then
			assert(s0 == 0 and boundary == 0 and blend == 0, "SplineBiome: initial record must precede the first road")
		elseif boundary <= get(n - 2) then
			local lo, hi = 1, n // 3
			while lo < hi do
				local mid = (lo + hi) // 2
				if get(3 * mid - 2) < boundary then lo = mid + 1 else hi = mid end
			end
			local at = 3 * lo - 2
			assert(get(at) == boundary and get(at + 1) == kind and get(at + 2) == blend, "SplineBiome: repeated records must match")
			continue
		else
			local length = boundary - get(n - 2)
			assert(kind ~= get(n - 1), "SplineBiome: adjacent categories must differ")
			assert(blend >= Biome.blendLength(get(n - 1), kind) - 1e-6 and blend <= C.MaxBlend, "SplineBiome: transition too short for its profile change")
			assert(length >= C.Length[1] - 1e-6 and length <= C.Length[2] + 1e-6, "SplineBiome: length outside bounds")
			assert(length - (get(n) + blend) * 0.5 >= C.PlateauMin - 1e-6, "SplineBiome: transitions must finish before the next starts")
			assert(boundary - blend * 0.5 >= s0 - 1e-6, "SplineBiome: new transition changes already emitted terrain")
		end
		table.insert(pending, boundary)
		table.insert(pending, kind)
		table.insert(pending, blend)
	end
	return pending
end

-- Called only after every part of a section validates. Existing records are
-- append-only; old ground and its phases never change. This is O(new records).
function Biome.commit(known: { number }?, pending: { number }?): { number }?
	if pending == nil or #pending == 0 then return known end
	local out = known or {}
	for _, value in pending do table.insert(out, value) end
	return out
end

-- Pure combination for snapshots and tests; runtime replay validates then commits
-- the small suffix so it does not repeatedly clone the whole retained history.
function Biome.merge(known: { number }?, additions: { number }?, s0: number): { number }?
	local pending = Biome.validate(known, additions, s0)
	if pending == nil or #pending == 0 then return known end
	return Biome.commit(if known then table.clone(known) else nil, pending)
end

-- No ordinary eased-track knots here: evaluate the original transition interval,
-- regardless of where road sections split it. nil means the older terrain contract.
function Biome.at(records: { number }?, s: number): (number?, number?, number)
	if records == nil or #records == 0 then return nil, nil, 0 end
	local lo, hi = 1, #records // 3
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		local at = 3 * mid - 2
		if records[at] - records[at + 2] * 0.5 <= s then lo = mid else hi = mid - 1 end
	end
	local at = 3 * lo - 2
	local boundary, kind, blend = records[at], records[at + 1], records[at + 2]
	if at == 1 or blend == 0 or s >= boundary + blend * 0.5 then return kind, kind, 0 end
	local u = math.clamp((s - boundary + blend * 0.5) / blend, 0, 1)
	return records[at - 2], kind, u * u * (3 - 2 * u)
end

function Biome.mix(records: { number }?, s: number, values: { number }, legacy: number): number
	local from, to, alpha = Biome.at(records, s)
	if from == nil or to == nil then return legacy end
	return values[from] + (values[to] - values[from]) * alpha
end

return Biome
