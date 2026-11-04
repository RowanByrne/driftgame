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
	-- studs long and 7.14 wide as it is actually built, so 35 studs is 4.9 car widths --
	-- deliberately tight. A big drift at speed will touch the barriers; that is intended.
	-- The car is NOT rescaled to the road and the road is NOT rescaled to the car.
	Width = 35, -- studs, kerb to kerb
	Thickness = 12, -- studs of slab under the surface. Buried: nothing ever sees its sides
	-- except at the very first and very last piece of a run
	SurfaceY = 0, -- world Y of the road's top. FLAT, everywhere: no elevation in this
	-- build at all (no crest, no banking), so both the other worlds'
	-- `FallY` / `RespawnBelowY` pair is right for this one too

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
	-- WHAT DID HAVE TO CHANGE IS THE BUDGET. At 4 000 every stall at depth 14 was the
	-- search giving up rather than the road running out: it was deciding the answer. The
	-- biggest search that ran to the END OF ITS OWN TREE, over some 30 000 pieces, tried
	-- 29 297, so the budget has to be clear of that, and 40 000 is. All five of the test
	-- suite's seeds then run 500 pieces without a stall where seed 7 stopped at piece 42
	-- on a budget of 20 000.
	--
	-- WHAT A NODE COSTS IS A PROPERTY OF `Pieces.quadsOverlap`, which is the only thing
	-- a search does. Rewriting it to allocate nothing took a node from 0.104 ms to 0.032
	-- and the worst single choice from 3.0 seconds to 0.93, which is most of why a budget
	-- this size is affordable at all.
	--
	-- WHAT IS LEFT, HONESTLY, AND IT IS TWO THINGS. 2 runs in 20 of 400 pieces still box
	-- themselves in, the earliest at piece 231 -- a quarter of an hour of driving -- and
	-- the two-piece road had none. And the worst single choice measured is 356 ms, which
	-- is a server hitch, not a stutter the player sees: the window is ten pieces of road
	-- ahead of the car, twenty seconds of driving, so a late piece is invisible. Both of
	-- these say the same thing: the spec's `SearchStepsPerFrame` -- spreading one search
	-- over frames -- has stopped being optional, and it belongs to `Road/Generator`.
	LookAhead = 14,
	SearchNodeBudget = 40000, -- placements one search may try before it gives up. A real
	-- number now rather than a guard: see above. Clear of the
	-- 29 297 the biggest complete search measured, and it bounds
	-- the worst hitch at roughly 40 000 x 0.032 ms = 1.3 s

	-- How much each footprint quad is shrunk by before two of them are asked whether they
	-- overlap. Neighbouring pieces SHARE a socket face by construction, and a corner's
	-- chords share their ends, so without a little slack every road would read as one
	-- long self-collision. Small next to the road's width.
	OverlapSlack = 0.75, -- studs off each side of every footprint quad

	-- --------------------------------------------------------------------- the piece set
	-- FIVE PIECE TYPES IN NINE VARIANTS, and all of them FLAT: `Crest` -- a straight with
	-- a rise and a fall -- is deliberately not here. The user asked for flat for this
	-- first build and elevation is its own decision, so there is no height anywhere in
	-- the set and `SurfaceY` is the whole of it.
	--
	-- `Shape` is how a piece is drawn (`straight`, `arc`, `chicane`); `kind` is what it is
	-- called. A corner, a sweeper and a hairpin are all `arc`, and the ENTIRE difference
	-- between them is the two numbers below each one.
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
		-- road stays 35 wide.
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
	},
	-- The order a tie is broken in, and the order every report lists them in. A variant
	-- not named here is still generated; this only fixes the reading order.
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

	-- Programmer art, and nothing else: flat grey road, plain grey walls. A look is its
	-- own task, after the system works.
	Colours = {
		Road = Color3.fromRGB(104, 112, 120),
		Edge = Color3.fromRGB(170, 176, 182),
		Barrier = Color3.fromRGB(142, 148, 156),
		Closing = Color3.fromRGB(196, 92, 72),
	},
}
