--!nonstrict
-- EngineTests: the fake engine the sound follows (docs/game/features/engine-sound.md
-- "Testing", T-125). ALL PURE: `Drift/Engine` is plain numbers in and out, so every rule
-- in it is driven here with scripted feeds -- no car, no place, no playtest.
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugEngineTests", "run")
-- or `require(...).run()` directly.
--
-- WHAT IS MEASURED: the revs stay up through a slowing drift; the gear never changes while
-- drifting; the entry flare; feathering moves the revs; the limiter cuts at `RedlineRpm`,
-- recovers and stutters near `LimiterHz`; hook-up brings the revs back to the road's; a
-- downshift blips; load is 0 under STOP, past 90 degrees and through a flick; an upshift
-- drops the revs; a straight's small slip wobble never counts as a drift.
-- WHAT IS NOT: whether any of it sounds right. That is the user's ear.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "EngineTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Engine = require(StarterPlayer.StarterPlayerScripts:WaitForChild("Drift").Engine)
local EngineSound = require(StarterPlayer.StarterPlayerScripts.Drift.EngineSound)

local Tests = {}

local DT = 1 / 60

local function f0(x: number): string
	return string.format("%.0f", x)
end

-- A feed with sensible defaults; `opts` overrides.
local function feed(opts)
	local fd = Engine.newFeed()
	fd.speed = opts.speed or 0
	local slipDeg = opts.slipDeg or 0
	fd.slip = math.rad(slipDeg)
	fd.drifting = math.abs(slipDeg) >= Config.Drift.MinSlipAngleForDrift
	fd.airborne = opts.airborne == true
	fd.braking = math.abs(slipDeg) > 90
	fd.handbrake = opts.handbrake == true
	fd.throttle = if opts.throttle == nil then 1 else opts.throttle
	fd.topSpeed = Config.Drift.TopSpeed
	return fd
end

-- Drive `seconds` of a scripted path: `at(t)` returns the feed opts for time t (0..seconds).
-- `each(e, t)` is called after every step.
local function drive(e, seconds: number, at, each)
	local frames = math.floor(seconds / DT + 0.5)
	for i = 1, frames do
		local t = i * DT
		Engine.step(e, feed(at(t)), DT)
		if each then
			each(e, t)
		end
	end
end

-- An engine brought to a steady straight at `speed`, in whatever gear that is.
local function cruising(speed: number)
	local e = Engine.new()
	local top = Config.Drift.TopSpeed
	-- Accelerate up to it over a few seconds, then hold it, so the box walks up properly.
	drive(e, 6, function(t)
		return { speed = math.min(speed, top * t / 6 * 1.2) }
	end)
	drive(e, 2, function()
		return { speed = speed }
	end)
	return e
end

