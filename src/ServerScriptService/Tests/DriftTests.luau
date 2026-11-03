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
local CORNER = {
	{ t = 0, steer = 0 },
	{ t = 3.0, steer = 1, drift = true },
	{ t = 4.43, steer = 0, drift = false },
}
local CORNER_SECONDS = 7

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
