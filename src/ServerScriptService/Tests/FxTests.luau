--!nonstrict
-- FxTests: the car's wheel effects, measured rather than looked at
-- (docs/game/features/car-fx.md "Testing", docs/workflow/TESTING.md, T-062).
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugFxTests", "run")
--
-- MOST OF IT IS PURE. The four gates, the tyre heat and the cancelling of the body's lean
-- are all plain functions with no instance in them, so every threshold and every curve in
-- this feature can be measured without a car, a place or a playtest. Two checks are not
-- pure and say so: the one that builds a stand-in rig and counts its instances, and the
-- one that drives a thousand frames through it and counts them again.
--
-- Since T-064 it covers the SOUNDS too -- the gearbox, the engine note and the squeal's
-- gate -- and the line between what a test can check and what only an ear can is worth
-- stating plainly:
--
--   WHAT IS MEASURED HERE  the gear tops against the geometric series, the shift speeds
--                          and their spacing, that no single frame moves the pitch more
--                          than the lerp allows, the squeal's volume against the
--                          configured lerp of the LATERAL SLIDE SPEED at every angle AND
--                          every speed, the step into a drift and its four ways to be
--                          silent, that `RollVolume` is still the one switch for the
--                          always-on hiss the user rejected, that the clip is started once
--                          and left running (T-083), and that a drive creates and destroys
--                          no instance.
--   WHAT IS NOT            whether any of it SOUNDS right: whether the clip loops cleanly
--                          when it is stretched, whether 0.7 and 2.2 are the right floor
--                          and ceiling, whether the squeal sits over the engine. That is
--                          the user's ear and no number here stands in for it.
--
-- The sound rig is built in SERVERSTORAGE on purpose: a `Sound` this test plays under a
-- part in Workspace would replicate to every client and be heard.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "FxTests is Studio only")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Engine = require(DriftFolder.Engine)
local EngineSound = require(DriftFolder.EngineSound)
local Model = require(DriftFolder.Model)
local Render = require(DriftFolder.Render)
local Suspension = require(DriftFolder.Suspension)
local SkidSound = require(DriftFolder.SkidSound)
local Wheels = require(DriftFolder.Wheels)
local GroundMarks = require(DriftFolder.GroundMarks)

local Tests = {}

local FRAMES = 1000 -- frames the allocation check drives through `Update`
local RATE_TOLERANCE = 1e-6

-- A list of numbers, readable, for a check's detail line.
local function fmtList(xs: { number }): string
	local out = {}
	for _, x in xs do
		table.insert(out, string.format("%.2f", x))
	end
	return table.concat(out, ", ")
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- A state with exactly the fields the gates read, and the rest left as `Model.new` made
-- them. `slip` is in DEGREES here because every threshold in `Config.Fx` is.
--
-- `speed` is written straight onto `u`, with `v` left at zero, rather than being resolved
-- out of the slip angle: `Model.speed` is `sqrt(u^2 + v^2)` and the gates read the slip
-- angle and the speed as two independent numbers, so a state that carries both honestly
-- is all this needs. It is not a state the model could have produced, and no check here
-- asks it to be.
local function stateWith(opts)
	local s = Model.new(CFrame.new(0, 0, 0))
	s.slip = math.rad(opts.slipDeg or 0)
	s.u = opts.speed or 0
	s.v = 0
	s.throttle = opts.throttle or 0
	s.bodyRoll = math.rad(opts.rollDeg or 0)
	s.airborne = opts.airborne == true
	s.grounded = not s.airborne
	local down = opts.down
	if down == nil then
		down = { not s.airborne, not s.airborne, not s.airborne, not s.airborne }
	end
	s.wheelsDown = down
	-- Each wheel's named ground (T-188): one name for all four, or a list of four.
	local surface = opts.surface
	if type(surface) == "string" then
		s.wheelSurface = { surface, surface, surface, surface }
	elseif type(surface) == "table" then
		s.wheelSurface = surface
	end
	s.drifting = math.abs(s.slip) >= math.rad(Config.Drift.MinSlipAngleForDrift)
	return s
end

-- Which of the four wheels emit, in FL/FR/RL/RR order, as a readable string.
local function emitting(state, handbrake: boolean): (string, { boolean })
	local out, flags = {}, {}
	for i, name in CarModel.WHEEL_NAMES do
		local front = CarModel.isFrontWheel(name)
		local down = state.wheelsDown[i] == true
		local emit = Wheels.evaluate(state, handbrake, front, down)
		flags[i] = emit
		table.insert(out, `{name}={if emit then "YES" else "no"}`)
	end
	return table.concat(out, " "), flags
end

local function count(flags: { boolean }): (number, number)
	local front, rear = 0, 0
	for i, on in flags do
		if on then
			if CarModel.isFrontWheel(CarModel.WHEEL_NAMES[i]) then
				front += 1
			else
				rear += 1
			end
		end
	end
	return front, rear
end

-- A stand-in rig: the same five parts `Drift/Render` holds, built by hand so the
-- allocation check needs no car, no server spawn and no mesh download. `Wheels.Attach`
-- reads `body` and each wheel's `part.Name` and `offset`, and nothing else.
local function standInRig(): (any, Model)
	local car = Instance.new("Model")
	car.Name = "FxTestCar"
	local body = Instance.new("Part")
	body.Name = CarModel.BODY_NAME
	body.Size = Vector3.new(4, 2, 8)
	body.Anchored = true
	body.CanCollide = false
	body.Transparency = 1
	body.Parent = car

	local wheels = {}
	for name, offset in CarModel.wheelOffsets() do
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.one
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.Parent = car
		table.insert(wheels, { part = part, offset = offset, front = CarModel.isFrontWheel(name), shell = nil })
	end
	car.Parent = workspace
	return { car = car, body = body, bodyShell = nil, wheels = wheels, complete = true }, car
end

--------------------------------------------------------------------------------
-- The run
--------------------------------------------------------------------------------

