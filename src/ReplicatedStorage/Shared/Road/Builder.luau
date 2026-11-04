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
-- One rule a curve breaks if it is built naively (learned the hard way in the playground,
-- T-026): two neighbouring boxes on a curve share their centre point but turn by the yaw
-- step, so their OUTER corners pull apart by (half the width) x (that step) and the gap
-- reads from the ground as a bite out of the edge. Each box is lengthened by exactly
-- that, so the outer corners meet and the inner ones overlap instead.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Pieces = require(script.Parent.Pieces)

local Builder = {}

local OVERLAP = 0.2 -- studs every box is lengthened by so no joint can show a hairline

local function newPart(name: string, size: Vector3, cf: CFrame, colour: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
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
	parent: Instance
): Part?
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-4 then
		return nil
	end
	local yaw = math.atan2(-dx, -dz) -- the heading whose forward is (dx, dz)
	local cf = CFrame.new((ax + bx) * 0.5, topY - height * 0.5, (az + bz) * 0.5) * CFrame.Angles(0, yaw, 0)
	return newPart(name, Vector3.new(width, height, len + OVERLAP + extra), cf, colour, parent)
end

export type Built = {
	n: number,
	folder: Folder,
	road: { Part },
	barriers: { Part },
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
			folder
		)
		if slab then
			CollectionService:AddTag(slab, surfaceTag)
			slab:SetAttribute(surfaceAttr, C.SurfaceTarmac)
			table.insert(road, slab)
		end

		-- Both walls. Each is built from its OWN pair of points -- the centre line pushed
		-- sideways at each node -- so the inner wall comes out shorter than the outer one
		-- on a curve and neither has to be fudged.
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
				folder
			)
			if wall then
				table.insert(barriers, wall)
			end
		end
	end

	folder.Parent = parent
	return { n = piece.n, folder = folder, road = road, barriers = barriers, parts = #road + #barriers }
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
