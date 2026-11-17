--!nonstrict
-- NearMissTests: the near miss detector (features/score-events.md, T-298), with a
-- recording sink in place of the score engine:
--   game.ServerStorage.DebugBridge:Invoke("DebugNearMissTests", "run")            -- all
--   game.ServerStorage.DebugBridge:Invoke("DebugNearMissTests", "run", { "unit" })  -- quick
-- `unit`: scripted straight passes by stand-in trunks (close, far, hit, slow, the same tree
-- twice, a fall, frame rates, bushes, the lookup's cost).
-- `drive`: the real model down a real road's maths (`Drift/SplineWorld`, the real grove
-- trunks) by an autopilot: plain driving on the road, then along grove stretches at set
-- distances out on the grass, measuring every pass's closest gap, what fires, and the cost.
-- The drive takes a minute or so: from execute_luau, run it in a task.spawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "NearMissTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")

local Tests = {}

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 2) .. "f", x)
end

local function recorder()
	local rec = { calls = {} }
	rec.sink = {
		oneOff = function(kind, size, info)
			table.insert(rec.calls, { kind = kind, size = size, info = info })
		end,
		start = function()
			error("a near miss never starts a sustained event")
		end,
	}
	return rec
end

--------------------------------------------------------------------------------
-- Unit: stand-in trunks, straight scripted passes
--------------------------------------------------------------------------------

