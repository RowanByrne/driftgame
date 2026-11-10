--!nonstrict
-- CarLooksTests: drawing a fitted build on a car -- `Drift/CarLooks` and `Config.CarLooks`
-- (docs/game/features/car-customization.md, T-104).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugCarLooksTests", "run")
--
-- On real cars built by `CarModel` -- the block, the four parts bodies, and the AE86 when
-- its meshes load -- plus a synthetic rig. Nothing here needs a player: the wrap GUIs and
-- the glow go into folders this makes and throws away.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "CarLooksTests only runs in Studio")

local Bodies = require(ReplicatedStorage.Shared.Cars.Bodies)
local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)
local Customization = require(ReplicatedStorage.Shared.Customization)
local Rig = require(ReplicatedStorage.Shared.Cars.Rig)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local CarLooks = require(DriftFolder.CarLooks)
local Render = require(DriftFolder.Render)

local CarLooksTests = {}

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
end

-- Every BasePart in the car, as it is now.
local function snapshot(car: Instance)
	local out = {}
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") then
			out[p] = { Color = p.Color, Material = p.Material, Reflectance = p.Reflectance }
		end
	end
	return out
end

-- Parts whose look differs from a snapshot.
local function changed(snap, only: { [BasePart]: boolean }?): { string }
	local out = {}
	for p, s in snap do
		if (only == nil or only[p]) and (p.Color ~= s.Color or p.Material ~= s.Material or p.Reflectance ~= s.Reflectance) then
			table.insert(out, p.Name)
		end
	end
	return out
end

local function setOf(roles): { [BasePart]: string }
	local out = {}
	for role, parts in roles do
		for _, p in parts do
			out[p] = role
		end
	end
	return out
end

local function buildWith(base, edits): any
	local build = Customization.stock(base)
	for category, choice in edits do
		build = assert(Customization.fit(build, category, choice))
	end
	return build
end

-- Draw through the car's attributes, exactly as a client does: publish, read, apply.
local function drawVia(state, build)
	for name, value in Customization.attributes(build) do
		state.car:SetAttribute(name, value)
	end
	CarLooks.apply(state, Customization.read(state.car))
end

local BODIES = { "block", "balanced", "gripper", "slider", "bruiser", "ae86" }

