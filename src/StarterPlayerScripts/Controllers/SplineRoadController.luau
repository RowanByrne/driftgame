--!strict
-- SplineRoadController: the endless run's spline road on this client
-- (features/spline-road.md "Server and client", T-136).
--
-- The server lays the road and sends it, a section at a time, on `RoadSpline`; this builds
-- the client's own copy of the curve from exactly those sections and hands it to
-- `DriftController`, whose car then stands on its maths and whose view draws it. The client
-- chooses nothing: it replays what it is sent, in order.
--
--   start    the origin and every section so far, and the closing barrier: sent once,
--            when this player joins the run, before the car is put on the road
--   more     the sections after the last one sent, as the window grows
--   closing  where the closing barrier now stands, in studs along the road
--   stop     the run is over for this player
--
-- Each section carries its mountainside with it (T-140): runoff, edges and K-rails.
--
-- A message out of order (a `more` that does not follow on) is not guessed at: it is
-- counted and the road stops growing on this client, which shows as the end of the drawn
-- road rather than a road that disagrees with the server's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)

local DriftController = require(script.Parent.DriftController)

local SplineRoadController = {}

local spline: any = nil
local closing: number? = nil
local stats = { starts = 0, sections = 0, outOfOrder = 0, stops = 0, closings = 0, bad = 0 }

local function numbers(list: any, group: number): boolean
	if type(list) ~= "table" or #list < group or #list % group ~= 0 then
		return false
	end
	for _, v in list do
		if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
			return false
		end
	end
	return true
end

-- The shape of a section. What the numbers mean -- in order, inside the section, a known
-- edge -- `Spline.append` checks, and a section it refuses is refused whole.
local function validSection(sec: any): boolean
	if type(sec) ~= "table" or type(sec.len) ~= "number" or sec.len <= 0 then
		return false
	end
	for _, key in { "k", "g", "b" } do
		if not numbers(sec[key], 2) then
			return false
		end
	end
	for _, key in { "rl", "rr", "el", "er", "gd" } do
		if sec[key] ~= nil and not numbers(sec[key], 2) then
			return false
		end
	end
	if sec.kr ~= nil and not numbers(sec.kr, 3) then
		return false
	end
	if sec.gl ~= nil and not numbers(sec.gl, 3) then -- gravel runs (T-181)
		return false
	end
	if sec.gv ~= nil and not numbers(sec.gv, 2) then
		return false
	end
	return true
end

function SplineRoadController:_on(message: any)
	if type(message) ~= "table" then
		stats.bad += 1
		return
	end
	local kind = message.kind
	if kind == "start" then
		local o = message.origin
		if type(o) ~= "table" or type(message.sections) ~= "table" then
			stats.bad += 1
			return
		end
		for _, sec in message.sections do
			if not validSection(sec) then
				stats.bad += 1
				return
			end
		end
		local ok, built = pcall(SplineGen.replay, message.sections, { x = o.x, y = o.y, z = o.z, yaw = o.yaw })
		if not ok then
			stats.bad += 1
			warn(`[SplineRoad] the road would not replay: {built}`)
			return
		end
		spline = built
		stats.starts += 1
		stats.sections = #message.sections
		closing = if type(message.closing) == "number" then message.closing else nil
		DriftController:UseSpline(spline)
		DriftController:SetSplineClosing(closing)
	elseif kind == "more" then
		if not spline then
			return
		end
		if message.from ~= spline.sections + 1 or type(message.sections) ~= "table" then
			stats.outOfOrder += 1
			return
		end
		for _, sec in message.sections do
			if not validSection(sec) then
				stats.bad += 1
				return
			end
			local ok, err = pcall(spline.append, spline, sec)
			if not ok then
				stats.bad += 1
				warn(`[SplineRoad] a section would not lay: {err}`)
				return
			end
			stats.sections += 1
		end
	elseif kind == "closing" then
		if spline and type(message.s) == "number" then
			stats.closings += 1
			closing = message.s
			DriftController:SetSplineClosing(message.s)
		end
	elseif kind == "stop" then
		stats.stops += 1
		spline = nil
		closing = nil
		DriftController:UseSpline(nil)
	else
		stats.bad += 1
	end
end

function SplineRoadController:Init() end

function SplineRoadController:Start()
	local remote = Net.event("RoadSpline")
	remote.OnClientEvent:Connect(function(message)
		self:_on(message)
	end)
end

-- The road on this client right now, and where its closing barrier stands: nil and nil
-- with no run. What `RoadGroundController` builds our walking avatar's ground from (T-154).
-- The curve is the live copy, growing as sections arrive: read it, never change it.
function SplineRoadController:Road(): (any?, number?)
	return spline, closing
end

function SplineRoadController:DebugState()
	return {
		on = spline ~= nil,
		length = spline and spline.length or 0,
		sections = spline and spline.sections or 0,
		counts = table.clone(stats),
	}
end

return SplineRoadController
