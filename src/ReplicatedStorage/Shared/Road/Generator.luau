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
-- proves a legal continuation `LookAhead` pieces deep, depth-first in that preference
-- order. A combination is illegal if any candidate's footprint overlaps a piece already
-- laid or an earlier candidate. If nothing is legal at all, NOTHING IS PLACED: the road
-- stops growing rather than growing wrongly, and it says so loudly.
--
-- THE SEARCH IS A STANDING PLAN, NOT A CALL (T-052, and the spec's `SearchStepsPerFrame`).
-- Step 2 ran the whole depth-first search from scratch for every piece and threw the
-- result away: the worst single call measured 922 ms on seed 7, which is eight tenths of
-- a second with the whole server stopped, in the middle of somebody's corner. Two things
-- are wrong with that and this fixes both with the same change.
--
--   * It threw away the answer. A search that proves "N .. N+13 is legal" has done
--     thirteen fourteenths of the work of proving "N+1 .. N+14 is legal", and then did it
--     again from nothing.
--   * It could not be interrupted. A recursive search either finishes or it has nothing.
--
-- So the search is kept as EXPLICIT STATE -- `plan`, a stack of frames, one per depth,
-- each holding the socket it starts at, the shuffled order it will try, how far down that
-- order it has got, and the candidate it is standing on. `step()` advances that stack by
-- exactly one placement. Everything else is built on it:
--
--   * A piece is emitted when the stack is `LookAhead` deep and every frame in it holds a
--     candidate -- the same proof step 2 made, reached the same way.
--   * Emitting shifts the stack down by one. The thirteen pieces behind the head are kept
--     and stay proven; only the new frontier frame has to be found.
--   * WORK IS SLICED BY THE CLOCK, not by the piece: `extendTo` spends a few milliseconds
--     and returns, and the next tick picks the stack up exactly where it left off.
--   * BACKTRACKING IS RECOVERY. When the frontier runs out of room the stack pops into
--     the plan and RE-CHOOSES pieces that were decided but never emitted -- up to thirteen
--     of them. Step 2 could only ever refuse at the head, because it had thrown away
--     every alternative it had found. Only a piece already handed to `RoadService` is
--     immovable here.
--
-- AND SLICING CANNOT CHANGE THE ROAD, which is the property the whole thing turns on.
-- `step()` is a pure function of the stack, the tail and the RNG; the clock only decides
-- HOW MANY steps run in one call, never which. Two players on the same seed who drove at
-- different speeds, on different frame rates, interrupted in different places, walk the
-- same stack through the same states and get the same pieces. There is no path by which a
-- piece is chosen because time ran out -- when a piece is needed now and the plan is not
-- ready, the generator works the SAME stack harder, it does not settle for less.
--
-- WHY A SEED IS A ROAD, and the other thing that had to change for it to be. The spec
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

-- One depth of the standing search. `piece` is the candidate this frame is currently
-- standing on, or nil while the frame is still looking; only the TOP frame is ever nil,
-- which is what makes the stack a plan rather than a half-explored tree.
export type Frame = {
	n: number, -- the absolute piece number this frame would become
	from: Pieces.Socket,
	order: { string }, -- the preference order, shuffled once when the frame was pushed
	i: number, -- how many of `order` have been tried
	piece: Pieces.Placed?,
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
		plan: { Frame }, -- the standing search, bottom (nearest) first
		planCounts: { [string]: number }, -- the bias tally over `recent` plus the plan
		furthestN: number,
		furthestT: number,
		stalled: boolean, -- the lookahead found nothing and placed nothing
		dead: boolean, -- it exhausted the whole tree rather than a budget
		searchNodes: number, -- placements tried since the last piece was emitted
		worstNodes: number,
		nodes: number, -- placements tried over the whole run
		steps: number, -- stack moves over the whole run: tries, pushes and pops
		worstCallMs: number, -- the longest single call into the generator
		worstCallAt: number, -- and the piece it was reaching for
		forcedCalls: number, -- calls that ran past the clock because the road was short
		recoveries: number, -- times the plan re-chose the piece it was about to hand out
		deepestRetreat: number, -- the shallowest the plan has fallen back to since the
		-- last piece: `LookAhead - 1` means it never backtracked
		bestDepth: number, -- the deepest chain this search has stood up
		bestFirst: Pieces.Placed?, -- and the piece at the bottom of it
		relaxed: number, -- pieces placed on less than `LookAhead` of proof
		worstProof: number, -- the least proof any piece of this run was placed on
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
		plan = {},
		planCounts = {},
		furthestN = 1,
		-- -1, not 0, so that the very start of piece 1 reads as forward on new road: a
		-- car standing on the spawn has not been anywhere yet, and 0 would make its
		-- first step the only one of a run that does not count.
		furthestT = -1,
		stalled = false,
		dead = false,
		searchNodes = 0,
		worstNodes = 0,
		nodes = 0,
		steps = 0,
		worstCallMs = 0,
		worstCallAt = 0,
		forcedCalls = 0,
		recoveries = 0,
		deepestRetreat = math.huge,
		bestDepth = 0,
		bestFirst = nil,
		relaxed = 0,
		worstProof = math.huge,
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

-- Throw the standing search away and start it again from the emitted head. Only two
-- things do this: a brand new generator, and `DebugForce`, which puts a piece down that
-- the search never chose and so invalidates every frame standing on it.
local function resetPlan(self: Generator)
	table.clear(self.plan)
	self.planCounts = countsOf(self)
	self.searchNodes = 0
	self.bestDepth = 0
	self.bestFirst = nil
	self.deepestRetreat = math.huge
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

-- Does this candidate cross anything already laid, or anything below it in the plan?
local function illegal(self: Generator, candidate: Pieces.Placed, below: number): boolean
	for _, piece in self.recent do
		if Pieces.overlap(candidate, piece) then
			return true
		end
	end
	local plan = self.plan
	for d = 1, below do
		local piece = plan[d].piece
		if piece and Pieces.overlap(candidate, piece) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- The standing search
--------------------------------------------------------------------------------
-- ONE MOVE OF THE STACK, and the whole of the search's cleverness is that there is
-- nothing else. Three moves exist and they are the three a recursive depth-first search
-- makes between two lines of itself:
--
--   push  the top frame is standing on a candidate and the stack is not deep enough yet,
--         so open a new frame beyond it. THIS is where the RNG is spent, once per frame,
--         on the weighted shuffle that fixes the order that frame will try things in.
--   try   the top frame has no candidate, so place the next variant in its order and
--         test it. A node, and the only thing the budget counts.
--   pop   the top frame has run out of order. Drop it, and take the candidate out from
--         under the frame below so that it tries ITS next variant. A pop below the
--         frontier is the generator re-choosing a piece it had decided but not emitted,
--         which is the only recovery there is.
--
-- Returns what it did, so the caller can count recoveries and notice a dead end.
local function step(self: Generator): string
	local C = Config.Road
	local plan = self.plan
	local d = #plan
	self.steps += 1

	if d == 0 or plan[d].piece ~= nil then
		if d >= C.LookAhead then
			return "ready"
		end
		local from = if d == 0 then self.next else (plan[d].piece :: Pieces.Placed).finish
		local n = if d == 0 then self.last + 1 else plan[d].n + 1
		plan[d + 1] = {
			n = n,
			from = from,
			order = weightedShuffle(self.rng, biasedWeights(self.planCounts, n)),
			i = 0,
			piece = nil,
		}
		return "push"
	end

	local frame = plan[d]
	if frame.i >= #frame.order then
		table.remove(plan)
		local below = plan[d - 1]
		if not below then
			return "dead"
		end
		local piece = below.piece :: Pieces.Placed
		self.planCounts[piece.id] = (self.planCounts[piece.id] or 1) - 1
		below.piece = nil
		-- A pop at depth 2 retracts the piece the generator was about to hand out: it has
		-- gone back and re-chosen road that was decided but never built. That is the
		-- recovery step 2 could not make, so it is counted on its own.
		if d == 2 then
			self.recoveries += 1
		end
		self.deepestRetreat = math.min(self.deepestRetreat, d - 1)
		return "pop"
	end

	frame.i += 1
	self.searchNodes += 1
	self.nodes += 1
	local variant = Pieces.get(frame.order[frame.i]) :: Pieces.Variant
	local candidate = Pieces.place(variant, frame.from, frame.n)
	if not illegal(self, candidate, d - 1) then
		frame.piece = candidate
		self.planCounts[candidate.id] = (self.planCounts[candidate.id] or 0) + 1
		-- THE BEST CHAIN THIS SEARCH HAS STOOD UP, kept so that giving up is not the same
		-- as stopping. Frames below the top always hold a piece, so reaching depth `d`
		-- means `d` pieces in a row are legal, and `plan[1].piece` is the first of them.
		if d > self.bestDepth then
			self.bestDepth = d
			self.bestFirst = plan[1].piece
		end
	end
	return "try"
end

-- Work the stack until it can emit, until it has proved there is nothing to emit, or
-- until `millis` of wall clock have gone (nil means "however long it takes").
--
-- THE CLOCK IS THE ONLY THING `millis` TOUCHES. Stopping early leaves the stack exactly
-- as it is and the next call carries on from there, so the sequence of states the stack
-- walks through -- and therefore the road -- is the same whatever the slices were.
local function work(self: Generator, millis: number?): string
	local C = Config.Road
	if self.dead then
		return "dead"
	end
	local t0 = os.clock()
	while true do
		local plan = self.plan
		local d = #plan
		if d >= C.LookAhead and plan[d].piece ~= nil then
			return "ready"
		end
		if self.searchNodes >= C.SearchNodeBudget then
			return "budget"
		end
		if millis and (os.clock() - t0) * 1000 >= millis then
			return "timeout"
		end
		if step(self) == "dead" then
			self.dead = true
			return "dead"
		end
	end
end

-- Hand a piece to the road. `counted` says whether the bias tally already holds it: a
-- piece taken off the plan does (it was counted when the frame chose it, and emitting
-- only moves it from the plan into the tail), a piece placed by `placeFirst` or
-- `DebugForce` does not.
local function emit(self: Generator, piece: Pieces.Placed, counted: boolean): Pieces.Placed
	self.last = piece.n
	self.pieces[piece.n] = piece
	self.next = piece.finish
	self.placed += 1
	if not counted then
		self.planCounts[piece.id] = (self.planCounts[piece.id] or 0) + 1
	end

	table.insert(self.recent, piece)
	while #self.recent > self.keep do
		local gone = table.remove(self.recent, 1) :: Pieces.Placed
		self.planCounts[gone.id] = (self.planCounts[gone.id] or 1) - 1
	end
	return piece
end

-- The plan is ready: take its bottom frame off and emit it.
local function commit(self: Generator): Pieces.Placed
	local piece = (self.plan[1].piece :: Pieces.Placed)
	table.remove(self.plan, 1)
	self.worstNodes = math.max(self.worstNodes, self.searchNodes)
	self.worstProof = math.min(self.worstProof, Config.Road.LookAhead)
	self.searchNodes = 0 -- the budget is per piece, as it always was
	self.deepestRetreat = #self.plan
	self.bestDepth = 0
	self.bestFirst = nil
	return emit(self, piece, true)
end

-- WHAT THE ROAD DOES WHEN IT CANNOT PROVE ITSELF FOURTEEN DEEP, and the reason it carries
-- on rather than stopping. The search has either run its whole tree out or run out of
-- budget; either way it has no chain `LookAhead` long. But along the way it stood up the
-- best chain it could find, and the first piece of that chain is legal -- it crosses
-- nothing -- it simply has less road proved beyond it than the road would like.
--
-- So the generator LOWERS ITS SIGHTS instead of refusing: it lays that piece, throws the
-- search away, and starts again from there. A road that keeps going on four pieces of
-- proof is a road; a road that stops dead in front of the player is not. Every one of
-- these is counted (`relaxed`), and the least proof a run ever settled for is reported,
-- because a run full of them is a piece set that needs looking at.
--
-- IT IS NOT THE CLOCK THAT DECIDES THIS. Relaxing happens when the SEARCH gives up, after
-- a number of nodes fixed by `SearchNodeBudget`, so it falls in the same place on the
-- same seed however the work was sliced. Nothing here reads a timer.
--
-- Returns the piece, or nil when there is not even one legal piece to lay -- which is the
-- real dead end, and the one the warning is for.
local function relax(self: Generator): Pieces.Placed?
	local piece = self.bestFirst
	self.worstNodes = math.max(self.worstNodes, self.searchNodes)
	if not piece then
		return nil
	end
	self.worstProof = math.min(self.worstProof, self.bestDepth)
	self.relaxed += 1
	resetPlan(self)
	self.dead = false
	return emit(self, piece, false)
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

local function stall(self: Generator, why: string)
	if not self.stalled then
		warn(
			`[Road] no legal piece at all at n={self.last + 1}: {self.searchNodes} placements tried, `
				.. `{self.recoveries} re-choices, the best chain found was {self.bestDepth} deep ({why}). `
				.. `Nothing placed: the road has boxed itself in.`
		)
	end
	self.stalled = true
end

-- Generate one more piece, however long that takes. This is the UNSLICED path: it works
-- the standing plan until it is ready, bounded only by `SearchNodeBudget`. Nothing in the
-- game calls it -- `RoadService` goes through `extendTo`, which slices -- and it is here
-- for the tests, which want a road rather than a schedule, and for the first piece of a
-- run, which has to exist before anything can be told where it is.
--
-- Returns nil if the lookahead found nothing legal -- which is a bug to catch in testing,
-- not a state to ship, so it warns.
function Generator.grow(self: Generator): Pieces.Placed?
	if self.last == 0 then
		local first = placeFirst(self)
		if not first then
			stall(self, "no start piece")
			return nil
		end
		self.stalled = false
		return emit(self, first, false)
	end
	local status = work(self, nil)
	if status == "ready" then
		self.stalled = false
		return commit(self)
	end
	local settled = relax(self)
	if settled then
		self.stalled = false
		return settled
	end
	stall(self, status)
	return nil
end

-- Build forward until `n` pieces exist, WITHOUT STOPPING THE SERVER. Returns what was
-- added, in order; the rest is picked up on the next call, from exactly where this one
-- left off.
--
-- HOW MUCH TIME ONE CALL MAY TAKE, and why it is allowed to vary. `RoadService` calls
-- this once a tick with `windowCentre + AheadPieces`, so `n - AheadPieces` is the piece
-- the car is on and `last - (n - AheadPieces)` is how much road is in front of it. That
-- number is the only thing the budget depends on:
--
--   more than `UrgentAheadPieces` ahead   `SearchMillisPerTick` -- there is no hurry at
--                                         all: ten pieces is about forty seconds of
--                                         driving and the plan only has to find one
--   fewer                                 `SearchMillisUrgent` -- the car is eating into
--                                         the window and the road should catch up
--   fewer than `MinAheadPieces`           the clock is ignored. This is ONLY reachable
--                                         with no road under the car at all, which in a
--                                         run means the first call of `Generate`, and it
--                                         is bounded by the node budget like everything
--                                         else. It is counted, not hidden
--
-- None of those change WHAT is chosen (see the head of this file): they change only how
-- many steps of the same walk run before the call returns.
--
-- AND THE ROAD CANNOT RUN OUT UNDERNEATH THE CAR, which is the other half of the reason
-- `SearchNodeBudget` is what it is. The most work the generator can owe at any moment is
-- one piece's budget; at the urgent slice that is paid off in about a second of wall
-- clock, and `MinAheadPieces` of road is several seconds of driving. When the search
-- does run out of budget the generator does not stop, it `relax`es -- see above -- so
-- there is always a piece at the end of that second.
function Generator.extendTo(self: Generator, n: number): { Pieces.Placed }
	local C = Config.Road
	local added: { Pieces.Placed } = {}
	local t0 = os.clock()
	-- `centre` is where the car is, read back out of the window the caller asked for. A
	-- caller that asks for fewer than `AheadPieces` is treated as a car on piece 1.
	local centre = math.max(1, n - C.AheadPieces)
	local forced = false

	while self.last < n and not self.stalled do
		if self.last == 0 then
			local first = self:grow()
			if not first then
				break
			end
			table.insert(added, first)
			forced = true
			continue
		end
		local ahead = self.last - centre
		local millis: number?
		if ahead < C.MinAheadPieces then
			millis = nil
			forced = true
		else
			local allow = if ahead < C.UrgentAheadPieces then C.SearchMillisUrgent else C.SearchMillisPerTick
			millis = allow - (os.clock() - t0) * 1000
			if millis <= 0 then
				break
			end
		end
		local status = work(self, millis)
		if status == "ready" then
			table.insert(added, commit(self))
			self.stalled = false
		elseif status == "timeout" then
			break
		else
			local settled = relax(self)
			if settled then
				table.insert(added, settled)
				self.stalled = false
			else
				stall(self, status)
				break
			end
		end
	end

	if forced then
		self.forcedCalls += 1
	end
	local took = (os.clock() - t0) * 1000
	if took > self.worstCallMs then
		self.worstCallMs, self.worstCallAt = took, self.last + 1
	end
	return added
end

-- Spend `millis` on the standing plan without emitting anything. Nothing in the game
-- calls this yet -- `extendTo` is the only pump `RoadService` has -- and it is here so a
-- test can interrupt a search at an arbitrary point and prove the road comes out the
-- same. Returns the plan's depth, out of `LookAhead`.
function Generator.pump(self: Generator, millis: number): number
	if self.last > 0 and not self.stalled then
		work(self, millis)
	end
	return #self.plan
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
	local piece = Pieces.place(variant, self.next, self.last + 1)
	emit(self, piece, false)
	-- Every frame of the standing plan was standing on the road this just replaced, so
	-- the plan goes and the search starts again from here.
	resetPlan(self)
	self.dead = false
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
		dead = self.dead,
		searchNodes = self.searchNodes,
		worstSearchNodes = self.worstNodes,
		nodes = self.nodes,
		steps = self.steps,
		planDepth = #self.plan,
		deepestRetreat = if self.deepestRetreat == math.huge then -1 else self.deepestRetreat,
		recoveries = self.recoveries,
		relaxed = self.relaxed,
		worstProof = if self.worstProof == math.huge then -1 else self.worstProof,
		forcedCalls = self.forcedCalls,
		worstCallMs = self.worstCallMs,
		worstCallAt = self.worstCallAt,
		furthestN = self.furthestN,
		furthestT = self.furthestT,
		nextSocket = self.next,
	}
end

return Generator
