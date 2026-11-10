--!nonstrict
-- CarKitsTests: body kits and interiors drawn on a car -- `Drift/CarKits` and
-- `Config.CarKits` (docs/game/features/car-customization.md, T-105).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugCarKitsTests", "run")
--
-- On real cars built by `CarModel` -- the block, the four parts bodies, and the AE86 when its
-- meshes load -- plus a synthetic rig that names its own slots. The kit parts go into a folder
-- this makes and throws away.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "CarKitsTests only runs in Studio")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)
local Customization = require(ReplicatedStorage.Shared.Customization)
local Catalog = require(ReplicatedStorage.Shared.Customization.Catalog)
local Rig = require(ReplicatedStorage.Shared.Cars.Rig)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local CarKits = require(DriftFolder.CarKits)
local Render = require(DriftFolder.Render)

local CarKitsTests = {}

local BODIES = { "block", "balanced", "gripper", "slider", "bruiser", "ae86" }
local KIT_CATEGORIES = { "BodyKit", "Interior" }

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
end

local function buildWith(base, edits): any
	local build = Customization.stock(base)
	for category, choice in edits do
		build = assert(Customization.fit(build, category, choice))
	end
	return build
end

local function f1(v: Vector3): string
	return string.format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
end

-- The worst gap between each kit part and where it belongs on the body now: studs, and
-- degrees of turn.
local function worstGap(state): (number, number)
	local body = state.car:FindFirstChild("Body") :: BasePart
	local dist, turn = 0, 0
	for i, part in state.parts do
		local want = body.CFrame * state.locals[i]
		dist = math.max(dist, (part.Position - want.Position).Magnitude)
		local _, angle = (want:Inverse() * part.CFrame):ToAxisAngle()
		turn = math.max(turn, math.deg(math.abs(angle)))
	end
	return dist, turn
end

