--!nonstrict
-- ScoreEventsTests: the score event engine and its first two detectors, jump and wheel lift
-- (docs/game/features/score-events.md "Testing", T-295).
--
-- Run it from the server debug bridge, or straight off the modules -- they are pure:
--   game.ServerStorage.DebugBridge:Invoke("DebugScoreEventsTests", "run")
--
-- Three parts. The ENGINE on stand-in car states with a `Drift/Score` of its own, where every
-- number is known: each kind's points, the bar, banking and loss, and the anti-farming rules.
-- The DETECTORS on stand-in state sequences with a recording sink (the shared interface: a
-- detector reaches the engine only through its sink). And the REAL CAR (`Drift/Sim`): plain
-- drifting scores exactly what it did with no events, and a kicker ramp makes a jump that
-- scores the same at 30 and 120 FPS.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "ScoreEventsTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local Score = require(DriftFolder.Score)
local ScoreEvents = require(DriftFolder.ScoreEvents)
local Sim = require(DriftFolder.Sim)
local World = require(DriftFolder.World)
local Jump = require(DriftFolder.Events.Jump)
local WheelLift = require(DriftFolder.Events.WheelLift)

local Tests = {}

local STEP = 1 / 120
local K = Config.ScoreEvents.Kinds
local E = Config.ScoreEvents

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6) * math.max(1, math.abs(b))
end

-- An engine fed to a fresh score, silent.
local function engine()
	local score = Score.new()
	local e = ScoreEvents.new()
	e.print = false
	e:bind(function()
		return score
	end)
	return e, score
end

-- A car moving `speed` along its nose at `slipDeg`, on the ground, at `x` along the world X.
local function car(speed: number, x: number?, slipDeg: number?)
	local b = math.rad(slipDeg or 0)
	return {
		slip = b,
		u = speed * math.cos(b),
		v = -speed * math.sin(b),
		surfaceScore = Config.Drift.ScoreTarmac,
		grounded = true,
		airborne = false,
		pinned = false,
		fell = false,
		position = Vector3.new(x or 0, 0, 0),
	}
end

-- `seconds` of steps as the live game takes them: the engine, then `each()` (the detectors'
-- part), then the score.
-- The car moves as its speed says (along X by `u`, along Z by `v`): the engine pays only for
-- ground really covered (T-301).
local function run(e, score, state, seconds: number, each: (() -> ())?)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		state.position += Vector3.new(state.u * STEP, 0, state.v * STEP)
		e:step(STEP, state)
		if each then
			each()
		end
		score:Step(STEP, state)
	end
end

-- A sink that records what a detector asks for.
local function recorder()
	local rec = { oneOffs = {}, starts = {} }
	rec.sink = {
		oneOff = function(kind, size, info)
			table.insert(rec.oneOffs, { kind = kind, size = size, info = info })
		end,
		start = function(kind, info)
			local h = { kind = kind, info = info, updates = {}, seconds = 0, maxSize = 0, finished = nil }
			function h:update(size, dt)
				table.insert(self.updates, { size = size, dt = dt })
				self.seconds += dt
				self.maxSize = math.max(self.maxSize, size)
			end
			function h:finish(completed)
				self.finished = completed
			end
			table.insert(rec.starts, h)
			return h
		end,
	}
	return rec
end

-- A stand-in state for the detectors.
local function pose(t)
	return {
		airborne = t.airborne == true,
		grounded = t.airborne ~= true,
		hanging = t.hanging == true,
		wheelsDown = t.wheelsDown or { true, true, true, true },
		fell = t.fell == true,
		wallHit = t.wallHit == true,
		position = Vector3.new(0, t.y or Config.Drift.RideHeight, 0),
		groundY = 0,
		fallFrom = 0,
		up = t.up or Vector3.yAxis,
	}
end

-- The stand-ins share one place, which moves along X at `walker.speed` studs/s (0: in place).
local walker = { x = 0, speed = 60 }
local function feedDetector(det, state, seconds: number)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		walker.x += walker.speed * STEP
		state.position = Vector3.new(walker.x, state.position.Y, 0)
		det:Update(STEP, state)
	end
