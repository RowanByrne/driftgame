--!strict
-- Horizon: the shapes of the mountains round the endless run, as triangles
-- (docs/game/features/horizon.md, T-150). Pure: no instances, the same answer for the same
-- config on every client. `Drift/HorizonView` draws them.
--
-- Every point is relative to the layer's own centre, at the height of the road's start: the
-- view puts each layer round the camera.
--
--   THE RIDGES: per layer, a ring of ridge vertices (peaks and saddles) at `Radius`, and a
--   ring of foot vertices `Depth` nearer and half a step round. Joined up, that is a strip of
--   triangles: one face falling from two ridge vertices to a foot, then one rising from two
--   feet to a ridge vertex, round the ring. The faces lean back, so the sun lights them
--   differently face by face.
--
--   THE SNOW PEAK: a cone at a fixed bearing, only its half facing the camera, in rings:
--   foot, shoulder, snow line, summit. The faces below the snow line are rock, above it snow.
--
--   THE VALLEY FLOOR (`floor`): square plates under the near layer, far below the cliffs.
--
-- A triangle longer than `MaxEdge` on any side is halved across that side until none is,
-- because a part may be at most 2 048 studs on a side.

local Horizon = {}

export type Triangle = { a: Vector3, b: Vector3, c: Vector3, colour: Color3 }
export type Layer = {
	name: string,
	lag: number,
	maxLag: number,
	radius: number,
	triangles: { Triangle },
}
export type Layout = { layers: { Layer }, triangles: number }

local TAU = 2 * math.pi

local function shade(colour: Color3, by: number): Color3
	local k = 1 + by
	return Color3.new(math.clamp(colour.R * k, 0, 1), math.clamp(colour.G * k, 0, 1), math.clamp(colour.B * k, 0, 1))
end

-- Halve a triangle across its longest side until no side is longer than `maxEdge`.
function Horizon.split(t: Triangle, maxEdge: number, out: { Triangle })
	local ab, bc, ca = (t.b - t.a).Magnitude, (t.c - t.b).Magnitude, (t.a - t.c).Magnitude
	local longest = math.max(ab, bc, ca)
	if longest <= maxEdge then
		table.insert(out, t)
		return
	end
	local a, b, c = t.a, t.b, t.c
	if bc == longest then
		a, b, c = t.b, t.c, t.a
	elseif ca == longest then
		a, b, c = t.c, t.a, t.b
	end
	-- `a`-`b` is the longest side now
	local m = (a + b) * 0.5
	Horizon.split({ a = a, b = m, c = c, colour = t.colour }, maxEdge, out)
	Horizon.split({ a = m, b = b, c = c, colour = t.colour }, maxEdge, out)
end

-- A point on a ring: `angle` radians clockwise from -Z (seen from above), `r` out, `y` up.
local function onRing(angle: number, r: number, y: number): Vector3
	return Vector3.new(math.sin(angle) * r, y, -math.cos(angle) * r)
end

local function ridgeLayer(L: any, rng: Random, maxEdge: number): Layer
	local n: number = L.Segments
	local step = TAU / n
	local lo, hi = L.Height[1], L.Height[2]
	local phase1, phase2 = rng:NextNumber(0, TAU), rng:NextNumber(0, TAU)
	local w1, w2 = L.Waves[1], L.Waves[2]

	local ridge: { Vector3 } = {}
	local foot: { Vector3 } = {}
	for k = 0, n - 1 do
		local angle = (k + rng:NextNumber(-L.AngleJitter, L.AngleJitter)) * step
		-- 0..1: two slow swells round the ring, and this vertex's own jump
		local swell = 0.5 + 0.3 * math.sin(w1 * angle + phase1) + 0.2 * math.sin(w2 * angle + phase2)
		local u = math.clamp(swell + L.Rough * rng:NextNumber(-1, 1), 0, 1)
		local r = L.Radius * (1 + rng:NextNumber(-L.RadiusJitter, L.RadiusJitter))
		ridge[k + 1] = onRing(angle, r, lo + (hi - lo) * u)
		local footAngle = (k + 0.5 + rng:NextNumber(-L.AngleJitter, L.AngleJitter) * 0.5) * step
		local footR = L.Radius * (1 - L.Depth) * (1 + rng:NextNumber(-L.RadiusJitter, L.RadiusJitter))
		foot[k + 1] = onRing(footAngle, footR, L.Base)
	end

	local tris: { Triangle } = {}
	for k = 1, n do
		local nextK = k % n + 1
		-- falling: ridge k, ridge k+1, the foot between them
		Horizon.split({
			a = ridge[k],
			b = ridge[nextK],
			c = foot[k],
			colour = shade(L.Colour, rng:NextNumber(-L.Shade, L.Shade)),
		}, maxEdge, tris)
		-- rising: the foot before ridge k+1, the foot after it, ridge k+1
		Horizon.split({
			a = foot[k],
			b = foot[nextK],
			c = ridge[nextK],
			colour = shade(L.Colour, rng:NextNumber(-L.Shade, L.Shade)),
		}, maxEdge, tris)
	end

	return { name = L.Name, lag = L.Lag, maxLag = L.MaxLag, radius = L.Radius, triangles = tris }
