--!nonstrict
-- RoadMapController: the road-ahead map in the top left (docs/game/features/road-ahead-map.md,
-- T-234). The drawing is `Drift/RoadMapView`; this is its feed.
--
-- CLIENT ONLY, AND IT SENDS NOTHING. The client already holds the run's whole road, replayed
-- from the server's sections (`SplineRoadController:Road()`), and its own car
-- (`DriftController:CurrentState()`). The map reads both and draws.
--
-- SHOWN WHILE THERE IS A ROAD AND A CAR: in a run. In the playground and the garage there
-- is no spline road, so no map; the garage's and settings' menus put it away with the rest
-- of the HUD (`UiVisibilityController`), and P hides it with everything else.
--
-- ROAD-UP (the user, 2026-11-15): the road's own heading at the car is up, eased through
-- `Config.RoadMap.TurnSmoothing` so a hairpin turns the map round rather than snapping it.
-- A drift never turns the map; the arrow turns instead, showing the nose against the road.
--
-- THE CAR'S PLACE ON THE ROAD is its own `s`, kept from frame to frame and found again
-- from it (`Spline:projectFrom`, a few Newton steps), or by search after a respawn or a
-- teleport. Off the road past `SearchReach`, the map holds the last place it had.
--
-- THE POINTS ARE ON A FIXED GRID along the road (every `PointEvery` studs from its start),
-- plus the car's own `s` and the two ends, so the line does not crawl as the car moves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local DriftFolder = script.Parent.Parent:WaitForChild("Drift")
local RoadMapView = require(DriftFolder:WaitForChild("RoadMapView"))

local DriftController = require(script.Parent.DriftController)
local SplineRoadController = require(script.Parent.SplineRoadController)

local RoadMapController = {}

local TAU = math.pi * 2

local function wrap(angle: number): number
	return (angle + math.pi) % TAU - math.pi
end

function RoadMapController:Init()
	self.spline = nil -- the road the map last drew from
	self.s = nil -- the car's place along it
	self.d = nil -- and off its centre line, nil when not found this time
	self.upYaw = nil -- the map's up, eased toward the road's heading at the car
	self.since = 0 -- seconds since the last redraw
	self.redraws = 0
	self.lastMs = 0
	self.worstMs = 0
	self.totalMs = 0
	self.lost = 0 -- redraws where the car could not be found on the road
	self.snapshot = { mode = "hidden" }
	self.frame = nil -- the last redraw's road frame: origin, up, the points' s
end

function RoadMapController:Start()
	self.view = RoadMapView.new(Players.LocalPlayer:WaitForChild("PlayerGui"))
	RunService.RenderStepped:Connect(function(dt)
		if self.fixture then
			return
		end
		self.since += dt
		if self.since < 1 / Config.RoadMap.RedrawHz then
			return
		end
		local t0 = os.clock()
		self:_redraw(self.since)
		self.since = 0
		local ms = (os.clock() - t0) * 1000
		self.lastMs = ms
		self.totalMs += ms
		self.redraws += 1
		if ms > self.worstMs then
			self.worstMs = ms
		end
	end)
end

-- Where the car is on the road: (s, d), or the last s and nil when it cannot be found.
function RoadMapController:_locate(spline, x: number, z: number)
	local C = Config.RoadMap
	local reach = Config.Road.Width * 0.5 + C.SearchReach
	local s, d
	if self.s then
		s, d = spline:projectFrom(x, z, self.s)
	end
	if not s or not d or math.abs(d) > reach then
		s, d = spline:project(x, z, reach)
	end
	if s and d and math.abs(d) <= reach then
		return s, d
	end
	self.lost += 1
	return self.s, nil
end

