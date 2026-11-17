--!nonstrict
-- Fx: every number the car's wheel effects and its sounds are made of, and none of them
-- in the logic (docs/game/features/car-fx.md "Rules and numbers",
-- docs/workflow/CODING.md "Foundation kit").
--
-- THE VALUES ARE THE REFERENCE GAME'S, CONVERTED, and they are a starting point to be
-- driven and tuned -- not measurements. Where the reference's unit is metres the
-- conversion is 3.571 studs/m. Anything marked OURS was never in the decompile and is a
-- choice made here; anything marked MEASURED was changed after driving it, and says why.
--
-- WHAT READS WHAT:
--   `Marks` and `Smoke` and `Surfaces`  Drift/Wheels   (T-062, built)
--   `Engine`                            Drift/Engine (the fake rpm, T-125) and
--                                       Drift/EngineSound (T-064, built)
--   `Skid`                              Drift/SkidSound   (T-064, built)
--   `Scrape`                            Drift/Scrape      (T-097, built)
-- Every number of this feature is in this one file, sound and look alike.
--
-- Angles are DEGREES in this table and radians nowhere in it, the same way `Config.Drift`
-- keeps `MinSlipAngleForDrift` in degrees: a number a human tunes is a number a human can
-- read. The modules convert once.

return {
	-- ------------------------------------------------------------------ tyre marks
	-- The rubber a sliding wheel leaves on the tarmac, and its scuff on the road's gravel: since
	-- T-269 a see-through mesh RIBBON on the road's own surface, one strip a wheel
	-- (`Drift/GroundMarks.rubberSpec`, features/car-fx.md "Rubber on the tarmac"), not a Trail.
	Marks = {
		Seconds = 5, -- s a mark stays on the road, and therefore how much of a corner you can
		-- still see behind you. It dries over all of it and fades over the last
		-- `1 - FadeAt` of it
		Width = 1.2, -- normal width in studs. A little under `Config.Drift.WheelWidth`.
		MinWidthRatio = 0.25, -- minimum share of each material width during a slide (T-207).
		-- User, 2026-11-14: narrow down to 25% width, not 25% thinner.
		Lift = 0.25, -- studs the smoke and dust sources sit ABOVE the contact patch (the
		-- ribbon has its own, `Ribbon.Lift`). It was the trails' lift, OURS, and
		-- MEASURED rather than chosen. A trail drawn exactly in the road's
		-- surface z-fights with it, so there has to be some.
		--
		-- IT WAS 0.05 AND THAT WAS NOT ENOUGH, and that is half of the
		-- user's vanishing-mark bug. The other half -- the body's cosmetic
		-- lean swinging the patches through six tenths of a stud -- is
		-- cancelled outright in `Drift/Wheels` and is not paid for here.
		-- What is left is the car's own ride height moving as the model
		-- lands it on the road each step, plus a little pitch over a grade.
		-- Measured over a 30-second drive of the generated road, with the
		-- lean already cancelled, the contact patches ranged from 0.166
		-- studs BELOW the road to 0.248 above it at a lift of 0.05.
		--
		-- AT 0.25, over a 60-second drive: 7 frames out of 14 400 samples
		-- dipped below the road, by at most 0.031 studs, and the worst
		-- float was 0.69. THE ASYMMETRY IS THE POINT -- a mark below the
		-- road vanishes, which is the bug, and a mark above it still
		-- draws -- so the error is pushed upward deliberately.
		--
		-- THE COST IS THAT A MARK FLOATS, up to about seven tenths of a
		-- stud over a grade. It is the user's eye that decides whether
		-- that reads; the alternative is a raycast per wheel per frame,
		-- which would place every mark exactly on the road and allocate a
		-- `RaycastResult` a wheel a frame to do it.
		FadeAt = 0.6, -- 0..1 of the lifetime the fade to invisible starts at. The last
		-- 40 per cent of a mark's life is it fading away, which is what
		-- stops five hundred marks ending in a hard edge

		-- THE RIBBON (T-269). One strip a wheel: a cross-section every few studs, mitred
		-- through bends, the newest following the tyre; laid on the spline road's own surface
		-- (`Spline.terrainXYZ`, which is the tarmac, its gravel bevel and its gravel runoff),
		-- not the ground mesh. See-through by vertex alpha: its edges, its ends and its age.
		Ribbon = {
			Wheels = 4,
			Sections = 64, -- cross-sections in each wheel's ring. THE MESH BUDGET (features/
			-- ground-trial.md) is the limit: 64 x 4 points x 4 wheels is 1 024 vertices. MEASURED
			-- (DR-Lane3, Road ahead and behind Longest): at 96 x 6 (2 304) the client ran out of
			-- EditableMesh memory streaming the road ("Failed to create EditableMesh ... memory
			-- budget"); without this ribbon it did not. At a section every 3 studs, 62 sections
			-- is about 185 studs of mark a wheel; a longer one loses its oldest end early
			ReOrigin = 800, -- studs a strip's origin may lag the tyre before it moves
			Spacing = 3, -- studs between cross-sections on a straight run...
			MinSpacing = 0.4, -- ...and down to this through a bend, a new one whenever the path
			TurnDegrees = 4, -- has turned this far since the last. So a curve is a curve
			FadeInStuds = 1.2, -- a mark comes in over this much of its start (short: rubber
			-- goes down the moment the tyre lets go), and fades out at its end
			BlendSeconds = 0.15, -- rubber to gravel scuff (and back) blends over this
			WidthSeconds = 0.1, -- the T-207 narrowing, smoothed so it never steps
			TileLength = 4, -- studs of mark one repeat of the streak texture covers
			AgeLevels = 20, -- how many steps the drying and fading are rewritten in (0.25 s)
			Lift = 0.08, -- studs over the road's surface. MEASURED against the drawn road mesh: at
			-- 0.05 the rubber sat 0.021 to 0.052 over it (none under); 0.08 keeps a margin for
			-- depth precision far off (features/car-fx.md "Rubber on the tarmac")
			MaxSnap = 1.5, -- studs a point may move off the car's plane to reach the road
			Material = Enum.Material.SmoothPlastic, -- rubber smeared flat: a little sheen
			Transparency = 0.02, -- the parts' own. ABOVE 0 IS THE POINT: only then is vertex
			-- alpha see-through (measured). 0.001 is still drawn solid

			-- How hard a wheel marks, 0..1, which is how much of the mark shows: the slip past
			-- that wheel's threshold, and its LOAD -- the wheel pressed hardest into the road
			-- leaves the darkest rubber.
			MinIntensity = 0.55, -- at the first degree past the threshold...
			IntensitySlipDegrees = 35, -- ...full this far past it
			HandbrakeIntensity = 0.7, -- a locked wheel with no slip to speak of
			LoadWeight = 0.35, -- how much the load moves it, either way of the wheels' average
			LoadSpread = 0.3, -- studs of suspension travel past the average that count as all
			IntensitySeconds = 0.12, -- eased over this, so the darkness never steps

			-- The streak texture, made in code (an `EditableImage`). Grey, tinting the rubber:
			-- fine tread lines along the travel, a little grit. Nothing is uploaded.
			Texture = {
				Width = 64,
				Height = 256,
				Seed = 269,
				Base = 0.95,
				StreakDepth = 0.4, -- tread lines: the rubber laid unevenly across the tyre
				StreakWobble = 0.3,
				Flecks = 90, -- grit and flecks of rubber
				FleckBand = 0.5,
				FleckLight = 1.0,
				FleckDark = 0.55,
			},
		},

		-- The ribbon's cross-section, from its outer edge in, mirrored: 4 points across. FLAT:
		-- rubber lies on the tarmac, it does not dig in (no berm, no walls). `Offset` is the
		-- share of the half-width out from the centre; `Height` and `Tilt` are zero here, kept
		-- for the shape the grass's ribbon shares; `Weight` 0 keeps every normal the road's own,
		-- so the rubber takes the light exactly as the tarmac under it does. (Each look's
		-- `Alpha` does the soft edge.)
		Profile = {
			{ Offset = 1.00, Height = 0, Tilt = 0, Weight = 0 }, -- the edge: nothing
			{ Offset = 0.30, Height = 0, Tilt = 0, Weight = 0 }, -- the dark middle, flat between:
			-- the alpha ramps from the edge in, the soft shoulder
		},

		-- The two looks, one entry per `Profile` point: `Colour` when laid, `DryColour` at the
		-- end of its life, `Alpha` at full strength. `Opacity` scales the whole look; how much
		-- of it shows is that times the wheel's intensity, the soft ends and the age.
		Rubber = { -- on the tarmac: burnt rubber, darkest along the middle where it pressed
			Opacity = 1, -- MEASURED: at 0.85 a 20-degree slide laid 0.64 at most and read faint
			HeightScale = 0,
			TiltScale = 0,
			Points = {
				{ Colour = Color3.fromRGB(32, 31, 32), DryColour = Color3.fromRGB(44, 43, 44), Alpha = 0 },
				{ Colour = Color3.fromRGB(20, 19, 20), DryColour = Color3.fromRGB(36, 35, 36), Alpha = 0.95 },
			},
		},
		Scuff = { -- on the road's gravel bevel and gravel runoff: stones pushed aside
			Opacity = 0.7,
			HeightScale = 0,
			TiltScale = 0,
			Points = {
				{ Colour = Color3.fromRGB(100, 92, 80), DryColour = Color3.fromRGB(112, 104, 92), Alpha = 0 },
				{ Colour = Color3.fromRGB(84, 76, 64), DryColour = Color3.fromRGB(100, 92, 80), Alpha = 0.75 },
			},
		},
	},

	-- ------------------------------------------------------------------ tyre heat
	-- PER WHEEL, 0..1, and the one piece of state this module keeps between frames.
	-- It rises while that wheel is actually sliding, faster the harder it is sliding, and
	-- falls when it stops. ONE thing reads it now: the stylized smoke's rate. The mark's
	-- darkness used to as well, through a rubber-per-stud curve, and that ramp is gone
	-- (features/car-fx.md "The darkness ramp that was built and removed"). THE HEAT IS
	-- NOT GONE WITH IT, because the smoke the user approved is built on it.
	--
	-- "How hard it is sliding" is the SLIP SPEED -- `speed * |sin(slip)|`, the speed the
	-- contact patch is being dragged sideways across the road. That is the number a real
	-- tyre heats on, and it is the honest one here too: a car fully sideways at walking
	-- pace heats slowly, and the same angle at speed heats fast.
	Heat = {
		FullSlipSpeed = 60, -- studs/s of sideways drag that counts as heating at full rate
		RiseSeconds = 2.5, -- s from cold to fully heated AT `FullSlipSpeed`. Longer at less
		FallSeconds = 4, -- s from fully heated back to cold once the wheel stops working.
		-- Slower than the rise, because a tyre cools slower than it heats
		IdleSlipSpeed = 3, -- studs/s of drag below which the tyre is COOLING, whatever the
		-- four gates say. MEASURED, and it is not a nicety: a car that
		-- has caught a slide and rolled to a crawl keeps a residual slip
		-- angle of a few degrees, so its rear gates stay open at a slip
		-- speed of about 0.1. Without this floor the heat could not rise
		-- (nothing was happening) and could not fall (the gate said it
		-- was sliding), and it sat at 0.56 four seconds after the drift
		-- had ended -- a car idling in a cloud of its own stylized smoke
	},

	-- ------------------------------------------------------------------ smoke
	-- TWO LAYERS, both on the first of that wheel's two attachments, so each puff leaves a
	-- contact patch and not an axle. Built-in particle textures only.
	--
	--   `Smoke`     the DIFFUSE layer. Realistic, soft, spreads wide and shares the air
	--               with the other three wheels. It is the body of the cloud, and the user
	--               approved it as it is -- it is not changed here.
	--   `Stylized`  the layer ON TOP. Tight, bright, short-lived and clearly leaving ONE
	--               wheel, so a glance can trace smoke back to the tyre making it. It
	--               builds with that wheel's own `heat` rather than with the car's slip
	--               angle, so a wheel that has been sliding for three seconds is visibly
	--               working harder than one that has just stepped out.
	Smoke = {
		Texture = "rbxasset://textures/particles/smoke_main.dds", -- BUILT IN. Nothing is
		-- uploaded for this feature (features/car-fx.md "Art and sound")
		RateMin = 8, -- particles/s at the smallest slide that marks at all
		RateMax = 60, -- particles/s at 180 degrees of slip. Lerped by `slip / pi`
		Lifetime = { 0.8, 1.6 }, -- s, min and max per particle
		SizeStart = 2.5, -- studs when a particle is born
		SizeEnd = 11, -- studs when it dies. Smoke expands; this is the whole of why it
		-- reads as smoke and not as dust
		Transparency = 0.55, -- at its thickest, a quarter of the way through its life
		Speed = { 2, 6 }, -- studs/s a particle leaves the contact patch at
		SpreadDegrees = 18, -- cone half-angle it leaves in
		RiseAcceleration = 6, -- studs/s^2 upward. Smoke rises; our gravity does not apply
		-- to a particle and nothing here asks it to
		Drag = 1.5, -- how fast a particle gives up the speed it was born with
		RotationDegrees = { -180, 180 }, -- it is one texture, so each puff is turned a
		-- random amount or the cloud reads as a pattern
		RotationSpeed = { -30, 30 }, -- deg/s
		LightEmission = 0, -- flat. Smoke is lit, not glowing
		LightInfluence = 1, -- and it takes the world's light
	},

	-- ------------------------------------------------------- the stylized layer
	-- The second emitter, on top of the diffuse one, and everything about it is chosen so
	-- that A PUFF CAN BE TRACED BACK TO THE WHEEL THAT MADE IT: small, so four of them do
	-- not merge into one cloud; slow and low-spread, so it stays over its own contact
	-- patch; bright and opaque, so it reads against the diffuse layer behind it; and
	-- short-lived, so the shape stays near the car rather than smearing down the road.
	--
	-- ITS RATE IS THE ONLY THING THAT MOVES, and that is deliberate rather than lazy:
	-- `Size`, `Transparency`, `Lifetime` and `Speed` are a `NumberSequence` or a
	-- `NumberRange` each, which are objects, and writing one every frame is the
	-- allocation this feature exists not to do (features/car-fx.md "The budget").
	Stylized = {
		Texture = "rbxasset://textures/particles/smoke_main.dds", -- BUILT IN, same sheet
		RateMin = 0, -- particles/s at zero heat. ZERO, so a wheel that has only just
		-- stepped out shows nothing but the diffuse layer, and the stylized
		-- one is visibly the thing that BUILDS
		RateMax = 42, -- particles/s at full heat
		Lifetime = { 0.30, 0.55 }, -- s. Short: a defined puff, not a smear
		SizeStart = 0.9, -- studs. Small enough that four of them stay four of them
		SizeEnd = 4.2, -- studs. It still expands, just far less than the diffuse layer
		Transparency = 0.18, -- much more opaque than the diffuse 0.55: this is the layer
		-- that has to read ON TOP of the other one
		Speed = { 9, 15 }, -- studs/s. Faster off the patch than the diffuse layer, which
		-- is what makes it read as being FLICKED off a spinning tyre
		SpreadDegrees = 7, -- a tight cone, not a cloud. THIS is the number that makes a
		-- puff traceable to one wheel; widen it and the four merge
		RiseAcceleration = 14, -- studs/s^2 up. It lifts away quickly and is gone
		Drag = 4.5, -- and gives up its speed quickly, so it stops near the wheel
		RotationDegrees = { -180, 180 },
		RotationSpeed = { -140, 140 }, -- much faster than the diffuse layer's 30: a
		-- tumbling puff reads as being thrown, not as drifting air
		LightEmission = 0.35, -- a little of its own light, so it stays visible inside the
		-- darker diffuse cloud rather than being swallowed by it
		LightInfluence = 0.6,
		EmitAngleDegrees = 35, -- how far BACKWARD along the car the cone is tilted, off
		-- straight up. A puff thrown back off the patch belongs to
		-- that patch; one going straight up could be any wheel's.
		-- THIS IS WHY THE STYLIZED EMITTER LIVES ON THE WHEEL'S SECOND
		-- attachment and the diffuse one on its first: the tilt is the
		-- attachment's own `Orientation`, and the diffuse layer is
		-- approved as it is and must not be tilted with it. A rotation
		-- does not move a `Trail`, which reads the two attachments'
		-- POSITIONS, so the mark is untouched either way
	},

	-- ------------------------------------------------------------------ the four gates
	-- What has to be true before a wheel marks and smokes
	-- (features/car-fx.md "Tyre marks and smoke: per wheel, per surface, gated on four
	-- things"). Every one of these is read by `Drift/Wheels` and nothing else.
	Gates = {
		-- THE ONE THAT SELLS IT. The front wheels are DRAWN pointing along the travel
		-- (`Drift/Render`: the model has no steering angle, so the drawn angle is read off
		-- the slip angle), which means a front tyre is not sliding until the slip angle
		-- exceeds that drawn angle. So the fronts' threshold is `slip - MaxSteerDegrees`
		-- and the rears' is zero: the rears mark first and alone through a small slide,
		-- and the fronts join in once it is a big one.
		MaxSteerDegrees = 30,

		-- A FLOATING-POINT FLOOR, NOT A GATE, AND IT IS OURS. The reference's rear
		-- threshold is literally `slip > 0`, which is right in its model because its drift
		-- angle is exactly zero when it is not drifting. Ours is an `atan2` of a velocity
		-- that gravity and grip are always nudging, so a car driving dead straight reads a
		-- slip angle of about a millionth of a degree and `> 0` would mark the whole road
		-- black. Half a degree is two hundred times smaller than
		-- `Config.Drift.MinSlipAngleForDrift`, so it changes nothing a player can see and
		-- it is not a second drift threshold.
		MinSlipDegrees = 0.5,

		StopSlipDegrees = 0.25, -- the same floor, but for a wheel that is ALREADY marking.
		-- A gate with one threshold chatters on anything that sits on
		-- it, and chatter in this gate is a hole in the mark: measured,
		-- a car running at 44 studs/s with its slip angle hovering on
		-- 0.5 degrees switched its rear marks on and off repeatedly at a
		-- density of 0.00. Start at `MinSlipDegrees`, keep going down to
		-- this, stop below it. A car genuinely running straight reads
		-- about 0.09 degrees, well under both, so nothing latches on

		MinMarkSpeed = 15, -- studs/s. A wheel STARTS marking only at or above this (T-151).
		-- Pulling away from rest with a finger held, the slip angle is an
		-- `atan2` of a velocity of a stud or two a second, and it swings
		-- several degrees either way: measured in DR-Lane3, rears marking
		-- from 0.1 studs/s, chattering on and off up to ~14 studs/s. A wheel
		-- ALREADY marking ignores this and keeps going down to
		-- `StopSlipDegrees`, so a drift that slows to a crawl keeps its mark

		MinThrottle = 0.2, -- 0..1. A car coasting sideways leaves nothing. `s.throttle` is
		-- eased in over `Config.Drift.FullThrottleSeconds` and is never an
		-- input, so this is a gate on how hard the car is driving and not
		-- on a finger
		MinHandbrakeSpeed = 3.6, -- studs/s. Below this the handbrake smokes nothing, which
		-- is what stops a parked car with the brake latched on from
		-- standing in a cloud of its own

		MaxSlipDegrees = 180, -- the angle the smoke rate is full at. The reference lerps
		-- by `slip / pi`, and pi radians is this
	},

	-- ------------------------------------------------------------------ surfaces
	-- A smoke's and a puff's colour, per SMOKING surface (the marks are `Marks.Rubber`). Only tarmac smokes: grass and
	-- gravel are `Ground` below (T-188), which tears up the ground instead. `Hit.surface`
	-- names each wheel's ground on the spline road; anything unnamed is `Default`. `dirt` is
	-- a look with no ground that is dirt, kept for the day there is some.
	Surfaces = {
		tarmac = {
			SmokeColour = Color3.fromRGB(226, 226, 230), -- burnt rubber is near white
			PuffColour = Color3.fromRGB(255, 252, 246), -- the stylized layer, a shade
			-- brighter and warmer than the diffuse one so
			-- it separates from the cloud behind it
		},
		dirt = {
			SmokeColour = Color3.fromRGB(190, 166, 132),
			PuffColour = Color3.fromRGB(214, 192, 156),
		},
	},

	-- The surfaces a car is actually built effects for, in order. THE INSTANCE BUDGET IS
	-- THIS LIST:
	--
	--   per car = 4 wheels x (2 Attachments + surfaces x (1 Trail + 2 Emitters))
	--
	-- This original tarmac-only layer is 4 x 5 = 20 at one smoking surface. With the
	-- off-road layer and fixed emitter anchors below, the current total is 88 (T-265; 64 at T-207),
	-- all built once when the rig is caught. The old tarmac layer was 16 before stylized
	-- smoke, 32 with four darkness rungs, 28 with three, then 20 after removal (T-062).
	-- A second smoking surface adds 12 instances.
	Built = { "tarmac" },
	Default = "tarmac", -- what a wheel is told it is standing on when its `Hit` has no
	-- `surface` (the parts world, the playground). The spline road names every hit (T-188)

	-- ------------------------------------------------------------------ off the road (T-188)
	-- What a wheel does on GRASS and GRAVEL instead of smoking (features/car-fx.md "Off the
	-- road"). The user: *"it should look like the weight of the car is tearing through the
	-- grass"*. Per wheel, from that wheel's own `Hit.surface`:
	--
	--   * the tarmac smoke (both layers) FADES OUT over `FadeSeconds` when the wheel leaves
	--     tarmac, and back in when it returns -- a rate scaled by a per-wheel mix, not a switch
	--   * on grass the mark is a flattened-grass line (`Grass.FlatMark`), and above
	--     `Grass.TrenchSlipDegrees` of slip a wider brown TRENCH (`Grass.TrenchMark`) replaces
	--     it (T-205). Each marking wheel emits green OR brown, never both; hysteresis keeps
	--     the choice steady, while marks already laid behind the car fade normally
	--   * on grass, `Grass.Clippings` (green bits) are kicked up behind the wheel, and
	--     `Grass.Dirt` (brown clods) blends in around the trench threshold
	--   * on gravel, a pale scuff mark and a tan dust cloud (`Gravel`). Kept to one emitter
	--
	-- BUILT-IN TEXTURES ONLY: the bits are `SquareParticle.png`, flat-coloured squares, which
	-- is the low-poly look. Nothing uploaded.
	--
	-- RUTS THAT LOOK CUT IN (T-265). A grass mark is a MESH RIBBON laid on the ground, not a
	-- trail (`Drift/GroundMarks`, features/car-fx.md "Ruts cut into the ground"): one per wheel,
	-- a cross-section every few studs, with a shaped profile -- a berm either side, a wall that
	-- leans in and a floor -- whose normals catch the scene's light, so one wall is lit and the
	-- other in shade, day or night. Its outer strips are drawn as the ground under them is (its
	-- material, colour and normal), so it has no edge to see; its inner ones are wet mud with a
	-- streak texture made in code (nothing uploaded). It comes in at the start of a mark, goes
	-- at the end, and dries and fades back into the ground with age. The flattened line and the
	-- rut are the same ribbon in two looks, blended over `Ribbon.BlendSeconds` where the slide
	-- crosses the trench threshold (T-205's hysteresis).
	--
	-- THE BUDGET: the off-road layer is, per wheel, 1 Trail (gravel) + 3 Emitters, and T-207's
	-- 3 fixed particle-source Attachments; the grass ribbon is one strip a wheel of two
	-- MeshParts and their folder. With the tarmac layer's 2 Attachments + 3 per smoking
	-- surface, one smoking surface is 12 per wheel:
	--   4 x (2 + 3 + 1 + 3 + 3) + 4 x 2 + 1 folder = 57 per car
	-- (88 with T-265's first, trail-built ruts; 64 before T-265; 20 before T-188). All built
	-- once, then switched or rewritten in place. `Drift/Wheels.perCar()` is the formula.
	Ground = {
		FadeSeconds = 0.2, -- s for a wheel's smoke to fade out when it leaves tarmac, and for
		-- the grass/gravel debris to fade in -- and the same back. Fast, but not a cut

		-- How the grass marks sit on the ground and how long they stay (T-265).
		MarkSeconds = 14, -- s a grass mark lasts. Longer than a tarmac mark (`Marks.Seconds`, 5):
		-- torn ground stays torn. It dries over all of it and fades over the last
		-- `1 - Marks.FadeAt` of it, like every mark
		Lift = 0.06, -- studs the ribbon's lowest points sit over the DRAWN ground under them
		MaxSnap = 1.5, -- studs. A point is moved at most this far off the car's plane to reach
		-- the drawn ground; further (a wall's foot, a tile not drawn yet) and it stays
		-- on the car's plane

		-- The ribbon itself (`Drift/GroundMarks`).
		Ribbon = {
			Wheels = 4, -- strips, one a wheel
			Sections = 96, -- cross-sections in each wheel's ring, two kept as points ahead of the
			-- tyre. THE MESH BUDGET: a client holds about 35 000 EditableMesh vertices with the
			-- ground and the road taking most (features/ground-trial.md). 96 x 8 points x 4 wheels
			-- is 3 072. MEASURED: a first build at 31 000 pushed the road out of budget. It was
			-- 128 (4 096) until T-269 gave the 1 024 to the tarmac's rubber, so the two ribbons
			-- together hold what the grass's alone did. At a section every 3 studs that is about
			-- 280 studs of mark a wheel; the oldest goes first
			ReOrigin = 800, -- studs a strip's origin may lag the tyre before it is moved: a mesh is
			-- at most 2 048 studs across, and sections past its box are let go
			Spacing = 3, -- studs between cross-sections on a straight run...
			MinSpacing = 0.5, -- ...and down to this through a bend, a new one whenever the path has
			TurnDegrees = 4, -- turned this far since the last. So a curve is a smooth curve
			FadeInStuds = 2.5, -- a mark comes in over this much of its start, not with an edge,
			-- and its last segment fades out to nothing when it ends
			BlendSeconds = 0.2, -- flattened line to rut (and back) blends over this along the mark
			WidthSeconds = 0.12, -- the width's T-207 narrowing is smoothed over this, so it never steps
			TileLength = 6, -- studs of the mark one repeat of the streak texture covers
			AgeLevels = 28, -- how many steps the drying and fading are rewritten in (0.5 s each)
			OuterMaterial = Enum.Material.Grass, -- the outer strips: the GROUND'S OWN material, on
			-- its own world UVs, so where the mark meets the grass there is nothing to see
			InnerMaterial = Enum.Material.Ground, -- the berm, walls and floor: soil. MEASURED: Mud's
			-- sheen caught the sky at a chase camera's angle and turned the floor grey (DR-Lane3)

			-- The inner strips' streak texture, made in code at start (an `EditableImage`). Grey,
			-- tinted by the ribbon's colours: lines along the travel, flecks and clods toward
			-- the edges. Opaque: the mark's edges blend into the ground by colour, not alpha.
			-- Nothing is uploaded.
			Texture = {
				Width = 64, -- pixels across the mark
				Height = 256, -- pixels along one `TileLength`; it repeats seamlessly
				Seed = 265,
				Base = 0.94, -- brightness between streaks
				StreakDepth = 0.32, -- how much darker the deepest tread streak is
				StreakWobble = 0.35, -- how much a streak varies along its length
				Flecks = 260, -- clods and flecks in one tile...
				FleckBand = 0.32, -- ...mostly within this share of the width from either edge
				FleckLight = 1.0, -- a dry clod catching the light
				FleckDark = 0.5, -- a wet one in shadow
			},
		},

		Grass = {
			TrenchSlipDegrees = 30, -- |slip| at which the trench starts being cut
			TrenchStopDegrees = 25, -- |slip| it has to fall under to stop. The gap is the
			-- hysteresis: a slide sitting on 30 must not flick the trench on and off
			DirtStartDegrees = 22, -- |slip| the dirt spray starts at, and...
			DirtFullDegrees = 40, -- ...is full at. A ramp, so the spray BLENDS in around the
			-- trench rather than popping on with it
			ClippingsAtFullDirt = 0.5, -- the grass bits are cut to this share once the dirt is
			-- full: deep slides throw mostly dirt
			FullSlipDegrees = 90, -- slip at which the debris rates are at their max

			Width = 3.0, -- studs edge to edge: wider than the tyre (1.6), for the soil it
			-- pushes aside. Narrows through a slide like every mark (`Marks.MinWidthRatio`, T-207)
			MinWidthRatio = 0.5, -- the ribbon narrows through a slide (T-207) only to this share:
			-- a tyre ploughing sideways still digs its contact patch's length. OURS, and wider
			-- than tyre marks' `Marks.MinWidthRatio` (0.25): at 0.25 a sideways rut was a thin line
			DebrisOffset = 0.95, -- studs left of the contact the clippings and dirt are thrown from

			-- The ribbon's cross-section, from its outer edge in to the floor beside the centre
			-- line, mirrored for the other side: 8 points across. `Offset` is the share of the
			-- half-width out from the centre, `Height` studs over `Lift` (times the look's
			-- `HeightScale`), `Tilt` degrees the surface's normal leans TOWARD the centre (times
			-- `TiltScale`): the inner wall leans hard, so the far wall faces the light and the
			-- near one turns away from it, which is what reads as depth. `Weight`: how much the
			-- point is the mark and not the ground -- 0 at the edge, which is drawn exactly as
			-- the ground under it is, so the mark has no edge to see.
			Profile = {
				{ Offset = 1.00, Height = 0.00, Tilt = 0, Weight = 0 }, -- the outer edge: the ground
				{ Offset = 0.66, Height = 0.10, Tilt = -12, Weight = 0.8 }, -- the berm: soil pushed up
				{ Offset = 0.30, Height = 0.00, Tilt = 50, Weight = 1 }, -- the floor's edge: the wall
				-- runs from the berm down to here, leaning in, and the floor between bowls
			},

			-- The two looks: `Opacity`, how far the mark's colour and shape replace the ground's
			-- (1 all the way), and one entry per `Profile` point, `Colour` when laid and
			-- `DryColour` at the end of its life (it fades back into the ground as well).
			FlatMark = { -- gentle slides: the grass pressed down along the travel, not torn
				Opacity = 0.45,
				HeightScale = 0,
				TiltScale = 0.15,
				Points = {
					{ Colour = Color3.fromRGB(96, 148, 66), DryColour = Color3.fromRGB(96, 148, 66) },
					{ Colour = Color3.fromRGB(104, 152, 70), DryColour = Color3.fromRGB(98, 146, 66) }, -- bent blades, lighter
					{ Colour = Color3.fromRGB(56, 98, 40), DryColour = Color3.fromRGB(66, 110, 46) }, -- pressed flat, darker
				},
			},
			TrenchMark = { -- past `TrenchSlipDegrees`: the rut, cut through to the soil
				Opacity = 1,
				HeightScale = 1,
				TiltScale = 1,
				Points = {
					{ Colour = Color3.fromRGB(100, 88, 56), DryColour = Color3.fromRGB(110, 98, 66) },
					{ Colour = Color3.fromRGB(112, 94, 62), DryColour = Color3.fromRGB(128, 110, 78) }, -- churned berm
					{ Colour = Color3.fromRGB(40, 28, 17), DryColour = Color3.fromRGB(80, 60, 40) }, -- wet floor, drying
				},
			},

			-- How far back the debris is thrown, off straight up. On its own attachment pair
			-- (the trench's), so the stylized smoke's 35 degrees is untouched
			KickAngleDegrees = 60,

			Clippings = {
				Texture = "rbxasset://textures/particles/SquareParticle.png", -- BUILT IN
				Colour = Color3.fromRGB(96, 156, 64),
				RateMin = 25, -- particles/s at the smallest slide that marks
				RateMax = 90, -- at `FullSlipDegrees`
				Lifetime = { 0.45, 0.8 },
				SizeStart = 0.42, -- studs. Chunky, low-poly bits
				SizeEnd = 0.26,
				Transparency = 0, -- solid bits
				FadeIn = 0, -- opaque from birth, fade only at the end
				Speed = { 12, 22 },
				SpreadDegrees = 28,
				RiseAcceleration = -60, -- NEGATIVE: gravity. Bits fall back down
				Drag = 1.2,
				RotationDegrees = { -180, 180 },
				RotationSpeed = { -400, 400 }, -- tumbling
				LightEmission = 0,
				LightInfluence = 1,
			},
			Dirt = {
				Texture = "rbxasset://textures/particles/SquareParticle.png",
				Colour = Color3.fromRGB(92, 64, 38),
				RateMin = 20, -- at the start of the dirt ramp
				RateMax = 110, -- full ramp, at `FullSlipDegrees`
				Lifetime = { 0.5, 0.9 },
				SizeStart = 0.55, -- clods, bigger than the grass
				SizeEnd = 0.35,
				Transparency = 0,
				FadeIn = 0,
				Speed = { 16, 28 }, -- thrown harder than the grass
				SpreadDegrees = 22,
				RiseAcceleration = -70,
				Drag = 0.8,
				RotationDegrees = { -180, 180 },
				RotationSpeed = { -300, 300 },
				LightEmission = 0,
				LightInfluence = 1,
			},
		},

		-- GRAVEL: the bevel at the road's edge and the tight-cliff strips. A pale scuff and a
		-- dust cloud, no smoke -- loose stone does not burn rubber. Kept to one emitter.
		Gravel = {
			-- Its mark is the tarmac ribbon's `Marks.Scuff` look (T-269).
			Dust = {
				Texture = "rbxasset://textures/particles/smoke_main.dds",
				Colour = Color3.fromRGB(176, 160, 132),
				RateMin = 10,
				RateMax = 45,
				Lifetime = { 0.6, 1.1 },
				SizeStart = 1.6,
				SizeEnd = 6,
				Transparency = 0.5,
				Speed = { 3, 7 },
				SpreadDegrees = 25,
				RiseAcceleration = 2,
				Drag = 1.5,
				RotationDegrees = { -180, 180 },
				RotationSpeed = { -30, 30 },
				LightEmission = 0,
				LightInfluence = 1,
			},
		},
	},

	-- The instance names a rig's effects are given, so `Drift/Wheels`, the tests and
	-- anything that inspects a car agree on what they are called (CONTRACTS.md).
	--
	-- THERE IS NO FOLDER. The eight attachments hang directly off the car's `Body` -- an
	-- Attachment has to be parented to a BasePart to have a position at all -- and each
	-- wheel's Trail and ParticleEmitter hang off its first attachment. A folder would be a
	-- seventeenth instance for nothing.
	Names = {
		Attachment = "FxA_%s_%s", -- wheel name, then "L" or "R": with "_Emitter" on the end, the
		-- diffuse smoke and dust source ("L") and the stylized smoke's ("R") (T-207)
		Emitter = "FxSmoke_%s_%s", -- wheel name, then surface. The DIFFUSE layer
		Stylized = "FxPuff_%s_%s", -- wheel name, then surface. The STYLIZED layer
		TrenchAttachment = "FxT_%s_%s", -- wheel name, then "L": with "_Emitter" on the end, the
		-- clippings and dirt source (T-188, T-207)
		RubberFolder = "FxRubberMarks", -- the local car's tarmac and gravel ribbon (T-269): a
		RubberStrip = "FxRubberMarks_%d", -- client-only folder in Workspace, and its MeshParts
		MarksFolder = "FxGroundMarks", -- the local car's grass ribbon: a client-only folder in
		MarksChunk = "FxGroundMarks_%d", -- Workspace, and its MeshParts (T-265)
		GroundEmitter = "FxKick_%s_%s", -- wheel name, then "grass", "dirt" or "dust" (T-188)
		Engine = "FxEngine", -- the one engine `Sound`, on the body (T-064)
		Skid = "FxSkid_%s", -- surface. One `Sound` per surface in `Built`, on the body
		Spark = "FxSpark_%d", -- slot. One anchored part per spark slot, NOT in the car (T-097)
		SparkFolder = "FxSparks", -- the folder the spark parts sit in
		Scrape = "FxScrape", -- the one scrape `Sound`, on the body (T-097)
	},

	-- ------------------------------------------------------------------ engine (T-064, T-125)
	-- A FAKE ENGINE the sound follows (`Drift/Engine`, features/engine-sound.md). The drive
	-- never reads any of it: there is still no engine in the physics.
	Engine = {
		GearCount = 5, -- how many bands the speed range is cut into
		GearLengthMultiplier = 1.5, -- each gear is this much longer than the one before.
		-- At 5 gears the divisor is 13.1875, so a 179 studs/s
		-- car shifts at about 13.6, 34, 64 and 110
		GearOverlap = 10, -- studs/s. How far under a gear's bottom the speed must fall
		-- before it shifts DOWN. Up is at the gear's top exactly
		MinTimeInGear = 0.5, -- s since the last shift before another is allowed

		-- The rpm (`Drift/Engine`). STARTING VALUES, set to be argued with by ear.
		IdleRpm = 1382, -- where the recorded sheet's idle loop was recorded (T-170). It was
		-- 900 with the synthesized sheet, which still plays fine from here.
		-- Sound only: the drive never reads it
		ShiftRpm = 6800, -- rpm at a gear's top: where it upshifts. x1.5 gears drop it to
		-- about 4 500 in the next
		RedlineRpm = 7400, -- the limiter
		RevUpRate = 8, -- /s the rpm chases a higher target (exponential)
		RevDownRate = 6, -- /s it chases a lower one. A shift is this
		LoadResponse = 12, -- /s the load (0 off throttle .. 1 on) chases its target

		-- The drift. Wheel spin, a held gear, revs that do not fall.
		DriftEnterDeg = 10, -- deg of slip before the ENGINE calls it a drift (the model
		-- says 5, and a straight's corrections cross 5 all the time)
		DriftMinSpeed = 15, -- studs/s. Slower than this a slide is not a drift to the engine
		SpinGain = 0.6, -- the rear wheels run `1 + SpinGain * sin(slip)` times the road
		DriftClimbRpm = 300, -- rpm/s the drift's floor climbs (it is a ratchet: it only
		-- falls when the ceiling below comes down on it)
		-- THE CEILING (T-147, the user: the limiter "should only really happen in an
		-- intense drift when all 4 tires are going"). An ordinary drift's revs stop here,
		-- feathering and the entry flare at most `FeatherRpm` over it
		DriftCeilingRpm = 6500,
		IntenseFromDeg = 40, -- deg of slip where the ceiling starts to rise. A held 25-35
		-- degree drift stays at DriftCeilingRpm
		IntenseFullDeg = 60, -- deg where it reaches IntenseCeilingRpm. The limiter is
		-- reachable from about 45 degrees. As the angle closes the
		-- ceiling falls and the revs leave the top
		IntenseCeilingRpm = 9000, -- the ceiling at IntenseFullDeg: far enough past the
		-- redline that the limiter stutters at its full LimiterHz
		-- (from about 8 300 up; any lower and the cuts come slower)
		EntryFlareRpm = 900, -- the clutch kick at a drift's start
		FlareSeconds = 0.35, -- about how long it takes to settle
		FeatherRpm = 350, -- rpm either way from feathering
		FeatherSlipRate = 1.0, -- rad/s of slip change that is full feathering
		FeatherResponse = 8, -- /s the feathering is smoothed at
		HookUpSeconds = 0.6, -- leaving a drift: the extra revs ease away over about this,
		-- and the gear stays held until it is up
		TransitionSlipDeg = 12, -- deg of slip each side for a flick to count as one
		TransitionLiftSeconds = 0.25, -- off throttle through a flick
		TransitionWindowSeconds = 1.0, -- s from sideways one way to sideways the other for
		-- it to count as a flick rather than two corners
		ShiftLiftSeconds = 0.12, -- off throttle for an upshift

		-- The limiter: the stutter at the top of a long drift.
		LimiterHz = 10, -- cuts a second
		LimiterDropRpm = 450, -- how far a cut lets the rpm fall
		LimiterFallRate = 30, -- /s it falls at during a cut
		BlipRpm = 700, -- a downshift's blip
		BlipSeconds = 0.15,

		-- THE LAYERED SOUND (T-129, two ladders since T-170). A "sheet" is ONE UPLOADED FILE
		-- holding every engine loop, and each `Sound` plays its own slice of it through
		-- `PlaybackRegion` and `LoopRegion` -- one upload instead of one per loop. Each slice
		-- is padded with a quarter second of itself either side in the file, so the codec's
		-- smear at a region's edge is engine, not silence.
		--
		-- A sheet has TWO LADDERS, `On` (on throttle) and `Off` (off throttle). Each is
		-- crossfaded by rpm ON ITS OWN, between its own rev points, and the load crossfades
		-- between the two. So the ladders need not have the same number of loops, nor sit at
		-- the same revs: recorded loops don't (features/engine-sound.md "Next").
		--
		-- `Sheet` NAMES THE ONE THAT PLAYS: switching sound is this one line. `Sheet = nil`
		-- (or a sheet with no `SoundId`) falls back to the one clip below.
		Sheet = "Recorded" :: string?, -- "Synth" is the synthesized sound it replaced
		Sheets = {
			-- Our own synthesized loops, picked by the user on 2026-11-11 (DECISIONS.md), at
			-- six rev points, the same six on and off throttle. Built by
			-- `..\art\generated\sfx-engine\set-v1\build_set.py`.
			Synth = {
				SoundId = "rbxassetid://132857262391195" :: string?, -- engine-sheet.ogg, uploaded 2026-11-12
				Volume = 0.84, -- the loops are normalised to an RMS of 0.16 and "Car idle" is
				-- 0.29: 0.45 x 0.29 / 0.16 keeps the engine bed where it was
				-- in the mix (AUDIO.md "Mix")
				OffLoadVolume = 0.75, -- the off-throttle loops sit this far under the on ones
				LimiterDuck = 0.5, -- volume share left during a limiter cut: the stutter
				MaxPitchShift = 0.6, -- a SAFETY CAP only, past the rev points' 1.52x spacing, so
				-- two loops in a crossfade always agree on the pitch. The louder
				-- of the two is never more than 23% off its own rpm (EngineTests)
				-- Each loop: its rev point, then where it is in the sheet, in seconds.
				On = {
					{ Rpm = 900, Start = 0.25, Length = 2.0 },
					{ Rpm = 1370, Start = 5.45, Length = 2.014604 },
					{ Rpm = 2090, Start = 10.65, Length = 2.009562 },
					{ Rpm = 3190, Start = 15.85, Length = 1.993729 },
					{ Rpm = 4860, Start = 21.05, Length = 2.0 },
					{ Rpm = 7400, Start = 26.25, Length = 1.994604 },
				},
				Off = {
					{ Rpm = 900, Start = 2.85, Length = 2.0 },
					{ Rpm = 1370, Start = 8.05, Length = 2.014604 },
					{ Rpm = 2090, Start = 13.25, Length = 2.009562 },
					{ Rpm = 3190, Start = 18.45, Length = 1.993729 },
					{ Rpm = 4860, Start = 23.65, Length = 2.0 },
					{ Rpm = 7400, Start = 28.85, Length = 1.994604 },
				},
			},
			-- RECORDED LOOPS, set B, picked by the user by ear on 2026-11-13 (DECISIONS.md,
			-- T-170): recordings from inside the car low down, from outside it from about
			-- 6 300 rpm up. Where they came from and the permission is in
			-- `assets/audio/sfx-engine/MANIFEST.md`. Each `Rpm` is the recording's MEASURED
			-- revs, so two loops in a crossfade sit at the same pitch.
			--   * The ladders do not match: five loops on throttle, three off.
			--   * Nothing was recorded on throttle under 3 261 rpm, so pulling away pitches
			--     that loop far down (accepted, features/engine-sound.md).
			--   * Its idle loop sits at 1 382 rpm: `IdleRpm` goes to 1382 with this sheet.
			Recorded = {
				SoundId = "rbxassetid://126307015260351" :: string?, -- engine-sheet-b.ogg, uploaded 2026-11-13
				Volume = 0.84, -- the loops are at the synthesized ones' loudness (RMS 0.16)
				OffLoadVolume = 0.75,
				LimiterDuck = 0.5,
				MaxPitchShift = 2.0, -- NO CAP in practice. The rev points are up to 2.95x apart
				-- (1 382 to 4 074 off throttle), and a cap that bit inside a
				-- crossfade would leave its two loops at different pitches
				On = {
					{ Rpm = 3261, Start = 0.25, Length = 3.552917 },
					{ Rpm = 5034, Start = 4.352917, Length = 2.634958 },
					{ Rpm = 5604, Start = 7.537875, Length = 5.782875 },
					{ Rpm = 6348, Start = 13.87075, Length = 3.1165 },
					{ Rpm = 7124, Start = 17.53725, Length = 2.3455 },
				},
				Off = {
					{ Rpm = 1382, Start = 20.43275, Length = 1.788729 },
					{ Rpm = 4074, Start = 22.771479, Length = 3.253062 },
					{ Rpm = 6636, Start = 26.574542, Length = 2.616 },
				},
			},
		},
		-- THE ONE CLIP, until the layered loops (T-123 step 3): its pitch is the rpm's share
		-- of IdleRpm .. RedlineRpm, lerped MinPitch .. MaxPitch, with NO smoothing of its own
		-- -- the rpm has inertia already. The notes below are from when the pitch was road
		-- speed through the gearbox (T-064); the sweep argument still holds.
		OffLoadVolume = 0.7, -- share of `Volume` off throttle. A lift is heard as quieter
		-- OURS, BOTH OF THEM. The reference's live on its car config and are not in the
		-- decompile. What CAN be argued from numbers rather than from an ear:
		--   * the sweep. 0.7 -> 2.2 is a ratio of 3.14, which is about what a real gear
		--     sweeps (roughly 2 200 to 7 000 rpm). Keep the RATIO near 3 if these move
		--   * the shift. The drop in pitch at each upshift is what a shift sounds like,
		--     and the gearbox's own geometry decides it: 2.20 -> 1.44 at the 1-2, then
		--     1.19, 1.03 and 0.92 at the three above it (measured, T-064). Narrow the
		--     sweep and the 4-5 shift stops being audible as a shift at all
		--   * the floor. The clip is a CAR IDLE and 4.64 s long, so at 0.7x a loop cycle
		--     runs 6.63 s and its content drops about five semitones BELOW idle, into the
		--     range a phone speaker reproduces least
		-- THE LAST WORD IS THE USER'S EAR and nothing here is a substitute for it.
		MinPitch = 0.7,
		MaxPitch = 2.2,
		-- AirbornePitch is MaxPitch: wheels up, engine free-revving

		-- "The squeal sits on top, the engine under it" (AUDIO.md "Mix"). The engine is a
		-- bed and never the loudest thing in a corner.
		Volume = 0.45,
		SoundId = "rbxassetid://5015124019", -- Creator Store, "Car idle" by 6ifqi, 4.64 s.
		-- Used BY ID: nothing is uploaded and there is no master
		-- (AUDIO.md "Sounds"). The user picked it by ear on
		-- 2026-11-04 and it is not an agent's to swap
		RollOffMin = 15, -- studs. Inside this the engine is at full volume
		RollOffMax = 180, -- studs. Past this it is gone. `InverseTapered`, so another
		-- player's car is heard WHERE IT IS and not everywhere
	},

	-- ------------------------------------------------------------------ skid (T-064)
	-- One looping clip per surface, all alive at once, each one's volume lerped rather
	-- than switched (features/car-fx.md "Skid sound").
	--
	-- THE CLIP NEVER STOPS WHILE THE CAR IS ROLLING (T-083), which is the reference's own
	-- shape. A clip that is started at the top of every drift re-plays its own loop seam at
	-- the top of every drift, and a 3-second clip's seam becomes a thing the player can
	-- hear coming. Left running -- at volume 0 when nothing is sliding -- the seam lands
	-- wherever it lands, under whatever the car is doing, and stops being a moment.
	--
	-- THE VOLUME IS THE LATERAL SLIDE SPEED, not the slip angle (T-083 round two, the
	-- user's call on 2026-11-08: "it's volume should be based off how hard it's actually
	-- sliding"). `speed * sin(|slip|)` is how fast the contact patch is scrubbing ACROSS
	-- the road, which is one number that is both "how fast" and "how sideways", and it is
	-- what a real tyre's noise follows. By the angle alone, a car pivoting at walking pace
	-- screamed exactly as loudly as one sliding at 170 studs/s.
	Skid = {
		MinSpeed = 3.6, -- studs/s. Below this, silence -- and the clip stops, along with
		-- airborne. Those are still the only two ways it is not running
		RollVolume = 0, -- the volume of a car that is grounded and above `MinSpeed` but
		-- NOT drifting. ZERO: no tyre sliding, no sound at all.
		--
		-- IT WAS 0.12 FOR ONE ROUND AND THE USER REJECTED IT (2026-11-08):
		-- "the permanent squeel doesn't work for me ... if no tires are
		-- drifting, no squeal should be heard". The argument for it was
		-- that a hiss the squeal grows out of has no silence to click
		-- out of; what it actually gave was a permanent noise under
		-- ordinary driving, which is worse.
		--
		-- THE KEY STAYS, because 0 costs nothing and this is how the
		-- always-on version comes back if the user changes their mind:
		-- raise it and a straight car hisses again, with no line of
		-- logic touched. `FxTests` checks both directions.
		--
		-- NOTE THE CLIP STILL RUNS while the car rolls, at volume 0: that
		-- is what keeps the loop seam from being re-heard at the top of
		-- every drift. Silence here is a volume, not a stop.
		MinVolume = 0.08, -- the volume a drift that has just begun plays at, when the
		-- lateral slide is still near nothing. QUIET ON PURPOSE: the
		-- drift threshold is 5 degrees, which a car crosses on any brisk
		-- corner, so this is the volume of the most common sound in the
		-- game. It was 0.25 and the user called the result too loud
		MaxVolume = 0.40, -- the volume at `SlideSpeedForMax`, the top of the squeal. It was
		-- 0.55 (and 1 before that); through the 0.85 master the peak is
		-- now 0.340 against 0.468, a cut of about 2.8 dB at the loudest
		-- moment and far more than that in ordinary driving, because the
		-- slide-speed curve no longer puts a slow pivot at the top. Raise
		-- it for a louder top end; 1 is the original ceiling
		SlideSpeedForMax = 90, -- studs/s of LATERAL slide -- `speed * sin(|slip|)` -- that
		-- the squeal is full at. Replaces the old `MaxSlipDegrees`, which
		-- was 90 degrees and took no notice of speed at all.
		--
		-- IN REAL TERMS, against a 179 studs/s top speed: 90 studs/s
		-- sideways is a car at top speed with 30 degrees of slip, or one
		-- at 127 studs/s with 45 degrees, or one at 90 studs/s fully
		-- sideways at 90. A committed drift at speed reaches it; a pivot
		-- in a car park never does -- a 90-degree spin at 10 studs/s is
		-- at 0.11 of the way up, which is the whole point of the change.
		--
		-- OURS, AND A GUESS AT THE SCALE: the reference's own curve is by
		-- angle, so there is no number to port. Lower it for a squeal
		-- that maxes out earlier, raise it for one that keeps growing
		-- into the big slides
		VolumeLerpSpeed = 1, -- /s. Fading in and out instead of clicking on

		-- The master the mix sets, on top of the `MinVolume`..`MaxVolume` lerp above
		-- (AUDIO.md "Mix"). UNCHANGED at 0.85, so the whole of the round's quietening is
		-- in the two volumes above and is readable there. It is still under 1 so it has
		-- somewhere to go the day anything else is in the mix.
		--
		-- WORTH THE USER'S EAR: 0.85 x `MaxVolume` is 0.340 at the loudest slide the game
		-- has, and the engine bed plays flat at `Engine.Volume` 0.45. So the squeal now
		-- sits UNDER the engine even at its peak, where the mix note says it sits on top.
		-- If the drift stops reading over the engine, the fix is the engine coming down,
		-- not this going back up.
		Volume = 0.85,
		-- One id per CLIP (`Clips` below; not `Built`, which is the smoke's budget). A clip
		-- with no id here gets no sound and no error -- a clip is a pick the user makes by
		-- ear, not a default.
		SoundIds = {
			tarmac = "rbxassetid://124978127809544", -- Creator Store, "tyre_slide" by
			-- knightracers, 3.00 s. By id, nothing uploaded
			dirt = "rbxassetid://113023380554627", -- Creator Store, "dirt" by clean_chips0,
			-- 7.65 s: the OFF-ROAD slide on grass, gravel and dirt (T-222). Picked by
			-- ear by the user 2026-11-15 (assets/audio/sfx-skid-dirt/MANIFEST.md)
		},
		-- OFF THE ROAD (T-222). The clips a car carries, in order, one `Sound` each, built
		-- whether or not the wheels ever reach that ground; a clip with no id above is
		-- skipped. EVERY ONE OF THEM RUNS WHILE THE CAR ROLLS (the T-083 rule, for each
		-- clip): a surface change moves their mix, never restarts one.
		Clips = { "tarmac", "dirt" },
		-- Which clip each ground a wheel can report slides with (`Drift/Wheels.surfaceOf`).
		-- A ground not listed uses the clip of its own name, and a clip with no id falls
		-- back to `Default`'s.
		Clip = { grass = "dirt", gravel = "dirt", dirt = "dirt" },
		-- Each clip's own level, on top of the curve and the master, so two recordings of
		-- different loudness sit at the same place in the mix. 1 is the file as it is
		-- ClipVolume.dirt, MEASURED (T-222): the file is 13 dB quieter than the squeal, so
		-- 4.5 matches their average loudness -- but it swells and dips, and at 4.5 its
		-- loudest 100 ms at the top of the curve is -15.9 dBFS, over the engine bed
		-- (-17.4). 3.2 puts its loudest moment level with the squeal's (-18.8, under
		-- the engine) and its average 3 dB under the squeal's; sample peak -6.8 dBFS.
		-- Roblox caps `Volume` at 10, and the top of the curve here is 0.34 x 3.2 = 1.09
		ClipVolume = { tarmac = 1, dirt = 3.2 },
		CrossfadeSeconds = 0.25, -- s for one clip to fade out and the other in at a change
		-- of ground. Short, but not a cut
		RollOffMin = 12, -- studs. Tighter than the engine's: a squeal is made at the road
		RollOffMax = 150, -- studs
	},
	-- ------------------------------------------------------------ suspension sounds (T-223)
	-- A clunk when a wheel's strut knocks on a bump or catches after a drop, and one bigger
	-- thud when the car lands from a jump (features/car-fx.md "Suspension sounds",
	-- `Drift/SuspensionSound`). Read off the model, never written back. The player's own car
	-- only.
	--
	-- THE CLUNK is the GROUND under one wheel rising faster than the plane the car is on says
	-- it should, by more than `ClunkRate` (T-252): a kerb, a bump, the gravel bevel up onto the
	-- tarmac. Not the wheel's travel closing: the body rolling and pitching in a drift closes
	-- the outside wheels' travel too, and that clunked on every weight transfer. Each wheel
	-- clunks on its own. A wheel that steps DOWN is drawn falling no faster than `DropTime`
	-- lets it; when it is back on its ground, having fallen `CatchMin` or more, it knocks
	-- softer (`CatchShare`).
	--
	-- THE LANDING is the car having had no wheel on the ground for `LandAirTime` and then
	-- touching down, having fallen at `LandMinSpeed` or more. It plays INSTEAD of the clunks: every
	-- wheel's clunk is held off for `LandQuiet` after it.
	Suspension = {
		ClunkRate = 4, -- studs/s a wheel's ground rises over its plane that is a knock. Under
		-- this, silence. A step in the ground lifts a wheel in ONE step (1/120 s), so this is a
		-- 0.033-stud step; the gravel bevel (1 up in 3 across) is this at 12 studs/s straight
		-- at its edge. Was 12 against the wheel's travel (T-223). MEASURED in DR-Lane4
		-- (T-252): hard drifting on the tarmac rises at most 1.1, driving and drifting on the
		-- grass 1.4; crossing the bevel onto the tarmac at 21 to 74 studs/s rises 6 to 13
		ClunkRearm = 0.5, -- a wheel that has knocked may again once its ground rises at under
		-- this share of `ClunkRate`: one knock a bevel, however many steps it takes to climb
		ClunkRateForMax = 24, -- studs/s (a 0.2-stud step, or the bevel straight on at 72
		-- studs/s) at which a clunk is at `ClunkMaxVolume`. Was 60 (a 0.5-stud step) when
		-- the threshold was 12; brought down with it (T-252), or the bevel's 6 to 9 were all
		-- at the bottom of the range
		ClunkSpeedForFull = 80, -- studs/s of the car's speed at which a clunk is at full
		-- volume; slower, it is quieter in proportion...
		ClunkSlowShare = 0.35, -- ...down to this share of it
		ClunkMinVolume = 0.16, -- the clunk just over `ClunkRate`
		ClunkMaxVolume = 0.60, -- at `ClunkRateForMax`. DOUBLED from 0.08 / 0.30 at the
		-- user's word after trying it in a lane (2026-11-15: "make both louder"). Through
		-- the master the peak is 0.51: OVER the squeal's 0.340 and the engine's 0.45, so the
		-- AUDIO.md "Mix" rule (everything else under both) no longer holds for it, by the
		-- user's choice. The quietest slice (Gain 22.3) reaches Roblox's Volume cap of 10
		-- near the top and is clamped there
		ClunkCooldown = 0.18, -- s before the same wheel may clunk again
		ClunkGap = 0, -- s between any two clunks, whichever wheels. 0 (T-252): each wheel is
		-- its own knock, as the user asked ("individual per wheel"); 0.05 made the front pair
		-- over one edge a single knock
		CatchMin = 0.2, -- studs a wheel must have been drawn falling for its catch to knock
		CatchShare = 0.3, -- a catch is the clunk of a step up as high as the fall, times this:
		-- off the bevel onto the grass (a 1-stud fall) is a softer knock than back up it
		PitchJitter = 0.08, -- each clunk plays 1 +- this fast, so repeats are not identical

		LandAirTime = 0.25, -- s with no wheel down before a touchdown counts as a landing.
		-- A kerb hop is shorter, and clunks instead
		LandMinSpeed = 8, -- studs/s falling at touchdown for the landing to play. Under it a
		-- touchdown is soft and silent (the clunks are still held off)
		LandSpeedForMax = 45, -- studs/s falling at which the landing is at `LandMaxVolume`.
		-- A 30-stud drop lands at about 46 studs/s (gravity is 35 studs/s^2)
		LandMinVolume = 0.30,
		LandMaxVolume = 0.76, -- DOUBLED from 0.15 / 0.38 with the clunk (2026-11-15). Through
		-- the master, 0.646: over the squeal and the engine, by the user's choice
		LandQuiet = 0.35, -- s after a landing that no wheel clunks

		Volume = 0.85, -- the master (AUDIO.md "Mix"), as the squeal's and the scrape's

		-- The sounds: Creator Store audio by id, each a SLICE of its file played through
		-- `PlaybackRegion` (assets/audio/sfx-suspension/MANIFEST.md). `Gain` evens out the
		-- slices' levels in their files (each brought to the same peak); `Speed`, if given,
		-- is the clip's own playback speed. No clip: no sound and no error, and the detection
		-- still runs and counts.
		--
		-- CLUNK D, picked by the user 2026-11-15 ("D: mixed"): three knocks out of Pro Sound
		-- Effects' "Vehicle Suspension 1 (SFX)" (Metal Ronk, Creaks), Creator Store, by id
		Clunks = {
			{ Id = "rbxassetid://9120399954", Start = 0.726, Length = 0.289, Gain = 2.6 },
			{ Id = "rbxassetid://9120399954", Start = 1.108, Length = 0.198, Gain = 9.7 },
			{ Id = "rbxassetid://9120399954", Start = 4.452, Length = 0.176, Gain = 22.3 },
		} :: { { Id: string, Start: number, Length: number, Gain: number, Speed: number? } },
		-- LANDING F, picked by the user 2026-11-15 ("F: massive clunk") after turning down a
		-- first four: the first hit of Pro Sound Effects' "Metal Bangs Shaking Large Aircraft
		-- Fuselage 3 (SFX)", Creator Store, by id. Nil would be no landing sound, with the
		-- clunks still held off at a landing
		Landing = { Id = "rbxassetid://9125661444", Start = 0.127, Length = 0.5, Gain = 0.84 } :: {
			Id: string,
			Start: number,
			Length: number,
			Gain: number,
			Speed: number?,
		}?,

		RollOffMin = 12, -- studs, as the squeal's
		RollOffMax = 150, -- studs
		Voices = 4, -- clunk `Sound`s on the body, played round-robin, so one clunk does not
		-- cut the last one off: one a wheel (T-252), so a bevel's four knocks all ring.
		-- Built once, with the car
		ClunkName = "FxClunk_%d", -- voice number
		LandingName = "FxLanding",
	},
	-- ------------------------------------------------------------ floor scraping (T-097)
	-- Sparks and a scrape while the car's floor rests on something (features/car-v2.md
	-- "Floor scraping"). LOOKS ONLY: read off the model's `floorContacts`, never written
	-- back. Programmer art until the art phase.
	Scrape = {
		MaxPoints = 6, -- spark slots per car: one anchored part + one emitter each, built
		-- once. More touching points than this light the fastest ones
		MergeDistance = 0.5, -- studs. Contacts closer than this are ONE point: a floor
		-- point is listed once per segment it touches
		MinSpeed = 0.5, -- studs/s. A point sliding slower than this throws no sparks and
		-- makes no sound: a car resting still on a kerb is silent
		SpeedForMax = 40, -- studs/s of sliding at which the sparks and the scrape are full
		Lift = 0.1, -- studs above the ground the spark part sits
		RateMin = 30, -- sparks/s per point just above `MinSpeed`
		RateMax = 160, -- sparks/s per point at `SpeedForMax`
		Sparks = {
			Colour = Color3.fromRGB(255, 190, 90),
			LightEmission = 1,
			Size = 0.12, -- studs, start; shrinks to nothing over its life
			Lifetime = { 0.15, 0.35 }, -- s
			Speed = { 8, 18 }, -- studs/s
			SpreadAngle = 35, -- degrees about "back and up from the slide"
			Gravity = 60, -- studs/s^2 down
			Drag = 2,
		},
		MinVolume = 0.25, -- the scrape just above `MinSpeed`
		MaxVolume = 0.8, -- at `SpeedForMax`
		VolumeLerpSpeed = 12, -- /s. Fast: a floor hitting the kerb is not a fade-in
		Volume = 0.85, -- the master (AUDIO.md "Mix")
		-- PLACEHOLDER, not the user's pick: Creator Store candidates are in
		-- assets/car-sfx/MANIFEST.md. Nil or "" gives no sound and no error
		SoundId = "rbxassetid://9125686089", -- "Metal Scrape Dragging Car Hood Across
		-- Asphalt 1", Pro Sound Effects, 3.8 s
		RollOffMin = 12, -- studs
		RollOffMax = 150, -- studs
	},
}
