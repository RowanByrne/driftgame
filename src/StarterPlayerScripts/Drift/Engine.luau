--!strict
-- Engine: a fake engine for the sound to follow (docs/game/features/engine-sound.md
-- "The fake engine"). PURE: no instances, no services but `ReplicatedStorage` for the
-- config, and nothing in the drive ever reads it. The car's physics has no engine and
-- still has none; this only decides what the engine would be doing, so the sound can say so.
--
-- WHY IT EXISTS. The old engine note was road speed through five fake gears, so a drift
-- -- where the car loses speed while the driver keeps their foot in -- sounded like the car
-- slowing down. In a real drift the rear tyres spin faster than the road, the gear is
-- held, and the revs stay up. Everything below is that sentence, one rule at a time:
--
--   * ROAD RPM. The gearbox is today's geometric one (`gearTops`), and inside a gear the
--     rpm is proportional to speed, like a real ratio: `ShiftRpm` at the gear's top. So an
--     upshift drops the revs by the gear's length ratio, about a third at x1.5.
--   * THE GEAR IS HELD WHILE DRIFTING, and for `HookUpSeconds` after. No shifts sideways.
--   * WHEEL SPIN. While drifting, the driven wheels turn faster than the road by
--     `SpinGain * |sin(slip)|` of it. The rpm in a drift also NEVER FALLS: its floor is a
--     ratchet that takes the spin when the spin is higher and otherwise creeps up by
--     `DriftClimbRpm` a second -- so a slowing drift keeps its revs. Only feathering moves
--     it down, and only for a moment.
--   * THE CEILING (T-147). An ordinary drift tops out at `DriftCeilingRpm`, clearly under
--     the limiter. Only an intense one -- the slip angle past `IntenseFromDeg`, all of it
--     by `IntenseFullDeg` -- lifts the ceiling past the redline and finds the limiter. The
--     ceiling also caps the ratchet, so as the angle closes the revs come down off the top.
--   * ENTRY FLARE. A drift starting kicks the rpm up by `EntryFlareRpm`, settling over
--     `FlareSeconds` (the clutch kick).
--   * FEATHERING. The slip angle opening means more throttle, closing means less: the rpm
--     moves with how fast the slip is changing, up to `FeatherRpm` either way.
--   * THE LIMITER. At `RedlineRpm` the ignition cuts: load to 0 and the rpm drops by
--     `LimiterDropRpm`, then it comes back. `LimiterHz` cuts a second: the stutter.
--   * HOOK-UP. Leaving a drift, the extra revs ease away over `HookUpSeconds` until the
--     rpm is the road's again, then the gearbox catches up -- with a `BlipRpm` blip on each
--     downshift.
--   * LOAD. 1 on throttle, 0 off. There is no throttle INPUT (the control stays one
--     finger), so "off" is inferred: STOP (the handbrake), past 90 degrees of slip (the
--     grip is braking), a flick from one side to the other (`TransitionLiftSeconds`), the
--     instant of an upshift (`ShiftLiftSeconds`), and a limiter cut.
--
-- THE RPM HAS INERTIA. It chases its target at `RevUpRate` going up and `RevDownRate`
-- coming down (per second, exponential), so nothing in it ever steps: a shift is the
-- target falling and the rpm following it down fast, which is what a shift sounds like.
--
-- NOTHING IS ALLOCATED PER FRAME. `step` writes into the engine table it is given, and
-- `feedFrom` into a feed table its caller keeps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Engine = {}

-- What the engine is told each frame. Plain numbers, so a test can drive it without a car.
export type Feed = {
	speed: number, -- studs/s, the car's speed in its own plane
	slip: number, -- radians, signed
	drifting: boolean,
	airborne: boolean,
	braking: boolean, -- past 90 degrees of slip: the grip is a brake
	handbrake: boolean, -- STOP
	throttle: number, -- 0 .. 1, the model's eased throttle
	topSpeed: number, -- the active car's, studs/s
}

