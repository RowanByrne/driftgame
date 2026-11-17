--!nonstrict
-- HairpinTests: the road's double-yellow bends and true hairpins (`Road/Hairpins`) and the
-- conditional score events built on them (features/score-events.md, T-299 and its send-back):
-- lane drift, perfect lane drift, perfect hairpin (all `Drift/Events/BendDrift`) and reverse
-- entry (`Drift/Events/ReverseEntry`).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugHairpinTests", "run")
--   require(game.ServerScriptService.Tests.HairpinTests).run()   -- pure: Edit works too
--   ...run({ drive = false })                                    -- skip the drives (about 15 s)
--
-- 1. DETECTION on seed 31337, 30 000 studs (and a count on four more seeds): the bends, the
--    true hairpins among them (120 degrees within 250 studs), their shape, the same answer
--    for any chunk and as the road grows, and built on the double yellow's stretches.
-- 2. THE LINES: which side of the double yellow a point is on, the white edge lines, the
--    wheels across the road and how many are out.
-- 3. THE DETECTORS on stand-in drift-model states ridden along real bends of that road, with
--    a recording sink: each way each event completes, voids or never starts.
-- 4. ACHIEVABLE? The real drift model (`Drift/Sim`) on the road's maths (`Drift/SplineWorld`),
--    driven by a slip-holding autopilot through every bend of the first 12 000 studs, in each
--    lane, three ways (a plain drift, a held 4-wheel drift, a scripted reverse entry).
--    Counted, not judged: the checks only ask that each event can be completed at all. How
--    it FEELS is the user's, by driving.
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
local BendDrift = require(DriftFolder.Events.BendDrift)
local LaneDrift = require(DriftFolder.Events.LaneDrift)
local PerfectLaneDrift = require(DriftFolder.Events.PerfectLaneDrift)
local PerfectHairpin = require(DriftFolder.Events.PerfectHairpin)
local ReverseEntry = require(DriftFolder.Events.ReverseEntry)
local Score = require(DriftFolder.Score)
local ScoreEvents = require(DriftFolder.ScoreEvents)

local SEED = 31337
local MORE_SEEDS = { 101, 2024, 8080, 777 }
local LENGTH = 30000
local DRIVE_LENGTH = 12000

local HairpinTests = {}

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

local FIELDS = { "zone", "entry", "apex", "exit", "dir", "radius", "turn", "hairpin", "hairpinTurn", "open" }
local function same(a, b): boolean
	for _, k in FIELDS do
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

local function seconds(e): number
	local sum = 0
	for _, u in e and e.updates or {} do
		sum += u.size * u.dt
	end
	return sum
end

--------------------------------------------------------------------------------
-- stand-in states, ridden along a bend
--------------------------------------------------------------------------------

-- A drift-model state at (s, d) on the road, travelling along it at `speed`, with `into`
-- degrees of slip turned INTO a bend turning `dir` (negative: out of it).
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
		surfaceScore = Config.Drift.ScoreTarmac,
		grounded = true,
		pinned = false,
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

-- The d (searched from `from` toward `to`) at which exactly `want` wheels are out, for a car
-- `into` degrees into bend `h` at its apex, with own side `side` (0: the edge lines only).
local function dWithOut(spline, h, into: number, side: number, want: number, from: number, to: number): number?
	local ds = table.create(4, 0)
	local step = if to > from then 0.05 else -0.05
	for d = from, to, step do
		local st = standIn(spline, h.apex, d, 60, into, h.dir)
		BendDrift.wheelsAcross(st, spline, h.apex, d, ds)
		if BendDrift.wheelsOut(ds, side) == want then
			return d
		end
	end
	return nil
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

