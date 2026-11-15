--!strict
-- SplineSequence: the spline road in the shape the run already drives -- a numbered
-- sequence of pieces (features/spline-road.md "The server", T-136).
--
-- `RoadService` keeps its window, its progress, its respawn rule and its closing barrier in
-- PIECES: build `AheadPieces` in front of the leader, forget `BehindPieces` behind, put the
-- barrier `BarrierBehind` back, never respawn behind it. Every one of those rules is right
-- for the spline road too, so rather than write them twice this hands the service what
-- `Road/Generator` hands it -- `extendTo`, `piece`, `trimBefore`, `locate`, `progress`,
-- `first`, `last`, `furthestN` -- with ONE SPLINE SECTION AS ONE PIECE. A section is one
-- decision of the generator, a bend or a straight, 60 to 600 studs: the size of a piece.
--
-- What is different, and why:
--   * A piece here is a span of arc length, `s0..s1`, and NOTHING IS BUILT FROM IT on the
--     server. Its sections go to the clients, who draw them.
--   * `locate` is the spline's own projection, not a search over pieces: one grid lookup
--     and a few Newton steps, wherever the road has wandered.
--   * `lateral` is signed by the spline (+ right) but handed back unsigned, as the piece
--     road's is; `sideOf` gives the sign to anyone who wants it.
--   * THE GENERATOR IS PRIVATE (T-212). It lays road into its own spline, on its own
--     coroutine, and `pump` runs it a few milliseconds a frame: a field's planning can take
--     seconds of work and must never freeze the server. `self.spline` is the PUBLIC copy,
--     the one everything else reads. A section reaches it only once the generator has
--     finished it, whole, by the same `Spline.append` a client uses, so nothing ever sees
--     road half-laid. `extendTo` still finishes the work at once, for tests and for the
--     rare moment the road ahead has run out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)
local SplineGen = require(script.Parent.SplineGen)
local Contact = require(script.Parent.SplineContact)

local SplineSequence = {}
SplineSequence.__index = SplineSequence

export type Piece = {
	n: number,
	s0: number,
	s1: number,
	length: number,
	kind: string,
	id: string,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	section: Spline.Section,
}

export type Pump = {
	resumes: number, -- coroutine resumes, each one bounded slice of generation
	steps: number, -- sections finished by the pump
	syncSteps: number, -- sections finished at once by `extendTo`
	lastSliceMs: number,
	worstSliceMs: number, -- the longest single resume: the frame cost a slice really took
	workMs: number, -- all pumped generation work
	publishMs: number, -- the public appends, which never suspend
	worstPublishMs: number,
	errors: number,
	lastError: string?,
}

export type Sequence = typeof(setmetatable(
	{} :: {
		gen: SplineGen.Gen, -- PRIVATE: only its own coroutine reads it while a step is open
		spline: Spline.Spline, -- the public road: complete sections only
		sections: { Spline.Section }, -- the public road's sections, in order
		seed: number,
		first: number,
		last: number,
		starts: { number }, -- s at the start of each section, by n
		pieces: { [number]: Piece },
		furthestN: number,
		furthestT: number,
		destroyed: number,
		target: number, -- sections the window has asked to be public
		thread: thread?, -- the generator's coroutine, while a step is open
		deadline: number, -- os.clock() at which the open step hands the frame back
		trimS: number?, -- a trim for the private spline, applied between steps
		pumpStats: Pump,
	},
	SplineSequence
))

