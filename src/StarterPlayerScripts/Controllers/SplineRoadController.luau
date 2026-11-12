--!strict
-- SplineRoadController: the endless run's spline road on this client
-- (features/spline-road.md "Server and client", T-136).
--
-- The server lays the road and sends it, a section at a time, on `RoadSpline`; this builds
-- the client's own copy of the curve from exactly those sections and hands it to
-- `DriftController`, whose car then stands on its maths and whose view draws it. The client
-- chooses nothing: it replays what it is sent, in order.
--
--   start    the origin and every section so far, the closing barrier, the guardrails:
--            sent once, when this player joins the run, before the car is put on the road
--   more     the sections after the last one sent, as the window grows
--   closing  where the closing barrier now stands, in studs along the road
--   rails    the guardrails, switched on or off
--   stop     the run is over for this player
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
local stats = { starts = 0, sections = 0, outOfOrder = 0, stops = 0, closings = 0, rails = 0, bad = 0 }

local function validSection(sec: any): boolean
	if type(sec) ~= "table" or type(sec.len) ~= "number" or sec.len <= 0 then
		return false
	end
	for _, key in { "k", "g", "b" } do
		local knots = sec[key]
		if type(knots) ~= "table" or #knots < 2 or #knots % 2 ~= 0 then
			return false
		end
		for _, v in knots do
			if type(v) ~= "number" or v ~= v then
				return false
			end
		end
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
		DriftController:SetSplineRails(message.rails ~= false)
		DriftController:UseSpline(spline)
		DriftController:SetSplineClosing(if type(message.closing) == "number" then message.closing else nil)
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
			spline:append(sec)
			stats.sections += 1
		end
	elseif kind == "closing" then
		if spline and type(message.s) == "number" then
			stats.closings += 1
			DriftController:SetSplineClosing(message.s)
		end
	elseif kind == "rails" then
		stats.rails += 1
		DriftController:SetSplineRails(message.on == true)
	elseif kind == "stop" then
		stats.stops += 1
		spline = nil
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

function SplineRoadController:DebugState()
	return {
		on = spline ~= nil,
		length = spline and spline.length or 0,
		sections = spline and spline.sections or 0,
		counts = table.clone(stats),
	}
end

return SplineRoadController
