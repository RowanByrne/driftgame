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

-- A flat position snapped to whole tiles, so parts moved there leave the cloud where it was.
function Vista.snap(p: Vector3, tile: number): Vector3
	return Vector3.new(math.round(p.X / tile) * tile, 0, math.round(p.Z / tile) * tile)
end

-- Where each part of a cloud layer stands round its anchor: a grid of `Grid` x `Grid`.
function Vista.cloudParts(sea: any): { Vector3 }
	local out = {}
	local g: number = sea.Grid
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
