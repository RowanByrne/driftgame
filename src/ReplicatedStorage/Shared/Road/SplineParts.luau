--!strict
-- SplineParts: a stretch of the spline road laid as ordinary parts (features/spline-road.md,
-- T-134). Not the road the game draws -- that is a mesh (step 3) and the car never asks it
-- anything. This is the same surface cut into triangles the way the piece road cuts its
-- own (`Road/Builder.triangleSlab`), for two jobs:
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
local Builder = require(script.Parent.Builder)
local Spline = require(script.Parent.Spline)

local SplineParts = {}

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
			Builder.triangleSlab(`Road_{i}_1`, la, ra, rb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
			Builder.triangleSlab(`Road_{i}_2`, la, rb, lb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
		else
			Builder.triangleSlab(`Road_{i}_1`, la, ra, lb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
			Builder.triangleSlab(`Road_{i}_2`, ra, rb, lb, R.Thickness, R.Colours.Road, R.RoadMaterial, folder, tris :: any)
		end
		for _, p in tris do
			p.CanQuery = queryable
			p.CanCollide = false
			p.CanTouch = false
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
				wall.CastShadow = false
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