local function unit(check)
	local NearMiss = require(DriftFolder.Events.NearMiss)
	local D = Config.Drift
	local hw = D.BodyWidth * 0.5
	local T = NearMiss.Defaults

	-- a trunk beside the line z = 0, `g` studs of gap from a car driving along x
	local function trunk(x, g, r)
		r = r or 1
		return { x = x, y = 0, z = hw + r + g, h = 20, trunk = r, s = x, side = 1 }
	end
	local function rigFor(trees)
		local rig = { spline = {}, splineAlong = 0, lookups = 0 }
		rig.lookup = function(_, s0, s1, out)
			rig.lookups += 1
			for _, t in trees do
				if t.s >= s0 and t.s < s1 then
					table.insert(out, t)
				end
			end
		end
		return rig
	end
	local function state(x, z, speed, dir, wall, fell)
		return {
			position = Vector3.new(x, 0, z),
			yaw = if dir > 0 then -math.pi / 2 else math.pi / 2,
			velocity = Vector3.new(dir * speed, 0, 0),
			u = speed,
			wallHit = wall or false,
			sinceWall = if wall then 0 else math.huge,
			fell = fell or false,
		}
	end
	-- drive from x0 to x1 at `speed`, z from `zAt(x)` (0), at `fps`; `wallAt`, `fellAt`: x -> bool
	local function drive(det, rig, x0, x1, speed, o)
		o = o or {}
		local fps = o.fps or 60
		local dt = 1 / fps
		local dir = if x1 > x0 then 1 else -1
		local x = x0
		while (x1 - x) * dir > 0 do
			x += dir * speed * dt
			rig.splineAlong = x
			local z = if o.zAt then o.zAt(x) else 0
			det:Update(dt, state(x, z, speed, dir, o.wallAt and o.wallAt(x), o.fellAt and o.fellAt(x)))
		end
	end
	local function idle(det, rig, x, seconds)
		for _ = 1, math.ceil(seconds * 60) do
			rig.splineAlong = x
			det:Update(1 / 60, state(x, -200, 0, 1))
		end
	end
	local function one(trees, x0, x1, speed, o)
		local rec = recorder()
		local rig = rigFor(trees)
		local det = NearMiss.new(rec.sink, rig)
		drive(det, rig, x0, x1, speed, o)
		return rec.calls, det, rig
	end

	-- 1. A close pass fires once, sized by the gap
	do
		local calls = one({ trunk(0, 0.8) }, -80, 80, 80)
		local c = calls[1]
		local want = (T.Threshold - 0.8) / (T.Threshold - T.FullGap)
		check(
			"a close pass fires one near miss",
			#calls == 1 and c.kind == "nearMiss" and math.abs(c.size - want) < 0.01 and math.abs(c.info.gap - 0.8) < 0.01,
			if c then `{#calls} call(s): kind {c.kind}, size {fmt(c.size, 3)} (want {fmt(want, 3)}), gap {fmt(c.info.gap, 3)}, speed {fmt(c.info.speed, 0)}` else "no call"
		)
	end

	-- 2. Closer is bigger; at FullGap and under it is 1
	do
		local sizes = {}
		for _, g in { 2.5, 2.0, 1.5, 1.0, 0.5, 0.2 } do
			local calls = one({ trunk(0, g) }, -80, 80, 80)
			table.insert(sizes, if calls[1] then calls[1].size else -1)
		end
		local rising = true
		for i = 2, #sizes do
			if sizes[i] < sizes[i - 1] then
				rising = false
			end
		end
		local text = {}
		for i, s in sizes do
			text[i] = fmt(s, 2)
		end
		check("closer passes are bigger, 1 at the full gap and under", rising and sizes[1] > 0 and sizes[5] == 1 and sizes[6] == 1, `sizes at gaps 2.5, 2, 1.5, 1, 0.5, 0.2: {table.concat(text, ", ")}`)
	end

	-- 3. A far pass fires nothing, but is measured
	do
		local calls, det = one({ trunk(0, 5) }, -80, 80, 80)
		local ds = det:DebugState()
		check("a far pass (5 studs) fires nothing", #calls == 0 and ds.passes == 1, `{#calls} calls; {ds.passes} pass measured`)
		local edge = one({ trunk(0, T.Threshold + 0.05) }, -80, 80, 80)
		local inside = one({ trunk(0, T.Threshold - 0.05) }, -80, 80, 80)
		check("the threshold is the line", #edge == 0 and #inside == 1, `just outside: {#edge}; just inside: {#inside}`)
	end

	-- 4. A hit fires nothing: through the trunk, a graze, or a wall touched just after
	do
		local through = one({ trunk(0, -0.5) }, -80, 80, 80)
		local graze = one({ trunk(0, 0.05) }, -80, 80, 80)
		local wallAfter = one({ trunk(0, 0.8) }, -80, 80, 80, { wallAt = function(x)
			return x > 15 and x < 17
		end })
		local wallLater = one({ trunk(0, 0.8) }, -80, 140, 80, { wallAt = function(x)
			return x > 120 and x < 122
		end })
		local _, det = one({ trunk(0, -0.5) }, -80, 80, 80)
		check(
			"a hit fires nothing",
			#through == 0 and #graze == 0 and #wallAfter == 0 and #wallLater == 1 and det:DebugState().hit == 1,
			`through it: {#through}; grazing it (0.05): {#graze}; a wall just after: {#wallAfter}; a wall 1.5 s after: {#wallLater} (fires); counted as hits: {det:DebugState().hit}`
		)
	end

	-- 5. A slow pass fires nothing, nor a backward one
	do
		local slow = one({ trunk(0, 0.8) }, -80, 80, T.MinSpeed - 10)
		local quick = one({ trunk(0, 0.8) }, -80, 80, T.MinSpeed + 2)
		local rec = recorder()
		local rig = rigFor({ trunk(0, 0.8) })
		local det = NearMiss.new(rec.sink, rig)
		-- rolling backward: moving +x, nose the other way
		local x = -80
		while x < 80 do
			x += 80 / 60
			rig.splineAlong = x
			local s = state(x, 0, 80, 1)
			s.u = -80
			det:Update(1 / 60, s)
		end
		check("a slow or backward pass fires nothing", #slow == 0 and #quick == 1 and #rec.calls == 0, `at {T.MinSpeed - 10}: {#slow}; at {T.MinSpeed + 2}: {#quick}; backward at 80: {#rec.calls}`)
	end

	-- 6. The same tree: once a pass, however the gap wobbles; again only after Rearm
	do
		local rec = recorder()
		local trees = { trunk(0, 0.8) }
		local rig = rigFor(trees)
		local det = NearMiss.new(rec.sink, rig)
		-- weaving: the gap swings 0.8 .. 2.8 as the car passes
		drive(det, rig, -80, 80, 80, { zAt = function(x)
			return -1 + math.cos(x / 2)
		end })
		local weave = #rec.calls
		drive(det, rig, 80, -80, 80) -- straight back at once
		local back = #rec.calls - weave
		idle(det, rig, -80, T.Rearm)
		drive(det, rig, -80, 80, 80)
		local later = #rec.calls - weave - back
		check("the same tree fires once a pass, again only after Rearm", weave == 1 and back == 0 and later == 1, `weaving past it: {weave}; straight back at once: {back}; again {T.Rearm} s later: {later}`)
	end

	-- 7. A row of trees: one each; a fall voids what's open; a put-back forgets
	do
		local row = {}
		for i = 0, 4 do
			table.insert(row, trunk(i * 20, 1.0 + i * 0.3))
		end
		local calls = one(row, -80, 200, 80)
		local fellCalls = one({ trunk(0, 0.8) }, -80, 80, 80, { fellAt = function(x)
			return x > 10 and x < 12
		end })
		-- a put-back: by the tree, then 500 studs away in a frame
		local rec = recorder()
		local rig = rigFor({ trunk(0, 0.8) })
		local det = NearMiss.new(rec.sink, rig)
		drive(det, rig, -80, 2, 80)
		rig.splineAlong = 500
		for _ = 1, 60 do
			det:Update(1 / 60, state(500, 0, 80, 1))
		end
		check("a row fires one each; a fall or a put-back fires nothing", #calls == 5 and #fellCalls == 0 and #rec.calls == 0, `5 trunks in a row: {#calls}; a fall just after: {#fellCalls}; a put-back mid-pass: {#rec.calls}`)
	end

	-- 8. Bushes (no trunk) never count; nor a tree the car is above or below
	do
		local bush = trunk(0, 0.5)
		bush.trunk = 0
		bush.z = hw + 0.5
		local high = trunk(0, 0.8)
		high.y = 40
		local calls = one({ bush, high }, -80, 80, 80)
		check("bushes and trees at another height do not count", #calls == 0, `{#calls} calls`)
	end

	-- 9. The same at any frame rate
	do
		local got = {}
		for _, fps in { 30, 60, 120, 240 } do
			local calls = one({ trunk(0, 1.2), trunk(40, 2.2) }, -80, 160, 80, { fps = fps })
			table.insert(got, { n = #calls, a = calls[1] and calls[1].size or -1, b = calls[2] and calls[2].size or -1 })
		end
		local same = true
		for _, g in got do
			if g.n ~= got[1].n or math.abs(g.a - got[1].a) > 0.01 or math.abs(g.b - got[1].b) > 0.01 then
				same = false
			end
		end
		check("the same at 30, 60, 120 and 240 FPS", same and got[1].n == 2, `{got[1].n} calls, sizes {fmt(got[1].a, 3)} and {fmt(got[1].b, 3)} at 30; {got[4].n}, {fmt(got[4].a, 3)}, {fmt(got[4].b, 3)} at 240`)
	end

	-- 11. The engine's rig (functions), stepped at 120 Hz as the drift controller steps it
	do
		local trees = { trunk(0, 0.8) }
		local plain = rigFor(trees)
		local along = 0
		local rig = { lookup = plain.lookup, spline = function()
			return plain.spline
		end, along = function()
			return along
		end }
		local rec = recorder()
		local det = NearMiss.new(rec.sink, rig)
		local x = -80
		while x < 80 do
			x += 80 / 120
			along = x
			det:Update(1 / 120, state(x, 0, 80, 1))
		end
		local c = rec.calls[1]
		check("the engine's rig, stepped at 120 Hz", #rec.calls == 1 and math.abs(c.size - 0.88) < 0.01, `{#rec.calls} call(s), size {if c then fmt(c.size, 3) else "-"}`)
	end

	-- 10. The lookup runs when the car has moved along, not every frame
	do
		local trees = {}
		for i = 1, 400 do
			table.insert(trees, trunk(i * 5, 8 + (i % 7)))
		end
		local _, det, rig = one(trees, 0, 2000, 80)
		local ds = det:DebugState()
		local frames = ds.frames
		check(
			"trees are fetched every few studs along, and few are looked at",
			rig.lookups <= 2000 / T.Refetch + 2 and ds.looked / frames < 12,
			`{rig.lookups} fetches over 2 000 studs ({frames} frames); {fmt(ds.looked / frames, 1)} trunks looked at a frame of {fmt(ds.near, 0)} fetched; {fmt(ds.microsPerFrame, 1)} microseconds a frame`
		)
	end
end

--------------------------------------------------------------------------------
-- Drive: the real model on a real road's maths, the real trunks
--------------------------------------------------------------------------------

local SEED = 101
local LENGTH = 40000
local FPS = 60
local LOOK_SECONDS, LOOK_MIN, LOOK_MAX = 0.9, 30, 120 -- RunTests' autopilot, copied
local BRAKE_LOOK, BRAKE_LIMIT = 1.6, 65
local GROVE_RUNS = 10 -- grove stretches driven at each distance out
local OUT = { 0, 4, 8, 10, 12, 14 } -- studs out past the tarmac's edge, the car's centre
local PLAIN_SECONDS = 180

local function signedAngle(ax, az, bx, bz)
	return math.atan2(bx * az - bz * ax, bx * ax + bz * az)
end

local function newTotals()
	return { seconds = 0, groveSeconds = 0, passes = 0, fired = 0, hit = 0, wall = 0, slow = 0, recent = {}, fell = 0, sizes = 0, treeStops = 0, falls = 0, hist = nil, micros = 0, frames = 0, fetches = 0, studs = 0 }
end

local function addDet(tot, det)
	local ds = det:DebugState()
	tot.passes += ds.passes
	tot.fired += ds.fired
	tot.hit += ds.hit
	tot.wall += ds.wall
	for _, r in ds.recent do
		table.insert(tot.recent, r)
	end
	tot.slow += ds.slow
	tot.fell += ds.fell
	tot.micros += ds.microsPerFrame * ds.frames
	tot.frames += ds.frames
	tot.fetches += ds.fetches
	if not tot.hist then
		tot.hist = {}
		for i, h in ds.hist do
			tot.hist[i] = { from = h.from, to = h.to, n = 0 }
		end
	end
	for i, h in ds.hist do
		tot.hist[i].n += h.n
	end
end

local function histText(hist)
	local parts = {}
	for _, h in hist or {} do
		if h.n > 0 then
			table.insert(parts, `{h.from}-{if h.to == math.huge then "+" else tostring(h.to)}: {h.n}`)
		end
	end
	return table.concat(parts, ", ")
end

-- One autopilot drive from `s0` to `s1` (or `seconds`), aiming `outAt(s)` studs across
-- (signed, + to the road's right). Returns the detector's numbers into `tot`.
local function drive(Sim, NearMiss, spline, world, s0, s1, seconds, outAt, tot, log)
	local D = Config.Drift
	local cf0 = spline:frame(s0, D.RideHeight)
	local runner = Sim.newRunner(CFrame.lookAt(cf0.Position, cf0.Position + cf0.LookVector * Vector3.new(1, 0, 1)))
	runner.state.velocity = Vector3.new(cf0.LookVector.X, 0, cf0.LookVector.Z).Unit * 70
	runner.state.time = 10
	local rec = recorder()
	local rig = { spline = spline, splineAlong = s0 }
	local det = NearMiss.new(rec.sink, rig)
	local input = { steer = 0, handbrake = false }
	local lastS = s0
	local elapsed = 0
	local stuck = 0
	local stops0 = world.stats.treeStops
	while elapsed < seconds and lastS < s1 do
		local st = runner.state
		local speed = math.sqrt(st.velocity.X ^ 2 + st.velocity.Z ^ 2)
		local heading = if speed > 1 then Vector3.new(st.velocity.X / speed, 0, st.velocity.Z / speed) else Vector3.new(-math.sin(st.yaw), 0, -math.cos(st.yaw))
		local look = math.clamp(speed * LOOK_SECONDS, LOOK_MIN, LOOK_MAX)
		local sl = math.min(lastS + look, spline.length)
		local tx, tz = spline:planAt(sl)
		local yaw = spline:yawAt(sl)
		local d = outAt(sl)
		tx, tz = tx + d * math.cos(yaw), tz - d * math.sin(yaw)
		local dx, dz = tx - st.position.X, tz - st.position.Z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 1e-3 then
			local alpha = signedAngle(heading.X, heading.Z, dx / len, dz / len)
			input.steer = math.clamp(speed * (2 * math.sin(alpha) / look) / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
		end
		local kMax = 0
		for u = 0, math.max(speed * BRAKE_LOOK, LOOK_MIN), 8 do
			kMax = math.max(kMax, math.abs(spline:curvatureAt(math.min(lastS + u, spline.length))))
		end
		input.handbrake = speed * speed * kMax > BRAKE_LIMIT
		Sim.advance(runner, 1 / FPS, input, world)
		elapsed += 1 / FPS
		local s = world.locate(runner.state.position)
		if s then
			tot.studs += math.max(0, s - lastS)
			lastS = s
		end
		rig.splineAlong = lastS
		det:Update(1 / FPS, runner.state)
		if outAt(lastS) ~= 0 then
			tot.groveSeconds += 1 / FPS
		end
		-- a fall, or stuck on a trunk: put back on the road a little further on
		stuck = if speed < 8 then stuck + 1 / FPS else 0
		if runner.state.fell or stuck > 2 then
			tot.falls += 1
			local cf = spline:frame(math.min(lastS + 30, spline.length), D.RideHeight)
			runner = Sim.newRunner(CFrame.lookAt(cf.Position, cf.Position + cf.LookVector * Vector3.new(1, 0, 1)))
			runner.state.velocity = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit * 70
			runner.state.time = 10
			stuck = 0
		end
		if math.floor(elapsed * FPS) % 240 == 0 then
			task.wait()
		end
	end
	tot.seconds += elapsed
	tot.treeStops += world.stats.treeStops - stops0
	for _, c in rec.calls do
		tot.sizes += c.size
		if log and #log < 400 then
			table.insert(log, string.format("%.0f,%d,%.2f,%.3f,%.0f", c.info.s, c.info.side, c.info.gap, c.size, c.info.speed))
		end
	end
	addDet(tot, det)
end

local function driveTests(check, results)
	local Sim = require(DriftFolder.Sim)
	local SplineWorld = require(DriftFolder.SplineWorld)
	local NearMiss = require(DriftFolder.Events.NearMiss)
	local half = Config.Road.Width * 0.5

	local gen = SplineGen.new(SEED)
	gen:extendTo(LENGTH)
	local spline = gen.spline
	local world = SplineWorld.new(spline, nil)

	-- the grove runs, both sides, in order along the road
	local runs = {}
	for _, side in { -1, 1 } do
		local g = spline:groves(side)
		for i = 1, #g.a do
			if g.b[i] - g.a[i] >= 150 and g.a[i] > 300 then
				table.insert(runs, { a = g.a[i], b = g.b[i], side = side })
			end
		end
	end
	table.sort(runs, function(p, q)
		return p.a < q.a
	end)
	local groveStuds = 0
	for _, r in runs do
		groveStuds += r.b - r.a
	end

	-- 1. Plain driving: the road's own line, three minutes
	local plain = newTotals()
	drive(Sim, NearMiss, spline, world, 200, spline.length - 200, PLAIN_SECONDS, function()
		return 0
	end, plain)
	results.plain = plain
	check(
		"plain driving on the tarmac: no near misses",
		plain.fired == 0,
		`{fmt(plain.seconds, 0)} s, {fmt(plain.studs, 0)} studs; {plain.passes} passes within {NearMiss.Defaults.Watch} studs, {plain.fired} fired, {plain.hit} hit the trunk, {plain.wall} voided by another wall; closest passes {histText(plain.hist)}; {plain.falls} put-backs. {#runs} grove stretches on the road's {LENGTH} studs ({fmt(groveStuds / LENGTH * 100, 1)}% of it)`
	)

	-- 2. Along the groves at set distances out on the grass
	local byOut = {}
	results.log = {}
	for _, out in OUT do
		local tot = newTotals()
		for i = 1, math.min(GROVE_RUNS, #runs) do
			local r = runs[i]
			local function outAt(s)
				if s < r.a + 40 or s > r.b - 40 then
					return 0
				end
				local ramp = math.min(1, (s - r.a - 40) / 50, (r.b - 40 - s) / 50)
				return r.side * (half + out) * math.max(0, ramp)
			end
			drive(Sim, NearMiss, spline, world, r.a - 150, r.b + 30, 60, outAt, tot, if out == 10 then results.log else nil)
		end
		byOut[out] = tot
		local perMin = tot.fired / math.max(tot.groveSeconds, 1e-6) * 60
		check(
			`along the groves, {out} studs out`,
			true,
			`{fmt(tot.groveSeconds, 0)} s out there: {tot.fired} fired ({fmt(perMin, 1)} a minute, mean size {fmt(tot.sizes / math.max(1, tot.fired), 2)}), {tot.hit} hit the trunk, {tot.wall} voided by another wall, {tot.slow} too slow, {tot.treeStops} steps stopped by a trunk, {tot.falls} put-backs; closest passes {histText(tot.hist)}`
		)
	end
	results.byOut = byOut

	-- 3. The groves' own layout: a car holding a straight line `out` studs past the tarmac's
	-- edge, beside the road, the length of every grove: per 100 studs, how many trunks it
	-- would pass within the threshold, and how many stand in its way.
	local hw = Config.Drift.BodyWidth * 0.5
	local SplineGrove = require(ReplicatedStorage.Shared.Road.SplineGrove)
	local thr = NearMiss.Defaults.Threshold
	local lines = {}
	for out = 0, 20, 2 do
		local near, blocked, studs, sizes = 0, 0, 0, 0
		for _, r in runs do
			local items = SplineGrove.items(spline, r.a + 40, r.b - 40, r.side)
			studs += math.max(0, r.b - r.a - 80)
			for _, it in items do
				if it.trunk > 0 then
					local g = math.abs(it.e - out) - hw - it.trunk
					if g < 0 then
						blocked += 1
					elseif g < thr then
						near += 1
						sizes += math.clamp((thr - g) / (thr - NearMiss.Defaults.FullGap), 0, 1)
					end
				end
			end
		end
		table.insert(lines, `{out}: {fmt(near / studs * 100, 2)} near, {fmt(blocked / studs * 100, 2)} in the way`)
		results.layout = results.layout or {}
		results.layout[out] = { near = near, blocked = blocked, studs = studs }
	end
	check("the groves' layout, a straight line N studs past the edge, per 100 studs", true, table.concat(lines, "; "))

	-- 4. The cost
	local frames, micros, fetches = plain.frames, plain.micros, plain.fetches
	for _, tot in byOut do
		frames += tot.frames
		micros += tot.micros
		fetches += tot.fetches
	end
	check("it costs little a frame", micros / frames < 25, `{fmt(micros / frames, 1)} microseconds a frame over {frames} frames, a fetch every {fmt(frames / math.max(1, fetches), 1)} frames`)
end

function Tests.run(which, ...)
	-- The DebugBridge calls a member as a method, so the module itself comes first.
	if which == Tests then
		which = ...
	end
	local function want(name)
		return which == nil or table.find(which, name) ~= nil
	end
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local results = {}
	if want("unit") then
		local ok, err = pcall(unit, check)
		if not ok then
			check("unit tests ran", false, tostring(err))
		end
	end
	if want("drive") then
		local ok, err = pcall(driveTests, check, results)
		if not ok then
			check("the drive ran", false, tostring(err))
		end
	end
	local passed = 0
	for _, c in checks do
		if c.ok then
			passed += 1
		end
	end
	Tests.last = results
	return { passed = passed, total = #checks, checks = checks }
end

return Tests
