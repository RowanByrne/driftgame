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
-- the build before the file existed.
--
-- T-072 THEN ADDED SIX, and only six: `CamRollMax` / `CamRollAtAngle` / `CamRollRate` and
-- `ShakePeriod` / `ShakeRotation` / `ShakePosition` / `ShakeRestoreRate`. Both effects are
-- applied to the RENDERED camera, downstream of the stepped targets, exactly as the pan
-- is, so neither joins the feedback loop that makes this camera frame-rate independent.
-- EVERY ONE OF THEM IS ZEROABLE AND ZERO IS TODAY: with `CamRollMax = 0` and
-- `ShakeRotation` / `ShakePosition` at zero, the same recorded drive matched the build
-- before them to every digit printed, step for step. That is the test that lets the roll
-- ship at all. Still no zoom and no position smoothing.
--
-- CORRECTED 2026-11-03: the decompile holds two cameras and the spec described the
-- predecessor, which nothing in the reference runs. The game's camera has NO ZOOM and NO
-- POSITION SMOOTHING -- it is placed at its target each frame and looks at the car.
-- `CamDriftDistance`, `CamZoomAtAngle`, `CamZoomRate`, `CamSmoothTime`, `CamLookRate` and
-- `CamFovTop` were that predecessor's and are gone; if one turns up in this table again,
-- something has drifted back to the wrong camera.
--
-- THE ROLL IS BACK, DELIBERATELY (T-072), and it is the one exception to the paragraph
-- above. It was taken out because the PREDECESSOR'S numbers were violent -- 45 degrees of
-- it, saturating at 20 degrees of slip, chased at rate 20 -- and the user drove that and
-- said it "spins/rotates wayyyyy to far". The shape was never the problem. What is here is
-- the same formula at about a ninth of the gain, measured (`CamRollMax` below), and
-- `CamRollMax = 0` gives the level horizon back exactly. `CamZoom*` and `CamSmoothTime`
-- stay gone.
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
	-- THE ROLL (T-072), and the one number in this file with a history. The camera banks
	-- with the slide: `CamRollMax` degrees of it, reached at `CamRollAtAngle` degrees of
	-- slip, eased at `CamRollRate`. THE PREDECESSOR'S WERE 45, 20 AND 20 -- the horizon at
	-- 45 degrees while the car was barely sideways -- and the user drove that and said it
	-- "spins/rotates wayyyyy to far". These are about a NINTH of that gain: a ninth of the
	-- angle, over more than twice the slip, chased at a third of the rate.
	-- WHICH WAY IT GOES: the camera banks INTO the corner, as a motorcycle does. A
	-- positive slip is the car travelling out to its LEFT, which is a RIGHT-hand drift
	-- (the nose is turned into the corner and the tail is out to the left), and the camera
	-- rolls right with it. NEGATE `CamRollMax` to go the other way -- the user said of the
	-- predecessor that they were "not even sure if it's the right direction", and this is
	-- where that is settled, with one minus sign
	CamRollMax = 4, -- deg, at `CamRollAtAngle` of slip. OURS (T-072). The predecessor's
	-- was 45. Measured over a full-lock drift the camera reaches its
	-- 4.00 deg stop and the HORIZON tilts 3.92 -- a little less, because
	-- the camera is pitched down and some of a roll about the look axis
	-- goes into the pitch rather than into the horizon. Four degrees
	-- moves the edge of a 1080-line screen by 67 pixels, so it is
	-- nothing like invisible; five is one line away if it wants more
	CamRollAtAngle = 45, -- deg of slip at which the roll saturates. OURS (T-072). The
	-- predecessor's was 20, which is why it was at full tilt before the
	-- car looked sideways at all. Measured, held: 10 deg of slip leans
	-- 0.89, 20 leans 1.78 (where the predecessor was at 45), 30 -- an
	-- ordinary drift -- leans 2.67, and 45 and anything past it is at
	-- the stop
	CamRollRate = 6, -- per second. OURS (T-072); a 167 ms time constant. The
	-- predecessor's was 20, which is most of why it read as a flick rather
	-- than a lean. Measured over a hard 20-second drive, the worst single
	-- frame of roll is 0.147 deg at 60 FPS (0.293 at 30, 0.073 at 120 --
	-- the same angular speed, which is what the exponential ease is for).
	-- A twenty-fifth of the whole lean in a frame: it arrives, and it is
	-- never caught moving
	-- THE SPEED SHAKE (T-072), the reference's own (`CameraShake.cs`). A new random kick
	-- is chosen every `ShakePeriod`, scaled by speed as a share of the CAR's top speed
	-- (`Config.Drift.TopSpeed`, so a faster car does not shake harder for the same speed),
	-- and the camera eases back toward zero between kicks at `ShakeRestoreRate`. The
	-- result is a camera that gets BUSY at speed rather than violent -- the biggest "this
	-- feels fast" lever there is after the FOV.
	-- IT IS APPLIED TO THE RENDERED CAMERA ONLY and never written where a target can read
	-- it, so it cannot move where the camera sits; and the kicks are chosen on their own
	-- clock from a seeded sequence, so 30, 60 and 120 FPS get the SAME kicks at the SAME
	-- moments and decay by the same exact exponential between them.
	ShakePeriod = 0.05, -- s. EXACT (`_shakePeriod`). Twenty kicks a second
	ShakeRotation = Vector3.new(0.15, 0.15, 0.1), -- DEGREES of pitch, yaw and roll at top
	-- speed. OURS (T-072). The rotation is what is
	-- actually seen, and THE ONLY HONEST UNIT FOR IT
	-- IS SCREEN PIXELS: at top speed the FOV is 84
	-- deg, so a 1080-line screen is 12.8 px to the
	-- degree, and this makes the picture move
	-- 3.3 px in the worst frame and 0.65 px in the
	-- average one. For scale, the car itself is
	-- about 210 px tall there, so the buzz is one
	-- and a half per cent of the car. THE
	-- CONSTRAINT IS THAT THE CAR STAYS EASY TO LOOK
	-- AT while the player is placing a drift, and
	-- what was measured against this is the whole
	-- ladder: 0.10 is 2.2 px worst and 0.44 mean,
	-- which is under what is felt; 0.20 is 4.5 and
	-- 0.88; 0.30 is 6.7 and 1.3, which is a shimmer
	-- rather than a buzz.
	-- IT IS LINEAR IN SPEED, measured: the kick is
	-- 0.043 deg at a quarter of top speed, 0.086 at
	-- half, 0.129 at three quarters and 0.172 at the
	-- top, and exactly nothing at a standstill
	ShakePosition = Vector3.new(0.07, 0.07, 0), -- STUDS, in the camera's own axes, at top
	-- speed. OURS (T-072). At a 46-stud radius
	-- 0.07 studs is 0.09 deg of arc, about a pixel,
	-- and it is there for texture under the rotation
	-- rather than for its own sake. THE Z IS ZERO ON
	-- PURPOSE: a tenth of a stud along the look axis
	-- is a 0.2 per cent change of scale and nothing
	-- else, so it costs a multiply and buys nothing
	ShakeRestoreRate = 14, -- per second. OURS (T-072); the reference's own is 1, applied
	-- to a kick it ADDS every frame rather than sets, which makes
	-- its shake depend on the frame rate. A kick here decays to
	-- half of itself in the 50 ms before the next one, so the
	-- camera is always moving and never sits still at a corner.
	-- Measured at the same magnitude, 8 is a sway (4.0 px worst,
	-- 0.69 mean) and 24 is a fizz (2.5 and 0.59)
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
