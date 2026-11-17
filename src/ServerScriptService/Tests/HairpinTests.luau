--!nonstrict
-- HairpinTests: the road's hairpins (`Road/Hairpins`) and the two hairpin conditional score
-- events built on them, perfect hairpin and reverse entry (`Drift/Events/PerfectHairpin`,
-- `Drift/Events/ReverseEntry`; features/score-events.md, T-299).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugHairpinTests", "run")
--   require(game.ServerScriptService.Tests.HairpinTests).run()   -- pure: Edit works too
--   ...run({ drive = false })                                    -- skip the drives (about 10 s)
--
-- 1. DETECTION on seed 31337, 30 000 studs: what is found, its shape, the same answer for
--    any chunk and as the road grows, and built on the double yellow's stretches.
-- 2. THE DOUBLE YELLOW: which side of it a point is on; the wheels' span across the road.
-- 3. THE DETECTORS on stand-in drift-model states ridden along real hairpins of that road,
--    with a recording sink: each way a perfect hairpin or reverse entry completes or voids.
-- 4. ACHIEVABLE? The real drift model (`Drift/Sim`) on the road's maths (`Drift/SplineWorld`),
--    driven by a slip-holding autopilot through every hairpin of the first 12 000 studs, in
--    each lane, four ways (a plain drift, a capped 2-wheel drift, a held 4-wheel drift, and a
--    scripted reverse entry). Counted, not judged: the checks only ask that each event can
--    be completed at all. How it FEELS is the user's, by driving.
--
-- `run()` returns `{ passed, checks, log }`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "HairpinTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)
local RoadTexture = require(ReplicatedStorage.Shared.Road.RoadTexture)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local PerfectHairpin = require(DriftFolder.Events.PerfectHairpin)
local ReverseEntry = require(DriftFolder.Events.ReverseEntry)

local SEED = 31337
local LENGTH = 30000
local DRIVE_LENGTH = 12000

local HairpinTests = {}

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

local function same(a, b): boolean
	for _, k in { "zone", "entry", "apex", "exit", "dir", "radius", "turn", "open" } do
		if a[k] ~= b[k] then
			return false
		end
	end
	return true
end

-- A sink that records everything a detector asks of it.
local function recordingSink()
	local rec = { started = {} }
	function rec.oneOff(kind, size, info)
		table.insert(rec.started, { kind = kind, oneOff = true, size = size, info = info })
	end
	function rec.start(kind, info)
		local e = { kind = kind, info = info, updates = {}, finished = nil, finishes = 0 }
		table.insert(rec.started, e)
		return {
			update = function(_, size, dt)
				assert(e.finished == nil, "update after finish")
				table.insert(e.updates, { size = size, dt = dt })
			end,
			finish = function(_, completed)
				e.finishes += 1
				e.finished = completed
			end,
		}
	end
	return rec
end

local function sizeSum(e): (number, number, number)
	local sum, lo, hi = 0, math.huge, -math.huge
	for _, u in e.updates do
		sum += u.size * u.dt
		lo = math.min(lo, u.size)
		hi = math.max(hi, u.size)
	end
	return sum, lo, hi
end

local function sums(e): (number, number, number)
	if not e then
		return 0, 0, 0
	end
	return sizeSum(e)
end

--------------------------------------------------------------------------------
-- stand-in states, ridden along a hairpin
--------------------------------------------------------------------------------

-- A drift-model state at (s, d) on the road, travelling along it at `speed`, with `into`
-- degrees of slip turned INTO a hairpin turning `dir` (negative: out of it).
local function standIn(spline, s: number, d: number, speed: number, into: number, dir: number)
	local b = -dir * math.rad(into) -- the model's signed slip: into a left bend is negative
	local yaw = spline:yawAt(s) - b -- the velocity runs along the road; the nose is off it by b
	local pos = spline:surface(s, d) + Vector3.new(0, Config.Drift.RideHeight, 0)
	return {
		position = pos,
		yaw = yaw,
		slip = b,
		u = speed * math.cos(b),
		v = -speed * math.sin(b),
		throttle = 1,
		drifting = math.abs(b) >= math.rad(Config.Drift.MinSlipAngleForDrift),
		wheelsDown = { true, true, true, true },
		airborne = false,
		fell = false,
	}