export type Engine = {
	rpm: number,
	target: number, -- what the rpm is chasing this frame
	gear: number,
	load: number, -- 0 .. 1, eased
	loadTarget: number,
	tops: { number }, -- gear tops, studs/s, written in place
	topsFor: number,
	sinceShift: number,
	shifts: number,
	upshifts: number,
	downshifts: number,
	-- drift memory
	inDrift: boolean,
	driftTime: number, -- s into the current drift
	driftFloor: number, -- rpm the drift began at: it does not fall below this
	sinceDrift: number, -- s since the last drift ended (hook-up runs on this)
	excess: number, -- rpm above the road's, eased away at hook-up
	flare: number, -- rpm of entry flare still to settle
	blip: number, -- rpm of downshift blip still to settle
	feather: number, -- rpm, smoothed, from the slip's rate of change
	lastSlip: number,
	lastSide: number, -- -1, 0, +1: which way the car was last sideways
	sinceSide: number, -- s since it was last sideways that way
	liftFor: number, -- s of lift still to run (a transition, an upshift)
	-- limiter
	cut: boolean,
	cutFor: number, -- s left in this cut
	cutCooldown: number, -- s before another cut may start
	cuts: number, -- how many there have been, for the tests
	-- measure
	maxRpm: number,
}

local EPS = 1e-4

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- An exponential chase that cannot overshoot on a long frame.
local function chase(value: number, target: number, rate: number, dt: number): number
	return value + (target - value) * math.clamp(rate * dt, 0, 1)
end

--------------------------------------------------------------------------------
-- The gearbox, pure. Today's geometric series, moved here from `Drift/EngineSound`.
--------------------------------------------------------------------------------

-- The gear tops, written INTO `out`. `out[i]` is the speed gear `i` runs up to, and
-- `out[GearCount]` is `topSpeed` exactly. Returns `out`.
function Engine.gearTops(topSpeed: number, out: { number }): { number }
	local E = Config.Fx.Engine
	local m = E.GearLengthMultiplier
	local n = E.GearCount
	local divisor, term = 0, 1
	for _ = 1, n do
		divisor += term
		term *= m
	end
	local first = topSpeed / math.max(divisor, EPS)
	local running = 0
	term = 1
	for i = 1, n do
		running += first * term
		out[i] = running
		term *= m
	end
	out[n] = topSpeed
	return out
end

function Engine.gearBottom(tops: { number }, gear: number): number
	return if gear <= 1 then 0 else tops[gear - 1]
end

-- Which gear `speed` asks for, ONE STEP AT A TIME. Up as soon as the speed is past the
-- gear's top; down only once it is `GearOverlap` under the gear's bottom (the hysteresis
-- that stops a car on a shift point machine-gunning between two gears).
function Engine.wanted(tops: { number }, gear: number, speed: number): number
	local E = Config.Fx.Engine
	local n = E.GearCount
	gear = math.clamp(gear, 1, n)
	if speed > tops[gear] and gear < n then
		return gear + 1
	end
	if speed < Engine.gearBottom(tops, gear) - E.GearOverlap and gear > 1 then
		return gear - 1
	end
	return gear
end

-- The rpm `speed` makes in `gear`: proportional, `ShiftRpm` at the gear's top, never
-- under idle (the clutch slips below that).
function Engine.roadRpm(tops: { number }, gear: number, speed: number): number
	local E = Config.Fx.Engine
	local top = tops[math.clamp(gear, 1, E.GearCount)]
	return math.max(E.IdleRpm, E.ShiftRpm * math.max(speed, 0) / math.max(top, EPS))
end

-- How intense a drift is, 0 .. 1, from its slip angle (radians, absolute): 0 up to
-- `IntenseFromDeg`, 1 from `IntenseFullDeg`, linear between. The drift model is one body
-- with no tyres of its own, so the angle stands in for "all four tyres going".
function Engine.intensity(absSlip: number): number
	local E = Config.Fx.Engine
	local from = math.rad(E.IntenseFromDeg)
	local span = math.max(math.rad(E.IntenseFullDeg) - from, EPS)
	return math.clamp((absSlip - from) / span, 0, 1)
