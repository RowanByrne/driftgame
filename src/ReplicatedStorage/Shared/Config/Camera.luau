--!nonstrict
-- Every number the drift camera is made of, and none of them in the logic
-- (docs/game/features/drift-camera.md "Rules and numbers").
--
-- MOVED OUT OF `Config/Drift.luau` BY T-071, name for name. They sat among the
-- model's numbers for historical reasons and have nothing to do with how the car drives:
-- the camera reads the model's state and writes nothing anywhere. `Config.Drift` keeps the
-- simulation, this keeps the look, and `CamOffset` is still `CamOffset`.
--
-- THE PREFIX IS KEPT ON PURPOSE. `Config.Camera.CamOffset` reads oddly against
-- `Config.Camera.Offset`, and that is the point: every reader, every test, every line of
-- `CarCameraController` and every sentence of the spec says `CamOffset`, so renaming
-- seventeen keys to save three letters would be a change nothing asked for in a file whose
-- whole job was to move house quietly.
--
-- A PLAIN TABLE, with no write guard, unlike `Config.Drift`: there is no car/model split
-- to protect here, and a Studio session sweeps these numbers (`CarCameraController
-- :DebugProbe` overrides `CamVelocityBlend` for the length of one run).
--
-- T-071 THEN CHANGED THREE OF THEM, and only three -- `CamOffset`, `CamVelocityBlend` and
-- the FOV's `CamFovBase` / `CamFovPerSpeed` / `CamFovRate`. Each one carries the
-- measurement that chose it, including the one that says the brief's premise was wrong.
-- The move itself was proved free first: with the old values in this file, a recorded
-- drive put the camera and its look point in exactly the same place, step for step, as
-- the build before the file existed. NOTHING NEW WAS ADDED. No roll, no shake, no zoom,
-- no position smoothing -- the roll and the shake are T-072's.
--
-- CORRECTED 2026-11-03: the decompile holds two cameras and the spec described the
-- predecessor, which nothing in the reference runs. The game's camera has NO ROLL, NO ZOOM
-- and NO POSITION SMOOTHING -- it is placed at its target each frame and looks at the car,
-- so the horizon is always level. `CamRollMax`, `CamRollAtAngle`, `CamRollRate`,
-- `CamDriftDistance`, `CamZoomAtAngle`, `CamZoomRate`, `CamSmoothTime`, `CamLookRate` and
-- `CamFovTop` were that predecessor's and are gone; if one turns up in this table again,
-- something has drifted back to the wrong camera.
--
-- Offsets are in the CAR's own axes, Roblox sense: +x right, +y up, +z BEHIND the car (the
-- spec quotes the reference's Unity figures, where behind is -z). Angles are DEGREES
-- wherever a name says Angle, Pitch or Elevation, because degrees are what the tuning
-- conversation uses. Every number says where it came from, as the model's do: EXACT
-- (written in the reference's own logic), FALLBACK (what its code declares when no editor
-- asset overrides it) or OURS.

