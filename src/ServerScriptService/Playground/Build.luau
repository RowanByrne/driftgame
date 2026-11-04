--!nonstrict
-- Build: turns a list of Path nodes into parts. Knows nothing about the layout; it is
-- given nodes, a width and height and bank profiles, and it makes the surface.
--
-- Two rules it never breaks (features/drift-playground.md "Rules and numbers"):
--   * Consecutive nodes share their endpoints, so the top faces meet exactly: a ray
--     walking the surface reads a piecewise-linear curve, never a step at a joint.
--   * Every part it makes is anchored and carries no constraint. Cones are built by
--     the service, not here.

local CollectionService = game:GetService("CollectionService")

local Build = {}

Build.SurfaceTag = "DriftSurface"

local UP = Vector3.yAxis

function Build.part(name: string, size: Vector3, cf: CFrame, colour: Color3, parent: Instance): Part
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

function Build.surface(name: string, size: Vector3, cf: CFrame, colour: Color3, parent: Instance): Part
	local part = Build.part(name, size, cf, colour, parent)
	CollectionService:AddTag(part, Build.SurfaceTag)
	return part
end

-- A building or a standalone block: a wall, never a floor. It is deliberately not tagged
-- DriftSurface, so the drift model's ground ray misses it and driving into one is a
-- collision rather than a climb. It stands on the plate and sinks a stud into it, so no
-- edge-on view ever shows daylight under it.
function Build.block(
	name: string,
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	height: number,
	colour: Color3,
	parent: Instance
): Part
	local sink = 1
	return Build.part(
		name,
		Vector3.new(sizeX, height + sink, sizeZ),
		CFrame.new(x, (height - sink) * 0.5, z),
		colour,
		parent
	)
end

