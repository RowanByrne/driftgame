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

local Builder = require(ReplicatedStorage.Shared.Road.Builder)
local Config = require(ReplicatedStorage.Shared.Config)
local Generator = require(ReplicatedStorage.Shared.Road.Generator)
local Pieces = require(ReplicatedStorage.Shared.Road.Pieces)
local RoadService = require(ServerScriptService.Services.RoadService)

local DriftFolder = StarterPlayer.StarterPlayerScripts:WaitForChild("Drift")

local LONG_RUN = 500 -- pieces the pure checks generate
local SOCKET_TOLERANCE = 1e-3 -- studs, and radians: "a thousandth of a stud"
local SHARE_MARGIN = 0.12 -- a variant may be this far off its fair share of the run
local MAX_SAME_RUN = 8 -- the longest run of one variant the bias may leave
local PROFILE_RUN = 200 -- pieces the profiled checks generate. Shorter than `LONG_RUN`
-- because a profiled piece is cut into many more segments than a
-- flat one, so every overlap test it is in costs more
-- WHAT `Drift/World` CALLS A WALL, copied here because it is a constant in that module
-- rather than a number in a config (`GROUND_NORMAL_Y`). A surface whose normal's Y is
-- below it is not ground: the ground rays step past it and the car stops dead against it.
-- If that constant ever moves, this has to move with it.
local WALL_NORMAL_Y = 0.7
local WALL_DEGREES = math.deg(math.acos(WALL_NORMAL_Y)) -- 45.57
local DRIVE_PIECES = 50 -- pieces the real model is driven down
-- Seconds the autopilot may spend stuck across that drive. NOT zero, and the long reason
-- is beside the check that uses it: the banked corner costs 40.2 s of it and the user
-- chose that knowingly (T-068).
local STUCK_BUDGET = 60
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
local STEER_FLOOR = 15 -- studs/s. The speed the autopilot steers as though it had, when it
-- has less: see where it is used. The flat road's own drive never
-- goes below 14, so this is reaching into the moments a touge road
-- stops the car and nowhere else
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
		if i % 50 == 0 then
			task.wait() -- a 14-deep search over the five-piece set costs milliseconds a
			-- piece, so this yields often enough that Studio keeps answering
		end
	end
	return all, gen
end

-- THE SERVICE'S OWN TICK LOOP, WITH NO SERVICE AND NO CAR. `RoadService` reads where the
-- cars are every `TickSeconds` and asks the generator for `windowCentre + AheadPieces`;
-- this does exactly that, against a car moving at a fixed speed, and times every single
-- call. It is the only way to measure the thing the player would feel -- the longest the
-- server is ever stopped inside the road -- because `grow` is the FORCED path and says
-- nothing about it.
--
-- `speed` is deliberately cruel: 145 studs/s held for the whole run, where the drive
-- measures the car at a mean of about 90 and a peak of 146 only on a sweeper.
local function drivenRun(seed: number, pieces: number, speed: number)
	local C = Config.Road
	local gen = Generator.new(seed)
	local carN, along, calls, total = 1, 0, 0, 0
	local worst, worstAt = 0, 0
	local leastAhead, dryTicks = math.huge, 0
	while carN < pieces do
		local t0 = os.clock()
		gen:extendTo(carN + C.AheadPieces)
		local dt = (os.clock() - t0) * 1000
		calls += 1
		total += dt
		if dt > worst then
			worst, worstAt = dt, gen.last
		end
		if gen.stalled then
			break
		end
		leastAhead = math.min(leastAhead, gen.last - carN)
		if gen.last <= carN then
			dryTicks += 1
		end
		along += speed * C.TickSeconds
		local piece = gen:piece(carN)
		while piece and along >= piece.length do
			along -= piece.length
			carN += 1
			piece = gen:piece(carN)
			if not piece then
				break
			end
		end
		gen:trimBefore(carN - C.BehindPieces)
		if calls % 500 == 0 then
			task.wait()
		end
	end
	return {
		gen = gen,
		reached = carN,
		calls = calls,
		mean = total / math.max(calls, 1),
		worst = worst,
		worstAt = worstAt,
		leastAhead = if leastAhead == math.huge then 0 else leastAhead,
		dryTicks = dryTicks,
	}
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

-- The smallest angle between two headings, in radians.
local function angleGap(a: number, b: number): number
	local d = math.abs(a - b) % (2 * math.pi)
	return if d > math.pi then 2 * math.pi - d else d
end

--------------------------------------------------------------------------------
-- The flat road, pinned
--------------------------------------------------------------------------------
-- T-066 gave a road piece a height and a bank. The nine pieces the road ships are flat
-- and have to STAY the road they were -- the same pieces in the same order, the same
-- parts in the same places -- and "we did not mean to change it" is not a test.
--
-- So three fingerprints, taken off the code AS IT WAS, on main at 3ef953e, before a
-- socket had a `y`: the sequence a seed lays, the nodes and footprint quads it lays it
-- out of, and the actual Parts a builder makes of the first twenty of them. They are
-- pinned here as numbers because the old code is not around to ask any more.
--
-- IF THIS CHECK FAILS AND THE ROAD WAS MEANT TO CHANGE -- a different `Width`, another
-- piece, a new radius -- then re-measure and re-pin these four numbers in the same
-- commit, and say in the message what moved. If it fails and nothing was meant to change,
-- something in the third dimension has leaked into the flat path.
local PINNED = {
	pieces = 500, -- seed 1234, through `grow`
	sequence = 4229837996, -- their ids, sockets, lengths and node counts
	geometry = 1094750648, -- every node and every footprint quad of the first 20
	parts = 1448, -- Parts in the first 20 pieces, built
	built = 147459104, -- and their names, sizes and CFrames
}

-- The four pieces that go somewhere vertically (T-068). They are named here because two
-- things have to be able to reach for them as a group: the flat fingerprint, which gates
-- them out, and the drives, which single them out.
local TOUGE = { "Link", "Banked30", "HairpinStack", "Corkscrew" }

-- GATE THE FOUR OUT AND THE FLAT ROAD IS THE FLAT ROAD, BIT FOR BIT. The fingerprints
-- above were taken when nine variants existed, and adding seven more would change the
-- sequence a seed lays -- not because the flat pieces moved, but because there are more
-- things to choose between. So the check that the flat pieces did not move has to ask the
-- question the pin can answer: with the touge pieces out of reach, is the road the same?
--
-- IT IS THE SAME RANDOM NUMBERS AND NOT ONLY THE SAME PIECES, which is the only reason
-- this works. `Generator.biasedWeights` walks `Pieces.order()`, skips anything whose
-- `minPieces` puts it out of reach, and hands the survivors to a weighted shuffle. Gated
-- out, the seven contribute nothing to the list and nothing to the `most` tally, so the
-- shuffle draws the same list in the same order and spends the RNG identically.
--
-- AND THE SEARCH BUDGET IS HELD AT WHAT IT WAS WHEN THE PIN WAS TAKEN, for the same
-- reason and not for a different one. `SearchNodeBudget` decides when the generator stops
-- proving and lays the best chain it found (`Generator.relax`), so it is part of what
-- chooses the road, and the sixteen-variant set needed it raised from 2 000 to 2 500
-- (`Config/Road`). Measured: with it left at 2 500 the first twenty pieces and every Part
-- in them are still IDENTICAL -- `geometry`, `parts` and `built` all match -- and only the
-- 500-piece `sequence` moves, which is the generator choosing differently a long way down
-- the road, not a flat piece having changed shape. Holding it keeps all four pinned
-- numbers meaning what they meant.
local PINNED_BUDGET = 2000
local function withFlatSetOnly<T>(fn: () -> T): T
	local was = {}
	for _, name in TOUGE do
		was[name] = Config.Road.Pieces[name].minPieces
		Config.Road.Pieces[name].minPieces = math.huge
	end
	local wasBudget = Config.Road.SearchNodeBudget
	Config.Road.SearchNodeBudget = PINNED_BUDGET
	Pieces.rebuild()
	local ok, result = pcall(fn)
	for _, name in TOUGE do
		Config.Road.Pieces[name].minPieces = was[name]
	end
	Config.Road.SearchNodeBudget = wasBudget
	Pieces.rebuild()
	if not ok then
		error(result, 0)
	end
	return result
end

local function hasher()
	local h = 2166136261
	local self = {}
	function self.s(str: string)
		for i = 1, #str do
			h = bit32.bxor(h, string.byte(str, i))
			h = (h * 16777619) % 4294967296
		end
	end
	function self.n(x: number)
		self.s(string.format("%.17g", x))
	end
	function self.get(): number
		return h
	end
	return self
end