end

-- A kicker: flat at y = 0, then a 15 degree ramp from 60 to 100 studs ahead (the car starts
-- facing -Z), then flat at 0 again: a 10.7-stud lip into a drop.
local function kicker(): any
	local t = math.tan(math.rad(15))
	local slope = Vector3.new(0, 1, t).Unit
	return {
		probe = function(pos: Vector3)
			local d = -pos.Z
			if d >= 60 and d <= 100 then
				return { y = (d - 60) * t, normal = slope, grip = Config.Drift.GripTarmac, score = Config.Drift.ScoreTarmac }
			end
			return { y = 0, normal = Vector3.yAxis, grip = Config.Drift.GripTarmac, score = Config.Drift.ScoreTarmac }
		end,
	}
end

-- The real car from a rolling start, the engine and detectors stepped as DriftController
-- steps them, the score after. `withEvents = false` steps the score alone.
local function drive(world, steer: number, seconds: number, fps: number, withEvents: boolean)
	local runner = Sim.newRunner(CFrame.new(0, Config.Drift.RideHeight, 0))
	runner.state.velocity = Vector3.new(0, 0, -100)
	local score = Score.new()
	local e = ScoreEvents.new()
	e.print = false
	e:bind(function()
		return score
	end)
	local sink = e:sink()
	local dets = { Jump.new(sink, nil), WheelLift.new(sink, nil) }
	for _ = 1, math.floor(seconds * fps + 0.5) do
		Sim.advance(runner, 1 / fps, { steer = steer }, world, function(s)
			if withEvents then
				e:step(Config.Drift.FixedStep, s)
				for _, d in dets do
					d:Update(Config.Drift.FixedStep, s)
				end
			end
			score:Step(Config.Drift.FixedStep, s)
		end)
	end
	return score, e, dets
end

