--!strict
-- Builder: turns a placed piece into parts, and nothing else. It knows about boxes; it
-- knows nothing about the generator, the window or the car.
--
-- Everything it makes is ANCHORED and carries no BodyMover and no constraint: the car is
-- kinematic and Roblox physics never moves anything the road is made of.
--
-- THE ROAD IS TAGGED AND THE BARRIERS ARE NOT, and that distinction is not decoration.
-- The drift model's ground rays filter to an INCLUDE list of parts tagged `DriftSurface`
-- (`Drift/World`), so an untagged part is not low-grip ground -- it is ABSENT, and a car
-- over it falls through the world. A barrier is meant to be absent from the ground rays;
-- that is exactly what makes it a wall and not a kerb you can climb.
--
-- THE CENTRE LINE IS SPACED ALONG THE RUN, NOT ALONG A PIECE. Its whole job is to say
-- how fast the car is going, so the marks must pass at the car's speed divided by
-- `MarkInterval` and at nothing else -- which means the interval is measured in the arc
-- length of the WHOLE road, carried across every join (`markPhase` below). Spacing them
-- per piece instead would make a hairpin's marks pass at a different rate from a
-- straight's, which is a lie about the car's speed. A mark is laid with
-- `Pieces.poseAt`, by arc-length fraction, so a corner is spaced exactly as evenly as a
-- straight is.
--
-- One rule a curve breaks if it is built naively (learned the hard way in the playground,
-- T-026): two neighbouring boxes on a curve share their centre point but turn by the yaw
-- step, so their OUTER corners pull apart by (half the width) x (that step) and the gap
-- reads from the ground as a bite out of the edge. Each box is lengthened by exactly
-- that, so the outer corners meet and the inner ones overlap instead.
--
-- THE SAME THING HAPPENS IN THE VERTICAL, AND THAT ONE IS WHY THE ROAD IS NOT ALL BOXES
-- ANY MORE (T-066). Where the road has grade AND turn, two neighbouring top faces crossed
-- along the centre line and each stood proud of the other on one half of the road: a
-- shallow wedge at every seam, worst at the kerb at 0.2967 studs, which is the banding the
-- user could see. It was NOT a sagitta -- `spanFrame` already puts the top face through
-- both end nodes -- and it could not be tuned out: the surface of a graded curve is not
-- developable, no flat quadrilateral lies in it, and the total along a piece is its turn
-- times its grade whatever the boxes are doing.
--
-- So a segment whose four corners are not coplanar is built as TWO TRIANGLES instead, and
-- a triangle always is planar. Each keeps the whole cross line at its end as an edge, the
-- next segment shares that edge exactly, and the step is gone rather than smaller: 0.2967
-- -> 0.0103, which is the road's own slope between two samples. The long version, the cost
-- and the alternatives are at "TRIANGLES" below and in `RoadTests` beside `seamSweep`.
--
-- THERE ARE TWO LOOPS IN HERE AND THAT IS DELIBERATE (T-066). A flat piece is built the
-- way it has always been built -- a box per pair of points, square to the world, placed
-- by `span` -- and a piece with a height or a bank is built from the two end FRAMES of
-- each segment, which is `Playground/Build.ribbon`'s way and includes its trick of
-- averaging the two ups and re-squaring the frame off the segment's own forward. Writing
-- one loop that did both would have meant the nine flat pieces coming out of a different
-- formula from the one that measured them; keeping the old one untouched is what makes
-- "the flat road is exactly the road it was" a fact rather than a tolerance.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Pieces = require(script.Parent.Pieces)

local Builder = {}

local OVERLAP = 0.2 -- studs every box is lengthened by so no joint can show a hairline

local function newPart(
	name: string,
	size: Vector3,
	cf: CFrame,
	colour: Color3,
	material: Enum.Material,
	parent: Instance,
	className: string?
): Part
	local part = Instance.new(className or "Part") :: Part
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = false
	part.Material = material
	part.Color = colour
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- The yaw step between two nodes, wrapped into -pi..pi.
local function yawStep(a: number, b: number): number
	local d = math.abs(b - a)
	if d > math.pi then
		d = math.abs(d - 2 * math.pi)
	end
	return d
