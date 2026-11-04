--!nonstrict
-- Every number the drift camera is made of, and none of them in the logic
-- (docs/game/features/drift-camera.md "Rules and numbers").
--
-- MOVED OUT OF `Config/Drift.luau` BY T-071, unchanged, name for name. They sat among the
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
	CamOffset = Vector3.new(0, 14.3, 53.6), -- studs. FALLBACK (0, 4, -15 m), from the
	-- camera-mode setting's own default. Its LENGTH is the
	-- radius the camera keeps from the car and its direction
	-- is the resting direction. Low and well back, which is
	-- most of why the reference reads flat and fast rather
	-- than like a drone shot
	CamLookAt = Vector3.new(0, 0, -10.7), -- studs. EXACT. What it looks at, AHEAD of the
	-- car. Only its HEIGHT is eased (`CamHeightRate`)
	CamVelocityBlend = 0.05, -- EXACT, and small on purpose: how much of the lean toward
	-- where the car is actually going is taken each frame. It is
	-- small because it COMPOUNDS -- the leaned target is what the
	-- next frame's resting direction is measured from, so the 5%
	-- is applied again every frame. What the player sees is the
	-- camera dropping and swinging wide through a drift, not a
	-- side-on shot. Raise it for a more dramatic camera
	CamSwingRate = 1, -- per second. FALLBACK. How fast the behind-the-travel point follows
	CamAngleRate = 1, -- per second. FALLBACK. How fast the resting DIRECTION follows the
	-- car round -- the camera swings around the car at a fixed radius
	-- rather than being dragged behind it. THE MAIN FEEL DIAL: low is
	-- a camera that lags and lets the car rotate in front of it, high
	-- is one glued behind the nose
	CamHeightRate = 1, -- per second. FALLBACK. How fast the look-at height follows
	CamFovBase = 60, -- deg at a standstill. FALLBACK
	CamFovPerSpeed = 0.14, -- deg per stud/s. FALLBACK (0.5 per m/s): 85 deg at top speed
	CamFovRate = 0.5, -- per second. FALLBACK. How fast the FOV follows. Slow on purpose
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
