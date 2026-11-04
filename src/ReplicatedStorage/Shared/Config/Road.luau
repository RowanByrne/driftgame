--!strict
-- Road: every number the endless road is made of, and none of them in the logic
-- (docs/game/features/track-generation.md, docs/workflow/CODING.md "Foundation kit").
--
-- NAMING. The road is the game's THIRD world and it is called the Road, never the Track:
-- `Services/TrackService` already means something else entirely -- the hand-placed kart
-- circuit that lives only in `DR-Main` and that git never sees. Nothing here touches it.
--
-- The three worlds, and where each is (docs/game/WORLD.md "The three worlds"):
--   the hand-placed track   at the origin, where its author put it
--   the playground          at `Config.Drift.PlaygroundOffsetFromTrack`, edge to edge
--                           with the track's baseplate so a car can drive between them
--   the ROAD                at `Offset` below, far from both, because it is not a place
--                           on a plate: it grows away from its start for as long as the
--                           run lasts and must never be able to reach the other two
--
-- A PIECE IS BUILT FROM NUMBERS, not modelled: radius, arc, width and length are here
-- and a builder (`Shared/Road/Builder`) turns them into anchored boxes. So the whole road
-- set is text in git and a corner's radius changes in a commit.

return {
	-- --------------------------------------------------------------- where the road is
	-- The start socket of piece 1, in world space. `Offset` and nothing else decides
	-- where this world sits, exactly as `PlaygroundOffsetFromTrack` does for the
	-- playground, so the generator's own maths can stay written about its own origin.
	--
	-- WHY -20 000 ON Z. The other two worlds sit between x -3 024 and x +1 024 and never
	-- leave z +/-1 024; the collision tests stand their rig at (20 000, 500, 20 000) and
	-- the jitter tests probe at (2 000, 0, 0). -Z is empty, and nothing else in the game
	-- ever offsets Z. 20 000 studs is about 110 seconds at this car's top speed, and the
	-- road's live window is at most about 14 pieces -- a few thousand studs -- so a run
	-- cannot wander out of its own quarter in any play session.
	Offset = Vector3.new(0, 0, -20000),
	StartHeading = 0, -- degrees; 0 faces -Z, the same convention as the playground's Path

	-- ------------------------------------------------------------------- the road itself
	-- WIDTH IS THE USER'S NUMBER (docs/game/DECISIONS.md, 2026-11-04). The car is 14.83
	-- studs long and 7.14 wide as it is actually built, so 50 studs is 7.0 car widths.
	-- It was 35 -- 4.9 car widths -- until the user drove it and asked for 50; the
	-- barriers stay exactly as they were. The car is NOT rescaled to the road and the
	-- road is NOT rescaled to the car.
	--
	-- IT IS NOT ONLY A LOOK, it is the generator's hardest number. `footprintHalfWidth`
	-- is `Width / 2 + BarrierThickness - OverlapSlack`, so every piece's footprint grew
	-- from 18.25 to 25.75 studs either side -- 15 studs wider overall -- and two pieces
	-- that used to pass each other now collide. The road therefore traps itself MORE
	-- easily at 50 than at 35, which is the opposite direction to the stall work in
	-- T-052, and the stall table in `features/track-generation.md` is measured at 50 for
	-- that reason.
	Width = 50, -- studs, kerb to kerb
	Thickness = 12, -- studs of slab under the surface. Buried: nothing ever sees its sides
	-- except at the very first and very last piece of a run
	SurfaceY = 0, -- world Y of the road's top WHERE IT HAS NO PROFILE: the zero every
	-- piece's height is measured from, exactly as `baseY` is for the
	-- playground's ribbons. Every one of the nine pieces below is flat, so
	-- today this is the whole of the road's height

	-- ------------------------------------------------------------------ height and bank
	-- A PIECE MAY START AT ONE HEIGHT AND FINISH AT ANOTHER, and may be banked across its
	-- width (features/road-elevation.md, T-066). The capability is here; the pieces that
	-- use it are not yet, so these five numbers bound what any piece may ask for rather
	-- than describing anything the road currently does.
	--
	-- WHAT MAKES THEM LIMITS AND NOT WISHES: a piece's height is summed from its grade
	-- AFTER the grade has been clamped (`Road/Pieces.applyProfile`), and its node count is
	-- read off the swing its profile needs (`profileSegments`). A piece that asks for more
	-- drop than `MaxGrade` allows gets the grade and lands higher than it wanted, rather
	-- than getting a wall.
	--
	-- THE SPEC SAID 14 DEGREES AND THE CAR SAYS 8, which is a measured result and not a
	-- preference. `features/road-elevation.md` picked 0.25 of grade -- 14.04 degrees --
	-- against the 46 degrees at which `Drift/World` calls a surface a wall. That is not
	-- the binding limit. The binding limit is THE CAR'S OWN COLLISION BOX, which is
	-- `BodyLength` long, `BodyHeight x 0.6` tall and NEVER PITCHED: it is swept flat
	-- through the world whatever the road is doing. So it rides `RideHeight` up with
	-- 1.44 studs of air under it and 7 studs of nose in front of it, and on a climb
	-- steeper than about atan(1.44 / 7) the nose is INSIDE the road ahead. The sweep sorts
	-- what it finds by the normal; the face it meets there is vertical, so it is a WALL,
	-- and the car stops dead against the hill it is driving up.
	--
	-- Measured, with gravity on the ground (T-065). A straight ramp at each grade, entered
	-- at 90 studs/s, 14 seconds of throttle and no steering:
	--
	--   grade    climbed in 14 s    speed at the end    what happened
	--     4 deg      70 studs           129 studs/s     climbs freely
	--     6         101                 121             climbs freely
	--     8         136                 116             climbs freely
	--    10         149                 103             climbs freely
	--    12          23                   0             STOPPED DEAD on the ramp
	--    14          26                   5             stopped dead
	--
	-- The break lands either side of the 11.6 the geometry predicts, which is the check
	-- that the explanation is the right one. (Before gravity it broke between 8 and 10
	-- instead, because the car was 25 studs/s faster and the box is swept a step's TRAVEL
	-- further forward as well.)
	--
	-- THAT HAS BEEN FIXED (T-073). The sweep box is posed on the surface under the car
	-- now, so the nose no longer digs into the hill it is climbing, and the whole table
	-- above belongs to history. Re-measured the same way with the tilted box:
	--
	--   grade    what happened
	--    12 deg   climbs freely, out at 123 studs/s   (used to STOP DEAD)
	--    20       climbs freely, out at 93
	--    24       climbs freely, out at 74
	--    25       stops -- and ONE touching step, against the audit's zero
	--
	-- So the binding limit is no longer the collision box at all: it is THE CAR'S POWER.
	-- It climbs 24 degrees and cannot climb 25, and that is gravity against the drivetrain,
	-- not a wall. An exhaustive audit -- the car placed at 25 points on every slab of a
	-- generated road, five headings each, about 16 000 sweeps a row -- read road as a wall
	-- ZERO times at every grade from 8 to 35. The flat box read 267 to 2 750 a row.
	--
	-- 20 AND NOT 24, for the margin: 24 is the last grade that works and leaves nothing,
	-- and a descent before a climb arrives faster than the test's 90 studs/s.
	--
	-- A DESCENT IS NOT LIMITED BY THIS directly: the ground falls away in front of the car
	-- and nothing is swept into. The limit is symmetric anyway, because a car that spins
	-- on a steep descent is then facing up it and can never drive out -- which is how the
	-- original 8 was found.
	--
	-- AND A WARNING FOR WHOEVER BUILDS THE PIECES THAT USE THIS. 8 degrees is what the car
	-- can be driven ON; it is not what a road should be made of. A road of nothing but
	-- descending corners, driven by the test autopilot (`RoadTests:drive`, 12 pieces, 120
	-- seconds, one seed, each corner 220 studs of radius and 90 degrees of it, each losing
	-- its height and handing on a level road):
	--
	--   the corner descends at   pieces reached   mean speed   top speed   stopped for
	--     nothing (flat)              12            59 studs/s    92           0.00 s
	--     4 degrees                   12            68            93          0.00
	--     8 degrees                   10            36           120          1.75
	--
	-- None of that is the road failing: traced, the sweep was stopped by ROAD zero times
	-- at both grades. It is the car going FASTER down a hill -- 120 against 92 -- while
	-- the test driver's aim was tuned on a flat road, so it runs wide and grinds along the
	-- outside wall. That is the feature working and the driver not keeping up. Build a
	-- touge out of 4-degree descents and level links before reaching for 8.
	--
	-- THAT WARNING STANDS, AND 20 MAKES IT LOUDER. This is a safety lid -- the steepest
	-- road the car can physically be on -- and not a number any piece should go near. The
	-- drivable range is still the single digits: a fall test drive down an ordinary
	-- descent touched 245 studs/s against the flat road's 106 (T-067), which is well past
	-- what anyone can place a drift at. Whoever builds the touge pieces picks real grades
	-- from driving, and they will be nearer 4 than 20.
	MaxGrade = 20, -- degrees of climb or descent, anywhere on any piece. A SAFETY LID, not
	-- a target: see the warning above. A 220-stud straight at this grade loses 75 studs
	-- THE SAME THING IN THE OTHER AXIS, AND THE SPEC'S 30 BECOMES 20. The collision box is
	-- never ROLLED either, so on a bank its uphill side digs in: half the car's width is
	-- 3.2 studs, the clearance is the same 1.44, and atan(1.44 / 3.2) is 24 degrees. Above
	-- that the car's own box is inside the high side of the road, and every little step
	-- between two segments at the road's edge -- a bank changing by `MaxBankStep` tips a
	-- 50-stud road's edge by a quarter of a stud -- becomes a face it can hit. The sweep
	-- calls a face a WALL and stops the car dead.
	--
	-- Measured the same way, two seeds, with every sweep that stopped the car traced back
	-- to the part that stopped it:
	--
	--   bank     ROAD read as a wall   barriers hit   stopped for   pieces reached
	--   10 deg           0 times           14           0.00 s          12/12, 12/12
	--   15               0                 17           0.00            12/12, 12/12
	--   20               0                 12           0.00            12/12, 12/12
	--   25               1                 13           0.40            12/12, 12/12
	--   30              17                  8           5.19            12/12, 12/12
	--
	-- Zero up to 20, one at 25, seventeen at 30 -- which brackets the 24 degrees the
	-- geometry predicts, so the explanation was the right one.
	--
	-- AND THAT IS ALSO FIXED (T-073), by the same one change: the box is rolled onto the
	-- surface as well as pitched. Re-measured, two seeds of a 12-piece road of banked
	-- corners, with every sweep that stopped the car traced to the part that stopped it:
	--
	--   bank    before (flat box)              after (tilted box)
	--   20 deg   5/12 and 4/12 pieces,          12/12 and 12/12, 0 road walls, 0.00 s
	--            stopped 96 s and 110 s
	--   30       3/12 both seeds, ~100 s        12/12 and 9/12, 0.63 s and 0.46 s slow
	--
	-- The exhaustive audit read road as a wall ZERO times at 20, 25 and 30 degrees of
	-- bank, and 10 times in 19 390 sweeps at 35. So 30 is clean and 35 is not.
	--
	-- 30 IS THE SPEC'S SHOWCASE PIECE BACK: `features/road-elevation.md` asks for "a
	-- 30-degree turn with big banking", which 20 could not give.
	MaxBank = 30, -- degrees across the road
	-- NOTHING MAY READ AS A WALL, and the two of them COMPOUND -- a banked descent is
	-- steeper than either alone. The surface normal's Y is exactly cos(grade) x cos(bank),
	-- so the pair is capped as well as each one separately: at 8 and 20 the product is
	-- 0.9903 x 0.9397 = 0.9305, a surface leaning 21.5 degrees.
	--
	-- `Drift/World` calls anything whose normal leans more than about 46 degrees
	-- (`GROUND_NORMAL_Y = 0.7`) a WALL: its ground rays step past it and the car stops
	-- dead against it instead of driving on it. 35 degrees leaves the normal at 0.819,
	-- which is 11 degrees and 0.12 of normal clear of that threshold -- room for the
	-- rounding in a chord's own slope, and nowhere near enough to be felt.
	--
	-- IT IS NO LONGER A BACKSTOP: IT IS THE THING ACTUALLY HOLDING THE LINE (T-073). It
	-- was written when 8 and 20 came to 21.5 together and nothing could reach 35. Now 20
	-- of grade and 30 of bank come to 35.5, so at both maxima at once this lid bites and
	-- trims the bank back to 29.4 degrees. That is the right behaviour and it is why this
	-- number is not being raised with the other two: the audit found road reading as a
	-- wall 10 times in 19 390 sweeps at 35 degrees of bank, so 35 is where the evidence
	-- runs out.
	MaxSurfaceTilt = 35, -- degrees the surface may lean, grade and bank together
	-- HOW MUCH EITHER MAY CHANGE IN ONE SEGMENT, which is `MaxSegmentChord` and
	-- `MaxArcDeviation`'s idea in the other two axes: a segment is one flat box, so a
	-- piece is cut into enough of them that its whole pitch and bank swing is shared out
	-- and no single joint is a step or a kink. A profiled piece is therefore cut more
	-- finely than a flat one -- a flat straight is ONE box however long it is, and a
	-- straight that has to unwind a 30-degree bank is twenty.
	MaxPitchStep = 1.15, -- degrees of grade change between neighbouring segments. The
	-- spec's 0.02 of grade is 1.15 degrees
	MaxBankStep = 1.5, -- degrees of bank change between neighbouring segments
	MaxProfileSegments = 64, -- and the ceiling on what those two may ask for, so a profile
	-- written carelessly costs a piece a few more parts rather than
	-- hundreds. A hairpin is 30 segments and 90 parts today

	-- HOW FINELY A CURVE IS CUT INTO STRAIGHT SEGMENTS. The car does not use Roblox
	-- physics -- it finds the ground with four downward rays -- so a curve made of short
	-- chords is PHYSICALLY identical to a smooth one while each chord is short next to the
	-- wheelbase (9.6 studs). It is purely a question of how it looks, and the deviation
	-- from the true arc is chord^2 / (8 x radius): at 13 studs that is 0.14 studs on a
	-- 150-stud corner and 0.07 on a 320-stud one. A tenth of a stud is invisible at
	-- 95 studs/s. A STRAIGHT IS ONE PART however long it is, because it is straight.
	MaxSegmentChord = 13, -- studs
	-- AND THE DEVIATION ITSELF IS CAPPED, because the chord is only a proxy for it. Step
	-- 1 had nothing tighter than a 220-radius corner, where 13 studs of chord is 0.093
	-- studs off the arc; the hairpin below is radius 70, where the same chord is 0.299 --
	-- three times as far out, on the one piece where the car is slowest, closest to the
	-- barriers and most able to see it. So a curve is cut by whichever of the two limits
	-- bites: chord <= sqrt(8 x radius x MaxArcDeviation) as well as <= MaxSegmentChord,
	-- which takes the hairpin from 17 segments to 27 and costs about thirty parts.
	MaxArcDeviation = 0.1, -- studs the built curve may fall inside the true arc

	-- --------------------------------------------------------------------- the barriers
	-- Low walls down both edges, solid, programmer-grey. NOT scenery and NOT tagged:
	-- the ground rays filter to an INCLUDE list of `DriftSurface` parts, so a barrier is
	-- not low-grip ground, it is not ground at all -- which is what makes it a wall.
	BarrierHeight = 6, -- studs above the road
	BarrierThickness = 2, -- studs
	BarrierSink = 1, -- studs the wall drops into the slab, so no edge-on view shows daylight

	-- --------------------------------------------------------------------- the markings
	-- WHY THERE ARE MARKINGS AT ALL: on smooth plastic a player cannot tell 40 studs/s
	-- from 120 (the user, 2026-11-04). A flat colour has nothing in it to stream past the
	-- camera, so the road reads as a static plane however fast the car is going. Marks
	-- laid at a fixed WORLD interval fix that exactly: the rate they pass the car is the
	-- car's speed in studs per second divided by `MarkInterval`, and nothing else --
	-- not the piece length, not the corner radius, not how finely a curve is segmented.
	--
	-- A MARKING IS DECORATION AND NOTHING ELSE. It is never tagged `DriftSurface`, so
	-- the ground rays cannot see it, and it is `CanCollide = false` and `CanQuery = false`
	-- so nothing else can either. The drift model is unchanged by anything in here.
	--
	-- THE INTERVAL IS THE WHOLE POINT, so it is chosen against the speeds the car really
	-- does (40..120 studs/s, `features/track-generation.md`): at 24 studs a mark passes
	-- 4.6 times a second at 110 studs/s and 1.7 at 40 -- fast enough to read as motion at
	-- the top end, slow enough to count at the bottom. Shorter and the top end blurs into
	-- a line; longer and the bottom end stops moving.
	MarkInterval = 24, -- studs of road between one dash starting and the next
	MarkDashLength = 10, -- studs of painted dash in each of those (so 14 studs of gap)
	MarkWidth = 1.6, -- studs across. A real centre line next to a 50-stud road
	MarkThickness = 0.4, -- studs tall. Mostly buried: only `MarkLift` of it is above the
	-- road, the rest is inside the slab so no edge-on view shows a kerb
	MarkLift = 0.02, -- studs the painted face sits above `SurfaceY`. Enough that the two
	-- faces never z-fight, far too little for a wheel to notice (the
	-- car rides 2+ studs up and rays to the slab, not to this)
	-- DASHES STRADDLING A JOIN ARE CLIPPED, NOT SKIPPED. The interval is measured along
	-- the whole run, so a dash that runs off the end of one piece is finished at the
	-- start of the next -- the two halves meet flush because the sockets do. Skipping it
	-- instead would leave one double-length gap at every join, which is the one
	-- irregularity a player would actually see.
	MarkMinLength = 0.05, -- studs. A clipped stub shorter than this is not worth a part

	-- ------------------------------------------------------------- what the road is made of
	-- Built-in materials only -- no uploaded textures anywhere in this game yet (art
	-- approval is the user's and has not happened, `docs/workflow/ART-PIPELINE.md`).
	-- Roblox projects a material's grain in WORLD space, so asphalt on the slab streams
	-- past the car for free: no parts, no ids, and it works at every speed. It is the
	-- floor under the markings, not a substitute for them -- grain this fine reads as
	-- texture, not as motion, which is why the dashes carry the speed cue.
	RoadMaterial = Enum.Material.Asphalt,
	BarrierMaterial = Enum.Material.Concrete, -- the walls, for the same reason: peripheral
	-- vision gets something that is not a flat colour

	-- ------------------------------------------------------------------------ the window
	-- The world stays about `AheadPieces + BehindPieces` pieces big however long the run
	-- lasts, which is why `StreamingEnabled` can stay off (docs/game/ARCHITECTURE.md).
	AheadPieces = 10, -- built in front of the car
	BehindPieces = 4, -- kept behind it before the oldest is destroyed
	BarrierBehind = 2, -- where the closing barrier sits, in pieces behind the car

	-- ---------------------------------------------------------------------- the lookahead
	-- A generator that only checks the next piece eventually places one that leaves
	-- nowhere to go. Before committing, it searches this many pieces deep, depth-first in
	-- the preference order, and accepts a first piece only if it has a legal continuation
	-- that far. If nothing is legal, NOTHING IS PLACED and it says so loudly.
	--
	-- THE SPEC SAID 5 AND 5 IS NOT ENOUGH, which is a measured result and not an opinion.
	-- With step 1's two piece types a 90-degree corner whose radius equals the straight's
	-- length put the whole road on a 220-stud square lattice, and a self-avoiding walk on
	-- a square lattice traps itself: four corners the same way close a ring exactly, and
	-- then every exit runs along road that is already there. Measured then, 40 runs of 400
	-- pieces: depth 3 stalled 35 times, 5 stalled 13, 9 stalled once, 11 and 14 never.
	--
	-- STEP 2 EXPECTED FIVE PIECE TYPES TO MEAN SHALLOWER LOOKING WOULD DO. IT IS THE
	-- OPPOSITE, and this is the measurement that says so -- the five piece types below,
	-- 20 runs of 400 pieces each, with the budget held well clear so that what is being
	-- measured is the DEPTH and not the giving up:
	--
	--   lookahead   boxed itself in   earliest   worst search   cost a piece   worst piece
	--        3        19 of 20         piece 15      81 nodes     0.11 ms          2 ms
	--        5        13 of 20         piece 15     261           0.23             7
	--        7         8 of 20         piece 43     989           0.36            30
	--        9         8 of 20         piece 126  2 925           0.59            65
	--       11         3 of 20         piece 116  7 902           0.82           175
	--       14         2 of 20         piece 231 22 779           1.30           356
	--       18         1 of 20         piece 172 80 000 (cap)     3.95         2 321
	--
	-- More ways to turn is not more ways OUT. A hairpin folds the road back on itself 140
	-- studs away from where it came, and a chicane steps it 65 studs sideways without
	-- turning it: both of those make corridors the road then has to thread, and the
	-- tallies of what the road was standing on when it ran out of room put the hairpin
	-- and the chicane at about half the stalls between them while they are a third of the
	-- pieces. Taking either one out measures WORSE, not better (10 of 20 with no hairpin
	-- against 6 of 20 with it, at depth 7): a hairpin is also an escape hatch, the one
	-- piece that turns round inside a dead end.
	--
	-- SO 14 STAYS, and it is still not a round number: it is `AheadPieces + BehindPieces`,
	-- how many pieces the window remembers, so what the search proves is "there is a way
	-- out of this window". It is now the best point on a curve rather than the first clean
	-- one. Looking further still helps a little -- 18 halves the stalls again -- but it
	-- costs three times as much a piece and its worst single choice is 2.3 SECONDS, and
	-- at that point the search is hitting the budget rather than finishing, so what it
	-- would be proving is "I gave up" rather than "there is a way out".
	--
	-- WHAT DID HAVE TO CHANGE IS THE BUDGET -- and this paragraph is step 2's reasoning,
	-- kept because it is why the budget used to be 40 000; it is NO LONGER the reasoning,
	-- see `SearchNodeBudget` below. At 4 000 every stall at depth 14 was the search giving
	-- up rather than the road running out: it was deciding the answer. The biggest search
	-- that ran to the END OF ITS OWN TREE, over some 30 000 pieces, tried 29 297, so the
	-- budget has to be clear of that, and 40 000 is. All five of the test suite's seeds
	-- then run 500 pieces without a stall where seed 7 stopped at piece 42 on a budget of
	-- 20 000.
	--
	-- WHAT A NODE COSTS IS A PROPERTY OF `Pieces.quadsOverlap`, which is the only thing
	-- a search does. Rewriting it to allocate nothing took a node from 0.104 ms to 0.032
	-- and the worst single choice from 3.0 seconds to 0.93, which is most of why a budget
	-- this size is affordable at all.
	--
	-- AND THEN T-052 TOOK THE SEARCH OFF THE CALL STACK, AND THE ROAD GOT WIDER. Two
	-- things changed at once and both of them land here. `Road/Generator` now keeps the
	-- search as a standing plan -- a stack of frames it can stop in the middle of -- so a
	-- piece costs only the frontier plus whatever backtracking it needs, the work is
	-- sliced across ticks, the backtracking RE-CHOOSES pieces that were decided but never
	-- built, and when even that fails it lays the best chain it found rather than
	-- stopping. And `Width` went from 35 to 50, which widened every footprint by 15 studs
	-- and makes the road trap itself more easily, not less.
	--
	-- THE TABLE ABOVE RE-MEASURED AT 50, with the plan and its recovery, 20 runs of 400
	-- pieces (`RoadTests:stalls`). The column the old table does not have is the price of
	-- carrying on: how many pieces went down on less than a full `LookAhead` of proof.
	--
	--   lookahead   boxed itself in   earliest   pieces   on short proof   worst search
	--        3        20 of 20         piece 17   2 311      22 (least 1)      86 nodes
	--        5        11 of 20         piece 25   5 098      41 (least 1)     180
	--        7         7 of 20         piece 120  6 775      49 (least 1)     578
	--        9         3 of 20         piece 129  7 476      45 (least 1)   2 000 (cap)
	--       11         0 of 20         never      8 000      19 (least 4)   2 000
	--       14         0 of 20         never      8 000      20 (least 4)   2 000
	--
	-- 14 STILL STAYS, and now it earns it twice over: it is the shallowest depth at which
	-- no run of 400 pieces boxes itself in at all -- where step 2 measured 2 in 20 at a
	-- NARROWER road -- and it is the depth at which the road almost never has to settle
	-- for short proof, 20 pieces in 8 000 and never below 4 of 14. Everything the old
	-- table says about WHY depth helps is unchanged and is still above.
	LookAhead = 14,

	-- THE BUDGET WENT DOWN, NOT UP, AND THAT IS THE WHOLE TRICK. Step 2 raised it from
	-- 4 000 to 40 000 because hitting it meant the road stopped, so the budget was
	-- deciding the answer. It no longer means that: when the plan cannot prove fourteen
	-- deep inside the budget it lays the best chain it DID stand up and carries on
	-- (`Road/Generator`, "what the road does when it cannot prove itself fourteen deep").
	-- Hitting the budget now costs a little proof, not the run, so the budget can be set
	-- where it bounds the worst call instead of where it never bites.
	--
	-- 20 runs of 400 pieces at the width the game ships, driven by the simulated service
	-- tick at 145 studs/s -- faster than the car has ever been measured going -- with the
	-- whole 8 000 pieces of road generated through `extendTo`:
	--
	--   budget   boxed itself in   pieces   WORST SINGLE CALL   least road ahead   gave up proof
	--    40 000     0 of 20         8 000      1 421.93 ms           1 piece          6 times
	--     8 000     1 of 20         7 885        263.37              1               23
	--     2 000     0 of 20         8 000          8.15              3               20
	--       800     1 of 20         7 644          2.44              4               44
	--
	-- 2 000 is where the worst call stops being a hitch at all: 8.15 ms IS
	-- `SearchMillisUrgent`, which is to say no call ever ran past its slice, and the car
	-- never got closer than three pieces to the end of the road. Above it the car does
	-- catch the road up, and then the one path that ignores the clock pays the whole
	-- budget in one go -- 1.4 seconds at 40 000, which is the bug this replaced.
	-- Below it the road starts settling for proof it should not have to: 44 relaxations
	-- against 20, and a run that got down to ONE piece of proof.
	-- AND THEN THE SET WENT FROM NINE VARIANTS TO SIXTEEN (T-068), AND 2 000 WAS A NUMBER
	-- ABOUT NINE. Every frame of the search shuffles everything legal at that depth and
	-- tries them in turn, so the tree the budget is spent on is `variants ^ depth` wide:
	-- adding the four touge pieces made it 16 wide where it was 9, and a budget that proved
	-- fourteen deep over nine variants does not prove fourteen deep over sixteen.
	--
	-- WHAT THAT LOOKS LIKE IS NOT A SLOWER ROAD, IT IS A ROAD THAT SETTLES. When the plan
	-- cannot prove itself it lays the best chain it stood up and carries on (`relax`), and
	-- a piece laid on one piece of proof is how a road walks into a dead end three pieces
	-- later. Measured over 45 runs of 500 pieces through `grow` -- the five suite seeds and
	-- two pools of twenty -- counting the pieces laid on less than a full `LookAhead`:
	--
	--   set and budget        runs that boxed in   pieces on short proof   worst driven call
	--   the flat nine, 2 000       0 of 45                58                   --
	--   the sixteen,   2 000       1 of 45 (at            92                   8.20 ms
	--                              piece 227)
	--   the sixteen,   2 500       1 of 45 (at            72                   8.60
	--                              piece 59)
	--   the sixteen,   3 000       0 of 5 measured        --                  89.81
	--
	-- 2 500 TAKES A FIFTH OFF THE SETTLING FOR NOTHING, which is what it is for. It does not
	-- take the tail stall away -- raising the budget only moves WHICH seed is unlucky, which
	-- is why the row above is honest about still being 1 of 45 -- and the comparison that
	-- actually says whether the set got worse is further down, under "the piece set".
	--
	-- 2 500 AND NOT 3 000, AND THE REASON IS THE 89.81 MS. The one path that ignores the
	-- clock -- `MinAheadPieces`, the road having run out under the car -- pays the whole
	-- budget in one go, and at 3 000 a 400-piece drive at 145 studs/s hit it once and stopped
	-- the server for 90 ms. At 2 500 the worst single call over 12 seeds x 400 pieces at the
	-- same cruel speed was 8.60 ms and NOT ONE call of 81 912 went past 10 ms. That is the
	-- same property 2 000 was chosen for, kept.
	SearchNodeBudget = 2500, -- placements the plan may try for one piece before it
	-- settles for the best chain it found

	-- ------------------------------------------------- how long one call may take, in ms
	-- THE NUMBER THAT MATTERS: no call into the generator may stop the server for long.
	-- Step 2's worst single call was 922 ms on seed 7 at 35 studs wide and 1 422 ms at
	-- the 50 the game ships -- every car's replication and every other player stopped for
	-- a second and a half, while a car travelling over 100 studs/s was mid-corner. These
	-- three numbers are what replaced it.
	--
	-- MEASURED AFTER: 40 seeds driven 400 pieces each at 145 studs/s through the
	-- service's own tick -- 282 360 calls -- the worst single call was 8.31 ms and the
	-- mean 0.03 ms. 8 ms of that is the urgent slice itself, so no call ever ran past
	-- its budget; the extra 0.31 is the one placement that was already running when the
	-- clock went. The road never came within 3 pieces of running out underneath the car.
	--
	-- `RoadService` ticks ten times a second and asks for `windowCentre + AheadPieces`,
	-- so the generator can read how much road is in front of the car out of what it was
	-- asked for, and spend accordingly. It is never in a hurry when it does not have to
	-- be: ten pieces of window is about forty seconds of driving, and at 2 ms a tick that
	-- is 800 ms of search time available before the car arrives -- far more than any one
	-- piece now costs.
	SearchMillisPerTick = 2, -- the normal slice. 2 ms of a 100 ms tick is 2% of one
	-- server thread, which is cheap enough to be always on, and
	-- small enough that nothing can see it
	SearchMillisUrgent = 8, -- when fewer than `UrgentAheadPieces` of road are left in
	-- front of the car. Still under half a frame at 60 FPS
	UrgentAheadPieces = 4, -- pieces of road ahead of the car below which it hurries
	MinAheadPieces = 1, -- and below which it IGNORES THE CLOCK: there is no road past
	-- the one the car is standing on, so a gap is imminent and a
	-- hitch is the lesser evil. In a run this is only ever the
	-- first call of `Generate`, where there is no road at all --
	-- measured, `forcedCalls` is 1 over a 500-piece drive -- and
	-- it is bounded by the node budget like every other path.
	-- Driven deliberately, with the car told to stand on the last
	-- piece of the road for two hundred ticks running, the worst
	-- call on this path measured 74 ms with the nine flat pieces
	-- and a budget of 2 000, and 162 ms with the sixteen and a
	-- budget of 2 500 (T-068; `RoadTests`, "a car that outruns
	-- the search still gets road"). That is the ONE number in
	-- this file above ten milliseconds, and reaching it means the
	-- road has already run out -- which the same suite measures
	-- never happening, the car never coming within two pieces of
	-- the end over 43 810 ticks

	-- How much each footprint quad is shrunk by before two of them are asked whether they
	-- overlap. Neighbouring pieces SHARE a socket face by construction, and a corner's
	-- chords share their ends, so without a little slack every road would read as one
	-- long self-collision. Small next to the road's width.
	OverlapSlack = 0.75, -- studs off each side of every footprint quad

	-- --------------------------------------------------------------------- the piece set
	-- NINE PIECE TYPES IN SIXTEEN VARIANTS: the five FLAT ones the road shipped with, and
	-- the four TOUGE ones that go somewhere vertically (T-068, features/road-elevation.md
	-- "The pieces: designed, not tilted"). The nine flat variants are untouched -- same
	-- numbers, same parts, same places -- and they are still what a flat road is made of.
	--
	-- THE FOUR ARE THE USER'S OWN FOUR, and they are DESIGNED, not tilted: not one of them
	-- is a flat piece with a grade added. Each has its plan shape, its height profile and
	-- its bank chosen together, and what it hands the next piece -- a height, a grade and a
	-- bank -- is part of its design rather than a side effect:
	--
	--   Link           flat or nearly, short, and it LEVELS the road and hands on a gentle
	--                  climb. The breather, and the piece that stops a descent being one
	--                  long ramp
	--   Banked30       a 30-degree direction change with 30 degrees of bank through it,
	--                  losing height. The showcase: the bank is what holds the car
	--   HairpinStack   two 180-degree hairpins back to back, opposite hands, dropping hard.
	--                  How a mountain road actually loses height
	--   Corkscrew      a flat entry and then the floor leaves: a chicane that drops away and
	--                  HANDS ON A DESCENT, so the road keeps falling until a link catches it
	--
	-- THE ROAD'S HEIGHT IS A STATE MACHINE AND THESE FOUR ARE ITS ONLY INPUTS, which is the
	-- thing to understand before changing any number in them. A piece with no `Height` does
	-- not flatten the road, it CARRIES the grade it arrived at (`Road/Pieces`), so all nine
	-- flat pieces are followers: whatever the last touge piece handed on, they keep doing.
	-- So the whole of the road's vertical behaviour is four `EndGrade`s:
	--
	--   Corkscrew   ends descending  -> every flat piece after it descends, until
	--   Link        ends climbing    -> every flat piece after it climbs, until
	--   Banked30, HairpinStack  end level -> the road runs level again
	--
	-- That is what makes it a BAND rather than a ramp, and the measured numbers are under
	-- `Link` below.
	--
	-- SEVEN MORE VARIANTS DID NOT MAKE THE GENERATOR WORSE, and that is measured rather than
	-- hoped for. At the shipped `LookAhead` of 14 both sets box themselves in about never --
	-- the flat nine 0 times in 45 runs of 500 pieces, the sixteen once, at piece 59 of one
	-- seed -- which is a difference too small to read anything into. So the comparison is
	-- made where stalls are COMMON enough to count, by cutting the lookahead down
	-- (`RoadTests:stalls`, 20 runs of 400 pieces):
	--
	--   lookahead   the flat nine            the sixteen
	--       5        11 of 20, 5 098 pieces   12 of 20, 5 493 pieces (earliest stall at
	--                 (earliest at piece 25)   piece 56, not 25)
	--       7         7 of 20, 6 775           4 of 20, 7 107
	--      14         0 of 45 x 500            1 of 45 x 500
	--
	-- MORE WAYS TO TURN IS MORE WAYS OUT, which is the same thing step 2 found when it added
	-- the hairpin: a piece that folds the road back on itself is a trap AND an escape hatch.
	-- The tallies of what the road was standing on when it ran out of room put the
	-- `HairpinStack` -- the biggest plan footprint in the set by some way -- at 0 of 4
	-- stalls at depth 7 while it is a tenth of the pieces.
	--
	-- `Shape` is how a piece is drawn (`straight`, `arc`, `chicane`); `kind` is what it is
	-- called. A corner, a sweeper and a hairpin are all `arc`, and the ENTIRE difference
	-- between them is the two numbers below each one.
	--
	-- HOW A PIECE IS GIVEN A HEIGHT AND A BANK, for the step that adds some. Both are
	-- optional and both are ABOUT THIS PIECE -- what it arrived at is carried in and
	-- blended, never snapped:
	--
	--   Height = { Drop = 60 }                 loses 60 studs and hands on the average
	--                                          grade it did it at
	--   Height = { EndGrade = -8 }             bends from the grade it arrived at to 8
	--                                          degrees of descent; the height falls out
	--   Height = { Drop = 60, EndGrade = 0 }   loses 60 studs and arrives LEVEL: a descent
	--                                          that settles onto a flat section
	--   Height = { Drop = 60, EndGrade = -12 } flat entry, floor leaves: with a level
	--                                          entry this is the corkscrew's shape
	--   Bank   = { Degrees = 25 }              banked 25 degrees through the piece, the
	--                                          outer edge of its own turn raised
	--   Bank   = { Degrees = 25, Shape = "crest" }   in and out again, level at both ends
	--
	-- NO `Height` AT ALL IS NOT "FLAT", IT IS "CARRY ON": a piece with no height profile
	-- keeps the grade it arrived at for its whole length, which is what stops a descent
	-- being a staircase of ramps. No `Bank` is the other way round -- a bank belongs to
	-- the corner it is in, so a piece without one eases whatever it arrived with back to
	-- level over its own length. Neither ever steps at a join.
	--
	-- `weight` is how often a variant should turn up relative to the others, BEFORE the
	-- bias against recent use. `minPieces` is how far into a run before it may appear at
	-- all. `mirror` doubles a piece for free: `Corner` becomes `CornerL` and `CornerR`.
	--
	-- THE STRAIGHT IS WEIGHTED 3 AND EVERYTHING ELSE 1. At one apiece the straight would
	-- be one piece in nine; at 3 it is three in eleven, 27%, which is what step 1's
	-- two-piece road had and the share the straight's own 220 studs was measured at. The
	-- drive barely tells them apart and that is worth writing down rather than dressing
	-- up: over three seeds of 24 pieces, weight 1 put 2, 3 and 3 straights in the run and
	-- the car topped out at 104, 101 and 119 studs/s; weight 3 put in 7, 4 and 6 and it
	-- topped out at 110, 106 and 116. The weight buys the road its breathing room without
	-- changing what the car can do, which is the most that can honestly be claimed for it.
	--
	-- WHY THESE TWO NUMBERS -- measured, not chosen by taste. The whole table of drives is
	-- in `features/track-generation.md` "The numbers, and the drives behind them"; the
	-- short version, from `RoadTests:sweep`, twelve generated pieces driven by the
	-- autopilot on the real model and the real Workspace at 60 FPS:
	--
	--   radius   speed through the run    sideways   worst off the centre line
	--      100     41 .. 95, mean 61         66%       13.6 of 17.5 studs
	--      180     46 ..107, mean 72         76%       14.1
	--      220     53 ..111, mean 79         71%       14.1
	--      320     60 ..113, mean 91         63%       14.1
	--      400     60 ..129, mean 100        66%       14.1
	--
	-- Every one of them is drivable; none of them put a wheel off the road. 220 is chosen
	-- because it is the radius at which THE CORNER STILL COSTS THE CAR HALF ITS SPEED --
	-- 111 studs/s down the straight, 53 at the corner's slowest -- while leaving it
	-- sideways for 71% of the run. Above 250 the corner stops costing anything (320 gives
	-- back 60 of 113) and the road reads as one long sweeper; below 180 the car is never
	-- travelling fast enough for the loss to mean anything. A 90-degree arc at 220 is
	-- 345.6 studs, cut into 27 chords of 12.80 studs, which is 0.093 studs off the true
	-- arc: inside the tenth of a stud the model's ground rays cannot tell from smooth.
	--
	-- The straight is 220 studs because that is what the car needs to go from the speed a
	-- corner leaves it at (53 studs/s, measured) to a speed the next corner cannot be held
	-- at (111 against about 75): so every straight ends in a real corner entry. At 100
	-- studs it only reaches 102 and the entry stops being a decision; at 400 it reaches
	-- 132 and the road is mostly straight line.
	--
	-- EVERY PIECE BELOW WAS CHOSEN THE SAME WAY, by driving it rather than by liking it,
	-- and each one's table is written out beside it. The sweeps are reproducible:
	--   DebugBridge:Invoke("DebugRoadTests", "sweep",
	--                      { piece = "Hairpin", field = "Radius", values = { ... },
	--                        only = { "Straight", "Hairpin" } })
	Pieces = {
		Straight = {
			kind = "Straight",
			Shape = "straight",
			weight = 3,
			minPieces = 0,
			mirror = false,
			Length = 220, -- studs
		},
		Corner = {
			kind = "Corner",
			Shape = "arc",
			weight = 1,
			minPieces = 0,
			mirror = true, -- CornerL and CornerR
			Radius = 220, -- studs to the centre line
			Arc = 90, -- degrees
		},
		-- THE SWEEPER IS THE CORNER THE CAR IS HAPPIEST DRIFTING: entered fast and HELD.
		-- Measured with `sweep { piece = "Sweeper", only = { "Straight", "Sweeper" } }`,
		-- which pushes every other piece out of the run so the numbers are about the
		-- sweeper and not about the road. The per-piece columns are what the car did on
		-- the sweepers themselves, ten or eleven of them in a twenty-piece run:
		--
		--   radius (arc 45)  speed on it   drifting it   held it all the way   longest slide
		--        280           49..135         83%            5 of 10              4.8 s
		--        340           70..132         82%            3 of 10              5.8
		--        400           79..138         84%            5 of 10              6.1
		--        500           83..141         79%            3 of 10              5.9
		--        650           91..145         76%            3 of 10              5.8
		--
		--   arc (radius 400)  speed on it   drifting it   held it all the way   on a barrier
		--        30             72..137         81%            5 of 10            53 steps
		--        45             79..138         84%            5 of 10            63
		--        60             71..136         81%            2 of 11           111
		--        90             71..146         77%            1 of 10           103
		--       120             70..138         76%            0 of 11           143
		--
		-- 400 AND 45 IS WHERE THE SLIDE LASTS LONGEST WITHOUT THE CAR RUNNING OUT OF ROAD:
		-- the longest unbroken slide of any sweep run (6.1 s against 4.8 at 280 and 5.8 at
		-- 650), the highest share of the piece spent sideways (84%), half of them held the
		-- whole way, and the car never drops below 79 studs/s on one -- where a 220-radius
		-- corner takes it down to 53. Opening it further only makes it a straight: at 650
		-- the slide falls to 76% and the car arrives at 91. Winding the arc on past 45
		-- costs the road rather than the car -- at 120 degrees the sweeper touches a
		-- barrier 143 steps against 63, because a long fast corner runs the car wide for
		-- longer. Nothing in any of these runs put a wheel off the road.
		Sweeper = {
			kind = "Sweeper",
			Shape = "arc",
			weight = 1,
			minPieces = 0,
			mirror = true,
			Radius = 400, -- studs
			Arc = 45, -- degrees; 314 studs of corner
		},

		-- THE HAIRPIN HAS TO GENUINELY SLOW AND ROTATE THE CAR, which is the one thing
		-- nothing else in the set does. Same isolated sweep, arc 180 throughout:
		--
		--   radius   speed on it   drifting it   peak slip   touched a barrier, per hairpin
		--      40      22.. 55         70%          72 deg        2.1 steps
		--      50      27.. 57         74%          65            2.1
		--      55      30.. 60         71%          64            2.7
		--      65      28.. 65         78%          61            4.1
		--      70      30.. 68         81%          63            5.0
		--      80      32.. 72         81%          57            6.7
		--     100      35.. 81         83%          56            8.1
		--     120      33.. 88         84%          62            9.9
		--     150      38.. 99         78%          61            9.4
		--
		-- THE AUTOPILOT GETS ROUND EVERY ONE OF THEM -- 0 steps off the road at every
		-- radius from 40 to 150 -- so the choice is not where it stops working, it is
		-- where the piece stops being a hairpin at one end and starts spinning the car at
		-- the other. 70 is the tightest radius that still holds the car in a slide for
		-- four fifths of the piece (81%, against 70..74% at 40..55, where the car is being
		-- braked rather than drifted) while keeping its peak slip at 63 degrees, well
		-- short of the 90 where the model's grip force turns into a brake and the car
		-- spins (`features/drift-model.md`). It costs the car two thirds of its speed --
		-- 30 studs/s at its slowest against the 94 the same run reaches on a straight --
		-- and touches a barrier for 5 of the roughly 230 steps it spends on each one, 2%.
		--
		-- The arc is 180 because a shorter one is a corner, not a hairpin, and measures
		-- like one: at radius 70, 120 degrees of it leaves the car drifting 79% and 150
		-- degrees 72%, against 81% at 180.
		--
		-- `minPieces = 8` IS THE GATE, and it is in pieces rather than seconds because
		-- that is what the generator counts. The first eight pieces of a run are 1 780 to
		-- 2 200 studs and about 30 seconds of driving (measured: the 50-piece drive runs
		-- 185 s, 3.7 s a piece), so a player meets straights, corners, sweepers and
		-- chicanes for half a minute before the road ever asks them to stop.
		--
		-- THE TIGHT RADIUS COSTS THE GENERATOR, and that is a real trade rather than a
		-- free choice: a 70-radius fold leaves 140 studs between the two legs of the U,
		-- which is a corridor nothing else in the set fits down, so the road boxes itself
		-- in more often. Measured at lookahead 11, 20 runs of 300 pieces: radius 70
		-- stalled 3 times, 110 twice, 150 once. 70 is kept because the car is what this
		-- piece is for and 150 is barely a hairpin (it leaves the car at 38 studs/s
		-- instead of 30 and drifting 78% instead of 81), but the cost is written down.
		Hairpin = {
			kind = "Hairpin",
			Shape = "arc",
			weight = 1,
			minPieces = 8,
			mirror = true,
			Radius = 70, -- studs
			Arc = 180, -- degrees; 220 studs of corner, and the road comes back on itself
		},

		-- THE CHICANE TESTS THE CATCH BETWEEN TWO SLIDES, which is the skill the whole
		-- drift model is built on, so the number it is chosen by is how often the car
		-- actually swaps a slide one way for a slide the other -- a slip reading passing
		-- all the way through zero from 12 degrees one side to 12 the other -- rather than
		-- how much of it is spent sideways:
		--
		--   radius (arc 40)  speed on it   drifting it   caught and swapped   on a barrier
		--       110            49.. 90        69%          1.1 per chicane      2.2 steps
		--       140            47.. 96        78%          1.5                  5.6
		--       180            54..108        82%          1.6                  9.4
		--       240            63..125        84%          1.7                 13.9
		--       320            73..131        86%          1.7                 16.6
		--
		--   arc (radius 140)  drifting it   caught and swapped   on a barrier
		--        25               31%          0.1 per chicane      0.1 steps
		--        40               78%          1.5                  5.6
		--        55               89%          1.4                 12.0
		--        70               91%          1.5                 14.6
		--
		-- THE 25-DEGREE ROW IS THE PROOF THE PIECE EARNS ITS PLACE: at that arc the car
		-- straight-lines it, drifting 31% of it and swapping once in ten chicanes, and the
		-- piece may as well be a straight. From 40 degrees on it transitions every time.
		-- 140 and 40 is the shallowest pair that does: 1.5 swaps a chicane and 78% of it
		-- sideways, for 5.6 steps on a barrier. Opening the radius buys almost nothing
		-- more (1.7 swaps at 320) and triples what it costs in wall contact, because the
		-- jink across the road grows with it -- 65 studs at 140, 150 at 320 -- while the
		-- road stays one width wide. (Every number in this block was measured on a
		-- 35-stud road, before the user asked for 50; the wall-contact columns will have
		-- come down with the extra width and nobody has re-driven them.)
		--
		-- `Middle` is a straight between the two bends, a beat to catch the first slide in
		-- before starting the second. It is ZERO because the beat is not worth what it
		-- costs: 30 studs of it buys 16 swaps against 15 and takes the barrier contact
		-- from 5.6 steps a chicane to 9.4; 60 studs takes it to 12.4.
		Chicane = {
			kind = "Chicane",
			Shape = "chicane",
			weight = 1,
			minPieces = 0,
			mirror = true,
			Radius = 140, -- studs, each bend
			Arc = 40, -- degrees, each bend; 196 studs of road, jinking 65 studs across
			Middle = 0, -- studs of straight between the two bends
		},

		------------------------------------------------------------------------------
		-- THE TOUGE PIECES (T-068)
		------------------------------------------------------------------------------

		-- THE LINK IS THE ONLY PIECE THAT CLIMBS, AND IT IS WHY THE ROAD IS A BAND.
		--
		-- The user asked for "flat sections between sections", and flat is what the piece
		-- itself is: `EndGrade` with no `Drop` blends the grade LINEARLY from whatever it
		-- arrived at to this one, so the link's own height change is the average of the two
		-- over its length -- about 6 studs from a level entry, and NEGATIVE from a steep
		-- descent, where it is the piece that catches the fall. It is 140 studs where the
		-- straight is 220, so it is a beat and not a leg.
		--
		-- `EndGrade` IS THE WHOLE OF THE ROAD'S HEIGHT BUDGET, because everything that is
		-- not a touge piece carries whatever it arrived at. Measured by generating 200
		-- pieces on each of 5 seeds and reading the net height at the end (`heightBand` in
		-- `RoadTests`), with every other number in this set as it ships:
		--
		--   Link EndGrade   net over 200 pieces   mean lowest   mean highest
		--      0 deg           -2 190 studs         -2 190          +0
		--      4               -1 444               -1 471        +102
		--      7 (shipped)       -880                 -950        +244
		--     10                 -309                 -549        +443
		--     12                  +78                 -373        +599
		--
		-- 7 IS WHERE THE ROAD IS A BAND THAT TRENDS DOWNHILL. 880 studs down over 200 pieces
		-- is 1.75% of the 50 500 studs of road it took to get there -- a real mountain
		-- road's average gradient -- and on the way it wanders about 1 200 studs between its
		-- lowest and its highest point and climbs 244 studs ABOVE where it started. At 0 it
		-- is a ramp and never once gets above its own start; at 12 it climbs on balance,
		-- which is the wrong side of the user's "downhill map".
		--
		-- IT IS NOT A STEEP PIECE EVEN AT 7. A 7-degree climb is a grade the car does not
		-- notice (it climbs 24 and the measured cost at 8 degrees is 116 studs/s against
		-- 129 at 4), and what climbs at 7 degrees is the STRAIGHTS AND CORNERS after the
		-- link, not the link itself.
		Link = {
			kind = "Link",
			Shape = "straight",
			weight = 3, -- as often as the straight: it is the piece the road is kept level
			-- by, so it has to turn up as often as the things that unlevel it
			minPieces = 0,
			mirror = false,
			Length = 140, -- studs. Short, and deliberately shorter than the straight's 220
			Height = { EndGrade = 7 }, -- degrees; no `Drop`, so the grade blends linearly
			-- from whatever arrived and the height falls out of it
		},

		-- THE BANKED 30 IS THE SHOWCASE: a 30-degree direction change with banking through
		-- it, losing height. It is the one piece in the set whose shape is chosen BY the
		-- bank rather than decorated with it.
		--
		-- THE 30 IS THE TURN, NOT THE BANK, and that distinction cost a morning to learn.
		-- The spec's words are "30 degree turns that have big banking"; `MaxBank` was raised
		-- to 30 for this piece and 30 degrees of bank IS geometrically safe -- T-073's
		-- exhaustive audit read the road as a wall 0 times in 18 865 sweeps at that bank.
		-- IT IS NOT DRIVABLE, and nothing about the audit said it would be.
		--
		-- A BANKED CORNER HAS A MINIMUM SPEED, which is the thing the audit could not see.
		-- Gravity acts along the surface now (T-065), so on a bank it pulls the car down the
		-- slope at `Gravity x sin(bank)` -- 35 x sin(bank) in this game's units -- and the
		-- speed at which the corner's own v^2/r exactly pays for that is
		--
		--     v = sqrt(radius x Gravity x tan(bank))
		--
		--   bank   balance speed at radius 400
		--    10 deg        50 studs/s
		--    15            61
		--    20            71
		--    30            90
		--
		-- Below it the car slides DOWN the bank towards the inside of its own corner, and
		-- the slide is slip: once the slip passes 90 degrees the model's grip force becomes
		-- a brake (`features/drift-model.md`), which slows it further, which makes it slide
		-- further. It is a trap with a floor and the car does not get out of it.
		--
		-- AND THE ROAD DELIVERS THE CAR AT 0 TO 99 STUDS/S, because the pieces either side
		-- of this one are hairpin stacks and corkscrews and they are SLOW. So the piece has
		-- to work at the bottom of that range, not at the top.
		--
		-- WHAT GOES WRONG IS NOT A SPIN, IT IS A PIN. A car that loses its speed on a bank
		-- slides down it into the barrier at the low edge; gravity along the surface holds
		-- it there; the sideways slide IS slip, and past 90 degrees of slip the grip force
		-- is a brake, so it never builds the speed it would need to come off the wall. The
		-- road is not what stops it -- traced, every sweep that stopped the car on this set
		-- was a BARRIER and not one was road, 0 of 351 -- it is the wall at the bottom of
		-- the bank plus a car that cannot get off it.
		--
		-- MEASURED, THE WHOLE SET DRIVEN 50 PIECES, radius 400, one seed, everything
		-- identical and only `Bank.Degrees` changing. The column that decides is the last
		-- one: `RoadTests` requires the shipped road never to stop the car for a second.
		--
		--   bank   pieces reached   mean speed   barrier steps on it   longest stop
		--     0        50             49 studs/s        4                 0.4 s
		--     5        50             49               21                 0.5
		--     8        50             41              158                11.9
		--    10        50             36              387                40.2
		--    12        37             32              253                21.7
		--    15        37             28              247               113.8
		--
		-- It is monotone and it is not the drop: the same sweep with the piece LEVEL (Drop
		-- 0) at 15 degrees stopped the car for 20 s, and with Drop 6 at 12 degrees for 50 s.
		-- It is not the radius either -- 550 measured worse than 400, and 340 worse again.
		-- It is the bank, and only the bank.
		--
		-- SO 5, WHICH IS THE MOST THE CAR CAN BE SLOW ON, and the honest thing to say about
		-- it is that it is a ROAD's superelevation rather than a speedway's: 5 degrees lifts
		-- the outer edge 4.4 studs above the inner across a 50-stud road, which is what a
		-- real mountain road is built with, and it is a bank on a road that was dead flat a
		-- day ago.
		--
		-- THE USER DRIVES THIS ONE, AND THIS NUMBER IS ONE LINE. What the table above
		-- measures is the TEST AUTOPILOT not getting a pinned car off a barrier, and a
		-- player in that spot turns the wheel and drives out -- the fixture was already
		-- given a floor under its steering for exactly this (`RoadTests`, `STEER_FLOOR`) and
		-- it was not enough. 10 to 15 degrees is where this piece starts to LOOK like a
		-- touge corner and the only thing in the way is a car that cannot unstick itself,
		-- which wants its own fix rather than a smaller bank.
		--
		-- RADIUS 400 AND NOT 340, measured before the bank came down: at 340 the car spun on
		-- every seed at 20 degrees of bank and above, and at 400 it did not. It is the
		-- balance speed again -- a tighter corner needs MORE bank for the same speed.
		--
		-- `Shape = "crest"` IS WHAT MAKES IT A CORNER AND NOT A STATE. The bank runs in and
		-- out again over the piece -- `sin(pi x u)`, level at both sockets -- which is how a
		-- real carriageway is superelevated, and it means the piece hands the next one a
		-- LEVEL road. Measured against a CONSTANT bank of the same size, which hands its
		-- roll to the next piece to unwind: constant 20 got the car stuck for 142 s and
		-- constant 30 threw it 203 studs off the centre line, where the crest at the same
		-- numbers reached 26 pieces. Every socket in this set is unbanked for that reason.
		Banked30 = {
			kind = "Banked30",
			Shape = "arc",
			weight = 1,
			minPieces = 3, -- not the first thing a player meets, but not a late piece either
			mirror = true,
			Radius = 400, -- studs
			Arc = 30, -- degrees; 209 studs of corner
			Height = { Drop = 14, EndGrade = 0 }, -- loses 14 studs and arrives LEVEL. A
			-- vertical curve that is level at both ends is steepest in the middle at 1.5x
			-- its average, so 14 over 209 studs peaks at 10.0% -- 5.7 degrees
			Bank = { Degrees = 5, Shape = "crest" }, -- in and out again over the piece
		},

		-- THE HAIRPIN STACK IS HOW A MOUNTAIN ROAD LOSES HEIGHT: two 180-degree hairpins
		-- back to back, opposite hands, dropping hard. It is the slowest and most technical
		-- thing in the set and it is the only piece that drops a serious number of studs.
		--
		-- IT IS A `chicane`, WHICH IS NOT A TRICK -- the shape is literally "an arc, then
		-- the same arc the other way", and at 180 degrees each that is two half-circles
		-- tangent at a point: the road folds back on itself, comes out pointing the way it
		-- went in, and has moved four radii sideways. `Middle = 0` because "back to back" is
		-- what the user asked for and a straight between them would make it an S.
		--
		-- RADIUS 70 IS THE SHIPPED HAIRPIN'S, and it is used here precisely because it was
		-- chosen by driving: tight enough that the car is braked and rotated rather than
		-- drifted wide, wide enough that it holds a slide for four fifths of the piece.
		-- Changing it here would be inventing a second answer to a question already
		-- measured.
		--
		-- IT COSTS THE GENERATOR AND THAT IS WRITTEN DOWN RATHER THAN HIDDEN. Two tangent
		-- 70-radius circles are 280 studs across and 140 deep, which is a bigger plan
		-- footprint than any other piece in the set -- the straight is 220 x 50 -- and the
		-- corridors it leaves are corridors the road then has to thread. The stall table in
		-- `features/track-generation.md` is measured with it in.
		--
		-- `minPieces = 14`, LATER THAN THE PLAIN HAIRPIN'S 8. A hairpin stops the car; a
		-- hairpin stack stops it twice while dropping 40 studs under it, and at 14 pieces --
		-- about a minute of driving -- a player has met every other piece in the set first.
		HairpinStack = {
			kind = "HairpinStack",
			Shape = "chicane",
			weight = 1,
			minPieces = 14,
			mirror = true,
			Radius = 70, -- studs, each hairpin
			Arc = 180, -- degrees, each; 440 studs of road, moving 280 studs sideways
			Middle = 0, -- studs between them: back to back
			Height = { Drop = 40, EndGrade = 0 }, -- 40 studs down and arrives LEVEL. Over
			-- 440 studs that is 13.6% at its steepest -- 7.77 degrees measured, and the
			-- steepest surface anywhere in the shipped set -- and the steepest point is the
			-- join between the two hairpins, which is where a real switchback is steepest too
		},

		-- THE CORKSCREW IS THE PIECE THE FLOOR LEAVES UNDER. Laguna Seca's: you commit on
		-- the flat and the road drops away through a chicane.
		--
		-- IT IS THE ONLY PIECE THAT HANDS ON A DESCENT, and that is its whole design. Every
		-- other touge piece arrives level; this one arrives at `EndGrade` and the straights
		-- and corners after it CARRY that grade until a link catches it (see the state
		-- machine at the head of this set). So the corkscrew is not a 20-stud drop, it is
		-- the START of one: measured over 5 seeds x 200 pieces, each run holds 15 to 18
		-- separate descents, a descent runs a mean of 2.6 to 3.1 pieces, and the longest
		-- unbroken one anywhere is 13 pieces before a link levels it.
		--
		-- `Drop` AND `EndGrade` TOGETHER IS WHAT MAKES THE ENTRY FLAT. With both, the
		-- vertical curve leaves the start socket at EXACTLY the grade it arrived at and
		-- reaches `EndGrade` by the exit, so after a link (which hands on a climb) the
		-- corkscrew is entered going UP and the floor drops 20 studs out from under the car
		-- inside 236 studs. That is the user's "slide over a crest and into a downhill
		-- drift" and it is free: no piece has to know what came before it.
		--
		-- RADIUS 150 AND ARC 45, which is a wider, faster jink than the shipped chicane's
		-- 140 and 40 (88 studs across against 65) -- because this one is taken at the speed
		-- a straight leaves the car at and the road is falling away while it is taken.
		-- `minPieces = 10` so it is not the first thing after the gate.
		Corkscrew = {
			kind = "Corkscrew",
			Shape = "chicane",
			weight = 1,
			minPieces = 10,
			mirror = true,
			Radius = 150, -- studs, each bend
			Arc = 45, -- degrees, each bend; 236 studs of road, jinking 88 studs across
			Middle = 0,
			Height = { Drop = 20, EndGrade = -5 }, -- 20 studs down THIS piece, and hands on
			-- 5 degrees of descent for the rest of the road to carry
		},
	},
	-- The order a tie is broken in, and the order every report lists them in. A variant
	-- not named here is still generated; this only fixes the reading order.
	-- THE FLAT NINE COME FIRST AND IN THE ORDER THEY ALWAYS HAD, which is not only tidiness:
	-- `Generator.biasedWeights` walks this order and skips whatever is gated out, so a run
	-- with the touge pieces gated out draws exactly the list -- and therefore exactly the
	-- random numbers -- it drew before they existed. That is what lets `RoadTests` check the
	-- flat road against fingerprints taken before this set was written.
	Order = {
		"Straight",
		"CornerL",
		"CornerR",
		"SweeperL",
		"SweeperR",
		"HairpinL",
		"HairpinR",
		"ChicaneL",
		"ChicaneR",
		"Link",
		"Banked30L",
		"Banked30R",
		"HairpinStackL",
		"HairpinStackR",
		"CorkscrewL",
		"CorkscrewR",
	},

	-- The first piece of every run, so a car is always put down on something straight
	-- pointing the way the road goes.
	StartPiece = "Straight",

	-- ------------------------------------------------------------------------ the service
	TickSeconds = 0.1, -- how often the service reads where the cars are and moves the window
	SurfaceTarmac = "tarmac", -- the `Surface` attribute every road part carries. Anything
	-- that is not `Config.Drift.SurfaceDirt` reads as tarmac, but it
	-- is written out rather than left absent so a part can be asked
	BarrierTransparency = 0.45, -- the closing barrier. The spec calls it invisible; while it
	-- is a prototype it is visible enough to be driven at on purpose

	-- Programmer art, and nothing else: grey asphalt, plain grey walls, a white centre
	-- line. A look is its own task, after the system works; the markings are here because
	-- speed has to be readable, not because the road has been art-directed.
	Colours = {
		Road = Color3.fromRGB(104, 112, 120),
		Edge = Color3.fromRGB(170, 176, 182),
		Barrier = Color3.fromRGB(142, 148, 156),
		Marking = Color3.fromRGB(232, 230, 214), -- the centre line. Off-white, not pure
		-- white: pure white blooms under the default
		-- lighting and loses its edges at speed
		Closing = Color3.fromRGB(196, 92, 72),
	},
}