end

-- One box spanning two points on the ground, at a given width, with its TOP at `topY`.
local function span(
	name: string,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	width: number,
	height: number,
	topY: number,
	extra: number,
	colour: Color3,
	material: Enum.Material,
	parent: Instance
): Part?
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-4 then
		return nil
	end
	local yaw = math.atan2(-dx, -dz) -- the heading whose forward is (dx, dz)
	local cf = CFrame.new((ax + bx) * 0.5, topY - height * 0.5, (az + bz) * 0.5) * CFrame.Angles(0, yaw, 0)
	return newPart(name, Vector3.new(width, height, len + OVERLAP + extra), cf, colour, material, parent)
end

-- One box spanning two POINTS IN SPACE, lying in the surface rather than square to the
-- world: `a` and `b` are the two ends of the segment's centre line and `ua`, `ub` the
-- surface's up at each. The box's top face is the road, so its centre is half its
-- thickness down its own up.
--
-- The frame is re-squared off the segment's own forward, exactly as `ribbon` does it: the
-- averaged up is not quite perpendicular to a segment that is both turning and tilting,
-- and a box built from a skewed frame is a box with a twist in it.
local function spanFrame(
	name: string,
	a: Vector3,
	b: Vector3,
	ua: Vector3,
	ub: Vector3,
	width: number,
	height: number,
	drop: number, -- studs from the top face down to the centre of the box
	extra: number,
	colour: Color3,
	material: Enum.Material,
	parent: Instance
): Part?
	local delta = b - a
	local len = delta.Magnitude
	if len < 1e-4 then
		return nil
	end
	local forward = delta.Unit
	local up = (ua + ub).Unit
	local right = forward:Cross(up)
	if right.Magnitude < 1e-6 then
		return nil
	end
	right = right.Unit
	up = right:Cross(forward).Unit
	local centre = (a + b) * 0.5 - up * drop
	local cf = CFrame.fromMatrix(centre, right, up)
	return newPart(name, Vector3.new(width, height, len + OVERLAP + extra), cf, colour, material, parent)
end