function CarLooksTests.run()
	local checks = {}
	local C = Config.CarLooks
	local scratch = Instance.new("Folder")
	scratch.Name = "CarLooksTestsScratch"
	scratch.Parent = workspace
	local guiParent = Instance.new("Folder")
	guiParent.Parent = scratch
	local glowParent = Instance.new("Folder")
	glowParent.Parent = scratch

	-- 1. The config draws everything the catalog has.
	do
		local missing = {}
		for _, part in Customization.partsIn("Wheels") do
			if part.look then
				if not C.Rims[part.look.rim] then
					table.insert(missing, `rim {part.look.rim}`)
				end
				if not C.Tyres[part.look.tyre] then
					table.insert(missing, `tyre {part.look.tyre}`)
				end
			end
		end
		for _, wrap in Customization.paintOptions("wraps") do
			if wrap.id ~= "none" and not C.Wraps[wrap.id] then
				table.insert(missing, `wrap {wrap.id}`)
			end
		end
		for _, finish in Customization.paintOptions("finishes") do
			if finish.id ~= "stock" and (Enum.Material :: any)[finish.material] == nil then
				table.insert(missing, `finish {finish.id}`)
			end
		end
		local glows = 0
		for _, part in Customization.partsIn("Underglow") do
			if part.look then
				glows += 1
				if typeof(part.look.colour) ~= "Color3" or not table.find({ "steady", "pulse" }, part.look.mode) then
					table.insert(missing, `glow {part.id}`)
				end
			end
		end
		for _, body in BODIES do
			if not C.Roles[body] then
				table.insert(missing, `roles for {body}`)
			end
		end
		check(
			checks,
			"every rim, tyre, wrap, finish, glow and body in the catalog has a look",
			#missing == 0 and glows == 4,
			if #missing == 0 then `4 wheel parts, 4 wraps, 3 finishes, {glows} glows, {#BODIES} bodies` else table.concat(missing, ", ")
		)
	end

	-- 2-6. Every body, every choice.
	local rows, problems = {}, {}
	local glowOffsets = {}
	for _, key in BODIES do
		CarModel.setBody(key)
		local car = CarModel.build()
		car.Parent = scratch
		local shelled = car:FindFirstChild("Shell") ~= nil
		if key ~= "block" and not shelled then
			table.insert(rows, `{key}: no shell (meshes did not load), skipped`)
			car:Destroy()
			continue
		end
		local state = CarLooks.new(car, guiParent, glowParent)
		local snap = snapshot(car)
		local roles = CarLooks.roles(car)
		local roleOf = setOf(roles)
		local isRole = {}
		for p in roleOf do
			isRole[p] = true
		end
		local function bad(text)
			table.insert(problems, `{key}: {text}`)
		end

		-- roles found, and none of them is glass or a lamp
		local n = { body = #roles.body, second = #roles.second, rim = #roles.rim, tyre = #roles.tyre }
		if n.body == 0 then
			bad("no body parts")
		end
		if key ~= "block" and key ~= "ae86" and n.second == 0 then
			bad("no second-colour parts")
		end
		if key ~= "block" and n.rim ~= 4 then
			bad(`{n.rim} rims`)
		end
		if n.tyre ~= 4 then
			bad(`{n.tyre} tyres`)
		end
		for p in roleOf do
			if p.Material == Enum.Material.Neon or p.Material == Enum.Material.Glass or p.Transparency > 0.5 then
				bad(`{p.Name} is a lamp or glass but has a role`)
			end
		end

		-- each colour as body, then as second; each finish
		for _, colour in Customization.paintOptions("colours") do
			if colour.id ~= "stock" then
				drawVia(state, buildWith(key, { Paint = { body = colour.id, second = "stock" } }))
				for _, p in roles.body do
					if p.Color ~= colour.colour then
						bad(`body {p.Name} is not {colour.id}`)
						break
					end
				end
				drawVia(state, buildWith(key, { Paint = { second = colour.id } }))
				for _, p in roles.second do
					if p.Color ~= colour.colour then
						bad(`second {p.Name} is not {colour.id}`)
						break
					end
				end
			end
		end
		for _, finish in Customization.paintOptions("finishes") do
			if finish.id ~= "stock" then
				drawVia(state, buildWith(key, { Paint = { body = "red", finish = finish.id } }))
				for _, p in roles.body do
					if p.Material.Name ~= finish.material or math.abs(p.Reflectance - finish.reflectance) > 1e-6 then
						bad(`finish {finish.id} on {p.Name}: {p.Material.Name} {p.Reflectance}`)
						break
					end
				end
			end
		end

		-- wheels: each part's rim and tyre
		for _, part in Customization.partsIn("Wheels") do
			drawVia(state, buildWith(key, { Wheels = part.id }))
			local rim, tyre = part.look and C.Rims[part.look.rim], part.look and C.Tyres[part.look.tyre]
			for _, p in roles.rim do
				local want = if rim then rim.colour else snap[p].Color
				if p.Color ~= want then
					bad(`{part.id}: rim {p.Name} {p.Color:ToHex()}`)
					break
				end
			end
			for _, p in roles.tyre do
				local want = if tyre then tyre.colour else snap[p].Color
				local wantM = if tyre then (Enum.Material :: any)[tyre.material] else snap[p].Material
				if p.Color ~= want or p.Material ~= wantM then
					bad(`{part.id}: tyre {p.Name} {p.Color:ToHex()} {p.Material.Name}`)
					break
				end
			end
		end

		-- nothing without a role was ever touched, through all of the above
		local strays = {}
		for p, s in snap do
			if not isRole[p] and (p.Color ~= s.Color or p.Material ~= s.Material or p.Reflectance ~= s.Reflectance) then
				table.insert(strays, p.Name)
			end
		end
		if #strays > 0 then
			bad(`parts with no role changed: {table.concat(strays, ", ")}`)
		end

		-- wraps: a pattern on the box parts in the second colour, gone again with "none"
		local wrapCounts = {}
		for _, wrap in Customization.paintOptions("wraps") do
			drawVia(state, buildWith(key, { Paint = { body = "white", second = "blue", wrap = wrap.id } }))
			local guis, shapes, wrong = #state.guis, 0, 0
			for _, gui in state.guis do
				if gui.Parent ~= guiParent or not gui.Adornee or not gui.Adornee:IsDescendantOf(car) then
					wrong += 1
				end
				for _, f in gui:GetChildren() do
					shapes += 1
					if f.BackgroundColor3 ~= Customization.paintColour("blue") then
						wrong += 1
					end
				end
			end
			if wrap.id == "none" and guis ~= 0 then
				bad(`wrap none left {guis} faces`)
			end
			if wrong > 0 then
				bad(`wrap {wrap.id}: {wrong} faces or shapes wrong`)
			end
			wrapCounts[wrap.id] = `{guis}/{shapes}`
		end
		-- a wrap with the second colour left stock contrasts with the body
		drawVia(state, buildWith(key, { Paint = { body = "white", wrap = "stripes" } }))
		local darkOnWhite = true
		for _, gui in state.guis do
			for _, f in gui:GetChildren() do
				darkOnWhite = darkOnWhite and f.BackgroundColor3 == C.WrapDark
			end
		end
		if not darkOnWhite then
			bad("a stock-second wrap on white is not dark")
		end

		-- underglow: each part on, its colour, a pulse that breathes, steady that does not
		for _, part in Customization.partsIn("Underglow") do
			drawVia(state, buildWith(key, { Underglow = part.id }))
			local look = part.look
			if look then
				local g = state.glow
				if not g or not state.surface or state.surface.Color ~= look.colour or state.glowMode ~= look.mode then
					bad(`{part.id}: glow not drawn`)
				elseif g.Parent ~= glowParent or g:IsDescendantOf(car) then
					bad(`{part.id}: glow is inside the car`)
				elseif not g.Anchored or g.CanCollide or g.CanQuery or g.CanTouch then
					bad(`{part.id}: glow part could be hit`)
				else
					local a, b = CarLooks.brightness(look.mode, 0), CarLooks.brightness(look.mode, C.Underglow.PulsePeriod * 0.5)
					if look.mode == "pulse" and math.abs(a - b) < 0.5 then
						bad(`{part.id}: pulse only moves {a} -> {b}`)
					elseif look.mode == "steady" and a ~= b then
						bad(`{part.id}: steady moves`)
					end
				end
			elseif state.glow then
				bad(`{part.id}: stock left a glow`)
			end
		end

		-- the glow rides with the car: 30 random poses, drawn by Render, stepped here
		drawVia(state, buildWith(key, { Underglow = "glow_ice" }))
		local rig = Render.rig(car)
		local rng = Random.new(104)
		local want = Vector3.new(0, -Config.Drift.RideHeight + C.Underglow.Height, 0)
		local worst = 0
		for _ = 1, 30 do
			local cf = CFrame.new(rng:NextNumber(-3000, 3000), rng:NextNumber(0, 200), rng:NextNumber(-3000, 3000))
				* CFrame.Angles(0, rng:NextNumber(-math.pi, math.pi), 0)
			Render.place(rig, cf, rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 10), rng:NextNumber(-0.1, 0.1))
			CarLooks.step({ state }, rng:NextNumber(0, 100))
			local offset = (car:FindFirstChild("Body") :: BasePart).CFrame:PointToObjectSpace(state.glow.Position)
			worst = math.max(worst, (offset - want).Magnitude)
		end
		glowOffsets[key] = worst

		-- stock puts every part back exactly, and takes the wrap and the glow away
		drawVia(state, buildWith(key, { Paint = { body = "purple", second = "orange", finish = "metallic", wrap = "hex" }, Wheels = "wheels_semislick", Underglow = "glow_magenta" }))
		local dirty = #changed(snap)
		drawVia(state, Customization.stock(key))
		local left = changed(snap)
		if #left > 0 or #state.guis > 0 or state.glow then
			bad(`stock left {#left} parts changed ({table.concat(left, ", ")}), {#state.guis} wraps, glow {state.glow ~= nil}`)
		end

		-- and drawing never put anything in the car
		local phys, stray = CarModel.physicsOffenders(car), CarModel.strayOffenders(car)
		if #phys + #stray > 0 then
			bad(`{#phys} physics, {#stray} stray offenders`)
		end

		table.insert(
			rows,
			`{key}: body {n.body}, second {n.second}, rim {n.rim}, tyre {n.tyre}; a full build changed {dirty} parts; wraps (faces/shapes) stripes {wrapCounts.stripes}, split {wrapCounts.split}, checker {wrapCounts.checker}, hex {wrapCounts.hex}`
		)
		CarLooks.clear(state)
		car:Destroy()
	end
	CarModel.setBody(nil)

	check(checks, "every body: roles found, every choice drawn, nothing else touched", #problems == 0, table.concat(if #problems > 0 then problems else rows, " | "))
	do
		local worst, parts = 0, {}
		for key, w in glowOffsets do
			worst = math.max(worst, w)
			table.insert(parts, `{key} {string.format("%.5f", w)}`)
		end
		check(checks, "the underglow stays under the body in any pose (to 0.001 studs)", worst < 0.001, `worst offset error: {table.concat(parts, ", ")}`)
	end

	-- 7. A rigged car: only what its own `Paint` attributes say.
	do
		local function box(name, paint)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = Vector3.new(2, 1, 4)
			p.Color = Color3.fromRGB(10, 20, 30)
			if paint then
				p:SetAttribute("Paint", paint)
			end
			return p
		end
		local y = Config.Drift.WheelDiameter * 0.5 - Config.Drift.RideHeight
		local shell = Rig.assemble({
			body = { box("Panel", "body"), box("Hull", nil), box("Paint", "none"), box("Stripe", "second") },
			groups = {
				{ name = "HubFL", kind = "hub", pivot = Vector3.new(-2.8, y, -4.8), wheel = "WheelFL", parts = {} },
				{ name = "WheelFL", kind = "spin", pivot = Vector3.new(-2.8, y, -4.8), on = "HubFL", parts = { box("Tire", nil), box("Spokes", "rim") } },
			},
		})
		CarModel.setBody("block")
		local car = CarModel.build()
		CarModel.setBody(nil)
		CarModel.dress(car, shell)
		local roles = CarLooks.roles(car)
		local function names(list)
			local out = {}
			for _, p in list do
				table.insert(out, p.Name)
			end
			table.sort(out)
			return table.concat(out, ",")
		end
		local got = `body {names(roles.body)}; second {names(roles.second)}; rim {names(roles.rim)}; tyre {names(roles.tyre)}`
		check(
			checks,
			"a rigged car is painted by its parts' Paint attributes, never by name",
			got == "body Panel; second Stripe; rim Spokes; tyre Tire",
			got
		)
		car:Destroy()
	end

	scratch:Destroy()
	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return CarLooksTests
