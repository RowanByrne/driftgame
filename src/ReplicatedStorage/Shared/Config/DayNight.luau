--!nonstrict
-- DayNight: every number of the sky and the day-night cycle, and none of them in the logic
-- (docs/game/features/day-night.md "Rules and numbers", T-144).
--
-- WHAT READS WHAT:
--   `Shared/DayNight`                     the cycle: the time to a phase and a look
--   `Controllers/SkyController`           sets the client's Lighting from that look
--   `Road/SplineMesh` (through the above) the foot of each cliff, `CliffHaze`
--
-- THE CYCLE, in seconds of the server's clock (`workspace:GetServerTimeNow()`), so every
-- client works out the same moment by itself and nothing is sent:
--   day | sunset | night | sunrise | day ...
-- A keyframe sits in a phase at a fraction `f` of it, so a phase's length can change
-- without moving any keyframe by hand.
--
-- THE CLOCK (`Lighting.ClockTime`) runs through the keyframes' `Clock` values on a smooth
-- curve, so the sun's speed never jumps: about 11 hours of sky in the 2 minutes of day,
-- less than one hour in the 20 s of sunset, which is where those 20 s are spent -- with the
-- sun just above the horizon and just below it (Roblox's sun crosses the horizon at 6:00
-- and 18:00, measured in the lane).
--
-- EVERY OTHER VALUE blends from one keyframe to the next with a smoothstep. Every keyframe
-- names every value (the unit test checks), so a look is always the keyframe's, whole.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	-- ---------------------------------------------------------------- lengths, s
	Day = 120, -- sunrise's end to sunset's start
	Sunset = 20,
	Night = 120, -- sunset's end to sunrise's start
	Sunrise = 20,
	-- Where the cycle starts against the server's clock. Any number works: it only moves
	-- which moment a brand new server opens on.
	Offset = 0, -- s

	-- --------------------------------------------------------------- held fixed
	-- Set once, not blended.
	Fixed = {
		GlobalShadows = true, -- the long shadows of sunset
		EnvironmentDiffuseScale = 1, -- light from the sky itself, which changes with it
		EnvironmentSpecularScale = 1,
		ShadowSoftness = 0.2,
		StarCount = 3000, -- Roblox fades its stars in and out with the clock
		SunAngularSize = 14, -- degrees; the default is 21
		MoonAngularSize = 11,
		BloomSize = 28,
		SunRaysSpread = 0.8,
	},

	-- How often the lighting is set, per second. The clock moves about 0.1 hour a second,
	-- so this is smooth; it is the colours of the cliffs' haze that cost (below).
	Rate = 30,
	-- The cliffs' haze is a colour inside each road chunk's mesh: it is written again only
	-- when it has moved this far (0..1 per channel), so a chunk's mesh is not rewritten
	-- every frame.
	HazeStep = 2 / 255,

	-- NIGHT READABLE: the road at midnight must stay easy to read. It is judged from the
	-- night shot in the lane, not a number: a playtest cannot read a frame's pixels (measured:
	-- `CaptureService` captures cannot be opened as an `EditableImage`). What keeps it lit
	-- is the night's `OutdoorAmbient` and the moon's `Brightness` -- down at your peril.

	-- ---------------------------------------------------------------- the looks
	-- Colours: `Ambient` lights what the sky cannot see, `OutdoorAmbient` what it can,
	-- `SunColour` tints the sun's (and at night the moon's) light. `Atmosphere*` is the air
	-- between you and the horizon and the sky's own colour. `Tint`, `Contrast`,
	-- `Saturation` are the colour grading over everything.
	Keyframes = {
		{
			Name = "morning",
			Phase = "day",
			f = 0,
			Clock = 6.4,
			Brightness = 2.2,
			Exposure = 0,
			Ambient = rgb(52, 50, 56),
			OutdoorAmbient = rgb(136, 130, 136),
			SunColour = rgb(255, 214, 180),
			AtmosphereDensity = 0.3,
			AtmosphereOffset = 0.2,
			AtmosphereColour = rgb(218, 214, 214),
			AtmosphereDecay = rgb(130, 124, 140),
			AtmosphereGlare = 0.6,
			AtmosphereHaze = 1.4,
			CloudCover = 0.55,
			CloudDensity = 0.6,
			CloudColour = rgb(255, 236, 222),
			Tint = rgb(255, 246, 240),
			Contrast = 0.07,
			Saturation = 0.1,
			BloomIntensity = 0.6,
			BloomThreshold = 1.4,
			SunRays = 0.1,
			CliffHaze = rgb(206, 202, 204),
		},
		{
			Name = "noon",
			Phase = "day",
			f = 0.5,
			Clock = 12,
			Brightness = 2.6,
			Exposure = 0,
			Ambient = rgb(40, 44, 52),
			OutdoorAmbient = rgb(120, 128, 140),
			SunColour = rgb(255, 250, 240),
			AtmosphereDensity = 0.28,
			AtmosphereOffset = 0.25,
			AtmosphereColour = rgb(198, 214, 232),
			AtmosphereDecay = rgb(104, 128, 160),
			AtmosphereGlare = 0,
			AtmosphereHaze = 1,
			CloudCover = 0.55,
			CloudDensity = 0.6,
			CloudColour = rgb(255, 255, 255),
			Tint = rgb(255, 255, 255),
			Contrast = 0.05,
			Saturation = 0.08,
			BloomIntensity = 0.4,
			BloomThreshold = 1.6,
			SunRays = 0.04,
			CliffHaze = rgb(190, 206, 224),
		},
		{
			Name = "afternoon",
			Phase = "day",
			f = 0.85,
			Clock = 15.92,
			Brightness = 2.4,
			Exposure = 0,
			Ambient = rgb(44, 44, 50),
			OutdoorAmbient = rgb(128, 124, 120),
			SunColour = rgb(255, 236, 205),
			AtmosphereDensity = 0.29,
			AtmosphereOffset = 0.25,
			AtmosphereColour = rgb(214, 212, 206),
			AtmosphereDecay = rgb(140, 120, 110),
			AtmosphereGlare = 0.3,
			AtmosphereHaze = 1.4,
			CloudCover = 0.55,
			CloudDensity = 0.6,
			CloudColour = rgb(255, 246, 232),
			Tint = rgb(255, 246, 232),
			Contrast = 0.06,
			Saturation = 0.1,
			BloomIntensity = 0.5,
			BloomThreshold = 1.5,
			SunRays = 0.06,
			CliffHaze = rgb(206, 204, 198),
		},
		{
			Name = "golden hour",
			Phase = "sunset",
			f = 0,
			Clock = 17.6,
			Brightness = 2.4,
			Exposure = 0.1,
			Ambient = rgb(60, 50, 48),
			OutdoorAmbient = rgb(140, 120, 108),
			SunColour = rgb(255, 184, 120),
			AtmosphereDensity = 0.3,
			AtmosphereOffset = 0.2,
			AtmosphereColour = rgb(240, 200, 150),
			AtmosphereDecay = rgb(180, 120, 100),
			AtmosphereGlare = 1,
			AtmosphereHaze = 1.6,
			CloudCover = 0.55,
			CloudDensity = 0.6,
			CloudColour = rgb(255, 214, 170),
			Tint = rgb(255, 232, 206),
			Contrast = 0.1,
			Saturation = 0.18,
			BloomIntensity = 0.8,
			BloomThreshold = 1.3,
			SunRays = 0.14,
			CliffHaze = rgb(230, 176, 136),
		},
		{
			Name = "sunset",
			Phase = "sunset",
			f = 0.5,
			Clock = 18,
			Brightness = 2.2,
			Exposure = 0.3,
			Ambient = rgb(70, 50, 56),
			OutdoorAmbient = rgb(150, 110, 110),
			SunColour = rgb(255, 150, 90),
			AtmosphereDensity = 0.3,
			AtmosphereOffset = 0.15,
			AtmosphereColour = rgb(255, 178, 120),
			AtmosphereDecay = rgb(190, 96, 110),
			AtmosphereGlare = 1.5,
			AtmosphereHaze = 1.6,
			CloudCover = 0.55,
			CloudDensity = 0.6,
			CloudColour = rgb(255, 190, 160),
			Tint = rgb(255, 236, 220),
			Contrast = 0.08,
			Saturation = 0.15,
			BloomIntensity = 1,
			BloomThreshold = 1.1,
			SunRays = 0.2,
			CliffHaze = rgb(240, 170, 130),
		},
		{
			Name = "dusk",
			Phase = "night",
			f = 0,
			Clock = 18.4,
			Brightness = 1,
			Exposure = 0.4,
			Ambient = rgb(56, 50, 80),
			OutdoorAmbient = rgb(120, 108, 150),
			SunColour = rgb(180, 110, 140),
			AtmosphereDensity = 0.3,
			AtmosphereOffset = 0.15,
			AtmosphereColour = rgb(130, 104, 150),
			AtmosphereDecay = rgb(60, 50, 110),
			AtmosphereGlare = 0.6,
			AtmosphereHaze = 1.2,
			CloudCover = 0.5,
			CloudDensity = 0.6,
			CloudColour = rgb(190, 140, 170),
			Tint = rgb(226, 214, 240),
			Contrast = 0.1,
			Saturation = 0.1,
			BloomIntensity = 0.8,
			BloomThreshold = 1.2,
			SunRays = 0.06,
			CliffHaze = rgb(124, 100, 144),
		},
		{
			Name = "night",
			Phase = "night",
			f = 0.5,
			Clock = 0,
			Brightness = 1.5,
			Exposure = 0.6,
			Ambient = rgb(64, 72, 108),
			OutdoorAmbient = rgb(110, 124, 170),
			SunColour = rgb(150, 170, 230),
			AtmosphereDensity = 0.28,
			AtmosphereOffset = 0.2,
			AtmosphereColour = rgb(40, 52, 90),
			AtmosphereDecay = rgb(20, 26, 56),
			AtmosphereGlare = 0,
			AtmosphereHaze = 0.4,
			CloudCover = 0.45,
			CloudDensity = 0.5,
			CloudColour = rgb(80, 92, 130),
			Tint = rgb(200, 214, 255),
			Contrast = 0.08,
			Saturation = -0.05,
			BloomIntensity = 0.6,
			BloomThreshold = 1.2,
			SunRays = 0,
			CliffHaze = rgb(40, 50, 84),
		},
		{
			Name = "dawn",
			Phase = "sunrise",
			f = 0,
			Clock = 5.6,
			Brightness = 1,
			Exposure = 0.4,
			Ambient = rgb(56, 56, 84),
			OutdoorAmbient = rgb(124, 122, 160),
			SunColour = rgb(170, 160, 200),
			AtmosphereDensity = 0.3,
			AtmosphereOffset = 0.15,
			AtmosphereColour = rgb(120, 124, 164),
			AtmosphereDecay = rgb(90, 80, 130),
			AtmosphereGlare = 0.4,
			AtmosphereHaze = 1.2,
			CloudCover = 0.5,
			CloudDensity = 0.6,
			CloudColour = rgb(170, 160, 190),
			Tint = rgb(224, 226, 245),
			Contrast = 0.08,
			Saturation = 0,
			BloomIntensity = 0.7,
			BloomThreshold = 1.2,
			SunRays = 0.04,
			CliffHaze = rgb(116, 118, 156),
		},
		{
			Name = "sunrise",
			Phase = "sunrise",
			f = 0.5,
			Clock = 6,
			Brightness = 2,
			Exposure = 0.2,
			Ambient = rgb(66, 56, 66),
			OutdoorAmbient = rgb(150, 128, 136),
			SunColour = rgb(255, 170, 130),
			AtmosphereDensity = 0.3,
			AtmosphereOffset = 0.15,
			AtmosphereColour = rgb(245, 196, 170),
			AtmosphereDecay = rgb(160, 120, 160),
			AtmosphereGlare = 1.4,
			AtmosphereHaze = 1.5,
			CloudCover = 0.55,
			CloudDensity = 0.6,
			CloudColour = rgb(255, 196, 180),
			Tint = rgb(255, 236, 232),
			Contrast = 0.1,
			Saturation = 0.14,
			BloomIntensity = 0.9,
			BloomThreshold = 1.15,
			SunRays = 0.16,
			CliffHaze = rgb(214, 170, 166),
		},
	},
}
