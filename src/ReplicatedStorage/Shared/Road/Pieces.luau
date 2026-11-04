--!strict
-- Pieces: what a road piece IS, as pure maths. No instances, no Workspace, no service.
--
-- A piece is one length of road with TWO SOCKETS -- a start and an end, each a position
-- and a heading -- and that is all the joining needs:
--
--   ROTATE THE NEW PIECE ABOUT ITS OWN START SOCKET until that socket's heading matches
--   the previous piece's end socket, THEN TRANSLATE IT INTO PLACE.
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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Pieces = {}

export type Socket = { x: number, z: number, yaw: number }
export type Node = { x: number, z: number, yaw: number }

-- An oriented rectangle on the ground: centre, its long axis, and the half-extent along
-- that axis and across it.
export type Quad = { cx: number, cz: number, ux: number, uz: number, hu: number, hv: number }

export type Variant = {
	id: string, -- `Straight`, `CornerL`, `CornerR`: the placeable unit
	kind: string, -- `Straight`, `Corner`: the piece type it is a version of
	dir: number, -- +1 left, -1 right, 0 neither
	weight: number,
	minPieces: number,
	radius: number?,
	arcDeg: number?,
	length: number, -- arc length down the centre
	nodes: { Node }, -- local centre line; nodes[1] is the start socket at the origin
	cum: { number }, -- arc length at each node, cum[1] = 0
	endSocket: Socket,
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

--------------------------------------------------------------------------------
-- The local shapes
--------------------------------------------------------------------------------

-- A straight is ONE segment however long it is, because it is straight: cutting it up
-- would only cost parts and gain nothing a ground ray could tell apart.
local function straightNodes(length: number): ({ Node }, { number })
	return { { x = 0, z = 0, yaw = 0 }, { x = 0, z = -length, yaw = 0 } }, { 0, length }
end

-- A corner is short straight segments. Each one turns half the step, advances one chord,
-- then turns the other half, which puts every node exactly on the true circle: the
-- segments are its chords, so more of them is a closer curve and the error is
-- chord^2 / (8 x radius) (`Config.Road.MaxSegmentChord`).
local function arcNodes(radius: number, arcDeg: number, maxChord: number): ({ Node }, { number })
	local total = math.rad(arcDeg)
	local arcLength = math.abs(total) * radius
	local n = math.max(1, math.ceil(arcLength / maxChord))
	local dTheta = total / n
	local chord = 2 * radius * math.sin(math.abs(dTheta) * 0.5)

	local nodes: { Node } = { { x = 0, z = 0, yaw = 0 } }
	local cum: { number } = { 0 }
	local x, z, yaw = 0, 0, 0
	for i = 1, n do
		yaw += dTheta * 0.5
		local fx, fz = forward(yaw)
		x += fx * chord
		z += fz * chord
		yaw += dTheta * 0.5
		nodes[i + 1] = { x = x, z = z, yaw = yaw }
		cum[i + 1] = (arcLength / n) * i
	end
	return nodes, cum
end

--------------------------------------------------------------------------------
-- The variant set, built once from the config
--------------------------------------------------------------------------------

local function makeVariant(id: string, kind: string, spec: any, dir: number, maxChord: number): Variant
	local nodes, cum
	local length: number
	if kind == "Corner" then
		nodes, cum = arcNodes(spec.Radius, spec.Arc * dir, maxChord)
		length = math.rad(spec.Arc) * spec.Radius
	else
		nodes, cum = straightNodes(spec.Length)
		length = spec.Length
	end
	local last = nodes[#nodes]
	return {
		id = id,
		kind = kind,
		dir = dir,
		weight = spec.weight or 1,
		minPieces = spec.minPieces or 0,
		radius = if kind == "Corner" then spec.Radius else nil,
		arcDeg = if kind == "Corner" then spec.Arc * dir else nil,
		length = length,
		nodes = nodes,
		cum = cum,
		endSocket = { x = last.x, z = last.z, yaw = last.yaw },
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

function Pieces.place(variant: Variant, socket: Socket, n: number): Placed
	local C = Config.Road
	local hv = Pieces.footprintHalfWidth()
	local slack = C.OverlapSlack

	local nodes: { Node } = table.create(#variant.nodes)
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for i, p in variant.nodes do
		local x, z = transform(p.x, p.z, socket)
		nodes[i] = { x = x, z = z, yaw = socket.yaw + p.yaw }
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
		start = { x = socket.x, z = socket.z, yaw = socket.yaw },
		finish = { x = last.x, z = last.z, yaw = last.yaw },
		nodes = nodes,
		cum = variant.cum,
		length = variant.length,
		quads = quads,
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
	}
end

--------------------------------------------------------------------------------
-- Do two of them overlap?
--------------------------------------------------------------------------------

-- Two oriented rectangles, by separating axes: four axes in two dimensions, and a gap on
-- any one of them is a gap.
local function quadsOverlap(a: Quad, b: Quad): boolean
	local dx, dz = b.cx - a.cx, b.cz - a.cz
	local axes = {
		a.ux,
		a.uz,
		-a.uz,
		a.ux, -- a's across axis is its long axis turned 90 degrees
		b.ux,
		b.uz,
		-b.uz,
		b.ux,
	}
	for i = 1, 8, 2 do
		local ax, az = axes[i], axes[i + 1]
		local ra = a.hu * math.abs(a.ux * ax + a.uz * az) + a.hv * math.abs(-a.uz * ax + a.ux * az)
		local rb = b.hu * math.abs(b.ux * ax + b.uz * az) + b.hv * math.abs(-b.uz * ax + b.ux * az)
		if math.abs(dx * ax + dz * az) >= ra + rb then
			return false
		end
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
	for _, qa in a.quads do
		for _, qb in b.quads do
			if quadsOverlap(qa, qb) then
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
-- the road goes.
function Pieces.poseAt(piece: Placed, t: number, y: number): CFrame
	local want = math.clamp(t, 0, 1) * piece.length
	for i = 1, #piece.nodes - 1 do
		local c0, c1 = piece.cum[i], piece.cum[i + 1]
		if want <= c1 or i == #piece.nodes - 1 then
			local s = if c1 > c0 then (want - c0) / (c1 - c0) else 0
			local a, b = piece.nodes[i], piece.nodes[i + 1]
			local x = a.x + (b.x - a.x) * s
			local z = a.z + (b.z - a.z) * s
			local yaw = a.yaw + (b.yaw - a.yaw) * s
			return CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		end
	end
	local a = piece.nodes[1]
	return CFrame.new(a.x, y, a.z) * CFrame.Angles(0, a.yaw, 0)
end

return Pieces
