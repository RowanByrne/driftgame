--!strict
-- SAMPLE DATA, not game state: feed entries for `ScoreFeedView`, for previewing and measuring
-- the score feed without driving to each event (docs/workflow/UI.md "Each screen is a view").
-- Entries have the engine's shape (features/score-events.md "The shared interface"):
-- `{ id, kind, label, points, state = "live" | "banked" | "void", rung }`, `points` the
-- event's total so far, the rung already in it.
--
-- Two sorts:
--   { entries = { ... }, hold = true }  a still picture: pushed at once, settled, never fading
--   { script = { { at = s, entry }, ... } }  played in time, as the engine would fire them
-- `ScoreController:DebugFeedFixture(name)` plays either.

type Entry = { [string]: any }

local function e(id: number, kind: string, label: string, points: number, state: string, rung: number?): Entry
	return { id = id, kind = kind, label = label, points = points, state = state, rung = rung or 1 }
end

-- A sustained event counting up from `t0` to `t1`, `steps` updates, then ending `finish`.
local function ramp(out: { Entry }, id: number, kind: string, label: string, total: number, t0: number, t1: number, finish: string?)
	local steps = math.max(1, math.floor((t1 - t0) * 10))
	for i = 0, steps do
		local k = i / steps
		local entry = e(id, kind, label, math.floor(total * k), "live", 2)
		entry.at = t0 + (t1 - t0) * k
		table.insert(out, entry)
	end
	if finish then
		local entry = e(id, kind, label, total, finish, 2)
		entry.at = t1 + 0.05
		table.insert(out, entry)
	end
end

-- A notice (T-304): "HAIRPIN AHEAD", turning `dir` (1 left, -1 right). No points.
local function hint(id: string, dir: number): Entry
	return { id = id, kind = "hairpinAhead", notice = "hairpinAhead", dir = dir, state = "banked", points = 0 }
end

local function at(t: number, entry: Entry): Entry
	entry.at = t
	return entry
end

local function sorted(list: { Entry }): { Entry }
	table.sort(list, function(a, b)
		return a.at < b.at
	end)
	return list
end

-- ----------------------------------------------------------------------------- scripts

-- A one-off near miss pops in, holds 2.5 s, fades.
local nearMissPop = { at(0, e(1, "nearMiss", "CLOSE CALL", 75, "banked")) }

-- A bumper grind held 3 s counting up live, then banked: flash, glide, fade.
local grindLive = {}
ramp(grindLive, 1, "bumperGrind", "BUMPER GRIND", 640, 0, 3, "banked")

-- A perfect hairpin (conditional) held, then completed.
local hairpinBanked = {}
ramp(hairpinBanked, 1, "perfectHairpin", "PERFECT HAIRPIN", 900, 0, 2.5, "banked")

-- The same, failed: crossed the double yellow. Red, LOST, struck through.
local hairpinVoid = {}
ramp(hairpinVoid, 1, "perfectHairpin", "PERFECT HAIRPIN", 520, 0, 2, "void")

-- One line for a bend's events (T-299): it counts up live as PERFECT HAIRPIN, then banks
-- upgraded to the best version completed, PERFECT LANE DRIFT, with the combined points.
local bendUpgrade = {}
ramp(bendUpgrade, 1, "perfectHairpin", "PERFECT HAIRPIN", 760, 0, 3)
table.insert(bendUpgrade, at(3.05, e(1, "perfectLaneDrift", "PERFECT LANE DRIFT", 2240, "banked", 4)))

-- Several at once: a grind live, a wheel lift starting under it, three near misses merging
-- into one line, a jump landing, the lift lost to a fall.
local stacking = {}
ramp(stacking, 1, "bumperGrind", "BUMPER GRIND", 820, 0, 4, "banked")
ramp(stacking, 2, "wheelLift", "WHEEL LIFT", 160, 0.8, 2.6, "void")
table.insert(stacking, at(1.0, e(3, "nearMiss", "NEAR MISS", 50, "banked")))
table.insert(stacking, at(1.6, e(4, "nearMiss", "NEAR MISS", 60, "banked")))
table.insert(stacking, at(2.2, e(5, "nearMiss", "NEAR MISS", 45, "banked")))
ramp(stacking, 6, "jump", "BIG AIR", 380, 2.8, 3.8, "banked")
sorted(stacking)

-- A long run: twelve events over 9 s, more than the feed holds, so the oldest finished
-- lines are pushed out while a long hang grind stays.
local longRun = {}
ramp(longRun, 1, "hangGrind", "HANG GRIND", 2400, 0, 7, "banked")
local kinds = {
	{ "nearMiss", "NEAR MISS", 40 },
	{ "jump", "JUMP", 120 },
	{ "wheelLift", "WHEEL LIFT", 60 },
	{ "nearMiss", "CLOSE CALL", 90 },
	{ "bumperGrind", "BUMPER GRIND", 300 },
	{ "jump", "HUGE AIR", 610 },
	{ "reverseEntry", "REVERSE ENTRY", 700 },
	{ "nearMiss", "PAINT SWAP", 140 },
	{ "wheelLift", "TWO WHEELS", 110 },
	{ "scandiFlick", "SCANDI FLICK", 1500 },
	{ "perfectHairpin", "PERFECT HAIRPIN", 900 },
}
for i, k in kinds do
	table.insert(longRun, at(0.3 + i * 0.7, e(10 + i, k[1], k[2], k[3], "banked", 3)))
