--!nonstrict
-- GroundLookTests: the ground's look by steepness and height (T-338 step 1, T-339,
-- features/ground-look.md). Pure maths, a second or two:
--   require(game.ServerScriptService.Tests.GroundLookTests).run()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

assert(RunService:IsStudio(), "GroundLookTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local GroundLook = require(ReplicatedStorage.Shared.Road.GroundLook)
local DetailTexture = require(ReplicatedStorage.Shared.Road.DetailTexture)

local Tests = {}

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 2) .. "f", x)
end

local function ny(deg: number): number
	return math.cos(math.rad(deg))
end

local function run(check)
	local L = Config.GroundLook

	-- THE SWITCH
	local was = Workspace:GetAttribute("__ground_look")
	Workspace:SetAttribute("__ground_look", nil)
	check("the look is the config's with no switch", GroundLook.current() == L.Look, GroundLook.current())
	Workspace:SetAttribute("__ground_look", "rock")
	check("the switch picks a look", GroundLook.current() == "rock", GroundLook.current())
	Workspace:SetAttribute("__ground_look", "nonsense")
	check("a look that is not one reads as old", GroundLook.current() == "old", GroundLook.current())
	Workspace:SetAttribute("__ground_look", was)

	-- STEEPNESS AND HEIGHT, over a spread of places
	local rng = Random.new(5)
	local places = {}
	for _ = 1, 400 do
		table.insert(places, { rng:NextNumber(-40000, 40000), rng:NextNumber(-40000, 40000) })
	end
	local flatLow, cliff, monoBad, snowBad, steepSnow, flatHighSnow = 0, 0, 0, 0, 0, 0
	local edges = {}
	for _, p in places do
		local x, z = p[1], p[2]
		if GroundLook.weights(x, z, 0, 1).rock == 0 and GroundLook.weights(x, z, 0, 1).snow == 0 then
			flatLow += 1
		end
		if GroundLook.weights(x, z, 0, ny(75)).rock > 0.99 then
			cliff += 1
		end
		local last, edge = -1, nil
		for a = 0, 89, 1 do
			local r = GroundLook.weights(x, z, 400, ny(a)).rock
			if r < last - 1e-9 then
				monoBad += 1
			end
			if not edge and r >= 0.5 then
				edge = a
			end
			last = r
		end
		table.insert(edges, edge or 90)
		local s = -1
		for alt = 0, 2000, 50 do
			local w = GroundLook.weights(x, z, alt, 1).snow
			if w < s - 1e-9 then
				snowBad += 1
			end
			s = w
		end
		if GroundLook.weights(x, z, 1600, ny(70)).snow > 0.01 then
			steepSnow += 1
		end
		if GroundLook.weights(x, z, 1600, 1).snow > 0.99 then
			flatHighSnow += 1
		end
	end
	check("flat ground in the start valley is grass", flatLow == #places, `{flatLow} of {#places}`)
	check("a 75 degree face is all rock", cliff == #places, `{cliff} of {#places}`)
	check("steeper is never less rock", monoBad == 0, `{monoBad} steps back`)
	check("higher is never less snow", snowBad == 0, `{snowBad} steps back`)
	check("snow does not lie on a 70 degree face", steepSnow == 0, `{steepSnow} of {#places}`)
	check("flat ground up high is snow", flatHighSnow == #places, `{flatHighSnow} of {#places}`)
	table.sort(edges)
	local spread = edges[#edges] - edges[1]
	check("the rock's edge wanders, so it never runs in a line", spread >= L.Jitter, `half-rock from {edges[1]} to {edges[#edges]} degrees`)

	-- THE COLOURS
	local c = GroundLook.colour(100, 0, 100, 0, 1)
	local lo, hi = L.Lush[1], L.Lush[2]
	local inLush = c.G >= math.min(lo.G, hi.G) - 1e-6 and c.G <= math.max(lo.G, hi.G) + 1e-6
	check("low flat ground is the old look's grass", inLush, `{fmt(c.R * 255, 0)}, {fmt(c.G * 255, 0)}, {fmt(c.B * 255, 0)}`)
	local r = GroundLook.colour(100, 0, 100, 0, ny(80))
	check("a cliff is grey, not green", math.abs(r.G - r.R) < 0.06 and math.abs(r.G - r.B) < 0.08, `{fmt(r.R * 255, 0)}, {fmt(r.G * 255, 0)}, {fmt(r.B * 255, 0)}`)
	local s = GroundLook.colour(100, 1600, 100, 1600, 1)
	check("snow is near white", s.R > 0.85 and s.G > 0.85 and s.B > 0.85, `{fmt(s.R * 255, 0)}, {fmt(s.G * 255, 0)}, {fmt(s.B * 255, 0)}`)
	local d = GroundLook.forTexture("detail", c)
	check("the detail look lifts its colours by the texture's average", math.abs(d.G - math.min(1, c.G / L.Detail.Mean)) < 1e-6, `{fmt(c.G, 3)} to {fmt(d.G, 3)}`)

	-- COST
	local t0 = os.clock()
	local N = 20000
	for i = 1, N do
		GroundLook.colour(i * 3.7, i % 1500, i * 1.3, i % 1500, ny(i % 80))
	end
	local us = (os.clock() - t0) / N * 1e6
	check("a vertex's colour costs little", us < 6, `{fmt(us)} microseconds`)

	-- THE DETAIL TEXTURE
	local size = 64
	local px = DetailTexture.pixels(size)
	local sum, inner, edge, ni, ne = 0, 0, 0, 0, 0
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local v = px[y * size + x + 1]
			sum += v
			local right = px[y * size + (x + 1) % size + 1]
			if x == size - 1 then
				edge += math.abs(v - right)
				ne += 1
			else
				inner += math.abs(v - right)
				ni += 1
			end
		end
	end
	local mean = sum / (size * size)
	check("the detail texture averages its mean", math.abs(mean - L.Detail.Mean) < 0.04, fmt(mean, 3))
	check("the detail texture tiles: no step at its edge", edge / ne < 2 * inner / ni + 1e-3, `edge {fmt(edge / ne, 4)}, inside {fmt(inner / ni, 4)}`)

	-- THE TEXTURE SHEET (T-340)
	local GroundSheet = require(ReplicatedStorage.Shared.Road.GroundSheet)
	check("snow over rock over rocky grass over grass", GroundLook.sheetCell(0.6, 0.9, 0.9) == 4 and GroundLook.sheetCell(0.2, 0.6, 0.9) == 3 and GroundLook.sheetCell(0, 0.2, 0.6) == 2 and GroundLook.sheetCell(0, 0, 0.2) == 1, "")
	local t = 48
	local tiles, means, seams = {}, {}, {}
	for i, kind in L.Sheet.Order do
		local p = GroundSheet.placeholder(kind, t)
		tiles[i] = p
		local s, e, inn = 0, 0, 0
		for y = 0, t - 1 do
			for x = 0, t - 1 do
				s += p[y * t + x + 1]
				local r = p[y * t + (x + 1) % t + 1]
				if x == t - 1 then
					e += math.abs(p[y * t + x + 1] - r)
				else
					inn += math.abs(p[y * t + x + 1] - r)
				end
			end
		end
		table.insert(means, `{kind} {fmt(s / (t * t), 2)}`)
		local ratio = (e / t) / (inn / (t * (t - 1)))
		table.insert(seams, `{kind} {fmt(ratio, 2)}`)
		check(`the {kind} placeholder averages near the sheet's mean`, math.abs(s / (t * t) - L.Sheet.Mean) < 0.12, fmt(s / (t * t), 3))
		check(`the {kind} placeholder tiles`, ratio < 2.5, `edge step {fmt(ratio, 2)} times the inside's`)
	end
	local size = 96
	local laid = GroundSheet.lay(tiles, t, size, L.Sheet.Repeats)
	local same = 0
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local row, col = y // (size // 2), x // (size // 2)
			local ty = math.floor(((y % (size // 2)) / (size // 2) * L.Sheet.Repeats) % 1 * t)
			local tx = math.floor(((x % (size // 2)) / (size // 2) * L.Sheet.Repeats) % 1 * t)
			if laid[y * size + x + 1] == tiles[row * 2 + col + 1][ty * t + tx + 1] then
				same += 1
			end
		end
	end
	check("the sheet lays each texture in its square", same == size * size, `{same} of {size * size}`)
end

function Tests.run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local ok, err = pcall(run, check)
	if not ok then
		check("the ground look tests ran", false, tostring(err))
	end
	local passed = true
	for _, c in checks do
		if not c.ok then
			passed = false
		end
	end
	return { passed = passed, checks = checks }
end

return Tests
