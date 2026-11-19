--!strict
-- RoadDressing: what stands beside the road, chosen once the road is laid
-- (features/road-dressing.md, T-327). Pure maths: no instances.
--
-- THE ROAD AND ITS DRESSING ARE TWO LAYERS. The planner (`Road/SplineGen`) decides where
-- the road goes and what the car drives on: the centreline, the runoff and its edges, a
-- tight cliff edge's gravel, a grove's widened runoff. This layer then dresses each section
-- the planner has accepted, reading the section and the ground beside it, and writes what
-- stands there: today the crash barriers (`sec.kr`). It reads the road and never writes it,
-- and draws from no stream the planner uses, so nothing here can change a road: every seed
-- lays the same road with or without it, whatever its settings (`Config.Dressing`).
--
-- HOW IT RUNS: `attach(gen)` gives a generator a dresser. The generator calls it for each
-- section it accepts, after the section is final and before it is appended to the road
-- (`SplineGen._commit`), so the barriers travel to the clients inside the section as they
-- always have. The planner's look-ahead (`_fitTurn`) never dresses its previews.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)

local RoadDressing = {}
RoadDressing.__index = RoadDressing

-- The drop beside a section, as `SplineGen.sideDrops` reads it: `u` the points, `k` the
-- curvature there, `drop[side]` how far the ground falls (negative: it rises; -huge where
-- the bend encloses that side).
export type Drops = { u: { number }, k: { number }, drop: { [number]: { number } } }

-- What the dresser needs of the generator: its road so far, and the drop reading.
export type Road = {
	seed: number,
	spline: Spline.Spline,
	sideDrops: (any, Spline.Section, { [number]: number }, any?) -> Drops,
	dress: ((Spline.Section) -> ())?,
}

export type Dresser = typeof(setmetatable(
	{} :: {
		gen: Road,
		-- the dressing's own stream, for the kinds of dressing still to come (signs, posts):
		-- the barriers are placed from the ground and draw nothing from it
		rng: Random,
		-- barriers carrying on into the next section, by side: studs of run-out still owed,
		-- the way a railed bend still turns at the section's end (0 none), and whether that
		-- bend is a tight one (a hairpin: its run-out is `HairpinRunOut`, T-334)
		outL: number,
		outR: number,
		bendL: number,
		bendR: number,
		tightL: boolean,
		tightR: boolean,
	},
	RoadDressing
))

-- Give `gen` a dresser: every section it accepts from now on is dressed before it is laid.
function RoadDressing.attach(gen: Road): Dresser
	local self = setmetatable({
		gen = gen,
		rng = Random.new((gen.seed * 23 + 4127) % 2 ^ 31),
		outL = 0,
		outR = 0,
		bendL = 0,
		bendR = 0,
		tightL = false,
		tightR = false,
	}, RoadDressing)
	gen.dress = function(sec: Spline.Section)
		self:dress(sec)
	end
	return self
end

-- Dress one accepted section, before it is appended: writes its barrier runs (`sec.kr`).
function RoadDressing.dress(self: Dresser, sec: Spline.Section)
	sec.kr = nil
	if sec.tag == "Start" then
		-- the start is never railed, and nothing carries on from it
		self.outL, self.outR, self.bendL, self.bendR = 0, 0, 0, 0
		self.tightL, self.tightR = false, false
		return
	end
	local B = Config.Dressing.Barrier
	local sp = self.gen.spline
	local startRun = { [-1] = sp:runoffRaw(sp.length, -1), [1] = sp:runoffRaw(sp.length, 1) }
	local drops = self.gen:sideDrops(sec, startRun, B)
	local grove: { [number]: boolean } = {}
	if sec.gv then
		for j = 1, #sec.gv, 2 do
			grove[sec.gv[j]] = true
		end
	end
	local pieces = self:_barrierPieces(sec, drops, grove)
	-- A TIGHT CLIFF EDGE (T-181) is the planner's: its gravel is road. Its rail is ours, over
	-- the whole of the gravel, joining any barrier already on that side.
	if sec.gl then
		for j = 1, #sec.gl, 3 do
			local side = sec.gl[j + 2]
			pieces[side] = RoadDressing._joinPiece(pieces[side], sec.gl[j], sec.gl[j + 1])
		end
	end
	local kr: { number } = {}
	for _, side in { -1, 1 } do
		for _, p in pieces[side] do
			table.insert(kr, p[1])
			table.insert(kr, p[2])
			table.insert(kr, side)
		end
	end
	if #kr > 0 then
		sec.kr = kr
	end
end

-- Pieces {a, b} in order, with [a, b] joined in (and any it overlaps).
function RoadDressing._joinPiece(list: { { number } }, a: number, b: number): { { number } }
	local out = {}
	local placed = false
	for _, p in list do
		if p[2] < a - 1e-6 then
			table.insert(out, p)
		elseif p[1] > b + 1e-6 then
			if not placed then
				table.insert(out, { a, b })
				placed = true
			end
			table.insert(out, p)
		else
			a, b = math.min(a, p[1]), math.max(b, p[2])
		end
	end
	if not placed then
		table.insert(out, { a, b })
	end
	return out
end

