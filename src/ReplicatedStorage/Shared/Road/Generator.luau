--!strict
-- Generator: the endless road as a sequence, and nothing that touches the Workspace.
--
-- It is pure on purpose. Everything that makes the road good -- the bias against what it
-- has just used, the depth-first lookahead that stops it boxing itself in, the rolling
-- window, the progress -- is here, where a test can drive it five hundred pieces deep in
-- a few milliseconds with no parts, no playtest and no car. `RoadService` owns the parts;
-- this owns the road.
--
-- CHOOSING THE NEXT PIECE is not uniform random. For each variant, count how many of it
-- are in the recent window; its weight is
--
--     (1 + mostUsedCount - thisCount) x variant.weight
--
-- so a variant the window is full of drops to the floor and one it has not used in a
-- while rises. Then a weighted shuffle picks the ORDER TO TRY, not the answer -- because
-- the answer also has to survive the lookahead.
--
-- LOOKING AHEAD, so the road cannot trap itself. A generator that only checks the next
-- piece will eventually place one that leaves nowhere to go. Before committing, this
-- searches `LookAhead` pieces deep, depth-first in that preference order, and accepts a
-- first piece only if a legal continuation exists that far. A combination is illegal if
-- any candidate's footprint overlaps a piece already laid or an earlier candidate. If
-- nothing is legal at all, NOTHING IS PLACED: the road stops growing rather than growing
-- wrongly, and it says so loudly.
--
-- WHY A SEED IS A ROAD, and the one thing that had to change for it to be. The spec
-- counts the pieces "currently in the window" and tests against "any piece already in the
-- world", and both of those depend on where the CAR is -- so two players with the same
-- seed who drove at different speeds would get different roads, and a run would not be
-- reproducible. So the generator keeps its own fixed-length tail of the sequence it has
-- generated (`Keep`, which is `AheadPieces + BehindPieces`), and counts and tests against
-- THAT. In normal play the tail and the live window are the same pieces; the difference
-- is only that the tail does not care how fast anyone drove.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Pieces = require(script.Parent.Pieces)

local Generator = {}
Generator.__index = Generator

export type Progress = {
	n: number, -- which piece the car is on
	t: number, -- 0..1 along that piece's centre line
	lateral: number, -- studs from the centre line
	onRoad: boolean, -- within half the road's width of it
	forwardOnNewRoad: boolean, -- further than this run has ever been
	backwards: boolean, -- more than one piece behind the furthest reached
	furthestN: number,
	furthestT: number,
}

export type Generator = typeof(setmetatable(
	{} :: {
		seed: number,
		rng: Random,
		pieces: { [number]: Pieces.Placed }, -- n -> piece, the live window
		recent: { Pieces.Placed }, -- the fixed tail the choice and the overlap test see
		keep: number,
		first: number, -- lowest n still held
		last: number, -- highest n generated
		next: Pieces.Socket, -- where the next piece starts
		furthestN: number,
		furthestT: number,
		stalled: boolean, -- the lookahead found nothing and placed nothing
		searchNodes: number, -- placements tried on the last choice
		worstNodes: number,
		placed: number,
		destroyed: number,
	},
	Generator
))

function Generator.new(seed: number?): Generator
	local C = Config.Road
	local self = setmetatable({
		seed = seed or 1,
		rng = Random.new(seed or 1),
		pieces = {},
		recent = {},
		keep = C.AheadPieces + C.BehindPieces,
		first = 1,
		last = 0,
		next = {
			x = C.Offset.X,
			z = C.Offset.Z,
			yaw = math.rad(C.StartHeading),
		},
		furthestN = 1,
		-- -1, not 0, so that the very start of piece 1 reads as forward on new road: a
		-- car standing on the spawn has not been anywhere yet, and 0 would make its
		-- first step the only one of a run that does not count.
		furthestT = -1,
		stalled = false,
		searchNodes = 0,
		worstNodes = 0,
		placed = 0,
		destroyed = 0,
	}, Generator)
	return self :: any
end

--------------------------------------------------------------------------------
-- The choice
--------------------------------------------------------------------------------

local function countsOf(self: Generator): { [string]: number }
	local counts: { [string]: number } = {}
	for _, id in Pieces.order() do
		counts[id] = 0
	end
	for _, piece in self.recent do
		counts[piece.id] = (counts[piece.id] or 0) + 1
	end
	return counts
end