end

--------------------------------------------------------------------------------
-- The engine
--------------------------------------------------------------------------------

function Engine.new(): Engine
	local E = Config.Fx.Engine
	local self: Engine = {
		rpm = E.IdleRpm,
		target = E.IdleRpm,
		gear = 1,
		load = 0,
		loadTarget = 0,
		tops = {},
		topsFor = -1,
		sinceShift = E.MinTimeInGear,
		shifts = 0,
		upshifts = 0,
		downshifts = 0,
		inDrift = false,
		driftTime = 0,
		driftFloor = 0,
		sinceDrift = math.huge,
		excess = 0,
		flare = 0,
		blip = 0,
		feather = 0,
		lastSlip = 0,
		lastSide = 0,
		sinceSide = math.huge,
		liftFor = 0,
		cut = false,
		cutFor = 0,
		cutCooldown = 0,
		cuts = 0,
		maxRpm = E.IdleRpm,
	}
	Engine.gearTops(Config.Drift.TopSpeed, self.tops)
	self.topsFor = Config.Drift.TopSpeed
	return self
end

-- Back to a standing start, for a spawn, a respawn or a teleport: first gear, idle, no
-- drift memory. The box must not walk down five gears from where the car was picked up.
function Engine.reset(self: Engine)
	local E = Config.Fx.Engine
	self.rpm = E.IdleRpm
	self.target = E.IdleRpm
	self.gear = 1
	self.load = 0
	self.loadTarget = 0
	self.sinceShift = E.MinTimeInGear
	self.inDrift = false
	self.driftTime = 0
	self.driftFloor = 0
	self.sinceDrift = math.huge
	self.excess = 0
	self.flare = 0
	self.blip = 0
	self.feather = 0
	self.lastSlip = 0
	self.lastSide = 0
	self.sinceSide = math.huge
	self.liftFor = 0
	self.cut = false
	self.cutFor = 0
	self.cutCooldown = 0
end

-- Fill `out` from the drift model's state and the frame's input. Writes in place.
function Engine.feedFrom(state: any, input: any, out: Feed): Feed
	out.speed = math.sqrt(state.u * state.u + state.v * state.v)
	out.slip = state.slip or 0
	out.drifting = state.drifting == true
	out.airborne = state.airborne == true
	out.braking = state.braking == true
	out.handbrake = input ~= nil and input.handbrake == true
	out.throttle = state.throttle or 1
	out.topSpeed = Config.Drift.TopSpeed
	return out
end

function Engine.newFeed(): Feed
	return {
		speed = 0,
		slip = 0,
		drifting = false,
		airborne = false,
		braking = false,
		handbrake = false,
		throttle = 1,
		topSpeed = Config.Drift.TopSpeed,
	}
end

