--!strict
-- SplineParts: a stretch of the spline road laid as ordinary parts (features/spline-road.md,
-- T-134). Not the road the game draws -- that is a mesh (step 3) and the car never asks it
-- anything. This is the same surface cut into triangles the way the piece road cuts its
-- own did (the triangle slab below, from the piece road's `Road/Builder`, T-066), for two jobs:
--
--   * THE YARDSTICK. Built queryable and tagged `DriftSurface`, it is a road the live
--     world's rays and sweeps can drive on, so the spline world's answers can be checked
--     against the answers the game has always trusted, on the very same curve.
--   * A STAND-IN TO LOOK AT. Built with nothing queryable, it is something to see while the
--     car drives on the maths, before the mesh exists.
--
-- Cross-sections every `step` studs of road, each slice two triangles (four wedges), and an
-- upright barrier box per slice either side, inner face at exactly half the width as on the
-- piece road.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Spline = require(script.Parent.Spline)

local SplineParts = {}

--------------------------------------------------------------------------------
-- One triangle of road as wedge slabs (moved here from `Road/Builder` in T-249)
--------------------------------------------------------------------------------

-- An anchored wedge, as the piece road's builder made every part (`Road/Builder`, gone
-- with the piece road in T-249).
local function newPart(name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material, parent: Instance, className: string?): Part
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

-- Studs every triangle is grown by, out from its own centroid and IN ITS OWN PLANE, so
-- its plane is untouched and only its outline moves. This is the piece road's box overlap done for
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


export type Options = {
	step: number?, -- studs between cross-sections (default 4)
	queryable: boolean?, -- solid to rays and sweeps, and tagged as road (default false)
	barriers: boolean?, -- build the side barriers (default true)
	yieldEvery: number?, -- slices between task.wait()s; nil never yields
}

local function point(spline: Spline.Spline, s: number, d: number): Vector3
	return Vector3.new(spline:surfaceXYZ(s, d))
end

-- Lay road from s0 to s1 under `parent`. Returns the parts made.
function SplineParts.build(spline: Spline.Spline, s0: number, s1: number, parent: Instance, opts: Options?): { BasePart }
	local o: Options = opts or {}
	local R = Config.Road
	local D = Config.Drift
	local step = o.step or 4
	local queryable = o.queryable == true
	local half = R.Width * 0.5
	local out: { BasePart } = {}
	local slices = math.max(1, math.ceil((s1 - s0) / step))
	local ds = (s1 - s0) / slices

	local folder = Instance.new("Folder")
	folder.Name = "Slices"
	local made = 0
	for i = 0, slices - 1 do
		local sa, sb = s0 + i * ds, s0 + (i + 1) * ds
		local la, ra = point(spline, sa, -half), point(spline, sa, half)
		local lb, rb = point(spline, sb, -half), point(spline, sb, half)
		local tris: { BasePart } = {}
		-- the diagonal alternates, as on the piece road, so no one edge carries the error
		if i % 2 == 0 then
			triangleSlab(`Road_{i}_1`, la, ra, rb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
			triangleSlab(`Road_{i}_2`, la, rb, lb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
		else
			triangleSlab(`Road_{i}_1`, la, ra, lb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
			triangleSlab(`Road_{i}_2`, ra, rb, lb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
		end
		for _, p in tris do
			p.CanQuery = queryable
			p.CanCollide = false
			p.CanTouch = false
			p.CastShadow = true -- T-178, as the mesh road
			if queryable then
				p:AddTag(D.SurfaceTag)
				p:SetAttribute(D.SurfaceAttribute, R.SurfaceTarmac)
			end
			table.insert(out, p)
		end
		if o.barriers ~= false then
			for _, side in { -1, 1 } do
				local off = side * (half + R.BarrierThickness * 0.5)
				local a = point(spline, sa, off)
				local b = point(spline, sb, off)
				-- upright, along the chord, standing from the road edge's height
				local ea = spline:heightAt(sa) + side * half * math.tan(spline:bankAt(sa))
				local eb = spline:heightAt(sb) + side * half * math.tan(spline:bankAt(sb))
				local base = (ea + eb) * 0.5
				local mid = Vector3.new((a.X + b.X) * 0.5, base + (R.BarrierHeight - R.BarrierSink) * 0.5, (a.Z + b.Z) * 0.5)
				local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
				local len = flat.Magnitude
				local cf = CFrame.lookAt(mid, mid + flat, Vector3.yAxis)
				local wall = Instance.new("Part")
				wall.Name = `Barrier_{if side < 0 then "L" else "R"}_{i}`
				wall.Anchored = true
				wall.CanCollide = false
				wall.CanTouch = false
				wall.CanQuery = queryable
				wall.CastShadow = true -- T-178, as the mesh road's barriers
				wall.Material = R.BarrierMaterial
				wall.Color = R.Colours.Barrier
				-- a little long, so neighbouring slices overlap rather than leave a slot
				wall.Size = Vector3.new(R.BarrierThickness, R.BarrierHeight + R.BarrierSink + math.abs(eb - ea), len + 0.3)
				wall.CFrame = cf
				wall.Parent = folder
				table.insert(out, wall)
			end
		end
		made += 1
		if o.yieldEvery and made % o.yieldEvery == 0 then
			folder.Parent = parent
			folder = Instance.new("Folder")
			folder.Name = "Slices"
			task.wait()
		end
	end
	folder.Parent = parent
	return out
end

return SplineParts
