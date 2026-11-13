--!strict
-- GrassTexture: the grass runoff's own texture (T-187), drawn in code into one EditableImage
-- that every chunk of the spline road shares (`Road/SplineMesh`).
--
-- WHY IN CODE, AND WHY ONE IMAGE. The road's mesh is one MeshPart a chunk, so it has one
-- Material: a built-in Grass material would put grass on the tarmac, the rocks and the trees
-- too (measured: a MeshPart's material is projected, it ignores the mesh's UVs). A texture
-- IS mapped by UVs, face by face, so the grass faces get UVs in world studs and tile it, and
-- every other face keeps UV (0, 0). A client has no EditableMesh to spare (measured: none
-- free while the road is drawn), so the grass cannot be a mesh of its own.
--
-- WHAT IT DOES TO THE REST. With a texture on it, a MeshPart no longer shows its material's
-- colour map (measured: the tarmac went flat and twice as bright). The Asphalt map darkened
-- everything about half (`Shade`), so the image's corners -- where UV (0, 0) samples -- are
-- `Shade` grey: the tarmac, gravel, rock and trees keep their brightness, without Asphalt's
-- grain. The grass blades average `Shade` too, so the grass keeps its brightness and gains
-- blades. Each pixel is a grey (a slight warm tint on the light blades) that the vertex
-- colour multiplies, so the grass stays `GrassColour`.
--
-- A device that will not make the image draws the road as before: no texture, flat grass.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GrassTexture = {}

local CORNER = 2 -- pixels each side of the wrap point held at `Shade`: a 4 x 4 block

-- The pixels, RGBA, `size` square, from `seed`: the same on every device. Tiles seamlessly.
function GrassTexture.pixels(size: number, seed: number): buffer
	local G = Config.Spline.Grass
	local n = size * size
	local f = table.create(n, 0) -- each pixel's offset from the mean, in units of `Shade`
	local rng = Random.new(seed)

	-- CLUMPS: tiling value noise, two octaves, so the grass is patchy rather than even
	local function octave(cells: number, amp: number)
		local lattice = table.create(cells * cells, 0)
		for i = 1, cells * cells do
			lattice[i] = rng:NextNumber() * 2 - 1
		end
		local function at(cx: number, cy: number): number
			return lattice[(cy % cells) * cells + (cx % cells) + 1]
		end
		local scale = cells / size
		for y = 0, size - 1 do
			local gy = y * scale
			local y0 = math.floor(gy)
			local ty = gy - y0
			ty = ty * ty * (3 - 2 * ty)
			for x = 0, size - 1 do
				local gx = x * scale
				local x0 = math.floor(gx)
				local tx = gx - x0
				tx = tx * tx * (3 - 2 * tx)
				local a = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * tx
				local b = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * tx
				local i = y * size + x + 1
				f[i] += (a + (b - a) * ty) * amp
			end
		end
	end
	octave(4, G.Clump)
	octave(16, G.Clump * 0.5)

	-- BLADES: short strokes in every direction (it is seen from above), lighter or darker
	-- than the ground, fading toward the tip, wrapping round the tile's edges
	local lenLo, lenHi = G.BladeLength[1], G.BladeLength[2]
	for _ = 1, G.Blades do
		local x0, y0 = rng:NextNumber() * size, rng:NextNumber() * size
		local angle = rng:NextNumber() * math.pi * 2
		local len = lenLo + (lenHi - lenLo) * rng:NextNumber()
		local tone = (if rng:NextNumber() < G.LightShare then 1 else -1) * G.Blade * (0.5 + 0.5 * rng:NextNumber())
		local dx, dy = math.cos(angle), math.sin(angle)
		local steps = math.max(1, math.floor(len * 2))
		for k = 0, steps do
			local t = k / steps
			local px = math.floor(x0 + dx * len * t) % size
			local py = math.floor(y0 + dy * len * t) % size
			local i = py * size + px + 1
			local w = 0.75 * (1 - 0.6 * t)
			f[i] = f[i] * (1 - w) + tone * w
		end
	end

	-- mean zero, so the grass averages `Shade`, as the Asphalt map made it before
	local sum = 0
	for i = 1, n do
		sum += f[i]
	end
	local mean = sum / n

	local shade = G.Shade
	local out = buffer.create(n * 4)
	local function put(i: number, r: number, g: number, b: number)
		local o = (i - 1) * 4
		buffer.writeu8(out, o, math.clamp(math.floor(r * 255 + 0.5), 0, 255))
		buffer.writeu8(out, o + 1, math.clamp(math.floor(g * 255 + 0.5), 0, 255))
		buffer.writeu8(out, o + 2, math.clamp(math.floor(b * 255 + 0.5), 0, 255))
		buffer.writeu8(out, o + 3, 255)
	end
	for i = 1, n do
		local d = f[i] - mean
		local v = shade * (1 + d)
		local warm = math.max(d, 0) * G.Warm
		put(i, v * (1 + warm), v, v * (1 - warm))
	end
	-- THE CORNERS, where every face that is not grass samples: exactly `Shade`. A block, not
	-- one pixel, so a texture a device draws at lower resolution still reads `Shade` there.
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			if (x < CORNER or x >= size - CORNER) and (y < CORNER or y >= size - CORNER) then
				put(y * size + x + 1, shade, shade, shade)
			end
		end
	end
	return out
end

local image: EditableImage? = nil
local tried = false
local buildMs = 0

-- The shared image, made the first time it is asked for. nil when this device will not make
-- one (out of its EditableImage memory), or when the texture is switched off.
function GrassTexture.get(): EditableImage?
	if tried then
		return image
	end
	tried = true
	local G = Config.Spline.Grass
	if not G.Enabled then
		return nil
	end
	local t0 = os.clock()
	local ok, made = pcall(function()
		local img = AssetService:CreateEditableImage({ Size = Vector2.new(G.Size, G.Size) })
		assert(img, "this device would not make an EditableImage")
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(G.Size, G.Size), GrassTexture.pixels(G.Size, G.Seed))
		return img
	end)
	buildMs = (os.clock() - t0) * 1000
	if ok then
		image = made
	else
		warn(`[GrassTexture] no grass texture on this device, the grass is drawn flat: {made}`)
	end
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
	return { made = image ~= nil, tried = tried, buildMs = buildMs }
end

return GrassTexture
