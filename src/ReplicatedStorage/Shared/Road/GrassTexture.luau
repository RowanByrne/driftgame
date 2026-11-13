--!strict
-- GrassTexture: the grass runoff's own texture (T-187): a painted grass tile, grey, which the
-- user picked on 2026-11-13 from four looks (DECISIONS.md). Uploaded once
-- (`Config.Spline.Grass.Image`, `assets/grass-texture/`), loaded here into one EditableImage
-- that every chunk of the spline road shares (`Road/SplineMesh`).
--
-- WHY A TEXTURE, AND WHY ONE IMAGE. The road's mesh is one MeshPart a chunk, so it has one
-- Material: a built-in Grass material would put grass on the tarmac, the rocks and the trees
-- too (measured: a MeshPart's material is projected, it ignores the mesh's UVs). A texture
-- IS mapped by UVs, face by face, so the grass faces get UVs in world studs and tile it, and
-- every other face samples UV (0, 0). A client has no EditableMesh to spare (measured: none
-- free while the road is drawn), so the grass cannot be a mesh of its own.
--
-- WHAT IT DOES TO THE REST. With a texture on it, a MeshPart no longer shows its material's
-- colour map (measured: the tarmac went flat and twice as bright). The Asphalt map darkened
-- everything about half (`Shade`), so the image's corners -- where UV (0, 0) samples -- are
-- set to `Shade` grey here: the tarmac, gravel, rock and trees keep their brightness, without
-- Asphalt's grain. The tile was evened out to average `Shade` before it was uploaded, so the
-- grass keeps its brightness. Each pixel is a grey the vertex colour multiplies, so the grass
-- stays `GrassColour`.
--
-- WHY AN EDITABLEIMAGE, not the asset id straight on the part: only an image the game holds
-- can have its corners set, and the corners are what keep the rest of the mesh looking right.
--
-- A device that will not load or make the image draws the road as before: no texture, flat
-- grass, the tarmac with its Asphalt grain.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GrassTexture = {}

local CORNER = 2 -- pixels each side of the wrap point held at `Shade`: a 4 x 4 block

-- THE CORNERS, where every face that is not grass samples: exactly `Shade`. A block, not one
-- pixel, so a texture a device draws at lower resolution still reads `Shade` there.
function GrassTexture.plainCorners(px: buffer, size: number)
	local v = math.floor(Config.Spline.Grass.Shade * 255 + 0.5)
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			if (x < CORNER or x >= size - CORNER) and (y < CORNER or y >= size - CORNER) then
				local o = (y * size + x) * 4
				buffer.writeu8(px, o, v)
				buffer.writeu8(px, o + 1, v)
				buffer.writeu8(px, o + 2, v)
				buffer.writeu8(px, o + 3, 255)
			end
		end
	end
end

local image: EditableImage? = nil
local state = "none" -- "none", "making", "done"
local buildMs = 0

-- The shared image, loaded the first time it is asked for (it yields: the first chunk to ask
-- waits for it, and so does any chunk asking meanwhile). nil when this device will not load
-- or make it, or when the texture is off.
function GrassTexture.get(): EditableImage?
	local G = Config.Spline.Grass
	if not G.Enabled then
		return nil -- read each time, so a test can switch it off and on
	end
	while state == "making" do
		task.wait()
	end
	if state == "done" then
		return image
	end
	state = "making"
	local t0 = os.clock()
	local ok, made = pcall(function()
		local img = AssetService:CreateEditableImageAsync(Content.fromUri(G.Image))
		local size = img.Size.X
		local px = img:ReadPixelsBuffer(Vector2.zero, img.Size)
		GrassTexture.plainCorners(px, size)
		img:WritePixelsBuffer(Vector2.zero, img.Size, px)
		return img
	end)
	buildMs = (os.clock() - t0) * 1000
	if ok then
		image = made
	else
		warn(`[GrassTexture] no grass texture on this device, the grass is drawn flat: {made}`)
	end
	state = "done"
	return image
end

-- A grass vertex's UV: world studs over `TileStuds`, shifted by a whole number of tiles
-- (`base`, from the chunk's centre) so the numbers stay small and the tiling runs on
-- unbroken from chunk to chunk.
function GrassTexture.uv(x: number, z: number, baseU: number, baseV: number): Vector2
	local tile = Config.Spline.Grass.TileStuds
	return Vector2.new(x / tile - baseU, z / tile - baseV)
end

-- The whole tiles to shift a chunk's UVs by, from its centre.
function GrassTexture.base(centre: Vector3): (number, number)
	local tile = Config.Spline.Grass.TileStuds
	return math.floor(centre.X / tile), math.floor(centre.Z / tile)
end

function GrassTexture.DebugState()
	-- `buildMs` is wall time, the asset's load included
	return {
		made = image ~= nil,
		state = state,
		buildMs = buildMs,
		size = if image then image.Size.X else 0,
	}
end

return GrassTexture
