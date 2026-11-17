--!strict
-- Config.Pebbles: the stones kicked up into the wheel wells off the road (T-292,
-- `Drift/PebbleSound`, docs/game/AUDIO.md). Round 1's pick ("D: Ticks + crunch", pebble
-- ticks) was sent back on 2026-11-17 ("this is like pebbles on pebbles"); the pick is round
-- 2's "E: Floor-pan clanks": stones on sheet metal, half heavy floor-pan and thin-metal
-- clanks and half light pings, fired at random over a quiet gravel crunch loop. Every id is Creator Store audio by Pro Sound Effects, free in any experience,
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
-- sliding, the hits are about -26.5 dBFS and the crunch -35.5 (together about -26), which
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
	MaxRate = 18, -- a second, full speed on gravel, not sliding (26 for round 1's pebble
	-- ticks; a ringing clank is longer than a tick)
	SlideRateBoost = 0.8, -- x(1 + this) at a full slide: about 32 a second
	MaxPerFrame = 4, -- a long frame never fires a burst bigger than this
	TickVolume = 0.36, -- the master for the hits (a hit's instance volume is held at 10)
	TickSpeedFloor = 0.35, -- a tick's loudness at walking pace, against 1 at `FullSpeed`
	TickRandomVolume = 0.35, -- each tick is this to 1 of its loudness, at random
	PitchMin = 0.85, -- each tick's PlaybackSpeed, at random between these
	PitchMax = 1.2,
	ClackShare = 0.5, -- the share of hits that are the heavy floor-pan clanks
	Voices = 14, -- `Sound`s the hits take turns on, made once per car: an idle one, else
	-- the one nearest its end, so a ring is seldom cut
	FadeTail = 0.05, -- s: each hit's volume ramps to 0 over its last this much
	-- The hits: `start` and `length` in seconds into the store file, `gain` brings each one's
	-- peak to 0.5. Each runs from its onset to where it has rung down 30 dB, and its last
	-- `FadeTail` fades out (a metal ring cut dead clicks). `clack = true` are the heavy ones.
	-- Pings: 9116695715 "Metal Impacts 6" (a vehicle floor, light), 9116701254 "Metal Impacts 2"
	-- (thin sheet metal, a vehicle body), 9125596462 "Hammer Soft Taps On Metal Roof Sharp Clinks 2".
	-- Clanks: 9116698689 / 9116698012 / 9116695441 "Metal Impacts 13 / 5 / 4" (an interior vehicle
	-- floor), 9125464752 / 9125464768 "Corrugated Roof Pounding Impacts On Thin Metal 2 / 6".
	Ticks = {
		{ id = 9116695715, start = 1.191, length = 0.214, gain = 20.048, clack = false },
		{ id = 9116701254, start = 0.000, length = 0.205, gain = 28.641, clack = false },
		{ id = 9125596462, start = 0.236, length = 0.229, gain = 3.242, clack = false },
		{ id = 9125596462, start = 1.361, length = 0.234, gain = 17.008, clack = false },
		{ id = 9125596462, start = 1.881, length = 0.234, gain = 9.479, clack = false },
		{ id = 9116698689, start = 0.861, length = 0.359, gain = 0.773, clack = true },
		{ id = 9116698012, start = 0.631, length = 0.359, gain = 1.144, clack = true },
		{ id = 9116695441, start = 0.621, length = 0.189, gain = 4.258, clack = true },
		{ id = 9125464752, start = 0.116, length = 0.269, gain = 1.462, clack = true },
		{ id = 9125464752, start = 0.716, length = 0.254, gain = 1.203, clack = true },
		{ id = 9125464752, start = 1.321, length = 0.259, gain = 1.175, clack = true },
		{ id = 9125464752, start = 1.986, length = 0.249, gain = 1.143, clack = true },
		{ id = 9125464752, start = 2.671, length = 0.249, gain = 1.131, clack = true },
		{ id = 9125464768, start = 0.176, length = 0.304, gain = 1.102, clack = true },
		{ id = 9125464768, start = 0.846, length = 0.234, gain = 1.318, clack = true },
		{ id = 9125464768, start = 1.566, length = 0.284, gain = 1.097, clack = true },
		{ id = 9125464768, start = 2.466, length = 0.259, gain = 2.781, clack = true },
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
