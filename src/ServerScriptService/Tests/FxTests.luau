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
-- Since T-064 it covers the SOUNDS too -- the gearbox, the pitch lerp and the squeal's
-- gate -- and the line between what a test can check and what only an ear can is worth
-- stating plainly:
--
--   WHAT IS MEASURED HERE  the gear tops against the geometric series, the shift speeds
--                          and their spacing, that no single frame moves the pitch more
--                          than the lerp allows, the squeal's volume against the
--                          configured lerp at every angle and its four ways to be silent,
--                          and that a drive creates and destroys no instance.
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

	----------------------------------------------------------------------------
	-- 8. THE GEARBOX, pure. A geometric series and nothing else.
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
	-- 9. THE SQUEAL'S GATE, pure. Volume is the slip angle and four ways to be silent.
	----------------------------------------------------------------------------
	do
		local S = F.Skid
		local function vol(opts)
			return SkidSound.volumeFor(stateWith(opts))
		end

		local worst = 0
		local shown = {}
		for _, deg in { 10, 45, 90 } do
			local got = vol({ slipDeg = deg, speed = 60, throttle = 1 })
			local t = math.clamp(deg / S.MaxSlipDegrees, 0, 1)
			local wanted = S.MinVolume + (1 - S.MinVolume) * t
			worst = math.max(worst, math.abs(got - wanted))
			table.insert(shown, `{deg} deg -> {string.format("%.4f", got)} (want {string.format("%.4f", wanted)})`)
		end
		check(
			"the squeal's volume is the configured lerp of the slip angle",
			worst < 1e-9,
			`{table.concat(shown, "; ")}; worst gap {string.format("%.2e", worst)}`
		)
		check(
			"past the full angle it stays at 1, it does not keep climbing",
			math.abs(vol({ slipDeg = 180, speed = 60, throttle = 1 }) - 1) < 1e-9,
			`180 deg -> {string.format("%.4f", vol({ slipDeg = 180, speed = 60, throttle = 1 }))}`
		)

		local notDrifting = Config.Drift.MinSlipAngleForDrift - 0.01
		check(
			"silent when the car is not drifting, and loud a hundredth of a degree later",
			vol({ slipDeg = notDrifting, speed = 60, throttle = 1 }) == 0
				and vol({ slipDeg = Config.Drift.MinSlipAngleForDrift, speed = 60, throttle = 1 }) > 0,
			`{string.format("%.2f", notDrifting)} deg silent, {Config.Drift.MinSlipAngleForDrift} deg not `
				.. "(the model's own drift threshold, not a second one)"
		)
		check(
			"silent in the air, whatever the angle",
			vol({ slipDeg = 90, speed = 60, throttle = 1, airborne = true }) == 0,
			"90 deg airborne -> 0"
		)
		check(
			"silent under the minimum speed, and not a hundredth above it",
			vol({ slipDeg = 90, speed = S.MinSpeed - 0.01 }) == 0 and vol({ slipDeg = 90, speed = S.MinSpeed }) > 0,
			`{S.MinSpeed - 0.01} studs/s silent, {S.MinSpeed} studs/s not`
		)
		check("silent with no state at all", SkidSound.volumeFor(nil) == 0, "nil -> 0")
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
	-- 10. THE SOUNDS ON A RIG. Not pure: it builds a stand-in car, IN SERVERSTORAGE
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
		local wanted45 = S.MinVolume + (1 - S.MinVolume) * (45 / S.MaxSlipDegrees)
		check(
			"a held 45-degree slide fades the squeal up to its target rather than snapping to it",
			skid.volume < wanted45 and math.abs(skid.volume - wanted45) < 1e-3 and climbed[1] ~= nil,
			`{table.concat(climbed, ", ")} against a target of {string.format("%.4f", wanted45)} `
				.. `at {S.VolumeLerpSpeed}/s`
		)
		local caught = stateWith({ slipDeg = 0, speed = 60, throttle = 1 })
		for _ = 1, 600 do
			skid:Update(caught, nil, DT)
		end
		check("catching it fades the squeal back down to nothing", skid.volume < 1e-3, string.format("%.6f", skid.volume))

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
