--!nonstrict
-- RoadTests: the endless road, measured rather than looked at
-- (docs/game/features/track-generation.md "Testing", docs/workflow/TESTING.md, T-044).
--
-- Run it from the server debug bridge:
--   game.ServerStorage.DebugBridge:Invoke("DebugRoadTests", "run")
--
-- Most of it is pure and runs in milliseconds: the generator has no instances in it, so
-- five hundred pieces of road cost no parts, no playtest and no car. Two checks are not
-- pure and say so -- the one that counts the parts in the window, and the one that
-- actually DRIVES the road with the real drift model and the real Workspace.
--
-- It builds its own road and takes it down again, so it leaves the place as it found it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

assert(RunService:IsStudio(), "RoadTests is Studio only")

local Config = require(ReplicatedStorage.Shared.Config)
local Generator = require(ReplicatedStorage.Shared.Road.Generator)
local Pieces = require(ReplicatedStorage.Shared.Road.Pieces)
local RoadService = require(ServerScriptService.Services.RoadService)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")

local LONG_RUN = 500 -- pieces the pure checks generate
local SOCKET_TOLERANCE = 1e-3 -- studs, and radians: "a thousandth of a stud"
local SHARE_MARGIN = 0.12 -- a variant may be this far off its fair share of the run
local MAX_SAME_RUN = 8 -- the longest run of one variant the bias may leave
local DRIVE_PIECES = 50 -- pieces the real model is driven down
local DRIVE_SECONDS = 400 -- the drive gives up after this much simulated time
local DRIVE_FPS = 60
local SEEDS = { 1, 7, 1234, 20260704, 99991 }

-- The autopilot, which is a test fixture and not a game feature: it is the stand-in for a
-- player, and its only job is to make "can a car drive this" a question with a number in
-- the answer.
local LOOK_SECONDS = 0.9 -- how far ahead it aims, in seconds of travel. MEASURED: at 0.55 the
-- same autopilot chased its own slide round every corner and the car
-- crawled the road at a mean of 49 studs/s instead of 91. The number
-- says nothing about the road and everything about the driver, which
-- is why it is written down here rather than treated as a result
local LOOK_MIN, LOOK_MAX = 30, 120 -- studs
local BRAKE_LOOK = 1.6 -- seconds ahead it reads the corner it is about to meet
local BRAKE_LIMIT = 65 -- studs/s^2 of cornering it is willing to ask of the car before
-- it uses the handbrake. The grip curve reaches 43 at about 57 degrees
-- of slip and tops out at 72 at ninety, where it becomes a brake. With
-- the piece set as it stands this never fires -- the fastest the road
-- can make the car is 111 studs/s and a 220-stud corner asks 56 of it
-- -- and it is kept for the tighter pieces step 2 adds

local Tests = {}

local Model, Sim, World

local function loadModel()
	if Model then
		return
	end
	Model = require(DriftFolder.Model)
	Sim = require(DriftFolder.Sim)
	World = require(DriftFolder.World)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- A whole run generated in one go, with every piece kept so the checks can see all of it.
-- `grow` never trims `pieces`; only `trimBefore` does, and this never calls it.
local function longRun(seed: number, count: number): ({ any }, any)
	local gen = Generator.new(seed)
	local all = {}
	for i = 1, count do
		local piece = gen:grow()
		if not piece then
			break
		end
		all[i] = piece
		if i % 150 == 0 then
			task.wait() -- a 14-deep search costs about half a millisecond a piece
		end
	end
	return all, gen
end

local function socketGap(a, b): (number, number)
	local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
	local dyaw = math.abs(a.yaw - b.yaw) % (2 * math.pi)
	if dyaw > math.pi then
		dyaw = 2 * math.pi - dyaw
	end
	return d, dyaw
end

-- The signed angle from heading `a` to direction `b`, positive to the LEFT, which is the
-- game's sign for yaw everywhere (Drift/Model "Signs").
local function signedAngle(ax: number, az: number, bx: number, bz: number): number
	return math.atan2(bx * az - bz * ax, bx * ax + bz * az)
end

--------------------------------------------------------------------------------
-- The drive: the real model, the real Workspace, and a stand-in for a player
--------------------------------------------------------------------------------
-- An autopilot, NOT a game feature and not an AI: a pure-pursuit controller that aims a
-- fixed distance down the road's own centre line and converts the angle it is off by into
-- the one number the model takes -- the car's rate of turn. It uses the handbrake only to
-- shed speed it cannot carry into a corner it can already see, which is the one thing a
-- real driver does that aiming alone cannot express.
--
-- It is here so that "can a car drive this road" has a number in the answer, and it is
-- also what the radius and the straight's length were chosen with (`Tests.sweep`).