-- `(1 + mostUsedCount - thisCount) x weight`, for every variant that may appear this far
-- into the run. Never below a floor, so a variant can always be tried.
local function biasedWeights(counts: { [string]: number }, n: number): { { id: string, w: number } }
	local most = 0
	for _, id in Pieces.order() do
		most = math.max(most, counts[id] or 0)
	end
	local out: { { id: string, w: number } } = {}
	for _, id in Pieces.order() do
		local variant = Pieces.get(id)
		if not variant or n <= variant.minPieces then
			continue
		end
		local w = (1 + most - (counts[id] or 0)) * variant.weight
		table.insert(out, { id = id, w = math.max(w, 1e-6) })
	end
	return out
end

-- A weighted shuffle: draw one by weight, remove it, draw again. The result is the ORDER
-- the lookahead tries them in, which is why the bias costs nothing when a choice is
-- refused -- the next preference is already queued behind it.
local function weightedShuffle(rng: Random, entries: { { id: string, w: number } }): { string }
	local pool = table.clone(entries)
	local out: { string } = {}
	while #pool > 0 do
		local total = 0
		for _, e in pool do
			total += e.w
		end
		local roll = rng:NextNumber() * total
		local pick = #pool
		for i, e in pool do
			roll -= e.w
			if roll <= 0 then
				pick = i
				break
			end
		end
		table.insert(out, pool[pick].id)
		table.remove(pool, pick)
	end
	return out
end

-- Does this candidate cross anything already laid, or anything earlier in this search?
local function illegal(self: Generator, candidate: Pieces.Placed, trial: { Pieces.Placed }): boolean
	for _, piece in self.recent do
		if Pieces.overlap(candidate, piece) then
			return true
		end
	end
	for _, piece in trial do
		if Pieces.overlap(candidate, piece) then
			return true
		end
	end
	return false
end

-- The depth-first search. Returns the first piece of a legal run `LookAhead` deep, or nil.
local function choose(self: Generator, socket: Pieces.Socket, n: number): Pieces.Placed?
	local C = Config.Road
	local counts = countsOf(self)
	local trial: { Pieces.Placed } = {}
	local nodes = 0

	local function rec(depth: number, from: Pieces.Socket): boolean
		if depth > C.LookAhead then
			return true
		end
		local at = n + depth - 1
		for _, id in weightedShuffle(self.rng, biasedWeights(counts, at)) do
			if nodes >= C.SearchNodeBudget then
				return false
			end
			nodes += 1
			local variant = Pieces.get(id) :: Pieces.Variant
			local candidate = Pieces.place(variant, from, at)
			if not illegal(self, candidate, trial) then
				trial[depth] = candidate
				counts[id] = (counts[id] or 0) + 1
				if rec(depth + 1, candidate.finish) then
					return true
				end
				counts[id] -= 1
				trial[depth] = nil
			end
		end
		return false
	end

	local ok = rec(1, socket)
	self.searchNodes = nodes
	self.worstNodes = math.max(self.worstNodes, nodes)
	if ok then
		return trial[1]
	end
	return nil
end

--------------------------------------------------------------------------------
-- Growing and trimming
--------------------------------------------------------------------------------

-- The first piece of every run is fixed, so a car is always put down on something
-- straight pointing the way the road goes.
local function placeFirst(self: Generator): Pieces.Placed?
	local C = Config.Road
	local variant = Pieces.get(C.StartPiece) or Pieces.get(Pieces.order()[1])
	if not variant then
		return nil
	end
	return Pieces.place(variant, self.next, 1)
end

-- Generate one more piece. Returns it, or nil if the lookahead found nothing legal --
-- which is a bug to catch in testing, not a state to ship, so it warns.
function Generator.grow(self: Generator): Pieces.Placed?
	local n = self.last + 1
	local piece: Pieces.Placed? = if n == 1 then placeFirst(self) else choose(self, self.next, n)
	if not piece then
		if not self.stalled then
			warn(
				`[Road] the lookahead found no legal piece at n={n}, {Config.Road.LookAhead} deep, `
					.. `after {self.searchNodes} tries. Nothing placed: the road has boxed itself in.`
			)
		end
		self.stalled = true
		return nil
	end
	self.stalled = false
	self.last = n
	self.pieces[n] = piece
	self.next = piece.finish
	self.placed += 1

	table.insert(self.recent, piece)
	while #self.recent > self.keep do
		table.remove(self.recent, 1)
	end
	return piece
end

-- Build forward until `n` pieces exist. Returns what was added, in order.
function Generator.extendTo(self: Generator, n: number): { Pieces.Placed }
	local added: { Pieces.Placed } = {}
	while self.last < n do
		local piece = self:grow()
		if not piece then
			break
		end
		table.insert(added, piece)
	end
	return added
end

