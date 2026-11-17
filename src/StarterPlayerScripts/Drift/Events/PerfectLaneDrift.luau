--!strict
-- PerfectLaneDrift: the "perfect lane drift" conditional score event (T-299 send-back: the
-- old perfect hairpin's hard level, renamed, still scoring very high). All four wheels
-- sliding into the bend from its entry to its exit (each by its own slip gate, a lapse up
-- to `Grace` forgiven), on every double-yellow bend, in your own lane: the double yellow's
-- side you entered on, out to the white edge line. One wheel over a line is forgiven, two
-- void it. The detector is `Drift/Events/BendDrift`; this is its spec. Numbers:
-- `Config.ScoreEvents.Detectors.PerfectLaneDrift`, points `Kinds.perfectLaneDrift`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BendDrift = require(script.Parent.BendDrift)

local PerfectLaneDrift = {}

PerfectLaneDrift.Kind = "perfectLaneDrift"
PerfectLaneDrift.Tuning = Config.ScoreEvents.Detectors.PerfectLaneDrift

function PerfectLaneDrift.new(sink: any, rig: any)
	return BendDrift.new(sink, rig, {
		kind = PerfectLaneDrift.Kind,
		tuning = PerfectLaneDrift.Tuning,
		intoBend = true,
		minWheels = 2,
		needFour = true,
		lane = "own",
	})
end

return PerfectLaneDrift
