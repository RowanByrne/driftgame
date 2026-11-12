--!nonstrict
-- SplineWorldTests: the car on the spline road's maths, against the same road built as parts
-- (features/spline-road.md "Testing", T-134).
--
-- THE YARDSTICK IS THE GAME'S OWN COLLISION. The piece road is ground rays and Blockcasts
-- against tagged parts (`Drift/World.live`), and that is what the car the user approved
-- drives on. So the same stretch of spline road is laid as parts the way the piece road
-- lays its own (`Road/SplineParts`, `Road/Builder.triangleSlab`), and every question the
-- model asks is put to both worlds: the spline's maths, and the live world on those parts.
--
-- It builds a few thousand parts in the place, so it runs in Studio only, yields while it
-- builds, and takes them all away again. Run it in a task, not a blocking call:
--   game.ServerStorage.DebugBridge:Invoke("DebugSplineWorldTests", "run")
--
-- What it cannot check: how the spline road FEELS. That is the user's, by driving it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "SplineWorldTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local SplineParts = require(ReplicatedStorage.Shared.Road.SplineParts)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")

local Tests = {}

local SEED = 31337
local LENGTH = 2600 -- studs of road laid as parts: past 1 500, so it holds hairpins
-- How finely the yardstick is cut, and how far its triangles may stand off the true surface.
-- A twisting, curving surface is not flat between two cross-sections, so a triangle is off
-- it by up to about this much; the piece road's own ray check allows 0.3 (RoadTests).
local YARD_STEP = 2
local YARD_TOLERANCE = 0.1
local DRIVE_SECONDS = 60
local DRIVE_FPS = 60
local LOOK_SECONDS, LOOK_MIN, LOOK_MAX = 0.9, 30, 120 -- RunTests' autopilot, copied
local BRAKE_LOOK, BRAKE_LIMIT = 1.6, 65

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 3) .. "f", x)
end

local function signedAngle(ax: number, az: number, bx: number, bz: number): number
	return math.atan2(bx * az - bz * ax, bx * ax + bz * az)
end

