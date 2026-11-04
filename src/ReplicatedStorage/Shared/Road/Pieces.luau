--!strict
-- Pieces: what a road piece IS, as pure maths. No instances, no Workspace, no service.
--
-- A piece is one length of road with TWO SOCKETS -- a start and an end, each a position
-- and an attitude -- and that is all the joining needs:
--
--   ROTATE THE NEW PIECE ABOUT ITS OWN START SOCKET until that socket matches the
--   previous piece's end socket, THEN TRANSLATE IT INTO PLACE.
--
-- That is the whole join. No splines, no curve fitting, no runtime geometry. Every piece
-- is defined in its own local frame with its start socket at the origin facing -Z, so the
-- road is flush by construction and `place` is one rotation and one addition.
--
-- Angles follow the playground's `Playground/Path`: yaw 0 faces -Z, a POSITIVE angle
-- turns LEFT, and forward(yaw) = (-sin yaw, -cos yaw) in XZ. The two modules are
-- deliberately not shared -- `Path` is server-only, under `ServerScriptService`, and
-- these fifteen lines of trigonometry are cheaper to repeat than to reach for.
--
-- A FOOTPRINT IS NOT WHAT IS DRAWN. It is a flat list of oriented rectangles, one per
-- segment, covering the road and both barriers: deliberately rough and deliberately
-- cheap, because the only question ever asked of it is "do these two overlap".
--
--------------------------------------------------------------------------------
-- THE THIRD DIMENSION (features/road-elevation.md, T-066)
--------------------------------------------------------------------------------
-- A socket is `{ x, y, z, yaw, pitch, roll }`: a point, a heading, a GRADE and a BANK.
-- The join matches all three angles, so a piece that arrives descending and banked
-- leaves the one before it with no step in height, no kink in the grade and no twist in
-- the bank. `y`, `pitch` and `roll` may be left out and read as zero, which is what the
-- generator's very first socket is.
--
-- A PIECE IS STILL DRAWN IN PLAN AND LIFTED AFTERWARDS, which is how a real road is
-- designed and how the playground already does it (`Playground/Build`: nodes in plan,
-- `heightAt(t)` and `bankAt(t)` over the top). `x`, `z` and `yaw` are untouched by any
-- profile, `cum` and `length` stay PLAN arc length, and so the overlap test, the bounding
-- boxes and the lookahead keep working in two dimensions and are not asked to change
-- (`features/road-elevation.md` "The footprint stays two-dimensional, on purpose"). The
-- true surface is longer than `length` by sqrt(1 + grade^2) -- 3.1% at the steepest grade
-- the config allows -- which no reader of either number cares about.
--
-- HEIGHT IS THE INTEGRAL OF THE GRADE, not a curve sampled directly, and that is what
-- makes the limits real rather than hoped for: the grade at each node is clamped to
-- `MaxGrade` and then the height is summed along the piece, so no surface can be steeper
-- than the clamp whatever a piece's profile asks for.
--
-- PITCH PERSISTS, BANK UNWINDS, and neither ever steps at a join. A grade is a state the
-- road is IN -- a piece with no height profile of its own keeps descending at the grade
-- it arrived at, which is what stops a descent being a staircase of ramps -- while a bank
-- belongs to the corner it is in, so a piece with no bank profile eases the bank it
-- arrived with back to level over its own length rather than snapping it to zero.
--
-- WHAT WAS TAKEN FROM `Playground/Build`, which lays banked, height-profiled ribbons
-- today, and where this differs:
--   * `frame(node, y, bank)` -> `Pieces.frame`: the same rotation of the plan right and
--     up vectors by the bank, with a pitch added so the forward tilts up the grade too.
--   * `bankProfile(spec, sign)` -> `bankProfile` below, sign and all: a positive
--     `Degrees` always raises the OUTER edge of the turn.
--   * `heightProfile(spec, from)` -> `gradeAt` below. The playground's shapes each start
--     from a height; a road piece has to start from a GRADE as well, or every join is a
--     crease, so this is a cubic Hermite in height -- the parabolic vertical curve a real
--     road is set out with -- rather than a smoothstep between two heights.
--   * `levelInnerEdge` is NOT taken. It exists to keep a banked ring from burying its
--     inner edge in the playground's plate; the road has no plate, and a carriageway is
--     superelevated about its own centre line, which is what `ribbon` does once that lift
--     is zero.
--   * `ribbon(nodes, opts)` -> the profiled half of `Road/Builder`, including its trick of
--     averaging the two end `up`s and re-squaring the frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Pieces = {}

-- `y`, `pitch` and `roll` are optional because the generator's first socket is written
-- flat; everything `place` hands back carries all six.
export type Socket = {
	x: number,
	z: number,
	yaw: number,
	y: number?, -- studs above `Config.Road.SurfaceY`
	pitch: number?, -- radians, positive climbing
	roll: number?, -- radians, positive raising the road's RIGHT edge
}

