--!nonstrict
-- GrindEventsTests: the bumper grind and the hang grind (features/score-events.md, T-297),
-- and the wall contact the drift model now carries for them.
--
--   game.ServerStorage.DebugBridge:Invoke("DebugGrindEventsTests", "run")
--   game.ServerStorage.DebugBridge:Invoke("DebugGrindEventsTests", "digest")
--   game.ServerStorage.DebugBridge:Invoke("DebugGrindEventsTests", "measure", seeds, seconds)
--
-- Each takes a few seconds to a minute: call it from a `task.spawn` and poll.
--
-- THE DETECTORS ARE TESTED WITH A RECORDING SINK, not the score engine: each records what it
-- was asked to start, every `update` it was fed and how it finished. First on made-up
-- frames (what each event must and must not do), then on the real model (`Drift/Sim`) on the
-- mountain road and on a ledge.
--
--   run      the checks: `{ passed, checks }`
--   digest   a hash of every number the car's motion is made of, every step, over a set of
--            recorded drives (an autopilot, K-rail scrapes, drop edges). The same on the
--            commit before the wall contact was carried out and after it is the proof that
--            the car moves the same to the bit
--   measure  a stylised driver down today's road, seed by seed, counting each grind: how
--            often they happen in plain driving

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "GrindEventsTests only runs in Studio")

local Cars = require(ReplicatedStorage.Shared.Cars)
local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")

local Tests = {}

local SEED = 2024 -- SplineWorldTests' road: it holds K-rails and railless drops early on
local FPS = 60

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 2) .. "f", x)
end

--------------------------------------------------------------------------------
-- The recording sink
--------------------------------------------------------------------------------

-- A sink that records, in place of the score engine. `rec.events` is every event started
-- (and every one-off), in order; each sustained one counts its updates, the size it was fed
-- over time, and how it finished (`result` true banked, false void, nil still live).
local function recorder()
	local rec = { events = {}, clock = 0, misuse = {} }
	rec.sink = {
		oneOff = function(kind, size, info)
			table.insert(rec.events, { kind = kind, oneOff = true, size = size, info = info, at = rec.clock })
		end,
		start = function(kind, info)
			local e = { kind = kind, info = info, at = rec.clock, updates = 0, sizeTime = 0, seconds = 0, maxSize = 0, minSize = math.huge, result = nil }
			table.insert(rec.events, e)
			return {
				update = function(_, size, dt)
					if e.result ~= nil then
						table.insert(rec.misuse, `{kind}: update after finish`)
					end
					if type(size) ~= "number" or size < 0 or size > 1 or size ~= size then
						table.insert(rec.misuse, `{kind}: size {tostring(size)}`)
					end
					e.updates += 1
					e.sizeTime += size * dt
					e.seconds += dt
					e.maxSize = math.max(e.maxSize, size)
					e.minSize = math.min(e.minSize, size)
				end,
				finish = function(_, completed)
					if e.result ~= nil then
						table.insert(rec.misuse, `{kind}: finished twice`)
					end
					e.result = completed == true
					e.endAt = rec.clock
				end,
			}
		end,
	}
	function rec.count(kind, result)
		local n = 0
		for _, e in rec.events do
			if e.kind == kind and (result == "any" or e.result == result) then
				n += 1
			end
		end
		return n
	end
	return rec
end

--------------------------------------------------------------------------------
-- Made-up frames
--------------------------------------------------------------------------------

-- A car sliding along a rail on its right, the rail's line along Z, the car heading -Z with
-- its nose turned `angle` degrees off the rail. The model's own fixed step and contact
-- clock are imitated: the rail is met on one step in `every` (`every = 12` is T-074's
-- measured one in twelve), and a frame is `120 / fps` steps.
-- `script(t)` returns this moment's { along, into, point, kind, angle, every, fell, jump }.
local function railFrames(fps: number, seconds: number, detector, rec, script)
	local D = Config.Drift
	local step = D.FixedStep
	local state = {
		position = Vector3.new(0, 10, 0),
		velocity = Vector3.zero,
		yaw = 0,
		u = 0,
		pinned = false,
		fell = false,
		sinceWall = math.huge,
		wallTouch = false,
		wallSteps = 0,
		wallKind = "",
		wallPoint = "",
		wallSide = "",
		wallInto = 0,
		wallAlong = 0,
		wallNormal = Vector3.zero,
	}
	local t, nStep, acc = 0, 0, 0
	local frameDt = 1 / fps
	while t < seconds - 1e-9 do
		acc += frameDt
		local sc = script(t)
		while acc >= step - 1e-9 do
			acc -= step
			nStep += 1
			t += step
			local yaw = math.rad(sc.angle or 20)
			state.yaw = yaw
			state.velocity = Vector3.new(0, 0, -(sc.along or 60))
			state.u = (sc.along or 60) * math.cos(yaw)
			state.position += state.velocity * step
			if sc.every and sc.every > 0 and nStep % sc.every == 0 then
				state.sinceWall = 0
				state.wallSteps += 1
				state.wallKind = sc.kind or "krail"
				state.wallPoint = sc.point or "rear"
				state.wallSide = "right"
				state.wallInto = sc.into or 5
				state.wallNormal = Vector3.new(-1, 0, 0)
			else
				state.sinceWall += step
			end
			state.wallTouch = state.sinceWall <= D.WallContactGrace and state.wallKind ~= ""
			if state.wallTouch then
				state.wallAlong = sc.along or 60
			else
				state.wallKind, state.wallPoint, state.wallSide, state.wallInto, state.wallAlong = "", "", "", 0, 0
			end
		end
		state.fell = sc.fell == true
		if sc.jump then
			state.position += Vector3.new(500, 0, 0)
		end
		rec.clock = t
		detector:Update(frameDt, state)
	end
	return state
end

