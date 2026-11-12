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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)
local SplineGen = require(script.Parent.SplineGen)

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

export type Sequence = typeof(setmetatable(
	{} :: {
		gen: SplineGen.Gen,
		spline: Spline.Spline,
		seed: number,
		first: number,
		last: number,
		starts: { number }, -- s at the start of each section, by n
		pieces: { [number]: Piece },
		furthestN: number,
		furthestT: number,
		destroyed: number,
	},
	SplineSequence
))

function SplineSequence.new(seed: number, origin: Spline.Origin?): Sequence
	local gen = SplineGen.new(seed, origin)
	local self = setmetatable({
		gen = gen,
		spline = gen.spline,
		seed = seed,
		first = 1,
		last = 0,
		starts = {},
		pieces = {},
		furthestN = 1,
		furthestT = 0,
		destroyed = 0,
	}, SplineSequence)
	self:_adopt()
	return self
end

-- Turn every section the generator has laid but this has not yet numbered into a piece.
function SplineSequence._adopt(self: Sequence): { Piece }
	local added: { Piece } = {}
	local sections = self.gen.sections
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
		s += self.gen.sections[i].len
	end
	return s
end

-- Lay sections until there are `n` pieces. Returns the new ones.
function SplineSequence.extendTo(self: Sequence, n: number): { Piece }
	while #self.gen.sections < n do
		if not self.gen:step() then
			break -- boxed in: the road stops growing, loudly (SplineGen warns)
		end
	end
	return self:_adopt()
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
-- unsigned. nil off the road altogether -- further from the centre line than the road and
-- its barriers and a margin, or not over live road at all.
function SplineSequence.locate(self: Sequence, position: Vector3): (number?, number, number)
	local reach = Config.Road.Width * 0.5 + Config.Road.BarrierThickness + 40
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

-- The same flags `Road/Generator.progress` hands back.
function SplineSequence.progress(self: Sequence, position: Vector3)
	local n, t, lateral = self:locate(position)
	if not n then
		return nil
	end
	local forward = n > self.furthestN or (n == self.furthestN and t > self.furthestT + 1e-9)
	if forward then
		self.furthestN, self.furthestT = n, t
	end
	return {
		n = n,
		t = t,
		lateral = lateral,
		onRoad = lateral <= Config.Road.Width * 0.5,
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
	return {
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