export type Node = {
	x: number,
	z: number,
	yaw: number,
	y: number, -- studs above `Config.Road.SurfaceY`
	pitch: number, -- radians; the grade of the surface AT this node
	bank: number, -- radians; positive raises the right edge
}

-- An oriented rectangle on the ground: centre, its long axis, and the half-extent along
-- that axis and across it.
export type Quad = { cx: number, cz: number, ux: number, uz: number, hu: number, hv: number }

-- What a piece does vertically, in the form `place` needs it: `drop` is studs of height
-- it loses, `endGrade` is the grade (dy/ds, not an angle) it hands to the next piece.
-- Either may be absent; both absent is no profile at all.
export type HeightSpec = { drop: number?, endGrade: number? }

export type Variant = {
	id: string, -- `Straight`, `CornerL`, `HairpinR`: the placeable unit
	kind: string, -- `Straight`, `Corner`, `Sweeper`, `Hairpin`, `Chicane`: the piece type
	dir: number, -- +1 left, -1 right, 0 neither
	weight: number,
	minPieces: number,
	radius: number?,
	arcDeg: number?,
	length: number, -- PLAN arc length down the centre
	nodes: { Node }, -- local centre line; nodes[1] is the start socket at the origin
	cum: { number }, -- arc length at each node, cum[1] = 0
	endSocket: Socket, -- plan only: where a piece ENDS vertically depends on where it began
	-- THE SAME SHAPE, CUT FINELY ENOUGH TO CARRY A PROFILE. A flat straight is one segment
	-- however long it is; a straight that has to lose 40 studs of height, or unwind a bank
	-- it arrived with, cannot be -- a single box would be one flat shelf and its two ends
	-- would be steps. So every variant is also built at the spacing its worst legal
	-- profile needs (`MaxPitchStep`, `MaxBankStep`), and `place` picks: the flat set when
	-- the piece has no profile AND arrives level, this one otherwise. That is what keeps
	-- the nine flat pieces exactly the parts they have always been.
	fineNodes: { Node },
	fineCum: { number },
	profiled: boolean, -- it has a height or a bank profile of its own
	height: HeightSpec?,
	bankOwn: (number) -> number, -- its own bank in radians at u (0..1), sign applied
	fineSegments: number, -- how many segments the profile asked for
}

export type Placed = {
	n: number, -- which piece of the run this is
	id: string,
	kind: string,
	dir: number,
	variant: Variant,
	start: Socket,
	finish: Socket,
	nodes: { Node }, -- world-space centre line
	cum: { number },
	length: number,
	quads: { Quad },
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	-- Level, unbanked and at `SurfaceY`: every node's `y`, `pitch` and `bank` is zero.
	-- The whole road is this today. `Builder` and `poseAt` both read it, and both answer
	-- exactly what they answered before there was a third dimension when it is true.
	flat: boolean,
}

local function forward(yaw: number): (number, number)
	return -math.sin(yaw), -math.cos(yaw)
end

function Pieces.forward(yaw: number): Vector3
	local fx, fz = forward(yaw)
	return Vector3.new(fx, 0, fz)
end

function Pieces.right(yaw: number): Vector3
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
end

-- THE SURFACE'S FRAME at one node: its right, its up and its forward, built from the plan
-- heading, the grade and the bank. The plan vectors are turned about the right axis by the
-- pitch and then about the forward axis by the bank, which is `Playground/Build.frame`
-- with the pitch added.
--
-- `up.Y` comes out as exactly cos(pitch) x cos(bank), and that one product is the whole of
-- the wall question: `Drift/World` calls anything whose normal leans more than about 46
-- degrees a wall and stops the car dead against it, so GRADE AND BANK COMPOUND and it is
-- the product that has to be capped, never the two separately (`Config.Road.MaxSurfaceTilt`).
function Pieces.frame(yaw: number, pitch: number, bank: number): (Vector3, Vector3, Vector3)
	local cy, sy = math.cos(yaw), math.sin(yaw)
	local rx, rz = cy, -sy -- plan right
	local fx, fz = -sy, -cy -- plan forward
	local cp, sp = math.cos(pitch), math.sin(pitch)
	local cb, sb = math.cos(bank), math.sin(bank)
	-- forward tilted up the grade, and the up that goes with it (bank not yet applied)
	local f = Vector3.new(fx * cp, sp, fz * cp)
	local ux, uy, uz = -fx * sp, cp, -fz * sp
	local right = Vector3.new(rx * cb + ux * sb, uy * sb, rz * cb + uz * sb)
	local up = Vector3.new(-rx * sb + ux * cb, uy * cb, -rz * sb + uz * cb)
	return right, up, f
end

--------------------------------------------------------------------------------
-- The profiles: what a piece does vertically
--------------------------------------------------------------------------------

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

