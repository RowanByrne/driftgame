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
	-- The black line a sliding wheel leaves. Per wheel: two `Attachment`s `Width` apart at
	-- the contact patch, and one `Trail` PER BAND strung between them -- enabled and
	-- disabled, never created or destroyed while driving (features/car-fx.md "The budget").
	Marks = {
		Seconds = 5, -- s of `Trail.Lifetime`. How long a mark stays on the road, and
		-- therefore how much of a corner you can still see behind you
		Width = 1.2, -- studs between the two attachments. A little under the tyre, which
		-- is `Config.Drift.WheelWidth` wide
		Lift = 0.25, -- studs the attachments sit ABOVE the contact patch. OURS, and
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
		TextureLength = 0, -- 0 is a solid ribbon. A repeating texture would need an
		-- uploaded asset, and this feature uploads nothing

		MinSegment = 0, -- studs the contact patch must travel before the trail lays
		-- another segment (`Trail.MinLength`). BACK TO ZERO, and the
		-- round it spent at 0.5 is worth writing down because it was the
		-- wrong diagnosis and it made the fault worse.
		--
		-- The mark was breaking up, and 0.5 was a guess at why: a ribbon
		-- 1.2 studs wide advancing a measured 0.104 to 1.261 studs a
		-- frame lays quads wider than they are long, so making each one
		-- longer looked like the cure. It was not. THE BREAKS ARE BAND
		-- CHATTER (see `SwapOverlap`): measured over 1 081 grounded
		-- frames, the rear wheels changed band 58 times and the fronts
		-- 30, and most of those swaps were 0 OR 1 STUD APART. Every swap
		-- starts an empty trail, and `MinLength` then makes that empty
		-- trail wait half a stud before it draws anything -- so 0.5
		-- turned a chain of hairline joins into the long clean dashes the
		-- user photographed.
		--
		-- With the chatter fixed at its source there is nothing for this
		-- to help, and at zero a fresh ribbon starts drawing on its very
		-- next frame. Raise it again only with a screenshot in hand.
		LightInfluence = 1, -- 1 takes the world's light, which is what makes a mark sit
		-- IN the road rather than glow on top of it. 0 would keep it
		-- the same near-black in shade and in sun

		-- HOW DARK A MARK IS. ONE NUMBER, FOR EVERY MARK, AT EVERY SPEED AND ANGLE.
		--
		-- `Trail.Transparency` applies to the WHOLE live ribbon and not to the segment
		-- being laid, so a darkness that varies along a mark cannot be a number at all: it
		-- has to be a LADDER OF TRAILS, one per darkness, switched between. That ramp was
		-- built, driven and removed at the user's call (features/car-fx.md "The darkness
		-- ramp that was built and removed"), because every switch between trails is a hole
		-- in the mark and the holes are inherent to the shape.
		--
		-- 0.52 IS THE MIDDLE RUNG OF THE LADDER THAT WAS THERE (0.70, 0.52, 0.34), which
		-- is the honest place to land: an ordinary drift spent most of its time in the
		-- middle of that ladder, so this reads about as the marks did before, without the
		-- light end going faint or the dark end going to paint. **It is one number and the
		-- whole look of a mark is in it** -- lower is darker.
		Transparency = 0.52,
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
	-- A mark's colour and a puff's colour, per surface. THE GAME HAS ONE SURFACE
	-- (features/car-fx.md "What our model already publishes"): `Drift/World`'s `Hit`
	-- carries a grip multiplier and not a surface name, so every wheel is told `Default`
	-- today. The table is here, and `Built` below is what decides how many instances a car
	-- actually carries -- the day `dirt` is laid, `Hit` grows a name, `dirt` goes in
	-- `Built`, and nothing else in `Drift/Wheels` changes.
	Surfaces = {
		tarmac = {
			MarkColour = Color3.fromRGB(26, 26, 28), -- near black, not black: a pure black
			-- mark reads as a hole in the road
			SmokeColour = Color3.fromRGB(226, 226, 230), -- burnt rubber is near white
			PuffColour = Color3.fromRGB(255, 252, 246), -- the stylized layer, a shade
			-- brighter and warmer than the diffuse one so
			-- it separates from the cloud behind it
		},
		dirt = {
			MarkColour = Color3.fromRGB(86, 66, 44),
			SmokeColour = Color3.fromRGB(190, 166, 132),
			PuffColour = Color3.fromRGB(214, 192, 156),
		},
	},

	-- The surfaces a car is actually built effects for, in order. THE INSTANCE BUDGET IS
	-- THIS LIST:
	--
	--   per car = 4 wheels x (2 Attachments + surfaces x (1 Trail + 2 Emitters))
	--
	-- At one surface that is 4 x 5 = 20, built once when the rig is caught and never
	-- again. It was 16 before the stylized smoke layer, 32 with a four-rung darkness
	-- ladder, 28 with a three-rung one, and 20 again now the ladder is gone (T-062).
	-- A second surface adds 12, which is why `dirt` is not in here until there is dirt.
	Built = { "tarmac" },
	Default = "tarmac", -- what a wheel on the ground is told it is standing on, until
	-- `Hit` can say

	-- The instance names a rig's effects are given, so `Drift/Wheels`, the tests and
	-- anything that inspects a car agree on what they are called (CONTRACTS.md).
	--
	-- THERE IS NO FOLDER. The eight attachments hang directly off the car's `Body` -- an
	-- Attachment has to be parented to a BasePart to have a position at all -- and each
	-- wheel's Trail and ParticleEmitter hang off its first attachment. A folder would be a
	-- seventeenth instance for nothing.
	Names = {
		Attachment = "FxA_%s_%s", -- wheel name, then "L" or "R" (the two ends of the mark)
		Trail = "FxMark_%s_%s", -- wheel name, then surface. ONE per wheel per surface
		Emitter = "FxSmoke_%s_%s", -- wheel name, then surface. The DIFFUSE layer
		Stylized = "FxPuff_%s_%s", -- wheel name, then surface. The STYLIZED layer
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
		IdleRpm = 900,
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

		-- THE LAYERED SOUND (T-129): our own synthesized loops, picked by the user on
		-- 2026-11-11 (DECISIONS.md), at six rev points, each on and off throttle. ALL TWELVE
		-- ARE ONE UPLOADED FILE, the "sheet", and each `Sound` plays its own slice of it
		-- through `PlaybackRegion` and `LoopRegion` -- one upload instead of twelve. Each
		-- slice is padded with a quarter second of itself either side in the file, so the
		-- codec's smear at a region's edge is engine, not silence.
		--
		-- `SoundId = nil` FALLS BACK TO THE ONE CLIP above (it was the game's sound until the sheet
		-- was uploaded). Built by `..\art\generated\sfx-engine\set-v1\build_set.py`.
		Layers = {
			SoundId = "rbxassetid://132857262391195" :: string?, -- engine-sheet.ogg, uploaded 2026-11-12
			Volume = 0.84, -- the loops are normalised to an RMS of 0.16 and "Car idle" is
			-- 0.29: 0.45 x 0.29 / 0.16 keeps the engine bed where it was
			-- in the mix (AUDIO.md "Mix")
			OffLoadVolume = 0.75, -- the off-throttle loops sit this far under the on ones
			LimiterDuck = 0.5, -- volume share left during a limiter cut: the stutter
			MaxPitchShift = 0.6, -- a SAFETY CAP only, past the rev points' 1.52x spacing, so
			-- two loops in a crossfade always agree on the pitch. The louder
			-- of the two is never more than 23% off its own rpm (EngineTests)
			-- Rev point, then { start, length } in seconds in the sheet, on and off.
			Loops = {
				{ Rpm = 900, On = { 0.25, 2.0 }, Off = { 2.85, 2.0 } },
				{ Rpm = 1370, On = { 5.45, 2.014604 }, Off = { 8.05, 2.014604 } },
				{ Rpm = 2090, On = { 10.65, 2.009562 }, Off = { 13.25, 2.009562 } },
				{ Rpm = 3190, On = { 15.85, 1.993729 }, Off = { 18.45, 1.993729 } },
				{ Rpm = 4860, On = { 21.05, 2.0 }, Off = { 23.65, 2.0 } },
				{ Rpm = 7400, On = { 26.25, 1.994604 }, Off = { 28.85, 1.994604 } },
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
		-- One id per surface. ONLY THE SURFACES IN `Built` GET A SOUND, so this is one
		-- `Sound` today and a table that already has room for the second. A surface with
		-- no id here gets no sound and no error -- the day `dirt` is laid it needs a pick
		-- from the user, not a default.
		SoundIds = {
			tarmac = "rbxassetid://124978127809544", -- Creator Store, "tyre_slide" by
			-- knightracers, 3.00 s. By id, nothing uploaded
		},
		RollOffMin = 12, -- studs. Tighter than the engine's: a squeal is made at the road
		RollOffMax = 150, -- studs
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