function Build.pillar(name: string, x: number, z: number, radius: number, height: number, colour: Color3, parent: Instance): Part
	local sink = 1
	local part = Build.part(
		name,
		Vector3.new(height + sink, radius * 2, radius * 2),
		CFrame.new(x, (height - sink) * 0.5, z) * CFrame.Angles(0, 0, math.rad(90)),
		colour,
		parent
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- The height and bank profiles, by name. t runs 0 to 1 along the feature.
local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

-- `from` is the height the previous feature ended at, so the chain stays continuous.
function Build.heightProfile(spec: { [string]: any }?, from: number): ((number) -> number, number)
	if not spec then
		return function()
			return from
		end, from
	end
	local shape = spec.shape
	if shape == "crest" then
		local peak = spec.peak
		return function(t: number)
			return from + peak * math.sin(math.pi * t)
		end, from
	elseif shape == "ramp" then
		local to = spec.to
		return function(t: number)
			return from + (to - from) * smoothstep(t)
		end, to
	elseif shape == "launch" then
		-- t^2: eased in at the bottom, STEEPEST AT THE TOP. `smoothstep` eases out as well,
		-- which is a ramp a car arrives at the end of travelling flat -- it does not jump,
		-- it falls off the end (T-026). A ramp that is meant to launch has to end on its
		-- steepest slope, and this is the shape that does it without a crease anywhere.
		local to = spec.to
		return function(t: number)
			return from + (to - from) * t * t
		end, to
	end
	return function()
		return from
	end, from
end

-- The slope a height profile ends on, in studs per stud travelled: what a ramp's lip has
-- to carry on at so the car leaves it pointing up, instead of off a flat shelf.
function Build.endSlope(heightAt: (number) -> number, length: number): number
	local back = math.clamp(1 / math.max(length, 1e-4), 1e-6, 1)
	return (heightAt(1) - heightAt(1 - back)) / (back * length)
end

-- Bank in radians. `sign` is +1 for a left-hand turn and -1 for a right-hand one, so a
-- positive `degrees` always raises the outer edge.
function Build.bankProfile(spec: { [string]: any }?, sign: number): (number) -> number
	if not spec then
		return function()
			return 0
		end
	end
	local radians = math.rad(spec.degrees) * sign
	if spec.shape == "crest" then
		return function(t: number)
			return radians * math.sin(math.pi * t)
		end
	end
	return function()
		return radians
	end
end

-- A banked ribbon rotates about its centre line, which would bury its inner edge in the
-- plate. This lifts the centre line by just enough to keep that inner edge level with
-- the road, so a banked corner is a bowl you drive on to, never a wall or a trench.
function Build.levelInnerEdge(heightAt: (number) -> number, bankAt: (number) -> number, halfWidth: number): (number) -> number
	return function(t: number)
		return heightAt(t) + halfWidth * math.abs(math.sin(bankAt(t)))
	end
end

-- The world point and axes of a node, once the height and bank profiles are applied.
function Build.frame(node: { pos: Vector3, yaw: number }, y: number, bank: number): (Vector3, Vector3, Vector3)
	local rightFlat = Vector3.new(math.cos(node.yaw), 0, -math.sin(node.yaw))
	local cosB, sinB = math.cos(bank), math.sin(bank)
	local right = rightFlat * cosB + UP * sinB
	local up = -rightFlat * sinB + UP * cosB
	return Vector3.new(node.pos.X, y, node.pos.Z), right, up
end

export type RibbonOptions = {
	name: string,
	width: number,
	thickness: number,
	colour: Color3,
	baseY: number, -- the road's top, in world Y, where the profile reads zero
	heightAt: (number) -> number,
	bankAt: (number) -> number,
	closed: boolean?, -- a ring: the last node is the first
	parent: Instance,
}

-- Builds one part per pair of nodes. Returns the parts and the world points of the
-- centre line, which the service keeps so tests can walk the surface.
function Build.ribbon(nodes: { { pos: Vector3, yaw: number } }, opts: RibbonOptions): ({ Part }, { Vector3 })
	local count = #nodes
	local parts: { Part } = {}
	local points: { Vector3 } = {}

	local tops: { Vector3 } = {}
	local ups: { Vector3 } = {}
	for i = 1, count do
		local t = (i - 1) / (count - 1)
		local y = opts.baseY + opts.heightAt(t)
		local pos, _, up = Build.frame(nodes[i], y, opts.bankAt(t))
		tops[i] = pos
		ups[i] = up
		points[i] = pos
	end

	local half = opts.thickness * 0.5
	local overlap = 0.2
	local halfWidth = opts.width * 0.5
	for i = 1, count - 1 do
		local a, b = tops[i], tops[i + 1]
		local delta = b - a
		local length = delta.Magnitude
		-- On a curve, two neighbouring boxes share their centre point but turn by the
		-- yaw step, so their *outer* corners pull apart by (half the width) x (that
		-- step): the wedge that reads from the ground as a bite out of the rim. Lengthen
		-- each box by exactly that, and the outer corners meet instead; the inner ones
		-- overlap, which a banked surface hides because neighbours are never coplanar.
		local yawStep = math.abs(nodes[i + 1].yaw - nodes[i].yaw)
		if yawStep > math.pi then
			yawStep = math.abs(yawStep - 2 * math.pi)
		end
		local close = halfWidth * yawStep
		if length > 1e-4 then
			local forward = delta.Unit
			local up = (ups[i] + ups[i + 1]).Unit
			local right = forward:Cross(up).Unit
			-- Re-square the frame: right and forward are already perpendicular enough,
			-- and up is rebuilt from them so the box is not skewed.
			up = right:Cross(forward).Unit
			local centre = (a + b) * 0.5 - up * half
			local cf = CFrame.fromMatrix(centre, right, up)
			local part = Build.surface(
				`{opts.name}_{i}`,
				Vector3.new(opts.width, opts.thickness, length + overlap + close),
				cf,
				opts.colour,
				opts.parent
			)
			table.insert(parts, part)
		end
	end

	return parts, points
end

--------------------------------------------------------------------------------
-- The two elevated features' SHAPES, with no parts in them
--------------------------------------------------------------------------------
-- Here rather than in PlaygroundService so that the world and the collision tests build
-- exactly the same shape: the tests stand their own copy of the circle and the ramp far
-- from the world and drive at it (T-026).

-- The banked band, and the apron that climbs to it. `right` along a `Path.ring` points
-- INWARD, so `levelInnerEdge` levels the band's inner edge with the plate and leaves its
-- rim standing `width x sin(bank)` proud; the apron is banked the other way, which levels
-- its OUTER edge with the plate and lands its inner edge exactly on that rim. The two
-- together are one continuous surface from the yard to the middle.
function Build.circleProfiles(spec)
	local zero = function(): number
		return 0
	end
	local bankAt = Build.bankProfile({ shape = "flat", degrees = spec.bank }, -1) -- a right-hand turn
	local heightAt = Build.levelInnerEdge(zero, bankAt, spec.width * 0.5)
	local skirtBankAt = Build.bankProfile({ shape = "flat", degrees = spec.skirt.bank }, 1)
	local skirtHeightAt = Build.levelInnerEdge(zero, skirtBankAt, spec.skirt.width * 0.5)
	return bankAt, heightAt, skirtBankAt, skirtHeightAt
end

-- The ramp's climb and its lip. The lip is a straight continuation of the slope the climb
-- ended on, so there is no crease between them and no flat shelf at the top to arrive at
-- travelling level.
function Build.rampProfiles(spec)
	local climbAt = Build.heightProfile({ shape = spec.shape, to = spec.rise }, 0)
	local slope = Build.endSlope(climbAt, spec.length)
	local lipAt = function(t: number): number
		return spec.rise + slope * spec.lip.length * t
	end
	return climbAt, lipAt, slope
end

return Build