-- THE GRADE AT `u` DOWN A PIECE THAT ARRIVED AT GRADE `g0`, in studs per stud of plan.
--
-- It is the derivative of the cubic Hermite in height through (0, 0) with slope `g0` and
-- (L, delta) with slope `g1` -- which is to say a parabolic vertical curve, what a road
-- is actually set out with. The two numbers a piece may give are what pin it down:
--
--   neither          it CARRIES: the grade it arrived at, all the way. Flat in, flat out
--   `EndGrade` only  a vertical curve from `g0` to `g1`; the height it loses falls out of
--                    it. The grade blends linearly, so the pitch step per segment is as
--                    small as a given swing can be made
--   `Drop` only      it loses exactly that much height and hands on the average grade
--   both             it loses exactly that much height AND hands on exactly that grade:
--                    the flat entry that drops away is this, with `g0` zero
local function gradeAt(h: HeightSpec?, g0: number, length: number, u: number): number
	if not h then
		return g0
	end
	local delta: number, g1: number
	if h.drop ~= nil and h.endGrade ~= nil then
		delta, g1 = -h.drop, h.endGrade
	elseif h.drop ~= nil then
		delta = -h.drop
		g1 = delta / length
	else
		g1 = h.endGrade :: number
		delta = length * (g0 + g1) * 0.5
	end
	return (3 * u * u - 4 * u + 1) * g0 + (6 * u - 6 * u * u) * (delta / length) + (3 * u * u - 2 * u) * g1
end

-- A piece's OWN bank in radians at `u`, before anything it arrived with is blended into
-- it. `sign` is the turn's direction, so a positive `Degrees` always raises the outer
-- edge, exactly as `Playground/Build.bankProfile` does it.
local function bankProfile(spec: any, sign: number): (number) -> number
	if not spec or not spec.Degrees then
		return function(): number
			return 0
		end
	end
	local radians = math.rad(spec.Degrees) * sign
	if spec.Shape == "crest" then
		-- In and out again over the piece: a bank that is gone by the exit socket.
		return function(u: number): number
			return radians * math.sin(math.pi * u)
		end
	end
	return function(): number
		return radians
	end
end

-- How much a bank blended from `roll0` into the piece's own reads at `u`.
--
-- WHAT IS BLENDED IS THE DIFFERENCE AT THE SOCKET, NOT THE WHOLE PROFILE, and that
-- distinction is a bug fix rather than a refinement (T-068). This used to be
-- `roll0 + (own(u) - roll0) * smoothstep(u)`, which is right for a bank that is CONSTANT
-- down the piece and wrong for one that is not: a crest's own bank is zero at both ends,
-- so multiplying it by a smoothstep that is 0.5 at the middle of the piece attenuated the
-- whole crest. MEASURED: a crest asking for 30 degrees reached 19.24, because
-- `sin(pi x u) x smoothstep(u)` peaks at 0.641 rather than at 1.
--
-- So what decays is only the step between what the piece arrived at and what its own
-- profile starts at, and the piece's own profile is laid down as written:
--
--   bank(0) = own(0) + (roll0 - own(0)) = roll0 exactly -- no step at the join
--   bank(1) = own(1)                                    -- the piece's own exit bank
--   own(0) == roll0 (the usual case, both zero)  =>  bank(u) IS own(u)
--
-- A CONSTANT BANK AND NO BANK AT ALL ARE ALGEBRAICALLY UNCHANGED by this -- for constant
-- `own`, `own + (roll0 - own)(1 - ss)` and `roll0 + (own - roll0) ss` are the same
-- expression -- so the unwind every unbanked piece does, which is the only bank behaviour
-- the shipped road had before T-068, is exactly what it was.
local function bankAt(own: (number) -> number, roll0: number, u: number): number
	local own0 = own(0)
	return own(u) + (roll0 - own0) * (1 - smoothstep(u))
end

--------------------------------------------------------------------------------
-- The local shapes
--------------------------------------------------------------------------------

-- Shapes are APPENDED to an open centre line rather than returned whole, because a piece
-- is not always one shape: a chicane is an arc, then the other way. A shape starts from
-- wherever the line has got to and leaves it ready for the next one, so a two-bend piece
-- is flush inside itself by exactly the construction that makes two pieces flush.
local function newNode(x: number, z: number, yaw: number): Node
	return { x = x, z = z, yaw = yaw, y = 0, pitch = 0, bank = 0 }
end

local function openLine(): ({ Node }, { number })
	return { newNode(0, 0, 0) }, { 0 }
end

