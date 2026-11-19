--!strict
-- OffRoadTests: the car past the runoff, on the drawn ground (T-258, features/car-edges.md).
-- Pure maths, so it runs in Edit: `require(game.ServerScriptService.Tests.OffRoadTests).run()`.
--
-- On a mountain road (seed `SEED`), it finds, beside straight stretches with no K-rail and
-- no grove:
--   a CUT    the ground past the grass rising steeper than `WallAngle` (a wall)
--   a FILL   the ground falling away steeper than it (a drop)
--   GENTLE   ground that stays under 25 degrees for 40 studs out
-- and drives a car straight out of the side at each, at 40 studs/s for 3 s. It also checks
-- the car's ground against the drawn ground's own maths (`Road/Ground.at`) beside the road,
-- and what a step costs on the grass and off it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "OffRoadTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Ground = require(ReplicatedStorage.Shared.Road.Ground)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local RoadDressing = require(ReplicatedStorage.Shared.Road.RoadDressing) -- the barriers, as the game's road has them (T-327)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")

local Tests = {}

local SEED = 2024
local LENGTH = 6000 -- studs of road
local FPS = 60
local SPEED = 40 -- studs/s
local OUT = 40 -- studs past the runoff's edge each side is surveyed

local function fmt(x: number, p: number?): string
	return string.format(`%.{p or 2}f`, x)
end