function Tests.run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local E = Config.Fx.Engine

	----------------------------------------------------------------------------
	-- 1. The config is sane
	----------------------------------------------------------------------------
	check(
		"idle < shift point < redline",
		E.IdleRpm < E.ShiftRpm and E.ShiftRpm < E.RedlineRpm,
		`{E.IdleRpm} < {E.ShiftRpm} < {E.RedlineRpm}`
	)

	----------------------------------------------------------------------------
	-- 2. On a straight: road rpm, upshifts drop the revs, and the box walks up
	----------------------------------------------------------------------------
	do
		local e = Engine.new()
		local top = Config.Drift.TopSpeed
		local drops, before = {}, nil
		local lastGear = 1
		drive(e, 16, function(t)
			return { speed = top * math.min(t / 12, 1) }
		end, function(eng)
			if eng.gear ~= lastGear then
				-- The rpm the frame BEFORE the shift, against the new gear's target.
				table.insert(drops, (before or 0) - eng.target)
				lastGear = eng.gear
			end
			before = eng.rpm
		end)
		local smallest = math.huge
		for _, d in drops do
			smallest = math.min(smallest, d)
		end
		local shown = {}
		for _, d in drops do
			table.insert(shown, f0(d))
		end
		check(
			`a run to top speed walks up to gear {E.GearCount}, and every upshift drops the revs over 1 500 rpm`,
			e.gear == E.GearCount and #drops == E.GearCount - 1 and smallest > 1500,
			`ends in gear {e.gear}; drops {table.concat(shown, ", ")} rpm`
		)
		check(
			"a straight never reaches the limiter",
			e.cuts == 0 and e.maxRpm <= E.ShiftRpm + 300,
			`cuts {e.cuts}, highest {f0(e.maxRpm)} rpm against a shift point of {E.ShiftRpm}`
		)
	end

	----------------------------------------------------------------------------
	-- 3. Small slip wobble on a straight is not a drift
	----------------------------------------------------------------------------
	do
		local e = cruising(90)
		local entered = false
		drive(e, 4, function(t)
			return { speed = 90, slipDeg = 8 * math.sin(t * 6) }
		end, function(eng)
			entered = entered or eng.inDrift
		end)
		check(
			`slip wobbling to 8 degrees (under DriftEnterDeg {E.DriftEnterDeg}) never starts an engine drift`,
			not entered,
			`entered {entered}`
		)
	end

	----------------------------------------------------------------------------
	-- 4. A slowing drift: revs stay up, the gear holds, the entry flares
	----------------------------------------------------------------------------
	do
		local e = cruising(100)
		local gearIn = e.gear
		local rpmIn = e.rpm
		local roadIn = Engine.roadRpm(e.tops, e.gear, 100)
		local shiftsIn = e.shifts
		local peakFlare = 0
		local lowest = math.huge
		local roadOut = 0
		-- 4 s at 35 degrees, losing speed from 100 to 55 studs/s.
		drive(e, 4, function(t)
			return { speed = 100 - 45 * (t / 4), slipDeg = 35 }
		end, function(eng, t)
			if t <= E.FlareSeconds then
				peakFlare = math.max(peakFlare, eng.rpm - rpmIn)
			end
			lowest = math.min(lowest, eng.rpm)
			roadOut = Engine.roadRpm(eng.tops, eng.gear, 100 - 45 * (t / 4))
		end)
		check(
			"through a slowing drift the gear never changes",
			e.shifts == shiftsIn and e.gear == gearIn,
			`gear {gearIn} -> {e.gear}, shifts {shiftsIn} -> {e.shifts}`
		)
		check(
			"the revs stay at or above where the drift began, while the road's revs fall",
			lowest >= rpmIn - 50 and roadOut < roadIn - 1000,
			`began at {f0(rpmIn)} rpm, lowest in the drift {f0(lowest)}; the road's revs `
				.. `{f0(roadIn)} -> {f0(roadOut)} in gear {e.gear}`
		)
		check(
			`the drift's entry flares the revs (EntryFlareRpm {E.EntryFlareRpm})`,
			peakFlare >= E.EntryFlareRpm * 0.4,
			`+{f0(peakFlare)} rpm inside the first {E.FlareSeconds} s`
		)
	end

	----------------------------------------------------------------------------
	-- 5. Feathering moves the revs
	----------------------------------------------------------------------------
	do
		-- Slow and in third, so two seconds of the floor's climb stay under the limiter.
		local steadyE = cruising(40)
		local featherE = cruising(40)
		drive(steadyE, 1.5, function()
			return { speed = 40, slipDeg = 20 }
		end)
		drive(featherE, 1.5, function()
			return { speed = 40, slipDeg = 20 }
		end)
		local function spread(e, wobble)
			local lo, hi = math.huge, -math.huge
			drive(e, 2, function(t)
				return { speed = 40, slipDeg = 20 + wobble * math.sin(t * 2 * math.pi * 1.5) }
			end, function(eng)
				-- The floor's climb is a ramp; take it out so only the wobble is left.
				local v = eng.rpm - E.DriftClimbRpm * eng.driftTime
				lo, hi = math.min(lo, v), math.max(hi, v)
			end)
			return hi - lo, e
		end
		local still = spread(steadyE, 0)
		local moving = spread(featherE, 10)
		check(
			"feathering the angle (20 +-10 degrees at 1.5 Hz) makes the revs wobble where a held angle does not",
			moving > still + 150,
			`spread {f0(moving)} rpm feathered against {f0(still)} held`
		)
	end

	----------------------------------------------------------------------------
	-- 6. A long drift finds the limiter: it cuts at the redline and recovers
	----------------------------------------------------------------------------
	do
		local e = cruising(80)
		local cutStarts = {}
		local wasCut = false
		local backAtTop = 0
		local lowestInCut = math.huge
		local loadInCut = math.huge
		drive(e, 14, function()
			return { speed = 80, slipDeg = 40 }
		end, function(eng, t)
			if eng.cut and not wasCut then
				table.insert(cutStarts, t)
			end
			if eng.cut then
				lowestInCut = math.min(lowestInCut, eng.rpm)
				loadInCut = math.min(loadInCut, eng.load)
			end
			if eng.rpm >= E.RedlineRpm - 1 and #cutStarts > 0 then
				backAtTop += 1
			end
			wasCut = eng.cut
		end)
		local hz = 0
		if #cutStarts >= 3 then
			hz = (#cutStarts - 1) / (cutStarts[#cutStarts] - cutStarts[1])
		end
		check(
			"a held drift reaches the redline and the limiter cuts, more than once",
			#cutStarts >= 3 and e.maxRpm <= E.RedlineRpm + 1e-6,
			`{#cutStarts} cuts, first at {if cutStarts[1] then string.format("%.2f", cutStarts[1]) else "never"} s; `
				.. `highest {f0(e.maxRpm)} rpm (redline {E.RedlineRpm})`
		)
		check(
			`the limiter stutters near LimiterHz ({E.LimiterHz}), dropping the revs and coming back`,
			hz > E.LimiterHz * 0.5 and hz < E.LimiterHz * 1.5 and lowestInCut <= E.RedlineRpm - E.LimiterDropRpm * 0.5 and backAtTop > 0,
			`{string.format("%.1f", hz)} cuts a second; lowest in a cut {f0(lowestInCut)} rpm; back at the top {backAtTop} frames`
		)
		check(
			"the load drops during a cut: the stutter is heard as the note cutting out",
			loadInCut < 0.6,
			`lowest load in a cut {string.format("%.2f", loadInCut)}`
		)
	end

	----------------------------------------------------------------------------
	-- 7. Hook-up: out of the drift, the revs come back to the road's
	----------------------------------------------------------------------------
	do
		local e = cruising(100)
		drive(e, 3, function(t)
			return { speed = 100 - 40 * (t / 3), slipDeg = 35 }
		end)
		local rpmOut = e.rpm
		local gaps = {}
		drive(e, 4, function()
			return { speed = 60 }
		end, function(eng, t)
			if math.abs(t - E.HookUpSeconds) < DT / 2 or math.abs(t - 4) < DT / 2 then
				table.insert(gaps, eng.rpm - Engine.roadRpm(eng.tops, eng.gear, 60))
			end
		end)
		local finalGap = gaps[#gaps] or math.huge
		check(
			"after the drift the revs settle onto the road's revs in the gear the box picks",
			math.abs(finalGap) < 60,
			`left the drift at {f0(rpmOut)} rpm; {f0(gaps[1] or 0)} rpm over the road at {E.HookUpSeconds} s, `
				.. `{f0(finalGap)} after 4 s, in gear {e.gear}`
		)
	end

	----------------------------------------------------------------------------
	-- 8. A downshift blips
	----------------------------------------------------------------------------
	do
		local e = cruising(120)
		local blipped, downs = 0, 0
		drive(e, 6, function(t)
			return { speed = math.max(120 - 25 * t, 5) }
		end, function(eng)
			if eng.downshifts > downs then
				downs = eng.downshifts
				blipped = math.max(blipped, eng.blip)
			end
		end)
		-- Read after the step, so the blip has had one frame of its settle already.
		local want = E.BlipRpm * (1 - math.clamp(3 / E.BlipSeconds * DT, 0, 1))
		check(
			`each downshift adds a blip (BlipRpm {E.BlipRpm})`,
			downs >= 2 and blipped >= want - 1,
			`{downs} downshifts; the blip on a shift's frame {f0(blipped)} rpm, `
				.. `{f0(E.BlipRpm)} less one frame's settle = {f0(want)}`
		)
	end

	----------------------------------------------------------------------------
	-- 9. Load: on throttle, and off under STOP, past 90 degrees and through a flick
	----------------------------------------------------------------------------
	do
		local e = cruising(80)
		local onLoad = e.load
		drive(e, 1, function()
			return { speed = 60, handbrake = true }
		end)
		local stopLoad = e.load
		check(
			"load is 1 cruising and 0 under STOP",
			onLoad > 0.9 and stopLoad < 0.05,
			`cruising {string.format("%.2f", onLoad)}, after 1 s of STOP {string.format("%.3f", stopLoad)}`
		)

		local e2 = cruising(80)
		drive(e2, 1, function()
			return { speed = 50, slipDeg = 120 }
		end)
		check(
			"load is 0 spun past 90 degrees (the grip is braking)",
			e2.load < 0.05,
			`load {string.format("%.3f", e2.load)} at 120 degrees`
		)

		local e3 = cruising(80)
		drive(e3, 1.5, function()
			return { speed = 80, slipDeg = 30 }
		end)
		local lowest = math.huge
		-- A flick: +30 to -30 degrees in 0.3 s, then held.
		drive(e3, 1, function(t)
			local deg = if t < 0.3 then 30 - 200 * t else -30
			return { speed = 80, slipDeg = deg }
		end, function(eng)
			lowest = math.min(lowest, eng.load)
		end)
		check(
			"a flick from one side to the other lifts off the throttle",
			lowest < 0.3 and e3.load > 0.9,
			`load dips to {string.format("%.2f", lowest)} through the flick, back to {string.format("%.2f", e3.load)} after`
		)

		-- Two corners the other way round, seconds apart, are not a flick.
		local e4 = cruising(80)
		drive(e4, 1.5, function()
			return { speed = 80, slipDeg = 30 }
		end)
		drive(e4, 3, function()
			return { speed = 80 }
		end)
		local lowest4 = math.huge
		drive(e4, 1.5, function()
			return { speed = 80, slipDeg = -30 }
		end, function(eng)
			lowest4 = math.min(lowest4, eng.load)
		end)
		check(
			`a drift the other way {3} s after the last is not a flick (TransitionWindowSeconds {E.TransitionWindowSeconds})`,
			lowest4 > 0.9,
			`load stays at or above {string.format("%.2f", lowest4)}`
		)
	end

	----------------------------------------------------------------------------
	-- 10. Reset and no allocation creep
	----------------------------------------------------------------------------
	do
		local e = cruising(150)
		Engine.reset(e)
		check(
			"reset puts the engine back to idle in first",
			e.gear == 1 and e.rpm == E.IdleRpm and not e.inDrift and not e.cut,
			`gear {e.gear}, {f0(e.rpm)} rpm`
		)
	end

	----------------------------------------------------------------------------
	-- 11. The layered mix (T-129), pure: which loops play, how loud, how far pitched
	----------------------------------------------------------------------------
	do
		local L = E.Layers
		local loops = L.Loops
		local n = #loops
		local vols, speeds = table.create(2 * n, 0), table.create(2 * n, 1)
		local function gains(rpm, load, cut)
			local total = EngineSound.mix(rpm, load, cut, vols, speeds)
			return total
		end

		-- On a rev point: that loop alone, at its own pitch.
		local exactOk, exactShown = true, {}
		for i, loop in loops do
			gains(loop.Rpm, 1, false)
			for j = 1, n do
				local want = if j == i then L.Volume else 0
				if math.abs(vols[2 * j - 1] - want) > 1e-6 or vols[2 * j] > 1e-9 then
					exactOk = false
				end
			end
			if math.abs(speeds[2 * i - 1] - 1) > 1e-9 then
				exactOk = false
			end
			table.insert(exactShown, tostring(loop.Rpm))
		end
		check(
			"on each rev point that loop plays alone, at its own pitch, full throttle only",
			exactOk,
			`checked {table.concat(exactShown, ", ")} rpm`
		)

		-- A sweep idle to redline: equal power (the sum of squared gains stays put), the
		-- louder loop never pitched past 25%, no loop past MaxPitchShift, at most two playing.
		local worstPower, worstLoud, worstAny, mostPlaying = 0, 0, 0, 0
		for rpm = loops[1].Rpm, loops[n].Rpm, 7 do
			gains(rpm, 1, false)
			local power, playing, loudest, loudestAt = 0, 0, -1, 1
			for j = 1, n do
				local v = vols[2 * j - 1]
				power += (v / L.Volume) ^ 2
				if v > 1e-6 then
					playing += 1
					-- Exactly the rpm's ratio: a cap biting here would detune the crossfade.
					worstAny = math.max(worstAny, math.abs(speeds[2 * j - 1] - rpm / loops[j].Rpm))
				end
				if v > loudest then
					loudest, loudestAt = v, j
				end
			end
			worstPower = math.max(worstPower, math.abs(power - 1))
			worstLoud = math.max(worstLoud, math.abs(speeds[2 * loudestAt - 1] - 1))
			mostPlaying = math.max(mostPlaying, playing)
		end
		check(
			"sweeping idle to redline, the crossfade is equal power and never more than two loops",
			worstPower < 1e-6 and mostPlaying <= 2,
			`power off by at most {string.format("%.1e", worstPower)}; at most {mostPlaying} loops at once`
		)
		check(
			"the louder loop is never pitched more than 25% from its own rpm, and both are at the rpm's exact ratio",
			worstLoud <= 0.25 + 1e-6 and worstAny <= 1e-9,
			`louder loop at most {string.format("%.1f", worstLoud * 100)}% off its own rpm; the furthest any playing `
				.. `loop is from the exact ratio {string.format("%.1e", worstAny)}`
		)

		-- Load: on throttle the off loops are silent, off throttle the on loops are.
		local mid = math.sqrt(loops[3].Rpm * loops[4].Rpm)
		gains(mid, 1, false)
		local offAtFull = vols[6] + vols[8]
		gains(mid, 0, false)
		local onAtNone = vols[5] + vols[7]
		local offAtNone = vols[6] + vols[8]
		check(
			"full throttle plays only the on loops, none plays only the off loops, OffLoadVolume under",
			offAtFull < 1e-9 and onAtNone < 1e-9 and offAtNone > 0,
			`off at full {offAtFull}, on at none {onAtNone}, off at none {string.format("%.3f", offAtNone)}`
		)

		-- A limiter cut ducks the whole mix.
		local whole = gains(loops[n].Rpm, 1, false)
		local ducked = gains(loops[n].Rpm, 1, true)
		check(
			`a limiter cut ducks the mix to LimiterDuck ({L.LimiterDuck})`,
			math.abs(ducked - whole * L.LimiterDuck) < 1e-9,
			`{string.format("%.3f", whole)} -> {string.format("%.3f", ducked)}`
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
