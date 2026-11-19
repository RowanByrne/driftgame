--!nonstrict
-- TightTurnTests: how tight a turnaround the car can get round (features/tight-hairpins.md,
-- T-329 step 1, T-330). A MEASUREMENT, not a guard: the radius tight hairpins are laid at is
-- set from what this prints.
--
--   require(game.ServerScriptService.Tests.TightTurnTests).run()          -- pure: Edit works
--   ...run({ cars = { "restyled", "gripper", "slider", "bruiser" } })     -- every car
--   ...run({ radii = { 40 }, speeds = { 90 } })                           -- one case
--
-- THE PAD: a hand-made bare road (`Road/Spline`, no mountain), 50 studs wide and walled at its
-- edges, as the tests' yardstick road is: 400 studs straight, a 180-degree turnaround of
-- centre-line radius R (eased in and out over `EASE` studs), then 400 straight back beside the
-- way in. Flat, and again falling at `DESCENT` through the whole thing, as a tight hairpin on a
-- steep face would.
--
-- THE DRIVER: the real drift model (`Drift/Sim` on `Drift/SplineWorld`, the code path the live
-- car runs) driven by HairpinTests' slip-holding autopilot. There is no brake and no throttle in
-- this game: the only way to shed speed is to put the car sideways (past about 70 degrees of
-- slip the grip is nearly all brake). So each drive tries one way of taking the corner:
--
--   scrub      before the turn, swing the tail out to this slip (0: no scrub) from `scrubAt`
--              studs before the turn until the car is down to `vIn`
--   bend       in the turn, hold the slip the line needs, clamped to [0, maxB]: 15 is a grip
--              line, 85 a full drift
--
-- A drive GETS ROUND when it reaches 80 studs down the exit leg without touching a wall, never
-- spins (past 135 degrees of slip) or stops (under 3 studs/s), and is driving straight down the
-- leg there (under 30 degrees of slip). Each case reports how many of the ways got round, the
-- quickest, and the speeds and slip it took.
--
-- `run()` returns `{ passed, checks, log, rows }`: one row per car, radius, entry speed and
-- grade. `passed` only says the measurement ran.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "TightTurnTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local Cars = require(ReplicatedStorage.Shared.Cars)
local Spline = require(ReplicatedStorage.Shared.Road.Spline)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Sim = require(DriftFolder.Sim)
local SplineWorld = require(DriftFolder.SplineWorld)

local TightTurnTests = {}

local RADII = { 35, 40, 45, 50, 55, 60, 70 }
local SPEEDS = { 60, 90, 120 } -- studs/s down the leg into the turn
local GRADES = { 0, -0.12 } -- flat, and falling 12 percent through the turn
local EASE = 12 -- studs of clothoid either side of the arc
local LEG = 400 -- studs of straight either side
local TURN = 180 -- degrees

-- the ways to take it
local SCRUB_SLIP = { 0, 70, 95 } -- degrees
local SCRUB_AT = { 60, 130, 220 } -- studs before the turn
local V_IN_G = { 20, 35, 55 } -- vIn = sqrt(g * R): the lateral pull, studs/s^2, the entry is aimed at
local MAX_B = { 15, 45, 85 } -- degrees

local DONE_PAST = 80 -- studs down the exit leg
local SPIN_DEG = 135
local STOP_SPEED = 3
local SETTLED_DEG = 30

local function fmt(x: number, p: number?): string
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

-- The pad: a straight, the turnaround, a straight back. Returns the spline and the arc's
-- (s) entry and exit, where the curvature starts to rise and finishes falling.
local function pad(R: number, grade: number, dir: number)
	local sp = Spline.new({ x = 0, y = 2000, z = 0, yaw = 0 })
	local k = dir / R
	local arc = math.rad(TURN) * R - EASE -- two clothoids turn EASE * k between them
	local function sec(len: number, kEnd: number)
		sp:append({ len = len, k = { len, kEnd }, g = { len, grade }, b = { len, 0 } })
	end
	sp:append({ len = LEG, k = { LEG, 0 }, g = { 40, grade, LEG, grade }, b = { LEG, 0 } })
	local entry = sp.length
	sec(EASE, k)
	sec(arc, k)
	sec(EASE, 0)
	local exit = sp.length
	sec(LEG, 0)
	return sp, entry, exit
