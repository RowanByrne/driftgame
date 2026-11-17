--!strict
-- LaneDrift: the "lane drift" conditional score event (T-299 send-back: the old perfect
-- hairpin's rule, on every double-yellow bend, under a new name). A drift into the bend on
-- 2+ wheels from its entry to its exit, in your own lane: the double yellow's side you
-- entered on, out to the white edge line; one wheel over a line is forgiven, two void it.
-- The detector is `Drift/Events/BendDrift`; this is its spec. Numbers:
-- `Config.ScoreEvents.Detectors.LaneDrift`, points `Kinds.laneDrift`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BendDrift = require(script.Parent.BendDrift)

local LaneDrift = {}

LaneDrift.Kind = "laneDrift"
LaneDrift.Tuning = Config.ScoreEvents.Detectors.LaneDrift

function LaneDrift.new(sink: any, rig: any)
	return BendDrift.new(sink, rig, {
		kind = LaneDrift.Kind,
		tuning = LaneDrift.Tuning,
		intoBend = true,
		minWheels = 2,
		lane = "own",
	})
end

return LaneDrift