function Tests.run()
	local checks = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end

	-- ------------------------------------------------------------------- one-offs
	do
		local e, score = engine()
		e:step(STEP, car(80, 0))
		e:oneOff("nearMiss", 1)
		local first = score:Get().score
		e:step(STEP, car(80, 500))
		e:oneOff("nearMiss", 0)
		local second = score:Get().score - first
		check(
			"a one-off: Base x size's scale, into the score at once",
			near(first, K.nearMiss.Base) and near(second, K.nearMiss.Base * K.nearMiss.SizeFloor * E.RepeatFactor),
			string.format("graze %.3f (want %d); edge, a repeat %.3f", first, K.nearMiss.Base, second)
		)
	end
	do
		local e, score = engine()
		score.multiplier = 3
		e:step(STEP, car(80, 0))
		e:oneOff("nearMiss", 1)
		check("a one-off is times the rung", near(score:Get().score, 3 * K.nearMiss.Base), `{score:Get().score} at x3`)
	end
	do
		local s = Score.new()
		s.multiplier, s.progress = 2, 0.5
		s:Award(0, 50)
		local r = s:Get()
		check(
			"one kick climbs one rung at most",
			r.multiplier == 3 and near(r.progress, Config.Score.MaxKick - 1),
			`x2 bar 0.5, kick 50 -> x{r.multiplier} bar {r.progress}`
		)
	end

	-- ------------------------------------------------------------------ sustained
	do
		local e, score = engine()
		local state = car(80, 0)
		e:step(STEP, state)
		local h = e:start("wheelLift")
		run(e, score, state, 1, function()
			h:update(1, STEP)
		end)
		local before = score:Get().score
		local entry = h.entry
		h:finish(true)
		local want = K.wheelLift.Rate * 80 * 1 -- a stud a step at 80 studs/s for 1 s, x1
		check(
			"a held event collects on its line, not in the score, while held",
			before == 0 and near(entry.points, want, 1e-4),
			string.format("score %.3f while held; line %.3f, want %.3f", before, entry.points, want)
		)
		check(
			"and banks into the score on a clean finish",
			near(score:Get().score, entry.points) and entry.state == "banked",
			string.format("score %.3f, %s", score:Get().score, entry.state)
		)
		check(
			"its bar fills at Fill a second and does not drain",
			near(score:Get().progress, K.wheelLift.Fill, 1e-4) and score:Get().multiplier == 1,
			`bar {score:Get().progress}`
		)
	end
	do
		local e, score = engine()
		local state = car(80, 0)
		e:step(STEP, state)
		local h = e:start("bumperGrind")
		run(e, score, state, 1, function()
			h:update(1, STEP)
		end)
		h:finish(false)
		check(
			"finish(false) loses it: nothing reaches the score",
			score:Get().score == 0 and h.entry.state == "void" and e.counts.bumperGrind.void == 1,
			`score {score:Get().score}, {h.entry.state}`
		)
	end
	do
		-- the drain: x3, half a bar, a straight for a second
		local function bar(held: boolean)
			local e, score = engine()
			score.multiplier, score.progress = 3, 0.5
			local state = car(80, 0)
			e:step(STEP, state)
			local h = e:start("wheelLift")
			run(e, score, state, 1, function()
				if held then
					h:update(0, STEP) -- size 0: no points, no fill, but held
				end
			end)
			return score:Get().progress
		end
		local held, free = bar(true), bar(false)
		check("a held event stops the drain", held == 0.5 and free < 0.5, `held {held}, not held {free}`)
	end
	do
		local e, score = engine()
		local state = car(80, 0)
		e:step(STEP, state)
		local h = e:start("wheelLift")
		local banked = {}
		e.feed:Connect(function(entry)
			if entry.state == "banked" then
				table.insert(banked, entry)
			end
		end)
		run(e, score, state, 13, function()
			h:update(0.4, STEP)
		end)
		local midway = #banked
		h:finish(true)
		local sum = 0
		for _, b in banked do
			sum += b.points
		end
		check(
			`held past MaxSeconds ({K.wheelLift.MaxSeconds} s) banks and starts a fresh line`,
			midway == 2 and #banked == 3 and banked[1].id < banked[2].id and banked[2].id < banked[3].id
				and near(score:Get().score, sum),
			`{midway} banked by 13 s, {#banked} after; score {score:Get().score}, lines {sum}`
		)
	end

	-- ---------------------------------------------------------------- conditional
	do
		local function hairpin(size: number)
			local e, score = engine()
			local state = car(80, 0)
			e:step(STEP, state)
			local h = e:start("perfectHairpin")
			run(e, score, state, 0.5, function()
				h:update(size, STEP)
			end)
			h:finish(true)
			return score:Get().score, h.entry
		end
		local four, entry = hairpin(1)
		local two = hairpin(0.5)
		check(
			"perfect hairpin: the 4-wheel level is worth twice the 2-wheel",
			near(four, 2 * two, 1e-9) and near(entry.points, four),
			string.format("4-wheel %.3f, 2-wheel %.3f", four, two)
		)
		local e, score = engine()
		local state = car(80, 0)
		e:step(STEP, state)
		local h = e:start("scandiFlick")
		run(e, score, state, 1, function()
			h:update(1, STEP)
		end)
		h:finish(false)
		check("a conditional not completed banks nothing", score:Get().score == 0, `score {score:Get().score}`)
	end

	-- --------------------------------------------------------------- anti-farming
	do
		local e, score = engine()
		local got = {}
		for i = 1, 3 do
			e:step(STEP, car(80, i * 100))
			local before = score:Get().score
			e:oneOff("nearMiss", 1)
			table.insert(got, score:Get().score - before)
		end
		run(e, score, car(80, 1000), K.nearMiss.RepeatWindow + 0.1)
		local before = score:Get().score
		local rung = score.multiplier
		e:oneOff("nearMiss", 1)
		local after = (score:Get().score - before) / rung
		check(
			"repeats in the window are worth half, compounding; after it, full again",
			near(got[1], 100) and near(got[2], 50) and near(got[3], 25) and near(after, 100),
			string.format("%.1f, %.1f, %.1f; after the window %.1f", got[1], got[2], got[3], after)
		)
	end
	do
		local e, score = engine()
		e:step(STEP, car(80, 0))
		e:oneOff("nearMiss", 1)
		run(e, score, car(80, 10), E.SameSpotGap + 0.5)
		e:step(STEP, car(80, 10)) -- back at the spot
		local before = score:Get().score
		e:oneOff("nearMiss", 1)
		local same = score:Get().score - before
		e:step(STEP, car(80, 200))
		e:oneOff("nearMiss", 1)
		local elsewhere = score:Get().score - before
		check(
			"the same spot again scores nothing; elsewhere it does",
			same == 0 and elsewhere > 0 and e.counts.nearMiss.spent == 1,
			`same spot +{same}, 200 studs on +{elsewhere}`
		)
	end
	do
		local e, score = engine()
		e:step(STEP, car(-60, 0))
		e:oneOff("nearMiss", 1)
		local h = e:start("wheelLift")
		run(e, score, car(-60, 300), 1, function()
			h:update(1, STEP)
		end)
		local backward = h.entry.points
		h:finish(true)
		local slow = engine()
		local s2 = car(E.MinSpeed - 1, 0)
		slow:step(STEP, s2)
		slow:oneOff("nearMiss", 1)
		local pinnedState = car(80, 0)
		pinnedState.pinned = true
		local p, ps = engine()
		p:step(STEP, pinnedState)
		local hp = p:start("bumperGrind")
		run(p, ps, pinnedState, 1, function()
			hp:update(1, STEP)
		end)
		local r, rs = engine()
		r:step(STEP, car(-60, 0))
		local hr = r:start("reverseEntry")
		run(r, rs, car(-60, 0), 1, function()
			hr:update(1, STEP)
		end)
		check(
			"nothing counts going backwards, too slow, or pinned",
			score:Get().score == 0 and backward == 0 and slow.counts.nearMiss.gated == 1 and hp.entry.points == 0,
			`backwards {score:Get().score}, slow gated {slow.counts.nearMiss.gated}, pinned {hp.entry.points}`
		)
		check("but reverse entry counts going backwards (Forward = false)", hr.entry.points > 0, `{hr.entry.points}`)
		check(
			"a held event that earned nothing never makes a line",
			e.counts.wheelLift.empty == 1 and e.counts.wheelLift.banked == 0 and #e.log == 0,
			`empty {e.counts.wheelLift.empty}, banked {e.counts.wheelLift.banked}, lines {#e.log}`
		)
	end
	do
		local e, score = engine()
		local state = car(1000, 0)
		e:step(STEP, state)
		local h = e:start("hangGrind")
		local worst = 0
		run(e, score, state, 30, function()
			h:update(1, STEP)
			worst = math.max(worst, e.binSum)
		end)
		local budget = E.MaxEventRate * E.RateWindow
		check(
			`the ceiling: {E.MaxEventRate} points a second at x1 over {E.RateWindow} s, all events together`,
			worst <= budget + 1e-6 and e.allowed <= E.MaxEventRate * (30 + E.RateWindow) + 1e-6
				and e.allowed >= E.MaxEventRate * 30 * 0.95,
			string.format("asked %.0f a second for 30 s; let through %.0f, window peak %.1f of %d", 0.5 * 1000, e.allowed, worst, budget)
		)
	end

	-- ------------------------------------------------------------ loss and the run
	do
		local e, score = engine()
		local state = car(80, 0)
		e:step(STEP, state)
		local h = e:start("bumperGrind")
		run(e, score, state, 0.5, function()
			h:update(1, STEP)
		end)
		local fall = car(80, 0)
		fall.fell = true
		e:step(STEP, fall)
		h:finish(true) -- too late: already lost
		check(
			"a fall loses a live event",
			h.entry.state == "void" and score:Get().score == 0,
			`{h.entry.state}, score {score:Get().score}`
		)

		local e2, score2 = engine()
		local a = car(80, 0)
		a.time = 5
		e2:step(STEP, a)
		local h2 = e2:start("bumperGrind")
		run(e2, score2, a, 0.5, function()
			h2:update(1, STEP)
		end)
		local b = car(80, 0)
		b.time = 0
		e2:step(STEP, b)
		check("the car put back (a new state) loses it", h2.entry.state == "void" and score2:Get().score == 0, h2.entry.state)
	end
	do
		local inRun = true
		local score = Score.new()
		local e = ScoreEvents.new()
		e.print = false
		e:bind(function()
			return if inRun then score else nil
		end)
		local state = car(80, 0)
		e:step(STEP, state)
		local h = e:start("bumperGrind")
		h:update(1, 0.5)
		inRun = false
		e:step(STEP, state)
		e:oneOff("nearMiss", 1)
		local inert = e:start("wheelLift")
		inert:update(1, 1)
		inert:finish(true)
		check(
			"outside a run nothing scores, and the run ending loses what is live",
			h.entry.state == "void" and score:Get().score == 0 and inert.live == false,
			`{h.entry.state}, score {score:Get().score}`
		)
	end
	do
		local e, score = engine()
		local entries = {}
		e.feed:Connect(function(entry)
			table.insert(entries, entry)
		end)
		local state = car(80, 0)
		e:step(STEP, state)
		local h = e:start("wheelLift")
		run(e, score, state, 1, function()
			h:update(1, STEP)
		end)
		h:finish(true)
		local rising = true
		for i = 2, #entries do
			rising = rising and entries[i].points >= entries[i - 1].points and entries[i].id == entries[1].id
		end
		local last = entries[#entries]
		check(
			"the feed: a live line, its growth no faster than FeedEvery, then banked",
			entries[1].state == "live" and last.state == "banked" and rising
				and #entries <= math.ceil(1 / E.FeedEvery) + 3 and last.label == "TWO WHEELS"
				and type(last.rung) == "number",
			`{#entries} entries, last {last.label} +{math.floor(last.points)} {last.state}`
		)
	end

	-- ---------------------------------------------------------- jump, on stand-ins
	do
		local D = Config.ScoreEvents.Detectors.Jump
		local rec = recorder()
		local j = Jump.new(rec.sink, nil)
		local ground, air = pose({}), pose({ airborne = true, y = Config.Drift.RideHeight + 6 })
		feedDetector(j, ground, 0.5)
		feedDetector(j, air, D.MinAir - 0.1)
		feedDetector(j, ground, 0.5)
		local hop = #rec.starts
		feedDetector(j, air, 1)
		local h = rec.starts[1]
		local liveWhileDown = h and h.finished
		feedDetector(j, ground, D.LandSettle + 0.05)
		check(
			`jump: a hop under {D.MinAir} s is nothing; a 1 s flight starts at {D.MinAir} s and banks after landing`,
			hop == 0 and #rec.starts == 1 and h.finished == true and liveWhileDown == nil
				and near(h.seconds, 1, 0.01) and near(h.maxSize, 6 / D.FullHeight, 0.01),
			h and string.format("%d starts; held %.3f s, size %.2f, finished %s", #rec.starts, h.seconds, h.maxSize, tostring(h.finished))
				or "no start"
		)
		local function lost(mid)
			local r = recorder()
			local jj = Jump.new(r.sink, nil)
			feedDetector(jj, ground, 0.1)
			feedDetector(jj, air, 0.6)
			feedDetector(jj, mid, STEP)
			feedDetector(jj, ground, 0.5)
			return r.starts[1] and r.starts[1].finished
		end
		local fell = lost(pose({ airborne = true, fell = true }))
		local wall = lost(pose({ airborne = true, wallHit = true }))
		local roof = lost(pose({ up = Vector3.new(0, -1, 0) }))
		check(
			"jump: lost on a fall, a wall, or landing on its roof",
			fell == false and wall == false and roof == false,
			`fall {fell}, wall {wall}, roof {roof}`
		)
	end

	-- ---------------------------------------------------- wheel lift, on stand-ins
	do
		local D = Config.ScoreEvents.Detectors.WheelLift
		local rec = recorder()
		local w = WheelLift.new(rec.sink, nil)
		local flat = pose({})
		local one = pose({ wheelsDown = { true, false, true, true } })
		local side = pose({ wheelsDown = { false, true, false, true } })
		local three = pose({ wheelsDown = { false, false, false, true } })
		local hang = pose({ hanging = true, wheelsDown = { true, true, false, false } })
		feedDetector(w, one, D.MinHold - 0.05)
		feedDetector(w, flat, 0.5)
		feedDetector(w, three, 1)
		feedDetector(w, flat, 0.5)
		feedDetector(w, hang, 1)
		feedDetector(w, flat, 0.5)
		local none = #rec.starts
		-- a second of one wheel up, flat for one step in every twelve
		for i = 1, 120 do
			w:Update(STEP, if i % 12 == 0 then flat else one)
		end
		feedDetector(w, side, 0.5)
		feedDetector(w, flat, D.Grace + 0.05)
		local h = rec.starts[1]
		check(
			"wheel lift: a flicker, three wheels up, or hanging is nothing",
			none == 0,
			`{none} starts`
		)
		check(
			"wheel lift: held through one-step gaps is one lift, two on a side is size 1, it banks",
			#rec.starts == 1 and h.finished == true and h.maxSize == D.TwoWheelSize
				and near(h.seconds, 1.5 - 10 * STEP, 0.02),
			h and string.format("%d starts, held %.3f s, size %.2f, finished %s", #rec.starts, h.seconds, h.maxSize, tostring(h.finished))
				or "no start"
		)
		local r2 = recorder()
		local w2 = WheelLift.new(r2.sink, nil)
		feedDetector(w2, one, 0.5)
		feedDetector(w2, pose({ airborne = true }), STEP)
		check("wheel lift: the car leaving the ground ends it cleanly", r2.starts[1] and r2.starts[1].finished == true, "")
	end

	-- ------------------------------------------------------------- the real car
	do
		local flat = World.flat(0)
		local plain = drive(flat, 0.15, 12, 60, false):Get()
		local withEvents, e = drive(flat, 0.15, 12, 60, true)
		local r = withEvents:Get()
		check(
			"the real car drifting on the flat: the same score to the bit with the events on, and none fired",
			r.score == plain.score and r.progress == plain.progress and r.multiplier == plain.multiplier
				and r.eventPoints == 0 and next(e.counts) == nil,
			string.format("%.6f x%d vs %.6f x%d; event points %s", r.score, r.multiplier, plain.score, plain.multiplier, tostring(r.eventPoints))
		)
	end
	do
		local world = kicker()
		local s60, e60, d60 = drive(world, 0, 4, 60, true)
		local s30 = drive(world, 0, 4, 30, true)
		local s120 = drive(world, 0, 4, 120, true)
		local js = d60[1]:DebugState().stats
		local c = e60.counts.jump
		local a, b, d = s30:Get().eventPoints, s60:Get().eventPoints, s120:Get().eventPoints
		check(
			"the real car off a 15 degree kicker: one jump, banked, its points in the score",
			c ~= nil and c.banked == 1 and b > 0 and near(s60:Get().score, b),
			c and string.format("%d jump, %d banked, %.1f points, %.2f s in the air, %.1f studs high", c.started, c.banked, b, js.longestAir, js.highest)
				or "no jump"
		)
		check(
			"and the same at 30, 60 and 120 FPS",
			near(a, b, 1e-9) and near(d, b, 1e-9),
			string.format("%.6f / %.6f / %.6f", a, b, d)
		)
		check(
			"and the same points as before the hop-farming fix (T-295: 70.184074)",
			near(b, 70.184074, 1e-7),
			string.format("%.6f", b)
		)
	end

	-- ------------------------------------------------- hopping in place (T-301)
	-- The farm T-297 found live: after a grind the car bounced in place against the rail,
	-- its velocity still reading 30 studs/s, and the console filled with banked jumps and
	-- lifts. Before the fix this scored 3,492 and 4,012 points in 30 s (measured, DR-Lane2).
	do
		local RH = Config.Drift.RideHeight
		local function hops(airS: number, downS: number, speed: number, seconds: number)
			local e, score = engine()
			local sink = e:sink()
			local j, w = Jump.new(sink, nil), WheelLift.new(sink, nil)
			local st = {
				slip = 0, u = 30, v = 0, surfaceScore = 1, grounded = true, airborne = false, pinned = false,
				fell = false, hanging = false, wallHit = false, position = Vector3.new(0, RH, 0), groundY = 0,
				fallFrom = 0, up = Vector3.yAxis, wheelsDown = { true, true, true, true }, time = 1,
			}
			if speed > 0 then
				st.u = speed
			end
			local t, x = 0, 0
			while t < seconds do
				local inAir = (t % (airS + downS)) < airS
				st.airborne, st.grounded = inAir, not inAir
				x += speed * STEP
				st.position = Vector3.new(x, RH + (if inAir then 1.5 else 0), 0)
				-- on the ground one wheel is up, as a car tipped against a rail
				st.wheelsDown = if inAir then { false, false, false, false } else { true, false, true, true }
				st.time += STEP
				e:step(STEP, st)
				j:Update(STEP, st)
				w:Update(STEP, st)
				score:Step(STEP, st)
				t += STEP
			end
			return score.eventPoints, e, j:DebugState().stats
		end
		local worst, parts = 0, {}
		for _, p in { { 0.5, 0.1 }, { 0.45, 0.3 }, { 0.6, 0.05 }, { 0.42, 0.2 } } do
			local pts, _, js = hops(p[1], p[2], 0, 30)
			worst = math.max(worst, pts)
			table.insert(parts, string.format("%.2f/%.2f s: %.1f (%d hops)", p[1], p[2], pts, js.hops))
		end
		check(
			"hopping in place for 30 s (velocity 30 studs/s, going nowhere) scores ~0",
			worst < 1,
			table.concat(parts, "; ")
		)
		-- Held against a rail on a lifted wheel, going nowhere: no lift points.
		local held = hops(0, 1, 0, 30)
		check("a wheel up on a car going nowhere scores nothing", held < 1e-9, `{held}`)

		-- The same bouncing, but driving forward at 60 studs/s: real flights, each covering 30
		-- studs. They still score, cut by the repeat rule rather than paid in full for ever.
		local moving, e = hops(0.5, 0.1, 60, 30)
		local c = e.counts.jump
		check(
			"bouncing along at 60 studs/s: the flights score, cut by repeats, bounded",
			c and c.banked >= 3 and c.banked + c.empty >= 10 and moving > 0 and moving < 400,
			c and string.format("%d jumps (%d with a line), %d same spot, %.1f points in 30 s", c.banked + c.empty, c.banked, c.spent, moving) or "no jump"
		)

		-- Lifts in a row while driving at 20 studs/s: the 8-stud spot never blocks them.
		local le, ls = engine()
		local wl = WheelLift.new(le:sink(), nil)
		local st = car(25, 0)
		st.grounded, st.airborne, st.hanging, st.time = true, false, false, 1
		local tt = 0
		while tt < 10 do
			st.wheelsDown = if (tt % 0.45) < 0.3 then { true, false, true, true } else { true, true, true, true }
			st.position += Vector3.new(25 * STEP, 0, 0)
			st.time += STEP
			le:step(STEP, st)
			wl:Update(STEP, st)
			ls:Step(STEP, st)
			tt += STEP
		end
		local lc = le.counts.wheelLift
		check(
			"lifts in a row while driving slowly still count (none taken for the same spot)",
			lc and lc.started >= 20 and lc.spent == 0 and ls.eventPoints > 0,
			lc and string.format("%d lifts, %d same spot, %.1f points", lc.started, lc.spent, ls.eventPoints) or "none"
		)
	end

	local passed = true
	for _, ch in checks do
		passed = passed and ch.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
