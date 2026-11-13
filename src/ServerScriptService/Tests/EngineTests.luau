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
-- drifting; the entry flare; feathering moves the revs; an ordinary drift stays under the
-- limiter and only an intense one finds it, and leaves it as the angle closes; the limiter cuts at `RedlineRpm`,
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
	-- 6. An intense drift finds the limiter: it cuts at the redline and recovers
	----------------------------------------------------------------------------
	do
		local e = cruising(80)
		local cutStarts = {}
		local wasCut = false
		local backAtTop = 0
		local lowestInCut = math.huge
		local loadInCut = math.huge
		drive(e, 14, function()
			return { speed = 80, slipDeg = 55 }
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
			"an intense drift (55 degrees) reaches the redline and the limiter cuts, more than once",
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
	-- 6b. An ordinary drift stays under the limiter (T-147)
	----------------------------------------------------------------------------
	do
		-- Held at 30 degrees for 8 s bleeding speed, and wobbling 25-35 from a fast entry.
		local function ordinary(entry, at)
			local e = cruising(entry)
			local highest = 0
			drive(e, 8, at, function(eng)
				if eng.inDrift then
					highest = math.max(highest, eng.rpm)
				end
			end)
			return e.cuts, highest
		end
		local heldCuts, heldTop = ordinary(80, function(t)
			return { speed = 80 - 15 * t / 8, slipDeg = 30 }
		end)
		local wobbleCuts, wobbleTop = ordinary(100, function(t)
			return { speed = 100 - 20 * t / 8, slipDeg = 30 + 5 * math.sin(t * 3) }
		end)
		local under = E.RedlineRpm - E.LimiterDropRpm
		check(
			`an ordinary drift (30 degrees held, or 25-35 wobbling) never cuts and stays under {under} rpm`,
			heldCuts == 0 and wobbleCuts == 0 and heldTop < under and wobbleTop < under,
			`held: {heldCuts} cuts, top {f0(heldTop)} rpm; wobbling: {wobbleCuts} cuts, top {f0(wobbleTop)} rpm `
				.. `(DriftCeilingRpm {E.DriftCeilingRpm})`
		)
	end

	----------------------------------------------------------------------------
	-- 6c. Straightening out leaves the limiter while the car still slides (T-147)
	----------------------------------------------------------------------------
	do
		local e = cruising(100)
		-- 3 s at 55 degrees, on the limiter; then the angle closes to 0 over 1 s.
		drive(e, 3, function(t)
			return { speed = 100 - 30 * t / 3, slipDeg = 55 }
		end)
		local cutsIn = e.cuts
		local lastCutAt, offTopAt, slipAtOff = 0, nil, nil
		drive(e, 1.5, function(t)
			return { speed = 70, slipDeg = 55 * math.max(1 - t, 0) }
		end, function(eng, t)
			if eng.cut then
				lastCutAt = t
			end
			if not offTopAt and not eng.cut and eng.rpm < E.RedlineRpm - E.LimiterDropRpm then
				offTopAt = t
				slipAtOff = 55 * math.max(1 - t, 0)
			end
		end)
		check(
			"straightening out from the limiter, the cuts stop within 0.3 s and the revs leave the top while still sideways",
			cutsIn > 0 and lastCutAt <= 0.3 and offTopAt ~= nil and (slipAtOff or 0) >= E.IntenseFromDeg * 0.5,
			`{cutsIn} cuts before; the last cut {string.format("%.2f", lastCutAt)} s after the angle began to close; `
				.. `under {f0(E.RedlineRpm - E.LimiterDropRpm)} rpm at {if offTopAt then string.format("%.2f", offTopAt) else "never"} s, `
				.. `{if slipAtOff then f0(slipAtOff) else "-"} degrees still on`
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
	-- 11. The layered mix (T-129), pure: which loops play, how loud, how far pitched.
	-- ON THE SYNTHESIZED SHEET, by name, whichever sheet the game is playing: these are
	-- that sheet's promises (its 1.52x spacing is what keeps the louder loop inside 25%).
	-- The mix writes the on ladder first, then the off (T-170).
	----------------------------------------------------------------------------
	do
		local L = E.Sheets.Synth
		local loops = L.On
		local n = #loops
		local count = EngineSound.loopCount(L)
		local vols, speeds = table.create(count, 0), table.create(count, 1)
		local function gains(rpm, load, cut)
			local total = EngineSound.mix(rpm, load, cut, vols, speeds, L)
			return total
		end

		-- On a rev point: that loop alone, at its own pitch.
		local exactOk, exactShown = true, {}
		for i, loop in loops do
			gains(loop.Rpm, 1, false)
			for j = 1, n do
				local want = if j == i then L.Volume else 0
				if math.abs(vols[j] - want) > 1e-6 or vols[n + j] > 1e-9 then
					exactOk = false
				end
			end
			if math.abs(speeds[i] - 1) > 1e-9 then
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
				local v = vols[j]
				power += (v / L.Volume) ^ 2
				if v > 1e-6 then
					playing += 1
					-- Exactly the rpm's ratio: a cap biting here would detune the crossfade.
					worstAny = math.max(worstAny, math.abs(speeds[j] - rpm / loops[j].Rpm))
				end
				if v > loudest then
					loudest, loudestAt = v, j
				end
			end
			worstPower = math.max(worstPower, math.abs(power - 1))
			worstLoud = math.max(worstLoud, math.abs(speeds[loudestAt] - 1))
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
		local offAtFull = vols[n + 3] + vols[n + 4]
		gains(mid, 0, false)
		local onAtNone = vols[3] + vols[4]
		local offAtNone = vols[n + 3] + vols[n + 4]
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

	----------------------------------------------------------------------------
	-- 12. TWO LADDERS CHANGE NOTHING (T-170 step 1). The synthesized sheet, in the new
	-- shape, must give every loop EXACTLY the volume and playback speed the old mix gave
	-- it. `OLD` and `oldMix` are the config and the function as they were before the
	-- split (commit fa3adca), frozen here, word for word: one list of rev points, each an
	-- on and off pair, written interleaved (`2i - 1` on, `2i` off).
	----------------------------------------------------------------------------
	do
		local OLD = {
			Volume = 0.84,
			OffLoadVolume = 0.75,
			LimiterDuck = 0.5,
			MaxPitchShift = 0.6,
			Loops = {
				{ Rpm = 900, On = { 0.25, 2.0 }, Off = { 2.85, 2.0 } },
				{ Rpm = 1370, On = { 5.45, 2.014604 }, Off = { 8.05, 2.014604 } },
				{ Rpm = 2090, On = { 10.65, 2.009562 }, Off = { 13.25, 2.009562 } },
				{ Rpm = 3190, On = { 15.85, 1.993729 }, Off = { 18.45, 1.993729 } },
				{ Rpm = 4860, On = { 21.05, 2.0 }, Off = { 23.65, 2.0 } },
				{ Rpm = 7400, On = { 26.25, 1.994604 }, Off = { 28.85, 1.994604 } },
			},
		}
		local function oldMix(rpm: number, load: number, cut: boolean, vols: { number }, speeds: { number }): number
			local L = OLD
			local loops = L.Loops
			local n = #loops
			local shift = L.MaxPitchShift

			local lo, w = 1, 0
			if rpm <= loops[1].Rpm then
				lo, w = 1, 0
			elseif rpm >= loops[n].Rpm then
				lo, w = n - 1, 1
			else
				for i = 1, n - 1 do
					if rpm < loops[i + 1].Rpm then
						lo = i
						w = math.log(rpm / loops[i].Rpm) / math.log(loops[i + 1].Rpm / loops[i].Rpm)
						break
					end
				end
			end
			local gLo = math.cos(w * math.pi * 0.5)
			local gHi = math.sin(w * math.pi * 0.5)

			local l = math.clamp(load, 0, 1)
			local on = math.sqrt(l)
			local off = math.sqrt(1 - l) * L.OffLoadVolume
			local duck = if cut then L.LimiterDuck else 1
			local master = L.Volume * duck

			local total = 0
			for i = 1, n do
				local g = if i == lo then gLo elseif i == lo + 1 then gHi else 0
				local speed = math.clamp(rpm / loops[i].Rpm, 1 - shift, 1 + shift)
				vols[2 * i - 1] = g * on * master
				vols[2 * i] = g * off * master
				speeds[2 * i - 1] = speed
				speeds[2 * i] = speed
				total += vols[2 * i - 1] + vols[2 * i]
			end
			return total
		end

		local S = E.Sheets.Synth
		local n = #OLD.Loops

		-- The same loops, in the same places in the same file.
		local sameSheet = #S.On == n and #S.Off == n
		if sameSheet then
			for i, old in OLD.Loops do
				local on, off = S.On[i], S.Off[i]
				sameSheet = sameSheet
					and on.Rpm == old.Rpm
					and off.Rpm == old.Rpm
					and on.Start == old.On[1]
					and on.Length == old.On[2]
					and off.Start == old.Off[1]
					and off.Length == old.Off[2]
			end
		end
		check(
			"the synthesized sheet is the game's sound, and holds the same twelve loops at the same places as before",
			sameSheet and E.Sheet == "Synth" and S.SoundId == "rbxassetid://132857262391195",
			`Sheet = {tostring(E.Sheet)}, {#S.On} on and {#S.Off} off loops, {tostring(S.SoundId)}`
		)

		-- Every loop's volume and speed, over a grid: 200 to 9 600 rpm (well under idle to
		-- well over the redline) every 3.7 rpm, 21 loads from -0.1 to 1.1 (so the clamp is
		-- in it), with and without a limiter cut.
		local oldVols, oldSpeeds = table.create(2 * n, 0), table.create(2 * n, 1)
		local newVols, newSpeeds = table.create(2 * n, 0), table.create(2 * n, 1)
		local points, compared = 0, 0
		local worstVol, worstSpeed, worstTotal = 0, 0, 0
		if sameSheet then
			local rpm = 200
			while rpm <= 9600 do
				for k = 0, 20 do
					local load = -0.1 + k * 0.06
					for c = 1, 2 do
						local cut = c == 2
						local oldTotal = oldMix(rpm, load, cut, oldVols, oldSpeeds)
						local newTotal = EngineSound.mix(rpm, load, cut, newVols, newSpeeds, S)
						points += 1
						worstTotal = math.max(worstTotal, math.abs(newTotal - oldTotal))
						for i = 1, n do
							worstVol = math.max(
								worstVol,
								math.abs(newVols[i] - oldVols[2 * i - 1]),
								math.abs(newVols[n + i] - oldVols[2 * i])
							)
							worstSpeed = math.max(
								worstSpeed,
								math.abs(newSpeeds[i] - oldSpeeds[2 * i - 1]),
								math.abs(newSpeeds[n + i] - oldSpeeds[2 * i])
							)
							compared += 2
						end
					end
				end
				rpm += 3.7
			end
			-- And exactly on every rev point, where the pair changes.
			for _, old in OLD.Loops do
				for _, load in { 0, 0.5, 1 } do
					oldMix(old.Rpm, load, false, oldVols, oldSpeeds)
					EngineSound.mix(old.Rpm, load, false, newVols, newSpeeds, S)
					points += 1
					for i = 1, n do
						worstVol = math.max(
							worstVol,
							math.abs(newVols[i] - oldVols[2 * i - 1]),
							math.abs(newVols[n + i] - oldVols[2 * i])
						)
						worstSpeed = math.max(
							worstSpeed,
							math.abs(newSpeeds[i] - oldSpeeds[2 * i - 1]),
							math.abs(newSpeeds[n + i] - oldSpeeds[2 * i])
						)
						compared += 2
					end
				end
			end
		end
		check(
			"in the new shape every loop gets exactly the old volume and playback speed, at every rpm, load and cut",
			sameSheet and points > 0 and worstVol == 0 and worstSpeed == 0,
			`{points} points, {compared} loop values compared: largest volume difference {worstVol}, `
				.. `largest speed difference {worstSpeed}`
		)
		check(
			"and the total volume is the old one",
			sameSheet and worstTotal < 1e-12,
			`largest difference {string.format("%.1e", worstTotal)}`
		)

		-- A sheet whose ladders do NOT match (what recorded loops are): each ladder
		-- crossfades between its own rev points, each loop pitched from its own rpm.
		local uneven = {
			Volume = 1,
			OffLoadVolume = 1,
			LimiterDuck = 0.5,
			MaxPitchShift = 0.6,
			On = {
				{ Rpm = 3000, Start = 0, Length = 1 },
				{ Rpm = 5000, Start = 0, Length = 1 },
				{ Rpm = 7000, Start = 0, Length = 1 },
			},
			Off = {
				{ Rpm = 1400, Start = 0, Length = 1 },
				{ Rpm = 6600, Start = 0, Length = 1 },
			},
		}
		local uv, us = table.create(5, 0), table.create(5, 1)
		EngineSound.mix(5000, 0.5, false, uv, us, uneven)
		local half = math.sqrt(0.5)
		local onOk = math.abs(uv[1]) < 1e-9 and math.abs(uv[2] - half) < 1e-9 and math.abs(uv[3]) < 1e-9
		-- 5 000 between 1 400 and 6 600 on a log scale.
		local w = math.log(5000 / 1400) / math.log(6600 / 1400)
		local offOk = math.abs(uv[4] - half * math.cos(w * math.pi / 2)) < 1e-9
			and math.abs(uv[5] - half * math.sin(w * math.pi / 2)) < 1e-9
		local speedOk = math.abs(us[2] - 1) < 1e-9
			and math.abs(us[4] - 1.6) < 1e-9 -- 5 000 / 1 400 is 3.57: capped at 1 + MaxPitchShift
			and math.abs(us[5] - 5000 / 6600) < 1e-9
		check(
			"ladders of different lengths at different revs each crossfade on their own",
			onOk and offOk and speedOk and EngineSound.loopCount(uneven) == 5,
			`at 5000 rpm, half load: on {string.format("%.3f %.3f %.3f", uv[1], uv[2], uv[3])}, `
				.. `off {string.format("%.3f %.3f", uv[4], uv[5])}, off speeds {string.format("%.3f %.3f", us[4], us[5])}`
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
