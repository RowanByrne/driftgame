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
--
-- A section that opens a FIELD (T-212) is checked a few ms a frame before it is laid: its
-- checks only read the road, and the road gains the section whole, in one append, once
-- they pass. Sections behind it wait their turn, so the order never changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local SplineGen = require(ReplicatedStorage.Shared.Road.SplineGen)
local Infield = require(ReplicatedStorage.Shared.Road.SplineInfield)

local DriftController = require(script.Parent.DriftController)

local SplineRoadController = {}

local spline: any = nil
local closing: number? = nil
local stats = { starts = 0, sections = 0, outOfOrder = 0, stops = 0, closings = 0, bad = 0, queuedMost = 0, slices = 0, worstSliceMs = 0, worstLayMs = 0 }
-- Sections received but not laid yet, oldest first, and the coroutine checking the first.
local queue: { any } = {}
local job: thread? = nil
local deadline = math.huge

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
	for _, key in { "rl", "rr", "el", "er", "gd", "hl", "hr" } do
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
	if sec.bm ~= nil and not numbers(sec.bm, 3) then
		return false
	end
	return true
end

-- Inside the checking coroutine only: hand the frame back once the slice is spent.
local function checkpoint()
	if job ~= nil and coroutine.running() == job and os.clock() >= deadline then
		coroutine.yield()
	end
end

-- A received section, ready to append: its fields made canonical and checked against the
-- road as it is, readonly. The append then reuses exactly these patches' compiled geometry
-- and repeats every guard, without suspending. Errors if the section would not lay.
local function prepare(road: any, sec: any): any
	if type(sec.ip) ~= "table" or #sec.ip == 0 then
		return sec
	end
	local list = {}
	for _, patch in sec.ip do
		table.insert(list, Infield.canonical(patch))
		checkpoint()
	end
	local index = road.infields or Infield.new()
	local pending = Infield.new()
	for i, patch in list do
		Infield.validate(index, patch, checkpoint)
		Infield.validate(pending, patch, checkpoint)
		if i < #list then
			Infield.add(pending, patch)
		end
	end
	local ready = table.clone(sec)
	ready.ip = list
	return ready
end

local function lay(sec: any): boolean
	local at = os.clock()
	local ok, err = pcall(spline.append, spline, sec)
	stats.worstLayMs = math.max(stats.worstLayMs, (os.clock() - at) * 1000)
	if not ok then
		stats.bad += 1
		warn(`[SplineRoad] a section would not lay: {err}`)
		return false
	end
	stats.sections += 1
	return true
end

local function cancelQueue()
	table.clear(queue)
	job = nil
end

-- One frame's work on the queue: check the first section a slice at a time, lay it once
-- checked, and go on to the next while the slice lasts.
local function drain(budgetMs: number)
	local road = spline
	if not road then
		cancelQueue()
		return
	end
	deadline = os.clock() + budgetMs / 1000
	while #queue > 0 and spline == road do
		local sec = queue[1]
		if not job then
			job = coroutine.create(prepare)
		end
		local thread = job :: thread
		local at = os.clock()
		local ok, ready = coroutine.resume(thread, road, sec)
		stats.slices += 1
		stats.worstSliceMs = math.max(stats.worstSliceMs, (os.clock() - at) * 1000)
		if not ok then
			stats.bad += 1
			warn(`[SplineRoad] a section would not lay: {ready}`)
			cancelQueue() -- the road stops growing here, as it always has
			return
		end
		if coroutine.status(thread) ~= "dead" then
			return -- the slice is spent; carry on next frame
		end
		job = nil
		table.remove(queue, 1)
		if spline ~= road or not lay(ready) then
			cancelQueue()
			return
		end
		if os.clock() >= deadline then
			return
		end
	end
	deadline = math.huge
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
		-- the mountain's uphill heading, for the hillside between the legs (T-190)
		local fall = if type(message.fall) == "number" and message.fall == message.fall then message.fall else nil
		local ok, built = pcall(SplineGen.replay, message.sections, { x = o.x, y = o.y, z = o.z, yaw = o.yaw }, fall)
		if not ok then
			stats.bad += 1
			warn(`[SplineRoad] the road would not replay: {built}`)
			return
		end
		cancelQueue()
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
		if message.from ~= spline.sections + #queue + 1 or type(message.sections) ~= "table" then
			stats.outOfOrder += 1
			return
		end
		for _, sec in message.sections do
			if not validSection(sec) then
				stats.bad += 1
				return
			end
			-- a plain section with nothing waiting ahead of it is laid at once, as always
			if #queue == 0 and (type(sec.ip) ~= "table" or #sec.ip == 0) then
				if not lay(sec) then
					return
				end
			else
				table.insert(queue, sec)
				stats.queuedMost = math.max(stats.queuedMost, #queue)
			end
		end
	elseif kind == "closing" then
		if spline and type(message.s) == "number" then
			stats.closings += 1
			closing = message.s
			DriftController:SetSplineClosing(message.s)
		end
	elseif kind == "stop" then
		stats.stops += 1
		cancelQueue()
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
	RunService.Heartbeat:Connect(function()
		if #queue > 0 then
			drain(Config.Spline.Pump.BudgetMs)
		end
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
		queued = #queue,
		counts = table.clone(stats),
	}
end

return SplineRoadController