-- A car hanging its rear off an edge at y = 0 that runs along X, the car facing -Z, sliding
-- along the edge. `script(t)` returns this moment's { hanging, rearOff, frontOff, speed,
-- out (studs of body behind the edge), y (feet height), airborne, fell }.
local function hangFrames(fps: number, seconds: number, detector, rec, script)
	local D = Config.Drift
	local half = D.BodyLength * 0.5
	local state = {
		position = Vector3.new(0, D.RideHeight, 0),
		velocity = Vector3.zero,
		yaw = 0,
		u = 0,
		pinned = false,
		fell = false,
		airborne = false,
		hanging = false,
		floorTouching = 0,
		floorContacts = {},
		wheelsDown = { true, true, true, true },
	}
	local t = 0
	local dt = 1 / fps
	while t < seconds - 1e-9 do
		t += dt
		local sc = script(t)
		local speed = sc.speed or 8
		state.velocity = Vector3.new(speed, 0, 0)
		state.position = Vector3.new(state.position.X + speed * dt, (sc.y or 0) + D.RideHeight, 0)
		state.hanging = sc.hanging == true
		state.airborne = sc.airborne == true
		state.fell = sc.fell == true
		state.wheelsDown = { not sc.frontOff, not sc.frontOff, not sc.rearOff, not sc.rearOff }
		if state.hanging then
			-- the rear `out` studs of the body are past the edge (z > 0 behind the car's middle)
			local zEdge = half - (sc.out or 3) -- behind the middle, in the car's frame
			local px = state.position.X
			state.floorContacts = {
				{ name = "edge", position = Vector3.new(px - 1, 0, zEdge), speed = speed, edge = true },
				{ name = "edge", position = Vector3.new(px + 1, 0, zEdge), speed = speed, edge = true },
			}
			state.floorTouching = 2
		else
			state.floorContacts = {}
			state.floorTouching = 0
		end
		rec.clock = t
		detector:Update(dt, state)
	end
	return state
end

--------------------------------------------------------------------------------
-- The real model
--------------------------------------------------------------------------------

local function dir(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- The digest's driver: RunTests' autopilot down the road, but aimed at the tarmac's very edge
-- on the outside of bends, with a weave on the finger, so it meets rails and slides. FROZEN:
-- the digest is compared across commits, so it must drive exactly the same.
local function wideDriver(sp, D, half)
	local lastS = nil
	return function(st)
		local s = sp:projectFrom(st.position.X, st.position.Z, lastS or 300) or lastS or 300
		lastS = s
		local speed = math.sqrt(st.velocity.X ^ 2 + st.velocity.Z ^ 2)
		local heading = if speed > 1 then Vector3.new(st.velocity.X / speed, 0, st.velocity.Z / speed) else dir(st.yaw)
		local look = math.clamp(speed * 0.9, 30, 120)
		local tx, tz = sp:planAt(math.min(s + look, sp.length))
		local k = sp:curvatureAt(math.min(s + look * 0.5, sp.length))
		local yawT = sp:yawAt(math.min(s + look, sp.length))
		local aim = if math.abs(k) > 1 / 400 then -math.sign(k) * (half - 1) else 0
		tx += math.cos(yawT) * aim
		tz += -math.sin(yawT) * aim
		local dx, dz = tx - st.position.X, tz - st.position.Z
		local len = math.sqrt(dx * dx + dz * dz)
		local steer = 0
		if len > 1e-3 then
			local alpha = math.atan2((dx / len) * heading.Z - (dz / len) * heading.X, (dx / len) * heading.X + (dz / len) * heading.Z)
			steer = math.clamp(speed * (2 * math.sin(alpha) / look) / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
		end
		steer = math.clamp(steer + 0.35 * math.sin(st.time * 4.1), -1, 1)
		local kMax = 0
		for u = 0, math.max(speed * 1.6, 30), 8 do
			kMax = math.max(kMax, math.abs(sp:curvatureAt(math.min(s + u, sp.length))))
		end
		return { steer = steer, handbrake = speed * speed * kMax > 65 }, s
	end
end

-- The drivers `measure` uses, each a stand-in for a way of driving. None of them is a player;
-- what they say is how often a grind turns up when nobody is looking for one.
--   tidy   the autopilot RunTests drives with: the middle of the road, braking for bends
--   wide   no brake (a player has none), on the outside of every bend `aim` studs in from
--          the tarmac's edge, where the K-rails stand, with a weave on the finger
--   hugging  the same, closer to the edge and weaving more: a player leaning on the rails
local DRIVERS = {
	tidy = { aim = 0, weave = 0, brake = 65 },
	wide = { aim = 3.5, weave = 0.25, brake = nil },
	hugging = { aim = 1.5, weave = 0.3, brake = nil },
}

local function driverFor(sp, D, half, how)
	local lastS = nil
	return function(st)
		local s = sp:projectFrom(st.position.X, st.position.Z, lastS or 300) or lastS or 300
		lastS = s
		local speed = math.sqrt(st.velocity.X ^ 2 + st.velocity.Z ^ 2)
		local heading = if speed > 1 then Vector3.new(st.velocity.X / speed, 0, st.velocity.Z / speed) else dir(st.yaw)
		local look = math.clamp(speed * 0.9, 30, 120)
		local tx, tz = sp:planAt(math.min(s + look, sp.length))
		local k = sp:curvatureAt(math.min(s + look * 0.5, sp.length))
		local yawT = sp:yawAt(math.min(s + look, sp.length))
		local aim = if how.aim > 0 and math.abs(k) > 1 / 400 then -math.sign(k) * (half - how.aim) else 0
		tx += math.cos(yawT) * aim
		tz += -math.sin(yawT) * aim
		local dx, dz = tx - st.position.X, tz - st.position.Z
		local len = math.sqrt(dx * dx + dz * dz)
		local steer = 0
		if len > 1e-3 then
			local alpha = math.atan2((dx / len) * heading.Z - (dz / len) * heading.X, (dx / len) * heading.X + (dz / len) * heading.Z)
			steer = math.clamp(speed * (2 * math.sin(alpha) / look) / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
		end
		steer = math.clamp(steer + how.weave * math.sin(st.time * 4.1), -1, 1)
		local brake = false
		if how.brake then
			local kMax = 0
			for u = 0, math.max(speed * 1.6, 30), 8 do
				kMax = math.max(kMax, math.abs(sp:curvatureAt(math.min(s + u, sp.length))))
			end
			brake = speed * speed * kMax > how.brake
		end
		return { steer = steer, handbrake = brake }, s
	end
end

-- The first few long K-rail runs on a road, and the first railless drops beside it.
local function railsOf(sp, n: number)
	local rails = {}
	for _, side in { 1, -1 } do
		local runs = sp:kRailsIn(300, 8000, side)
		for i = 1, #runs, 2 do
			if #rails < n and runs[i + 1] - runs[i] > 120 then
				table.insert(rails, { a = runs[i], b = runs[i + 1], side = side })
			end
		end
	end
	return rails
end

local function dropsOf(sp, off, half: number, n: number)
	local drops = {}
	for s = 400, 7800, 13 do
		if #drops >= n then
			break
		end
		for _, side in { 1, -1 } do
			if not sp:kRailAt(s, side) and math.abs(sp:curvatureAt(s)) < 1 / 300 then
				local edge = half + sp:runoffAt(s, side)
				local yaw = sp:yawAt(s)
				local cx, cz = sp:planAt(s)
				local rx, rz = math.cos(yaw) * side, -math.sin(yaw) * side
				local y1 = off.sample(cx + rx * (edge + 0.5), cz + rz * (edge + 0.5))
				local y8 = off.sample(cx + rx * (edge + 8), cz + rz * (edge + 8))
				if y1 - y8 > 4.5 and #drops < n and (#drops == 0 or s - drops[#drops].s > 300) then
					table.insert(drops, { s = s, side = side, edge = edge })
				end
			end
		end
	end
	return drops
end

--------------------------------------------------------------------------------
-- digest: the car's motion, to the bit
--------------------------------------------------------------------------------

-- `world` is wrapped by `wrap(world)` when given: the run checks use it to strip the wall
-- contact's extra returns and show the motion is the same either way.
function Tests.digest(_self, wrap)
	if _self ~= Tests then
		wrap = _self
	end
	local Sim = require(DriftFolder.Sim)
	local SplineWorld = require(DriftFolder.SplineWorld)
	local D = Config.Drift
	local half = Config.Road.Width * 0.5
	local rateK = D.MaxSteeringSpeed * D.SteeringSensitivity * (if D.InvertSteering then 1 else -1)
	local function steerFor(rate)
		return math.clamp(rate / rateK, -1, 1)
	end

	local buf = buffer.create(8 * 48)
	local h1, h2, nSteps = 0, 0, 0
	local function absorb(st)
		local i = 0
		local function w(x)
			buffer.writef64(buf, i, x)
			i += 8
		end
		local function v3(v)
			w(v.X)
			w(v.Y)
			w(v.Z)
		end
		v3(st.position)
		v3(st.velocity)
		w(st.yaw)
		w(st.r)
		w(st.u)
		w(st.v)
		w(st.vy)
		w(st.slip)
		w(st.throttle)
		w(st.gripAccel)
		v3(st.up)
		v3(st.groundUp)
		w(st.heave)
		w(st.height)
		w(st.sinceWall)
		w(st.crawlSeconds)
		w(st.tiltRate.X)
		w(st.tiltRate.Y)
		w(st.body.z)
		w(st.body.p)
		w(st.body.q)
		w(st.body.vz)
		w(st.body.vp)
		w(st.body.vq)
		for k = 1, 4 do
			w(st.travel[k])
		end
		for k = 1, 4 do
			w(st.strut[k])
		end
		w(st.fallFrom)
		w(st.surfaceGrip)
		local flags = (if st.airborne then 1 else 0) + (if st.hanging then 2 else 0) + (if st.pinned then 4 else 0)
			+ (if st.wallHit then 8 else 0) + (if st.rearDown then 16 else 0) + (if st.fell then 32 else 0)
		for k = 1, 4 do
			flags += if st.wheelsDown[k] then 64 * 2 ^ (k - 1) else 0
		end
		w(flags)
		w(st.floorTouching)
		for k = 0, i - 4, 4 do
			local word = buffer.readu32(buf, k)
			h1 = (h1 * 31 + word) % 4294967291
			h2 = (h2 * 65599 + word) % 2147483647
		end
		nSteps += 1
	end

	local gen = SplineGen.new(SEED)
	gen:extendTo(8300)
	local sp = gen.spline
	local result = { scenarios = {} }
	local function newWorld()
		local w = SplineWorld.new(sp, nil)
		return if wrap then wrap(w) else w
	end

	local function start(s, d, yaw, speedVec, t)
		local x, y, z = sp:surfaceXYZ(s, d)
		local runner = Sim.newRunner(CFrame.new(x, y + D.RideHeight, z) * CFrame.Angles(0, yaw, 0))
		runner.state.velocity = speedVec
		runner.state.time = t or 10
		return runner
	end

	local function run(name, runner, world, seconds, inputFn)
		local walls, hangs, air = 0, 0, 0
		local nb = nSteps
		local elapsed, frames = 0, 0
		while elapsed < seconds do
			local input = inputFn(runner.state)
			Sim.advance(runner, 1 / FPS, input, world, function(st)
				absorb(st)
				if st.wallHit then
					walls += 1
				end
				if st.hanging then
					hangs += 1
				end
				if st.airborne then
					air += 1
				end
			end)
			elapsed += 1 / FPS
			frames += 1
			if frames % 30 == 0 then
				task.wait()
			end
		end
		local st = runner.state
		table.insert(result.scenarios, {
			name = name,
			steps = nSteps - nb,
			walls = walls,
			hangs = hangs,
			air = air,
			pos = string.format("%.17g,%.17g,%.17g", st.position.X, st.position.Y, st.position.Z),
		})
	end

	do
		local w = newWorld()
		local yaw0 = sp:yawAt(300)
		local runner = start(300, 0, yaw0, dir(yaw0) * 40)
		local drive = wideDriver(sp, D, half)
		run("autopilot", runner, w, 60, function(st)
			return (drive(st))
		end)
	end

	local rails = railsOf(sp, 4)
	result.rails = #rails
	for ri, rail in rails do
		for _, k in { 0, 0.15, 0.3 } do
			local w = newWorld()
			local s0 = rail.a + 15
			local y0 = sp:yawAt(s0)
			local side = rail.side
			local runner = start(s0, side * (half - 4), y0 + side * math.rad(20), dir(y0 - side * math.rad(6)) * 70)
			local steer = steerFor(-side * k * rateK)
			run(`rail{ri}/k{k}`, runner, w, 2.5, function()
				return { steer = steer, handbrake = false }
			end)
		end
	end

	local probe = SplineWorld.new(sp, nil)
	local drops = dropsOf(sp, probe.offRoad, half, 3)
	result.drops = #drops
	for di, drop in drops do
		local yaw = sp:yawAt(drop.s)
		local outYaw = yaw - drop.side * math.pi / 2
		for _, v in { 8, 14 } do
			local w = newWorld()
			local runner = start(drop.s, drop.side * (drop.edge - 4), outYaw, dir(outYaw) * v, 0)
			run(`drop{di}/fwd{v}`, runner, w, 3, function()
				return { steer = 0, handbrake = false }
			end)
			local w2 = newWorld()
			local runner2 = start(drop.s, drop.side * (drop.edge - 4), outYaw + math.pi, dir(outYaw) * v, 0)
			run(`drop{di}/back{v}`, runner2, w2, 3, function()
				return { steer = 0, handbrake = false }
			end)
		end
		for _, v in { 10, 14 } do
			local w3 = newWorld()
			local s0 = drop.s - 20
			local y0 = sp:yawAt(s0)
			local runner3 = start(s0, drop.side * (drop.edge - 1.5), y0 + drop.side * math.rad(50), dir(y0) * v, 0)
			local steer = steerFor(drop.side * 0.2 * rateK)
			run(`drop{di}/tail{v}`, runner3, w3, 3, function()
				return { steer = steer, handbrake = false }
			end)
		end
	end

	result.steps = nSteps
	result.hash = string.format("%d/%d", h1, h2)
	return result
end

--------------------------------------------------------------------------------
-- measure: how often each grind happens in plain driving
--------------------------------------------------------------------------------

-- `seconds` of driving on each seed with the driver named `how` (`DRIVERS`), both detectors
-- fed every frame with the real model's state, a recording sink behind them. The car is put
-- back on the road, as the game does, when it falls or stops getting anywhere. Returns a log
-- per seed and the totals, with what the car's bumper did on the rails when no grind came.
function Tests.measure(_self, seeds, seconds, how)
	if _self ~= Tests then
		seeds, seconds, how = _self, seeds, seconds
	end
	seeds = seeds or { 2024, 268, 270, 31337 }
	seconds = seconds or 60
	how = how or "wide"
	local Sim = require(DriftFolder.Sim)
	local SplineWorld = require(DriftFolder.SplineWorld)
	local BumperGrind = require(DriftFolder.Events.BumperGrind)
	local HangGrind = require(DriftFolder.Events.HangGrind)
	local HS = game:GetService("HttpService")
	local D = Config.Drift
	local B = BumperGrind.Tuning
	local half = Config.Road.Width * 0.5
	local out = { driver = how, seeds = {}, totals = {} }
	local totals = {
		seconds = 0, studs = 0, puts = 0,
		bumper = 0, bumperBanked = 0, bumperVoid = 0, bumperSeconds = 0,
		hang = 0, hangBanked = 0, hangVoid = 0, hangSeconds = 0,
		krailSteps = 0, rockSteps = 0, treeSteps = 0, otherSteps = 0, hangingSteps = 0, rearHangSteps = 0,
		-- frames with a bumper corner on a K-rail, and why each was not a grind
		bumperFrames = 0, tooSlow = 0, tooSquare = 0, backwards = 0, qualifying = 0,
	}
	for _, seed in seeds do
		local gen = SplineGen.new(seed)
		local length = 140 * seconds + 1000
		gen:extendTo(length)
		local sp = gen.spline
		local world = SplineWorld.new(sp, nil)
		local rec = recorder()
		local bumper = BumperGrind.new(rec.sink, nil)
		local hang = HangGrind.new(rec.sink, nil)
		local s0 = sp.firstSample * sp.step + 100
		local function put(s)
			local cf = sp:frame(s, D.RideHeight)
			local yaw = sp:yawAt(s)
			local runner = Sim.newRunner(CFrame.lookAt(cf.Position, cf.Position + dir(yaw)))
			runner.state.velocity = dir(yaw) * 40
			runner.state.time = 10
			return runner
		end
		local runner = put(s0)
		local drive = driverFor(sp, D, half, DRIVERS[how])
		local log = { seed = seed, events = {} }
		local elapsed, frames, lastS = 0, 0, s0
		local progressAt, progressS = 0, s0
		local kindSteps = { krail = 0, rock = 0, other = 0, tree = 0, closing = 0 }
		local hangingSteps, rearHang = 0, 0
		while elapsed < seconds do
			local input, s = drive(runner.state)
			Sim.advance(runner, 1 / FPS, input, world, function(st)
				if st.wallHit and st.wallKind ~= "" then
					kindSteps[st.wallKind] = (kindSteps[st.wallKind] or 0) + 1
				end
				if st.hanging then
					hangingSteps += 1
					if HangGrind.axle(st) == "rear" then
						rearHang += 1
					end
				end
			end)
			elapsed += 1 / FPS
			frames += 1
			rec.clock = elapsed
			local st = runner.state
			bumper:Update(1 / FPS, st)
			hang:Update(1 / FPS, st)
			if st.wallTouch and st.wallKind == "krail" and (st.wallPoint == "front" or st.wallPoint == "rear") then
				totals.bumperFrames += 1
				local ds = bumper:DebugState()
				if st.u <= 0 then
					totals.backwards += 1
				elseif ds.angle < B.MinAngle then
					totals.tooSquare += 1
				elseif ds.along < B.MinSpeed then
					totals.tooSlow += 1
				else
					totals.qualifying += 1
				end
			end
			-- put back on the road when it falls or stops getting anywhere, as the game does
			if s > progressS + 20 then
				progressAt, progressS = elapsed, s
			end
			if st.fell or elapsed - progressAt > 3 then
				local at = math.min(math.max(s, progressS) + 40, length - 500)
				runner = put(at)
				progressAt, progressS = elapsed, at
				totals.puts += 1
			end
			totals.studs += math.clamp(s - lastS, 0, 10)
			lastS = s
			if s >= length - 400 then
				break
			end
			if frames % 30 == 0 then
				task.wait()
			end
		end
		for _, e in rec.events do
			table.insert(log.events, string.format("%s at %.1fs for %.2fs: %s, size %.2f..%.2f, %s", e.kind, e.at, e.seconds, if e.result == true then "banked" elseif e.result == false then "void" else "live", if e.minSize == math.huge then 0 else e.minSize, e.maxSize, HS:JSONEncode(e.info or {})))
			if e.kind == "bumperGrind" then
				totals.bumper += 1
				totals.bumperSeconds += e.seconds
				totals.bumperBanked += if e.result == true then 1 else 0
				totals.bumperVoid += if e.result == false then 1 else 0
			elseif e.kind == "hangGrind" then
				totals.hang += 1
				totals.hangSeconds += e.seconds
				totals.hangBanked += if e.result == true then 1 else 0
				totals.hangVoid += if e.result == false then 1 else 0
			end
		end
		log.kinds = kindSteps
		log.hangingSteps = hangingSteps
		log.rearHangSteps = rearHang
		log.seconds = elapsed
		log.misuse = rec.misuse
		totals.seconds += elapsed
		totals.krailSteps += kindSteps.krail
		totals.rockSteps += kindSteps.rock
		totals.treeSteps += kindSteps.tree
		totals.otherSteps += kindSteps.other
		totals.hangingSteps += hangingSteps
		totals.rearHangSteps += rearHang
		table.insert(out.seeds, log)
	end
	out.totals = totals
	return out
end

--------------------------------------------------------------------------------
-- run: the checks
--------------------------------------------------------------------------------

function Tests.run(which, ...)
	if which == Tests then
		which = ...
	end
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok == true, detail = detail })
	end
	local function want(name)
		return which == nil or table.find(which, name) ~= nil
	end
	local Model = require(DriftFolder.Model)
	local Sim = require(DriftFolder.Sim)
	local SplineWorld = require(DriftFolder.SplineWorld)
	local BumperGrind = require(DriftFolder.Events.BumperGrind)
	local HangGrind = require(DriftFolder.Events.HangGrind)
	local D = Config.Drift
	local B = BumperGrind.Tuning
	local H = HangGrind.Tuning
	local half = Config.Road.Width * 0.5

	local ok, err = pcall(function()
		------------------------------------------------------------ the bumper grind, made-up
		if want("bumper") then
			-- held: the rail met one step in twelve, at 60 studs/s, the tail on it; then off
			local function held(fps)
				local rec = recorder()
				local g = BumperGrind.new(rec.sink, nil)
				railFrames(fps, 2, g, rec, function(t)
					return { every = if t < 1.5 then 12 else 0, along = 60 }
				end)
				return rec, g
			end
			local rec, g = held(60)
			local e = rec.events[1]
			check(
				"a bumper on the rail, met one step in twelve, is one grind, banked when it peels off",
				#rec.events == 1 and e.kind == "bumperGrind" and e.result == true and e.at >= B.MinHold and e.at < 0.3 and e.endAt >= 1.5 + B.Grace - 0.05 and e.endAt <= 1.5 + B.Grace + 0.15 and #rec.misuse == 0,
				`{#rec.events} event(s): started at {e and fmt(e.at) or "-"} s, ended at {e and e.endAt and fmt(e.endAt) or "-"} s (contact stopped at 1.50, grace {B.Grace}), {e and (if e.result then "banked" else "void") or "-"}, {e and e.updates or 0} updates, size {e and fmt(e.minSize) or "-"}..{e and fmt(e.maxSize) or "-"}; misuse {#rec.misuse}; {g:DebugState().lastEnd}`
			)
			-- the same at 30 and 120 FPS
			local totals = {}
			for _, fps in { 30, 60, 120 } do
				local r = held(fps)
				local ev = r.events[1]
				table.insert(totals, { fps = fps, n = #r.events, at = ev and ev.at or -1, sizeTime = ev and ev.sizeTime or 0, ok = ev and ev.result == true })
			end
			local lo, hi = math.huge, 0
			for _, x in totals do
				lo, hi = math.min(lo, x.sizeTime), math.max(hi, x.sizeTime)
			end
			check(
				"the same grind at 30, 60 and 120 FPS",
				totals[1].n == 1 and totals[2].n == 1 and totals[3].n == 1 and totals[1].ok and totals[3].ok and hi - lo < 0.1 * hi,
				`size x seconds {fmt(totals[1].sizeTime, 3)} / {fmt(totals[2].sizeTime, 3)} / {fmt(totals[3].sizeTime, 3)}, started at {fmt(totals[1].at)} / {fmt(totals[2].at)} / {fmt(totals[3].at)} s`
			)
			-- what must never start one
			local function none(name, sc)
				local r = recorder()
				local gg = BumperGrind.new(r.sink, nil)
				railFrames(60, 1.5, gg, r, function()
					return sc
				end)
				return #r.events, name
			end
			local rows, bad = {}, 0
			for _, case in {
				{ "a door along the rail", { every = 12, along = 60, point = "side" } },
				{ "a middle point", { every = 12, along = 60, point = "middle" } },
				{ "square along it (2 degrees)", { every = 12, along = 60, angle = 2 } },
				{ "a rock cut", { every = 12, along = 60, kind = "rock" } },
				{ "a tree", { every = 12, along = 60, kind = "tree" } },
				{ "too slow along it", { every = 12, along = B.MinSpeed - 5 } },
				{ "met it hard", { every = 12, along = 60, into = B.MaxInto + 10 } },
				{ "one knock", { every = 100, along = 60 } },
			} do
				local n = none(case[1], case[2])
				table.insert(rows, `{case[1]}: {n}`)
				bad += n
			end
			check("a door, a middle, square along, rock, a tree, too slow, a hard hit or one knock start nothing", bad == 0, table.concat(rows, "; "))
			-- void: a crash, a big loss of speed, a fall, a put-back
			local function voidBy(sc)
				local r = recorder()
				local gg = BumperGrind.new(r.sink, nil)
				railFrames(60, 1.5, gg, r, sc)
				local ev = r.events[1]
				return ev and ev.result, gg:DebugState().lastEnd, #r.events
			end
			local hit = { voidBy(function(t)
				return { every = 12, along = 60, into = if t > 0.6 then 40 else 5 }
			end) }
			local slow = { voidBy(function(t)
				return { every = 12, along = if t > 0.6 then 25 else 70 }
			end) }
			local fell = { voidBy(function(t)
				return { every = 12, along = 60, fell = t > 0.6 }
			end) }
			local put = { voidBy(function(t)
				return { every = 12, along = 60, jump = t > 0.6 and t < 0.62 }
			end) }
			check(
				"void on a hard hit, a big loss of speed, a fall and a put-back",
				hit[1] == false and hit[2] == "crash" and slow[1] == false and slow[2] == "crash" and fell[1] == false and fell[2] == "fell" and put[1] == false and put[2] == "putBack",
				`hard hit: {tostring(hit[1])} ({hit[2]}); 70 to 25 studs/s: {tostring(slow[1])} ({slow[2]}); fall: {tostring(fell[1])} ({fell[2]}); put-back: {tostring(put[1])} ({put[2]})`
			)
			-- the size: faster along the rail is bigger, and a patchy contact is smaller
			local function sizeAt(along, every)
				local r = recorder()
				local gg = BumperGrind.new(r.sink, nil)
				railFrames(60, 1.5, gg, r, function()
					return { every = every, along = along }
				end)
				local ev = r.events[1]
				return if ev then ev.sizeTime / math.max(ev.seconds, 1e-6) else 0
			end
			local s45, s90, sPatchy = sizeAt(45, 6), sizeAt(90, 6), sizeAt(90, 24)
			check(
				"faster along the rail is a bigger grind, a patchy one smaller",
				s90 > s45 and s45 > 0 and sPatchy < s90 and sPatchy > 0,
				`mean size at 45 studs/s {fmt(s45)}, at 90 {fmt(s90)}; at 90 met one step in 24 {fmt(sPatchy)}`
			)
		end

		------------------------------------------------------------ the hang grind, made-up
		if want("hang") then
			local function hang(sc, seconds)
				local r = recorder()
				local g = HangGrind.new(r.sink, nil)
				hangFrames(60, seconds or 2, g, r, sc)
				return r, g
			end
			-- hangs, slides along the edge, pulls back on at the edge's height
			local r, g = hang(function(t)
				local on = t < 1.2
				return { hanging = on, rearOff = on, speed = 10, out = 4, y = 0 }
			end)
			local e = r.events[1]
			check(
				"the rear hanging off an edge, sliding along it, is one hang grind, banked when it gets back on",
				#r.events == 1 and e.kind == "hangGrind" and e.result == true and e.at >= H.MinHold and e.at < 0.3 and e.maxSize > 0 and #r.misuse == 0,
				`{#r.events} event(s): started at {e and fmt(e.at) or "-"} s, {e and (if e.result then "banked" elseif e.result == false then "void" else "live") or "-"} at {e and e.endAt and fmt(e.endAt) or "-"} s, size {e and fmt(e.minSize) or "-"}..{e and fmt(e.maxSize) or "-"}; {g:DebugState().lastEnd}`
			)
			-- further out is bigger
			local function meanSize(out)
				local rr = hang(function()
					return { hanging = true, rearOff = true, speed = 10, out = out }
				end, 1)
				local ev = rr.events[1]
				return if ev then ev.sizeTime / math.max(ev.seconds, 1e-6) else 0
			end
			local near, far = meanSize(1.5), meanSize(5)
			check("further out over the edge is a bigger hang grind", far > near and near > 0, `mean size {fmt(near)} with 1.5 studs of body past the edge, {fmt(far)} with 5`)
			-- goes over: airborne, then lands well below the edge
			local over = hang(function(t)
				if t < 0.8 then
					return { hanging = true, rearOff = true, speed = 10, out = 4, y = 0 }
				elseif t < 1.4 then
					return { airborne = true, speed = 10, y = -2 * (t - 0.8) * 10 }
				end
				return { speed = 10, y = -12 }
			end, 2)
			local fall = hang(function(t)
				return { hanging = t < 0.8, rearOff = t < 0.8, airborne = t >= 0.8, speed = 10, out = 4, fell = t > 1 }
			end, 2)
			local front = hang(function()
				return { hanging = true, frontOff = true, speed = 10, out = 4 }
			end, 1)
			local slow = hang(function()
				return { hanging = true, rearOff = true, speed = H.MinSpeed * 0.5, out = 4 }
			end, 1)
			local oe, fe = over.events[1], fall.events[1]
			check(
				"void when it goes over (lands below the edge) or falls; nothing for a front axle or a car barely moving",
				oe and oe.result == false and fe and fe.result == false and #front.events == 0 and #slow.events == 0,
				`over the edge and down 12: {oe and tostring(oe.result) or "none"}; fell: {fe and tostring(fe.result) or "none"}; front axle hanging: {#front.events} events; at {H.MinSpeed * 0.5} studs/s: {#slow.events}`
			)
		end

		------------------------------------------------------------ the model's wall contact
		local gen = SplineGen.new(SEED)
		gen:extendTo(8300)
		local sp = gen.spline

		if want("contact") then
			-- the outline points, as the mask says them
			local p1, s1 = Model.wallPart(bit32.lshift(1, 2)) -- rear right
			local p2, s2 = Model.wallPart(bit32.bor(1, 2, 4)) -- the whole right side
			local p3, s3 = Model.wallPart(bit32.bor(1, 8)) -- both front corners
			check(
				"the outline points read as the car's parts",
				p1 == "rear" and s1 == "right" and p2 == "side" and s2 == "right" and p3 == "front" and s3 == "",
				`rear right: {p1}/{s1}; front, middle and rear right: {p2}/{s2}; both front corners: {p3}/'{s3}'`
			)
			-- the tail swung into K-rails: what the model says it met, step by step
			local rails = railsOf(sp, 4)
			local rows = {}
			local kinds, points, steps, hitSteps, touchSteps, span = {}, {}, 0, 0, 0, 0
			local gaps = {}
			local alongMax, intoMax = 0, 0
			for ri, rail in rails do
				for _, k in { 0, 0.15, 0.3 } do
					local w = SplineWorld.new(sp, nil)
					local s0 = rail.a + 15
					local y0 = sp:yawAt(s0)
					local side = rail.side
					local x, y, z = sp:surfaceXYZ(s0, side * (half - 4))
					local runner = Sim.newRunner(CFrame.new(x, y + D.RideHeight, z) * CFrame.Angles(0, y0 + side * math.rad(20), 0))
					runner.state.velocity = dir(y0 - side * math.rad(6)) * 70
					runner.state.time = 10
					local steer = math.clamp(-side * k, -1, 1) -- as digest's rail drives
					local first, last, since = nil, nil, nil
					local n = 0
					local stepTouch = {}
					for _ = 1, 150 do
						Sim.advance(runner, 1 / FPS, { steer = steer, handbrake = false }, w, function(st)
							n += 1
							steps += 1
							if st.wallHit then
								hitSteps += 1
								kinds[st.wallKind] = (kinds[st.wallKind] or 0) + 1
								points[st.wallPoint] = (points[st.wallPoint] or 0) + 1
								first = first or n
								last = n
								if since then
									table.insert(gaps, n - since)
								end
								since = n
								intoMax = math.max(intoMax, st.wallInto)
							end
							stepTouch[n] = st.wallTouch
							if st.wallTouch then
								alongMax = math.max(alongMax, st.wallAlong)
							end
						end)
					end
					if first then
						span += last - first + 1
						for i = first, last do
							if stepTouch[i] then
								touchSteps += 1
							end
						end
					end
					table.insert(rows, `rail {ri} k {k}: {first and (last - first + 1) or 0} steps from first to last contact`)
				end
			end
			table.sort(gaps)
			local gapMax = gaps[#gaps] or 0
			local gap95 = gaps[math.max(1, math.floor(#gaps * 0.95))] or 0
			local kindRows, pointRows = {}, {}
			for k, n in kinds do
				table.insert(kindRows, `{k} {n}`)
			end
			for k, n in points do
				table.insert(pointRows, `{if k == "" then "?" else k} {n}`)
			end
			check(
				"the tail swung into a K-rail: the model says a K-rail, and which end of the car met it",
				(kinds.krail or 0) > 0 and (points.rear or 0) > 0 and alongMax > 0,
				`{hitSteps} contact steps of {steps}; kinds: {table.concat(kindRows, ", ")}; parts: {table.concat(pointRows, ", ")}; most into {fmt(intoMax, 1)} studs/s, most along {fmt(alongMax, 1)}`
			)
			-- A HELD CONTACT is one whose gaps are shorter than the grind's own grace: longer, the
			-- car has come off the rail and come back. Of those gaps, how many the model's grace
			-- bridges, so the contact reads as unbroken
			local held, bridged = 0, 0
			for _, g in gaps do
				if g * D.FixedStep <= B.Grace then
					held += 1
					if (g - 1) * D.FixedStep <= D.WallContactGrace then
						bridged += 1
					end
				end
			end
			local function pct(p)
				return gaps[math.max(1, math.ceil(#gaps * p))] or 0
			end
			check(
				`the grace ({D.WallContactGrace} s) reads a held contact as continuous`,
				held > 0 and bridged / held >= 0.95,
				`{#gaps} gaps between contact steps, in steps of 1/120 s: half within {pct(0.5)}, 90% within {pct(0.9)}, 95% within {pct(0.95)}, 99% within {pct(0.99)}, the longest {gapMax}; of the {held} under the grind's grace ({B.Grace} s), {bridged} ({fmt(100 * bridged / math.max(held, 1), 1)}%) bridged; between each drive's first and last contact {fmt(100 * touchSteps / math.max(span, 1), 1)}% of steps read as touching (the rest is the car off the rail)`
			)
		end

		------------------------------------------------------------ the motion is the same
		if want("same") then
			-- the world's extra returns stripped: the model sees only what it saw before
			local function strip(w)
				return {
					probe = w.probe,
					sweep = function(a, b, c)
						local safe, n = w.sweep(a, b, c)
						return safe, n
					end,
					penetration = function(a, b)
						local dirn, depth = w.penetration(a, b)
						return dirn, depth
					end,
					edge = w.edge,
				}
			end
			local full = Tests.digest()
			local bare = Tests.digest(strip)
			check(
				"the car moves the same to the bit whether or not the world says what it met",
				full.hash == bare.hash and full.steps == bare.steps and full.steps > 10000,
				`{full.steps} steps over {#full.scenarios} recorded drives ({full.rails} K-rails, {full.drops} drops): hash {full.hash} with, {bare.hash} without`
			)
		end

		------------------------------------------------------------ the real model: a bumper grind
		if want("realBumper") then
			local rails = railsOf(sp, 4)
			local rows, found, banked = {}, 0, 0
			for ri, rail in rails do
				for _, k in { 0, 0.15, 0.3 } do
					local w = SplineWorld.new(sp, nil)
					local s0 = rail.a + 15
					local y0 = sp:yawAt(s0)
					local side = rail.side
					local x, y, z = sp:surfaceXYZ(s0, side * (half - 4))
					local runner = Sim.newRunner(CFrame.new(x, y + D.RideHeight, z) * CFrame.Angles(0, y0 + side * math.rad(20), 0))
					runner.state.velocity = dir(y0 - side * math.rad(6)) * 70
					runner.state.time = 10
					local steer = math.clamp(-side * k, -1, 1) -- as digest's rail drives
					local rec = recorder()
					local g = BumperGrind.new(rec.sink, nil)
					local t = 0
					for _ = 1, 180 do
						Sim.advance(runner, 1 / FPS, { steer = steer, handbrake = false }, w)
						t += 1 / FPS
						rec.clock = t
						g:Update(1 / FPS, runner.state)
					end
					local e = rec.events[1]
					if e then
						found += 1
						banked += if e.result == true then 1 else 0
					end
					table.insert(rows, `rail {ri} k {k}: {#rec.events} grind(s){if e then string.format(" from %.2f s, %.2f s long, %s, mean size %.2f", e.at, e.seconds, if e.result == true then "banked" elseif e.result == false then "void (" .. g:DebugState().lastEnd .. ")" else "live", e.sizeTime / math.max(e.seconds, 1e-6)) else ""}`)
				end
			end
			check("the real car's tail swung into K-rails grinds", found > 0 and banked > 0, table.concat(rows, "; "))
		end

		------------------------------------------------------------ the real model: a hang grind
		if want("realHang") then
			-- ScrapeTests' ledge: the car rolled backwards off a ledge, its floor landing on the
			-- edge, then slid along the edge, then pulled back on (or let go over it)
			local COAST = { MaxAcceleration = 0, ConstantFriction = 0, SlipFriction = 0, SlipSqFriction = 0 }
			local function ledge(pullBack: boolean)
				local world = {
					probe = function(pos)
						local y = if pos.Z <= 0 then 0 else -8
						return { y = y, normal = Vector3.yAxis, grip = D.GripTarmac, score = D.ScoreTarmac }
					end,
				}
				local rec = recorder()
				local g = HangGrind.new(rec.sink, nil)
				local s = Model.new(CFrame.new(0, D.RideHeight, -9))
				local hangSteps, rearSteps = 0, 0
				local t = 0
				Cars.withTuning(COAST, function()
					local steps = 0
					local phase = "back"
					for _ = 1, math.floor(6 / D.FixedStep) do
						steps += 1
						if phase == "back" and s.hanging and HangGrind.axle(s) == "rear" then
							phase = "slide"
						end
						if phase == "slide" and steps * D.FixedStep > 3.5 then
							phase = if pullBack then "pull" else "over"
						end
						local v = if phase == "back" then Vector3.new(0, s.velocity.Y, 3)
							elseif phase == "slide" then Vector3.new(12, s.velocity.Y, 0)
							elseif phase == "pull" then Vector3.new(0, s.velocity.Y, -6)
							else Vector3.new(0, s.velocity.Y, 6)
						s.velocity = v
						Model.step(s, { steer = 0 }, D.FixedStep, world)
						if s.hanging then
							hangSteps += 1
							if HangGrind.axle(s) == "rear" then
								rearSteps += 1
							end
						end
						if steps % 2 == 0 then
							t += 2 * D.FixedStep
							rec.clock = t
							g:Update(2 * D.FixedStep, s)
						end
					end
				end)
				return rec, g, hangSteps, rearSteps, s
			end
			local r1, g1, h1, rear1, s1 = ledge(true)
			local r2, g2, h2, rear2, s2 = ledge(false)
			local e1, e2 = r1.events[1], r2.events[1]
			check(
				"the real car's rear hung off a ledge grinds; banked when pulled back on, void when it goes over",
				e1 ~= nil and e1.result == true and e2 ~= nil and e2.result == false,
				`pulled back: {h1} hanging steps ({rear1} rear), {#r1.events} event(s), {e1 and string.format("%.2f s, %s, size %.2f..%.2f", e1.seconds, tostring(e1.result), e1.minSize, e1.maxSize) or "none"}, ended {g1:DebugState().lastEnd}, the car at y {fmt(s1.position.Y)}; let go: {h2} hanging steps ({rear2} rear), {#r2.events} event(s), {e2 and string.format("%.2f s, %s", e2.seconds, tostring(e2.result)) or "none"}, ended {g2:DebugState().lastEnd}, the car at y {fmt(s2.position.Y)}`
			)
		end
	end)
	if not ok then
		check("the suite ran", false, tostring(err))
	end
	local passed = 0
	for _, c in checks do
		if c.ok then
			passed += 1
		end
	end
	return { passed = passed, total = #checks, checks = checks }
end

return Tests