-- A straight is ONE segment however long it is, because it is straight: cutting it up
-- would only cost parts and gain nothing a ground ray could tell apart. `maxLength` is
-- `math.huge` for exactly that reason, and is only ever finite when a profile is going to
-- be laid over the shape and the straight has to bend vertically.
local function appendStraight(nodes: { Node }, cum: { number }, length: number, maxLength: number)
	local n = math.max(1, math.ceil(length / maxLength))
	local last = nodes[#nodes]
	local fx, fz = forward(last.yaw)
	local x, z, yaw = last.x, last.z, last.yaw
	local base = cum[#cum]
	for i = 1, n do
		local d = length * (i / n)
		nodes[#nodes + 1] = newNode(x + fx * d, z + fz * d, yaw)
		cum[#cum + 1] = base + d
	end
end

-- A corner is short straight segments. Each one turns half the step, advances one chord,
-- then turns the other half, which puts every node exactly on the true circle: the
-- segments are its chords, so more of them is a closer curve and the error is
-- chord^2 / (8 x radius) (`Config.Road.MaxSegmentChord`).
local function appendArc(nodes: { Node }, cum: { number }, radius: number, arcDeg: number, maxChord: number, maxLength: number)
	local total = math.rad(arcDeg)
	local arcLength = math.abs(total) * radius
	-- Whichever limit bites: a chord no longer than `MaxSegmentChord`, AND a curve no
	-- further inside the true arc than `MaxArcDeviation`. The deviation is the one that
	-- matters and the chord is a proxy for it, so a tight radius is cut more finely than
	-- a wide one at the same chord (`Config.Road.MaxArcDeviation`). `maxLength` is the
	-- third, and is only finite when a profile needs the curve cut more finely still.
	local byDeviation = math.sqrt(8 * radius * Config.Road.MaxArcDeviation)
	local n = math.max(1, math.ceil(arcLength / math.min(maxChord, byDeviation, maxLength)))
	local dTheta = total / n
	local chord = 2 * radius * math.sin(math.abs(dTheta) * 0.5)

	local last = nodes[#nodes]
	local x, z, yaw = last.x, last.z, last.yaw
	local base = cum[#cum]
	for i = 1, n do
		yaw += dTheta * 0.5
		local fx, fz = forward(yaw)
		x += fx * chord
		z += fz * chord
		yaw += dTheta * 0.5
		nodes[#nodes + 1] = newNode(x, z, yaw)
		cum[#cum + 1] = base + (arcLength / n) * i
	end
end

--------------------------------------------------------------------------------
-- The variant set, built once from the config
--------------------------------------------------------------------------------

-- The plan shape, at a given spacing. Called twice per variant: once with no length limit
-- at all, which is the flat set the road has always had, and once at whatever spacing the
-- piece's profile needs.
local function buildShape(shape: string, spec: any, dir: number, maxChord: number, maxLength: number): ({ Node }, { number })
	local nodes, cum = openLine()
	if shape == "arc" then
		appendArc(nodes, cum, spec.Radius, spec.Arc * dir, maxChord, maxLength)
	elseif shape == "chicane" then
		-- Left then right, or right then left: two equal and opposite bends, with an
		-- optional straight between them so the car has a beat to catch the first slide
		-- in before it has to start the second.
		appendArc(nodes, cum, spec.Radius, spec.Arc * dir, maxChord, maxLength)
		if (spec.Middle or 0) > 0 then
			appendStraight(nodes, cum, spec.Middle, maxLength)
		end
		appendArc(nodes, cum, spec.Radius, -spec.Arc * dir, maxChord, maxLength)
	else
		appendStraight(nodes, cum, spec.Length, maxLength)
	end
	return nodes, cum
end

-- HOW FINELY THIS PIECE HAS TO BE CUT FOR ITS PROFILE, which is the same idea as
-- `MaxSegmentChord` in the other two axes: a segment is a flat box, so the whole of a
-- piece's pitch and bank change has to be shared out between its segments or a join
-- reads as a step and a bank reads as a kink.
--
-- It is measured off the profile rather than guessed, at the WORST ENTRY STATE the limits
-- allow -- a piece can arrive at any grade up to `MaxGrade` and any bank up to `MaxBank`,
-- and the node count is fixed when the set is built, so it has to be the count that
-- survives all of them.
--
-- IT IS THE BIGGEST STEP THAT DECIDES, NOT THE TOTAL SWING, and that distinction is a
-- measured one rather than a careful one: dividing the total swing by the limit assumes
-- the swing is spread evenly down the piece, and a profile the clamp has bitten into is
-- the opposite of that -- `Cliff`, which asks for four times the drop it may have, does
-- ALL of its grade change in the first fourteen studs and the rest at the limit. So the
-- spacing is tried, the worst single step at that spacing is measured, and the spacing is
-- halved until it fits or `MaxProfileSegments` says stop.
--
-- WHEN IT CANNOT FIT, `applyProfile` STILL HOLDS THE LINE: it rate-limits what it lays
-- down. This only decides how finely a piece is cut, which is to say how FAST it is
-- allowed to achieve the profile it asked for.
--
-- AND A BANK ON A CURVE KINKS WITHOUT THE BANK ANGLE CHANGING AT ALL, which is the third
-- criterion and the least obvious: a banked surface's normal leans towards the outside of
-- the turn, so as the heading comes round the normal comes round WITH it. Two segments of
-- a 30-degree bank whose headings differ by 4 degrees have normals 4 x sin(30) = 2 degrees
-- apart, and that is a kink in the road even though both are banked identically. Measured
-- on a 120-degree banked arc before this was in: 3.7 degrees between the surface a car was
-- put down on and the box it was standing on.
local function profileSegments(height: HeightSpec?, own: (number) -> number, length: number, turn: number): number
	local C = Config.Road
	local maxGrade = math.tan(math.rad(C.MaxGrade))
	local maxBank = math.rad(C.MaxBank)
	local maxPitchStep = math.rad(C.MaxPitchStep)
	local maxBankStep = math.rad(C.MaxBankStep)

	local function fits(n: number): boolean
		local dYaw = math.abs(turn) / n
		for _, entry in { -1, 0, 1 } do
			local g0 = maxGrade * entry
			local roll0 = maxBank * entry
			local lastP = math.atan(g0)
			local lastB = roll0
			for i = 1, n do
				local u = i / n
				local p = math.atan(math.clamp(gradeAt(height, g0, length, u), -maxGrade, maxGrade))
				local b = bankAt(own, roll0, u)
				if math.abs(p - lastP) > maxPitchStep or math.abs(b - lastB) > maxBankStep then
					return false
				end
				if dYaw * math.abs(math.sin(b)) > maxBankStep then
					return false
				end
				lastP, lastB = p, b
			end
		end
		return true
	end

	for n = 1, C.MaxProfileSegments do
		if fits(n) then
			return n
		end
	end
	return C.MaxProfileSegments
end

-- `Shape` is HOW a piece is drawn; `kind` is what it is called. They are deliberately
-- separate: a corner, a sweeper and a hairpin are the same shape with different numbers,
-- and the whole difference between them is the numbers (`Config.Road.Pieces`).
local function makeVariant(id: string, kind: string, spec: any, dir: number, maxChord: number): Variant
	local shape = spec.Shape or (if kind == "Corner" then "arc" else "straight")
	local nodes, cum = buildShape(shape, spec, dir, maxChord, math.huge)
	-- The length is the centre line's own arc length, never a formula beside it: `locate`
	-- and `poseAt` both read `cum`, so a length that disagreed with it would put `t`
	-- quietly out of step with where the car actually is.
	local length: number = cum[#cum]
	local last = nodes[#nodes]

	-- Its profile. `Height.EndGrade` is written in degrees, like every other angle in the
	-- config, and kept here as a grade because that is what the maths wants.
	local height: HeightSpec? = nil
	if spec.Height and (spec.Height.Drop or spec.Height.EndGrade) then
		height = {
			drop = spec.Height.Drop,
			endGrade = if spec.Height.EndGrade then math.tan(math.rad(spec.Height.EndGrade)) else nil,
		}
	end
	-- A mirrored piece banks the way it turns; one that turns neither way takes its bank
	-- as written.
	local bankOwn = bankProfile(spec.Bank, if dir ~= 0 then dir else 1)
	-- How far the heading comes round over the whole piece, which is what turns a bank
	-- into a kink. A chicane turns twice, and both ways: it is the turning that counts,
	-- not where it ends up.
	local turn = if shape == "straight" then 0 else math.rad(math.abs(spec.Arc)) * (if shape == "chicane" then 2 else 1)
	local segments = profileSegments(height, bankOwn, length, turn)
	local fineNodes, fineCum = buildShape(shape, spec, dir, maxChord, length / segments)

	return {
		id = id,
		kind = kind,
		dir = dir,
		weight = spec.weight or 1,
		minPieces = spec.minPieces or 0,
		-- A chicane keeps its radius even though its curvature changes sign halfway: the
		-- only reader is `Generator.ahead`, which hands out `dir / radius`, and the only
		-- reader of THAT is a brake that takes its magnitude. The magnitude is right
		-- everywhere on a chicane; the sign is right on its first bend.
		radius = if shape == "straight" then nil else spec.Radius,
		arcDeg = if shape == "straight" then nil else spec.Arc * dir,
		length = length,
		nodes = nodes,
		cum = cum,
		endSocket = { x = last.x, z = last.z, yaw = last.yaw },
		fineNodes = fineNodes,
		fineCum = fineCum,
		profiled = height ~= nil or (spec.Bank ~= nil and spec.Bank.Degrees ~= nil),
		height = height,
		bankOwn = bankOwn,
		fineSegments = segments,
	}
end

local variants: { [string]: Variant } = {}
local order: { string } = {}

local function buildSet()
	local C = Config.Road
	table.clear(variants)
	table.clear(order)
	local names: { string } = {}
	for name in C.Pieces do
		table.insert(names, name)
	end
	table.sort(names) -- the set is the same whatever order the config table iterates in
	for _, name in names do
		local spec = C.Pieces[name]
		local kind = spec.kind or name
		if spec.mirror then
			variants[name .. "L"] = makeVariant(name .. "L", kind, spec, 1, C.MaxSegmentChord)
			variants[name .. "R"] = makeVariant(name .. "R", kind, spec, -1, C.MaxSegmentChord)
			table.insert(order, name .. "L")
			table.insert(order, name .. "R")
		else
			variants[name] = makeVariant(name, kind, spec, 0, C.MaxSegmentChord)
			table.insert(order, name)
		end
	end
	-- `Config.Road.Order` only fixes the reading order; anything it misses keeps its place.
	local rank: { [string]: number } = {}
	for i, id in C.Order do
		rank[id] = i
	end
	table.sort(order, function(a, b)
		local ra, rb = rank[a] or 1000, rank[b] or 1000
		if ra == rb then
			return a < b
		end
		return ra < rb
	end)
end

buildSet()

function Pieces.rebuild()
	buildSet()
end

function Pieces.all(): { [string]: Variant }
	return variants
end

function Pieces.order(): { string }
	return order
end

function Pieces.get(id: string): Variant?
	return variants[id]
end

--------------------------------------------------------------------------------
-- Placing one
--------------------------------------------------------------------------------

-- The whole of "rotate about the start socket, then translate", for one point.
local function transform(px: number, pz: number, socket: Socket): (number, number)
	local c, s = math.cos(socket.yaw), math.sin(socket.yaw)
	return socket.x + px * c + pz * s, socket.z - px * s + pz * c
end

-- How wide the piece reaches, for the overlap test: the road and both barriers, less the
-- slack that stops two pieces sharing a socket face from reading as a collision.
function Pieces.footprintHalfWidth(): number
	local C = Config.Road
	return C.Width * 0.5 + C.BarrierThickness - C.OverlapSlack
end

-- Fill in the height, the grade and the bank down a piece that arrived at `y0`, `p0` and
-- `r0`. Called only when there is something to do -- see `place`.
--
-- THE FIRST NODE IS THE SOCKET IT ARRIVED AT, EXACTLY: `gradeAt` returns `g0` at u = 0
-- whatever the profile, the height starts at `y0` because nothing has been integrated
-- yet, and the bank blend is `roll0` at u = 0. So the gap at a join is not small, it is
-- zero, and that is by construction rather than by measurement.
--
-- THREE LIMITS, IN THIS ORDER, AND THEY ARE WHAT MAKES THE PROFILE A REQUEST RATHER THAN
-- AN INSTRUCTION:
--   1. the grade is clamped to `MaxGrade`, and the bank to whatever `MaxSurfaceTilt`
--      leaves once that grade has taken its share of the lean;
--   2. then neither may move more than `MaxPitchStep` or `MaxBankStep` from the node
--      before it, so no two neighbouring boxes are a step or a kink WHATEVER a piece
--      asks for -- a profile that wants to fall off a cliff gets a ramp instead;
--   3. and the tilt cap gets the last word, because a surface that reads as a wall is
--      worse than a bank that moved quickly. It can only bite when the grade ALONE is
--      near the tilt limit, which at 14 degrees against 35 it never is.
--
-- The height is then summed from the grade that survived all of that, so the road that
-- exists is always the road the limits allow, and the exit socket is read off it.
local function applyProfile(nodes: { Node }, cum: { number }, variant: Variant, y0: number, p0: number, r0: number)
	local C = Config.Road
	local maxGrade = math.tan(math.rad(C.MaxGrade))
	local maxBank = math.rad(C.MaxBank)
	local maxPitchStep = math.rad(C.MaxPitchStep)
	local maxBankStep = math.rad(C.MaxBankStep)
	local cosTilt = math.cos(math.rad(C.MaxSurfaceTilt))
	local length = cum[#cum]
	local height = variant.height
	local own = variant.bankOwn
	local g0 = math.tan(p0)

	local y, lastG = y0, g0
	local pitch, bank = p0, r0
	for i = 1, #nodes do
		local u = if length > 0 then cum[i] / length else 0
		if i > 1 then
			local want = math.atan(math.clamp(gradeAt(height, g0, length, u), -maxGrade, maxGrade))
			pitch = math.clamp(want, pitch - maxPitchStep, pitch + maxPitchStep)
			local g = math.tan(pitch)
			y += (lastG + g) * 0.5 * (cum[i] - cum[i - 1])
			lastG = g
		end
		local lid = math.min(maxBank, math.acos(math.clamp(cosTilt / math.cos(pitch), -1, 1)))
		if i > 1 then
			local want = math.clamp(bankAt(own, r0, u), -lid, lid)
			bank = math.clamp(math.clamp(want, bank - maxBankStep, bank + maxBankStep), -lid, lid)
		else
			bank = math.clamp(bank, -lid, lid)
		end
		local node = nodes[i]
		node.y = y
		node.pitch = pitch
		node.bank = bank
	end
end

function Pieces.place(variant: Variant, socket: Socket, n: number): Placed
	local C = Config.Road
	local hv = Pieces.footprintHalfWidth()
	local slack = C.OverlapSlack

	-- WHICH SET OF NODES, and the one branch that keeps the flat road exactly the road it
	-- was: a piece with no profile of its own, arriving level and unbanked, is the shape
	-- it has always been with a constant height written down its nodes -- and when that
	-- height is `SurfaceY` too, it is flat and `Builder` and `poseAt` take their old paths.
	local y0 = socket.y or 0
	local p0 = socket.pitch or 0
	local r0 = socket.roll or 0
	local level = not variant.profiled and p0 == 0 and r0 == 0
	local source = if level then variant.nodes else variant.fineNodes
	local cum = if level then variant.cum else variant.fineCum

	local nodes: { Node } = table.create(#source)
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for i, p in source do
		local x, z = transform(p.x, p.z, socket)
		nodes[i] = { x = x, z = z, yaw = socket.yaw + p.yaw, y = y0, pitch = 0, bank = 0 }
	end
	if not level then
		applyProfile(nodes, cum, variant, y0, p0, r0)
	end

	local quads: { Quad } = table.create(#nodes - 1)
	for i = 1, #nodes - 1 do
		local a, b = nodes[i], nodes[i + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 1e-6 then
			local ux, uz = dx / len, dz / len
			local hu = math.max(len * 0.5 - slack, 1e-3)
			quads[#quads + 1] = {
				cx = (a.x + b.x) * 0.5,
				cz = (a.z + b.z) * 0.5,
				ux = ux,
				uz = uz,
				hu = hu,
				hv = hv,
			}
		end
	end

	-- The bounding box is of the FOOTPRINT, not the centre line: the quick reject has to
	-- be at least as big as the thing it is rejecting for.
	for _, q in quads do
		local rx = math.abs(q.ux) * q.hu + math.abs(q.uz) * q.hv
		local rz = math.abs(q.uz) * q.hu + math.abs(q.ux) * q.hv
		minX = math.min(minX, q.cx - rx)
		maxX = math.max(maxX, q.cx + rx)
		minZ = math.min(minZ, q.cz - rz)
		maxZ = math.max(maxZ, q.cz + rz)
	end

	local last = nodes[#nodes]
	return {
		n = n,
		id = variant.id,
		kind = variant.kind,
		dir = variant.dir,
		variant = variant,
		start = { x = socket.x, z = socket.z, yaw = socket.yaw, y = y0, pitch = p0, roll = r0 },
		-- The exit socket is READ OFF THE BUILT PIECE, never off the profile that asked
		-- for it: the clamps are allowed to have had their say, and what the next piece
		-- has to start from is the road that is actually there.
		finish = { x = last.x, z = last.z, yaw = last.yaw, y = last.y, pitch = last.pitch, roll = last.bank },
		nodes = nodes,
		cum = cum,
		length = variant.length,
		quads = quads,
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
		flat = level and y0 == 0,
	}
end

--------------------------------------------------------------------------------
-- Do two of them overlap?
--------------------------------------------------------------------------------

-- Two oriented rectangles, by separating axes: four axes in two dimensions, and a gap on
-- any one of them is a gap.
--
-- THIS IS THE HOTTEST FUNCTION IN THE GAME and it is written to look like it. The
-- lookahead asks it millions of times a run -- every candidate placement against every
-- quad of fourteen remembered pieces, and a hairpin alone is 27 quads -- so it builds no
-- table, calls nothing, and gets out on the first axis that separates. An earlier version
-- that packed the four axes into a table it allocated per call cost 0.104 ms a NODE,
-- which turned a deep search into a freeze measured in seconds.
local function quadsOverlap(a: Quad, b: Quad): boolean
	local dx, dz = b.cx - a.cx, b.cz - a.cz

	-- Cheapest reject first: two circles round the rectangles. `hu + hv` is an upper
	-- bound on either one's reach from its centre, and most pairs the search asks about
	-- are nowhere near each other.
	local reach = (a.hu + a.hv) + (b.hu + b.hv)
	if dx * dx + dz * dz >= reach * reach then
		return false
	end

	local aux, auz, ahu, ahv = a.ux, a.uz, a.hu, a.hv
	local bux, buz, bhu, bhv = b.ux, b.uz, b.hu, b.hv
	-- Each rectangle's across axis is its long axis turned 90 degrees, so the four axes
	-- are (aux, auz), (-auz, aux), (bux, buz), (-buz, bux).
	local dot = aux * bux + auz * buz -- cos of the angle between them
	local cross = aux * buz - auz * bux -- sin of it
	local adot, across = math.abs(dot), math.abs(cross)

	-- a's long axis
	if math.abs(dx * aux + dz * auz) >= ahu + bhu * adot + bhv * across then
		return false
	end
	-- a's across axis
	if math.abs(-dx * auz + dz * aux) >= ahv + bhu * across + bhv * adot then
		return false
	end
	-- b's long axis
	if math.abs(dx * bux + dz * buz) >= bhu + ahu * adot + ahv * across then
		return false
	end
	-- b's across axis
	if math.abs(-dx * buz + dz * bux) >= bhv + ahu * across + ahv * adot then
		return false
	end
	return true
end

Pieces.quadsOverlap = quadsOverlap

function Pieces.boxesApart(a: Placed, b: Placed): boolean
	return a.maxX <= b.minX or b.maxX <= a.minX or a.maxZ <= b.minZ or b.maxZ <= a.minZ
end

-- Does this piece's footprint cross that one's? Neighbours are not asked: two pieces one
-- apart in the chain SHARE a socket face by construction, which is a join, not a crash.
function Pieces.overlap(a: Placed, b: Placed): boolean
	if math.abs(a.n - b.n) < 2 then
		return false
	end
	if Pieces.boxesApart(a, b) then
		return false
	end
	-- Numeric loops, not generic ones: see `quadsOverlap` for why this one function's
	-- shape is worth caring about.
	local qa, qb = a.quads, b.quads
	for i = 1, #qa do
		local q = qa[i]
		for j = 1, #qb do
			if quadsOverlap(q, qb[j]) then
				return true
			end
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Where on a piece a point is
--------------------------------------------------------------------------------

-- The nearest point on this piece's centre line, as `t` from 0 to 1 along it, how far
-- the point is to the side of it, and which way round. Used for progress and for the
-- "is the car still on the road" check.
function Pieces.locate(piece: Placed, x: number, z: number): (number, number)
	local bestT, bestD = 0, math.huge
	for i = 1, #piece.nodes - 1 do
		local a, b = piece.nodes[i], piece.nodes[i + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local len2 = dx * dx + dz * dz
		if len2 < 1e-12 then
			continue
		end
		local s = ((x - a.x) * dx + (z - a.z) * dz) / len2
		s = math.clamp(s, 0, 1)
		local px, pz = a.x + dx * s, a.z + dz * s
		local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		if d < bestD then
			bestD = d
			local along = piece.cum[i] + (piece.cum[i + 1] - piece.cum[i]) * s
			bestT = if piece.length > 0 then along / piece.length else 0
		end
	end
	return bestT, bestD
end

-- The pose a car is put down in at `t` along a piece: on the centre line, facing the way
-- the road goes, AT THE PIECE'S OWN HEIGHT and lying with its bank.
--
-- `y` means what it always meant -- a world height on a flat road, where
-- `Config.Road.SurfaceY` is the road's own surface -- so every caller that asks for
-- `SurfaceY + RideHeight` or `SurfaceY + BarrierHeight` still gets exactly that much
-- clearance. What changes is that the clearance is measured from THIS PIECE's surface and
-- along its up, not from a plane at zero: on a thirty-degree bank a car put down two
-- studs up is two studs off the road rather than 1.7.
--
-- `SafeStart`, `JoinCFrame`, the respawn, the closing barrier and every centre-line mark
-- come through here, which is why this is the only place that has to know.
function Pieces.poseAt(piece: Placed, t: number, y: number): CFrame
	local want = math.clamp(t, 0, 1) * piece.length
	local nodes = piece.nodes
	local a, b, s = nodes[1], nodes[1], 0
	for i = 1, #nodes - 1 do
		local c0, c1 = piece.cum[i], piece.cum[i + 1]
		if want <= c1 or i == #nodes - 1 then
			a, b = nodes[i], nodes[i + 1]
			s = if c1 > c0 then (want - c0) / (c1 - c0) else 0
			break
		end
	end
	local x = a.x + (b.x - a.x) * s
	local z = a.z + (b.z - a.z) * s
	local yaw = a.yaw + (b.yaw - a.yaw) * s
	if piece.flat then
		return CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	end
	local sy = a.y + (b.y - a.y) * s
	local pitch = a.pitch + (b.pitch - a.pitch) * s
	local bank = a.bank + (b.bank - a.bank) * s
	local right, up = Pieces.frame(yaw, pitch, bank)
	local C = Config.Road
	return CFrame.fromMatrix(Vector3.new(x, C.SurfaceY + sy, z) + up * (y - C.SurfaceY), right, up)
end

-- The surface's height and attitude at `t`, for anything that needs the numbers rather
-- than a CFrame: the world Y of the road's top, its grade and its bank.
function Pieces.surfaceAt(piece: Placed, t: number): (number, number, number)
	local want = math.clamp(t, 0, 1) * piece.length
	local nodes = piece.nodes
	local a, b, s = nodes[1], nodes[1], 0
	for i = 1, #nodes - 1 do
		local c0, c1 = piece.cum[i], piece.cum[i + 1]
		if want <= c1 or i == #nodes - 1 then
			a, b = nodes[i], nodes[i + 1]
			s = if c1 > c0 then (want - c0) / (c1 - c0) else 0
			break
		end
	end
	return Config.Road.SurfaceY + a.y + (b.y - a.y) * s,
		a.pitch + (b.pitch - a.pitch) * s,
		a.bank + (b.bank - a.bank) * s
end

return Pieces
