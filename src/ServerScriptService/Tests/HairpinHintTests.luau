--!nonstrict
-- HairpinHintTests: the "HAIRPIN AHEAD" line in the score feed (T-304): when
-- `Drift/HairpinHint` says so, and how `Drift/ScoreFeedView` draws it.
--
--   game.ServerStorage.DebugBridge:Invoke("DebugHairpinHintTests", "run")
--   require(game.ServerScriptService.Tests.HairpinHintTests).run()   -- pure: Edit works too
--
-- 1. WHEN, on seed 31337 (14 000 studs): a car ridden down the centre line at 40, 60 and 100
--    studs/s gets one hint for every true hairpin and none for the plain double-yellow bends,
--    `Lead` studs (less at most one look ahead) before each entry zone; the same at 30, 60
--    and 120 steps a second; with the road laid only a few hundred studs ahead, as it is live;
--    and after a put-back, nothing for `Quiet` seconds, then a fresh pass hints again.
-- 2. THE LINE: the fixtures drawn in a feed: the notice's words, outline, no points, no
--    underline, never `Active`, its hold and fade; a full feed of live lines keeps them all.
--
-- `run()` returns `{ passed, checks, log }`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "HairpinHintTests only runs in Studio")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local Hairpins = require(ReplicatedStorage.Shared.Road.Hairpins)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")
local HairpinHint = require(DriftFolder.HairpinHint)
local ScoreFeedView = require(DriftFolder.ScoreFeedView)
local Fixtures = require(DriftFolder:WaitForChild("ScoreFeedView.fixtures"))

local SEED = 31337
local LENGTH = 14000

local HairpinHintTests = {}

local function fmt(x: number?, p: number?): string
	if x == nil then
		return "nil"
	end
	return string.format("%." .. tostring(p or 1) .. "f", x)
end

-- A state on the centre line at `s`, moving along the road at `speed`.
local function at(spline, s: number, speed: number)
	return {
		position = spline:surface(s, 0) + Vector3.new(0, Config.Drift.RideHeight, 0),
		u = speed,
		v = 0,
	}
end

-- Ride from `from` to `to` at `speed`, `hz` steps a second; `grow(s)` may lay more road;
-- `jump(s)` may return studs to jump. Returns every hint, with the s it came at.
local function ride(gen, opts)
	local spline = gen.spline
	local hinter = HairpinHint.new({ spline = spline })
	local dt = 1 / (opts.hz or 120)
	local speed = opts.speed or 60
	local s = opts.from or 0
	local to = opts.to or (spline.length - 50)
	local hints = {}
	local t = 0
	while s <= to do
		if opts.grow then
			opts.grow(s)
		end
		local h = hinter:Update(dt, at(spline, s, speed))
		if h then
			h.s = s
			h.t = t
			table.insert(hints, h)
		end
		s += speed * dt
		t += dt
		if opts.jump then
			local j = opts.jump(s, t)
			if j then
				s += j
			end
		end
		if opts.until_ and s > opts.until_ then
			break
		end
	end
	return hints, hinter
end

