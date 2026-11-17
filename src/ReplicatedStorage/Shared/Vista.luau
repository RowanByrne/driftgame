--!strict
-- Vista: the sums behind the painted vista round the run (docs/game/features/painted-vista.md,
-- T-266). PURE: numbers in, numbers out; `Drift/VistaView` builds and moves the parts.
--
-- Every position here is relative to a layer's anchor: the camera's spot on the ground plan,
-- at the layer's level (Y = 0).

local Config = require(script.Parent.Config)

local Vista = {}

export type Panel = {
	index: number,
	cframe: CFrame, -- the panel's centre; its front face (-Z) looks in at the anchor
	size: Vector3,
	image: string, -- "" for none
	slice: number?, -- which slice of its picture it shows, 0 first (T-278)
	slices: number?,
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

-- How many panels one picture spans (`Config.Vista.Mesh.Slices`, T-278): each panel shows
-- its slice of the picture, so a ring pushed out keeps its pictures whole and the same size
-- on screen while every part stays under 2 048 studs.
function Vista.slices(): number
	return Config.Vista.Mesh.Slices or 1
end

-- The width a whole picture is drawn across (the chord of `Slices` panels), which sets the
-- art's height; and panel `i`'s picture (1-based) and slice in it (0-based).
function Vista.pictureWidth(radius: number, panels: number, slices: number): number
	return 2 * radius * math.sin(math.pi * slices / panels)
end

-- Panels go round the ring LEFTWARD as seen from the centre (each next one at a larger
-- angle, toward +X, which is on the left), and a picture's u runs left to right: so a
-- picture's first panel shows its last (rightmost) slice.
function Vista.pictureOf(i: number, slices: number): (number, number)
	return (i - 1) // slices + 1, slices - 1 - (i - 1) % slices
end

-- How far panel `i`'s picture is lifted so its end saddles stand where the first picture's
-- do (`Edges`, a share of the picture's height `art` from its top).
function Vista.edgeLift(layer: any, i: number, art: number): number
	local edges = layer.Edges
	local images = layer.Images or {}
	if not edges or #images == 0 then
		return 0
	end
	local picture = Vista.pictureOf(i, Vista.slices())
	local k = (picture - 1) % #images + 1
	return ((edges[k] or edges[1]) - edges[1]) * art
end

-- Where each panel of a ridge layer stands round its anchor.
function Vista.panels(layer: any): { Panel }
	local n: number = layer.Panels
	local r: number = layer.Radius
	local slices = Vista.slices()
	local width = Vista.panelWidth(r, n)
	local height = Vista.pictureWidth(r, n, slices) / layer.Aspect
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
		local y = centreY + Vista.edgeLift(layer, i, height)
		local cf = CFrame.lookAt(at + Vector3.yAxis * y, Vector3.yAxis * y)
		local skirt = nil
		if (layer.Skirt or 0) > 0 then
			local h: number = layer.Skirt + SKIRT_OVERLAP
			local skirtTop = y - height / 2 + SKIRT_OVERLAP
			local behind = at + dir * SKIRT_BEHIND
			skirt = {
				cframe = CFrame.lookAt(behind + Vector3.yAxis * (skirtTop - h / 2), Vector3.yAxis * (skirtTop - h / 2)),
				size = Vector3.new(width, h, 1),
			}
		end
		local picture, slice = Vista.pictureOf(i, slices)
		table.insert(out, {
			index = i,
			cframe = cf,
			size = Vector3.new(width, height, 1),
			image = if #images > 0 then images[(picture - 1) % #images + 1] else "",
			slice = slice,
			slices = slices,
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
	local slices = Vista.slices()
	local width = Vista.panelWidth(r, n)
	local art = Vista.pictureWidth(r, n, slices) / layer.Aspect
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
		local y = centreY + Vista.edgeLift(layer, i, art)
		local cf = CFrame.lookAt(at + Vector3.yAxis * y, Vector3.yAxis * y)
		local picture, slice = Vista.pictureOf(i, slices)
		table.insert(out, {
			index = i,
			cframe = cf,
			size = Vector3.new(width, height, depth),
			image = if #images > 0 then images[(picture - 1) % #images + 1] else "",
			slice = slice,
			slices = slices,
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
-- as seen from the centre; v down the picture (kept just inside its edges, clear of the wrap
-- to its transparent top). Under it the skirt fades into one even colour of its mist.
-- `slice` (0 first, of `mesh.Slices`): the mesh shows that slice of the picture (T-278).
function Vista.arcGeometry(mesh: any, slice: number?): ArcGeometry
	local radius = 1000
	local slices = mesh.Slices or 1
	local j = slice or 0
	local half = math.rad(mesh.ArcDeg / 2)
	local width = 2 * radius * math.sin(half)
	local art = 2 * radius * math.sin(half * slices) / 3
	local height = art / mesh.ArtShare - mesh.TopV * art
	local zc = -radius * (1 + math.cos(half)) / 2
	local cols: number = mesh.Columns
	local top, base = mesh.TopV, 0.995
	-- UNDER THE PICTURE: the skirt fades, over `SkirtFade` of the picture's height, into the
	-- picture's own mist at `SkirtUV`, then holds it down to the panel's bottom (the user,
	-- T-278: a blank bottom is fine; repeating the hills under it looked wrong)
	local artBottom = height / 2 - art * (base - top)
	local ys: { number } = { height / 2, artBottom, artBottom - art * mesh.SkirtFade, -height / 2 }
	local nr = #ys
	local out: ArcGeometry = { positions = {}, normals = {}, uvs = {}, triangles = {}, size = Vector3.zero }
	for i = 0, cols do
		local t = i / cols
		-- seen from the centre looking +Z, +X is on the left: u = 0 there
		local a = half - 2 * half * t
		local u = (j + t) / slices
		local x, z = radius * math.sin(a), zc + radius * math.cos(a)
		local n = Vector3.new(-math.sin(a), 0, -math.cos(a))
		for r = 1, nr do
			table.insert(out.positions, Vector3.new(x, ys[r], z))
			table.insert(out.normals, n)
			local uv = if r == 1 then Vector2.new(u, top) elseif r == 2 then Vector2.new(u, base) else mesh.SkirtUV
			table.insert(out.uvs, uv)
		end
	end
	for i = 0, cols - 1 do
		for r = 0, nr - 2 do
			local tl = i * nr + r + 1
			local bl, tr = tl + 1, tl + nr
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

-- How far a layer stands above the road's start: its `slide` (else `FollowHeight`, the cloud
-- sea's) of the (eased) camera's height above it.
function Vista.lift(cfg: any, originY: number, camY: number, slide: number?): number
	return (slide or cfg.FollowHeight) * (camY - originY)
end

-- A ring's level for a vista `scale` times as far out and as big (`Config.Vista.Scale`,
-- T-278): `scale` times as far from the camera's height, so it is seen at the same angles.
function Vista.scaledLevel(level: number, camY: number, scale: number): number
	return camY + (level - camY) * scale
end

-- How far below the camera a ring's anchor stands with no dip (T-278): as it stood, scaled,
-- with the camera `EyeHeight` above the road's start.
function Vista.drop(cfg: any, slide: number): number
	return (cfg.Scale or 1) * (1 - slide) * (cfg.EyeHeight or 0)
end

-- Height of a curved ring's art bottom (the picture's v = 0.995) above its anchor.
function Vista.artBottom(layer: any, mesh: any): number
	local r: number = layer.Radius
	local art = Vista.pictureWidth(r, layer.Panels, mesh.Slices or 1) / layer.Aspect
	local top = math.tan(math.rad(layer.Peak)) * r + layer.PeakAt * art
	return top - 0.995 * art
end

-- How far a ring must drop for its art bottom (`yBottom` over its anchor, at radius `r`, the
-- anchor `drop` under the camera) to be seen `dip` degrees lower.
function Vista.dipDrop(r: number, yBottom: number, drop: number, dip: number): number
	if dip <= 0 then
		return 0
	end
	local a = math.atan((yBottom - drop) / r)
	return r * (math.tan(a) - math.tan(a - math.rad(dip)))
end

-- The nearest and furthest a ring's panels come to the camera: their ends are nearest, their
-- middles furthest, and the ring may trail by up to `MaxLag` either way.
function Vista.ringSpan(layer: any): (number, number)
	return layer.Radius * math.cos(math.pi / layer.Panels) - layer.MaxLag, layer.Radius + layer.MaxLag
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
