--!nonstrict
-- ScandiFlickTests: the Scandinavian flick conditional score event
-- (`Drift/Events/ScandiFlick`; features/score-events.md, T-300).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugScandiFlickTests", "run")
--   require(game.ServerScriptService.Tests.ScandiFlickTests).run()   -- pure: Edit works too
--   ...run({ drive = false })                                        -- skip the drives
--
-- 1. THE DETECTOR on stand-in drift-model states ridden along real hairpins of the seeded
--    road (seed 31337), one each way, with a recording sink: each way a flick completes or
--    voids, and the same at 30, 60 and 120 FPS.
-- 2. ACHIEVABLE? The real drift model (`Drift/Sim`) on the road's maths (`Drift/SplineWorld`),
--    driven by a slip-holding autopilot through every hairpin of the first 12 000 studs, in
--    each lane, flicking at three points before the entry. Counted, not judged: the check
--    asks only that it can be completed at all. How it FEELS is the user's, by driving.
--
-- `run()` returns `{ passed, checks, log }`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "ScandiFlickTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local ScandiFlick = require(DriftFolder.Events.ScandiFlick)

local SEED = 31337
local LENGTH = 14000
local DRIVE_LENGTH = 12000

local ScandiFlickTests = {}

local function fmt(x: number?, p: number?): string
	if x == nil then
		return "nil"
	end
	return string.format("%." .. tostring(p or 1) .. "f", x)
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
				assert(e.finished == nil, "finished twice")
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

--------------------------------------------------------------------------------
-- stand-in states, ridden along a hairpin
--------------------------------------------------------------------------------

-- A drift-model state at (s, d) on the road, travelling along it at `speed`, with `into`
-- degrees of slip turned INTO a hairpin turning `dir` (negative: out of it, the wrong way).
local function standIn(spline, s: number, d: number, speed: number, into: number, dir: number)
	local b = -dir * math.rad(into) -- the model's signed slip: into a left bend is negative
	local yaw = spline:yawAt(s) - b
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
-- and optionally { fell = true } / { jump = studs }.
local function ride(spline, h, det, opts)
	local fps = opts.fps or 60
	local dt = 1 / fps
	local speed = opts.speed or 60
	local s = opts.from or (h.zone - 40)
	local to = opts.to or (h.exit + 20)
	local t = 0
	while s <= to do
		local d, into, extra = opts.plan(s, t)
		local st = standIn(spline, s, d, speed, into, h.dir)
		if extra and extra.fell then
			st.fell = true
		end
		det:Update(dt, st)
		s += speed * dt
		if extra and extra.jump then
			s += extra.jump
		end
		t += dt
	end
end