function RoadMapController:_redraw(dt: number)
	local C = Config.RoadMap
	local spline = SplineRoadController:Road()
	local state = DriftController:CurrentState()
	if spline ~= self.spline then
		-- a new run, or none: start the car's place and the map's up afresh
		self.spline = spline
		self.s, self.d, self.upYaw = nil, nil, nil
	end
	if not spline or not state then
		self.snapshot = { mode = "hidden" }
		self.frame = nil
		self.view:setData(self.snapshot)
		return
	end
	local pos = state.position
	local s, d = self:_locate(spline, pos.X, pos.Z)
	if not s then
		self.snapshot = { mode = "hidden" }
		self.frame = nil
		self.view:setData(self.snapshot)
		return
	end
	self.s, self.d = s, d

	-- the map's up: the road's heading at the car, eased
	local roadYaw = spline:yawAt(s)
	if not self.upYaw then
		self.upYaw = roadYaw
	else
		local k = 1 - math.exp(-dt / math.max(C.TurnSmoothing, 1e-3))
		self.upYaw = wrap(self.upYaw + wrap(roadYaw - self.upYaw) * k)
	end
	local up = self.upYaw
	local fx, fz = -math.sin(up), -math.cos(up)
	local rx, rz = math.cos(up), -math.sin(up)
	local ox, oz = spline:planAt(s)

	-- the stretch to draw, inside the road this client has
	local first = spline.firstSample * spline.step
	local s0 = math.max(s - C.BehindStuds, first, 0)
	local s1 = math.min(s + C.AheadStuds, spline.length)
	local every = C.PointEvery
	local list = { s0 }
	local k = math.floor(s0 / every) + 1
	local carAdded = s <= s0
	while k * every < s1 do
		local sk = k * every
		if not carAdded and sk >= s then
			if sk > s then
				table.insert(list, s)
			end
			carAdded = true
		end
		table.insert(list, sk)
		k += 1
	end
	if not carAdded and s < s1 then
		table.insert(list, s)
	end
	if s1 > list[#list] then
		table.insert(list, s1)
	end

	local tightK = 1 / C.TightRadius
	local r, a, tight = table.create(#list), table.create(#list), table.create(#list)
	local behind = 0
	for i, si in list do
		local x, z = spline:planAt(si)
		local dx, dz = x - ox, z - oz
		r[i] = dx * rx + dz * rz
		a[i] = dx * fx + dz * fz
		if i > 1 then
			local mid = (list[i - 1] + si) * 0.5
			tight[i - 1] = math.abs(spline:curvatureAt(mid)) >= tightK
			if si <= s then
				behind = i - 1
			end
		end
	end

	-- the arrow: the car's true place, and its nose against the map's up (clockwise)
	local cdx, cdz = pos.X - ox, pos.Z - oz
	local arrow = {
		r = cdx * rx + cdz * rz,
		a = cdx * fx + cdz * fz,
		deg = -math.deg(wrap(state.yaw - up)),
	}

	self.frame = { ox = ox, oz = oz, up = up, list = list }
	self.snapshot = { mode = "map", r = r, a = a, tight = tight, behind = behind, arrow = arrow }
	self.view:setData(self.snapshot)
end

------------------------------------------------------------------------------- debug

-- The map as drawn, for tests and agent playtests:
--   game.Players.LocalPlayer.PlayerScripts.DebugBridge:Invoke("RoadMapController", "DebugState")
function RoadMapController:DebugState()
	local snap = self.snapshot
	local list = self.frame and self.frame.list
	return {
		shown = snap.mode == "map",
		points = snap.r and #snap.r or 0,
		studsAhead = (list and self.s) and (list[#list] - self.s) or 0,
		studsBehind = (list and self.s) and (self.s - list[1]) or 0,
		tightSegments = snap.tight and (function()
			local n = 0
			for _, t in snap.tight do
				if t then
					n += 1
				end
			end
			return n
		end)() or 0,
		s = self.s,
		d = self.d,
		upDeg = self.upYaw and math.deg(self.upYaw) or nil,
		roadDeg = (self.spline and self.s) and math.deg(self.spline:yawAt(self.s)) or nil,
		arrowDeg = snap.arrow and snap.arrow.deg or nil,
		redraws = self.redraws,
		lost = self.lost,
		lastMs = self.lastMs,
		avgMs = if self.redraws > 0 then self.totalMs / self.redraws else 0,
		worstMs = self.worstMs,
		view = self.view and self.view:describe() or nil,
	}
end

-- Checks the whole drawing against the road, back from the PIXELS the view placed: each
-- point's pixel is turned back into a world plan point and measured against the spline's
-- own centre line at that `s`; the arrow's pixel against the car. Studs.
function RoadMapController:DebugCheck()
	local snap, frame, view, spline = self.snapshot, self.frame, self.view, self.spline
	if snap.mode ~= "map" or not frame or not spline then
		return { shown = false }
	end
	local fx, fz = -math.sin(frame.up), -math.cos(frame.up)
	local rx, rz = math.cos(frame.up), -math.sin(frame.up)
	local function back(px: number, py: number): (number, number)
		local r = (px - view.anchor.X) / view.scale
		local a = (view.anchor.Y - py) / view.scale
		return frame.ox + r * rx + a * fx, frame.oz + r * rz + a * fz
	end
	local worst, worstAt, inside = 0, nil, 0
	local size = view.layout.size
	for i, si in frame.list do
		local px, py = view:toPixels(snap.r[i], snap.a[i])
		if px >= 0 and px <= size and py >= 0 and py <= size then
			inside += 1
		end
		local x, z = back(px, py)
		local tx, tz = spline:planAt(si)
		local err = math.sqrt((x - tx) ^ 2 + (z - tz) ^ 2)
		if err > worst then
			worst, worstAt = err, si
		end
	end
	-- the arrow as drawn, relative to the panel
	local arrowPx = view.arrow.AbsolutePosition + view.arrow.AbsoluteSize * 0.5 - view.panel.AbsolutePosition
	local ax, az = back(arrowPx.X, arrowPx.Y)
	local state = DriftController:CurrentState()
	local carGap = state and math.sqrt((ax - state.position.X) ^ 2 + (az - state.position.Z) ^ 2) or nil
	-- and the arrow from the line: the centre line's point at the car
	local lineGap = math.sqrt((ax - frame.ox) ^ 2 + (az - frame.oz) ^ 2)
	return {
		shown = true,
		points = #frame.list,
		pointsInside = inside,
		worstPointError = worst,
		worstAt = worstAt,
		arrowToCar = carGap,
		arrowToLine = lineGap,
		carOffRoad = self.d,
		scale = view.scale,
	}
end

-- Studio only: draw the map from a fixture (`Drift/RoadMapView.fixtures`), or `nil` to hand
-- it back to the live road.
function RoadMapController:DebugFixture(name: string?)
	if not RunService:IsStudio() then
		return nil
	end
	if name == nil then
		self.fixture = nil
		return self.view:describe()
	end
	local fixtures = require(DriftFolder:WaitForChild("RoadMapView.fixtures"))
	self.fixture = fixtures[name]
	assert(self.fixture, `no fixture '{name}'`)
	self.view:setData(self.fixture)
	return self.view:describe()
end

return RoadMapController