-- Drive the real model from 100 studs before a bend's zone to 30 past its exit, aiming down
-- the lane `lane` studs right of the centre line, with every bend detector on. In the bend it
-- holds the slip the lane's curve needs, clamped to [minB, maxB] degrees; `reverse` first
-- swings the nose to 110 degrees into the bend from 40 studs before the entry, then drifts on.
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
	local dets = {
		LaneDrift.new(sink, rig),
		PerfectLaneDrift.new(sink, rig),
		PerfectHairpin.new(sink, rig),
		ReverseEntry.new(sink, rig),
	}
	local input = { steer = 0, handbrake = false }
	local lastS = startS
	local swung = false
	local stats = { vIn = nil, slipMax = 0 }
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
		for _, det in dets do
			det:Update(1 / 60, runner.state)
		end
		if cs >= h.entry and cs <= h.exit then
			stats.vIn = stats.vIn or speed
			stats.slipMax = math.max(stats.slipMax, math.deg(-runner.state.slip * h.dir))
		end
		if cs > h.exit + 30 then
			break
		end
	end
	return sink, dets, stats
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
	local all = Hairpins.bends(spline, 0, spline.length)
	local closed, pins = {}, {}
	for _, h in all do
		if not h.open then
			table.insert(closed, h)
			if h.hairpin then
				table.insert(pins, h)
			end
		end
	end

	-------------------------------------------------------------- 1. detection
	do
		local lines = {}
		for _, h in closed do
			table.insert(lines, `{fmt(h.entry, 0)}{if h.dir > 0 then "L" else "R"} r{fmt(h.radius, 0)} {fmt(h.hairpinTurn, 0)}deg{if h.hairpin then " HAIRPIN" else ""}`)
		end
		table.insert(log, "bends on seed " .. SEED .. " (most turn within the hairpin stretch): " .. table.concat(lines, ", "))
		local more = {}
		for _, seed in MORE_SEEDS do
			local g = SplineGen.new(seed)
			g:extendTo(LENGTH)
			local nb, np = 0, 0
			for _, h in Hairpins.bends(g.spline, 0, g.spline.length) do
				if not h.open then
					nb += 1
					if h.hairpin then
						np += 1
					end
				end
			end
			table.insert(more, `seed {seed}: {np} of {nb}`)
		end
		check(
			"bends and true hairpins found on the seeded road",
			#closed >= 15 and #pins >= 4 and #pins < #closed,
			`seed {SEED}: {#closed} double-yellow bends in {fmt(spline.length, 0)} studs, {#pins} of them hairpins ({T.HairpinDegrees} deg within {T.HairpinStretch} studs), one every {fmt(spline.length / math.max(#pins, 1), 0)}; {table.concat(more, ", ")}`
		)

		local bad = {}
		local prevExit = -math.huge
		for _, h in closed do
			local ok = h.zone <= h.entry and h.entry < h.apex and h.apex < h.exit and math.abs(h.dir) == 1
				and h.radius < Config.Road.CentreLineRadius and h.turn >= T.MinTurnDegrees
				and h.entry - h.zone <= T.EntryZone + 1e-9 and h.zone > prevExit
				and h.hairpin == (h.hairpinTurn >= T.HairpinDegrees) and h.hairpinTurn > 0
			if not ok then
				table.insert(bad, fmt(h.entry, 0))
			end
			prevExit = h.exit
		end
		check("each bend is shaped: zone, entry, apex, exit in order, tight, zones apart, hairpin by its turn", #bad == 0, if #bad == 0 then `all {#closed}` else "bad at " .. table.concat(bad, ", "))

		-- find / around: only the hairpins
		local findOk = #Hairpins.find(spline, 0, LENGTH - 400) == #pins
		local aroundBad, aroundAsked = 0, 0
		for _, h in closed do
			local s = h.zone
			while s <= h.exit do
				aroundAsked += 1
				local a = Hairpins.around(spline, s)
				if h.hairpin then
					if not a or not same(a, h) then
						aroundBad += 1
					end
				elseif a then
					aroundBad += 1
				end
				s += 3.7
			end
		end
		check(
			"around() and find() answer the hairpins only; bendAround() and bends() every bend",
			findOk and aroundBad == 0,
			`find(): {#Hairpins.find(spline, 0, LENGTH - 400)} for {#pins} hairpins; around() at {aroundAsked} points of every zone and bend: {aroundBad} wrong`
		)

		-- the same for any chunk: windows of several sizes and offsets
		local mismatches, windows = 0, 0
		for _, size in { 300, 777, 1500, 4096 } do
			for _, off in { 0, 123 } do
				local seen = {}
				local s0 = off
				while s0 < LENGTH - 400 do
					windows += 1
					for _, h in Hairpins.bends(spline, s0, s0 + size) do
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
					if h.exit < LENGTH - 400 and (not seen[h.entry] or not same(seen[h.entry], h)) then
						mismatches += 1
					end
				end
			end
		end
		local aroundBendBad, asked = 0, 0
		for _, h in closed do
			local s = h.zone
			while s <= h.exit do
				asked += 1
				local a = Hairpins.bendAround(spline, s)
				if not a or not same(a, h) then
					aroundBendBad += 1
				end
				s += 3.7
			end
		end
		check(
			"the same bends, to the bit, from any chunk",
			mismatches == 0 and aroundBendBad == 0,
			`{windows} windows of 300 to 4096 studs at two offsets: {mismatches} differ from the whole road's; bendAround() at {asked} points: {aroundBendBad} differ`
		)

		-- and as the road grows: a road laid only to 6000 studs agrees where it is closed
		local g2 = SplineGen.new(SEED)
		g2:extendTo(6000)
		local grewBad, compared = 0, 0
		local byEntry = {}
		for _, h in closed do
			byEntry[h.entry] = h
		end
		for _, h in Hairpins.bends(g2.spline, 0, g2.spline.length) do
			if not h.open then
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
		local plain = nil
		for s = 300, LENGTH, 50 do
			if #RoadTexture.centreRuns(spline, s - 5, s + 5) == 0 then
				plain = s
				break
			end
		end
		check(
			"each bend lies on the double yellow; none elsewhere",
			noLine == 0 and plain ~= nil and Hairpins.lineAt(spline, plain :: number) == nil,
			`{pts} points along the bends, {noLine} without the line; at {plain and fmt(plain, 0) or "?"} (no line drawn) lineAt is {tostring(plain and Hairpins.lineAt(spline, plain))}`
		)

		local planned, held = 0, 0
		for _, tn in gen.turns do
			if tn[3] == "turnaround" and tn[2] < LENGTH - 300 then
				planned += 1
				for _, h in pins do
					if h.entry < tn[2] and h.exit > tn[1] then
						held += 1
						break
					end
				end
			end
		end
		table.insert(log, `{held} of {planned} planned turnarounds hold a true hairpin (the others turn under 120 deg within the stretch)`)

		-- the cost: a frame asking between bends, and in one (cached once closed)
		local t0 = os.clock()
		local n = 0
		for s = 0, LENGTH - 400, 13 do
			Hairpins.around(spline, s)
			Hairpins.bendAround(spline, s)
			n += 2
		end
		local us = (os.clock() - t0) / n * 1e6
		check("around() is cheap enough to ask every step", us < 100, `{fmt(us, 1)} microseconds a call, mean over {n} calls`)
	end

	-------------------------------------------------------------- 2. the lines
	do
		local hw = Hairpins.lineHalfWidth()
		local R = Config.Road
		local sides = { Hairpins.sideOf(-5), Hairpins.sideOf(-hw - 0.01), Hairpins.sideOf(-0.3), Hairpins.sideOf(0), Hairpins.sideOf(0.3), Hairpins.sideOf(hw + 0.01), Hairpins.sideOf(5) }
		check(
			"which side of the double yellow; where the white edge lines are",
			hw == R.CentreLineGap * 0.5 + R.CentreLineWidth and table.concat(sides, ",") == "-1,-1,0,0,0,1,1" and Hairpins.edgeLine() == R.Width * 0.5 - R.EdgeLineInset,
			`half width {fmt(hw, 3)}; at d -5, -{fmt(hw + 0.01, 2)}, -0.3, 0, 0.3, {fmt(hw + 0.01, 2)}, 5: {table.concat(sides, ", ")}; edge lines' outer sides at ±{Hairpins.edgeLine()}`
		)
		local h = closed[1]
		local D = Config.Drift
		local lo, hi = BendDrift.wheelSpan(standIn(spline, h.apex, 8, 50, 0, h.dir), spline, h.apex, 8)
		local lo9, hi9 = BendDrift.wheelSpan(standIn(spline, h.apex, 8, 50, 90, h.dir), spline, h.apex, 8)
		local e = Hairpins.edgeLine()
		local outs = {
			BendDrift.wheelsOut({ 3, 4, 5, 6 }, 1),
			BendDrift.wheelsOut({ -1, 4, 5, 6 }, 1),
			BendDrift.wheelsOut({ -1, -2, 5, e + 0.1 }, 1),
			BendDrift.wheelsOut({ -1, -2, 5, e + 0.1 }, 0),
			BendDrift.wheelsOut({ -e - 1, -2, 5, e + 0.1 }, 0),
		}
		check(
			"the wheels across the road, and how many are out",
			math.abs(lo - (8 - D.TrackWidth / 2)) < 1e-6 and math.abs(hi - (8 + D.TrackWidth / 2)) < 1e-6 and math.abs(lo9 - (8 - D.Wheelbase / 2)) < 1e-6 and math.abs(hi9 - (8 + D.Wheelbase / 2)) < 1e-6
				and table.concat(outs, ",") == "0,1,3,1,2",
			`straight at d 8: {fmt(lo, 3)}..{fmt(hi, 3)} (track {D.TrackWidth}); square across: {fmt(lo9, 3)}..{fmt(hi9, 3)} (wheelbase {D.Wheelbase}); out: {table.concat(outs, ", ")}`
		)
	end

	-------------------------------------------------------------- 3. the detectors
	do
		-- a hairpin each way, and a bend that is not a hairpin
		local hL, hR, bend
		for _, h in pins do
			if h.dir > 0 and not hL then
				hL = h
			elseif h.dir < 0 and not hR then
				hR = h
			end
		end
		for _, h in closed do
			if not h.hairpin and not bend and h.turn >= 50 then
				bend = h
			end
		end
		local rig = { spline = spline }
		local function go(Mod, h, plan, more)
			local sink = recordingSink()
			local det = Mod.new(sink, rig)
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
		local function said(det)
			return tostring(det.last and det.last.reason)
		end

		for _, h in { hL, hR, bend } do
			local tag = `{if h.hairpin then "hairpin" else "bend"} {if h.dir > 0 then "L" else "R"} at {fmt(h.entry, 0)}`
			local outside = 12 * h.dir -- the outside lane: right of the centre line in a left bend

			-- LANE DRIFT
			local sink, det = go(LaneDrift, h, function()
				return outside, 20
			end)
			local e = one(sink)
			check(
				`{tag}: lane drift on 2 wheels in your lane completes`,
				e and e.finished == true and e.kind == "laneDrift" and #e.updates > 0,
				`{#sink.started} started, finished {tostring(e and e.finished)}, {e and #e.updates or 0} updates of size 1`
			)
			-- one wheel over the double yellow is forgiven; two void
			local own = h.dir -- the outside lane's side of the line
			local d1 = dWithOut(spline, h, 20, own, 1, 6 * own, -2 * own)
			local d2 = dWithOut(spline, h, 20, own, 2, 6 * own, -4 * own)
			local s1, det1 = go(LaneDrift, h, function(s)
				return if s < h.apex then outside else (d1 or outside), 20
			end)
			local s2, det2 = go(LaneDrift, h, function(s)
				return if s < h.apex then outside else (d2 or outside), 20
			end)
			local e1, e2 = one(s1), one(s2)
			check(
				`{tag}: one wheel over the double yellow is forgiven; two void it`,
				d1 ~= nil and d2 ~= nil and e1 and e1.finished == true and e2 and e2.finished == false and said(det2) == "out of the lane",
				`one wheel over (d {d1 and fmt(d1, 2)}): finished {tostring(e1 and e1.finished)}; two (d {d2 and fmt(d2, 2)}): {tostring(e2 and e2.finished)} ({said(det2)})`
			)
			-- and the same at the white edge line
			local e1w = dWithOut(spline, h, 20, own, 1, 20 * own, 30 * own)
			local e2w = dWithOut(spline, h, 20, own, 2, 20 * own, 30 * own)
			local w1 = one((go(LaneDrift, h, function(s)
				return if s < h.apex then outside else (e1w or outside), 20
			end)))
			local s2w, det2w = go(LaneDrift, h, function(s)
				return if s < h.apex then outside else (e2w or outside), 20
			end)
			local w2 = one(s2w)
			check(
				`{tag}: one wheel past the white edge line is forgiven; two void it`,
				e1w ~= nil and e2w ~= nil and w1 and w1.finished == true and w2 and w2.finished == false and said(det2w) == "out of the lane",
				`one (d {e1w and fmt(e1w, 2)}): {tostring(w1 and w1.finished)}; two (d {e2w and fmt(e2w, 2)}): {tostring(w2 and w2.finished)} ({said(det2w)})`
			)
			-- the drift broken for 0.5 s after the apex: void; for 0.1 s: forgiven
			local function breakFor(len)
				local at
				return function(s, t)
					if s >= h.apex and not at then
						at = t
					end
					return outside, if at and t - at < len then 0 else 25
				end
			end
			local sb, detb = go(LaneDrift, h, breakFor(0.5))
			local eb = one(sb)
			local ef = one((go(LaneDrift, h, breakFor(0.1))))
			check(
				`{tag}: lane drift broken voids; a 0.1 s lapse does not`,
				eb and eb.finished == false and said(detb) == "drift broken" and ef and ef.finished == true,
				`0.5 s off: {tostring(eb and eb.finished)} ({said(detb)}); 0.1 s off: {tostring(ef and ef.finished)}`
			)
			-- not drifting at the entry, or drifting out of the bend: nothing starts
			local sl, detl = go(LaneDrift, h, function(s)
				return outside, if s < h.entry + 10 then 0 else 25
			end)
			local sw = go(LaneDrift, h, function()
				return outside, -25
			end)
			check(
				`{tag}: not drifting into it at the entry starts nothing`,
				#sl.started == 0 and #sw.started == 0 and said(detl) == "not drifting",
				`late drift: {#sl.started} ({said(detl)}); out of the bend: {#sw.started}`
			)
			-- a fall voids; a put-back voids, and before the bend gives a fresh try
			local sf, detf = go(LaneDrift, h, function(s)
				return outside, 25, if s >= h.apex then { fell = true } else nil
			end)
			local ef2 = one(sf)
			local jumped = false
			local sj = go(LaneDrift, h, function(s)
				if s >= h.apex and not jumped then
					jumped = true
					return outside, 25, { jump = (h.zone - 20) - s } -- back before the zone
				end
				return outside, 25
			end)
			check(
				`{tag}: a fall or a put-back voids it; put back before it, a fresh try`,
				ef2 and ef2.finished == false and said(detf) == "fell" and #sj.started == 2 and sj.started[1].finished == false and sj.started[2].finished == true,
				`fall: {tostring(ef2 and ef2.finished)}; put back before the zone: {#sj.started} started, {tostring(sj.started[1] and sj.started[1].finished)} then {tostring(sj.started[2] and sj.started[2].finished)}`
			)
			-- the same at 30, 60 and 120 frames a second
			local secs, fins = {}, {}
			for _, fps in { 30, 60, 120 } do
				local e3 = one((go(LaneDrift, h, function()
					return outside, 20
				end, { fps = fps })))
				table.insert(secs, seconds(e3))
				table.insert(fins, tostring(e3 and e3.finished))
			end
			check(
				`{tag}: lane drift the same at 30, 60 and 120 FPS`,
				table.concat(fins, ",") == "true,true,true" and math.abs(secs[1] - secs[3]) < 0.03 * secs[3] and math.abs(secs[2] - secs[3]) < 0.03 * secs[3],
				`finished {table.concat(fins, ", ")}; held {fmt(secs[1], 3)}, {fmt(secs[2], 3)}, {fmt(secs[3], 3)} s`
			)

			-- PERFECT LANE DRIFT
			local sp4, detp4 = go(PerfectLaneDrift, h, function()
				return -outside, 45
			end)
			local p4 = one(sp4)
			local sp2, detp2 = go(PerfectLaneDrift, h, function()
				return outside, 20
			end)
			local spd, detpd = go(PerfectLaneDrift, h, function(s)
				return outside, if s < h.apex then 45 else 20
			end)
			local pd = one(spd)
			local d1p = dWithOut(spline, h, 45, own, 1, 7 * own, -2 * own)
			local sp1 = go(PerfectLaneDrift, h, function(s)
				return if s < h.apex then outside else (d1p or outside), 45
			end)
			local p1 = one(sp1)
			check(
				`{tag}: perfect lane drift: 4 wheels the whole way completes; 2 at the entry starts nothing; dropping to 2 voids; one wheel over is forgiven`,
				p4 and p4.finished == true and p4.kind == "perfectLaneDrift" and #sp2.started == 0 and said(detp2) == "under four wheels"
					and pd and pd.finished == false and said(detpd) == "under four wheels" and d1p ~= nil and p1 and p1.finished == true,
				`4 wheels: {tostring(p4 and p4.finished)}; 2 wheels: {#sp2.started} started ({said(detp2)}); 4 then 2: {tostring(pd and pd.finished)} ({said(detpd)}); one wheel over (d {d1p and fmt(d1p, 2)}): {tostring(p1 and p1.finished)}`
			)

			-- PERFECT HAIRPIN (lenient): any drift, across the double yellow, inside the edge lines
			local sph, detph = go(PerfectHairpin, h, function(s)
				return (if s < h.apex then outside else -outside), 20
			end)
			local ph = sph.started[1]
			if h.hairpin then
				local swo = go(PerfectHairpin, h, function()
					return outside, -25
				end)
				local o2 = dWithOut(spline, h, 20, 0, 2, 20 * own, 30 * own)
				local o1 = dWithOut(spline, h, 20, 0, 1, 20 * own, 30 * own)
				local se2, dete2 = go(PerfectHairpin, h, function(s)
					return if s < h.apex then outside else (o2 or outside), 20
				end)
				local se1 = go(PerfectHairpin, h, function(s)
					return if s < h.apex then outside else (o1 or outside), 20
				end)
				local sbk, detbk = go(PerfectHairpin, h, breakFor(0.6))
				local sbf = go(PerfectHairpin, h, breakFor(0.25))
				local x2, x1, xb, xf = one(se2), one(se1), one(sbk), one(sbf)
				check(
					`{tag}: perfect hairpin: any drift through completes, across the double yellow and either way round`,
					ph and #sph.started == 1 and ph.finished == true and ph.kind == "perfectHairpin" and #swo.started == 1 and swo.started[1].finished == true,
					`crossing the double yellow at the apex: {tostring(ph and ph.finished)} ({said(detph)}); drifting out of the bend: {tostring(swo.started[1] and swo.started[1].finished)}`
				)
				check(
					`{tag}: perfect hairpin: two wheels past an edge line void it, one does not; a 0.6 s break voids, 0.25 s does not`,
					o1 ~= nil and o2 ~= nil and x2 and x2.finished == false and said(dete2) == "past the edge line" and x1 and x1.finished == true
						and xb and xb.finished == false and said(detbk) == "drift broken" and xf and xf.finished == true,
					`one past (d {o1 and fmt(o1, 2)}): {tostring(x1 and x1.finished)}; two (d {o2 and fmt(o2, 2)}): {tostring(x2 and x2.finished)} ({said(dete2)}); 0.6 s: {tostring(xb and xb.finished)}; 0.25 s: {tostring(xf and xf.finished)}`
				)
			else
				check(`{tag}: perfect hairpin does not start on a bend that is not a hairpin`, #sph.started == 0, `{#sph.started} started (turns {fmt(h.hairpinTurn, 0)} deg within {T.HairpinStretch} studs)`)
			end

			-- ONE FEED LINE: the bend's events through a real engine, its feed recorded
			local function feedRide(plan)
				local score = Score.new()
				local eng = ScoreEvents.new()
				eng.print = false
				eng:bind(function()
					return score
				end)
				local seen = {}
				eng.feed:Connect(function(entry)
					table.insert(seen, entry)
				end)
				local sinkE = eng:sink()
				local dets = { LaneDrift.new(sinkE, rig), PerfectLaneDrift.new(sinkE, rig), PerfectHairpin.new(sinkE, rig) }
				local dt = 1 / 120
				local s, t = h.zone - 40, 0
				while s <= h.exit + 20 do
					local d, into = plan(s, t)
					local st = standIn(spline, s, d, 60, into, h.dir)
					eng:step(dt, st)
					for _, det in dets do
						det:Update(dt, st)
					end
					score:Step(dt, st)
					s += 60 * dt
					t += dt
				end
				local ids, voids = {}, 0
				for _, en in seen do
					ids[en.id] = true
					if en.state == "void" then
						voids += 1
					end
				end
				local n = 0
				for _ in ids do
					n += 1
				end
				local banked = 0
				for _, kind in { "laneDrift", "perfectLaneDrift", "perfectHairpin" } do
					local c = eng.counts[kind]
					banked += if c then c.points else 0
				end
				return n, seen[1], seen[#seen], banked, voids
			end
			local W = Config.ScoreEvents.Kinds
			local liveWord = if h.hairpin then W.perfectHairpin.Words[1].text else W.laneDrift.Words[1].text
			local n4, f4, l4, b4 = feedRide(function()
				return outside, 45
			end)
			local n2, _, l2 = feedRide(function()
				return outside, 20
			end)
			local nv, _, lv, _, vv = feedRide(breakFor(0.6))
			local nd, _, ld = feedRide(function(s)
				return outside, if s < h.apex then 45 else 20
			end)
			check(
				`{tag}: the bend's events show as one feed line, worded {liveWord} live, upgraded to the best banked, LOST once`,
				n4 == 1 and f4 and f4.state == "live" and f4.label == liveWord and l4 and l4.state == "banked" and l4.label == W.perfectLaneDrift.Words[1].text
					and math.abs(l4.points - b4) < 1e-6 and b4 > 0
					and n2 == 1 and l2 and l2.state == "banked" and l2.label == liveWord
					and nv == 1 and lv and lv.state == "void" and vv == 1
					and nd == 1 and ld and ld.state == "banked" and ld.label == liveWord,
				`all four wheels: {n4} line, {f4 and f4.label} live, banked as {l4 and l4.label} +{l4 and fmt(l4.points, 0)} (the kinds banked {fmt(b4, 0)}); two wheels: {n2} line, {l2 and l2.label}; broken: {nv} line, {lv and lv.state}, {vv} void entry; 4 then 2: {nd} line, {ld and ld.label}`
			)

			-- REVERSE ENTRY, on every bend
			local swingAt = h.entry - 20
			local sr, detr = go(ReverseEntry, h, function(s)
				return outside, if s < swingAt then 20 elseif s < swingAt + 15 then 110 else 60
			end)
			local r = one(sr)
			local sr2, detr2 = go(ReverseEntry, h, function(s)
				if s < swingAt then
					return outside, 20
				elseif s < swingAt + 15 then
					return outside, 110
				elseif s < h.apex then
					return outside, 0
				end
				return outside, 110
			end)
			local r2 = one(sr2)
			local so = go(ReverseEntry, h, function(s)
				return outside, if s < swingAt then 20 elseif s < swingAt + 15 then -110 else 40
			end)
			local sn = go(ReverseEntry, h, function()
				return outside, 85
			end)
			local ss, dets = go(ReverseEntry, h, function(s)
				return outside, if s < swingAt then 20 else 110
			end, {
				speedAt = function(s)
					return if s < h.apex then 50 else 10
				end,
			})
			local rs = one(ss)
			check(
				`{tag}: reverse entry completes; stops drifting or slows to a crawl voids (once); out of the bend or under 90 starts nothing`,
				r and r.finished == true and r.kind == "reverseEntry" and detr.last.peakDegrees >= 110 - 1e-6
					and r2 and r2.finished == false and said(detr2) == "drift broken" and #sr2.started == 1
					and #so.started == 0 and #sn.started == 0 and rs and rs.finished == false and said(dets) == "drift broken",
				`through: {tostring(r and r.finished)} (peak {fmt(detr.last and detr.last.peakDegrees or 0, 0)}); stopped: {tostring(r2 and r2.finished)} ({said(detr2)}), {#sr2.started} started; out of the bend {#so.started}, 85 deg {#sn.started}; slowed: {tostring(rs and rs.finished)}`
			)
		end
	end

	-------------------------------------------------------------- 4. the drives
	if opts.drive ~= false then
		local Sim = require(DriftFolder.Sim)
		local SplineWorld = require(DriftFolder.SplineWorld)
		local done = { laneDrift = 0, perfectLaneDrift = 0, perfectHairpin = 0, reverseEntry = 0 }
		local tries = { bends = 0, hairpins = 0, reverse = 0 }
		local rows = {}
		local slow = 0
		local SHORT = { laneDrift = "L", perfectLaneDrift = "P", perfectHairpin = "H", reverseEntry = "R" }
		for _, h in closed do
			if h.exit < DRIVE_LENGTH then
				local row = { `{fmt(h.entry, 0)}{if h.dir > 0 then "L" else "R"} r{fmt(h.radius, 0)}{if h.hairpin then " HAIRPIN" else ""}:` }
				for _, laneSide in { -1, 1 } do
					local lane = 12 * laneSide * h.dir -- -1: the inside lane
					for _, way in { "drift", "four", "reverse" } do
						local minB = if way == "four" then 40 else 8
						local sink, _, st = pilot(Sim, SplineWorld, spline, h, lane, 60, minB, 85, way == "reverse")
						tries.bends += 1
						if h.hairpin then
							tries.hairpins += 1
						end
						if way == "reverse" then
							tries.reverse += 1
						end
						local mark = ""
						for _, e in sink.started do
							if e.finished then
								done[e.kind] += 1
								mark ..= SHORT[e.kind] or "?"
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
		table.insert(log, "drives (L = lane drift, P = perfect lane drift, H = perfect hairpin, R = reverse entry, - = none):\n  " .. table.concat(rows, "\n  "))
		check(
			"the autopilot completes each bend event",
			done.laneDrift > 0 and done.perfectLaneDrift > 0 and done.perfectHairpin > 0 and done.reverseEntry > 0,
			`{tries.bends} drives through bends: lane drift {done.laneDrift}, perfect lane drift {done.perfectLaneDrift}; of {tries.hairpins} through hairpins, perfect hairpin {done.perfectHairpin}; of {tries.reverse} scripted swings past 90, reverse entry {done.reverseEntry}`
		)
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