-- One frame. Mutates `self`.
function Engine.step(self: Engine, feed: Feed, dt: number)
	local E = Config.Fx.Engine
	dt = math.max(dt, 0)
	if dt <= 0 then
		return
	end

	if feed.topSpeed ~= self.topsFor then
		Engine.gearTops(feed.topSpeed, self.tops)
		self.topsFor = feed.topSpeed
		self.gear = math.clamp(self.gear, 1, E.GearCount)
	end

	local speed = feed.speed
	local absSlip = math.min(math.abs(feed.slip), math.pi * 0.5)
	self.sinceShift += dt

	---------------------------------------------------------------- drift entry and exit
	-- HYSTERESIS. The model calls 5 degrees a drift, and a straight's small corrections
	-- cross that all the time; a flare on each would be a car revving at nothing. So the
	-- engine's drift STARTS at `DriftEnterDeg` and `DriftMinSpeed`, and lasts while the
	-- model still says drifting.
	local drifting = feed.drifting and not feed.airborne
	if not self.inDrift then
		drifting = drifting and absSlip >= math.rad(E.DriftEnterDeg) and speed >= E.DriftMinSpeed
	end
	if drifting and not self.inDrift then
		self.inDrift = true
		self.driftTime = 0
		-- The floor is where the revs were as the drift began, plus the kick.
		self.driftFloor = self.rpm
		self.flare = E.EntryFlareRpm
	elseif not drifting and self.inDrift then
		self.inDrift = false
		self.sinceDrift = 0
	end
	if self.inDrift then
		self.driftTime += dt
	else
		self.sinceDrift += dt
	end

	-- A FLICK: the car swaps from sideways one way to sideways the other, inside
	-- `TransitionWindowSeconds`. The driver lifts through it. Only counted between two real
	-- drifts' worth of angle, so the small slip wobble of a straight never trips it, and only
	-- inside the window, so two separate corners the other way round are not a flick.
	local side = 0
	if math.abs(feed.slip) >= math.rad(E.TransitionSlipDeg) then
		side = if feed.slip > 0 then 1 else -1
	end
	self.sinceSide += dt
	if side ~= 0 then
		if self.lastSide ~= 0 and side ~= self.lastSide and self.sinceSide <= E.TransitionWindowSeconds then
			self.liftFor = math.max(self.liftFor, E.TransitionLiftSeconds)
		end
		self.lastSide = side
		self.sinceSide = 0
	end

	---------------------------------------------------------------- the gearbox
	-- Held while drifting and through the hook-up. Otherwise today's box, one gear at a
	-- time, `MinTimeInGear` apart.
	local holding = self.inDrift or self.sinceDrift < E.HookUpSeconds
	if not holding then
		local wanted = Engine.wanted(self.tops, self.gear, speed)
		if wanted ~= self.gear and self.sinceShift >= E.MinTimeInGear then
			if wanted > self.gear then
				self.upshifts += 1
				self.liftFor = math.max(self.liftFor, E.ShiftLiftSeconds)
			else
				self.downshifts += 1
				self.blip = E.BlipRpm
			end
			self.gear = wanted
			self.sinceShift = 0
			self.shifts += 1
		end
	end

	---------------------------------------------------------------- the target
	local road = Engine.roadRpm(self.tops, self.gear, speed)

	-- Feathering: the slip's rate of change, smoothed, as a share of `FeatherSlipRate`.
	-- Opening (|slip| growing) is more throttle, so the revs rise; closing, they fall.
	local slipRate = (math.abs(feed.slip) - math.abs(self.lastSlip)) / dt
	self.lastSlip = feed.slip
	local featherWant = 0
	if self.inDrift then
		featherWant = E.FeatherRpm * math.clamp(slipRate / math.max(E.FeatherSlipRate, EPS), -1, 1)
	end
	self.feather = chase(self.feather, featherWant, E.FeatherResponse, dt)

	local target: number
	local driftCap: number? = nil
	if feed.airborne then
		-- Wheels off the ground, foot in: the engine free-revs into the limiter.
		target = E.RedlineRpm + E.LimiterDropRpm
		self.excess = math.max(target - road, 0)
	elseif self.inDrift then
		-- Spinning tyres: the wheels run faster than the road. The floor is a RATCHET: it
		-- takes the spin whenever the spin is higher and otherwise climbs at
		-- `DriftClimbRpm`, so a drift that bleeds speed keeps its revs (measured on the
		-- real car: without the ratchet a 35-degree drift losing 15 studs/s sagged 900 rpm).
		--
		-- THE CEILING (T-147). Only an intense drift -- a big angle, all four tyres going --
		-- may reach the limiter. An ordinary one tops out at `DriftCeilingRpm`, with its
		-- feathering and flare at most `FeatherRpm` over that. The ceiling rises with the
		-- slip angle from `IntenseFromDeg` to `IntenseFullDeg`, to `IntenseCeilingRpm`, and
		-- it caps the ratchet too: as the car straightens out, the ceiling falls with the
		-- angle and pulls the floor down with it, so the revs leave the limiter while the
		-- car is still sliding instead of only when the drift ends.
		local intensity = Engine.intensity(absSlip)
		local ceiling = lerp(E.DriftCeilingRpm, E.IntenseCeilingRpm, intensity)
		local spin = road * (1 + E.SpinGain * math.sin(absSlip))
		self.driftFloor = math.min(math.max(self.driftFloor + E.DriftClimbRpm * dt, spin), ceiling)
		target = self.driftFloor + self.feather
		driftCap = ceiling + E.FeatherRpm
		self.excess = math.max(math.min(target, driftCap) - road, 0)
	else
		-- Hook-up: whatever the drift left above the road's rpm eases away.
		self.excess = chase(self.excess, 0, 1 / math.max(E.HookUpSeconds, EPS) * 3, dt)
		target = road + self.excess
	end

	self.flare = chase(self.flare, 0, 1 / math.max(E.FlareSeconds, EPS) * 3, dt)
	self.blip = chase(self.blip, 0, 1 / math.max(E.BlipSeconds, EPS) * 3, dt)
	target += self.flare + self.blip
	if driftCap then
		-- The flare and the feathering ride on the floor but not through the ceiling.
		target = math.min(target, driftCap)
	end

	-- Lifting off (STOP, the grip braking): the revs fall towards the road's, with no spin.
	local lifting = feed.handbrake or feed.braking or self.liftFor > 0
	if feed.handbrake or feed.braking then
		target = road
	end

	---------------------------------------------------------------- the limiter
	self.cutCooldown = math.max(self.cutCooldown - dt, 0)
	if self.cut then
		self.cutFor -= dt
		if self.cutFor <= 0 then
			self.cut = false
			self.cutCooldown = 0.5 / math.max(E.LimiterHz, EPS)
		end
	elseif self.rpm >= E.RedlineRpm - 1 and self.cutCooldown <= 0 and not lifting then
		self.cut = true
		self.cuts += 1
		self.cutFor = 0.5 / math.max(E.LimiterHz, EPS)
	end
	-- The target may sit ABOVE the redline -- that is what asking for more than the engine
	-- has looks like -- and the rpm is clamped to it below, so it arrives there rather than
	-- creeping up on it for ever, and the cut can begin.
	if self.cut then
		target = E.RedlineRpm - E.LimiterDropRpm
	end

	---------------------------------------------------------------- the rpm follows
	self.target = target
	local rate = if target > self.rpm then E.RevUpRate else E.RevDownRate
	if self.cut then
		rate = E.LimiterFallRate
	end
	self.rpm = math.clamp(chase(self.rpm, target, rate, dt), E.IdleRpm, E.RedlineRpm)
	if self.rpm > self.maxRpm then
		self.maxRpm = self.rpm
	end

	---------------------------------------------------------------- load
	self.liftFor = math.max(self.liftFor - dt, 0)
	local loadTarget = math.clamp(feed.throttle, 0, 1)
	if lifting or self.cut then
		loadTarget = 0
	end
	self.loadTarget = loadTarget
	self.load = chase(self.load, loadTarget, E.LoadResponse, dt)
end

-- 0 at idle, 1 at the redline. What the sound reads to pick and pitch its loops.
function Engine.rpmShare(self: Engine): number
	local E = Config.Fx.Engine
	return math.clamp((self.rpm - E.IdleRpm) / math.max(E.RedlineRpm - E.IdleRpm, EPS), 0, 1)
end

-- A copy of what the engine is doing, for tests and the debug readout. Allocates.
function Engine.debug(self: Engine)
	return {
		rpm = math.floor(self.rpm + 0.5),
		target = math.floor(self.target + 0.5),
		gear = self.gear,
		load = self.load,
		loadTarget = self.loadTarget,
		inDrift = self.inDrift,
		driftTime = self.driftTime,
		driftFloor = self.driftFloor,
		excess = self.excess,
		flare = self.flare,
		blip = self.blip,
		feather = self.feather,
		cut = self.cut,
		cuts = self.cuts,
		shifts = self.shifts,
		upshifts = self.upshifts,
		downshifts = self.downshifts,
		maxRpm = self.maxRpm,
		share = Engine.rpmShare(self),
	}
end

-- Exposed for the tests: the same easing the module uses.
Engine._lerp = lerp

return Engine