function Tests.run(...)
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local Sim = require(DriftFolder.Sim) :: any
	local SplineWorld = require(DriftFolder.SplineWorld) :: any
	local D = Config.Drift
	local O = D.OffRoad
	local half = Config.Road.Width * 0.5
	local tanWall = math.tan(math.rad(O.WallAngle))

	local gen = SplineGen.new(SEED)
	RoadDressing.attach(gen)
	gen:extendTo(LENGTH)
	local spline = gen.spline
	local field = spline.mountain
	check("the road has a mountain", field ~= nil)
	if not field then
		return { passed = false, checks = checks }
	end

	------------------------------------------------------------------ the spots
	-- Every 24 studs, each side: the ground square out from the runoff's edge, every stud.
	local survey = {}
	local first = spline.firstSample * spline.step
	local s = first + 100
	while s < spline.length - 400 do
		local straight = math.abs(spline:curvatureAt(s)) < 1 / 400 and math.abs(spline:curvatureAt(s - 30)) < 1 / 400 and math.abs(spline:curvatureAt(s + 30)) < 1 / 400
		if straight then
			for _, side in { -1, 1 } do
				local clear = true
				for u = s - 30, s + 30, 10 do
					if spline:kRailAt(u, side) then
						clear = false
					end
				end
				local g = spline:groves(side)
				for i = 1, #g.a do
					if g.a[i] <= s + 40 and g.b[i] >= s - 40 then
						clear = false
					end
				end
				if clear then
					local edge = half + spline:runoffAt(s, side)
					local ctx: Ground.Context? = nil
					local ys = {}
					local yaw = spline:yawAt(s)
					local cx, cz = spline:planAt(s)
					local rx, rz = math.cos(yaw) * side, -math.sin(yaw) * side
					for e = 0, OUT do
						local x, z = cx + rx * (edge + e), cz + rz * (edge + e)
						if not ctx then
							ctx = Ground.context(field, spline, x - 60, z - 60, x + 60, z + 60)
						end
						ys[e] = (Ground.at(ctx :: Ground.Context, x, z))
					end
					local steepest, steepAt = 0, 0
					for e = 1, OUT do
						local g1 = math.abs(ys[e] - ys[e - 1])
						if g1 > steepest then
							steepest, steepAt = g1, e
						end
					end
					table.insert(survey, { s = s, side = side, edge = edge, ys = ys, steepest = steepest, steepAt = steepAt, rise = ys[math.min(steepAt + 6, OUT)] - ys[0] })
				end
			end
		end
		s += 24
	end
	-- A cut with a FOOT: the ground is still within `WallStep` of the edge where it first gets
	-- steeper than the wall. A rounded toe the car can climb partway (T-326's cuts have them)
	-- leaves it standing on the toe, which is right, but is not the stop this asks about.
	local function hasFoot(p): boolean
		for e = 1, OUT do
			if p.ys[e] - p.ys[e - 1] > tanWall then
				return p.ys[e - 1] - p.ys[0] < O.WallStep
			end
		end
		return false
	end
	local cut, fill, gentle
	for _, p in survey do
		if not cut and p.steepest > tanWall * 1.3 and p.rise > 6 and p.steepAt < 20 and hasFoot(p) then
			cut = p
		elseif not fill and p.steepest > tanWall * 1.3 and p.rise < -6 and p.steepAt < 20 then
			fill = p
		elseif not gentle and p.steepest < math.tan(math.rad(25)) and math.abs(p.ys[OUT] - p.ys[0]) > 4 then
			gentle = p
		end
	end
	check("spots found", cut ~= nil and fill ~= nil and gentle ~= nil, `{#survey} profiles: cut {cut and fmt(cut.s, 0) or "none"}, fill {fill and fmt(fill.s, 0) or "none"}, gentle {gentle and fmt(gentle.s, 0) or "none"}`)

	------------------------------------------------------------------ the car's ground
	do
		local w = SplineWorld.new(spline, nil)
		local n, worst, sum, missed = 0, 0, 0, 0
		local rng = Random.new(7)
		local ctx: Ground.Context? = nil
		for _ = 1, 400 do
			local p = survey[rng:NextInteger(1, #survey)]
			local e = rng:NextNumber(0.5, OUT)
			local yaw = spline:yawAt(p.s)
			local cx, cz = spline:planAt(p.s)
			local along = rng:NextNumber(-10, 10)
			local x = cx + math.cos(yaw) * p.side * (p.edge + e) - math.sin(yaw) * along
			local z = cz - math.sin(yaw) * p.side * (p.edge + e) - math.cos(yaw) * along
			ctx = Ground.context(field, spline, x - 2, z - 2, x + 2, z + 2)
			local want = Ground.at(ctx :: Ground.Context, x, z)
			local hit = w.probe(Vector3.new(x, want + 1, z))
			if hit then
				n += 1
				local dy = math.abs(hit.y - want)
				worst = math.max(worst, dy)
				sum += dy
			else
				missed += 1
			end
		end
		check("past the grass the car stands on the drawn ground", missed == 0 and worst < 0.5, `{n} points out to {OUT} studs past the edge: worst {fmt(worst, 3)} studs off the drawn ground's maths, mean {fmt(sum / math.max(n, 1), 3)}; {missed} found nothing`)
	end

	------------------------------------------------------------------ driving off the side
	local function offTheSide(p, seconds: number?)
		local w = SplineWorld.new(spline, nil)
		local yaw = spline:yawAt(p.s)
		local outYaw = yaw - p.side * math.pi / 2
		local x, y, z = spline:surfaceXYZ(p.s, p.side * (half - 3))
		local runner = Sim.newRunner(CFrame.new(x, y + D.RideHeight, z) * CFrame.Angles(0, outYaw, 0))
		runner.state.velocity = Vector3.new(-math.sin(outYaw), 0, -math.cos(outYaw)) * SPEED
		runner.state.time = 10
		local airborne, steps = 0, 0
		local lowest = math.huge
		for _ = 1, (seconds or 3) * FPS do
			Sim.advance(runner, 1 / FPS, { steer = 0, handbrake = false }, w, function(st)
				steps += 1
				if st.airborne then
					airborne += 1
				end
			end)
			lowest = math.min(lowest, runner.state.position.Y)
		end
		local pos = runner.state.position
		local _, d = spline:projectFrom(pos.X, pos.Z, p.s)
		local ctx = Ground.context(field, spline, pos.X - 2, pos.Z - 2, pos.X + 2, pos.Z + 2)
		local under = Ground.at(ctx, pos.X, pos.Z)
		return {
			out = (d or math.huge) * p.side - p.edge, -- studs past the runoff's edge
			y = pos.Y,
			startY = y,
			above = pos.Y - D.RideHeight - under, -- over the drawn ground under it
			airborne = airborne,
			steps = steps,
			grounded = not runner.state.airborne,
			stats = w.stats,
			speed = Vector3.new(runner.state.velocity.X, 0, runner.state.velocity.Z).Magnitude,
		}
	end

	if cut then
		local r = offTheSide(cut)
		-- where the face first gets steeper than the wall angle and higher than the step
		local wallAt = OUT
		for e = 1, OUT do
			if (cut.ys[e] - cut.ys[e - 1]) > tanWall and cut.ys[e] - cut.ys[0] > O.WallStep then
				wallAt = e
				break
			end
		end
		local nose = r.out + D.BodyLength * 0.5
		check(
			"a steep cut stops the car at its foot",
			r.stats.groundStops > 0 and r.grounded and nose < wallAt + 1.5 and nose > wallAt - 4 and r.above < 1.5,
			`at s {fmt(cut.s, 0)}: the face is steeper than {O.WallAngle} degrees from {wallAt} studs past the edge (slope up to {fmt(math.deg(math.atan(cut.steepest)), 0)} degrees); after 3 s the car's nose is {fmt(nose, 2)} studs past the edge, {fmt(r.above, 2)} over the ground, on the ground {tostring(r.grounded)}, {r.stats.groundStops} steep-ground stops, {r.stats.wallStops} rock-face stops`
		)
	end
	if fill then
		local r = offTheSide(fill)
		check(
			"a steep drop is gone over, and the car lands below",
			r.stats.groundStops == 0 and r.airborne > 0 and r.startY - r.y > 6 and r.grounded and math.abs(r.above) < 1.5 and r.out > 8,
			`at s {fmt(fill.s, 0)} (drop up to {fmt(math.deg(math.atan(fill.steepest)), 0)} degrees): after 3 s the car is {fmt(r.out, 1)} studs past the edge and {fmt(r.startY - r.y, 1)} below the road, {fmt(r.above, 2)} over the ground, airborne for {r.airborne} of {r.steps} steps, on the ground at the end {tostring(r.grounded)}, {r.stats.groundStops} steep-ground stops`
		)
	end
	if gentle then
		local r = offTheSide(gentle, 2)
		check(
			"gentle ground beside the road is driven on",
			r.stats.groundStops == 0 and r.stats.wallStops == 0 and r.out > 25 and r.grounded and math.abs(r.above) < 1 and r.stats.offRoad > 0,
			`at s {fmt(gentle.s, 0)} (ground {fmt(gentle.ys[OUT] - gentle.ys[0], 1)} studs up over {OUT} out): after 2 s the car is {fmt(r.out, 1)} studs past the edge, {fmt(r.above, 2)} over the ground, on the ground {tostring(r.grounded)}, {fmt(r.speed, 1)} studs/s, {r.stats.offRoad} probes on the drawn ground, {r.stats.groundStops + r.stats.wallStops} wall stops`
		)
	end

	------------------------------------------------------------------ too far off: put back
	-- (T-260) how far the road is, measured from where the car is, against the put-back line
	do
		local w = SplineWorld.new(spline, nil)
		local limit = O.PutBack
		local worst, nearMiss, farFound, n = 0, 0, 0, 0
		local t0 = os.clock()
		for _, p in survey do
			local yaw = spline:yawAt(p.s)
			local cx, cz = spline:planAt(p.s)
			for _, out in { 20, limit - 20, limit + 20 } do
				local x = cx + math.cos(yaw) * p.side * (half + out)
				local z = cz - math.sin(yaw) * p.side * (half + out)
				-- the truth: the nearest centre-line point of any leg, every 2 studs
				local best = math.huge
				for u = first, spline.length, 2 do
					local ux, uz = spline:planAt(u)
					best = math.min(best, math.sqrt((ux - x) ^ 2 + (uz - z) ^ 2))
				end
				local truth = math.max(best - half, 0)
				local got = w.offBy(Vector3.new(x, 0, z), limit)
				n += 1
				if truth < limit - 2 and not got then
					nearMiss += 1
				elseif truth > limit + 2 and got then
					farFound += 1
				elseif got and truth < limit - 2 then
					worst = math.max(worst, math.abs(got - truth))
				end
			end
			if n >= 60 then
				break
			end
		end
		local us = (os.clock() - t0) -- (the truth's brute force dominates; timed apart below)
		local t1 = os.clock()
		for _ = 1, 200 do
			local p = survey[1]
			local cx, cz = spline:planAt(p.s)
			w.offBy(Vector3.new(cx + 250, 0, cz + 250), limit)
		end
		local each = (os.clock() - t1) / 200 * 1e6
		check(
			`over {limit} studs from the road is told apart`,
			nearMiss == 0 and farFound == 0 and worst < 2,
			`{n} points 20, {limit - 20} and {limit + 20} studs out: {nearMiss} within reach missed, {farFound} beyond it found; worst {fmt(worst, 2)} studs off the true distance; a far check costs {fmt(each, 0)} microseconds ({fmt(us, 1)} s with the brute-force truth)`
		)
	end

	------------------------------------------------------------------ what it costs
	if gentle then
		local function cost(onRoad: boolean): (number, number)
			local w = SplineWorld.new(spline, nil)
			local yaw = spline:yawAt(gentle.s)
			local outYaw = if onRoad then yaw else yaw - gentle.side * math.pi / 2
			local x, y, z = spline:surfaceXYZ(gentle.s - (if onRoad then 60 else 0), if onRoad then 0 else gentle.side * (half + 2))
			local runner = Sim.newRunner(CFrame.new(x, y + D.RideHeight, z) * CFrame.Angles(0, outYaw, 0))
			runner.state.velocity = Vector3.new(-math.sin(outYaw), 0, -math.cos(outYaw)) * SPEED
			runner.state.time = 10
			local t0 = os.clock()
			local steps = 0
			for _ = 1, FPS do
				Sim.advance(runner, 1 / FPS, { steer = 0.3, handbrake = false }, w, function()
					steps += 1
				end)
			end
			local off = (w :: any).offRoad
			return (os.clock() - t0) / math.max(steps, 1) * 1e6, if off then off.stats.points else 0
		end
		local onUs = cost(true)
		local offUs, points = cost(false)
		check("a step off the road costs little more than one on it", offUs < onUs * 2 + 60, `a model step on the road {fmt(onUs, 0)} microseconds, on the drawn ground {fmt(offUs, 0)} (its first second, {points} points of ground worked out)`)
	end

	local passed = true
	for _, c in checks do
		if not c.ok then
			passed = false
		end
	end
	return { passed = passed, checks = checks }
end

return Tests