--------------------------------------------------------------------------------
-- TRIANGLES, because a box cannot lie in this surface (T-066, the user's call)
--------------------------------------------------------------------------------
-- A segment of road is a quadrilateral: the cross line at one node and the cross line at
-- the next. WHERE THE ROAD BOTH TURNS AND TILTS THOSE FOUR CORNERS ARE NOT COPLANAR --
-- the surface of a graded curve is not developable -- so no flat-topped box lies in it,
-- and two neighbouring boxes meet at a step instead of sharing an edge. That was measured
-- at up to 0.2967 studs at the kerb, and proved irreducible for boxes: see `seamSweep` in
-- `RoadTests`.
--
-- A TRIANGLE IS ALWAYS PLANAR, which is the whole of the answer. Split the quad along a
-- diagonal and both halves lie exactly in the surface; each one keeps the WHOLE cross line
-- at its end as an edge, so the next segment shares that edge exactly and the step is not
-- made smaller, it is GONE. The diagonal alternates segment to segment so a long strip
-- stays symmetric and no one edge accumulates the error.
--
-- WHAT IT COSTS. Roblox has no triangle: a `WedgePart` is a prism whose cross section is a
-- RIGHT triangle (measured, not assumed -- rays down a wedge of size (4,2,6) rise linearly
-- with z and are constant across x). So an arbitrary triangle is two wedges, split by the
-- altitude from the vertex opposite the longest side, and a quad is four. That is only
-- paid where it is needed: a straight, a level corner and every flat piece have a planar
-- quad, a box is exact there, and the box is what they keep. Measured on a window of the
-- generated road, 195 of 336 slabs need it and the window goes 1 126 -> 1 711 parts.
--
-- The wedges of one triangle are extruded along THAT triangle's normal, so under a crease
-- the two prisms open a sliver below the surface -- 0.07 studs at the full 12 of thickness.
-- It is buried, and nothing ever sees the underside of the road.

-- Studs of non-planarity below which a quad IS flat and a box is exact. Tiny on purpose:
-- the cost of being wrong is a visible step and the cost of being over-careful is three
-- extra parts on twelve segments in a window.
local PLANAR_EPSILON = 1e-6

-- Studs every triangle is grown by, out from its own centroid and IN ITS OWN PLANE, so
-- its plane is untouched and only its outline moves. This is `OVERLAP`'s job done for
-- triangles, and it is needed for the same reason plus one more.
--
-- Two triangles that abut exactly along an edge are watertight on paper and not in
-- floating point: a sample landing on the edge can fall a hair outside BOTH, and because
-- each prism is extruded along its own triangle's normal -- which leans with the bank --
-- the ray then slides down a leaning side wall instead of stopping on a top face.
-- Measured, that put a one-sample notch 0.33 studs deep at the seams of a banked corner,
-- which is a hairline to the eye and a pothole to the car's ground rays.
--
-- GROWING COSTS ALMOST NOTHING HERE, and that is the point: neighbouring triangles now
-- share a whole cross line, so they differ only by the crease about it, and 0.15 studs of
-- overlap past that line buys back a step of 0.15 x the change in grade -- thousandths of
-- a stud, against the 0.2967 the box road had. The kerb edge grows by the same 0.15 and
-- disappears under the barrier, whose inner face is at exactly half the width.
local TRIANGLE_GROW = 0.15
local MAX_OVERSHOOT = 0.2 -- studs a half-triangle may reach past its parent's apex when
-- it is grown over the altitude: see `triangleSlab`

-- How far `d` stands off the plane of `a`, `b`, `c`, measured STRAIGHT DOWN, which is what
-- an eye would see. Zero means a box lies in the quad exactly.
local function outOfPlane(a: Vector3, b: Vector3, c: Vector3, d: Vector3): number
	local n = (b - a):Cross(c - a)
	if n.Magnitude < 1e-9 then
		return 0
	end
	n = n.Unit
	if math.abs(n.Y) < 1e-9 then
		return 0
	end
	return math.abs((d - a):Dot(n) / n.Y)
end

-- One `WedgePart` filling a RIGHT triangle, as a slab `thickness` deep below it.
--
-- A wedge of size (X, Y, Z) is the prism whose face at local +X is the right triangle with
-- its corner at (-Y/2, +Z/2), one leg Y up the local +Y and the other Z down the local -Z.
-- So the triangle's own normal is the wedge's X axis and the slab hangs along -X.
--
-- `q` is the right-angle corner, `d1`/`d2` the two perpendicular leg directions with
-- lengths `l1`/`l2`, and `n` the surface normal. Which leg becomes Y and which becomes Z
-- is forced by the handedness of `CFrame.fromMatrix`, and that is the one test below.
local function rightWedge(
	name: string,
	q: Vector3,
	d1: Vector3,
	l1: number,
	d2: Vector3,
	l2: number,
	n: Vector3,
	thickness: number,
	colour: Color3,
	material: Enum.Material,
	parent: Instance
): Part?
	if l1 < 1e-4 or l2 < 1e-4 then
		return nil -- a sliver Roblox would clamp to its minimum size and so distort
	end
	local u, pdir, ly, lz
	if d1:Cross(d2):Dot(n) > 0 then
		u, pdir, ly, lz = d2, d1, l2, l1
	else
		u, pdir, ly, lz = d1, d2, l1, l2
	end
	local centre = q + u * (ly * 0.5) + pdir * (lz * 0.5) - n * (thickness * 0.5)
	return newPart(name, Vector3.new(thickness, ly, lz), CFrame.fromMatrix(centre, n, u), colour, material, parent, "WedgePart")
end

-- One triangle of road, as the two right triangles the altitude cuts it into. The altitude
-- is dropped from the vertex opposite the LONGEST side, which is what guarantees its foot
-- lands strictly inside that side and both halves are real triangles.
local function triangleSlab(
	name: string,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	thickness: number,
	colour: Color3,
	material: Enum.Material,
	parent: Instance,
	out: { Part }
)
	-- Grown out from the centroid, in plane, before anything else is worked out.
	local centroid = (p1 + p2 + p3) / 3
	local function grow(p: Vector3): Vector3
		local d = p - centroid
		return if d.Magnitude < 1e-6 then p else p + d.Unit * TRIANGLE_GROW
	end
	p1, p2, p3 = grow(p1), grow(p2), grow(p3)

	local U, V, W = p1, p2, p3
	local l12, l23, l31 = (p2 - p1).Magnitude, (p3 - p2).Magnitude, (p1 - p3).Magnitude
	if l23 >= l12 and l23 >= l31 then
		U, V, W = p2, p3, p1
	elseif l31 >= l12 and l31 >= l23 then
		U, V, W = p3, p1, p2
	end
	local edge = V - U
	local len = edge.Magnitude
	if len < 1e-4 then
		return
	end
	local eu = edge / len
	local along = (W - U):Dot(eu)
	local foot = U + eu * along
	local rise = W - foot
	local height = rise.Magnitude
	if height < 1e-4 then
		return -- three points in a line: no triangle to build
	end
	local ru = rise / height
	local n = eu:Cross(ru)
	if n.Y < 0 then
		n = -n
	end
	-- THE TWO HALVES MEET ALONG THE ALTITUDE, AND AN EXACT ABUTMENT IS A HAIRLINE for the
	-- same reason a seam is: measured, it left a 0.12-stud notch one sample wide in the
	-- middle of a triangle. So each half is pushed past the altitude into the other.
	--
	-- The push is a SCALE ABOUT THE HALF'S OWN FAR CORNER, not a shift. Shifting the right
	-- angle along the long side was tried and is wrong: it moves the half off the parent's
	-- apex and opens a gap there instead, which measured 0.72 studs -- worse than the step
	-- it was meant to cure. Scaling about `U` (or `V`) keeps that corner and the whole of
	-- the original half inside, keeps the right angle a right angle, and stays in the
	-- triangle's own plane, so the surface does not move at all.
	--
	-- AND THE SCALE IS CAPPED BY WHAT IT COSTS AT THE OTHER END. Growing past the altitude
	-- by `g` grows past the apex by `g / along * height`, and that overshoot lands on a
	-- neighbour -- where it is harmless but not free, costing the overshoot times the
	-- crease between them. Held to 0.2 studs, that is thousandths. A sliver half -- the
	-- altitude of these triangles lands near one end, so one half is always thin -- ends
	-- up with a hundredth of a stud of overlap, which is still a thousand times the float
	-- error it is there to cover.
	local function cappedGrow(leg: number): number
		return math.min(TRIANGLE_GROW, MAX_OVERSHOOT * leg / math.max(height, 1e-6))
	end
	local ga, gb = cappedGrow(along), cappedGrow(len - along)
	local ka = (along + ga) / math.max(along, 1e-6)
	local kb = (len - along + gb) / math.max(len - along, 1e-6)
	local a = rightWedge(`{name}a`, foot + eu * ga, -eu, along * ka, ru, height * ka, n, thickness, colour, material, parent)
	local b = rightWedge(`{name}b`, foot - eu * gb, eu, (len - along) * kb, ru, height * kb, n, thickness, colour, material, parent)
	if a then
		table.insert(out, a)
	end
	if b then
		table.insert(out, b)
	end
end

-- Where the run's arc length had got to at the end of the last piece built. The window
-- builds pieces in order (`RoadService.buildPiece`), so carrying one number is enough;
-- anything else -- a piece built out of order, or piece 1 of a new run -- falls back to
-- starting the pattern at zero, which is correct for a fresh road and harmless otherwise.
local markPhase = { n = 0, distance = 0 }

-- Start the dash pattern again from zero. Only `RoadTests` calls it, so that a road built
-- for a measurement comes out the same whatever was built before it.
function Builder.DebugResetMarks()
	markPhase.n, markPhase.distance = 0, 0
end

-- The centre line of one piece: dashes at a fixed interval along the WHOLE run, clipped
-- at both ends of the piece rather than skipped (see the header). Returns the parts.
-- The height of a triangulated segment's surface over `x, z`, or nil if that point is not
-- over either of its triangles. Plain barycentric coordinates in plan, with a whisker of
-- slack so a point exactly on the shared diagonal belongs to one of them rather than to
-- neither.
-- Which segment of `piece` the arc length `dist` falls on.
local function segmentAt(piece: Pieces.Placed, dist: number): number
	local cum = piece.cum
	for i = 1, #cum - 1 do
		if dist <= cum[i + 1] then
			return i
		end
	end
	return math.max(#cum - 1, 1)
end

local function triangleHeightAt(tris, x: number, z: number): number?
	for _, t in tris do
		local a, b, c = t[1], t[2], t[3]
		local d = (b.Z - c.Z) * (a.X - c.X) + (c.X - b.X) * (a.Z - c.Z)
		if math.abs(d) > 1e-9 then
			local l1 = ((b.Z - c.Z) * (x - c.X) + (c.X - b.X) * (z - c.Z)) / d
			local l2 = ((c.Z - a.Z) * (x - c.X) + (a.X - c.X) * (z - c.Z)) / d
			local l3 = 1 - l1 - l2
			if l1 >= -1e-3 and l2 >= -1e-3 and l3 >= -1e-3 then
				return a.Y * l1 + b.Y * l2 + c.Y * l3
			end
		end
	end
	return nil
end

-- A MARK IS LAID ON THE SURFACE THAT WAS BUILT, not on the one the profile describes, and
-- once a segment is triangles those are not the same thing (T-066). `Pieces.poseAt` gives
-- the smooth profile; the triangles pass exactly through every node's cross line and cut
-- the corner in between, so the two differ by up to a tenth of a stud. Measured with the
-- marks laid on the profile: 144 of 888 dash corners were UNDER the road, worst 0.1188
-- studs, which is a dash with a bite out of it. Lifting every mark by that much instead
-- would have left the worst of them standing 0.28 studs proud -- as big as the step this
-- whole change removes -- so each mark is put where the road actually is.
--
-- `tris` is per segment and is absent for a segment built as a box, which is right: a box
-- is only used where the quad IS flat, and there the built surface and the profile are
-- the same surface.
local function centreLine(piece: Pieces.Placed, startDistance: number, tris, parent: Instance): { Part }
	local C = Config.Road
	local interval, dash = C.MarkInterval, C.MarkDashLength
	local marks: { Part } = {}
	if interval <= 0 or dash <= 0 then
		return marks
	end

	local finishDistance = startDistance + piece.length
	local topY = C.SurfaceY + C.MarkLift
	local first = math.floor(startDistance / interval) -- the dash that may straddle the start
	local last = math.floor(finishDistance / interval)

	for k = first, last do
		-- The dash in run-space, then the slice of it that belongs to this piece.
		local a = math.max(k * interval, startDistance) - startDistance
		local b = math.min(k * interval + dash, finishDistance) - startDistance
		local len = b - a
		if len > C.MarkMinLength then
			local mid = (a + b) * 0.5
			local t = mid / piece.length
			-- How far the road that was BUILT is above the road the profile describes,
			-- here, measured along the surface's own up so it can be added to the lift.
			-- LIFTED TO CLEAR ITS OWN HIGHEST CORNER, not its middle. Correcting only the
			-- middle was tried and made things worse -- 144 buried dash corners became 226
			-- -- because a dash is up to a few studs long and straddles the crease where
			-- two triangles meet: the middle sits on the road and a corner goes under it.
			--
			-- THE SEARCH IS LIMITED TO THE SEGMENT THE DASH IS ON AND ITS TWO NEIGHBOURS,
			-- which is as far as a dash can reach. Searching the whole piece is wrong: a
			-- hairpin stack passes over itself, so two triangles can cover the same ground
			-- in PLAN at different heights, and the first match is then wrong by metres.
			local lift = 0
			if tris then
				local seg = segmentAt(piece, mid)
				local near = {}
				for s = seg - 1, seg + 1 do
					local pair = tris[s]
					if pair then
						table.insert(near, pair[1])
						table.insert(near, pair[2])
					end
				end
				local on = Pieces.poseAt(piece, t, C.SurfaceY)
				local up = on.UpVector
				if near[1] and up.Y > 1e-3 then
					local p0, right, fwd = on.Position, on.RightVector, -on.LookVector
					local worst = 0
					for _, c in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
						-- A corner of the dash, ON the profile's own plane, so the plane's
						-- height there is just the corner's own Y.
						local q = p0 + right * (c.X * C.MarkWidth * 0.5) + fwd * (c.Y * len * 0.5)
						local built = triangleHeightAt(near, q.X, q.Z)
						if built then
							worst = math.max(worst, built - q.Y)
						end
					end
					lift = worst / up.Y
				end
			end
			local cf = Pieces.poseAt(piece, t, topY - C.MarkThickness * 0.5 + lift)
			local part = newPart(
				`Mark_{piece.n}_{k}`,
				Vector3.new(C.MarkWidth, C.MarkThickness, len),
				cf,
				C.Colours.Marking,
				Enum.Material.SmoothPlastic, -- paint, not asphalt: it should NOT have grain
				parent
			)
			part.CanCollide = false
			part.CanQuery = false -- the ground rays must never find a marking
			part.CanTouch = false
			marks[#marks + 1] = part
		end
	end
	return marks
end

export type Built = {
	n: number,
	folder: Folder,
	road: { Part },
	barriers: { Part },
	marks: { Part },
	parts: number,
	-- Only filled when `Config.Road.Profile` is on (T-085). Milliseconds, and they add up
	-- to the whole of `Builder.build`: `makeMs` is every `Instance.new` and every property
	-- written while the piece is still OUTSIDE the DataModel, `tagMs` is the
	-- `CollectionService:AddTag` calls alone, and `parentMs` is the single `.Parent` write
	-- that puts the finished subtree into the Workspace.
	makeMs: number?,
	tagMs: number?,
	parentMs: number?,
}

-- Build one piece. `parent` is the road's folder; the piece gets a folder of its own named
-- for its run number, which is what lets the window destroy exactly one piece.
function Builder.build(piece: Pieces.Placed, parent: Instance): Built
	local C = Config.Road
	local surfaceTag = Config.Drift.SurfaceTag
	local surfaceAttr = Config.Drift.SurfaceAttribute

	-- The profile, off by default and one boolean read when it is (`Config.Road.Profile`).
	local profiling = C.Profile == true
	local startedAt = if profiling then os.clock() else 0
	local tagSeconds = 0

	local folder = Instance.new("Folder")
	folder.Name = `Piece_{piece.n}`
	folder:SetAttribute("N", piece.n)
	folder:SetAttribute("Kind", piece.kind)
	folder:SetAttribute("Variant", piece.id)

	local road: { Part } = {}
	local barriers: { Part } = {}
	local tris: { { { Vector3 } } } = {} -- the two triangles of each segment, for the marks

	local halfWidth = C.Width * 0.5
	local barrierOffset = halfWidth + C.BarrierThickness * 0.5
	local nodes = piece.nodes

	if piece.flat then
		for i = 1, #nodes - 1 do
			local a, b = nodes[i], nodes[i + 1]
			local step = yawStep(a.yaw, b.yaw)

			local slab = span(
				`Road_{piece.n}_{i}`,
				a.x,
				a.z,
				b.x,
				b.z,
				C.Width,
				C.Thickness,
				C.SurfaceY,
				halfWidth * step,
				C.Colours.Road,
				C.RoadMaterial,
				folder
			)
			if slab then
				local tagAt = if profiling then os.clock() else 0
				CollectionService:AddTag(slab, surfaceTag)
				if profiling then
					tagSeconds += os.clock() - tagAt
				end
				slab:SetAttribute(surfaceAttr, C.SurfaceTarmac)
				table.insert(road, slab)
			end

			-- Both walls. Each is built from its OWN pair of points -- the centre line
			-- pushed sideways at each node -- so the inner wall comes out shorter than the
			-- outer one on a curve and neither has to be fudged.
			for _, side in { -1, 1 } do
				local ra, rb = Pieces.right(a.yaw), Pieces.right(b.yaw)
				local wall = span(
					`Barrier_{if side < 0 then "L" else "R"}_{piece.n}_{i}`,
					a.x + ra.X * barrierOffset * side,
					a.z + ra.Z * barrierOffset * side,
					b.x + rb.X * barrierOffset * side,
					b.z + rb.Z * barrierOffset * side,
					C.BarrierThickness,
					C.BarrierHeight + C.BarrierSink,
					C.SurfaceY + C.BarrierHeight,
					C.BarrierThickness * 0.5 * step,
					C.Colours.Barrier,
					C.BarrierMaterial,
					folder
				)
				if wall then
					table.insert(barriers, wall)
				end
			end
		end
	else
		-- THE PROFILED PATH. The road rotates about its own centre line, so a banked
		-- segment is a bowl you drive on to from either edge, never a trench on one side
		-- and a wall on the other. (The playground's `levelInnerEdge` lifts the centre
		-- line to keep a banked ring's inner edge down on the plate; a road has no plate
		-- under it and wants the rotation plain.)
		--
		-- Each barrier is built from ITS OWN pair of points, as on the flat -- the centre
		-- line pushed out along the surface's banked right -- so on a banked curve the two
		-- walls differ in length and in height and neither has to be fudged.
		--
		-- A WALL FOLLOWS THE GRADE AND NOT THE BANK, and that is a measured choice rather
		-- than a tidy one. Leaning it with the road puts its inner face OVER the road:
		-- six studs of wall at the 20 degrees `MaxBank` allows overhangs by two, and since
		-- the car's collision box is never rolled either, what that overhang catches is
		-- the car's ROOF while its wheels still have room. Measured on a banked corner
		-- with leaning walls, the car ground along the outside of it at 13 studs/s.
		-- Standing it up costs a little daylight where the wall meets a steeply banked
		-- road, and gives the road its full width back.
		local barrierDrop = (C.BarrierSink - C.BarrierHeight) * 0.5
		for i = 1, #nodes - 1 do
			local a, b = nodes[i], nodes[i + 1]
			local step = yawStep(a.yaw, b.yaw)
			local ra, ua = Pieces.frame(a.yaw, a.pitch, a.bank)
			local rb, ub = Pieces.frame(b.yaw, b.pitch, b.bank)
			local _, wa = Pieces.frame(a.yaw, a.pitch, 0) -- the same up with the bank taken
			local _, wb = Pieces.frame(b.yaw, b.pitch, 0) -- out of it, for the walls
			local pa = Vector3.new(a.x, C.SurfaceY + a.y, a.z)
			local pb = Vector3.new(b.x, C.SurfaceY + b.y, b.z)

			-- THE SEGMENT'S FOUR CORNERS, which are the road and not an approximation of
			-- it: each cross line is shared whole with the neighbour that ends on it.
			local am, ap = pa - ra * halfWidth, pa + ra * halfWidth
			local bm, bp = pb - rb * halfWidth, pb + rb * halfWidth

			local made: { Part } = {}
			if not C.TriangulateSegments or outOfPlane(am, ap, bp, bm) <= PLANAR_EPSILON then
				-- Flat quad: one box lies in it exactly, and a box is a third of the parts.
				local slab = spanFrame(
					`Road_{piece.n}_{i}`,
					pa,
					pb,
					ua,
					ub,
					C.Width,
					C.Thickness,
					C.Thickness * 0.5,
					halfWidth * step,
					C.Colours.Road,
					C.RoadMaterial,
					folder
				)
				if slab then
					table.insert(made, slab)
				end
			else
				-- Not flat, so no box lies in it. Two triangles do, and the diagonal
				-- alternates so a strip of them stays symmetric.
				local t1, t2
				if i % 2 == 1 then
					t1, t2 = { am, ap, bp }, { am, bp, bm }
				else
					t1, t2 = { am, ap, bm }, { ap, bp, bm }
				end
				triangleSlab(`Road_{piece.n}_{i}_1`, t1[1], t1[2], t1[3], C.Thickness, C.Colours.Road, C.RoadMaterial, folder, made)
				triangleSlab(`Road_{piece.n}_{i}_2`, t2[1], t2[2], t2[3], C.Thickness, C.Colours.Road, C.RoadMaterial, folder, made)
				-- Kept UNGROWN and kept PER SEGMENT, so the centre line is laid on the
				-- surface itself rather than on the overlap that stops it hairlining.
				tris[i] = { t1, t2 }
			end
			for _, slab in made do
				local tagAt = if profiling then os.clock() else 0
				CollectionService:AddTag(slab, surfaceTag)
				if profiling then
					tagSeconds += os.clock() - tagAt
				end
				slab:SetAttribute(surfaceAttr, C.SurfaceTarmac)
				table.insert(road, slab)
			end

			for _, side in { -1, 1 } do
				local wall = spanFrame(
					`Barrier_{if side < 0 then "L" else "R"}_{piece.n}_{i}`,
					pa + ra * (barrierOffset * side),
					pb + rb * (barrierOffset * side),
					wa,
					wb,
					C.BarrierThickness,
					C.BarrierHeight + C.BarrierSink,
					barrierDrop,
					C.BarrierThickness * 0.5 * step,
					C.Colours.Barrier,
					C.BarrierMaterial,
					folder
				)
				if wall then
					table.insert(barriers, wall)
				end
			end
		end
	end

	-- The centre line last, so the slabs it sits on already exist.
	local startDistance = if piece.n == markPhase.n + 1 then markPhase.distance else 0
	markPhase.n, markPhase.distance = piece.n, startDistance + piece.length
	local marks = centreLine(piece, startDistance, if next(tris) then tris else nil, folder)

	local madeAt = if profiling then os.clock() else 0
	folder.Parent = parent
	local parentedAt = if profiling then os.clock() else 0

	return {
		n = piece.n,
		folder = folder,
		road = road,
		barriers = barriers,
		marks = marks,
		parts = #road + #barriers + #marks,
		makeMs = if profiling then (madeAt - startedAt - tagSeconds) * 1000 else nil,
		tagMs = if profiling then tagSeconds * 1000 else nil,
		parentMs = if profiling then (parentedAt - madeAt) * 1000 else nil,
	}
end

-- The wall that closes the road behind the car. It is part of the generator's job, not
-- scenery: it moves up with the car so nobody can drive back into pieces that are about
-- to be destroyed. Untagged, like every other wall here.
function Builder.closingBarrier(parent: Instance): Part
	local C = Config.Road
	local part = newPart(
		"ClosingBarrier",
		Vector3.new(C.Width + C.BarrierThickness * 2, C.BarrierHeight * 2, C.BarrierThickness),
		CFrame.new(0, -10000, 0),
		C.Colours.Closing,
		Enum.Material.SmoothPlastic,
		parent
	)
	part.Transparency = C.BarrierTransparency
	return part
end

function Builder.moveClosingBarrier(part: Part, piece: Pieces.Placed, t: number)
	local C = Config.Road
	local cf = Pieces.poseAt(piece, t, C.SurfaceY + C.BarrierHeight)
	part.CFrame = cf
end

return Builder