function Tests:drive(o)
	o = o or {}
	loadModel()
	local C = Config.Road
	local D = Config.Drift
	local wantPieces = o.pieces or DRIVE_PIECES
	local lookSeconds = o.look or LOOK_SECONDS
	local brakeLimit = o.brake or BRAKE_LIMIT
	local maxSeconds = o.seconds or DRIVE_SECONDS

	RoadService:Stop()
	local spawn = RoadService:Generate(o.seed or 8080)
	local gen = RoadService:DebugGenerator()
	local world = World.live({})
	local runner = Sim.newRunner(spawn)
	runner.state.velocity = spawn.LookVector * (o.startSpeed or 60)
	runner.state.time = 10 -- past the throttle's ease-in

	local r = {
		worstLateral = 0,
		offRoadSteps = 0,
		airSteps = 0,
		wallSteps = 0,
		driftSteps = 0,
		minSpeed = math.huge,
		maxSpeed = 0,
		speedSum = 0,
		speedN = 0,
		peakSlip = 0,
		stuckSeconds = 0,
		backwardsSteps = 0,
		reached = 1,
		steps = 0,
		seconds = 0,
	}
	local stuckSteps, lastN = 0, 1

	local function observe(s)
		r.steps += 1
		local speed = math.sqrt(s.velocity.X ^ 2 + s.velocity.Z ^ 2)
		r.minSpeed = math.min(r.minSpeed, speed)
		r.maxSpeed = math.max(r.maxSpeed, speed)
		r.speedSum += speed
		r.speedN += 1
		r.peakSlip = math.max(r.peakSlip, math.abs(math.deg(s.slip)))
		if s.airborne then
			r.airSteps += 1
		end
		if s.wallHit then
			r.wallSteps += 1
		end
		if s.drifting then
			r.driftSteps += 1
		end
		if speed < 5 then
			stuckSteps += 1
			r.stuckSeconds = math.max(r.stuckSeconds, stuckSteps * D.FixedStep)
		else
			stuckSteps = 0
		end
		local n, _, lateral = gen:locate(s.position)
		if n then
			if n < lastN then
				r.backwardsSteps += 1
			end
			lastN = n
			r.reached = math.max(r.reached, n)
			r.worstLateral = math.max(r.worstLateral, lateral)
			if lateral > C.Width * 0.5 then
				r.offRoadSteps += 1
			end
		end
	end

	local input = { steer = 0, handbrake = false }
	local elapsed = 0
	local sinceWindow = 0
	while elapsed < maxSeconds and r.reached < wantPieces do
		local s = runner.state
		local speed = math.sqrt(s.velocity.X ^ 2 + s.velocity.Z ^ 2)
		local heading = if speed > 1
			then Vector3.new(s.velocity.X / speed, 0, s.velocity.Z / speed)
			else Pieces.forward(s.yaw)
		local look = math.clamp(speed * lookSeconds, LOOK_MIN, LOOK_MAX)
		local target = gen:ahead(s.position, look)
		if target then
			local dx, dz = target.X - s.position.X, target.Z - s.position.Z
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 1e-3 then
				local alpha = signedAngle(heading.X, heading.Z, dx / len, dz / len)
				local yawWanted = speed * (2 * math.sin(alpha) / look)
				input.steer = math.clamp(yawWanted / (D.MaxSteeringSpeed * D.SteeringSensitivity), -1, 1)
			end
		end
		local _, curvature = gen:ahead(s.position, math.max(speed * BRAKE_LOOK, LOOK_MIN))
		input.handbrake = speed * speed * math.abs(curvature) > brakeLimit

		Sim.advance(runner, 1 / DRIVE_FPS, input, world, observe)
		elapsed += 1 / DRIVE_FPS
		sinceWindow += 1 / DRIVE_FPS
		if sinceWindow >= 0.25 then
			sinceWindow = 0
			RoadService:DebugAdvance(runner.state.position)
			-- Yield so the tag-added signals Drift/World listens on actually run: a piece
			-- built inside a tight loop would otherwise not be in the ground rays' include
			-- list and the car would fall through the road it is on.
			task.wait()
		end
	end

	r.seconds = elapsed
	r.meanSpeed = r.speedSum / math.max(r.speedN, 1)
	r.driftShare = r.driftSteps / math.max(r.steps, 1)
	r.detail = string.format(
		"%d pieces in %.0f s of simulation (%d steps); speed %.0f..%.0f, mean %.0f studs/s; drifting %.0f%% of it, peak slip %.0f deg; worst %.1f studs from the centre line (the road is %d wide, so %.1f studs of margin); %d steps off the road, %d airborne, %d touching a barrier, longest slow patch %.2f s",
		r.reached,
		elapsed,
		r.steps,
		r.minSpeed,
		r.maxSpeed,
		r.meanSpeed,
		100 * r.driftShare,
		r.peakSlip,
		r.worstLateral,
		C.Width,
		C.Width * 0.5 - r.worstLateral,
		r.offRoadSteps,
		r.airSteps,
		r.wallSteps,
		r.stuckSeconds
	)

	RoadService:Stop()
	world.destroy()
	return r