-- Forget every piece before `n`. Returns what was dropped, so the service can destroy
-- exactly those parts. The generator's own tail (`recent`) is untouched: it is what makes
-- a seed a road, and it must not depend on how fast anyone drove.
function Generator.trimBefore(self: Generator, n: number): { number }
	local dropped: { number } = {}
	while self.first < n and self.first <= self.last do
		if self.pieces[self.first] then
			table.insert(dropped, self.first)
			self.pieces[self.first] = nil
			self.destroyed += 1
		end
		self.first += 1
	end
	return dropped
end

function Generator.count(self: Generator): number
	local n = 0
	for _ in self.pieces do
		n += 1
	end
	return n
end

--------------------------------------------------------------------------------
-- Progress
--------------------------------------------------------------------------------

-- Which piece a point is on, and how far along it. The road is a chain, so the answer is
-- whichever live piece the point is nearest the centre line of; a tie goes to the later
-- piece, which is the one a car crossing a socket is moving on to.
function Generator.locate(self: Generator, position: Vector3): (number?, number, number)
	local bestN, bestT, bestD = nil, 0, math.huge
	for n = self.first, self.last do
		local piece = self.pieces[n]
		if not piece then
			continue
		end
		if
			position.X < piece.minX - 64
			or position.X > piece.maxX + 64
			or position.Z < piece.minZ - 64
			or position.Z > piece.maxZ + 64
		then
			continue
		end
		local t, d = Pieces.locate(piece, position.X, position.Z)
		if d < bestD - 1e-6 or (d < bestD + 1e-6 and bestN and n > bestN) then
			bestN, bestT, bestD = n, t, d
		end
	end
	return bestN, bestT, bestD
end

-- Where the car is in the run, and the two flags the road owns because only the road can
-- answer them: is this forward on road it has not used, and is it going back down it.
function Generator.progress(self: Generator, position: Vector3): Progress?
	local C = Config.Road
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
		onRoad = lateral <= C.Width * 0.5,
		forwardOnNewRoad = forward,
		backwards = n < self.furthestN - 1,
		furthestN = self.furthestN,
		furthestT = self.furthestT,
	}
end

function Generator.piece(self: Generator, n: number): Pieces.Placed?
	return self.pieces[n]
end

-- A point `distance` studs further down the centre line than `position` is, walking from
-- piece to piece, plus the curvature of the road where that point is (1/radius, signed,
-- zero on a straight). This is what an autopilot aims at, and what a camera or a
-- lookahead HUD would read: nothing else in the game knows the shape of the road.
function Generator.ahead(self: Generator, position: Vector3, distance: number): (Vector3?, number)
	local n, t = self:locate(position)
	if not n then
		return nil, 0
	end
	local piece = self.pieces[n] :: Pieces.Placed
	local left = distance
	while true do
		local remaining = (1 - t) * piece.length
		if left <= remaining or not self.pieces[piece.n + 1] then
			local want = math.clamp(t + left / math.max(piece.length, 1e-6), 0, 1)
			local cf = Pieces.poseAt(piece, want, position.Y)
			local curvature = 0
			if piece.variant.radius then
				curvature = piece.dir / piece.variant.radius
			end
			return cf.Position, curvature
		end
		left -= remaining
		piece = self.pieces[piece.n + 1] :: Pieces.Placed
		t = 0
	end
end

--------------------------------------------------------------------------------
-- Driving the generator by hand, for the tests
--------------------------------------------------------------------------------

-- Place a named variant whatever the search would have preferred, so a test can walk the
-- road into a corner deliberately. Nothing in the game calls this.
function Generator.DebugForce(self: Generator, id: string): Pieces.Placed?
	local variant = Pieces.get(id)
	if not variant then
		return nil
	end
	local n = self.last + 1
	local piece = Pieces.place(variant, self.next, n)
	self.last = n
	self.pieces[n] = piece
	self.next = piece.finish
	self.placed += 1
	table.insert(self.recent, piece)
	while #self.recent > self.keep do
		table.remove(self.recent, 1)
	end
	return piece
end

function Generator.report(self: Generator): { [string]: any }
	local counts: { [string]: number } = {}
	local window: { { n: number, id: string } } = {}
	for n = self.first, self.last do
		local piece = self.pieces[n]
		if piece then
			counts[piece.id] = (counts[piece.id] or 0) + 1
			table.insert(window, { n = n, id = piece.id })
		end
	end
	return {
		seed = self.seed,
		first = self.first,
		last = self.last,
		inWindow = #window,
		window = window,
		counts = counts,
		placed = self.placed,
		destroyed = self.destroyed,
		stalled = self.stalled,
		searchNodes = self.searchNodes,
		worstSearchNodes = self.worstNodes,
		furthestN = self.furthestN,
		furthestT = self.furthestT,
		nextSocket = self.next,
	}
end

return Generator