end

local function peakLayer(P: any, rng: Random, maxEdge: number): Layer
	local bearing = math.rad(P.Bearing)
	local centre = onRing(bearing, P.Radius, 0)
	-- the cone's own frame: `toward` points from the peak back at the camera
	local toward = -Vector3.new(centre.X, 0, centre.Z).Unit
	local side = Vector3.yAxis:Cross(toward)
	local function around(angle: number, r: number, y: number): Vector3
		-- angle 0 faces the camera
		return centre + toward * (math.cos(angle) * r) + side * (math.sin(angle) * r) + Vector3.yAxis * y
	end

	local sides: number = P.Sides
	-- the half facing the camera, and one face's worth more each side for the silhouette
	local spanHalf = math.pi / 2 + math.pi / sides
	local stepA = 2 * spanHalf / sides
	local H = P.Height
	local summit = centre
		+ toward * (P.Foot * P.Lean * rng:NextNumber(-1, 1))
		+ side * (P.Foot * P.Lean * rng:NextNumber(-1, 1))
		+ Vector3.yAxis * H

	-- the rings, foot to snow line: the shoulder and snow line narrow towards the summit
	local footRing, shoulderRing, snowRing = {}, {}, {}
	for i = 0, sides do
		local angle = -spanHalf + i * stepA
		local jag = 1 + rng:NextNumber(-0.08, 0.08)
		footRing[i + 1] = around(angle, P.Foot * jag, P.Base)
		local sh = P.Shoulder + rng:NextNumber(-0.04, 0.04)
		shoulderRing[i + 1] = around(angle, P.Foot * (1 - sh) * 0.75 * jag, H * sh)
		local sn = P.SnowLine + rng:NextNumber(-P.SnowJag, P.SnowJag)
		-- the snow line ring sits on the straight line from the shoulder to the summit
		local onLine = (sn - sh) / (1 - sh)
		local shoulderPoint = shoulderRing[i + 1]
		snowRing[i + 1] = shoulderPoint:Lerp(summit, onLine)
	end

	local tris: { Triangle } = {}
	local function face(a: Vector3, b: Vector3, c: Vector3, colour: Color3)
		Horizon.split({ a = a, b = b, c = c, colour = shade(colour, rng:NextNumber(-P.Shade, P.Shade)) }, maxEdge, tris)
	end
	for i = 1, sides do
		local j = i + 1
		face(footRing[i], footRing[j], shoulderRing[i], P.Rock)
		face(shoulderRing[i], footRing[j], shoulderRing[j], P.Rock)
		face(shoulderRing[i], shoulderRing[j], snowRing[i], P.Rock)
		face(snowRing[i], shoulderRing[j], snowRing[j], P.Rock)
		face(snowRing[i], snowRing[j], summit, P.Snow)
	end

	return { name = "Peak", lag = 0, maxLag = 0, radius = P.Radius, triangles = tris }
end

-- Every layer's triangles, nearest first, the snow peak last.
function Horizon.layout(config: any): Layout
	local rng = Random.new(config.Seed)
	local layers: { Layer } = {}
	local count = 0
	for _, L in config.Layers do
		local layer = ridgeLayer(L, rng, config.MaxEdge)
		count += #layer.triangles
		table.insert(layers, layer)
	end
	if config.Peak then
		local peak = peakLayer(config.Peak, rng, config.MaxEdge)
		count += #peak.triangles
		table.insert(layers, peak)
	end
	return { layers = layers, triangles = count }
end

export type Plate = { centre: Vector3, size: Vector3, colour: Color3 }

-- The valley floor's plates, relative to the near layer's centre at the road's start height.
function Horizon.floor(config: any): { Plate }
	local F = config.Floor
	local plates: { Plate } = {}
	if not F then
		return plates
	end
	local rng = Random.new(config.Seed + 1)
	local n: number = F.Tiles
	local side = F.Size / n
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local x = -F.Size / 2 + (i + 0.5) * side
			local z = -F.Size / 2 + (j + 0.5) * side
			table.insert(plates, {
				-- its top at `-Depth`
				centre = Vector3.new(x, -F.Depth - F.Thickness / 2, z),
				size = Vector3.new(side, F.Thickness, side),
				colour = shade(F.Colour, rng:NextNumber(-F.Shade, F.Shade)),
			})
		end
	end
	return plates
end

-- Where a layer's centre is after `dt` seconds of catching up `cam` (both flat, Y = 0):
-- eased over `lag` seconds, and never more than `maxLag` behind.
function Horizon.follow(centre: Vector3, cam: Vector3, dt: number, lag: number, maxLag: number): Vector3
	if lag <= 0 or maxLag <= 0 then
		return cam
	end
	local nextCentre = centre + (cam - centre) * (1 - math.exp(-dt / lag))
	local behind = cam - nextCentre
	if behind.Magnitude > maxLag then
		nextCentre = cam - behind.Unit * maxLag
	end
	return nextCentre
end

return Horizon
