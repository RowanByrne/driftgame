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
--   `Engine`                            Drift/EngineSound (T-064, built)
--   `Skid`                              Drift/SkidSound   (T-064, built)
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

		MinSegment = 0.5, -- studs the contact patch must travel before the trail lays
		-- another segment (`Trail.MinLength`). MEASURED, and it is what
		-- stopped the mark coming out as a LADDER of short rungs with
		-- road showing between them.
		--
		-- It was 0, which lays a segment every frame however short. A
		-- mark is `Width` studs wide -- 1.2 -- and sampled every frame
		-- through a real drift the contact patch advances 0.104 to 1.261
		-- studs, mean 0.675: so very nearly every quad in the ribbon is
		-- WIDER THAN IT IS LONG, and at the slow end twelve times wider.
		-- The other two suspects were ruled out in the same sample: the
		-- wheel left the ground 0 times in 481 frames and the trail
		-- switched on or off once, so it was neither the ground gate nor
		-- a band swapping.
		--
		-- Half a stud is just under that mean, so a drift at speed lays
		-- the same segments it always did and a crawling car merges
		-- several frames into one honest quad instead of a stack of
		-- slivers. Raise it and a slow mark gets chunky; drop it to zero
		-- and the ladder comes back.
		LightInfluence = 1, -- 1 takes the world's light, which is what makes a mark sit
		-- IN the road rather than glow on top of it. 0 would keep it
		-- the same near-black in shade and in sun

		-- HOW DARK A MARK IS, AND WHY IT IS A LADDER AND NOT A NUMBER.
		--
		-- `Trail.Transparency` applies to the WHOLE live ribbon, not to the segment being
		-- laid: turn it down and the five seconds of mark already on the road darken with
		-- it. A mark has to keep the darkness it was laid at -- rubber on a road does not
		-- change its mind -- so each wheel carries one trail per band, all strung between
		-- the same two attachments, and only the band matching this frame's intensity is
		-- enabled. Each band's ribbon then persists at its own fixed darkness, and the
		-- line through a corner genuinely gets darker where the car was working hardest.
		--
		-- Lightest first. More bands is a smoother ramp and four more instances a car
		-- each; two would read as on/off, six is past what an eye can separate on asphalt.
		Bands = { 0.74, 0.60, 0.46, 0.32 }, -- `Trail.Transparency` per band
		BandHysteresis = 0.04, -- how far past a band's boundary the density has to get
		-- before the trail is actually swapped. WITHOUT IT a density
		-- sitting on a boundary swaps every other frame, and every swap
		-- ends one ribbon and starts another -- a dotted line down the
		-- road instead of a mark. In units of density, so 0.04 is four
		-- per cent of the whole ladder

		-- The intensity the bands are chosen by: RUBBER LAID PER STUD OF ROAD, 0..1.
		-- The user's own framing, and the whole of why there is a `/speed` in it:
		-- *"if the drift continues as the car's speed lowers, more rubber is deposited
		-- per foot"*. Same slide, less ground covered, darker line.
		--
		--   speedTerm = (RefSpeed / speed) ^ SpeedExponent      slower is denser
		--   angleTerm = |sin(slip)| ^ AngleExponent             more sideways is more rubber
		--   intensity = speedTerm * angleTerm * (1 .. HeatGain by the wheel's heat)
		--
		-- IT IS A FEEL CURVE AND NOT PHYSICS, and it is written as two independent
		-- exponents on purpose so either half can be tuned without algebra on the other.
		RefSpeed = 70, -- studs/s. The speed at which `speedTerm` is exactly 1
		SpeedExponent = 0.5, -- > 0 makes a slow slide darker than a fast one. At 0.5 a
		-- mark laid at 30 studs/s is 1.91x the density of the same
		-- slide at 110. ZERO takes speed out of it entirely
		AngleExponent = 1.6, -- how fast darkness grows with the slip angle. MEASURED, and
		-- changed from the 0.8 it was first written at: at 0.8 a
		-- perfectly ordinary 45-degree slide at 70 studs/s already read
		-- 0.758 and sat in the darkest band, so three quarters of the
		-- ladder were only reachable by a slide nobody drives. At 1.6
		-- the four bands land at about 10, 30, 45 and 70 degrees at
		-- that speed, which is the range the car is actually driven in
		MinSpeedForDensity = 12, -- studs/s. The floor under `speed` in the division, so a
		-- car that has nearly stopped does not divide its way to a
		-- black stripe. Below this the density stops growing
		HeatGain = 1.6, -- what a fully heated tyre multiplies the density by. This is the
		-- user's link between the two: *"the longer a drift goes, the
		-- hotter the tyres, and the more smoke -- that tyre mark would be
		-- darker"*. Same `heat` the stylized smoke is driven by
	},

	-- ------------------------------------------------------------------ tyre heat
	-- PER WHEEL, 0..1, and the one piece of state this module keeps between frames.
	-- It rises while that wheel is actually sliding, faster the harder it is sliding, and
	-- falls when it stops. Two things read it: the stylized smoke's rate, and the mark's
	-- density (`Marks.HeatGain`).
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
	-- THIS LIST AND `Marks.Bands`:
	--
	--   per car = 4 wheels x (2 Attachments + surfaces x (#Bands Trails + 2 Emitters))
	--
	-- At one surface and four bands that is 4 x (2 + 6) = 32, built once when the rig is
	-- caught and never again. It was 16 before the bands and the stylized layer (T-062).
	-- A second surface adds 24, which is why `dirt` is not in here until there is dirt.
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
		Trail = "FxMark_%s_%s_%d", -- wheel name, surface, then the band's index in
		-- `Marks.Bands`, 1 being the lightest
		Emitter = "FxSmoke_%s_%s", -- wheel name, then surface. The DIFFUSE layer
		Stylized = "FxPuff_%s_%s", -- wheel name, then surface. The STYLIZED layer
		Engine = "FxEngine", -- the one engine `Sound`, on the body (T-064)
		Skid = "FxSkid_%s", -- surface. One `Sound` per surface in `Built`, on the body
	},

	-- ------------------------------------------------------------------ engine (T-064)
	-- One looping clip, pitched by a gearbox that does not exist: there is no engine model
	-- and no RPM anywhere in this game (features/car-fx.md "Engine sound").
	Engine = {
		GearCount = 5, -- how many bands the speed range is cut into
		GearLengthMultiplier = 1.5, -- each gear is this much longer than the one before.
		-- At 5 gears the divisor is 13.1875, so a 179 studs/s
		-- car shifts at about 13.6, 34, 64 and 110
		GearOverlap = 10, -- studs/s. Half-width of the band two gears share (the
		-- reference's 3 m/s). A car sitting on a shift point must not
		-- machine-gun between two gears
		MinTimeInGear = 0.5, -- s since the last shift before another is allowed
		PitchLerpSpeed = 1, -- /s the pitch chases its target. NEVER SNAPPED: the lerp
		-- across the gap is the whole reason a shift sounds like one
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
	Skid = {
		MinSpeed = 3.6, -- studs/s. Below this, silence
		MinVolume = 0.25, -- the volume a drift that has just begun plays at
		MaxSlipDegrees = 90, -- the angle the squeal is full at
		VolumeLerpSpeed = 1, -- /s. Fading in and out instead of clicking on

		-- The master the mix sets, on top of the `MinVolume`..1 lerp above: the squeal is
		-- the loudest thing in a drift, and it is still under 1 so it has somewhere to go
		-- the day anything else is in the mix (AUDIO.md "Mix").
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
}
