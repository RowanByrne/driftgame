--!strict
-- Internal to SplineMesh. A caster is fitted inward, then clipped against
-- inward halfspaces of the exact triangles/footprint that contain it. No sampling of
-- the spline, guessed setback, or absolute height can certify an opaque caster.
local Shadow = {}
export type Plane = { n: Vector3, d: number, span: boolean? }
local MARGIN = 0.12 -- also covers the rendered mesh's measured ~0.03-stud quantization

function Shadow.plane(out: { Plane }, a: Vector3, b: Vector3, c: Vector3, outward: Vector3)
	local n = (b - a):Cross(c - a)
	if n.Magnitude < 1e-7 then return end
	n = n.Unit
	if n:Dot(outward) < 0 then n = -n end
	table.insert(out, { n = n, d = n:Dot(a) })
end

function Shadow.edge(out: { Plane }, a: Vector3, b: Vector3, inside: Vector3)
	local n = (b - a):Cross(Vector3.yAxis)
	if n.Magnitude < 1e-7 then return end
	n = n.Unit
	if n:Dot(inside - a) > 0 then n = -n end
	table.insert(out, { n = n, d = n:Dot(a) })
end

function Shadow.fit(cf: CFrame, size: Vector3, planes: { Plane }, inward: Vector3?): (CFrame?, Vector3?)
	local localPlanes = table.create(#planes)
	for i, p in planes do
		localPlanes[i] = {
			p.n:Dot(cf.XVector), p.n:Dot(cf.YVector), p.n:Dot(cf.ZVector),
			limit = p.d - p.n:Dot(cf.Position) - MARGIN,
			rate = if inward then p.n:Dot(inward) else 0,
		}
	end
	local shift = 0
	-- First preserve the full face height by finding an ACTUAL feasible setback.
	-- A fixed setback followed only by trimming can throw away the foot of a tall
	-- face when an upper jag's plane extends in front of it. Span ends are trimmed
	-- afterwards; all other planes bound this translation, including the crest.
	if inward then
		local from, to = 0, math.huge
		for i, p in planes do
			if p.span then continue end
			local n = localPlanes[i]
			local reach = (math.abs(n[1]) * size.X + math.abs(n[2]) * size.Y + math.abs(n[3]) * size.Z) / 2
			local room, rate = n.limit - reach, n.rate
			if rate > 1e-7 then to = math.min(to, room / rate)
			elseif rate < -1e-7 then from = math.max(from, room / rate)
			elseif room < 0 then to = -1 end
		end
		if from <= to then shift = from; cf += inward * shift end
	end
	local lo, hi = { -size.X / 2, -size.Y / 2, -size.Z / 2 }, { size.X / 2, size.Y / 2, size.Z / 2 }
	for _, n in localPlanes do
		local limit = n.limit - n.rate * shift
		local extreme = 0
		for i = 1, 3 do extreme += n[i] * (if n[i] > 0 then hi[i] else lo[i]) end
		local excess = extreme - limit
		for _ = 1, 3 do
			if excess <= 1e-5 then break end
			-- Trim the cheapest fraction of one dimension. Every trim is a subset, so a
			-- plane already satisfied stays satisfied. Prefer keeping caster thickness.
			local axis, best = 0, 0
			for i = 1, 3 do
				local room = math.abs(n[i]) * math.max(0, hi[i] - lo[i] - 0.1)
				local score = room / (if i == 3 then 4 else 1)
				if room > 1e-6 and score > best then axis, best = i, score end
			end
			if axis == 0 then return nil, nil end
			local take = math.min(excess / math.abs(n[axis]), hi[axis] - lo[axis] - 0.1)
			if n[axis] > 0 then hi[axis] -= take else lo[axis] += take end
			excess -= take * math.abs(n[axis])
		end
		if excess > 1e-4 then return nil, nil end
	end
	local fitted = Vector3.new(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
	local frame = cf * CFrame.new((lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2)
	-- Check the support of the WHOLE box, not only sampled face points.
	for _, p in planes do
		local reach = (math.abs(p.n:Dot(frame.XVector)) * fitted.X + math.abs(p.n:Dot(frame.YVector)) * fitted.Y + math.abs(p.n:Dot(frame.ZVector)) * fitted.Z) / 2
		if p.n:Dot(frame.Position) + reach > p.d - MARGIN * 0.5 then return nil, nil end
	end
	return frame, fitted
end

return Shadow