local Camera = {
	CamOffset = Vector3.new(0, 17.2, 42.7), -- studs. OURS (T-071), driven and measured.
	-- A 46.0-STUD RADIUS AT 22 DEGREES, against the
	-- 55.5 at 14.9 this shipped with -- the reference's
	-- own fallback, (0, 4, -15 m). Its LENGTH is the
	-- radius the camera keeps from the car and its
	-- direction is the resting direction.
	-- NINE AND A HALF STUDS CLOSER: the car subtends
	-- 16.5 deg rather than 13.8, about a fifth bigger on
	-- screen. THE SEVEN EXTRA DEGREES OF ELEVATION ARE
	-- NOT A STYLE CHOICE, they pay for the raised
	-- `CamVelocityBlend` below: the lean drops the camera
	-- as it swings wide, and at the old flat 14.9 deg the
	-- new blend left it 5.9 studs above the car in a
	-- 60-degree drift against today's 8.5, which is
	-- roof height. At 22 it settles at 7.2 and a drift
	-- frames about as it does now.
	-- THE RADIUS IS THE ONE NUMBER HERE THAT IS A
	-- JUDGEMENT, not a measurement. Measured
	-- alternatives, same blend: (0, 14.3, 43.7) is the
	-- same flat angle as today, 9.5 studs closer and
	-- 5.9 up in a drift; (0, 20.2, 41.3) is steeper
	-- still and holds 8.4 up; the reference's other
	-- default, (0, 28.6, 35.7), is 45.7 at 38.7 deg and
	-- reads like a drone shot
	CamLookAt = Vector3.new(0, 0, -10.7), -- studs. EXACT. What it looks at, AHEAD of the
	-- car. Only its HEIGHT is eased (`CamHeightRate`)
	CamVelocityBlend = 0.12, -- OURS (T-071). The reference's is 0.05. How much of the lean
	-- toward where the car is actually going is taken each step.
	-- IT COMPOUNDS -- the leaned target is what the next step's
	-- resting direction is measured from, so this fraction is
	-- applied again every step and the number is nothing like the
	-- answer. Where the camera ACTUALLY SETTLES, measured, behind a
	-- car held at 60 degrees of slip: 0.05 puts it 46 deg round,
	-- 77% of the way to the travel; 0.12 puts it 56 deg, 93%.
	-- SO THE SETTLED ANGLE WAS NEVER THE PROBLEM. What this number
	-- really buys is HOW LONG IT TAKES, and most drifts are a
	-- second, not twenty. One second into a 60-degree drift: 0.05
	-- has come 36% round, 0.12 has come 52%. At 30 degrees of
	-- slip, where the quadratic ease keeps the camera calm, 16%
	-- against 28%. Past about 0.25 the camera is behind the travel
	-- before the slide has finished opening, which is the side-on
	-- shot this was small to avoid. The camera also DROPS as it
	-- leans, which is why `CamOffset` above went up seven degrees
	-- when this went up
	CamSwingRate = 1, -- per second. FALLBACK. How fast the behind-the-travel point follows
	CamAngleRate = 1, -- per second. FALLBACK. How fast the resting DIRECTION follows the
	-- car round -- the camera swings around the car at a fixed radius
	-- rather than being dragged behind it. THE MAIN FEEL DIAL: low is
	-- a camera that lags and lets the car rotate in front of it, high
	-- is one glued behind the nose
	CamHeightRate = 1, -- per second. FALLBACK. How fast the look-at height follows
	-- THE FOV, and the one place T-071 found the obvious reading of the brief to be wrong.
	-- Measured before anything was changed, over a 60-second drive from a standstill with
	-- the shipped 60 / 0.14 / 0.5: the FOV swings 22.0 degrees, 60.0 to 82.1, and it is
	-- NOT behind its own target -- worst lag 3.6 deg, because the car takes 16 seconds to
	-- reach speed and the FOV's own time constant was 2. So `CamFovRate` was never too
	-- slow to arrive. The trouble is that ALL 22 DEGREES ARE SPENT IN THAT FIRST 16
	-- SECONDS. Once up to speed the car lives between 115 and 159 studs/s, and across the
	-- rest of the drive the FOV only ever moved inside a 5.4-degree band (76.6 to 82.1,
	-- median 80.1) -- wide the whole time, and never visibly changing. "Pick up some FOV
	-- while the speed increases" was asking for something that measurably was not
	-- happening WHERE IT WOULD BE SEEN, while 22 degrees happened once, slowly, at the
	-- start of a run.
	-- So the fix is the SHAPE, not the size: a lower base and a steeper slope put the
	-- swing inside the speeds that are actually driven, and a faster rate lets the dips a
	-- drift takes out of the speed show at all. Measured on the same drive, these three:
	-- 52.0 to 80.9 over the whole run, and 70.7 to 80.9 -- a 10.2-degree band -- once up
	-- to speed, which is nearly double. THE TOP IS UNCHANGED (80.9 against 82.1), so
	-- nothing gets wider than it already was; what moved is the bottom.
	CamFovBase = 52, -- deg at a standstill. OURS (T-071); the FALLBACK is 60
	CamFovPerSpeed = 0.18, -- deg per stud/s. OURS (T-071); the FALLBACK is 0.14 (0.5 per
	-- m/s). 52 + 0.18 x 179 is 84 deg at top speed, against 85
	CamFovRate = 2, -- per second. OURS (T-071); the FALLBACK is 0.5. A 500 ms time
	-- constant rather than two seconds. At 0.5 the FOV ran up to 3.6 deg
	-- behind its target and smoothed away exactly the speed the car loses
	-- in a drift, which is the only FOV movement there is at racing speed.
	-- Worst lag at 2 is 2.0 deg. Higher is not better: a wall hit drops the
	-- speed instantly, and this is what decides whether that reads as a
	-- shove or as a snap
	-- The pan (T-036): hold right and look around. An ORBIT OFFSET on the placed camera,
	-- about the car, at the same radius -- applied downstream of the targets, so the
	-- feedback that makes this camera frame-rate independent never sees it.
	CamPanSensitivity = 0.005, -- rad per pixel of mouse travel: 0.286 deg/px, so a
	-- 400-pixel drag is 114.6 deg. OURS, and about what Roblox's
	-- own camera does
	CamPanRate = 9, -- per second. OURS. How fast the view follows the hand: a 111 ms time
	-- constant. THE "SLIGHTLY SMOOTHENED" DIAL -- lower is more cinematic,
	-- and past about 5 it starts reading as lag rather than as weight
	CamPanReturnDelay = 0.5, -- s. OURS. How long after letting go before the view starts
	-- coming home. Without it a release snaps and feels cheap; much
	-- past a second and the player is driving again before it lets go
	CamPanReturnRate = 2, -- per second. OURS. How fast it comes home once it starts: a
	-- 500 ms time constant, about 2.1 s from a big pan to centred
	CamPanPitchMin = -12, -- deg. OURS. How far the player may drag the view DOWN, as an
	-- offset from where the camera already sits
	CamPanPitchMax = 60, -- deg. OURS. And UP
	CamPanElevationMin = 1, -- deg. OURS. The hard guard, on the RESULT rather than the
	-- offset: the camera may never sit below this above the car,
	-- or it is under the road
	CamPanElevationMax = 80, -- deg. OURS. Nor past this, or it is straight down the roof
	CamTargetStep = 1 / 60, -- s. OURS, and NOT `FixedStep`. The camera's targets feed back
	-- into themselves (the swung target is what the next frame's resting
	-- direction is measured from), so where they settle depends on how
	-- often they are stepped: left at frame rate, the camera sat 16.2
	-- studs above a drifting car at 30 FPS and 10.1 at 120. They run on
	-- this fixed step instead, interpolated between, and 60 is the rate
	-- the reference ran at -- so this number reproduces its look, and
	-- changing it changes how the camera sits in a drift at every frame
	-- rate at once. The model's own step is finer and deliberately
	-- separate: the camera does not need 120 and the feedback is why.
	CamMaxTargetSteps = 8, -- safety, as `MaxStepsPerFrame` is for the model: a stalled
	-- frame must not be paid back as a burst of camera steps
}

return Camera