end

-- Ride from `from` to `to` along the road at `fps`; `plan(s, t)` returns d, into-degrees,
-- and optionally { fell = true } / a jump in s. Every detector is updated each frame.
local function ride(spline, h, detectors, opts)
	local fps = opts.fps or 60
	local dt = 1 / fps
	local speed = opts.speed or 60
	local s = opts.from or (h.zone - 40)
	local to = opts.to or (h.exit + 20)
	local t = 0
	while s <= to do
		local d, into, extra = opts.plan(s, t)
		local st = standIn(spline, s, d, opts.speedAt and opts.speedAt(s, t) or speed, into, h.dir)
		if extra and extra.fell then
			st.fell = true
		end
		for _, det in detectors do
			det:Update(dt, st)
		end
		local v = opts.speedAt and opts.speedAt(s, t) or speed
		s += v * dt
		if extra and extra.jump then
			s += extra.jump
		end
		t += dt
	end
end

--------------------------------------------------------------------------------
-- the autopilot: holds a slip angle that makes the car follow a lane
--------------------------------------------------------------------------------

local function signedAngle(ax: number, az: number, bx: number, bz: number): number
	return math.atan2(bx * az - bz * ax, bx * ax + bz * az)
end

-- The slip at which the grip makes `a` studs/s^2 sideways (the model's quadratic, inverted).
local function slipFor(a: number): number
	local D = Config.Drift
	local fm = D.FrictionMultiplier or 1
	local c0, c1, c2 = D.ConstantFriction * fm, D.SlipFriction * fm, D.SlipSqFriction * fm
	if a <= c0 then
		return 0
	end
	return (-c1 + math.sqrt(math.max(c1 * c1 - 4 * c2 * (c0 - a), 0))) / (2 * c2)
end

-- Drive the real model from 100 studs before a hairpin's zone to 30 past its exit, aiming
-- down the lane `lane` studs right of the centre line. In the hairpin it holds the slip the
-- lane's curve needs, clamped to [minB, maxB] degrees; `reverse` first swings the nose to
-- 110 degrees into the bend from 40 studs before the entry, then drifts on.
local function pilot(Sim, SplineWorld, spline, h, lane: number, v0: number, minB: number, maxB: number, reverse: boolean?)
	local D = Config.Drift
	local world = SplineWorld.new(spline, nil)
	local startS = h.zone - 100
	local cf = spline:frame(startS, D.RideHeight)
	local pos = spline:surface(startS, lane) + Vector3.new(0, D.RideHeight, 0)
	local runner = Sim.newRunner(CFrame.lookAt(pos, pos + cf.LookVector * Vector3.new(1, 0, 1)))
	runner.state.velocity = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit * v0
	runner.state.time = 10
	local sink = recordingSink()
	local rig = { spline = spline }
	local ph, re = PerfectHairpin.new(sink, rig), ReverseEntry.new(sink, rig)
	local input = { steer = 0, handbrake = false }
	local lastS = startS
	local swung = false
	local stats = { vIn = nil, slipMax = 0, frames = 0, four = 0 }
	for _ = 1, 60 * 30 do
		local s = runner.state
		local speed = math.sqrt(s.velocity.X ^ 2 + s.velocity.Z ^ 2)
		local heading = if speed > 1 then Vector3.new(s.velocity.X / speed, 0, s.velocity.Z / speed) else Vector3.new(-math.sin(s.yaw), 0, -math.cos(s.yaw))
		local cs = Hairpins.locate(spline, s.position, lastS) or lastS
		lastS = cs
		local look = math.clamp(speed * 0.7, 20, 80)
		local tp = spline:surface(math.min(cs + look, spline.length), lane)
		local dx, dz = tp.X - s.position.X, tp.Z - s.position.Z
		local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
		local kappa = 2 * math.sin(signedAngle(heading.X, heading.Z, dx / len, dz / len)) / len
		local bmag = slipFor(speed * speed * math.abs(kappa))
		local bStar = -math.sign(kappa) * bmag
		if cs >= h.entry - 30 and cs <= h.exit then
			bStar = -h.dir * math.clamp(bmag, math.rad(minB), math.rad(maxB))
		end
		if reverse and not swung and cs >= h.entry - 40 then
			bStar = -h.dir * math.rad(110)
			swung = -s.slip * h.dir > math.rad(95)
		end
		local r = speed * kappa + 8 * (s.slip - bStar) -- a firm hand on the slip: 4 lags a 4-wheel drift under its gate at the ends
		input.steer = math.clamp(r / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
		Sim.advance(runner, 1 / 60, input, world)
		ph:Update(1 / 60, runner.state)
		re:Update(1 / 60, runner.state)
		if cs >= h.entry and cs <= h.exit then
			stats.vIn = stats.vIn or speed
			stats.frames += 1
			stats.slipMax = math.max(stats.slipMax, math.deg(-runner.state.slip * h.dir))
			if ph.sliding == 4 then
				stats.four += 1
			end
		end
		if cs > h.exit + 30 then
			break
		end
	end
	return sink, ph, re, stats
end

--------------------------------------------------------------------------------

local function runAll(opts)
	opts = opts or {}
	local checks, log = {}, {}
	local function check(name: string, ok: boolean, detail: string)
		table.insert(checks, { name = name, ok = ok == true, detail = detail })
	end

	local T = Hairpins.Tuning
	local gen = SplineGen.new(SEED)
	gen:extendTo(LENGTH)
	local spline = gen.spline
	local all = Hairpins.find(spline, 0, spline.length)
	local closed = {}
	for _, h in all do
		if not h.open then
			table.insert(closed, h)
		end
	end

	-------------------------------------------------------------- 1. detection
	do
		local lines, left = {}, 0
		for _, h in closed do
			if h.dir > 0 then
				left += 1
			end
			table.insert(lines, `{fmt(h.entry, 0)}-{fmt(h.exit, 0)} {if h.dir > 0 then "L" else "R"} r{fmt(h.radius, 0)} {fmt(h.turn, 0)}deg`)
		end
		table.insert(log, "hairpins on seed " .. SEED .. ": " .. table.concat(lines, ", "))
		check(
			"hairpins found on the seeded road",
			#closed >= 10 and left > 0 and left < #closed,
			`{#closed} in {fmt(spline.length, 0)} studs (one every {fmt(spline.length / math.max(#closed, 1), 0)}), {left} left and {#closed - left} right; {#all - #closed} open at the road's end`
		)

		local bad = {}
		local prevExit = -math.huge
		for _, h in closed do
			local ok = h.zone <= h.entry and h.entry < h.apex and h.apex < h.exit and math.abs(h.dir) == 1
				and h.radius < Config.Road.CentreLineRadius and h.turn >= T.MinTurnDegrees
				and h.entry - h.zone <= T.EntryZone + 1e-9 and h.zone > prevExit
			if not ok then
				table.insert(bad, fmt(h.entry, 0))
			end
			prevExit = h.exit
		end
		check("each one is shaped: zone, entry, apex, exit in order, tight, turning enough, zones apart", #bad == 0, if #bad == 0 then `all {#closed}` else "bad at " .. table.concat(bad, ", "))

		-- the same for any chunk: windows of several sizes and offsets
		local mismatches, windows = 0, 0
		for _, size in { 300, 777, 1500, 4096 } do
			for _, off in { 0, 123 } do
				local seen = {}
				local s0 = off
				while s0 < LENGTH - 200 do
					windows += 1
					for _, h in Hairpins.find(spline, s0, s0 + size) do
						if not h.open then
							local prev = seen[h.entry]
							if prev and not same(prev, h) then
								mismatches += 1
							end
							seen[h.entry] = h
						end
					end
					s0 += size
				end
				for _, h in closed do
					if not seen[h.entry] or not same(seen[h.entry], h) then
						mismatches += 1
					end
				end
			end
		end
		local aroundBad, asked = 0, 0
		for _, h in closed do
			local s = h.zone
			while s <= h.exit do
				asked += 1
				local a = Hairpins.around(spline, s)
				if not a or not same(a, h) then
					aroundBad += 1
				end
				s += 3.7
			end
		end
		check(
			"the same hairpins, to the bit, from any chunk",
			mismatches == 0 and aroundBad == 0,
			`{windows} windows of 300 to 4096 studs at two offsets: {mismatches} differ from the whole road's; around() at {asked} points inside zones and bends: {aroundBad} differ`
		)

		-- and as the road grows: a road laid only to 6000 studs agrees where it is closed
		local g2 = SplineGen.new(SEED)
		g2:extendTo(6000)
		local early = Hairpins.find(g2.spline, 0, g2.spline.length)
		local grewBad, compared = 0, 0
		local byEntry = {}
		for _, h in closed do
			byEntry[h.entry] = h
		end
		for _, h in early do
			if not h.open and h.exit < g2.spline.length - 200 then
				compared += 1
				if not byEntry[h.entry] or not same(byEntry[h.entry], h) then
					grewBad += 1
				end
			end
		end
		check("a shorter road finds the same ones", grewBad == 0 and compared >= 3, `{compared} closed on the road at {fmt(g2.spline.length, 0)} studs, {grewBad} differ from the road at {LENGTH}`)

		-- built on the double yellow: every point of every bend has the line
		local noLine, pts = 0, 0
		for _, h in closed do
			local s = h.entry
			while s <= h.exit do
				pts += 1
				if Hairpins.lineAt(spline, s) ~= 0 then
					noLine += 1
				end
				s += 5
			end
		end
		-- and somewhere with no double yellow, lineAt is nil
		local plain = nil
		for s = 300, LENGTH, 50 do
			if #RoadTexture.centreRuns(spline, s - 5, s + 5) == 0 then
				plain = s
				break
			end
		end
		check(
			"each hairpin lies on the double yellow; none elsewhere",
			noLine == 0 and plain ~= nil and Hairpins.lineAt(spline, plain :: number) == nil,
			`{pts} points along the bends, {noLine} without the line; at {plain and fmt(plain, 0) or "?"} (no line drawn) lineAt is {tostring(plain and Hairpins.lineAt(spline, plain))}`
		)

		local planned, held = 0, 0
		for _, tn in gen.turns do
			if tn[3] == "turnaround" and tn[2] < LENGTH - 300 then
				planned += 1
				for _, h in closed do
					if h.entry < tn[2] and h.exit > tn[1] then
						held += 1
						break
					end
				end
			end
		end
		check("every planned turnaround holds a hairpin", planned > 0 and held == planned, `{held} of {planned} turnarounds the generator planned`)

		-- the cost: a frame asking around() between hairpins
		local t0 = os.clock()
		local n = 0
		for s = 0, LENGTH, 13 do
			Hairpins.around(spline, s)
			n += 1
		end
		local us = (os.clock() - t0) / n * 1e6
		check("around() is cheap enough to ask every frame", us < 200, `{fmt(us, 1)} microseconds a call, mean over {n} points`)
	end

	-------------------------------------------------------------- 2. the line
	do
		local hw = Hairpins.lineHalfWidth()
		local R = Config.Road
		local sides = { Hairpins.sideOf(-5), Hairpins.sideOf(-hw - 0.01), Hairpins.sideOf(-0.3), Hairpins.sideOf(0), Hairpins.sideOf(0.3), Hairpins.sideOf(hw + 0.01), Hairpins.sideOf(5) }
		check(
			"which side of the double yellow",
			hw == R.CentreLineGap * 0.5 + R.CentreLineWidth and table.concat(sides, ",") == "-1,-1,0,0,0,1,1",
			`half width {fmt(hw, 3)}; at d -5, -{fmt(hw + 0.01, 2)}, -0.3, 0, 0.3, {fmt(hw + 0.01, 2)}, 5: {table.concat(sides, ", ")}`
		)
		local h = closed[1]
		local D = Config.Drift
		local st = standIn(spline, h.apex, 8, 50, 0, h.dir)
		local lo, hi = PerfectHairpin.wheelSpan(st, spline, h.apex, 8)
		local st90 = standIn(spline, h.apex, 8, 50, 90, h.dir)
		local lo9, hi9 = PerfectHairpin.wheelSpan(st90, spline, h.apex, 8)
		check(
			"the wheels' span across the road",
			math.abs(lo - (8 - D.TrackWidth / 2)) < 1e-6 and math.abs(hi - (8 + D.TrackWidth / 2)) < 1e-6 and math.abs(lo9 - (8 - D.Wheelbase / 2)) < 1e-6 and math.abs(hi9 - (8 + D.Wheelbase / 2)) < 1e-6,
			`straight at d 8: {fmt(lo, 3)}..{fmt(hi, 3)} (track {D.TrackWidth}); square across: {fmt(lo9, 3)}..{fmt(hi9, 3)} (wheelbase {D.Wheelbase})`
		)
	end

	-------------------------------------------------------------- 3. the detectors
	do
		-- one hairpin each way, both closed and well inside the road
		local hL, hR
		for _, h in closed do
			if h.dir > 0 and not hL and h.turn >= 80 then
				hL = h
			elseif h.dir < 0 and not hR and h.turn >= 80 then
				hR = h
			end
		end
		for _, h in { hL, hR } do
			local tag = (if h.dir > 0 then "left" else "right") .. ` hairpin at {fmt(h.entry, 0)}`
			local rig = { spline = spline }
			local function perfect(plan, more)
				local sink = recordingSink()
				local det = PerfectHairpin.new(sink, rig)
				local o = { plan = plan }
				for k, v in more or {} do
					o[k] = v
				end
				ride(spline, h, { det }, o)
				return sink, det
			end
			local function one(sink)
				return #sink.started == 1 and sink.started[1].finishes == 1 and sink.started[1]
			end

			-- complete, 2-wheel: 20 degrees, on the outside lane
			local outside = 12 * h.dir -- the outside lane: right of the centre line in a left bend
			local sink, det = perfect(function()
				return outside, 20
			end)
			local e = one(sink)
			local sum, lo, hi = sums(e)
			check(
				`{tag}: a 2-wheel drift the whole way completes`,
				e and e.finished == true and e.kind == "perfectHairpin" and e.info.level == 2 and lo == 0.5 and hi == 0.5 and det.stats.completed == 1,
				`{#sink.started} started, finished {tostring(e and e.finished)}, level {tostring(e and e.info.level)}, sizes {lo}..{hi}, {e and #e.updates or 0} updates, size x s {fmt(sum, 3)}`
			)
			local sum2 = sum

			-- complete, 4-wheel: 45 degrees, on the inside lane
			sink, det = perfect(function()
				return -outside, 45
			end)
			e = one(sink)
			sum, lo, hi = sums(e)
			check(
				`{tag}: a 4-wheel drift the whole way completes, worth twice`,
				e and e.finished == true and e.info.level == 4 and lo == 1 and hi == 1 and math.abs(sum - 2 * sum2) < 0.02 * sum,
				`finished {tostring(e and e.finished)}, level {tostring(e and e.info.level)}, sizes {lo}..{hi}, size x s {fmt(sum, 3)} against the 2-wheel's {fmt(sum2, 3)}`
			)

			-- 4 wheels to the apex, then 2: completes at level 2
			sink, det = perfect(function(s)
				return outside, if s < h.apex then 45 else 20
			end)
			e = one(sink)
			sum, lo, hi = sums(e)
			check(
				`{tag}: dropping to 2 wheels at the apex completes at level 2`,
				e and e.finished == true and e.info.level == 4 and det.last.level == 2 and lo == 0.5 and hi == 1 and e.info.label == Config.ScoreEvents.Kinds.perfectHairpin.Words[1].text,
				`started at level {tostring(e and e.info.level)}, ended at {tostring(det.last and det.last.level)}, sizes {lo}..{hi}, the line relabelled {tostring(e and e.info.label)}`
			)

			-- crossing the double yellow after the apex: void
			sink, det = perfect(function(s)
				return if s < h.apex then outside else -3 * h.dir, 30
			end)
			e = one(sink)
			check(
				`{tag}: crossing the double yellow voids it`,
				e and e.finished == false and det.last.reason == "crossed the line",
				`finished {tostring(e and e.finished)} ({tostring(det.last and det.last.reason)})`
			)
			-- close to the line but not over it: 7 studs off at 45 degrees (wheels 1.4 clear)
			sink, det = perfect(function()
				return 7 * -h.dir, 45
			end)
			e = one(sink)
			local wlo, whi = PerfectHairpin.wheelSpan(standIn(spline, h.apex, 7 * -h.dir, 60, 45, h.dir), spline, h.apex, 7 * -h.dir)
			check(
				`{tag}: close to the line but never over it completes`,
				e and e.finished == true,
				`finished {tostring(e and e.finished)}; wheels from {fmt(wlo, 2)} to {fmt(whi, 2)} across, the paint's edge at ±{fmt(Hairpins.lineHalfWidth(), 3)}`
			)

			-- the drift broken for 0.5 s after the apex: void; for 0.1 s: forgiven
			local brokeAt
			sink, det = perfect(function(s, t)
				if s >= h.apex and not brokeAt then
					brokeAt = t
				end
				return outside, if brokeAt and t - brokeAt < 0.5 then 0 else 25
			end)
			e = one(sink)
			local brokeAt2
			local sinkB, detB = perfect(function(s, t)
				if s >= h.apex and not brokeAt2 then
					brokeAt2 = t
				end
				return outside, if brokeAt2 and t - brokeAt2 < 0.1 then 0 else 25
			end)
			local eB = one(sinkB)
			check(
				`{tag}: the drift broken voids it; a 0.1 s lapse does not`,
				e and e.finished == false and det.last.reason == "drift broken" and eB and eB.finished == true,
				`0.5 s off: finished {tostring(e and e.finished)} ({tostring(det.last and det.last.reason)}); 0.1 s off: finished {tostring(eB and eB.finished)}`
			)

			-- not drifting at the entry, or drifting the wrong way: nothing starts
			sink, det = perfect(function(s)
				return outside, if s < h.entry + 10 then 0 else 25
			end)
			local sinkW = perfect(function()
				return outside, -25
			end)
			check(
				`{tag}: not drifting into it at the entry starts nothing`,
				#sink.started == 0 and #sinkW.started == 0 and det.last and det.last.reason == "not drifting",
				`late drift: {#sink.started} started ({tostring(det.last and det.last.reason)}); drifting out of the bend: {#sinkW.started} started`
			)

			-- a fall, and a put-back, mid-hairpin: void
			sink, det = perfect(function(s)
				return outside, 25, if s >= h.apex then { fell = true } else nil
			end)
			e = one(sink)
			local jumped = false
			local sinkJ, detJ = perfect(function(s)
				if s >= h.apex and not jumped then
					jumped = true
					return outside, 25, { jump = -150 }
				end
				return outside, 25
			end)
			local eJ = sinkJ.started[1]
			check(
				`{tag}: a fall or a put-back voids it; put back before it, a fresh try`,
				e and e.finished == false and det.last.reason == "fell" and eJ and eJ.finished == false and eJ.finishes == 1
					and #sinkJ.started == 2 and sinkJ.started[2].finished == true,
				`fall: {tostring(e and e.finished)} ({tostring(det.last and det.last.reason)}); put back 150 studs: {tostring(eJ and eJ.finished)}, then {#sinkJ.started} started, the second finished {tostring(sinkJ.started[2] and sinkJ.started[2].finished)}`
			)

			-- the same at 30, 60 and 120 frames a second
			local sums, fins = {}, {}
			for _, fps in { 30, 60, 120 } do
				local s3 = perfect(function()
					return outside, 20
				end, { fps = fps })
				local e3 = one(s3)
				table.insert(sums, if e3 then (sizeSum(e3)) else -1)
				table.insert(fins, tostring(e3 and e3.finished))
			end
			check(
				`{tag}: the same at 30, 60 and 120 FPS`,
				table.concat(fins, ",") == "true,true,true" and math.abs(sums[1] - sums[3]) < 0.03 * sums[3] and math.abs(sums[2] - sums[3]) < 0.03 * sums[3],
				`finished {table.concat(fins, ", ")}; size x s {fmt(sums[1], 3)}, {fmt(sums[2], 3)}, {fmt(sums[3], 3)}`
			)

			-- REVERSE ENTRY
			local function reverse(plan, more)
				local sink2 = recordingSink()
				local det2 = ReverseEntry.new(sink2, rig)
				local o = { plan = plan }
				for k, v in more or {} do
					o[k] = v
				end
				ride(spline, h, { det2 }, o)
				return sink2, det2
			end
			local swingAt = h.entry - 20
			-- past 90 into the bend before the entry, then a 60-degree drift through
			sink, det = reverse(function(s)
				return outside, if s < swingAt then 20 elseif s < swingAt + 15 then 110 else 60
			end)
			e = one(sink)
			check(
				`{tag}: reverse entry, past 90 then drifting through, completes`,
				e and e.finished == true and e.kind == "reverseEntry" and #e.updates > 0 and det.last.peakDegrees >= 110 - 1e-6,
				`{#sink.started} started at {tostring(e and fmt(e.info.at, 0))} ({tostring(e and fmt(e.info.angle, 0))} deg), finished {tostring(e and e.finished)}, peak {fmt(det.last and det.last.peakDegrees or 0, 0)} deg`
			)
			-- past 90, then the drift stops: void; and no second try at the same hairpin
			sink, det = reverse(function(s)
				if s < swingAt then
					return outside, 20
				elseif s < swingAt + 15 then
					return outside, 110
				elseif s < h.apex then
					return outside, 0
				end
				return outside, 110 -- past 90 again: the same hairpin, no second attempt
			end)
			e = one(sink)
			check(
				`{tag}: reverse entry that stops drifting voids, once`,
				e and e.finished == false and det.last.reason == "drift broken" and #sink.started == 1,
				`{#sink.started} started, finished {tostring(e and e.finished)} ({tostring(det.last and det.last.reason)})`
			)
			-- past 90 the wrong way (out of the bend), or never past 90: nothing
			local sinkO = reverse(function(s)
				return outside, if s < swingAt then 20 elseif s < swingAt + 15 then -110 else 40
			end)
			local sinkN = reverse(function()
				return outside, 85
			end)
			check(
				`{tag}: past 90 out of the bend, or under 90, starts nothing`,
				#sinkO.started == 0 and #sinkN.started == 0,
				`out of the bend: {#sinkO.started}; 85 degrees in: {#sinkN.started}`
			)
			-- past 90 but slowing to a crawl: void
			sink, det = reverse(function(s)
				return outside, if s < swingAt then 20 else 110
			end, {
				speedAt = function(s)
					return if s < h.apex then 50 else 10
				end,
			})
			e = one(sink)
			check(
				`{tag}: reverse entry that slows under the slide speed voids`,
				e and e.finished == false and det.last.reason == "drift broken",
				`finished {tostring(e and e.finished)} ({tostring(det.last and det.last.reason)}) at 10 studs/s, under {Config.Fx.Gates.MinMarkSpeed}`
			)
		end
	end

	-------------------------------------------------------------- 4. the drives
	if opts.drive ~= false then
		local Sim = require(DriftFolder.Sim)
		local SplineWorld = require(DriftFolder.SplineWorld)
		local counts = {
			drift = { ph2 = 0, ph4 = 0, tries = 0 },
			two = { ph2 = 0, ph4 = 0, tries = 0 },
			four = { ph2 = 0, ph4 = 0, tries = 0 },
			reverse = { re = 0, tries = 0 },
		}
		local reasons = {}
		local rows = {}
		local slow = 0
		for _, h in closed do
			if h.exit < DRIVE_LENGTH then
				local row = { `{fmt(h.entry, 0)} {if h.dir > 0 then "L" else "R"} r{fmt(h.radius, 0)} {fmt(h.turn, 0)}deg:` }
				for _, laneSide in { -1, 1 } do
					local lane = 12 * laneSide * h.dir -- -1: the inside lane
					for _, way in { "drift", "two", "four", "reverse" } do
						local minB, maxB = 8, 85
						if way == "two" then
							maxB = 28
						elseif way == "four" then
							minB = 40
						end
						local sink, ph, re, st = pilot(Sim, SplineWorld, spline, h, lane, 60, minB, maxB, way == "reverse")
						local c = counts[way]
						c.tries += 1
						local mark = ""
						for _, e in sink.started do
							if e.finished then
								if e.kind == "reverseEntry" then
									c.re += 1
									mark ..= "R"
								elseif ph.last and ph.last.level == 4 then
									c.ph4 = (c.ph4 or 0) + 1
									mark ..= "4"
								else
									c.ph2 = (c.ph2 or 0) + 1
									mark ..= "2"
								end
							end
						end
						for _, last in { ph.last, re.last } do
							if last and last.result ~= "completed" then
								reasons[last.reason] = (reasons[last.reason] or 0) + 1
							end
						end
						table.insert(row, `{if laneSide < 0 then "in" else "out"}/{way} {if mark == "" then "-" else mark} (in at {fmt(st.vIn or 0, 0)}, slip to {fmt(st.slipMax, 0)})`)
					end
				end
				table.insert(rows, table.concat(row, " "))
				slow += 1
				if slow % 3 == 0 then
					task.wait()
				end
			end
		end
		table.insert(log, "drives (2 = perfect hairpin at 2 wheels, 4 = at 4, R = reverse entry, - = nothing completed):\n  " .. table.concat(rows, "\n  "))
		local why = {}
		for k, v in reasons do
			table.insert(why, `{k} {v}`)
		end
		table.sort(why)
		local ph2 = counts.drift.ph2 + counts.two.ph2 + counts.four.ph2
		local ph4 = counts.drift.ph4 + counts.two.ph4 + counts.four.ph4
		check(
			"the autopilot completes perfect hairpins at both levels",
			ph2 > 0 and ph4 > 0,
			`plain drift: {counts.drift.ph2} at 2 wheels and {counts.drift.ph4} at 4 of {counts.drift.tries}; capped at 28 deg: {counts.two.ph2} + {counts.two.ph4} of {counts.two.tries}; held over 40 deg: {counts.four.ph2} + {counts.four.ph4} of {counts.four.tries}. Not completed: {table.concat(why, ", ")}`
		)
		check("the scripted reverse entry completes sometimes", counts.reverse.re > 0, `{counts.reverse.re} of {counts.reverse.tries} scripted swings past 90 degrees carried through`)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = table.concat(log, "\n") }
end

function HairpinTests.run(opts)
	return runAll(opts)
end

return HairpinTests
