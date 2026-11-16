--!strict
-- Vista: the sums behind the painted vista round the run (docs/game/features/painted-vista.md,
-- T-266). PURE: numbers in, numbers out; `Drift/VistaView` builds and moves the parts.
--
-- Every position here is relative to a layer's anchor: the camera's spot on the ground plan,
-- at the layer's level (Y = 0).

local Vista = {}

export type Panel = {
	index: number,
	cframe: CFrame, -- the panel's centre; its front face (-Z) looks in at the anchor
	size: Vector3,
	image: string, -- "" for none
	skirt: { cframe: CFrame, size: Vector3 }?,
}

-- Studs the skirt overlaps the art's bottom edge, and how far behind the panel it stands,
-- so the two never fight over the same pixels.
local SKIRT_OVERLAP = 4
local SKIRT_BEHIND = 2

-- A panel's width: the chord of its share of the ring.
function Vista.panelWidth(radius: number, panels: number): number
	return 2 * radius * math.sin(math.pi / panels)
end

-- Where each panel of a ridge layer stands round its anchor.
function Vista.panels(layer: any): { Panel }
	local n: number = layer.Panels
	local r: number = layer.Radius
	local width = Vista.panelWidth(r, n)
	local height = width / layer.Aspect
	local mid = r * math.cos(math.pi / n) -- the anchor to the middle of each panel
	-- the art's highest summit at `Peak` degrees above level, seen from the anchor
	local top = math.tan(math.rad(layer.Peak)) * mid + layer.PeakAt * height
	local centreY = top - height / 2
	local images: { string } = layer.Images or {}
	local out: { Panel } = {}
	for i = 1, n do
		local angle = (i - 0.5) * 2 * math.pi / n
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local at = dir * mid
		local cf = CFrame.lookAt(at + Vector3.yAxis * centreY, Vector3.yAxis * centreY)
		local skirt = nil
		if (layer.Skirt or 0) > 0 then
			local h: number = layer.Skirt + SKIRT_OVERLAP
			local skirtTop = centreY - height / 2 + SKIRT_OVERLAP
			local behind = at + dir * SKIRT_BEHIND
			skirt = {
				cframe = CFrame.lookAt(behind + Vector3.yAxis * (skirtTop - h / 2), Vector3.yAxis * (skirtTop - h / 2)),
				size = Vector3.new(width, h, 1),
			}
		end
		table.insert(out, {
			index = i,
			cframe = cf,
			size = Vector3.new(width, height, 1),
			image = if #images > 0 then images[(i - 1) % #images + 1] else "",
			skirt = skirt,
		})
	end
	return out
end

-- Where each curved panel of a ridge layer stands round its anchor (`Config.Vista.Mesh`):
-- the mesh's box, centred, its inner face looking in at the anchor. The art fills its top
-- `ArtShare`, the art's summit at `Peak` degrees as with flat panels, and the skirt below.
function Vista.arcs(layer: any, mesh: any): { Panel }
	local n: number = layer.Panels
	local r: number = layer.Radius
	local half = math.pi / n
	local width = Vista.panelWidth(r, n)
	local art = width / layer.Aspect
	local height = art / mesh.ArtShare - mesh.TopV * art
	local depth = r * (1 - math.cos(half))
	local mid = r * math.cos(half) -- to the panel's ends, where the art meets its neighbours
	-- the picture's top edge (its v = 0), and the shape's, a little below it
	local top = math.tan(math.rad(layer.Peak)) * r + layer.PeakAt * art
	local centreY = top - mesh.TopV * art - height / 2
	local images: { string } = layer.Images or {}
	local out: { Panel } = {}
	for i = 1, n do
		local angle = (i - 0.5) * 2 * math.pi / n
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local at = dir * (r + mid) / 2 -- the box's centre, halfway through its depth
		local cf = CFrame.lookAt(at + Vector3.yAxis * centreY, Vector3.yAxis * centreY)
		table.insert(out, {
			index = i,
			cframe = cf,
			size = Vector3.new(width, height, depth),
			image = if #images > 0 then images[(i - 1) % #images + 1] else "",
			skirt = nil,
		})
	end
	return out
end

export type ArcGeometry = {
	positions: { Vector3 },
	normals: { Vector3 },
	uvs: { Vector2 },
	triangles: { { number } }, -- indices into the three lists above, which share them
	size: Vector3, -- the box, centred on the origin
}