local function runAll()
	local checks, log = {}, {}
	local function check(name: string, ok: boolean, detail: string)
		table.insert(checks, { name = name, ok = ok == true, detail = detail })
	end
	local T = HairpinHint.Tuning

	local gen = SplineGen.new(SEED)
	gen:extendTo(LENGTH)
	local spline = gen.spline
	local pins, plain = {}, {}
	for _, b in Hairpins.bends(spline, 0, spline.length) do
		if not b.open and b.exit < LENGTH - 400 then
			if b.hairpin then
				table.insert(pins, b)
			else
				table.insert(plain, b)
			end
		end
	end
	local pinList = {}
	for _, h in pins do
		table.insert(pinList, `{fmt(h.entry, 0)} {if h.dir > 0 then "L" else "R"}`)
	end
	table.insert(log, `seed {SEED}, {fmt(spline.length, 0)} studs: {#pins} true hairpins ({table.concat(pinList, ", ")}), {#plain} plain double-yellow bends`)

	-------------------------------------------------------------- 1. when
	local function judge(hints)
		local byEntry, extra, worst, best = {}, 0, math.huge, -math.huge
		for _, h in hints do
			if byEntry[h.entry] then
				extra += 1
			end
			byEntry[h.entry] = (byEntry[h.entry] or 0) + 1
			worst = math.min(worst, h.toZone)
			best = math.max(best, h.toZone)
		end
		local missing, onPlain = 0, 0
		for _, h in pins do
			if not byEntry[h.entry] then
				missing += 1
			end
		end
		for _, b in plain do
			if byEntry[b.entry] then
				onPlain += 1
			end
		end
		return missing, onPlain, extra, worst, best
	end
	local secs = {}
	for _, speed in { 40, 60, 100 } do
		local hints = ride(gen, { speed = speed, to = LENGTH - 400 })
		local missing, onPlain, extra, worst, best = judge(hints)
		local slack = T.QueryEvery + speed / 120 + 1e-6
		local secLo, secHi = math.huge, -math.huge
		for _, h in hints do
			secLo = math.min(secLo, h.seconds)
			secHi = math.max(secHi, h.seconds)
		end
		table.insert(secs, `{speed} studs/s: {fmt(secLo, 2)}-{fmt(secHi, 2)} s`)
		check(
			`at {speed} studs/s: one hint per true hairpin, none on plain bends, {T.Lead} studs before the zone`,
			missing == 0 and onPlain == 0 and extra == 0 and #hints == #pins and worst >= T.Lead - slack and best <= T.Lead + 1e-6,
			`{#hints} hints for {#pins} hairpins ({missing} missing, {extra} twice), {onPlain} on the {#plain} plain bends; {fmt(worst, 1)} to {fmt(best, 1)} studs before the zone, {fmt(secLo, 2)} to {fmt(secHi, 2)} s at that speed`
		)
	end
	table.insert(log, "seconds from the hint to the zone: " .. table.concat(secs, "; "))

	-- frame rate: the same hints at 30, 60 and 120 steps a second
	local sets = {}
	for _, hz in { 30, 60, 120 } do
		local hints = ride(gen, { speed = 60, hz = hz, to = LENGTH - 400 })
		local ids = {}
		for _, h in hints do
			table.insert(ids, fmt(h.entry, 0))
		end
		table.insert(sets, table.concat(ids, ","))
	end
	check("the same hints at 30, 60 and 120 steps a second", sets[1] == sets[2] and sets[2] == sets[3], `30: {sets[1]}; 60: {sets[2]}; 120: {sets[3]}`)

	-- the road laid only a little ahead, as live: still each hairpin, before its zone
	for _, ahead in { 900, 600 } do
		local g2 = SplineGen.new(SEED)
		g2:extendTo(ahead + 200)
		local hints, hinter = ride(g2, {
			speed = 60,
			to = LENGTH - 400 - ahead,
			grow = function(s)
				if g2.spline.length < s + ahead then
					g2:extendTo(s + ahead + 100)
				end
			end,
		})
		local missing, onPlain, extra, worst = 0, 0, 0, math.huge
		local seen = {}
		for _, h in hints do
			seen[h.entry] = true
			worst = math.min(worst, h.toZone)
		end
		for _, h in pins do
			if h.zone < LENGTH - 400 - ahead and not seen[h.entry] then
				missing += 1
			end
		end
		for _, b in plain do
			if seen[b.entry] then
				onPlain += 1
			end
		end
		check(
			`the road laid {ahead} studs ahead: every hairpin hinted, before its zone`,
			missing == 0 and onPlain == 0 and worst > 0,
			`{#hints} hints, {missing} missing, {onPlain} on plain bends; nearest {fmt(worst, 1)} studs before the zone; {hinter.stats.openSkips} looks found it not yet known`
		)
	end

	-- a put-back: driven back 400 studs just after a hint: nothing for `Quiet`, then the same
	-- hairpin again on the new pass; and a jump forward to just short of a zone: no hint
	do
		local h = pins[1]
		local jumped, jumpT = false, nil
		local hints = ride(gen, {
			speed = 60,
			from = h.zone - T.Lead - 100,
			until_ = h.exit,
			jump = function(s, t)
				if not jumped and s > h.zone - T.Lead + 20 then
					jumped, jumpT = true, t
					return -400
				end
				return nil
			end,
		})
		local first, second = hints[1], hints[2]
		local quietOk = second ~= nil and second.t - jumpT >= T.Quiet - 1e-6
		local jf = false
		local hintsF = ride(gen, {
			speed = 60,
			from = h.zone - T.Lead - 300,
			until_ = h.exit,
			jump = function(s)
				if not jf and s > h.zone - T.Lead - 250 then
					jf = true
					return 400 - 30 -- lands 30 studs before the zone, inside the lead
				end
				return nil
			end,
		})
		check(
			"a put-back: quiet for a moment, then a fresh pass hints again; landing near the zone, none",
			first ~= nil and second ~= nil and first.entry == h.entry and second.entry == h.entry and #hints == 2 and quietOk and #hintsF == 0,
			`back 400: {#hints} hints, the second {second and fmt(second.t - jumpT, 2) or "-"} s after the put-back (quiet {T.Quiet} s); forward to 30 short of the zone: {#hintsF} hints`
		)
	end

	-- the cost: one step
	do
		local hinter = HairpinHint.new({ spline = spline })
		local t0 = os.clock()
		local n = 0
		local s = 0
		while s < 12000 do
			hinter:Update(1 / 120, at(spline, s, 60))
			s += 0.5
			n += 1
		end
		local us = (os.clock() - t0) / n * 1e6
		check("cheap enough to step each simulation step", us < 60, `{fmt(us, 1)} microseconds a step, mean over {n} steps (a look ahead every {T.QueryEvery} studs)`)
	end

	-------------------------------------------------------------- 2. the line
	do
		local holder = Instance.new("ScreenGui")
		holder.Name = "__HintTest"
		local folder = Instance.new("Folder")
		local view = ScoreFeedView.new(folder)
		local VC = ScoreFeedView.Config
		-- not on a screen here (a test on the server): give it a desktop's width and no
		-- height cap, as `_layout` does on a 1280 x 720 screen
		view.width = VC.Width
		view.maxHeight = nil
		view.maxLines = VC.Lines

		view:setData(Fixtures.hairpinAhead)
		local d = view:describe()
		local hintLine
		for _, l in d.lines do
			if l.notice then
				hintLine = l
			end
		end
		check(
			"the fixture: HAIRPIN AHEAD, its way, an outline, no points, no underline, nothing Active",
			hintLine ~= nil and hintLine.name == "HAIRPIN AHEAD" and hintLine.points == "LEFT" and hintLine.outline == true and not hintLine.underline
				and not string.find(hintLine.points, "+", 1, true) and d.anyActive == false and #d.lines == 3 and d.lines[1].notice == "hairpinAhead",
			`{#d.lines} lines, newest first: {d.lines[1] and d.lines[1].name} / {d.lines[1] and d.lines[1].points}; outline {tostring(hintLine and hintLine.outline)}, underline {tostring(hintLine and hintLine.underline)}, any Active {tostring(d.anyActive)}`
		)
		view:setData(Fixtures.hairpinAheadRight)
		d = view:describe()
		check("turning right reads RIGHT", d.lines[1] and d.lines[1].points == "RIGHT", `{d.lines[1] and d.lines[1].name} / {d.lines[1] and d.lines[1].points}`)

		-- in time: it holds `NoticeHold`, then fades; a second one never merges into it
		view:clear()
		view:push({ id = "a", kind = "hairpinAhead", notice = "hairpinAhead", dir = 1, state = "banked", points = 0 })
		view:push({ id = "b", kind = "hairpinAhead", notice = "hairpinAhead", dir = -1, state = "banked", points = 0 })
		local two = #view:describe().lines
		view:step(VC.NoticeHold - 0.1)
		local during = #view:describe().lines
		view:step(0.2 + VC.Fade)
		local after = #view:describe().lines
		check(
			`it holds {VC.NoticeHold} s and fades; two never merge`,
			two == 2 and during == 2 and after == 0,
			`two pushed: {two} lines; at {VC.NoticeHold - 0.1} s: {during}; after the fade: {after}`
		)

		-- a full feed of live lines: the hint never pushes one out
		view:setData(Fixtures.hintOverLive)
		d = view:describe()
		local liveKept, liveFading = 0, 0
		for _, l in d.lines do
			if l.state == "live" then
				if l.fading then
					liveFading += 1
				else
					liveKept += 1
				end
			end
		end
		check("a full feed of live lines keeps every one", liveKept == 5 and liveFading == 0, `{liveKept} live lines kept, {liveFading} fading, of 5 (most {d.maxLines})`)

		view:destroy()
		folder:Destroy()
		holder:Destroy()
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks, log = table.concat(log, "\n") }
end

function HairpinHintTests.run()
	return runAll()
end

return HairpinHintTests