function Tests.run(opts)
	opts = opts or {}
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end

	local F = Config.Fx

	----------------------------------------------------------------------------
	-- 1. The config is a config
	----------------------------------------------------------------------------
	do
		local builtOk, missing = true, {}
		for _, surface in F.Built do
			local look = F.Surfaces[surface]
			-- A built surface needs both colours: the diffuse smoke and the stylized puff on
			-- top of it. (Its mark is the rubber ribbon's `Marks.Rubber`, T-269.)
			if not look or not look.SmokeColour or not look.PuffColour then
				builtOk = false
				table.insert(missing, surface)
			end
		end
		check(
			"every built surface has a smoke and a puff colour",
			builtOk,
			`built: {table.concat(F.Built, ", ")}{if builtOk then "" else "; incomplete look for " .. table.concat(missing, ", ")}`
		)
		-- THE INSTANCE BUDGET IS THIS FORMULA: 4 wheels x (smoking surfaces x 2 ParticleEmitters
		-- + the off-road layer's 3 ParticleEmitters -- the grass's fine spray and the dust, T-188,
		-- and the grass's earthy cloud, T-279; the mud is the client's 3D clods since T-283 -- + 3
		-- fixed emitter anchors, T-207), the grass ribbon's strips, two MeshParts a wheel (T-265),
		-- the rubber ribbon's, one a wheel (T-269), and their two folders: 46 a car.
		check(
			"one smoking surface, and the budget it comes to",
			#F.Built == 1 and Wheels.perWheel() == 8
				and Wheels.perCar() == 4 * 8 + F.Ground.Ribbon.Wheels * 2 + F.Marks.Ribbon.Wheels + 2
				and Wheels.perCar() == 46,
			`{#F.Built} surface(s) -> {Wheels.perWheel()} a wheel, {Wheels.perCar()} instances per car`
		)
		-- THE RUBBER IS SEE-THROUGH BY VERTEX ALPHA (T-269), which needs its part above 0
		-- Transparency (measured: 0 and 0.001 draw solid), and no darkness ladder: one ribbon.
		check(
			"the rubber is a see-through ribbon: its part over 0 transparency, its edge clear",
			F.Marks.Ribbon.Transparency > 0.001 and F.Marks.Ribbon.Transparency < 0.1
				and F.Marks.Rubber.Points[1].Alpha == 0 and F.Marks.Scuff.Points[1].Alpha == 0
				and F.Marks.Bands == nil,
			`part transparency {F.Marks.Ribbon.Transparency}; edge alpha {F.Marks.Rubber.Points[1].Alpha}; no Bands table`
		)
		check(
			"a mark is narrower than the tyre that leaves it",
			F.Marks.Width < Config.Drift.WheelWidth,
			`mark {F.Marks.Width} studs, tyre {Config.Drift.WheelWidth} studs`
		)
		check(
			"the fronts' threshold is well clear of the floating-point floor",
			F.Gates.MaxSteerDegrees > F.Gates.MinSlipDegrees * 10,
			`fronts {F.Gates.MaxSteerDegrees} deg, floor {F.Gates.MinSlipDegrees} deg`
		)
		check(
			"the floor is far below the model's own drift threshold",
			F.Gates.MinSlipDegrees < Config.Drift.MinSlipAngleForDrift * 0.5,
			`floor {F.Gates.MinSlipDegrees} deg, drifting at {Config.Drift.MinSlipAngleForDrift} deg`
		)
		-- THE PAINTED SHEETS (T-279): every emitter names a sheet that is an uploaded id with a
		-- flipbook grid, lies under the one light rule, and stays under the mobile cap of 100
		-- particles a second at its maximum.
		local G = F.Ground
		local emitters = {
			Smoke = F.Smoke, Stylized = F.Stylized, Clippings = G.Grass.Clippings,
			Spray = G.Grass.Spray, Dust = G.Gravel.Dust,
		}
		local sheetsOk, sheetLine = true, {}
		for name, S in emitters do
			local sheet = F.Sheets[S.Sheet]
			local ok = sheet ~= nil
				and string.match(sheet.Texture, "^rbxassetid://%d+$") ~= nil
				and sheet.Layout ~= Enum.ParticleFlipbookLayout.None
				and typeof(S.Orientation) == "EnumItem"
				and type(S.ZOffset) == "number"
				and S.LightInfluence == nil
				and S.RateMax <= 100
			sheetsOk = sheetsOk and ok
			if not ok then
				table.insert(sheetLine, `{name}: sheet {tostring(S.Sheet)}, RateMax {S.RateMax}`)
			end
		end
		check(
			"every emitter draws from an uploaded sheet, under one light, under the mobile cap",
			sheetsOk and F.Light.Influence > 0 and F.Light.Emission == 0 and F.Flipbook.Framerate == 0,
			if sheetsOk then `5 emitters; light {F.Light.Influence} / {F.Light.Emission}` else table.concat(sheetLine, "; ")
		)
	end

	----------------------------------------------------------------------------
	-- 2. THE FRONT/REAR THRESHOLD. The check this feature is about.
	----------------------------------------------------------------------------
	do
		local small = stateWith({ slipDeg = 20, speed = 60, throttle = 1 })
		local big = stateWith({ slipDeg = 60, speed = 60, throttle = 1 })
		local smallText, smallFlags = emitting(small, false)
		local bigText, bigFlags = emitting(big, false)
		local sf, sr = count(smallFlags)
		local bf, br = count(bigFlags)
		check(
			"a small slide (20 deg): the rears mark and the fronts do not",
			sf == 0 and sr == 2,
			`{smallText} -- {sf} front, {sr} rear; the fronts' threshold is {F.Gates.MaxSteerDegrees} deg`
		)
		check("a big slide (60 deg): all four mark", bf == 2 and br == 2, `{bigText} -- {bf} front, {br} rear`)

		-- And the fronts switch on exactly where the config says, not somewhere near it.
		local switchAt = nil
		for deg = 0, 90, 0.1 do
			local _, flags = emitting(stateWith({ slipDeg = deg, speed = 60, throttle = 1 }), false)
			local f = count(flags)
			if f == 2 then
				switchAt = deg
				break
			end
		end
		local want = F.Gates.MaxSteerDegrees + F.Gates.MinSlipDegrees
		check(
			"the fronts switch on at MaxSteerDegrees, swept at a tenth of a degree",
			switchAt ~= nil and math.abs(switchAt - want) <= 0.15,
			`fronts start at {switchAt} deg, config says {want} deg`
		)

		-- The rears switch on at the floor and nowhere else.
		local rearAt = nil
		for deg = 0, 10, 0.01 do
			local _, flags = emitting(stateWith({ slipDeg = deg, speed = 60, throttle = 1 }), false)
			local _, r = count(flags)
			if r == 2 then
				rearAt = deg
				break
			end
		end
		check(
			"the rears switch on at the floating-point floor",
			rearAt ~= nil and math.abs(rearAt - F.Gates.MinSlipDegrees) <= 0.02,
			`rears start at {rearAt} deg, floor is {F.Gates.MinSlipDegrees} deg`
		)

		-- A car driving dead straight marks nothing, which is the whole reason the floor
		-- exists: the model's slip angle is an `atan2` and is never exactly zero.
		local straight = stateWith({ slipDeg = 1e-5, speed = 120, throttle = 1 })
		local straightText, straightFlags = emitting(straight, false)
		local zf, zr = count(straightFlags)
		check("a car driving straight marks nothing", zf == 0 and zr == 0, straightText)
	end

	----------------------------------------------------------------------------
	-- 3. The throttle gate
	----------------------------------------------------------------------------
	do
		local coasting = stateWith({ slipDeg = 60, speed = 60, throttle = 0 })
		local text, flags = emitting(coasting, false)
		local f, r = count(flags)
		check("coasting sideways at zero throttle marks nothing", f == 0 and r == 0, `60 deg of slip, {text}`)

		local just = stateWith({ slipDeg = 60, speed = 60, throttle = F.Gates.MinThrottle })
		local _, justFlags = emitting(just, false)
		local jf, jr = count(justFlags)
		check(
			"and it marks the moment the throttle reaches MinThrottle",
			jf == 2 and jr == 2,
			`throttle {F.Gates.MinThrottle}: {jf} front, {jr} rear`
		)

		local under = stateWith({ slipDeg = 60, speed = 60, throttle = F.Gates.MinThrottle - 0.01 })
		local _, underFlags = emitting(under, false)
		local uf, ur = count(underFlags)
		check("and not a hundredth below it", uf == 0 and ur == 0, `throttle {F.Gates.MinThrottle - 0.01}`)
	end

	----------------------------------------------------------------------------
	-- 4. The handbrake, which is its own gate
	----------------------------------------------------------------------------
	do
		local still = stateWith({ slipDeg = 0, speed = 0, throttle = 0 })
		local stillText, stillFlags = emitting(still, true)
		local sf, sr = count(stillFlags)
		check("the handbrake from a standstill does nothing", sf == 0 and sr == 0, `0 studs/s: {stillText}`)

		local moving = stateWith({ slipDeg = 0, speed = 40, throttle = 0 })
		local movingText, movingFlags = emitting(moving, true)
		local mf, mr = count(movingFlags)
		check(
			"the handbrake at 40 studs/s lights all four, straight and off the throttle",
			mf == 2 and mr == 2,
			`{movingText} -- no throttle, no slip`
		)

		local edge = stateWith({ slipDeg = 0, speed = F.Gates.MinHandbrakeSpeed - 0.01, throttle = 0 })
		local _, edgeFlags = emitting(edge, true)
		local ef, er = count(edgeFlags)
		check(
			"and nothing a hundredth of a stud below MinHandbrakeSpeed",
			ef == 0 and er == 0,
			`{F.Gates.MinHandbrakeSpeed - 0.01} studs/s against a floor of {F.Gates.MinHandbrakeSpeed}`
		)
	end

	----------------------------------------------------------------------------
	-- 5. Smoke rate against the configured lerp
	----------------------------------------------------------------------------
	do
		local lines, ok = {}, true
		for _, deg in { 10, 45, 90, 180 } do
			local s = stateWith({ slipDeg = deg, speed = 60, throttle = 1 })
			local _, rate = Wheels.evaluate(s, false, false, true)
			local t = math.clamp(deg / F.Gates.MaxSlipDegrees, 0, 1)
			local want = F.Smoke.RateMin + (F.Smoke.RateMax - F.Smoke.RateMin) * t
			ok = ok and math.abs(rate - want) < RATE_TOLERANCE
			table.insert(lines, string.format("%d deg: %.2f/s (want %.2f)", deg, rate, want))
		end
		check("smoke rate follows the configured lerp", ok, table.concat(lines, " | "))

		local _, floor = Wheels.evaluate(stateWith({ slipDeg = 0, speed = 60, throttle = 1 }), false, false, true)
		local _, ceiling = Wheels.evaluate(stateWith({ slipDeg = 180, speed = 60, throttle = 1 }), false, false, true)
		check(
			"and is bounded by RateMin and RateMax",
			math.abs(floor - F.Smoke.RateMin) < RATE_TOLERANCE and math.abs(ceiling - F.Smoke.RateMax) < RATE_TOLERANCE,
			string.format("%.2f .. %.2f per second", floor, ceiling)
		)
	end

	----------------------------------------------------------------------------
	-- 6. Airborne, and one wheel at a time
	----------------------------------------------------------------------------
	do
		local air = stateWith({ slipDeg = 90, speed = 100, throttle = 1, airborne = true })
		local airText, airFlags = emitting(air, true)
		local af, ar = count(airFlags)
		check(
			"airborne marks nothing, handbrake and full throttle and 90 deg of slip",
			af == 0 and ar == 0,
			airText
		)

		-- One rear wheel off the ground: that wheel alone stops marking.
		local oneUp = stateWith({ slipDeg = 60, speed = 60, throttle = 1, down = { true, true, false, true } })
		local oneText, oneFlags = emitting(oneUp, false)
		check(
			"a wheel off the ground stops marking, and only that wheel",
			oneFlags[1] and oneFlags[2] and not oneFlags[3] and oneFlags[4],
			oneText
		)
	end

	----------------------------------------------------------------------------
	-- 7. THE LEAN, which is the bug the user found. Pure.
	--
	-- `Drift/Render` rolls the Body about the centre of mass, the attachments are children
	-- of the Body, and `Marks.Lift` is five hundredths of a stud. The roll was putting the
	-- outside patch most of a stud out of place and the mark with it.
	----------------------------------------------------------------------------
	do
		local com = Config.Drift.CenterOfMass
		-- The patch the real car uses, at the outside rear corner.
		local offsets = CarModel.wheelOffsets()
		local radius = Config.Drift.WheelDiameter * 0.5
		local patch = offsets.WheelRR - Vector3.new(0, radius - F.Marks.Lift, 0)
			+ Vector3.new(F.Marks.Width * 0.5, 0, 0)
		local left = Vector3.new(-patch.X, patch.Y, patch.Z)

		-- What the OLD code did: the flat patch, rolled forward by the body.
		local maxRollDeg = Config.Drift.BodyRollMax
		local r = math.rad(maxRollDeg)
		local c, s = math.cos(r), math.sin(r)
		local wasRight = Wheels.applyRoll(patch, com, c, s).Y - patch.Y
		local wasLeft = Wheels.applyRoll(left, com, c, s).Y - left.Y
		check(
			"the body's lean really did move the contact patches further than Marks.Lift",
			math.min(math.abs(wasRight), math.abs(wasLeft)) > F.Marks.Lift,
			string.format(
				"at the full %g deg of BodyRollMax: outside %+0.3f studs, inside %+0.3f studs, against %g of lift",
				maxRollDeg, wasRight, wasLeft, F.Marks.Lift
			)
		)

		-- And what it does now: the written position, rolled forward, lands back on the
		-- flat patch. Swept across the whole roll range and both sides.
		local worst, worstAt = 0, 0
		for deg = -maxRollDeg, maxRollDeg, 0.25 do
			local rr = math.rad(deg)
			local cc, ss = math.cos(rr), math.sin(rr)
			for _, p in { patch, left } do
				local back = Wheels.applyRoll(Wheels.patchLocal(p, com, cc, ss), com, cc, ss)
				local err = (back - p).Magnitude
				if err > worst then
					worst, worstAt = err, deg
				end
			end
		end
		-- A QUARTER OF A MICRON IS EXACT. The tolerance is not 1e-9 because `Vector3` is
		-- single-precision: the round trip is algebraically exact and what is left is the
		-- float, measured at 2.4e-7 studs across the whole sweep.
		check(
			"cancelling the lean is exact across the whole roll range",
			worst < 1e-5,
			string.format("worst residual %.2e studs, at %+g deg of roll -- a Vector3 is a float32",
				worst, worstAt)
		)
	end

	----------------------------------------------------------------------------
	-- 8. TYRE HEAT, which drives the stylized smoke. Pure.
	----------------------------------------------------------------------------
	do
		local H = F.Heat
		-- Cold to hot at full slip speed, in about RiseSeconds.
		local heat, t, dt = 0, 0, 1 / 60
		while heat < 1 and t < H.RiseSeconds * 3 do
			heat = Wheels.heatStep(heat, true, H.FullSlipSpeed, dt)
			t += dt
		end
		check(
			"a wheel heats to full in about Heat.RiseSeconds at full slip speed",
			math.abs(t - H.RiseSeconds) < 0.1,
			string.format("%.2f s against a configured %g", t, H.RiseSeconds)
		)

		-- Half the slip speed, about twice as long: the rise is scaled by how hard it is
		-- sliding, not by a stopwatch.
		local half, th = 0, 0
		while half < 1 and th < H.RiseSeconds * 6 do
			half = Wheels.heatStep(half, true, H.FullSlipSpeed * 0.5, dt)
			th += dt
		end
		check(
			"half the slip speed takes about twice as long to heat",
			math.abs(th - H.RiseSeconds * 2) < 0.15,
			string.format("%.2f s against %.2f expected", th, H.RiseSeconds * 2)
		)

		-- And it cools in FallSeconds once the wheel stops sliding.
		local cool, tc = 1, 0
		while cool > 0 and tc < H.FallSeconds * 3 do
			cool = Wheels.heatStep(cool, false, 0, dt)
			tc += dt
		end
		check(
			"and cools to nothing in about Heat.FallSeconds",
			math.abs(tc - H.FallSeconds) < 0.1 and cool == 0,
			string.format("%.2f s against a configured %g, ending at %.3f", tc, H.FallSeconds, cool)
		)
		check(
			"heat is clamped at both ends",
			Wheels.heatStep(1, true, 1000, 10) == 1 and Wheels.heatStep(0, false, 0, 10) == 0,
			"1 stays 1 under ten seconds of slide, 0 stays 0 under ten of rest"
		)

		-- A WHEEL WHOSE GATE IS OPEN BUT WHICH IS NOT WORKING MUST STILL COOL. This is
		-- the stuck-hot case, measured live: a car that has caught a slide and rolled to a
		-- crawl keeps a few degrees of residual slip, so its rear gates stay open at a
		-- slip speed of about 0.1 studs/s and the heat sat at 0.56 four seconds after the
		-- drift had ended.
		local stuck, ts = 1, 0
		while stuck > 0 and ts < H.FallSeconds * 3 do
			stuck = Wheels.heatStep(stuck, true, H.IdleSlipSpeed * 0.1, dt) -- gate OPEN
			ts += dt
		end
		check(
			"a wheel sliding at a crawl cools, however open its gates are",
			stuck == 0 and math.abs(ts - H.FallSeconds) < 0.1,
			string.format("gates open at %.1f studs/s of drag: cold in %.2f s", H.IdleSlipSpeed * 0.1, ts)
		)
		check(
			"and the idle floor is far below the slip speed of a real slide",
			H.IdleSlipSpeed < H.FullSlipSpeed * 0.1,
			`idle floor {H.IdleSlipSpeed} studs/s against a full-rate {H.FullSlipSpeed}`
		)

		-- The stylized layer is driven by that heat, and starts at nothing.
		check(
			"the stylized layer starts at nothing and tops out at RateMax",
			math.abs(Wheels.stylizedRate(0) - F.Stylized.RateMin) < 1e-9
				and math.abs(Wheels.stylizedRate(1) - F.Stylized.RateMax) < 1e-9
				and Wheels.stylizedRate(0.5) > Wheels.stylizedRate(0.2),
			string.format("cold %.1f/s, half %.1f/s, hot %.1f/s",
				Wheels.stylizedRate(0), Wheels.stylizedRate(0.5), Wheels.stylizedRate(1))
		)


		-- THE SLIP GATE IS STICKY, and it survives the darkness rollback: a gate that
		-- chatters is a hole in the mark whether or not a darkness ramp exists. Measured
		-- live before it was there: a car at 44 studs/s with its slip hovering on half a
		-- degree switched its rear marks on and off, and every one of those is a break.
		local between = (F.Gates.MinSlipDegrees + F.Gates.StopSlipDegrees) * 0.5
		local cold = Wheels.evaluate(stateWith({ slipDeg = between, speed = 44, throttle = 1 }), false, false, true, false)
		local warm = Wheels.evaluate(stateWith({ slipDeg = between, speed = 44, throttle = 1 }), false, false, true, true)
		check(
			"the slip gate is sticky: between the two thresholds it holds whatever it was",
			not cold and warm,
			string.format("%.3f deg is between start %g and stop %g: not marking -> %s, already marking -> %s",
				between, F.Gates.MinSlipDegrees, F.Gates.StopSlipDegrees, tostring(cold), tostring(warm))
		)
		check(
			"and the stop threshold really is the lower of the two",
			F.Gates.StopSlipDegrees < F.Gates.MinSlipDegrees and F.Gates.StopSlipDegrees > 0,
			`start {F.Gates.MinSlipDegrees} deg, stop {F.Gates.StopSlipDegrees} deg`
		)

		-- And it does not chatter when the slip sits on the start threshold.
		local marking, chatters = false, 0
		for i = 1, 300 do
			local jitter = F.Gates.MinSlipDegrees + (if i % 2 == 0 then 0.08 else -0.08)
			local now = Wheels.evaluate(stateWith({ slipDeg = jitter, speed = 44, throttle = 1 }), false, false, true, marking)
			if now ~= marking then
				chatters += 1
			end
			marking = now
		end
		check(
			"a slip angle jittering on the gate does not chatter the mark on and off",
			chatters <= 1,
			`{chatters} changes over 300 frames of jitter either side of {F.Gates.MinSlipDegrees} deg`
		)
		-- T-151: pulling away from rest lays nothing, but a slide already marking keeps on.
		local launch = stateWith({ slipDeg = 8, speed = F.Gates.MinMarkSpeed - 0.5, throttle = 1 })
		check(
			"pulling away from rest does not start a mark, but a mark already down carries on",
			not Wheels.evaluate(launch, false, false, true, false) and Wheels.evaluate(launch, false, false, true, true),
			`8 deg at {F.Gates.MinMarkSpeed - 0.5} studs/s, under MinMarkSpeed {F.Gates.MinMarkSpeed}`
		)
		check(
			"a car running dead straight still marks nothing, sticky gate or not",
			not Wheels.evaluate(stateWith({ slipDeg = 0.09, speed = 110, throttle = 1 }), false, false, true, true),
			`0.09 deg -- what a straight car actually reads -- against a stop threshold of {F.Gates.StopSlipDegrees}`
		)
	end

	----------------------------------------------------------------------------
	-- 9. IT ALLOCATES NOTHING. Not pure: it builds a stand-in car.
	----------------------------------------------------------------------------
	if opts.skipInstances ~= true then
		local rig, car = standInRig()
		-- The grass ribbon is built in its own thread (making a mesh yields): wait for it.
		local w = Wheels.new(ServerStorage)
		local waitUntil = os.clock() + 15
		while not w:Ready() and not w.marks.failed and os.clock() < waitUntil do
			task.wait()
		end
		local attached = w:Attach(rig)
		local want = #CarModel.WHEEL_NAMES * Wheels.perWheel()
		local before = w:CountInstances()
		local bodyBefore = #rig.body:GetDescendants()
		check(
			`a rig gets exactly {want} instances, once`,
			attached and before == want and bodyBefore == want,
			`attached {attached}, counted {before}, under the body {bodyBefore}`
		)

		-- A second Attach on the same body must build nothing.
		w:Attach(rig)
		check("attaching again builds nothing", w:CountInstances() == want, `{w:CountInstances()} instances`)

		-- T-207: measure capped natural width ACROSS THE ACTUAL CONTACT PATH.
		-- The former body-X span still measured Width end-to-end while shrinking to
		-- Width*cos(slip) on the road. Preserve that thinning only down to MinWidthRatio.
		-- Use coherent world velocity and Render.apply
		-- so suspension, banking, yaw and the renderer's remainder are all exercised.
		rig.lift = {}
		local widthError, centreError, emitterError, planeError, diagnosticError, flips = 0, 0, 0, 0, 0, 0
		local geometryFrames = 0
		local function geometry(s, steps, remA, remB, change)
			w:Cut()
			local previous, spans, acrosses = {}, {}, {}
			for frame = 1, steps do
				if change then change(s, frame) end
				if frame > 1 then
					s.position += s.velocity / 60
					s.yaw += s.r / 60
				end
				local rem = if frame % 2 == 0 then remB else remA
				Render.apply(rig, s, rem)
				w:Update(s, { handbrake = true }, 1 / 60)
				local road = Render.pose(s, rem)
				for _, debugWheel in w:DebugState(s, { handbrake = true }).wheels do
					diagnosticError = math.max(diagnosticError, math.abs(debugWheel.patchResidualY))
				end
				for _, wheel in w.wheels do
					local lift = Vector3.new(0, s.wheelLift[wheel.index], 0)
					local expected = road:PointToWorldSpace((wheel.patchA + wheel.patchB) * 0.5 + lift)
					local actual = (wheel.markA + wheel.markB) * 0.5
					centreError = math.max(centreError, (actual - expected).Magnitude)
					for _, pair in { { wheel.sourceA, wheel.patchA }, { wheel.sourceB, wheel.patchB }, { wheel.sourceC, wheel.patchC } } do
						emitterError = math.max(emitterError, (pair[1].WorldPosition - road:PointToWorldSpace(pair[2] + lift)).Magnitude)
					end
					local path = if previous[wheel.index] then expected - previous[wheel.index] else s.velocity
					path -= s.groundUp * path:Dot(s.groundUp)
					local span = wheel.markB - wheel.markA
					planeError = math.max(planeError, math.abs(span:Dot(s.groundUp)))
					local across
					if path.Magnitude > 1e-4 then
						across = path.Unit:Cross(s.groundUp).Unit
						acrosses[wheel.index] = across
					else
						across = acrosses[wheel.index] or road.RightVector
					end
					-- The former body-X ribbon projected across this measured path is the
					-- natural width. Retain it above the floor; sideways must not collapse.
					local natural = math.abs(road:VectorToWorldSpace(Vector3.xAxis):Dot(across))
					local ratio = math.max(F.Marks.MinWidthRatio, natural)
					-- Ignore the first yawing frame's instantaneous fallback vs chord.
					if frame > 1 or s.r == 0 then
						widthError = math.max(widthError, math.abs(math.abs(span:Dot(across)) - F.Marks.Width * ratio))
					end
					if spans[wheel.index] and span:Dot(spans[wheel.index]) < -1e-5 then flips += 1 end
					previous[wheel.index], spans[wheel.index] = expected, span
					geometryFrames += 1
				end
			end
		end
		for _, profile in { 0, 1, 2 } do
			local banked = profile > 0
			for _, deg in { 0, -45, 45, -60, 60, -89.9, 89.9, -90, 90, -135, 135 } do
				local s = stateWith({ slipDeg = deg, speed = 70, throttle = 1, rollDeg = if banked then 10 else 0 })
				s.up = if banked then Vector3.new(0.25, 1, -0.15).Unit else Vector3.yAxis
				s.groundUp = if profile == 2 then Vector3.new(0.1, 1, -0.05).Unit else s.up
				local f, right = Suspension.basis(s.yaw, s.groundUp)
				s.velocity = (f * math.cos(s.slip) - right * math.sin(s.slip)) * 70
				if banked then s.body.z, s.body.p, s.body.q = 0.3, math.rad(8), math.rad(-6) end
				s.wheelLift = if banked then { 0.1, -0.2, 0.3, -0.1 } else { 0, 0, 0, 0 }
				geometry(s, 3, 0, 0)
				s.r = if deg < 0 then -1.2 else 1.2
				geometry(s, 6, 0.001, 0.007)
			end
		end
		local stopped = stateWith({ speed = 0, throttle = 1 })
		stopped.wheelLift = { 0, 0, 0, 0 }
		geometry(stopped, 3, 0, 0)
		geometry(stopped, 12, 0, 0, function(s, frame)
			local deg = ({ -90, -60, -45, 0, 45, 60, 89.9, 90, 135, -45, -45, -45 })[frame]
			s.slip = math.rad(deg)
			s.u = if frame == 11 then 0 else if frame == 12 then 1e-8 else 70
			s.velocity = Vector3.new(-math.sin(s.slip), 0, -math.cos(s.slip)) * s.u
		end)
		check(
			"marks retain natural thinning across the actual path with the configured sideways floor",
			widthError < 1e-4 and planeError < 1e-4,
			string.format("%d wheel-frames; max cross-path width error %.2e, out-of-plane %.2e studs; natural 60deg %.3f studs; sideways floor %.3f",
				geometryFrames, widthError, planeError, F.Marks.Width * math.cos(math.rad(60)), F.Marks.Width * F.Marks.MinWidthRatio)
		)
		check(
			"turning mark spans preserves patch centres and fixed smoke/debris sources",
			centreError < 1e-4 and emitterError < 1e-4 and diagnosticError < 1e-4,
			string.format("max patch-centre error %.2e, particle-source error %.2e, diagnostic residual %.2e studs", centreError, emitterError, diagnosticError)
		)
		local angleError, floorError = 0, 0
		for _, deg in { 0, -45, 45, -60, 60, -75, 75, -89.9, 89.9, -90, 90 } do
			w:Cut()
			local s = stateWith({ slipDeg = deg, speed = 70, throttle = 1 })
			s.velocity = Vector3.new(-math.sin(s.slip), 0, -math.cos(s.slip)) * 70
			Render.apply(rig, s)
			w:Update(s, { handbrake = true }, 1 / 60)
			local expected = math.max(math.abs(math.cos(math.rad(deg))), F.Marks.MinWidthRatio)
			for _, wheel in w.wheels do
				local width = (wheel.markB - wheel.markA).Magnitude
				angleError = math.max(angleError, math.abs(width - F.Marks.Width * expected))
				if math.abs(deg) == 90 then
					floorError = math.max(floorError, math.abs(width - F.Marks.Width * F.Marks.MinWidthRatio))
				end
			end
		end
		check("flat marks follow the natural angle curve and bottom out at one quarter width",
			angleError < 1e-4 and floorError < 1e-4 and F.Marks.MinWidthRatio == 0.25,
			string.format("angle error %.2e, sideways floor error %.2e studs; width %.2f -> %.2f, grass mark %.2f -> %.3f",
				angleError, floorError, F.Marks.Width, F.Marks.Width * F.Marks.MinWidthRatio,
				F.Ground.Grass.Width, F.Ground.Grass.Width * F.Marks.MinWidthRatio))
		check("mark endpoints stay ordered through turns and rest fallback", flips == 0, `{flips} endpoint flips`)
		w:Cut()

		local function litTrails(): (number, number)
			local lit, maxPerWheel = 0, 0
			for _, wheel in w.wheels do
				local here = 0
				-- Both ribbons count: rubber or scuff (T-269), flattened grass or rut (T-265).
				if w.rubber:Kind(wheel.index) then
					here += 1
				end
				if w.marks:Kind(wheel.index) then
					here += 1
				end
				lit += here
				maxPerWheel = math.max(maxPerWheel, here)
			end
			return lit, maxPerWheel
		end

		-- Now drive it. The slip angle sweeps the whole range and back, the speed sweeps
		-- with it, the throttle and the handbrake are toggled, and wheels leave the ground
		-- -- so every gate flips many times over the thousand frames.
		--
		-- `blank` is the number that mattered when there was a darkness ladder and still
		-- matters now: a frame in which a wheel is MARKING but nothing is drawn is a hole
		-- in the mark. With one trail per wheel there is nothing left that can cause one.
		local flips, lastOn, worstPerWheel, blank = 0, false, 0, 0
		for frame = 1, FRAMES do
			local t = frame / FRAMES
			local deg = 180 * math.abs(math.sin(t * math.pi * 7))
			local s = stateWith({
				slipDeg = deg,
				speed = 20 + 100 * math.abs(math.cos(t * math.pi * 3)),
				throttle = if frame % 7 == 0 then 0 else 1,
				airborne = frame % 97 == 0,
				rollDeg = Config.Drift.BodyRollMax * math.sin(t * math.pi * 5),
				-- and the ground changes under it (T-188), one wheel at a time
				surface = {
					({ "tarmac", "grass", "gravel" })[(frame // 37) % 3 + 1],
					({ "tarmac", "grass", "gravel" })[(frame // 41) % 3 + 1],
					({ "tarmac", "grass", "gravel" })[(frame // 43) % 3 + 1],
					({ "tarmac", "grass", "gravel" })[(frame // 47) % 3 + 1],
				},
			})
			w:Update(s, { handbrake = frame % 53 == 0 }, 1 / 60)
			local on = w.wheels[1].marking
			if on ~= lastOn then
				flips += 1
				lastOn = on
			end
			local _, perWheel = litTrails()
			worstPerWheel = math.max(worstPerWheel, perWheel)
			for _, wheel in w.wheels do
				local drawn = w.marks:Kind(wheel.index) ~= nil or w.rubber:Kind(wheel.index) ~= nil
				if wheel.marking and not drawn then
					blank += 1
				end
			end
		end
		local after = w:CountInstances()
		local bodyAfter = #rig.body:GetDescendants()
		check(
			`{FRAMES} frames of driving create and destroy nothing`,
			after == before and bodyAfter == bodyBefore,
			`before {before}, after {after}; under the body {bodyBefore} -> {bodyAfter}; {flips} gate flips in those frames`
		)
		-- Only one trail may emit per wheel, including green versus brown on grass.
		check(
			"never more than one of a wheel's trails drawing",
			worstPerWheel <= 1,
			`worst was {worstPerWheel} at once`
		)
		-- AND THE BAR THE LADDER WAS REMOVED OVER: never a frame in which a wheel is
		-- marking and nothing is drawn.
		check(
			"and never a frame where a marking wheel draws nothing",
			blank == 0,
			`{blank} blank frames over {FRAMES} frames x {#CarModel.WHEEL_NAMES} wheels`
		)

		-- The heat is per wheel, and the fronts and the rears do not share it: through a
		-- small slide only the rears are sliding, so only the rears heat up.
		w:Cut()
		local small = stateWith({ slipDeg = 15, speed = 70, throttle = 1 })
		for _ = 1, 120 do
			w:Update(small, { handbrake = false }, 1 / 60)
		end
		local frontHeat, rearHeat = 0, 0
		for _, wheel in w.wheels do
			if wheel.front then
				frontHeat = math.max(frontHeat, wheel.heat)
			else
				rearHeat = math.max(rearHeat, wheel.heat)
			end
		end
		check(
			"heat is per wheel: through a small slide the rears heat and the fronts do not",
			rearHeat > 0.1 and frontHeat == 0,
			string.format("after 2 s at 15 deg -- rears %.3f, fronts %.3f", rearHeat, frontHeat)
		)

		-- And it decays once the wheel stops sliding.
		local straight = stateWith({ slipDeg = 0, speed = 70, throttle = 1 })
		local hot = rearHeat
		for _ = 1, 120 do
			w:Update(straight, { handbrake = false }, 1 / 60)
		end
		local cooled = 0
		for _, wheel in w.wheels do
			cooled = math.max(cooled, wheel.heat)
		end
		check(
			"and it decays when that wheel stops sliding",
			cooled < hot,
			string.format("%.3f after the slide, %.3f two seconds later", hot, cooled)
		)

		-- Cut and the switch both turn everything off without touching an instance count.
		local lit = stateWith({ slipDeg = 90, speed = 80, throttle = 1 })
		w:Update(lit, { handbrake = false }, 1 / 60)
		local anyOn = litTrails() > 0
		w:Cut()
		local anyAfterCut, coldAfterCut = litTrails() > 0, true
		for _, wheel in w.wheels do
			coldAfterCut = coldAfterCut and wheel.heat == 0
			for _, fx in wheel.fx do
				anyAfterCut = anyAfterCut or fx.diffuse.Enabled or fx.stylized.Enabled
			end
		end
		check(
			"Cut puts everything out, and puts the tyres back cold",
			anyOn and not anyAfterCut and coldAfterCut,
			`lit {anyOn}, after Cut {anyAfterCut}, all cold {coldAfterCut}`
		)

		w:SetEnabled(false)
		w:Update(lit, { handbrake = true }, 1 / 60)
		local anyWhileOff = litTrails() > 0
		for _, wheel in w.wheels do
			for _, fx in wheel.fx do
				anyWhileOff = anyWhileOff or fx.diffuse.Enabled or fx.stylized.Enabled
			end
		end
		check(
			"SetEnabled(false) is a real switch, and destroys nothing",
			not anyWhileOff and w:CountInstances() == want,
			`emitting {anyWhileOff}, instances {w:CountInstances()}`
		)
		w:SetEnabled(true)

		------------------------------------------------------------------------
		-- 9b. OFF THE ROAD (T-188): the smoke fades, the grass tears up.
		------------------------------------------------------------------------
		local G = F.Ground
		local DT = 1 / 60
		w:Cut()
		-- A rear wheel (RL) on tarmac at 20 deg -- smoking -- then all four go on grass.
		local rl
		for _, wheel in w.wheels do
			if wheel.name == CarModel.WHEEL_NAMES[3] then
				rl = wheel
			end
		end
		local tarmac20 = stateWith({ slipDeg = 20, speed = 70, throttle = 1, surface = "tarmac" })
		for _ = 1, 30 do
			w:Update(tarmac20, { handbrake = false }, DT)
		end
		local smokeBefore = rl.fx[1].diffuse.Rate
		local grass20 = stateWith({ slipDeg = 20, speed = 70, throttle = 1, surface = "grass" })
		local clodsBefore20 = w.debris:DebugState().spawned
		local framesToZero, halfway = nil, nil
		for frame = 1, 60 do
			w:Update(grass20, { handbrake = false }, DT)
			if frame == 6 then
				halfway = rl.fx[1].diffuse.Rate
			end
			if not framesToZero and not rl.fx[1].diffuse.Enabled then
				framesToZero = frame
			end
		end
		local wantFrames = math.ceil(G.FadeSeconds / DT)
		check(
			"on grass the smoke FADES out over FadeSeconds, not a cut",
			smokeBefore > 0
				and halfway ~= nil
				and halfway > 0
				and halfway < smokeBefore
				and framesToZero ~= nil
				and math.abs(framesToZero - wantFrames) <= 1,
			string.format(
				"rate %.2f on tarmac, %.2f after 0.1 s on grass, off after %s frames (want %d = %.2f s)",
				smokeBefore,
				halfway or -1,
				tostring(framesToZero),
				wantFrames,
				G.FadeSeconds
			)
		)
		check(
			"at a low angle on grass: the flat grass line, the grass spray and its cloud, no trench, no clods",
			w.marks:Kind(rl.index) == "flat"
				and w.rubber:Kind(rl.index) == nil
				and rl.ground.clippings.emitter.Enabled
				and rl.ground.spray.emitter.Enabled
				and math.abs(rl.ground.spray.emitter.Rate - Wheels.kickRate(G.Grass.Spray, 20) * rl.mixGrass) < 1e-6
				and w.debris:DebugState().spawned == clodsBefore20,
			string.format("clippings %.1f/s, spray %.1f/s, mix %.2f", rl.ground.clippings.emitter.Rate, rl.ground.spray.emitter.Rate, rl.mixGrass)
		)
		-- Past the trench threshold: brown replaces green, and the clods fly (T-205, T-283).
		local grass45 = stateWith({ slipDeg = 45, speed = 70, throttle = 1, surface = "grass" })
		for _ = 1, 60 do
			w:Update(grass45, { handbrake = false }, DT)
		end
		local d = w.debris:DebugState()
		check(
			"at a high angle on grass: only the trench, and low-poly clods (built-in wedges) are thrown",
			w.marks:Kind(rl.index) == "rut"
				and d.ready and d.live > 0 and d.pool == G.Chunks.Pool
				and d.triangles <= 30
				and #w.debris.folder:GetDescendants() == G.Chunks.Pool -- no meshes: built-in wedges
				and #w.debris.folder:GetChildren() == G.Chunks.Pool,
			string.format(
				"%d clods out of %d (%d in the air), %d thrown in a second; %d shapes of %d triangles; grass spray %.1f/s",
				d.live, d.pool, d.flying, d.spawned, d.shapes, d.triangles, rl.ground.clippings.emitter.Rate
			)
		)
		check(
			"the grass spray is streaked along its flight, from under the middle of the wheel",
			rl.ground.clippings.emitter.Orientation == Enum.ParticleOrientation.VelocityParallel
				and G.Grass.DebrisOffset == 0 and G.Grass.Clippings.RateMax <= 100,
			`{rl.ground.clippings.emitter.Orientation.Name}, offset {G.Grass.DebrisOffset}`
		)
		-- Hysteresis: 27 deg keeps the trench (stop is 25), 24 drops it.
		w:Update(stateWith({ slipDeg = 27, speed = 70, throttle = 1, surface = "grass" }), { handbrake = false }, DT)
		local held = w.marks:Kind(rl.index) == "rut"
		w:Update(stateWith({ slipDeg = 24, speed = 70, throttle = 1, surface = "grass" }), { handbrake = false }, DT)
		local dropped = w.marks:Kind(rl.index) == "flat"
		check(
			"the trench has hysteresis, and green resumes only after it ends",
			held and dropped and Wheels.trenchOn(30, false) and not Wheels.trenchOn(29.9, false),
			`brown only at 27 {held}, green only at 24 {dropped}`
		)
		-- T-205: exercise both switch directions on every wheel, including the fronts
		-- forced to mark at low slip by the handbrake. Check actual Trail.Enabled too,
		-- not just the trench state: the old layering passed hysteresis on its own.
		w:Cut()
		local exclusive, snapshots, grassFrames, doubles = true, {}, 0, 0
		for _, sample in {
			{ 20, false }, { 29.9, false }, { 30.1, true }, { 45, true },
			{ 29.9, true }, { 27, true }, { 25.1, true }, { 24.9, false },
			{ 27, false }, { 30.1, true }, { 24, false },
		} do
			local s = stateWith({ slipDeg = sample[1], speed = 70, throttle = 1, surface = "grass" })
			w:Update(s, { handbrake = true }, DT)
			local snapshot = w:DebugState(s, { handbrake = true })
			for _, wheel in snapshot.wheels do
				grassFrames += 1
				if wheel.grassMark and wheel.trenchMark then
					doubles += 1
				end
				exclusive = exclusive and wheel.emitting and wheel.lit == 1
					and wheel.trenchMark == sample[2] and wheel.grassMark == not sample[2]
			end
			table.insert(snapshots, `{sample[1]}:{if sample[2] then "brown" else "green"}`)
		end
		check(
			"each grass-marking wheel emits exactly one colour through both hysteresis crossings",
			exclusive,
			`{grassFrames} wheel-frames, {doubles} doubles; {table.concat(snapshots, ", ")}`
		)
		-- The dirt is a smooth ramp, not a step.
		local shares = {}
		for _, deg in { G.Grass.DirtStartDegrees, 26, 31, 36, G.Grass.DirtFullDegrees } do
			table.insert(shares, Wheels.dirtShare(deg))
		end
		local rising = true
		for i = 2, #shares do
			rising = rising and shares[i] > shares[i - 1]
		end
		check(
			"the dirt blends in: 0 at its start, 1 at its full, rising between",
			shares[1] == 0 and shares[#shares] == 1 and rising,
			fmtList(shares)
		)
		-- Back on tarmac: the debris fades out, the smoke fades back in.
		local back = stateWith({ slipDeg = 45, speed = 70, throttle = 1, surface = "tarmac" })
		w:Update(back, { handbrake = false }, DT)
		local smokeIn1 = rl.fx[1].diffuse.Rate
		local clipStill = rl.ground.clippings.emitter.Enabled
		for _ = 1, 30 do
			w:Update(back, { handbrake = false }, DT)
		end
		local full = select(2, Wheels.evaluate(back, false, false, true, true))
		check(
			"back on tarmac the smoke fades IN and the grass fades out",
			smokeIn1 > 0
				and smokeIn1 < full * 0.2
				and clipStill
				and math.abs(rl.fx[1].diffuse.Rate - full) < 1e-6
				and not rl.ground.clippings.emitter.Enabled
				and not rl.ground.spray.emitter.Enabled
				and w.rubber:Kind(rl.index) == "rubber"
				and w.marks:Kind(rl.index) == nil,
			string.format("smoke %.2f one frame back, %.2f half a second later (full %.2f)", smokeIn1, rl.fx[1].diffuse.Rate, full)
		)
		-- Per wheel: two wheels on grass, two on tarmac.
		w:Cut()
		local split = stateWith({ slipDeg = 60, speed = 70, throttle = 1, surface = { "tarmac", "grass", "tarmac", "grass" } })
		for _ = 1, 30 do
			w:Update(split, { handbrake = false }, DT)
		end
		local perWheelOk, line = true, {}
		for _, wheel in w.wheels do
			local onGrass = wheel.index == 2 or wheel.index == 4
			local smoking = wheel.fx[1].diffuse.Enabled
			local kicking = wheel.ground.clippings.emitter.Enabled
			perWheelOk = perWheelOk and smoking == not onGrass and kicking == onGrass
			table.insert(line, `{wheel.name}: smoke {smoking} grass {kicking}`)
		end
		check("each wheel reads its own ground", perWheelOk, table.concat(line, "; "))
		-- Gravel: dust, a scuff, no smoke.
		local gravel = stateWith({ slipDeg = 40, speed = 70, throttle = 1, surface = "gravel" })
		for _ = 1, 30 do
			w:Update(gravel, { handbrake = false }, DT)
		end
		check(
			"on gravel: a scuff mark and dust, no smoke, no grass",
			w.rubber:Kind(rl.index) == "scuff"
				and rl.ground.dust.emitter.Enabled
				and not rl.fx[1].diffuse.Enabled
				and not rl.ground.clippings.emitter.Enabled
				and not rl.ground.spray.emitter.Enabled,
			string.format("dust %.1f/s", rl.ground.dust.emitter.Rate)
		)
		-- T-283: the clods land, sink and go back to the pool, and none are made after the first.
		w:Cut()
		local before = w.debris:DebugState().spawned
		for _ = 1, 30 do
			w:Update(grass45, { handbrake = false }, DT)
		end
		local thrown = w.debris:DebugState().spawned - before
		local tarmacHard = stateWith({ slipDeg = 45, speed = 70, throttle = 1, surface = "tarmac" })
		for _ = 1, math.ceil(G.Chunks.Lifetime[2] / DT) + 5 do
			w:Update(tarmacHard, { handbrake = false }, DT)
		end
		local after = w.debris:DebugState()
		check(
			"clods land, sink and go back to the pool, and none are made after the first",
			thrown > 0 and after.live == 0 and #w.debris.folder:GetChildren() == G.Chunks.Pool,
			`{thrown} thrown in half a second; {after.live} still out after {G.Chunks.Lifetime[2]} s; {#w.debris.folder:GetChildren()} parts`
		)
		w:Cut()
		check(
			"a hit with no name is the default surface",
			Wheels.surfaceOf(stateWith({ surface = "" }), 1, true) == F.Default
				and Wheels.surfaceOf(stateWith({ surface = "grass" }), 1, true) == "grass"
				and Wheels.surfaceOf(stateWith({ surface = "grass" }), 1, false) == nil,
			"'' -> default, grass -> grass, not down -> nil"
		)

		------------------------------------------------------------------------
		-- 9c. RUTS CUT INTO THE GROUND (T-265): the grass marks are a lit mesh ribbon
		-- (`Drift/GroundMarks`) laid on the drawn ground: one strip a wheel, with soft ends,
		-- mitred joins, a shaped profile, a streak texture made in code, and an age.
		------------------------------------------------------------------------
		do
			local GG = G.Grass
			local RB = G.Ribbon
			local marks = w.marks
			local P = #GG.Profile * 2

			-- The texture: deterministic, opaque, streaked.
			local T = RB.Texture
			local px1 = GroundMarks.texturePixels(T)
			local px2 = GroundMarks.texturePixels(T)
			local same = buffer.len(px1) == T.Width * T.Height * 4 and buffer.tostring(px1) == buffer.tostring(px2)
			local alphaMin, greyLo, greyHi = 255, 255, 0
			for y = 0, T.Height - 1 do
				local row = y * T.Width * 4
				for x = 0, T.Width - 1 do
					alphaMin = math.min(alphaMin, buffer.readu8(px1, row + x * 4 + 3))
				end
				for x = T.Width // 4, 3 * T.Width // 4 do
					local gval = buffer.readu8(px1, row + x * 4)
					greyLo, greyHi = math.min(greyLo, gval), math.max(greyHi, gval)
				end
			end
			check(
				"the streak texture is made in code, the same every time, opaque and streaked",
				same and alphaMin == 255 and greyHi - greyLo > 40,
				string.format("%dx%d, identical twice %s; alpha at least %d; greys %d..%d across the middle",
					T.Width, T.Height, tostring(same), alphaMin, greyLo, greyHi)
			)

			-- Built once, inside the client's mesh budget: a strip a wheel, two parts each.
			local parts, scaleOk, dressed = 0, true, true
			if marks.folder then
				for _, part in marks.folder:GetChildren() do
					if part:IsA("MeshPart") then
						parts += 1
						scaleOk = scaleOk and math.abs(part.Size.X - 2000) < 1
						if part.Name:find("Inner$") then
							-- its streak texture: opaque content (T-274), or the EditableImage where that failed
							local tex = part.TextureContent
							local textured = if marks.image then tex.Object == marks.image else tex.SourceType == Enum.ContentSourceType.Opaque
							dressed = dressed and textured and part.Material == RB.InnerMaterial
						else
							dressed = dressed and part.Material == RB.OuterMaterial
						end
					end
				end
			end
			local made = #marks.folder:GetDescendants()
			local vertices = marks:DebugState().vertices
			check(
				"the ribbon is built once, two parts a wheel at scale 1, within the mesh budget",
				marks.ready and parts == RB.Wheels * 2 and scaleOk and dressed and vertices <= 4200
					and Wheels.perWheel() * #CarModel.WHEEL_NAMES + made + 1 + #w.rubber.folder:GetDescendants() + 1 == Wheels.perCar(),
				`ready {marks.ready} ({marks.failed or "ok"}); {parts} MeshParts; scale 1 {scaleOk}; materials and texture {dressed}; {vertices} mesh vertices; {Wheels.perCar()} a car`
			)

			-- A stand-in drawn ground: a tilted plane with long, gentle swells, so a point
			-- interpolated between two on the ground is on it too, near enough.
			local calls = 0
			local function groundY(x: number, z: number): number
				return 20 + 0.08 * x + 0.03 * z + 0.6 * math.sin(x * 0.05) + 0.4 * math.cos(z * 0.04)
			end
			local drawn = { _drawnAt = function(_, x: number, z: number): number
				calls += 1
				return groundY(x, z)
			end }
			local up = Vector3.yAxis
			local folderBefore = #marks.folder:GetDescendants()

			-- What must never be drawn: a quad stretched between sections that are not
			-- neighbours on one mark. Every pair of ring neighbours is either two sections of a
			-- mark within a segment's length, or touches a point -- and a point is either next
			-- to another point or sits on its neighbour's centre.
			local function stretched(strip, pp: number?): (number, number)
				local P = pp or P
				local worst, real = 0, 0
				local n = #strip
				for idx = 1, n do
					local a, b = strip[idx], strip[idx % n + 1]
					if a.real then
						real += 1
					end
					local function centre(s)
						return (s.points[1] + s.points[P]) * 0.5
					end
					local function isPoint(s)
						return (s.points[1] - s.points[P]).Magnitude < 1e-4
					end
					local gap
					if a.real and b.real and not isPoint(a) and not isPoint(b) then
						gap = (centre(b) - centre(a)).Magnitude - (RB.Spacing + 1)
					elseif isPoint(a) and isPoint(b) then
						gap = 0
					elseif isPoint(a) then
						gap = (a.points[1] - centre(b)).Magnitude
					else
						gap = (b.points[1] - centre(a)).Magnitude
					end
					worst = math.max(worst, gap)
				end
				return worst, real
			end

			-- Drive wheel 1 round a 40-stud arc at 50 studs/s, cutting a rut, then flat, then lift.
			GroundMarks.Clear(marks)
			local radius, speed, DT2 = 40, 50, 1 / 60
			local function at(t: number): (Vector3, Vector3)
				local a = speed * t / radius
				local x, z = radius * math.sin(a), radius * (1 - math.cos(a))
				local p = Vector3.new(x, groundY(x, z) + 0.5, z) -- the car's plane, half a stud up
				local tangent = Vector3.new(math.cos(a), 0, math.sin(a))
				return p, tangent:Cross(up)
			end
			local calls0 = calls
			for f = 0, 90 do
				local p, across = at(f * DT2)
				GroundMarks.Wheel(marks, 1, true, p, up, across, 1, f < 60, drawn, DT2)
				GroundMarks.Age(marks, DT2)
			end
			local lookupsPerFrame = (calls - calls0) / 91
			local depthAfterSwitch = marks.strips[1].depth
			local kindAfter = GroundMarks.Kind(marks, 1)
			GroundMarks.Wheel(marks, 1, false, at(91 * DT2), up, Vector3.xAxis, 1, false, drawn, DT2)
			-- And a second mark after a gap, so marks have to be kept apart too.
			for f = 120, 150 do
				local p, across = at(f * DT2)
				GroundMarks.Wheel(marks, 1, true, p, up, across, 1, true, drawn, DT2)
			end
			GroundMarks.Wheel(marks, 1, false, at(151 * DT2), up, Vector3.xAxis, 1, true, drawn, DT2)
			local strip = marks:DebugStrip(1)
			local worstStretch, realCount = stretched(strip)

			-- The first mark's sections, in order.
			local mark = {}
			for _, s in strip do
				if s.real and (s.points[1] - s.points[P]).Magnitude > 1e-4 then
					table.insert(mark, s)
				elseif #mark > 0 then
					break
				end
			end
			local edgeError, widthError, turnMax, spacingMax = 0, 0, 0, 0
			local lastDir
			for n, s in mark do
				local pts = s.points
				for _, j in { 1, P } do
					edgeError = math.max(edgeError, math.abs(pts[j].Y - (groundY(pts[j].X, pts[j].Z) + G.Lift)))
				end
				local wide = pts[P] - pts[1]
				widthError = math.max(widthError, math.abs(Vector3.new(wide.X, 0, wide.Z).Magnitude - GG.Width))
				if n > 1 then
					local c0 = (mark[n - 1].points[1] + mark[n - 1].points[P]) * 0.5
					local c1 = (pts[1] + pts[P]) * 0.5
					local d = Vector3.new(c1.X - c0.X, 0, c1.Z - c0.Z)
					spacingMax = math.max(spacingMax, d.Magnitude)
					if lastDir and d.Magnitude > 1e-3 then
						turnMax = math.max(turnMax, math.deg(math.acos(math.clamp(d.Unit:Dot(lastDir), -1, 1))))
					end
					if d.Magnitude > 1e-3 then
						lastDir = d.Unit
					end
				end
			end
			check(
				"the ribbon is one strip: no quad ever joins two marks, round a bend no steps",
				#mark > 10 and worstStretch < 1e-3 and turnMax <= RB.TurnDegrees * 1.6 and spacingMax <= RB.Spacing + speed * DT2 + 1e-3,
				string.format("%d sections in the first mark of two, %d real in the ring; worst stretch %.1e studs; sharpest joint %.1f deg; longest segment %.2f studs",
					#mark, realCount, worstStretch, turnMax, spacingMax)
			)
			check(
				"the ribbon lies on the drawn ground at its full width, three lookups a frame",
				edgeError < 2e-3 and widthError < 0.02 and lookupsPerFrame >= 3 and lookupsPerFrame < 3.5,
				string.format("edges %.1e studs off ground + Lift; width error %.3f studs of %.1f; %.2f lookups a frame",
					edgeError, widthError, GG.Width, lookupsPerFrame)
			)

			-- The shape: the rut's walls lean in, its berms stand up.
			local mid = mark[math.max(#mark // 3, 1)]
			local acrossDir = (mid.points[P] - mid.points[1]).Unit
			local floorL, floorR = P // 2, P // 2 + 1
			local leftWall, rightWall = mid.normals[floorL]:Dot(acrossDir), mid.normals[floorR]:Dot(acrossDir)
			local bermUp = mid.points[2].Y - (groundY(mid.points[2].X, mid.points[2].Z) + G.Lift) > 0.05
			check(
				"a rut's walls lean toward its centre, so one catches the light and the other is in shade",
				leftWall > 0.5 and rightWall < -0.5 and bermUp,
				string.format("left floor-edge normal %.2f across, right %.2f; berm raised %s", leftWall, rightWall, tostring(bermUp))
			)

			-- Soft ends: the mark comes in over its first sections and ends at nothing.
			local ramp = {}
			for n = 1, math.min(5, #mark) do
				table.insert(ramp, mark[n].showing)
			end
			local rising = true
			for n = 2, #ramp do
				rising = rising and ramp[n] >= ramp[n - 1]
			end
			local endShown = mark[#mark].showing
			local midShown = mid.showing
			check(
				"a mark fades in at its start and out at its end, and is solid between",
				ramp[1] == 0 and rising and endShown == 0 and midShown > 0.99,
				string.format("first sections show %s, its end %.2f, mid-rut %.2f", fmtList(ramp), endShown, midShown)
			)
			-- The edges ARE the ground: its colour and its normal, so there is no seam to see;
			-- the floor is the mark's own colour (the stand-in ground has no tiles, so its colour
			-- is the runoff's grass).
			local grass = Config.Spline.Terrain.GrassColour
			local function gap(a: Color3, b: Color3): number
				return math.max(math.abs(a.R - b.R), math.abs(a.G - b.G), math.abs(a.B - b.B))
			end
			local edgeGap = math.max(gap(mid.colours[1], grass), gap(mid.colours[P], grass))
			local edgeTilt = math.max(1 - mid.normals[1]:Dot(up), 1 - mid.normals[P]:Dot(up))
			local floorGap = gap(mid.colours[floorL], GG.TrenchMark.Points[#GG.Profile].Colour)
			check(
				"a mark's edges are drawn as the ground is, and its floor as the mark",
				edgeGap < 1e-3 and edgeTilt < 1e-4 and floorGap < 0.06,
				string.format("edge colour %.4f off the ground's, normal %.1e off; floor %.3f off the rut colour (ageing has begun)", edgeGap, edgeTilt, floorGap)
			)
			check(
				"rut to flattened line blends over BlendSeconds, never both at once",
				kindAfter == "flat" and depthAfterSwitch < 1e-6,
				string.format("look after the switch %s, blend %.2f after %.2f s (BlendSeconds %.2f)", tostring(kindAfter), depthAfterSwitch, 30 * DT2, RB.BlendSeconds)
			)

			-- Ageing: it dries and fades, and goes when its life is up.
			local function shownAt(k: number): number
				for _, s in marks:DebugStrip(1) do
					if s.k == k then
						return s.showing
					end
				end
				return -1
			end
			local a0 = shownAt(mid.k)
			GroundMarks.Age(marks, G.MarkSeconds * 0.85)
			local a1 = shownAt(mid.k)
			local liveMid = marks:LiveCount()
			GroundMarks.Age(marks, G.MarkSeconds * 0.2)
			local liveEnd = marks:LiveCount()
			local afterWorst = stretched(marks:DebugStrip(1))
			check(
				"laid marks fade with age and go when their life is up, leaving nothing stretched",
				a1 < a0 * 0.6 and liveMid > 0 and liveEnd == 0 and afterWorst < 1e-3,
				string.format("showing %.2f fresh, %.2f at 85%% of %.0f s; %d sections then, %d after; worst stretch %.1e",
					a0, a1, G.MarkSeconds, liveMid, liveEnd, afterWorst)
			)

			-- No ground drawn, or too far to reach: the points stay on the car's plane.
			local far = { _drawnAt = function(_, x: number, z: number): number
				return groundY(x, z) + G.MaxSnap + 2
			end }
			local planeError = 0
			for _, ground in { far, false } do
				GroundMarks.Clear(marks)
				for f = 0, 12 do
					local p, across = at(f * DT2)
					GroundMarks.Wheel(marks, 2, true, p, up, across, 1, true, if ground then ground else nil, DT2)
				end
				local tipK = marks.strips[2].tip
				local q
				for _, s in marks:DebugStrip(2) do
					if s.k == tipK then
						q = s.points
					end
				end
				local p = at(12 * DT2)
				planeError = math.max(planeError, math.abs(q[1].Y - (p.Y + G.Lift)), math.abs(q[P].Y - (p.Y + G.Lift)))
			end
			check(
				"with no drawn ground in reach the ribbon lies on the car's plane",
				planeError < 1e-3,
				string.format("edges %.1e studs off the plane + Lift", planeError)
			)

			-- Room: a long straight run lays more than the ring holds, far past the origin.
			-- The oldest go first, and nothing is ever stretched.
			GroundMarks.Clear(marks)
			local t0 = os.clock()
			local laid, x = 0, 0
			for _ = 1, RB.Sections * 3 do
				x += RB.Spacing * 4 -- 12 studs a step: far from the origin quickly
				local p = Vector3.new(x, groundY(x, 0) + 0.5, 0)
				GroundMarks.Wheel(marks, 3, true, p, up, Vector3.zAxis, 1, true, drawn, DT2)
				laid += 1
			end
			local perCall = (os.clock() - t0) / laid * 1e6
			local ringWorst, ringReal = stretched(marks:DebugStrip(3))
			-- (12-stud steps here: the stretch allowance is a segment's length)
			local tipK = marks.strips[3].tip
			local tipPts
			for _, s in marks:DebugStrip(3) do
				if s.k == tipK then
					tipPts = s.points
				end
			end
			local tipError = math.abs(tipPts[P].Y - (groundY(tipPts[P].X, tipPts[P].Z) + G.Lift))
			check(
				"a full ring reuses its oldest sections, moves its origin, and still lays marks in the right place",
				marks.recycled > 0 and marks.reorigins > 0 and ringReal <= RB.Sections and tipError < 2e-3 and ringWorst <= RB.Spacing * 4,
				string.format("%d sections over %.0f studs; %d real of %d, %d reused early, origin moved %d times; tip edge %.1e studs off; %.1f us a section",
					laid, x, ringReal, RB.Sections, marks.recycled, marks.reorigins, tipError, perCall)
			)
			GroundMarks.Clear(marks)
			check(
				"and the ribbon made nothing while it drew",
				#marks.folder:GetDescendants() == folderBefore and marks:LiveCount() == 0,
				`{folderBefore} in its folder before, {#marks.folder:GetDescendants()} after; Clear leaves {marks:LiveCount()} sections`
			)

			------------------------------------------------------------------------
			-- 9d. RUBBER ON THE TARMAC (T-269): the same ribbon, see-through, flat, on the
			-- spline road's own surface; darkest where the wheel is loaded and sliding most.
			------------------------------------------------------------------------
			do
				local MR = F.Marks.Ribbon
				local rub = w.rubber
				local RP = #F.Marks.Profile * 2

				-- Built once, see-through, inside the budget.
				local rparts, see = 0, true
				for _, part in rub.folder:GetChildren() do
					if part:IsA("MeshPart") then
						rparts += 1
						see = see and part.Transparency > 0.001 and part.Material == MR.Material
							and (if rub.image then part.TextureContent.Object == rub.image else part.TextureContent.SourceType == Enum.ContentSourceType.Opaque)
							and math.abs(part.Size.X - 2000) < 1
					end
				end
				local rverts = rub:DebugState().vertices
				local allVerts = rverts + marks:DebugState().vertices
				check(
					"the rubber ribbon is built once, one see-through part a wheel; both ribbons hold what the grass's alone did",
					rub.ready and rparts == MR.Wheels and see and rverts <= 1100 and allVerts <= 4200,
					`ready {rub.ready} ({rub.failed or "ok"}); {rparts} MeshParts, see-through and textured {see}; {rverts} mesh vertices, {allVerts} with the grass's`
				)

				-- How hard a wheel marks: slip past its own threshold, and its load.
				local I = Wheels.markIntensity
				local rear0, rear1, rearFull = I(0, false, false, 0.5), I(1, false, false, 0.5), I(40, false, false, 0.5)
				local front30, frontFull = I(29, true, false, 0.5), I(F.Gates.MaxSteerDegrees + MR.IntensitySlipDegrees, true, false, 0.5)
				local hb = I(0, false, true, 0.5)
				local loaded, light = I(20, false, false, 1), I(20, false, false, 0)
				local mid = I(20, false, false, 0.5)
				local s0 = stateWith({ slipDeg = 30, speed = 60, throttle = 1 })
				s0.travel = { 0.25, 0.25, 0.4, 0.1 }
				local shares = { Wheels.loadShare(s0, 1), Wheels.loadShare(s0, 3), Wheels.loadShare(s0, 4) }
				check(
					"rubber goes down with the slip past each wheel's threshold, and darkest where the wheel is loaded",
					rear0 == 0 and rear1 >= MR.MinIntensity * 0.99 and rear1 < MR.MinIntensity + 0.1 and rearFull == 1 and front30 == 0
						and frontFull == 1 and hb >= MR.HandbrakeIntensity and loaded > mid and mid > light
						and math.abs(shares[1] - 0.5) < 1e-6 and shares[2] > 0.5 and shares[3] < 0.5,
					string.format("rear 0/1/40 deg %.2f/%.2f/%.2f; front 29 deg %.2f, full %.2f; handbrake %.2f; 20 deg loaded/even/light %.2f/%.2f/%.2f; load shares %s",
						rear0, rear1, rearFull, front30, frontFull, hb, loaded, mid, light, fmtList(shares))
				)

				-- A stand-in road: the spline's own surface, a tilted, wavy plane, s along x and d
				-- along z. The ribbon must lie on it, not on the drawn ground (none here).
				local function roadY(sx: number, dz: number): number
					return 30 + 0.05 * sx + 0.02 * dz + 0.3 * math.sin(sx * 0.1)
				end
				local probes = 0
				local fakeSpline = {
					projectFrom = function(_, x: number, z: number, _hint: number?)
						probes += 1
						return x, z
					end,
					project = function(_, x: number, z: number)
						probes += 1
						return x, z
					end,
					terrainXYZ = function(_, sx: number, dz: number)
						return sx, roadY(sx, dz), dz
					end,
					terrainNormal = function()
						return Vector3.yAxis
					end,
					-- the road runs along +x (s) with d along +z: yaw -90 degrees, straight
					yawAt = function()
						return -math.pi / 2
					end,
					curvatureAt = function()
						return 0
					end,
				}
				local roadGround = { spline = fakeSpline, _drawnAt = function() return nil end }
				GroundMarks.Clear(rub)
				local function onArc(t: number): (Vector3, Vector3)
					local a = 50 * t / 40
					local x, z = 40 * math.sin(a), 40 * (1 - math.cos(a))
					local tangent = Vector3.new(math.cos(a), 0, math.sin(a))
					return Vector3.new(x, roadY(x, z) + 0.4, z), tangent:Cross(up)
				end
				for f = 0, 60 do
					local p, across = onArc(f / 60)
					GroundMarks.Wheel(rub, 1, true, p, up, across, 1, f > 45, roadGround, 1 / 60, 1)
					GroundMarks.Age(rub, 1 / 60)
				end
				local scuffKind = GroundMarks.Kind(rub, 1)
				GroundMarks.Wheel(rub, 1, false, onArc(61 / 60), up, Vector3.xAxis, 1, true, roadGround, 1 / 60, 1)
				local strip = rub:DebugStrip(1)
				local worst = stretched(strip, RP)
				local rmark = {}
				for _, sct in strip do
					if sct.real and (sct.points[1] - sct.points[RP]).Magnitude > 1e-4 then
						table.insert(rmark, sct)
					end
				end
				local edgeErr, flatErr, edgeAlpha, midAlpha = 0, 0, 0, 0
				for _, sct in rmark do
					for _, j in { 1, RP } do
						edgeErr = math.max(edgeErr, math.abs(sct.points[j].Y - (roadY(sct.points[j].X, sct.points[j].Z) + MR.Lift)))
						edgeAlpha = math.max(edgeAlpha, sct.alphas[j])
					end
					for j = 1, RP do
						flatErr = math.max(flatErr, math.abs(sct.normals[j]:Dot(Vector3.yAxis) - 1))
					end
				end
				local midSct = rmark[math.max(#rmark // 2, 1)]
				midAlpha = midSct.alphas[RP // 2]
				local wantMid = F.Marks.Rubber.Points[#F.Marks.Profile].Alpha * F.Marks.Rubber.Opacity
				check(
					"the rubber lies flat on the road's own surface, clear at its edges, darkest in its middle",
					#rmark > 10 and worst < 1e-3 and edgeErr < 2e-3 and flatErr < 1e-4 and edgeAlpha == 0
						and math.abs(midAlpha - wantMid) < 0.02 and probes > 0,
					string.format("%d sections; worst stretch %.1e; edges %.1e studs off the road + Lift; normals flat to %.1e; edge alpha %.2f, middle %.2f (want %.2f); %d road lookups",
						#rmark, worst, edgeErr, flatErr, edgeAlpha, midAlpha, wantMid, probes)
				)
				check(
					"onto the gravel the rubber becomes a scuff",
					scuffKind == "scuff",
					`look on the gravel: {tostring(scuffKind)}`
				)
				-- It fades with its life (`Marks.Seconds`) and goes.
				local a0 = midSct.showing
				GroundMarks.Age(rub, F.Marks.Seconds * 0.85)
				local aged
				for _, sct in rub:DebugStrip(1) do
					if sct.k == midSct.k then
						aged = sct
					end
				end
				local liveMid = rub:LiveCount()
				GroundMarks.Age(rub, F.Marks.Seconds * 0.2)
				check(
					"the rubber dries and fades over its life and goes",
					aged and aged.showing < a0 * 0.6 and aged.alphas[RP // 2] < midAlpha * 0.6 and liveMid > 0 and rub:LiveCount() == 0,
					string.format("showing %.2f fresh, %.2f at 85%% of %.0f s; %d sections then, %d after",
						a0, if aged then aged.showing else -1, F.Marks.Seconds, liveMid, rub:LiveCount())
				)
				GroundMarks.Clear(rub)

				-- Through `Wheels`: on tarmac the rubber comes in eased, never at once.
				w:Cut()
				local rear
				for _, wheel in w.wheels do
					if not wheel.front then
						rear = wheel
						break
					end
				end
				local tarmacSlide = stateWith({ slipDeg = 40, speed = 70, throttle = 1, surface = "tarmac" })
				w:Update(tarmacSlide, { handbrake = false }, DT, roadGround)
				local first = rear.intensity
				for _ = 1, 30 do
					w:Update(tarmacSlide, { handbrake = false }, DT, roadGround)
				end
				local later = rear.intensity
				check(
					"through Wheels the rubber's darkness is eased in",
					w.rubber:Kind(rear.index) == "rubber" and first > 0 and first < later and later > 0.9,
					string.format("intensity %.2f after a frame, %.2f half a second later", first, later)
				)
				w:Cut()
				GroundMarks.Clear(rub)
			end

			-- Through `Wheels`: the ground is asked only while a wheel marks grass.
			calls = 0
			w:Cut()
			for _, s in {
				stateWith({ slipDeg = 45, speed = 70, throttle = 1, surface = "tarmac" }),
				stateWith({ slipDeg = 45, speed = 70, throttle = 1, surface = "gravel" }),
				stateWith({ slipDeg = 45, speed = 70, throttle = 0, surface = "grass" }),
			} do
				w:Update(s, { handbrake = false }, DT, drawn)
			end
			local idleCalls = calls
			calls = 0
			w:Cut()
			w:Update(stateWith({ slipDeg = 45, speed = 70, throttle = 1, surface = "grass" }), { handbrake = false }, DT, drawn)
			check(
				"the ground is asked only by wheels marking grass: three lookups each",
				idleCalls == 0 and calls == 3 * #CarModel.WHEEL_NAMES,
				`{idleCalls} lookups on tarmac, gravel and coasting on grass; {calls} for four wheels cutting ruts`
			)
			w:Cut()
			GroundMarks.Clear(marks)
		end
		check("and none of it built anything", w:CountInstances() == want, `{w:CountInstances()} instances`)

		w:Clear()
		check("Clear takes all of them away", w:CountInstances() == 0, `{#rig.body:GetDescendants()} left on the body`)
		car:Destroy()
		w.marks:Destroy()
		w.rubber:Destroy()
		w.debris:Destroy()
	end

	----------------------------------------------------------------------------
	-- 11. THE GEARBOX, pure. A geometric series and nothing else.
	----------------------------------------------------------------------------
	do
		local E = F.Engine
		local top = Config.Drift.TopSpeed
		local tops = EngineSound.gearTops(top, {})

		-- The series computed here, independently of the module, from the spec's own
		-- description: first gear is `TopSpeed / sum(m^i)` and each gear adds `m^i` of it.
		local divisor, term = 0, 1
		for _ = 1, E.GearCount do
			divisor += term
			term *= E.GearLengthMultiplier
		end
		local want, running = {}, 0
		term = 1
		for i = 1, E.GearCount do
			running += (top / divisor) * term
			want[i] = running
			term *= E.GearLengthMultiplier
		end

		local worst, worstAt = 0, 0
		for i = 1, E.GearCount do
			local d = math.abs(tops[i] - want[i])
			if d > worst then
				worst, worstAt = d, i
			end
		end
		check(
			`the gear tops are the geometric series ({E.GearCount} gears, x{E.GearLengthMultiplier})`,
			worst < 1e-6 and #tops == E.GearCount,
			`{fmtList(tops)} studs/s; divisor {string.format("%.4f", divisor)}; worst gap {string.format("%.2e", worst)} at gear {worstAt}`
		)
		check(
			"top gear tops out at the car's top speed, exactly",
			math.abs(tops[E.GearCount] - top) < 1e-9,
			`gear {E.GearCount} top {string.format("%.3f", tops[E.GearCount])}, car {string.format("%.3f", top)} studs/s`
		)

		-- The overlap is hysteresis and nothing else: a speed sitting on a shift point
		-- must leave the gear it is in alone, in BOTH directions.
		local onPoint = tops[1]
		check(
			"a speed sitting exactly on a shift point does not shift, either way",
			EngineSound.wanted(tops, 1, onPoint) == 1 and EngineSound.wanted(tops, 2, onPoint) == 2,
			`at {string.format("%.2f", onPoint)} studs/s: from 1st stays 1st, from 2nd stays 2nd `
				.. `(overlap {E.GearOverlap} studs/s either side)`
		)
		check(
			"clear of the overlap it does shift",
			EngineSound.wanted(tops, 1, onPoint + E.GearOverlap + 0.01) == 2
				and EngineSound.wanted(tops, 2, onPoint - E.GearOverlap - 0.01) == 1,
			`up at {string.format("%.2f", onPoint + E.GearOverlap)}, down at {string.format("%.2f", onPoint - E.GearOverlap)}`
		)
		check(
			"the box never skips a gear, however far the speed jumps",
			EngineSound.wanted(tops, 1, top * 10) == 2 and EngineSound.wanted(tops, E.GearCount, -top) == E.GearCount - 1,
			"one gear per call, up and down"
		)
		check(
			"the clip's pitch runs MinPitch at idle to MaxPitch at the redline",
			math.abs(EngineSound.pitchForShare(0) - E.MinPitch) < 1e-9
				and math.abs(EngineSound.pitchForShare(1) - E.MaxPitch) < 1e-9,
			`{E.MinPitch} at {E.IdleRpm} rpm, {E.MaxPitch} at {E.RedlineRpm} rpm`
		)

		-- THE SHIFT ITSELF: how far the pitch TARGET falls at each upshift, which is what
		-- a shift sounds like. Measured here so a change to the sweep or the multiplier
		-- shows up as a number rather than as "it stopped sounding like a shift".
		local drops = {}
		for i = 1, E.GearCount - 1 do
			-- The rpm the speed makes in each gear (Drift/Engine), as the clip's pitch.
			local at = tops[i]
			local function pitchAt(g)
				local share = (Engine.roadRpm(tops, g, at) - E.IdleRpm) / (E.RedlineRpm - E.IdleRpm)
				return EngineSound.pitchForShare(share)
			end
			drops[i] = pitchAt(i) - pitchAt(i + 1)
		end
		local smallest = math.huge
		for _, d in drops do
			smallest = math.min(smallest, d)
		end
		check(
			"every upshift drops the pitch, and the smallest drop is still audible",
			smallest > 0.25,
			`drops {fmtList(drops)} of pitch at the {E.GearCount - 1} upshifts; smallest {string.format("%.3f", smallest)}`
		)
	end

	----------------------------------------------------------------------------
	-- 12. THE SQUEAL'S GATE, pure. The volume is the LATERAL SLIDE SPEED (T-083 round two):
	-- `speed * |sin(slip)|`, lerped from `MinVolume` to `MaxVolume` across
	-- `SlideSpeedForMax`. FOUR ways to be silent and no more: no state, airborne, under
	-- `MinSpeed`, not drifting (`RollVolume`, 0 today).
	----------------------------------------------------------------------------
	do
		local S = F.Skid
		local function vol(opts)
			return SkidSound.volumeFor(stateWith(opts))
		end
		local function slide(deg, speed)
			return speed * math.abs(math.sin(math.rad(deg)))
		end

		-- THE CURVE, read at two angles crossed with three speeds, so a mistake that
		-- dropped either variable out of the sum fails here.
		local worst = 0
		local shown = {}
		for _, deg in { 10, 45 } do
			for _, speed in { 20, 60, 140 } do
				local got = vol({ slipDeg = deg, speed = speed, throttle = 1 })
				local t = math.clamp(slide(deg, speed) / S.SlideSpeedForMax, 0, 1)
				local wanted = S.MinVolume + (S.MaxVolume - S.MinVolume) * t
				worst = math.max(worst, math.abs(got - wanted))
				table.insert(
					shown,
					`{deg} deg at {speed} studs/s (slide {string.format("%.1f", slide(deg, speed))}) -> `
						.. `{string.format("%.4f", got)}`
				)
			end
		end
		check(
			"the squeal's volume is the configured lerp of the LATERAL SLIDE SPEED",
			worst < 1e-9,
			`{table.concat(shown, "; ")}; worst gap {string.format("%.2e", worst)}`
		)

		-- THE WHOLE POINT OF THE ROUND. Same angle, different speed: the old curve gave
		-- these two the same number, and a slow pivot screamed like a fast slide.
		local pivot = vol({ slipDeg = 90, speed = 10, throttle = 1 })
		local fast = vol({ slipDeg = 90, speed = 140, throttle = 1 })
		check(
			"a slow pivot is quiet and a fast slide is loud at the SAME angle",
			fast > pivot * 3 and math.abs(pivot - (S.MinVolume + (S.MaxVolume - S.MinVolume) * (10 / S.SlideSpeedForMax))) < 1e-9,
			`90 deg at 10 studs/s -> {string.format("%.4f", pivot)} (slide 10.0), `
				.. `90 deg at 140 -> {string.format("%.4f", fast)} (slide 140.0, capped at `
				.. `{S.SlideSpeedForMax}); by the old slip-angle curve both were `
				.. `{string.format("%.4f", 0.25 + 0.30 * (90 / 90))}`
		)
		check(
			`past {S.SlideSpeedForMax} studs/s of slide it stays at MaxVolume ({S.MaxVolume})`,
			math.abs(vol({ slipDeg = 90, speed = S.SlideSpeedForMax, throttle = 1 }) - S.MaxVolume) < 1e-9
				and math.abs(vol({ slipDeg = 90, speed = 179, throttle = 1 }) - S.MaxVolume) < 1e-9,
			`90 deg at {S.SlideSpeedForMax} studs/s -> {string.format("%.4f", vol({ slipDeg = 90, speed = S.SlideSpeedForMax, throttle = 1 }))}, `
				.. `at 179 -> {string.format("%.4f", vol({ slipDeg = 90, speed = 179, throttle = 1 }))}`
		)
		-- PAST 90 DEGREES THE SLIDE FALLS AWAY AGAIN, because the car is travelling
		-- backwards under itself and the patch is barely moving sideways. Honest, not a
		-- bug, and written down here so a future round does not "fix" it by accident.
		check(
			"past 90 degrees the slide, and so the volume, comes back down",
			vol({ slipDeg = 170, speed = 60, throttle = 1 }) < vol({ slipDeg = 90, speed = 60, throttle = 1 }),
			`90 deg at 60 studs/s -> {string.format("%.4f", vol({ slipDeg = 90, speed = 60, throttle = 1 }))} `
				.. `(slide {string.format("%.1f", slide(90, 60))}), 170 deg -> `
				.. `{string.format("%.4f", vol({ slipDeg = 170, speed = 60, throttle = 1 }))} `
				.. `(slide {string.format("%.1f", slide(170, 60))})`
		)

		-- NOT DRIFTING IS SILENT. The user drove the always-on hiss and rejected it
		-- (2026-11-08): `RollVolume` is 0, so no tyre sliding means no sound.
		local floorShown = {}
		local floorOk = true
		for _, speed in { 10, 60, 179 } do
			local got = vol({ slipDeg = 4.9, speed = speed, throttle = 1 })
			floorOk = floorOk and got == 0
			table.insert(floorShown, `4.9 deg at {speed} studs/s -> {string.format("%.4f", got)}`)
		end
		check(
			`a car that is not drifting makes no sound at all (RollVolume {S.RollVolume})`,
			floorOk and S.RollVolume == 0,
			`{table.concat(floorShown, ", ")}; and 0 deg at 60 -> `
				.. `{string.format("%.4f", vol({ slipDeg = 0, speed = 60, throttle = 1 }))}`
		)

		-- AND THE KEY STILL DOES WHAT ITS COMMENT SAYS: raise `RollVolume` and the
		-- always-on hiss comes back, with no line of logic touched. Mutated and restored
		-- in four lines with nothing between them that can throw.
		local keptRoll = S.RollVolume
		S.RollVolume = 0.12
		local hiss = { vol({ slipDeg = 0, speed = 60 }), vol({ slipDeg = 4.9, speed = 179 }), vol({ slipDeg = 0, speed = S.MinSpeed - 0.01 }) }
		S.RollVolume = keptRoll
		check(
			"RollVolume is still the one switch for the always-on hiss, in both directions",
			math.abs(hiss[1] - 0.12) < 1e-9 and math.abs(hiss[2] - 0.12) < 1e-9 and hiss[3] == 0 and S.RollVolume == keptRoll,
			`at RollVolume 0.12: 0 deg -> {string.format("%.4f", hiss[1])}, 4.9 deg at 179 -> `
				.. `{string.format("%.4f", hiss[2])}, under MinSpeed -> {string.format("%.4f", hiss[3])} `
				.. `(restored to {S.RollVolume})`
		)

		-- THE STEP at the drift threshold, from `RollVolume` to the bottom of the curve.
		-- `VolumeLerpSpeed` carries it -- the measured single-frame move is in section 13.
		local notDrifting = Config.Drift.MinSlipAngleForDrift - 0.01
		local below = vol({ slipDeg = notDrifting, speed = 60, throttle = 1 })
		local above = vol({ slipDeg = Config.Drift.MinSlipAngleForDrift, speed = 60, throttle = 1 })
		check(
			"there is a step up at the drift threshold, from silence to just over MinVolume",
			math.abs(below - S.RollVolume) < 1e-9 and above > below and above >= S.MinVolume,
			`{string.format("%.2f", notDrifting)} deg -> {string.format("%.4f", below)}, `
				.. `{Config.Drift.MinSlipAngleForDrift} deg -> {string.format("%.4f", above)} `
				.. `(a step of {string.format("%.4f", above - below)}; the model's own drift `
				.. "threshold, not a second one)"
		)

		check(
			"silent in the air, whatever the angle or the speed",
			vol({ slipDeg = 90, speed = 60, throttle = 1, airborne = true }) == 0
				and vol({ slipDeg = 90, speed = 179, throttle = 1, airborne = true }) == 0,
			"90 deg airborne at 60 and 179 studs/s -> 0"
		)
		check(
			"silent under the minimum speed, and not a hundredth above it",
			vol({ slipDeg = 90, speed = S.MinSpeed - 0.01 }) == 0 and vol({ slipDeg = 90, speed = S.MinSpeed }) > 0,
			`{S.MinSpeed - 0.01} studs/s silent, {S.MinSpeed} studs/s -> `
				.. `{string.format("%.4f", vol({ slipDeg = 90, speed = S.MinSpeed }))}`
		)
		check("silent with no state at all", SkidSound.volumeFor(nil) == 0, "nil -> 0")
		check(
			"slideSpeed is speed x |sin(slip)|, and 0 with no state",
			math.abs(SkidSound.slideSpeed(stateWith({ slipDeg = 30, speed = 100 })) - 50) < 1e-9
				and math.abs(SkidSound.slideSpeed(stateWith({ slipDeg = -30, speed = 100 })) - 50) < 1e-9
				and SkidSound.slideSpeed(nil) == 0,
			`30 deg at 100 studs/s -> {string.format("%.4f", SkidSound.slideSpeed(stateWith({ slipDeg = 30, speed = 100 })))} `
				.. `studs/s sideways, and the same sliding the other way`
		)
		-- Not a check, a note: the squeal has no throttle gate and no handbrake gate. The
		-- marks have both; the reference's squeal has neither, and nor does ours.
		check(
			"the surface is the one surface, and nothing in the air",
			SkidSound.surfaceOf(stateWith({ slipDeg = 45, speed = 60 })) == F.Default
				and SkidSound.surfaceOf(stateWith({ slipDeg = 45, speed = 60, airborne = true })) == nil,
			`on the ground: {tostring(SkidSound.surfaceOf(stateWith({ slipDeg = 45, speed = 60 })))}`
		)
		-- T-222: the off-road clip, by a vote of the wheels, a tie keeping the clip playing
		local function clipOn(wheels, current)
			return SkidSound.surfaceOf(stateWith({ slipDeg = 45, speed = 60, surface = wheels }), current)
		end
		local offRoad = SkidSound.clipFor("grass")
		local hasDirt = F.Skid.SoundIds.dirt ~= nil
		local allGrass = clipOn({ "grass", "grass", "grass", "grass" })
		local oneGravel = clipOn({ "gravel", "tarmac", "tarmac", "tarmac" })
		local threeOff = clipOn({ "gravel", "grass", "tarmac", "grass" })
		local tieDirt = clipOn({ "gravel", "gravel", "tarmac", "tarmac" }, offRoad)
		local tieTarmac = clipOn({ "gravel", "gravel", "tarmac", "tarmac" }, F.Default)
		check(
			"off the road the wheels vote for the clip, and a tie keeps the one playing",
			allGrass == offRoad and oneGravel == F.Default and threeOff == offRoad
				and tieDirt == offRoad and tieTarmac == F.Default
				and (not hasDirt or offRoad == "dirt"),
			`grass x4 {allGrass}, gravel x1 {oneGravel}, off x3 {threeOff}, tie from {offRoad} {tieDirt}, `
				.. `tie from {F.Default} {tieTarmac}`
		)
	end

	----------------------------------------------------------------------------
	-- 13. THE SOUNDS ON A RIG. Not pure: it builds a stand-in car, IN SERVERSTORAGE
	-- so that a `Sound` this test plays can never replicate to a client and be heard.
	----------------------------------------------------------------------------
	if opts.skipInstances ~= true then
		local E = F.Engine
		local S = F.Skid
		local rig, car = standInRig()
		car.Parent = ServerStorage

		local engine = EngineSound.new()
		local skid = SkidSound.new()
		local engineOk = engine:Attach(rig)
		local skidOk = skid:Attach(rig)
		local skidClips = 0 -- one skid Sound per clip in `Skid.Clips` that has an id (T-222)
		for _, clip in S.Clips do
			skidClips += if S.SoundIds[clip] then 1 else 0
		end
		local wantSounds = EngineSound.expectedInstances() + skidClips -- the engine (1, or 12 layered), one per skid clip
		local soundsBefore = engine:CountInstances() + skid:CountInstances()
		check(
			`a rig gets exactly {wantSounds} sounds, once`,
			engineOk and skidOk and soundsBefore == wantSounds,
			`engine {engine:CountInstances()}, skid {skid:CountInstances()}`
		)
		engine:Attach(rig)
		skid:Attach(rig)
		check(
			"attaching again makes no second sound",
			engine:CountInstances() + skid:CountInstances() == wantSounds,
			`{engine:CountInstances() + skid:CountInstances()} sounds`
		)
		-- The engine is one clip, or one slice per loop of the uploaded sheet `Sheet`
		-- names (T-129, T-170): every one must carry the picked id.
		local engineId = if EngineSound.isLayered() then EngineSound.sheet().SoundId else E.SoundId
		local engineSounds = {}
		for _, child in rig.body:GetChildren() do
			if child:IsA("Sound") and string.sub(child.Name, 1, #F.Names.Engine) == F.Names.Engine then
				table.insert(engineSounds, child)
			end
		end
		local idsOk, tapered = #engineSounds == EngineSound.expectedInstances(), true
		for _, sound in engineSounds do
			idsOk = idsOk and sound.SoundId == engineId
			tapered = tapered and sound.RollOffMode == Enum.RollOffMode.InverseTapered
		end
		local skidSound = rig.body:FindFirstChild(string.format(F.Names.Skid, F.Default))
		check(
			"every sound is an id the user picked, by id",
			idsOk and skidSound.SoundId == S.SoundIds[F.Default],
			`{#engineSounds} engine sounds on {engineId}, skid {S.SoundIds[F.Default]}`
		)
		check(
			"all are 3D: tapered roll-off, so another car is heard where it is",
			tapered and skidSound.RollOffMode == Enum.RollOffMode.InverseTapered,
			`engine {E.RollOffMin}..{E.RollOffMax} studs, skid {S.RollOffMin}..{S.RollOffMax} studs`
		)

		----------------------------------------------------------------------
		-- Drive 0 to top speed and record every shift.
		----------------------------------------------------------------------
		local DT = 1 / 60
		local SECONDS = 20
		local top = Config.Drift.TopSpeed
		local tops = EngineSound.gearTops(top, {})
		local shiftAt, shiftTime = {}, {}
		local lastShifts, elapsed = engine.engine.upshifts, 0
		local maxPitchStep = 0
		local pitchWas = engine.pitch

		engine:ResetMeasure()
		for frame = 1, SECONDS / DT do
			elapsed += DT
			local speed = top * math.min(frame * DT / (SECONDS * 0.75), 1)
			local s = stateWith({ slipDeg = 0, speed = speed, throttle = 1 })
			engine:Update(s, nil, DT)
			skid:Update(s, nil, DT)
			if engine.engine.upshifts ~= lastShifts then
				lastShifts = engine.engine.upshifts
				table.insert(shiftAt, speed)
				table.insert(shiftTime, elapsed)
			end
			maxPitchStep = math.max(maxPitchStep, math.abs(engine.pitch - pitchWas))
			pitchWas = engine.pitch
		end

		local shiftWorst, shiftShown = 0, {}
		for i, at in shiftAt do
			local series = tops[i] or top
			shiftWorst = math.max(shiftWorst, math.abs(at - series))
			table.insert(
				shiftShown,
				`{i}-{i + 1} at {string.format("%.2f", at)} (gear {i} tops at {string.format("%.2f", series)})`
			)
		end
		check(
			`a run to top speed makes exactly {E.GearCount - 1} upshifts`,
			#shiftAt == E.GearCount - 1,
			`{#shiftAt} shifts: {table.concat(shiftShown, "; ")}`
		)
		-- WITHIN THE OVERLAP, which is what the overlap IS: a gear is held until the
		-- speed is clear of its band, so a shift lands at its top plus the overlap, plus
		-- whatever one frame of acceleration adds on top.
		local allowed = E.GearOverlap + top * DT / (SECONDS * 0.75) + 1e-6
		check(
			"every shift lands within the overlap of the computed series",
			shiftWorst <= allowed,
			`worst {string.format("%.3f", shiftWorst)} studs/s against an allowance of `
				.. `{string.format("%.3f", allowed)} (overlap {E.GearOverlap} + one frame)`
		)
		local closest = math.huge
		for i = 2, #shiftTime do
			closest = math.min(closest, shiftTime[i] - shiftTime[i - 1])
		end
		check(
			`no two shifts closer together than MinTimeInGear ({E.MinTimeInGear} s)`,
			#shiftTime < 2 or closest >= E.MinTimeInGear - 1e-6,
			`closest pair {if closest == math.huge then "n/a" else string.format("%.3f", closest) .. " s"}`
		)

		-- And the debounce under something that WOULD machine-gun: slammed from a
		-- standstill to top speed in one frame, the box must still walk up one gear every
		-- `MinTimeInGear` and never faster. A real car cannot do this; a `DebugTeleport`
		-- out of a wall can.
		do
			local e2 = EngineSound.new()
			e2:Attach(rig)
			local flat = stateWith({ slipDeg = 0, speed = top, throttle = 1 })
			local at, clock = {}, 0
			local was = e2.engine.shifts
			for _ = 1, 600 do
				clock += DT
				e2:Update(flat, nil, DT)
				if e2.engine.shifts ~= was then
					was = e2.engine.shifts
					table.insert(at, clock)
				end
			end
			local tightest = math.huge
			for i = 2, #at do
				tightest = math.min(tightest, at[i] - at[i - 1])
			end
			local shown = {}
			for _, v in at do
				table.insert(shown, string.format("%.3f", v))
			end
			check(
				"slammed from a standstill to top speed, the box still walks up one gear per debounce",
				#at == E.GearCount - 1 and tightest >= E.MinTimeInGear - 1e-6 and e2.engine.gear == E.GearCount,
				`{#at} shifts at {table.concat(shown, ", ")} s; tightest {string.format("%.3f", tightest)} s `
					.. `against {E.MinTimeInGear} s; ends in gear {e2.engine.gear}`
			)
			e2:Clear()
		end

		----------------------------------------------------------------------
		-- Pitch is continuous: the rpm's inertia, not a snap. On a plain run (no
		-- limiter) no frame moves the rpm more than its chase rate allows across the range.
		----------------------------------------------------------------------
		local rate = math.max(E.RevUpRate, E.RevDownRate)
		local bound = (E.MaxPitch - E.MinPitch) * rate * DT
		check(
			"the largest single-frame pitch change over the whole run is inside the rpm's chase bound",
			maxPitchStep <= bound + 1e-9,
			`largest {string.format("%.5f", maxPitchStep)}, bound {string.format("%.5f", bound)} `
				.. `= ({E.MaxPitch} - {E.MinPitch}) x {rate}/s x {string.format("%.4f", DT)} s`
		)
		check(
			"and the module's own measure agrees with the one taken here",
			math.abs(engine:ResetMeasure() - maxPitchStep) < 1e-9,
			"ResetMeasure() matches the frame-by-frame maximum"
		)

		----------------------------------------------------------------------
		-- Airborne: the engine free-revs into the limiter and the squeal cuts dead.
		----------------------------------------------------------------------
		local air = stateWith({ slipDeg = 90, speed = 120, throttle = 1, airborne = true })
		local cutsBefore = engine.engine.cuts
		local lowest = math.huge
		for frame = 1, 600 do
			engine:Update(air, nil, DT)
			skid:Update(air, nil, DT)
			if frame > 120 then
				lowest = math.min(lowest, engine.pitch)
			end
		end
		local floorShare = (E.RedlineRpm - E.LimiterDropRpm - E.IdleRpm) / (E.RedlineRpm - E.IdleRpm)
		local floorPitch = EngineSound.pitchForShare(floorShare)
		check(
			"airborne revs into the limiter and stays in its band, and the squeal goes to nothing",
			engine.engine.cuts > cutsBefore and lowest >= floorPitch - 0.02 and skid.volume < 1e-3,
			`{engine.engine.cuts - cutsBefore} cuts; lowest pitch after 2 s {string.format("%.3f", lowest)} `
				.. `(limiter floor {string.format("%.3f", floorPitch)}), skid {string.format("%.6f", skid.volume)}`
		)

		----------------------------------------------------------------------
		-- The squeal fades up with the angle and back down when it is caught.
		----------------------------------------------------------------------
		local sliding = stateWith({ slipDeg = 45, speed = 60, throttle = 1 })
		local climbed = {}
		for frame = 1, 600 do
			skid:Update(sliding, nil, DT)
			if frame == 6 or frame == 60 or frame == 600 then
				table.insert(climbed, string.format("%.1f s -> %.4f", frame * DT, skid.volume))
			end
		end
		local wanted45 = SkidSound.volumeFor(sliding)
		check(
			"a held 45-degree slide fades the squeal up to its target rather than snapping to it",
			skid.volume < wanted45 and math.abs(skid.volume - wanted45) < 1e-3 and climbed[1] ~= nil,
			`{table.concat(climbed, ", ")} against a target of {string.format("%.4f", wanted45)} `
				.. `at {S.VolumeLerpSpeed}/s`
		)
		-- CATCHING IT FADES TO SILENCE -- `RollVolume` is 0 -- AND THE CLIP STAYS RUNNING
		-- through the whole of it (T-083). Both at once is the point: nothing is heard,
		-- and the next drift does not restart the clip and re-play its loop seam.
		local caught = stateWith({ slipDeg = 0, speed = 60, throttle = 1 })
		local stayedPlaying = true
		for _ = 1, 600 do
			skid:Update(caught, nil, DT)
			stayedPlaying = stayedPlaying and skid.sounds[1].playing
		end
		check(
			"catching it fades the squeal away to RollVolume, and never stops the clip",
			math.abs(skid.volume - S.RollVolume) < 1e-3 and stayedPlaying,
			`{string.format("%.6f", skid.volume)} against RollVolume {S.RollVolume}; the clip `
				.. `stayed running: {stayedPlaying}`
		)

		--------------------------------------------------------------------
		-- THE STEP AT THE DRIFT THRESHOLD, measured a frame at a time: the
		-- thing that must not click. The lerp carries it, so the biggest
		-- single-frame move is a fraction of the step itself.
		--------------------------------------------------------------------
		local justDrifting = stateWith({ slipDeg = Config.Drift.MinSlipAngleForDrift, speed = 60, throttle = 1 })
		skid:ResetMeasure()
		local crossedFrom = skid.volume
		for _ = 1, 120 do
			skid:Update(justDrifting, nil, DT)
		end
		local stepAcross = skid:ResetMeasure()
		local stepSize = SkidSound.volumeFor(justDrifting) - S.RollVolume
		check(
			"crossing the drift threshold is a swell, not a click",
			stepAcross < stepSize and stepAcross < 0.02,
			`largest single-frame volume move {string.format("%.5f", stepAcross)} at {math.floor(1 / DT)} fps, `
				.. `crossing a step of {string.format("%.4f", stepSize)} `
				.. `({string.format("%.4f", crossedFrom)} -> {string.format("%.4f", SkidSound.volumeFor(justDrifting))})`
		)

		-- AND THE ONLY TWO THINGS THAT STOP IT. A drift beginning or ending is not one of
		-- them, which is the whole of T-083; the clip is started once and left running.
		local rollingOn = skid.sounds[1].playing
		skid:Update(stateWith({ slipDeg = 0, speed = S.MinSpeed - 0.01, throttle = 1 }), nil, DT)
		local slowOff = not skid.sounds[1].playing
		skid:Update(stateWith({ slipDeg = 0, speed = 60, throttle = 1 }), nil, DT)
		local backOn = skid.sounds[1].playing
		skid:Update(stateWith({ slipDeg = 45, speed = 60, throttle = 1, airborne = true }), nil, DT)
		local airOff = not skid.sounds[1].playing
		skid:Update(stateWith({ slipDeg = 45, speed = 60, throttle = 1 }), nil, DT)
		local drifting = skid.sounds[1].playing
		check(
			"the clip runs whenever the car is rolling, and stops only in the air or under MinSpeed",
			rollingOn and slowOff and backOn and airOff and drifting,
			`straight {rollingOn}, under {S.MinSpeed} studs/s {not slowOff}, rolling again {backOn}, `
				.. `airborne {not airOff}, drifting {drifting}`
		)

		----------------------------------------------------------------------
		-- Cut, the switch, and the thing that matters: IT ALLOCATES NOTHING.
		----------------------------------------------------------------------
		skid:Update(sliding, nil, 10) -- one huge step: straight to the target
		local wasWanted = skid.sounds[1].playing
		local wasPlaying = skid.sounds[1].sound.IsPlaying
		skid:Cut()
		-- The LOGIC's flag, not the instance's: in a quiet playtest the clip is muted AND
		-- never started, so `IsPlaying` is false throughout and would prove nothing here.
		check(
			"Cut silences the squeal at once and stops the clip",
			wasWanted and not skid.sounds[1].playing and not skid.sounds[1].sound.IsPlaying and skid.volume == 0,
			`wanted {wasWanted} -> {skid.sounds[1].playing}; the instance {wasPlaying} -> `
				.. `{skid.sounds[1].sound.IsPlaying} (quiet playtest: {skid:DebugState(nil).quiet})`
		)
		engine.engine.gear = E.GearCount
		engine:Cut()
		check("Cut puts the gearbox back into first", engine.engine.gear == 1, `gear {engine.engine.gear}`)

		engine:SetEnabled(false)
		skid:SetEnabled(false)
		for _ = 1, 120 do
			engine:Update(sliding, nil, DT)
			skid:Update(sliding, nil, DT)
		end
		check(
			"SetEnabled(false) is a real switch, and destroys nothing",
			engine.volume == 0
				and skid.volume < 1e-3
				and engine:CountInstances() + skid:CountInstances() == wantSounds,
			`engine volume {engine.volume}, skid {string.format("%.6f", skid.volume)}, `
				.. `{engine:CountInstances() + skid:CountInstances()} sounds`
		)
		engine:SetEnabled(true)
		skid:SetEnabled(true)

		local soundsAfter = engine:CountInstances() + skid:CountInstances()
		local bodySounds = 0
		for _, child in rig.body:GetChildren() do
			if child:IsA("Sound") then
				bodySounds += 1
			end
		end
		check(
			`{math.floor(SECONDS / DT) + 1920} frames of driving create and destroy no sound`,
			soundsAfter == soundsBefore and bodySounds == wantSounds,
			`before {soundsBefore}, after {soundsAfter}; Sounds under the body {bodySounds}`
		)

		engine:Clear()
		skid:Clear()
		check(
			"Clear takes both sounds away",
			engine:CountInstances() + skid:CountInstances() == 0,
			`{#rig.body:GetChildren()} children left on the body`
		)
		car:Destroy()
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
