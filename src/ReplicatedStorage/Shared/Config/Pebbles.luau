--!strict
-- Config.Pebbles: the stones kicked up into the wheel wells off the road (T-292,
-- `Drift/PebbleSound`, docs/game/AUDIO.md). The user's pick on 2026-11-17, "D: Ticks +
-- crunch": single pebble ticks and heavier clacks fired at random, over a quiet gravel
-- crunch loop. Every id is Creator Store audio by Pro Sound Effects, free in any experience,
-- used by id (assets/audio/sfx-pebbles/MANIFEST.md).
--
-- HOW HARD IT GOES, in three numbers made each frame:
--   ground = mean over the four wheels of `Surfaces[wheel's ground]` (0 on tarmac and for a
--            wheel in the air), and the heard value moves toward it over `FadeSeconds`
--   speedT = clamp01((speed - MinSpeed) / (FullSpeed - MinSpeed))
--   slideT = clamp01(lateral slide speed / SlideFull)       (SkidSound.slideSpeed)
--
--   ticks a second = MaxRate * ground * speedT * (1 + SlideRateBoost * slideT)
--   a tick's volume = TickVolume * tick.gain * ground * lerp(TickSpeedFloor, 1, speedT)
--                     * random(TickRandomVolume, 1)
--   the crunch's    = BedVolume * ground * speedT^BedSpeedPower * (1 + BedSlideBoost * slideT)
--
-- LEVELS, measured on the store files (MANIFEST.md "Level"): at full speed on gravel, not
-- sliding, the ticks are about -26.5 dBFS and the crunch -35.5 (together about -26), which
-- is 8.5 dB under the engine bed (-17.4) and under the off-road skid's loudest (-18.8).

