--!strict
-- PerfectHairpin: the "perfect hairpin" conditional score event, the lenient one (T-299
-- send-back: "sustained drift within the white lines, that's it"). On a true hairpin only
-- (`Road/Hairpins`: 120 degrees within 200 studs), a drift held from its entry to its exit
-- (the model's drift, any number of wheels, either way round; a lapse up to `Grace`
-- forgiven) on the tarmac between the two white edge lines. Crossing the double yellow is
-- fine; one wheel past an edge line is forgiven, two void it. The detector is
-- `Drift/Events/BendDrift`; this is its spec. Numbers:
-- `Config.ScoreEvents.Detectors.PerfectHairpin`, points `Kinds.perfectHairpin`.
--
-- Its helpers (`slidingWheels`, `wheelSpan`, `speed`, `splineOf`) are `BendDrift`'s, kept
-- here too for the detectors that reach them through this module (the flick, T-300).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BendDrift = require(script.Parent.BendDrift)

local PerfectHairpin = {}

PerfectHairpin.Kind = "perfectHairpin"
PerfectHairpin.Tuning = Config.ScoreEvents.Detectors.PerfectHairpin

PerfectHairpin.slidingWheels = BendDrift.slidingWheels
PerfectHairpin.wheelsAcross = BendDrift.wheelsAcross
PerfectHairpin.wheelSpan = BendDrift.wheelSpan
PerfectHairpin.speed = BendDrift.speed
PerfectHairpin.splineOf = BendDrift.splineOf

function PerfectHairpin.new(sink: any, rig: any)
	return BendDrift.new(sink, rig, {
		kind = PerfectHairpin.Kind,
		tuning = PerfectHairpin.Tuning,
		hairpinsOnly = true,
		lane = "edges",
	})
end

return PerfectHairpin
