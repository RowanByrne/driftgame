--!nonstrict
-- PebbleSoundTests: the stones off the road (T-292, Drift/PebbleSound, Config.Pebbles).
--
--   game.ServerStorage.DebugBridge:Invoke("DebugPebbleSoundTests", "run")
--
-- Pure: made-up car states on each ground, and a seeded stream run for simulated seconds
-- with no car and no sound. `run()` returns `{ passed, checks, log }`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "PebbleSoundTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local Model = require(DriftFolder.Model)
local PebbleSound = require(DriftFolder.PebbleSound)

local PebbleSoundTests = {}

local function check(checks, name: string, ok: boolean, detail: string)
	table.insert(checks, { name = name, ok = ok == true, detail = detail })
end

local function f(x: number): string
	return string.format("%.3f", x)
end

-- A car at `speed` studs/s with `slipDeg` of slip, all four wheels on `surface` (or a list).
local function stateWith(opts)
	local s = Model.new(CFrame.new(opts.x or 0, 0, 0))
	s.slip = math.rad(opts.slipDeg or 0)
	s.u = opts.speed or 0
	s.v = 0
	s.airborne = opts.airborne == true
	s.grounded = not s.airborne
	s.wheelsDown = { not s.airborne, not s.airborne, not s.airborne, not s.airborne }
	local surface = opts.surface or "tarmac"
	s.wheelSurface = if type(surface) == "table" then surface else { surface, surface, surface, surface }
	return s
end

local function levels(opts)
	local st = stateWith(opts)
	local g = PebbleSound.groundOf(st)
	local sp = PebbleSound.speedT(st)
	local sl = PebbleSound.slideT(st)
	return {
		ground = g,
		rate = PebbleSound.rateFor(g, sp, sl),
		bed = PebbleSound.bedVolumeFor(g, sp, sl),
		tick = PebbleSound.tickLevelFor(g, sp),
	}
end