-- WHERE THE BARRIERS STAND (T-306, features/mountain-road.md "Where the K-rails stand").
-- Each side on its own, from the drop beside it; no random draw:
--   * a rail only ever stands where the ground falls away (`FallDrop`): the downhill side,
--     never against a rising bank;
--   * A CORNER (tighter than `CornerRadius`, one way) whose outside drops `CornerDrop`
--     anywhere along it is railed the whole way round, from `LeadIn` before it to `RunOut`
--     after;
--   * A TIGHT BEND (tighter than `HairpinRadius`: every hairpin) is railed the same way on
--     EITHER side that drops `HairpinDrop` (a turnaround turns through the drop, so its
--     inside can be the drop). Past its end the rail runs on only `HairpinRunOut`, not
--     `RunOut` (T-334): the user, 2026-11-19, the rail should end where the bend straightens,
--     not carry on into the next turn. A bend tighter than that anywhere is a tight one all
--     the way round, across a section's end too;
--   * anywhere else, a cliff (`CliffDrop`) is railed, with the same lead-in and run-out.
-- What runs past the section's end carries on into the next one (`out*`, and a railed bend
-- still turning there, `bend*`), and joins on: `Spline.append` makes it one run. Pieces
-- shorter than `MinRun` are dropped unless they carry a rail on across an end. Never on a
-- grove's side (the grass it widened is runoff the car may use).
-- Returns each side's pieces, {a, b} in order, and leaves the carry for the next section.
function RoadDressing._barrierPieces(self: Dresser, sec: Spline.Section, drops: Drops, grove: { [number]: boolean }): { [number]: { { number } } }
	local B = Config.Dressing.Barrier
	local us, ks = drops.u, drops.k
	local n = #us
	local len = sec.len
	local kCorner, kTight = 1 / B.CornerRadius, 1 / B.HairpinRadius
	local sp = self.gen.spline
	local out: { [number]: { { number } } } = { [-1] = {}, [1] = {} }
	for _, side in { -1, 1 } do
		local drop = drops.drop[side]
		local runs = if side < 0 then sp.railL else sp.railR
		-- a rail that reaches this section's start, carried on
		local railedIn = #runs.b > 0 and runs.b[#runs.b] >= sp.length - 1e-6
		local carryIn = if railedIn then (if side < 0 then self.outL else self.outR) else 0
		local bendIn = if railedIn then (if side < 0 then self.bendL else self.bendR) else 0
		local tightIn = railedIn and (if side < 0 then self.tightL else self.tightR)
		local windows: { { number } } = {}
		if carryIn > 0 then
			table.insert(windows, { 0, carryIn })
		end
		local bendOut, tightOut = 0, false
		local i = 1
		while i <= n do
			local k = ks[i]
			if math.abs(k) >= kCorner then
				local dir = if k > 0 then 1 else -1 -- a left turn (k > 0): its outside is the right
				local j, most, tight = i, drop[i], math.abs(k) >= kTight
				while j < n and math.abs(ks[j + 1]) >= kCorner and (ks[j + 1] > 0) == (dir > 0) do
					j += 1
					most = math.max(most, drop[j])
					tight = tight or math.abs(ks[j]) >= kTight
				end
				local carried = i == 1 and bendIn == dir
				tight = tight or (carried and tightIn)
				if carried or (side == dir and most >= B.CornerDrop) or (tight and most >= B.HairpinDrop) then
					table.insert(windows, { us[i] - B.LeadIn, us[j] + (if tight then B.HairpinRunOut else B.RunOut) })
					if j == n then
						bendOut, tightOut = dir, tight
					end
				end
				i = j + 1
			else
				i += 1
			end
		end
		for m = 1, n do
			if drop[m] >= B.CliffDrop then
				table.insert(windows, { us[m] - B.LeadIn, us[m] + B.RunOut })
			end
		end
		local reach = 0
		for _, w in windows do
			reach = math.max(reach, w[2])
		end
		local function wanted(u: number): boolean
			for _, w in windows do
				if u >= w[1] - 1e-6 and u <= w[2] + 1e-6 then
					return true
				end
			end
			return false
		end
		-- the pieces: wanted, and on ground that falls away the whole length
		local allowed = not grove[side]
		local pieces: { { number } } = {}
		local from: number? = nil
		for m = 1, n do
			local on = allowed and drop[m] >= B.FallDrop and wanted(us[m])
			if on and not from then
				from = m
			end
			if from and (not on or m == n) then
				local to = if on then m else m - 1
				local a, b = us[from], us[to]
				local carriesIn = from == 1 and railedIn
				local carriesOut = to == n and reach > len + 1e-6
				if b > a + 1e-6 and (b - a >= B.MinRun or carriesIn or carriesOut) then
					table.insert(pieces, { a, b })
				end
				from = nil
			end
		end
		local last = pieces[#pieces]
		local reachesEnd = last ~= nil and last[2] >= len - 1e-6
		local carryOut = if reachesEnd then math.max(reach - len, 0) else 0
		if side < 0 then
			self.outL, self.bendL, self.tightL = carryOut, if reachesEnd then bendOut else 0, reachesEnd and tightOut
		else
			self.outR, self.bendR, self.tightR = carryOut, if reachesEnd then bendOut else 0, reachesEnd and tightOut
		end
		out[side] = pieces
	end
	return out
end

return RoadDressing
