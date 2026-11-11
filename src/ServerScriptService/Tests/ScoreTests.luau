--!nonstrict
-- ScoreTests: the endless run's score and its multiplier ladder
-- (docs/game/features/endless-score.md "Testing", T-119).
--
-- Run it from the server debug bridge, or straight off the module -- it is pure:
--   game.ServerStorage.DebugBridge:Invoke("DebugScoreTests", "run")
--
-- Two halves. The LADDER is checked on stand-in car states, where every number is known and
-- the maths can be checked against itself. The SCORE ON THE CAR is checked by driving the
-- real model (`Drift/Sim`, a flat world) with the score stepped exactly as the live game
-- steps it -- once per simulation step -- so "a held drift climbs" is a claim about the car
-- the player drives, not about a table.
--
-- What it cannot check: whether the ladder FEELS right. Its rates are guesses
-- (`Config.Score`, FALLBACK), and that is the user's to judge by driving.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "ScoreTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Score = require(DriftFolder.Score)
local Sim = require(DriftFolder.Sim)
local World = require(DriftFolder.World)

local Tests = {}

local STEP = 1 / 120 -- the stand-ins step at the model's rate, so a second is 120 steps

-- A car sliding at `slipDeg` and `speed`, on the ground unless told otherwise.
local function car(slipDeg: number, speed: number, airborne: boolean?)
	local b = math.rad(slipDeg)
	return {
		slip = b,
		u = speed * math.cos(b),
		v = -speed * math.sin(b),
		surfaceScore = if airborne then 0 else Config.Drift.ScoreTarmac,
		grounded = not airborne,
	}
end

local function run(score, state, seconds: number)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		score:Step(STEP, state)
	end
end

-- The real model, a finger held from a rolling start, the score stepped on every step.
local HELD_STEER = 0.15 -- inside the usable bottom of the finger's travel (PROJECT.md)
local HELD_ENTRY = 100 -- studs/s
local HELD_SECONDS = 12
local function drive(steer: number, seconds: number, fps: number)
	local yaw = math.rad(15) -- off a world axis, as DriftTests does, for the same reason
	local runner = Sim.newRunner(CFrame.new(0, Config.Drift.RideHeight, 0) * CFrame.Angles(0, yaw, 0))
	runner.state.velocity = Model.axes(yaw) * HELD_ENTRY
	local score = Score.new()
	local world = World.flat(0)
	local frames = math.floor(seconds * fps + 0.5)
	for _ = 1, frames do
		Sim.advance(runner, 1 / fps, { steer = steer }, world, function(s)
			score:Step(Config.Drift.FixedStep, s)
		end)
	end
	return score, runner
end

