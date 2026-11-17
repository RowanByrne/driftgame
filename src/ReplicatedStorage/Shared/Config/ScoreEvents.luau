--!strict
-- ScoreEvents: every number the score events are made of (docs/game/features/score-events.md,
-- T-293), and none of them in the logic. The engine is `Drift/ScoreEvents`; each detector is
-- a module in `Drift/Events/` with its own table here, under `Detectors`.
--
-- ALL OF THEM ARE STARTING GUESSES, to be tuned by driving. They are set against the drift
-- itself: a steady drift on the real car earns about 10 points a second at x1 (T-119).
--
-- THE THREE KINDS (the spec's "The two kinds" and "The user's revision"):
--   oneOff      a moment: `Base` points times the size's scale, times the rung, straight into
--               the score; `Kick` of a rung pushed onto the bar (at most one rung).
--   sustained   held: `Rate` points a second or a stud (`Per`) times the size's scale, times
--               the rung at that step, collect on the event's line; the bar fills at `Fill` a
--               second and does not drain. Banks on a clean finish, lost on finish(false), a
--               fall or a put-back. Past `MaxSeconds` it banks and a fresh line starts.
--   conditional the same handle as sustained; it banks only on finish(true), and adds `Static`
--               points (times the mean scale over the hold, times the rung) and `Kick` then.
--
-- THE SIZE'S SCALE: `SizeFloor + (1 - SizeFloor) * size`, size 0 .. 1 from the detector. A
-- floor of 0 makes the points proportional to the size (perfect hairpin: size 1 for a
-- 4-wheel drift, 0.5 for a 2-wheel one, so the 4-wheel level is worth twice).
--
-- THE WORDS: the line's label is the last of `Words` whose `at` the event has reached, by
-- its peak size (`WordsBy = "size"`) or its seconds held (`"seconds"`). A detector may
-- override it with `info.label`.

return {
	-- ----------------------------------------------------------------- shared rules
	-- Anti-farming. A repeat of the same kind started within its `RepeatWindow` is worth
	-- `RepeatFactor` of the one before it, compounding (x0.5, x0.25, ...).
	RepeatWindow = 10, -- seconds; a kind may set its own
	RepeatFactor = 0.5,
	-- The same spot: an event of the same kind started within `SameSpot` studs (flat) of
	-- one that started between `SameSpotGap` and `SameSpotWindow` seconds ago scores nothing
	-- (a crest jumped again by turning round and driving back). The gap lets a chain of the
	-- same thing in a row (lifts over a crest, trees side by side) count, cut only by the
	-- repeat rule.
	SameSpot = 40, -- studs
	SameSpotGap = 4, -- seconds
	SameSpotWindow = 60, -- seconds
	-- Forward only, as the drift: nothing counts while the car goes backwards along its nose
	-- (a kind may set `Forward = false`), slower than its `MinSpeed`, or pinned on a wall.
	MinSpeed = 20, -- studs/s, across the ground; a kind may set its own
	-- The ceiling: all event points together, before the rung, may not pass `MaxEventRate`
	-- a second averaged over `RateWindow` seconds. Points over it are cut, never owed. The
	-- spec's 60 over 5 s could not pay a single extreme conditional; this is the budget the
	-- largest one fits in. The server's bound, when a score is first saved, uses the same.
	MaxEventRate = 80, -- points a second at x1
	RateWindow = 10, -- seconds
	RateBin = 0.25, -- seconds a bin of the window's ring holds
	-- A fall (`state.fell`) or the car put back (a new state) loses every live event.
	VoidOnFall = true,
	-- How often a live line's growing points go to the feed, at most (seconds). Starts and
	-- ends always go at once.
	FeedEvery = 0.05,
	-- A held (sustained) line first goes to the feed once it has earned this many points,
	-- rung included. Less than that banks quietly, with no line: in a 5-minute drive 10 of
	-- 26 wheel lifts earned under a point, and each was a `+0` line.
	ShowPoints = 1,
	-- TEMPORARY, until the feed (T-296) draws them: each finished event printed to the
	-- console in Studio, `[ScoreEvents] JUMP +52 x2 banked`.
	PrintInStudio = true,
	-- Entries the debug log keeps.
	LogSize = 40,

	-- -------------------------------------------------------------------- the kinds
	-- `Difficulty` is the user's word for each (T-293); nothing reads it but people.
	Kinds = {
		-- The flight is the sustain (the user's revision): points a second of air, scaled by
		-- the height over the ground, growing the longer it flies (`Ramp`: the rate a second
		-- in is `Rate * (1 + Ramp)`).
		jump = {
			Mode = "sustained",
			Difficulty = "medium",
			Per = "second",
			Rate = 40,
			Ramp = 0.6,
			SizeFloor = 0.3,
			Fill = 0.6, -- of a rung a second
			MaxSeconds = 8,
			WordsBy = "seconds",
			Words = { { at = 0, text = "JUMP" }, { at = 1, text = "BIG AIR" }, { at = 2, text = "HUGE AIR" } },
		},
		-- Easy, small. Size 0.4 for one wheel up, 1 for both wheels on one side (the
		-- detector's), so 0.12 and 0.3 points a stud: about a drift's rate at 80 studs/s.
		wheelLift = {
			Mode = "sustained",
			Difficulty = "easy",
			Per = "stud",
			Rate = 0.3,
			SizeFloor = 0,
			Fill = 0.25,
			MaxSeconds = 6,
			RepeatWindow = 4,
			WordsBy = "size",
			Words = { { at = 0, text = "WHEEL LIFT" }, { at = 0.75, text = "TWO WHEELS" } },
		},
		-- Sort of hard, medium (T-297 detects it).
		bumperGrind = {
			Mode = "sustained",
			Difficulty = "medium",
			Per = "stud",
			Rate = 0.25,
			SizeFloor = 0.5,
			Fill = 0.35,
			MaxSeconds = 15,
			WordsBy = "size",
			Words = { { at = 0, text = "BUMPER GRIND" } },
		},
		-- Difficult, big (T-297).
		hangGrind = {
			Mode = "sustained",
			Difficulty = "hard",
			Per = "stud",
			Rate = 0.5,
			SizeFloor = 0.5,
			Fill = 0.5,
			MaxSeconds = 10,
			WordsBy = "size",
			Words = { { at = 0, text = "HANG GRIND" } },
		},
		-- Easy; trees only; the closer, the bigger (T-298). Size 1 is a graze.
		nearMiss = {
			Mode = "oneOff",
			Difficulty = "easy",
			Base = 100,
			SizeFloor = 0.25, -- 25 points at the edge of the range, 100 at a graze
			Kick = 0.4,
			RepeatWindow = 6,
			WordsBy = "size",
			Words = { { at = 0, text = "NEAR MISS" }, { at = 0.5, text = "CLOSE CALL" }, { at = 0.85, text = "PAINT SWAP" } },
		},
		-- Medium. Conditional: drift the whole hairpin on your own side (T-299). Size 1 for
		-- a 4-wheel drift, 0.5 for a 2-wheel one; the floor of 0 makes the 4-wheel level
		-- worth twice, while held and at the finish.
		perfectHairpin = {
			Mode = "conditional",
			Difficulty = "medium",
			Per = "second",
			Rate = 15,
			SizeFloor = 0,
			Fill = 0.3,
			Static = 150,
			Kick = 0.5,
			WordsBy = "size",
			Words = { { at = 0, text = "PERFECT HAIRPIN" }, { at = 0.75, text = "PERFECT HAIRPIN 4W" } },
		},
		-- Extreme (T-299).
		scandiFlick = {
			Mode = "conditional",
			Difficulty = "extreme",
			Per = "second",
			Rate = 20,
			SizeFloor = 0.5,
			Fill = 0.5,
			Static = 600,
			Kick = 1,
			WordsBy = "size",
			Words = { { at = 0, text = "SCANDINAVIAN FLICK" } },
		},
		-- Hard: past 90 degrees into the hairpin, so it counts going backwards (T-299).
		reverseEntry = {
			Mode = "conditional",
			Difficulty = "hard",
			Per = "second",
			Rate = 15,
			SizeFloor = 0.5,
			Fill = 0.4,
			Static = 350,
			Kick = 0.7,
			Forward = false,
			WordsBy = "size",
			Words = { { at = 0, text = "REVERSE ENTRY" } },
		},
	},

	-- ---------------------------------------------------------------- the detectors
	Detectors = {
		-- `Drift/Events/Jump`: all four wheels off the ground (`state.airborne`) for `MinAir`
		-- seconds starts it -- a bump or the tarmac's 1-stud edge is shorter -- and those
		-- seconds count. It banks once the car has been back down `LandSettle` seconds; a
		-- second hop inside that is the same jump. Lost on a fall, a put-back, landing tilted
		-- past `LandTiltDeg` (on its side or roof), or a wall touched in the air or on landing.
		Jump = {
			MinAir = 0.4, -- seconds
			LandSettle = 0.2, -- seconds
			LandTiltDeg = 60,
			VoidOnWall = true,
			FullHeight = 12, -- studs over the ground under the car for size 1
		},
		-- `Drift/Events/WheelLift`: on the ground, not hanging on the floor, with one or two
		-- wheels off it (not three) for `MinHold`; a gap up to `Grace` does not end it.
		WheelLift = {
			MinHold = 0.15, -- seconds
			Grace = 0.1, -- seconds
			OneWheelSize = 0.4,
			TwoWheelSize = 1, -- both wheels on one side
			OtherTwoSize = 0.4, -- two that are not one side (an axle, a diagonal)
		},
		-- `Drift/Events/NearMiss` (T-298): passing a grove tree's trunk (`Road/SplineGrove`)
		-- closer than `Threshold` studs of gap (the car's body box to the trunk's circle) at
		-- `MinSpeed` or more, moving forward, touching nothing then or for `Confirm` after.
		-- Size 0 at `Threshold`, 1 at `FullGap` and closer. Once per tree per pass. Trees
		-- stand 16+ studs past the tarmac, only in groves: rare by the user's choice.
		NearMiss = {
			Threshold = 3, -- studs of gap
			FullGap = 0.5, -- studs: size 1 here and closer
			MinSpeed = 50, -- studs/s, flat, at the closest moment
			TouchGap = 0.1, -- studs: this close is a touch (the collision holds a car 0.05 clear)
			Confirm = 0.5, -- seconds after the pass with no wall touched
			Open = 1.5, -- studs the gap opens past its closest for the pass to be over
			Rearm = 5, -- seconds before the same tree can have another pass
			Watch = 10, -- studs: passes under this are measured (DebugState's histogram)
			Window = 30, -- studs of road each side of the car the trunks are fetched over
			Refetch = 8, -- studs the car moves along before they are fetched again
			Teleport = 30, -- studs in one step past its speed: a put-back, all forgotten
		},
		-- `Drift/Events/BumperGrind` (T-297): a front or rear corner on a K-rail (the model's
		-- `wallKind`, `wallPoint`), the car at least `MinAngle` off the rail's line (less is its
		-- door), sliding along it at `MinSpeed`, met gently (`MaxInto`). It starts on a meeting
		-- at least `MinHold` after the first, banks `Grace` after the car leaves the rail, and is
		-- lost on a hard hit, losing `CrashLoss` of the speed within `CrashWindow`, a fall or a
		-- put-back. Size: the speed along the rail (`SizeFloor` at `MinSpeed`, 1 at `FullSpeed`)
		-- times the share of the last `SteadySeconds` the car read as touching it.
		BumperGrind = {
			Walls = { krail = true, rock = false }, -- rock cuts are not the user's "barrier rail"
			MinAngle = 6, -- degrees
			MinSpeed = 40, -- studs/s along the rail to start
			KeepSpeed = 30, -- studs/s along it to keep going
			FullSpeed = 100, -- studs/s along it for the speed's full share
			SizeFloor = 0.3,
			MaxInto = 25, -- studs/s into the rail at a meeting; harder is a crash
			MinHold = 0.12, -- seconds
			MinContacts = 2, -- steps that met the rail within the hold
			Grace = 0.25, -- seconds off the rail before it ends
			CrashLoss = 0.4, -- share of the speed
			CrashWindow = 0.35, -- seconds
			SteadySeconds = 0.4, -- seconds
			PutBack = 30, -- studs moved in one update past where the car could get
		},
	},
}