function CarKitsTests.run()
	local checks = {}
	local C = Config.CarKits
	local scratch = Instance.new("Folder")
	scratch.Name = "CarKitsTestsScratch"
	scratch.Parent = workspace
	local kitParent = Instance.new("Folder")
	kitParent.Name = "Kits"
	kitParent.Parent = scratch

	-- 1. Every piece the catalog names is drawn, in the slot the catalog puts it in.
	do
		local missing, pieces = {}, 0
		for _, category in KIT_CATEGORIES do
			for _, slot in Catalog.Slots[category] do
				if not table.find(C.Slots[category], slot) then
					table.insert(missing, `slot {slot} not in Config.CarKits.Slots`)
				end
			end
			for _, part in Customization.partsIn(category) do
				for slot, piece in (part.look and part.look.slots) or {} do
					pieces += 1
					local def = C.Pieces[piece]
					if not def then
						table.insert(missing, `{part.id}: no piece {piece}`)
					elseif def.slot ~= slot then
						table.insert(missing, `{part.id}: {piece} is a {def.slot} piece, fitted in {slot}`)
					elseif #CarKits.shapes(piece) == 0 then
						table.insert(missing, `{piece} has no shapes`)
					end
				end
			end
		end
		for _, body in BODIES do
			if not C.Bodies[body] then
				table.insert(missing, `no slots for body {body}`)
			end
		end
		check(
			checks,
			"every kit and interior piece in the catalog has shapes, in its own slot, and every body has slots",
			#missing == 0,
			if #missing == 0 then `{pieces} piece fittings, {#BODIES} bodies` else table.concat(missing, ", ")
		)
	end

	-- 2-5. Every body, every kit and interior part.
	local rows, problems, rides = {}, {}, {}
	local totals = { parts = 0, draws = 0 }
	local hittable = 0
	for _, key in BODIES do
		CarModel.setBody(key)
		local car = CarModel.build()
		car.Parent = scratch
		if key ~= "block" and not car:FindFirstChild("Shell") then
			table.insert(rows, `{key}: no shell (meshes did not load), skipped`)
			car:Destroy()
			continue
		end
		local function bad(text)
			table.insert(problems, `{key}: {text}`)
		end
		local inCar = #car:GetDescendants()
		local state = CarKits.new(car, kitParent)
		local lo, hi = CarKits.box(car)
		local slots = CarKits.slots(car)
		local paint = Color3.fromRGB(12, 200, 90)

		-- each part alone: its slots filled, every piece where its slot says, on the car
		local worstPlace, worstOut, counts = 0, 0, {}
		for _, category in KIT_CATEGORIES do
			for _, part in Customization.partsIn(category) do
				CarKits.apply(state, buildWith(key, { [category] = part.id }), paint)
				totals.draws += 1
				local want = part.look and part.look.slots or {}
				local nWant = 0
				for slot, piece in want do
					nWant += 1
					if state.fitted[slot] ~= piece then
						bad(`{part.id}: {slot} is {state.fitted[slot]}, not {piece}`)
					end
				end
				if nWant == 0 and #state.parts > 0 then
					bad(`{part.id} (stock) drew {#state.parts} parts`)
				end
				if nWant > 0 and #state.parts == 0 then
					bad(`{part.id} drew nothing`)
				end
				counts[part.id] = #state.parts
				totals.parts += #state.parts
				local d = worstGap(state)
				worstPlace = math.max(worstPlace, d)
				for i, p in state.parts do
					-- each part's slot origin is the one `slots` reports
					local slot = slots[p:GetAttribute("KitSlot")]
					if not slot then
						bad(`{p.Name} has no slot`)
					end
					-- and it is on the car: inside the body's box grown by 2.5 studs (the block car's interior stands on its roof)
					local at = state.locals[i].Position
					local out = (at - at:Max(lo - Vector3.one * 2.5):Min(hi + Vector3.one * 2.5)).Magnitude
					worstOut = math.max(worstOut, out)
					if p:IsDescendantOf(car) or p.Parent ~= state.model or state.model.Parent ~= kitParent then
						bad(`{p.Name} is not in the kit folder`)
					end
					if not p.Anchored or p.CanCollide or p.CanQuery or p.CanTouch then
						hittable += 1
					end
					if p.Color ~= paint and string.find(p.Name, "Flares_1") then
						bad(`{p.Name} is not the body colour`)
					end
				end
			end
		end
		if worstOut > 0 then
			bad(`a kit part sits {string.format("%.2f", worstOut)} studs off the body's box`)
		end

		-- everything at once rides with the car through 40 poses drawn by Render
		CarKits.apply(state, buildWith(key, { BodyKit = "kit_wide", Interior = "int_full" }), paint)
		local full = #state.parts
		CarKits.apply(state, buildWith(key, { BodyKit = "kit_wing", Interior = "int_full" }), paint)
		local rig = Render.rig(car)
		local rng = Random.new(105)
		local worstD, worstT = 0, 0
		for _ = 1, 40 do
			local cf = CFrame.new(rng:NextNumber(-3000, 3000), rng:NextNumber(0, 200), rng:NextNumber(-3000, 3000))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-math.pi, math.pi), rng:NextNumber(-0.3, 0.3))
			local offset = CFrame.new(0, rng:NextNumber(-0.3, 0.3), 0) * CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, 0)
			Render.place(rig, cf, rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 10), rng:NextNumber(-0.1, 0.1), offset)
			CarKits.step({ state })
			local d, t = worstGap(state)
			worstD, worstT = math.max(worstD, d), math.max(worstT, t)
		end
		rides[key] = { d = worstD, t = worstT }
		if worstPlace > 1e-3 then
			bad(`drawn {worstPlace} studs from its place`)
		end

		-- stock takes every part away
		CarKits.apply(state, Customization.stock(key), paint)
		if #state.parts > 0 or state.model ~= nil or #kitParent:GetChildren() > 0 then
			bad(`stock left {#state.parts} parts, {#kitParent:GetChildren()} models`)
		end
		-- and the car itself was never touched
		local phys, stray = CarModel.physicsOffenders(car), CarModel.strayOffenders(car)
		if #car:GetDescendants() ~= inCar or #phys + #stray > 0 then
			bad(`the car went from {inCar} to {#car:GetDescendants()} instances, {#phys} physics, {#stray} stray`)
		end

		local where = {}
		for _, slot in { "KitFront", "KitRear", "KitSkirts", "KitSpoiler", "KitFlares", "InteriorSeat" } do
			local s = slots[slot]
			table.insert(where, `{slot} {s and f1(s.cf.Position) or "none"}`)
		end
		table.insert(
			rows,
			`{key}: box {f1(lo)}..{f1(hi)}; {table.concat(where, ", ")}; parts kit_wide+int_full {full}, street {counts.kit_street}, wing {counts.kit_wing}, ducktail {counts.kit_ducktail}, cage {counts.int_cage}`
		)
		CarKits.clear(state)
		car:Destroy()
	end
	CarModel.setBody(nil)

	check(checks, "every body: each kit and interior part in its slots, on the car, in the kit folder; stock is none; the car untouched", #problems == 0, table.concat(if #problems > 0 then problems else rows, " | "))
	check(checks, "no kit part can be hit: anchored, no collision, query or touch", hittable == 0, `{totals.parts} parts over {totals.draws} draws, {hittable} hittable`)
	do
		local worst, parts = 0, {}
		for _, key in BODIES do
			local r = rides[key]
			if r then
				worst = math.max(worst, r.d)
				table.insert(parts, `{key} {string.format("%.6f", r.d)} studs / {string.format("%.4f", r.t)} deg`)
			end
		end
		check(checks, "kits ride with the body in any pose, lean and suspension included (to 0.001 studs)", worst < 0.001, table.concat(parts, ", "))
	end

	-- 6. A car that names its own slots: they win, and a slot it does not name keeps the rule.
	do
		local function box(name)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = Vector3.new(6, 2, 12)
			return p
		end
		local shell = Rig.assemble({ body = { box("Hull") }, groups = {} })
		local spoilerAt = CFrame.new(0, 1.5, 5) * CFrame.Angles(0, 0, math.rad(5))
		shell:SetAttribute("KitSpoiler", spoilerAt)
		shell:SetAttribute("KitSpoilerSize", Vector3.new(5, 1, 1))
		shell:SetAttribute("KitFront", Vector3.new(0, -1, -6.5))
		CarModel.setBody("block")
		local car = CarModel.build()
		CarModel.setBody(nil)
		CarModel.dress(car, shell)
		car.Parent = scratch
		local slots = CarKits.slots(car)
		local state = CarKits.new(car, kitParent)
		CarKits.apply(state, buildWith("balanced", { BodyKit = "kit_wing" }))
		local wingTop
		for i, p in state.parts do
			if string.find(p.Name, "KitSpoiler_WingHigh_2") then
				wingTop = state.locals[i]
			end
		end
		local wantTop = spoilerAt * CFrame.new(0, 1.2, 1 * 0.05)
		local err = if wingTop then (wingTop.Position - wantTop.Position).Magnitude else math.huge
		local ok = slots.KitSpoiler.from == "rig"
			and slots.KitSpoiler.span == Vector3.new(5, 1, 1)
			and slots.KitFront.from == "rig"
			and slots.KitFront.cf.Position == Vector3.new(0, -1, -6.5)
			and slots.KitFront.span.X == 6
			and slots.KitRear.from == "body"
			and err < 1e-4
		check(
			checks,
			"a rig's own slot points win: KitSpoiler (CFrame + size) and KitFront (point, ruled span)",
			ok,
			`spoiler {slots.KitSpoiler.from} {f1(slots.KitSpoiler.cf.Position)} span {f1(slots.KitSpoiler.span)}, wing at {string.format("%.5f", err)} studs from its place; front {slots.KitFront.from} {f1(slots.KitFront.cf.Position)} span {f1(slots.KitFront.span)}; rear {slots.KitRear.from}`
		)
		CarKits.clear(state)
		car:Destroy()
	end

	scratch:Destroy()
	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return CarKitsTests