function SplineSequence.new(seed: number, origin: Spline.Origin?): Sequence
	local gen = SplineGen.new(seed, origin)
	local public = Spline.new(gen.spline.origin)
	public.fall = gen.spline.fall
	local self = setmetatable({
		gen = gen,
		spline = public,
		sections = {},
		seed = seed,
		first = 1,
		last = 0,
		starts = {},
		pieces = {},
		furthestN = 1,
		furthestT = 0,
		destroyed = 0,
		target = 0,
		thread = nil,
		deadline = math.huge,
		trimS = nil,
		pumpStats = {
			resumes = 0,
			steps = 0,
			syncSteps = 0,
			lastSliceMs = 0,
			worstSliceMs = 0,
			workMs = 0,
			publishMs = 0,
			worstPublishMs = 0,
			errors = 0,
			lastError = nil,
		},
	}, SplineSequence)
	gen.tick = function()
		self:_checkpoint()
	end
	self:_publish(#gen.sections)
	self:_adopt()
	return self
end

-- The generator's checkpoint. It hands the frame back only from the generator's own
-- coroutine, and only once the slice is spent; anywhere else it does nothing.
function SplineSequence._checkpoint(self: Sequence)
	local thread = self.thread
	if thread == nil or coroutine.running() ~= thread or os.clock() < self.deadline then
		return
	end
	local at = os.clock()
	coroutine.yield()
	self.gen.pausedMs += (os.clock() - at) * 1000
end

-- Run the generator until one step finishes or the slice ends at `deadline`. True when
-- the step finished (a section, or the road boxed in); false when it is suspended. A trim
-- reaches the private spline only between steps, never under an open one.
function SplineSequence._run(self: Sequence, deadline: number): boolean
	local gen = self.gen
	if not self.thread then
		if gen.stats.stalled then
			return true
		end
		if self.trimS then
			gen.spline:trim(self.trimS)
			self.trimS = nil
		end
		self.thread = coroutine.create(function()
			return gen:step()
		end)
	end
	local thread = self.thread :: thread
	self.deadline = deadline
	local st = self.pumpStats
	local at = os.clock()
	local ok, err = coroutine.resume(thread)
	local ms = (os.clock() - at) * 1000
	self.deadline = math.huge
	st.resumes += 1
	st.lastSliceMs = ms
	st.worstSliceMs = math.max(st.worstSliceMs, ms)
	st.workMs += ms
	if not ok then
		-- the step is abandoned, as a failed step always was; the next one starts afresh
		self.thread = nil
		st.errors += 1
		st.lastError = tostring(err)
		error(debug.traceback(thread, tostring(err)), 0)
	end
	if coroutine.status(thread) == "dead" then
		self.thread = nil
		return true
	end
	return false
end

-- Make the generator's finished sections public, in order, up to section `n`. Each is a
-- whole `Spline.append`, which never suspends. With a `deadline`, stops once it is spent.
function SplineSequence._publish(self: Sequence, n: number, deadline: number?)
	local source = self.gen.sections
	local st = self.pumpStats
	while #self.sections < math.min(n, #source) do
		local sec = source[#self.sections + 1]
		local at = os.clock()
		self.spline:append(sec)
		table.insert(self.sections, sec)
		local ms = (os.clock() - at) * 1000
		st.publishMs += ms
		st.worstPublishMs = math.max(st.worstPublishMs, ms)
		if deadline and os.clock() >= deadline then
			break
		end
	end
end

-- Turn every public section this has not yet numbered into a piece.
function SplineSequence._adopt(self: Sequence): { Piece }
	local added: { Piece } = {}
	local sections = self.sections
	local s = if self.last > 0 then self.pieces[self.last] and self.pieces[self.last].s1 or self:_endOf(self.last) else 0
	for n = self.last + 1, #sections do
		local sec = sections[n]
		local s0, s1 = s, s + sec.len
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		local step = math.max(8, sec.len / 24)
		local u = s0
		while true do
			local x, z = self.spline:planAt(math.min(u, s1))
			minX, maxX = math.min(minX, x), math.max(maxX, x)
			minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
			if u >= s1 then
				break
			end
			u += step
		end
		local tag = sec.tag or "Section"
		local piece: Piece = {
			n = n,
			s0 = s0,
			s1 = s1,
			length = sec.len,
			kind = tag,
			id = tag,
			minX = minX,
			maxX = maxX,
			minZ = minZ,
			maxZ = maxZ,
			section = sec,
		}
		self.pieces[n] = piece
		self.starts[n] = s0
		self.last = n
		table.insert(added, piece)
		s = s1
	end
	return added
end

function SplineSequence._endOf(self: Sequence, n: number): number
	local s = 0
	for i = 1, n do
		s += self.sections[i].len
	end
	return s
end

-- Lay sections until there are `n` pieces, AT ONCE (a step the pump left open is finished
-- first). For tests, debug moves and a road that has run out. Returns the new pieces.
function SplineSequence.extendTo(self: Sequence, n: number): { Piece }
	self.target = math.max(self.target, n)
	local gen = self.gen
	while #gen.sections < n and not gen.stats.stalled do
		local before = #gen.sections
		self:_run(math.huge)
		self.pumpStats.syncSteps += #gen.sections - before
	end
	self:_publish(n)
	return self:_adopt()
end

-- Ask for `n` public pieces WITHOUT generating: whatever the pump has finished goes
-- public, up to `n`. Returns the new pieces.
function SplineSequence.request(self: Sequence, n: number): { Piece }
	self.target = math.max(self.target, n)
	self:_publish(n)
	return self:_adopt()
end

-- Spend at most `budgetMs` of this frame generating toward `lead` sections beyond what
-- has been asked for, then make finished sections public up to the ask. A step the slice
-- cannot finish is suspended and carries on next frame.
function SplineSequence.pump(self: Sequence, budgetMs: number, lead: number)
	local deadline = os.clock() + budgetMs / 1000
	local gen = self.gen
	while #gen.sections < self.target + lead and not gen.stats.stalled and os.clock() < deadline do
		local before = #gen.sections
		local finished = self:_run(deadline)
		self.pumpStats.steps += #gen.sections - before
		if not finished then
			break
		end
	end
	self:_publish(self.target, deadline)
end

-- Sections the generator has finished that are not public yet, and whether a step is open.
function SplineSequence.pending(self: Sequence): (number, boolean)
	return #self.gen.sections - #self.sections, self.thread ~= nil
end

function SplineSequence.piece(self: Sequence, n: number): Piece?
	if n < self.first then
		return nil
	end
	return self.pieces[n]
end

-- Forget every piece before `n`, and the curve's samples behind it. The knots and the
-- no-crossing grid are kept: they are what stops the road crossing road it laid long ago.
function SplineSequence.trimBefore(self: Sequence, n: number): { number }
	local dropped: { number } = {}
	while self.first < n and self.first <= self.last do
		if self.pieces[self.first] then
			table.insert(dropped, self.first)
			self.pieces[self.first] = nil
			self.destroyed += 1
		end
		self.first += 1
	end
	local p = self.pieces[self.first]
	if p then
		self.spline:trim(p.s0)
		-- the private copy forgets the same samples, between steps
		self.trimS = p.s0
		if not self.thread then
			self.gen.spline:trim(p.s0)
			self.trimS = nil
		end
	end
	return dropped
end

-- Which piece `s` is in, among the live ones.
function SplineSequence.pieceAtS(self: Sequence, s: number): Piece?
	local lo, hi = self.first, self.last
	if hi < lo then
		return nil
	end
	local starts = self.starts
	if s < starts[lo] then
		return nil
	end
	while hi > lo do
		local mid = (lo + hi + 1) // 2
		if starts[mid] <= s then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return self.pieces[lo]
end

-- Which piece a point is on, how far along it (0..1) and how far off the centre line,
-- unsigned. nil off the road altogether -- further from the centre line than the road, the
-- widest runoff and a margin (T-140), or not over live road at all.
function SplineSequence.locate(self: Sequence, position: Vector3): (number?, number, number)
	local reach = Config.Road.Width * 0.5 + math.max(Config.Spline.Terrain.RunoffMax,if self.spline:hasBiomeGround() then Config.Spline.Biomes.Width[1] else 0) + 30
	local s, d = self.spline:project(position.X, position.Z, reach)
	if not s or not d then
		return nil, 0, math.huge
	end
	local piece = self:pieceAtS(s)
	if not piece then
		return nil, 0, math.huge
	end
	return piece.n, (s - piece.s0) / math.max(piece.length, 1e-6), math.abs(d)
end

-- Gameplay lookup belongs to one runner. A broad field must never reacquire a
-- different leg when its current projection fails or leaves supported ground.
function SplineSequence.locateOwned(self:Sequence,position:Vector3,hint:number,maxAdvance:number?,peer:Contact.Token?,creditS:number?):(number?,number,number,number?,Contact.Hit?)
	local hit=Contact.resolve(self.spline,position.X,position.Z,hint,{limit=maxAdvance,
		low=position.Y-40,high=position.Y+8,first=self.starts[self.first],peer=peer,creditS=creditS})
	if not hit then return nil,0,math.huge,nil,nil end
	local piece=self:pieceAtS(hit.ownerS)
	-- Physical support can remain live after the original credit anchor retires.
	-- The caller still needs a real credited piece before publishing progress.
	if not piece then return nil,0,math.huge,hit.ownerS,hit end
	return piece.n,(hit.ownerS-piece.s0)/math.max(piece.length,1e-6),math.abs(hit.routeD),hit.ownerS,hit
end

-- Off-road travel cannot postpone an arc-length shortcut until re-entry. Give
-- ordinary drifting its small chord/sampling allowance, but cap any catch-up
-- by the actual plan distance driven since the last earned asphalt position.
function SplineSequence.reentryS(self:Sequence,anchor:number,travel:number,s:number):number
	return Contact.credit(anchor,travel,s)
end

-- The same flags `Road/Generator.progress` hands back.
function SplineSequence.progress(self: Sequence, position: Vector3)
	local n, t, lateral = self:locate(position)
	if not n then
		return nil
	end
	return self:progressAt(n,t,lateral)
end

-- Consume an already accepted projection; no second nearest-leg lookup.
function SplineSequence.progressAt(self:Sequence,n:number,t:number,lateral:number)
	local onRoad=lateral<=Config.Road.Width*.5
	local forward = (not self.spline:hasBiomeGround() or onRoad) and (n > self.furthestN or (n == self.furthestN and t > self.furthestT + 1e-9))
	if forward then
		self.furthestN, self.furthestT = n, t
	end
	return {
		n = n,
		t = t,
		lateral = lateral,
		onRoad = onRoad,
		forwardOnNewRoad = forward,
		backwards = n < self.furthestN - 1,
		furthestN = self.furthestN,
		furthestT = self.furthestT,
	}
end

-- A pose on a piece's centre line, `into` studs in, raised `lift` above the surface: where
-- a car is put down. Facing along the road, level (the car settles on to the surface itself).
function SplineSequence.poseOn(self: Sequence, piece: Piece, into: number, lift: number): CFrame
	local s = math.clamp(piece.s0 + into, piece.s0, piece.s1)
	local x, y, z = self.spline:surfaceXYZ(s, 0)
	return CFrame.new(x, y + lift, z) * CFrame.Angles(0, self.spline:yawAt(s), 0)
end

-- Where along the road the start of a piece is: the closing barrier's place.
function SplineSequence.startOf(self: Sequence, n: number): number?
	local p = self.pieces[n]
	return p and p.s0 or nil
end

function SplineSequence.report(self: Sequence): { [string]: any }
	local st = self.gen.stats
	local pump = self.pumpStats
	local waiting, open = self:pending()
	return {
		generated = #self.gen.sections,
		waiting = waiting,
		stepOpen = open,
		pumpResumes = pump.resumes,
		pumpSteps = pump.steps,
		syncSteps = pump.syncSteps,
		worstSliceMs = pump.worstSliceMs,
		lastSliceMs = pump.lastSliceMs,
		pumpWorkMs = pump.workMs,
		publishMs = pump.publishMs,
		worstPublishMs = pump.worstPublishMs,
		pumpErrors = pump.errors,
		seed = self.seed,
		first = self.first,
		last = self.last,
		inWindow = self.last - self.first + 1,
		length = self.spline.length,
		placed = st.sections,
		destroyed = self.destroyed,
		stalled = st.stalled,
		escapes = st.escapes,
		worstMs = st.worstMs,
		furthestN = self.furthestN,
		furthestT = self.furthestT,
		spline = true,
	}
end

return SplineSequence