-- The curved panel's mesh, at a ring 1 000 studs round (the game scales it to each layer).
-- In mesh space the ring's centre is on -Z, the way a part's front looks, and the box is
-- centred on the origin, as Roblox centres a mesh in its part. Every normal points in at the
-- centre, so the shading runs on smoothly from one panel into the next. u runs left to right
-- as seen from the centre; v down the picture, and held at its bottom row down the skirt
-- (kept just inside the edges, clear of the wrap to the transparent top).
function Vista.arcGeometry(mesh: any): ArcGeometry
	local radius = 1000
	local half = math.rad(mesh.ArcDeg / 2)
	local width = 2 * radius * math.sin(half)
	local art = width / 3
	local height = art / mesh.ArtShare - mesh.TopV * art
	local zc = -radius * (1 + math.cos(half)) / 2
	local cols: number = mesh.Columns
	local top, base = mesh.TopV, 0.995
	local out: ArcGeometry = { positions = {}, normals = {}, uvs = {}, triangles = {}, size = Vector3.zero }
	for i = 0, cols do
		local t = i / cols
		-- seen from the centre looking +Z, +X is on the left: u = 0 there
		local a = half - 2 * half * t
		local x, z = radius * math.sin(a), zc + radius * math.cos(a)
		local n = Vector3.new(-math.sin(a), 0, -math.cos(a))
		for _, row in { { height / 2, top }, { height / 2 - art * (base - top), base }, { -height / 2, base } } do
			table.insert(out.positions, Vector3.new(x, row[1], z))
			table.insert(out.normals, n)
			table.insert(out.uvs, Vector2.new(t, row[2]))
		end
	end
	for i = 0, cols - 1 do
		for r = 0, 1 do
			local tl = i * 3 + r + 1
			local bl, tr = tl + 1, tl + 3
			local br = tr + 1
			-- front faces look in at the centre
			table.insert(out.triangles, { tl, bl, tr })
			table.insert(out.triangles, { tr, bl, br })
		end
	end
	out.size = Vector3.new(width, height, radius * (1 - math.cos(half)))
	return out
end

-- The angle, in degrees above level, of the art's highest summit, the panel's top edge and
-- its bottom edge, seen from the anchor (what the tests check against the spec).
function Vista.angles(layer: any): (number, number, number)
	local p = Vista.panels(layer)[1]
	local mid = layer.Radius * math.cos(math.pi / layer.Panels)
	local y = p.cframe.Position.Y
	local h = p.size.Y
	local peak = y + h / 2 - layer.PeakAt * h
	return math.deg(math.atan(peak / mid)), math.deg(math.atan((y + h / 2) / mid)), math.deg(math.atan((y - h / 2) / mid))
end

-- The layer's centre eased toward the camera over `lag` s, never more than `maxLag` behind.
-- Flat positions (Y = 0).
function Vista.follow(centre: Vector3, cam: Vector3, dt: number, lag: number, maxLag: number): Vector3
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

-- How far the layers stand above the road's start: `FollowHeight` of the (eased) camera's
-- height above it.
function Vista.lift(cfg: any, originY: number, camY: number): number
	return cfg.FollowHeight * (camY - originY)
end

-- The cloud sea's top layer height: under the road's start, rising with the road, and never
-- nearer than `MinBelow` under the camera.
function Vista.cloudTop(cfg: any, originY: number, camY: number): number
	local sea = cfg.CloudSea
	local y = originY + Vista.lift(cfg, originY, camY) - sea.Below
	return math.min(y, camY - sea.MinBelow)
end

-- How far the cloud sea's top layer reaches from the camera at the least (its anchor
-- snaps to the nearest whole tile, up to half a tile off).
function Vista.cloudReach(sea: any): number
	return sea.Layers[1].Grid * sea.PartSize / 2 - sea.Tile / 2
end

-- A flat position snapped to whole tiles, so parts moved there leave the cloud where it was.
function Vista.snap(p: Vector3, tile: number): Vector3
	return Vector3.new(math.round(p.X / tile) * tile, 0, math.round(p.Z / tile) * tile)
end

-- Where each part of a cloud layer stands round its anchor: a grid of `grid` x `grid`.
function Vista.cloudParts(sea: any, grid: number): { Vector3 }
	local out = {}
	local g = grid
	for i = 0, g - 1 do
		for j = 0, g - 1 do
			table.insert(out, Vector3.new((i - (g - 1) / 2) * sea.PartSize, 0, (j - (g - 1) / 2) * sea.PartSize))
		end
	end
	return out
end

-- How far a cloud layer has drifted after `t` s, as a texture offset, wrapped to one tile.
function Vista.drift(t: number, speed: number, heading: number, tile: number): (number, number)
	local a = math.rad(heading)
	local u = (t * speed * math.cos(a)) % tile
	local v = (t * speed * math.sin(a)) % tile
	return u, v
end

return Vista
