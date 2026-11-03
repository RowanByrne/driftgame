--!strict
-- Path: the pure maths the playground is walked with. No instances, no Layout.
--
-- A cursor is a pose on the flat plane: a position (y ignored) and a yaw in radians,
-- where yaw 0 faces -Z, the same as CFrame.Angles(0, yaw, 0).LookVector.
-- Walking a straight or an arc returns n+1 nodes, the first being the pose it started
-- from, and leaves the cursor at the far end. Every node of an arc sits on the true
-- circle, so consecutive nodes are its chords: more segments, a closer curve.

local Path = {}

export type Node = { pos: Vector3, yaw: number }
export type Cursor = { pos: Vector3, yaw: number }

function Path.forward(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- The cursor's right: used for the road's width and for banking.
function Path.right(yaw: number): Vector3
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
end

function Path.cursor(x: number, z: number, headingDegrees: number): Cursor
	return { pos = Vector3.new(x, 0, z), yaw = math.rad(headingDegrees) }
end

function Path.clone(c: Cursor): Cursor
	return { pos = c.pos, yaw = c.yaw }
end

function Path.straight(c: Cursor, length: number, n: number): { Node }
	local nodes: { Node } = { { pos = c.pos, yaw = c.yaw } }
	local step = length / n
	for _ = 1, n do
		c.pos = c.pos + Path.forward(c.yaw) * step
		table.insert(nodes, { pos = c.pos, yaw = c.yaw })
	end
	return nodes
end

-- Positive angleDegrees turns left, negative right. Each segment turns half the step,
-- advances one chord, then turns the other half, which is exact for a circle.
function Path.arc(c: Cursor, angleDegrees: number, radius: number, n: number): { Node }
	local nodes: { Node } = { { pos = c.pos, yaw = c.yaw } }
	local dTheta = math.rad(angleDegrees) / n
	local chord = 2 * radius * math.sin(math.abs(dTheta) * 0.5)
	for _ = 1, n do
		c.yaw += dTheta * 0.5
		c.pos = c.pos + Path.forward(c.yaw) * chord
		c.yaw += dTheta * 0.5
		table.insert(nodes, { pos = c.pos, yaw = c.yaw })
	end
	return nodes
end

-- A closed ring of n chords around a centre, walked clockwise in XZ so that the
-- cursor's right points at the centre: a right-hand turn, the same as arc(-360, ...).
function Path.ring(centre: Vector3, radius: number, n: number): { Node }
	local nodes: { Node } = {}
	for i = 0, n do
		local phi = (i / n) * math.pi * 2
		local pos = Vector3.new(centre.X + math.cos(phi) * radius, 0, centre.Z + math.sin(phi) * radius)
		table.insert(nodes, { pos = pos, yaw = math.pi - phi })
	end
	return nodes
end

-- The arc length a straight or arc covers, so a feature can be resampled at a spacing.
function Path.length(kind: string, step: { [string]: any }): number
	if kind == "arc" then
		return math.abs(math.rad(step.angle)) * step.radius
	end
	return step.length
end

return Path
