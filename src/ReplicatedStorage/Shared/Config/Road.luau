--!strict
-- Road: the endless road's own numbers, and none of them in the logic
-- (docs/game/features/spline-road.md, docs/workflow/CODING.md "Foundation kit"). The road
-- is the spline road: its curve's numbers are `Config.Spline`, and these are where it is,
-- how wide, what it is drawn with, and the run's window. The piece road whose numbers
-- filled this file went in T-249 (features/legacy-removal.md).
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

return {
	-- --------------------------------------------------------------- where the road is
	-- The road's start, in world space. `Offset` and nothing else decides
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
	-- It was 35 -- 4.9 car widths -- until the user drove it and asked for 50. The car is
	-- NOT rescaled to the road and the road is NOT rescaled to the car.
	Width = 50, -- studs, kerb to kerb
	Thickness = 12, -- studs of slab under a parts copy of the road (`Road/SplineParts`)
	SurfaceY = 0, -- world Y of the road's start

	-- THE STEEPEST THE SURFACE MAY LEAN, grade and bank together: what the car's collision
	-- box was proved against (T-073), and what `SplineTests` holds the spline road to.
	MaxSurfaceTilt = 35, -- degrees

	-- --------------------------------------------------------------------- the barriers
	-- The closing barrier's height and look, and the low walls a parts copy of the road can
	-- stand down both edges (`Road/SplineParts`). NOT tagged: the ground rays filter to an
	-- INCLUDE list of `DriftSurface` parts, so a barrier is not ground at all -- a wall.
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
	-- DASHES STRADDLING A CHUNK'S END ARE CLIPPED, NOT SKIPPED: the interval is measured
	-- along the whole run, so the next chunk finishes the dash.
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
	-- In SECTIONS of the spline road (`Road/SplineSequence` hands each one to `RoadService`
	-- as a piece, so the names stay): the server keeps about `AheadPieces + BehindPieces`
	-- sections however long the run lasts.
	AheadPieces = 10, -- laid in front of the car
	BehindPieces = 4, -- kept behind it before the oldest is forgotten
	BarrierBehind = 2, -- where the closing barrier sits, in sections behind the car

	-- ------------------------------------------------------------------------ the service
	TickSeconds = 0.1, -- how often the service reads where the cars are and moves the window
	SurfaceTarmac = "tarmac", -- the `Surface` attribute a queryable parts copy carries
	BarrierTransparency = 0.45, -- the closing barrier. The spec calls it invisible; while it
	-- is a prototype it is visible enough to be driven at on purpose

	-- Programmer art, and nothing else: grey asphalt, plain grey walls, a white centre
	-- line. A look is its own task, after the system works; the markings are here because
	-- speed has to be readable, not because the road has been art-directed.
	Colours = {
		Road = Color3.fromRGB(104, 112, 120), -- the tarmac drawn without its texture (a parts copy)
		Barrier = Color3.fromRGB(142, 148, 156),
		Marking = Color3.fromRGB(232, 230, 214), -- the centre line. Off-white, not pure
		-- white: pure white blooms under the default
		-- lighting and loses its edges at speed
		Closing = Color3.fromRGB(196, 92, 72),

		-- THE TARMAC'S TEXTURE (T-268, `Road/RoadTexture`, features/road-surface.md): the
		-- colours it is painted in, as they show (the texture replaces the Asphalt material's
		-- colour map). After the concept art: a cool blue-violet grey, not black
		Tarmac = Color3.fromRGB(70, 72, 84),
		TarmacWorn = Color3.fromRGB(47, 48, 57), -- the wheel tracks' middles, polished darker
		TarmacEdge = Color3.fromRGB(98, 96, 94), -- the dusty last stud or two at each edge
		-- patches of newer tarmac, a little darker (send-back: the lighter older patch and
		-- strong ones read as flat panels)
		TarmacPatch = { Color3.fromRGB(58, 59, 69), Color3.fromRGB(62, 63, 74) },
		Crack = Color3.fromRGB(30, 30, 36),
		EdgeLine = Color3.fromRGB(222, 222, 214), -- Japanese edge lines: solid white
		CentreLine = Color3.fromRGB(230, 168, 46), -- the double yellow (the touge's orange-yellow)
		-- THE GRAVEL'S TEXTURE (T-270, `Config.Spline.Gravel`): the dusty bed, and the two ends a
		-- stone's tone goes toward, in the asphalt's value range (`TarmacEdge` is the dust at
		-- the tarmac's edge), so the edge reads as one painting; and the grass at its outer edge
		GravelDust = Color3.fromRGB(100, 99, 100),
		GravelLight = Color3.fromRGB(132, 129, 124),
		GravelDark = Color3.fromRGB(68, 69, 76),
		GravelGrass = Color3.fromRGB(66, 98, 48),
	},

	-- THE PAINTED LINES (T-268). The user, send-back 2: "get rid of the dashes - it's not
	-- realistic. do the 2 painted lines on either side - that's the classic touge design
	-- style. they should be faded and cracked/weather lines though. you can do the double
	-- yellow lines that touge has for dangerous 2 lane sections, like switchbacks."
	-- So no centre line on ordinary road (the dash parts of before are gone too, wherever the
	-- tarmac is textured). The edge lines are in the tarmac's texture, weathered
	-- (`Config.Spline.Tarmac` "the paint's weathering"); the double yellow is two thin strips
	-- of the road's mesh, `CentreLineLift` above the tarmac, on the tight stretches only.
	EdgeLineWidth = 0.8, -- studs
	EdgeLineInset = 0.9, -- studs from the tarmac's edge to the line's outer side
	CentreLineStyle = "tight", -- "tight": the double yellow on the tight stretches; "none"
	CentreLineWidth = 0.45, -- studs, each of the two lines
	CentreLineGap = 0.45, -- studs between them
	-- THE TIGHT STRETCHES: tighter than `CentreLineRadius` (every hairpin, 70 to 95, and the
	-- tightest "Tight" bends, 95 to 170: `Config.Spline.Bends`), `CentreLineLead` studs either
	-- side (the lead-in before the bend, the run-out after), and a gap shorter than
	-- `CentreLineMerge` closed (a switchback's two bends get one line), read every
	-- `CentreLineStep` studs (`Road/RoadTexture.centreRuns`)
	CentreLineRadius = 130, -- studs
	CentreLineLead = 40, -- studs
	CentreLineMerge = 80, -- studs
	CentreLineStep = 2, -- studs
	CentreLineLift = 0.04, -- studs over the tarmac (more on a coarse far chunk: its tolerance / 4)
}