-- The autopilot RunTests drives with, aimed down the spline instead of the pieces.
local function drive(Sim, spline, world, locate, seconds: number, startS: number, stopS: number)
	local D = Config.Drift
	local R = Config.Road
	local cf = spline:frame(startS, D.RideHeight)
	local runner = Sim.newRunner(CFrame.lookAt(cf.Position, cf.Position + cf.LookVector * Vector3.new(1, 0, 1)))
	runner.state.velocity = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit * 40
	runner.state.time = 10
	local input = { steer = 0, handbrake = false }
	local r = { steps = 0, offRoad = 0, airborne = 0, wallSteps = 0, worstLateral = 0, s = startS, seconds = 0, path = {}, speedSum = 0 }
	local elapsed = 0
	local lastS = startS
	while elapsed < seconds do
		local st = runner.state
		local speed = math.sqrt(st.velocity.X ^ 2 + st.velocity.Z ^ 2)
		local heading = if speed > 1 then Vector3.new(st.velocity.X / speed, 0, st.velocity.Z / speed) else Vector3.new(-math.sin(st.yaw), 0, -math.cos(st.yaw))
		local look = math.clamp(speed * LOOK_SECONDS, LOOK_MIN, LOOK_MAX)
		local s = locate(st.position, lastS) or lastS
		lastS = s
		local tx, tz = spline:planAt(math.min(s + look, spline.length))
		local dx, dz = tx - st.position.X, tz - st.position.Z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 1e-3 then
			local alpha = signedAngle(heading.X, heading.Z, dx / len, dz / len)
			input.steer = math.clamp(speed * (2 * math.sin(alpha) / look) / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
		end
		-- the sharpest curvature within the braking look
		local kMax = 0
		local ahead = math.max(speed * BRAKE_LOOK, LOOK_MIN)
		for u = 0, ahead, 8 do
			kMax = math.max(kMax, math.abs(spline:curvatureAt(math.min(s + u, spline.length))))
		end
		input.handbrake = speed * speed * kMax > BRAKE_LIMIT
		Sim.advance(runner, 1 / DRIVE_FPS, input, world, function(state)
			r.steps += 1
			if state.airborne then
				r.airborne += 1
			end
			if state.wallHit then
				r.wallSteps += 1
			end
		end)
		elapsed += 1 / DRIVE_FPS
		local _, d = locate(runner.state.position, lastS)
		if d then
			r.worstLateral = math.max(r.worstLateral, math.abs(d))
			if math.abs(d) > R.Width * 0.5 then
				r.offRoad += 1
			end
		else
			r.offRoad += 1
		end
		r.speedSum += speed
		if (#r.path < 2000) and (r.steps % 6 == 0) then
			table.insert(r.path, runner.state.position)
		end
		if lastS >= stopS then
			break
		end
	end
	r.s = lastS
	r.seconds = elapsed
	r.meanSpeed = r.speedSum / math.max(1, elapsed * DRIVE_FPS)
	r.state = runner.state
	return r
end

function Tests.run(which: { string }?)
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local Sim = require(DriftFolder.Sim)
	local World = require(DriftFolder.World)
	local SplineWorld = require(DriftFolder.SplineWorld)
	local D = Config.Drift
	local R = Config.Road
	local half = R.Width * 0.5

	local gen = SplineGen.new(SEED)
	gen:extendTo(LENGTH + 200)
	local spline = gen.spline

	local old = workspace:FindFirstChild("__SplineYardstick")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "__SplineYardstick"
	folder.Parent = workspace
	local t0 = os.clock()
	local parts = SplineParts.build(spline, 0, LENGTH, folder, { step = YARD_STEP, queryable = true, yieldEvery = 40 })
	local buildSeconds = os.clock() - t0
	task.wait()

	local ok, err = pcall(function()
		local live = World.live({})
		-- THE WALLS ARE ASKED OF THE BARRIERS ALONE. The yardstick is cut every 2 studs, so a
		-- car stands on about thirty road slabs, and the overlap query stops at 16 parts
		-- (`Drift/World`): it can fill up with road before it reaches the barrier. The
		-- piece road's slabs are far bigger and never get there.
		local surface = {}
		for _, p in parts do
			if p:HasTag(D.SurfaceTag) then
				table.insert(surface, p)
			end
		end
		local liveWalls = World.live(surface)
		local sw = SplineWorld.new(spline, nil)
		local function want(name)
			return which == nil or table.find(which, name) ~= nil
		end

		-- 1. The ground: the same answer as rays on the parts.
		if want("ground") then
			local rng = Random.new(3)
			local worstY, worstDeg, misses, n, sumDeg = 0, 0, 0, 0, 0
			local worstAt = ""
			for _ = 1, 3000 do
				local s = 60 + rng:NextNumber() * (LENGTH - 120)
				local d = (rng:NextNumber() * 2 - 1) * (half - 0.3)
				local x, y, z = spline:surfaceXYZ(s, d)
				local pos = Vector3.new(x, y + D.RideHeight, z)
				local a = sw.probe(pos)
				local b = live.probe(pos)
				n += 1
				if not a or not b then
					misses += 1
				else
					local dy = math.abs(a.y - b.y)
					if dy > worstY then
						worstY = dy
						worstAt = `s {fmt(s, 1)}, d {fmt(d, 1)}, bank {fmt(math.deg(spline:bankAt(s)), 1)}, k {fmt(spline:curvatureAt(s) * 1000, 2)}e-3`
					end
					local deg = math.deg(math.acos(math.clamp(a.normal:Dot(b.normal), -1, 1)))
					worstDeg = math.max(worstDeg, deg)
					sumDeg += deg
				end
			end
			check("ground height matches the parts", misses == 0 and worstY < YARD_TOLERANCE, `{n} points across the road: {misses} missed by one or the other; worst {fmt(worstY, 4)} studs ({worstAt})`)
			-- A TRIANGLE IS FLAT AND THE ROAD IS NOT. Where the bank is rolling on a grade
			-- through a bend the surface twists, and its slope along the road differs from kerb
			-- to kerb (measured 0.10 against 0.16 across one slice): a triangle the whole width
			-- of the road takes one of them. So the worst is the yardstick's, and it is the mean
			-- that says the two surfaces agree. The maths' own normal is checked against its
			-- own surface in SplineTests, to 0.04 degrees.
			local mean = sumDeg / math.max(1, n - misses)
			check("ground normal matches the parts", mean < 1 and worstDeg < 8, `mean {fmt(mean, 2)} degrees, worst {fmt(worstDeg, 2)} (where the road twists and a full-width triangle cannot)`)
		end

		-- 2. The walls: a step into a barrier stops in the same place.
		if want("walls") then
			local rng = Random.new(4)
			local worstGap, worstDeg, disagree, trials, stops, late = 0, 0, 0, 0, 0, 0
			local worstAt = ""
			for _ = 1, 300 do
				local s = 80 + rng:NextNumber() * (LENGTH - 160)
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				local yawRoad = spline:yawAt(s)
				-- heading into the wall at 10..80 degrees, the body slipped up to 40 off it
				local into = math.rad(10 + rng:NextNumber() * 70)
				local travelYaw = yawRoad - side * into
				local yaw = travelYaw + math.rad((rng:NextNumber() * 2 - 1) * 40)
				-- START CLEAR OF THE WALL. A car that starts inside it is a question only the
				-- spline can answer: a Blockcast does not see a part it already overlaps.
				local rel = yaw - yawRoad
				local ext = D.BodyWidth * 0.5 * math.abs(math.cos(rel)) + D.BodyLength * 0.5 * math.abs(math.sin(rel))
				local d0 = side * (half - ext - 0.3 - rng:NextNumber() * 1.7)
				local x, y, z = spline:surfaceXYZ(s, d0)
				local from = Vector3.new(x, y + D.RideHeight, z)
				local dir = Vector3.new(-math.sin(travelYaw), 0, -math.cos(travelYaw))
				local to = from + dir * 4
				-- and clear by both worlds' reckoning: on the inside of a bend the road's
				-- edge curves in toward the car's nose, so a car whose middle is clear can
				-- still start with a corner over the line
				local _, startIn = sw.penetration(from, yaw)
				local _, startInParts = liveWalls.penetration(from, yaw)
				if startIn > 0 or startInParts > 0 then
					continue
				end
				trials += 1
				local a, an = sw.sweep(from, to, yaw)
				local b, bn = liveWalls.sweep(from, to, yaw)
				if (a == nil) ~= (b == nil) then
					-- one stops and the other does not: only fair if the stop was a whisker
					-- measured ACROSS the wall: at a shallow angle a hair of width is a long
					-- way along the travel, and the width is what the car meets
					local stopAt = a or b
					local n = an or bn
					local gap = math.abs((Vector3.new(stopAt.X, 0, stopAt.Z) - Vector3.new(to.X, 0, to.Z)):Dot(n))
					-- A GRAZE THE BLOCKCAST MISSES: the parts' sweep lets the car through and
					-- their own overlap check then finds it inside the barrier at the end of
					-- the step, as deep as the maths says. That is the parts agreeing, late.
					local _, depthMaths = sw.penetration(to, yaw)
					local _, depthParts = liveWalls.penetration(to, yaw)
					local caughtLate = a ~= nil and depthParts > 0 and math.abs(depthParts - depthMaths) < YARD_TOLERANCE
					if caughtLate then
						late += 1
					elseif gap > YARD_TOLERANCE then
						disagree += 1
						worstAt = `s {fmt(s, 1)} side {side}: spline {a and "stops" or "clear"}, parts {b and "stop" or "clear"}, {fmt(gap, 3)} from the end`
					end
				elseif a and b then
					stops += 1
					local gap = math.abs((Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)):Dot(an))
					if gap > worstGap then
						worstGap = gap
						worstAt = `s {fmt(s, 1)} side {side}, into {fmt(math.deg(into), 0)} deg`
					end
					worstDeg = math.max(worstDeg, math.deg(math.acos(math.clamp(an:Dot(bn), -1, 1))))
				end
			end
			check(
				"a step into a barrier stops where the parts stop it",
				disagree == 0 and worstGap < YARD_TOLERANCE * 1.5,
				`{trials} steps of 4 studs at 10..80 degrees: {stops} stopped by both, {late} grazes the parts' sweep missed and their overlap then caught, {disagree} disagreed; worst stop {fmt(worstGap, 3)} studs apart across the wall ({worstAt})`
			)
			check("the barrier's normal matches", worstDeg < 3, `worst {fmt(worstDeg, 2)} degrees (the parts are 4-stud chords of the curve)`)
		end

		-- 3. Inside a barrier: pushed out the same way, as far.
		if want("push") then
			local rng = Random.new(5)
			local worstDepth, worstDeg, misses, tried, joints = 0, 0, 0, 0, 0
			for _ = 1, 200 do
				local s = 80 + rng:NextNumber() * (LENGTH - 160)
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				local rel = math.rad((rng:NextNumber() * 2 - 1) * 5)
				local yaw = spline:yawAt(s) + rel
				-- the car's widest point 0.2..0.8 studs into the wall: well under the barrier's
				-- 2 studs of thickness, so the shortest way out of the parts is back on to the road
				local ext = D.BodyWidth * 0.5 * math.abs(math.cos(rel)) + D.BodyLength * 0.5 * math.abs(math.sin(rel))
				local d0 = side * (half - ext + 0.2 + rng:NextNumber() * 0.6)
				local x, y, z = spline:surfaceXYZ(s, d0)
				local pos = Vector3.new(x, y + D.RideHeight, z)
				local a, ad = sw.penetration(pos, yaw)
				local b, bd = liveWalls.penetration(pos, yaw)
				-- only cars genuinely 0.2..0.9 in by the maths: a bend moves the corners
				if not a or ad < 0.2 + 0.05 or ad > 0.9 + 0.05 then
					continue
				end
				tried += 1
				if not b then
					misses += 1
				else
					-- THE PARTS HAVE JOINTS: one barrier box a slice, each 0.3 studs long, so
					-- near a joint the shortest way out of a box is out of its END, along the
					-- road. That is the yardstick, not the road; counted and shown, not judged.
					if a.Unit:Dot(b.Unit) < 0.5 then
						joints += 1
					else
						worstDepth = math.max(worstDepth, math.abs(ad - bd))
						worstDeg = math.max(worstDeg, math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))))
					end
				end
			end
			check("a car inside a barrier is pushed out as far as by the parts", misses == 0 and tried >= 100 and worstDepth < 0.15, `{tried} cars 0.2..0.9 studs in by the maths: {misses} not pushed by the parts, {joints} pushed out of a barrier joint along the road; otherwise depths differ by {fmt(worstDepth, 3)} at worst, directions by {fmt(worstDeg, 2)} degrees`)
		end

		-- 4. A drive: the same autopilot down the same road on each world.
		if want("drive") then
			local function locateS(pos, hint)
				local s, d = spline:projectFrom(pos.X, pos.Z, hint)
				if not s then
					s, d = spline:project(pos.X, pos.Z, 80)
				end
				return s, d
			end
			local tA = os.clock()
			local a = drive(Sim, spline, sw, locateS, DRIVE_SECONDS, 20, LENGTH - 150)
			local secA = os.clock() - tA
			local tB = os.clock()
			local b = drive(Sim, spline, live, locateS, DRIVE_SECONDS, 20, LENGTH - 150)
			local secB = os.clock() - tB
			check(
				"the car drives the spline road on the maths",
				a.s >= LENGTH - 160 and a.offRoad == 0 and a.airborne == 0,
				`{fmt(a.s, 0)} of {LENGTH - 150} studs in {fmt(a.seconds, 1)} s (mean {fmt(a.meanSpeed, 0)} studs/s), {a.offRoad} steps off the road, {a.airborne} airborne, {a.wallSteps} touching a barrier, widest {fmt(a.worstLateral, 1)} from the centre`
			)
			check(
				"and drives it as it drives the parts",
				b.s >= LENGTH - 160 and math.abs(a.seconds - b.seconds) <= 0.1 * b.seconds,
				`parts: {fmt(b.s, 0)} studs in {fmt(b.seconds, 1)} s (mean {fmt(b.meanSpeed, 0)}), {b.offRoad} off, {b.airborne} airborne, {b.wallSteps} on a barrier, widest {fmt(b.worstLateral, 1)}`
			)
			-- the first seconds should be the same drive, before small differences grow
			local apart = 0
			for i = 1, math.min(#a.path, #b.path, 50) do
				apart = math.max(apart, (a.path[i] - b.path[i]).Magnitude)
			end
			check("the first 2.5 seconds are the same drive", apart < 0.5, `worst {fmt(apart, 3)} studs apart over the first {math.min(#a.path, #b.path, 50)} samples (every 0.05 s)`)
			local perStepA = secA / math.max(1, a.steps) * 1e6
			local perStepB = secB / math.max(1, b.steps) * 1e6
			check("the maths costs no more than the rays", perStepA <= perStepB * 1.2, `a whole model step on the maths {fmt(perStepA, 0)} microseconds, on the parts {fmt(perStepB, 0)} (autopilot included in both)`)
		end

		-- 5. Barriers off: the car leaves the road and falls.
		if want("rails") then
			local s = 900
			local function offTheSide(world)
				local yaw = spline:yawAt(s)
				-- heading straight out of the right side, at 50 studs/s
				local outYaw = yaw - math.pi / 2
				local x, y, z = spline:surfaceXYZ(s, half - 6)
				local runner = Sim.newRunner(CFrame.new(x, y + D.RideHeight, z) * CFrame.Angles(0, outYaw, 0))
				runner.state.velocity = Vector3.new(-math.sin(outYaw), 0, -math.cos(outYaw)) * 50
				runner.state.time = 10
				for _ = 1, 3 * DRIVE_FPS do
					Sim.advance(runner, 1 / DRIVE_FPS, { steer = 0, handbrake = false }, world)
				end
				local p = runner.state.position
				local _, d = spline:projectFrom(p.X, p.Z, s)
				return d or math.huge, y - p.Y, runner.state
			end
			sw.setRails(true)
			local dOn, dropOn = offTheSide(sw)
			sw.setRails(false)
			local dOff, dropOff, stOff = offTheSide(sw)
			sw.setRails(true)
			check("rails on: the barrier holds the car", dOn <= half and dropOn < 1, `after 3 s driving at it: {fmt(dOn, 2)} studs from the centre (barrier at {half}), {fmt(dropOn, 2)} below the road`)
			check("rails off: the car leaves the road and falls", dOff > half and dropOff > 20 and stOff.airborne, `after 3 s: {fmt(dOff, 1)} from the centre, {fmt(dropOff, 1)} studs below the road, airborne {tostring(stOff.airborne)}`)
		end

		-- 6. The closing barrier behind the car never switches off.
		if want("closing") then
			local sc = 400
			sw.setClosing(sc)
			sw.setRails(false)
			local yaw = spline:yawAt(sc + 30)
			local x, y, z = spline:surfaceXYZ(sc + 30, 0)
			-- reversing toward it: facing back down the road
			local back = yaw + math.pi
			local runner = Sim.newRunner(CFrame.new(x, y + D.RideHeight, z) * CFrame.Angles(0, back, 0))
			runner.state.velocity = Vector3.new(-math.sin(back), 0, -math.cos(back)) * 50
			runner.state.time = 10
			local least = math.huge
			for _ = 1, 3 * DRIVE_FPS do
				Sim.advance(runner, 1 / DRIVE_FPS, { steer = 0, handbrake = false }, sw)
				local p = runner.state.position
				local s = spline:projectFrom(p.X, p.Z, sc)
				if s then
					least = math.min(least, s)
				end
			end
			sw.setClosing(nil)
			sw.setRails(true)
			check("the closing barrier stops a car going back, rails off or on", least >= sc + D.BodyLength * 0.5 - 0.5, `driven back at it for 3 s: the car's middle got to {fmt(least - sc, 2)} studs in front of it (half the car is {fmt(D.BodyLength * 0.5, 2)})`)
		end

		-- 7. Lost: a lookup from a hint that is nowhere near still finds the road.
		if want("lost") then
			sw.hint = LENGTH - 20
			local x, y, z = spline:surfaceXYZ(150, 7)
			local hit = sw.probe(Vector3.new(x, y + D.RideHeight, z))
			check("a car put somewhere else entirely still finds the ground", hit ~= nil and math.abs(hit.y - y) < 1e-3 and math.abs(sw.hint - 150) < 1, `hint {LENGTH - 20} studs out, ground found at {hit and fmt(hit.y - y, 5) or "nothing"} from the surface, hint now {fmt(sw.hint, 2)}`)
		end
		live.destroy()
		liveWalls.destroy()
	end)
	if not ok then
		check("the suite ran", false, tostring(err))
	end
	folder:Destroy()
	table.insert(checks, 1, { name = "yardstick built", ok = #parts > 0, detail = `{#parts} parts for {LENGTH} studs of road in {fmt(buildSeconds, 1)} s` })

	local passed = 0
	for _, c in checks do
		if c.ok then
			passed += 1
		end
	end
	return { passed = passed, total = #checks, checks = checks }
end

return Tests