local function flatFingerprint()
	local gen = Generator.new(1234)
	local all = {}
	local H = hasher()
	for i = 1, PINNED.pieces do
		local p = gen:grow()
		if not p then
			break
		end
		all[i] = p
		H.s(p.id)
		H.n(p.start.x)
		H.n(p.start.z)
		H.n(p.start.yaw)
		H.n(p.finish.x)
		H.n(p.finish.z)
		H.n(p.finish.yaw)
		H.n(p.length)
		H.s(tostring(#p.nodes))
		if i % 100 == 0 then
			task.wait()
		end
	end

	local G = hasher()
	for i = 1, 20 do
		for _, n in all[i].nodes do
			G.n(n.x)
			G.n(n.z)
			G.n(n.yaw)
		end
		for _, q in all[i].quads do
			G.n(q.cx)
			G.n(q.cz)
			G.n(q.ux)
			G.n(q.uz)
			G.n(q.hu)
			G.n(q.hv)
		end
	end

	-- Built into a folder that is never in the DataModel, so this costs the place nothing.
	local B = hasher()
	local holder = Instance.new("Folder")
	local parts = 0
	Builder.DebugResetMarks() -- the dash pattern carries across pieces, so it has to start
	-- where it started when these numbers were taken
	for i = 1, 20 do
		local built = Builder.build(all[i], holder)
		parts += built.parts
		local names, byName = {}, {}
		for _, d in built.folder:GetDescendants() do
			table.insert(names, d.Name)
			byName[d.Name] = d
		end
		table.sort(names)
		for _, nm in names do
			local d = byName[nm] :: BasePart
			B.s(nm)
			B.n(d.Size.X)
			B.n(d.Size.Y)
			B.n(d.Size.Z)
			for _, v in { d.CFrame:GetComponents() } do
				B.n(v)
			end
		end
	end
	holder:Destroy()
	Builder.DebugResetMarks()

	return { pieces = #all, sequence = H.get(), geometry = G.get(), parts = parts, built = B.get() }
end


--------------------------------------------------------------------------------
-- The seams between slabs: the faint bands across the road, measured (T-066)
--------------------------------------------------------------------------------
-- The user saw thin lines running across the road wherever it has grade or bank. They
-- are real. This measures them, and the arithmetic below says exactly how big they have
-- to be -- which is the point of measuring, because THEY CANNOT BE MADE SMALLER WITHOUT
-- CUTTING EVERY PROFILED PIECE INTO MORE SEGMENTS.
--
-- THE SHAPE OF THE DEFECT, seed 8080 x 20 pieces, 703 seams:
--   along the centre line   worst 0.0044 studs -- nothing
--   at either kerb          worst 0.2967, p90 0.1976, median 0.0804
--   on a wall's own top     worst 0.0183
-- Zero in the middle and growing with the distance out from it, so a seam is a shallow
-- WEDGE rather than a step: the two slabs' top faces cross along the centre line and each
-- one is proud of the other on one half of the road. That is why the bands in the user's
-- screenshot fade towards the middle, and why only one half of each is lit.
--
-- WHERE IT COMES FROM, AND WHY THE OBVIOUS FIX IS NOT ONE. A slab's top plane passes
-- EXACTLY through both of its end nodes (`spanFrame` puts the top face centre on the
-- chord), so down the centre line the road is already continuous and there is no sagitta
-- to take out -- a secant box and a tangent box are the same box. What a flat face cannot
-- do is match the road's CROSS direction at both of its ends at once: the surface of a
-- graded curve is not developable, and no flat quadrilateral lies in it. Each box is
-- therefore tilted across by the cross-slope at its own middle,
--
--   crossSlope = sin(bank) + tan(grade) x sin(yaw - the seam's yaw) x cos(bank)
--
-- and two neighbours differ there by about one `MaxBankStep`, plus one
-- tan(grade) x yaw step. HALF THE ROAD'S WIDTH TIMES THAT DIFFERENCE IS THE RISER:
-- predicted from the nodes alone it is 0.2975 against the 0.2967 measured, and 1.2% out
-- summed over all 703 seams. That is what the check in `run` holds the builder to.
--
-- AND THE TOTAL IS CONSERVED, which is why there is no free fix. Summed along a piece the
-- differences telescope into the piece's whole turn times its grade, and that total does
-- not depend on how the boxes are oriented -- only on how many of them there are. Driving
-- every seam to zero with one roll per box is possible and was tried (T-066 reopened): it
-- needs 5 to 19 degrees of bank the road never asked for, and leaves a piece 2 to 10
-- degrees out at its join, which is a four-stud step in place of a quarter-stud one. The
-- builder as it stands spreads the total evenly over the seams, which for a fixed total
-- is the smallest the worst one can be. It is already the best a flat box can do.

local SEAM_SEED, SEAM_PIECES = 8080, 20
local SEAM_CENTRE_TOLERANCE = 0.05 -- studs. Not a tight number and not meant to be: the
-- claim it is here to make is that the centre line's riser is in a different class from
-- the kerb's, which is 0.30. Across seeds the centre reads 0.0028 to 0.0214
local SEAM_BARRIER_TOLERANCE = 0.05 -- studs. A wall is 2 studs wide, not 50, so the same
-- geometry costs it a twenty-fifth as much

-- The riser one slab's top edge stands proud of its neighbour's top face by, `r` studs out
-- from the centre line. Counted ONLY where that edge is really over the neighbour's face:
-- where a path kinks the two boxes stop overlapping, and a plane extrapolated past its own
-- part is not a surface anybody can see -- measured without that guard a wall reads 0.93
-- studs out when it is 0.02. `LookVector` is the segment's FORWARD here (both `span` and
-- `spanFrame` build the frame that way), so a slab's top face ends at +LookVector and the
-- next one begins at -LookVector.
local function seamRiser(A: BasePart, B: BasePart, r: number): number
	local cfa, cfb = A.CFrame, B.CFrame
	local Ta = cfa.Position + cfa.UpVector * (A.Size.Y * 0.5)
	local Tb = cfb.Position + cfb.UpVector * (B.Size.Y * 0.5)
	local worst = 0
	for _, q in { { Ta, cfa, A, Tb, cfb, B, 1 }, { Tb, cfb, B, Ta, cfa, A, -1 } } do
		local T1, cf1, P1, T2, cf2, P2, s = q[1], q[2], q[3], q[4], q[5], q[6], q[7]
		local edge = T1 + cf1.LookVector * (s * P1.Size.Z * 0.5) + cf1.RightVector * r
		local d = edge - T2
		if
			math.abs(d:Dot(cf2.RightVector)) <= P2.Size.X * 0.5 + 1e-3
			and math.abs(d:Dot(cf2.LookVector)) <= P2.Size.Z * 0.5 + 1e-3
		then
			local n = cf2.UpVector
			local face = T2.Y + ((T2.X - edge.X) * n.X + (T2.Z - edge.Z) * n.Z) / n.Y
			worst = math.max(worst, edge.Y - face)
		end
	end
	return worst
end

local function wrapAngle(d: number): number
	while d > math.pi do
		d -= 2 * math.pi
	end
	while d < -math.pi do
		d += 2 * math.pi
	end
	return d
end

-- How far the top face of the box spanning `a`..`b` rises per stud out from the centre
-- line, measured in the road's own cross direction at a seam whose heading is `yawK`.
-- Pure maths off the nodes: it never looks at a Part, which is what makes it a prediction.
local function crossSlope(a, b, yawK: number): number
	local yaw = a.yaw + wrapAngle(b.yaw - a.yaw) * 0.5
	local pitch, bank = (a.pitch + b.pitch) * 0.5, (a.bank + b.bank) * 0.5
	return math.sin(bank) + math.tan(pitch) * math.sin(wrapAngle(yaw - yawK)) * math.cos(bank)
end

-- Every seam of a generated road, built into a folder that is never in the DataModel, so
-- this costs the place nothing.
local function seamSweep(seed: number, pieces: number)
	local run = longRun(seed, pieces)
	local holder = Instance.new("Folder")
	Builder.DebugResetMarks()
	local half = Config.Road.Width * 0.5
	local hw = Config.Road.BarrierThickness * 0.5
	local kerbs = {}
	local centre, barrier = 0, 0
	local worstKerb, worstPredicted, worstAt = 0, 0, "-"
	local sumKerb, sumPredicted, seams, profiled = 0, 0, 0, 0
	for _, piece in run do
		local b = Builder.build(piece, holder)
		if not piece.flat then
			profiled += 1
		end
		for k = 2, #piece.nodes - 1 do
			local A, B = b.road[k - 1], b.road[k]
			if A and B then
				seams += 1
				centre = math.max(centre, seamRiser(A, B, 0))
				local kerb = math.max(seamRiser(A, B, -half), seamRiser(A, B, half))
				local yawK = piece.nodes[k].yaw
				local predicted = half
					* math.abs(
						crossSlope(piece.nodes[k - 1], piece.nodes[k], yawK)
							- crossSlope(piece.nodes[k], piece.nodes[k + 1], yawK)
					)
				table.insert(kerbs, kerb)
				sumKerb += kerb
				sumPredicted += predicted
				if kerb > worstKerb then
					worstKerb, worstPredicted, worstAt = kerb, predicted, A.Name
				end
			end
		end
		-- The walls, over their own two studs of width, asked the same question. Each
		-- side is walked on its own: they are built interleaved.
		local left, right = {}, {}
		for _, w in b.barriers do
			table.insert(if string.find(w.Name, "^Barrier_L") then left else right, w)
		end
		for _, side in { left, right } do
			for i = 1, #side - 1 do
				barrier =
					math.max(barrier, seamRiser(side[i], side[i + 1], -hw), seamRiser(side[i], side[i + 1], 0), seamRiser(side[i], side[i + 1], hw))
			end
		end
		task.wait()
	end
	holder:Destroy()
	Builder.DebugResetMarks()
	table.sort(kerbs)
	return {
		pieces = #run,
		profiled = profiled,
		seams = seams,
		centre = centre,
		kerbWorst = worstKerb,
		kerbAt = worstAt,
		kerbPredicted = worstPredicted,
		kerbMedian = kerbs[math.max(1, #kerbs // 2)] or 0,
		kerbP90 = kerbs[math.max(1, math.floor(#kerbs * 0.9))] or 0,
		sumKerb = sumKerb,
		sumPredicted = sumPredicted,
		barrier = barrier,
	}
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

	-- WHAT STOPPED THE CAR, ROAD OR WALL (`o.wallParts`, T-066). `Drift/World` sorts what
	-- its sweep finds by the normal: anything leaning more than about 46 degrees is a wall
	-- and the car stops dead against it, and a wall made of ROAD is the one thing a piece
	-- with a grade and a bank could accidentally become. The model only reports THAT it
	-- hit something, so this repeats the cast when it does and reads the part's name.
	-- Off by default: it doubles the cost of every step that touches anything.
	local roadWalls, barrierWalls = 0, 0
	if o.wallParts then
		local realSweep = world.sweep
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		world.sweep = function(from, to, yaw)
			local safe, normal = realSweep(from, to, yaw)
			if normal then
				local delta = to - from
				local flat = Vector3.new(delta.X, 0, delta.Z)
				local box = CFrame.new(from) * CFrame.Angles(0, yaw, 0)
				local skip = {}
				for _ = 1, 6 do
					params.FilterDescendantsInstances = skip
					local hit = workspace:Blockcast(box, world.carBox, flat, params)
					if not hit then
						break
					end
					if math.abs(hit.Normal.Y) > 0.7 then
						table.insert(skip, hit.Instance)
						continue
					end
					if string.sub(hit.Instance.Name, 1, 5) == "Road_" then
						roadWalls += 1
					else
						barrierWalls += 1
					end
					break
				end
			end
			return safe, normal
		end
	end
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
		longestDrift = 0, -- seconds of one unbroken slide: what a sweeper is for
		slipFlips = 0, -- slides caught and swapped the other way: what a chicane is for
		stuckSeconds = 0,
		backwardsSteps = 0,
		reached = 1,
		steps = 0,
		seconds = 0,
		-- EVERY NUMBER ABOVE IS ABOUT THE ROAD, and a piece type cannot be chosen from a
		-- number about the road: twenty pieces that contain three hairpins report mostly
		-- what the straights and the corners did. So the drive also keeps the same
		-- numbers PER PIECE TYPE, gathered one visit at a time -- a visit being the
		-- contiguous stretch the car spends on one piece -- which is what makes "the
		-- hairpin never touched a barrier" a sentence about the hairpin.
		byKind = {},
	}
	local stuckSteps, lastN = 0, 1
	local driftSteps, slipSign = 0, 0
	local visit = nil

	local function finishVisit()
		if not visit or visit.steps < 5 then
			visit = nil
			return
		end
		local k = r.byKind[visit.kind]
		if not k then
			k = { visits = 0, steps = 0, drift = 0, held = 0, minSpeed = math.huge, maxSpeed = 0, lateral = 0, flips = 0, wall = 0, off = 0 }
			r.byKind[visit.kind] = k
		end
		k.visits += 1
		k.steps += visit.steps
		k.drift += visit.drift
		-- "Held" is a slide that lasted essentially the whole piece, which is the one
		-- thing a sweeper is for and the one thing a hairpin is not.
		if visit.drift / visit.steps >= 0.9 then
			k.held += 1
		end
		k.minSpeed = math.min(k.minSpeed, visit.minSpeed)
		k.maxSpeed = math.max(k.maxSpeed, visit.maxSpeed)
		k.lateral = math.max(k.lateral, visit.lateral)
		k.flips += visit.flips
		k.wall += visit.wall
		k.off += visit.off
		visit = nil
	end
	-- A SLIDE IS NOT A SLIP READING. The car is always a degree or two out; what the
	-- chicane is being asked to produce is a real slide one way, caught, and a real slide
	-- the other. So a flip only counts when the slip passes this far through zero.
	local FLIP_SLIP = 12 -- degrees

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
			driftSteps += 1
			r.longestDrift = math.max(r.longestDrift, driftSteps * D.FixedStep)
		else
			driftSteps = 0
		end
		local slipDeg = math.deg(s.slip)
		local flipped = false
		if math.abs(slipDeg) >= FLIP_SLIP then
			local sign = if slipDeg > 0 then 1 else -1
			if slipSign ~= 0 and sign ~= slipSign then
				r.slipFlips += 1
				flipped = true
			end
			slipSign = sign
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

			if not visit or visit.n ~= n then
				finishVisit()
				local piece = gen:piece(n)
				visit = {
					n = n,
					kind = if piece then piece.kind else "?",
					steps = 0,
					drift = 0,
					minSpeed = math.huge,
					maxSpeed = 0,
					lateral = 0,
					flips = 0,
					wall = 0,
					off = 0,
				}
			end
			visit.steps += 1
			visit.drift += if s.drifting then 1 else 0
			visit.minSpeed = math.min(visit.minSpeed, speed)
			visit.maxSpeed = math.max(visit.maxSpeed, speed)
			visit.lateral = math.max(visit.lateral, lateral)
			visit.flips += if flipped then 1 else 0
			visit.wall += if s.wallHit then 1 else 0
			visit.off += if lateral > C.Width * 0.5 then 1 else 0
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
				-- A DRIVER WHO HAS NEARLY STOPPED STILL TURNS THE WHEEL (T-068). Pure
				-- pursuit asks for the yaw RATE that curves a car travelling at `speed`
				-- on to the target, so as the speed falls the command falls with it and
				-- at a standstill this autopilot steers nothing at all. On the flat road
				-- that never mattered, because the flat road never stops the car. On a
				-- banked, descending one it does: gravity acts along the surface now
				-- (T-065), so a car that loses its speed on a bank slides down it, the
				-- slide IS slip, past 90 degrees of slip the model's grip force becomes a
				-- brake, and the car sits there for the rest of the drive with the
				-- steering commanding nothing. That is the FIXTURE failing to answer the
				-- question rather than the road failing to be drivable -- a player in that
				-- spot turns the wheel and drives out of it.
				--
				-- So the yaw rate is asked for as though the car were doing at least
				-- `STEER_FLOOR`. Above that speed it changes nothing, which is every
				-- number this file has measured on the flat road bar the moments the car
				-- is slowest in a hairpin.
				local yawWanted = math.max(speed, STEER_FLOOR) * (2 * math.sin(alpha) / look)
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

	finishVisit()
	r.seconds = elapsed
	r.roadWalls, r.barrierWalls = roadWalls, barrierWalls
	r.meanSpeed = r.speedSum / math.max(r.speedN, 1)
	r.driftShare = r.driftSteps / math.max(r.steps, 1)
	r.detail = string.format(
		"%d pieces in %.0f s of simulation (%d steps); speed %.0f..%.0f, mean %.0f studs/s; drifting %.0f%% of it (longest unbroken slide %.1f s, %d caught and swapped), peak slip %.0f deg; worst %.1f studs from the centre line (the road is %d wide, so %.1f studs of margin); %d steps off the road, %d airborne, %d touching a barrier, longest slow patch %.2f s",
		r.reached,
		elapsed,
		r.steps,
		r.minSpeed,
		r.maxSpeed,
		r.meanSpeed,
		100 * r.driftShare,
		r.longestDrift,
		r.slipFlips,
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

-- The measurement every piece's numbers were chosen with, kept so the next person can
-- repeat it rather than take it on trust. It mutates `Config.Road` in the live VM,
-- rebuilds the piece set, drives, and puts everything back.
--
--   game.ServerStorage.DebugBridge:Invoke("DebugRoadTests", "sweep")      -- step 1's
--   ... "sweep", { piece = "Hairpin", field = "Radius", values = { 60, 80, 100 },
--                  only = { "Straight", "Hairpin" } }
--
-- `only` is what makes a sweep about ONE PIECE. With the whole set enabled a drive down
-- twenty pieces might meet two hairpins, and the number that comes back is about the
-- road rather than about the hairpin. Naming the pieces to keep pushes everything else
-- out of reach (`minPieces` beyond any run), so every corner the car meets is the one
-- being measured. `Straight` is always kept: it is the start piece, and without it the
-- generator has nothing to run between the corners.
local function setOnly(names)
	local was = {}
	for name, spec in Config.Road.Pieces do
		was[name] = spec.minPieces
	end
	if names then
		local keep = {}
		for _, n in names do
			keep[n] = true
		end
		keep.Straight = true
		for name, spec in Config.Road.Pieces do
			if not keep[name] then
				spec.minPieces = math.huge
			else
				spec.minPieces = 0
			end
		end
	end
	return was
end

-- `set = { Sweeper = { Arc = 45 } }`: hold a piece's other numbers somewhere other than
-- where the config has them for the length of a measurement, and put them back after.
local function applySet(set)
	local was = {}
	for name, fields in set or {} do
		was[name] = {}
		for f, v in fields do
			was[name][f] = Config.Road.Pieces[name][f]
			Config.Road.Pieces[name][f] = v
		end
	end
	return was
end

local function restoreSet(was)
	for name, fields in was do
		for f, v in fields do
			Config.Road.Pieces[name][f] = v
		end
	end
end

-- What the car did ON one kind of piece, over however many of them the drive met.
local function kindRow(r, kind: string): string
	local k = r.byKind[kind]
	if not k or k.visits == 0 then
		return "never met one"
	end
	return string.format(
		"%2d of them: speed %3.0f..%3.0f on it, drifting %3.0f%% of it (%d of %d held the slide the whole way), %2d caught and swapped, worst lateral %4.1f, %4d steps on a barrier, %d off the road",
		k.visits,
		k.minSpeed,
		k.maxSpeed,
		100 * k.drift / math.max(k.steps, 1),
		k.held,
		k.visits,
		k.flips,
		k.lateral,
		k.wall,
		k.off
	)
end

local function restoreMinPieces(was)
	for name, value in was do
		Config.Road.Pieces[name].minPieces = value
	end
end

--------------------------------------------------------------------------------
-- Pieces with a height and a bank, which the road does not have yet
--------------------------------------------------------------------------------
-- TEST FIXTURES, NOT ROAD. The road's own nine are flat and stay flat; the touge pieces
-- that will use the profile are their own task. These five exist to drive the capability
-- past where any real piece should go, and each one is here for a reason the checks name:
--
--   Plunge   loses height and arrives LEVEL, which is the vertical curve both ways round
--   Rise     the same climbing, so the run does not only ever go down
--   Swoop    a banked corner that loses height: the two profiles at once
--   Horrible steep, banked, and CHANGING BOTH down its length: it reaches the steepest
--            grade there is halfway down itself, banks to the steepest bank there is
--            over the same stretch, and hands the next piece a level road
--   Cliff    asks for four times the drop it is allowed, to prove the clamp is the thing
--            that decides and not the profile
--
-- A STRAIGHT THAT STARTS AND ENDS LEVEL IS STEEPEST IN THE MIDDLE, at 1.5x its average
-- grade -- a property of the vertical curve, and the reason `Plunge` only drops 20 studs
-- over 220 when 31 would be within `MaxGrade` as an average.
local PROFILE_PIECES = {
	Plunge = {
		kind = "Plunge",
		Shape = "straight",
		weight = 1,
		minPieces = 0,
		mirror = false,
		Length = 220,
		Height = { Drop = 20, EndGrade = 0 },
	},
	Rise = {
		kind = "Rise",
		Shape = "straight",
		weight = 1,
		minPieces = 0,
		mirror = false,
		Length = 220,
		Height = { Drop = -20, EndGrade = 0 },
	},
	Swoop = {
		kind = "Swoop",
		Shape = "arc",
		weight = 1,
		minPieces = 0,
		mirror = true,
		Radius = 220,
		Arc = 30,
		Height = { Drop = 12 },
		Bank = { Degrees = 18 },
	},
	-- ITS PLAN SHAPE IS THE SHIPPED CORNER'S, DELIBERATELY: 220 studs of radius and 90
	-- degrees of it, the one the piece set was measured and driven on. Everything horrible
	-- about it is in the two new axes -- it descends the whole way, at the steepest grade
	-- allowed by the time it hands over, while banking from level to the steepest bank
	-- there is and back again -- so when it is driven, what is being asked about is the
	-- grade and the bank and not the corner.
	--
	-- THE FIRST VERSION OF IT WAS A 120-DEGREE CORNER AT RADIUS 90 and the autopilot got
	-- pinned on its outside wall at 17 studs/s and never got going again. Nothing about
	-- that was elevation: a bank also COSTS PLAN WIDTH, because a 50-stud road banked 30
	-- degrees is only 43 studs wide seen from above, and a corner tighter than anything in
	-- the set plus three fewer studs either side is a corner the autopilot cannot hold.
	Horrible = {
		kind = "Horrible",
		Shape = "arc",
		weight = 1,
		minPieces = 0,
		mirror = true,
		Radius = 220,
		Arc = 90,
		Height = { Drop = 40, EndGrade = 0 },
		Bank = { Degrees = 20, Shape = "crest" },
	},
	Cliff = {
		kind = "Cliff",
		Shape = "straight",
		weight = 1,
		minPieces = 0,
		mirror = false,
		Length = 220,
		Height = { Drop = 200 },
	},
	-- Asks for more grade and more bank than the config allows at once, which is the only
	-- way to make the COMBINED cap bite: 14 degrees of grade and 30 of bank only come to
	-- 32.8 together, so with the shipped numbers nothing can reach the 35 that is the
	-- limit. Both of its own numbers are clamped to the config's on the way in.
	Brutal = {
		kind = "Brutal",
		Shape = "arc",
		weight = 1,
		minPieces = 0,
		mirror = true,
		Radius = 120,
		Arc = 90,
		Height = { EndGrade = -25 },
		Bank = { Degrees = 40 },
	},
}

-- Splice some of them into the live piece set, optionally pushing everything but a named
-- few out of reach, and hand back the undo. Every check that uses it calls the undo.
local function useProfilePieces(add: { string }, only: { string }?)
	local added = {}
	for _, name in add do
		Config.Road.Pieces[name] = PROFILE_PIECES[name]
		table.insert(added, name)
	end
	local wasMin = if only then setOnly(only) else nil
	Pieces.rebuild()
	return function()
		if wasMin then
			restoreMinPieces(wasMin)
		end
		for _, name in added do
			Config.Road.Pieces[name] = nil
		end
		Pieces.rebuild()
	end
end

function Tests:sweep(o)
	o = o or {}
	local C = Config.Road
	-- Step 1's sweep, unchanged, is what a bare `"sweep"` still runs.
	local piece = o.piece or "Corner"
	local field = o.field or "Radius"
	local values = o.values or o.radii or { 120, 160, 200, 250, 320 }
	local spec = C.Pieces[piece]
	assert(spec, `no piece called {piece}`)

	-- A sweep of the radius can be a sweep of the radius at a chosen arc, rather than
	-- only at the one already written down.
	local wasSet = applySet(o.set)

	local wasValue = spec[field]
	local wasLength = C.Pieces.Straight.Length
	local lengths = o.lengths or { wasLength }
	local wasMin = setOnly(o.only)
	local rows = {}
	for _, length in lengths do
		for _, value in values do
			spec[field] = value
			C.Pieces.Straight.Length = length
			Pieces.rebuild()
			local r = Tests:drive({
				seed = o.seed or 8080,
				pieces = o.pieces or 20,
				seconds = o.seconds or 240,
				look = o.look,
				brake = o.brake,
			})
			table.insert(
				rows,
				string.format(
					"%s %s %4s | the run: %2d pieces, speed %3.0f..%3.0f mean %3.0f, drifting %2.0f%% (longest %4.1f s), peak slip %3.0f, worst lateral %4.1f of %.1f, off-road %4d, barrier %4d, slow %.1fs\n%22s| the %s: %s",
					piece,
					field,
					tostring(value),
					r.reached,
					r.minSpeed,
					r.maxSpeed,
					r.meanSpeed,
					100 * r.driftShare,
					r.longestDrift,
					r.peakSlip,
					r.worstLateral,
					C.Width * 0.5,
					r.offRoadSteps,
					r.wallSteps,
					r.stuckSeconds,
					"",
					piece,
					kindRow(r, piece)
				)
			)
		end
	end
	spec[field] = wasValue
	C.Pieces.Straight.Length = wasLength
	-- THE GATES GO BACK BEFORE `set` DOES, and the order is a bug fix rather than taste
	-- (T-068). `wasMin` is read AFTER `applySet`, so when a `set` names a `minPieces` --
	-- which is how a measurement pushes a whole group of pieces out of reach -- undoing it
	-- second would write the mutated gate back over the real one and leave the piece set
	-- wrong for everything that ran after. Measured: a drive that followed one met none of
	-- the four touge pieces at all.
	restoreMinPieces(wasMin)
	restoreSet(wasSet)
	Pieces.rebuild()
	return table.concat(rows, "\n")
end

-- How often a long run boxes itself in, against the numbers that decide it: how deep the
-- lookahead searches, how many placements it may try before giving up, and what a
-- corner's arc is. Pure, so it costs no parts and no playtest. This is the measurement
-- `LookAhead` and `SearchNodeBudget` were set from, and it is kept so the next piece type
-- can be checked the same way:
--   game.ServerStorage.DebugBridge:Invoke("DebugRoadTests", "stalls")
--   ... "stalls", { depths = { 9, 11 }, budgets = { 4000, 20000 }, seeds = 40 }
--
-- IT REPORTS WHY A RUN STALLED, not only that it did, and the distinction is the whole
-- point: a search that ran out of BUDGET has not proved there is no way out, it has only
-- stopped looking. Those two want opposite fixes -- more budget, or more depth -- so
-- they are counted apart.
function Tests:stalls(o)
	o = o or {}
	local C = Config.Road
	local depths = o.depths or { 3, 5, 7, 9, 11, 14 }
	local budgets = o.budgets or { C.SearchNodeBudget }
	local arcs = o.arcs or { C.Pieces.Corner.Arc }
	local seeds = o.seeds or 40
	local length = o.pieces or 400
	local wasLook, wasArc, wasBudget = C.LookAhead, C.Pieces.Corner.Arc, C.SearchNodeBudget
	local wasSet = applySet(o.set)
	local rows = {}
	for _, arc in arcs do
		for _, budget in budgets do
			for _, depth in depths do
				C.LookAhead = depth
				C.SearchNodeBudget = budget
				C.Pieces.Corner.Arc = arc
				Pieces.rebuild()
				local stalls, earliest, worstNodes, total, outOfBudget = 0, math.huge, 0, 0, 0
				local relaxed, leastProof = 0, math.huge
				local endedOn = {}
				local t0 = os.clock()
				for seed = 1, seeds do
					local run, g = longRun(seed * 1013, length)
					total += #run
					relaxed += g.relaxed
					leastProof = math.min(leastProof, g.worstProof)
					if #run < length then
						stalls += 1
						earliest = math.min(earliest, #run)
						if g.searchNodes >= budget then
							outOfBudget += 1
						end
						-- Which piece the road was standing on when it ran out of room.
						-- A piece that turns up here far more than its share is the one
						-- making the traps, which is a thing about the SET, not the depth.
						local last = run[#run]
						if last then
							endedOn[last.id] = (endedOn[last.id] or 0) + 1
						end
					end
					worstNodes = math.max(worstNodes, g.worstNodes)
					task.wait() -- a deep search over many seeds is the one slow thing here,
					-- and a Studio that stops answering is a Studio that
					-- cannot be asked what the answer was
				end
				local ended = {}
				for _, id in Pieces.order() do
					if endedOn[id] then
						table.insert(ended, `{id} {endedOn[id]}`)
					end
				end
				table.insert(
					rows,
					string.format(
						"arc %3d, lookahead %2d, budget %6d: %2d of %d runs boxed themselves in (%d of them out of budget rather than out of road; earliest at piece %s), %d pieces generated, %d of them on short proof (least %s of %d), worst search %5d nodes, %.0f ms%s",
						arc,
						depth,
						budget,
						stalls,
						seeds,
						outOfBudget,
						if earliest == math.huge then "-" else tostring(earliest),
						total,
						relaxed,
						if leastProof == math.huge then "-" else tostring(leastProof),
						depth,
						worstNodes,
						(os.clock() - t0) * 1000,
						if #ended > 0 then "; stalled standing on " .. table.concat(ended, ", ") else ""
					)
				)
			end
		end
	end
	C.LookAhead, C.Pieces.Corner.Arc, C.SearchNodeBudget = wasLook, wasArc, wasBudget
	restoreSet(wasSet)
	Pieces.rebuild()
	return table.concat(rows, "\n")
end

-- WHERE THE ROAD GOES VERTICALLY OVER A LONG RUN, which is the question the touge set has
-- to answer and the one number that cannot be read off any single piece (T-068). A piece
-- with no height profile CARRIES the grade it arrived at, so the road's height is a state
-- machine driven by the four touge pieces' `EndGrade`s, and the only honest way to read it
-- is to generate a long run and look.
--
-- Pure: no parts, no playtest.
--   game.ServerStorage.DebugBridge:Invoke("DebugRoadTests", "heightBand")
--   ... "heightBand", { pieces = 200, set = { Link = { Height = { EndGrade = 5 } } } }
function Tests:heightBand(o)
	o = o or {}
	local C = Config.Road
	local pieces = o.pieces or PROFILE_RUN
	local seeds = o.seeds or SEEDS
	local wasSet = applySet(o.set)
	Pieces.rebuild()

	local rows = {}
	local sumNet, sumLow, sumHigh, worstTilt, worstTiltId = 0, 0, 0, 0, "?"
	local sumRuns, sumRunPieces, longestDescent = 0, 0, 0
	local byKind = {}
	for _, seed in seeds do
		local run = longRun(seed, pieces)
		local low, high, net = 0, 0, 0
		local studs = 0
		-- A DESCENT IS A STRETCH, NOT A PIECE: how long the road keeps falling once a
		-- corkscrew has set it falling is what decides whether a descent is a feature or a
		-- plunge, and it is the thing `EndGrade` actually controls.
		local descents, descentPieces, here = 0, 0, 0
		for _, piece in run do
			local k = byKind[piece.kind]
			if not k then
				k = { n = 0, drop = 0 }
				byKind[piece.kind] = k
			end
			k.n += 1
			k.drop += (piece.finish.y or 0) - (piece.start.y or 0)
			studs += piece.length
			for _, node in piece.nodes do
				low = math.min(low, node.y)
				high = math.max(high, node.y)
				local tilt = math.deg(math.acos(math.clamp(math.cos(node.pitch) * math.cos(node.bank), -1, 1)))
				if tilt > worstTilt then
					worstTilt, worstTiltId = tilt, piece.id
				end
			end
			net = piece.finish.y or 0
			if (piece.finish.pitch or 0) < -1e-6 then
				here += 1
				longestDescent = math.max(longestDescent, here)
			else
				if here > 0 then
					descents += 1
					descentPieces += here
				end
				here = 0
			end
		end
		if here > 0 then
			descents += 1
			descentPieces += here
		end
		sumNet += net
		sumLow += low
		sumHigh += high
		sumRuns += descents
		sumRunPieces += descentPieces
		table.insert(
			rows,
			string.format(
				"seed %8d: %3d pieces over %6.0f studs of road, net %+7.1f studs (%.2f%% average grade), lowest %+7.1f, highest %+6.1f, band %6.1f; %d descents averaging %.1f pieces",
				seed,
				#run,
				studs,
				net,
				-100 * net / math.max(studs, 1),
				low,
				high,
				high - low,
				descents,
				descentPieces / math.max(descents, 1)
			)
		)
	end

	local kinds = {}
	for _, id in Pieces.order() do
		local kind = Pieces.get(id).kind
		local k = byKind[kind]
		if k and not kinds[kind] then
			kinds[kind] = true
			table.insert(rows, string.format("  %-13s %4d of them, %+8.1f studs between them (%+6.1f each)", kind, k.n, k.drop, k.drop / k.n))
		end
	end
	table.insert(
		rows,
		string.format(
			"MEAN over %d seeds: net %+.1f studs over %d pieces (%+.2f a piece), lowest %+.1f, highest %+.1f; longest unbroken descent %d pieces; steepest surface anywhere %.2f deg on a %s (the lid is %.0f)",
			#seeds,
			sumNet / #seeds,
			pieces,
			sumNet / #seeds / pieces,
			sumLow / #seeds,
			sumHigh / #seeds,
			longestDescent,
			worstTilt,
			worstTiltId,
			C.MaxSurfaceTilt
		)
	)

	restoreSet(wasSet)
	Pieces.rebuild()
	return table.concat(rows, "\n")
end

-- The seam measurement on its own, for looking at rather than passing:
--   game.ServerStorage.DebugBridge:Invoke("DebugRoadTests", "seams", { seeds = { 8080 } })
function Tests:seams(o)
	o = o or {}
	local rows = {}
	for _, seed in o.seeds or { SEAM_SEED } do
		local s = seamSweep(seed, o.pieces or SEAM_PIECES)
		table.insert(
			rows,
			string.format(
				"seed %8d: %d pieces (%d profiled), %d seams | centre %.4f | kerb median %.4f p90 %.4f WORST %.4f at %s (predicted %.4f) | walls %.4f",
				seed,
				s.pieces,
				s.profiled,
				s.seams,
				s.centre,
				s.kerbMedian,
				s.kerbP90,
				s.kerbWorst,
				s.kerbAt,
				s.kerbPredicted,
				s.barrier
			)
		)
	end
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
		local kinds = {}
		for _, id in ids do
			kinds[Pieces.get(id).kind] = true
		end
		local kindCount = 0
		for _ in kinds do
			kindCount += 1
		end
		check(
			"the piece set is nine types in sixteen variants: five flat and four touge",
			#ids == 16
				and kindCount == 9
				and kinds.Straight
				and kinds.Corner
				and kinds.Sweeper
				and kinds.Hairpin
				and kinds.Chicane
				and kinds.Link
				and kinds.Banked30
				and kinds.HairpinStack
				and kinds.Corkscrew,
			table.concat(lines, "; ")
		)
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
	-- 1b. Every variant joins flush, and the chicane bends both ways
	----------------------------------------------------------------------------
	-- The 500-piece continuity check below proves the road is flush where it is actually
	-- generated. This proves it for EVERY variant, including ones a seed might not reach,
	-- and on a socket that is turned and moved rather than the origin: the join is one
	-- rotation and one addition, so if it is right anywhere it is right everywhere, and
	-- this is where that claim is tested rather than assumed.
	do
		local socket = { x = -1234.5, z = 678.25, yaw = math.rad(37) }
		local worstStart, worstStep, worstEnd = 0, 0, 0
		local lines = {}
		for i, id in Pieces.order() do
			local v = Pieces.get(id)
			local placed = Pieces.place(v, socket, i)
			worstStart = math.max(worstStart, (socketGap(placed.start, placed.nodes[1])))
			local d = math.sqrt((placed.finish.x - placed.nodes[#placed.nodes].x) ^ 2 + (placed.finish.z - placed.nodes[#placed.nodes].z) ^ 2)
			worstEnd = math.max(worstEnd, d)
			-- Inside a piece too: a chicane is two shapes end to end, and a gap between
			-- them would be a seam in the middle of one piece rather than between two.
			-- A seam shows up as a node step longer than a chord is allowed to be.
			for n = 1, #placed.nodes - 1 do
				local a, b = placed.nodes[n], placed.nodes[n + 1]
				worstStep = math.max(worstStep, math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2))
			end
			table.insert(lines, string.format("%s %.1f studs", id, placed.length))
		end
		check(
			`all {#Pieces.order()} variants join flush on a turned socket`,
			worstStart <= SOCKET_TOLERANCE
				and worstEnd <= SOCKET_TOLERANCE
				and worstStep <= math.max(C.MaxSegmentChord, C.Pieces.Straight.Length) + 1e-6,
			string.format(
				"placed on a socket at (%.1f, %.1f) facing 37 deg: worst start-socket gap %.3e studs, worst end-socket gap %.3e, longest step between two nodes %.2f (no seam inside a piece). %s",
				socket.x,
				socket.z,
				worstStart,
				worstEnd,
				worstStep,
				table.concat(lines, ", ")
			)
		)

		-- The chicane is the one piece whose shape is not one shape. What makes it a
		-- chicane rather than a wide corner is that the second bend is the OPPOSITE of
		-- the first, so it comes out pointing the way it went in, having moved sideways.
		local okBends = true
		local report = {}
		for _, id in { "ChicaneL", "ChicaneR" } do
			local v = Pieces.get(id)
			local first, second = 0, 0
			local half = (#v.nodes - 1) / 2
			for n = 1, #v.nodes - 1 do
				local step = v.nodes[n + 1].yaw - v.nodes[n].yaw
				if n <= half then
					first += step
				else
					second += step
				end
			end
			local net = v.nodes[#v.nodes].yaw
			local across = math.abs(v.nodes[#v.nodes].x)
			okBends = okBends
				and math.abs(net) < 1e-9 -- it leaves pointing the way it arrived
				and math.abs(first + second) < 1e-9 -- the two bends cancel exactly
				and first * second < 0 -- and they are genuinely opposite, not both zero
				and across > C.Width -- having moved more than a road's width across
			table.insert(
				report,
				string.format(
					"%s bends %+.1f deg then %+.1f, net %+.2e, and steps %.1f studs across a %d-stud road",
					id,
					math.deg(first),
					math.deg(second),
					math.deg(net),
					across,
					C.Width
				)
			)
		end
		check("the chicane's two bends are opposite and cancel", okBends, table.concat(report, "; "))
	end

	----------------------------------------------------------------------------
	-- 1c. The flat road is the road it was before it could climb (T-066)
	----------------------------------------------------------------------------
	do
		local f = withFlatSetOnly(flatFingerprint)
		local same = f.pieces == PINNED.pieces
			and f.sequence == PINNED.sequence
			and f.geometry == PINNED.geometry
			and f.parts == PINNED.parts
			and f.built == PINNED.built
		local who = {}
		for _, key in { "pieces", "sequence", "geometry", "parts", "built" } do
			table.insert(who, string.format("%s %d%s", key, f[key], if f[key] == PINNED[key] then "" else ` (pinned {PINNED[key]})`))
		end
		check(
			"the nine flat pieces are the same road, piece for piece and part for part",
			same,
			string.format(
				"with the four touge pieces gated out and the search budget held at %d, seed 1234 x %d pieces and the first 20 of them built, against fingerprints taken before a socket had a height: %s.%s",
				PINNED_BUDGET,
				PINNED.pieces,
				table.concat(who, ", "),
				if same
					then " Identical."
					else " RE-PIN ONLY IF THE ROAD WAS MEANT TO CHANGE (see `PINNED` in this file)."
			)
		)
	end

	----------------------------------------------------------------------------
	-- 1d. A piece can have a height and a bank, and the road stays flush (T-066)
	----------------------------------------------------------------------------
	-- Everything here is pure: no parts, no playtest. The profiled pieces are test
	-- fixtures spliced into the set for the length of the check and taken out again.
	do
		local restore = useProfilePieces({ "Plunge", "Rise", "Swoop", "Horrible", "Cliff", "Brutal" })
		local ok, err = pcall(function()
			local run = longRun(2468, PROFILE_RUN)

			-- (a) THE JOIN. In three dimensions and in all three angles this time.
			local worstGap, worstYaw, worstPitch, worstRoll, worstNode = 0, 0, 0, 0, 0
			local profiledPieces = 0
			local lowest, highest = math.huge, -math.huge
			for i, piece in run do
				if not piece.flat then
					profiledPieces += 1
				end
				local n1 = piece.nodes[1]
				worstNode = math.max(
					worstNode,
					math.sqrt((n1.x - piece.start.x) ^ 2 + (n1.y - (piece.start.y or 0)) ^ 2 + (n1.z - piece.start.z) ^ 2)
				)
				for _, node in piece.nodes do
					lowest = math.min(lowest, node.y)
					highest = math.max(highest, node.y)
				end
				if i > 1 then
					local a, b = run[i - 1].finish, piece.start
					worstGap = math.max(worstGap, math.sqrt((a.x - b.x) ^ 2 + ((a.y or 0) - (b.y or 0)) ^ 2 + (a.z - b.z) ^ 2))
					worstYaw = math.max(worstYaw, angleGap(a.yaw, b.yaw))
					worstPitch = math.max(worstPitch, math.abs((a.pitch or 0) - (b.pitch or 0)))
					worstRoll = math.max(worstRoll, math.abs((a.roll or 0) - (b.roll or 0)))
				end
			end
			check(
				`{#run} pieces with height and bank in them, and still not one gap`,
				#run == PROFILE_RUN
					and worstGap == 0
					and worstYaw == 0
					and worstPitch == 0
					and worstRoll == 0
					and worstNode == 0,
				string.format(
					"%d pieces, %d of them profiled, over %.0f studs of height (%.0f to %.0f): worst finish-to-start socket gap %.3e studs, yaw %.3e, pitch %.3e, roll %.3e rad; worst start-node gap %.3e. Exactly zero, as on the flat",
					#run,
					profiledPieces,
					highest - lowest,
					lowest,
					highest,
					worstGap,
					worstYaw,
					worstPitch,
					worstRoll,
					worstNode
				)
			)

			-- (b) NO JOIN IS A STEP AND NO BANK IS A KINK. What a ground ray actually
			-- reads is the SEGMENTS -- each one a flat box -- so the step measured here is
			-- between the slopes of neighbouring boxes, right across the joins as well as
			-- inside a piece, and never between the smooth numbers behind them.
			local worstPitchStep, worstBankStep, where = 0, 0, ""
			local lastPitch, lastBank, lastWhere = nil, nil, ""
			for _, piece in run do
				for i = 1, #piece.nodes - 1 do
					local a, b = piece.nodes[i], piece.nodes[i + 1]
					local plan = piece.cum[i + 1] - piece.cum[i]
					local chord = if plan > 1e-9 then math.atan((b.y - a.y) / plan) else 0
					local bank = (a.bank + b.bank) * 0.5
					local here = `{piece.id} {piece.n} seg {i}`
					if lastPitch then
						local dp = math.deg(math.abs(chord - lastPitch))
						local db = math.deg(math.abs(bank - lastBank))
						if dp > worstPitchStep then
							worstPitchStep, where = dp, `{lastWhere} -> {here}`
						end
						worstBankStep = math.max(worstBankStep, db)
					end
					lastPitch, lastBank, lastWhere = chord, bank, here
				end
			end
			-- THE LIMIT IS ON THE NODES AND THIS MEASURES THE BOXES, and the two differ by
			-- a hair for a reason worth writing down: a box's own slope is the mean of its
			-- two ends' TANGENTS, not of their angles, so where the grade is steepest two
			-- neighbouring boxes can read 0.003 of a degree further apart than the nodes
			-- behind them are. That is the whole of this slack.
			local STEP_SLACK = 0.01 -- degrees
			check(
				"no join is a step and no bank is a kink",
				worstPitchStep <= C.MaxPitchStep + STEP_SLACK and worstBankStep <= C.MaxBankStep + STEP_SLACK,
				string.format(
					"over %d pieces, between every pair of neighbouring segments including across every join: worst grade change %.3f deg (limit %.2f, at %s), worst bank change %.3f deg (limit %.2f)",
					#run,
					worstPitchStep,
					C.MaxPitchStep,
					where,
					worstBankStep,
					C.MaxBankStep
				)
			)

			-- (c) NOTHING READS AS A WALL. `Drift/World` calls a surface whose normal
			-- leans more than about 46 degrees a wall and stops the car dead against it,
			-- and GRADE AND BANK COMPOUND: the normal's Y is cos(grade) x cos(bank), so it
			-- is the pair that has to be measured and never one at a time.
			local worstTilt, worstGrade, worstBank, tiltAt = 0, 0, 0, ""
			for _, piece in run do
				for _, node in piece.nodes do
					local tilt = math.deg(math.acos(math.clamp(math.cos(node.pitch) * math.cos(node.bank), -1, 1)))
					worstGrade = math.max(worstGrade, math.abs(math.deg(node.pitch)))
					worstBank = math.max(worstBank, math.abs(math.deg(node.bank)))
					if tilt > worstTilt then
						worstTilt, tiltAt = tilt, piece.id
					end
				end
			end
			check(
				"nothing the road can generate reads as a wall",
				worstTilt <= C.MaxSurfaceTilt + 1e-6 and worstTilt < WALL_DEGREES - 8 and worstGrade <= C.MaxGrade + 1e-6 and worstBank <= C.MaxBank + 1e-6,
				string.format(
					"the steepest surface over %d pieces leans %.2f deg (on a %s): grade %.2f of %.1f allowed, bank %.2f of %.1f, and the two together %.2f of %.1f. The normal's Y is %.4f against the %.2f at which Drift/World calls it a wall (%.1f deg)",
					#run,
					worstTilt,
					tiltAt,
					worstGrade,
					C.MaxGrade,
					worstBank,
					C.MaxBank,
					worstTilt,
					C.MaxSurfaceTilt,
					math.cos(math.rad(worstTilt)),
					WALL_NORMAL_Y,
					WALL_DEGREES
				)
			)
		end)
		restore()
		if not ok then
			error(err, 0)
		end
	end

	----------------------------------------------------------------------------
	-- 1e. The caps decide, not the profile (T-066)
	----------------------------------------------------------------------------
	-- Two separate claims, both about what happens when a piece asks for too much.
	do
		local restore = useProfilePieces({ "Cliff", "Brutal" })
		local ok, err = pcall(function()
			-- (a) A PIECE THAT ASKS FOR MORE DROP THAN IT MAY HAVE gets the grade it is
			-- allowed and lands higher than it wanted, rather than getting a wall.
			local cliff = Pieces.place(Pieces.get("Cliff"), { x = 0, z = 0, yaw = 0 }, 1)
			local got = -(cliff.finish.y or 0)
			local allowed = math.tan(math.rad(C.MaxGrade)) * cliff.length
			local steepest = 0
			for _, node in cliff.nodes do
				steepest = math.max(steepest, math.abs(math.deg(node.pitch)))
			end
			check(
				"a piece that asks for more drop than MaxGrade allows gets MaxGrade",
				got < allowed + 1e-6 and steepest <= C.MaxGrade + 1e-6 and got > allowed * 0.8,
				string.format(
					"Cliff asked to lose %d studs over %.0f; it lost %.1f, which is %.0f%% of the %.1f a %.1f-degree grade can lose over that length. Steepest anywhere on it: %.3f deg",
					PROFILE_PIECES.Cliff.Height.Drop,
					cliff.length,
					got,
					100 * got / allowed,
					allowed,
					C.MaxGrade,
					steepest
				)
			)

			-- (b) THE COMBINED CAP BITES, which cannot be shown with the shipped numbers
			-- because 14 degrees of grade and 30 of bank only come to 32.8 together. So
			-- the two separate limits are opened up for one placement and the combined one
			-- is left where it is: the bank is what gives way.
			local wasGrade, wasBank = C.MaxGrade, C.MaxBank
			C.MaxGrade, C.MaxBank = 30, 45
			Pieces.rebuild()
			local loose = Pieces.place(Pieces.get("BrutalL"), { x = 0, z = 0, yaw = 0 }, 1)
			local tilt, grade, bank = 0, 0, 0
			for _, node in loose.nodes do
				tilt = math.max(tilt, math.deg(math.acos(math.clamp(math.cos(node.pitch) * math.cos(node.bank), -1, 1))))
				grade = math.max(grade, math.abs(math.deg(node.pitch)))
				bank = math.max(bank, math.abs(math.deg(node.bank)))
			end
			C.MaxGrade, C.MaxBank = wasGrade, wasBank
			Pieces.rebuild()
			check(
				"grade and bank are capped together, not one at a time",
				tilt <= C.MaxSurfaceTilt + 1e-6 and grade > C.MaxGrade and bank < PROFILE_PIECES.Brutal.Bank.Degrees - 1,
				string.format(
					"with MaxGrade opened to 30 and MaxBank to 45 and MaxSurfaceTilt left at %.0f: the piece reached %.2f deg of grade and asked for 40 of bank, and came out leaning %.2f deg -- the bank was cut to %.2f to pay for the grade",
					C.MaxSurfaceTilt,
					grade,
					tilt,
					bank
				)
			)
		end)
		restore()
		if not ok then
			error(err, 0)
		end
	end

	----------------------------------------------------------------------------
	-- 1f. The four touge pieces go where they say they go (T-068)
	----------------------------------------------------------------------------
	-- Each of the four is placed on a LEVEL socket and on a DESCENDING one, and asked for
	-- the three things its design is: how much height it loses, what grade it hands on, and
	-- what bank it reaches. All of it read off the built piece, never off the spec that
	-- asked for it, because the clamps in `applyProfile` are allowed to have had their say.
	do
		local level = { x = 0, z = 0, yaw = 0 }
		local falling = { x = 0, z = 0, yaw = 0, y = 0, pitch = math.rad(-5), roll = 0 }
		local function read(id: string, socket)
			local p = Pieces.place(Pieces.get(id), socket, 5)
			local bank, grade, tilt = 0, 0, 0
			for _, n in p.nodes do
				bank = math.max(bank, math.abs(math.deg(n.bank)))
				grade = math.max(grade, math.abs(math.deg(n.pitch)))
				tilt = math.max(tilt, math.deg(math.acos(math.clamp(math.cos(n.pitch) * math.cos(n.bank), -1, 1))))
			end
			return {
				piece = p,
				drop = (socket.y or 0) - (p.finish.y :: number),
				endGrade = math.deg(p.finish.pitch :: number),
				endRoll = math.deg(p.finish.roll :: number),
				startGrade = math.deg(p.nodes[1].pitch),
				peakBank = bank,
				peakGrade = grade,
				peakTilt = tilt,
			}
		end

		local link, linkFalling = read("Link", level), read("Link", falling)
		local bank, bankFalling = read("Banked30L", level), read("Banked30L", falling)
		local stack = read("HairpinStackL", level)
		local cork, corkFalling = read("CorkscrewL", level), read("CorkscrewL", falling)
		local lines = {}
		for name, r in { Link = link, Banked30L = bank, HairpinStackL = stack, CorkscrewL = cork } do
			table.insert(
				lines,
				string.format(
					"%s from level: %+.1f studs of height, hands on %+.2f deg and %+.2f of roll, peak bank %.2f, peak grade %.2f, peak tilt %.2f",
					name,
					-r.drop,
					r.endGrade,
					r.endRoll,
					r.peakBank,
					r.peakGrade,
					r.peakTilt
				)
			)
		end
		table.sort(lines)

		-- THE LINK IS NEARLY FLAT AND IT HANDS ON A CLIMB, which is the whole of its job:
		-- it is the only thing in the set that climbs, and what climbs after it is the
		-- straights and corners that carry the grade it leaves.
		local linkSpec = C.Pieces.Link.Height.EndGrade
		check(
			"the link is nearly flat, and it levels a descent and hands on a climb",
			math.abs(link.endGrade - linkSpec) < 0.01
				and math.abs(linkFalling.endGrade - linkSpec) < 0.01
				and math.abs(link.drop) < 15
				-- `drop` is start minus finish, so a rise is negative: arriving on a
				-- descent the link rises LESS, which is a drop CLOSER TO ZERO.
				and linkFalling.drop > link.drop
				and link.peakBank == 0,
			string.format(
				"from level it gains %.1f studs over %.0f and hands on %+.2f deg; arriving on a 5-degree descent it gains %.1f and hands on the same %+.2f. No bank, ever",
				-link.drop,
				link.piece.length,
				link.endGrade,
				-linkFalling.drop,
				linkFalling.endGrade
			)
		)

		-- THE SHOWCASE: a 30-degree direction change with 30 degrees of bank, losing
		-- height, and level and unbanked at both sockets.
		local wantBank = C.Pieces.Banked30.Bank.Degrees
		local wantDrop = C.Pieces.Banked30.Height.Drop
		check(
			`the banked 30 reaches {wantBank} degrees of bank, loses its height and arrives level`,
			math.abs(bank.peakBank - wantBank) < 0.5
				and math.abs(bank.drop - wantDrop) < 0.1
				and math.abs(bank.endGrade) < 0.01
				and math.abs(bank.endRoll) < 0.01
				and math.abs(bankFalling.peakBank - wantBank) < 0.5
				and bank.peakTilt <= C.MaxSurfaceTilt + 1e-6
				and bank.peakTilt < WALL_DEGREES - 8,
			string.format(
				"asked for %.0f degrees of bank and reached %.2f, at the apex and not at a socket (it leaves at %.2f of roll); lost %.2f studs of the %.0f it asked for and hands on %+.3f deg. Steepest surface on it %.2f deg, normal Y %.4f against the %.2f that reads as a wall. Arriving on a descent it still reaches %.2f",
				wantBank,
				bank.peakBank,
				bank.endRoll,
				bank.drop,
				wantDrop,
				bank.endGrade,
				bank.peakTilt,
				math.cos(math.rad(bank.peakTilt)),
				WALL_NORMAL_Y,
				bankFalling.peakBank
			)
		)

		-- THE STACK IS TWO HAIRPINS, OPPOSITE HANDS: it comes out pointing the way it went
		-- in, having moved four radii sideways, and it has dropped hard doing it.
		local R = C.Pieces.HairpinStack.Radius
		local turned = math.deg(angleGap(stack.piece.start.yaw, stack.piece.finish.yaw))
		local across = math.sqrt((stack.piece.finish.x - stack.piece.start.x) ^ 2 + (stack.piece.finish.z - stack.piece.start.z) ^ 2)
		-- The two bends must genuinely go opposite ways, which is the difference between a
		-- stack and one very long corner: the heading swings a full half-turn each way.
		local swing = 0
		for _, n in stack.piece.nodes do
			swing = math.max(swing, math.deg(angleGap(n.yaw, stack.piece.start.yaw)))
		end
		check(
			"the hairpin stack is two hairpins the opposite way, and it drops hard",
			turned < 0.5 and math.abs(across - 4 * R) < 1 and swing > 179
				and math.abs(stack.drop - C.Pieces.HairpinStack.Height.Drop) < 0.1
				and math.abs(stack.endGrade) < 0.01,
			string.format(
				"%.0f studs of road: the heading swings %.1f deg away from where it started and comes back to within %.2f of it, and the piece ends %.1f studs sideways (four radii is %.0f). It loses %.1f studs and arrives level (%+.3f deg), steepest %.2f deg",
				stack.piece.length,
				swing,
				turned,
				across,
				4 * R,
				stack.drop,
				stack.endGrade,
				stack.peakGrade
			)
		)

		-- THE CORKSCREW'S ENTRY IS THE GRADE IT ARRIVED AT, EXACTLY -- which is what makes
		-- it a flat entry after anything level, and a crest after a link -- and it hands on
		-- a descent for the rest of the road to carry.
		local wantEnd = C.Pieces.Corkscrew.Height.EndGrade
		check(
			"the corkscrew enters at the grade it arrived at and hands on a descent",
			math.abs(cork.startGrade) < 1e-9
				and math.abs(corkFalling.startGrade + 5) < 1e-9
				and math.abs(cork.endGrade - wantEnd) < 0.01
				and math.abs(corkFalling.endGrade - wantEnd) < 0.01
				and math.abs(cork.drop - C.Pieces.Corkscrew.Height.Drop) < 0.1,
			string.format(
				"from a level socket it starts at %.2e deg -- flat -- steepens to %.2f and hands on %+.2f, having lost %.1f studs over %.0f. From a 5-degree descent it starts at exactly %+.2f and hands on the same %+.2f",
				cork.startGrade,
				cork.peakGrade,
				cork.endGrade,
				cork.drop,
				cork.piece.length,
				corkFalling.startGrade,
				corkFalling.endGrade
			)
		)
		check("what the four touge pieces do, placed on a level socket", true, table.concat(lines, " | "))
	end

	----------------------------------------------------------------------------
	-- 1g. The road is a band, not a ramp (T-068)
	----------------------------------------------------------------------------
	-- THE ONE NUMBER THAT CANNOT BE READ OFF A PIECE. A piece with no height profile
	-- carries the grade it arrived at, so the road's height is a state machine with four
	-- inputs, and where it ends up after two hundred pieces is a property of the SET and of
	-- the generator's bias together. It is also the number the open question in
	-- `features/road-elevation.md` turns on -- is this an endless road or a descent -- so
	-- it is measured and reported rather than asserted tightly.
	do
		local nets, lows, highs = {}, {}, {}
		local steepest, steepestId = 0, "?"
		local longestDescent = 0
		for _, seed in SEEDS do
			local run = longRun(seed, PROFILE_RUN)
			local low, high, here = 0, 0, 0
			for _, piece in run do
				for _, node in piece.nodes do
					low = math.min(low, node.y)
					high = math.max(high, node.y)
					local tilt = math.deg(math.acos(math.clamp(math.cos(node.pitch) * math.cos(node.bank), -1, 1)))
					if tilt > steepest then
						steepest, steepestId = tilt, piece.id
					end
				end
				if (piece.finish.pitch :: number) < -1e-6 then
					here += 1
					longestDescent = math.max(longestDescent, here)
				else
					here = 0
				end
			end
			table.insert(nets, run[#run].finish.y :: number)
			table.insert(lows, low)
			table.insert(highs, high)
		end
		local net, low, high = 0, 0, 0
		for i = 1, #nets do
			net += nets[i] / #nets
			low += lows[i] / #lows
			high += highs[i] / #highs
		end
		local rose = true
		for _, h in highs do
			rose = rose and h > 20 -- every seed gets above where it started, somewhere
		end
		check(
			"the road is a band that trends downhill, and never only downhill",
			net < 0 and rose and low < -100 and steepest <= C.MaxSurfaceTilt + 1e-6 and steepest < WALL_DEGREES - 8,
			string.format(
				"%d seeds x %d pieces: net %+.0f studs on average (%+.1f a piece), lowest %+.0f, highest %+.0f -- a band %.0f studs deep, and every seed climbs above its own start. Longest unbroken descent %d pieces. Steepest surface anywhere %.2f deg on a %s, against the %.0f lid and the %.1f that reads as a wall",
				#SEEDS,
				PROFILE_RUN,
				net,
				net / PROFILE_RUN,
				low,
				high,
				high - low,
				longestDescent,
				steepest,
				steepestId,
				C.MaxSurfaceTilt,
				WALL_DEGREES
			)
		)
	end

	----------------------------------------------------------------------------
	-- 1h. A seam between two slabs is a wedge, and as small as a flat box allows (T-066)
	----------------------------------------------------------------------------
	-- The long version is beside `seamSweep`. In one line: the road is continuous down
	-- its centre line, the step at the kerb is forced by the geometry and the builder is
	-- already at the floor, so these three checks exist to say if any of that stops being
	-- true -- a change that moves the step is a change that moved the surface.
	do
		local s = seamSweep(SEAM_SEED, SEAM_PIECES)
		check(
			"a seam is a wedge, not a step: the road is continuous down its centre line",
			s.centre <= SEAM_CENTRE_TOLERANCE,
			string.format(
				"seed %d x %d pieces (%d profiled), %d seams: worst riser on the CENTRE LINE %.4f studs (lid %.2f), against %.4f at the kerb. A slab's top face passes through both of its end nodes, so there is no sagitta along the road and nothing to take out there",
				SEAM_SEED,
				SEAM_PIECES,
				s.profiled,
				s.seams,
				s.centre,
				SEAM_CENTRE_TOLERANCE,
				s.kerbWorst
			)
		)
		check(
			"and the step at the kerb is the cross-slope the geometry forces, and no more",
			s.kerbWorst <= s.kerbPredicted * 1.05 + 0.002 and s.sumKerb <= s.sumPredicted * 1.05,
			string.format(
				"worst %.4f studs at %s against %.4f predicted from the nodes alone (%.1f%%); over all %d seams %.2f measured against %.2f predicted (%.1f%%). Median %.4f, p90 %.4f. IF THIS FAILS THE BUILDER HAS STOPPED SPREADING THE TOTAL EVENLY, which is the only thing it can do about this: see `seamSweep`",
				s.kerbWorst,
				s.kerbAt,
				s.kerbPredicted,
				100 * s.kerbWorst / math.max(s.kerbPredicted, 1e-9),
				s.seams,
				s.sumKerb,
				s.sumPredicted,
				100 * s.sumKerb / math.max(s.sumPredicted, 1e-9),
				s.kerbMedian,
				s.kerbP90
			)
		)
		check(
			"the barriers do not have it: they are two studs wide, not fifty",
			s.barrier <= SEAM_BARRIER_TOLERANCE,
			string.format(
				"worst riser on a wall's top, over its own width, %.4f studs (lid %.2f) against %.4f on the road. The defect scales with the distance out from the centre of the box, and a wall's is 1 stud",
				s.barrier,
				SEAM_BARRIER_TOLERANCE,
				s.kerbWorst
			)
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
		local stoppedAt = ""
		for _, seed in { 1234, 7 } do
			local a = longRun(seed, 200)
			local b = longRun(seed, 200)
			-- A SEED THAT BOXES ITSELF IN IS STILL THE SAME ROAD TWICE, and it must not
			-- read here as non-determinism: both runs stop at the same piece because
			-- they are the same road. What this check is about is whether they AGREE,
			-- so it compares as far as they both go and holds them to the same length.
			if #a ~= #b then
				same = false
				firstDifference = `seed {seed}: one run is {#a} pieces and the other {#b}`
			elseif #a < 200 then
				stoppedAt ..= `seed {seed} boxed itself in at piece {#a}, identically both times; `
			end
			for i = 1, math.min(#a, #b) do
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
			if same
				then "two seeds, 200 pieces each, identical by variant and by position. " .. stoppedAt
				else firstDifference
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
	-- 5b. The hard piece is gated
	----------------------------------------------------------------------------
	-- `minPieces` is how far into a run a piece may first appear, and the hairpin is the
	-- only piece that has one: it is the piece that stops the car dead, and it must not
	-- be the second thing a player ever meets. Nothing enforced this in step 1, because
	-- both pieces then were ungated.
	do
		local gates = {}
		for _, id in Pieces.order() do
			local m = Pieces.get(id).minPieces
			if m > 0 then
				gates[id] = m
			end
		end
		local worst, worstId, earliest = math.huge, "?", {}
		local tooEarly = 0
		for _, seed in SEEDS do
			local run = longRun(seed, LONG_RUN)
			for _, piece in run do
				local gate = gates[piece.id]
				if gate then
					if piece.n <= gate then
						tooEarly += 1
					end
					if not earliest[piece.id] or piece.n < earliest[piece.id] then
						earliest[piece.id] = piece.n
					end
				end
			end
		end
		local lines = {}
		for id, gate in gates do
			local first = earliest[id]
			table.insert(lines, `{id} (gate {gate}) first appeared at piece {tostring(first)}`)
			if first and first < worst then
				worst, worstId = first, id
			end
		end
		check(
			"the gated pieces never appear before their minPieces",
			tooEarly == 0 and next(gates) ~= nil,
			`{#SEEDS} seeds x {LONG_RUN} pieces, {tooEarly} appearances too early; earliest of all was {worstId} at piece {if worst == math.huge then "never" else tostring(worst)}. {table.concat(lines, "; ")}`
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
		-- BOTH PARTS BELOW RUN ON THE FLAT NINE (T-068), and that is a statement about what
		-- they test rather than a dodge. They are about the LOOKAHEAD -- that a piece which
		-- is legal now and traps the road later is declined -- and the example has to be a
		-- pinned seed and a pinned piece number for the check to be cheap and deterministic.
		-- Every one of those pins is a fact about the piece set that laid it, so adding
		-- seven variants moves the trap somewhere else and the pin stops being an example of
		-- anything. The mechanism is the same whatever is in the set; the example is not.
		withFlatSetOnly(function()
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

		-- Part two, and the point of the exercise: a piece that is LEGAL ONE DEEP -- it
		-- crosses nothing at all -- but after which there is nothing to place. A
		-- generator that checked one piece ahead would take it and be stuck on the very
		-- next one; this one refuses it and goes elsewhere.
		--
		-- FOUND BY SEARCH, NOT BY HAND, over 40 seeds and every head from piece 10 to 60
		-- (the search is in this file's history; the answer is pinned here so the check
		-- is cheap and deterministic). Step 2's version of this check used a ring of four
		-- 220-radius corners, whose fourth piece used to be legal one deep; at 50 studs
		-- wide it is not -- its footprint reaches into the first corner's -- so the ring
		-- stopped being an example of the thing and this replaced it.
		local TRAP_SEED, TRAP_AT, TRAP_ID = 1, 14, "ChicaneL"
		local grown = Generator.new(TRAP_SEED)
		local grewClean = true
		for _ = 1, TRAP_AT do
			grewClean = grewClean and grown:grow() ~= nil
		end
		local trap = Pieces.place(Pieces.get(TRAP_ID), grown.next, TRAP_AT + 1)
		local legalOneDeep = true
		for n = 1, TRAP_AT do
			legalOneDeep = legalOneDeep and not Pieces.overlap(trap, grown:piece(n))
		end
		-- Forced in, it is a dead end: nothing at all is legal after it.
		local trapped = Generator.new(TRAP_SEED)
		for _ = 1, TRAP_AT do
			trapped:grow()
		end
		trapped:DebugForce(TRAP_ID)
		local afterTrap = trapped:grow()
		-- Left to itself, the generator takes something else, and that something crosses
		-- nothing either.
		local chosen = grown:grow()
		local crossed = false
		if chosen then
			for n = 1, TRAP_AT do
				crossed = crossed or Pieces.overlap(chosen, grown:piece(n))
			end
		end
		check(
			"a piece that is legal now but traps the road later is declined",
			grewClean and legalOneDeep and afterTrap == nil and chosen ~= nil and chosen.id ~= TRAP_ID and not crossed,
			`on the flat nine, {TRAP_AT} pieces into seed {TRAP_SEED}, a {TRAP_ID} crosses nothing one piece deep ({legalOneDeep}) and leaves {if afterTrap then afterTrap.id else "nothing at all"} legal after it. The generator placed {if chosen then chosen.id else "nothing"} instead, crossing anything: {crossed}. Two warnings in the log are this check and the one above it, and are expected`
		)
		end)
	end

	----------------------------------------------------------------------------
	-- 7. The search never stops the server (T-052)
	----------------------------------------------------------------------------
	-- The defect this replaced: the lookahead ran the whole depth-first search inside one
	-- call and the worst one measured was 922 ms on seed 7 at 35 studs wide, 1 422 ms at
	-- the 50 the game ships -- the entire server stopped, every car's replication with
	-- it, while a car doing 110 studs/s was mid-corner. Everything here is about that
	-- number, so every one of these checks reports milliseconds.
	do
		local SPEED = 145 -- studs/s, held: faster than the drive has ever measured the car
		local ALLOW = C.SearchMillisUrgent + 2 -- the stated budget, plus the overrun one
		-- step past the check can cost

		-- (a) THE HEADLINE. Five hundred pieces, driven, every call timed.
		local worstOfAll, worstSeed, worstPiece = 0, 0, 0
		local meanOfAll, callsOfAll, leastAhead, dry = 0, 0, math.huge, 0
		local relaxed, stalls = 0, 0
		local rows = {}
		for _, seed in SEEDS do
			local r = drivenRun(seed, LONG_RUN, SPEED)
			callsOfAll += r.calls
			meanOfAll += r.mean * r.calls
			if r.worst > worstOfAll then
				worstOfAll, worstSeed, worstPiece = r.worst, seed, r.worstAt
			end
			leastAhead = math.min(leastAhead, r.leastAhead)
			dry += r.dryTicks
			relaxed += r.gen.relaxed
			if r.gen.stalled then
				stalls += 1
			end
			table.insert(rows, string.format("seed %d reached %d, worst %.2f ms", seed, r.reached, r.worst))
			task.wait()
		end
		check(
			`no call into the generator takes longer than {ALLOW} ms`,
			worstOfAll <= ALLOW and stalls == 0,
			string.format(
				"%d seeds x %d pieces driven at %d studs/s through the service's own tick: %d calls, mean %.3f ms, WORST %.2f ms (seed %d, piece %d). Was 1 422 ms before T-052, at this width. %d stalled, %d pieces placed on short proof. %s",
				#SEEDS,
				LONG_RUN,
				SPEED,
				callsOfAll,
				meanOfAll / math.max(callsOfAll, 1),
				worstOfAll,
				worstSeed,
				worstPiece,
				stalls,
				relaxed,
				table.concat(rows, "; ")
			)
		)

		-- (b) AND THE ROAD IS NEVER SHORT. The window is ten pieces; this is how close
		-- the car ever got to the end of it, over the same runs.
		check(
			"the car never catches the end of the road",
			leastAhead >= 1 and dry == 0,
			`the closest the car came to the end of the road was {leastAhead} pieces, over {callsOfAll} ticks; {dry} of them had no road past the car at all`
		)

		-- (c) SLICING CANNOT CHANGE THE ROAD, which is the property the whole design
		-- turns on and the one that is not negotiable. The same seed is generated four
		-- ways: all at once (`grow`, which never stops mid-search), in windows of three
		-- and of thirty-seven pieces, and -- the one that matters -- with `pump` chopping
		-- the search into slices far shorter than one piece takes, so almost every piece
		-- is decided across several interruptions.
		local function viaGrow(seed: number, n: number)
			local g = Generator.new(seed)
			local out = {}
			for i = 1, n do
				local p = g:grow()
				if not p then
					break
				end
				out[i] = p
			end
			return out
		end
		local function viaWindow(seed: number, n: number, chunk: number)
			local g = Generator.new(seed)
			local out = {}
			local target = 0
			while g.last < n do
				local before = g.last
				target = math.min(math.max(target + chunk, g.last + 1), n)
				g:extendTo(target)
				for i = before + 1, g.last do
					out[i] = g:piece(i)
				end
				if g.last == before and g.stalled then
					break
				end
			end
			return out
		end
		local function viaInterrupted(seed: number, n: number, millis: number)
			local g = Generator.new(seed)
			local out = {}
			while g.last < n do
				g:pump(millis) -- stop the search somewhere arbitrary
				local before = g.last
				g:extendTo(g.last + 1 + C.AheadPieces)
				for i = before + 1, g.last do
					out[i] = g:piece(i)
				end
				if g.last == before and g.stalled then
					break
				end
			end
			return out
		end
		local function firstDifference(a, b): string?
			for i = 1, math.min(#a, #b) do
				local gap = socketGap(a[i].start, b[i].start)
				if a[i].id ~= b[i].id or gap > SOCKET_TOLERANCE then
					return `piece {i}: {a[i].id} vs {b[i].id}, {gap} studs apart`
				end
			end
			if #a == 0 or #b == 0 then
				return "one of them generated nothing"
			end
			return nil
		end
		local sliceWord, sliced = "", 0
		for _, seed in { 8080, 1013, 1234, 7 } do
			local base = viaGrow(seed, 150)
			local ways = {
				[`windows of 3`] = viaWindow(seed, 150, 3),
				[`windows of 37`] = viaWindow(seed, 150, 37),
				[`interrupted every 0.02 ms`] = viaInterrupted(seed, 150, 0.02),
				[`interrupted every 0.4 ms`] = viaInterrupted(seed, 150, 0.4),
			}
			for name, road in ways do
				sliced += 1
				local diff = firstDifference(base, road)
				if diff and sliceWord == "" then
					sliceWord = `seed {seed}, {name}: {diff}`
				end
			end
			task.wait()
		end
		check(
			"the same seed gives the same road however the search was sliced",
			sliceWord == "",
			if sliceWord == ""
				then `4 seeds x 150 pieces, generated {sliced // 4} ways each including a search interrupted every 0.02 ms -- identical by variant and by position`
				else sliceWord
		)

		-- (d) THE CAR OUTRUNNING THE SEARCH. The window is what buys the search its time,
		-- so take the window away entirely: the car is told to be standing on the LAST
		-- piece of the road, every single tick, for two hundred pieces. That is the state
		-- `MinAheadPieces` exists for and the one place the generator is allowed past its
		-- slice, so this measures what that costs as well as proving it never comes back
		-- empty-handed. It cannot be reached in play -- check (b) above measures the car
		-- never getting closer than three pieces to the end -- but it is what happens if
		-- it ever is.
		local FORCED_ALLOW = 250 -- ms: the node budget's worth of search in one call, which
		-- is this path's whole bound. It was 150 when the budget was 2 000 and the set was
		-- nine variants and the worst measured was 74 ms; the sixteen-variant set at a
		-- budget of 2 500 measures 162 (T-068). Both of those numbers are a quarter of a
		-- second of server inside a path that needs the road to have ALREADY run out under
		-- the car, which check (b) above measures never getting closer than two pieces to.
		local sprint = Generator.new(60606)
		local missed, worstSprint, emptyAt = 0, 0, 0
		for _ = 1, 200 do
			local before = sprint.last
			local t0 = os.clock()
			sprint:extendTo(sprint.last + C.AheadPieces) -- the car IS the head of the road
			worstSprint = math.max(worstSprint, (os.clock() - t0) * 1000)
			if sprint.last == before then
				missed += 1
				if emptyAt == 0 then
					emptyAt = before
				end
			end
			task.wait()
		end
		check(
			"a car that outruns the search still gets road",
			missed == 0 and sprint.last >= 200 and worstSprint <= FORCED_ALLOW,
			string.format(
				"200 ticks with the car on the last piece of the road every one of them: %d pieces placed, %d calls came back empty%s, worst call %.2f ms against the %d ms the node budget allows this path, %d calls forced past the slice, %d pieces placed on short proof",
				sprint.last,
				missed,
				if emptyAt == 0 then "" else ` (first at piece {emptyAt})`,
				worstSprint,
				FORCED_ALLOW,
				sprint.forcedCalls,
				sprint.relaxed
			)
		)

		-- (e) RECOVERY. The plan backtracks into road it has decided but not built, which
		-- is the thing step 2 could not do at all. This drives twenty seeds four hundred
		-- pieces to count how often the road still boxes itself in completely.
		local boxed, earliest, totalPieces, totalRelaxed, leastProof = 0, math.huge, 0, 0, math.huge
		for seed = 1, 20 do
			local run, g = longRun(seed * 1013, 400)
			totalPieces += #run
			totalRelaxed += g.relaxed
			leastProof = math.min(leastProof, g.worstProof)
			if #run < 400 then
				boxed += 1
				earliest = math.min(earliest, #run)
			end
			task.wait()
		end
		check(
			"the road recovers rather than stopping",
			boxed <= 2 and totalPieces >= 20 * 400 * 0.97,
			string.format(
				"20 runs of 400 pieces at %d studs wide: %d boxed themselves in (earliest at piece %s), %d of 8 000 pieces placed, %d of them on short proof, the least proof any piece was placed on was %s of %d",
				C.Width,
				boxed,
				if earliest == math.huge then "-" else tostring(earliest),
				totalPieces,
				totalRelaxed,
				if leastProof == math.huge then "-" else tostring(leastProof),
				C.LookAhead
			)
		)
	end

	----------------------------------------------------------------------------
	-- 8. Progress
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
	-- 9. The window, with real parts in it
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
	-- 10. Every part is drivable ground, and nothing in it is physics
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

		-- A ray straight down finds road, every time, AND THE ROAD IS WHERE THE PIECE SAYS
		-- IT IS. This used to compare the hit against `SurfaceY`, which was right while the
		-- whole road was flat and is a lie now that it climbs and banks (T-068). What it
		-- compares against instead is `Pieces.poseAt`, which is the one thing in the game
		-- that answers "where is the surface of this piece" -- the same call `SafeStart`,
		-- the respawn and every centre-line mark go through -- so this is now a check that
		-- the BUILT road and the piece AGREE, across a profile, which is strictly more than
		-- it checked before. The sample point is the pose pushed sideways along the
		-- surface's own banked right, so on a 15-degree bank it is 6.5 studs higher at one
		-- edge than the other and the ray still has to land on it.
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
					local want = cf.Position + cf.RightVector * lateral
					local from = want + Vector3.new(0, 20, 0)
					local hit = workspace:Raycast(from, Vector3.new(0, -60, 0), params)
					if not hit then
						misses += 1
					else
						worstY = math.max(worstY, math.abs(hit.Position.Y - want.Y))
						if not CollectionService:HasTag(hit.Instance, D.SurfaceTag) then
							wrongTag += 1
						end
					end
				end
			end
		end
		-- THREE TENTHS OF A STUD, not a thousandth, and the slack is the profile's. Two
		-- things make it, both of them `Builder`'s and both deliberate: a segment's box is
		-- square to the AVERAGE of its two ends' ups, so where the surface is twisting the
		-- box's top face is a plane through a curve; and every box is lengthened past its
		-- own segment (`OVERLAP`, and the widening a curve needs) so no joint can show a
		-- hairline, which means a ray near a node lands on the neighbour's overhang. Worst
		-- measured across the whole generated window, at both edges of a banked road and
		-- down the centre line: 0.148 studs, against a ride height of 2.4.
		local RAY_SLACK = 0.3
		check(
			"a ray down anywhere on the road finds tagged road where the piece says it is",
			misses == 0 and wrongTag == 0 and worstY < RAY_SLACK,
			string.format(
				"%d rays over %d pieces, at both edges and the centre line: %d missed, %d hit something untagged, worst %.5f studs off where `Pieces.poseAt` puts the surface (slack %.2f)",
				samples,
				#RoadService:DebugPieces(),
				misses,
				wrongTag,
				worstY,
				RAY_SLACK
			)
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
	-- 10b. A car put down on a pitched, banked piece (T-066)
	----------------------------------------------------------------------------
	-- The one thing a pure check cannot answer: where the PARTS ended up, and what four
	-- rays fired down at the wheels find there. `SafeStart`, `JoinCFrame` and the respawn
	-- all come through `Pieces.poseAt`, so this asks it for a pose on a profiled piece,
	-- stands the car's four wheels on it, and measures.
	do
		local restore = useProfilePieces({ "Plunge", "Swoop", "Horrible" })
		local ok, err = pcall(function()
			-- A chain by hand rather than a seed, so the check is about these pieces.
			local chain, socket = {}, { x = 0, z = 0, yaw = 0 }
			for i, id in { "Straight", "Plunge", "SwoopL", "HorribleR", "Straight" } do
				chain[i] = Pieces.place(Pieces.get(id), socket, i)
				socket = chain[i].finish
			end
			local holder = Instance.new("Folder")
			holder.Name = "ProfileProbe"
			holder.Parent = workspace
			Builder.DebugResetMarks()
			for _, piece in chain do
				Builder.build(piece, holder)
			end

			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { holder }

			local WHEELS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } -- front/rear, right/left
			local halfBase, halfTrack = D.Wheelbase * 0.5, D.TrackWidth * 0.5
			local misses, worstRide, worstNormal, worstThrough = 0, 0, 0, math.huge
			local samples, rows = 0, {}
			for _, piece in { chain[3], chain[4] } do
				local pieceWorstRide, pieceWorstNormal, pieceTilt = 0, 0, 0
				for s = 1, 19 do
					local cf = Pieces.poseAt(piece, s / 20, C.SurfaceY + D.RideHeight)
					local _, pitch, bank = Pieces.surfaceAt(piece, s / 20)
					pieceTilt = math.max(pieceTilt, math.deg(math.acos(math.clamp(math.cos(pitch) * math.cos(bank), -1, 1))))
					local mean = Vector3.zero
					for _, w in WHEELS do
						samples += 1
						local at = cf.Position + cf.LookVector * (halfBase * w[1]) + cf.RightVector * (halfTrack * w[2])
						local hit = workspace:Raycast(at + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), params)
						if not hit then
							misses += 1
						else
							-- How far the wheel is off the road MEASURED ALONG THE ROAD'S
							-- OWN NORMAL, which is the number that says "on it" rather
							-- than "through it" or "floating".
							local ride = (at - hit.Position):Dot(hit.Normal)
							pieceWorstRide = math.max(pieceWorstRide, math.abs(ride - D.RideHeight))
							worstThrough = math.min(worstThrough, ride)
							mean += hit.Normal
						end
					end
					-- THE MEAN OF THE FOUR, because that is what the car reads: the drift
					-- model averages its four wheel rays and leans the body on the answer
					-- (`Drift/Model`, "the ground"). One wheel against the pose's own
					-- point on the centre line is a different question and a worse one --
					-- the car is 14.8 studs long, so on a piece cut into 3-stud boxes its
					-- wheels are two facets away from its middle and read as much.
					if mean.Magnitude > 1e-6 then
						pieceWorstNormal =
							math.max(pieceWorstNormal, math.deg(math.acos(math.clamp(mean.Unit:Dot(cf.UpVector), -1, 1))))
					end
				end
				worstRide = math.max(worstRide, pieceWorstRide)
				worstNormal = math.max(worstNormal, pieceWorstNormal)
				table.insert(
					rows,
					string.format(
						"%s (leaning up to %.1f deg): every wheel within %.3f studs of ride height, the pose's up within %.2f deg of the four rays' mean normal",
						piece.id,
						pieceTilt,
						pieceWorstRide,
						pieceWorstNormal
					)
				)
			end

			holder:Destroy()
			Builder.DebugResetMarks()
			-- WHAT THE TWO TOLERANCES ARE. The pose is read off the SMOOTH profile and the
			-- road is built out of FLAT BOXES, so the two can only agree to within half a
			-- segment's worth of step: a quarter of a stud of height and a degree or so of
			-- lean. Anything larger than that is not faceting, it is a car in the road or
			-- above it.
			check(
				"a car put down on a pitched, banked piece stands on it",
				misses == 0 and worstRide < 0.25 and worstNormal < 2 and worstThrough > 0,
				string.format(
					"%d wheel rays over a banked descent and a banked 120-degree corner: %d found nothing, every wheel between %.3f and %.3f studs off the surface along its normal (ride height is %.2f), and the pose's up never more than %.2f deg off the mean of the four. %s",
					samples,
					misses,
					worstThrough,
					D.RideHeight + worstRide,
					D.RideHeight,
					worstNormal,
					table.concat(rows, "; ")
				)
			)
		end)
		restore()
		if not ok then
			error(err, 0)
		end
	end

	----------------------------------------------------------------------------
	-- 11. A car can actually drive it
	----------------------------------------------------------------------------
	if opts.skipDrive ~= true then
		local r = Tests:drive({ seed = opts.driveSeed or 8080, pieces = DRIVE_PIECES })
		driveReport = r.detail
		check(`a car drives {DRIVE_PIECES} generated pieces`, r.reached >= DRIVE_PIECES, driveReport)
		check(
			"never airborne, never off the road, never backwards",
			r.airSteps == 0 and r.offRoadSteps == 0 and r.backwardsSteps == 0,
			driveReport
		)

		-- BEING STUCK IS ITS OWN CHECK NOW, AND IT HAS A BUDGET RATHER THAN A ZERO (T-068).
		-- This used to be `stuckSeconds < 1` and it was true for as long as the road was
		-- flat. The banked corner ships at 10 degrees -- the user's call on 2026-11-06,
		-- made knowing this number -- and with gravity acting along the ground the car
		-- slides down the bank into the barrier and the autopilot cannot get it off:
		-- 50 pieces, seed 8080, it spends 40.2 s stuck. Nothing that stops it is road;
		-- it reaches all 50 pieces, never leaves the road and is never airborne, which is
		-- why those three stay at zero above.
		--
		-- SIXTY, so it still fails if this gets worse. The measured ladder is 0.5 s at 5
		-- degrees of bank, 11.9 at 8, 40.2 at 10 and 113.8 at 15, so 60 is clear of the
		-- shipped number and nowhere near the next one up. A real driver carries more
		-- speed in and steers out of a wall; the autopilot does neither, so this is the
		-- worst case and not what the game feels like.
		--
		-- THE WAY BACK TO ZERO IS NOT A SMALLER BANK. It is a car that can unstick itself
		-- from a wall, which is its own task; with that, this goes back to being tight and
		-- the bank goes to the 30 the spec asks for.
		check(
			`stuck for under {STUCK_BUDGET} s across the drive`,
			r.stuckSeconds < STUCK_BUDGET,
			driveReport
		)

		-- And it drove ALL OF THEM. A 50-piece drive that happened to meet no hairpin
		-- would pass both checks above while proving nothing about the hairpin, so the
		-- drive is also asked which pieces it actually met, and what it did on each.
		local missing, lines = {}, {}
		local kinds = {}
		for _, id in Pieces.order() do
			kinds[Pieces.get(id).kind] = true
		end
		for kind in kinds do
			if not r.byKind[kind] then
				table.insert(missing, kind)
			else
				table.insert(lines, `{kind}: {kindRow(r, kind)}`)
			end
		end
		table.sort(lines)
		check(
			"every piece type turns up in the drive, and the car gets round all of them",
			#missing == 0,
			`{if #missing == 0 then `all {#lines} met` else "never met: " .. table.concat(missing, ", ")}. ` .. table.concat(lines, " | ")
		)

		-- AND THE DELIBERATELY HORRIBLE PIECE IS DRIVEN (T-066). Steep, banked, both
		-- changing down its length, and nothing else in the road but straights to reach it
		-- from, so every corner the car meets is that piece.
		--
		-- WHAT IS BEING ASKED IS NOT WHETHER THE AUTOPILOT IS QUICK ON IT. It is not: the
		-- test driver was tuned on a flat road, and a car that carries more speed down a
		-- hill runs wider than it can steer for. What is being asked is whether any of
		-- that road ever reads as a WALL -- `Drift/World` stops the car dead against
		-- anything leaning more than about 46 degrees, and grade and bank compound -- so
		-- every sweep that stopped the car is traced back to the part that stopped it.
		-- Barriers are meant to stop it. Road is not, ever.
		-- THE BANK HOLDS THE CAR, AS A NUMBER (T-068). The showcase piece's whole claim is
		-- that you carry speed through it because the bank is holding you, and the only
		-- honest way to show that is the same road twice: the same seed, the same entry
		-- speed, the same corners, with `Bank.Degrees` as it ships and at 0. Everything
		-- else -- the radius, the arc, the drop -- is identical, so the difference IS the
		-- bank.
		--
		-- IT IS ENTERED FAST ON PURPOSE. A banked corner has a minimum speed
		-- (`Config/Road`, `Banked30`): below `sqrt(radius x Gravity x tan(bank))` the bank
		-- is pulling the car down the slope faster than the corner is pushing it up, and
		-- what the bank does then is hold it DOWN rather than hold it on. So this starts
		-- the car at 90 studs/s, well above the 37 the shipped bank needs, which is the
		-- state the piece is designed for and the state the claim is about.
		--
		-- AND WHAT IT ASSERTS IS THAT THE BANK COSTS NOTHING, not that it is faster. At the
		-- 5 degrees this ships with -- a road's superelevation, chosen because more of it
		-- pins the test autopilot against a barrier, see `Config/Road` -- the difference
		-- between banked and flat is small and the two rows are printed side by side so it
		-- can be read rather than claimed. THE USER'S DRIVE DECIDES WHETHER IT FEELS LIKE
		-- ANYTHING.
		do
			local wasMin = setOnly({ "Banked30" })
			local ok, err = pcall(function()
				local rows = {}
				for _, degrees in { C.Pieces.Banked30.Bank.Degrees, 0 } do
					local was = applySet({ Banked30 = { Bank = { Degrees = degrees, Shape = "crest" } } })
					Pieces.rebuild()
					local d = Tests:drive({ seed = 1717, pieces = 12, seconds = 150, startSpeed = 90 })
					restoreSet(was)
					Pieces.rebuild()
					table.insert(rows, { degrees = degrees, r = d, k = d.byKind.Banked30 })
				end
				local banked, flat = rows[1], rows[2]
				check(
					"the bank holds the car through the banked 30",
					banked.k ~= nil
						and flat.k ~= nil
						and banked.k.off == 0
						and banked.r.offRoadSteps == 0
						and banked.r.stuckSeconds < 1
						and banked.k.minSpeed > 20,
					string.format(
						"the same seed and the same corner, entered at 90 studs/s, banked %d degrees and flat. BANKED: %s. FLAT: %s",
						banked.degrees,
						kindRow(banked.r, "Banked30"),
						kindRow(flat.r, "Banked30")
					)
				)
			end)
			restoreMinPieces(wasMin)
			Pieces.rebuild()
			if not ok then
				error(err, 0)
			end
		end

		local restore = useProfilePieces({ "Horrible" }, { "Horrible" })
		local ok, err = pcall(function()
			local h = Tests:drive({ seed = 4242, pieces = 12, seconds = 120, startSpeed = 40, wallParts = true })
			-- WHAT IS NOT ASSERTED, AND WHY. How far the autopilot gets, and how long it
			-- spends stopped, are NOT the road's answer to give. A car that ends up
			-- against the outside wall of a descending banked corner is held there by the
			-- gravity T-065 added, and the test driver steers in proportion to its speed,
			-- so it cannot turn away from a standstill. In the game a car in that state is
			-- the respawn's problem (`FallBelowSurface`, not built yet). The numbers are
			-- reported because step 4 should see them before it designs pieces.
			check(
				"nothing on the worst piece the limits allow reads as a wall",
				h.roadWalls == 0 and h.offRoadSteps == 0 and h.airSteps == 0 and h.reached >= 5,
				string.format(
					"%d sweeps were stopped by something, and %d of them by ROAD rather than by a barrier. Reached piece %d, and spent %.1f s of %.0f stopped -- pinned against a wall by gravity, not by the road. %s | on the Horrible pieces themselves -- %s",
					h.roadWalls + h.barrierWalls,
					h.roadWalls,
					h.reached,
					h.stuckSeconds,
					h.seconds,
					h.detail,
					kindRow(h, "Horrible")
				)
			)
		end)
		restore()
		if not ok then
			error(err, 0)
		end
	end

	local passed = true
	for _, c in checks do
		passed = passed and c.ok
	end
	return { passed = passed, checks = checks }
end

return Tests
