--!strict
-- NearMiss: the near miss score event (features/score-events.md, T-298): a one-off when the
-- car passes a grove tree's trunk close, at speed, without touching it. Trees only (the
-- user, 2026-11-17: "near miss (easy, trees only, proximity to object gives higher boost)").
--
-- A detector (score-events.md "The shared interface"): `NearMiss.new(sink, rig)`,
-- `:Update(dt, state)` each frame with the model's state, `:DebugState()`. It calls only
-- `sink.oneOff("nearMiss", size, info)`; points, words, repeats and the feed are the
-- engine's.
--
-- WHERE THE TREES ARE. No part: a grove's trees are drawn into the road's chunk meshes and
-- their trunks are solid only in the road's maths (`Road/SplineGrove`, `Drift/SplineWorld`).
-- Every device places the same trees from the section's seed, so this asks the same
-- lookup the car's collision asks: `SplineGrove.items(spline, s0, s1, side)`, a binary
-- search over the grove runs by distance along the road. The trees within `Window` studs
-- of the car's `s` are fetched only when the car has moved `Refetch` studs since the last
-- fetch; between fetches a frame looks at a handful of trunks at most.
--
-- THE GAP is the one the collision uses: the car's body box (`BodyWidth` x `BodyLength`)
-- against the trunk's circle, flat, in studs; 0 is touching. The collision holds a scraping
-- car `0.05` clear, so a gap under `TouchGap` is a touch.
--
-- A PASS. A tree comes under watch when the gap falls under `Watch`, and its pass is over
-- when the gap has opened `Open` studs past the closest it came (or the tree is out of
-- reach). Then `Confirm` seconds more must go by with nothing touched: any wall hit from
-- the pass's start to the end of `Confirm`, or a fall, voids it. A pass whose closest gap
-- was under `Threshold`, with the car moving forward at `MinSpeed` or more at that moment,
-- fires once: `size` = 0 at `Threshold`, 1 at `FullGap` and closer. A tree that has had a
-- pass is ignored for `Rearm` seconds, so a gap wobbling round the line is one pass.
--
-- `Watch` is wider than `Threshold` only to measure: every pass under `Watch` goes into
-- the closest-pass histogram `DebugState` returns.
--
-- `rig` is the engine's (`DriftController.scoreRig`): `spline()` (the road, a `Road/Spline`,
-- or nil off it) and `along()` (the car's distance along it), asked fresh each update. A
-- plain `spline` / `splineAlong` field is taken too. Tests may give
-- `rig.lookup(spline, s0, s1, out)` to stand in for the grove.
--
-- Stepped once per simulation step (120 Hz) by the drift controller, or once per frame:
-- everything is measured in the `dt` it is handed, so either gives the same events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SplineGrove = require(ReplicatedStorage.Shared.Road.SplineGrove)

local NearMiss = {}
NearMiss.__index = NearMiss

NearMiss.KIND = "nearMiss"

-- The numbers: `Config.ScoreEvents.Detectors.NearMiss` (points, words and repeats are the
-- engine's `Kinds.nearMiss`).
NearMiss.Defaults = Config.ScoreEvents.Detectors.NearMiss

-- the closest-pass histogram's bucket edges, studs of gap
local BUCKETS = { 0.1, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 10 }
local RECENT = 20

export type Tree = { x: number, y: number, z: number, h: number, trunk: number, s: number, side: number }

type Pass = {
	tree: Tree,
	minGap: number,
	speedAtMin: number,
	forwardAtMin: boolean,
	touched: boolean, -- this trunk was touched
	wall: boolean, -- another wall was, during the pass or its `Confirm`
	over: boolean,
	clock: number, -- seconds since the pass was over
}

export type Sink = { oneOff: (kind: string, size: number, info: { [string]: any }?) -> () }

local function tuning(): { [string]: number }
	return table.clone(NearMiss.Defaults)
end

-- The flat gap between the car's box (centre px, pz; right and forward; half width and
-- length) and a trunk's circle: as `Road/SplineGrove`'s collision measures it.
local function gap(px: number, pz: number, rx: number, rz: number, fx: number, fz: number, hw: number, hl: number, tx: number, tz: number, tr: number): number
	local ex, ez = tx - px, tz - pz
	local lx, lz = ex * rx + ez * rz, ex * fx + ez * fz
	local qx, qz = math.abs(lx) - hw, math.abs(lz) - hl
	if qx > 0 or qz > 0 then
		local ox, oz = math.max(qx, 0), math.max(qz, 0)
		return math.sqrt(ox * ox + oz * oz) - tr
	end
	return math.max(qx, qz) - tr
end
NearMiss._gap = gap

local function defaultLookup(spline: any, s0: number, s1: number, out: { any })
	SplineGrove.items(spline, s0, s1, -1, out)
	SplineGrove.items(spline, s0, s1, 1, out)
end

function NearMiss.new(sink: Sink, rig: any, opts: { [string]: number }?)
	local self = setmetatable({}, NearMiss)
	self.sink = sink
	self.rig = rig
	self.t = tuning()
	if opts then
		for k, v in opts do
			self.t[k] = v
		end
	end
	local D = Config.Drift
	self.hw = D.BodyWidth * 0.5
	self.hl = D.BodyLength * 0.5
	self.bh = D.BodyHeight * 0.6 * 0.5 -- the collision's box height (`Drift/SplineWorld`)
	self.clock = 0
	self.trees = {} :: { Tree } -- trunks only, near the car
	self.fetchedAt = nil :: number?
	self.fetchedSpline = nil :: any
	self.passes = {} :: { [Tree]: Pass }
	self.rested = setmetatable({}, { __mode = "k" }) :: any -- tree -> clock its last pass ended
	self.lastPos = nil :: Vector3?
	self.seen = {} :: { [Tree]: boolean }
	-- measuring
	self.stats = {
		frames = 0,
		fetches = 0,
		looked = 0, -- trunks looked at, all frames
		passes = 0, -- passes under Watch
		fired = 0,
		hit = 0, -- would have fired, voided by touching this trunk
		wall = 0, -- would have fired, voided by touching another wall (another trunk)
		slow = 0, -- under Threshold, but too slow or backward
		fell = 0,
		hist = table.create(#BUCKETS + 1, 0),
		closest = math.huge, -- the closest gap this frame
		last = nil :: any,
		recent = {} :: { any }, -- the last `RECENT` passes under Threshold, and what came of each
		micros = 0, -- total Update time
	}
	return self
end

function NearMiss:_forget(why: string?)
	for _, p in self.passes do
		if why == "fell" and p.minGap < self.t.Threshold then
			self.stats.fell += 1
		end
		self.rested[p.tree] = self.clock
	end
	table.clear(self.passes)
end

function NearMiss:_end(p: Pass)
	local t = self.t
	local st = self.stats
	self.passes[p.tree] = nil
	self.rested[p.tree] = self.clock
	st.passes += 1
	local bucket = #BUCKETS + 1
	for i, edge in BUCKETS do
		if p.minGap < edge then
			bucket = i
			break
		end
	end
	st.hist[bucket] += 1
	if p.minGap >= t.Threshold then
		return
	end
	local outcome = if p.touched then "hit" elseif p.wall then "wall" elseif not p.forwardAtMin or p.speedAtMin < t.MinSpeed then "slow" else "fired"
	if #st.recent >= RECENT then
		table.remove(st.recent, 1)
	end
	table.insert(st.recent, { gap = p.minGap, outcome = outcome, speed = p.speedAtMin, s = p.tree.s, side = p.tree.side, e = (p.tree :: any).e, at = self.clock })
	if outcome ~= "fired" then
		st[outcome] += 1
		return
	end
	local size = math.clamp((t.Threshold - p.minGap) / (t.Threshold - t.FullGap), 0, 1)
	st.fired += 1
	local info = { gap = p.minGap, speed = p.speedAtMin, s = p.tree.s, side = p.tree.side, x = p.tree.x, z = p.tree.z }
	st.last = { gap = p.minGap, size = size, speed = p.speedAtMin, at = self.clock }
	self.sink.oneOff(NearMiss.KIND, size, info)
end

function NearMiss:Update(dt: number, state: any)
	local t0 = os.clock()
	self:_update(dt, state)
	self.stats.micros += (os.clock() - t0) * 1e6
end

function NearMiss:_update(dt: number, state: any)
	local t = self.t
	local st = self.stats
	self.clock += dt
	st.frames += 1
	st.closest = math.huge

	local rig = self.rig
	local spline, along = nil, nil
	if rig then
		spline = if type(rig.spline) == "function" then rig.spline() else rig.spline
		along = if type(rig.along) == "function" then rig.along() else rig.splineAlong
	end
	local pos: Vector3 = state.position
	if state.fell or not spline or type(along) ~= "number" then
		self:_forget(if state.fell then "fell" else nil)
		self.lastPos = pos
		return
	end
	-- a put-back or a teleport: whatever was near before is not a pass
	local vel: Vector3 = state.velocity
	local speed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
	if self.lastPos and (pos - self.lastPos).Magnitude > speed * dt + t.Teleport then
		self:_forget(nil)
		self.fetchedAt = nil
	end
	self.lastPos = pos

	-- the trunks near the car, fetched again only after it has moved along
	if self.fetchedSpline ~= spline or not self.fetchedAt or math.abs(along - self.fetchedAt) > t.Refetch then
		local list = {}
		local lookup = rig.lookup or defaultLookup
		lookup(spline, along - t.Window, along + t.Window, list)
		local trees = {}
		for _, it in list do
			if it.trunk > 0 then
				table.insert(trees, it)
			end
		end
		self.trees = trees
		self.fetchedAt = along
		self.fetchedSpline = spline
		st.fetches += 1
	end

	-- a wall touched anywhere while a pass is open or confirming voids it
	-- (a frame is a few model steps: `sinceWall` catches a touch on any of them, `wallHit`
	-- only the last)
	local since = state.sinceWall
	local wall = state.wallHit == true or (type(since) == "number" and since <= dt + 1e-6)

	local yaw: number = state.yaw
	local fx, fz = -math.sin(yaw), -math.cos(yaw)
	local rx, rz = math.cos(yaw), -math.sin(yaw)
	local hw, hl = self.hw, self.hl
	local reach = math.sqrt(hw * hw + hl * hl) + t.Watch + 1.5
	local forward = (state.u or 0) > 0
	local px, pz, py = pos.X, pos.Z, pos.Y
	local passes = self.passes
	local seen: { [Tree]: boolean } = self.seen
	table.clear(seen)
	for _, tree in self.trees do
		local dx, dz = tree.x - px, tree.z - pz
		local r = reach + tree.trunk
		if dx * dx + dz * dz < r * r and py - self.bh < tree.y + tree.h and py + self.bh > tree.y - 1 then
			st.looked += 1
			local g = gap(px, pz, rx, rz, fx, fz, hw, hl, tree.x, tree.z, tree.trunk)
			if g < st.closest then
				st.closest = g
			end
			local p = passes[tree]
			if not p then
				local rested = self.rested[tree]
				if g < t.Watch and not (rested and self.clock - rested < t.Rearm) then
					p = { tree = tree, minGap = math.huge, speedAtMin = 0, forwardAtMin = false, touched = false, wall = false, over = false, clock = 0 }
					passes[tree] = p
				end
			end
			if p then
				seen[tree] = true
				if g <= t.TouchGap then
					p.touched = true
				end
				if not p.over then
					if g < p.minGap then
						p.minGap, p.speedAtMin, p.forwardAtMin = g, speed, forward
					elseif g > p.minGap + t.Open then
						p.over = true
					end
				end
			end
		end
	end

	for tree, p in passes do
		if wall and not p.touched then
			p.wall = true
		end
		if not seen[tree] then
			p.over = true
		end
		if p.over then
			p.clock += dt
			if p.clock >= t.Confirm then
				self:_end(p)
			end
		end
	end
end

function NearMiss:DebugState()
	local st = self.stats
	local open = 0
	for _ in self.passes do
		open += 1
	end
	local hist = {}
	for i, n in st.hist do
		local lo = if i == 1 then 0 else BUCKETS[i - 1]
		local hi = BUCKETS[i]
		hist[i] = { from = lo, to = hi or math.huge, n = n }
	end
	return {
		threshold = self.t.Threshold,
		minSpeed = self.t.MinSpeed,
		near = #self.trees,
		open = open,
		closest = if st.closest < math.huge then st.closest else nil,
		frames = st.frames,
		fetches = st.fetches,
		looked = st.looked,
		passes = st.passes,
		fired = st.fired,
		hit = st.hit,
		wall = st.wall,
		recent = st.recent,
		slow = st.slow,
		fell = st.fell,
		last = st.last,
		hist = hist,
		microsPerFrame = if st.frames > 0 then st.micros / st.frames else 0,
	}
end

return NearMiss