function PebbleSoundTests.run()
	local checks, log = {}, {}
	local P = Config.Pebbles

	-- The grounds
	local tarmac = levels({ surface = "tarmac", speed = 100 })
	local gravel = levels({ surface = "gravel", speed = 100 })
	local dirt = levels({ surface = "dirt", speed = 100 })
	local grass = levels({ surface = "grass", speed = 100 })
	check(checks, "tarmac at 100 studs/s is silent", tarmac.rate == 0 and tarmac.bed == 0 and tarmac.tick == 0,
		`rate {f(tarmac.rate)}, crunch {f(tarmac.bed)}`)
	check(checks, "gravel > dirt > grass > 0 (ticks a second and crunch)",
		gravel.rate > dirt.rate and dirt.rate > grass.rate and grass.rate > 0
			and gravel.bed > dirt.bed and dirt.bed > grass.bed and grass.bed > 0,
		`rate {f(gravel.rate)} / {f(dirt.rate)} / {f(grass.rate)}; crunch {f(gravel.bed)} / {f(dirt.bed)} / {f(grass.bed)}`)
	table.insert(log, `at 100 studs/s: gravel {f(gravel.rate)}/s crunch {f(gravel.bed)}; dirt {f(dirt.rate)}/s; grass {f(grass.rate)}/s`)

	local stopped = levels({ surface = "gravel", speed = 2 })
	check(checks, "stopped on gravel (2 studs/s) is silent", stopped.rate == 0 and stopped.bed == 0,
		`rate {f(stopped.rate)}, crunch {f(stopped.bed)} under MinSpeed {P.MinSpeed}`)
	local air = levels({ surface = "gravel", speed = 100, airborne = true })
	check(checks, "airborne over gravel is silent", air.rate == 0 and air.bed == 0, `ground {f(air.ground)}`)

	local half = levels({ surface = { "gravel", "gravel", "tarmac", "tarmac" }, speed = 100 })
	check(checks, "two wheels on gravel give half the gravel", math.abs(half.ground - 0.5 * P.Surfaces.gravel) < 1e-9,
		`ground {f(half.ground)}`)

	-- Speed and slide
	local r30 = levels({ surface = "gravel", speed = 30 })
	local r60 = levels({ surface = "gravel", speed = 60 })
	local r110 = levels({ surface = "gravel", speed = 110 })
	local r170 = levels({ surface = "gravel", speed = 170 })
	check(checks, "faster is denser and louder, full at FullSpeed",
		r30.rate < r60.rate and r60.rate < r110.rate and math.abs(r110.rate - r170.rate) < 1e-9
			and r30.bed < r60.bed and r60.bed < r110.bed and r30.tick < r110.tick,
		`rate 30/60/110/170: {f(r30.rate)} {f(r60.rate)} {f(r110.rate)} {f(r170.rate)}`)
	local slide = levels({ surface = "gravel", speed = 110, slipDeg = 40 })
	check(checks, "a slide adds more", slide.rate > r110.rate and slide.bed > r110.bed,
		`rate {f(r110.rate)} -> {f(slide.rate)}, crunch {f(r110.bed)} -> {f(slide.bed)}`)
	table.insert(log, `gravel rate by speed 30/60/110: {f(r30.rate)} {f(r60.rate)} {f(r110.rate)}; sliding 40 deg at 110: {f(slide.rate)}`)

	-- The fade: a full swing takes FadeSeconds at 60 fps, and no frame moves more than its share
	local g, frames, worst = 0, 0, 0
	while g < 1 and frames < 1000 do
		local before = g
		g = PebbleSound.fadeStep(g, 1, 1 / 60)
		worst = math.max(worst, g - before)
		frames += 1
	end
	check(checks, "a change of ground fades over FadeSeconds",
		math.abs(frames / 60 - P.FadeSeconds) <= 1 / 60 + 1e-9 and worst <= (1 / 60) / P.FadeSeconds + 1e-9,
		`{frames} frames ({f(frames / 60)} s), largest step {f(worst)}`)

	-- The stream, seeded, 20 simulated seconds at full speed on gravel
	local pebble = PebbleSound.new(292)
	local state = stateWith({ surface = "gravel", speed = 110 })
	local dt = 1 / 60
	local times = {}
	local t = 0
	for _ = 1, 20 * 60 do
		local before = pebble.ticks
		PebbleSound.Update(pebble, state, dt)
		for _ = 1, pebble.ticks - before do
			table.insert(times, t)
		end
		t += dt
	end
	local n = #times
	local expect = P.MaxRate * 20 * (P.Surfaces.gravel)
	local intervals = {}
	for i = 2, n do
		table.insert(intervals, times[i] - times[i - 1])
	end
	local mean, var = 0, 0
	for _, x in intervals do
		mean += x
	end
	mean /= math.max(#intervals, 1)
	for _, x in intervals do
		var += (x - mean) ^ 2
	end
	local cv = math.sqrt(var / math.max(#intervals, 1)) / math.max(mean, 1e-9)
	check(checks, "the stream fires about MaxRate a second on gravel at full speed",
		math.abs(n - expect) / expect < 0.15, `{n} ticks in 20 s, expected about {expect} (the first 0.25 s fades in)`)
	check(checks, "irregular, never a beat: interval spread near a random stream's (CV 0.7 to 1.3)",
		cv > 0.7 and cv < 1.3, `interval mean {f(mean)} s, CV {f(cv)}`)
	local share = pebble.clacks / math.max(pebble.ticks, 1)
	check(checks, "about ClackShare of them are clacks", math.abs(share - P.ClackShare) < 0.06,
		`{pebble.clacks} of {pebble.ticks} ({f(share)}, wanted {P.ClackShare})`)

	-- Onto tarmac: silent within FadeSeconds, and no tick after it
	local road = stateWith({ surface = "tarmac", speed = 110 })
	local after = 0
	for i = 1, 60 do
		local before = pebble.ticks
		PebbleSound.Update(pebble, road, dt)
		if i * dt > P.FadeSeconds + dt then
			after += pebble.ticks - before
		end
	end
	check(checks, "onto tarmac: silent after the fade", pebble.ground == 0 and pebble.rate == 0 and after == 0,
		`ground {f(pebble.ground)}, ticks after the fade {after}`)

	-- A jump silences at once
	PebbleSound.Update(pebble, state, 1)
	local cutsBefore = pebble.cuts
	PebbleSound.Update(pebble, stateWith({ surface = "gravel", speed = 110, x = 500 }), 0)
	check(checks, "a teleport silences at once", pebble.cuts == cutsBefore + 1 and pebble.ground == 0,
		`cuts {cutsBefore} -> {pebble.cuts}, ground {f(pebble.ground)}`)

	-- The slice table
	local okTable, worstLevel = true, 0
	for _, tick in P.Ticks do
		if not (tick.length > 0.01 and tick.length < 0.1 and tick.start >= 0 and tick.gain > 0) then
			okTable = false
		end
		worstLevel = math.max(worstLevel, P.TickVolume * tick.gain)
	end
	check(checks, "every slice is a short, positive window", okTable and #P.Ticks >= 20, `{#P.Ticks} slices`)
	table.insert(log, `loudest tick instance volume wanted {f(worstLevel)} (held at 10)`)

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = log }
end

return PebbleSoundTests
