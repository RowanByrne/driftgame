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
-- Since T-064 it covers the SOUNDS too -- the gearbox, the pitch lerp and the squeal's
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
local EngineSound = require(DriftFolder.EngineSound)
local Model = require(DriftFolder.Model)
local SkidSound = require(DriftFolder.SkidSound)
local Wheels = require(DriftFolder.Wheels)

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
			-- A built surface needs all three colours: the mark, the diffuse smoke and the
			-- stylized puff on top of it.
			if not look or not look.MarkColour or not look.SmokeColour or not look.PuffColour then
				builtOk = false
				table.insert(missing, surface)
			end
		end
		check(
			"every built surface has a mark, a smoke and a puff colour",
			builtOk,
			`built: {table.concat(F.Built, ", ")}{if builtOk then "" else "; incomplete look for " .. table.concat(missing, ", ")}`
		)
		-- THE INSTANCE BUDGET IS THIS FORMULA, and the surfaces are all that is left in it
		-- since the darkness ladder came out:
		-- 4 wheels x (2 Attachments + surfaces x (1 Trail + 2 ParticleEmitters)).
		check(
			"one built surface, and the budget it comes to",
			#F.Built == 1,
			`{#F.Built} surface(s) -> {#CarModel.WHEEL_NAMES * (2 + #F.Built * 3)} instances per car`
		)
		-- ONE DARKNESS, which is the whole of the rollback. A ladder would be a table.
		check(
			"a mark has exactly one darkness",
			type(F.Marks.Transparency) == "number"
				and F.Marks.Transparency > 0
				and F.Marks.Transparency < 1
				and F.Marks.Bands == nil,
			`Marks.Transparency {F.Marks.Transparency}, and no Bands table`
		)
		check(
			"a mark is narrower than the tyre that leaves it",
			F.Marks.Width < Config.Drift.WheelWidth,
			`mark {F.Marks.Width} studs, tyre {Config.Drift.WheelWidth} studs`
		)
		-- `MinSegment` MUST STAY SMALL, and this check is here because it was 0.5 for a
		-- round and that is what turned a chain of hairline band joins into the long
		-- dashes the user photographed: a trail that will not draw until the patch has
		-- moved half a stud starts every fresh ribbon half a stud late. Measured, the
		-- patch advances as little as 0.104 studs in a frame through a real drift, so
		-- anything at or above that drops segments at speed.
		check(
			"a fresh ribbon starts drawing straight away",
			F.Marks.MinSegment < 0.1,
			`MinSegment {F.Marks.MinSegment} studs; the patch advances as little as 0.104 studs a frame`
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
		check(
			"nothing in this feature uploads an asset",
			string.sub(F.Smoke.Texture, 1, 11) == "rbxasset://",
			`smoke texture {F.Smoke.Texture}`
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
		local w = Wheels.new()
		local attached = w:Attach(rig)
		local want = #CarModel.WHEEL_NAMES * (2 + #F.Built * 3)
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

		local function litTrails(): (number, number)
			local lit, maxPerWheel = 0, 0
			for _, wheel in w.wheels do
				local here = 0
				for _, fx in wheel.fx do
					if fx.trail.Enabled then
						here += 1
					end
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
			})
			w:Update(s, { handbrake = frame % 53 == 0 }, 1 / 60)
			local on = w.wheels[1].fx[1].on
			if on ~= lastOn then
				flips += 1
				lastOn = on
			end
			local _, perWheel = litTrails()
			worstPerWheel = math.max(worstPerWheel, perWheel)
			for _, wheel in w.wheels do
				for _, fx in wheel.fx do
					if fx.on and not fx.trail.Enabled then
						blank += 1
					end
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
		-- ONE TRAIL PER WHEEL, EVER. The darkness ladder used to put several between the
		-- same two attachments and switch between them, which is where the breaks in the
		-- user's marks came from; with one there is nothing to switch.
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

		w:Clear()
		check("Clear takes all of them away", w:CountInstances() == 0, `{#rig.body:GetDescendants()} left on the body`)
		car:Destroy()
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
			"pitch runs the full sweep inside every gear",
			math.abs(EngineSound.pitchFor(tops, 1, 0) - E.MinPitch) < 1e-9
				and math.abs(EngineSound.pitchFor(tops, E.GearCount, top) - E.MaxPitch) < 1e-9,
			`{E.MinPitch} at the bottom of 1st, {E.MaxPitch} at the top of {E.GearCount}th`
		)

		-- THE SHIFT ITSELF: how far the pitch TARGET falls at each upshift, which is what
		-- a shift sounds like. Measured here so a change to the sweep or the multiplier
		-- shows up as a number rather than as "it stopped sounding like a shift".
		local drops = {}
		for i = 1, E.GearCount - 1 do
			local at = tops[i] + E.GearOverlap
			drops[i] = EngineSound.pitchFor(tops, i, at) - EngineSound.pitchFor(tops, i + 1, at)
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
		local wantSounds = 1 + #F.Built -- one engine, one squeal per built surface
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
		check(
			"both sounds are the ids the user picked, by id, nothing uploaded",
			rig.body:FindFirstChild(F.Names.Engine).SoundId == E.SoundId
				and rig.body:FindFirstChild(string.format(F.Names.Skid, F.Default)).SoundId == S.SoundIds[F.Default],
			`{E.SoundId} and {S.SoundIds[F.Default]}`
		)
		check(
			"both are 3D: tapered roll-off, so another car is heard where it is",
			rig.body:FindFirstChild(F.Names.Engine).RollOffMode == Enum.RollOffMode.InverseTapered
				and rig.body:FindFirstChild(string.format(F.Names.Skid, F.Default)).RollOffMode
					== Enum.RollOffMode.InverseTapered,
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
		local lastShifts, elapsed = engine.shifts, 0
		local maxPitchStep = 0
		local pitchWas = engine.pitch

		engine:ResetMeasure()
		for frame = 1, SECONDS / DT do
			elapsed += DT
			local speed = top * math.min(frame * DT / (SECONDS * 0.75), 1)
			local s = stateWith({ slipDeg = 0, speed = speed, throttle = 1 })
			engine:Update(s, nil, DT)
			skid:Update(s, nil, DT)
			if engine.shifts ~= lastShifts then
				lastShifts = engine.shifts
				table.insert(shiftAt, engine.lastShiftSpeed)
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
			local was = e2.shifts
			for _ = 1, 600 do
				clock += DT
				e2:Update(flat, nil, DT)
				if e2.shifts ~= was then
					was = e2.shifts
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
				#at == E.GearCount - 1 and tightest >= E.MinTimeInGear - 1e-6 and e2.gear == E.GearCount,
				`{#at} shifts at {table.concat(shown, ", ")} s; tightest {string.format("%.3f", tightest)} s `
					.. `against {E.MinTimeInGear} s; ends in gear {e2.gear}`
			)
			e2:Clear()
		end

		----------------------------------------------------------------------
		-- Pitch is continuous: the lerp, not a snap.
		----------------------------------------------------------------------
		local bound = (E.MaxPitch - E.MinPitch) * E.PitchLerpSpeed * DT
		check(
			"the largest single-frame pitch change over the whole run is inside the lerp's bound",
			maxPitchStep <= bound + 1e-9,
			`largest {string.format("%.5f", maxPitchStep)}, bound {string.format("%.5f", bound)} `
				.. `= ({E.MaxPitch} - {E.MinPitch}) x {E.PitchLerpSpeed}/s x {string.format("%.4f", DT)} s`
		)
		check(
			"and the module's own measure agrees with the one taken here",
			math.abs(engine:ResetMeasure() - maxPitchStep) < 1e-9,
			"ResetMeasure() matches the frame-by-frame maximum"
		)

		----------------------------------------------------------------------
		-- Airborne: the engine free-revs and the squeal cuts dead.
		----------------------------------------------------------------------
		local air = stateWith({ slipDeg = 90, speed = 120, throttle = 1, airborne = true })
		for _ = 1, 600 do -- ten seconds: the lerp is exponential and never arrives exactly
			engine:Update(air, nil, DT)
			skid:Update(air, nil, DT)
		end
		check(
			"airborne pitches to the ceiling and the squeal goes to nothing",
			math.abs(engine.target - E.MaxPitch) < 1e-9 and math.abs(engine.pitch - E.MaxPitch) < 1e-3 and skid.volume < 1e-3,
			`target {E.MaxPitch}, pitch {string.format("%.5f", engine.pitch)}, `
				.. `skid {string.format("%.6f", skid.volume)} at 90 deg of slip in the air`
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
		engine.gear = E.GearCount
		engine:Cut()
		check("Cut puts the gearbox back into first", engine.gear == 1, `gear {engine.gear}`)

		engine:SetEnabled(false)
		skid:SetEnabled(false)
		for _ = 1, 120 do
			engine:Update(sliding, nil, DT)
			skid:Update(sliding, nil, DT)
		end
		check(
			"SetEnabled(false) is a real switch, and destroys nothing",
			engine.target == E.MinPitch
				and skid.volume < 1e-3
				and engine:CountInstances() + skid:CountInstances() == wantSounds,
			`engine target {engine.target}, skid {string.format("%.6f", skid.volume)}, `
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