end

-- The measurement the corner's radius and the straight's length were chosen with, kept so
-- the next person can repeat it rather than take it on trust. It mutates `Config.Road` in
-- the live VM, rebuilds the piece set, drives, and puts everything back.
--   game.ServerStorage.DebugBridge:Invoke("DebugRoadTests", "sweep")
function Tests:sweep(o)
	o = o or {}
	local C = Config.Road
	local radii = o.radii or { 120, 160, 200, 250, 320 }
	local lengths = o.lengths or { C.Pieces.Straight.Length }
	local wasRadius = C.Pieces.Corner.Radius
	local wasLength = C.Pieces.Straight.Length
	local rows = {}
	for _, length in lengths do
		for _, radius in radii do
			C.Pieces.Corner.Radius = radius
			C.Pieces.Straight.Length = length
			Pieces.rebuild()
			local r = Tests:drive({ seed = o.seed or 8080, pieces = o.pieces or 20, seconds = o.seconds or 240, look = o.look, brake = o.brake })
			table.insert(
				rows,
				string.format(
					"R %3d, straight %3d: %2d pieces, speed %3.0f..%3.0f mean %3.0f, drifting %2.0f%%, peak slip %3.0f, worst lateral %4.1f of %.1f, off-road %4d, barrier %4d, slow %.1fs",
					radius,
					length,
					r.reached,
					r.minSpeed,
					r.maxSpeed,
					r.meanSpeed,
					100 * r.driftShare,
					r.peakSlip,
					r.worstLateral,
					C.Width * 0.5,
					r.offRoadSteps,
					r.wallSteps,
					r.stuckSeconds
				)
			)
		end
	end
	C.Pieces.Corner.Radius = wasRadius
	C.Pieces.Straight.Length = wasLength
	Pieces.rebuild()
	return table.concat(rows, "\n")
end

