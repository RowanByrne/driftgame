--!nonstrict
-- Redraw coverage when streamed road arrives during a sliced mesh build (T-190).
local RunService = game:GetService("RunService")
assert(RunService:IsStudio(), "SplineViewTests is Studio only")
local Config = require(game.ReplicatedStorage.Shared.Config)
local View = require(game.StarterPlayer.StarterPlayerScripts.Drift.SplineRoadView)
local Tests = {}
function Tests.run()
	local checks = {}
	local function check(name, ok, detail)
		table.insert(checks, {name=name, ok=ok, detail=detail})
	end
	local L = Config.Spline.Mesh.ChunkLength
	local spline = {length=L * 2, cell=64, planAt=function(_, s) return s, 0 end}
	local state = {spline=spline, checkedTo=L, chunks={}, building=0, builtAt={[0]=L}, stale={}}
	View._checkNewRoad(state)
	check("new road invalidates a first chunk still being built", state.stale[0] == true,
		"road arrives before the first mesh is inserted into chunks")
	state = {spline=spline, checkedTo=L, chunks={[0]=true}, builtAt={[0]=L}, stale={}}
	View._checkNewRoad(state)
	check("nearby stations invalidate completed ground even if no ray gets shorter", state.stale[0] == true,
		"caps and meeting heights use every gathered station cell")
	local distant = {length=L*2, cell=64, planAt=function(_, s) return if s>L then 10000+s else s, 0 end}
	state = {spline=distant, checkedTo=L+16, chunks={[0]=true}, builtAt={[0]=L}, stale={}}
	View._checkNewRoad(state)
	check("road outside gathered cells leaves a chunk alone", state.stale[0] == nil,
		"far stations cannot affect its hillside context")
	local passed=0
	for _, c in checks do if c.ok then passed+=1 end end
	return {passed=passed,total=#checks,checks=checks}
end
return Tests