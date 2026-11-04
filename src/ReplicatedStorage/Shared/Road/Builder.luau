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
	parent: Instance
): Part
	local part = Instance.new("Part")
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
local function centreLine(piece: Pieces.Placed, startDistance: number, parent: Instance): { Part }
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
			local cf = Pieces.poseAt(piece, mid / piece.length, topY - C.MarkThickness * 0.5)
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
}

-- Build one piece. `parent` is the road's folder; the piece gets a folder of its own named
-- for its run number, which is what lets the window destroy exactly one piece.
function Builder.build(piece: Pieces.Placed, parent: Instance): Built
	local C = Config.Road
	local surfaceTag = Config.Drift.SurfaceTag
	local surfaceAttr = Config.Drift.SurfaceAttribute

	local folder = Instance.new("Folder")
	folder.Name = `Piece_{piece.n}`
	folder:SetAttribute("N", piece.n)
	folder:SetAttribute("Kind", piece.kind)
	folder:SetAttribute("Variant", piece.id)

	local road: { Part } = {}
	local barriers: { Part } = {}

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
				CollectionService:AddTag(slab, surfaceTag)
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
				CollectionService:AddTag(slab, surfaceTag)
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
	local marks = centreLine(piece, startDistance, folder)

	folder.Parent = parent
	return {
		n = piece.n,
		folder = folder,
		road = road,
		barriers = barriers,
		marks = marks,
		parts = #road + #barriers + #marks,
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