end

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

-- One drive round the pad, one way. Returns what happened.
local function drive(sp, entry: number, exit: number, dir: number, v0: number, way, R: number)
	local D = Config.Drift
	local world = SplineWorld.new(sp, nil)
	local startS = entry - 300
	local cf = sp:frame(startS, D.RideHeight)
	local pos = sp:surface(startS, 0) + Vector3.new(0, D.RideHeight, 0)
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
	local runner = Sim.newRunner(CFrame.lookAt(pos, pos + flat))
	runner.state.velocity = flat * v0
	runner.state.time = 10 -- full throttle, as on a run
	local input = { steer = 0, handbrake = false }
	local vIn = math.sqrt(way.g * R)
	local lastS = startS
	local r = {
		ok = false,
		why = "timeout",
		walls = 0,
		minSpeed = math.huge,
		apexSpeed = nil,
		entrySpeed = nil,
		maxSlip = 0,
		maxD = 0,
		t = nil,
	}
	local scrubbing, scrubbed = false, false
	local tStart = nil
	local dt = 1 / 60
	for _ = 1, 60 * 30 do
		local s = runner.state
		local speed = math.sqrt(s.velocity.X ^ 2 + s.velocity.Z ^ 2)
		local heading = if speed > 1
			then Vector3.new(s.velocity.X / speed, 0, s.velocity.Z / speed)
			else Vector3.new(-math.sin(s.yaw), 0, -math.cos(s.yaw))
		local cs, cd = Hairpins.locate(sp, s.position, lastS)
		cs = cs or lastS
		lastS = cs
		local look = math.clamp(speed * 0.7, 15, 80)
		local tp = sp:surface(math.min(cs + look, sp.length), 0)
		local dx, dz = tp.X - s.position.X, tp.Z - s.position.Z
		local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
		local kappa = 2 * math.sin(signedAngle(heading.X, heading.Z, dx / len, dz / len)) / len
		local bmag = slipFor(speed * speed * math.abs(kappa))
		local bStar = -math.sign(kappa) * math.min(bmag, math.rad(15))
		-- the scrub: tail out, into the turn, until the car is slow enough
		if way.scrub > 0 and not scrubbed and cs >= entry - way.scrubAt and cs < entry + 20 then
			if speed > vIn then
				scrubbing = true
				bStar = -dir * math.rad(way.scrub)
			elseif scrubbing then
				scrubbing, scrubbed = false, true
			end
		end
		if not scrubbing and cs >= entry - 10 and cs <= exit then
			bStar = -dir * math.clamp(bmag, 0, math.rad(way.maxB))
		end
		local rate = speed * kappa + 8 * (s.slip - bStar)
		input.steer = math.clamp(rate / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
		Sim.advance(runner, dt, input, world)
		s = runner.state
		speed = math.sqrt(s.velocity.X ^ 2 + s.velocity.Z ^ 2)
		local slipDeg = math.abs(math.deg(s.slip))

		if cs >= entry - 250 then
			tStart = tStart or s.time
			if s.wallHit then
				r.walls += 1
			end
			r.maxSlip = math.max(r.maxSlip, slipDeg)
			r.maxD = math.max(r.maxD, math.abs(cd or 0))
		end
		if cs >= entry then
			r.entrySpeed = r.entrySpeed or speed
			r.minSpeed = math.min(r.minSpeed, speed)
		end
		if not r.apexSpeed and cs >= (entry + exit) * 0.5 then
			r.apexSpeed = speed
		end
		if slipDeg > SPIN_DEG then
			r.why = "spun"
			return r
		end
		if cs >= entry and speed < STOP_SPEED then
			r.why = "stopped"
			return r
		end
		if r.walls > 0 then
			r.why = "wall"
			return r
		end
		if cs >= exit + DONE_PAST then
			if slipDeg > SETTLED_DEG then
				r.why = `still {fmt(slipDeg, 0)} deg sideways`
				return r
			end
			r.ok = true
			r.why = "round"
			r.t = s.time - (tStart or s.time)
			r.exitSpeed = speed
			return r
		end
	end
	return r
end

local function ways()
	local list = {}
	for _, scrub in SCRUB_SLIP do
		for _, at in (if scrub > 0 then SCRUB_AT else { 0 }) do
			for _, g in (if scrub > 0 then V_IN_G else { 0 }) do
				for _, maxB in MAX_B do
					table.insert(list, { scrub = scrub, scrubAt = at, g = g, maxB = maxB })
				end
			end
		end
	end
	return list
end

local function wayName(w): string
	local bend = if w.maxB <= 15 then "grip" else `slip<={w.maxB}`
	if w.scrub == 0 then
		return `no scrub, {bend}`
	end
	return `scrub {w.scrub}deg from {w.scrubAt} to sqrt({w.g}R), {bend}`
end

local function measure(opts, log, rows)
	local radii = opts.radii or RADII
	local speeds = opts.speeds or SPEEDS
	local grades = opts.grades or GRADES
	local allWays = ways()
	for _, carKey in opts.cars or { Cars.Default } do
		Cars.withActive(carKey, function()
			table.insert(log, `--- car {carKey}: MaxSteeringSpeed {Config.Drift.MaxSteeringSpeed}, grip {Config.Drift.ConstantFriction}/{Config.Drift.SlipFriction}/{Config.Drift.SlipSqFriction} max {Config.Drift.MaxFriction}, TopSpeed {Config.Drift.TopSpeed}`)
			for _, grade in grades do
				for _, R in radii do
					local sp, entry, exit = pad(R, grade, 1)
					for _, v0 in speeds do
						local okCount, best, gripOk = 0, nil, false
						local fails = {}
						for _, w in allWays do
							local res = drive(sp, entry, exit, 1, v0, w, R)
							if res.ok then
								okCount += 1
								if w.scrub == 0 and w.maxB <= 15 then
									gripOk = true
								end
								if not best or res.t < best.res.t then
									best = { res = res, way = w }
								end
							else
								fails[res.why] = (fails[res.why] or 0) + 1
							end
						end
						local failText = {}
						for why, n in fails do
							table.insert(failText, `{n} {why}`)
						end
						table.sort(failText)
						local row = {
							car = carKey,
							grade = grade,
							R = R,
							v0 = v0,
							ok = okCount,
							of = #allWays,
							grip = gripOk,
						}
						local line = `{carKey} grade {grade} R{R} in at {v0}: {okCount}/{#allWays} ways round`
						if best then
							local b = best.res
							row.best = wayName(best.way)
							row.t = b.t
							row.minSpeed = b.minSpeed
							row.apexSpeed = b.apexSpeed
							row.exitSpeed = b.exitSpeed
							row.maxSlip = b.maxSlip
							row.maxD = b.maxD
							line ..= `; quickest {fmt(b.t, 2)} s ({wayName(best.way)}): slowest {fmt(b.minSpeed, 0)}, apex {fmt(b.apexSpeed or 0, 0)}, out {fmt(b.exitSpeed or 0, 0)} studs/s, slip up to {fmt(b.maxSlip, 0)} deg, {fmt(b.maxD, 1)} off centre`
						end
						line ..= `; grip line {if gripOk then "gets round" else "does not"}; failed: {table.concat(failText, ", ")}`
						table.insert(rows, row)
						table.insert(log, line)
						task.wait()
					end
				end
			end
		end)
	end
end

function TightTurnTests.run(opts)
	opts = opts or {}
	local checks, log, rows = {}, {}, {}
	local t0 = os.clock()
	local ok, err = pcall(measure, opts, log, rows)
	table.insert(checks, { name = "the measurement ran", ok = ok, detail = if ok then `{#rows} cases in {fmt(os.clock() - t0, 0)} s` else tostring(err) })
	return { passed = ok, checks = checks, log = table.concat(log, "\n"), rows = rows }
end

TightTurnTests.pad = pad
TightTurnTests.drive = drive

return TightTurnTests