end
sorted(longRun)

-- A drift counting up live; "HAIRPIN AHEAD" comes in over it, holds 2 s and fades while the
-- drift's line carries on; then the bend's line starts.
local hairpinHint = {}
ramp(hairpinHint, 1, "wheelLift", "WHEEL LIFT", 90, 0, 4, "banked")
table.insert(hairpinHint, at(0.5, hint("hint:demo", -1)))
ramp(hairpinHint, 2, "perfectHairpin", "PERFECT HAIRPIN", 400, 3.0, 5.5, "banked")
sorted(hairpinHint)

-- ------------------------------------------------------------------------------ stills

return {
	-- Nothing yet.
	empty = { entries = {}, hold = true },

	-- One of each kind, banked: two pictures, as no screen holds all eight at once.
	kindsA = {
		hold = true,
		entries = {
			e(1, "jump", "BIG AIR", 420, "banked", 2),
			e(2, "wheelLift", "WHEEL LIFT", 64, "banked"),
			e(3, "bumperGrind", "BUMPER GRIND", 312, "banked", 3),
			e(4, "hangGrind", "HANG GRIND", 880, "banked", 4),
			e(5, "nearMiss", "CLOSE CALL", 75, "banked"),
		},
	},
	kindsB = {
		hold = true,
		entries = {
			e(1, "perfectHairpin", "PERFECT HAIRPIN", 1200, "banked", 2),
			e(2, "scandiFlick", "SCANDI FLICK", 2600, "banked", 3),
			e(3, "reverseEntry", "REVERSE ENTRY", 950, "banked", 3),
		},
	},

	-- Three near misses merged into one line.
	merged = {
		hold = true,
		entries = {
			e(1, "nearMiss", "NEAR MISS", 50, "banked"),
			e(2, "nearMiss", "NEAR MISS", 60, "banked"),
			e(3, "nearMiss", "NEAR MISS", 45, "banked"),
		},
	},

	-- A live sustained line at a huge total, underline on.
	liveBig = { hold = true, entries = { e(1, "hangGrind", "HANG GRIND", 1234567, "live", 9) } },

	-- Five lines, one lost.
	fiveWithLost = {
		hold = true,
		entries = {
			e(1, "jump", "JUMP", 120, "banked"),
			e(2, "nearMiss", "NEAR MISS", 40, "banked"),
			e(3, "wheelLift", "WHEEL LIFT", 220, "void", 2),
			e(4, "bumperGrind", "BUMPER GRIND", 540, "live", 2),
			e(5, "perfectHairpin", "PERFECT HAIRPIN", 1100, "banked", 3),
		},
	},

	-- The longest name with the largest points, banked and lost, and merged.
	longest = {
		hold = true,
		entries = {
			e(1, "scandiFlick", "SCANDINAVIAN FLICK", 98765432, "banked", 9),
			e(2, "scandiFlick", "SCANDINAVIAN FLICK", 98765432, "void", 9),
			e(3, "perfectHairpin", "PERFECT HAIRPIN", 98765, "live", 9),
		},
	},

	-- The hint (T-304): one each way, over a scored line, banked and live.
	hairpinAhead = {
		hold = true,
		entries = {
			e(1, "jump", "BIG AIR", 420, "banked", 2),
			e(2, "bumperGrind", "BUMPER GRIND", 312, "live", 3),
			hint("hint:left", 1),
		},
	},
	hairpinAheadRight = { hold = true, entries = { hint("hint:right", -1) } },
	-- A full feed of live lines (5, or 3 on a phone) and a hint: no live line is pushed out.
	hintOverLive = {
		hold = true,
		entries = {
			e(1, "bumperGrind", "BUMPER GRIND", 640, "live", 2),
			e(2, "wheelLift", "WHEEL LIFT", 80, "live", 2),
			e(3, "hangGrind", "HANG GRIND", 900, "live", 2),
			e(4, "jump", "JUMP", 220, "live", 2),
			e(5, "perfectHairpin", "PERFECT HAIRPIN", 300, "live", 2),
			hint("hint:full", 1),
		},
	},

	-- In time.
	hairpinHint = { script = hairpinHint },
	nearMissPop = { script = nearMissPop },
	grindLive = { script = grindLive },
	hairpinBanked = { script = hairpinBanked },
	hairpinVoid = { script = hairpinVoid },
	bendUpgrade = { script = bendUpgrade },
	stacking = { script = stacking },
	longRun = { script = longRun },
}