-- A flick, as a plan: straight up to `outFrom`; `wrong` degrees out of the bend to
-- `outTo`; then the swing, `ramp` seconds from `-wrong` to `into` through zero, with
-- `pause` seconds at zero slip in its middle; then `into` degrees on. `after(s, t, a)` may
-- replace the angle once the swing is done; `extra(s, t)` adds a fall or a jump.
local function flickPlan(h, o)
	o = o or {}
	local outFrom = o.outFrom or (h.zone + 5)
	local outTo = o.outTo or (h.entry - 10)
	local wrong = o.wrong or 45
	local into = o.into or 45
	local ramp = o.ramp or 0.4
	local pause = o.pause or 0
	local d = o.d or 0
	local tOut = nil
	return function(s, t)
		if s < outFrom then
			return d, 0
		end
		if not tOut and s < outTo then
			return d, -wrong
		end
		tOut = tOut or t
		local u = t - tOut
		local half = ramp * 0.5
		local a
		if u < half then
			a = -wrong + wrong * (u / half)
		elseif u < half + pause then
			a = 0
		elseif u < ramp + pause then
			a = into * ((u - half - pause) / half)
		else
			a = into
			if o.after then
				a = o.after(s, t, a) or a
			end
		end
		return d, a, o.extra and o.extra(s, t)
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
-- down the lane `lane` studs right of the centre line (the same autopilot as HairpinTests').
-- The flick, as a driver would try it: from `outAt` studs before the entry it swings to
-- `wrong` degrees OUT of the bend; the moment the attempt starts (the detector's `MinHold`
-- met inside the zone) it flicks, at a full finger, into a drift INTO the bend held between
-- `minIn` and 85 degrees (the 4-wheel drift) to the exit. `st` says what happened, and why
-- the 4-wheel drift first lapsed if it did.
local function pilot(Sim, SplineWorld, spline, h, o)
	local D = Config.Drift
	local G = Config.Fx.Gates
	local lane = o.lane
	-- the speed it arrives at: `v0`, or `k` times the speed a 4-wheel drift at about 31 to
	-- 40 degrees (26 to 31 studs/s^2 of grip) carries round the hairpin's radius without
	-- losing speed, which is what a player who has been drifting arrives at
	local v0 = o.v0 or (o.k * math.sqrt(28 * h.radius))
	local world = SplineWorld.new(spline, nil)
	local startS = math.min(h.zone, h.entry - o.outAt) - 20
	local cf = spline:frame(startS, D.RideHeight)
	local pos = spline:surface(startS, lane) + Vector3.new(0, D.RideHeight, 0)
	local runner = Sim.newRunner(CFrame.lookAt(pos, pos + cf.LookVector * Vector3.new(1, 0, 1)))
	runner.state.velocity = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit * v0
	runner.state.time = 10
	local sink = recordingSink()
	local sf = ScandiFlick.new(sink, { spline = spline })
	local input = { steer = 0, handbrake = false }
	local lastS = startS
	local outFrom = h.entry - o.outAt
	local flicked = false
	local st = { vFlick = nil, outMax = 0, inMin = math.huge, dMax = 0, lapse = nil, holdMax = 0 }
	local prevHeading = nil
	local frame = 0
	for _ = 1, 60 * 30 do
		frame += 1
		local s = runner.state
		local speed = math.sqrt(s.velocity.X ^ 2 + s.velocity.Z ^ 2)
		local heading = if speed > 1 then Vector3.new(s.velocity.X / speed, 0, s.velocity.Z / speed) else Vector3.new(-math.sin(s.yaw), 0, -math.cos(s.yaw))
		-- how fast the travel itself is turning: what the nose must match to hold a slip
		local omega = if prevHeading then signedAngle(prevHeading.X, prevHeading.Z, heading.X, heading.Z) * 60 else 0
		prevHeading = heading
		local cs, cd = Hairpins.locate(spline, s.position, lastS)
		cs = cs or lastS
		lastS = cs
		local look = math.clamp(speed * 0.7, 20, 80)
		local tp = spline:surface(math.min(cs + look, spline.length), lane)
		local dx, dz = tp.X - s.position.X, tp.Z - s.position.Z
		local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
		local kappa = 2 * math.sin(signedAngle(heading.X, heading.Z, dx / len, dz / len)) / len
		local bmag = slipFor(speed * speed * math.abs(kappa))
		local bStar = -math.sign(kappa) * bmag
		if not flicked and (sf.phase == "out" or cs >= h.apex) then
			flicked = true
			st.vFlick = speed
			st.flickS = cs - h.entry
		end
		if not flicked and cs >= outFrom then
			bStar = h.dir * math.rad(o.wrong) -- out of the bend
			st.outMax = math.max(st.outMax, math.deg(s.slip * h.dir))
		elseif flicked and cs <= h.exit then
			bStar = -h.dir * math.clamp(bmag, math.rad(o.minIn), math.rad(85))
			if sf.phase == "in" then
				st.inMin = math.min(st.inMin, math.deg(-s.slip * h.dir))
			end
		end
		if cd and cs >= h.zone and cs <= h.exit then
			st.dMax = math.max(st.dMax, math.abs(cd))
		end
		-- following the lane, the nose turns with the path; holding a slip (out, then in), it
		-- turns with the travel, so the slip sits on its target instead of under it
		local held = (not flicked and cs >= outFrom) or (flicked and cs <= h.exit)
		local r = (if held then omega else speed * kappa) + 8 * (s.slip - bStar)
		input.steer = math.clamp(r / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
		Sim.advance(runner, 1 / 60, input, world)
		sf:Update(1 / 60, runner.state)
		st.holdMax = math.max(st.holdMax, sf.hold)
		if o.trace and frame % 6 == 0 and cs >= h.zone - 30 and cs <= h.exit + 10 then
			local ns = runner.state
			table.insert(o.trace, string.format("s%+4.0f d%+5.1f out%+5.1f v%3.0f n%d %s%s", cs - h.entry, cd or 0, math.deg(ns.slip * h.dir), math.sqrt(ns.u * ns.u + ns.v * ns.v), sf.sliding, sf.phase, if ns.airborne then " AIR" else ""))
		end
		-- why the 4-wheel drift first lapsed, if it did
		local ns = runner.state
		if sf.phase == "in" and sf.bad4 > 0 and not st.lapse then
			local down = 0
			for i = 1, 4 do
				if ns.wheelsDown[i] then
					down += 1
				end
			end
			local v = math.sqrt(ns.u * ns.u + ns.v * ns.v)
			local into = math.deg(-ns.slip * h.dir)
			st.lapse = if ns.airborne or down < 4 then "wheels up"
				elseif v < G.MinMarkSpeed then "slow"
				elseif into < G.MaxSteerDegrees + G.MinSlipDegrees then "slip under the fronts' gate"
				elseif into > 90 then "spun past 90"
				else "other"
			st.lapseAt = { s = sf.s - h.entry, d = sf.d, into = into, v = v, down = down }
		end
		if cs > h.exit + 30 then
			break
		end
	end
	return sink, sf, st
end

--------------------------------------------------------------------------------

local function runAll(opts)
	opts = opts or {}
	local checks, log = {}, {}
	local function check(name: string, ok: boolean, detail: string)
		table.insert(checks, { name = name, ok = ok == true, detail = detail })
	end

	local T = ScandiFlick.Tuning
	local gen = SplineGen.new(SEED)
	gen:extendTo(LENGTH)
	local spline = gen.spline
	local closed = {}
	for _, h in Hairpins.find(spline, 0, spline.length) do
		if not h.open then
			table.insert(closed, h)
		end
	end
	local cut = 0
	for _, h in closed do
		if h.entry - h.zone < Hairpins.Tuning.EntryZone - 1 then
			cut += 1
		end
	end
	table.insert(log, `{#closed} hairpins in {fmt(spline.length, 0)} studs; {cut} with an entry zone cut short by the bend before it`)

	-------------------------------------------------------------- 1. the detector
	do
		-- one hairpin each way: a full entry zone, turning a lot, its apex well past the entry
		local hL, hR
		for _, h in closed do
			local good = h.turn >= 80 and h.entry - h.zone >= Hairpins.Tuning.EntryZone - 1 and h.apex - h.entry >= 40
			if good and h.dir > 0 and not hL then
				hL = h
			elseif good and h.dir < 0 and not hR then
				hR = h
			end
		end
		check("a full-zone hairpin each way to ride", hL ~= nil and hR ~= nil, `left at {fmt(hL and hL.entry, 0)}, right at {fmt(hR and hR.entry, 0)}`)
		for _, h in { hL, hR } do
			if not h then
				continue
			end
			local tag = (if h.dir > 0 then "left" else "right") .. ` hairpin at {fmt(h.entry, 0)} (zone {fmt(h.entry - h.zone, 0)}, apex +{fmt(h.apex - h.entry, 0)}, exit +{fmt(h.exit - h.entry, 0)})`
			local rig = { spline = spline }
			local function go(planOpts, more)
				local sink = recordingSink()
				local det = ScandiFlick.new(sink, rig)
				local o = { plan = flickPlan(h, planOpts) }
				for k, v in more or {} do
					o[k] = v
				end
				ride(spline, h, det, o)
				return sink, det
			end
			local function one(sink)
				return #sink.started == 1 and sink.started[1]
			end

			-- complete: 45 out in the zone, a 0.4 s swing, 45 in to the exit
			local sink, det = go()
			local e = one(sink)
			local sum, lo, hi = 0, 0, 0
			if e then
				sum, lo, hi = sizeSum(e)
			end
			check(
				`{tag}: out, a quick flick, in, held through: completes`,
				e and e.finished == true and e.finishes == 1 and e.kind == "scandiFlick" and e.info.dir == h.dir and lo == 1 and hi == 1 and det.stats.completed == 1 and det.last.reason == "through",
				`{#sink.started} started at {fmt(e and e.info.at, 0)} ({fmt(e and e.info.angle, 0)} deg out), finished {tostring(e and e.finished)}, flick {fmt(det.last and det.last.flick, 3)} s, right way from {fmt(det.last and det.last.flickAt and det.last.flickAt - h.entry, 0)} past the entry, sizes {lo}..{hi}, size x s {fmt(sum, 3)}`
			)

			-- the window: a 0.6 s pause at zero inside the swing is in time, 0.9 s is not
			local sinkA, detA = go({ pause = 0.6, outTo = h.zone + 25 })
			local sinkB, detB = go({ pause = 0.9, outTo = h.zone + 25 })
			local eA, eB = one(sinkA), one(sinkB)
			check(
				`{tag}: a flick inside the {T.Window} s window completes, a slower one voids`,
				eA and eA.finished == true and eB and eB.finished == false and detB.last.reason == "flick too slow",
				`0.6 s pause: {tostring(eA and eA.finished)}, flick {fmt(detA.last and detA.last.flick, 3)} s; 0.9 s pause: {tostring(eB and eB.finished)} ({tostring(detB.last and detB.last.reason)})`
			)

			-- the first drift the hairpin's own way, or not a 4-wheel one: nothing starts
			local sinkW, detW = go({ wrong = -45 }) -- "out" of -45 is 45 INTO the bend
			local sinkT, detT = go({ wrong = 22 }) -- 22 out: the rears slide, the fronts don't
			check(
				`{tag}: a first drift the hairpin's way, or on 2 wheels, starts nothing`,
				#sinkW.started == 0 and #sinkT.started == 0 and detW.stats.started == 0 and detT.stats.started == 0,
				`into the bend first: {#sinkW.started} started; 22 deg out (2 wheels, sliding {detT.sliding} at the end): {#sinkT.started} started`
			)

			-- outside the entry zone: the wrong-way drift all before it, or all after the entry
			local sinkE = go({ outFrom = h.zone - 50, outTo = h.zone - 10 })
			local sinkL = go({ outFrom = h.entry + 2, outTo = h.entry + 30 })
			local sinkM = go({ outFrom = h.zone + 10, outTo = h.zone + 14 }) -- held under MinHold
			check(
				`{tag}: the wrong-way drift outside the zone, or under {T.MinHold} s in it, starts nothing`,
				#sinkE.started == 0 and #sinkL.started == 0 and #sinkM.started == 0,
				`before the zone: {#sinkE.started}; after the entry: {#sinkL.started}; 4 studs (0.07 s) in the zone: {#sinkM.started}`
			)

			-- the flick left until past the apex: void
			local sinkP, detP = go({ outTo = h.apex + 5 })
			local eP = one(sinkP)
			check(
				`{tag}: still drifting the wrong way at the apex voids it`,
				eP and eP.finished == false and detP.last.reason == "flick too late",
				`finished {tostring(eP and eP.finished)} ({tostring(detP.last and detP.last.reason)})`
			)

			-- the 4-wheel drift broken in the hairpin (down to 2 wheels after the apex) for
			-- 0.5 s: void; for 0.1 s: forgiven
			local function lapse(seconds)
				local at = nil
				return go({
					after = function(s, t)
						if s >= h.apex and not at then
							at = t
						end
						if at and t - at < seconds then
							return 20
						end
						return nil
					end,
				})
			end
			local sinkX, detX = lapse(0.5)
			local sinkY = lapse(0.1)
			local eX, eY = one(sinkX), one(sinkY)
			check(
				`{tag}: the 4-wheel drift broken in the hairpin voids it; a 0.1 s lapse does not`,
				eX and eX.finished == false and detX.last.reason == "drift broken" and eY and eY.finished == true,
				`0.5 s on 2 wheels: {tostring(eX and eX.finished)} ({tostring(detX.last and detX.last.reason)}); 0.1 s: {tostring(eY and eY.finished)}`
			)

			-- a fall, and a put-back, mid-hairpin: void
			local sinkF, detF = go({
				extra = function(s)
					return if s >= h.apex then { fell = true } else nil
				end,
			})
			local jumped = false
			local sinkJ, detJ = go({
				extra = function(s)
					if s >= h.apex and not jumped then
						jumped = true
						return { jump = -150 }
					end
					return nil
				end,
			})
			local eF, eJ = one(sinkF), sinkJ.started[1]
			check(
				`{tag}: a fall or a put-back voids it`,
				eF and eF.finished == false and detF.last.reason == "fell" and eJ and eJ.finished == false and eJ.finishes == 1 and #sinkJ.started == 1,
				`fall: {tostring(eF and eF.finished)} ({tostring(detF.last and detF.last.reason)}); put back 150 studs: {tostring(eJ and eJ.finished)} ({tostring(detJ.last and detJ.last.reason)}), {#sinkJ.started} started`
			)

			-- the same at 30, 60 and 120 frames a second
			local sums, fins, flicks = {}, {}, {}
			for _, fps in { 30, 60, 120 } do
				local s3, d3 = go(nil, { fps = fps })
				local e3 = one(s3)
				table.insert(sums, if e3 then (sizeSum(e3)) else -1)
				table.insert(fins, tostring(e3 and e3.finished))
				table.insert(flicks, fmt(d3.last and d3.last.flick, 3))
			end
			check(
				`{tag}: the same at 30, 60 and 120 FPS`,
				table.concat(fins, ",") == "true,true,true" and math.abs(sums[1] - sums[3]) < 0.03 * sums[3] and math.abs(sums[2] - sums[3]) < 0.03 * sums[3],
				`finished {table.concat(fins, ", ")}; size x s {fmt(sums[1], 3)}, {fmt(sums[2], 3)}, {fmt(sums[3], 3)}; flick {table.concat(flicks, ", ")} s`
			)
		end
	end

	-------------------------------------------------------------- 2. the drives
	if opts.drive ~= false then
		local Sim = require(DriftFolder.Sim)
		local SplineWorld = require(DriftFolder.SplineWorld)
		-- the ways tried at each hairpin: lane (studs to the INSIDE of the bend, so -12 is the
		-- outside lane), speed 100 studs before the zone, and where the swing out starts
		local ways = {}
		for _, lane in { 12, 0, -12 } do
			for _, v0 in { 45, 60 } do
				for _, outAt in { 80, 65, 50 } do
					table.insert(ways, { lane = lane, v0 = v0, outAt = outAt, wrong = 38, minIn = 34 })
				end
			end
		end
		local rows, reasons, lapses, flicks = {}, {}, {}, {}
		local byWay = {}
		local tries, done, hairpinsDone, driven = 0, 0, 0, 0
		local n = 0
		for _, h in closed do
			if h.exit >= DRIVE_LENGTH then
				continue
			end
			driven += 1
			local ok, best, why = 0, nil, {}
			for wi, w in ways do
				local o = table.clone(w)
				o.lane = -w.lane * h.dir -- studs right of the centre line
				local sink, sf, st = pilot(Sim, SplineWorld, spline, h, o)
				tries += 1
				local e = sink.started[1]
				local mark
				if e and e.finished then
					done += 1
					ok += 1
					byWay[wi] = (byWay[wi] or 0) + 1
					table.insert(flicks, sf.last.flick)
					if not best or sf.last.flick < best.flick then
						best = { flick = sf.last.flick, w = w, v = st.vFlick, at = st.flickS }
					end
				else
					mark = if e then (sf.last and sf.last.reason or "?") else "not started"
					if mark == "drift broken" and st.lapse then
						lapses[st.lapse] = (lapses[st.lapse] or 0) + 1
					end
					reasons[mark] = (reasons[mark] or 0) + 1
					why[mark] = (why[mark] or 0) + 1
				end
				n += 1
				if n % 6 == 0 then
					task.wait()
				end
			end
			if ok > 0 then
				hairpinsDone += 1
			end
			local wl = {}
			for k, v in why do
				table.insert(wl, `{k} {v}`)
			end
			table.sort(wl)
			table.insert(
				rows,
				`{fmt(h.entry, 0)} {if h.dir > 0 then "L" else "R"} r{fmt(h.radius, 0)} {fmt(h.turn, 0)}deg zone {fmt(h.entry - h.zone, 0)}: {ok} of {#ways}`
					.. (if best then ` (quickest flick {fmt(best.flick, 2)} s, lane {best.w.lane} in, {best.w.v0} st/s start, out from -{best.w.outAt}, {fmt(best.v, 0)} st/s at the flick)` else "")
					.. (if #wl > 0 then "; " .. table.concat(wl, ", ") else "")
			)
		end
		local wayRows = {}
		for wi, w in ways do
			table.insert(wayRows, `lane {w.lane} in, {w.v0} st/s, out from -{w.outAt}: {byWay[wi] or 0}`)
		end
		table.insert(log, "drives, per hairpin (of " .. #ways .. " ways):\n  " .. table.concat(rows, "\n  "))
		table.insert(log, "completed, per way (of " .. driven .. " hairpins):\n  " .. table.concat(wayRows, "\n  "))
		local function list(t)
			local out = {}
			for k, v in t do
				table.insert(out, `{k} {v}`)
			end
			table.sort(out)
			return table.concat(out, ", ")
		end
		table.sort(flicks)
		local fl = if #flicks > 0 then `flick {fmt(flicks[1], 2)} to {fmt(flicks[#flicks], 2)} s` else "no flicks"
		check(
			"the autopilot completes a Scandinavian flick sometimes",
			done > 0,
			`{done} of {tries} drives ({hairpinsDone} of {driven} hairpins at least once); {fl}. Not completed: {list(reasons)}. The 4-wheel drift first lapsed: {list(lapses)}`
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = table.concat(log, "\n") }
end

-- One drive, traced, for tuning the autopilot by hand: the hairpin whose entry is nearest
-- `entry` on the seeded road, and the pilot's options (lane studs to the inside, v0, outAt,
-- wrong, minIn). Returns the result, the stats and a line every 0.1 s.
function ScandiFlickTests.drive(entry: number, o)
	local gen = SplineGen.new(SEED)
	gen:extendTo(LENGTH)
	local spline = gen.spline
	local best = nil
	for _, h in Hairpins.find(spline, 0, spline.length) do
		if not best or math.abs(h.entry - entry) < math.abs(best.entry - entry) then
			best = h
		end
	end
	local h = best
	local trace = {}
	local po = table.clone(o)
	po.lane = -(o.lane or 0) * h.dir
	po.trace = trace
	local sink, sf, st = pilot(require(DriftFolder.Sim), require(DriftFolder.SplineWorld), spline, h, po)
	local e = sink.started[1]
	return {
		hairpin = `{fmt(h.entry, 0)} {if h.dir > 0 then "L" else "R"} r{fmt(h.radius, 0)} zone -{fmt(h.entry - h.zone, 0)} apex +{fmt(h.apex - h.entry, 0)} exit +{fmt(h.exit - h.entry, 0)}`,
		result = if e then tostring(e.finished) else "not started",
		last = sf.last,
		st = st,
		trace = table.concat(trace, "\n"),
	}
end

function ScandiFlickTests.run(opts)
	return runAll(opts)
end

return ScandiFlickTests