function Tests.run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end
	local C = Config.Score

	-- 1. The points: exactly the formula, times the rung.
	do
		local s = Score.new()
		local state = car(30, 100)
		s:Step(STEP, state)
		local want = math.rad(30) * 100 * Config.Drift.ScoreTarmac * C.ScoreRate * STEP
		check(
			"one step of a 30 deg slide at 100 studs/s earns the formula's points at x1",
			math.abs(s:Get().score - want) < 1e-9,
			string.format("got %.6f, want %.6f", s:Get().score, want)
		)
	end

	-- 2. The ladder climbs under a steady drift.
	local climbed = Score.new()
	do
		local times = {}
		local t = 0
		for _ = 1, math.floor(60 / STEP) do
			local before = climbed:Get().multiplier
			climbed:Step(STEP, car(35, 150))
			t += STEP
			if climbed:Get().multiplier > before then
				table.insert(times, string.format("x%d at %.1fs", climbed:Get().multiplier, t))
			end
		end
		local r = climbed:Get()
		check(
			"a steady drift climbs the ladder",
			r.multiplier >= 3,
			`{table.concat(times, ", ")}; after 60 s x{r.multiplier}, score {math.floor(r.score)}`
		)
	end

	-- 3. Never past the top: a slide no car can do, held for a minute.
	do
		local s = Score.new()
		local over = false
		for _ = 1, math.floor(60 / STEP) do
			s:Step(STEP, car(80, 1000))
			local r = s:Get()
			over = over or r.multiplier > C.MaxMultiplier or r.progress > 1
		end
		local r = s:Get()
		check(
			`never past x{C.MaxMultiplier}, and the bar never past full`,
			not over and r.multiplier == C.MaxMultiplier,
			`ended x{r.multiplier}, bar {r.progress}`
		)
	end

	-- 4. A straight drains the ladder to x1, and takes no points away.
	do
		local s = Score.new()
		run(s, car(80, 1000), 30) -- to the top
		local top = s:Get()
		local under = false
		local drops = {}
		local t = 0
		for _ = 1, math.floor(60 / STEP) do
			local before = s:Get().multiplier
			s:Step(STEP, car(0, 150))
			t += STEP
			local r = s:Get()
			under = under or r.multiplier < 1 or (r.multiplier == 1 and r.progress < 0)
			if r.multiplier < before then
				table.insert(drops, string.format("x%d %.1fs", r.multiplier, t))
			end
		end
		local r = s:Get()
		check(
			"a straight drains the ladder to x1, never under it",
			r.multiplier == 1 and not under and r.progress == 0,
			`from x{top.multiplier}: {table.concat(drops, ", ")}`
		)
		check("the straight takes no points away", r.score == top.score, `{top.score} -> {r.score}`)
	end

	-- 5. Nothing scores under MinSlipAngleForDrift.
	do
		local s = Score.new()
		run(s, car(Config.Drift.MinSlipAngleForDrift - 0.1, 150), 5)
		check(
			`nothing scores under {Config.Drift.MinSlipAngleForDrift} deg of slip`,
			s:Get().score == 0,
			`score {s:Get().score}`
		)
		local t = Score.new()
		run(t, car(Config.Drift.MinSlipAngleForDrift + 0.1, 150), 1)
		check("and just over it does", t:Get().score > 0, `score {t:Get().score}`)
	end

	-- 6. Nothing scores going backward: past 90 deg of slip, or reversing.
	do
		local s = Score.new()
		run(s, car(120, 150), 5)
		run(s, car(-150, 150), 5)
		run(s, car(180, 40), 5)
		check("nothing scores sliding or rolling backwards", s:Get().score == 0, `score {s:Get().score}`)
	end

	-- 7. In the air: no points, and the ladder holds.
	do
		local s = Score.new()
		run(s, car(80, 1000), 3)
		local before = s:Get()
		run(s, car(30, 150, true), 2)
		local r = s:Get()
		check(
			"airborne: no points, and the ladder neither fills nor drains",
			r.score == before.score and r.multiplier == before.multiplier and r.progress == before.progress,
			`x{before.multiplier} bar {before.progress} -> x{r.multiplier} bar {r.progress}`
		)
	end

	-- 8. Reset zeroes the run and keeps the best.
	do
		local s = Score.new()
		run(s, car(35, 150), 10)
		local first = s:Get().score
		s:Reset()
		local r = s:Get()
		local zeroed = r.score == 0 and r.multiplier == 1 and r.progress == 0 and r.peakMultiplier == 1
		check("Reset() zeroes the run", zeroed, `x{r.multiplier} bar {r.progress} score {r.score}`)
		check("and keeps the best", r.best == first, `best {r.best}, first run {first}`)
		run(s, car(35, 150), 2) -- a worse run
		check("a worse run leaves the best alone", s:Get().best == first, `best {s:Get().best}`)
		s:Reset()
		run(s, car(35, 150), 20) -- a better one
		check("a better run is the new best, live", s:Get().best == s:Get().score, `best {s:Get().best}`)
	end

	-- 9. On the real car: a held drift reaches at least x3.
	do
		local s, runner = drive(HELD_STEER, HELD_SECONDS, 60)
		local r = s:Get()
		check(
			`the real car, finger held at {HELD_STEER}, reaches x3 or more in {HELD_SECONDS} s`,
			r.peakMultiplier >= 3,
			string.format(
				"peak x%d, score %.0f, scoring %.1f of %d s, ends at %.0f studs/s",
				r.peakMultiplier,
				r.score,
				r.driftSeconds,
				HELD_SECONDS,
				Model.speed(runner.state)
			)
		)
		-- And straight on: the real car on a straight line scores nothing.
		local straight = drive(0, 5, 60)
		check("the real car driving straight scores nothing", straight:Get().score == 0, `score {straight:Get().score}`)
	end

	-- 10. The same drive scores the same at every frame rate.
	do
		local a = drive(HELD_STEER, HELD_SECONDS, 30):Get()
		local b = drive(HELD_STEER, HELD_SECONDS, 120):Get()
		check(
			"the same drive at 30 and 120 FPS scores the same",
			math.abs(a.score - b.score) < 1e-6 * math.max(1, a.score) and a.multiplier == b.multiplier,
			string.format("%.4f x%d vs %.4f x%d", a.score, a.multiplier, b.score, b.multiplier)
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
