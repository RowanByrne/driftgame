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
	-- THE SPEC SAID 5 AND 5 IS NOT ENOUGH, which is a measured result and not an opinion
	-- (`RoadTests:stalls`, 40 runs of 400 pieces each):
	--
	--   lookahead   runs that boxed themselves in   worst search
	--       3            35 of 40, by piece 9           21 nodes
	--       5            13 of 40, by piece 16          45
	--       7             3 of 40, by piece 21          75
	--       9             1 of 40, by piece 263        117
	--      11             0 of 40                      156
	--      14             0 of 300 runs of 500         527
	--
	-- A 90-degree corner whose radius equals the straight's length puts the whole road on
	-- a 220-stud square lattice, and a self-avoiding walk on a square lattice traps
	-- itself: four corners the same way close a ring exactly, and then every exit runs
	-- along road that is already there. With only three variants there is no third way
	-- out, so the fix is to see it coming from further off.
	--
	-- 14 IS NOT A ROUND NUMBER, it is `AheadPieces + BehindPieces` -- how many pieces the
	-- window remembers. Look that far and a legal continuation reaches past everything
	-- currently being avoided, so what the search proves is "there is a way out of this
	-- window", which is the question. Measured over 150 000 generated pieces -- about
	-- fifty hours of driving -- it never once had nothing to place, and it costs 0.46 ms
	-- a piece against a piece arriving every three seconds or so.
	LookAhead = 14,
	SearchNodeBudget = 4000, -- placements one search may try before it gives up. A guard,
	-- not a tuning number: the worst search over those 150 000
	-- pieces tried 527 and a normal choice costs fourteen. The
	-- spec's `SearchStepsPerFrame` -- spreading the search over
	-- frames -- is deferred until a piece set big enough to need it

	-- How much each footprint quad is shrunk by before two of them are asked whether they
	-- overlap. Neighbouring pieces SHARE a socket face by construction, and a corner's
	-- chords share their ends, so without a little slack every road would read as one
	-- long self-collision. Small next to the road's width.
	OverlapSlack = 0.75, -- studs off each side of every footprint quad

	-- --------------------------------------------------------------------- the piece set
	-- Step 1 of three builds TWO piece types, which is what exercises every part of the
	-- machinery: one that does not turn, one that does, and the mirror that makes left and
	-- right both exist. `Sweeper`, `Hairpin`, `Chicane` and `Crest` are step 2's and are
	-- deliberately absent rather than stubbed.
	--
	-- `weight` is how often a variant should turn up relative to the others, BEFORE the
	-- bias against recent use. `minPieces` is how far into a run before it may appear at
	-- all. `mirror` doubles a piece for free: `Corner` becomes `CornerL` and `CornerR`.
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
	Pieces = {
		Straight = {
			kind = "Straight",
			weight = 1,
			minPieces = 0,
			mirror = false,
			Length = 220, -- studs
		},
		Corner = {
			kind = "Corner",
			weight = 1,
			minPieces = 0,
			mirror = true, -- CornerL and CornerR
			Radius = 220, -- studs to the centre line
			Arc = 90, -- degrees
		},
	},
	-- The order a tie is broken in, and the order every report lists them in. A variant
	-- not named here is still generated; this only fixes the reading order.
	Order = { "Straight", "CornerL", "CornerR" },

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
