--!nonstrict
-- DriftTests: the drift model's automated checks
-- (docs/game/features/drift-model.md "Testing", docs/workflow/TESTING.md).
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugDriftTests", "run")
--
-- Everything here is pure: the model is maths plus two injected world queries, so these
-- run with no player, no car and no playtest. The one check that needs the Workspace
-- (`no physics`) builds its own car and also looks at any live ones.
--
-- The model lives in StarterPlayerScripts because the client that drives a car owns its
-- simulation. The server can still require it -- it is a ModuleScript in a container the
-- server can see -- and that is deliberate: one code path, tested where the test kit is.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "DriftTests only runs in Studio")

local CarModel = require(ReplicatedStorage.Shared.CarModel)
local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Sim = require(DriftFolder.Sim)
local World = require(DriftFolder.World)

local DriftTests = {}

-- The scripted 90 degree corner the spec measures: stand still, run up, one input through
-- the corner, catch the exit. Changing this changes what the numbers below mean, so it
-- lives here as one named thing rather than inline in three checks.
--
-- It is 70% of a finger, not a full one, since the rebuild (features/drift-model.md "How
-- it plays"): the offset now says how hard the car is sliding, and a full one held for a
-- second and a half is not a corner, it is the brake. The old full-lock version of this
-- line now turns the car 132 degrees and leaves it at 29% of its entry speed -- a useful
-- number, and not a 90 degree corner.
local CORNER = {
	{ t = 0, steer = 0 },
	{ t = 3.0, steer = 0.7 },
	{ t = 4.6, steer = 0 },
}
local CORNER_SECONDS = 7

-- Run up to top speed on flat ground, then hold one offset: the shape of the whole
-- control, in one function. Returns what the hold cost.
local function holdOffset(offset: number, holdFor: number)
	local C = Config.Drift
	local runner = Sim.newRunner(CFrame.new(0, C.RideHeight, 0))
	local world = World.flat(0)
	local runUp = 4
	local entry, peak, samples = nil, 0, {}
	local function observe(s)
		if s.time < runUp then
			return
		end
		if not entry then
			entry = Model.speed(s)
		end
		peak = math.max(peak, math.abs(math.deg(s.slip)))
		table.insert(samples, { t = s.time - runUp, slip = math.deg(s.slip), speed = Model.speed(s), r = s.r })
	end
	local function inputAt(t: number)
		return { steer = t < runUp and 0 or offset, drift = false, brake = false }
	end
	local total, elapsed = runUp + holdFor, 0
	while elapsed < total - 1e-9 do
		local dt = math.min(1 / 60, total - elapsed)
		Sim.advance(runner, dt, inputAt, world, observe)
		elapsed += dt
	end
	-- Settled: the mean of the last second, so one wobble is not the answer.
	local n, slipSum, speedSum, yawSum = 0, 0, 0, 0
	for _, s in samples do
		if s.t >= holdFor - 1 then
			n += 1
			slipSum += s.slip
			speedSum += s.speed
			yawSum += math.abs(s.r)
		end
	end
	n = math.max(n, 1)
	local settledSlip, settledSpeed, settledYaw = slipSum / n, speedSum / n, yawSum / n
	local reached, stopped = -1, -1
	for _, s in samples do
		if reached < 0 and math.abs(s.slip) >= 0.9 * math.abs(settledSlip) then
			reached = s.t
		end
		if stopped < 0 and s.speed <= 0.1 * C.TopSpeed then
			stopped = s.t
		end
	end
	return {
		entry = entry or 0,
		peakSlip = peak,
		slip = settledSlip,
		speed = settledSpeed,
		share = settledSpeed / math.max(entry or 1, 1),
		reached = reached,
		stopped = stopped,
		radius = settledYaw > 0.01 and settledSpeed / settledYaw or math.huge,
		state = runner.state,
	}
end

local function check(checks, name, ok, detail)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
	return ok == true
end

-- Every physics object a car must not have, wherever it came from.
local function offenderReport(model: Instance): (boolean, string)
	local offenders = CarModel.physicsOffenders(model)
	if #offenders == 0 then
		local parts = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		return true, `{model.Name}: {parts} parts, all anchored, nothing that moves them`
	end
	return false, `{model.Name}: {table.concat(offenders, "; ")}`
end

function DriftTests.run()
	local checks = {}
	local C = Config.Drift

	------------------------------------------------------------------ determinism
	local pathA, cornerA = Sim.drive(CORNER, CORNER_SECONDS, { fps = 60 })
	local pathB = Sim.drive(CORNER, CORNER_SECONDS, { fps = 60 })
	local worst = 0
	for i = 1, math.min(#pathA, #pathB) do
		worst = math.max(worst, (pathA[i] - pathB[i]).Magnitude)
	end
	check(
		checks,
		"a repeatable line",
		#pathA == #pathB and worst < 1,
		`{#pathA} points, worst deviation {string.format("%.6f", worst)} studs (same inputs, same start)`
	)

	------------------------------------------------------------------ frame independence
	local ends, spread = {}, 0
	for _, fps in { 30, 60, 120 } do
		local _, summary = Sim.drive(CORNER, CORNER_SECONDS, { fps = fps })
		ends[fps] = summary.endPosition
	end
	for _, a in ends do
		for _, b in ends do
			spread = math.max(spread, (a - b).Magnitude)
		end
	end
	check(
		checks,
		"the same line at 30, 60 and 120 FPS",
		spread < 2,
		`worst gap between the three end points {string.format("%.3f", spread)} studs`
	)

	------------------------------------------------------------------ the corner
	-- Not a feel judgement: that is the user's (features/drift-model.md "Testing"). These
	-- only catch a model that has stopped working -- a corner that never breaks loose, one
	-- that spins, or one that arrives at the exit stopped.
	local turned = math.abs(cornerA.headingChangeDeg)
	check(
		checks,
		"a 90 degree corner, taken sideways",
		turned > 60 and turned < 170 and cornerA.peakSlipDeg > C.BreakLooseSlip and cornerA.peakSlipDeg < C.SlipAngleMax,
		string.format(
			"entry %.1f studs/s, peak slip %.1f deg, exit %.1f studs/s, loose %.3f s after the input, turned %.1f deg",
			cornerA.entrySpeed or -1,
			cornerA.peakSlipDeg,
			cornerA.exitSpeed or -1,
			cornerA.breakLooseSeconds or -1,
			cornerA.headingChangeDeg
		)
	)
	check(
		checks,
		"the exit carries speed",
		(cornerA.exitSpeed or 0) > C.TopSpeed * 0.4,
		string.format(
			"exit %.1f studs/s, %.0f%% of the %.0f it went in at",
			cornerA.exitSpeed or -1,
			100 * (cornerA.exitSpeed or 0) / math.max(cornerA.entrySpeed or 1, 1),
			cornerA.entrySpeed or -1
		)
	)

	------------------------------------------------------------------ the finger is on the rear
	-- The first thing the player feels, and the easiest to get backwards
	-- (features/drift-model.md "How it plays", item 3). A finger to the RIGHT throws the
	-- tail right, which points the nose left and arcs the car left. Measured three ways,
	-- because a sign error can hide in any one of them: the slip angle, the heading, and
	-- where the car actually ended up.
	local invRunner = Sim.newRunner(CFrame.new(0, C.RideHeight, 0))
	local invWorld = World.flat(0)
	local startYaw, startPos = nil, nil
	local invInput = function(t)
		return { steer = t < 3 and 0 or 0.4, drift = false, brake = false }
	end
	local invElapsed = 0
	while invElapsed < 4.5 - 1e-9 do
		local dt = math.min(1 / 60, 4.5 - invElapsed)
		Sim.advance(invRunner, dt, invInput, invWorld, function(s)
			if s.time >= 3 and not startYaw then
				startYaw, startPos = s.yaw, s.position
			end
		end)
		invElapsed += dt
	end
	local invState = invRunner.state
	local invFwd, invRight = Model.axes(startYaw or 0)
	local moved = invState.position - (startPos or Vector3.zero)
	local sideways = moved:Dot(invRight)
	local turned = math.deg(invState.yaw - (startYaw or 0)) -- Roblox yaw: + is to the left
	check(
		checks,
		"the finger is on the car's rear, not its nose",
		math.deg(invState.slip) > 5 and turned > 5 and sideways < -5,
		string.format(
			"finger +0.4 (tail to the right) for 1.5 s: slip %+.1f deg (tail out to the right), heading %+.1f deg (left), ended %+.1f studs ahead and %+.1f to its right",
			math.deg(invState.slip),
			turned,
			moved:Dot(invFwd),
			sideways
		)
	)

	------------------------------------------------------------------ the offset ladder
	-- What the offset buys and what it costs, which is the whole control
	-- (features/drift-model.md "How it plays", items 3 and 5). Each notch of finger has to
	-- buy more slide than the last and cost more speed than the last, or the player has a
	-- switch rather than a dial. The numbers themselves are the user's to judge; this only
	-- catches a ladder that has stopped being one.
	local rungs = {}
	for _, offset in { 0.25, 0.5, 0.75, 1.0 } do
		table.insert(rungs, { offset = offset, r = holdOffset(offset, 8) })
	end
	local climbs, costs = true, true
	local parts = {}
	for i, rung in rungs do
		if i > 1 then
			climbs = climbs and math.abs(rung.r.slip) > math.abs(rungs[i - 1].r.slip) - 2
			costs = costs and rung.r.speed < rungs[i - 1].r.speed
		end
		table.insert(
			parts,
			string.format(
				"%.0f%%: %.0f deg (leans %.0f), %.0f studs/s = %.0f%%, circle %.0f",
				rung.offset * 100,
				math.abs(rung.r.slip),
				rung.r.peakSlip,
				rung.r.speed,
				100 * rung.r.share,
				math.min(rung.r.radius, 999)
			)
		)
	end
	check(checks, "every notch of finger buys more slide and costs more speed", climbs and costs, table.concat(parts, " | "))

	-- And the cost has to be worth feeling. A quarter of a finger should be nearly free
	-- and three quarters should hurt: that gap is the trade the game is made of.
	local shallow, deep = rungs[1].r, rungs[3].r
	check(
		checks,
		"a shallow drift is nearly free and a big one is ruinous",
		shallow.share > 0.8 and deep.share < 0.55,
		string.format(
			"a quarter offset keeps %.0f%% of entry speed at %.0f deg; three quarters keeps %.0f%% at %.0f deg",
			100 * shallow.share,
			math.abs(shallow.slip),
			100 * deep.share,
			math.abs(deep.slip)
		)
	)

	------------------------------------------------------------------ full lock is the brake
	-- The user's hard requirement: "putting it 100% to the side being an action that will
	-- effectively kill our momentum fully if held there" (DECISIONS.md, 2026-11-03). It
	-- falls out of the scrub and the throttle cut; nothing here is a brake force.
	local lock = rungs[4].r
	check(
		checks,
		"full offset held kills the car's momentum",
		lock.stopped > 0 and lock.stopped < 3 and lock.share < 0.12,
		string.format(
			"from %.1f studs/s: under a tenth of top speed in %.2f s, settling at %.1f studs/s (%.0f%% of entry) with the car leaning %.0f deg across",
			lock.entry,
			lock.stopped,
			lock.speed,
			100 * lock.share,
			lock.peakSlip
		)
	)

	-- It must not be able to drive its way back out while the finger is still there.
	check(
		checks,
		"and it stays stopped while the finger is held",
		lock.state ~= nil and Model.speed(lock.state) <= 0.12 * C.TopSpeed,
		string.format(
			"still %.1f studs/s after 8 s of full offset held (top speed %.0f)",
			Model.speed(lock.state),
			C.TopSpeed
		)
	)

	------------------------------------------------------------------ nothing runs away
	-- The whole model rests on being able to trust the numbers it produces. A model that
	-- can reach twice its top speed, or spin at ten radians a second, is broken whatever
	-- it looks like on screen -- and that is how it was broken when this task picked it up.
	local held = {
		{ t = 0, steer = 1, drift = true },
		{ t = 2, steer = -1, drift = true },
		{ t = 4, steer = 1, drift = false, brake = true },
		{ t = 6, steer = -1, drift = true },
	}
	local _, abused = Sim.drive(held, 12, { fps = 60 })
	check(
		checks,
		"no runaway under abuse",
		abused.maxSpeed <= C.TopSpeed * C.SpeedCeiling + 1 and abused.peakYawRate <= C.YawRateMax + 0.01,
		string.format(
			"12 s of lock-to-lock with the drift held: top speed %.1f (ceiling %.1f), top yaw %.2f rad/s (ceiling %.2f)",
			abused.maxSpeed,
			C.TopSpeed * C.SpeedCeiling,
			abused.peakYawRate,
			C.YawRateMax
		)
	)

	------------------------------------------------------------------ no physics
	-- The rule the whole model rests on, and the one most easily broken later
	-- (docs/game/DECISIONS.md, 2026-11-03).
	local built = CarModel.build()
	local builtOk, builtDetail = offenderReport(built)
	built:Destroy()
	check(checks, "a fresh car model holds no physics object", builtOk, builtDetail)

	local live, liveDetails, liveCount = true, {}, 0
	local cars = workspace:FindFirstChild("Cars")
	if cars then
		for _, car in cars:GetChildren() do
			if car:IsA("Model") then
				liveCount += 1
				local ok, detail = offenderReport(car)
				live = live and ok
				table.insert(liveDetails, detail)
			end
		end
	end
	check(
		checks,
		"every live car holds no physics object",
		live,
		if liveCount == 0
			then "no cars spawned yet (nothing to check: start a playtest to cover this)"
			else table.concat(liveDetails, " | ")
	)

	------------------------------------------------------------------ the ground
	-- The model must drive on a bare plate, with nothing tagged, as well as on the
	-- playground (docs/game/CONTRACTS.md, tag `DriftSurface`).
	local _, flat = Sim.drive({ { t = 0, steer = 0 } }, 4, { fps = 60, world = World.flat(0) })
	check(
		checks,
		"a bare plate is drivable",
		flat.airborneSeconds == 0 and flat.endSpeed > 0,
		string.format(
			"4 s on a flat plane with nothing tagged: %.1f studs/s, %.2f s airborne, %d surfaces tagged in this place",
			flat.endSpeed,
			flat.airborneSeconds,
			#CollectionService:GetTagged(C.SurfaceTag)
		)
	)

	------------------------------------------------------------------ the server owns respawns
	-- What the server owning respawns buys, checked where it lives: the movement check
	-- (docs/game/CONTRACTS.md, `CarState` and `CarRespawn`). A respawn is a position the
	-- server chose, so the first packet after it follows from something the server knows;
	-- a jump the server did not choose is rejected, and stays rejected however often it is
	-- repeated, because a rejected packet never becomes what the next one is measured
	-- against. There is no run-of-drops amnesty left to wear down.
	local CarService = require(ServerScriptService.Services.CarService)
	local spawnAt = Vector3.new(0, C.RideHeight, 0)
	local period = 1 / C.StateSendRate
	local clock = 0

	-- A car at top speed, one send period at a time: honest across the ground.
	local track = CarService.track(spawnAt, clock)
	clock += period
	local driving = spawnAt + Vector3.new(C.TopSpeed * period, 0, 0)
	local drivingOk = CarService.fits(track, driving, clock)

	-- Off the edge: honest down the vertical axis too, at the fastest a fall may get.
	track = CarService.track(driving, clock)
	clock += period
	local falling = driving + Vector3.new(C.TopSpeed * period, -C.TerminalFall * period, 0)
	local fallingOk = CarService.fits(track, falling, clock)
	local fallenTrack = CarService.track(falling, clock)

	-- The server puts it back and records where: the next packet checks against that.
	local respawned = CarService.track(spawnAt, clock)
	local afterOk = CarService.fits(respawned, spawnAt + Vector3.new(C.TopSpeed * period, 0, 0), clock + period)
	-- And a packet sent before the respawn, landing after it, still has the old track
	-- (`RespawnGrace`), which is why a respawn costs no dropped packets at all.
	local inFlightOk =
		CarService.fits(fallenTrack, falling + Vector3.new(0, -C.TerminalFall * period, 0), clock + period)
	check(
		checks,
		"a respawn the server decided is not a teleport",
		drivingOk and fallingOk and afterOk and inFlightOk,
		string.format(
			"driving %s, falling at %.0f studs/s %s, the packet after the respawn %s, one in flight over it %s",
			drivingOk and "fits" or "FAILS",
			C.TerminalFall,
			fallingOk and "fits" or "FAILS",
			afterOk and "fits" or "FAILS",
			inFlightOk and "fits" or "FAILS"
		)
	)

	-- A jump nobody asked for. The track it is measured against never moves, so repeating
	-- it does not wear the server down -- the thing `StateResyncDrops` used to do.
	local jumped = spawnAt + Vector3.new(500, 0, 500)
	local cheat = CarService.track(spawnAt, clock)
	local rejected = 0
	local tries = 20
	for i = 1, tries do
		if not CarService.fits(cheat, jumped, clock + i * period) then
			rejected += 1
		end
	end
	check(
		checks,
		"a jump the server did not decide stays rejected",
		rejected == tries and C.StateResyncDrops == nil,
		string.format(
			"%d of %d packets %.0f studs from where the server put the car rejected, over %.1f s; no StateResyncDrops in Config: %s",
			rejected,
			tries,
			(jumped - spawnAt).Magnitude,
			tries * period,
			tostring(C.StateResyncDrops == nil)
		)
	)

	------------------------------------------------------------------ no numbers in the logic
	-- Config is the only place a tuning number may live (docs/workflow/CODING.md). Move one
	-- and the model must move with it: if it does not, something has been hard-coded.
	local topSpeed = C.TopSpeed
	C.TopSpeed = topSpeed * 0.5
	local _, slow = Sim.drive({ { t = 0, steer = 0 } }, 8, { fps = 60 })
	C.TopSpeed = topSpeed
	local _, fast = Sim.drive({ { t = 0, steer = 0 } }, 8, { fps = 60 })
	check(
		checks,
		"the model reads its numbers from Config",
		slow.endSpeed < fast.endSpeed * 0.7,
		string.format("halving Config.Drift.TopSpeed took the car from %.1f to %.1f studs/s", fast.endSpeed, slow.endSpeed)
	)

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return DriftTests