return {
	-- How much each ground kicks up. Any ground not listed (tarmac) is 0: silence.
	Surfaces = {
		gravel = 1.0,
		dirt = 0.75,
		grass = 0.4,
	},
	FadeSeconds = 0.25, -- a full swing of the ground value, either way: the same 0.25 s
	-- the skid clips crossfade over
	MinSpeed = 3.6, -- studs/s. Under it, nothing (the skid's own `MinSpeed`)
	FullSpeed = 110, -- studs/s the stream is full at (top speed is about 179)
	SlideFull = 60, -- studs/s of lateral slide that gives the full slide boost
	JumpDistance = 40, -- studs in one frame: a spawn, respawn or teleport. Silent at once

	-- The ticks
	MaxRate = 26, -- a second, full speed on gravel, not sliding
	SlideRateBoost = 0.8, -- x(1 + this) at a full slide: about 47 a second
	MaxPerFrame = 4, -- a long frame never fires a burst bigger than this
	TickVolume = 1.4, -- the master for the ticks (a tick's instance volume is held at 10)
	TickSpeedFloor = 0.35, -- a tick's loudness at walking pace, against 1 at `FullSpeed`
	TickRandomVolume = 0.35, -- each tick is this to 1 of its loudness, at random
	PitchMin = 0.85, -- each tick's PlaybackSpeed, at random between these
	PitchMax = 1.2,
	ClackShare = 0.18, -- the share of ticks that are the heavier rock clacks
	Voices = 8, -- `Sound`s the ticks take turns on, made once per car
	-- The slices: `start` and `length` in seconds into the store file, `gain` brings each
	-- one's peak to 0.5. Cut from the onsets, ending at the quietest point before the next
	-- one (every end 29 dB or more under its peak, so no cut is heard as a click).
	-- 9117266254/57/65/97: "Pebble Drop Roll Stone Impact On Concrete 1 to 4".
	-- 9118624159/415/423/649/847: "Rock Impacts 1, 2, 3, 6, 8" (the clacks).
	Ticks = {
		{ id = 9117266254, start = 0.643, length = 0.066, gain = 2.374, clack = false },
		{ id = 9117266254, start = 0.731, length = 0.062, gain = 9.113, clack = false },
		{ id = 9117266254, start = 1.029, length = 0.034, gain = 1.078, clack = false },
		{ id = 9117266254, start = 1.063, length = 0.028, gain = 1.345, clack = false },
		{ id = 9117266254, start = 1.095, length = 0.052, gain = 1.348, clack = false },
		{ id = 9117266254, start = 1.149, length = 0.062, gain = 1.249, clack = false },
		{ id = 9117266254, start = 1.233, length = 0.054, gain = 1.390, clack = false },
		{ id = 9117266254, start = 1.293, length = 0.032, gain = 3.778, clack = false },
		{ id = 9117266254, start = 1.335, length = 0.062, gain = 11.132, clack = false },
		{ id = 9117266257, start = 0.127, length = 0.064, gain = 1.397, clack = false },
		{ id = 9117266257, start = 0.235, length = 0.016, gain = 4.223, clack = false },
		{ id = 9117266257, start = 0.265, length = 0.062, gain = 1.497, clack = false },
		{ id = 9117266257, start = 0.365, length = 0.062, gain = 1.656, clack = false },
		{ id = 9117266257, start = 0.453, length = 0.018, gain = 8.360, clack = false },
		{ id = 9117266257, start = 0.481, length = 0.032, gain = 6.608, clack = false },
		{ id = 9117266257, start = 0.517, length = 0.020, gain = 2.228, clack = false },
		{ id = 9117266257, start = 0.543, length = 0.030, gain = 3.894, clack = false },
		{ id = 9117266257, start = 0.585, length = 0.066, gain = 4.733, clack = false },
		{ id = 9117266257, start = 0.685, length = 0.068, gain = 15.130, clack = false },
		{ id = 9117266265, start = 0.341, length = 0.032, gain = 1.425, clack = false },
		{ id = 9117266265, start = 0.421, length = 0.062, gain = 1.402, clack = false },
		{ id = 9117266265, start = 0.559, length = 0.062, gain = 1.727, clack = false },
		{ id = 9117266265, start = 0.631, length = 0.034, gain = 13.495, clack = false },
		{ id = 9117266265, start = 0.675, length = 0.066, gain = 8.883, clack = false },
		{ id = 9117266497, start = 0.047, length = 0.062, gain = 1.993, clack = false },
		{ id = 9117266497, start = 0.111, length = 0.032, gain = 2.672, clack = false },
		{ id = 9117266497, start = 0.159, length = 0.062, gain = 1.714, clack = false },
		{ id = 9117266497, start = 0.223, length = 0.066, gain = 2.666, clack = false },
		{ id = 9117266497, start = 0.297, length = 0.024, gain = 2.370, clack = false },
		{ id = 9117266497, start = 0.327, length = 0.048, gain = 2.755, clack = false },
		{ id = 9117266497, start = 0.403, length = 0.034, gain = 1.582, clack = false },
		{ id = 9117266497, start = 0.439, length = 0.026, gain = 2.873, clack = false },
		{ id = 9117266497, start = 0.467, length = 0.044, gain = 2.348, clack = false },
		{ id = 9117266497, start = 0.515, length = 0.050, gain = 4.069, clack = false },
		{ id = 9117266497, start = 0.573, length = 0.064, gain = 11.120, clack = false },
		{ id = 9118624159, start = 0.000, length = 0.076, gain = 0.619, clack = true },
		{ id = 9118624415, start = 0.000, length = 0.084, gain = 1.011, clack = true },
		{ id = 9118624423, start = 0.000, length = 0.088, gain = 0.620, clack = true },
		{ id = 9118624649, start = 0.000, length = 0.076, gain = 0.617, clack = true },
		{ id = 9118624847, start = 0.000, length = 0.082, gain = 0.619, clack = true },
	},

	-- The crunch under the ticks: "Vehicle Gravel Tire Pass By Constant No Engine 2", the
	-- steady 6.5 to 17.5 s of it, looped, never restarted while the car exists
	Bed = {
		SoundId = "rbxassetid://9126157118",
		RegionStart = 6.5,
		RegionEnd = 17.5,
		LowGain = -30, -- dB, an `EqualizerSoundEffect` under 400 Hz: the tyre rumble out
	},
	BedVolume = 0.62,
	BedSpeedPower = 0.8,
	BedSlideBoost = 0.5,
	BedPitchMin = 0.85, -- the crunch's PlaybackSpeed from standing to `FullSpeed`
	BedPitchMax = 1.15,

	RollOffMin = 12, -- studs, as the skid's
	RollOffMax = 150,
}
