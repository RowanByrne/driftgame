--!nonstrict
-- FxTests: the car's wheel effects, measured rather than looked at
-- (docs/game/features/car-fx.md "Testing", docs/workflow/TESTING.md, T-062).
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugFxTests", "run")
--
-- MOST OF IT IS PURE. `Drift/Wheels.evaluate` is the four gates with no instance in it,
-- so every threshold in this feature can be measured without a car, a place or a
-- playtest. Two checks are not pure and say so: the one that builds a stand-in rig and
-- counts the sixteen instances, and the one that drives a thousand frames through it and
-- counts them again.
--
-- WHAT THIS CANNOT TEST is the look, which is the user's, and the sound, which is T-064's
-- and does not exist yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "FxTests is Studio only")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Wheels = require(DriftFolder.Wheels)

local Tests = {}

local FRAMES = 1000 -- frames the allocation check drives through `Update`
local RATE_TOLERANCE = 1e-6

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
			if not F.Surfaces[surface] then
				builtOk = false
				table.insert(missing, surface)
			end
		end
		check(
			"every built surface has a look",
			builtOk,
			`built: {table.concat(F.Built, ", ")}{if builtOk then "" else "; no look for " .. table.concat(missing, ", ")}`
		)
		-- The sixteen-instance budget IS this number. A second built surface is 24.
		check(
			"one built surface, which is the sixteen-instance budget",
			#F.Built == 1,
			`{#F.Built} surface(s) -> {#CarModel.WHEEL_NAMES * (2 + #F.Built * 2)} instances per car`
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
	-- 7. IT ALLOCATES NOTHING. Not pure: it builds a stand-in car.
	----------------------------------------------------------------------------
	if opts.skipInstances ~= true then
		local rig, car = standInRig()
		local w = Wheels.new()
		local attached = w:Attach(rig)
		local want = #CarModel.WHEEL_NAMES * (2 + #F.Built * 2)
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

		-- Now drive it. The slip angle sweeps the whole range and back, the throttle and
		-- the handbrake are toggled, and wheels leave the ground -- so every gate flips
		-- many times over the thousand frames.
		local flips = 0
		local lastOn = false
		for frame = 1, FRAMES do
			local t = frame / FRAMES
			local deg = 180 * math.abs(math.sin(t * math.pi * 7))
			local s = stateWith({
				slipDeg = deg,
				speed = 20 + 100 * math.abs(math.cos(t * math.pi * 3)),
				throttle = if frame % 7 == 0 then 0 else 1,
				airborne = frame % 97 == 0,
			})
			w:Update(s, { handbrake = frame % 53 == 0 }, 1 / 60)
			local on = w.wheels[1].fx[1].on
			if on ~= lastOn then
				flips += 1
				lastOn = on
			end
		end
		local after = w:CountInstances()
		local bodyAfter = #rig.body:GetDescendants()
		check(
			`{FRAMES} frames of driving create and destroy nothing`,
			after == before and bodyAfter == bodyBefore,
			`before {before}, after {after}; under the body {bodyBefore} -> {bodyAfter}; {flips} gate flips in those frames`
		)
		check("and the drive actually worked the gates", flips > 10, `{flips} flips on one wheel`)

		-- Cut and the switch both turn everything off without touching an instance count.
		local lit = stateWith({ slipDeg = 90, speed = 80, throttle = 1 })
		w:Update(lit, { handbrake = false }, 1 / 60)
		local anyOn = false
		for _, wheel in w.wheels do
			for _, fx in wheel.fx do
				anyOn = anyOn or fx.trail.Enabled
			end
		end
		w:Cut()
		local anyAfterCut = false
		for _, wheel in w.wheels do
			for _, fx in wheel.fx do
				anyAfterCut = anyAfterCut or fx.trail.Enabled or fx.emitter.Enabled
			end
		end
		check("Cut puts everything out", anyOn and not anyAfterCut, `lit {anyOn}, after Cut {anyAfterCut}`)

		w:SetEnabled(false)
		w:Update(lit, { handbrake = true }, 1 / 60)
		local anyWhileOff = false
		for _, wheel in w.wheels do
			for _, fx in wheel.fx do
				anyWhileOff = anyWhileOff or fx.trail.Enabled or fx.emitter.Enabled
			end
		end
		check(
			"SetEnabled(false) is a real switch, and destroys nothing",
			not anyWhileOff and w:CountInstances() == want,
			`emitting {anyWhileOff}, instances {w:CountInstances()}`
		)

		w:Clear()
		check("Clear takes all of them away", w:CountInstances() == 0, `{#rig.body:GetDescendants()} left on the body`)
		car:Destroy()
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