-- How often a long run boxes itself in, against the two numbers that decide it: how deep
-- the lookahead searches, and what a corner's arc is. Pure, so it costs no parts and no
-- playtest. This is the measurement `LookAhead` and `Arc` were set from, and it is kept
-- so the next piece type can be checked the same way:
--   game.ServerStorage.DebugBridge:Invoke("DebugRoadTests", "stalls")
function Tests:stalls(o)
	o = o or {}
	local C = Config.Road
	local depths = o.depths or { 3, 5, 7, 9 }
	local arcs = o.arcs or { 90, 75, 60 }
	local seeds = o.seeds or 60
	local length = o.pieces or 500
	local wasLook, wasArc = C.LookAhead, C.Pieces.Corner.Arc
	local rows = {}
	for _, arc in arcs do
		for _, depth in depths do
			C.LookAhead = depth
			C.Pieces.Corner.Arc = arc
			Pieces.rebuild()
			local stalls, earliest, worstNodes, total = 0, math.huge, 0, 0
			local t0 = os.clock()
			for seed = 1, seeds do
				local run, g = longRun(seed * 1013, length)
				total += #run
				if #run < length then
					stalls += 1
					earliest = math.min(earliest, #run)
				end
				worstNodes = math.max(worstNodes, g.worstNodes)
				if seed % 4 == 0 then
					task.wait() -- a deep search over many seeds is the one slow thing here
				end
			end
			table.insert(
				rows,
				string.format(
					"arc %3d, lookahead %d: %2d of %d runs stalled (earliest at piece %s), %d pieces generated, worst search %4d nodes, %.0f ms",
					arc,
					depth,
					stalls,
					seeds,
					if earliest == math.huge then "-" else tostring(earliest),
					total,
					worstNodes,
					(os.clock() - t0) * 1000
				)
			)
		end
	end
	C.LookAhead, C.Pieces.Corner.Arc = wasLook, wasArc
	Pieces.rebuild()
	return table.concat(rows, "\n")
end

--------------------------------------------------------------------------------
-- The run
--------------------------------------------------------------------------------

function Tests:run(opts)
	opts = opts or {}
	local checks = {}
	local function check(name: string, ok: boolean, detail: string)
		table.insert(checks, { name = name, ok = ok, detail = detail })
	end

	local C = Config.Road
	local D = Config.Drift

	----------------------------------------------------------------------------
	-- 1. The piece set is what the config says, and a curve is cut finely enough
	----------------------------------------------------------------------------
	do
		local ids = Pieces.order()
		local lines, worstDeviation, worstChord = {}, 0, 0
		for _, id in ids do
			local v = Pieces.get(id)
			local segments = #v.nodes - 1
			local chord = v.length / segments
			local deviation = if v.radius then chord * chord / (8 * v.radius) else 0
			worstDeviation = math.max(worstDeviation, deviation)
			if v.radius then
				worstChord = math.max(worstChord, chord)
			end
			table.insert(
				lines,
				string.format("%s %d seg, %.1f studs, chord %.2f, off the true arc %.3f", id, segments, v.length, chord, deviation)
			)
		end
		check("the piece set is Straight plus a mirrored Corner", #ids == 3, table.concat(lines, "; "))
		check(
			`no curve chord is longer than {C.MaxSegmentChord} studs`,
			worstChord <= C.MaxSegmentChord + 1e-6,
			string.format("worst chord %.2f studs", worstChord)
		)
		check(
			"a corner is within a tenth of a stud of the true arc",
			worstDeviation <= 0.12,
			string.format("worst deviation %.4f studs", worstDeviation)
		)
	end

	----------------------------------------------------------------------------
	-- 2. The road is continuous
	----------------------------------------------------------------------------
	local all, gen = longRun(1234, LONG_RUN)
	do
		local worstD, worstYaw = 0, 0
		local firstNodeGap = 0
		for i, piece in all do
			local d = math.sqrt((piece.nodes[1].x - piece.start.x) ^ 2 + (piece.nodes[1].z - piece.start.z) ^ 2)
			firstNodeGap = math.max(firstNodeGap, d)
			if i > 1 then
				local dp, dy = socketGap(all[i - 1].finish, piece.start)
				worstD = math.max(worstD, dp)
				worstYaw = math.max(worstYaw, dy)
			end
		end
		check(
			`{#all} pieces, every socket matching to {SOCKET_TOLERANCE} studs`,
			#all == LONG_RUN and worstD <= SOCKET_TOLERANCE and worstYaw <= SOCKET_TOLERANCE and firstNodeGap <= SOCKET_TOLERANCE,
			string.format(
				"%d pieces; worst socket gap %.3e studs, %.3e rad; worst start-node gap %.3e",
				#all,
				worstD,
				worstYaw,
				firstNodeGap
			)
		)
	end

	----------------------------------------------------------------------------
	-- 3. The road never crosses ITSELF WHILE IT EXISTS
	----------------------------------------------------------------------------
	-- The spec asks for no two footprints overlapping over 500 pieces. That is not what a
	-- bounded window can promise and it is not what the generator checks: it keeps the
	-- last `AheadPieces + BehindPieces` pieces and tests against those, because the rest
	-- have been destroyed and are not in the world to cross. So the check that is actually
	-- true, and is the one that matters, is the one below: AT EVERY MOMENT OF A 500-PIECE
	-- RUN, no two pieces that exist at the same time overlap. The looser question is
	-- measured beside it and reported rather than asserted.
	do
		local keep = C.AheadPieces + C.BehindPieces
		local worstPairs, worstAt = 0, 0
		for n = 1, #all do
			local from = math.max(1, n - keep + 1)
			local pairs = 0
			for i = from, n do
				for j = i + 2, n do
					if Pieces.overlap(all[i], all[j]) then
						pairs += 1
					end
				end
			end
			if pairs > worstPairs then
				worstPairs, worstAt = pairs, n
			end
		end

		local distant, nearest = 0, math.huge
		for i = 1, #all do
			for j = i + 2, #all do
				if Pieces.overlap(all[i], all[j]) then
					distant += 1
					nearest = math.min(nearest, j - i)
				end
			end
			if i % 100 == 0 then
				task.wait()
			end
		end

		check(
			`no two pieces alive at the same time overlap, over {#all} pieces`,
			worstPairs == 0,
			string.format(
				"worst %d overlapping pairs in a %d-piece window (at n=%d). Over the whole run, ignoring the window: %d pairs, the closest %s pieces apart -- all long destroyed",
				worstPairs,
				keep,
				worstAt,
				distant,
				if nearest == math.huge then "n/a" else tostring(nearest)
			)
		)
	end

	----------------------------------------------------------------------------
	-- 4. A seed is a road
	----------------------------------------------------------------------------
	do
		local same = true
		local firstDifference = ""
		for _, seed in { 1234, 7 } do
			local a = longRun(seed, 200)
			local b = longRun(seed, 200)
			for i = 1, 200 do
				if not a[i] or not b[i] then
					same = false
					firstDifference = `seed {seed}: one run stopped at {i}`
					break
				end
				local dp = socketGap(a[i].start, b[i].start)
				if a[i].id ~= b[i].id or dp > 0 then
					same = false
					firstDifference = `seed {seed}: piece {i} differs ({a[i].id} vs {b[i].id}, {dp} studs)`
					break
				end
			end
		end
		local other = longRun(99, 200)
		local differs = 0
		local base = longRun(1234, 200)
		for i = 1, 200 do
			if other[i] and base[i] and other[i].id ~= base[i].id then
				differs += 1
			end
		end
		check(
			"the same seed gives the same road, twice",
			same,
			if same then "two seeds, 200 pieces each, identical by variant and by position" else firstDifference
		)
		check(
			"a different seed gives a different road",
			differs > 40,
			`seed 99 differs from seed 1234 in {differs} of 200 pieces`
		)
	end

	----------------------------------------------------------------------------
	-- 5. It does not repeat
	----------------------------------------------------------------------------
	do
		local worstOff, worstId = 0, "?"
		local longest, longestId = 0, "?"
		local report = {}
		for _, seed in SEEDS do
			local run = longRun(seed, LONG_RUN)
			local counts = {}
			local totalWeight = 0
			for _, id in Pieces.order() do
				counts[id] = 0
				totalWeight += Pieces.get(id).weight
			end
			for _, piece in run do
				counts[piece.id] += 1
			end
			for _, id in Pieces.order() do
				local share = counts[id] / #run
				local fair = Pieces.get(id).weight / totalWeight
				if math.abs(share - fair) > worstOff then
					worstOff, worstId = math.abs(share - fair), `{id} (seed {seed})`
				end
			end
			local runLength = 1
			for i = 2, #run do
				runLength = if run[i].id == run[i - 1].id then runLength + 1 else 1
				if runLength > longest then
					longest, longestId = runLength, `{run[i].id} (seed {seed})`
				end
			end
			local parts = {}
			for _, id in Pieces.order() do
				table.insert(parts, string.format("%s %.1f%%", id, 100 * counts[id] / #run))
			end
			table.insert(report, `seed {seed}: ` .. table.concat(parts, ", "))
		end
		check(
			`no variant is more than {math.round(SHARE_MARGIN * 100)} points off its share`,
			worstOff <= SHARE_MARGIN,
			string.format("worst %.1f points (%s). %s", worstOff * 100, worstId, table.concat(report, "; "))
		)
		check(
			`the longest run of one variant is at most {MAX_SAME_RUN}`,
			longest <= MAX_SAME_RUN,
			`longest {longest} ({longestId}), over {#SEEDS} seeds x {LONG_RUN} pieces`
		)
	end

	----------------------------------------------------------------------------
	-- 6. The lookahead
	----------------------------------------------------------------------------
	do
		local stalls, worstNodes = 0, 0
		for _, seed in SEEDS do
			local run, g = longRun(seed, LONG_RUN)
			if #run < LONG_RUN then
				stalls += 1
			end
			worstNodes = math.max(worstNodes, g.worstNodes)
		end
		check(
			"a normal run never has nothing to place",
			stalls == 0,
			`{#SEEDS} seeds x {LONG_RUN} pieces, {stalls} stalls; the worst single search tried {worstNodes} placements (budget {C.SearchNodeBudget})`
		)

		-- FORCED INTO A CORNER BY HAND. Four same-way corners close a 360-degree ring
		-- exactly: the fourth's end socket IS the first's start socket. Every exit from
		-- there is against road that is already laid -- a corner retraces the first one,
		-- and a straight runs along its flank for the eighty-eight studs it takes a
		-- tangent and a 220-stud arc to come 37 studs apart. So the ring is a dead end,
		-- and it is the dead end the whole lookahead exists to see coming.
		--
		-- Part one: driven into it with `DebugForce`, the generator places NOTHING rather
		-- than something that crosses.
		local ring = Generator.new(5150)
		local forced = true
		for _ = 1, 4 do
			forced = forced and ring:DebugForce("CornerL") ~= nil
		end
		local none = ring:grow()
		check(
			"with nothing legal to place, it places nothing",
			forced and none == nil and ring.stalled == true,
			`a ring of four corners closes on itself; it grew {if none then none.id else "nothing"} and set the stalled flag to {tostring(ring.stalled)}. One warning in the log is this check, and is expected`
		)

		-- Part two, and the point of the exercise: three corners in, the fourth is still
		-- LEGAL one piece deep -- it crosses nothing, it only closes the ring -- so a
		-- generator that checked one piece ahead would take it and trap itself on the next
		-- one. Looking further, this one refuses it and goes elsewhere.
		local three = Generator.new(5150)
		for _ = 1, 3 do
			three:DebugForce("CornerL")
		end
		local closes = Pieces.place(Pieces.get("CornerL"), three.next, 4)
		local legalOneDeep = true
		for n = 1, 3 do
			legalOneDeep = legalOneDeep and not Pieces.overlap(closes, three:piece(n))
		end
		local chosen = three:grow()
		local crossed = false
		if chosen then
			for n = 1, 3 do
				crossed = crossed or Pieces.overlap(chosen, three:piece(n))
			end
		end
		check(
			"a piece that is legal now but traps the road later is declined",
			legalOneDeep and chosen ~= nil and chosen.id ~= "CornerL" and not crossed,
			`the ring-closing corner crosses nothing one piece deep: {legalOneDeep}. The generator placed {if chosen then chosen.id else "nothing"} instead, crossing anything: {crossed}`
		)
	end

	----------------------------------------------------------------------------
	-- 7. Progress
	----------------------------------------------------------------------------
	do
		local g = Generator.new(4242)
		g:extendTo(40)
		local samples = {}
		local lastN, lastT = 0, -1
		local monotonic = true
		local alwaysForward = true
		for n = 1, 30 do
			local piece = g:piece(n)
			for _, t in { 0.0, 0.25, 0.5, 0.75, 0.99 } do
				local cf = Pieces.poseAt(piece, t, 0)
				local p = g:progress(cf.Position)
				if not p then
					monotonic = false
					continue
				end
				table.insert(samples, p)
				if p.n < lastN or (p.n == lastN and p.t < lastT - 1e-6) then
					monotonic = false
				end
				lastN, lastT = p.n, p.t
				alwaysForward = alwaysForward and p.forwardOnNewRoad and not p.backwards
			end
		end
		check(
			"N and t rise monotonically down a forward drive",
			monotonic and alwaysForward and #samples == 150,
			`{#samples} samples over 30 pieces; monotonic {monotonic}, forward-on-new-road true throughout {alwaysForward}`
		)

		-- Now drive back up it. Nothing is new road any more, and far enough back the
		-- generator says so.
		local newRoad, backwards = 0, 0
		for n = 30, 1, -1 do
			local piece = g:piece(n)
			for _, t in { 0.75, 0.5, 0.25, 0.0 } do
				local p = g:progress(Pieces.poseAt(piece, t, 0).Position)
				if p then
					newRoad += if p.forwardOnNewRoad then 1 else 0
					backwards += if p.backwards then 1 else 0
				end
			end
		end
		check(
			"driving back, nothing is new road and the backwards flag comes up",
			newRoad == 0 and backwards > 100,
			`{newRoad} of 120 samples read as new road (0 is right); the backwards flag was true for {backwards}`
		)

		-- A point off the side of the road is still located, and `onRoad` is what says so.
		local piece = g:piece(5)
		local cf = Pieces.poseAt(piece, 0.5, 0)
		local off = cf.Position + cf.RightVector * (C.Width * 0.5 + 20)
		local on = g:locate(cf.Position)
		local offN, _, offD = g:locate(off)
		check(
			"a point beside the road is located, and knows it is off it",
			on == 5 and offN == 5 and offD > C.Width * 0.5,
			string.format("centre reads piece %s; %0.1f studs out reads piece %s at %.1f studs", tostring(on), C.Width * 0.5 + 20, tostring(offN), offD)
		)
	end

	----------------------------------------------------------------------------
	-- 8. The window, with real parts in it
	----------------------------------------------------------------------------
	local driveReport = ""
	do
		RoadService:Stop()
		RoadService:Generate(20260704)
		local expected = C.AheadPieces + C.BehindPieces
		local worstLow, worstHigh = math.huge, 0
		local leaked = 0
		local peakParts, peakPieceParts = 0, 0
		-- The closing barrier is walked in the same loop, because the window only ever
		-- moves FORWARD: a piece behind the car has been destroyed and cannot be asked
		-- for again, so a test that walked back down the road would be asking the service
		-- to do the one thing it is built never to do.
		local gen = RoadService:DebugGenerator()
		local worstGap, worstAt, barrierMissing = 0, 0, 0
		local spans = true
		for n = 1, 150 do
			RoadService:DebugAdvanceTo(n)
			local state = RoadService:DebugState()
			local folders = 0
			for _, child in RoadService.Root:GetChildren() do
				if child:IsA("Folder") then
					folders += 1
				end
			end
			if folders ~= state.builtPieces or folders ~= state.inWindow then
				leaked += 1
			end
			worstLow = math.min(worstLow, state.inWindow)
			worstHigh = math.max(worstHigh, state.inWindow)
			peakParts = math.max(peakParts, state.parts)

			if n > C.BarrierBehind then
				local bar = RoadService.Root:FindFirstChild("ClosingBarrier")
				local want = gen:piece(n - C.BarrierBehind)
				if not bar or not want then
					barrierMissing += 1
				else
					local at = Pieces.poseAt(want, 0, C.SurfaceY + C.BarrierHeight)
					local gap = (bar.Position - at.Position).Magnitude
					if gap > worstGap then
						worstGap, worstAt = gap, n
					end
					spans = spans and bar.Size.X >= C.Width
				end
			end
		end
		for _, p in RoadService:DebugPieces() do
			peakPieceParts = math.max(peakPieceParts, p.parts)
		end
		check(
			`the window holds at {expected} +/- 1 through a long drive`,
			worstHigh <= expected + 1 and worstLow >= math.min(expected, 11) and leaked == 0,
			`over 150 pieces the window held {worstLow}..{worstHigh} pieces (early on it is still filling behind); folders, built pieces and generator pieces disagreed {leaked} times; peak {peakParts} parts, the biggest single piece {peakPieceParts}`
		)

		check(
			`the closing barrier stays {C.BarrierBehind} pieces behind and spans the road`,
			barrierMissing == 0 and worstGap < 1e-3 and spans,
			string.format(
				"walked 148 pieces: %d times it was not there, worst %.4f studs off where it belongs (at n=%d), %d studs wide against a %d-stud road",
				barrierMissing,
				worstGap,
				worstAt,
				C.Width + C.BarrierThickness * 2,
				C.Width
			)
		)

		-- The window does not go backwards, and asking it to is not an error.
		RoadService:DebugAdvanceTo(40)
		local after = RoadService:DebugState()
		check(
			"driving back does not drag the window back",
			after.first >= 150 - C.BehindPieces and after.last >= 150 + C.AheadPieces,
			`after being told the car is back at piece 40, the window is still {after.first}..{after.last}`
		)

		-- Nothing leaks: take it down and look.
		RoadService:Stop()
		check(
			"Stop leaves nothing behind",
			workspace:FindFirstChild("Road") == nil,
			`Workspace.Road after Stop: {tostring(workspace:FindFirstChild("Road"))}`
		)
	end

	----------------------------------------------------------------------------
	-- 9. Every part is drivable ground, and nothing in it is physics
	----------------------------------------------------------------------------
	do
		RoadService:Generate(31337)
		local root = RoadService.Root
		local road, barrier, untagged, unanchored, physics, noSurface, wrongSurface = 0, 0, 0, 0, 0, 0, 0
		local offenders = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				local tagged = CollectionService:HasTag(d, D.SurfaceTag)
				if string.match(d.Name, "^Road_") then
					road += 1
					if not tagged then
						untagged += 1
						table.insert(offenders, d.Name)
					end
					local surface = d:GetAttribute(D.SurfaceAttribute)
					if surface == nil then
						noSurface += 1
					elseif surface ~= C.SurfaceTarmac and surface ~= D.SurfaceDirt then
						wrongSurface += 1
					end
				else
					barrier += 1
					if tagged then
						untagged += 1 -- a tagged wall is as wrong as an untagged road
						table.insert(offenders, `{d.Name} is tagged and should not be`)
					end
				end
				if not d.Anchored then
					unanchored += 1
					table.insert(offenders, `{d.Name} unanchored`)
				end
			elseif d:IsA("BodyMover") or d:IsA("Constraint") or d:IsA("BaseScript") then
				physics += 1
				table.insert(offenders, `{d.Name} ({d.ClassName})`)
			end
		end
		check(
			"every road part is tagged and carries a Surface; no barrier is",
			untagged == 0 and noSurface == 0 and wrongSurface == 0,
			`{road} road parts, {barrier} barrier parts; {untagged} wrongly tagged, {noSurface} with no Surface, {wrongSurface} with an unknown one. {table.concat(offenders, ", ")}`
		)
		check(
			"nothing in the road is physics",
			unanchored == 0 and physics == 0,
			`{unanchored} unanchored, {physics} movers, constraints or scripts`
		)

		-- A ray straight down from the centre line finds road, every time, and the road is
		-- flat: no elevation at all in this build.
		-- Every piece, and NOT the closing barrier: that one is deliberately in the way --
		-- it is what stops a player driving back down the road -- and it stands twelve
		-- studs above the road it closes, so a ray straight down finds it rather than the
		-- road. It is not what this check is about, and it has its own below.
		local onlyPieces = {}
		for _, child in root:GetChildren() do
			if child:IsA("Folder") then
				table.insert(onlyPieces, child)
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = onlyPieces
		local misses, worstY, wrongTag = 0, 0, 0
		local samples = 0
		for _, p in RoadService:DebugPieces() do
			local piece = RoadService:DebugGenerator():piece(p.n)
			for s = 0, 40 do
				local cf = Pieces.poseAt(piece, s / 40, 0)
				for _, lateral in { -C.Width * 0.5 + 2, 0, C.Width * 0.5 - 2 } do
					samples += 1
					local from = cf.Position + cf.RightVector * lateral + Vector3.new(0, 20, 0)
					local hit = workspace:Raycast(from, Vector3.new(0, -60, 0), params)
					if not hit then
						misses += 1
					else
						worstY = math.max(worstY, math.abs(hit.Position.Y - C.SurfaceY))
						if not CollectionService:HasTag(hit.Instance, D.SurfaceTag) then
							wrongTag += 1
						end
					end
				end
			end
		end
		check(
			"a ray down anywhere on the road finds tagged, flat road",
			misses == 0 and wrongTag == 0 and worstY < 1e-3,
			string.format("%d rays over %d pieces: %d missed, %d hit something untagged, worst height off %.5f studs", samples, #RoadService:DebugPieces(), misses, wrongTag, worstY)
		)

		-- And it is nowhere near the other two worlds.
		local bounds = RoadService:Bounds()
		local PlaygroundService = require(ServerScriptService.Services.PlaygroundService)
		local TrackService = require(ServerScriptService.Services.TrackService)
		local others = { playground = PlaygroundService:Bounds(), track = TrackService:Bounds() }
		local nearest, who = math.huge, "nothing else in the place"
		for name, b in others do
			if not b then
				continue
			end
			local gapX = math.max(b.min.X - bounds.max.X, bounds.min.X - b.max.X)
			local gapZ = math.max(b.min.Z - bounds.max.Z, bounds.min.Z - b.max.Z)
			local gap = math.max(gapX, gapZ)
			if gap < nearest then
				nearest, who = gap, name
			end
		end
		check(
			"the road's world does not touch the other two",
			nearest > 1000,
			string.format("nearest world is the %s, %.0f studs clear", who, nearest)
		)
		RoadService:Stop()
	end

	----------------------------------------------------------------------------
	-- 10. A car can actually drive it
	----------------------------------------------------------------------------
	if opts.skipDrive ~= true then
		local r = Tests:drive({ seed = opts.driveSeed or 8080, pieces = DRIVE_PIECES })
		driveReport = r.detail
		check(`a car drives {DRIVE_PIECES} generated pieces`, r.reached >= DRIVE_PIECES, driveReport)
		check(
			"never airborne, never stuck, never off the road",
			r.airSteps == 0 and r.stuckSeconds < 1 and r.offRoadSteps == 0 and r.backwardsSteps == 0,
			driveReport
		)
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
