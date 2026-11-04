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
--   `Engine`                            Drift/EngineSound (T-064, not built yet)
--   `Skid`                              Drift/SkidSound   (T-064, not built yet)
-- The sound tables are here because the spec puts every number of this feature in one
-- file and because the sound task should have to add a module and not a config. Nothing
-- reads them today.
--
-- Angles are DEGREES in this table and radians nowhere in it, the same way `Config.Drift`
-- keeps `MinSlipAngleForDrift` in degrees: a number a human tunes is a number a human can
-- read. The modules convert once.

return {
	-- ------------------------------------------------------------------ tyre marks
	-- The black line a sliding wheel leaves. One `Trail` per wheel, between two
	-- `Attachment`s `Width` apart at the contact patch, enabled and disabled -- never
	-- created or destroyed while driving (features/car-fx.md "The budget").
	Marks = {
		Seconds = 5, -- s of `Trail.Lifetime`. How long a mark stays on the road, and
		-- therefore how much of a corner you can still see behind you
		Width = 1.2, -- studs between the two attachments. A little under the tyre, which
		-- is `Config.Drift.WheelWidth` wide
		Lift = 0.05, -- studs the attachments sit ABOVE the contact patch. OURS, and not a
		-- look: a trail drawn exactly in the road's surface z-fights with it.
		-- Small enough that the mark still reads as being on the road
		Transparency = 0.45, -- the mark at its freshest. It is a tyre mark, not paint
		FadeAt = 0.6, -- 0..1 of the lifetime the fade to invisible starts at. The last
		-- 40 per cent of a mark's life is it fading away, which is what
		-- stops five hundred marks ending in a hard edge
		TextureLength = 0, -- 0 is a solid ribbon. A repeating texture would need an
		-- uploaded asset, and this feature uploads nothing
		LightInfluence = 1, -- 1 takes the world's light, which is what makes a mark sit
		-- IN the road rather than glow on top of it. 0 would keep it
		-- the same near-black in shade and in sun
	},

	-- ------------------------------------------------------------------ smoke
	-- One `ParticleEmitter` per wheel, on the first of that wheel's two attachments, so
	-- the puff leaves the contact patch and not the axle. Built-in particle texture only.
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
		},
		dirt = {
			MarkColour = Color3.fromRGB(86, 66, 44),
			SmokeColour = Color3.fromRGB(190, 166, 132),
		},
	},

	-- The surfaces a car is actually built effects for, in order. ONE ENTRY IS THE
	-- SIXTEEN-INSTANCE BUDGET: 4 wheels x (1 Trail + 1 ParticleEmitter + 2 Attachments).
	-- A second entry doubles it, which is why `dirt` is not in here until there is dirt.
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
		Trail = "FxMark_%s_%s", -- wheel name, then surface
		Emitter = "FxSmoke_%s_%s", -- wheel name, then surface
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
		MinPitch = 0.7, -- OURS. The reference's live on its car config and are not in
		MaxPitch = 2.2, -- the decompile, so these two are a guess to be tuned by ear
		-- AirbornePitch is MaxPitch: wheels up, engine free-revving
	},

	-- ------------------------------------------------------------------ skid (T-064)
	-- One looping clip per surface, all alive at once, each one's volume lerped rather
	-- than switched (features/car-fx.md "Skid sound").
	Skid = {
		MinSpeed = 3.6, -- studs/s. Below this, silence
		MinVolume = 0.25, -- the volume a drift that has just begun plays at
		MaxSlipDegrees = 90, -- the angle the squeal is full at
		VolumeLerpSpeed = 1, -- /s. Fading in and out instead of clicking on
	},
}
